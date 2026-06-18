You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets.
**Start immediately. Do not ask for anything.**

---

## Step 1 — Set up SSH key (always first, every session)

Run this in the bash tool:

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  { mode: 0o600 });
console.log('SSH key ready');
"
```

Verify Oracle is alive:
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

---

## Step 2 — Read current project state

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -80
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
```

**Read `agent-hub/TASKS.md` first** — it lists open/in-progress tasks. Continue any OPEN tasks before starting new work.

---

## Step 2.5 — Local Workspace (ALWAYS do this before editing any file)

**Download all files you plan to edit into `/tmp/raddflix/` first. Edit locally. Push once at the end.**
This avoids repeated GitHub API round-trips and prevents SHA drift mid-edit.

```bash
mkdir -p /tmp/raddflix

# Download everything you plan to touch in one batch:
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/raddflix_flutter/lib/screens/player_screen.dart" > /tmp/raddflix/player_screen.dart
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md" > /tmp/raddflix/TASKS.md
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" > /tmp/raddflix/TASK_LOG.md
# … add any other files you need
```

**Edit using Node.js string replacement** (never use sed for multi-line Dart):
```javascript
const fs = require('fs');
let c = fs.readFileSync('/tmp/raddflix/player_screen.dart', 'utf8');
c = c.replace(OLD_STRING, NEW_STRING);
if (c === original) throw new Error('patch had no effect!');
fs.writeFileSync('/tmp/raddflix/player_screen.dart', c);
```

**Push all changed files in one go** using the `pushFile` helper from Step 3, or the `pushTree`
helper for an atomic multi-file commit. Always push SEQUENTIALLY with 1.5s delays between calls.

```javascript
// Recommended push script pattern — write to /tmp/push.js and run with node /tmp/push.js:
const fs = require('fs'), https = require('https');
const TOKEN = process.env.GITHUB_TOKEN, REPO = 'raddclub/raddflix-app';

function api(method, path, body) { /* … same as Step 3 … */ }

async function pushFile(repoPath, localPath, message) {
  const meta = await api('GET', `contents/${repoPath}`);   // always fetch fresh SHA
  const content = fs.readFileSync(localPath).toString('base64');
  const r = await api('PUT', `contents/${repoPath}`, { message, content, sha: meta.sha });
  if (!r.commit) throw new Error(r.message);
  console.log('✅', repoPath, '->', r.commit.sha.slice(0,7));
  return r.commit.sha.slice(0,7);
}

const delay = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const sha1 = await pushFile('raddflix_flutter/lib/screens/player_screen.dart',
                              '/tmp/raddflix/player_screen.dart',
                              'fix: description');
  await delay(1500);
  await pushFile('agent-hub/TASKS.md', '/tmp/raddflix/TASKS.md',
                 `chore(tasks): mark X done (${sha1})`);
  await delay(1500);
  await pushFile('agent-hub/history/TASK_LOG.md', '/tmp/raddflix/TASK_LOG.md',
                 'docs(tasklog): document fix X');
}
main().catch(e => { console.error(e.message); process.exit(1); });
```

> **Why `pushFile` fetches the SHA fresh inside the function**: if any earlier push in the same
> session already bumped that file, a stale SHA will cause a 422 conflict. Always GET the file
> meta right before PUT — never cache SHAs across pushes.


---

## Step 3 — GitHub file push (the ONLY way — no git shell ever)

**For 1–2 files** — write to `/tmp/push.js` using Replit `write` tool, then `node /tmp/push.js`:

```javascript
const https = require('https'), fs = require('fs');
const TOKEN = process.env.GITHUB_TOKEN, REPO = 'raddclub/raddflix-app';

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

async function pushFile(filePath, localPath, message) {
  const existing = await api('GET', `contents/${filePath}`);
  const sha = existing.sha;
  const content = fs.readFileSync(localPath).toString('base64');
  const result = await api('PUT', `contents/${filePath}`, { message, sha, content });
  if (!result.commit) throw new Error(result.message || 'push failed');
  console.log('✅', filePath, '→', result.commit.sha.slice(0,7));
}
```

**For 3+ files — push SEQUENTIALLY (never in parallel).**
Parallel pushes cause branch tree SHA conflicts. Always `await` each push before the next,
and add a 1–2s delay between calls (`await new Promise(r => setTimeout(r, 1200))`).

**For one atomic multi-file commit** use the Trees API:

```javascript
async function pushTree(files, commitMsg) {
  const ref    = await api('GET', 'git/refs/heads/main');
  const commit = await api('GET', `git/commits/${ref.object.sha}`);
  const blobs  = await Promise.all(files.map(f =>
    api('POST', 'git/blobs', {
      content: Buffer.from(fs.readFileSync(f.local)).toString('base64'),
      encoding: 'base64'
    })
  ));
  const tree   = await api('POST', 'git/trees', {
    base_tree: commit.tree.sha,
    tree: files.map((f,i) => ({ path: f.path, mode: '100644', type: 'blob', sha: blobs[i].sha }))
  });
  const nc     = await api('POST', 'git/commits', {
    message: commitMsg, tree: tree.sha, parents: [ref.object.sha]
  });
  await api('PATCH', 'git/refs/heads/main', { sha: nc.sha, force: false });
  console.log('✅ Committed:', nc.sha.slice(0,7), '—', commitMsg);
}
```

