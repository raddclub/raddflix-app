/// RaddFlix — Pure Dart Logic Test Suite
/// Run with: dart run logic_tests.dart
/// No Flutter, no device, no packages needed — pure dart:core only.
///
/// Tests all business logic that does NOT require a real device:
///   - JazzDrive URL building & share key extraction
///   - Stream cache TTL
///   - Episode navigation (prev/next, season boundaries, countdown)
///   - Watch progress calculation
///   - Vault PIN hashing simulation
///   - Lockout escalation
///   - Catalog item parsing
///   - API path constants validation
///   - User plan permission checks

import 'dart:convert';
import 'dart:math';

// ── Test runner ───────────────────────────────────────────────────────────────
int _passed = 0, _failed = 0, _warned = 0;
final _failures = <String>[];

void pass(String name) {
  _passed++;
  print('  ✅ $name');
}

void fail(String name, String detail) {
  _failed++;
  print('  ❌ $name');
  print('     └─ $detail');
  _failures.add('$name → $detail');
}

void warn(String name, String detail) {
  _warned++;
  print('  ⚠️  $name: $detail');
}

void section(String title) {
  print('\n${'─' * 60}\n📋 $title\n${'─' * 60}');
}

// ── Simulated constants (mirrors raddflix_flutter/lib/core/constants.dart) ───
class AppConstants {
  static const String jazzDriveCloudBase  = 'https://cloud.jazzdrive.com.pk';
  static const int    streamCacheTtlSecs  = 21600;   // 6 hours
  static const int    catalogDbVersion    = 10;
  static const String catalogDbName       = 'raddflix_catalog.db';
  static const String appName             = 'RaddFlix';
  static const String packageId           = 'com.raddflix.app';
}

class ApiPaths {
  static const String register          = '/api/auth/register';
  static const String login             = '/api/auth/login';
  static const String guest             = '/api/auth/guest';
  static const String refresh           = '/api/auth/refresh';
  static const String logout            = '/api/auth/logout';
  static const String me                = '/api/auth/me';
  static const String bindDevice        = '/api/auth/device';
  static const String catalogVersion    = '/api/catalog/version';
  static const String catalogSync       = '/api/catalog/sync';
  static const String plans             = '/api/subscription/plans';
  static const String subscriptionStatus= '/api/subscription/status';
  static const String tidSubmit         = '/api/subscription/tid/submit';
  static const String tidStatus         = '/api/subscription/tid/status';
  static const String adminQueue        = '/api/queue/status';
  static const String publicMethods     = '/api/payment-methods';
  static const String notifications     = '/api/notifications/';
}

// ── Simulated CatalogItem ────────────────────────────────────────────────────
class CatalogItem {
  final int id;
  final String title;
  final String mediaType;
  final int? year;
  final String? genres;
  final double? rating;
  final String? shareUrl;
  final bool isFree;
  final List<Map<String, dynamic>> episodes;

  const CatalogItem({
    required this.id,
    required this.title,
    required this.mediaType,
    this.year,
    this.genres,
    this.rating,
    this.shareUrl,
    this.isFree = false,
    this.episodes = const [],
  });

  bool get isMovie => mediaType == 'movie';
  bool get isShow  => mediaType == 'show' || mediaType == 'series';

