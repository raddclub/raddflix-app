# NEXT AGENT BRIEFING — RaddFlix Hub
_Written: 2026-06-10 | Updated: 2026-06-18 | Read HANDOFF_NEXT.md for latest state_

> ⚠️ For up-to-date state, read `agent-hub/HANDOFF_NEXT.md` and `agent-hub/AGENT_STATUS.md` first.
> This file covers the Oracle backend architecture and critical rules (still valid).

**Latest (2026-06-18):** FIX-VF-STARTUP + FEAT-TIMELINE (PlaybackTimeline) committed. Build #1147 in progress.

---

## Who You Are / What This Project Is

You manage the **RaddFlix** Pakistani Flutter streaming app backend.
- Oracle server: `ubuntu@92.4.95.252` — Flask hub runs here (port 5000, not public)
- GitHub repo: `raddclub/raddflix-app`
- SSH key: reconstruct from `ORACLE_SSH_KEY` env var to `/tmp/oracle_key` (chmod 600) at session start
- GitHub token: in Oracle git remote URL — extract with `git remote -v` on Oracle
- Flask supervisor: `sudo supervisorctl restart raddflix_radd`
- Logs: `tail -f /opt/jazzmax/radd-hub/data/logs/raddhub.log`
- Health: `curl -s http://localhost:5000/healthz`

---

## CRITICAL RULES — NEVER BREAK THESE

1. `db.setting(k)` NOT `db.get_setting(k)`
2. GitHub pushes via **Contents API (python3 on Oracle)** — Replit sandbox blocks git shell commits
3. Always `git stash && git pull && git stash pop` before any git ops on Oracle
4. `sqflite_sqlcipher` pinned at `3.1.0+1` — NEVER upgrade in Flutter
5. XOR padding fix must stay in `request_encoder.dart` — removing it breaks ALL API calls
6. `androidAttachSurfaceAfterVideoParameters: true` — NEVER add this
7. Proxy background scanning permanently removed from code — do NOT re-add threads to ProxyPool
8. After any direct SQL `is_published` change: regenerate `db_update.json` manually via Python
9. JazzDrive share keys: the long suffix (`zc1MjI...`) is PART of the real key — NEVER truncate
10. Add tasks to `TASKS.md` BEFORE making changes

---

## BUGS TO FIX (priority order)

### BUG-1 — delta_push pipeline broken (HIGH PRIORITY)
**File:** `/opt/jazzmax/radd-hub/hub/routes/delta_push.py` line ~270
**Error in logs every 6 hours:**
```
AttributeError: module 'hub.jazzdrive' has no attribute 'upload_json_to_jazzdrive'
```
**Fix:** Change `jd.upload_json_to_jazzdrive(delta_path)` to `jd.upload_file_to_jazzdrive(delta_path)`
The real function is `upload_file_to_jazzdrive` (confirmed in `hub/jazzdrive.py` line 2430).
Also check what `upload_file_to_jazzdrive` returns vs what `upload_and_configure()` expects — may need a small adapter.
**Impact:** Flutter never gets updated delta catalog pushed to JazzDrive automatically.

---

### BUG-2 — /app-users/api/stats crashes every 60 seconds (HIGH PRIORITY)
**Error in logs every 60s:**
```
hub.app: Exception: OperationalError
GET /app-users/api/stats → 500
```
**Steps:**
- Check `hub/routes/app_users.py` — likely empty or querying a missing DB table
- Run: `sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db ".tables"` to see what tables exist
- Either create the missing table with a schema or return a safe empty `{"ok": true, "stats": {}}` instead of 500
**Impact:** Admin panel polls this every 60s, polluting logs with errors constantly.

---

### BUG-3 — db_update.json does NOT auto-regenerate (MEDIUM PRIORITY)
**Problem:** When `is_published` changes (via scan, admin UI, or SQL), `db_update.json` is NOT
automatically regenerated. Flutter apps keep showing stale catalog — user must run Python script manually.
**Fix:** Hook the regen script into:
1. `hub/scanner.py` — after `_auto_publish_titled_files()` call
2. `hub/routes/admin.py` — after any endpoint that changes `is_published`
3. Optionally: background task that checks DB version > JSON version every 5 min
**Impact:** Without this, every scan requires a manual step or users see old catalog.

---

### BUG-4 — AGENT_STATUS.md is stale (LOW PRIORITY)
`agent-hub/AGENT_STATUS.md` last updated 2026-06-06 — shows wrong DB state (old title IDs 1-8).
Current published titles are IDs 25, 27, 28, 30. Also missing: CPU now ~2%, proxy scanning OFF,
Background Services toggle system added. Update after fixing the above bugs.

---

## DATA WORK NEEDED