---

## Step 4 — After editing Oracle Python files, restart Flask

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sleep 3 && curl -s http://localhost:5000/healthz"
```

Oracle pull from GitHub (if needed):
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cd /opt/jazzmax/radd-hub && git stash && git pull && git stash pop"
```

---

## Step 5 — Trigger and monitor APK build

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.run_number,'|',r.status,'|',(r.conclusion||'-'),'| commit:',r.head_sha.slice(0,7)));
  });"
```

---

## Non-Negotiable Rules

**Rule 0 (CRITICAL): Task tracking is mandatory.**
Before starting ANY change/fix/feature: add a row to `agent-hub/TASKS.md` marked ⏳ IN PROGRESS.
Mark ✅ DONE when complete + pushed. This is the handoff bridge between agents.

1. **JazzDrive is globally accessible — NO geo-restriction of any kind.**
   wg0 WireGuard works for ALL JazzDrive calls. With PROXY_BYPASS=1, every proxy chain
   (`_ar_chain`, `_s2_chain`, `_sub_chain`, etc.) must use `is_proxy_bypass()` guard → `[None]` direct.
   Never call `pool.get_best()` or `pool.get_proxy_chain()` when bypass=1 — pool is dead/untested.
2. **SAPI 401 with `<!DOCTYPE HTML` body** = dead proxy returning its own error, not JazzDrive.
3. **No git shell commands** — GitHub API only (Contents or Trees API). Push files SEQUENTIALLY — parallel pushes cause SHA race conditions.
4. **No bash heredoc** for Node scripts — use Replit `write` tool or `cat > file << 'EOF'` pattern instead
5. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
6. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (causes black screen)
7. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
8. **XOR padding fix** must always stay in `core/security/request_encoder.dart`:
   `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
9. **No Oracle destructive changes** without explicit user approval
10. **Append session summary** to `agent-hub/history/TASK_LOG.md` when done
11. **Always fetch fresh SHA** right before `pushFile` (or use `pushTree` for multi-file)
12. **Debug screen** (`DebugDiagnosticsScreen`) is intentionally NOT gated by `kDebugMode` — accessible in release APK via 5-tap on version. Do NOT re-add `if (!kDebugMode)` gate. Other debug-only code should still be gated.
13. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist in `db.py`
14. **For bulk DELETEs** use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()`
15. **Oracle git pull**: always `git stash && git pull && git stash pop` — Oracle has local uncommitted files
16. **Flutter icons**: Only use icon names confirmed in Flutter 3.22.3 source. `replay_15`, `forward_15` (and `_rounded` variants) do NOT exist. Use `replay_10` / `forward_10` / `replay_30` / `forward_30`.
17. **`_np` getter in player_screen.dart**: Never name a local variable `_np` inside `player_screen.dart`. The class has `NativePlayer get _np => _player.platform as NativePlayer`. A local `final _np = anything` silently shadows it — any `_np.setProperty()` in that scope compiles but calls the wrong object.
18. **Import hygiene**: When removing a widget or class from `player_screen.dart`, always check for and remove its import. Orphaned imports cause Dart unused-import warnings on every build.
19. **Clock/timer displays**: Any timer driving a visible HH:MM clock overlay must fire at ≤10s intervals. 30s intervals leave the display up to 30s stale.
20. **Local workspace first**: Before editing any file, download it to `/tmp/raddflix/`. Edit locally. Push at the end using `pushFile` (always fetches fresh SHA inside the fn). Never edit-and-push in the same GitHub API round-trip without downloading first. See Step 2.5.
21. **MediaTek recovery-seek after pipeline changes**: Any `_np.setProperty` that touches the decoder pipeline mid-play (`vf=`, `framedrop`, `speed` above 1×) needs: set property → `Future.delayed(150ms)` → `_player.seek(position)`. Not needed for audio-only props (`af=`, `audio-delay`, `volume`).
22. **`_lastAppliedVf` must be primed on gate block**: `_applyVideoFilters` startup gate must call `_lastAppliedVf = _buildVfString(p)` in the blocked branch. Any guard/gate that returns early must still update its "already-done" tracking state or the next call bypasses dedup.

Full rules: `agent-hub/RULES.md` | Architecture: `agent-hub/CONTEXT.md`

---

## Key file paths

```
Flutter:  raddflix_flutter/lib/
  core/security/request_encoder.dart   XOR decode + padding fix (critical)
  core/api/api_client.dart             Dio + XOR + auth interceptors
  core/db/local_db.dart                SQLCipher DB, schema v17
  screens/player_screen.dart           Video player (7,094 lines) — no androidAttachSurface
  providers/auth_provider.dart         Auth state + session restore

