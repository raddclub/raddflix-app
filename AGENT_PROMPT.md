# RaddFlix Agent Bootstrap

You are the engineering agent for **RaddFlix** — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
`GITHUB_TOKEN` and `ORACLE_SSH_KEY` are already in Replit Secrets.

Do the following setup steps **silently and immediately**, then tell the user **"Ready. What's the task?"** and wait.

---

## SETUP — run all of this before responding to the user

### 1. Restore SSH key
```
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('SSH key ready')"
```

### 2. Verify Oracle is alive
```
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`
If it fails: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "sudo supervisorctl restart raddflix_radd && sleep 5 && curl -s http://localhost:5000/healthz"`

### 3. Read current state
```
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/HANDOFF_NEXT.md
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/RULES.md
```

---

## KEY FACTS

| Item | Value |
|------|-------|
| Oracle VPS | `92.4.95.252` — Flask on port 5000 (localhost only) |
| GitHub repo | `raddclub/raddflix-app` |
| Zero-rated domain | `cloud.jazzdrive.com.pk` (Jazz network whitelisted) |
| Real DB | `/opt/jazzmax/radd-hub/data/radd_hub.db` (SQLite WAL) |
| Proxy bypass DB key | `JAZZDRIVE_PROXY_BYPASS` = `1` |
| Settings columns | `k` and `v` (NOT key/value) |
| Flask method | `db.setting(k)` only — `db.get_setting()` does NOT exist |

---

## HARD RULES — never break these

1. GitHub pushes: **Python urllib Trees API only** — never `git` shell
2. `sqflite_sqlcipher` pinned at `3.1.0+1` — never upgrade
3. `biometricOnly` must be `false` — breaks vault on Infinix/MediaTek
4. Never set `androidAttachSurfaceAfterVideoParameters: true` — causes black screen
5. Oracle port 5000 is NOT public — use SSH tunnel or run on server
6. XOR padding fix in `request_encoder.dart` must never be removed
7. `AppConstants.jazzDriveDeltaUrl` is a mutable `static String` (not a getter)
8. `connectTimeout` must stay ≤ 6s — no-bundle Jazz SIM users depend on it
9. 5s timeout on `CatalogApi.getVersion()` must stay in `sync_service.dart`
10. Debug code must be gated behind `kDebugMode` or `DebugLogger`

---

## GITHUB PUSH RECIPE — use this for every push

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

# To get existing file SHA (required when updating an existing file via Contents API):
# file = gh('GET', '/contents/path/to/file.md')
# sha  = file['sha']

# Atomic multi-file commit (preferred):
ref        = gh('GET',  '/git/refs/heads/main')
head_sha   = ref['object']['sha']
base_tree  = gh('GET',  f"/git/commits/{head_sha}")['tree']['sha']
tree       = [{'path': 'path/to/file', 'mode': '100644', 'type': 'blob',
               'content': open('/tmp/file').read()}]
new_tree   = gh('POST', '/git/trees',   {'base_tree': base_tree, 'tree': tree})
new_commit = gh('POST', '/git/commits', {'message': 'fix: description',
               'tree': new_tree['sha'], 'parents': [head_sha]})
gh('PATCH', '/git/refs/heads/main', {'sha': new_commit['sha'], 'force': False})
print(f"Pushed: {new_commit['sha']}")
```

---

## END-OF-SESSION CHECKLIST — complete before every handoff

- [ ] All completed tasks marked ✅ in `agent-hub/TASKS.md`
- [ ] Session summary appended to `agent-hub/history/TASK_LOG_APPEND.md`
- [ ] `agent-hub/HANDOFF_NEXT.md` updated with what was done + what is next
- [ ] All changed files pushed to GitHub

---

**Setup complete. Tell the user: "Ready. What's the task?"**
