# AGENT_PROMPT.md — Universal Prompt for New Replit Agents

> Copy everything below this line and paste it as your first message to any new
> Replit agent working on RaddFlix. The agent will have full context immediately.
> Secrets GITHUB_TOKEN and ORACLE_SSH_KEY are already added to Replit Secrets.

---

You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated). Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets. Start immediately.

## Step 1 — Set up SSH (do this first, always)

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing or malformed'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  {mode: 0o600});
console.log('SSH key ready');
"
```

## Step 2 — Verify Oracle is alive

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```
Expected: `{"status":"ok","version":"3.0.0",...}`

Note: Port 5000 is NOT publicly exposed — always test via SSH tunnel to localhost.

## Step 3 — Read current project state

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -150
```

## Architecture (memorize this)

**GitHub repo:** `raddclub/raddflix-app` (main branch)
**Oracle server:** Flask at `ubuntu@92.4.95.252` (supervisord, process: `raddflix_radd`)
**Flutter app:** `raddflix_flutter/lib/`

**XOR encoding — THE most important detail:**
Every `/api/*` response is XOR-encoded. Server strips base64 `=` padding before sending.
Client must re-add before decoding. This is in `core/security/request_encoder.dart`:
```dart
final pad = (4 - b64.length % 4) % 4;
b64 += '=' * pad;  // NEVER remove this — it fixes 5 critical bugs
```
XOR-excluded paths (plain JSON): `/api/auth/login`, `/register`, `/refresh`, `/guest`, `/healthz`

**DB:** SQLCipher — `sqflite_sqlcipher: 3.1.0+1` **PINNED — NEVER upgrade**

**Video:** `media_kit` — NEVER add `androidAttachSurfaceAfterVideoParameters: true`
(causes 3–5 second black screen on Android)

## GitHub API — Only way to push files (NO git shell commands)

```javascript
// Write this to a .js file using the Replit write tool, then run with: node file.js
// NEVER use heredoc (cat > file << 'END') — bash scanner may block it
// NEVER use git push/commit/add from shell

const https = require('https');
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

async function getSha(path) {
  return new Promise(r => {
    const opts = { hostname:'api.github.com', port:443,
      path:`/repos/${REPO}/contents/${path}`, method:'GET',
      headers:{'Authorization':`token ${TOKEN}`,'User-Agent':'agent',
               'Accept':'application/vnd.github.v3+json'} };
    const req = https.request(opts, res => {
      let d=''; res.on('data',c=>d+=c);
      res.on('end',()=>{ try{r(JSON.parse(d).sha||null);}catch{r(null);} });
    }); req.on('error',()=>r(null)); req.end();
  });
}

async function putFile(path, content, message, sha) {
  const body = JSON.stringify({
    message, content: Buffer.from(content,'utf8').toString('base64'),
    ...(sha ? {sha} : {})
  });
  return new Promise((resolve, reject) => {
    const opts = { hostname:'api.github.com', port:443,
      path:`/repos/${REPO}/contents/${path}`, method:'PUT',
      headers:{'Authorization':`token ${TOKEN}`,'User-Agent':'agent',
               'Accept':'application/vnd.github.v3+json',
               'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)} };
    const req = https.request(opts, res => {
      let d=''; res.on('data',c=>d+=c);
      res.on('end',()=>{ const r=JSON.parse(d); r.content?resolve(r):reject(new Error(r.message)); });
    }); req.on('error',reject); req.write(body); req.end();
  });
}

// Usage:
// const sha = await getSha('path/to/file.dart');   // null if new file
// await putFile('path/to/file.dart', content, 'fix: description', sha);
```

**Important:** Always fetch fresh SHA immediately before each push. Never cache SHA across commits.

## Oracle server commands (via SSH)

```bash
# Check status
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "supervisorctl status"

# View logs
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "tail -100 /var/log/supervisor/raddflix_radd.log"

# Deploy server update (safe sequence — only after user approval for changes)
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 \
  "cd /opt/jazzmax && git stash && git pull origin main && git stash pop && supervisorctl restart raddflix_radd"
```

## Non-Negotiable Rules (full list in `.agents/PROJECT_RULES.md`)

1. No git shell commands — GitHub Contents API only
2. No secrets in committed files
3. No Oracle destructive changes without user approval
4. Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
5. Debug code behind `kDebugMode` only
6. XOR padding fix must always exist in `request_encoder.dart`
7. Never use `androidAttachSurfaceAfterVideoParameters: true`
8. Append session summary to `agent-hub/history/TASK_LOG.md` when done
9. Always fetch fresh SHA before every push
10. Test Oracle via SSH tunnel only

## Key Files

```
Flutter:
  core/security/request_encoder.dart  — XOR decode WITH padding fix
  core/api/api_client.dart            — Dio + XOR + auth interceptors
  core/db/local_db.dart               — SQLCipher DB (schema v17)
  core/db/sync_service.dart           — Catalog sync
  core/debug/debug_logger.dart        — In-memory logger (getLastLines, shareLogs)
  providers/auth_provider.dart        — Auth state + session restore
  providers/catalog_provider.dart     — Catalog state + sync fallback
  screens/player_screen.dart          — VideoController (no androidAttachSurface!)
  screens/debug_diagnostics_screen.dart — kDebugMode-only: checks + logcat viewer
  screens/profile_screen.dart         — 7-tap version text → debug screen

Oracle (/opt/jazzmax/radd-hub/hub/):
  request_encoding.py    — XOR WSGI hook (strips padding here)
  db.py                  — SQLite schema
  routes/catalog_api.py  — /api/catalog/*
  routes/mobile_api.py   — /api/auth/*, usage, history
  routes/subscriptions.py — /api/subscription/*

Coordination:
  AGENT_HANDOFF.md               — Full architecture + rules
  .agents/tasks/BUG_TRACKER.md   — Bug status table
  agent-hub/history/TASK_LOG.md  — Session history (append when done)
  .agents/PROJECT_RULES.md       — All 10 rules in detail
```

## After you finish

Append your session summary to `agent-hub/history/TASK_LOG.md` via GitHub API.

My task for you today:
