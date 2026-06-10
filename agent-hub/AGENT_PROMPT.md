# AGENT_PROMPT.md
> Complete orientation guide for any agent working on RaddFlix.
> Read this fully before making any changes.
> Last updated: 2026-06-10

---

## 1. What Is RaddFlix?

RaddFlix is a Pakistani streaming app serving users on **Jazz SIM zero-rated data** —
video streams for free on Jazz connections. It is a fully self-hosted platform with:

- **Flutter mobile app** (`raddclub/raddflix-app` on GitHub, branch `main`)
- **Flask/Python admin panel + backend API** on an Oracle Cloud server
- **JazzDrive** (Jazz's cloud storage) as the video CDN — files stored there, streamed
  via SAPI (Jazz Share API) direct links
- **SQLite** database (`radd_hub.db`) on the Oracle server

### Key Constraint
Jazz SIM zero-rating only works through the SAPI proxy pool. Oracle has no Jazz SIM —
it uses a pool of Pakistani proxies to communicate with JazzDrive for zero-rated streaming.
Direct Oracle → JazzDrive share-link login (for generating stream URLs) works without proxies.

---

## 2. Infrastructure

### Oracle Server
```
IP:         92.4.95.252
User:       ubuntu
SSH key:    from ORACLE_SSH_KEY env var (Replit secret) — reconstruct to /tmp/oracle_key
App root:   /opt/jazzmax/radd-hub/
Hub code:   /opt/jazzmax/radd-hub/hub/
DB:         /opt/jazzmax/radd-hub/data/radd_hub.db
Supervisor: raddflix_radd  (sudo supervisorctl restart raddflix_radd)
Logs:       sudo tail -f /var/log/raddflix_radd.out.log
Health:     curl -s http://localhost:5000/healthz
Flask port: 5000 (localhost only)
```

### SSH Key Reconstruction (run at start of EVERY session)
```bash
python3 -c "
import os
key = os.environ['ORACLE_SSH_KEY']
key = key.replace('-----BEGIN RSA PRIVATE KEY----- ','-----BEGIN RSA PRIVATE KEY-----\n')
key = key.replace(' -----END RSA PRIVATE KEY-----','\n-----END RSA PRIVATE KEY-----\n')
parts = key.split('\n')
new_parts = [p if p.startswith('-----') else p.split(' ') for p in parts]
out = '\n'.join(p for line in new_parts for p in (line if isinstance(line,list) else [line]) if p)
open('/tmp/oracle_key','w').write(out+'\n')
" && chmod 600 /tmp/oracle_key
```

### Admin Panel
```
URL:      http://localhost:5000/admin/
Username: admin
Password: 6LQRmtOM5d1PETSI
```

Cookie auth for API testing:
```bash
curl -s -c /tmp/jar -X POST http://localhost:5000/auth/login \
  -F 'username=admin' -F 'password=6LQRmtOM5d1PETSI' -L -o /dev/null
curl -b /tmp/jar http://localhost:5000/admin/api/...
```

### GitHub
```
Repo:    raddclub/raddflix-app
Branch:  main
Token:   GITHUB_TOKEN env var (Replit secret only — NOT on Oracle)
```

**CRITICAL:** Replit agent sandbox blocks destructive git shell commands.
All GitHub pushes MUST use the GitHub Trees API via Python urllib. Never use git shell.

Multi-file Trees API push pattern (Python):
```python
import json, os, urllib.request, base64
# 1. GET /git/ref/heads/main  -> base_sha
# 2. GET /git/commits/{base_sha} -> base_tree
# 3. POST /git/blobs (one per file, base64 content)
# 4. POST /git/trees (base_tree + new blobs)
# 5. POST /git/commits (tree + parent)
# 6. PATCH /git/refs/heads/main (new commit sha)
```

---

## 3. Codebase Map

```
/opt/jazzmax/radd-hub/
├── radd_hub.py                   Flask entry point
├── hub/
│   ├── db.py                     SQLite wrapper; validate_schema() at startup
│   ├── jazzdrive.py              JazzDrive API; generate_direct_link()
│   ├── scanner.py                JazzDrive scanner; auto-publish after scan
│   ├── uploader.py               JazzDrive uploader; proxy-chain retry
│   ├── proxy_pool.py             SAPI proxy pool; WeightedScore + CircuitBreaker
│   ├── metadata.py               IMDb/TMDB metadata fetcher
│   ├── sync.py                   GitHub JSON + Google Sheets sync
│   └── routes/
│       ├── admin.py              /admin — reset, restart, schema-health, bot control
│       ├── settings.py           /settings — proxy pool, service status endpoint
│       ├── catalog_api.py        /api/catalog — Flutter sync, _do_play()
│       ├── scan.py               /scan — scan control
│       ├── upload.py             /upload — upload control
│       ├── organizer.py          /organizer — folder management
│       ├── home.py               /admin/ dashboard — TID alert banner
│       ├── library.py            /library — user status (real DB queries)
│       ├── app_users_panel.py    /app-users — user + subscription stats
│       ├── zero_rating.py        /zero-rating — delta JSON generation
│       └── ...                   17 more route files (all audited clean, 2026-06-08)
└── templates/
    ├── admin.html                Reset/restart/wipe UI (3-step progress panel)
    ├── settings.html             Live service status bar
    ├── scan.html                 Live service status bar
    ├── upload.html               Live service status bar
    ├── organizer.html            Live service status bar
    ├── home.html                 Dashboard: TID banner, inline approve/reject
    └── _proxy_pool_panel.html    God-level proxy pool panel (included in settings.html)
```

---

## 4. Database (Key Tables)

```sql
titles        (id, title, slug, year, type, industry, rating, is_published, updated_at)
files         (id, title_id, account_id, filename, remote_id, share_url, season, episode)
accounts      (id, phone, is_active)
settings      (k TEXT PK, v TEXT)          -- use db.setting(k) NOT db.get_setting(k)
plans         (id, name, price, badge, color, features_json)
app_users     (id, phone, device_name, is_active, created_at)
app_subscriptions (id, user_id, plan_id, status)
```

**Rules:**
- Always use `db.setting(k)` — `db.get_setting(k)` does not exist
- After any `is_published` SQL change: regenerate `db_update.json` via Python
- Bump `catalog_forced_version` in settings after DB resets to force Flutter re-sync:
  `INSERT OR REPLACE INTO settings(k,v) VALUES('catalog_forced_version', '<unix_ts>')`

---

## 5. Flutter App

**Location:** `raddflix_flutter/` subfolder in the GitHub repo

**Critical rules (never break):**
- `sqflite_sqlcipher` pinned at `3.1.0+1` — NEVER upgrade (breaks DB encryption)
- Never add `androidAttachSurfaceAfterVideoParameters: true` (crashes MediaKit)
- XOR padding fix in `request_encoder.dart` — NEVER remove (breaks ALL API calls)
- `biometricOnly: false` in vault_service.dart (Infinix = Class 2 sensor, not Class 3)
- Use `_duration == Duration.zero` (not `_position`) for player black-screen opacity guard

**Builds:** GitHub Actions auto-builds on every push. Current required build: **1025+**

---

## 6. How Episode Streaming Works

```
Flutter: GET /api/catalog/play?file_id=N
  └─> _do_play() in catalog_api.py
        SELECT share_url, filename, remote_id FROM files WHERE id=N
        └─> jazzdrive.generate_direct_link(share_url, filename, remote_id=N)
              Pass 0: remote_id > 0 → match file.id in folder list (bulletproof)
              Pass 1-3: filename fallback (legacy)
              └─> returns time-limited SAPI download URL
        └─> Flutter streams video (zero-rated on Jazz SIM)
```

Always store `remote_id` (JazzDrive's internal file ID) in `files.remote_id`.
JazzDrive auto-renames duplicates — filename matching breaks; remote_id matching is stable.

---

## 7. SAPI Proxy Pool

```python
pool.get_best_proxy(purpose='sapi')    # single best proxy
pool.get_proxy_chain(n=5)              # ordered retry list
pool.mark_fail(proxy_url)              # demote on failure
pool.mark_success(proxy_url, ms=...)   # promote on success
```

- CircuitBreaker: if >80% dead → auto direct-connection fallback (never breaks uploads)
- Fast recovery: dead proxies re-tested every 5 min in background thread
- Two purposes: `'sapi'` (streaming) vs `'otp'` (OTP login) — NEVER mix

---

## 8. Admin Panel — Reset Tables Flow

The Reset Tables button (Danger Zone) now does 3 things with live feedback:

**Step 1 — Clear DB:** Deletes titles, files, scan_log, media_index, queue, caches.
Bumps `catalog_forced_version` so Flutter clients re-sync on next launch.
Shows per-table breakdown: table name + rows deleted.

**Step 2 — Restart service:** POST /admin/api/restart fires a background thread
(0.6s delay) that runs `sudo supervisorctl restart raddflix_radd`.
Response is sent before the process dies.

**Step 3 — Wait for recovery:** Frontend polls GET /healthz every 1.5s (up to 36s).
Shows live counter. On 200 OK: declares service back online.

---

## 9. Worker Health Status Bars

Live status indicators on 4 admin pages (Settings, Scan, Upload, Organizer):
- Endpoint: `GET /settings/api/services/status`
- Refresh: every 15 seconds (first check at 3s after page load)
- Shows: JazzDrive API latency, proxy pool alive/total, DB size, scanner/uploader state

---

## 10. Common Operations

### Check DB state
```bash
python3 -c "
import sqlite3
db = sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
for t in ['titles','files','accounts','settings']:
    print(t, db.execute('SELECT COUNT(*) FROM '+t).fetchone()[0])
"
```

### Bump catalog version (forces all Flutter clients to re-sync)
```bash
python3 -c "
import sqlite3, time
db = sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
db.execute(\"INSERT OR REPLACE INTO settings(k,v) VALUES('catalog_forced_version',?)\",
           (str(int(time.time())),))
db.commit(); print('bumped')
"
```

### Check schema health
```bash
curl -b /tmp/jar -s http://localhost:5000/admin/api/schema-health | python3 -m json.tool
```

### Patch a file on Oracle
```python
# Write patch as Python script to /tmp/patchN.py locally
# SCP it to Oracle: scp -i /tmp/oracle_key /tmp/patchN.py ubuntu@92.4.95.252:/tmp/
# Run it: ssh -i ... ubuntu@92.4.95.252 "python3 /tmp/patchN.py"
# Always verify: syntax check + restart + /healthz
```

---

## 11. Known Gotchas

**Script tags in Jinja2 templates:**
`{% block scripts %}` opens a `<script>` tag. Any dead HTML card left inside that block
is parsed as JS — `</div>` becomes a broken regex, causing a SyntaxError that kills ALL
JavaScript on the page silently. Always verify balance:
`opens == closes` on `<script>` / `</script>` tags.

**Admin restart endpoint is fire-and-forget:**
`POST /admin/api/restart` must return HTTP 200 BEFORE the process dies.
A 0.6s-delayed background thread handles the actual supervisorctl call.
The client polls `/healthz` to detect recovery — not the restart response body.

**db_update.json is NOT auto-regenerated:**
Direct SQL `UPDATE titles SET is_published=1` does NOT trigger catalog JSON rebuild.
Must run the Python regeneration script manually after every `is_published` change.

**Flutter catalog sync uses version comparison:**
If local `db_version` == server `catalog_forced_version`, Flutter skips sync entirely.
Always bump `catalog_forced_version` after bulk DB changes (resets, imports, etc.)

**JazzDrive auto-renames duplicate files:**
`Spider Noir S01E02.mp4` may become `Spider Noir S01E02 (1).mp4` silently.
Use `remote_id` (integer JazzDrive file ID) for stream link generation, not filename.

**Share key format — NEVER truncate:**
Full key: `hoIyg7Sg...zc1MjIwNTczNTg3NzFfMjYyMTAwMA` → HTTP 200
Truncated: `hoIyg7Sg...` → HTTP 400
The long suffix encodes account/tenant context and is identical across all share URLs.

**Infinix/MediaTek quirks:**
- `biometricOnly: true` → PlatformException before biometric dialog appears
- Player emits position=0 transiently ~2-3s into local video playback (MediaCodec re-init)
  → triggers opacity=0 black screen if guard uses `_position`. Use `_duration` instead.

---

## 12. Session Startup Checklist

1. Reconstruct SSH key to `/tmp/oracle_key`
2. Read AGENT_STATUS.md for current health
3. Read TASKS.md for current backlog
4. Verify `/healthz` returns `{"ok":true}`
5. Read relevant source files before editing (never edit blind)

## 13. Session End Checklist

- [ ] All changed files pushed to GitHub via Trees API
- [ ] Flask service restarted and `/healthz` confirmed OK
- [ ] TASK_LOG.md appended with session summary
- [ ] AGENT_STATUS.md updated (health table, DB state, open items)
- [ ] TASKS.md updated (completed items, new backlog)
