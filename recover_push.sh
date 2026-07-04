#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Recovery Push                                            ║
# ║                                                                      ║
# ║  Run this if the agent hit its context limit before auto_commit.sh  ║
# ║  ran. Reads agent-hub/UNPUSHED.txt and pushes every pending entry   ║
# ║  to GitHub via the Trees API.                                        ║
# ║                                                                      ║
# ║  HOW TO RUN (user runs this manually if agent limit is hit):        ║
# ║    bash recover_push.sh                                              ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets (repo scope)           ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

[ -n "${GITHUB_TOKEN:-}" ] || { echo "  ❌ GITHUB_TOKEN is not set" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_LOG="$REPO_ROOT/agent-hub/UNPUSHED.txt"

[ -f "$PENDING_LOG" ] || { echo "  ✓ No UNPUSHED.txt found — nothing to recover."; exit 0; }

# Check if there's anything pending (look for PENDING entries)
if ! grep -q "^## PENDING" "$PENDING_LOG" 2>/dev/null; then
  echo "  ✓ UNPUSHED.txt is empty — all changes are already pushed."
  exit 0
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         RaddFlix — Recovery Push                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Found pending entries in UNPUSHED.txt — pushing now..."
echo ""

node --input-type=module - "$REPO_ROOT" "$PENDING_LOG" <<'ENDNODE'
import fs from 'fs';
import https from 'https';
import path from 'path';

const [,, repoRoot, pendingLog] = process.argv;
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

function ghReq(method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.github.com', path: apiPath, method,
      headers: {
        'Authorization': `token ${TOKEN}`,
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        'User-Agent': 'RaddFlix-Agent',
        ...(data ? {'Content-Length': Buffer.byteLength(data)} : {})
      }
    }, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => {
        const j = JSON.parse(d);
        if (res.statusCode >= 400)
          reject(new Error(`HTTP ${res.statusCode} ${apiPath}: ${JSON.stringify(j).slice(0,300)}`));
        else resolve(j);
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

// Parse UNPUSHED.txt — extract all PENDING blocks
function parsePending(logPath) {
  const text = fs.readFileSync(logPath, 'utf8');
  const blocks = [];
  const blockRegex = /^## PENDING.*?\nmessage: (.+)\nfiles:\n((?:  - .+\n?)*)/gm;
  let match;
  while ((match = blockRegex.exec(text)) !== null) {
    const message = match[1].trim();
    const files   = match[2].trim().split('\n').map(l => l.replace(/^\s*-\s*/, '').trim()).filter(Boolean);
    if (message && files.length > 0) blocks.push({ message, files });
  }
  return blocks;
}

async function pushBlock(block, headSha, treeSha) {
  const treeEntries = [];
  for (const relPath of block.files) {
    const diskPath = path.isAbsolute(relPath) ? relPath : path.join(repoRoot, relPath);
    if (!fs.existsSync(diskPath)) {
      console.warn(`  ⚠️  File not found (skipping): ${diskPath}`);
      continue;
    }
    const content = fs.readFileSync(diskPath, 'utf8');
    const blob    = await ghReq('POST', `/repos/${REPO}/git/blobs`, { content, encoding: 'utf-8' });
    treeEntries.push({ path: relPath, mode: '100644', type: 'blob', sha: blob.sha });
    console.log(`    blob: ${relPath}`);
  }
  if (treeEntries.length === 0) return { headSha, treeSha };

  const newTree   = await ghReq('POST', `/repos/${REPO}/git/trees`, { base_tree: treeSha, tree: treeEntries });
  const newCommit = await ghReq('POST', `/repos/${REPO}/git/commits`, {
    message: block.message, tree: newTree.sha, parents: [headSha]
  });
  await ghReq('PATCH', `/repos/${REPO}/git/refs/heads/main`, { sha: newCommit.sha });
  console.log(`  ✅ Pushed: [${newCommit.sha.slice(0,7)}] ${block.message}`);
  return { headSha: newCommit.sha, treeSha: newTree.sha };
}

async function main() {
  const blocks = parsePending(pendingLog);
  if (blocks.length === 0) {
    console.log('  ✓ No pending entries found — all changes already pushed.');
    return;
  }

  console.log(`  Found ${blocks.length} pending commit(s):\n`);
  blocks.forEach((b, i) => console.log(`  ${i+1}. "${b.message}" (${b.files.length} file(s))`));
  console.log('');

  // Get current HEAD
  const ref     = await ghReq('GET', `/repos/${REPO}/git/ref/heads/main`);
  let headSha   = ref.object.sha;
  const commit  = await ghReq('GET', `/repos/${REPO}/git/commits/${headSha}`);
  let treeSha   = commit.tree.sha;

  // Push each block sequentially (Rule 41 — no parallel pushes)
  for (const block of blocks) {
    console.log(`\n  Pushing: "${block.message}"`);
    ({ headSha, treeSha } = await pushBlock(block, headSha, treeSha));
    await new Promise(r => setTimeout(r, 1300)); // 1.3s delay between pushes (Rule 41)
  }

  // Clear the pending log
  const cleared = `# Pending push log — auto-managed by auto_commit.sh\n# EMPTY — all changes are pushed.\n`;
  fs.writeFileSync(pendingLog, cleared, 'utf8');

  console.log('\n  ✅ Recovery complete — UNPUSHED.txt cleared.');
  console.log(`     https://github.com/${REPO}/commits/main\n`);
}

main().catch(e => { console.error('  ❌ Recovery failed:', e.message); process.exit(1); });
ENDNODE
