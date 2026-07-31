package com.raddflix.app

  import android.Manifest
  import android.content.ContentUris
  import android.content.Context
  import android.content.Intent
  import android.content.pm.PackageManager
  import android.net.Uri
  import android.os.Build
  import android.graphics.Bitmap
import android.provider.MediaStore
  import android.provider.Settings
  import androidx.core.content.ContextCompat
  import io.flutter.embedding.engine.plugins.FlutterPlugin
  import io.flutter.embedding.engine.plugins.activity.ActivityAware
  import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
  import io.flutter.plugin.common.MethodCall
  import io.flutter.plugin.common.MethodChannel
  import io.flutter.plugin.common.PluginRegistry

  class MediaStorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
      ActivityAware, PluginRegistry.RequestPermissionsResultListener {

      private lateinit var channel: MethodChannel
      private lateinit var context: Context
      private var activityBinding: ActivityPluginBinding? = null
      private var pendingResult: MethodChannel.Result? = null

      // 0C THUMB-PERF: background executor for blocking MediaMetadataRetriever
      // calls. CachedThreadPool reuses idle threads for concurrent thumb loads
      // (e.g. grid scroll) without spawning a new Thread per file.
      private val executor = java.util.concurrent.Executors.newCachedThreadPool()
      // All MethodChannel.Result callbacks must be delivered on the main thread.
      private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

      companion object {
          private const val CHANNEL = "com.raddflix.app/media_store"
          private const val PERMISSION_REQUEST_CODE = 9001
      }

      override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
          context = binding.applicationContext
          channel = MethodChannel(binding.binaryMessenger, CHANNEL)
          channel.setMethodCallHandler(this)
      }

      override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
          channel.setMethodCallHandler(null)
      }

      override fun onAttachedToActivity(binding: ActivityPluginBinding) {
          activityBinding = binding
          binding.addRequestPermissionsResultListener(this)
      }

      override fun onDetachedFromActivity() {
          activityBinding?.removeRequestPermissionsResultListener(this)
          activityBinding = null
      }

      override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
      override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

      override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
          when (call.method) {
              "checkMediaPermission"   -> result.success(hasPermission())
              "checkAudioPermission"   -> result.success(hasAudioPermission())
              "requestMediaPermission" -> { pendingResult = result; requestPermission() }
              "queryVideos"            -> queryVideos(result)
              "queryAudio"             -> queryAudio(result)
              "getThumbnail"           -> getThumbnail(call, result)
              "getAlbumArt"            -> getAlbumArt(call, result)
              "getFrameAtTime"         -> getFrameAtTime(call, result)
              "openAppSettings"        -> { openAppSettings(); result.success(null) }
              else                     -> result.notImplemented()
          }
      }

      // ── Permission helpers ────────────────────────────────────────────────────

      // Video permission — unchanged for backward compat (Videos tab depends on this)
      private fun hasPermission(): Boolean {
          return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) ==
                      PackageManager.PERMISSION_GRANTED
          } else {
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                      PackageManager.PERMISSION_GRANTED
          }
      }

      // Audio permission — separate check for Music tab (API 33+ has granular permissions)
      private fun hasAudioPermission(): Boolean {
          return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_AUDIO) ==
                      PackageManager.PERMISSION_GRANTED
          } else {
              // Below API 33, READ_EXTERNAL_STORAGE covers both video and audio
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                      PackageManager.PERMISSION_GRANTED
          }
      }

      // Request both video + audio at once on API 33+; READ_EXTERNAL_STORAGE covers both below.
      private fun requestPermission() {
          val activity = activityBinding?.activity ?: run {
              pendingResult?.success(false); return
          }
          val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
              arrayOf(
                  Manifest.permission.READ_MEDIA_VIDEO,
                  Manifest.permission.READ_MEDIA_AUDIO,
              )
          else
              arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
          activity.requestPermissions(permissions, PERMISSION_REQUEST_CODE)
      }

      // grantResults[0] = READ_MEDIA_VIDEO (or READ_EXTERNAL_STORAGE on API < 33).
      // We report "granted" based on the video permission — the Videos tab is primary.
      // Audio permission (grantResults[1] on API 33+) is independently checked via
      // hasAudioPermission() before queryAudio() runs.
      override fun onRequestPermissionsResult(
          requestCode: Int, permissions: Array<out String>, grantResults: IntArray
      ): Boolean {
          if (requestCode != PERMISSION_REQUEST_CODE) return false
          val granted = grantResults.isNotEmpty() &&
                  grantResults[0] == PackageManager.PERMISSION_GRANTED
          pendingResult?.success(granted)
          pendingResult = null
          return true
      }

      private fun openAppSettings() {
          val activity = activityBinding?.activity ?: return
          val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
              data = Uri.fromParts("package", context.packageName, null)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          }
          activity.startActivity(intent)
      }

      // ── Video MediaStore query ────────────────────────────────────────────────
      private fun queryVideos(result: MethodChannel.Result) {
          if (!hasPermission()) { result.success(emptyList<Any>()); return }

          val videos = mutableListOf<Map<String, Any?>>()

          val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
              MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
          else
              MediaStore.Video.Media.EXTERNAL_CONTENT_URI

          val projection = arrayOf(
              MediaStore.Video.Media._ID,
              MediaStore.Video.Media.TITLE,
              MediaStore.Video.Media.DISPLAY_NAME,
              MediaStore.Video.Media.DATA,
              MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
              MediaStore.Video.Media.BUCKET_ID,
              MediaStore.Video.Media.DURATION,
              MediaStore.Video.Media.SIZE,
              MediaStore.Video.Media.WIDTH,
              MediaStore.Video.Media.HEIGHT,
              MediaStore.Video.Media.DATE_MODIFIED,
              MediaStore.Video.Media.MIME_TYPE,
          )

          val sortOrder = "${MediaStore.Video.Media.DATE_MODIFIED} DESC"

          try {
              context.contentResolver.query(
                  collection, projection, null, null, sortOrder
              )?.use { cursor ->
                  val idCol          = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                  val titleCol       = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.TITLE)
                  val displayCol     = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                  val dataCol        = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                  val bucketNameCol  = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                  val durationCol    = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                  val sizeCol        = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                  val widthCol       = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
                  val heightCol      = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
                  val dateModCol     = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
                  val mimeCol        = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)

                  while (cursor.moveToNext()) {
                      val id       = cursor.getLong(idCol)
                      val filePath = cursor.getString(dataCol) ?: continue
                      val folderPath = filePath.substringBeforeLast("/")
                      val bucketName = cursor.getString(bucketNameCol) ?: folderPath.substringAfterLast("/")

                      videos.add(mapOf(
                          "id"            to id.toInt(),
                          "title"         to (cursor.getString(titleCol) ?: ""),
                          "display_name"  to (cursor.getString(displayCol) ?: ""),
                          "file_path"     to filePath,
                          "folder_name"   to bucketName,
                          "folder_path"   to folderPath,
                          "duration"      to cursor.getLong(durationCol).toInt(),
                          "size"          to cursor.getLong(sizeCol).toInt(),
                          "width"         to cursor.getInt(widthCol),
                          "height"        to cursor.getInt(heightCol),
                          "date_modified" to cursor.getLong(dateModCol).toInt(),
                          "mime_type"     to (cursor.getString(mimeCol) ?: "video/mp4"),
                      ))
                  }
              }
          } catch (e: Exception) {
              result.error("QUERY_FAILED", e.message, null)
              return
          }

          result.success(videos)
      }

      // ── Audio MediaStore query ────────────────────────────────────────────────
      // Queries MediaStore.Audio.Media — returns tracks with artist/album/album_id
      // so the Music tab can display metadata and load album art separately.
      // Skips tracks < 50 KB (ringtones, notification sounds, etc.).
      // MediaStore returns "<unknown>" for artist/album when tags are absent —
      // normalised to empty string so the UI doesn't display that literal.
      private fun queryAudio(result: MethodChannel.Result) {
          if (!hasAudioPermission()) { result.success(emptyList<Any>()); return }

          val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
          val projection = arrayOf(
              MediaStore.Audio.Media._ID,
              MediaStore.Audio.Media.TITLE,
              MediaStore.Audio.Media.ARTIST,
              MediaStore.Audio.Media.ALBUM,
              MediaStore.Audio.Media.ALBUM_ID,
              MediaStore.Audio.Media.DURATION,
              MediaStore.Audio.Media.SIZE,
              MediaStore.Audio.Media.DATE_MODIFIED,
              MediaStore.Audio.Media.DATA,
              MediaStore.Audio.Media.DISPLAY_NAME,
              MediaStore.Audio.Media.MIME_TYPE,
              MediaStore.Audio.Media.BUCKET_DISPLAY_NAME,
          )
          val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
          val tracks = mutableListOf<Map<String, Any?>>()

          try {
              context.contentResolver.query(collection, projection, null, null, sortOrder)?.use { cursor ->
                  val idCol      = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                  val titleCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                  val artistCol  = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                  val albumCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                  val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                  val durCol     = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                  val sizeCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                  val dateCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                  val dataCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                  val dispCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                  val mimeCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                  val bucketCol  = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.BUCKET_DISPLAY_NAME)

                  while (cursor.moveToNext()) {
                      val filePath = cursor.getString(dataCol) ?: continue
                      val size     = cursor.getLong(sizeCol)
                      if (size < 50 * 1024) continue // skip ringtones / notif sounds
                      val folderPath = filePath.substringBeforeLast("/")
                      // Normalise MediaStore "<unknown>" tags to empty string
                      val artist = cursor.getString(artistCol)?.takeIf { it != "<unknown>" } ?: ""
                      val album  = cursor.getString(albumCol)?.takeIf  { it != "<unknown>" } ?: ""
                      tracks.add(mapOf(
                          "id"            to cursor.getLong(idCol).toInt(),
                          "title"         to (cursor.getString(titleCol) ?: ""),
                          "artist"        to artist,
                          "album"         to album,
                          "album_id"      to cursor.getLong(albumIdCol).toInt(),
                          "duration"      to cursor.getLong(durCol).toInt(),
                          "size"          to size.toInt(),
                          "date_modified" to cursor.getLong(dateCol).toInt(),
                          "file_path"     to filePath,
                          "display_name"  to (cursor.getString(dispCol) ?: ""),
                          "mime_type"     to (cursor.getString(mimeCol) ?: "audio/mpeg"),
                          "folder_name"   to (cursor.getString(bucketCol) ?: "Music"),
                          "folder_path"   to folderPath,
                      ))
                  }
              }
          } catch (e: Exception) {
              result.error("QUERY_FAILED", e.message, null)
              return
          }
          result.success(tracks)
      }

      // ── Video thumbnail (fast — reads MediaStore cached thumbnail DB on API 29+) ─
      private fun getThumbnail(call: MethodCall, result: MethodChannel.Result) {
          val id   = (call.argument<Any>("id") as? Number)?.toLong()
          val size = call.argument<Int>("size") ?: 200
          if (id == null) { result.success(null); return }
          try {
              val uri = ContentUris.withAppendedId(
                  MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
              val bytes: ByteArray = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                  val sz  = android.util.Size(size, size)
                  val bmp = context.contentResolver.loadThumbnail(uri, sz, null)
                  java.io.ByteArrayOutputStream().also { out ->
                      bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                  }.toByteArray()
              } else {
                  val filePath = context.contentResolver.query(
                      uri, arrayOf(MediaStore.Video.Media.DATA), null, null, null
                  )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                      ?: return result.success(null)
                  @Suppress("DEPRECATION")
                  val bmp = android.media.ThumbnailUtils.createVideoThumbnail(
                      filePath, MediaStore.Images.Thumbnails.MINI_KIND
                  ) ?: return result.success(null)
                  java.io.ByteArrayOutputStream().also { out ->
                      bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                  }.toByteArray()
              }
              result.success(bytes)
          } catch (e: Exception) {
              result.success(null)
          }
      }

      // ── Frame extraction via MediaMetadataRetriever (0C THUMB-PERF) ──────────
      // Replaces the MediaKit fallback path (full libmpv Player per thumb —
      // 1.5–4 s each). MediaMetadataRetriever uses Android's built-in video
      // codec to seek + decode a single frame — typically 50–200 ms for local
      // files. The blocking call runs on ioExecutor; result is posted back to
      // the Flutter/main thread via mainHandler.
      private fun getFrameAtTime(call: MethodCall, result: MethodChannel.Result) {
          val path   = call.argument<String>("path")
          val timeMs = (call.argument<Any>("time_ms") as? Number)?.toLong() ?: 3000L
          val maxW   = call.argument<Int>("max_width") ?: 240
          if (path.isNullOrBlank()) { mainHandler.post { result.success(null) }; return }
          executor.execute {
              var mmr: android.media.MediaMetadataRetriever? = null
              try {
                  mmr = android.media.MediaMetadataRetriever()
                  mmr.setDataSource(path)
                  // OPTION_CLOSEST_SYNC: fast seek to nearest sync frame;
                  // avoids long decode chain for non-key frames.
                  val bmp = mmr.getFrameAtTime(
                      timeMs * 1_000L, // μs
                      android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                  ) ?: mmr.getFrameAtTime() // fall back to default position
                  if (bmp == null) {
                      mainHandler.post { result.success(null) }
                      return@execute
                  }
                  val scale  = if (bmp.width > maxW) maxW.toFloat() / bmp.width else 1f
                  val scaledW = (bmp.width  * scale).toInt().coerceAtLeast(1)
                  val scaledH = (bmp.height * scale).toInt().coerceAtLeast(1)
                  val scaled  = if (scale < 1f)
                      Bitmap.createScaledBitmap(bmp, scaledW, scaledH, true)
                  else bmp
                  val bytes = java.io.ByteArrayOutputStream().also { out ->
                      scaled.compress(Bitmap.CompressFormat.JPEG, 75, out)
                  }.toByteArray()
                  mainHandler.post { result.success(bytes) }
              } catch (e: Exception) {
                  mainHandler.post { result.success(null) }
              } finally {
                  try { mmr?.release() } catch (_: Exception) {}
              }
          }
      }

      // ── Album art (reads MediaStore audio/albumart content URI) ───────────────
      // API 29+: uses loadThumbnail on the content://media/external/audio/albumart/<id> URI.
      // API < 29: falls back to the deprecated ALBUM_ART column from MediaStore.Audio.Albums.
      // Returns null (not an error) when no art exists — callers show a music-note placeholder.
      private fun getAlbumArt(call: MethodCall, result: MethodChannel.Result) {
          val albumId = (call.argument<Any>("album_id") as? Number)?.toLong()
          val size    = call.argument<Int>("size") ?: 200
          if (albumId == null) { result.success(null); return }
          try {
              val bytes: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                  try {
                      val artUri = Uri.parse("content://media/external/audio/albumart/$albumId")
                      val sz  = android.util.Size(size, size)
                      val bmp = context.contentResolver.loadThumbnail(artUri, sz, null)
                      java.io.ByteArrayOutputStream().also { out ->
                          bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
                      }.toByteArray()
                  } catch (_: Exception) { null }
              } else {
                  try {
                      @Suppress("DEPRECATION")
                      val cursor = context.contentResolver.query(
                          MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI,
                          arrayOf(MediaStore.Audio.Albums.ALBUM_ART),
                          "${MediaStore.Audio.Albums._ID} = ?",
                          arrayOf(albumId.toString()),
                          null
                      )
                      val artPath = cursor?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                      if (artPath != null) {
                          val bmp = android.graphics.BitmapFactory.decodeFile(artPath)
                              ?: return result.success(null)
                          val scaled = Bitmap.createScaledBitmap(bmp, size, size, true)
                          java.io.ByteArrayOutputStream().also { out ->
                              scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
                          }.toByteArray()
                      } else null
                  } catch (_: Exception) { null }
              }
              result.success(bytes)
          } catch (e: Exception) {
              result.success(null)
          }
      }
  }
