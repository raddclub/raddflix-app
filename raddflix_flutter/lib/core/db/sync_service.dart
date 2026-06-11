import 'dart:async';
import 'package:dio/dio.dart';
import '../api/catalog_api.dart';
import '../debug/debug_logger.dart';
import '../services/jazzdrive_service.dart';
import '../services/usage_service.dart';
import 'local_db.dart';
import '../../models/catalog_item.dart';

/// Handles syncing the catalog from the Oracle server into the local SQLite DB.
///
/// Oracle (http://92.4.95.252) is the single catalog source.
/// If Oracle is unreachable the sync returns a failure — no JazzDrive fallback.
/// Stream links are generated on the Flutter client side via jazzdrive_service.dart
/// using folder_share_url from the catalog; no stream links are generated server-side.
///
/// Sync type decision:
///   - First run (lastSyncTs == 0)          → full sync
///   - Admin force-bump (forcedTs > local)  → full sync (plan/quota change)
///   - Normal delta                         → syncDelta(localVersion)
class SyncService {
  static Future<SyncResult> sync() async {
    try {
      return await _syncFromOracle();
    } catch (e) {
      DebugLogger.logError('SYNC', 'Oracle sync failed', e);
      return const SyncResult(
        success: false,
        itemsSynced: 0,
        message: 'Sync failed: could not reach Oracle server',
        isUpToDate: false,
      );
    }
  }

  // ── Oracle server sync ────────────────────────────────────────────────────

  static Future<SyncResult> _syncFromOracle() async {
    UsageService.fetchQuota().ignore();

    final lastSyncTs = await LocalDb.getLastSyncTimestamp();
    // Short probe timeout: if Oracle doesn't respond in 5s the user has no bundle.
    final serverVersion = await CatalogApi.getVersion().timeout(
      const Duration(seconds: 5),
    );
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

    // If admin force-bumped the catalog (e.g. plan/quota change) and the
    // forced_ts is newer than our local catalog version, run a full sync.
    final needsFullSync = lastSyncTs == 0 || serverVersion.forcedTs > localVersion;
    if (needsFullSync) {
      DebugLogger.log('SYNC', lastSyncTs == 0
          ? 'First sync — running full catalog sync'
          : 'Admin force-bump detected (forcedTs=${serverVersion.forcedTs} > local=$localVersion) — running full sync');
      final fullResult = await CatalogApi.syncFull();
      items = fullResult.items;
      await _persistItems(items);
      // Prune stale IDs after a full sync (BUG-STALE-IDS fix).
      if (fullResult.validTitleIds.isNotEmpty) {
        final pruned = await LocalDb.pruneStaleIds(fullResult.validTitleIds);
        if (pruned > 0) {
          DebugLogger.log('SYNC', 'Pruned $pruned stale title(s) from local DB');
        }
      }
    } else {
      items = await CatalogApi.syncDelta(localVersion);
      await _persistItems(items);
    }

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
          'remote_id': ep['remote_id'] as int? ?? 0,
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
