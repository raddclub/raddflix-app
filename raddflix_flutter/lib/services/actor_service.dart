import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';

/// A single cast member fetched from TVMaze/IMDB/Wikipedia and cached locally.
class CastMember {
  final int    personId;
  final String name;
  final String? character;
  final int    orderIdx;
  final String? profileUrl;
  final String? profileLocal;
  final String? bio;

  const CastMember({
    required this.personId,
    required this.name,
    this.character,
    required this.orderIdx,
    this.profileUrl,
    this.profileLocal,
    this.bio,
  });
}

/// Fetches, caches, and serves cast data.
///
/// ## Data sources (all free, no paid subscription required)
///
/// 1. **TVMaze API** — `api.tvmaze.com/singlesearch/shows?q={title}&embed=cast`
///    Free, no API key. Returns full cast with character names and profile photos
///    for TV shows. Primary source for any show.
///
/// 2. **IMDB suggestion API** — `v3.sg.media-imdb.com/suggestion/titles`
///    IMDB's own autocomplete endpoint. No API key. Used for movies and as
///    fallback for shows. Returns 2-3 top-billed star names.
///
/// 3. **OMDb API** — `omdbapi.com` (optional, free tier 1000 req/day)
///    Extends the cast list beyond the ~2 names from the suggestion API.
///    Only used when `--dart-define=OMDB_API_KEY=<key>` is supplied at
///    build time. Completely optional — the service works without it.
///
/// 4. **Wikipedia Thumbnail API** — `en.wikipedia.org/w/api.php`
///    Batch-fetches actor profile photos (one HTTP request for all actors).
///    Completely free, no API key required. Also used for short actor bios.
///
/// ## Caching
/// All cast rows are persisted to SQLite (`persons` + `cast_members` tables)
/// after the first fetch. Photos are downloaded to
/// `getApplicationDocumentsDirectory()/.cast_imgs/` — app-private internal
/// storage, invisible to file managers and other apps.
class ActorService {
  ActorService._();

  // TVMaze API — completely free, no key
  static const String _tvMazeBase = 'https://api.tvmaze.com';

  // IMDB suggestion API — free, no key, IMDB's own autocomplete endpoint
  static const String _imdbSuggest =
      'https://v3.sg.media-imdb.com/suggestion/titles';

  // OMDb API — optional free key (1 000 req/day on free tier)
  static const String _omdbBase = 'https://www.omdbapi.com';
  static const String _omdbKey =
      String.fromEnvironment('OMDB_API_KEY', defaultValue: '');
  static bool get _hasOmdb => _omdbKey.isNotEmpty;

