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
        if (uri != null) {
            // Pass both uri and resolved display name so Flutter can show a proper title
            val args = mapOf("uri" to uri, "title" to (pendingVideoTitle ?: ""))
            intentMethodChannel?.invokeMethod("onVideoUri", args)
            pendingVideoUri = null
            pendingVideoTitle = null
        }
    }

    private fun extractVideoUri(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val data = intent.data ?: return
            val uriStr = data.toString()
            if (uriStr.isNotEmpty()) {
                pendingVideoUri = uriStr
                pendingVideoTitle = resolveDisplayName(data)
            }
        }
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
