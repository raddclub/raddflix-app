import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';

/// A single cast member, as fetched from TMDB and cached locally.
class CastMember {
  final int    personId;
  final String name;
  final String? character;
  final int    orderIdx;
  final String? profileUrl;    // TMDB CDN URL (w185)
  final String? profileLocal;  // Absolute path in internal storage (invisible to file manager)

  const CastMember({
    required this.personId,
    required this.name,
    this.character,
    required this.orderIdx,
    this.profileUrl,
    this.profileLocal,
  });
}

/// Fetches, caches, and serves cast data using TMDB (free API).
///
/// Images are stored in getApplicationDocumentsDirectory()/.cast_imgs/
/// This directory is the app-private internal storage on Android —
/// NOT accessible via any file manager, not visible to other apps.
///
/// API key is injected at build time via --dart-define=TMDB_API_KEY=xxx
/// If the key is not set the feature is silently disabled (no crash).
class ActorService {
  ActorService._();

  static const String _apiBase = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p/w185';

  static const String _apiKey =
      String.fromEnvironment('TMDB_API_KEY', defaultValue: '');

  static bool get hasKey => _apiKey.isNotEmpty;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
  ));

  static Directory? _castDir;

  static Future<Directory> _dir() async {
    if (_castDir != null && _castDir!.existsSync()) return _castDir!;
    final docs = await getApplicationDocumentsDirectory();
    _castDir = Directory(p.join(docs.path, '.cast_imgs'));
    if (!_castDir!.existsSync()) _castDir!.createSync(recursive: true);
    return _castDir!;
  }

  static String _imgPath(Directory dir, int personId) =>
      p.join(dir.path, '$personId.jpg');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the top-12 cast for [item].
  /// Checks SQLite cache first; fetches from TMDB on miss.
  /// Image downloads are kicked off in the background after first fetch.
  static Future<List<CastMember>> getCastForTitle(CatalogItem item) async {
    if (!hasKey) return [];

    final cached = await LocalDb.getCastRaw(item.id);
    if (cached.isNotEmpty) {
      final dir = await _dir();
      return _hydrate(cached, dir);
    }

    try {
      final tmdbId = await _searchId(item);
      if (tmdbId == null) return [];

      final type = item.isMovie ? 'movie' : 'tv';
      final resp = await _dio.get(
        '$_apiBase/$type/$tmdbId/credits',
        queryParameters: {'api_key': _apiKey},
      );

      final raw = (resp.data['cast'] as List? ?? []).take(12).toList();
      if (raw.isEmpty) return [];

      final dir  = await _dir();
      final rows = <Map<String, dynamic>>[];

      for (int i = 0; i < raw.length; i++) {
        final c   = raw[i] as Map;
        final pid = (c['id'] as int?) ?? 0;
        if (pid == 0) continue;
        final profile = c['profile_path'] as String?;
        rows.add({
          'person_id':  pid,
          'name':       c['name'] as String? ?? '',
          'character':  c['character'] as String? ?? c['roles']?[0]?['character'] as String?,
          'order_idx':  i,
          'profile_url': profile != null ? '$_imgBase$profile' : null,
          'profile_local': null,
        });
      }

      await LocalDb.saveCastRaw(item.id, rows);
      final members = _hydrate(rows, dir);
      _downloadImages(rows, dir);
      return members;
    } catch (_) {
      return [];
    }
  }

  /// All titles in our local catalog featuring [personId].
  static Future<List<CatalogItem>> getFilmography(int personId) =>
      LocalDb.getPersonTitles(personId);

  // ── Private helpers ────────────────────────────────────────────────────────

  static Future<int?> _searchId(CatalogItem item) async {
    try {
      final type   = item.isMovie ? 'movie' : 'tv';
      final params = <String, dynamic>{'api_key': _apiKey, 'query': item.title};
      if (item.year != null) params['year'] = item.year;
      final r = await _dio.get('$_apiBase/search/$type', queryParameters: params);
      final results = r.data['results'] as List? ?? [];
      if (results.isEmpty) return null;
      return (results.first['id'] as int?);
    } catch (_) {
      return null;
    }
  }

  /// Convert raw DB rows to [CastMember], using local file if already cached.
  static List<CastMember> _hydrate(List<Map<String, dynamic>> rows, Directory dir) {
    return rows.map((r) {
      final pid = r['person_id'] as int;
      final localFile = File(_imgPath(dir, pid));
      final localPath = localFile.existsSync() ? localFile.path : null;
      return CastMember(
        personId:     pid,
        name:         r['name'] as String? ?? '',
        character:    r['character'] as String?,
        orderIdx:     r['order_idx'] as int? ?? 0,
        profileUrl:   r['profile_url'] as String?,
        profileLocal: localPath ?? r['profile_local'] as String?,
      );
    }).toList();
  }

  /// Download images to internal storage in background (best-effort, silent).
  static void _downloadImages(List<Map<String, dynamic>> rows, Directory dir) {
    Future.microtask(() async {
      for (final r in rows) {
        final url = r['profile_url'] as String?;
        if (url == null) continue;
        final pid  = r['person_id'] as int;
        final file = File(_imgPath(dir, pid));
        if (file.existsSync()) continue;
        try {
          final resp = await _dio.get<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes),
          );
          if (resp.data != null && resp.data!.isNotEmpty) {
            await file.writeAsBytes(resp.data!);
            await LocalDb.updatePersonImagePath(pid, file.path);
          }
        } catch (_) {}
      }
    });
  }
}
