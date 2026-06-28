You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets.
**Start immediately. Do not ask for anything.**

---

## Step 1 — SSH key (always first, every session)

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing'); process.exit(1); }
require('fs').mkdirSync(require('os').homedir()+'/.ssh', { recursive: true });
require('fs').writeFileSync(require('os').homedir()+'/.ssh/raddflix_oracle',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  { mode: 0o600 });
console.log('SSH key ready →', require('os').homedir()+'/.ssh/raddflix_oracle');
"
```

Verify Oracle is alive:
```bash
ssh -i ~/.ssh/raddflix_oracle -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

---

## Step 2 — Read project state

**Read `agent-hub/TASKS.md` first** — continue any OPEN/IN-PROGRESS tasks before starting new work.

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -80
```

---

## Step 3 — Edit & push files

> **No /tmp ever.** `/tmp` is wiped by the OS unpredictably. All persistent files go inside the
> Replit workspace (`/home/runner/workspace/.local/`) or home dir (`~/.ssh/` for keys).
> File *content* (Dart, Python, etc.) is never written to disk at all — read from GitHub into
> memory, patch the string, push back immediately.

### 3a. Download push helper (once per session — persists in workspace)

```bash
mkdir -p /home/runner/workspace/.local
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/push.js" \
  > /home/runner/workspace/.local/push.js
echo "Push helper ready"
```

Provides: `readFile(repoPath)` → string, `pushFile(repoPath, newContent, message)` → sha,
`pushTree(files, msg)` → sha, `delay(ms)`.

### 3b. Read → patch in memory → push

Write your session script using the Replit `write` tool to `/home/runner/workspace/.local/run.js`,
then run `node /home/runner/workspace/.local/run.js`.

**Never use `sed` for multi-line Dart — use JS string replace.**
**Always push SEQUENTIALLY with `await delay(1500)` between calls — parallel pushes cause SHA 422 conflicts.**

```javascript
const { readFile, pushFile, delay } = require('/home/runner/workspace/.local/push.js');

async function main() {
  // 1. Read from GitHub into memory
  let dart = await readFile('raddflix_flutter/lib/screens/player_screen.dart');

  // 2. Patch in memory — verify the patch actually fired
  const before = dart;
  dart = dart.replace('OLD_STRING', 'NEW_STRING');
  if (dart === before) throw new Error('patch had no effect — check OLD_STRING');

  // 3. Push files SEQUENTIALLY
  const sha = await pushFile(
    'raddflix_flutter/lib/screens/player_screen.dart',
    dart,
    'fix: short description'
  );
  await delay(1500);

  // 4. Mark task done in TASKS.md
  let tasks = await readFile('agent-hub/TASKS.md');
  tasks = tasks.replace('⏳ IN PROGRESS', '✅ DONE');
  await pushFile('agent-hub/TASKS.md', tasks, `chore(tasks): mark done (${sha})`);
  await delay(1500);

  // 5. Append session summary to TASK_LOG.md
  let log = await readFile('agent-hub/history/TASK_LOG.md');
  log += `\n---\n\n## Session ${new Date().toISOString().slice(0, 10)} — describe what you did\n\n- Task: ...\n- Files changed: ...\n- Commit: ${sha}\n`;
  await pushFile('agent-hub/history/TASK_LOG.md', log, 'docs(tasklog): session summary');
}
main().catch(e => { console.error(e.message); process.exit(1); });
```

### 3c. Multiple files in one atomic commit — use pushTree

```javascript
const { readFile, pushTree } = require('/home/runner/workspace/.local/push.js');

const dart = await readFile('raddflix_flutter/lib/screens/player_screen.dart');
const app  = await readFile('raddflix_flutter/lib/app.dart');
// ... patch dart and app in memory ...

await pushTree([
  { path: 'raddflix_flutter/lib/screens/player_screen.dart', content: dart },
  { path: 'raddflix_flutter/lib/app.dart',                   content: app  },
], 'fix: atomic description');
```

---

## Step 4 — Restart Oracle Flask

*Only needed if you edited Oracle Python files.*

```bash
ssh -i ~/.ssh/raddflix_oracle -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sleep 3 && curl -s http://localhost:5000/healthz"
```

Oracle git pull (always stash — Oracle has local uncommitted files):
```bash
ssh -i ~/.ssh/raddflix_oracle -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cd /opt/jazzmax/radd-hub && git stash && git pull && git stash pop"
```

---

## Step 5 — Trigger APK build

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'
```

