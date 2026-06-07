package com.raddflix.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
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

    companion object {
        private val SUBTITLE_EXTS = setOf("srt", "ass", "ssa", "vtt", "sub")
        private val VIDEO_EXTS    = setOf("mp4", "mkv", "avi", "mov", "flv", "wmv", "m4v", "3gp", "ts", "webm", "m2ts", "mts")
        // Request code for MediaStore.createDeleteRequest (Android 11+ vault import cleanup)
        private const val DELETE_MEDIA_REQUEST_CODE = 9002
    }

    private var intentMethodChannel: MethodChannel? = null

    // Holds the pending MethodChannel.Result for deleteMediaFiles while the
    // system delete-permission dialog is shown on Android 11+.
    private var pendingDeleteResult: MethodChannel.Result? = null

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

        // ── Media Channel (scanFile + deleteMediaFiles for vault) ─────────
        //
        // deleteMediaFiles — removes the ORIGINAL files from MediaStore so they
        // disappear from the gallery and all third-party media players after
        // the user imports them into the private vault.
        //
        // Android 11+ (API 30+): uses MediaStore.createDeleteRequest which shows
        // a one-time system confirmation dialog "Allow RaddFlix to delete N items?"
        //
        // Android 10 and below: deletes via ContentResolver directly (works
        // because requestLegacyExternalStorage=true grants broad write access).
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
                            // Android 11+: show system dialog asking user to approve deletion.
                            // The system enforces this — apps cannot silently delete MediaStore
                            // items they don't own without MANAGE_EXTERNAL_STORAGE permission.
                            try {
                                val deleteRequest = MediaStore.createDeleteRequest(contentResolver, uris)
                                pendingDeleteResult = result
                                startIntentSenderForResult(
                                    deleteRequest.intentSender,
                                    DELETE_MEDIA_REQUEST_CODE,
                                    null, 0, 0, 0
                                )
                                // result will be resolved in onActivityResult
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        } else {
                            // Android 10 and below: direct delete via ContentResolver.
                            // With requestLegacyExternalStorage=true, the app has write
                            // access to external storage, so this succeeds.
                            var deletedCount = 0
                            for (uri in uris) {
                                try {
                                    val rows = contentResolver.delete(uri, null, null)
                                    if (rows > 0) deletedCount++
                                } catch (e: SecurityException) {
                                    // Fallback: scan the path so MediaStore removes
                                    // the stale entry when it finds the file gone
                                    val filePath = getFilePath(uri)
                                    if (filePath != null) {
                                        MediaScannerConnection.scanFile(
                                            this, arrayOf(filePath), null, null
                                        )
                                        deletedCount++
                                    }
                                } catch (e: Exception) {
                                    // Silent — best-effort deletion
                                }
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

    // ── Activity result: handle MediaStore.createDeleteRequest response ───
    // Called after the system dialog "Allow RaddFlix to delete N items?" on API 30+.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DELETE_MEDIA_REQUEST_CODE) {
            val approved = resultCode == Activity.RESULT_OK
            pendingDeleteResult?.success(approved)
            pendingDeleteResult = null
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
