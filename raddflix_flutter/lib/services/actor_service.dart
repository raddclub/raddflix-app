import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';

/// A single cast member fetched from IMDB/Wikipedia and cached locally.
class CastMember {
  final int    personId;
  final String name;
  final String? character;
  final int    orderIdx;
  final String? profileUrl;
  final String? profileLocal;

  const CastMember({
    required this.personId,
    required this.name,
    this.character,
    required this.orderIdx,
    this.profileUrl,
    this.profileLocal,
  });
}

/// Fetches, caches, and serves cast data.
///
/// ## Data sources (all free, no paid subscription required)
///
/// 1. **IMDB suggestion API** — `v3.sg.media-imdb.com/suggestion/titles`
///    IMDB's own autocomplete endpoint. No API key. Used to resolve
///    title → IMDB `tt` ID and grab the top-billed star names.
///
/// 2. **OMDb API** — `omdbapi.com` (optional, free tier 1000 req/day)
///    Extends the cast list beyond the ~2 names from the suggestion API.
///    Only used when `--dart-define=OMDB_API_KEY=<key>` is supplied at
///    build time. Completely optional — the service works without it.
///
/// 3. **Wikipedia Thumbnail API** — `en.wikipedia.org/w/api.php`
///    Batch-fetches actor profile photos (one HTTP request for all actors).
///    Completely free, no API key required.
///
/// ## Caching
/// All cast rows are persisted to SQLite (`persons` + `cast_members` tables)
/// after the first fetch. Photos are downloaded to
/// `getApplicationDocumentsDirectory()/.cast_imgs/` — app-private internal
/// storage, invisible to file managers and other apps.
///
/// ## Person IDs
/// SQLite requires INTEGER primary keys. Since we no longer have TMDB numeric
/// IDs, each actor name is hashed with a deterministic FNV-1a 32-bit function.
/// The same name always produces the same ID across devices and app versions,
/// enabling the filmography query (`getPersonTitles`) to work correctly.
class ActorService {
  ActorService._();

  // IMDB suggestion API — free, no key, IMDB's own autocomplete endpoint
  static const String _imdbSuggest =
      'https://v3.sg.media-imdb.com/suggestion/titles';

  // OMDb API — optional free key (1 000 req/day on free tier)
  static const String _omdbBase = 'https://www.omdbapi.com';
  static const String _omdbKey =
      String.fromEnvironment('OMDB_API_KEY', defaultValue: '');
  static bool get _hasOmdb => _omdbKey.isNotEmpty;

  // Wikipedia Thumbnail API — completely free, no key
  static const String _wikiApi = 'https://en.wikipedia.org/w/api.php';

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'RaddFlix/1.0 (Android; imdb-wikipedia-cast)',
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
  ///
  /// Produces a stable integer person_id that is consistent across devices,
  /// platforms, and app versions — so the same actor in two different titles
  /// always gets the same ID, enabling filmography queries to work correctly.
  static int _nameToId(String name) {
    var h = 2166136261;
    for (final c in name.toLowerCase().trim().codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the top cast for [item] (up to ~12 members).
  ///
  /// Checks SQLite cache first. On miss: searches IMDB, expands cast list
  /// via OMDb (if key available), fetches photos from Wikipedia, saves to DB,
  /// and kicks off background image downloads to internal storage.
  static Future<List<CastMember>> getCastForTitle(CatalogItem item) async {
    final cached = await LocalDb.getCastRaw(item.id);
    if (cached.isNotEmpty) {
      final dir = await _dir();
      return _hydrate(cached, dir);
    }

    try {
      // Step 1 — resolve title → IMDB ID + initial star names (keyless)
      final (imdbId, initialNames) = await _searchImdb(item);
      if (imdbId == null && initialNames.isEmpty) return [];

      // Step 2 — extend cast list via OMDb if key is available; else use
      //          the 2–3 names returned by the IMDB suggestion API
      final List<String> actorNames;
      if (_hasOmdb && imdbId != null) {
        final omdbNames = await _fetchOmdbCast(imdbId);
        actorNames = omdbNames.isNotEmpty ? omdbNames : initialNames;
      } else {
        actorNames = initialNames;
      }
      if (actorNames.isEmpty) return [];

      // Step 3 — batch-fetch Wikipedia profile photos (single HTTP call)
      final photos = await _fetchWikiPhotos(actorNames);

      // Step 4 — build rows, persist to SQLite, start background downloads
      final dir  = await _dir();
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

      await LocalDb.saveCastRaw(item.id, rows);
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

  // ── IMDB Suggestion API (keyless) ─────────────────────────────────────────

  /// Resolves [item] to an IMDB `tt` ID and returns the top-billed star names
  /// from IMDB's own autocomplete endpoint.
  ///
  /// URL format: `https://v3.sg.media-imdb.com/suggestion/titles/{c}/{q}.json`
  /// where {c} is the first character of the query (lowercase).
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

      // Prefer an entry whose year and type match our catalog item
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

  /// Fetches the cast list from OMDb using the IMDB title ID.
  /// OMDb free tier: 1 000 requests/day. Key via `--dart-define=OMDB_API_KEY`.
  /// Returns actor names as a list (OMDb provides up to ~4 top-billed actors).
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

  /// Fetches profile photo thumbnails for up to 50 actor names in a single
  /// Wikipedia API call. Returns a map of {name → thumbnail URL}.
  ///
  /// Uses Wikipedia's `pageimages` prop with `formatversion=2` so the response
  /// is an array (easier to iterate than the legacy keyed-by-pageid object).
  static Future<Map<String, String>> _fetchWikiPhotos(
      List<String> names) async {
    if (names.isEmpty) return {};
    try {
      // Wikipedia supports up to 50 titles per query separated by |
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
        // Match back to the original name (Wikipedia normalises capitalisation)
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

  /// Downloads actor profile images to app-private internal storage.
  /// Runs in the background (microtask queue) — never blocks the UI.
  /// Already-cached files are skipped. Failures are silent.
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
