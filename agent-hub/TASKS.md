# RaddFlix Agent Task Board

_Last updated: 2026-06-11_

## In Progress

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-DEVICE-NAME | hub/keepalive.py + DB | Fix garbled device name on JazzDrive website + human-like keepalive behavior | ⏳ IN PROGRESS |

## Completed This Session

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| JD-IDENTITY-01..03 | hub/jazzdrive.py | fac- deviceid, omh UA, x-request-id, X-devicename, Authorization oauth, validationkey-from-response-body | 3cd109c |
| JD-IDENTITY-04 | hub/routes/jd_auth.py (new), hub/app.py | GET /api/jd/oauth2/authorize_url + POST /api/jd/oauth2/token + POST /api/jd/mobileconnect/validate | 330d479, 5131e32 |
| FIX-WG0-ENFORCE | hub/jazzdrive.py | Hard-block ALL JazzDrive network calls if wg0 not routing JD IPs | pending |
| FEAT-SERVICES-01 | admin.py, services.html | Consolidated all 8 service toggles to /admin/services page | b55df7f |
| PERF-01..05 | proxy_pool.py, multiple | Proxy CPU fix, thread removal, service toggles, dependency logic | 519f649-88be21e |

## Previous Completed Tasks

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-CATALOG-01 | Oracle DB | Bumped updated_at on 3 titles | SQL |
| FIX-PLAYER-01 | player_screen.dart | Local video black screen fix | 215bbc2055 |
| FIX-VAULT-01 | vault_service.dart | Vault biometric fix | 59fc97249c |
| FEAT-AUTOPUB-01 | scanner.py | Auto-publish titles after scan | Oracle only |
| FIX-CATALOG-02..03 | Oracle DB | Ghost title cleanup + db_update.json regen | SQL |

## Background Services — Current State

| Service | Key | Default | Description |
|---------|-----|---------|-------------|
| Upload Watcher | UPLOAD_ENABLED | OFF | Watches for new files, uploads to JazzDrive |
| Download Queue | DOWNLOAD_ENABLED | ON | Processes queued download jobs |
| Mirror Retry | MIRROR_ENABLED | ON | Retries failed GitHub mirror pushes every 60s |
| JazzDrive Keepalive | KEEPALIVE_ENABLED | ON | Heartbeat pings every 15 min |
| Scanner | SCAN_ENABLED | OFF | Scans JazzDrive accounts for new content |
| Smart Scheduler | SCHEDULER_ENABLED | OFF | Rescans ongoing series + delta generation |
| Domain Doctor | DOMAIN_DOCTOR_ENABLED | ON | Finds working mirror domains every 24h |
| WhatsApp Bot | supervisorctl | ON | WA bot via supervisorctl start/stop |

> Proxy scanning is **permanently OFF** (threads removed in PERF-02).

## Current Published Catalog

| title_id | Title | Type | share_url |
|----------|-------|------|-----------|
| 25 | Bhooth Bangla | movie | YES |
| 27 | Luka Chuppi | movie | YES |
| 28 | Spider-Noir | show | S1E1+S1E2 YES |
| 30 | Vincenzo | show | S1E1+S1E2 YES |

## APK Status

| Build | Status | Expires |
|-------|--------|---------|
| 1034 | LATEST | 2026-07-08 |

## Backlog

_No open backlog items._

## Non-Negotiable Rules

- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- GitHub pushes via Contents API only — no git shell
- db.setting(k) not db.get_setting(k)
- DB: /opt/jazzmax/radd-hub/data/radd_hub.db
- Add tasks to TASKS.md BEFORE making changes
- Proxy background scanning permanently removed — do NOT re-add threads to ProxyPool
- git stash gotcha: if git pull fails, && skips stash pop. Pop manually if needed.
