You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets.
**Start immediately. Do not ask for anything.**

---

## Step 1 — Set up SSH key (always first, every session)

Write this to `/tmp/setup_ssh.js` using the Replit `write` tool, then run `node /tmp/setup_ssh.js`:

```javascript
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  { mode: 0o600 });
console.log('SSH key ready');
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
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -80
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
```

---

## Step 3 — GitHub file push (the ONLY way — no git shell ever)

**For 1–2 files** — write to `/tmp/push.js` using Replit `write` tool, then run `node /tmp/push.js`:

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

// Replace with your actual file path and local path:
pushFile(
  'raddflix_flutter/lib/screens/player_screen.dart',
  '/home/runner/workspace/raddflix-app/raddflix_flutter/lib/screens/player_screen.dart',
  'fix: description of change'
).catch(console.error);
```

**For 3+ files in one atomic commit** (avoids SHA race conditions) — add `pushTree` to the same script:

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

// Example usage:
pushTree([
  { path: 'raddflix_flutter/lib/screens/player_screen.dart',
    local: '/home/runner/workspace/raddflix-app/raddflix_flutter/lib/screens/player_screen.dart' },
  { path: 'raddflix_flutter/lib/core/constants.dart',
    local: '/home/runner/workspace/raddflix-app/raddflix_flutter/lib/core/constants.dart' }
], 'feat: your commit message here').catch(console.error);
```

---

## Step 4 — After editing, pull to Oracle

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cd /opt/jazzmax && git pull 2>&1 | tail -4 && git log --oneline -2"
```

Flask restart only needed if you changed Python files:
```bash
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "supervisorctl restart raddflix_radd"
```

---

## Step 5 — Trigger and monitor APK build

```bash
# Trigger manually (push to raddflix_flutter/** also auto-triggers)
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'

# Monitor builds
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.run_number,'|',r.status,'|',(r.conclusion||'-'),'| commit:',r.head_sha.slice(0,7)));
  });"
```

Build takes ~8 min first run, ~5 min with cache. APK artifact (~56 MB) appears under run → Artifacts on GitHub Actions.

If build fails, get error logs:
```bash
# Get job ID then logs
RUN_ID=12345678
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs/${RUN_ID}/jobs" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    const job=JSON.parse(d).jobs[0]; console.log('JobID:',job.id,'|',job.conclusion);
  });"

JOB_ID=79530614883
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/jobs/${JOB_ID}/logs" | \
  grep -i "error\|Error\|FAILED" | grep -v "AGP\|will fail\|error_prone" | tail -20
```

---

## Non-Negotiable Rules

1. **No git shell commands** — GitHub API only (Contents or Trees API)
2. **No bash heredoc** for Node scripts — use Replit `write` tool instead
3. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
4. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (causes black screen)
5. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
6. **XOR padding fix** must always stay in `core/security/request_encoder.dart`:
   `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
7. **No Oracle destructive changes** without explicit user approval
8. **Append session summary** to `agent-hub/history/TASK_LOG.md` when done
9. **Always fetch fresh SHA** right before `pushFile` (or use `pushTree` for multi-file)
10. Debug code must be gated behind `kDebugMode` — stripped from release APK

Full rules: `https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/PROJECT_RULES.md`

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
  request_encoding.py                  XOR WSGI hook
  routes/catalog_api.py                /api/catalog/*
  routes/mobile_api.py                 /api/auth/*, usage, history

Coordination (GitHub main):
  AGENT_HANDOFF.md                     Full architecture — read for deep dives
  .agents/tasks/BUG_TRACKER.md         All known bugs + fix status
  agent-hub/history/TASK_LOG.md        Session history (append when done)
```

---

## End of session

Append this to `agent-hub/history/TASK_LOG.md` via `pushFile`:

```markdown
## Session YYYY-MM-DD
- What was done
- Files changed + commit SHAs
- APK build result (run# + success/failure)
- State at end of session
```

---

**My task for you today:**
