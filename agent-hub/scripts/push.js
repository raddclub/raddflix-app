// RaddFlix push helper — download once per session:
// curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/push.js" \
//   > /home/runner/workspace/.local/push.js
// Usage: const { readFile, pushFile, pushTree, delay } = require('/home/runner/workspace/.local/push.js');

const https = require('https');
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

const delay = ms => new Promise(r => setTimeout(r, ms));

// ── Single HTTP attempt — resolves { status, body, headers } ─────────────────
function _request(method, path, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const req = https.request({
      hostname: 'api.github.com', port: 443,
      path: `/repos/${REPO}/${path}`, method,
      headers: {
        'Authorization':  `token ${TOKEN}`,
        'User-Agent':     'raddflix-agent',
        'Accept':         'application/vnd.github.v3+json',
        'Content-Type':   'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {})
      }
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        let body;
        try { body = JSON.parse(d); } catch { body = d; }
        resolve({ status: res.statusCode, body, headers: res.headers });
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// ── api() — wraps _request with exponential-backoff retry ────────────────────
// Retries on: network errors, HTTP 429 (rate limit), HTTP 5xx (server errors)
// Never retries: HTTP 4xx (bad SHA, not found, etc.) — these are logic errors
const RETRYABLE_CODES = new Set(['ECONNRESET', 'ETIMEDOUT', 'ENOTFOUND', 'ECONNREFUSED', 'EPIPE']);

async function api(method, path, body, maxRetries = 3) {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    let res;

    try {
      res = await _request(method, path, body);
    } catch (err) {
      if (attempt < maxRetries && RETRYABLE_CODES.has(err.code)) {
        const wait = (2 ** attempt) * 1000;
        console.warn(`  ↻ [${attempt + 1}/${maxRetries}] network error (${err.code}) — retrying in ${wait}ms`);
        await delay(wait);
        continue;
      }
      throw err;
    }

    const { status, body: data, headers } = res;

    // 429 Rate limited — respect Retry-After or default 60s
    if (status === 429 && attempt < maxRetries) {
      const wait = headers['retry-after'] ? parseInt(headers['retry-after']) * 1000 : 60000;
      console.warn(`  ↻ [${attempt + 1}/${maxRetries}] rate limited — retrying in ${wait / 1000}s`);
      await delay(wait);
      continue;
    }

    // 5xx Server error — exponential backoff (1s, 2s, 4s)
    if (status >= 500 && attempt < maxRetries) {
      const wait = (2 ** attempt) * 1000;
      console.warn(`  ↻ [${attempt + 1}/${maxRetries}] GitHub ${status} — retrying in ${wait}ms`);
      await delay(wait);
      continue;
    }

    return data; // success or non-retryable (4xx) — caller decides what to do
  }
}

// ── readFile — read a repo file, returns UTF-8 string ────────────────────────
async function readFile(repoPath) {
  const data = await api('GET', `contents/${repoPath}`);
  if (!data || !data.content)
    throw new Error(`readFile: '${repoPath}' not found — ${data && data.message}`);
  return Buffer.from(data.content, 'base64').toString('utf8');
}

// ── pushFile — push string content (always fetches fresh SHA before PUT) ─────
async function pushFile(repoPath, newContent, message) {
  const meta = await api('GET', `contents/${repoPath}`);
  if (!meta || !meta.sha)
    throw new Error(`pushFile: cannot get SHA for '${repoPath}' — ${meta && meta.message}`);
  const r = await api('PUT', `contents/${repoPath}`, {
    message, sha: meta.sha,
    content: Buffer.from(newContent).toString('base64')
  });
  if (!r || !r.commit)
    throw new Error(`pushFile failed for '${repoPath}': ${r && r.message}`);
  console.log('✅', repoPath, '→', r.commit.sha.slice(0, 7));
  return r.commit.sha.slice(0, 7);
}

// ── pushTree — multiple files in one atomic commit (Trees API) ────────────────
// files: [{ path: 'repo/path/to/file.dart', content: 'string content' }, ...]
async function pushTree(files, commitMsg) {
  const ref    = await api('GET', 'git/refs/heads/main');
  const commit = await api('GET', `git/commits/${ref.object.sha}`);
  const blobs  = await Promise.all(files.map(f =>
    api('POST', 'git/blobs', {
      content:  Buffer.from(f.content).toString('base64'),
      encoding: 'base64'
    })
  ));
  const tree = await api('POST', 'git/trees', {
    base_tree: commit.tree.sha,
    tree: files.map((f, i) => ({ path: f.path, mode: '100644', type: 'blob', sha: blobs[i].sha }))
  });
  const nc = await api('POST', 'git/commits', {
    message: commitMsg, tree: tree.sha, parents: [ref.object.sha]
  });
  await api('PATCH', 'git/refs/heads/main', { sha: nc.sha, force: false });
  console.log('✅ Committed:', nc.sha.slice(0, 7), '—', commitMsg);
  return nc.sha.slice(0, 7);
}

module.exports = { api, readFile, pushFile, pushTree, delay, REPO };
