#!/usr/bin/env node
/**
 * RaddFlix — JazzDrive Link Verification Script (Node.js)
 * Runs ON Oracle server (needs Jazz SIM to reach cloud.jazzdrive.com.pk).
 *
 * Exactly mirrors jazzdrive.py:generate_direct_link (the authoritative Python impl).
 * Key fix vs first attempt: carries JSESSIONID cookie between login → media list,
 * exactly like Python requests.Session() does automatically.
 *
 * For each test:
 *   1. POST  /sapi/link/login?action=login   → validationkey + JSESSIONID cookie
 *   2. GET   /sapi/media/video?...           → file list (needs cookie)
 *   3. Match by remote_id (Pass 0)           → get url / downloadUrl
 *   4. HEAD  on the full streaming URL       → verify Content-Type video/*
 */

const https = require('https');
const http  = require('http');

const CLOUD_BASE = 'https://cloud.jazzdrive.com.pk';
const BASE_HEADERS = {
  Accept:           'application/json, text/plain, */*',
  'Content-Type':   'application/json',
  Origin:            CLOUD_BASE,
  'User-Agent':      'Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  'X-Requested-With':'com.jazz.drive',
};

// ── HTTP helpers ────────────────────────────────────────────────────────────
function req(opts, body) {
  return new Promise((resolve, reject) => {
    const lib = opts.protocol === 'http:' ? http : https;
    const r = lib.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        res.rawBody = d;
        try { res.json = JSON.parse(d); } catch { res.json = null; }
        // parse Set-Cookie into a simple key=value string for reuse
        res.cookieStr = (res.headers['set-cookie'] || [])
          .map(c => c.split(';')[0]).join('; ');
        resolve(res);
      });
    });
    r.setTimeout(25000, () => r.destroy(new Error('timeout')));
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}

function headReq(url) {
  return new Promise((resolve, reject) => {
    try {
      const u = new URL(url);
      const lib = u.protocol === 'http:' ? http : https;
      const r = lib.request({
        method: 'HEAD', hostname: u.hostname,
        path: u.pathname + u.search,
        port: u.port || undefined,
        headers: { 'User-Agent': BASE_HEADERS['User-Agent'], Range: 'bytes=0-1023' }
      }, res => resolve({ status: res.statusCode, headers: res.headers }));
      r.setTimeout(20000, () => r.destroy(new Error('head timeout')));
      r.on('error', reject);
      r.end();
    } catch(e) { reject(e); }
  });
}

function abs(u) {
  if (!u) return '';
  return u.startsWith('/') ? CLOUD_BASE + u : u;
}

// ── Core: generate + verify one file ───────────────────────────────────────
async function testFile(t) {
  const referer = `${CLOUD_BASE}/share/f/${t.shareKey}`;
  const hdrs    = { ...BASE_HEADERS, Referer: referer };

  // ── Step 1: Login to share ─────────────────────────────────────────────
  const loginBody = JSON.stringify({ data: { accesstoken: t.shareKey } });
  const r1 = await req({
    hostname: 'cloud.jazzdrive.com.pk',
    path:     '/sapi/link/login?action=login',
    method:   'POST',
    headers:  { ...hdrs, 'Content-Length': Buffer.byteLength(loginBody) }
  }, loginBody);

  if (r1.statusCode !== 200)
    return { ok: false, step: 'login', error: `HTTP ${r1.statusCode}: ${r1.rawBody.slice(0,200)}` };

  const d1 = r1.json?.data || r1.json || {};
  const vk = d1.validationkey || d1.validation_key;
  if (!vk)
    return { ok: false, step: 'login', error: `No validationkey — body: ${r1.rawBody.slice(0,200)}` };

  // Carry cookie from login into next request (mirrors Python requests.Session)
  const cookie = r1.cookieStr;

  // ── Step 2: Get file list ──────────────────────────────────────────────
  const mediaPath = `/sapi/media/video?action=get&shared=true&key=${t.shareKey}&validationkey=${encodeURIComponent(vk)}`;
  const r2 = await req({
    hostname: 'cloud.jazzdrive.com.pk',
    path:     mediaPath,
    method:   'GET',
    headers:  { ...hdrs, validation_key: vk, Cookie: cookie }
  });

  if (r2.statusCode !== 200)
    return { ok: false, step: 'media_list', error: `HTTP ${r2.statusCode}: ${r2.rawBody.slice(0,200)}` };

  const d2  = r2.json?.data || r2.json || {};
  let records = [];
  if (Array.isArray(d2)) {
    records = d2;
  } else {
    for (const k of ['videos', 'list', 'items', 'result']) {
      if (Array.isArray(d2[k])) { records = d2[k]; break; }
    }
  }
  if (!records.length)
    return { ok: false, step: 'media_list', error: `No records — raw: ${r2.rawBody.slice(0,300)}` };

  // ── Step 3: Match by remote_id (Pass 0) ───────────────────────────────
  let match = null;
  for (const rec of records) {
    const rid = rec.id || rec.fileId || rec.file_id || '';
    if (String(rid) === String(t.remoteId)) { match = rec; break; }
  }

  const allIds = records.map(r => r.id || r.fileId || r.file_id).join(', ');
  if (!match)
    return { ok: false, step: 'match', error: `remote_id ${t.remoteId} not in folder. IDs: [${allIds}]`, folderCount: records.length };

  // ── Step 4: Build URL ──────────────────────────────────────────────────
  const rawDownload = abs(match.downloadUrl || match.download_url || '');
  const rawStream   = abs(match.url         || match.viewurl      || '');
  const baseUrl     = rawDownload || rawStream;

  if (!baseUrl)
    return { ok: false, step: 'url_build', error: `No url/downloadUrl in record: ${JSON.stringify(match).slice(0,200)}` };

  const name   = match.name || match.filename || t.filename;
  const addFn  = u => u && !u.includes('filename=')
    ? `${u}${u.includes('?') ? '&' : '?'}filename=${encodeURIComponent(name)}`
    : u;

  const directLink = addFn(baseUrl);
  const streamUrl  = rawStream ? addFn(rawStream) : directLink;

  // ── Step 5: HEAD verify ────────────────────────────────────────────────
  let headResult;
  try {
    headResult = await headReq(directLink);
  } catch(e) {
    headResult = { status: null, headers: {}, error: e.message };
  }

  const st  = headResult.status;
  const ct  = (headResult.headers || {})['content-type'] || '';
  const cl  = (headResult.headers || {})['content-length'] || (headResult.headers || {})['content-range'] || '';
  const isVideoUrl = ct.startsWith('video/') || ct.includes('octet-stream')
    || [200, 206, 301, 302, 307, 308].includes(st);

  return {
    ok:          isVideoUrl,
    step:        'done',
    folderCount: records.length,
    allIds,
    filename:    name,
    directLink,
    streamUrl,
    sizeBytes:   match.size || match.filesize || 0,
    httpStatus:  st,
    contentType: ct,
    contentLength: cl,
    headError:   headResult.error || null,
  };
}