Oracle:   /opt/jazzmax/radd-hub/hub/
  jazzdrive.py                         JazzDrive session, OTP, upload, keepalive
  proxy_pool.py                        Proxy pool management
  keepalive.py                         Heartbeat upload scheduler
  routes/catalog_api.py                /api/catalog/*
  routes/mobile_api.py                 /api/auth/*, usage, history, /api/app/config
  routes/admin.py                      Admin panel API

Oracle DB: /opt/jazzmax/radd-hub/data/radd_hub.db
Oracle logs: /opt/jazzmax/radd-hub/data/logs/raddhub.log

Coordination (GitHub main):
  agent-hub/TASKS.md                   ← READ FIRST every session
  agent-hub/CONTEXT.md                 System context + proxy architecture
  agent-hub/RULES.md                   Full rules list
  AGENT_HANDOFF.md                     Current state + handoff notes
  .agents/tasks/BUG_TRACKER.md         All known bugs + fix status
  agent-hub/history/TASK_LOG.md        Session history (append when done)
  AGENT_PROMPT.md                      This file
```

---

## player_screen.dart — current status (2026-06-18)

| Item | Detail |
|------|--------|
| Lines | 7,488 (as of 2026-06-18, after LP2 fix) |
| Last commit | `69824d79` — FIX-BLACKSCREEN-LP2: recovery seek on longPress START |
| Last build | ✅ run#27729363694 (build triggered by latest commits — check GitHub Actions) |
| Total bugs fixed this session | 17 (15 previous + FIX-VF-BLACKSCREEN-GAP `a7898f8f` + FIX-BLACKSCREEN-LP2 `69824d79`) |
| Remaining | Duplicate UX systems (D1–D6), ghost features (safe no-ops), architecture (A1–A6) |

### Critical player_screen.dart rules (hardware-specific bugs)

| Rule | Detail |
|------|--------|
| vf= mid-play | NEVER call `_np.setProperty('vf', ...)` from startup code paths while playing. Check `_firstVfApplied` gate + `_lastAppliedVf` dedup. Even empty `vf=` destroys GL surface on MediaTek/Infinix HW decoder → black screen. When gate blocks, still set `_lastAppliedVf = _buildVfString(p)`. Mid-play vf= changes (user-initiated) require the recovery-seek pattern after. |
| hwdec mid-play | NEVER call `_np.setProperty('hwdec', ...)` while video is playing or media is open. Guard: `if (!_playing && !_player.state.playing && _player.state.duration == Duration.zero && !_videoSurfaceReady)`. |
| Speed channel ordering | `_setSpeed()` MUST use `_np.setProperty('speed', ...)` — NOT `_player.setRate()`. Both framedrop and speed must go through the same NativePlayer channel. |
| _videoSurfaceReady latch | Set `true` immediately after `VideoController` construction — NOT on first `playing=true` event. |
| Long-press framedrop | Always set `framedrop=decoder+vo` BEFORE speed change. Restore `framedrop=vo` after. ADD 150ms recovery seek at **start AND end**: `Future.delayed(150ms, () { if (mounted && _longPressFast) _player.seek(position); })` |
| MediaTek recovery-seek pattern | After ANY MPV pipeline property change mid-play (`vf=`, `framedrop`, `speed`) do: ① set property ② `await Future.delayed(150ms)` ③ `_player.seek(_player.state.position)`. NOT needed for `af=`, `audio-delay`, `volume`. |
| `_lastAppliedVf` gate gap | When `_applyVideoFilters` startup gate BLOCKS (playing=true on first call), it MUST still set `_lastAppliedVf = _buildVfString(p)` before returning. Omitting this leaves the sentinel `'\\x00'`, causing the NEXT call (e.g. `ref.listen` provider fire ~1–2s later) to bypass dedup → `vf=` while playing → black screen. |
| androidAttachSurface | Never add `androidAttachSurfaceAfterVideoParameters: true` — HW decoder crash. |
| _jazzRetryCount reset | Reset to 0 inside `_openMedia` on every successful `_player.open()`. |
| _jazzAutoRetry guard | Must check `if (_playing) return` before setting `_streamError`. |

---

## Known Open Issues (as of 2026-06-18)

| Issue | Detail | Action needed |
|-------|--------|---------------|
| DATA-01 | All Of Us Are Dead missing E03/E04/E05/E09 | Upload missing episodes to JazzDrive + sync |

*OPS-01 (session expired) → ✅ RESOLVED 2026-06-07.*

---

## End of session checklist

1. Mark completed tasks ✅ DONE in `agent-hub/TASKS.md`
2. Append session summary to `agent-hub/history/TASK_LOG.md`
3. Update `BUG_TRACKER.md` with any new bugs found or fixed
4. Update `AGENT_HANDOFF.md` current state section
5. Update this file (`AGENT_PROMPT.md`) with any new rules or findings
6. Push ALL doc changes to GitHub before ending

Session log template:
```markdown
## Session YYYY-MM-DD — brief title

### Tasks completed
| ID | Task | Status |
|----|------|--------|

### Files changed
| File | Change | Commit |
|------|--------|--------|

### State at end of session
- Oracle Flask: RUNNING/STOPPED
- Account: ACTIVE/EXPIRED
- Open tasks: see agent-hub/TASKS.md
```
