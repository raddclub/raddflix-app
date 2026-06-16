import 'dart:convert';
import 'package:crypto/crypto.dart';

/// RequestEncoder — Custom XOR obfuscation layer for Oracle API traffic.
///
/// Adds a thin scrambling layer on top of HTTPS:
///   - Session key is derived hourly from device ID + timestamp
///   - App and Oracle server independently derive the same key
///   - Requests encoded with this key appear as garbled base64 to proxies
///   - Even if someone strips TLS (Burp Suite / Charles Proxy), they see junk
///
/// Status: [enabled] = false by default.
///   Server-side decode must be implemented in radd-hub BEFORE enabling.
///   See agent-hub/SECURITY_ARCHITECTURE.md for the server implementation spec.
///
/// Usage (once server is ready):
///   RequestEncoder.enabled = true;  // Set in AppConstants or RemoteConfig
///   final encoded = RequestEncoder.encode(requestBody, sessionKey);
///   final decoded = RequestEncoder.decode(responseBody, sessionKey);
///
/// Also provides share_url scrambling for local SQLite storage:
///   Even if SQLCipher is broken, the attacker sees XOR-scrambled URLs.
///   Prefix: "RF1:" identifies a scrambled URL vs plain legacy URL.
class RequestEncoder {
  /// Enable XOR encoding layer for all Oracle API calls.
  /// Server-side decode/encode is fully implemented in radd-hub/hub/request_encoding.py.
  /// Toggle via RemoteConfig if a hotfix requires temporarily disabling.
  static bool enabled = true;

  static const String _xorSeed = 'raddflix_xor_v1';

  // ── Session Key ────────────────────────────────────────────────────────────

  /// Generate a session key that changes every hour.
  /// Both the app and Oracle server derive the same key without communicating.
  ///
  /// Key formula: SHA-256( "raddflix_xor_v1" + ":" + deviceId + ":" + day + ":" + hour )
  ///   day  = UTC day-of-month (1–31)
  ///   hour = UTC hour (0–23)
  ///
  /// Key rotates every hour. Max replay window = 1 hour if someone captures it.
  static String generateSessionKey(String deviceId) {
    final now = DateTime.now().toUtc();
    final raw = '$_xorSeed:$deviceId:${now.day}:${now.hour}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  // ── Request / Response Encoding ────────────────────────────────────────────

  /// XOR-encode a JSON request body.
  /// Returns the original [jsonBody] unchanged if [enabled] is false.
  static String encode(String jsonBody, String sessionKey) {
    if (!enabled || jsonBody.isEmpty) return jsonBody;
    final bodyBytes = utf8.encode(jsonBody);
    final keyBytes = utf8.encode(sessionKey);
    final encoded = List<int>.generate(
      bodyBytes.length,
      (i) => bodyBytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return base64Url.encode(encoded);
  }

  /// XOR-decode a response from Oracle server.
  /// Returns the original [encodedBody] unchanged if [enabled] is false,
  /// or on any decoding failure (passthrough avoids crashes on bad data).
  static String decode(String encodedBody, String sessionKey) {
    if (!enabled || encodedBody.isEmpty) return encodedBody;
    try {
      // Server strips base64 padding (rstrip '='); Dart's base64Url.decode requires valid padding.
      // Re-add it before decoding to prevent FormatException that silently breaks all catalog syncs.
      final paddingLen = (4 - encodedBody.length % 4) % 4;
      final padded = encodedBody + ('=' * paddingLen);
      final encodedBytes = base64Url.decode(padded);
      final keyBytes = utf8.encode(sessionKey);
      final decoded = List<int>.generate(
        encodedBytes.length,
        (i) => encodedBytes[i] ^ keyBytes[i % keyBytes.length],
      );
      return utf8.decode(decoded);
    } catch (e) {
      // C-02: log decode failures so clock-skew / corrupt data is detectable
      assert(() { print('[XOR] decode failed: $e'); return true; }());
      return encodedBody;
    }
  }

  // ── share_url Scrambling (SQLite at-rest protection) ────────────────────────

  /// XOR-scramble a JazzDrive share_url before storing in SQLite.
  ///
  /// Why: JazzDrive share_urls NEVER expire (confirmed architecture).
  ///   Even if an attacker breaks SQLCipher encryption (requires root + time),
  ///   they still see scrambled URLs instead of working JazzDrive links.
  ///
  /// Scrambled format: "RF1:<base64url(xor(url, deviceId))>"
  /// Un-scrambled on demand in player before playback — stored scrambled always.
  static String scrambleUrl(String url, String deviceId) {
    if (url.isEmpty) return url;
    // Don't double-scramble
    if (url.startsWith('RF1:')) return url;
    final key = deviceId.isNotEmpty ? deviceId : _xorSeed;
    final urlBytes = utf8.encode(url);
    final keyBytes = utf8.encode(key);
    final scrambled = List<int>.generate(
      urlBytes.length,
      (i) => urlBytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return 'RF1:${base64Url.encode(scrambled)}';
  }

  /// Unscramble a share_url previously scrambled with [scrambleUrl].
  ///
  /// Returns the original [scrambled] string unchanged if:
  ///   - It doesn't start with "RF1:" (legacy plain URL — pass through)
  ///   - Decoding fails for any reason
  static String unscrambleUrl(String scrambled, String deviceId) {
    if (!scrambled.startsWith('RF1:')) {
      // Legacy or plain URL — return as-is for backward compatibility
      return scrambled;
    }
    try {
      final payload = scrambled.substring(4);
      final encodedBytes = base64Url.decode(payload);
      final key = deviceId.isNotEmpty ? deviceId : _xorSeed;
      final keyBytes = utf8.encode(key);
      final decoded = List<int>.generate(
        encodedBytes.length,
        (i) => encodedBytes[i] ^ keyBytes[i % keyBytes.length],
      );
      return utf8.decode(decoded);
    } catch (_) {
      // Decode failed — return scrambled as-is to avoid crash
      return scrambled;
    }
  }
}
