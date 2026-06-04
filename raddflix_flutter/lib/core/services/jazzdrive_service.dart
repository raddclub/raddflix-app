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
///   4. Cache result for 6 hours (shared between watch + download)
class JazzDriveService {
  static const String _cloudBase = 'https://cloud.jazzdrive.com.pk';
  // FIX-TTL: CDN tokens expire in ~1-2h — 180 min cache reduces re-fetches while staying safe
    static const Duration _cacheTtl = Duration(minutes: 180);

  static final _inMemory = <String, _CacheEntry>{};

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
  static Future<JazzDriveLink> getStreamLink(
    String fileId,
    String shareUrl, {
    int? titleId,
    String? targetFilename,
  }) async {
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
    DebugLogger.log('JAZZDRIVE', 'Generating fresh link for file $fileId');
    final link = await _generateLink(shareUrl, targetFilename: targetFilename);

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


  /// Pre-warm the stream-link cache for the top [count] free movies.
  ///
  /// Fire-and-forget: call with [unawaited] so it never delays app launch
  /// or UI rendering. Queries SQLite for the top [count] is_free=1 movie
  /// titles ordered by db_version DESC, then calls [getStreamLink] for each.
  ///
  /// Because [getStreamLink] honours the existing 180-min TTL the warm step
  /// is a no-op for items already cached — zero extra network calls within
  /// the TTL window. On Jazz SIM all SAPI calls go directly to
  /// cloud.jazzdrive.com.pk (zero-rated). Silently swallows all errors so
  /// an offline device or unreachable JazzDrive never surfaces to the user.
  ///
  /// AUDIT-09: called from multiple sites (main.dart, Oracle sync, JazzDrive sync).
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

  static Future<JazzDriveLink> _generateLink(String shareUrl, {String? targetFilename}) async {
    // Extract share key from URL
    final shareKey = _extractShareKey(shareUrl);
    if (shareKey == null) {
      throw Exception('Invalid JazzDrive share URL: $shareUrl');
    }

    // Step 1: Login to share session → get validationKey + JSESSIONID cookie
    final session = await _loginShare(shareKey);

    // Step 2: Get video media list → get CDN URL + poster
    final record = await _getMedia(shareKey, session.validationKey, session.cookie, targetFilename: targetFilename);

    // Step 3: Build final URL (DO NOT add validationkey — k= token is self-signing)
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

    final resp = await _dio.post<Map<String, dynamic>>(
      loginUrl,
      data: {'data': {'accesstoken': shareKey}},
      options: Options(headers: headers),
    );

    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('JazzDrive login failed: HTTP ${resp.statusCode}');
    }

    final data = resp.data!;
    final inner = (data['data'] as Map<String, dynamic>?) ?? data;
    final vk = (inner['validationkey'] ?? inner['validationKey'] ?? inner['validation_key']
                ?? data['validationkey'] ?? data['validationKey']) as String?;

    if (vk == null || vk.isEmpty) {
      throw Exception('JazzDrive login: no validationkey in response');
    }

    // Extract JSESSIONID from Set-Cookie header
    final rawHeaders = resp.headers.map;
    final setCookieList = rawHeaders['set-cookie'] ?? [];
    String cookie = '';
    for (final c in setCookieList) {
      final m = RegExp(r'JSESSIONID=([^;]+)').firstMatch(c);
      if (m != null) {
        cookie = 'JSESSIONID=${m.group(1)}';
        break;
      }
    }

    return _ShareSession(validationKey: vk, cookie: cookie);
  }

  static Future<_MediaRecord> _getMedia(
    String shareKey,
    String validationKey,
    String cookie, {
    String? targetFilename,
  }) async {
    final mediaUrl = '$_cloudBase/sapi/media/video'
        '?action=get&shared=true'
        '&key=${Uri.encodeComponent(shareKey)}'
        '&validationkey=${Uri.encodeComponent(validationKey)}';

    final headers = Map<String, String>.from(_baseHeaders)
      ..['Referer'] = '$_cloudBase/share/f/$shareKey'
      ..['validation_key'] = validationKey;
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;

    final resp = await _dio.get<dynamic>(
      mediaUrl,
      options: Options(headers: headers),
    );

    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('JazzDrive media fetch failed: HTTP ${resp.statusCode}');
    }

    final body = resp.data is String
        ? json.decode(resp.data as String) as Map<String, dynamic>
        : resp.data as Map<String, dynamic>;

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

    // 3-pass filename match so folder-shares (e.g. Off Campus) pick the right episode.
    // Falls back to records.first for single-file shares.
    String _rname(dynamic r) =>
        ((r as Map<String, dynamic>)['name'] ?? r['filename'] ?? '') as String;
    Map<String, dynamic>? rec;
    if (targetFilename != null && targetFilename.isNotEmpty) {
      final tgt = targetFilename.toLowerCase();
      // Pass 1: exact case-insensitive substring
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
      // Pass 3: episode code match — e.g. "s01e04" anywhere in filename
      if (rec == null) {
        final em = RegExp(r's(\d{1,2})e(\d{1,2})', caseSensitive: false).firstMatch(tgt);
        if (em != null) {
          final code = 's\${em.group(1)!.padLeft(2, "0")}e\${em.group(2)!.padLeft(2, "0")}';
          for (final r in records) {
            if (_rname(r).toLowerCase().contains(code)) { rec = r as Map<String, dynamic>; break; }
          }
        }
      }
    }
    rec ??= records.first as Map<String, dynamic>;
    final rawUrl = (rec['url'] ?? rec['downloadUrl'] ?? rec['download_url'] ?? '') as String;
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

  static String _buildStreamUrl(String rawUrl, String filename) {
    var url = rawUrl.startsWith('/') ? '$_cloudBase$rawUrl' : rawUrl;
    // Append real filename (with correct extension like .mkv)
    // DO NOT append validationkey — the k= token is self-authenticating
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
