import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../db/local_db.dart';
import '../debug/debug_logger.dart';
import 'poster_service.dart';

/// Result of a successful JazzDrive link generation.
class JazzDriveLink {
  final String streamUrl;
  final String? posterUrl;
  final String filename;
  const JazzDriveLink({
    required this.streamUrl,
    this.posterUrl,
    required this.filename,
  });
}

/// On-device JazzDrive stream link generator.
///
/// Generates direct CDN stream URLs from JazzDrive share URLs without
/// going through the Oracle server — fully zero-rated for Jazz SIM users.
///
/// Flow:
///   1. Check in-memory cache (instant, no network)
///   2. Check persistent SQLite cache (fast, no network)
///   3. Call JazzDrive API directly (2 calls to cloud.jazzdrive.com.pk, zero-rated)
///   4. Cache result for 110 minutes (safely under ~2h CDN token expiry)
class JazzDriveService {
  static const String _cloudBase = 'https://cloud.jazzdrive.com.pk';
  // CDN tokens expire in ~2h — 110 min cache is safely under that limit to avoid stale URL errors
  static const Duration _cacheTtl = Duration(minutes: 110);

  static final _inMemory = <String, _CacheEntry>{};
  static const int _maxCacheEntries = 200; // H-05: cap to prevent unbounded growth
  static final _inFlight = <String, Future<JazzDriveLink>>{}; // H-05: dedup concurrent requests

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json;charset=UTF-8',
    'Origin': _cloudBase,
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'X-Requested-With': 'com.jazz.drive',
  };

  /// Load non-expired cache entries from SQLite into memory on app start.
  /// Call this once from main.dart after LocalDb is ready.
  static Future<void> loadCacheFromDb() async {
    try {
      final rows = await LocalDb.getValidStreamCache();
      for (final row in rows) {
        final fileId = row['file_id'] as String? ?? '';
        final streamUrl = row['stream_url'] as String? ?? '';
        final posterUrl = row['poster_url'] as String?;
        final expiresAt = row['expires_at'] as int? ?? 0;
        if (fileId.isEmpty || streamUrl.isEmpty) continue;
        _inMemory[fileId] = _CacheEntry(
          streamUrl: streamUrl,
          posterUrl: posterUrl,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
        );
      }
      DebugLogger.log('JAZZDRIVE', 'Loaded ${_inMemory.length} cached links from DB');
    } catch (e) {
      DebugLogger.logError('JAZZDRIVE', 'loadCacheFromDb failed', e);
    }
  }

  /// Get a stream URL for a file.
  ///
  /// [fileId]   — the file's ID (used as cache key)
  /// [shareUrl] — the JazzDrive share URL (stored in local DB)
  /// [titleId]  — optional title ID; when provided, the JazzDrive poster thumbnail
  ///              is saved permanently to device storage at no extra network cost.
  ///
  /// Returns a [JazzDriveLink] with streamUrl + optional posterUrl.
  /// Throws if all attempts fail.
  /// H-05: Evict expired entries and trim to _maxCacheEntries to bound memory usage.
  static void _evictExpired() {
    final now = DateTime.now();
    _inMemory.removeWhere((_, v) => v.expiresAt.isBefore(now));
    while (_inMemory.length > _maxCacheEntries) {
      _inMemory.remove(_inMemory.keys.first);
    }
  }

  static Future<JazzDriveLink> getStreamLink(
    String fileId,
    String shareUrl, {
    int? titleId,
    String? targetFilename,
    int remoteId = 0,
  }) async {
    // H-05: periodic eviction — runs when cache is getting large
    if (_inMemory.length > _maxCacheEntries ~/ 2) _evictExpired();

    // H-05: in-flight dedup — if a concurrent call is already generating this
    // link, wait for it rather than firing a duplicate JazzDrive API request.
    if (_inFlight.containsKey(fileId)) {
      DebugLogger.log('JAZZDRIVE', 'In-flight dedup for file $fileId');
      return _inFlight[fileId]!;
    }

    // 1. Check in-memory cache
    final mem = _inMemory[fileId];
    if (mem != null && mem.expiresAt.isAfter(DateTime.now())) {
      DebugLogger.log('JAZZDRIVE', 'Cache hit (memory) for file $fileId');
      return JazzDriveLink(
        streamUrl: mem.streamUrl,
        posterUrl: mem.posterUrl,
        filename: '',
      );
    }

    // 2. Check DB cache
    final dbRow = await LocalDb.getStreamCache(fileId);
    if (dbRow != null) {
      final expiresAt = dbRow['expires_at'] as int? ?? 0;
      if (expiresAt > DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        final streamUrl = dbRow['stream_url'] as String? ?? '';
        final posterUrl = dbRow['poster_url'] as String?;
        DebugLogger.log('JAZZDRIVE', 'Cache hit (DB) for file $fileId');
        _inMemory[fileId] = _CacheEntry(
          streamUrl: streamUrl,
          posterUrl: posterUrl,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
        );
        return JazzDriveLink(
          streamUrl: streamUrl,
          posterUrl: posterUrl,
          filename: '',
        );
      }
    }

    // 3. Generate fresh link via JazzDrive API (zero-rated)
    // H-05: register in-flight future before awaiting to dedup races
    DebugLogger.log('JAZZDRIVE', 'Generating fresh link for file $fileId');
    final generationFuture = _generateLink(shareUrl, targetFilename: targetFilename, remoteId: remoteId);
    _inFlight[fileId] = generationFuture;
    late final JazzDriveLink link;
    try {
      link = await generationFuture;
    } finally {
      _inFlight.remove(fileId);
    }

    // 4. Cache result
    final expiresAt = DateTime.now().add(_cacheTtl);
    _inMemory[fileId] = _CacheEntry(
      streamUrl: link.streamUrl,
      posterUrl: link.posterUrl,
      expiresAt: expiresAt,
    );
    await LocalDb.saveStreamCache(
      fileId: fileId,
      streamUrl: link.streamUrl,
      posterUrl: link.posterUrl,
      expiresAt: expiresAt.millisecondsSinceEpoch ~/ 1000,
    );

    // Task 3.7 — poster comes free with every fresh link; save it permanently.
    // Fire-and-forget: never blocks playback. Only runs when a fresh API call was needed.
    if (titleId != null && titleId > 0 &&
        link.posterUrl != null && link.posterUrl!.isNotEmpty) {
      unawaited(PosterService.saveFromJazzDrive(titleId, link.posterUrl!));
    }

    DebugLogger.log('JAZZDRIVE', 'Generated + cached link for file $fileId → ${link.filename}');
    return link;
  }

  /// Invalidate cache for a file (force fresh link on next play).
  static Future<void> invalidate(String fileId) async {
    _inMemory.remove(fileId);
    await LocalDb.deleteStreamCache(fileId);
  }

  /// Runs a fresh end-to-end diagnostic of the JazzDrive share link chain.
  /// Bypasses all caches — every step exercises the actual JazzDrive API.
  ///
  /// Returns a map with step results:
  ///   'share_key'  — first 12 chars of the extracted share key
  ///   'login'      — VK prefix + .NODE suffix on success
  ///   'media'      — matched filename on success
  ///   'stream_url' — first 80 chars of the final CDN URL on success
  ///   'error'      — present only on failure (any step); describes which step failed
  ///
  /// Called by [DebugDiagnosticsScreen._checkJazzDrive].
  static Future<Map<String, dynamic>> diagnosticTest({
    required String shareUrl,
    String? targetFilename,
    int remoteId = 0,
  }) async {
    final out = <String, dynamic>{};
    try {
      final shareKey = _extractShareKey(shareUrl);
      if (shareKey == null) {
        out['error'] = 'Cannot extract share key from URL';
        return out;
      }
      out['share_key'] = shareKey.length > 12
          ? '${shareKey.substring(0, 12)}…' : shareKey;

      final session  = await _loginShare(shareKey);
      final jidEnd   = session.cookie.split('.').last;
      out['login']   = 'OK · VK=${session.validationKey.substring(0, 8)}… · .NODE=.$jidEnd';

      final record   = await _getMedia(
        shareKey, session.validationKey, session.cookie,
        targetFilename: targetFilename, remoteId: remoteId,
      );
      out['media']   = 'OK · "${record.filename}"';

      final streamUrl = _buildStreamUrl(record.rawUrl, record.filename);
      out['stream_url'] = streamUrl.length > 80
          ? '${streamUrl.substring(0, 80)}…' : streamUrl;
    } catch (e) {
      out['error'] = e.toString().split('\n').first;
    }
    return out;
  }

  /// Pre-warm the stream-link cache for the top [count] free movies.
  ///
  /// Fire-and-forget: call with [unawaited] so it never delays app launch
  /// or UI rendering. Queries SQLite for the top [count] is_free=1 movie
  /// titles ordered by db_version DESC, then calls [getStreamLink] for each.
  ///
  /// Because [getStreamLink] honours the existing 110-min TTL the warm step
  /// is a no-op for items already cached — zero extra network calls within
  /// the TTL window. On Jazz SIM all SAPI calls go directly to
  /// cloud.jazzdrive.com.pk (zero-rated). Silently swallows all errors so
  /// an offline device or unreachable JazzDrive never surfaces to the user.
  ///
  /// A 60-minute static guard ensures the warm only executes once per hour
  /// regardless of how many callers trigger it on cold start.
  static DateTime? _lastWarmTime;

  static Future<void> warmTopFreeItems(int count) async {
    final now = DateTime.now();
    if (_lastWarmTime != null &&
        now.difference(_lastWarmTime!).inMinutes < 60) {
      DebugLogger.log('JAZZDRIVE', 'warmTopFreeItems skipped (already ran ${now.difference(_lastWarmTime!).inMinutes}m ago)');
      return;
    }
    _lastWarmTime = now;
    try {
      final rows = await LocalDb.getTopFreeMovies(count);
      int warmed = 0;
      for (final row in rows) {
        try {
          final fileId   = row['file_id']   as String? ?? '';
          final shareUrl = row['share_url'] as String? ?? '';
          if (fileId.isEmpty || shareUrl.isEmpty) continue;
          await getStreamLink(fileId, shareUrl);
          warmed++;
        } catch (_) {
          // Per-item failure — silently continue to the next item.
        }
      }
      DebugLogger.log(
          'JAZZDRIVE', 'Warm complete: $warmed/${rows.length} item(s) pre-fetched');
    } catch (e) {
      DebugLogger.logWarn('JAZZDRIVE', 'warmTopFreeItems failed silently: $e');
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Future<JazzDriveLink> _generateLink(String shareUrl, {String? targetFilename, int remoteId = 0}) async {
    final shareKey = _extractShareKey(shareUrl);
    if (shareKey == null) {
      throw Exception('Invalid JazzDrive share URL: $shareUrl');
    }

    // Step 1: Login to share → get validationKey + JSESSIONID cookie
    final session = await _loginShare(shareKey);

    // Step 2: Get video list → CDN raw URL + filename + poster
    final record = await _getMedia(
      shareKey, session.validationKey, session.cookie,
      targetFilename: targetFilename, remoteId: remoteId,
    );

    // Step 3: Build final CDN stream URL.
    // The rawUrl from JazzDrive already contains a self-signed k= token that
    // authenticates the CDN request. Just prepend the cloud base if the URL
    // is relative, and append filename= for correct Content-Disposition.
    final streamUrl = _buildStreamUrl(record.rawUrl, record.filename);
    final posterUrl = _buildPosterUrl(record.rawPosterUrl);

    return JazzDriveLink(
      streamUrl: streamUrl,
      posterUrl: posterUrl,
      filename: record.filename,
    );
  }

  static String? _extractShareKey(String shareUrl) {
    final m = RegExp(r'/(?:share-landing/f|share/f|f)/([^/?#]+)').firstMatch(shareUrl);
    return m?.group(1);
  }

  static Future<_ShareSession> _loginShare(String shareKey) async {
    final loginUrl = '$_cloudBase/sapi/link/login?action=login';
    final headers = Map<String, String>.from(_baseHeaders)
      ..['Referer'] = '$_cloudBase/share/f/$shareKey';

    // FIX-JAZZDRIVE-HTML: use validateStatus=(s)=>true so non-200 responses
    // don't throw before we can inspect the body.  JazzDrive sometimes returns
    // an HTML error page (e.g. when NOT on Jazz SIM) — without validateStatus
    // Dio throws DioException with no useful body, losing the real error reason.
    final resp = await _dio.post<dynamic>(
      loginUrl,
      data: {'data': {'accesstoken': shareKey}},
      options: Options(
        headers: headers,
        validateStatus: (s) => true,
      ),
    );

    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('JazzDrive login failed: HTTP ${resp.statusCode}');
    }

    // Parse response body — may be a pre-decoded Map or a raw JSON/HTML String.
    final Map<String, dynamic> data;
    if (resp.data is Map<String, dynamic>) {
      data = resp.data as Map<String, dynamic>;
    } else if (resp.data is String) {
      final raw = resp.data as String;
      if (raw.trimLeft().startsWith('<')) {
        // HTML error page — device is not on Jazz SIM or JazzDrive is down
        throw Exception(
            'JazzDrive returned an HTML page (not on Jazz SIM data, or service unavailable)');
      }
      try {
        data = json.decode(raw) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('JazzDrive login: unexpected response format');
      }
    } else {
      throw Exception('JazzDrive login: unreadable response');
    }

    // Detect explicit JazzDrive error (MED-1011 = share key invalid, FOL-1004 = folder deleted)
    final errorObj = data['error'] as Map<String, dynamic>?;
    if (errorObj != null && (errorObj['code'] as String? ?? '').isNotEmpty) {
      final errCode = errorObj['code'] as String? ?? 'UNKNOWN';
      final errMsg  = errorObj['message'] as String? ?? 'Link expired';
      throw Exception('Content unavailable ($errCode: $errMsg). Please contact admin.');
    }

    final inner = (data['data'] as Map<String, dynamic>?) ?? data;
    final vk = (inner['validationkey'] ?? inner['validationKey'] ?? inner['validation_key']
                ?? data['validationkey'] ?? data['validationKey']) as String?;

    if (vk == null || vk.isEmpty) {
      throw Exception('JazzDrive login: no validationkey in response');
    }

    // Extract JSESSIONID — prefer JSON body (more reliable on Android where
    // Dart's HttpClient may absorb Set-Cookie headers before they reach Dio).
    String cookie = '';
    final bodyJsid = (inner['jsessionid'] ?? inner['JSESSIONID']
                     ?? data['jsessionid'] ?? data['JSESSIONID']) as String?;
    if (bodyJsid != null && bodyJsid.isNotEmpty) {
      // BUG-JD-SESSION: Keep the FULL JSESSIONID including the .NODE suffix
      // (e.g. "9A126D26...B6.2i182"). JazzDrive load balancer uses that suffix
      // for sticky session routing. Stripping it sends /sapi/media/video to a
      // different node with no session record -> HTTP 401 HTML -> parse failure.
      // Root-cause confirmed: WITH suffix -> 200 OK, WITHOUT -> 401 HTML.
      cookie = 'JSESSIONID=$bodyJsid';
    } else {
      // Fallback: extract from Set-Cookie response header
      final setCookieList = resp.headers.map['set-cookie'] ?? [];
      for (final c in setCookieList) {
        final m = RegExp(r'JSESSIONID=([^;]+)').firstMatch(c);
        if (m != null) {
          cookie = 'JSESSIONID=${m.group(1)}';
          break;
        }
      }
    }

    return _ShareSession(validationKey: vk, cookie: cookie);
  }

  static Future<_MediaRecord> _getMedia(
    String shareKey,
    String validationKey,
    String cookie, {
    String? targetFilename,
    int remoteId = 0,
  }) async {
    final mediaUrl = '$_cloudBase/sapi/media/video'
        '?action=get&shared=true'
        '&key=${Uri.encodeComponent(shareKey)}'
        '&validationkey=${Uri.encodeComponent(validationKey)}';

    final headers = Map<String, String>.from(_baseHeaders)
      ..['Referer'] = '$_cloudBase/share/f/$shareKey'
      ..['validation_key'] = validationKey;
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    // FIX-JAZZDRIVE-HTML: validateStatus so non-200 responses don't discard body.
    final resp = await _dio.get<dynamic>(
      mediaUrl,
      options: Options(
        headers: headers,
        validateStatus: (s) => true,
      ),
    );

    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('JazzDrive media fetch failed: HTTP ${resp.statusCode}');
    }

    // Parse — handle pre-decoded Map, raw JSON string, or HTML error page.
    final Map<String, dynamic> body;
    if (resp.data is Map<String, dynamic>) {
      body = resp.data as Map<String, dynamic>;
    } else if (resp.data is String) {
      final raw = resp.data as String;
      if (raw.trimLeft().startsWith('<')) {
        throw Exception(
            'JazzDrive media fetch: HTML response (session expired or not on Jazz SIM)');
      }
      try {
        body = json.decode(raw) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('JazzDrive media fetch: unexpected response format');
      }
    } else {
      throw Exception('JazzDrive media fetch: unreadable response');
    }

    // Parse records list from various response shapes
    List<dynamic> records = [];
    final rawBody = body['data'] ?? body;
    final d = rawBody is Map<String, dynamic> ? rawBody : (body is Map<String, dynamic> ? body : <String, dynamic>{});
    if (rawBody is List) {
      records = rawBody as List<dynamic>;
    } else {
      for (final key in ['list', 'items', 'videos', 'records', 'files']) {
        if (d[key] is List) { records = d[key] as List; break; }
        if (body[key] is List) { records = body[key] as List; break; }
      }
      if (records.isEmpty && (d['url'] != null || d['id'] != null)) {
        records = [d];
      }
    }

    if (records.isEmpty) {
      throw Exception('JazzDrive: no video records found in share');
    }
    DebugLogger.log('JAZZDRIVE', 'Records (${records.length}): ${records.map((r) { final m = r as Map<String,dynamic>; return (m["name"] ?? m["filename"] ?? "?") as String; }).toList()}');

    String _rname(dynamic r) =>
        ((r as Map<String, dynamic>)['name'] ?? r['filename'] ?? '') as String;

    Map<String, dynamic>? rec;

    // Pass 0: exact match by JazzDrive file ID (remote_id) — filename-independent
    if (remoteId > 0) {
      for (final r in records) {
        final m = r as Map<String, dynamic>;
        final rid = (m['id'] ?? m['fileId'] ?? m['file_id'] ?? 0);
        final ridInt = rid is int ? rid : int.tryParse(rid.toString()) ?? 0;
        if (ridInt == remoteId) {
          rec = m;
          DebugLogger.log('JAZZDRIVE', 'Pass0 match by remote_id=$remoteId → ${_rname(m)}');
          break;
        }
      }
    }

    // Passes 1-3: filename-based fallback
    if (rec == null && targetFilename != null && targetFilename.isNotEmpty) {
      final tgt = targetFilename.toLowerCase();
      // Pass 1: case-insensitive substring
      for (final r in records) {
        final n = _rname(r).toLowerCase();
        if (n.contains(tgt) || tgt.contains(n)) { rec = r as Map<String, dynamic>; break; }
      }
      // Pass 2: normalised (dots/underscores → spaces)
      if (rec == null) {
        String norm(String s) => s.replaceAll(RegExp(r'[._]'), ' ').toLowerCase();
        for (final r in records) {
          final n = norm(_rname(r));
          if (n.contains(norm(tgt)) || norm(tgt).contains(n)) { rec = r as Map<String, dynamic>; break; }
        }
      }
      // Pass 3: episode code e.g. "s01e04"
      if (rec == null) {
        final em = RegExp(r's(\d{1,2})e(\d{1,2})', caseSensitive: false).firstMatch(tgt);
        if (em != null) {
          final s = em.group(1)!.padLeft(2, '0');
          final e = em.group(2)!.padLeft(2, '0');
          final code = 's' + s + 'e' + e;
          DebugLogger.log('JAZZDRIVE', 'Pass3 code: $code');
          for (final r in records) {
            if (_rname(r).toLowerCase().contains(code)) { rec = r as Map<String, dynamic>; break; }
          }
        }
      }
    }

    rec ??= records.first as Map<String, dynamic>;

    final rawUrl  = (rec['url'] ?? rec['downloadUrl'] ?? rec['download_url'] ?? '') as String;
    final filename = (rec['name'] ?? rec['filename'] ?? 'video.mkv') as String;

    // Extract poster from thumbnails[]
    final thumbs = (rec['thumbnails'] as List<dynamic>?) ?? [];
    String? rawPosterUrl;
    if (thumbs.isNotEmpty) {
      final last = thumbs.last as Map<String, dynamic>? ?? {};
      rawPosterUrl = (last['url'] ?? thumbs.first['url']) as String?;
    }

    return _MediaRecord(rawUrl: rawUrl, filename: filename, rawPosterUrl: rawPosterUrl);
  }

  /// Build the final CDN stream URL.
  ///
  /// JazzDrive returns a pre-signed CDN URL in `record.url`. This URL already
  /// contains a self-authenticating k= token (HMAC-signed, includes expiry).
  /// All we need to do is:
  ///   1. Prepend the cloud base URL if rawUrl is a relative path (starts with '/')
  ///   2. Append filename= for correct Content-Disposition headers (if not present)
  ///
  /// DO NOT append validationkey= to the CDN URL.
  /// The validationkey is used only for SAPI calls (/sapi/link/login and
  /// /sapi/media/video). The final CDN download URL is authenticated entirely
  /// by the k= token — adding validationkey= is incorrect and breaks the URL.
  static String _buildStreamUrl(String rawUrl, String filename) {
    var url = rawUrl.startsWith('/') ? '$_cloudBase$rawUrl' : rawUrl;
    if (!url.contains('filename=')) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url${sep}filename=${Uri.encodeComponent(filename)}';
    }
    return url;
  }

  static String? _buildPosterUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    return rawUrl.startsWith('/') ? '$_cloudBase$rawUrl' : rawUrl;
  }
}

// ── Internal data classes ─────────────────────────────────────────────────────

class _CacheEntry {
  final String streamUrl;
  final String? posterUrl;
  final DateTime expiresAt;
  const _CacheEntry({
    required this.streamUrl,
    this.posterUrl,
    required this.expiresAt,
  });
}

class _ShareSession {
  final String validationKey;
  final String cookie;
  const _ShareSession({required this.validationKey, required this.cookie});
}

class _MediaRecord {
  final String rawUrl;
  final String filename;
  final String? rawPosterUrl;
  const _MediaRecord({
    required this.rawUrl,
    required this.filename,
    this.rawPosterUrl,
  });
}
