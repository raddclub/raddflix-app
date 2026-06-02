import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../api/catalog_api.dart';
import '../constants.dart';
import '../debug/debug_logger.dart';
import '../services/jazzdrive_service.dart';
import '../services/usage_service.dart';
import 'local_db.dart';
import '../../models/catalog_item.dart';

/// Handles syncing the catalog from the server into the local SQLite database.
///
/// Sync priority:
///   1. Oracle server (http://92.4.95.252) — when internet is available
///   2. JazzDrive delta.json — zero-rated fallback when no internet bundle
///
/// Delta format (delta_v2): 24h rolling window of published titles.
/// Includes file_id, share_url, folder_share_url, and full episode list.
/// Merges into local SQLite — skips duplicates, never deletes user data.
///
/// JazzDrive share URL resolution:
///   The jd_delta_url is a share page URL (cloud.jazzdrive.com.pk/share/f/KEY).
///   Fetching it directly returns HTML. Resolution requires a 2-step API flow:
///     1. POST /sapi/link/login?action=login → validationKey
///     2. GET /sapi/media/video → CDN download URL
///   Both calls are zero-rated on Jazz SIM.
class SyncService {
  static Future<SyncResult> sync() async {
    // Try Oracle server first
    try {
      final result = await _syncFromOracle();
      return result;
    } catch (e) {
      DebugLogger.logWarn('SYNC', 'Oracle sync failed: $e — trying JazzDrive fallback');
    }

    // Fallback: JazzDrive zero-rated delta sync (works without internet bundle)
    if (AppConstants.jazzDriveDeltaUrl.isNotEmpty) {
      try {
        final result = await _syncFromJazzDriveDelta();
        return result;
      } catch (e) {
        DebugLogger.logError('SYNC', 'JazzDrive delta fallback also failed', e);
      }
    }

    return const SyncResult(
      success: false,
      itemsSynced: 0,
      message: 'Sync failed: no internet and no JazzDrive delta fallback configured',
      isUpToDate: false,
    );
  }

  // ── Oracle server sync ────────────────────────────────────────────────────

  static Future<SyncResult> _syncFromOracle() async {
    UsageService.fetchQuota().ignore();

    final lastSyncTs = await LocalDb.getLastSyncTimestamp();
    final serverVersion = await CatalogApi.getVersion();
    final localVersion = await LocalDb.getLastSyncVersion();

    if (localVersion >= serverVersion.version && lastSyncTs > 0) {
      return const SyncResult(
        success: true,
        itemsSynced: 0,
        message: 'Already up to date',
        isUpToDate: true,
      );
    }

    List<CatalogItem> items;
    if (lastSyncTs == 0) {
      items = await CatalogApi.syncFull();
    } else {
      items = await CatalogApi.syncDelta(lastSyncTs);
    }

    await _persistItems(items);

    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setLastSyncVersion(serverVersion.version);
    await LocalDb.setLastSyncTimestamp(nowTs);

    DebugLogger.log('SYNC', 'Oracle sync complete: ${items.length} item(s)');
    unawaited(JazzDriveService.warmTopFreeItems(8));
    return SyncResult(
      success: true,
      itemsSynced: items.length,
      message: 'Synced ${items.length} item(s) from server',
      isUpToDate: false,
    );
  }

  // ── JazzDrive zero-rated delta sync ──────────────────────────────────────

  /// Fetches delta.json from JazzDrive (zero-rated) and merges it into the
  /// local catalog. delta_v2 format carries full playback data (file_id,
  /// share_url, folder_share_url, episodes) — everything needed to play.
  ///
  /// If jazzDriveDeltaUrl is a JazzDrive share URL it resolves it first via
  /// the 2-step SAPI flow (also zero-rated) to get the CDN download URL.
  static Future<SyncResult> _syncFromJazzDriveDelta() async {
    DebugLogger.log('SYNC', 'Attempting JazzDrive delta.json sync (zero-rated)');

    final deltaUrl = AppConstants.jazzDriveDeltaUrl;
    String downloadUrl = deltaUrl;

    // If it is a JazzDrive share URL, resolve to CDN URL first (2-step zero-rated flow)
    if (_isJazzDriveShareUrl(deltaUrl)) {
      DebugLogger.log('SYNC', 'Resolving JazzDrive share URL → CDN URL');
      downloadUrl = await _resolveJazzDriveDocumentUrl(deltaUrl);
      DebugLogger.log('SYNC', 'Resolved CDN URL: $downloadUrl');
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ));