### DATA-01 — All Of Us Are Dead missing episodes (MEDIUM)
Episodes E03, E04, E05, E09 are not in Oracle DB.
Upload to JazzDrive, then trigger a JazzDrive scan — auto-publish will handle the rest
(FEAT-AUTOPUB-01 was added in a prior session so no manual SQL needed after scan).

### OAUTH-01 — Expired OAuth token (LOW)
Account `03286829827` refresh_token has expired (`invalid_grant`).
User must manually log in via Settings > JazzDrive Scan > OTP login. Not a code fix.

---

## APK STATUS — DEADLINE

| Build | Status | Expires |
|-------|--------|---------|
| 1023  | OLD — do not use | — |
| 1025  | LATEST — install this | 2026-07-07 |

Before **2026-07-07**: push any commit to `main` to trigger GitHub Actions and get a fresh build.
Otherwise build1025 artifact expires and users cannot install the app.

---

## IMPROVEMENTS TO ADD

### IMPROVE-1 — Service health indicators in admin panel
The Background Services card has toggle switches but no health info.
Add to each service card: last run time, error count, status badge (green/yellow/red).
Each service loop should call `db.set_setting("X_LAST_RUN", str(int(time.time())))` each cycle
and `db.set_setting("X_LAST_ERROR", message)` on failure.
Admin GET `/admin/api/services` should return these fields.

### IMPROVE-2 — Trigger delta push after fixing BUG-1
After BUG-1 is fixed, manually trigger a full delta pipeline run so Flutter apps get
the current catalog (4 titles, correct share_urls, remote_ids, episode data).

### IMPROVE-3 — Proxy pool UI shows stale options
Settings page has buttons like "Start Health Check" that trigger background threads
which no longer exist (permanently removed in PERF-02). Update the UI to show
"Background scanning disabled" and only offer the manual one-off trigger options.

---

## CURRENT SERVER STATE (updated 2026-06-17)

| Item | Value |
|------|-------|
| CPU | ~2% |
| RAM | ~85 MB |
| Threads | 9 |
| Flask | RUNNING via supervisorctl (raddflix_radd) |
| WA Bot | RUNNING (raddflix_wa_bot) |
| DB path | /opt/jazzmax/radd-hub/data/radd_hub.db |
| App path | /opt/jazzmax/radd-hub/ |

### Background Services State
| Service | State | DB Key |
|---------|-------|--------|
| Upload Watcher | OFF | UPLOAD_ENABLED |
| Download Queue | ON | DOWNLOAD_ENABLED |
| Mirror Retry | ON | MIRROR_ENABLED |
| JazzDrive Keepalive | ON | KEEPALIVE_ENABLED |
| Scanner | OFF | SCAN_ENABLED |
| Smart Scheduler | OFF | SCHEDULER_ENABLED |
| Domain Doctor | ON | DOMAIN_DOCTOR_ENABLED |
| WhatsApp Bot | ON | supervisorctl only |

### Current Published Catalog
| title_id | Title | Type | Files |
|----------|-------|------|-------|
| 25 | Bhooth Bangla | movie | file_id=18 |
| 27 | Luka Chuppi | movie | file_id=28 |
| 28 | Spider-Noir | show | S1E1(f31) S1E2(f30) |
| 30 | Vincenzo | show | S1E1(f35) S1E2(f32) |

---

## HOW TO START A SESSION

Step 1 — Reconstruct SSH key:
```
node -e "const fs=require('fs'); fs.writeFileSync('/tmp/oracle_key', process.env.ORACLE_SSH_KEY+'\n'); fs.chmodSync('/tmp/oracle_key', 0o600); console.log('done');"
```

Step 2 — Test connection:
```
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz && sudo supervisorctl status"
```

Step 3 — Get GitHub token:
```
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "git -C /opt/jazzmax/radd-hub remote get-url origin" | grep -o 'ghp_[^@]*'
```

Step 4 — Read TASKS.md at `/opt/jazzmax/radd-hub/agent-hub/TASKS.md` before doing any work.

---

## Player UX Session Completed — 2026-06-17
8 MX Player layout improvements pushed to player_screen.dart and player_prefs.dart.
See agent-hub/AGENT_STATUS.md for full details.
No bugs open as of 2026-06-17.

## RECOMMENDED WORK ORDER

1. Fix BUG-1 (delta_push wrong function name) — ~15 min, one-line change
2. Fix BUG-2 (app-users 500 error) — ~30 min, investigate + fix or create table
3. Trigger delta push to JazzDrive (after BUG-1 fixed)
4. Fix BUG-3 (auto-regen db_update.json) — ~1 hr, hook into scanner + admin
5. Update AGENT_STATUS.md (BUG-4)
6. Add service health indicators (IMPROVE-1)
7. Trigger new APK build before 2026-07-07
