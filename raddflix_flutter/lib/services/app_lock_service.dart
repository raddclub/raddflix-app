/// App-level PIN / biometric lock service.
///
/// Completely independent from [VaultService] — the vault PIN and the app-lock
/// PIN are stored under different keys with different salts. A user can have
/// both, one, or neither.
///
/// Lifecycle integration (called from _AppLockGuard in app.dart):
///   • [onAppPaused]   — call when AppLifecycleState.paused fires
///   • [onAppResumed]  — call when AppLifecycleState.resumed fires;
///                       returns true if the lock screen should be shown
///
/// FLAG_SECURE is applied via [setFlagSecure], which goes through the existing
/// com.raddflix.app/security MethodChannel.  Call it from the settings screen
/// when the user enables or disables app lock (not from this service directly,
/// so the service stays platform-agnostic for tests).
library app_lock_service;

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class AppLockService {
  AppLockService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const _pinKey       = 'app_lock_pin_hash';
  static const _pinLengthKey = 'app_lock_pin_length';
  static const _biometricKey = 'app_lock_biometric_enabled';
  static const _timeoutKey   = 'app_lock_timeout_seconds';

  /// Reuse the existing security channel — avoids opening a second channel.
  static const _securityChannel = MethodChannel('com.raddflix.app/security');

  static final _auth = LocalAuthentication();

  // ── In-memory state ──────────────────────────────────────────────────────
  static bool      _isLocked     = false;
  static DateTime? _pausedAt;
  /// Cached so [onAppResumed] / [onAppPaused] never block on SharedPreferences.
  static int       _cachedTimeout = 0; // 0 = immediately, -1 = never

  // ── PIN hashing ──────────────────────────────────────────────────────────
  static String _hashPin(String pin) {
    final bytes = utf8.encode('raddflix_app_lock_salt_$pin');
    return sha256.convert(bytes).toString();
  }

  // ── Setup ────────────────────────────────────────────────────────────────
  static Future<bool> hasPin() async {
    final h = await _storage.read(key: _pinKey);
    return h != null && h.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    if (pin.length < 4) throw ArgumentError('PIN must be at least 4 digits');
    await _storage.write(key: _pinKey, value: _hashPin(pin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pinLengthKey, pin.length);
    // Do NOT lock after setup — the user just configured it in this session.
    _isLocked = false;
  }

  static Future<int> getPinLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pinLengthKey) ?? 4;
  }

  static Future<bool> checkPin(String pin) async {
    final hash   = _hashPin(pin);
    final stored = await _storage.read(key: _pinKey);
    return stored != null && hash == stored;
  }

  static Future<void> removePin() async {
    await _storage.delete(key: _pinKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinLengthKey);
    _isLocked = false;
    _pausedAt  = null;
  }

  // ── Auth ─────────────────────────────────────────────────────────────────
  static bool get isLocked => _isLocked;

  static void lock() {
    _isLocked = true;
    _pausedAt  = null;
  }

  static void unlock() {
    _isLocked = false;
    _pausedAt  = null;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  /// Called when AppLifecycleState.paused fires.
  static void onAppPaused() {
    _pausedAt = DateTime.now();
    if (_cachedTimeout == 0) {
      // Lock immediately — show lock screen as soon as the app resumes.
      _isLocked = true;
    }
    // timeout > 0: elapsed-time check in onAppResumed handles it.
    // timeout == -1: never auto-lock.
  }

  /// Called when AppLifecycleState.resumed fires.
  /// Returns true if the app should show the lock screen now.
  static bool onAppResumed() {
    if (_isLocked) return true;

    final timeout = _cachedTimeout;
    if (timeout == -1) return false; // "Never" — don't auto-lock

    if (timeout == 0) {
      // Already locked in onAppPaused; _isLocked is already true.
      return _isLocked;
    }

    // Time-based: lock if enough time elapsed since background.
    if (_pausedAt == null) return false;
    final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
    if (elapsed >= timeout) {
      _isLocked = true;
      _pausedAt  = null;
      return true;
    }
    return false;
  }

  // ── Settings ─────────────────────────────────────────────────────────────
  /// timeout == 0  → lock immediately when app goes to background
  /// timeout == -1 → never auto-lock (stays unlocked for the whole session)
  /// timeout > 0   → lock after N seconds in background
  static Future<int> getAutoLockTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedTimeout = prefs.getInt(_timeoutKey) ?? 0;
    return _cachedTimeout;
  }

  static Future<void> setAutoLockTimeout(int seconds) async {
    _cachedTimeout = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, seconds);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, v);
  }

  /// FIX-BIOMETRIC-01 pattern: getAvailableBiometrics() works on Class 2
  /// (Weak) sensors (Infinix / MediaTek Helio) where canCheckBiometrics
  /// incorrectly returns false. Mirrors VaultService.isBiometricAvailable().
  static Future<bool> isBiometricAvailable() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      if (available.isNotEmpty) return true;
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Authenticate with device biometric / device credential.
  /// On success: calls [unlock] and returns true.
  static Future<bool> authenticateBiometric() async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return false;

    final available = await _auth.getAvailableBiometrics();
    if (available.isEmpty && !await _auth.isDeviceSupported()) return false;

    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Touch the fingerprint sensor to unlock RaddFlix',
        options: const AuthenticationOptions(
          biometricOnly: false, // false avoids PlatformException on Class 2 sensors
          stickyAuth:    true,
          useErrorDialogs: true,
        ),
      );
      if (ok) unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ── FLAG_SECURE via native SECURITY_CHANNEL ───────────────────────────────
  /// Adds (or clears) WindowManager.FLAG_SECURE so app content is hidden in
  /// the recents thumbnail and screenshots are blocked while the lock is active.
  /// Call from the settings screen when enabling/disabling — not from this service
  /// (keeps the service testable without platform channels).
  static Future<void> setFlagSecure(bool enabled) async {
    try {
      await _securityChannel.invokeMethod('setFlagSecure', {'enabled': enabled});
    } catch (_) {}
  }

  // ── Cache warmer ──────────────────────────────────────────────────────────
  /// Populate [_cachedTimeout] from SharedPreferences before the first
  /// lifecycle event fires.  Called once from [_AppLockGuard._init].
  static Future<void> warmCache() => getAutoLockTimeout();
}
