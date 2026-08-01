import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'media_kit_thumbnail_extractor.dart';

/// Generates and disk-caches video thumbnails for local files.
class ThumbService {
  ThumbService._();
  static final _mem = <String, Uint8List>{};
  static const int _maxMemEntries = 100; // H-10: cap in-memory thumbnail cache
  static Directory? _cacheDir;

  // 0C THUMB-PERF: Fast path via MediaMetadataRetriever in MediaStorePlugin.kt.
  // MMR uses Android's built-in video codec — ~50–200 ms per frame vs the
  // 1.5–4 s cost of spawning a full libmpv Player in MediaKitThumbnailExtractor.
  // Only available on Android; returns null on failure so caller falls back.
  static const _mediaStoreChannel = MethodChannel('com.raddflix.app/media_store');

  static Future<Uint8List?> _getFrameAtTimeFast(
    String path, {
    required int timeMs,
    required int maxWidth,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _mediaStoreChannel.invokeMethod<Uint8List>('getFrameAtTime', {
        'path': path,
        'time_ms': timeMs,
        'max_width': maxWidth,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _getDir() async {
    _cacheDir ??= Directory(
        p.join((await getApplicationDocumentsDirectory()).path, '.thumbs'));
    if (!_cacheDir!.existsSync()) _cacheDir!.createSync(recursive: true);
    return _cacheDir!;
  }

  static String _key(String videoPath, int timeMs) {
    final hash = md5.convert(utf8.encode('$videoPath:$timeMs')).toString();
    return hash;
  }

  // ── 0C Fix 0C-4: disk cache size / age limit ─────────────────────────────
  // Runs at most once per process lifetime (fire-and-forget). Keeps the cache
  // under 200 MB and removes files older than 30 days.
  static bool _evictChecked = false;

  static void _scheduleEviction() {
    if (_evictChecked) return;
    _evictChecked = true;
    unawaited(_evictDiskCache());
  }

  static Future<void> _evictDiskCache() async {
    try {
      final dir = await _getDir();
      final entries = dir.listSync().whereType<File>().toList();
      final now = DateTime.now();
      const maxAgeDays  = 30;
      const maxBytes    = 200 * 1024 * 1024; // 200 MB hard limit
      const targetBytes = 150 * 1024 * 1024; // 150 MB trim target

      // Pass 1 — delete files older than maxAgeDays.
      final alive = <File>[];
      for (final f in entries) {
        try {
          if (now.difference(f.statSync().modified).inDays >= maxAgeDays) {
            await f.delete();
          } else {
            alive.add(f);
          }
        } catch (_) { alive.add(f); }
      }

      // Pass 2 — if still over size limit, remove oldest-first.
      int total = 0;
      for (final f in alive) {
        try { total += f.lengthSync(); } catch (_) {}
      }
      if (total > maxBytes) {
        alive.sort((a, b) {
          try {
            return a.statSync().modified.compareTo(b.statSync().modified);
          } catch (_) { return 0; }
        });
        for (final f in alive) {
          if (total <= targetBytes) break;
          try {
            final size = f.lengthSync();
            await f.delete();
            total -= size;
          } catch (_) {}
        }
      }
    } catch (_) {} // never crash the app for a cache cleanup
  }
  // ─────────────────────────────────────────────────────────────────────────

  /// Get thumbnail for a local video file.
  /// [timeMs] = position in milliseconds (default: 3000ms / 3 seconds).
  static Future<Uint8List?> getThumbnail(
    String videoPath, {
    int timeMs = 3000,
    int maxWidth = 240,
    int quality = 70,
  }) async {
    if (videoPath.isEmpty) return null;
    // Kick off disk cache eviction once per session (non-blocking).
    _scheduleEviction();
    final key = _key(videoPath, timeMs);

    // Memory cache
    if (_mem.containsKey(key)) return _mem[key];

    // Disk cache
    try {
      final dir = await _getDir();
      final file = File(p.join(dir.path, '$key.jpg'));
      if (file.existsSync()) {
        final bytes = await file.readAsBytes(); // H-10: async — was blocking main thread
        // H-10: evict oldest entries if cache is at capacity
        if (_mem.length >= _maxMemEntries) _mem.remove(_mem.keys.first);
        _mem[key] = bytes;
        return bytes;
      }

      // 0C THUMB-PERF: try fast path (MediaMetadataRetriever, ~50–200 ms)
      // before the slow MediaKit path (full libmpv Player, 1.5–4 s).
      var bytes = await _getFrameAtTimeFast(
        videoPath, timeMs: timeMs, maxWidth: maxWidth);

      // Slow fallback: MediaKit frame extraction (G3 — needed for formats
      // that Android's built-in decoders don't handle, e.g. some MKV/H.265
      // content on API 28 devices).
      bytes ??= await MediaKitThumbnailExtractor.extractFrame(
        videoPath,
        timeMs: timeMs,
      );

      if (bytes != null) {
        await file.writeAsBytes(bytes); // H-10: async — was blocking main thread
        if (_mem.length >= _maxMemEntries) _mem.remove(_mem.keys.first);
        _mem[key] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Preheat thumbnails for a list of local video paths in background.
  static void preheat(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty) {
        Future(() => getThumbnail(path, timeMs: 3000));
      }
    }
  }

  static void clearMemCache() => _mem.clear();
}
