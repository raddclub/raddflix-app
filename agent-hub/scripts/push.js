// RaddFlix push helper — download once per session:
// curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/push.js" > /tmp/push.js
// Then: const { readFile, pushFile, pushTree, delay } = require('/tmp/push.js');
const https = require('https');
const TOKEN = process.env.GITHUB_TOKEN;
const REPO = 'raddclub/raddflix-app';

function api(method, path, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const opts = {
      hostname: 'api.github.com', port: 443,
      path: `/repos/${REPO}/${path}`, method,
      headers: {
        'Authorization': `token ${TOKEN}`,
        'User-Agent': 'raddflix-agent',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {})
      }
    };
    const req = https.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve(d); } });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// Read a file from GitHub repo, returns decoded UTF-8 string
async function readFile(repoPath) {
  const meta = await api('GET', `contents/${repoPath}`);
  if (!meta.content) throw new Error(`readFile: '${repoPath}' not found — ${meta.message}`);
  return Buffer.from(meta.content, 'base64').toString('utf8');
}

// Push new string content to GitHub (always fetches fresh SHA right before PUT)
async function pushFile(repoPath, newContent, message) {
  const meta = await api('GET', `contents/${repoPath}`);
  if (!meta.sha) throw new Error(`pushFile: cannot get SHA for '${repoPath}' — ${meta.message}`);
  const content = Buffer.from(newContent).toString('base64');
  const r = await api('PUT', `contents/${repoPath}`, { message, content, sha: meta.sha });
  if (!r.commit) throw new Error(`pushFile failed for '${repoPath}': ${r.message}`);
  console.log('✅', repoPath, '→', r.commit.sha.slice(0, 7));
  return r.commit.sha.slice(0, 7);
}

// Push multiple files in one atomic commit using the Trees API
// files: [{ path: 'repo/path/file.dart', content: 'string content' }, ...]
async function pushTree(files, commitMsg) {
  const ref = await api('GET', 'git/refs/heads/main');
  const commit = await api('GET', `git/commits/${ref.object.sha}`);
  const blobs = await Promise.all(files.map(f =>
    api('POST', 'git/blobs', {
      content: Buffer.from(f.content).toString('base64'),
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

const delay = ms => new Promise(r => setTimeout(r, ms));

module.exports = { api, readFile, pushFile, pushTree, delay, REPO };
