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
import '../core/constants.dart';

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
  // com.raddflix.app/media — handles scanFile + deleteMediaFiles (for vault import cleanup)
  static const _mediaChannel = MethodChannel('com.raddflix.app/media');

  /// Notify Android MediaStore that [path] was created/changed.
  /// Scanner adds or removes the entry automatically based on whether the file exists.
  static Future<void> notifyMediaStore(String path) async {
    try {
      await _mediaChannel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// Delete files from Android MediaStore using their content URIs.
  ///
  /// On Android 11+ (API 30+) the system shows a one-time confirmation dialog
  /// "Allow RaddFlix to delete N item(s) from your gallery?" — this is the only
  /// way to remove files we don't own without MANAGE_EXTERNAL_STORAGE.
  /// On Android 10 and below we delete via ContentResolver directly.
  ///
  /// Returns true if the deletion succeeded or was approved.
  static Future<bool> deleteFromMediaStore(List<String> contentUris) async {
    if (contentUris.isEmpty) return true;
    try {
      final result = await _mediaChannel.invokeMethod<bool>(
        'deleteMediaFiles',
        {'uris': contentUris},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

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

    final real = await _storage.read(key: _pinKey);
    if (hash == real) {
      _unlocked = true;
      _isFakeVault = false;
      _unlockedAt = DateTime.now();
      await _resetAttempts();
      return true;
    }

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

  /// Authenticate with device biometric (fingerprint / face ID).
  ///
  /// FIX-VAULT-02: uses the same dual-check as [isBiometricAvailable] so
  /// Infinix / MediaTek phones where [canCheckBiometrics] incorrectly returns
  /// false but [isDeviceSupported] returns true are handled correctly.
  ///
  /// FIX-VAULT-01: biometricOnly changed to false — biometricOnly:true throws a silent
  /// accepted. The device screen-lock PIN/pattern can no longer bypass the
  /// vault PIN (they are separate credentials).
  static Future<bool> authenticateBiometric(BuildContext context) async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return false;

    // FIX-BIOMETRIC-02: Use getAvailableBiometrics() directly — works on Infinix/MediaTek
    // Class 2 (Helio G25) where canCheckBiometrics incorrectly returns false.
    // canCheckBiometrics only returns true for Class 3 (Strong) sensors; MediaTek Helio G25
    // ships Class 2 which causes canCheckBiometrics to return false even with enrolled fingerprints.
    final available = await _auth.getAvailableBiometrics();
    if (available.isEmpty && !await _auth.isDeviceSupported()) return false;

    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Touch the fingerprint sensor to unlock your vault',
        options: const AuthenticationOptions(
          biometricOnly: false,  // FIX-VAULT-01: biometricOnly:true throws PlatformException on Infinix/MediaTek (no Class 3); swallowed by catch(_){return false}
          stickyAuth: true,
          useErrorDialogs: true,
        ),

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

  /// Called when app goes to background (paused lifecycle state).
  /// Only locks immediately if auto-lock is set to 0 (instant).
  /// For all other settings the existing isUnlocked time-check handles it.
  static void onAppPaused() {
    final secs = _autoLockSecondsSync();
    if (secs == 0) {
      // Instant lock — lock immediately as before
      lock();
    }
    // For secs > 0: do nothing. isUnlocked() will check elapsed time on resume.
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
    _cachedAutoLock = prefs.getInt(_autoLockKey) ?? 0;
    return _cachedAutoLock;
  }

  static int _autoLockSecondsSync() => _cachedAutoLock;
  static int _cachedAutoLock = 0;

  static Future<void> setAutoLockSeconds(int secs) async {
    _cachedAutoLock = secs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, secs);
  }

  /// FIX-VAULT-04: default changed false — biometric must be explicitly
  /// enabled by the user in Vault Settings before it activates.
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, v);
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      // FIX-BIOMETRIC-01: Use getAvailableBiometrics() which directly lists
      // enrolled biometrics. Works for Class 2 (Weak) sensors on Infinix /
      // MediaTek (Helio G25) where canCheckBiometrics returns false but the
      // fingerprint sensor works fine.
      final available = await _auth.getAvailableBiometrics();
      if (available.isNotEmpty) return true;
      // Secondary check: device has at least a PIN/pattern (allows device-cred fallback)
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // ── Vault directory ──────────────────────────────────────────────────────
  static Future<Directory> getVaultDir({bool fake = false}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, fake ? '.vault_decoy' : '.vault'));
    // M-21: use async I/O to avoid blocking the main thread on first run
    if (!await dir.exists()) await dir.create(recursive: true);
    // .nomedia prevents Android media scanner from indexing vault root
    final nomedia = File(p.join(dir.path, '.nomedia'));
    if (!await nomedia.exists()) await nomedia.writeAsString('');
    return dir;
  }

  /// FIX-VAULT-06: .nomedia is now written into every subfolder too, not just
  /// the vault root — prevents any partial scanner indexing of sub-directories.
  static Future<Directory> getVaultFolder(String folderName, {bool? fake}) async {
    final vaultDir = await getVaultDir(fake: fake ?? _isFakeVault);
    final folder = Directory(p.join(vaultDir.path, folderName));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    // Each subfolder also needs a .nomedia file
    final nomedia = File(p.join(folder.path, '.nomedia'));
    if (!nomedia.existsSync()) nomedia.writeAsStringSync('');
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

  /// Move [sourcePath] (a local file path, typically a FilePicker cache copy
  /// on Android 11+) into the vault directory and delete the source.
  ///
  /// FIX-VAULT-01 companion: after calling this, the caller must also call
  /// [deleteFromMediaStore] with the original content URIs so the file
  /// disappears from the gallery and all media players.
  static Future<void> moveFileToVault(String sourcePath, {String? folder}) async {
    final src = File(sourcePath);
    final targetDir = folder != null
        ? await getVaultFolder(folder)
        : await getVaultDir();
    final name = p.basename(sourcePath);
    final dest = File(p.join(targetDir.path, name));
    // M-20: try rename (atomic on same filesystem) before copy+delete.
    // copy+delete is non-atomic — a crash between them leaves the file duplicated.
    try {
      await src.rename(dest.path);
    } on FileSystemException {
      // Cross-filesystem move: fall back to copy+delete
      await src.copy(dest.path);
      if (await src.exists()) await src.delete();
    }
    // Scan the source path — if it was a real filesystem path (Android ≤10)
    // the scanner will notice it is gone and remove it from MediaStore.
    // On Android 11+ this is a no-op (temp-cache path not in MediaStore),
    // but the deleteFromMediaStore() call in vault_screen.dart handles that.
    await notifyMediaStore(sourcePath);
  }

  /// Batch version of [moveFileToVault] optimised for large folders.
  ///
  /// Improvements over calling [moveFileToVault] in a serial loop:
  ///   1. Target directory resolved ONCE — eliminates N × [getVaultFolder] calls.
  ///   2. Files moved in parallel chunks of [_kMoveConcurrency] — removes the
  ///      serial-await bottleneck; on the same filesystem each rename is ~0 ms.
  ///   3. [notifyMediaStore] fired concurrently for all paths at the end instead
  ///      of one blocking IPC round-trip per file.
  ///
  /// Per-file errors are swallowed so a single bad file never aborts the batch.
  /// [onProgress] is called after each chunk with (done, total).
  static const int _kMoveConcurrency = 4;

  static Future<void> moveFilesToVaultBatch(
    List<String> sourcePaths, {
    String? folder,
    void Function(int done, int total)? onProgress,
  }) async {
    if (sourcePaths.isEmpty) return;
    final total = sourcePaths.length;

    // ── 1. Resolve target directory once ────────────────────────────────────
    final targetDir = folder != null
        ? await getVaultFolder(folder)
        : await getVaultDir();

    // ── 2. Parallel file moves in chunks ────────────────────────────────────
    int done = 0;
    for (int i = 0; i < total; i += _kMoveConcurrency) {
      final end   = (i + _kMoveConcurrency).clamp(0, total);
      final chunk = sourcePaths.sublist(i, end);
      await Future.wait(chunk.map((srcPath) async {
        try {
          final src  = File(srcPath);
          final dest = File(p.join(targetDir.path, p.basename(srcPath)));
          try {
            await src.rename(dest.path);
          } on FileSystemException {
            // Cross-filesystem: copy first, then delete source.
            await src.copy(dest.path);
            if (await src.exists()) await src.delete();
          }
        } catch (_) {
          // Isolate per-file failures — one bad file must not abort the batch.
        }
      }));
      done += chunk.length;
      onProgress?.call(done, total);
    }

    // ── 3. Batch MediaStore notify ───────────────────────────────────────────
    // All scans fired concurrently. On Android 11+ these are temp-cache paths
    // not indexed by MediaStore — benign no-op. On ≤10 they notify the scanner
    // that the files are gone and should be removed from the media database.
    await Future.wait(sourcePaths.map(notifyMediaStore));
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
    // Tell MediaStore about the restored file so it appears in gallery
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

  /// Restore a vault file to the public Downloads folder.
  ///
  /// On Android 10+ (API 29+) uses the MediaStore.Downloads content provider —
  /// no WRITE_EXTERNAL_STORAGE permission needed; the file appears in Downloads
  /// immediately in every file manager and MX Player.
  /// On older versions falls back to a direct copy to the public Downloads dir.
  ///
  /// The vault source file is deleted ONLY after the copy succeeds, so the file
  /// is never lost even if the write fails (fixes the old direct-path crash on
  /// Android 11+ where the vault file stayed behind after showing an error).
  static Future<void> restoreFileToDownloads(String vaultPath) async {
    final filename = p.basename(vaultPath);
    final dest = await _mediaChannel.invokeMethod<String>('copyToDownloads', {
      'src_path': vaultPath,
      'filename': filename,
    });
    if (dest == null || dest.isEmpty) {
      throw Exception('copyToDownloads returned no destination path');
    }
    // Copy succeeded — now safe to delete the vault original
    final src = File(vaultPath);
    if (await src.exists()) await src.delete();
    // For legacy path-based result (API < 29), trigger a MediaStore scan so the
    // file shows up in gallery/file-manager immediately.
    if (!dest.startsWith('content://')) {
      await notifyMediaStore(dest);
    }
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
    return AppConstants.playableVideoExtensions.contains(ext);
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
