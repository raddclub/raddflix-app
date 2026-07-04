/// RaddFlix — JazzDrive Link Generation Integration Test
///
/// Tests the EXACT same logic as jazzdrive_service.dart against real JazzDrive API.
/// No Flutter, no packages — only dart:io + dart:convert.
///
/// Run: dart run raddflix_flutter/test_suite/jazzdrive_dart_test.dart
///
/// ══ SSL NOTE (Replit / Nix) ══
/// The Nix-bundled Dart SDK lacks the system CA bundle, causing
/// CERTIFICATE_VERIFY_FAILED on HTTPS. Both HttpClient instances use
/// badCertificateCallback = true so this test runs from any environment.
/// This is a DEVELOPER TEST ONLY — production code (jazzdrive_service.dart)
/// always uses Flutter's platform TLS and does NOT bypass cert verification.
///
/// ══ CONFIRMED WORKING FLOW (matches Node.js reference script) ══
///
/// Step 1: POST /sapi/link/login?action=login
///   Body: { data: { accesstoken: <shareKey> } }
///   Returns: { data: { validationkey, jsessionid } }
///
/// Step 2: GET /sapi/media/video?action=get&shared=true&key=<key>&validationkey=<vk>
///   Headers: validation_key: <vk>, Cookie: JSESSIONID=<jsid>
///   Returns: { data: { list: [ { id, name, url, thumbnails } ] } }
///
/// Step 3: Build CDN URL:
///   <rawUrl>?validationkey=<vk>&filename=<name>
///   ^^^ validationkey MUST be in the final URL — CDN auth fails without it.
///   This was wrong in previous service versions (had a "DO NOT add" comment).
///
/// ══ MED-1011 NOTES ══
/// If ALL shares return MED-1011 → JazzDrive SAPI session expired on Oracle.
/// This is NOT geo-blocking. Fix: OTP re-login from Oracle admin panel.
/// Share URLs themselves never expire.

import 'dart:convert';
import 'dart:io';

const String _cloudBase = 'https://cloud.jazzdrive.com.pk';

// ══════════════════════════════════════════════════════════════════════════════
// Test cases — update share URLs from Oracle:
//   sqlite3 data/radd_hub.db
//   'SELECT f.id, t.title, f.filename, f.remote_id, f.share_url
//    FROM files f JOIN titles t ON t.id=f.title_id
//    WHERE f.share_url!="" AND f.is_ready=1 ORDER BY f.id'
// ══════════════════════════════════════════════════════════════════════════════
final List<Map<String, dynamic>> _tests = [

  // ── Movies ─────────────────────────────────────────────────────────────────
  {
    'name': 'Movie | Interstellar — Pass 0 by remote_id',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/lTzy2wdJQDqnsHSZNJGMBjA0NzE3MTIzNzE2NzFfMjYwMzgwMA',
    'targetFilename': 'Interstellar (2014).mkv',
    'remoteId': 242373442,
    'expectFilenameContains': 'interstellar',
  },
  {
    'name': 'Movie | Interstellar — Pass 1 substring (no remote_id)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/lTzy2wdJQDqnsHSZNJGMBjA0NzE3MTIzNzE2NzFfMjYwMzgwMA',
    'targetFilename': 'Interstellar (2014).mkv',
    'remoteId': 0,
    'expectFilenameContains': 'interstellar',
  },
  {
    'name': 'Movie | Luka Chuppi — Pass 0 by remote_id (2-file folder)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/fTDjCGqPTwS0_Mq6G-LtIzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Luka Chuppi (2019).mp4',
    'remoteId': 242527434,
    'expectFilenameContains': 'luka',
  },

  // ── TV Episodes ─────────────────────────────────────────────────────────────
  {
    'name': 'TV | Vincenzo S01E01 — Pass 0 by remote_id',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E01.mp4',
    'remoteId': 242518574,
    'expectFilenameContains': 'vncenz0',
    'mustContainEpisodeCode': 's01e01',
  },
  {
    'name': 'TV | Vincenzo S01E02 — Pass 0 by remote_id (must NOT return E01)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E02.mp4',
    'remoteId': 242531168,
    'expectFilenameContains': 'vncenz0',
    'mustContainEpisodeCode': 's01e02',
  },
  {
    'name': 'TV | Vincenzo S01E02 — Pass 3 episode code (no remote_id)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/sVvWxQoMSlqKoPZvlt7zUzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Vincenzo S01E02.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'vncenz0',
    'mustContainEpisodeCode': 's01e02',
  },
  {
    'name': 'TV | Spider-Noir S01E01 — Pass 3 episode code',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Spider Noir S01E01.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'spider',
    'mustContainEpisodeCode': 's01e01',
  },
  {
    'name': 'TV | Spider-Noir S01E02 — Pass 3 episode code (must NOT return E01)',
    'shareUrl': 'https://cloud.jazzdrive.com.pk/share/f/hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    'targetFilename': 'Spider Noir S01E02.mp4',
    'remoteId': 0,
    'expectFilenameContains': 'spider',
    'mustContainEpisodeCode': 's01e02',
  },
];

