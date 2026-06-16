import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api/history_api.dart';
import '../debug/debug_logger.dart';
import 'usage_service.dart';

/// Listens for network connectivity changes and flushes pending sync data
/// the moment the device comes back online.
///
/// Why needed:
///   - HistoryApi.flushUnsynced() runs on cold start (main.dart)
///   - But if the user never cold-starts after going offline, positions
///     stay unsynced indefinitely.
///   - This service bridges that gap: whenever connectivity changes from
///     none → any, it immediately flushes pending history positions and
///     usage bytes without waiting for the next app restart.
///
/// Usage:
///   Call ConnectivitySyncService.start() once from main() after runApp().
///   The subscription lives for the app's lifetime — no need to stop it.
class ConnectivitySyncService {
  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static bool _wasOffline = false;

  /// Start listening for connectivity changes.
  /// Idempotent — safe to call multiple times (only one listener created).
  static void start() {
    if (_sub != null) return;

    // BUG-F13 fix: pessimistic default — assume offline until probe confirms otherwise.
    // If listener fires before checkConnectivity().then() resolves, _stateSettled
    // prevents .then() from overwriting the value the listener already set.
    // L-13: _stateSettled is local to this call — since start() is idempotent
    // (returns early if _sub != null), this closure is only created once.
    bool _stateSettled = false;
    _wasOffline = true;

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      _stateSettled = true;
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline && _wasOffline) {
        DebugLogger.log('CONNECTIVITY', 'Back online — flushing pending sync data');
        _flush();
      }
      _wasOffline = !isOnline;
    });

    // Probe current state — but only apply if listener hasn't already settled state
    Connectivity().checkConnectivity().then((results) {
      if (_stateSettled) return;  // listener already set authoritative state — skip
      _wasOffline = results.every((r) => r == ConnectivityResult.none);
      if (!_wasOffline) {
        // Started with internet — flush leftovers from previous offline session
        _flush();
      }
    }).catchError((_) {});
  }

  static void _flush() {
    HistoryApi.flushUnsynced().ignore();
    UsageService.flushPending().ignore();
  }

  /// Stop the connectivity listener (call on app dispose if needed).
  static void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
