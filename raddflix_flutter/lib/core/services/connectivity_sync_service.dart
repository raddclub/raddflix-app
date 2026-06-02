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

    // Determine initial offline state (non-blocking)
    Connectivity().checkConnectivity().then((results) {
      _wasOffline = results.every((r) => r == ConnectivityResult.none);
      if (!_wasOffline) {
        // App started with internet — flush any leftovers from previous offline session
        _flush();
      }
    }).catchError((_) {});

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline && _wasOffline) {
        DebugLogger.log('CONNECTIVITY', 'Back online — flushing pending sync data');
        _flush();
      }
      _wasOffline = !isOnline;
    });
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