// ══════════════════════════════════════════════════════════════════════════════
// Core logic — mirrors jazzdrive_service.dart exactly (including the fix)
// ══════════════════════════════════════════════════════════════════════════════

String? _extractShareKey(String shareUrl) {
  final m = RegExp(r'/(?:share-landing/f|share/f|f)/([^/?#]+)').firstMatch(shareUrl);
  return m?.group(1);
}

Future<Map<String, String>> _loginShare(String shareKey) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    // ignore: avoid_returning_null_for_void
    ..badCertificateCallback = (cert, host, port) => true; // dev test only
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

    // Detect JazzDrive error codes (MED-1011 = share invalid, FOL-1004 = folder deleted)
    final errorObj = data['error'] as Map<String, dynamic>?;
    if (errorObj != null && (errorObj['code'] as String? ?? '').isNotEmpty) {
      final errCode = errorObj['code'] as String? ?? 'UNKNOWN';
      final errMsg  = errorObj['message'] as String? ?? '';
      throw Exception(
        'JazzDrive error ($errCode: $errMsg).\n'
        '    If MED-1011 on ALL shares → Oracle JazzDrive session expired.\n'
        '    Fix: OTP re-login from Oracle admin panel (Settings → JazzDrive Login).'
      );
    }

    final vk = (inner['validationkey'] ?? inner['validationKey'] ?? inner['validation_key']
               ?? data['validationkey'] ?? data['validationKey']) as String?;
    if (vk == null || vk.isEmpty) {
      throw Exception('no validationkey in login response. Keys: ${data.keys.toList()}');
    }

    // Check JSON body for JSESSIONID first (primary on Android — Set-Cookie may be absorbed)
    String cookie = '';
    final bodyJsid = (inner['jsessionid'] ?? inner['JSESSIONID']
                     ?? data['jsessionid'] ?? data['JSESSIONID']) as String?;
    if (bodyJsid != null && bodyJsid.isNotEmpty) {
      final jsidPart = bodyJsid.contains('.') ? bodyJsid.split('.').first : bodyJsid;
      cookie = 'JSESSIONID=$jsidPart';
    } else {
      resp.headers.forEach((name, values) {
        if (name.toLowerCase() == 'set-cookie') {
          for (final v in values) {
            final m = RegExp(r'JSESSIONID=([^;]+)').firstMatch(v);
            if (m != null && cookie.isEmpty) {
              final raw = m.group(1)!;
              final stripped = raw.contains('.') ? raw.split('.').first : raw;
              cookie = 'JSESSIONID=$stripped';
            }
          }
        }
      });
    }

    return {'validationKey': vk, 'cookie': cookie};
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _getMedia(
  String shareKey, String validationKey, String cookie, {
  String? targetFilename, int remoteId = 0,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    // ignore: avoid_returning_null_for_void
    ..badCertificateCallback = (cert, host, port) => true; // dev test only
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

    final body = jsonDecode(respBody) as Map<String, dynamic>;
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
      if (records.isEmpty && (d['url'] != null || d['id'] != null)) records = [d];
    }

    if (records.isEmpty) throw Exception('no video records found');

    String rname(dynamic r) =>
        ((r as Map<String, dynamic>)['name'] ?? r['filename'] ?? '') as String;

    print('    folder has ${records.length} file(s): [${records.map(rname).join(', ')}]');

    Map<String, dynamic>? rec;

    if (remoteId > 0) {
      for (final r in records) {
        final m = r as Map<String, dynamic>;
        final rid = m['id'] ?? m['fileId'] ?? m['file_id'] ?? 0;
        final ridInt = rid is int ? rid : int.tryParse(rid.toString()) ?? 0;
        if (ridInt == remoteId) { rec = m; print('    Pass 0 → remote_id=$remoteId: "${rname(m)}"'); break; }
      }
    }

    if (rec == null && targetFilename != null && targetFilename.isNotEmpty) {
      final tgt = targetFilename.toLowerCase();
      for (final r in records) {
        final n = rname(r).toLowerCase();
        if (n.contains(tgt) || tgt.contains(n)) { rec = r as Map<String, dynamic>; print('    Pass 1 → substring: "${rname(r)}"'); break; }
      }
      if (rec == null) {
        String norm(String s) => s.replaceAll(RegExp(r'[._]'), ' ').toLowerCase();
        for (final r in records) {
          final n = norm(rname(r));
          if (n.contains(norm(tgt)) || norm(tgt).contains(n)) { rec = r as Map<String, dynamic>; print('    Pass 2 → normalised: "${rname(r)}"'); break; }
        }
      }
      if (rec == null) {
        final em = RegExp(r's(\d{1,2})e(\d{1,2})', caseSensitive: false).firstMatch(tgt);
        if (em != null) {
          final code = 's${em.group(1)!.padLeft(2,'0')}e${em.group(2)!.padLeft(2,'0')}';
          for (final r in records) {
            if (rname(r).toLowerCase().contains(code)) { rec = r as Map<String, dynamic>; print('    Pass 3 → episode code "$code": "${rname(r)}"'); break; }
          }
        }
      }
    }

    if (rec == null) { rec = records.first as Map<String, dynamic>; print('    Fallback → first: "${rname(rec)}"'); }

    final rawUrl   = (rec['url'] ?? rec['downloadUrl'] ?? rec['download_url'] ?? '') as String;
    final filename = (rec['name'] ?? rec['filename'] ?? 'video.mkv') as String;

    return {'rawUrl': rawUrl, 'filename': filename, 'recordCount': records.length};
  } finally {
    client.close();
  }
}