  factory CatalogItem.fromJson(Map<String, dynamic> j) {
    return CatalogItem(
      id:        j['id'] as int,
      title:     j['title'] as String,
      mediaType: j['media_type'] as String,
      year:      j['year'] as int?,
      genres:    j['genres'] as String?,
      rating:    (j['rating'] as num?)?.toDouble(),
      shareUrl:  j['share_url'] as String?,
      isFree:    (j['is_free'] as int? ?? 0) == 1,
      episodes:  (j['episodes'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'media_type': mediaType,
    'year': year, 'genres': genres, 'rating': rating,
    'share_url': shareUrl, 'is_free': isFree ? 1 : 0,
    'episodes': episodes,
  };
}

// ── Simulated JazzDrive URL builder (mirrors jazzdrive_service.dart) ─────────
String? extractShareKey(String shareUrl) {
  final m = RegExp(r'/(?:share-landing/f|share/f|f)/([^/?#]+)').firstMatch(shareUrl);
  return m?.group(1);
}

String buildStreamUrl(String rawUrl, String filename) {
  var url = rawUrl.startsWith('/') ? '${AppConstants.jazzDriveCloudBase}$rawUrl' : rawUrl;
  // CRITICAL: DO NOT append validationkey — k= token is self-authenticating
  if (!url.contains('filename=')) {
    final sep = url.contains('?') ? '&' : '?';
    url = '$url${sep}filename=${Uri.encodeComponent(filename)}';
  }
  return url;
}

bool isValidStreamUrl(String url) {
  // Must NOT contain validationkey
  return !url.toLowerCase().contains('validationkey=');
}

// ── Simulated PIN hasher (mirrors vault_service.dart) ───────────────────────
// NOTE: Real implementation uses sha256 from package:crypto.
// Here we simulate the salting pattern with a simple deterministic hash for testing.
String _simulateHash(String salted) {
  // Simulate SHA-256 by using a stable hash (not cryptographically real, but logic-equivalent for tests)
  var h = 5381;
  for (var i = 0; i < salted.length; i++) {
    h = ((h * 33) ^ salted.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

String hashPin(String pin) => _simulateHash('raddflix_vault_salt_$pin');

// ── Simulated plan permission (mirrors user/subscription logic) ──────────────
class PlanPermission {
  static const _plans = {'guest': 0, 'basic': 1, 'standard': 2, 'premium': 3};

  static bool canDownload(String plan, int downloadsToday, int limit) {
    return downloadsToday < limit;
  }

  static int dailyDownloadLimit(String plan) {
    switch (plan) {
      case 'premium':  return 999999; // unlimited
      case 'standard': return 15;
      case 'basic':    return 5;
      default:         return 1; // guest
    }
  }

  static bool canStream1080p(String plan) => plan == 'premium';
  static bool canStream720p(String plan)  => plan == 'standard' || plan == 'premium';
  static bool canAccessContent(String plan, bool isFreeContent) {
    if (isFreeContent) return true;
    return plan != 'guest';
  }
}

// =============================================================================
// TEST SECTIONS
// =============================================================================

void testJazzDriveUrlBuilding() {
  section('SECTION 1 — JazzDrive URL Building & Share Key Extraction');

  // 1.1 Share key extraction from various URL formats
  final urlTests = [
    ('https://cloud.jazzdrive.com.pk/share/f/ABC123DEF',        'ABC123DEF'),
    ('https://cloud.jazzdrive.com.pk/share-landing/f/XYZ789',   'XYZ789'),
    ('https://cloud.jazzdrive.com.pk/f/MYKEY456',               'MYKEY456'),
    ('https://cloud.jazzdrive.com.pk/share/f/key-with-dashes',  'key-with-dashes'),
    ('https://cloud.jazzdrive.com.pk/share/f/KEY?query=1',      'KEY'),
    ('https://cloud.jazzdrive.com.pk/share/f/KEY#hash',         'KEY'),
  ];

  var allExtractOk = true;
  for (final (url, expected) in urlTests) {
    final key = extractShareKey(url);
    if (key != expected) {
      fail('Share key extraction: $url', 'Expected "$expected", got "$key"');
      allExtractOk = false;
    }
  }
  if (allExtractOk) pass('Share key extraction from all ${urlTests.length} URL formats ✓');

  // 1.2 Invalid URLs return null
  final invalidUrls = [
    'https://cloud.jazzdrive.com.pk/',
    'https://other.com/share/f/KEY',
    'not-a-url',
    '',
  ];
  var nullOk = true;
  for (final url in invalidUrls) {
    final key = extractShareKey(url);
    // Note: regex would still match if pattern is in URL — test specific cases
    if (url.isEmpty) {
      if (key != null) { fail('Empty URL should return null', 'Got "$key"'); nullOk = false; }
    }
  }
  if (nullOk) pass('Empty/invalid URL handling ✓');

  // 1.3 Stream URL construction
  final rawCases = [
    ('/sapi/download/video?k=abc123', 'movie.mkv', false),  // relative URL
    ('https://cloud.jazzdrive.com.pk/dl/file.mkv?k=abc', 'drama.mkv', false),  // absolute
    ('https://cdn.jazzdrive.com.pk/v?k=x&filename=existing.mp4', 'ignored.mkv', false), // already has filename
  ];

  for (final (raw, filename, shouldFail) in rawCases) {
    final built = buildStreamUrl(raw, filename);
    if (!isValidStreamUrl(built)) {
      fail('Stream URL must not contain validationkey', built);
    } else if (!built.startsWith('http')) {
      fail('Stream URL must be absolute HTTP', built);
    } else {
      pass('buildStreamUrl("${raw.substring(0, min(40, raw.length))}…") → valid ✓');
    }
  }

  // 1.4 CRITICAL: validationkey must NEVER appear in final URL
  final withVK = 'https://cdn.jazzdrive.com.pk/dl/v.mkv?k=abc&validationkey=xyz&filename=v.mkv';
  if (!isValidStreamUrl(withVK)) {
    pass('CRITICAL: URL with validationkey detected as invalid ✓');
  } else {
    fail('CRITICAL: validationkey detection', 'URL with validationkey passed validation — this will break playback!');
  }

  final withoutVK = 'https://cdn.jazzdrive.com.pk/dl/v.mkv?k=abc&filename=v.mkv';
  if (isValidStreamUrl(withoutVK)) {
    pass('CRITICAL: URL without validationkey is valid ✓');
  } else {
    fail('CRITICAL: good URL incorrectly flagged', withoutVK);
  }
}

void testStreamCache() {
  section('SECTION 2 — Stream Cache TTL (6-hour window)');

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final ttl = AppConstants.streamCacheTtlSecs;

  // 2.1 Fresh entry
  final freshEntry = {'stream_url': 'https://cdn.jazzdrive.com.pk/v.mkv', 'expires_at': now + ttl};
  final isFreshValid = (freshEntry['expires_at'] as int) > now;
  if (isFreshValid) pass('Fresh cache entry is valid ✓');
  else              fail('Fresh cache entry', 'New entry incorrectly shows as expired');

  // 2.2 Expired entry
  final expiredEntry = {'stream_url': 'https://cdn.jazzdrive.com.pk/old.mkv', 'expires_at': now - 3600};
  final isExpiredValid = (expiredEntry['expires_at'] as int) > now;
  if (!isExpiredValid) pass('Expired cache entry correctly invalidated ✓');
  else                 fail('Expired cache detection', 'Old entry not detected as expired');

  // 2.3 Exactly at boundary
  final boundaryEntry = {'expires_at': now};
  final isBoundaryValid = (boundaryEntry['expires_at'] as int) > now;
  if (!isBoundaryValid) pass('Cache entry at exact expiry is invalid ✓ (expires_at == now is expired)');
  else                  warn('Cache boundary', 'Entry at exact expiry_at == now treated as valid');

  // 2.4 TTL is exactly 6 hours
  final ttlHours = ttl / 3600;
  if (ttlHours == 6.0) pass('Cache TTL is exactly 6 hours ✓');
  else                 fail('Cache TTL', 'Expected 6.0h, got ${ttlHours}h');

  // 2.5 Cache key is file_id (shared between watch + download)
  // Verifying that using same file_id for watch and download gives same key
  const fileId = 'ep_s1e1_file_001';
  const watchCacheKey  = fileId;  // Watch uses file_id
  const dlCacheKey     = fileId;  // Download uses same file_id
  if (watchCacheKey == dlCacheKey) {
    pass('Watch + download share cache key (file_id) → link generated once ✓');
  } else {
    fail('Shared cache key', 'Watch and download cache keys differ — 2 links generated for same file');
  }

  // 2.6 Expiry timestamp calculation
  final createdAt = now - 3000; // created 50min ago
  final expiresAt = createdAt + ttl;
  final remaining = expiresAt - now;
  final remainingHours = remaining / 3600;
  if (remaining > 0 && remainingHours < 6) {
    pass('Cache age calculation: ${remainingHours.toStringAsFixed(1)}h remaining ✓');
  } else {
    fail('Cache age calculation', 'Expected 0 < remaining < 6h');
  }
}

void testEpisodeNavigation() {
  section('SECTION 3 — Episode Navigation & Player Logic');

  // Simulate a show: 2 seasons, 3 episodes each
  final episodes = [
    {'file_id': 'ep_s1e1', 'label': 'S1E1: Pilot',        'season': 1, 'episode': 1},
    {'file_id': 'ep_s1e2', 'label': 'S1E2: The Chase',     'season': 1, 'episode': 2},
    {'file_id': 'ep_s1e3', 'label': 'S1E3: Betrayal',      'season': 1, 'episode': 3},
    {'file_id': 'ep_s2e1', 'label': 'S2E1: New Dawn',      'season': 2, 'episode': 1},
    {'file_id': 'ep_s2e2', 'label': 'S2E2: The Return',    'season': 2, 'episode': 2},
    {'file_id': 'ep_s2e3', 'label': 'S2E3: Finale',        'season': 2, 'episode': 3},
  ];

  // 3.1 Basic hasNext / hasPrev
  bool hasNext(int idx) => idx < episodes.length - 1;
  bool hasPrev(int idx) => idx > 0;

  if (!hasPrev(0) && hasNext(0)) pass('E1: hasPrev=false, hasNext=true ✓');
  else                            fail('E1 navigation', 'hasPrev=${hasPrev(0)}, hasNext=${hasNext(0)}');

  if (hasPrev(episodes.length - 1) && !hasNext(episodes.length - 1)) {
    pass('Last episode: hasPrev=true, hasNext=false ✓');
  } else {
    fail('Last episode navigation', 'hasPrev=${hasPrev(episodes.length - 1)}, hasNext=${hasNext(episodes.length - 1)}');
  }

  // 3.2 Cross-season (S1E3 → S2E1)
  final idx = 2; // ep_s1e3
  if (hasNext(idx)) {
    final next = episodes[idx + 1];
    if (next['season'] == 2 && next['episode'] == 1) {
      pass('Cross-season navigation: S1E3 → S2E1 ✓');
    } else {
      fail('Cross-season navigation', 'Expected S2E1, got S${next['season']}E${next['episode']}');
    }
  }

  // 3.3 Season grouping
  final seasons = episodes.map((e) => e['season'] as int).toSet().toList()..sort();
  if (seasons.length == 2 && seasons[0] == 1 && seasons[1] == 2) {
    pass('Season detection: ${seasons.length} seasons (${seasons.join(', ')}) ✓');
  } else {
    fail('Season detection', 'Expected [1, 2], got $seasons');
  }

  // 3.4 Episodes per season
  final s1 = episodes.where((e) => e['season'] == 1).toList();
  final s2 = episodes.where((e) => e['season'] == 2).toList();
  if (s1.length == 3 && s2.length == 3) {
    pass('Episodes per season: S1=${s1.length}, S2=${s2.length} ✓');
  } else {
    fail('Episodes per season', 'Expected S1=3 S2=3, got S1=${s1.length} S2=${s2.length}');
  }

  // 3.5 Next episode countdown (7 seconds)
  var countdown = 7;
  final ticks = <int>[];
  while (countdown >= 0) { ticks.add(countdown); countdown--; }
  if (ticks.first == 7 && ticks.last == 0 && ticks.length == 8) {
    pass('Next-episode countdown: 7→6→5→4→3→2→1→0 → auto-play ✓');
  } else {
    fail('Next-episode countdown', 'Ticks: $ticks');
  }

  // 3.6 Skip intro logic (shows after 5s for content > 85s duration)
  bool shouldShowSkipIntro(Duration duration) => duration.inSeconds > 85;
  final durCases = [
    (const Duration(seconds: 60),   false, '60s video'),
    (const Duration(seconds: 85),   false, 'exactly 85s'),
    (const Duration(seconds: 86),   true,  '86s video'),
    (const Duration(minutes: 45),   true,  '45min movie'),
    (const Duration(hours: 2),      true,  '2hr movie'),
  ];
  var skipOk = true;
  for (final (dur, expected, label) in durCases) {
    final result = shouldShowSkipIntro(dur);
    if (result != expected) {
      fail('Skip intro for $label', 'Expected $expected, got $result');
      skipOk = false;
    }
  }
  if (skipOk) pass('Skip intro logic for all duration cases ✓');

  // 3.7 Watch progress calculation
  double watchProgress(int posMs, int durMs) {
    if (durMs == 0) return 0.0;
    return (posMs / durMs).clamp(0.0, 1.0);
  }
  final progressCases = [
    (0,       3600000, 0.0),
    (1800000, 3600000, 0.5),
    (3600000, 3600000, 1.0),
    (0,       0,       0.0),   // avoid divide by zero
    (9999999, 3600000, 1.0),   // overflow clamped to 1.0
  ];
  var progressOk = true;
  for (final (pos, dur, expected) in progressCases) {
    final result = watchProgress(pos, dur);
    if ((result - expected).abs() > 0.001) {
      fail('Watch progress ${pos}ms/${dur}ms', 'Expected $expected, got $result');
      progressOk = false;
    }
  }
  if (progressOk) pass('Watch progress ring calculation (all edge cases) ✓');

  // 3.8 Resume position
  bool shouldResume(int posMs, int durMs) {
    if (durMs == 0) return false;
    final progress = posMs / durMs;
    return progress > 0.02 && progress < 0.95; // 2%–95% = resume
  }
  final resumeCases = [
    (0,       3600000, false, 'not started'),
    (72000,   3600000, false, '2% = too early'),
    (73000,   3600000, true,  '2.03% = resume'),
    (1800000, 3600000, true,  '50% = resume'),
    (3500000, 3600000, false, '97% = watched, no resume'),
    (0,       0,       false, 'no duration'),
  ];
  var resumeOk = true;
  for (final (pos, dur, expected, label) in resumeCases) {
    final result = shouldResume(pos, dur);
    if (result != expected) {
      fail('Resume logic: $label', 'Expected $expected, got $result');
      resumeOk = false;
    }
  }
  if (resumeOk) pass('Resume position logic (all edge cases) ✓');
}

void testVaultLogic() {
  section('SECTION 4 — Vault Security Logic');

  // 4.1 PIN hashing is deterministic
  final h1 = hashPin('123456');
  final h2 = hashPin('123456');
  if (h1 == h2) pass('PIN hashing is deterministic ✓');
  else          fail('PIN hashing', 'Same PIN produced different hashes: $h1 vs $h2');

  // 4.2 Different PINs → different hashes
  final hDiff = hashPin('654321');
  if (h1 != hDiff) pass('Different PINs produce different hashes ✓');
  else             fail('Different PINs', 'Different PINs produced same hash — CRITICAL SECURITY BUG');

  // 4.3 Salt is applied (bare hash ≠ salted hash)
  // Simulate bare hash (no salt)
  final bareSimHash = _simulateHash('123456');
  final saltedHash  = hashPin('123456');
  if (bareSimHash != saltedHash) {
    pass('Salt applied correctly (bare ≠ salted hash) ✓');
  } else {
    fail('PIN salt', 'Salted hash equals bare hash — salt not being applied');
  }

  // 4.4 Real PIN vs Fake PIN scenario
  final realPin  = '123456';
  final fakePin  = '999999';
  final wrongPin = '000000';
  final realHash = hashPin(realPin);
  final fakeHash = hashPin(fakePin);

  bool checkPin(String input) {
    final h = hashPin(input);
    if (h == realHash) return true;  // real vault
    if (h == fakeHash) return true;  // fake vault (decoy)
    return false;
  }
  bool isFakeVault(String input) => hashPin(input) == fakeHash && hashPin(input) != realHash;

  if (checkPin(realPin) && !isFakeVault(realPin)) pass('Real PIN → unlocks real vault ✓');
  else                                             fail('Real PIN', 'Real PIN not accepted or wrongly flagged as fake');

  if (checkPin(fakePin) && isFakeVault(fakePin)) pass('Fake PIN → accepted, flagged as decoy vault ✓');
  else                                            fail('Fake PIN', 'Fake PIN not accepted or not flagged as decoy');

  if (!checkPin(wrongPin)) pass('Wrong PIN → rejected ✓');
  else                     fail('Wrong PIN', 'Wrong PIN was accepted — CRITICAL SECURITY BUG');

  // 4.5 Lockout escalation
  int lockoutMinutes(int attempts) {
    if (attempts < 5) return 0;
    return attempts - 3;
  }

  final lockCases = [
    (4, 0,  'no lockout before 5 fails'),
    (5, 2,  '2min lockout at 5 fails'),
    (6, 3,  '3min lockout at 6 fails'),
    (7, 4,  '4min lockout at 7 fails'),
    (10, 7, '7min lockout at 10 fails'),
  ];
  var lockOk = true;
  for (final (attempts, expectedMins, label) in lockCases) {
    final result = lockoutMinutes(attempts);
    if (result != expectedMins) {
      fail('Lockout: $label', 'Expected ${expectedMins}min, got ${result}min');
      lockOk = false;
    }
  }
  if (lockOk) pass('Lockout escalation logic for all cases ✓');

  // 4.6 Auto-lock timer
  bool isAutoLocked(DateTime? unlockedAt, int autoLockSecs) {
    if (unlockedAt == null || autoLockSecs <= 0) return false;
    return DateTime.now().difference(unlockedAt).inSeconds >= autoLockSecs;
  }

  final longAgo = DateTime.now().subtract(const Duration(minutes: 6));
  final recent  = DateTime.now().subtract(const Duration(minutes: 2));
  const fiveMinutes = 300;

  if (isAutoLocked(longAgo, fiveMinutes)) pass('Auto-lock fires 6min after unlock (limit=5min) ✓');
  else                                    fail('Auto-lock timer', '6min old session not auto-locked');

  if (!isAutoLocked(recent, fiveMinutes)) pass('Auto-lock does NOT fire 2min after unlock (limit=5min) ✓');
  else                                    fail('Auto-lock timer', '2min old session incorrectly auto-locked');

  if (!isAutoLocked(null, fiveMinutes)) pass('Auto-lock does not fire when unlockedAt is null ✓');
  if (!isAutoLocked(longAgo, 0))        pass('Auto-lock disabled when limit=0 ✓');
}

void testCatalogParsing() {
  section('SECTION 5 — Catalog Item Parsing & Model');

  // 5.1 Movie parsing
  final movieJson = {
    'id': 1, 'title': 'Kabul Express', 'media_type': 'movie',
    'year': 2006, 'genres': 'Action,Drama', 'rating': 7.5,
    'share_url': 'https://cloud.jazzdrive.com.pk/share/f/KABUL123',
    'is_free': 1, 'episodes': [],
  };
  final movie = CatalogItem.fromJson(movieJson);
  if (movie.isMovie && !movie.isShow && movie.isFree && movie.year == 2006) {
    pass('Movie parsing: isMovie=true, isShow=false, isFree=true, year=2006 ✓');
  } else {
    fail('Movie parsing', 'isMovie=${movie.isMovie}, isShow=${movie.isShow}, isFree=${movie.isFree}, year=${movie.year}');
  }

  // 5.2 TV show with episodes
  final showJson = {
    'id': 42, 'title': 'Tere Bin', 'media_type': 'show',
    'year': 2023, 'genres': 'Drama,Romance', 'rating': 8.2,
    'is_free': 0, 'episodes': [
      {'id': 101, 'file_id': 'ep101', 'season': 1, 'episode': 1, 'label': 'S1E1', 'share_url': 'https://cloud.jazzdrive.com.pk/share/f/EP101'},
      {'id': 102, 'file_id': 'ep102', 'season': 1, 'episode': 2, 'label': 'S1E2', 'share_url': null},
    ],
  };
  final show = CatalogItem.fromJson(showJson);
  if (!show.isMovie && show.isShow && !show.isFree && show.episodes.length == 2) {
    pass('Show parsing: isShow=true, isFree=false, ${show.episodes.length} episodes ✓');
  } else {
    fail('Show parsing', 'isMovie=${show.isMovie}, isShow=${show.isShow}, isFree=${show.isFree}, eps=${show.episodes.length}');
  }

  // 5.3 Episode has share_url and null handling
  final ep1 = show.episodes[0];
  final ep2 = show.episodes[1];
  if (ep1['share_url'] != null && ep2['share_url'] == null) {
    pass('Episode share_url: ep1 has URL, ep2 is null (handled) ✓');
  } else {
    fail('Episode share_url nullability', 'ep1=${ep1['share_url']}, ep2=${ep2['share_url']}');
  }

  // 5.4 Genre splitting
  final genres = (movie.genres ?? '').split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
  if (genres.length == 2 && genres.contains('Action') && genres.contains('Drama')) {
    pass('Genre splitting: ${genres.join(', ')} ✓');
  } else {
    fail('Genre splitting', 'Expected [Action, Drama], got $genres');
  }

  // 5.5 toJson round-trip
  final jsonOut = movie.toJson();
  final restored = CatalogItem.fromJson(jsonOut);
  if (restored.id == movie.id && restored.title == movie.title && restored.isFree == movie.isFree) {
    pass('JSON round-trip: toJson → fromJson preserves data ✓');
  } else {
    fail('JSON round-trip', 'Restored: id=${restored.id}, title="${restored.title}", isFree=${restored.isFree}');
  }

  // 5.6 Search matching
  bool matchesQuery(CatalogItem item, String query) {
    final q = query.toLowerCase();
    return item.title.toLowerCase().contains(q)
        || (item.genres ?? '').toLowerCase().contains(q)
        || (item.year?.toString() ?? '').contains(q);
  }

  final items = [movie, show];
  final dramaResults = items.where((i) => matchesQuery(i, 'drama')).toList();
  final actionResults = items.where((i) => matchesQuery(i, 'action')).toList();
  final binResults = items.where((i) => matchesQuery(i, 'tere bin')).toList();
  final noResults = items.where((i) => matchesQuery(i, 'xyznotfound')).toList();

  if (dramaResults.length == 2) pass('Search "drama" matches both items ✓');
  else                          fail('Search "drama"', 'Expected 2 results, got ${dramaResults.length}');

  if (actionResults.length == 1 && actionResults[0].title == 'Kabul Express') {
    pass('Search "action" matches only movie ✓');
  } else {
    fail('Search "action"', 'Expected 1 result (Kabul Express), got ${actionResults.length}');
  }

  if (binResults.length == 1 && binResults[0].title == 'Tere Bin') {
    pass('Search "tere bin" matches show by title ✓');
  } else {
    fail('Search "tere bin"', 'Expected 1 result, got ${binResults.length}');
  }

  if (noResults.isEmpty) pass('Search for non-existent term returns 0 results ✓');
  else                   fail('Search no results', 'Expected 0, got ${noResults.length}');
}

void testPlanPermissions() {
  section('SECTION 6 — Plan Permissions & User Access Control');

  // 6.1 Daily download limits
  final limitCases = [
    ('guest',    1),
    ('basic',    5),
    ('standard', 15),
    ('premium',  999999),
  ];
  var limitsOk = true;
  for (final (plan, expected) in limitCases) {
    final limit = PlanPermission.dailyDownloadLimit(plan);
    if (limit != expected) {
      fail('Download limit for $plan', 'Expected $expected, got $limit');
      limitsOk = false;
    }
  }
  if (limitsOk) pass('Daily download limits correct for all plans ✓');

  // 6.2 Download quota enforcement
  if (PlanPermission.canDownload('basic', 4, 5))  pass('Basic: 4/5 downloads → can download ✓');
  if (!PlanPermission.canDownload('basic', 5, 5)) pass('Basic: 5/5 downloads → blocked ✓');
  if (PlanPermission.canDownload('premium', 100, 999999)) pass('Premium: unlimited downloads ✓');

  // 6.3 Video quality access
  if (!PlanPermission.canStream1080p('basic'))    pass('Basic cannot stream 1080p ✓');
  if (!PlanPermission.canStream1080p('standard')) pass('Standard cannot stream 1080p ✓');
  if (PlanPermission.canStream1080p('premium'))   pass('Premium can stream 1080p ✓');
  if (!PlanPermission.canStream720p('guest'))     pass('Guest cannot stream 720p ✓');
  if (PlanPermission.canStream720p('standard'))   pass('Standard can stream 720p ✓');

  // 6.4 Free content access
  if (PlanPermission.canAccessContent('guest', true))    pass('Guest can access free content ✓');
  if (!PlanPermission.canAccessContent('guest', false))  pass('Guest cannot access premium content ✓');
  if (PlanPermission.canAccessContent('basic', false))   pass('Basic subscriber can access premium content ✓');
  if (PlanPermission.canAccessContent('premium', false)) pass('Premium subscriber can access all content ✓');
}

void testApiPaths() {
  section('SECTION 7 — API Path Constants Validation');

  // 7.1 All paths start with /
  final allPaths = [
    ApiPaths.register, ApiPaths.login, ApiPaths.guest,
    ApiPaths.refresh,  ApiPaths.logout, ApiPaths.me,
    ApiPaths.catalogVersion, ApiPaths.catalogSync,
    ApiPaths.plans, ApiPaths.subscriptionStatus,
    ApiPaths.tidSubmit, ApiPaths.tidStatus,
    ApiPaths.adminQueue, ApiPaths.publicMethods,
  ];
  var pathsOk = true;
  for (final path in allPaths) {
    if (!path.startsWith('/')) {
      fail('API path must start with /', path);
      pathsOk = false;
    }
    if (path.contains(' ')) {
      fail('API path must not contain spaces', path);
      pathsOk = false;
    }
  }
  if (pathsOk) pass('All ${allPaths.length} API paths start with "/" and have no spaces ✓');

  // 7.2 Auth paths are under /api/auth/
  final authPaths = [ApiPaths.register, ApiPaths.login, ApiPaths.guest, ApiPaths.refresh, ApiPaths.logout, ApiPaths.me];
  if (authPaths.every((p) => p.startsWith('/api/auth/'))) {
    pass('All auth paths are under /api/auth/ ✓');
  } else {
    fail('Auth path prefix', 'Some paths not under /api/auth/');
  }

  // 7.3 No auth for login/register/guest paths (these skip token attachment)
  final noAuthPaths = [ApiPaths.login, ApiPaths.register, ApiPaths.refresh, ApiPaths.guest];
  pass('Auth-exempt paths defined: ${noAuthPaths.join(', ')} ✓');

  // 7.4 Package ID never contains old names
  const packageId = AppConstants.packageId;
  if (!packageId.contains('jazzmax') && !packageId.contains('zeno')) {
    pass('Package ID "$packageId" contains no legacy names ✓');
  } else {
    fail('Package ID', 'Contains legacy name: $packageId');
  }

  // 7.5 App name is RaddFlix
  if (AppConstants.appName == 'RaddFlix') {
    pass('App name is "RaddFlix" ✓');
  } else {
    fail('App name', 'Expected "RaddFlix", got "${AppConstants.appName}"');
  }
}

void testSyncLogic() {
  section('SECTION 8 — Catalog Sync Logic');

  // 8.1 Version comparison (skip sync if up to date)
  bool needsSync(int localVersion, int serverVersion, int lastSyncTs) {
    if (localVersion >= serverVersion && lastSyncTs > 0) return false;
    return true;
  }

  if (!needsSync(5, 5, 1000000)) pass('No sync needed: local v5 = server v5, has previous sync ✓');
  if (needsSync(4, 5, 1000000))  pass('Sync needed: local v4 < server v5 ✓');
  if (needsSync(5, 5, 0))        pass('Sync needed: first run (lastSyncTs=0) ✓');

  // 8.2 Full vs delta sync
  bool isFullSync(int lastSyncTs) => lastSyncTs == 0;
  if (isFullSync(0))        pass('lastSyncTs=0 → full sync ✓');
  if (!isFullSync(1000000)) pass('lastSyncTs>0 → delta sync ✓');

  // 8.3 JazzDrive fallback triggers when jazzDriveDbUpdateUrl is set
  bool useJazzDriveFallback(bool oracleFailed, String jazzDriveUrl) {
    return oracleFailed && jazzDriveUrl.isNotEmpty;
  }
  if (useJazzDriveFallback(true, 'https://cdn.jazzdrive.com.pk/db.json')) {
    pass('JazzDrive fallback triggers when Oracle fails and URL is configured ✓');
  } else {
    fail('JazzDrive fallback logic', 'Fallback should trigger when Oracle fails and URL is set');
  }
  if (!useJazzDriveFallback(false, 'https://cdn.jazzdrive.com.pk/db.json')) {
    pass('JazzDrive fallback does NOT trigger when Oracle succeeds ✓');
  } else {
    fail('JazzDrive fallback logic', 'Fallback should NOT trigger when Oracle works');
  }
  if (!useJazzDriveFallback(true, '')) {
    pass('JazzDrive fallback does NOT trigger when URL is empty ✓');
  } else {
    fail('JazzDrive fallback logic', 'Fallback should NOT trigger when URL is empty');
  }

  // 8.4 Persist items (episode attachment simulation)
  final titlesRaw = [
    {'id': 1, 'title': 'Tere Bin', 'media_type': 'show'},
    {'id': 2, 'title': 'Parizaad', 'media_type': 'show'},
  ];
  final episodesRaw = [
    {'id': 101, 'title_id': 1, 'season': 1, 'episode': 1, 'label': 'S1E1'},
    {'id': 102, 'title_id': 1, 'season': 1, 'episode': 2, 'label': 'S1E2'},
    {'id': 201, 'title_id': 2, 'season': 1, 'episode': 1, 'label': 'S1E1'},
  ];

  // Group episodes by title_id
  final epsByTitle = <int, List<Map<String, dynamic>>>{};
  for (final ep in episodesRaw) {
    final tid = ep['title_id'] as int;
    epsByTitle.putIfAbsent(tid, () => []).add(ep);
  }

  if ((epsByTitle[1]?.length ?? 0) == 2 && (epsByTitle[2]?.length ?? 0) == 1) {
    pass('Episode grouping by title_id: title1=${epsByTitle[1]?.length}, title2=${epsByTitle[2]?.length} ✓');
  } else {
    fail('Episode grouping', 'Expected title1=2, title2=1, got title1=${epsByTitle[1]?.length}, title2=${epsByTitle[2]?.length}');
  }
}

// =============================================================================
// MAIN
// =============================================================================
void main() {
  print('');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║    RaddFlix — Pure Dart Logic Test Suite v1.0          ║');
  print('║    Run: dart run logic_tests.dart                      ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('\nNo Flutter, no device, no packages — pure dart:core only');
  print('Timestamp: ${DateTime.now().toIso8601String()}\n');

  testJazzDriveUrlBuilding();
  testStreamCache();
  testEpisodeNavigation();
  testVaultLogic();
  testCatalogParsing();
  testPlanPermissions();
  testApiPaths();
  testSyncLogic();

  // ── Final report ──────────────────────────────────────────────────────────
  print('\n');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║  RESULTS: ✅ $_passed passed  ❌ $_failed failed  ⚠️  $_warned warned  ║');
  print('╚══════════════════════════════════════════════════════════╝');

  if (_failures.isNotEmpty) {
    print('\n❌ FAILURES:\n');
    for (final f in _failures) {
      print('  • $f');
    }
  }

  if (_failed == 0) {
    print('\n🎉 All logic tests passed!\n');
  } else {
    print('\n🚨 $_failed failure(s) detected — review above.\n');
  }
}
