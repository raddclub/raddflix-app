import 'package:workmanager/workmanager.dart';
import '../db/sync_service.dart';
import '../services/usage_service.dart';
import '../debug/debug_logger.dart';

// ── Background task entry point ───────────────────────────────────────────────
// MUST be a top-level function (not a class method).
// WorkManager calls this in a separate Dart isolate — no Flutter UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      DebugLogger.log('BG_SYNC', 'Background task started: $task');
      final result = await SyncService.sync();
      // Also refresh quota so subscription/plan changes propagate immediately
      await UsageService.fetchQuota();
      DebugLogger.log('BG_SYNC',
          'Background sync done: ${result.itemsSynced} items — ${result.message}');
      return true;
    } catch (e, st) {
      DebugLogger.logError('BG_SYNC', 'Background sync failed', e, st);
      return false; // WorkManager will retry with exponential backoff
    }
  });
}

/// Background sync service — catalog delta + quota refresh every 6 hours,
/// even when the app is fully closed.
///
/// Sync trigger matrix:
///   1. Every 6 h  — WorkManager periodic task (app closed / background)
///   2. App resume — CatalogNotifier WidgetsBindingObserver (min 5-min gap)
///   3. Every 15 min — foreground poll timer while app is open
///   4. Reconnect  — ConnectivitySyncService (internet restored)
class BackgroundSyncService {
  static const _taskName   = 'raddflix.catalog_sync';
  static const _taskUnique = 'raddflix_catalog_periodic';

  /// Register the 6-hour periodic background sync with WorkManager.
  /// Safe to call on every cold start — ExistingWorkPolicy.keep is a no-op
  /// if the task is already queued, so the 6-hour window is not reset.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      _taskUnique,
      _taskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 30),
    );

    DebugLogger.log('BG_SYNC', 'Periodic background sync registered (every 6h)');
  }
}
