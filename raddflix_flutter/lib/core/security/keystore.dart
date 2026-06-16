import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants.dart';

/// Stores and retrieves JWT tokens and the SQLite encryption key
/// using Android Keystore (flutter_secure_storage with encryptedSharedPreferences).
/// Nothing sensitive is ever stored in plain SharedPreferences or SQLite.
class Keystore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ── SQLite Encryption Key (Task 4.2) ──────────────────────────────────────
  // Key name versioned — if we ever need to rotate, bump to _v2 and re-encrypt.
  static const _dbKeyName = 'raddflix_db_key_v1';

  /// Get the SQLite encryption key, generating it on first call.
  ///
  /// On first install: generates 32 cryptographically random bytes,
  /// encodes as URL-safe base64 (44 chars), stores in Android Keystore.
  /// On all subsequent calls: retrieves the stored key.
  ///
  /// The key is tied to this device and app install — uninstalling clears it,
  /// making the encrypted DB unreadable (data-at-rest protection).
  static Future<String> getOrCreateDbKey() async {
    final existing = await _storage.read(key: _dbKeyName);
    if (existing != null && existing.isNotEmpty) return existing;

    // Generate a cryptographically secure 32-byte random key
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Url.encode(bytes); // 44-char URL-safe base64
    await _storage.write(key: _dbKeyName, value: key);
    return key;
  }

  // ── Access Token ──────────────────────────────────────────────────────────

  static Future<String?> getAccessToken() =>
      _storage.read(key: StorageKeys.accessToken);

  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: StorageKeys.accessToken, value: token);

  // ── Refresh Token ─────────────────────────────────────────────────────────

  static Future<String?> getRefreshToken() =>
      _storage.read(key: StorageKeys.refreshToken);

  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: StorageKeys.refreshToken, value: token);

  // ── User ID ───────────────────────────────────────────────────────────────

  static Future<String?> getUserId() =>
      _storage.read(key: StorageKeys.userId);

  static Future<void> saveUserId(String userId) =>
      _storage.write(key: StorageKeys.userId, value: userId);

  // ── Device ID ─────────────────────────────────────────────────────────────

  static Future<String?> getDeviceId() =>
      _storage.read(key: StorageKeys.deviceId);

  static Future<void> saveDeviceId(String deviceId) =>
      _storage.write(key: StorageKeys.deviceId, value: deviceId);

  // ── Save full token pair at once ──────────────────────────────────────────

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
      saveUserId(userId),
    ]);
  }

  // ── Clear all on logout ───────────────────────────────────────────────────

  static Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: StorageKeys.accessToken),
      _storage.delete(key: StorageKeys.refreshToken),
      _storage.delete(key: StorageKeys.userId),
    ]);
    // Note: intentionally NOT clearing _dbKeyName on logout.
    // The DB key must persist so the encrypted catalog survives logout/re-login.
  }

  static Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
