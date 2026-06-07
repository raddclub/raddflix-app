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

**For 3+ files in one atomic commit** (avoids SHA race conditions):

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
3. **No git shell commands** — GitHub API only (Contents or Trees API)
4. **No bash heredoc** for Node scripts — use Replit `write` tool instead
5. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
6. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (causes black screen)
7. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
8. **XOR padding fix** must always stay in `core/security/request_encoder.dart`:
   `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
9. **No Oracle destructive changes** without explicit user approval
10. **Append session summary** to `agent-hub/history/TASK_LOG.md` when done
11. **Always fetch fresh SHA** right before `pushFile` (or use `pushTree` for multi-file)
12. **Debug code** must be gated behind `kDebugMode` — stripped from release APK
13. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist in `db.py`
14. **For bulk DELETEs** use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()`
15. **Oracle git pull**: always `git stash && git pull && git stash pop` — Oracle has local uncommitted files
17. **THE ONLY REAL DB is `/opt/jazzmax/radd-hub/data/radd_hub.db`** (~4.3 MB).
    All other `.db` files on Oracle (radd.db, radd_hub.db, raddflix.db, hub.db, etc.) are **0-byte
    empty artifacts** — they have NO tables and NO data. Never query them. If `find` shows 15 DB
    files, ignore all except `data/radd_hub.db`. Full guide: `agent-hub/DATABASE.md`.
16. **TV show metadata search**: strip BOTH `SxxExx` AND `Season N` from the clean name before
    any metadata API search. Both strips are in `enrich_and_save()` (prefer='tv' path).
    "The Boys S02E01" → search "The Boys". "The Boys Season 2" → search "The Boys".
    Never pass episode/season suffixes to any title search API.

Full rules: `agent-hub/RULES.md` | Architecture: `agent-hub/CONTEXT.md`

---

## Key file paths

```
Flutter:  raddflix_flutter/lib/
  core/security/request_encoder.dart   XOR decode + padding fix (critical)
  core/api/api_client.dart             Dio + XOR + auth interceptors
  core/db/local_db.dart                SQLCipher DB, schema v17
  screens/player_screen.dart           Video player — no androidAttachSurface
  providers/auth_provider.dart         Auth state + session restore

Oracle:   /opt/jazzmax/radd-hub/hub/
  jazzdrive.py                         JazzDrive session, OTP, upload, keepalive
  proxy_pool.py                        Proxy pool management
  keepalive.py                         Heartbeat upload scheduler
  routes/catalog_api.py                /api/catalog/*
  routes/mobile_api.py                 /api/auth/*, usage, history, /api/app/config
  routes/admin.py                      Admin panel API (db/reset + db/restore)
  _legacy/scanner.py                   Scanner: enrich_and_save() is IMDb-first primary; TMDB direct is final safety net only
  media_naming.py                      _detect_season_episode, _plan_tv, MediaPlan
  metadata_lookup.py                   enrich() — PRIMARY: IMDb → OMDB → TMDB → AI → YouTube → Google KG
  metadata.py                          fetch_imdbapi(), enrich_title()
  _legacy/enricher.py                  TMDB fetch_full_metadata(), _clean_filename()
  templates/scan.html                  Scan log UI — human-readable messages
  templates/admin.html                 Admin panel — Restore Catalog + Danger Zone

Oracle DB: /opt/jazzmax/radd-hub/data/radd_hub.db
Oracle logs: /opt/jazzmax/radd-hub/data/logs/raddhub.log

Coordination (GitHub main):
  agent-hub/TASKS.md                   ← READ FIRST every session
  agent-hub/CONTEXT.md                 System context + proxy + scan pipeline
  agent-hub/RULES.md                   Full rules list
  AGENT_HANDOFF.md                     Full architecture
  .agents/tasks/BUG_TRACKER.md         All known bugs + fix status
  agent-hub/history/TASK_LOG.md        Session history (append when done)
  AGENT_PROMPT.md                      This file
```

---

## TV Seasons/Episodes — How It Works

### Detection
A folder is treated as TV if ANY file in it matches `[Ss]\d{1,2}[Ee]\d{1,3}` or has `season` set.
`prefer='tv'` is passed to the metadata lookup chain.

### Episode number parsing (`_parse_episode_info`)
Three patterns (tried in order):
1. `S01E02` → season=1, episode=2
2. `Season 1 Episode 2` → season=1, episode=2
3. `1x02` → season=1, episode=2

### Storage
`files.season` (INTEGER) + `files.episode` (INTEGER).
Dedup key: `(account_id, title_id, season, episode)` — one row per unique episode.

### Metadata search for TV
When searching IMDbAPI for a TV show, the episode suffix is stripped first:
`"Spider Noir S01E02"` → search for `"Spider Noir"` → finds `tt30460310` ✅

### Known edge cases
- Files in wrong folders (e.g. episode loose in root) — `media_naming.py` detects and re-plans
- Two filenames for same episode (clean + dirty upload) — dedup removes the duplicate
- No TMDB/IMDb match yet (e.g. brand-new show) — file saved with `title_id=NULL`, picked up by `_enrich_low_confidence_titles` on next scan

---

## Known Open Issues (as of 2026-06-07)

| Issue | Detail | Action needed |
|-------|--------|---------------|
| — | No open issues | — |

*DATA-01 (All Of Us Are Dead missing episodes) → ✅ RESOLVED 2026-06-07.*
*OPS-01 (session expired) → ✅ RESOLVED 2026-06-07. Session auto-recovers (~3-5s) via wg0.*

---

## End of session checklist

1. Mark completed tasks ✅ DONE in `agent-hub/TASKS.md`
2. Append session summary to `agent-hub/history/TASK_LOG.md`
3. Update `BUG_TRACKER.md` with any new bugs found or fixed
4. Update `AGENT_HANDOFF.md` current state section
5. Update this file with any new rules or findings
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

