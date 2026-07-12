#!/usr/bin/env node
/**
 * JazzDrive Stream Link Generator — Logic Test Suite
 *
 * Tests ALL logic from jazzdrive_service.dart WITHOUT needing Jazz SIM.
 * For full network test (requires Jazz SIM device), pass --live flag.
 *
 * Run: node jazzdrive_logic_test.js
 * Run (live): node jazzdrive_logic_test.js --live <shareUrl> <targetFilename>
 *
 * Mirrors the Dart _extractShareKey, _rname, 3-pass match, 
 * _buildStreamUrl, _buildPosterUrl logic exactly.
 */

const https = require('https');

const CLOUD = 'https://cloud.jazzdrive.com.pk';
let passed = 0, failed = 0;
function pass(name) { passed++; console.log('  ✅ ' + name); }
function fail(name, expected, got) { failed++; console.log('  ❌ ' + name + '\n     expected: ' + JSON.stringify(expected) + '\n     got:      ' + JSON.stringify(got)); }
function section(s) { console.log('\n── ' + s + ' ' + '─'.repeat(50 - s.length)); }

// ── Dart mirror: _extractShareKey ─────────────────────────────────────────────
function extractShareKey(shareUrl) {
  const m = shareUrl.match(/\/(?:share-landing\/f|share\/f|f)\/([^/?#]+)/);
  return m ? m[1] : null;
}

section('_extractShareKey');
(function() {
  const cases = [
    ['https://cloud.jazzdrive.com.pk/share/f/uyiN5SOaTCG_tJZpKYMZnTA0Nz', 'uyiN5SOaTCG_tJZpKYMZnTA0Nz'],
    ['https://cloud.jazzdrive.com.pk/share-landing/f/ABCdef123', 'ABCdef123'],
    ['https://cloud.jazzdrive.com.pk/f/XYZ789', 'XYZ789'],
    ['https://cloud.jazzdrive.com.pk/share/f/KEY?foo=bar', 'KEY'],
    ['https://cloud.jazzdrive.com.pk/share/f/KEY#anchor', 'KEY'],
    ['https://invalid.com/other', null],
    ['', null],
  ];
  for (const [input, expected] of cases) {
    const got = extractShareKey(input);
    got === expected ? pass(input.substring(0,60)) : fail(input.substring(0,60), expected, got);
  }
})();

// ── Dart mirror: _rname ────────────────────────────────────────────────────────
function rname(r) { return (r.name || r.filename || ''); }

// ── Dart mirror: 3-pass filename match ────────────────────────────────────────
function matchRecord(records, targetFilename) {
  if (!targetFilename) return records[0] || null;
  const tgt = targetFilename.toLowerCase();

  // Pass 1: exact case-insensitive substring
  let rec = records.find(r => {
    const n = rname(r).toLowerCase();
    return n.includes(tgt) || tgt.includes(n);
  }) || null;
  if (rec) { console.log('    Pass1 match: ' + rname(rec)); return rec; }

  // Pass 2: normalised (dots/underscores → spaces)
  function norm(s) { return s.replace(/[._]/g, ' ').toLowerCase(); }
  rec = records.find(r => {
    const n = norm(rname(r));
    return n.includes(norm(tgt)) || norm(tgt).includes(n);
  }) || null;
  if (rec) { console.log('    Pass2 match: ' + rname(rec)); return rec; }

  // Pass 3: episode code match (FIXED - was broken by \$ escape in Dart)
  const em = tgt.match(/s(\d{1,2})e(\d{1,2})/i);
  if (em) {
    const s = em[1].padStart(2, '0');
    const e = em[2].padStart(2, '0');
    const code = 's' + s + 'e' + e;
    console.log('    Pass3 code: ' + code);
    rec = records.find(r => rname(r).toLowerCase().includes(code)) || null;
    if (rec) { console.log('    Pass3 match: ' + rname(rec)); return rec; }
  }

  return records[0] || null; // fallback
}

section('3-pass filename match');
(function() {
  const folder = [
    { name: 'All.Of.Us.Are.Dead.S01E01.1080p.mkv' },
    { name: 'All.Of.Us.Are.Dead.S01E02.1080p.mkv' },
    { name: 'All.Of.Us.Are.Dead.S01E06.1080p.mkv' },
    { name: 'All.Of.Us.Are.Dead.S01E07.1080p.mkv' },
  ];

  // Pass 1 tests
  let r = matchRecord(folder, 'S01E01');
  r && r.name.includes('E01') ? pass('Pass1: S01E01 substring') : fail('Pass1: S01E01 substring', 'E01', r?.name);

  r = matchRecord(folder, 'All Of Us Are Dead S01E02.mkv');
  r && r.name.includes('E02') ? pass('Pass1: full filename') : fail('Pass1: full filename', 'E02', r?.name);

  // Pass 2 tests (normalised dots→spaces)
  r = matchRecord(folder, 'All Of Us Are Dead S01E06 1080p');
  r && r.name.includes('E06') ? pass('Pass2: normalised spaces') : fail('Pass2: normalised spaces', 'E06', r?.name);

  // Pass 3 tests (episode code — this was BROKEN in Dart before fix)
  r = matchRecord(folder, 'All_Of_Us_Are_Dead_S01E07_DUBBED.mkv');
  r && r.name.includes('E07') ? pass('Pass3: episode code s01e07') : fail('Pass3: episode code', 'E07', r?.name);

  // Folder with numeric filenames (single-file share fallback)
  const single = [{ name: 'Interstellar.2014.mkv' }];
  r = matchRecord(single, null);
  r && r.name === 'Interstellar.2014.mkv' ? pass('Fallback: single file no target') : fail('Fallback', 'Interstellar.2014.mkv', r?.name);

  // Edge: no match at all → fallback to first
  r = matchRecord(folder, 'NonExistentMovie.mkv');
  r === folder[0] ? pass('Fallback: no match → records[0]') : fail('Fallback: no match', folder[0].name, r?.name);
})();

// ── Dart mirror: _buildStreamUrl ─────────────────────────────────────────────
function buildStreamUrl(rawUrl, filename) {
  let url = rawUrl.startsWith('/') ? CLOUD + rawUrl : rawUrl;
  if (!url.includes('filename=')) {
    const sep = url.includes('?') ? '&' : '?';
    url = url + sep + 'filename=' + encodeURIComponent(filename);
  }
  return url;
}

section('_buildStreamUrl');
(function() {
  let u = buildStreamUrl('/sapi/download/video?action=get&k=TOKEN123', 'All.Of.Us.Are.Dead.S01E01.mkv');
  u.startsWith(CLOUD) ? pass('relative URL prefixed with CLOUD') : fail('relative URL', CLOUD + '...', u.substring(0,60));
  u.includes('filename=') ? pass('filename param appended') : fail('filename param', 'filename=...', u);
  u.includes('filename=All') ? pass('filename correctly encoded') : fail('filename encoding', 'filename=All', u);

  // Already has filename= → no double-append
  const already = 'https://cloud.jazzdrive.com.pk/sapi/dl?k=X&filename=test.mkv';
  u = buildStreamUrl(already, 'other.mkv');
  const count = (u.match(/filename=/g) || []).length;
  count === 1 ? pass('no double filename= when already present') : fail('double filename=', 1, count);

  // Absolute URL
  u = buildStreamUrl('https://cloud.jazzdrive.com.pk/sapi/dl?k=X', 'movie.mkv');
  u.startsWith('https://cloud') ? pass('absolute URL unchanged') : fail('absolute URL', 'https://cloud...', u.substring(0,40));
})();

// ── Dart mirror: _buildPosterUrl ──────────────────────────────────────────────
function buildPosterUrl(rawUrl) {
  if (!rawUrl) return null;
  return rawUrl.startsWith('/') ? CLOUD + rawUrl : rawUrl;
}

section('_buildPosterUrl');
(function() {
  let p = buildPosterUrl('/sapi/image/thumb/abc.jpg');
  p === CLOUD + '/sapi/image/thumb/abc.jpg' ? pass('relative poster prefixed') : fail('relative poster', CLOUD + '...', p);

  p = buildPosterUrl('https://other.com/img.jpg');
  p === 'https://other.com/img.jpg' ? pass('absolute poster unchanged') : fail('absolute poster', 'https://...', p);

  p = buildPosterUrl(null);
  p === null ? pass('null poster → null') : fail('null poster', null, p);

  p = buildPosterUrl('');
  p === null ? pass('empty poster → null') : fail('empty poster', null, p);
})();

// ── Mock response parsing (mirrors _getMedia body parsing) ────────────────────
section('_getMedia response parsing');
(function() {
  function parseRecords(body) {
    const rawBody = body.data !== undefined ? body.data : body;
    let records = [];
    if (Array.isArray(rawBody)) {
      records = rawBody;
    } else {
      const d = (rawBody && typeof rawBody === 'object') ? rawBody : {};
      for (const key of ['list', 'items', 'videos', 'records', 'files']) {
        if (Array.isArray(d[key])) { records = d[key]; break; }
        if (Array.isArray(body[key])) { records = body[key]; break; }
      }
      if (!records.length && (d.url || d.id)) records = [d];
    }
    return records;
  }

  // Shape 1: data.list[]
  let recs = parseRecords({ data: { list: [{ name: 'ep1.mkv', url: '/dl/1' }] } });
  recs.length === 1 && recs[0].name === 'ep1.mkv' ? pass('Shape: data.list[]') : fail('Shape: data.list[]', 1, recs.length);

  // Shape 2: data[] (array directly)
  recs = parseRecords({ data: [{ name: 'ep2.mkv', url: '/dl/2' }] });
  recs.length === 1 && recs[0].name === 'ep2.mkv' ? pass('Shape: data[] array') : fail('Shape: data[] array', 1, recs.length);

  // Shape 3: top-level videos[]
  recs = parseRecords({ videos: [{ name: 'movie.mkv', url: '/dl/3' }] });
  recs.length === 1 ? pass('Shape: root.videos[]') : fail('Shape: root.videos[]', 1, recs.length);

  // Shape 4: single record object
  recs = parseRecords({ data: { url: '/dl/4', name: 'single.mkv' } });
  recs.length === 1 && recs[0].name === 'single.mkv' ? pass('Shape: single record object') : fail('Shape: single record', 1, recs.length);

  // Thumbnail extraction
  const record = { name: 'ep.mkv', url: '/dl/5', thumbnails: [
    { url: '/img/thumb_sm.jpg' },
    { url: '/img/thumb_lg.jpg' },
  ]};
  const thumbs = record.thumbnails || [];
  const posterRaw = thumbs.length ? (thumbs[thumbs.length - 1]?.url || thumbs[0]?.url) : null;
  const poster = buildPosterUrl(posterRaw);
  poster === CLOUD + '/img/thumb_lg.jpg' ? pass('Poster: last thumbnail selected') : fail('Poster selection', CLOUD + '/img/thumb_lg.jpg', poster);
})();

// ── Summary ───────────────────────────────────────────────────────────────────
console.log('\n' + '═'.repeat(55));
console.log('  Logic tests: ' + (passed + failed) + ' total | ✅ ' + passed + ' passed | ❌ ' + failed + ' failed');
console.log('═'.repeat(55));

if (failed > 0) process.exit(1);

// ── LIVE network test (Jazz SIM required) ─────────────────────────────────────
if (process.argv.includes('--live')) {
  const shareUrl = process.argv[process.argv.indexOf('--live') + 1];
  const target   = process.argv[process.argv.indexOf('--live') + 2] || '';
  if (!shareUrl) { console.error('\nUsage: node jazzdrive_logic_test.js --live <shareUrl> [targetFilename]'); process.exit(1); }

  console.log('\n── LIVE TEST (Jazz SIM) ' + '─'.repeat(35));
  console.log('Share URL:  ' + shareUrl);
  console.log('Target:     ' + (target || '(none)'));

  const key = extractShareKey(shareUrl);
  if (!key) { console.error('Invalid share URL'); process.exit(1); }

  const baseHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json;charset=UTF-8',
    'Origin': CLOUD,
    'Referer': CLOUD + '/share/f/' + key,
    'User-Agent': 'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'X-Requested-With': 'com.jazz.drive',
  };

  function post(url, data, hdrs) {
    return new Promise((res, rej) => {
      const body = JSON.stringify(data);
      const u = new URL(url);
      const req = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: 'POST',
        headers: { ...hdrs, 'Content-Length': Buffer.byteLength(body) } }, r => {
        let d = ''; const sc = r.headers['set-cookie'] || [];
        r.on('data', c => d += c); r.on('end', () => { try { res({ st: r.statusCode, data: JSON.parse(d), sc }); } catch(e) { res({ st: r.statusCode, raw: d, sc }); } });
      }); req.on('error', rej); req.setTimeout(15000, () => { req.destroy(); rej(new Error('timeout')); }); req.write(body); req.end();
    });
  }
  function get(url, hdrs) {
    return new Promise((res, rej) => {
      const u = new URL(url);
      const req = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: 'GET', headers: hdrs }, r => {
        let d = ''; r.on('data', c => d += c); r.on('end', () => { try { res({ st: r.statusCode, data: JSON.parse(d) }); } catch(e) { res({ st: r.statusCode, raw: d.substring(0, 500) }); } });
      }); req.on('error', rej); req.setTimeout(15000, () => { req.destroy(); rej(new Error('timeout')); }); req.end();
    });
  }

  (async () => {
    // Login
    console.log('\n[1] Login...');
    const login = await post(CLOUD + '/sapi/link/login?action=login', { data: { accesstoken: key } }, baseHeaders);
    console.log('    HTTP ' + login.st);
    if (login.raw) { console.log('    Non-JSON:', login.raw.substring(0, 300)); process.exit(1); }
    const inner = login.data?.data || login.data;
    const vk = inner?.validationkey || inner?.validationKey || login.data?.validationkey;
    if (!vk) { console.error('    No validation key. Full response:', JSON.stringify(login.data)); process.exit(1); }
    console.log('    validationkey: ' + vk.substring(0, 20) + '...');
    const jsid = (login.sc.join(';').match(/JSESSIONID=([^;]+)/) || [])[1] || '';
    console.log('    JSESSIONID: ' + (jsid ? jsid.substring(0, 15) + '...' : 'NOT FOUND'));

    // Media list
    console.log('\n[2] Media list...');
    const murl = CLOUD + '/sapi/media/video?action=get&shared=true&key=' + key + '&validationkey=' + encodeURIComponent(vk);
    const media = await get(murl, { ...baseHeaders, Cookie: jsid ? 'JSESSIONID=' + jsid : '' });
    console.log('    HTTP ' + media.st);
    if (media.raw) { console.log('    Non-JSON:', media.raw); process.exit(1); }

    const body = media.data;
    console.log('    Top-level keys:', Object.keys(body));
    const rawBody = body.data !== undefined ? body.data : body;
    let records = [];
    if (Array.isArray(rawBody)) records = rawBody;
    else { const d = rawBody || {}; for (const k of ['list','items','videos','records','files']) { if (Array.isArray(d[k])) { records = d[k]; break; } } }
    if (!records.length && (rawBody?.url || rawBody?.id)) records = [rawBody];
    console.log('    Records:', records.length);
    if (records.length > 0) {
      console.log('    Names:', records.map(r => rname(r)));
    }

    // Match
    console.log('\n[3] Filename match...');
    const rec = matchRecord(records, target);
    if (!rec) { console.error('    No record matched'); process.exit(1); }
    console.log('    Selected:', rname(rec));
    const rawUrl = rec.url || rec.downloadUrl || rec.download_url || '';
    const streamUrl = buildStreamUrl(rawUrl, rname(rec));
    const posterUrl = buildPosterUrl((rec.thumbnails || []).slice(-1)[0]?.url);
    console.log('\n[RESULT]');
    console.log('  filename:  ', rname(rec));
    console.log('  streamUrl: ', streamUrl.substring(0, 100) + '...');
    console.log('  posterUrl: ', posterUrl ? posterUrl.substring(0, 80) : 'none');
  })().catch(e => { console.error('LIVE ERROR:', e.message); process.exit(1); });
}
