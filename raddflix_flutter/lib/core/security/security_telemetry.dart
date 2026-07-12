import 'package:dio/dio.dart';
import '../app_container.dart';
import '../../providers/remote_values_provider.dart';
import '../security/device_id.dart';
import '../security/app_guard.dart';

/// SecurityTelemetry — silent best-effort tamper attempt reporter.
///
/// When AppGuard detects a cracked APK, Frida, or other tampering:
///   1. AppGuard sets isTampered = true (silent degradation)
///   2. SecurityTelemetry.reportTamperAttempt() fires ONCE in the background
///   3. A POST is made to /api/security/tamper-report on Oracle
///   4. Admin panel shows tamper events by device hash, reason, timestamp
///
/// Design principles:
///   - Silent: never shows UI, never delays app startup
///   - Best-effort: failure is silently swallowed (network, server down = ok)
///   - Privacy: only device_hash (opaque 8-char hex), never full device_id
///   - Single fire: _reported flag prevents duplicate reports per cold start
///   - No auth: attacker may not have a valid JWT — endpoint is open
class SecurityTelemetry {
  static bool _reported = false;

  /// Report a tamper event to Oracle. Call once per detection.
  ///
  /// [reason] — human-readable trigger: 'signature_mismatch', 'frida_detected',
  ///            'frida_port', 'root_detected'
  /// [deviceId] — optional, fetched from DeviceIdentifier if null
  static Future<void> reportTamperAttempt(String reason, {String? deviceId}) async {
    if (_reported) return;
    _reported = true;

    // Fire and forget — never await the result, never surface errors
    _sendReport(reason, deviceId: deviceId).ignore();
  }

  static Future<void> _sendReport(String reason, {String? deviceId}) async {
    try {
      final id = deviceId ?? await DeviceIdentifier.getDeviceId();
      // Obfuscate: send a short non-reversible hash, not the full device_id
      final idHash = id.hashCode.abs().toRadixString(16).padLeft(8, '0');

      // Use a fresh Dio with short timeout — no interceptors, no auth header
      // (The tampered app may not have a valid JWT, so we skip auth entirely)
      final dio = Dio(BaseOptions(
        baseUrl: appContainer.read(remoteValuesProvider).apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Content-Type': 'application/json'},
      ));

      await dio.post(
        '/api/security/tamper-report',
        data: {
          'device_hash': idHash,
          'reason':      reason,
          'timestamp':   DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'app_version': '1.0',     // bump when pubspec version changes
          'is_rooted':   AppGuard.isRooted,
        },
      );
    } catch (_) {
      // Silently discard all errors:
      //   - network unavailable (user is offline)
      //   - server down
      //   - endpoint not yet deployed on Oracle
      // None of these should affect the user experience.
    }
  }
}