    final resp = await dio.get<dynamic>(downloadUrl);
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('JazzDrive delta sync: HTTP ${resp.statusCode}');
    }

    final raw = resp.data is String
        ? json.decode(resp.data as String) as Map<String, dynamic>
        : resp.data as Map<String, dynamic>;

    final remoteVersion = raw['version'] as int? ?? 0;
    final localVersion = await LocalDb.getLastSyncVersion();

    if (localVersion >= remoteVersion && localVersion > 0) {
      DebugLogger.log('SYNC', 'JazzDrive delta: already up to date (v$localVersion)');
      return const SyncResult(
        success: true,
        itemsSynced: 0,
        message: 'Already up to date (JazzDrive delta)',
        isUpToDate: true,
      );
    }

    final titlesRaw = raw['titles'] as List<dynamic>? ?? [];
    int merged = 0;

    for (final t in titlesRaw) {
      final row = t as Map<String, dynamic>;

      // Merge title row (preserves existing share_url if delta has none)
      await LocalDb.mergeDeltaTitle({
        'id':               row['id'],
        'title':            row['title'] ?? '',
        'year':             row['year'],
        'media_type':       row['media_type'] ?? 'movie',
        'description':      row['description'] ?? '',
        'rating':           (row['rating'] as num?)?.toDouble() ?? 0.0,
        'genres':           row['genres'] is List
            ? json.encode(row['genres'])
            : (row['genres'] as String? ?? '[]'),
        'poster_url':       row['poster_url'] ?? '',
        'is_free':          (row['is_free'] == true || row['is_free'] == 1) ? 1 : 0,
        'db_version':       row['db_version'] ?? 0,
        'language':         row['language'] ?? '',
        'status':           row['status'] ?? 'released',
        'is_ongoing':       (row['is_ongoing'] == true || row['is_ongoing'] == 1) ? 1 : 0,
        'share_url':        row['share_url'] ?? '',
        'folder_share_url': row['folder_share_url'] ?? '',
        'poster_share_url': row['poster_share_url'] ?? '',
        'file_id':          row['file_id']?.toString() ?? '',
      });

      // Merge episode list for shows
      final episodes = row['episodes'] as List<dynamic>? ?? [];
      if (episodes.isNotEmpty) {
        for (final ep in episodes) {
          final epRow = ep as Map<String, dynamic>;
          await LocalDb.upsertEpisode({
            'id':              epRow['id'],
            'title_id':        row['id'],
            'file_id':         epRow['file_id']?.toString(),
            'season':          epRow['season'],
            'episode':         epRow['episode'],
            'label':           epRow['label'],
            'quality':         epRow['quality'],
            'is_free':         (epRow['is_free'] == true || epRow['is_free'] == 1) ? 1 : 0,
            'share_url':       epRow['share_url'] ?? '',
            'filename':        epRow['filename']  ?? '',
          });
        }
      }

      merged++;
    }

    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setLastSyncVersion(remoteVersion);
    await LocalDb.setLastSyncTimestamp(nowTs);

    DebugLogger.log('SYNC', 'JazzDrive delta sync complete: $merged title(s) merged');
    unawaited(JazzDriveService.warmTopFreeItems(8));
    return SyncResult(
      success: true,
      itemsSynced: merged,
      message: 'Synced $merged title(s) via JazzDrive (zero-rated)',
      isUpToDate: false,
    );
  }

  // ── JazzDrive share URL resolver ──────────────────────────────────────────

  /// Returns true if [url] is a JazzDrive share page URL (not a direct CDN URL).
  static bool _isJazzDriveShareUrl(String url) {
    return url.contains('cloud.jazzdrive.com.pk/share/') ||
           url.contains('cloud.jazzdrive.com.pk/share-landing/');
  }

  /// Resolves a JazzDrive share URL to a direct CDN download URL.
  ///
  /// JazzDrive share URLs return HTML when fetched directly.
  /// This 2-step flow retrieves the actual file download URL:
  ///   Step 1: POST /sapi/link/login?action=login with the share key
  ///           → returns validationKey
  ///   Step 2: GET /sapi/media/video?shared=true&key=KEY&validationkey=VK
  ///           → returns list of files; picks the first document/JSON entry
  ///
  /// Both steps hit cloud.jazzdrive.com.pk which is zero-rated on Jazz SIM.
  static Future<String> _resolveJazzDriveDocumentUrl(String shareUrl) async {
    const cloudBase = 'https://cloud.jazzdrive.com.pk';

    // Extract share key from URL  e.g. /share/f/ABC123
    final keyMatch = RegExp(r'/(?:share(?:-landing)?/f|f)/([^/?#]+)').firstMatch(shareUrl);
    if (keyMatch == null) throw Exception('Invalid JazzDrive share URL: $shareUrl');
    final shareKey = keyMatch.group(1)!;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)',
        'X-Requested-With': 'com.jazz.drive',
      },
    ));

    // Step 1: Login to share link → validationKey
    final loginResp = await dio.post<dynamic>(
      '$cloudBase/sapi/link/login?action=login',
      data: {'data': {'accesstoken': shareKey}},
    );
    if (loginResp.statusCode != 200) {
      throw Exception('JazzDrive share login failed: ${loginResp.statusCode}');
    }
    final loginData = loginResp.data is Map
        ? loginResp.data as Map<String, dynamic>
        : json.decode(loginResp.data as String) as Map<String, dynamic>;
    final inner = (loginData['data'] as Map<String, dynamic>?) ?? loginData;
    final vk = (inner['validationkey'] ?? inner['validation_key']) as String?;
    if (vk == null || vk.isEmpty) {
      throw Exception('JazzDrive share login: no validationKey in response');
    }

    // Step 2: Fetch file list → find JSON document download URL
    final mediaResp = await dio.get<dynamic>(
      '$cloudBase/sapi/media/video',
      queryParameters: {
        'action': 'get',
        'shared': 'true',
        'key': shareKey,
        'validationkey': vk,
      },
      options: Options(headers: {'validation_key': vk}),
    );
    if (mediaResp.statusCode != 200) {
      throw Exception('JazzDrive media fetch failed: ${mediaResp.statusCode}');
    }
    final mediaData = mediaResp.data is Map
        ? mediaResp.data as Map<String, dynamic>
        : json.decode(mediaResp.data as String) as Map<String, dynamic>;

    // Extract file list
    List<dynamic> records = [];
    final res = mediaData['data'] ?? mediaData;
    if (res is List) {
      records = res;
    } else if (res is Map) {
      for (final k in ['list', 'items', 'videos', 'result']) {
        if (res[k] is List) { records = res[k] as List; break; }
      }
    }
    if (records.isEmpty) throw Exception('JazzDrive share: no files in response');

    // Pick first record (delta.json is the only file in the share folder)
    final rec = records.first as Map<String, dynamic>;
    final rawUrl = rec['downloadUrl'] ?? rec['download_url'] ?? rec['url'] ?? '';
    if ((rawUrl as String).isEmpty) throw Exception('JazzDrive share: no download URL in record');

    return rawUrl.startsWith('/') ? '$cloudBase$rawUrl' : rawUrl;
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Full persist — used by Oracle sync. Replaces the full row including
  /// share_url and file_id which come from the trusted Oracle server.
  static Future<void> _persistItems(List<CatalogItem> items) async {
    for (final item in items) {
      await LocalDb.upsertTitle(item);
      for (final ep in item.episodes) {
        await LocalDb.upsertEpisode({
          'id':        ep['id'],
          'title_id':  item.id,
          'file_id':   ep['file_id']?.toString(),
          'season':    ep['season'],
          'episode':   ep['episode'],
          'label':     ep['label'],
          'quality':   ep['quality'],
          'is_free':   (ep['is_free'] == true || ep['is_free'] == 1) ? 1 : 0,
          'share_url': ep['share_url'] as String?,
          'filename':  ep['filename']  as String?,
        });
      }
    }
  }
}

class SyncResult {
  final bool success;
  final int itemsSynced;
  final String message;
  final bool isUpToDate;

  const SyncResult({
    required this.success,
    required this.itemsSynced,
    required this.message,
    required this.isUpToDate,
  });
}
