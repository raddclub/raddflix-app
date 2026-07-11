#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Auto-Commit & Push (GitHub API)                          ║
# ║                                                                      ║
# ║  Call this after EVERY file edit, big or small.                     ║
# ║  Uses the GitHub Trees API — no git shell required.                 ║
# ║                                                                      ║
# ║  WORKFLOW (agent must follow this order every time):                ║
# ║    1. BEFORE editing: log_pending.sh "message" file1 [file2 ...]   ║
# ║    2. Edit the files                                                 ║
# ║    3. AFTER editing: auto_commit.sh "message" file1 [file2 ...]    ║
# ║       (auto_commit clears the pending log on success)               ║
# ║                                                                      ║
# ║  If agent hits context limit between steps 2 and 3:                 ║
# ║    User runs:  bash recover_push.sh                                 ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash auto_commit.sh "message" file1 [file2 ...]                  ║
# ║    DRY_RUN=1 bash auto_commit.sh "preview" file1                    ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets (repo scope)           ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

[ -n "${GITHUB_TOKEN:-}" ] || { echo "  ❌ GITHUB_TOKEN is not set" >&2; exit 1; }
[ "${1:-}" != "" ]         || { echo "  ❌ Usage: bash auto_commit.sh \"message\" file1 [file2 ...]" >&2; exit 1; }
[ "${2:-}" != "" ]         || { echo "  ❌ At least one file path is required" >&2; exit 1; }

COMMIT_MSG="$1"; shift
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_LOG="$REPO_ROOT/agent-hub/UNPUSHED.txt"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "  ℹ️  DRY_RUN=1 — would commit: $COMMIT_MSG ($*)"
  exit 0
fi

if [ "${SKIP_PREFLIGHT:-0}" != "1" ]; then
  if ! bash "$REPO_ROOT/preflight_check.sh" "$@"; then
    echo "  ❌ Aborting push — preflight_check.sh found a known-bad pattern (see above)." >&2
    exit 1
  fi
fi

echo ""; echo "  → Committing: $COMMIT_MSG"; echo "    Files: $*"; echo ""

node --input-type=module - "$COMMIT_MSG" "$REPO_ROOT" "$PENDING_LOG" "$@" <<'ENDNODE'
import fs from 'fs';
import https from 'https';
import path from 'path';

const [,, commitMsg, repoRoot, pendingLog, ...filePaths] = process.argv;
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

async function main() {
  const ref      = await ghReq('GET', `/repos/${REPO}/git/ref/heads/main`);
  const headSha  = ref.object.sha;
  const commit   = await ghReq('GET', `/repos/${REPO}/git/commits/${headSha}`);
  const treeSha  = commit.tree.sha;

  const treeEntries = [];
  for (const relPath of filePaths) {
    const diskPath = path.isAbsolute(relPath) ? relPath : path.join(repoRoot, relPath);
    if (!fs.existsSync(diskPath)) {
      console.error(`  ❌ File not found: ${diskPath}`); process.exit(1);
    }
    // Binary assets (images, fonts, etc.) must be base64-encoded — reading
    // them as utf8 corrupts the bytes. Detect by extension.
    const BINARY_EXT = new Set(['.png','.jpg','.jpeg','.gif','.webp','.ico','.ttf','.otf','.woff','.woff2','.mp3','.mp4','.wav','.zip']);
    const isBinary = BINARY_EXT.has(path.extname(diskPath).toLowerCase());
    const blob = isBinary
      ? await ghReq('POST', `/repos/${REPO}/git/blobs`, { content: fs.readFileSync(diskPath).toString('base64'), encoding: 'base64' })
      : await ghReq('POST', `/repos/${REPO}/git/blobs`, { content: fs.readFileSync(diskPath, 'utf8'), encoding: 'utf-8' });
    treeEntries.push({ path: relPath, mode: '100644', type: 'blob', sha: blob.sha });
    console.log(`  blob: ${relPath}`);
  }

  const newTree   = await ghReq('POST', `/repos/${REPO}/git/trees`, { base_tree: treeSha, tree: treeEntries });
  const newCommit = await ghReq('POST', `/repos/${REPO}/git/commits`, {
    message: commitMsg, tree: newTree.sha, parents: [headSha]
  });
  await ghReq('PATCH', `/repos/${REPO}/git/refs/heads/main`, { sha: newCommit.sha });

  // Clear the pending log on success
  const cleared = `# Pending push log — auto-managed by auto_commit.sh\n# EMPTY — all changes are pushed.\n`;
  fs.writeFileSync(pendingLog, cleared, 'utf8');

  console.log(`\n  ✅ Pushed: ${newCommit.sha}`);
  console.log(`     https://github.com/${REPO}/commit/${newCommit.sha}\n`);
}

main().catch(e => { console.error('  ❌ Push failed:', e.message); process.exit(1); });
ENDNODE
