#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Auto-Commit & Push (GitHub API)                          ║
# ║                                                                      ║
# ║  Call this after EVERY file edit, big or small. Uses the GitHub     ║
# ║  Trees API directly — no git shell required.                        ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash auto_commit.sh "message" file1 [file2 ...]                  ║
# ║    bash auto_commit.sh "fix player zoom" raddflix_flutter/lib/screens/player_screen.dart
# ║    DRY_RUN=1 bash auto_commit.sh "preview" file1                    ║
# ║                                                                      ║
# ║  Arguments:                                                          ║
# ║    $1  — commit message (required)                                   ║
# ║    $2+ — repo-relative paths of files that changed (required)       ║
# ║           These are read from disk and pushed via the GitHub API.   ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets (repo scope)           ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

[ -n "${GITHUB_TOKEN:-}" ] || { echo "  ❌ GITHUB_TOKEN is not set" >&2; exit 1; }
[ "${1:-}" != "" ] || { echo "  ❌ Usage: bash auto_commit.sh \"message\" file1 [file2 ...]" >&2; exit 1; }
[ "${2:-}" != "" ] || { echo "  ❌ At least one file path is required" >&2; exit 1; }

COMMIT_MSG="$1"
shift

# Resolve the repo root — the directory this script lives in
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$DRY_RUN:-0}" != "1" ] || { echo "  ℹ️  DRY_RUN=1 — would commit: $COMMIT_MSG"; exit 0; }

echo ""
echo "  → Committing: $COMMIT_MSG"
echo "    Files: $*"
echo ""

# Pass everything to the Node.js implementation
node --input-type=module - "$COMMIT_MSG" "$REPO_ROOT" "$@" <<'ENDNODE'
import fs from 'fs';
import https from 'https';
import path from 'path';

const [, , commitMsg, repoRoot, ...filePaths] = process.argv;
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

function ghReq(method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.github.com',
      path: apiPath,
      method,
      headers: {
        'Authorization': `token ${TOKEN}`,
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        'User-Agent': 'RaddFlix-Agent',
        ...(data ? {'Content-Length': Buffer.byteLength(data)} : {})
      }
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        const j = JSON.parse(d);
        if (res.statusCode >= 400) {
          reject(new Error(`HTTP ${res.statusCode} ${apiPath}: ${JSON.stringify(j).slice(0,300)}`));
        } else resolve(j);
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function main() {
  // 1. Get HEAD commit SHA for main
  const ref    = await ghReq('GET', `/repos/${REPO}/git/ref/heads/main`);
  const headSha = ref.object.sha;

  // 2. Get base tree SHA
  const commit  = await ghReq('GET', `/repos/${REPO}/git/commits/${headSha}`);
  const treeSha  = commit.tree.sha;

  // 3. Build blob list from the provided file paths
  const treeEntries = [];
  for (const relPath of filePaths) {
    const diskPath = path.isAbsolute(relPath) ? relPath : path.join(repoRoot, relPath);
    if (!fs.existsSync(diskPath)) {
      console.error(`  ❌ File not found: ${diskPath}`);
      process.exit(1);
    }
    const content = fs.readFileSync(diskPath, 'utf8');
    const blob = await ghReq('POST', `/repos/${REPO}/git/blobs`, { content, encoding: 'utf-8' });
    treeEntries.push({ path: relPath, mode: '100644', type: 'blob', sha: blob.sha });
    console.log(`  blob: ${relPath}`);
  }

  // 4. Create a new tree on top of the base
  const newTree = await ghReq('POST', `/repos/${REPO}/git/trees`, {
    base_tree: treeSha,
    tree: treeEntries
  });

  // 5. Create the commit
  const newCommit = await ghReq('POST', `/repos/${REPO}/git/commits`, {
    message: commitMsg,
    tree: newTree.sha,
    parents: [headSha]
  });

  // 6. Fast-forward main to the new commit
  await ghReq('PATCH', `/repos/${REPO}/git/refs/heads/main`, { sha: newCommit.sha });

  console.log(`  ✅ Pushed: ${newCommit.sha}`);
  console.log(`     https://github.com/${REPO}/commit/${newCommit.sha}`);
}

main().catch(e => { console.error('  ❌ Push failed:', e.message); process.exit(1); });
ENDNODE
