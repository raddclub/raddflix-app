import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class VaultService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const int minPinLength = 4;
  static const int maxPinLength = 6;

  static const _pinKey       = 'vault_pin_hash';
  static const _fakePinKey   = 'vault_fake_pin_hash';
  static const _autoLockKey  = 'vault_auto_lock_seconds';
  static const _biometricKey = 'vault_biometric_enabled';
  static const _attemptsKey  = 'vault_failed_attempts';
  static const _lockUntilKey  = 'vault_locked_until';
  static const _pinLengthKey  = 'vault_pin_length';

  static final _auth = LocalAuthentication();
  static const _mediaChannel = MethodChannel('com.raddflix.app/media');

  /// Notify Android MediaStore about [path] (deletion or new file).
  /// Call after deleting a file — scanner notices it's gone and removes it from gallery index.
  /// Call after restoring/creating a file — scanner adds it to gallery.
  static Future<void> notifyMediaStore(String path) async {
    try {
      await _mediaChannel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }
  // Keep private alias for internal use
  static Future<void> _removefromMediaStore(String path) => notifyMediaStore(path);
  static bool _unlocked = false;
  static DateTime? _unlockedAt;
  static bool _isFakeVault = false;

  // ── PIN hashing ──────────────────────────────────────────────────────────
  static String _hashPin(String pin) {
    final bytes = utf8.encode('raddflix_vault_salt_$pin');
    return sha256.convert(bytes).toString();
  }

  // ── Setup ────────────────────────────────────────────────────────────────
  static Future<bool> hasPin() async {
    final h = await _storage.read(key: _pinKey);
    return h != null && h.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    if (pin.length < minPinLength) throw ArgumentError('PIN must be at least $minPinLength digits');
    if (pin.length > maxPinLength) throw ArgumentError('PIN must be at most $maxPinLength digits');
    await _storage.write(key: _pinKey, value: _hashPin(pin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pinLengthKey, pin.length);
  }

  static Future<void> setFakePin(String pin) async {
    if (pin.isEmpty) {
      await _storage.delete(key: _fakePinKey);
    } else {
      if (pin.length < minPinLength) throw ArgumentError('Decoy PIN must be at least $minPinLength digits');
      if (pin.length > maxPinLength) throw ArgumentError('Decoy PIN must be at most $maxPinLength digits');
      await _storage.write(key: _fakePinKey, value: _hashPin(pin));
    }
  }

  static Future<int> getPinLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pinLengthKey) ?? 6;
  }

  static Future<bool> hasFakePin() async {
    final h = await _storage.read(key: _fakePinKey);
    return h != null && h.isNotEmpty;
  }

  // ── Auth ─────────────────────────────────────────────────────────────────
  static Future<bool> checkPin(String pin) async {
    await _checkLockout();
    final hash = _hashPin(pin);

    // Real PIN
    final real = await _storage.read(key: _pinKey);
    if (hash == real) {
      _unlocked = true;
      _isFakeVault = false;
      _unlockedAt = DateTime.now();
      await _resetAttempts();
      return true;
    }

    // Fake PIN
    final fake = await _storage.read(key: _fakePinKey);
    if (fake != null && hash == fake) {
      _unlocked = true;
      _isFakeVault = true;
      _unlockedAt = DateTime.now();
      await _resetAttempts();
      return true;
    }

    await _recordFailedAttempt();
    return false;
  }

  static Future<bool> authenticateBiometric(BuildContext context) async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return false;
    final available = await _auth.canCheckBiometrics;
    if (!available) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your private vault',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok) {
        _unlocked = true;
        _isFakeVault = false;
        _unlockedAt = DateTime.now();
        await _resetAttempts();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static bool get isUnlocked {
    if (!_unlocked) return false;
    // Check auto-lock
    final secs = _autoLockSecondsSync();
    if (secs > 0 && _unlockedAt != null) {
      if (DateTime.now().difference(_unlockedAt!).inSeconds >= secs) {
        lock();
        return false;
      }
    }
    return true;
  }

  static bool get isFakeVault => _isFakeVault;

  static void lock() {
    _unlocked = false;
    _unlockedAt = null;
  }

  static void refreshUnlockTime() {
    if (_unlocked) _unlockedAt = DateTime.now();
  }

  // ── Lockout after failed attempts ────────────────────────────────────────
  static Future<void> _recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
    await prefs.setInt(_attemptsKey, attempts);
    if (attempts >= 5) {
      final lockUntil = DateTime.now().add(Duration(minutes: attempts - 3));
      await prefs.setInt(_lockUntilKey, lockUntil.millisecondsSinceEpoch);
    }
  }

  static Future<void> _resetAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptsKey);
    await prefs.remove(_lockUntilKey);
  }

  static Future<({int attempts, DateTime? lockedUntil})> getLockoutInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt(_attemptsKey) ?? 0;
    final until = prefs.getInt(_lockUntilKey);
    return (
      attempts: attempts,
      lockedUntil: until != null ? DateTime.fromMillisecondsSinceEpoch(until) : null,
    );
  }

  static Future<void> _checkLockout() async {
    final info = await getLockoutInfo();
    if (info.lockedUntil != null && DateTime.now().isBefore(info.lockedUntil!)) {
      throw VaultLockedException(info.lockedUntil!);
    }
  }

  // ── Settings ─────────────────────────────────────────────────────────────
  static Future<int> getAutoLockSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedAutoLock = prefs.getInt(_autoLockKey) ?? 0; // keep sync cache up to date
    return _cachedAutoLock;
  }

  static int _autoLockSecondsSync() {
    // Read sync — call after first async load
    return _cachedAutoLock;
  }
  static int _cachedAutoLock = 0;

  static Future<void> setAutoLockSeconds(int secs) async {
    _cachedAutoLock = secs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, secs);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? true;
  }

  static Future<void> setBiometricEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, v);
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      if (await _auth.canCheckBiometrics) return true;
      // Fallback for devices (e.g. Infinix) where canCheckBiometrics
      // returns false even with enrolled fingerprints
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // ── Vault directory ──────────────────────────────────────────────────────
  static Future<Directory> getVaultDir({bool fake = false}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, fake ? '.vault_decoy' : '.vault'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // .nomedia prevents Android media scanner from indexing
    final nomedia = File(p.join(dir.path, '.nomedia'));
    if (!nomedia.existsSync()) nomedia.writeAsStringSync('');
    return dir;
  }

  static Future<Directory> getVaultFolder(String folderName, {bool? fake}) async {
    final vaultDir = await getVaultDir(fake: fake ?? _isFakeVault);
    final folder = Directory(p.join(vaultDir.path, folderName));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  // ── File operations ──────────────────────────────────────────────────────
  static Future<List<VaultFile>> listFiles({String? folder}) async {
    final vaultDir = await getVaultDir(fake: _isFakeVault);
    final scanDir = folder != null
        ? Directory(p.join(vaultDir.path, folder))
        : vaultDir;
    if (!scanDir.existsSync()) return [];

    final results = <VaultFile>[];
    await for (final entity in scanDir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        final count = entity.listSync().where((f) => !p.basename(f.path).startsWith('.')).length;
        results.add(VaultFile(
          name: name, path: entity.path, isFolder: true,
          fileCount: count, size: 0,
          modified: entity.statSync().modified,
        ));
      } else if (entity is File) {
        final stat = entity.statSync();
        results.add(VaultFile(
          name: name, path: entity.path, isFolder: false,
          size: stat.size, modified: stat.modified,
        ));
      }
    }
    results.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results;
  }

  static Future<void> moveFileToVault(String sourcePath, {String? folder}) async {
    final src = File(sourcePath);
    final targetDir = folder != null
        ? await getVaultFolder(folder)
        : await getVaultDir();
    final name = p.basename(sourcePath);
    final dest = File(p.join(targetDir.path, name));
    await src.copy(dest.path);
    await src.delete();
    // Tell Android MediaStore the source file is gone so it disappears from gallery/other apps
    await _removefromMediaStore(sourcePath);
  }

  static Future<void> importFileBytes(Uint8List bytes, String name, {String? folder}) async {
    final targetDir = folder != null
        ? await getVaultFolder(folder)
        : await getVaultDir();
    final dest = File(p.join(targetDir.path, name));
    await dest.writeAsBytes(bytes);
  }

  static Future<void> restoreFile(String vaultPath, String destDir) async {
    final src = File(vaultPath);
    final dest = File(p.join(destDir, p.basename(vaultPath)));
    await src.copy(dest.path);
    await src.delete();
    // Tell Android MediaStore about the newly restored file so it appears in gallery
    await notifyMediaStore(dest.path);
  }

  static Future<void> deleteVaultFile(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  static Future<void> createFolder(String name) async {
    await getVaultFolder(name);
  }

  static Future<void> renameFile(String path, String newName) async {
    final f = File(path);
    final newPath = p.join(p.dirname(path), newName);
    await f.rename(newPath);
  }

  static Future<int> totalVaultSize() async {
    final dir = await getVaultDir();
    int total = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) total += f.statSync().size;
    }
    return total;
  }

  static Future<void> changePin(String oldPin, String newPin) async {
    final ok = await checkPin(oldPin);
    if (!ok) throw Exception('Incorrect current PIN');
    await setPin(newPin);
  }

  static Future<void> clearVault() async {
    final dir = await getVaultDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create();
    final nomedia = File(p.join(dir.path, '.nomedia'));
    nomedia.writeAsStringSync('');
  }
}

