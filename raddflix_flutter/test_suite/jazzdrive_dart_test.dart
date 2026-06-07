/// RaddFlix — JazzDrive Link Generation Integration Test
/// Makes REAL HTTP calls to cloud.jazzdrive.com.pk using real share URLs
/// from the Oracle DB. Tests the exact same logic as jazzdrive_service.dart.
///
/// Run: dart run jazzdrive_dart_test.dart
/// CI:  dart run raddflix_flutter/test_suite/jazzdrive_dart_test.dart
///
/// No Flutter, no packages — only dart:io + dart:convert.

import 'dart:convert';
import 'dart:io';

const String _cloudBase = 'https://cloud.jazzdrive.com.pk';

// =============================================================================
// Test cases — real data from Oracle radd_hub.db (queried 2026-06-07)
// =============================================================================
final List<Map<String, dynamic>> _tests = [

  // ── Movies (single file per share) ────────────────────────────────────────
  {
    'name': 'Movie | Swapped (2026) — Pass 0 by remote_id',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/WGSUU9PgTLaxqqQHYGHjhTc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Swapped (2026).mp4',
    'remoteId': 242518532,
    'expectFilenameContains': 'swapped',
    'note': 'Single-file movie — Pass 0 matches by remote_id',
  },
  {
    'name': 'Movie | Swapped (2026) — Pass 1 substring (no remote_id)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/WGSUU9PgTLaxqqQHYGHjhTc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Swapped (2026).mp4',
    'remoteId': 0,
    'expectFilenameContains': 'swapped',
    'note': 'Same movie — skips Pass 0, must match via Pass 1 substring',
  },
  {
    'name': 'Movie | Luka Chuppi (2019) — Pass 0 by remote_id',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/fTDjCGqPTwS0_Mq6G-LtIzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Luka Chuppi (2019).mp4',
    'remoteId': 242527434,
    'expectFilenameContains': 'luka',
    'note': 'Single-file movie — Pass 0',
  },

  // ── TV Episodes (Vincenzo — 2 files in SAME share folder) ─────────────────
  {
    'name': 'TV | Vincenzo S01E01 — Pass 0 by remote_id',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E01.mp4',
    'remoteId': 242518574,
    'expectFilenameContains': 'vincenzo',
    'mustContainEpisodeCode': 's01e01',
    'note': 'Season folder with 2 files — Pass 0 picks E01 by remote_id',
  },
  {
    'name': 'TV | Vincenzo S01E02 — Pass 0 by remote_id (CRITICAL: must NOT return E01)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E02.mp4',
    'remoteId': 242531168,
    'expectFilenameContains': 'vincenzo',
    'mustContainEpisodeCode': 's01e02',
    'note': 'Same share folder as E01 — Pass 0 must return E02, not E01',
  },
  {
    'name': 'TV | Vincenzo S01E02 — Pass 3 episode code (no remote_id)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E02.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'vincenzo',
    'mustContainEpisodeCode': 's01e02',
    'note': 'No remote_id — Pass 3 must extract s01e02 and find E02, not E01',
  },

  // ── TV Episodes (Spider-Noir — 2 files in SAME share folder) ──────────────
  {
    'name': 'TV | Spider-Noir S01E01 — Pass 3 episode code (no remote_id)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Spider Noir S01E01.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'spider',
    'mustContainEpisodeCode': 's01e01',
    'note': 'Season folder — no remote_id, Pass 3 picks E01 by episode code',
  },
  {
    'name': 'TV | Spider-Noir S01E02 — Pass 3 episode code (no remote_id, CRITICAL)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Spider Noir S01E02.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'spider',
    'mustContainEpisodeCode': 's01e02',
    'note': 'No remote_id — Pass 3 must pick E02, not E01 (the records.first fallback)',
  },
];

// =============================================================================
// Core logic — mirrors jazzdrive_service.dart exactly
// =============================================================================

String? _extractShareKey(String shareUrl) {
  final m = RegExp(r'/(?:share-landing/f|share/f|f)/([^/?#]+)').firstMatch(shareUrl);
  return m?.group(1);
}

