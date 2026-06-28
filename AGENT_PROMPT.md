You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets.
**Start immediately. Do not ask for anything.**

---

## Step 1 — Session init (idempotent — skips what's already done)

Run once at the start of every session. Safe to re-run — each line only executes if its target is missing.

```bash
# SSH key (skipped if already written)
[ -f ~/.ssh/raddflix_oracle ] && echo "✓ SSH key" || node -e "
const raw=process.env.ORACLE_SSH_KEY||'';
const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if(!m){console.error('ORACLE_SSH_KEY missing');process.exit(1);}
const fs=require('fs'),os=require('os');
fs.mkdirSync(os.homedir()+'/.ssh',{recursive:true});
fs.writeFileSync(os.homedir()+'/.ssh/raddflix_oracle',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});
console.log('SSH key written');
"

# Push helper (skipped if already downloaded)
[ -f /home/runner/workspace/.local/push.js ] && echo "✓ push helper" || (
  mkdir -p /home/runner/workspace/.local &&
  curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/push.js" \
    > /home/runner/workspace/.local/push.js && echo "push helper downloaded"
)

# Oracle health check (always verify)
ssh -i ~/.ssh/raddflix_oracle -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

---

## Step 2 — Read project state

**Read TASKS.md first** — continue any OPEN/IN-PROGRESS tasks before starting new work.

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
# Only if you need historical context:
# curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -60
```

---

## Step 3 — Edit & push files

> All file content stays in memory — never write Dart/Python/etc. to disk.
> Read from GitHub → patch string → push back. No disk I/O = no stale-file risk.

### Write your session script, then run it

Use the Replit `write` tool to create `/home/runner/workspace/.local/run.js`, then:
```bash
node /home/runner/workspace/.local/run.js
```

**Rules: never use `sed` for multi-line Dart. Always push SEQUENTIALLY — parallel pushes cause SHA 422 conflicts.**

```javascript
const { readFile, pushFile, validatePatch, delay } = require('/home/runner/workspace/.local/push.js');

const FILE = 'raddflix_flutter/lib/screens/player_screen.dart';
const OLD  = `exact old string here`;
const NEW  = `replacement string here`;

async function main() {
  let dart = await readFile(FILE);

  // validatePatch throws immediately if OLD is not found — shows nearest matching
  // lines so you can see what changed. Always call before .replace().
  validatePatch(dart, OLD, FILE);
  dart = dart.replace(OLD, NEW);

  const sha = await pushFile(FILE, dart, 'fix: description');
  await delay(1500);

  let tasks = await readFile('agent-hub/TASKS.md');
  validatePatch(tasks, '⏳ IN PROGRESS');
  tasks = tasks.replace('⏳ IN PROGRESS', '✅ DONE');
  await pushFile('agent-hub/TASKS.md', tasks, `chore(tasks): done (${sha})`);
  await delay(1500);

  let log = await readFile('agent-hub/history/TASK_LOG.md');
  log += `\n---\n\n## Session ${new Date().toISOString().slice(0,10)} — what you did\n\n` +
         `- Task: ...\n- Files: ...\n- Commit: ${sha}\n`;
  await pushFile('agent-hub/history/TASK_LOG.md', log, 'docs(tasklog): session summary');
}
main().catch(e => { console.error(e.message); process.exit(1); });
```

### Multiple files → use pushTree (one atomic commit, no SHA conflicts)

```javascript
const { readFile, pushTree, validatePatch } = require('/home/runner/workspace/.local/push.js');

let dart = await readFile('raddflix_flutter/lib/screens/player_screen.dart');
let app  = await readFile('raddflix_flutter/lib/app.dart');

validatePatch(dart, OLD_DART, 'screens/player_screen.dart');
dart = dart.replace(OLD_DART, NEW_DART);

validatePatch(app, OLD_APP, 'app.dart');
app = app.replace(OLD_APP, NEW_APP);

await pushTree([
  { path: 'raddflix_flutter/lib/screens/player_screen.dart', content: dart },
  { path: 'raddflix_flutter/lib/app.dart',                   content: app  },
], 'fix: description');
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
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.run_number,'|',r.status,'|',(r.conclusion||'-'),'|',r.head_sha.slice(0,7)));
  });"
```

---

## Non-Negotiable Rules

**Rule 0 — Task tracking (mandatory, every session):**
Before ANY change → add row to `agent-hub/TASKS.md` marked ⏳ IN PROGRESS.
After pushing → mark ✅ DONE. Append summary to `agent-hub/history/TASK_LOG.md`.

| # | Rule |
|---|------|
| 1 | **Never** add `androidAttachSurfaceAfterVideoParameters: true` — causes black screen |
| 2 | **Never** upgrade `sqflite_sqlcipher` past `3.1.0+1` |
| 3 | **`db.setting(k)`** not `db.get_setting(k)` — `get_setting` does not exist |
| 4 | **`DebugDiagnosticsScreen`** must NOT be gated by `kDebugMode` — 5-tap version access in release APK |
| 5 | **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only |
| 6 | **Never name a local var `_np`** in `player_screen.dart` — silently shadows the class getter |
| 7 | **XOR padding fix** in `request_encoder.dart` — never remove the `'=' * pad` line |
| 8 | **Bulk DELETEs** — use `sqlite3.connect()` + `BEGIN IMMEDIATE`, never `db.conn()` |
| 9 | **MediaTek recovery-seek** — `vf=` / `framedrop` / `speed > 1×` setProperty needs: set → `Future.delayed(150ms)` → `_player.seek(pos)` |
| 10 | **Flutter icons** — `replay_15` / `forward_15` don't exist; use `replay_10` / `forward_10` / `replay_30` / `forward_30` |
| 11 | **PROXY_BYPASS=1** — all proxy chains must use `is_proxy_bypass()` guard → `[None]`; never call `pool.get_best()` |
| 12 | **SAPI 401 + `<!DOCTYPE HTML` body** = dead proxy error, not JazzDrive |

→ Full rules + architecture: `agent-hub/RULES.md` · `agent-hub/CONTEXT.md`

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
  jazzdrive.py  proxy_pool.py  keepalive.py
  routes/catalog_api.py  routes/mobile_api.py  routes/admin.py

Oracle DB:   /opt/jazzmax/radd-hub/data/radd_hub.db
Oracle logs: /opt/jazzmax/radd-hub/data/logs/raddhub.log

Coordination (GitHub main):
  agent-hub/TASKS.md          ← READ FIRST
  agent-hub/RULES.md          Full rules
  agent-hub/CONTEXT.md        Architecture + proxy
  agent-hub/scripts/push.js   Push helper (readFile / pushFile / pushTree / validatePatch)
  AGENT_HANDOFF.md            Current state
  agent-hub/history/TASK_LOG.md

Workspace (Replit — persists, never committed to git):
  ~/.ssh/raddflix_oracle                       Oracle SSH key
  /home/runner/workspace/.local/push.js        Push helper
  /home/runner/workspace/.local/run.js         Session script
```