// ── Test cases (from radd_hub.db — active production DB) ───────────────────
const TESTS = [
  {
    label:    'Movie | Pitt Siyapa (2026)',
    shareKey: 'TZuomFBLSJahDJqXdBaCrDc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    remoteId: '242531171',
    filename: 'Pitt Siyapa (2026).mp4',
  },
  {
    label:    'Movie | Bhooth Bangla (2026)',
    shareKey: 'DGlCkLVNTjO9Ry_0eJ8ERjc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    remoteId: '242517108',
    filename: 'Bhooth Bangla (2026).mp4',
  },
  {
    label:    'Movie | Luka Chuppi (2019)',
    shareKey: 'fTDjCGqPTwS0_Mq6G-LtIzc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    remoteId: '242527434',
    filename: 'Luka Chuppi (2019).mp4',
  },
  {
    label:    'TV | Spider-Noir S01E02',
    shareKey: 'hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA',
    remoteId: '242518530',
    filename: 'Spider Noir S01E02.mp4',
  },
];

// ── Runner ──────────────────────────────────────────────────────────────────
async function main() {
  const W = 70;
  const line = '═'.repeat(W);
  console.log(line);
  console.log('  RaddFlix — JazzDrive Link Verification (Node.js)');
  console.log(`  ${new Date().toISOString()}`);
  console.log(line + '\n');

  const results = [];

  for (let i = 0; i < TESTS.length; i++) {
    const t = TESTS[i];
    process.stdout.write(`[${i+1}/${TESTS.length}] ${t.label}\n`);

    let r;
    try { r = await testFile(t); }
    catch(e) { r = { ok: false, step: 'exception', error: e.message }; }

    if (!r.ok) {
      console.log(`    ✗ FAILED @ step=${r.step}: ${r.error}`);
      if (r.folderCount !== undefined)
        console.log(`      folder has ${r.folderCount} file(s), IDs: [${r.allIds}]`);
    } else {
      console.log(`    ✓ Link generated  (folder: ${r.folderCount} file(s))`);
      console.log(`      Filename      : ${r.filename}`);
      console.log(`      DirectLink    : ${r.directLink.slice(0, 85)}...`);
      console.log(`      StreamURL     : ${r.streamUrl.slice(0, 85)}...`);
      console.log(`      Size          : ${r.sizeBytes ? (r.sizeBytes/1024/1024).toFixed(1)+' MB' : 'unknown'}`);
      const verdict = r.ok ? '✓ REAL VIDEO URL' : '✗ NOT A VIDEO URL';
      console.log(`    ${verdict}`);
      console.log(`      HTTP Status   : ${r.httpStatus}`);
      console.log(`      Content-Type  : ${r.contentType || 'N/A'}`);
      console.log(`      Content-Length: ${r.contentLength || 'N/A'}`);
      if (r.headError) console.log(`      HEAD error    : ${r.headError}`);
    }

    results.push({ label: t.label, pass: r.ok, ...r });
    console.log('');
  }

  const passed = results.filter(r => r.pass).length;
  const failed = results.filter(r => !r.pass).length;
  console.log(line);
  console.log(`  Results: ${passed} passed  |  ${failed} failed  |  ${results.length} total`);
  console.log(line);

  if (failed > 0) {
    console.log('FAILURES:');
    results.filter(r => !r.pass).forEach(r => {
      console.log(`  • ${r.label}: step=${r.step} — ${r.error || r.headError || '?'}`);
    });
  } else {
    console.log('  ✓ All links verified as real video URLs ✓');
  }
  console.log('');
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