Future<Map<String, String>> _loginShare(String shareKey) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final uri = Uri.parse('$_cloudBase/sapi/link/login?action=login');
    final req = await client.postUrl(uri);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set('Content-Type', 'application/json;charset=UTF-8');
    req.headers.set('Origin', _cloudBase);
    req.headers.set('Referer', '$_cloudBase/share/f/$shareKey');
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36');
    req.headers.set('X-Requested-With', 'com.jazz.drive');

    final body = jsonEncode({'data': {'accesstoken': shareKey}});
    req.contentLength = utf8.encode(body).length;
    req.write(body);

    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();

    if (resp.statusCode != 200) {
      throw Exception('login HTTP ${resp.statusCode}: ${respBody.substring(0, respBody.length.clamp(0, 300))}');
    }

    final data = jsonDecode(respBody) as Map<String, dynamic>;
    final inner = (data['data'] as Map<String, dynamic>?) ?? data;

    final vk = (inner['validationkey'] ??
            inner['validationKey'] ??
            inner['validation_key'] ??
            data['validationkey'] ??
            data['validationKey']) as String?;

    if (vk == null || vk.isEmpty) {
      throw Exception('no validationkey in login response: $respBody');
    }

    // Extract JSESSIONID from Set-Cookie
    String cookie = '';
    resp.headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') {
        for (final v in values) {
          final m = RegExp(r'JSESSIONID=([^;]+)').firstMatch(v);
          if (m != null && cookie.isEmpty) {
            cookie = 'JSESSIONID=${m.group(1)}';
          }
        }
      }
    });

    return {'validationKey': vk, 'cookie': cookie};
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _getMedia(
  String shareKey,
  String validationKey,
  String cookie, {
  String? targetFilename,
  int remoteId = 0,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final uri = Uri.parse('$_cloudBase/sapi/media/video'
        '?action=get&shared=true'
        '&key=${Uri.encodeComponent(shareKey)}'
        '&validationkey=${Uri.encodeComponent(validationKey)}');

    final req = await client.getUrl(uri);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set('Origin', _cloudBase);
    req.headers.set('Referer', '$_cloudBase/share/f/$shareKey');
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36');
    req.headers.set('X-Requested-With', 'com.jazz.drive');
    req.headers.set('validation_key', validationKey);
    if (cookie.isNotEmpty) req.headers.set('Cookie', cookie);

    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();

    if (resp.statusCode != 200) {
      throw Exception('media HTTP ${resp.statusCode}: ${respBody.substring(0, respBody.length.clamp(0, 300))}');
    }

    final Map<String, dynamic> body = jsonDecode(respBody) as Map<String, dynamic>;

    // Parse records list — same multi-shape logic as jazzdrive_service.dart
    List<dynamic> records = [];
    final rawBody = body['data'] ?? body;
    final d = rawBody is Map<String, dynamic> ? rawBody : body;

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
      throw Exception('no video records found in response');
    }

    String rname(dynamic r) =>
        ((r as Map<String, dynamic>)['name'] ?? r['filename'] ?? '') as String;

    print('    records in folder: ${records.length} → [${records.map(rname).join(', ')}]');

    // Pass 0: match by JazzDrive remote_id
    Map<String, dynamic>? rec;
    if (remoteId > 0) {
      for (final r in records) {
        final m = r as Map<String, dynamic>;
        final rid = (m['id'] ?? m['fileId'] ?? m['file_id'] ?? 0);
        final ridInt = rid is int ? rid : int.tryParse(rid.toString()) ?? 0;
        if (ridInt == remoteId) {
          rec = m;
          print('    Pass 0 → matched by remote_id=$remoteId: "${rname(m)}"');
          break;
        }
      }
    }

    // Passes 1-3: filename-based fallback
    if (rec == null && targetFilename != null && targetFilename.isNotEmpty) {
      final tgt = targetFilename.toLowerCase();

      // Pass 1: case-insensitive substring
      for (final r in records) {
        final n = rname(r).toLowerCase();
        if (n.contains(tgt) || tgt.contains(n)) {
          rec = r as Map<String, dynamic>;
          print('    Pass 1 → substring match: "${rname(r)}"');
          break;
        }
      }

      // Pass 2: dots/underscores normalised to spaces
      if (rec == null) {
        String norm(String s) => s.replaceAll(RegExp(r'[._]'), ' ').toLowerCase();
        for (final r in records) {
          final n = norm(rname(r));
          if (n.contains(norm(tgt)) || norm(tgt).contains(n)) {
            rec = r as Map<String, dynamic>;
            print('    Pass 2 → normalised match: "${rname(r)}"');
            break;
          }
        }
      }

      // Pass 3: episode code e.g. "s01e04"
      if (rec == null) {
        final em = RegExp(r's(\d{1,2})e(\d{1,2})', caseSensitive: false).firstMatch(tgt);
        if (em != null) {
          final s = em.group(1)!.padLeft(2, '0');
          final e = em.group(2)!.padLeft(2, '0');
          final code = 's' + s + 'e' + e;
          print('    Pass 3 → looking for episode code "$code"');
          for (final r in records) {
            if (rname(r).toLowerCase().contains(code)) {
              rec = r as Map<String, dynamic>;
              print('    Pass 3 → matched: "${rname(r)}"');
              break;
            }
          }
        }
      }
    }

    if (rec == null) {
      rec = records.first as Map<String, dynamic>;
      print('    Fallback → records.first: "${rname(rec)}"');
    }

    final rawUrl   = (rec['url'] ?? rec['downloadUrl'] ?? rec['download_url'] ?? '') as String;
    final filename = (rec['name'] ?? rec['filename'] ?? 'video.mkv') as String;
    final matchedRemoteId = (rec['id'] ?? rec['fileId'] ?? rec['file_id'] ?? 0);

    // Build final stream URL — same as _buildStreamUrl in jazzdrive_service.dart
    var streamUrl = rawUrl.startsWith('/') ? '$_cloudBase$rawUrl' : rawUrl;
    if (!streamUrl.contains('filename=')) {
      final sep = streamUrl.contains('?') ? '&' : '?';
      streamUrl = '$streamUrl${sep}filename=${Uri.encodeComponent(filename)}';
    }

    return {
      'filename': filename,
      'remoteId': matchedRemoteId,
      'streamUrl': streamUrl,
      'recordCount': records.length,
    };
  } finally {
    client.close();
  }
}

