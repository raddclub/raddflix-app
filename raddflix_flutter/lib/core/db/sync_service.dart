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
      DebugLogger.logError('SYNC', 'Catalog sync failed', e);
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
          ? 'First run — starting full catalog download'
          : 'Server update detected — running full sync');
      // B7: retry up to 3× on transient failure before propagating the error
      final fullResult = await _withRetry(() => CatalogApi.syncFull());
      items = fullResult.items;
      await _persistItems(items);
      // M-17: write timestamps BEFORE the optional prune step so they are
      // committed even if prune throws — prevents a repeated full sync on next
      // launch due to missing timestamp when prune rarely fails.
      final nowTs1 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await LocalDb.setLastSyncVersion(serverVersion.version);
      await LocalDb.setLastSyncTimestamp(nowTs1);
      // Prune stale IDs after a full sync (BUG-STALE-IDS fix).
      if (fullResult.validTitleIds.isNotEmpty) {
        final pruned = await LocalDb.pruneStaleIds(fullResult.validTitleIds);
        if (pruned > 0) {
          DebugLogger.log('SYNC', 'Pruned $pruned stale title(s) from local DB');
        }
      }
    } else {
      items = await _withRetry(() => CatalogApi.syncDelta(localVersion)); // B7
      await _persistItems(items);
      // M-17: write timestamps immediately after persist (delta sync)
      final nowTs2 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await LocalDb.setLastSyncVersion(serverVersion.version);
      await LocalDb.setLastSyncTimestamp(nowTs2);
    }

    DebugLogger.log('SYNC', 'Catalog sync complete: ${items.length} item(s)');
    unawaited(JazzDriveService.warmTopFreeItems(8));
    return SyncResult(
      success: true,
      itemsSynced: items.length,
      message: 'Synced ${items.length} item(s) from server',
      isUpToDate: false,
    );
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// B4: Delegate to [LocalDb.persistBatch] which wraps the entire list in a
  /// single SQLite transaction. Either all titles + episodes commit, or none do —
  /// DB is never left in a partial state after power loss or process kill.
  /// M-17 timestamps are written AFTER this returns, so a thrown exception here
  /// causes the next app open to retry the full sync automatically (self-healing).
  static Future<void> _persistItems(List<CatalogItem> items) async {
    if (items.isEmpty) return;
    await LocalDb.persistBatch(items);
  }

  // ── B7: Retry helper ────────────────────────────────────────────────────────

  /// Simple exponential back-off retry for transient network failures.
  /// On Pakistani mobile networks (frequent handoff, variable signal) a single
  /// timeout would silently abort the entire catalog sync with no recovery until
  /// the user manually reopens the app.
  static Future<T> _withRetry<T>(Future<T> Function() fn,
      {int attempts = 3}) async {
    for (int i = 0; i < attempts; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i == attempts - 1) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw StateError('unreachable');
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
