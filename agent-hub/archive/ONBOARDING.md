# ONBOARDING.md — New Agent Quick Start

> 4 steps. Takes 3 minutes. Do not skip any step.

---

## Step 1 — Restore SSH key

Paste into Replit shell:

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY not set correctly'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  {mode: 0o600});
console.log('SSH key ready at /tmp/oracle_key');
"
```

If this fails: ask the user to re-paste the SSH private key into Replit Secrets as `ORACLE_SSH_KEY`.
The key must include the full `-----BEGIN RSA PRIVATE KEY-----` / `-----END RSA PRIVATE KEY-----` lines.

---

## Step 2 — Verify Oracle is alive

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```

Expected response:
```json
{"ok": true, "version": "3.0.0"}
```

If this fails:
- Check Oracle is running: `ssh ... "sudo supervisorctl status"`
- Check logs: `ssh ... "sudo supervisorctl tail -50 raddflix_radd"`
- If process is stopped: `ssh ... "sudo supervisorctl start raddflix_radd"`

**Supervisor process name: `raddflix_radd`** (NOT `radd-hub` — that name does not exist)

---

## Step 3 — Read current project state

```bash
# Full architecture + rules (READ THIS)
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"

# Bug status
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"

# What previous agents did
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -150
```

---

## Step 4 — Verify GitHub token

```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app" | node -e "
const d=require('fs').readFileSync('/dev/stdin','utf8');
const r=JSON.parse(d);
console.log(r.name ? 'Token OK — repo: '+r.full_name : 'Token FAIL: '+r.message);
"
```

---

## Critical facts (memorize these)

| Topic | Fact |
|-------|------|
| DB package | `sqflite_sqlcipher: 3.1.0+1` — **NEVER upgrade** |
| XOR padding | Server strips `=` from base64. Client must add back: `b64 += '=' * ((4 - len%4)%4)` |
| VideoController | Never add `androidAttachSurfaceAfterVideoParameters: true` |
| Oracle test | Always via SSH tunnel to localhost:5000, NOT direct port |
| Push method | GitHub Contents API via Node.js `https` module only (or Trees API for multi-file) |
| Script files | Use Replit `write` tool to create .js files, then `node file.js` — no heredocs |
| Supervisor name | `raddflix_radd` — NOT `radd-hub` |
| Dart semicolons | Semicolons MUST come BEFORE inline comments: `expr); // comment` not `expr) // comment;` |
| db.py API | `db.setting(k)` to read settings — `db.get_setting()` does NOT exist |
| Real DB path | `/opt/jazzmax/radd-hub/data/radd_hub.db` — all other .db files are empty/stale |

---

## Required Replit Secrets (user adds these, not you)

| Secret | Description |
|--------|-------------|
| `GITHUB_TOKEN` | GitHub Personal Access Token with `repo` scope |
| `ORACLE_SSH_KEY` | SSH private key — full PEM including BEGIN/END lines |

---

See `AGENT_HANDOFF.md` for complete architecture, file map, and GitHub API patterns.
