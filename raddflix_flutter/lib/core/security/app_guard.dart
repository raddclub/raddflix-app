import 'dart:io';
import 'package:flutter/services.dart';
import 'security_telemetry.dart';

/// AppGuard — Multi-layer runtime security shield for RaddFlix.
///
/// Runs on every cold start (call AppGuard.initialize() in main() before runApp()).
/// Performs three checks in parallel:
///   1. APK signature integrity — cracked/repackaged APK has different cert
///   2. Frida dynamic instrumentation detection
///   3. Root detection (rooted phone)
///
/// Tamper response strategy (Silent Degradation):
///   - App does NOT crash or show error — that would alert the attacker
///   - [isTampered] = true
///   - ApiClient checks this flag and returns fake empty responses
///   - User sees blank catalog, all login attempts "fail" gracefully
///   - Attacker thinks the crack doesn't work and gives up
///
/// Why this matters:
///   - JazzDrive share_urls in delta.json NEVER expire (user confirmed)
///   - A cracked APK distributing those URLs freely would drain the service
///   - APK signature check stops 99% of cracked APK redistribution
///   - Frida detection stops runtime URL extraction via hooking
///
/// To activate signature enforcement:
///   1. Build a signed release APK
///   2. Run: keytool -printcert -jarfile app-release.apk
///   3. Copy the SHA-256 fingerprint (colon-separated hex)
///   4. Set _officialFingerprint to that value
///   5. Rebuild and deploy — enforcement is live
class AppGuard {
  /// True if any tamper check triggered. All API calls return fake data.
  static bool isTampered = false;

  /// True if the device is rooted. App continues but shows a warning once.
  static bool isRooted = false;

  static bool _initialized = false;

  /// Official RaddFlix release APK signing certificate SHA-256 fingerprint.
  /// Format: "AA:BB:CC:..." (colon-separated uppercase hex, 32 byte pairs)
  /// 
  /// PLACEHOLDER — enforcement is disabled until this is set to the real value.
  /// Run: keytool -printcert -jarfile app-release.apk  to get this.
  /// Then replace the placeholder and re-deploy.
  static const String _officialFingerprint =
      'RADDFLIX_CERT_SHA256_PLACEHOLDER';

  static const MethodChannel _channel =
      MethodChannel('com.raddflix.app/security');

  /// Run all security checks. Call once from main() before runApp().
  /// Never throws — all errors are silently caught.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await Future.wait([
      _checkSignature(),
      _checkFrida(),
      _checkRoot(),
    ]);
  }

  // ── Signature Check ────────────────────────────────────────────────────────

  /// Compare this APK's signing certificate against the official fingerprint.
  /// A cracked/re-signed APK has a different certificate → isTampered = true.
  static Future<void> _checkSignature() async {
    if (_officialFingerprint == 'RADDFLIX_CERT_SHA256_PLACEHOLDER') {
      // Enforcement not active yet — skip check
      return;
    }
    try {
      final fingerprint =
          await _channel.invokeMethod<String>('getSignatureFingerprint');
      if (fingerprint != null && fingerprint != _officialFingerprint) {
        isTampered = true;
        SecurityTelemetry.reportTamperAttempt('signature_mismatch');
      }
    } catch (_) {
      // Native channel unavailable (unit tests, emulator, etc.) — skip
    }
  }

  // ── Frida Detection ────────────────────────────────────────────────────────

  /// Detect Frida dynamic instrumentation framework.
  /// Frida is the primary tool attackers use to hook into apps and:
  ///   - Extract JazzDrive share_urls from memory
  ///   - Bypass subscription checks
  ///   - Dump SQLCipher decryption keys
  ///
  /// Detection methods:
  ///   1. Try to connect to Frida's default port (27042)
  ///   2. Check for Frida agent library in /proc/self/maps via native channel
  static Future<void> _checkFrida() async {
    // Method 1: Frida server default port
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        27042,
        timeout: const Duration(milliseconds: 400),
      );
      socket.destroy();
      // Connection succeeded → Frida server is running
      isTampered = true;
      SecurityTelemetry.reportTamperAttempt('frida_port');
      return;
    } catch (_) {
      // Connection refused = Frida not running = good
    }

    // Method 2: Native memory map scan
    try {
      final hasFrida =
          await _channel.invokeMethod<bool>('checkFrida') ?? false;
      if (hasFrida) {
        isTampered = true;
        SecurityTelemetry.reportTamperAttempt('frida_detected');
      }
    } catch (_) {}
  }

  // ── Root Detection ─────────────────────────────────────────────────────────

  /// Detect if device is rooted. Rooted devices make it easier to:
  ///   - Extract the SQLCipher AES key from Android Keystore
  ///   - Read app data with root file manager
  ///
  /// We set [isRooted] but do NOT set [isTampered] — many power users
  /// have legitimate rooted devices and we don't want to block them.
  static Future<void> _checkRoot() async {
    if (!Platform.isAndroid) return;
    try {
      const suPaths = [
        '/system/bin/su',
        '/system/xbin/su',
        '/sbin/su',
        '/data/local/su',
        '/data/local/bin/su',
        '/data/local/xbin/su',
      ];
      for (final path in suPaths) {
        if (await File(path).exists()) {
          isRooted = true;
          return;
        }
      }
    } catch (_) {}

    // Native check (detects Magisk hidden root)
    try {
      final nativeRoot =
          await _channel.invokeMethod<bool>('checkRoot') ?? false;
      if (nativeRoot) isRooted = true;
    } catch (_) {}
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether the app should serve real catalog data.
  /// Returns false if any tamper check triggered.
  static bool get shouldShowRealContent => !isTampered;

  /// Returns a safe device ID for API calls.
  /// If tampered, returns a fake-looking ID to confuse the attacker.
  static String safeDeviceId(String realDeviceId) {
    if (!isTampered) return realDeviceId;
    // Fake ID that looks plausible — attacker thinks the app "works"
    final fakeHash =
        realDeviceId.hashCode.abs().toRadixString(16).padLeft(12, '0');
    return 'FFFFFFF-FFF-FFF-FFF-$fakeHash';
  }
}