Check last 5 runs:
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.run_number,'|',r.status,'|',(r.conclusion||'-'),'| commit:',r.head_sha.slice(0,7)));
  });"
```

---

## Non-Negotiable Rules

**Rule 0 — Task tracking is mandatory (every session, no exceptions):**
Before ANY change → add row to `agent-hub/TASKS.md` marked ⏳ IN PROGRESS.
After pushing → mark ✅ DONE. Append session summary to `agent-hub/history/TASK_LOG.md`.

**Rules that cause silent bugs or data loss if missed:**

| # | Rule |
|---|------|
| 1 | **Never** add `androidAttachSurfaceAfterVideoParameters: true` — causes black screen |
| 2 | **Never** upgrade `sqflite_sqlcipher` past `3.1.0+1` |
| 3 | **`db.setting(k)`** not `db.get_setting(k)` — `get_setting` does not exist |
| 4 | **`DebugDiagnosticsScreen`** must NOT be gated by `kDebugMode` — accessible in release APK via 5-tap on version |
| 5 | **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only |
| 6 | **`_np` local variable** in `player_screen.dart` — never name a local var `_np`, silently shadows the class getter |
| 7 | **XOR padding fix** in `core/security/request_encoder.dart` — never remove the `'=' * pad` line |
| 8 | **Bulk DELETEs** — use `sqlite3.connect()` + `BEGIN IMMEDIATE`, never `db.conn()` |
| 9 | **MediaTek recovery-seek** — any `_np.setProperty` touching `vf=` / `framedrop` / `speed > 1×` needs: set property → `Future.delayed(150ms)` → `_player.seek(position)` |
| 10 | **Flutter icons** — `replay_15` / `forward_15` do not exist in Flutter 3.22.3; use `replay_10` / `forward_10` / `replay_30` / `forward_30` |
| 11 | **JazzDrive is globally accessible** — with `PROXY_BYPASS=1`, all proxy chains must use `is_proxy_bypass()` guard → `[None]`. Never call `pool.get_best()` or `pool.get_proxy_chain()` when bypass=1 |
| 12 | **SAPI 401 with `<!DOCTYPE HTML` body** = dead proxy returning its own error, not JazzDrive |

→ Full rules + architecture: `agent-hub/RULES.md` and `agent-hub/CONTEXT.md`

---

## Key file paths

```
Flutter:  raddflix_flutter/lib/
  core/security/request_encoder.dart   XOR decode + padding fix (critical)
  core/api/api_client.dart             Dio + XOR + auth interceptors
  core/db/local_db.dart                SQLCipher DB, schema v17
  screens/player_screen.dart           Video player (~7,500 lines)
  providers/auth_provider.dart         Auth state + session restore

Oracle:   /opt/jazzmax/radd-hub/hub/
  jazzdrive.py                         JazzDrive session, OTP, upload, keepalive
  proxy_pool.py                        Proxy pool management
  keepalive.py                         Heartbeat upload scheduler
  routes/catalog_api.py                /api/catalog/*
  routes/mobile_api.py                 /api/auth/*, usage, history, /api/app/config
  routes/admin.py                      Admin panel API

Oracle DB:   /opt/jazzmax/radd-hub/data/radd_hub.db
Oracle logs: /opt/jazzmax/radd-hub/data/logs/raddhub.log

Coordination (GitHub main branch):
  agent-hub/TASKS.md                   ← READ FIRST every session
  agent-hub/CONTEXT.md                 System context + proxy architecture
  agent-hub/RULES.md                   Full rules list
  agent-hub/scripts/push.js            Push helper (readFile / pushFile / pushTree)
  AGENT_HANDOFF.md                     Current state + handoff notes
  agent-hub/history/TASK_LOG.md        Session history (append when done)
  AGENT_PROMPT.md                      This file

Workspace (Replit — persists across sessions, never committed):
  ~/.ssh/raddflix_oracle               Oracle SSH key (written by Step 1)
  /home/runner/workspace/.local/push.js   Push helper (downloaded by Step 3a)
  /home/runner/workspace/.local/run.js    Session script (written per task)
```
