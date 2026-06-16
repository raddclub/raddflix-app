import '../api/api_client.dart';
import '../db/local_db.dart';
import '../debug/debug_logger.dart';

/// BUG-A08 / BUG-A19: Watch history API client.
///
/// Syncs local watch positions to the server so history is accessible
/// across devices. Previously no HistoryApi class existed — the server
/// endpoints at /api/history/* were completely unused by the Flutter app.
///
/// BUG-A11 note: server stores position_ms and duration_ms in milliseconds.
/// The watched_at field returned by GET /api/history is epoch SECONDS (not ms).
/// Always parse it as: DateTime.fromMillisecondsSinceEpoch(watchedAt * 1000).
class HistoryApi {
  /// POST /api/history/<fileId>
  /// Sends current position to server. Called on player exit.
  /// Fire-and-forget: errors are silently ignored (offline is normal).
  static Future<void> syncPosition({
    required String fileId,
    required int positionMs,
    required int durationMs,
  }) async {
    if (fileId.isEmpty || positionMs <= 0) return;
    try {
      await ApiClient.instance.post(
        '/api/history/$fileId',
        data: {
          'position_ms': positionMs,
          'duration_ms': durationMs,
        },
      );
      // Mark synced so flushUnsynced() skips it on next startup
      await LocalDb.markPositionSynced(fileId);
    } catch (_) {
      // Offline or auth error — synced=0 stays in local DB; flushUnsynced() retries on next startup.
    }
  }

  /// GET /api/history
  /// Returns the server-side watch history list.
  /// Each entry: {file_id, position_ms, duration_ms, watched_at (epoch seconds)}.
  /// Returns empty list on any error.
  static Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final resp = await ApiClient.instance.get('/api/history');
      final data = resp.data;
      if (data is Map && data['ok'] == true) {
        final list = data['history'];
        if (list is List) {
          return List<Map<String, dynamic>>.from(list);
        }
      }
    } catch (_) {}
    return [];
  }

  /// Parse watched_at from server response correctly.
  /// Server returns epoch SECONDS; DateTime needs milliseconds (BUG-A11).
  static DateTime watchedAtToDateTime(dynamic watchedAt) {
    // M-13: server may send int, double, or stringified number — cast-as-num? throws
    // if the type is String, so we use is-check + tryParse fallback.
    final secs = watchedAt == null
        ? 0
        : (watchedAt is num)
            ? watchedAt.toInt()
            : int.tryParse(watchedAt.toString()) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }

  // ── Offline-first sync ────────────────────────────────────────────────────

  /// Push all locally-saved positions not yet confirmed on the server (synced=0).
  /// Safe to call every app startup — idempotent. Guest/offline users fail gracefully.
  static Future<void> flushUnsynced() async {
    final pending = await LocalDb.getUnsyncedPositions();
    if (pending.isEmpty) return;
    DebugLogger.log('HISTORY', 'Flushing ${pending.length} unsynced position(s) to server');
    for (final row in pending) {
      final fileId     = row['file_id']     as String? ?? '';
      final positionMs = row['position_ms'] as int?    ?? 0;
      final durationMs = row['duration_ms'] as int?    ?? 0;
      if (fileId.isEmpty || positionMs <= 0) continue;
      await syncPosition(
          fileId: fileId, positionMs: positionMs, durationMs: durationMs);
    }
  }

  /// Pull watch history from the server and merge into local DB (newer wins).
  /// Enables cross-device 'Continue Watching': positions saved on another device
  /// appear locally after this call. Should be called when authenticated.
  static Future<void> mergeServerHistory() async {
    final serverHistory = await getHistory();
    if (serverHistory.isEmpty) return;
    DebugLogger.log('HISTORY', 'Merging ${serverHistory.length} server history entry/ies into local DB');
    for (final entry in serverHistory) {
      final fileId     = entry['file_id']     as String? ?? '';
      final positionMs = (entry['position_ms'] as num?)?.toInt() ?? 0;
      final durationMs = (entry['duration_ms'] as num?)?.toInt() ?? 0;
      final watchedAt  = (entry['watched_at']  as num?)?.toInt() ?? 0;
      if (fileId.isEmpty) continue;
      await LocalDb.upsertServerPosition(
        fileId:             fileId,
        positionMs:         positionMs,
        durationMs:         durationMs,
        watchedAtEpochSecs: watchedAt,
      );
    }
  }
}
