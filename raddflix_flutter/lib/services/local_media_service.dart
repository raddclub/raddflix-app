import 'dart:io';
  import 'dart:typed_data';
  import 'package:flutter/services.dart';
  import 'package:path/path.dart' as p;
  import 'package:video_thumbnail/video_thumbnail.dart';
  import '../models/local_video.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  class LocalMediaService {
    static const _channel = MethodChannel('com.raddflix.app/media_store');
    static const _seenKey = 'lm_seen_files';

    // ── Permission ─────────────────────────────────────────────────────────────
    static Future<bool> requestPermission() async {
      try {
        final granted = await _channel.invokeMethod<bool>('requestMediaPermission');
        return granted ?? false;
      } on PlatformException {
        return false;
      }
    }

    static Future<bool> checkPermission() async {
      try {
        final granted = await _channel.invokeMethod<bool>('checkMediaPermission');
        return granted ?? false;
      } on PlatformException {
        return false;
      }
    }

    // ── Query all videos from MediaStore ──────────────────────────────────────
    static Future<List<LocalVideo>> queryAllVideos() async {
      try {
        final List<dynamic> raw =
            await _channel.invokeMethod<List<dynamic>>('queryVideos') ?? [];

        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getStringList(_seenKey) ?? [];

        // await not allowed inside .map() — resolve all subtitle paths first
        final maps = raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        final subtitlePaths = await Future.wait(
          maps.map((m) => _findSubtitlePath(m['file_path'] as String? ?? '')),
        );
        final videos = <LocalVideo>[];
        for (int i = 0; i < maps.length; i++) {
          final m = maps[i];
          final v = LocalVideo(
            id:             m['id'] as int? ?? 0,
            title:          m['title'] as String? ?? '',
            displayName:    m['display_name'] as String? ?? '',
            filePath:       m['file_path'] as String? ?? '',
            folderName:     m['folder_name'] as String? ?? 'Videos',
            folderPath:     m['folder_path'] as String? ?? '',
            durationMs:     m['duration'] as int? ?? 0,
            sizeBytes:      m['size'] as int? ?? 0,
            width:          m['width'] as int? ?? 0,
            height:         m['height'] as int? ?? 0,
            dateModifiedMs: (m['date_modified'] as int? ?? 0) * 1000,
            mimeType:       m['mime_type'] as String?,
            subtitlePath:   subtitlePaths[i],
          );
          if (v.durationMs > 0 && v.sizeBytes > 50 * 1024) videos.add(v);
        }

        return videos;
      } on PlatformException catch (e) {
        // Fallback: scan filesystem directly (slower)
        return _fallbackScan();
      }
    }

    // ── Group videos into folders ─────────────────────────────────────────────
    static List<LocalFolder> groupByFolder(List<LocalVideo> videos) {
      final map = <String, List<LocalVideo>>{};
      for (final v in videos) {
        map.putIfAbsent(v.folderPath, () => []).add(v);
      }
      return map.entries.map((e) => LocalFolder(
        name: p.basename(e.key).isNotEmpty ? p.basename(e.key) : e.key,
        path: e.key,
        videos: e.value..sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs)),
      )).toList()
        ..sort((a, b) => b.videos.first.dateModifiedMs.compareTo(a.videos.first.dateModifiedMs));
    }

    // ── Native MediaStore thumbnail (fast — API 29+ reads pre-cached thumbs) ────
    static Future<Uint8List?> getThumbnailById(int mediaStoreId, {int size = 200}) async {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('getThumbnail', {
          'id': mediaStoreId,
          'size': size,
        });
        return bytes;
      } catch (_) {
        return null;
      }
    }

    // ── File-path thumbnail fallback (filesystem / "Open With" URIs) ──────────
    // Uses timeMs:0 (first frame) — safe for clips of any length.
    static Future<Uint8List?> getThumbnail(String filePath, {int quality = 50, int maxDimension = 200}) async {
      try {
        return await VideoThumbnail.thumbnailData(
          video: filePath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxDimension,
          quality: quality,
          timeMs: 0,
        );
      } catch (_) {
        return null;
      }
    }

    // ── Mark files as seen ────────────────────────────────────────────────────
    static Future<void> markSeen(List<String> paths) async {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_seenKey) ?? [];
      seen.addAll(paths);
      await prefs.setStringList(_seenKey, seen.toSet().toList());
    }

    static Future<Set<String>> getSeenPaths() async {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_seenKey) ?? []).toSet();
    }

    // ── Find subtitle file alongside video (checks .srt .ass .ssa .vtt .sub) ─────
    // M-22: async to avoid blocking main thread with existsSync() in a loop
    static Future<String?> _findSubtitlePath(String filePath) async {
      if (filePath.isEmpty) return null;
      final base = filePath.replaceAll(RegExp(r'\.[^.]+$'), '');
      const exts = ['srt', 'SRT', 'ass', 'ASS', 'ssa', 'SSA', 'vtt', 'VTT', 'sub', 'SUB'];
      for (final ext in exts) {
        final candidate = File('$base.$ext');
        if (await candidate.exists()) return candidate.path;
      }
      return null;
    }

    // ── Filesystem fallback scan ──────────────────────────────────────────────
    static Future<List<LocalVideo>> _fallbackScan() async {
      final dirs = [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Videos',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Download',
      ];
      final results = <LocalVideo>[];
      const videoExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.m4v', '.3gp', '.ts', '.webm'};

      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!videoExtensions.contains(ext)) continue;
          final stat = await entity.stat();
          final name = p.basenameWithoutExtension(entity.path);
          final folder = p.dirname(entity.path);
          results.add(LocalVideo(
            id: entity.path.hashCode,
            title: name,
            displayName: p.basename(entity.path),
            filePath: entity.path,
            folderName: p.basename(folder),
            folderPath: folder,
            durationMs: 0,
            sizeBytes: stat.size,
            width: 0,
            height: 0,
            dateModifiedMs: stat.modified.millisecondsSinceEpoch,
            subtitlePath: await _findSubtitlePath(entity.path),
          ));
        }
      }
      return results;
    }
  }
  