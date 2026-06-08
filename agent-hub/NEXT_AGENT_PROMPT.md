You are continuing work on **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
Secrets `ORACLE_SSH_KEY` and `GITHUB_TOKEN` are already in Replit Secrets.
**Start immediately. Do not ask for anything.**

---

## Step 1 — Set up SSH key (always first, every session)

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
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/HANDOFF_NEXT.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -80
```

---

## Step 3 — Your Task: Full System Audit

Run the comprehensive audit described in:
```
agent-hub/FULL_AUDIT_PROMPT.md
```

Read it fully, then work through every section in order.

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/FULL_AUDIT_PROMPT.md"
```

This audit covers:
1. **6 confirmed discrepancies** between docs and actual code — fix all of them
2. **File-by-file code verification** (Flutter + Flask + Android)
3. **Oracle live state checks**
4. **Final 25-point verification checklist**

---

## Current System State (as of 2026-06-08 17:55 PKT)

| Component | State |
|-----------|-------|
| Oracle Flask | ✅ RUNNING — restarted, health OK |
| JAZZDRIVE_PROXY_BYPASS | ✅ = 1 (direct wg0, all proxies bypassed) |
| jd_delta_url | ✅ set |
| delta_auto_enabled | ✅ = 1 (auto-runs every 6 hours) |
| APK Build | ✅ #1029 triggered — monitor at https://github.com/raddclub/raddflix-app/actions |
| Latest commit | `d81f2fc` (main branch) |

---

## Key Architecture Facts (memorize before touching code)

- **Oracle VPS**: `92.4.95.252` — Flask port 5000, localhost only (SSH tunnel to test)
- **Zero-rating**: `cloud.jazzdrive.com.pk` is Jazz network-whitelisted — no data bundle needed
- **Share URLs**: JazzDrive share_urls NEVER expire — security via APK integrity, not link expiry
- **Sync priority**: Oracle first (5s probe) → JazzDrive delta fallback on timeout
- **DB path**: `/opt/jazzmax/radd-hub/data/radd_hub.db` (SQLite WAL, this is the ONLY real DB)
- **Proxy setting key**: `JAZZDRIVE_PROXY_BYPASS` = `1` (NOT `proxy_bypass`)
- **GitHub push**: Trees API ONLY — never git shell

---

## Critical Rules (never break these)

```
1.  No git shell — GitHub Trees/Contents API only
2.  sqflite_sqlcipher pinned at 3.1.0+1 — never upgrade
3.  androidAttachSurfaceAfterVideoParameters must NEVER be true (black screen)
4.  biometricOnly must be false — breaks vault on Infinix/MediaTek
5.  Oracle port 5000 NOT public — test via SSH tunnel only
6.  XOR padding fix stays in request_encoder.dart — never remove
7.  AppConstants.jazzDriveDeltaUrl = mutable static String (not getter)
8.  connectTimeout must stay 6s max — no-bundle Jazz SIM users depend on it
9.  5s timeout on CatalogApi.getVersion() must stay in sync_service.dart
10. db.setting(k) only — db.get_setting() does NOT exist → AttributeError + 500
11. Settings table columns: k and v (NOT key and value)
12. JAZZDRIVE_PROXY_BYPASS DB key (NOT proxy_bypass)
13. Debug code must be gated behind kDebugMode or DebugLogger
14. share_url scrambling: unscrambleUrl() passes through non-RF1: URLs (backward compat)
```

---

## GitHub Push Recipe (Python — use this for all pushes)

```python
import json, os, urllib.request

TOKEN = os.environ['GITHUB_TOKEN']
BASE  = 'https://api.github.com/repos/raddclub/raddflix-app'

def gh(method, path, body=None):
    req = urllib.request.Request(BASE + path,
        data=json.dumps(body).encode() if body else None,
        headers={'Authorization': f'token {TOKEN}',
                 'Accept': 'application/vnd.github.v3+json',
                 'Content-Type': 'application/json',
                 'User-Agent': 'raddflix-agent'},
        method=method)
    with urllib.request.urlopen(req) as r:
        d = r.read()
        return json.loads(d) if d else {}

# Multi-file atomic commit:
ref       = gh('GET', '/git/refs/heads/main')
head_sha  = ref['object']['sha']
base_tree = gh('GET', f'/git/commits/{head_sha}')['tree']['sha']
tree      = [{'path': 'path/to/file.dart', 'mode': '100644', 'type': 'blob',
              'content': open('/tmp/file.dart').read()}]
new_tree  = gh('POST', '/git/trees', {'base_tree': base_tree, 'tree': tree})
new_commit= gh('POST', '/git/commits',
               {'message': 'fix: description', 'tree': new_tree['sha'], 'parents': [head_sha]})
gh('PATCH', '/git/refs/heads/main', {'sha': new_commit['sha'], 'force': False})
print(f"Pushed: {new_commit['sha']}")
```

---

## End of Session Requirements (every session, no exceptions)

Before you finish:
1. Mark all tasks ✅ DONE in `agent-hub/TASKS.md`
2. Append session summary to `agent-hub/history/TASK_LOG_APPEND.md`
3. Update `agent-hub/HANDOFF_NEXT.md` with what was done + what's next
4. Push all doc changes to GitHub
