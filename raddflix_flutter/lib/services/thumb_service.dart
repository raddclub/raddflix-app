import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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

  /// Get thumbnail for a local video file.
  /// [timeMs] = position in milliseconds (default: 3000ms / 3 seconds).
  static Future<Uint8List?> getThumbnail(
    String videoPath, {
    int timeMs = 3000,
    int maxWidth = 240,
    int quality = 70,
  }) async {
    if (videoPath.isEmpty) return null;
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

      // Generate (G3: media_kit frame extraction — see extractor for why)
      final bytes = await MediaKitThumbnailExtractor.extractFrame(
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
