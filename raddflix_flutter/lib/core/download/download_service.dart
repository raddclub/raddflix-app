import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../db/local_db.dart';
import '../services/jazzdrive_service.dart';
import '../debug/debug_logger.dart';
import '../../core/constants.dart';
import '../api/api_client.dart';
import '../services/usage_service.dart';

/// Picks the real container extension for a downloaded file instead of
/// blindly assuming `.mp4`. Tries, in order: the episode/share filename the
/// server told us about, then the resolved stream URL's own path — falling
/// back to `mp4` only when neither yields a known video extension. Keeps a
/// downloaded MKV/TS/AVI file honestly named on disk instead of an .mp4 that
/// isn't really one (harmless for in-app playback, since mpv sniffs content
/// not extension, but misleading for anything outside the app — sharing,
/// "Open With", scoped-storage MediaStore scans, etc.).
String _resolveDownloadExtension({String? targetFilename, required String resolvedUrl}) {
  String? extFrom(String? nameOrUrl) {
    if (nameOrUrl == null || nameOrUrl.isEmpty) return null;
    final noQuery = nameOrUrl.split('?').first;
    final dot = noQuery.lastIndexOf('.');
    if (dot == -1 || dot == noQuery.length - 1) return null;
    final ext = noQuery.substring(dot + 1).toLowerCase();
    return AppConstants.playableVideoExtensions.contains(ext) ? ext : null;
  }
  return extFrom(targetFilename) ?? extFrom(resolvedUrl) ?? 'mp4';
}

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
    required void Function(double progress, int received, int total) onProgress,
    String? contentType,
  }) async {
    await _checkDownloadQuota();

    String resolvedUrl = streamUrl;
    String? resolvedFilename = targetFilename;

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
        DebugLogger.log('DOWNLOAD', 'Stream link resolved');
      } catch (e) {
        DebugLogger.logWarn('DOWNLOAD', 'Stream link failed, using fallback');
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
          resolvedFilename = dbFilename ?? targetFilename;
          DebugLogger.log('DOWNLOAD', 'Stream link resolved (cached)');
        } catch (e) {
          DebugLogger.logWarn('DOWNLOAD', 'Cached stream link failed, using fallback');
        }
      }
    }
    final dir = await _getDownloadDir();
    final ext = _resolveDownloadExtension(targetFilename: resolvedFilename, resolvedUrl: resolvedUrl);
    final localPath = '${dir.path}/$fileId.$ext';

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
    // BUG-DL-VALIDATE-01: remember the server-reported Content-Length (once known)
    // so completion can be validated against the *expected* size, not just a fixed
    // 512 KB floor — a large file truncated mid-download (e.g. connection dropped
    // at 80%) would previously pass the 512 KB check and be wrongly marked 'completed'.
    int expectedTotal = 0;
    try {
      await _dio.download(
        resolvedUrl,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) expectedTotal = total;
          final progress = total > 0 ? received / total : 0.0;
          onProgress(progress, received, total > 0 ? total : 0);
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
      // BUG-DL-08: validate file is not a partial/empty download (< 512 KB = broken).
      // BUG-DL-VALIDATE-01: also fail if the server told us the real size up front
      // (Content-Length) and we ended up with materially less than that — catches
      // truncated downloads on large files that would otherwise clear the 512 KB floor.
      final tooSmallAbsolute = fileSize < 512 * 1024;
      final tooSmallVsExpected = expectedTotal > 0 && fileSize < (expectedTotal * 0.99).floor();
      if (tooSmallAbsolute || tooSmallVsExpected) {
        await file.exists().then((e) => e ? file.delete() : Future.value());
        await LocalDb.updateDownloadStatus(fileId, 'failed', 0.0, 0);
        throw Exception(
          'Download incomplete: got $fileSize bytes'
          '${expectedTotal > 0 ? ' of expected $expectedTotal' : ''}',
        );
      }
      await LocalDb.updateDownloadStatus(fileId, 'completed', 1.0, fileSize);
      // Count actual downloaded bytes toward monthly quota (exact size, counted once at completion).
      // Playback of this file later uses _isLocal=true → zero additional quota deduction.
      UsageService.addDownloadBytes(bytes: fileSize).ignore();
      onProgress(1.0, fileSize, fileSize);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Delete partial file and remove DB record entirely so the item
        // disappears from the downloads list and the episode tile resets to
        // "not downloaded". Previously a stale 'cancelled' row and partial
        // .mp4 file were left on disk wasting storage.
        try { await File(localPath).delete(); } catch (_) {}
        await LocalDb.deleteDownload(fileId);
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

  // Real on-disk extension varies per file now (BUG-DL-EXT-01 fix — downloads
  // used to always assume `$fileId.mp4`), so both lookups below go through the
  // DB's recorded `local_path` rather than reconstructing a filename.
  static Future<bool> isDownloaded(String fileId) async {
    final downloads = await LocalDb.getDownloads();
    final match = downloads.where((d) => d['file_id'] == fileId && d['status'] == 'completed').firstOrNull;
    final path = match?['local_path'] as String?;
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  static Future<String?> getLocalPath(String fileId) async {
    final downloads = await LocalDb.getDownloads();
    final match = downloads.where((d) => d['file_id'] == fileId).firstOrNull;
    final path = match?['local_path'] as String?;
    if (path == null || path.isEmpty) return null;
    return (await File(path).exists()) ? path : null;
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

  // BUG-8 fix: system moved to monthly GB-based limits; 'daily_limit_reached' no longer
  // meaningful and the old "Resets at midnight" message was wrong and confusing.
  String get userMessage {
    switch (reason) {
      case 'daily_limit_reached':   return 'Monthly streaming quota reached. Upgrade your plan for more data.';
      case 'monthly_limit_reached': return 'Monthly data limit reached. Upgrade your plan.';
      case 'no_subscription':       return 'Active subscription required to download.';
      default:                      return 'Download quota exceeded. Try again later.';
    }
  }

  @override
  String toString() => 'DownloadQuotaException($reason)';
}