  // Wikipedia APIs — completely free, no key
  static const String _wikiApi = 'https://en.wikipedia.org/w/api.php';

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'RaddFlix/1.0 (Android; tvmaze-imdb-wikipedia-cast)',
      'Accept-Language': 'en-US,en;q=0.9',
    },
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

  /// Deterministic FNV-1a 32-bit hash of actor name.
  static int _nameToId(String name) {
    var h = 2166136261;
    for (final c in name.toLowerCase().trim().codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns cast for [item] — up to 20 members for shows (via TVMaze),
  /// up to ~10 for movies (via IMDB/OMDb + Wikipedia photos).
  ///
  /// Checks SQLite cache first. On miss: fetches from TVMaze (shows) or
  /// IMDB+OMDb (movies), photos from Wikipedia, saves to DB, and kicks off
  /// background image downloads to internal storage.
  static Future<List<CastMember>> getCastForTitle(CatalogItem item) async {
    final cached = await LocalDb.getCastRaw(item.id);
    if (cached.isNotEmpty) {
      final dir = await _dir();
      return _hydrate(cached, dir);
    }

    try {
      List<Map<String, dynamic>> rows;

      if (item.isShow) {
        // TV shows: TVMaze gives full cast with character names + photos
        rows = await _fetchTvMazeCast(item.title);
      } else {
        rows = [];
      }

      // Fallback to IMDB/OMDb for movies or when TVMaze returns nothing
      if (rows.isEmpty) {
        rows = await _fetchImdbOmdbCast(item);
      }

      if (rows.isEmpty) return [];

      await LocalDb.saveCastRaw(item.id, rows);
      final dir = await _dir();
      final members = _hydrate(rows, dir);
      _downloadImages(rows, dir);
      return members;
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] getCastForTitle error: $e');
      return [];
    }
  }

  /// All titles in our local catalog that feature [personId].
  static Future<List<CatalogItem>> getFilmography(int personId) =>
      LocalDb.getPersonTitles(personId);

  /// Fetch a short biography for an actor from Wikipedia (1–2 sentences).
  /// Returns null if not found or network error.
  static Future<String?> getBio(String name) async {
    try {
      final r = await _dio.get(_wikiApi, queryParameters: {
        'action':       'query',
        'prop':         'extracts',
        'exintro':      '1',
        'exsentences':  '2',
        'explaintext':  '1',
        'titles':       name,
        'format':       'json',
        'formatversion':'2',
      });
      final d = r.data is String
          ? jsonDecode(r.data as String) as Map
          : r.data as Map;
      final pages = (d['query']?['pages'] as List? ?? []);
      if (pages.isEmpty) return null;
      final extract = pages.first['extract'] as String?;
      if (extract == null || extract.isEmpty || extract.startsWith('may refer to')) {
        return null;
      }
      // Trim to 2 sentences max
      final sentences = extract.split(RegExp(r'(?<=[.!?])\s+'));
      return sentences.take(2).join(' ').trim();
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] getBio error: $e');
      return null;
    }
  }

  // ── TVMaze Cast (TV Shows — free, full cast with character names) ──────────

  /// Fetches full cast from TVMaze for a TV show.
  /// Returns rows ready for SQLite insertion, including profile_url from TVMaze.
  /// TVMaze provides character names and actor photos — no secondary fetch needed
  /// for photos (though Wikipedia fallback is still tried for missing ones).
  static Future<List<Map<String, dynamic>>> _fetchTvMazeCast(String title) async {
    try {
      final r = await _dio.get(
        '$_tvMazeBase/singlesearch/shows',
        queryParameters: {
          'q':       title,
          'embed':   'cast',
        },
        options: Options(validateStatus: (_) => true),
      );
      if (r.statusCode != 200) return [];
      final d = r.data is String
          ? jsonDecode(r.data as String) as Map
          : r.data as Map;
      final cast = (d['_embedded']?['cast'] as List? ?? []);
      if (cast.isEmpty) return [];

      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < cast.length && i < 20; i++) {
        final entry  = cast[i] as Map;
        final person = entry['person'] as Map? ?? {};
        final char   = entry['character'] as Map? ?? {};
        final name   = person['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final imgMap     = person['image'] as Map?;
        final profileUrl = imgMap?['medium'] as String? ?? imgMap?['original'] as String?;
        rows.add({
          'person_id':    _nameToId(name),
          'name':         name,
          'character':    char['name'] as String?,
          'order_idx':    i,
          'profile_url':  profileUrl,
          'profile_local': null,
        });
      }
      return rows;
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] TVMaze error: $e');
      return [];
    }
  }

  // ── IMDB + OMDb flow (movies + show fallback) ─────────────────────────────

  static Future<List<Map<String, dynamic>>> _fetchImdbOmdbCast(
      CatalogItem item) async {
    // Step 1 — resolve title → IMDB ID + initial star names
    final (imdbId, initialNames) = await _searchImdb(item);
    if (imdbId == null && initialNames.isEmpty) return [];

    // Step 2 — extend cast list via OMDb if key available
    final List<String> actorNames;
    if (_hasOmdb && imdbId != null) {
      final omdbNames = await _fetchOmdbCast(imdbId);
      actorNames = omdbNames.isNotEmpty ? omdbNames : initialNames;
    } else {
      actorNames = initialNames;
    }
    if (actorNames.isEmpty) return [];

    // Step 3 — batch-fetch Wikipedia profile photos
    final photos = await _fetchWikiPhotos(actorNames);

    // Step 4 — build rows
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < actorNames.length; i++) {
      final name = actorNames[i];
      rows.add({
        'person_id':    _nameToId(name),
        'name':         name,
        'character':    null,
        'order_idx':    i,
        'profile_url':  photos[name],
        'profile_local': null,
      });
    }
    return rows;
  }

  // ── IMDB Suggestion API (keyless) ─────────────────────────────────────────

  static Future<(String?, List<String>)> _searchImdb(CatalogItem item) async {
    try {
      final query = item.title.trim();
      if (query.isEmpty) return (null, <String>[]);

      final c   = Uri.encodeComponent(query[0].toLowerCase());
      final q   = Uri.encodeComponent(query);
      final url = '$_imdbSuggest/$c/$q.json';

      final r = await _dio.get(url);
      final d = r.data is String
          ? jsonDecode(r.data as String) as Map
          : r.data as Map;
      final results = (d['d'] as List? ?? []);
      if (results.isEmpty) return (null, <String>[]);

      Map<String, dynamic>? best;
      for (final entry in results) {
        final e    = Map<String, dynamic>.from(entry as Map);
        final qid  = (e['qid'] as String? ?? '').toLowerCase();
        final typeOk = item.isMovie
            ? (qid == 'movie' || qid == 'tvmovie' || qid.isEmpty)
            : (qid == 'tvseries' || qid == 'tvshortseries');
        final entryYear = e['y'] as int?;
        final yearOk  = item.year == null ||
            entryYear == item.year ||
            (e['yr'] as String? ?? '').contains(item.year.toString());
        if (typeOk && yearOk) { best = e; break; }
      }
      best ??= Map<String, dynamic>.from(results.first as Map);

      final ttId  = best['id'] as String?;
      final stars = best['s'] as String? ?? '';
      final names = stars
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      return (ttId, names);
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] IMDB suggest error: $e');
      return (null, <String>[]);
    }
  }

  // ── OMDb Cast List (optional free key) ────────────────────────────────────

  static Future<List<String>> _fetchOmdbCast(String imdbId) async {
    try {
      final r = await _dio.get(_omdbBase, queryParameters: {
        'i':      imdbId,
        'apikey': _omdbKey,
      });
      final d = r.data is String
          ? jsonDecode(r.data as String) as Map
          : r.data as Map;
      if (d['Response'] == 'False') return [];
      final actors = d['Actors'] as String? ?? '';
      return actors
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] OMDb error: $e');
      return [];
    }
  }

  // ── Wikipedia Batch Thumbnail Fetch (keyless) ─────────────────────────────

  static Future<Map<String, String>> _fetchWikiPhotos(
      List<String> names) async {
    if (names.isEmpty) return {};
    try {
      final batch = names.take(50).toList();
      final r = await _dio.get(_wikiApi, queryParameters: {
        'action':        'query',
        'titles':        batch.join('|'),
        'prop':          'pageimages',
        'piprop':        'thumbnail',
        'pithumbsize':   '185',
        'format':        'json',
        'formatversion': '2',
      });
      final d = r.data is String
          ? jsonDecode(r.data as String) as Map
          : r.data as Map;
      final pages = (d['query']?['pages'] as List? ?? []);
      final map   = <String, String>{};
      for (final raw in pages) {
        final page     = raw as Map;
        final thumbUrl = page['thumbnail']?['source'] as String?;
        if (thumbUrl == null) continue;
        final pageTitle = page['title'] as String? ?? '';
        final match = batch.firstWhere(
          (n) => n.toLowerCase() == pageTitle.toLowerCase(),
          orElse: () => '',
        );
        if (match.isNotEmpty) map[match] = thumbUrl;
      }
      return map;
    } catch (e) {
      if (kDebugMode) debugPrint('[ActorService] Wikipedia photo error: $e');
      return {};
    }
  }

  // ── Hydrate from cached DB rows ────────────────────────────────────────────

  static List<CastMember> _hydrate(
      List<Map<String, dynamic>> rows, Directory dir) {
    return rows.map((r) {
      final pid       = r['person_id'] as int;
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

  // ── Background image download ──────────────────────────────────────────────

  static void _downloadImages(
      List<Map<String, dynamic>> rows, Directory dir) {
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
