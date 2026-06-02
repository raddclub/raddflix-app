package com.raddflix.app

import android.app.PictureInPictureParams
import android.media.MediaScannerConnection
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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
    private var pendingVideoTitle: String? = null   // display name resolved from ContentResolver
    private var pendingSubtitleUri: String? = null  // subtitle file alongside the video (or vice versa)

    // Known subtitle and video file extensions for "Open With" routing
    companion object {
        private val SUBTITLE_EXTS = setOf("srt", "ass", "ssa", "vtt", "sub")
        private val VIDEO_EXTS    = setOf("mp4", "mkv", "avi", "mov", "flv", "wmv", "m4v", "3gp", "ts", "webm", "m2ts", "mts")
    }
    private var intentMethodChannel: MethodChannel? = null

    private var castContext: CastContext? = null
    private var castSession: CastSession? = null
    private var castSessionListener: SessionManagerListener<CastSession>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        // Extract video URI from the cold-start intent
        extractVideoUri(intent)

        // ── PiP Channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
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
                    else -> result.notImplemented()
                }
            }

        // ── Media Scanner Channel ────────────────────────────────────────
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
                    else -> result.notImplemented()
                }
            }

        // ── Security Channel ─────────────────────────────────────────────
        // Used by AppGuard for: APK signature check, Frida detection, root check.
        // Tampered APK / Frida detected → AppGuard.isTampered = true → fake empty data.
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
                            val url       = call.argument<String>("url")       ?: ""
                            val title     = call.argument<String>("title")     ?: ""
                            val posMs     = call.argument<Int>("positionMs")   ?: 0
                            val sess = castContext?.sessionManager?.currentCastSession
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
                    "pause"  -> { castSession?.remoteMediaClient?.pause(); result.success(null) }
                    "resume" -> { castSession?.remoteMediaClient?.play();  result.success(null) }
                    "stop"   -> { castSession?.remoteMediaClient?.stop();  result.success(null) }
                    "seek"   -> {
                        val ms = call.argument<Int>("positionMs") ?: 0
                        castSession?.remoteMediaClient?.seek(ms.toLong())
                        result.success(null)
                    }
                    "isConnected" -> {
                        val connected =
                            castContext?.sessionManager?.currentCastSession?.isConnected == true
                        result.success(connected)
                    }
                    "disconnect" -> {
                        castContext?.sessionManager?.endCurrentSession(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Warm-start intent (user taps "Open with RaddFlix" while app is running) ─
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
                // User opened a subtitle file — find the matching video in the same directory.
                val subPath = resolveSubtitlePath(data, displayName)
                pendingSubtitleUri = subPath ?: uriStr  // prefer real path, keep URI as fallback
                val videoPath = findMatchingVideo(data, displayName)
                if (videoPath != null) {
                    pendingVideoUri   = "file://${'$'}videoPath"
                    pendingVideoTitle = videoPath.substringAfterLast('/')
                }
                // If no matching video found, pendingVideoUri stays null →
                // Flutter won't push the player (subtitle alone is useless).
            }
            else -> {
                // Normal video file (or unknown — pass through so media_kit can try).
                pendingVideoUri   = uriStr
                pendingVideoTitle = displayName.ifEmpty { resolveDisplayName(data) }
                // Try to auto-discover a sidecar subtitle next to the video.
                val videoFilePath = getFilePath(data)
                if (videoFilePath != null) {
                    pendingSubtitleUri = findMatchingSubtitle(videoFilePath, displayName)
                }
            }
        }
    }

    /** Resolve a subtitle URI to an absolute file path.
     *  Tries DATA column first; falls back to copying content into app cache. */
    private fun resolveSubtitlePath(uri: android.net.Uri, displayName: String): String? {
        // Fast path: real file path via _data
        val filePath = getFilePath(uri)
        if (filePath != null) return filePath
        // Fallback: copy to app cache so MPV can read it by absolute path
        val ext = displayName.substringAfterLast('.', "srt")
        return try {
            val tmp = java.io.File(cacheDir, "sub_${'$'}{System.currentTimeMillis()}.${'$'}ext")
            contentResolver.openInputStream(uri)?.use { input ->
                tmp.outputStream().use { out -> input.copyTo(out) }
            }
            tmp.absolutePath
        } catch (_: Exception) { null }
    }

    /** Given a subtitle URI, find a video file with the same base name in the same directory. */
    private fun findMatchingVideo(subtitleUri: android.net.Uri, subtitleName: String): String? {
        val base = subtitleName.substringBeforeLast('.')
        if (base.isEmpty()) return null

        // Try filesystem first (works when we have a real file path)
        val subPath = getFilePath(subtitleUri)
        if (subPath != null) {
            val dir = java.io.File(subPath).parentFile ?: return null
            for (ext in VIDEO_EXTS) {
                val candidate = java.io.File(dir, "${'$'}base.${'$'}ext")
                if (candidate.exists()) return candidate.absolutePath
            }
            return null
        }

        // MediaStore fallback: query by display name
        val proj = arrayOf(android.provider.MediaStore.Video.Media.DATA)
        for (ext in VIDEO_EXTS) {
            try {
                contentResolver.query(
                    android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    proj,
                    "${'$'}{android.provider.MediaStore.Video.Media.DISPLAY_NAME} = ?",
                    arrayOf("${'$'}base.${'$'}ext"),
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

    /** Given a video file path + display name, find a subtitle file in the same directory. */
    private fun findMatchingSubtitle(videoFilePath: String, videoName: String): String? {
        val base = videoName.substringBeforeLast('.')
        if (base.isEmpty()) return null
        val dir = java.io.File(videoFilePath).parentFile ?: return null
        for (ext in SUBTITLE_EXTS) {
            val candidate = java.io.File(dir, "${'$'}base.${'$'}ext")
            if (candidate.exists()) return candidate.absolutePath
            val upper = java.io.File(dir, "${'$'}base.${'$'}{ext.uppercase()}")
            if (upper.exists()) return upper.absolutePath
        }
        return null
    }

    /** Get the real filesystem path from a URI (content:// or file://).
     *  Returns null when the path cannot be resolved (e.g. cloud-only providers). */
    private fun getFilePath(uri: android.net.Uri): String? {
        return try {
            when (uri.scheme) {
                "file" -> uri.path
                "content" -> contentResolver.query(
                    uri,
                    arrayOf(android.provider.MediaStore.MediaColumns.DATA),
                    null, null, null
                )?.use { c ->
                    if (c.moveToFirst()) c.getString(0) else null
                }
                else -> null
            }
        } catch (_: Exception) { null }
    }

    /** Query Android ContentResolver for the human-readable display name of a URI.
     *  Works for content:// (MediaStore, Downloads, file pickers) and file:// URIs.
     *  Returns null if name cannot be resolved — caller falls back to URI path segment. */
    private fun resolveDisplayName(uri: android.net.Uri): String? {
        return when (uri.scheme) {
            "content" -> {
                try {
                    val cursor = contentResolver.query(uri, null, null, null, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val col = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (col >= 0) it.getString(col) else null
                        } else null
                    }
                } catch (e: Exception) { null }
            }
            "file" -> {
                try {
                    val raw = uri.lastPathSegment ?: return null
                    java.net.URLDecoder.decode(raw, "UTF-8")
                } catch (e: Exception) { uri.lastPathSegment }
            }
            else -> null
        }
    }
}
