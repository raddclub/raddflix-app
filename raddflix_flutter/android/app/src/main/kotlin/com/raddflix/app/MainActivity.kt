package com.raddflix.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Rational
import android.hardware.fingerprint.FingerprintManager
import android.os.CancellationSignal
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private val PIP_CHANNEL      = "com.raddflix.app/pip"
    private val MEDIA_CHANNEL    = "com.raddflix.app/media"
    private val CAST_CHANNEL     = "com.raddflix.app/cast"
    private val INTENT_CHANNEL   = "com.raddflix.app/intent"
    private val SECURITY_CHANNEL = "com.raddflix.app/security"

    private var pendingVideoUri: String? = null
    private var pendingVideoTitle: String? = null
    private var pendingSubtitleUri: String? = null

    private var activeEngine: FlutterEngine? = null

    // Stored pip channel reference so both notifReceiver and onPipExited can use it
    // without creating a second MethodChannel instance.
    private var pipMethodChannel: MethodChannel? = null

    // ── Media notification BroadcastReceiver ──────────────────────────────────
    // Catches button-tap and seek-gesture broadcasts from PlaybackService and
    // forwards them to Flutter as "onNotificationAction" on the pip channel.
    //
    //  Action strings sent to Flutter:
    //    "play_pause"          — toggle play/pause
    //    "seek_back"           — skip −10 s
    //    "seek_forward"        — skip +30 s
    //    "seek_to:<positionMs>"— swipe-to-seek on Android 13+ progress bar
    private val notifReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            // BroadcastReceiver callbacks arrive on the main thread — safe to call invokeMethod.
            when (action) {
                PlaybackService.ACTION_PLAY_PAUSE ->
                    pipMethodChannel?.invokeMethod("onNotificationAction", "play_pause")
                PlaybackService.ACTION_SEEK_BACK  ->
                    pipMethodChannel?.invokeMethod("onNotificationAction", "seek_back")
                PlaybackService.ACTION_SEEK_FWD   ->
                    pipMethodChannel?.invokeMethod("onNotificationAction", "seek_forward")
                PlaybackService.ACTION_SEEK_TO    -> {
                    val pos = intent.getLongExtra(PlaybackService.EXTRA_SEEK_TO_MS, -1L)
                    if (pos >= 0) {
                        pipMethodChannel?.invokeMethod("onNotificationAction", "seek_to:$pos")
                    }
                }
            }
        }
    }

    companion object {
        private val SUBTITLE_EXTS = setOf("srt", "ass", "ssa", "vtt", "sub")
        private val VIDEO_EXTS    = setOf("mp4", "mkv", "avi", "mov", "flv", "wmv", "m4v", "3gp", "ts", "webm", "m2ts", "mts")
        private const val DELETE_MEDIA_REQUEST_CODE = 9002
    }

    private var intentMethodChannel: MethodChannel? = null
    private var pendingDeleteResult: MethodChannel.Result? = null

    // ── Legacy FingerprintManager fallback (Infinix / Transsion fix) ─────────
    // Transsion side-mounted sensors register with FingerprintManager but NOT
    // with BiometricManager, so BiometricPrompt fails silently on Infinix Hot
    // series. These fields hold the pending Flutter result and cancellation
    // signal while a legacy fingerprint authentication is in progress.
    private var pendingBiometricResult: MethodChannel.Result? = null
    private var fingerprintCancellationSignal: CancellationSignal? = null

    private var castContext: CastContext? = null
    private var castSession: CastSession? = null
    private var castSessionListener: SessionManagerListener<CastSession>? = null

    // ── Register / unregister notification receiver ───────────────────────────

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(PlaybackService.ACTION_PLAY_PAUSE)
            addAction(PlaybackService.ACTION_SEEK_BACK)
            addAction(PlaybackService.ACTION_SEEK_FWD)
            addAction(PlaybackService.ACTION_SEEK_TO)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notifReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notifReceiver, filter)
        }
    }

    override fun onStop() {
        super.onStop()
        try { unregisterReceiver(notifReceiver) } catch (_: Exception) {}
    }

    // ─────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        activeEngine = flutterEngine

        // ── MediaStore Plugin (local video browser) ──────────────────────
        flutterEngine.plugins.add(MediaStorePlugin())

        // ── Intent Channel: incoming video "Open with" from file managers ─
        intentMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL
        )
        intentMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingVideoUri" -> {
                    result.success(pendingVideoUri)
                    pendingVideoUri = null
                }
                "getPendingVideoTitle" -> {
                    result.success(pendingVideoTitle)
                    pendingVideoTitle = null
                }
                "getPendingSubtitleUri" -> {
                    result.success(pendingSubtitleUri)
                    pendingSubtitleUri = null
                }
                "openVideoWith" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(android.net.Uri.parse(uri), "video/*")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(intent, "Open with"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_WITH_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        extractVideoUri(intent)

        // ── PiP + Background Playback Channel ────────────────────────────
        val pipCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel = pipCh
        pipCh.setMethodCallHandler { call, result ->
            when (call.method) {

                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()
                        enterPictureInPictureMode(params)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                // Start (or restart/update) the foreground media notification service.
                // Accepts full play state — title, isPlaying, positionMs, durationMs.
                "startBgPlayback" -> {
                    val title     = call.argument<String>("title")      ?: "Playing…"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val posMs     = (call.argument<Int>("positionMs")   ?: 0).toLong()
                    val durMs     = (call.argument<Int>("durationMs")   ?: 0).toLong()
                    startPlaybackService(title, isPlaying, posMs, durMs)
                    result.success(null)
                }

                // Update the notification with refreshed state (play/pause toggle,
                // updated position for the progress bar, title change).
                "updateBgNotification" -> {
                    val title     = call.argument<String>("title")      ?: "Playing…"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val posMs     = (call.argument<Int>("positionMs")   ?: 0).toLong()
                    val durMs     = (call.argument<Int>("durationMs")   ?: 0).toLong()
                    startPlaybackService(title, isPlaying, posMs, durMs)
                    result.success(null)
                }

                "stopBgPlayback" -> {
                    try {
                        stopService(Intent(this, PlaybackService::class.java))
                    } catch (_: Exception) {}
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── Media Channel (scanFile + deleteMediaFiles for vault) ─────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "scanFile" -> {
                        val scanPath = call.argument<String>("path")
                        if (scanPath != null) {
                            MediaScannerConnection.scanFile(
                                this, arrayOf(scanPath), null, null
                            )
                        }
                        result.success(null)
                    }

                    "deleteMediaFiles" -> {
                        val uriStrings = call.argument<List<String>>("uris") ?: emptyList()
                        if (uriStrings.isEmpty()) {
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        val uris = uriStrings.mapNotNull { uriStr ->
                            try { Uri.parse(uriStr) } catch (e: Exception) { null }
                        }

                        if (uris.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                val deleteRequest = MediaStore.createDeleteRequest(contentResolver, uris)
                                pendingDeleteResult = result
                                startIntentSenderForResult(
                                    deleteRequest.intentSender,
                                    DELETE_MEDIA_REQUEST_CODE,
                                    null, 0, 0, 0
                                )
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        } else {
                            var deletedCount = 0
                            for (uri in uris) {
                                try {
                                    val rows = contentResolver.delete(uri, null, null)
                                    if (rows > 0) deletedCount++
                                } catch (e: SecurityException) {
                                    val filePath = getFilePath(uri)
                                    if (filePath != null) {
                                        MediaScannerConnection.scanFile(
                                            this, arrayOf(filePath), null, null
                                        )
                                        deletedCount++
                                    }
                                } catch (e: Exception) {}
                            }
                            result.success(deletedCount > 0)
                        }
                    }

                    // Copy a vault file to the public Downloads folder.
                    // API 29+ (Android 10+): MediaStore.Downloads content provider —
                    //   no WRITE_EXTERNAL_STORAGE needed; result is a content:// URI.
                    // API < 29: direct file copy to Environment.DIRECTORY_DOWNLOADS.
                    "copyToDownloads" -> {
                        val srcPath  = call.argument<String>("src_path") ?: run {
                            result.error("MISSING_ARG", "src_path required", null)
                            return@setMethodCallHandler
                        }
                        val filename = call.argument<String>("filename")
                            ?: java.io.File(srcPath).name
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val ext = filename.substringAfterLast('.', "").lowercase()
                                val mime = when (ext) {
                                    "mkv"  -> "video/x-matroska"
                                    "avi"  -> "video/x-msvideo"
                                    "mov"  -> "video/quicktime"
                                    "webm" -> "video/webm"
                                    "ts", "m2ts", "mts" -> "video/mp2t"
                                    "wmv"  -> "video/x-ms-wmv"
                                    else   -> "video/mp4"
                                }
                                val values = ContentValues().apply {
                                    put(MediaStore.Downloads.DISPLAY_NAME, filename)
                                    put(MediaStore.Downloads.MIME_TYPE, mime)
                                    put(MediaStore.Downloads.IS_PENDING, 1)
                                }
                                val uri = contentResolver.insert(
                                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                    ?: run {
                                        result.error("INSERT_FAILED",
                                            "MediaStore.Downloads insert failed", null)
                                        return@setMethodCallHandler
                                    }
                                contentResolver.openOutputStream(uri)?.use { out ->
                                    java.io.File(srcPath).inputStream().use { it.copyTo(out) }
                                }
                                values.clear()
                                values.put(MediaStore.Downloads.IS_PENDING, 0)
                                contentResolver.update(uri, values, null, null)
                                result.success(uri.toString())
                            } else {
                                @Suppress("DEPRECATION")
                                val dlDir = android.os.Environment
                                    .getExternalStoragePublicDirectory(
                                        android.os.Environment.DIRECTORY_DOWNLOADS)
                                dlDir.mkdirs()
                                val dest = java.io.File(dlDir, filename)
                                java.io.File(srcPath).copyTo(dest, overwrite = true)
                                MediaScannerConnection.scanFile(
                                    this, arrayOf(dest.absolutePath), null, null)
                                result.success(dest.absolutePath)
                            }
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Security Channel ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSignatureFingerprint" -> {
                        try {
                            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.GET_SIGNING_CERTIFICATES
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.GET_SIGNATURES
                                )
                            }
                            val certBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pkgInfo.signingInfo!!.apkContentsSigners[0].toByteArray()
                            } else {
                                @Suppress("DEPRECATION")
                                pkgInfo.signatures!![0].toByteArray()
                            }
                            val md = java.security.MessageDigest.getInstance("SHA-256")
                            val hash = md.digest(certBytes)
                            val fingerprint = hash.joinToString(":") { "%02X".format(it) }
                            result.success(fingerprint)
                        } catch (e: Exception) {
                            result.error("SIGN_CHECK_FAILED", e.message, null)
                        }
                    }
                    "checkFrida" -> {
                        try {
                            val maps = java.io.File("/proc/self/maps").readText()
                            val hasFrida = maps.contains("frida") ||
                                           maps.contains("gadget") ||
                                           maps.contains("gum-js-loop") ||
                                           maps.contains("linjector")
                            result.success(hasFrida)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "checkRoot" -> {
                        val suPaths = listOf(
                            "/system/bin/su", "/system/xbin/su", "/sbin/su",
                            "/data/local/su", "/data/local/bin/su",
                            "/data/local/xbin/su"
                        )
                        result.success(suPaths.any { java.io.File(it).exists() })
                    }
                    // App-lock FLAG_SECURE toggle.
                    // Hides app content from the recents thumbnail and blocks
                    // screenshots while the lock screen is covering the UI.
                    // Called by AppLockService.setFlagSecure(bool) via Dart.
                    "setFlagSecure" -> {
                        val on = call.argument<Boolean>("enabled") ?: true
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    // Legacy FingerprintManager fallback — called by Dart when
                    // BiometricPrompt throws a PlatformException on Infinix / Transsion
                    // Hot series phones. Their side-mounted sensor is bound to the old
                    // FingerprintManager driver but not to BiometricManager, so
                    // BiometricPrompt fails. FingerprintManager still works on those
                    // devices — the same path AppLock-type apps use.
                    //
                    // Returns: true  → fingerprint matched
                    //          false → user cancelled / wrong finger (no error shown)
                    // Error BIOMETRIC_HW_ERROR → hardware genuinely absent; Dart surfaces
                    //   "Fingerprint not supported on your device — use your PIN".
                    "fingerprintAuthenticate" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.error("BIOMETRIC_HW_ERROR",
                                "Fingerprint requires Android 6.0 or higher", null)
                            return@setMethodCallHandler
                        }
                        @Suppress("DEPRECATION")
                        val fm = getSystemService(FingerprintManager::class.java)
                        @Suppress("DEPRECATION")
                        if (fm == null || !fm.isHardwareDetected) {
                            result.error("BIOMETRIC_HW_ERROR",
                                "No fingerprint hardware detected on this device", null)
                            return@setMethodCallHandler
                        }
                        @Suppress("DEPRECATION")
                        if (!fm.hasEnrolledFingerprints()) {
                            result.error("BIOMETRIC_HW_ERROR",
                                "No fingerprints enrolled — go to Settings → Security to add one", null)
                            return@setMethodCallHandler
                        }
                        // Cancel any previously pending auth before starting a new one.
                        pendingBiometricResult?.error("CANCELLED", "Replaced by new auth", null)
                        pendingBiometricResult = result
                        fingerprintCancellationSignal?.cancel()
                        val signal = CancellationSignal()
                        fingerprintCancellationSignal = signal
                        @Suppress("DEPRECATION")
                        fm.authenticate(
                            null, signal, 0,
                            object : FingerprintManager.AuthenticationCallback() {
                                override fun onAuthenticationSucceeded(
                                    r: FingerprintManager.AuthenticationResult?
                                ) {
                                    pendingBiometricResult?.success(true)
                                    pendingBiometricResult = null
                                }
                                override fun onAuthenticationFailed() {
                                    // Wrong fingerprint — keep prompt open, user can retry.
                                }
                                override fun onAuthenticationError(
                                    errorCode: Int, errString: CharSequence?
                                ) {
                                    // ERROR_CANCELED / ERROR_USER_CANCELED → user dismissed.
                                    // Any other error code still resolves false so the lock
                                    // screen stays visible rather than crashing.
                                    pendingBiometricResult?.success(false)
                                    pendingBiometricResult = null
                                }
                            },
                            null // handler — null = run callbacks on main thread
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Orientation Channel ──────────────────────────────────────────────
        // Allows Flutter to set requestedOrientation via native API.
        // This works even when system auto-rotate is OFF — unlike
        // SystemChrome.setPreferredOrientations which respects that setting.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.raddflix.app/orient")
            .setMethodCallHandler { call, result ->
                if (call.method == "setOrientation") {
                    val mode = call.argument<String>("mode") ?: "sensor"
                    requestedOrientation = when (mode) {
                        "sensor"           -> ActivityInfo.SCREEN_ORIENTATION_SENSOR
                        "sensor_landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        "sensor_portrait"  -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                        "landscape_right"  -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        "landscape_left"   -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                        "portrait"         -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "portrait_reverse" -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                        "unspecified"      -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                        else               -> ActivityInfo.SCREEN_ORIENTATION_SENSOR
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // ── Cast Channel ─────────────────────────────────────────────────
        try {
            castContext = CastContext.getSharedInstance(this)
        } catch (e: Exception) {
            // Cast SDK unavailable on this device — silently ignore
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAST_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "discoverDevices" -> {
                        try {
                            val devices = mutableListOf<Map<String, String>>()
                            val sess = castContext?.sessionManager?.currentCastSession
                            if (sess != null && sess.isConnected) {
                                val ri = sess.castDevice
                                if (ri != null) devices.add(mapOf(
                                    "id"    to (ri.deviceId     ?: ""),
                                    "name"  to (ri.friendlyName ?: "Chromecast"),
                                    "model" to (ri.modelName    ?: "")
                                ))
                            }
                            result.success(devices)
                        } catch (e: Exception) {
                            result.success(listOf<Map<String, String>>())
                        }
                    }
                    "castVideo" -> {
                        try {
                            val url   = call.argument<String>("url")     ?: ""
                            val title = call.argument<String>("title")   ?: ""
                            val posMs = call.argument<Int>("positionMs") ?: 0
                            val sess  = castContext?.sessionManager?.currentCastSession
                            if (sess == null || !sess.isConnected) {
                                result.success(false); return@setMethodCallHandler
                            }
                            val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
                            meta.putString(MediaMetadata.KEY_TITLE, title)
                            val mediaInfo = MediaInfo.Builder(url)
                                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                                .setContentType("video/mp4")
                                .setMetadata(meta)
                                .build()
                            val loadRequest = MediaLoadRequestData.Builder()
                                .setMediaInfo(mediaInfo)
                                .setCurrentTime(posMs.toLong())
                                .setAutoplay(true)
                                .build()
                            sess.remoteMediaClient?.load(loadRequest)
                            result.success(true)
                        } catch (e: Exception) { result.success(false) }
                    }
                    "pause"       -> { castSession?.remoteMediaClient?.pause(); result.success(null) }
                    "resume"      -> { castSession?.remoteMediaClient?.play();  result.success(null) }
                    "stop"        -> { castSession?.remoteMediaClient?.stop();  result.success(null) }
                    "seek"        -> {
                        val ms = call.argument<Int>("positionMs") ?: 0
                        castSession?.remoteMediaClient?.seek(ms.toLong())
                        result.success(null)
                    }
                    "isConnected" -> {
                        val connected =
                            castContext?.sessionManager?.currentCastSession?.isConnected == true
                        result.success(connected)
                    }
                    "disconnect"  -> {
                        castContext?.sessionManager?.endCurrentSession(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Shared helper: start / update the PlaybackService ────────────────────
    private fun startPlaybackService(
        title: String,
        isPlaying: Boolean,
        posMs: Long,
        durMs: Long
    ) {
        val svcIntent = Intent(this, PlaybackService::class.java).apply {
            putExtra(PlaybackService.EXTRA_TITLE,      title)
            putExtra(PlaybackService.EXTRA_IS_PLAYING, isPlaying)
            putExtra(PlaybackService.EXTRA_POSITION,   posMs)
            putExtra(PlaybackService.EXTRA_DURATION,   durMs)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(svcIntent)
            } else {
                startService(svcIntent)
            }
        } catch (_: Exception) {}
    }

    // ── PiP exit → notify Flutter ─────────────────────────────────────────
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!isInPictureInPictureMode) {
            pipMethodChannel?.invokeMethod("onPipExited", null)
        }
    }

    // ── Activity result: handle MediaStore.createDeleteRequest on API 30+ ─
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DELETE_MEDIA_REQUEST_CODE) {
            pendingDeleteResult?.success(resultCode == Activity.RESULT_OK)
            pendingDeleteResult = null
        }
    }

    // ── Warm-start intent ────────────────────────────────────────────────
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extractVideoUri(intent)
        val uri = pendingVideoUri
        if (uri != null || pendingSubtitleUri != null) {
            val args = mapOf(
                "uri"      to (uri ?: ""),
                "title"    to (pendingVideoTitle ?: ""),
                "subtitle" to (pendingSubtitleUri ?: "")
            )
            intentMethodChannel?.invokeMethod("onVideoUri", args)
            pendingVideoUri    = null
            pendingVideoTitle  = null
            pendingSubtitleUri = null
        }
    }

    private fun extractVideoUri(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val data = intent.data ?: return
        val uriStr = data.toString()
        if (uriStr.isEmpty()) return

        val displayName = resolveDisplayName(data) ?: ""
        val ext = displayName.substringAfterLast('.', "").lowercase()

        when {
            ext in SUBTITLE_EXTS -> {
                val subPath = resolveSubtitlePath(data, displayName)
                pendingSubtitleUri = subPath ?: uriStr
                val videoPath = findMatchingVideo(data, displayName)
                if (videoPath != null) {
                    pendingVideoUri   = "file://$videoPath"
                    pendingVideoTitle = videoPath.substringAfterLast('/')
                }
            }
            else -> {
                pendingVideoUri   = uriStr
                pendingVideoTitle = displayName.ifEmpty { resolveDisplayName(data) }
                val videoFilePath = getFilePath(data)
                if (videoFilePath != null) {
                    pendingSubtitleUri = findMatchingSubtitle(videoFilePath, displayName)
                }
            }
        }
    }

    private fun resolveSubtitlePath(uri: android.net.Uri, displayName: String): String? {
        val filePath = getFilePath(uri)
        if (filePath != null) return filePath
        val ext = displayName.substringAfterLast('.', "srt")
        return try {
            val tmp = java.io.File(cacheDir, "sub_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                tmp.outputStream().use { out -> input.copyTo(out) }
            }
            tmp.absolutePath
        } catch (_: Exception) { null }
    }

    private fun findMatchingVideo(subtitleUri: android.net.Uri, subtitleName: String): String? {
        val base = subtitleName.substringBeforeLast('.')
        if (base.isEmpty()) return null

        val subPath = getFilePath(subtitleUri)
        if (subPath != null) {
            val dir = java.io.File(subPath).parentFile ?: return null
            for (ext in VIDEO_EXTS) {
                val candidate = java.io.File(dir, "$base.$ext")
                if (candidate.exists()) return candidate.absolutePath
            }
            return null
        }

        val proj = arrayOf(android.provider.MediaStore.Video.Media.DATA)
        for (ext in VIDEO_EXTS) {
            try {
                contentResolver.query(
                    android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    proj,
                    "${android.provider.MediaStore.Video.Media.DISPLAY_NAME} = ?",
                    arrayOf("$base.$ext"),
                    null
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val path = c.getString(0)
                        if (!path.isNullOrEmpty()) return path
                    }
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun findMatchingSubtitle(videoFilePath: String, videoName: String): String? {
        val base = videoName.substringBeforeLast('.')
        if (base.isEmpty()) return null
        val dir = java.io.File(videoFilePath).parentFile ?: return null
        for (ext in SUBTITLE_EXTS) {
            val candidate = java.io.File(dir, "$base.$ext")
            if (candidate.exists()) return candidate.absolutePath
            val upper = java.io.File(dir, "$base.${ext.uppercase()}")
            if (upper.exists()) return upper.absolutePath
        }
        return null
    }

    private fun getFilePath(uri: android.net.Uri): String? {
        return try {
            when (uri.scheme) {
                "file"    -> uri.path
                "content" -> contentResolver.query(
                    uri,
                    arrayOf(android.provider.MediaStore.MediaColumns.DATA),
                    null, null, null
                )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                else      -> null
            }
        } catch (_: Exception) { null }
    }

    private fun resolveDisplayName(uri: android.net.Uri): String? {
        return when (uri.scheme) {
            "content" -> try {
                contentResolver.query(uri, null, null, null, null)?.use {
                    if (it.moveToFirst()) {
                        val col = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (col >= 0) it.getString(col) else null
                    } else null
                }
            } catch (e: Exception) { null }
            "file"    -> try {
                val raw = uri.lastPathSegment ?: return null
                java.net.URLDecoder.decode(raw, "UTF-8")
            } catch (e: Exception) { uri.lastPathSegment }
            else      -> null
        }
    }
}
