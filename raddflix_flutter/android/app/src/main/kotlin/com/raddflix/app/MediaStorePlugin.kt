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
              "requestMediaPermission" -> { pendingResult = result; requestPermission() }
              "queryVideos"            -> queryVideos(result)
              "getThumbnail"           -> getThumbnail(call, result)
              "openAppSettings"        -> { openAppSettings(); result.success(null) }
              else                     -> result.notImplemented()
          }
      }

      // ── Permission helpers ────────────────────────────────────────────────────
      private fun hasPermission(): Boolean {
          return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) ==
                      PackageManager.PERMISSION_GRANTED
          } else {
              ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                      PackageManager.PERMISSION_GRANTED
          }
      }

      private fun requestPermission() {
          val activity = activityBinding?.activity ?: run {
              pendingResult?.success(false); return
          }
          val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
              Manifest.permission.READ_MEDIA_VIDEO
          else
              Manifest.permission.READ_EXTERNAL_STORAGE
          activity.requestPermissions(arrayOf(permission), PERMISSION_REQUEST_CODE)
      }

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

      // ── MediaStore query ──────────────────────────────────────────────────────
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
                          "title"         to (cursor.getString(titleCol) ?: filePath.substringAfterLast("/").substringBeforeLast(".")),
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
  }
