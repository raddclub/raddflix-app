package com.raddflix.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Rational
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

    // Stored reference used by onPictureInPictureModeChanged and notifReceiver
    // to send events back to Flutter. Set in configureFlutterEngine().
    private var activeEngine: FlutterEngine? = null

    // Pip channel reference — stored so notifReceiver can invoke methods on it
    // without creating a new MethodChannel instance (which would not have the handler set).
    private var pipMethodChannel: MethodChannel? = null

    // ── Media notification BroadcastReceiver ──────────────────────────────────
    // Catches button taps from PlaybackService's PendingIntent broadcasts and
    // forwards them to Flutter as "onNotificationAction" on the pip channel.
    private val notifReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = when (intent?.action) {
                PlaybackService.ACTION_PLAY_PAUSE -> "play_pause"
                PlaybackService.ACTION_SEEK_BACK  -> "seek_back"
                PlaybackService.ACTION_SEEK_FWD   -> "seek_forward"
                else -> return
            }
            // invokeMethod must be called on the main thread; BroadcastReceiver
            // callbacks always arrive on the main thread so this is safe.
            pipMethodChannel?.invokeMethod("onNotificationAction", action)
        }
    }

    companion object {
        private val SUBTITLE_EXTS = setOf("srt", "ass", "ssa", "vtt", "sub")
        private val VIDEO_EXTS    = setOf("mp4", "mkv", "avi", "mov", "flv", "wmv", "m4v", "3gp", "ts", "webm", "m2ts", "mts")
        private const val DELETE_MEDIA_REQUEST_CODE = 9002
    }

    private var intentMethodChannel: MethodChannel? = null
    private var pendingDeleteResult: MethodChannel.Result? = null

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
        pipMethodChannel = pipCh   // store for notifReceiver access
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
                // Accepts optional isPlaying, positionMs, durationMs in addition to title
                // so the notification reflects the current playback state immediately.
                "startBgPlayback" -> {
                    val title     = call.argument<String>("title")      ?: "Playing…"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val posMs     = (call.argument<Int>("positionMs")   ?: 0).toLong()
                    val durMs     = (call.argument<Int>("durationMs")   ?: 0).toLong()
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
                        result.success(null)
                    } catch (e: Exception) {
                        result.success(null) // best-effort
                    }
                }

                // Update the notification with new state (play/pause toggle, title change).
                // Delivers the intent to an already-running service via onStartCommand.
                "updateBgNotification" -> {
                    val title     = call.argument<String>("title")      ?: "Playing…"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val posMs     = (call.argument<Int>("positionMs")   ?: 0).toLong()
                    val durMs     = (call.argument<Int>("durationMs")   ?: 0).toLong()
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
                    else -> result.notImplemented()
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