// =============================================================================
// Runner
// =============================================================================

Future<void> main() async {
  int passed = 0;
  int failed = 0;
  final List<String> failures = [];

  print('');
  print('══════════════════════════════════════════════════════════════');
  print('  RaddFlix — JazzDrive Dart Integration Tests');
  print('  Real HTTP calls to $_cloudBase');
  print('  Tests: ${_tests.length} (movies + TV seasons)');
  print('══════════════════════════════════════════════════════════════');
  print('');

  for (int i = 0; i < _tests.length; i++) {
    final t         = _tests[i];
    final name      = t['name'] as String;
    final shareUrl  = t['shareUrl'] as String;
    final filename  = t['targetFilename'] as String?;
    final remoteId  = (t['remoteId'] as int?) ?? 0;
    final expectContains = (t['expectFilenameContains'] as String?)?.toLowerCase();
    final mustCode       = (t['mustContainEpisodeCode'] as String?)?.toLowerCase();
    final note      = t['note'] as String? ?? '';

    print('[${i + 1}/${_tests.length}] $name');
    print('    $note');

    try {
      // Step 1: extract share key
      final shareKey = _extractShareKey(shareUrl);
      if (shareKey == null) throw Exception('could not extract share key from URL');

      // Step 2: login → validationKey + JSESSIONID
      final session = await _loginShare(shareKey);
      print('    login OK | validationKey=${session['validationKey']!.substring(0, 12)}…'
            '  cookie=${session['cookie']!.isEmpty ? 'none' : session['cookie']!.substring(0, 20)}…');

      // Step 3: fetch media list + pick correct record
      final result = await _getMedia(
        shareKey,
        session['validationKey']!,
        session['cookie']!,
        targetFilename: filename,
        remoteId: remoteId,
      );

      final matched     = (result['filename'] as String);
      final matchedLow  = matched.toLowerCase();
      final streamUrl   = result['streamUrl'] as String;
      final recordCount = result['recordCount'] as int;

      // Validate 1: got a real HTTP stream URL
      if (streamUrl.isEmpty || !streamUrl.startsWith('http')) {
        throw Exception('stream URL is empty or not HTTP: "$streamUrl"');
      }

      // Validate 2: validationkey must NOT be in the final URL
      if (streamUrl.toLowerCase().contains('validationkey=')) {
        throw Exception('CRITICAL: validationkey found in stream URL — breaks playback!');
      }

      // Validate 3: filename matches expected title
      if (expectContains != null && !matchedLow.contains(expectContains)) {
        throw Exception('wrong file: "$matched" does not contain "$expectContains"');
      }

      // Validate 4: episode code is correct (critical for multi-file folders)
      if (mustCode != null && !matchedLow.contains(mustCode)) {
        throw Exception(
          'WRONG EPISODE from $recordCount-file folder: '
          '"$matched" does not contain "$mustCode" — '
          'app would play wrong episode!'
        );
      }

      print('    PASS | records=$recordCount | matched="$matched"');
      print('    URL: ${streamUrl.substring(0, streamUrl.length.clamp(0, 85))}…');
      print('');
      passed++;

    } catch (e) {
      print('    FAIL | $e');
      print('');
      failed++;
      failures.add('[${i + 1}] $name\n    $e');
    }
  }

  print('══════════════════════════════════════════════════════════════');
  print('  Results: $passed passed  |  $failed failed  |  ${_tests.length} total');
  print('══════════════════════════════════════════════════════════════');

  if (failures.isNotEmpty) {
    print('');
    print('FAILURES:');
    for (final f in failures) print('  • $f');
    print('');
    exit(1);
  }

  print('');
  print('All ${_tests.length} tests passed.');
  print('');
  exit(0);
}