/// Build final CDN URL — validationkey MUST be appended (CDN auth requirement).
/// Matches working Node.js reference script exactly.
String _buildStreamUrl(String rawUrl, String filename, String validationKey) {
  var url = rawUrl.startsWith('/') ? '$_cloudBase$rawUrl' : rawUrl;
  final sep = url.contains('?') ? '&' : '?';
  url = '${url}${sep}validationkey=${Uri.encodeComponent(validationKey)}'
        '&filename=${Uri.encodeComponent(filename)}';
  return url;
}

// ══════════════════════════════════════════════════════════════════════════════
// Runner
// ══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  int passed = 0, failed = 0;
  final List<String> failures = [];

  print('');
  print('══════════════════════════════════════════════════════════════');
  print('  RaddFlix — JazzDrive Dart Integration Tests');
  print('  Endpoint: $_cloudBase');
  print('  Tests: ${_tests.length}');
  print('  NOTE: MED-1011 on ALL tests = Oracle OTP re-login needed.');
  print('══════════════════════════════════════════════════════════════');
  print('');

  for (int i = 0; i < _tests.length; i++) {
    final t               = _tests[i];
    final name            = t['name'] as String;
    final shareUrl        = t['shareUrl'] as String;
    final filename        = t['targetFilename'] as String?;
    final remoteId        = (t['remoteId'] as int?) ?? 0;
    final expectContains  = (t['expectFilenameContains'] as String?)?.toLowerCase();
    final mustCode        = (t['mustContainEpisodeCode'] as String?)?.toLowerCase();

    print('[${i + 1}/${_tests.length}] $name');

    try {
      final shareKey = _extractShareKey(shareUrl)
          ?? (throw Exception('could not extract share key'));

      final session = await _loginShare(shareKey);
      print('    login OK | vk=${session['validationKey']!.substring(0, 12)}… | cookie=${session['cookie']!.isNotEmpty ? "present" : "MISSING"}');

      final result = await _getMedia(shareKey, session['validationKey']!, session['cookie']!,
          targetFilename: filename, remoteId: remoteId);

      final matched    = result['filename'] as String;
      final matchedLow = matched.toLowerCase();
      final rawUrl     = result['rawUrl'] as String;
      final count      = result['recordCount'] as int;

      // Build final URL exactly as the service does
      final streamUrl = _buildStreamUrl(rawUrl, matched, session['validationKey']!);

      // Validate 1: is a real HTTP URL
      if (streamUrl.isEmpty || !streamUrl.startsWith('http')) {
        throw Exception('stream URL empty or not HTTP: "$streamUrl"');
      }
      // Validate 2: validationkey MUST be in final URL (CDN auth requirement)
      if (!streamUrl.contains('validationkey=')) {
        throw Exception('CRITICAL: validationkey missing from stream URL — CDN will reject playback!');
      }
      // Validate 3: matched file contains expected title fragment
      if (expectContains != null && !matchedLow.contains(expectContains)) {
        throw Exception('wrong file: "$matched" does not contain "$expectContains"');
      }
      // Validate 4: correct episode (no wrong-episode bug)
      if (mustCode != null && !matchedLow.contains(mustCode)) {
        throw Exception('WRONG EPISODE from $count-file folder: "$matched" missing "$mustCode"');
      }

      print('    PASS | files=$count | matched="$matched"');
      print('    URL: ${streamUrl.substring(0, streamUrl.length.clamp(0, 90))}…');
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
    print('\nFAILURES:');
    for (final f in failures) print('  • $f');
    print('');
    exit(1);
  }
  print('\nAll ${_tests.length} tests passed.\n');
  exit(0);
}
