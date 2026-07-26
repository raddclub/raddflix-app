import 'dart:io';
  import 'dart:typed_data';
  import 'package:flutter/services.dart';
  import 'package:path/path.dart' as p;
  import 'thumb_service.dart';
  import '../core/constants.dart';
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

    // Audio permission — checked independently for the Music tab.
    // On API < 33, READ_EXTERNAL_STORAGE covers audio too, so this mirrors
    // the video check. On API 33+, READ_MEDIA_AUDIO is a separate grant.
    static Future<bool> checkAudioPermission() async {
      try {
        final granted = await _channel.invokeMethod<bool>('checkAudioPermission');
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

        // await not allowed inside .map() — resolve all subtitle paths first.
        // Process in batches of 20 to avoid a parallel I/O storm on large libraries
        // (1000+ videos × 10 extension checks = 10,000+ simultaneous File.exists()
        // calls was freezing the UI event loop on budget MediaTek devices).
        final maps = raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        final subtitlePaths = <String?>[];
        for (int i = 0; i < maps.length; i += 20) {
          final end = (i + 20).clamp(0, maps.length);
          final batch = await Future.wait(
            maps.sublist(i, end).map((m) => _findSubtitlePath(m['file_path'] as String? ?? '')),
          );
          subtitlePaths.addAll(batch);
        }
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

    // ── Query all audio tracks from MediaStore (Music tab) ────────────────────
    // Returns tracks sorted by date descending. Skips tracks < 50 KB (the
    // Kotlin side already applies this filter, but double-check here too).
    // Does NOT run _fallbackScan for audio — MediaStore is reliable for music.
    static Future<List<LocalVideo>> queryAllAudio() async {
      try {
        final List<dynamic> raw =
            await _channel.invokeMethod<List<dynamic>>('queryAudio') ?? [];
        final maps = raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        final tracks = <LocalVideo>[];
        for (final m in maps) {
          final v = LocalVideo(
            id:             m['id'] as int? ?? 0,
            title:          (m['title'] as String? ?? '').isNotEmpty
                                ? m['title'] as String
                                : (m['display_name'] as String? ?? 'Unknown'),
            displayName:    m['display_name'] as String? ?? '',
            filePath:       m['file_path'] as String? ?? '',
            folderName:     m['folder_name'] as String? ?? 'Music',
            folderPath:     m['folder_path'] as String? ?? '',
            durationMs:     m['duration'] as int? ?? 0,
            sizeBytes:      m['size'] as int? ?? 0,
            width:          0,
            height:         0,
            dateModifiedMs: (m['date_modified'] as int? ?? 0) * 1000,
            mimeType:       m['mime_type'] as String?,
            artist:         (m['artist'] as String? ?? '').isNotEmpty ? m['artist'] as String : null,
            album:          (m['album'] as String? ?? '').isNotEmpty  ? m['album']  as String : null,
            albumId:        m['album_id'] as int?,
          );
          if (v.sizeBytes > 50 * 1024) tracks.add(v);
        }
        return tracks;
      } on PlatformException catch (_) {
        return [];
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
    static Future<Uint8List?> getThumbnail(String filePath, {int quality = 50, int maxDimension = 200}) {
      return ThumbService.getThumbnail(filePath, timeMs: 0, maxWidth: maxDimension, quality: quality);
    }

    // ── Album art from MediaStore.Audio.Albums ────────────────────────────────
    // Returns null when no embedded art is available — callers show a
    // music-note placeholder instead. Cached at the call site by album_id.
    static Future<Uint8List?> getAlbumArt(int albumId, {int size = 200}) async {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('getAlbumArt', {
          'album_id': albumId,
          'size': size,
        });
        return bytes;
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

      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (!AppConstants.playableVideoExtensions.contains(ext)) continue;
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
