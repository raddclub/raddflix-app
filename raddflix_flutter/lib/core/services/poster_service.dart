import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../db/local_db.dart';
import '../debug/debug_logger.dart';

/// Manages poster images with a smart priority chain and permanent hidden storage.
///
/// Priority when user HAS internet (WiFi / mobile data bundle):
///   1. Already in hidden permanent folder → show instantly
///   2. TMDB/OMDB URL from catalog → download, save permanently
///   3. JazzDrive thumbnail → last resort only
///
/// Priority when user has NO internet (Jazz SIM, zero-rated only):
///   1. Already in hidden permanent folder → show instantly
///   2. Show placeholder — poster arrives when user taps play
///      (JazzDrive thumbnail is fetched for free alongside stream link)
///
/// Storage: getExternalFilesDir / getApplicationDocumentsDirectory + /raddflix_posters/
/// Files named title_{id}.jpg — no collisions even if JazzDrive names all "poster.jpg"
class PosterService {
  static Directory? _posterDir;
  static bool _initialized = false;

  static const int _dailyDownloadLimit = 100;
  static int _downloadsToday = 0;
  static DateTime? _downloadCountDate;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// Initialize the poster directory. Call once on app start.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      _posterDir = Directory('${base.path}/raddflix_posters');
      if (!await _posterDir!.exists()) {
        await _posterDir!.create(recursive: true);
      }
      _initialized = true;
      DebugLogger.log('POSTER', 'Poster dir: ${_posterDir!.path}');
    } catch (e) {
      DebugLogger.logError('POSTER', 'init failed', e);
    }
  }

  /// Get the local file path for a title's poster (if it exists on device).
  /// Returns null if not cached yet.
  static Future<String?> getLocalPath(int titleId) async {
    await init();
    final file = _file(titleId);
    if (await file.exists()) return file.path;
    return null;
  }

  /// Download a poster from [url] and save it permanently.
  /// Also persists the local path to SQLite so home_screen can find it instantly.
  /// No-op if already on disk. Safe to call multiple times.
  static Future<String?> downloadAndCache(int titleId, String url) async {
    await init();
    final file = _file(titleId);
    if (await file.exists()) return file.path;
    if (url.isEmpty) return null;

    try {
      await _dio.download(url, file.path);
      // Task 3.6: persist local path so CatalogItem.posterPath is populated on next load
      await LocalDb.savePosterPath(titleId, file.path);
      DebugLogger.log('POSTER', 'Saved poster for title $titleId');
      return file.path;
    } catch (e) {
      DebugLogger.logError('POSTER', 'Download failed for title $titleId from $url', e);
      try { await file.delete(); } catch (_) {}
      return null;
    }
  }

  /// Save a poster from a JazzDrive thumbnail URL.
  /// Called automatically when a stream link is generated (poster comes free).
  /// Only saves if not already cached — never makes extra JazzDrive requests.
  static Future<void> saveFromJazzDrive(int titleId, String jdUrl) async {
    if (titleId <= 0 || jdUrl.isEmpty) return;
    await init();
    final file = _file(titleId);
    if (await file.exists()) return;
    try {
      await _dio.download(jdUrl, file.path);
      // Persist path so UI picks it up on next app launch
      await LocalDb.savePosterPath(titleId, file.path);
      DebugLogger.log('POSTER', 'Saved JazzDrive poster for title $titleId');
    } catch (e) {
      DebugLogger.logError('POSTER', 'JazzDrive poster save failed for $titleId', e);
      try { await file.delete(); } catch (_) {}
    }
  }

  /// Background poster sync — downloads missing posters from TMDB/OMDB URLs.
  ///
  /// ONLY uses TMDB/OMDB URLs (online sources). Never touches JazzDrive in bulk.
  /// Rate-limited to [_dailyDownloadLimit] per day.
  /// Call when app is in foreground and internet is available.
  static Future<void> runBackgroundSync(
    List<Map<String, dynamic>> items,
  ) async {
    await init();
    _resetDailyCounterIfNeeded();
    if (_downloadsToday >= _dailyDownloadLimit) return;

    for (final item in items) {
      if (_downloadsToday >= _dailyDownloadLimit) break;
      final titleId = item['id'] as int? ?? 0;
      final posterUrl = item['poster_url'] as String? ?? '';
      if (titleId <= 0 || posterUrl.isEmpty) continue;
      final file = _file(titleId);
      if (await file.exists()) continue;
      if (!_isOnlineSource(posterUrl)) continue;
      final result = await downloadAndCache(titleId, posterUrl);
      if (result != null) _downloadsToday++;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static File _file(int titleId) => File('${_posterDir!.path}/title_$titleId.jpg');

  static bool _isOnlineSource(String url) {
    return url.contains('tmdb.org') ||
        url.contains('omdbapi.com') ||
        url.contains('image.tmdb') ||
        url.contains('imdb.com') ||
        url.startsWith('https://');
  }

  static void _resetDailyCounterIfNeeded() {
    final today = DateTime.now();
    if (_downloadCountDate == null ||
        _downloadCountDate!.day != today.day) {
      _downloadsToday = 0;
      _downloadCountDate = today;
    }
  }
}