class VaultFile {
  final String name;
  final String path;
  final bool isFolder;
  final int size;
  final int fileCount;
  final DateTime modified;

  VaultFile({
    required this.name,
    required this.path,
    required this.isFolder,
    required this.size,
    this.fileCount = 0,
    required this.modified,
  });

  String get displaySize {
    if (isFolder) return '$fileCount items';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  bool get isVideo {
    final ext = name.split('.').last.toLowerCase();
    return ['mp4','mkv','avi','mov','ts','m2ts','wmv','flv','webm','3gp'].contains(ext);
  }

  IconData get icon {
    if (isFolder) return Icons.folder_rounded;
    if (isVideo) return Icons.video_file_rounded;
    final ext = name.split('.').last.toLowerCase();
    if (['jpg','jpeg','png','webp','gif'].contains(ext)) return Icons.image_rounded;
    if (['mp3','aac','flac','ogg','wav'].contains(ext)) return Icons.audio_file_rounded;
    return Icons.insert_drive_file_rounded;
  }
}

class VaultLockedException implements Exception {
  final DateTime until;
  VaultLockedException(this.until);
  String get message {
    final remaining = until.difference(DateTime.now());
    if (remaining.inSeconds <= 0) return '';
    if (remaining.inMinutes < 1) return 'Try again in ${remaining.inSeconds}s';
    return 'Try again in ${remaining.inMinutes}m';
  }
}
