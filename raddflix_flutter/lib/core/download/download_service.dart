import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../db/local_db.dart';
import '../services/jazzdrive_service.dart';
import '../debug/debug_logger.dart';
import '../constants.dart';
import '../api/api_client.dart';

class DownloadService {
  static final Dio _dio = Dio();
  static final _cancelTokens = <String, CancelToken>{};


  static Future<void> _checkDownloadQuota() async {
    try {
      final res = await ApiClient.instance.get(ApiPaths.quota);
      final quota = (res.data as Map<String, dynamic>?)?['quota']
                    as Map<String, dynamic>?;
      if (quota != null && quota['allowed'] == false) {
        final reason = quota['reason'] as String? ?? 'quota_exceeded';
        throw DownloadQuotaException(reason);
      }
    } on DownloadQuotaException {
      rethrow;
    } catch (e) {
      DebugLogger.logWarn('DOWNLOAD', 'Quota check failed (allowing): $e');
    }
  }

  /// Download a video file and save to private app storage.
  ///
  /// [targetFilename] — optional episode filename (e.g. "S01E04.mkv").
  ///   For folder-share episodes, this is passed to [JazzDriveService.getStreamLink]
  ///   so the 3-pass filename matcher picks the correct episode instead of
  ///   blindly returning records.first.
  /// [remoteId] — JazzDrive's permanent numeric file ID (from Oracle remote_id).
  ///   Enables Pass 0 exact matching — completely filename-independent.
  ///   Pass 0 when not available; the service falls through to Passes 1-3.
  static Future<void> downloadFile({
    required String fileId,
    required String titleText,
    required String streamUrl,
    String? posterUrl,
    String? shareUrl,
    String? targetFilename,
    int remoteId = 0,
    required void Function(double progress) onProgress,
    String? contentType,
  }) async {
    await _checkDownloadQuota();

    String resolvedUrl = streamUrl;

    // Path A: shareUrl passed in from caller (may be RF1:xxx scrambled from
    // CatalogItem.shareUrl — decode it before handing to JazzDriveService).
    // FIX-BUG2: CatalogItem.shareUrl carries raw RF1:xxx from _rowToItem;
    // _extractShareKey regex fails on scrambled URLs → decode first.
    if (shareUrl != null && shareUrl.isNotEmpty) {
      final decodedShareUrl = await LocalDb.decodeShareUrl(shareUrl) ?? shareUrl;
      try {
        final link = await JazzDriveService.getStreamLink(
          fileId,
          decodedShareUrl,
          targetFilename: targetFilename,
          remoteId: remoteId,
        );
        resolvedUrl = link.streamUrl;
        DebugLogger.log('DOWNLOAD', 'Using JazzDrive URL for $fileId');
      } catch (e) {
        DebugLogger.logWarn('DOWNLOAD', 'JazzDrive link failed, using provided URL: $e');
      }
    } else {
      // Path B: no shareUrl passed — look up in SQLite.
      // FIX-BUG1: was using getShareUrl() which only returns the URL string,
      // losing filename and remote_id. For folder-share TV episodes this caused
      // getStreamLink to skip Pass 0 (remote_id) and Passes 1-3 (filename),
      // always falling back to records.first — downloading the wrong episode.
      // Fix: use getShareInfo() which returns all three fields in one query.
      final shareInfo      = await LocalDb.getShareInfo(fileId);
      final dbShareUrl     = shareInfo['share_url'] as String?;
      final dbFilename     = shareInfo['filename']  as String?;
      final dbRemoteId     = shareInfo['remote_id'] as int? ?? 0;

      if (dbShareUrl != null && dbShareUrl.isNotEmpty) {
        try {
          final link = await JazzDriveService.getStreamLink(
            fileId,
            dbShareUrl,
            targetFilename: dbFilename ?? targetFilename,
            remoteId: dbRemoteId > 0 ? dbRemoteId : remoteId,
          );
          resolvedUrl = link.streamUrl;
          DebugLogger.log('DOWNLOAD', 'Using DB JazzDrive URL for $fileId');
        } catch (e) {
          DebugLogger.logWarn('DOWNLOAD', 'DB JazzDrive link failed, using provided URL: $e');
        }
      }
    }
    final dir = await _getDownloadDir();
    final localPath = '${dir.path}/$fileId.mp4';

    await LocalDb.insertDownload(
      fileId: fileId,
      titleText: titleText,
      posterUrl: posterUrl,
      localPath: localPath,
      contentType: contentType,
    );

    final cancelToken = CancelToken();
    _cancelTokens[fileId] = cancelToken;
    int localProgressPct5 = -1; // H-06: local per-download, not shared across concurrent downloads
    try {
      await _dio.download(
        resolvedUrl,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          onProgress(progress);
          // FIX-DL-THROTTLE: only write to DB when progress crosses a 5% boundary
          // to avoid flooding SQLite with hundreds of UPDATE calls per second.
          final pct5 = (progress * 20).floor();
          if (pct5 != localProgressPct5) {
            localProgressPct5 = pct5;
            LocalDb.updateDownloadProgress(fileId, progress);
          }
        },
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final file = File(localPath);
      final fileSize = await file.exists() ? await file.length() : 0;
      // BUG-DL-08: validate file is not a partial/empty download (< 512 KB = broken)
      if (fileSize < 512 * 1024) {
        await file.exists().then((e) => e ? file.delete() : Future.value());
        await LocalDb.updateDownloadStatus(fileId, 'failed', 0.0, 0);
        throw Exception('Download incomplete: file too small (${fileSize} bytes)');
      }
      await LocalDb.updateDownloadStatus(fileId, 'completed', 1.0, fileSize);
      onProgress(1.0);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await LocalDb.updateDownloadStatus(fileId, 'cancelled', 0.0, 0);
        return; // cancelled by user — not an error
      }
      await LocalDb.updateDownloadStatus(fileId, 'failed', 0.0, 0);
      rethrow;
    } catch (e) {
      await LocalDb.updateDownloadStatus(fileId, 'failed', 0.0, 0);
      rethrow;
    } finally {
      _cancelTokens.remove(fileId);
    }
  }

  /// Cancel an in-progress download. No-op if not downloading.
  static void cancelDownload(String fileId) {
    _cancelTokens[fileId]?.cancel('User cancelled');
    _cancelTokens.remove(fileId);
  }

  static Future<void> deleteDownload(String fileId) async {
    await LocalDb.deleteDownload(fileId);
  }

  static Future<bool> isDownloaded(String fileId) async {
    final downloads = await LocalDb.getDownloads();
    final match = downloads.where((d) =>
        d['file_id'] == fileId && d['status'] == 'completed');
    if (match.isEmpty) return false;
    final path = match.first['local_path'] as String?;
    if (path == null) return false;
    return File(path).exists();
  }

  static Future<String?> getLocalPath(String fileId) async {
    final downloads = await LocalDb.getDownloads();
    final match = downloads.where((d) =>
        d['file_id'] == fileId && d['status'] == 'completed');
    if (match.isEmpty) return null;
    return match.first['local_path'] as String?;
  }

  static Future<Directory> _getDownloadDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class DownloadQuotaException implements Exception {
  final String reason;
  const DownloadQuotaException(this.reason);

  String get userMessage {
    switch (reason) {
      case 'daily_limit_reached':   return 'Daily data limit reached. Resets at midnight.';
      case 'monthly_limit_reached': return 'Monthly data limit reached. Upgrade your plan.';
      case 'no_subscription':       return 'Active subscription required to download.';
      default:                      return 'Download quota exceeded. Try again later.';
    }
  }

  @override
  String toString() => 'DownloadQuotaException($reason)';
}
