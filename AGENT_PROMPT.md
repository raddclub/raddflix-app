You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated). Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets. Start immediately without asking for anything.

---

## Step 1 — Set up SSH (always do this first)

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
Expected: `{"ok":true,"version":"3.0.0"}`

Port 5000 is NOT publicly exposed — always test via SSH tunnel to localhost.

## Step 3 — Read current project state

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -150
```

---

## Architecture (know this before touching any code)

**GitHub repo:** `raddclub/raddflix-app` (main branch)
**Oracle server:** Flask at `ubuntu@92.4.95.252` (supervisord, process: `raddflix_radd`)
**Flutter app:** `raddflix_flutter/lib/`

### XOR Encoding — most critical detail

Every `/api/*` response is XOR-encoded. Server strips base64 `=` padding before sending.
Client must re-add before decoding. This fix lives in `core/security/request_encoder.dart`:

```dart
final pad = (4 - b64.length % 4) % 4;
b64 += '=' * pad;  // NEVER remove — fixes 5 critical bugs
```

XOR-excluded paths (plain JSON, no XOR): `/api/auth/login`, `/register`, `/refresh`, `/guest`, `/healthz`

Key formula: `SHA-256("raddflix_xor_v1:{deviceId}:{utc_day}:{utc_hour}")[:32]`

### Database

`sqflite_sqlcipher: 3.1.0+1` — **PINNED — NEVER upgrade** (SQLCipher Dart API changed after this version)

### Video player

Never add `androidAttachSurfaceAfterVideoParameters: true` to `VideoController` — causes 3–5 second black screen on Android.

---

## GitHub API — Only way to push files (NO git shell commands ever)

Write this to a .js file using the Replit `write` tool, then run with `node file.js`.
**Never use heredoc** (`cat > file << 'END'`) — bash scanner may block it if it sees git-like strings.

```javascript
const https = require('https');
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

function api(method, path, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const opts = {
      hostname: 'api.github.com', port: 443,
      path: `/repos/${REPO}/${path}`, method,
      headers: {
        'Authorization': `token ${TOKEN}`, 'User-Agent': 'agent',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {})
      }
    };
    const req = https.request(opts, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve(d); } });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// Single file push:
async function pushFile(path, content, message) {
  const existing = await api('GET', `contents/${path}`);
  const sha = existing.sha || undefined;
  const result = await api('PUT', `contents/${path}`, {
    message, sha,
    content: Buffer.from(content, 'utf8').toString('base64')
  });
  if (!result.content) throw new Error(result.message || 'push failed');
  console.log('Pushed:', path);
}

// Multi-file atomic commit (use for 3+ files to avoid SHA race conditions):
async function pushTree(files, commitMsg) {
  const ref     = await api('GET', 'git/refs/heads/main');
  const commit  = await api('GET', `git/commits/${ref.object.sha}`);
  const blobs   = await Promise.all(files.map(f =>
    api('POST', 'git/blobs', { content: Buffer.from(f.content).toString('base64'), encoding: 'base64' })
  ));
  const newTree = await api('POST', 'git/trees', {
    base_tree: commit.tree.sha,
    tree: files.map((f,i) => ({ path: f.path, mode: '100644', type: 'blob', sha: blobs[i].sha }))
  });
  const newCommit = await api('POST', 'git/commits', {
    message: commitMsg, tree: newTree.sha, parents: [ref.object.sha]
  });
  const updated = await api('PATCH', 'git/refs/heads/main', { sha: newCommit.sha, force: false });
  console.log('Committed:', newCommit.sha.slice(0,7), '—', commitMsg);
}
```

---

## APK Builds — GitHub Actions CI/CD

The repo has a fully working CI/CD pipeline. **Never install Flutter locally** — always use Actions.

### Trigger a build (any Replit account, no setup needed):

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'
echo "Build triggered. Monitor at: https://github.com/raddclub/raddflix-app/actions"
```

### Monitor build progress:

```bash
# Get latest run ID and status
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" | \
  node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  JSON.parse(chunks.join('')).workflow_runs.forEach(r=>{
    console.log('id:'+r.id+' | '+r.status+' | '+(r.conclusion||'running')+' | '+r.created_at);
  });
});"

# Get step-by-step progress for a specific run ID:
RUN_ID=12345678
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs/${RUN_ID}/jobs" | \
  node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  JSON.parse(chunks.join('')).jobs.forEach(j=>{
    console.log('JOB:',j.name,'|',(j.conclusion||j.status));
    j.steps.filter(s=>s.status!=='queued').forEach(s=>
      console.log('  ['+(s.conclusion||s.status)+']',s.name));
  });
});"
```

### Download the built APK:

```bash
# List artifacts for a completed run
RUN_ID=12345678
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs/${RUN_ID}/artifacts" | \
  node -e "
const chunks=[];process.stdin.on('data',c=>chunks.push(c));process.stdin.on('end',()=>{
  JSON.parse(chunks.join('')).artifacts.forEach(a=>{
    console.log(a.name,'| size:',Math.round(a.size_in_bytes/1024/1024)+'MB');
    console.log('  Download URL (expires 1min):');
    // Use Actions artifact download API to get short-lived URL
  });
});"
# Then download at: https://github.com/raddclub/raddflix-app/actions/runs/<RUN_ID>
```

### Build timeline (approx):
- Set up Java + Flutter: ~2 min (cached after first run → ~30s)
- `flutter pub get`: ~1 min
- Gradle patch: ~30s
- `flutter build apk --release`: ~5-8 min (first) / ~3-4 min (cached)
- **Total: ~8-12 min first run, ~5 min with cache**

### What triggers a build automatically:
- Any push to `main` that touches `raddflix_flutter/**`
- Manual `workflow_dispatch` (the curl above)
- NOT triggered by pushes to `.github/`, `docs/`, `*.md`

---

## Oracle server commands (via SSH tunnel only)

```bash
# Check server health
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"

# Check process status
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "supervisorctl status"

# View last 100 server log lines
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 \
  "tail -100 /var/log/supervisor/raddflix_radd.log"

# Test a specific API endpoint (XOR-encoded responses):
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/api/catalog/version"

# Deploy server update (user approval required first):
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 \
  "cd /opt/jazzmax && git stash && git pull origin main && git stash pop && supervisorctl restart raddflix_radd"

# Check disk / RAM before deploying:
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "df -h /home | tail -1; free -h | grep Mem"
```

---

## Multi-agent coordination (when working alongside another agent)

**IMPORTANT: Two agents pushing to the same file within minutes will cause SHA conflicts.**

Strategy:
1. Before starting any work, write a "lock" entry to `agent-hub/locks/active.json`:
   ```json
   { "agent": "AccountNameHere", "started": "2026-06-04T12:00:00Z", "working_on": ["file1.dart","file2.dart"] }
   ```
2. Check if another agent already has a lock before touching those files.
3. Use Git Trees API (pushTree) for bulk commits — eliminates SHA race conditions entirely.
4. On session end, delete the lock file and write TASK_LOG entry.

---

## Using the built-in Debug Screen (no PC needed)

1. Open the app on Android
2. Go to Profile → tap the version number **7 times** (debug-only, stripped from release)
3. Screen shows **two tabs:**
   - **Checks** — live API connectivity, DB health, auth state, sync status
   - **Live Logs** — real-time logcat with color-coded filter chips (ALL/ERROR/WARN/API/SYNC/DB)
4. **Share button** → sends full log file via Android share sheet (WhatsApp, email, etc.)
5. **Clear** chip → clears the in-memory log buffer
6. Auto-scroll pauses when you tap the pause button (so you can read)

**Using logs to debug without ADB:**
- Reproduce the issue
- Open debug screen → Logs tab
- Filter by ERROR or the relevant category
- Share → send to yourself via WhatsApp/Telegram
- Paste into Replit chat for analysis

---

## Non-Negotiable Rules

1. No git shell commands — GitHub Contents API (or Trees API) only
2. No secrets in committed files — GITHUB_TOKEN and ORACLE_SSH_KEY in Replit Secrets only
3. No Oracle destructive changes without explicit user approval
4. Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
5. Debug code must be gated behind `kDebugMode` — stripped from release APK
6. XOR padding fix must always exist in `request_encoder.dart`
7. Never use `androidAttachSurfaceAfterVideoParameters: true`
8. Append session summary to `agent-hub/history/TASK_LOG.md` when done
9. Always fetch fresh SHA immediately before each file push (or use Trees API)
10. Test Oracle via SSH tunnel only — port 5000 not publicly accessible
11. Never use bash heredoc to write scripts with git-like strings — use Replit `write` tool

Full rule details: `https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/PROJECT_RULES.md`

---

## Key Files

```
Flutter (raddflix_flutter/lib/):
  core/security/request_encoder.dart     XOR decode WITH padding fix — critical
  core/api/api_client.dart               Dio + XOR + auth interceptors
  core/db/local_db.dart                  SQLCipher DB schema v17, all CRUD
  core/db/sync_service.dart              Catalog delta sync against Oracle
  core/debug/debug_logger.dart           getLastLines(), shareLogs(), clearBuffer()
  providers/auth_provider.dart           Auth state, login, logout, session restore
  providers/catalog_provider.dart        Catalog state, sync, loadFromDb fallback
  screens/player_screen.dart             VideoController — no androidAttachSurface
  screens/debug_diagnostics_screen.dart  kDebugMode-only: 6 checks + live logcat
  screens/profile_screen.dart            7-tap version text → debug screen (debug only)

Oracle (/opt/jazzmax/radd-hub/hub/):
  request_encoding.py     XOR WSGI hook — strips padding here
  db.py                   SQLite schema + migrations
  routes/catalog_api.py   GET /api/catalog/version|titles|episodes
  routes/mobile_api.py    POST /api/auth/*, usage, history
  routes/subscriptions.py GET /api/subscription/plans|status

CI/CD (.github/workflows/):
  build-apk.yml   Release APK build — triggers on push to raddflix_flutter/**
  ci-tests.yml    API health check + flutter analyze (manual trigger)

Coordination (GitHub main branch):
  AGENT_HANDOFF.md               Full architecture + rules — READ FIRST
  ONBOARDING.md                  SSH + connection setup (4 steps)
  .agents/tasks/BUG_TRACKER.md   All bugs with root causes + fix status
  agent-hub/history/TASK_LOG.md  Session history (append when done)
  agent-hub/locks/active.json    Multi-agent lock file (check before editing files)
  .agents/PROJECT_RULES.md       All 10 rules in detail
  AGENT_PROMPT.md                This file (canonical copy on GitHub)
```

---

## After you finish your session

Push a summary to `agent-hub/history/TASK_LOG.md` via GitHub API:

```markdown
## Session YYYY-MM-DD (AccountName)
- Summary of what you did
- Files changed
- Bugs fixed (with IDs from BUG_TRACKER.md)
- State at end of session
```

Also delete `agent-hub/locks/active.json` if you created one.

---

**My task for you today:**
