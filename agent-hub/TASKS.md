# RaddFlix Agent Task Board

_Last updated: 2026-06-12_

## Completed This Session

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| ✅ FIX-UPLOAD-VISIBLE | hub/uploader.py | Promote paused-tick log from DEBUG→INFO (throttled) so Services toggle is visible in upload log stream | this |
| ✅ FIX-SVC-TOGGLE | mirror.py, scheduler.py, downloader.py, keepalive.py, domain_doctor.py | Add *_ENABLED DB-key checks to all background service loops so Services page toggle actually pauses work | this |
| ✅ FEAT-SERVICES-ROUTES | hub/routes/admin.py | Added /services page + /api/services GET + /api/services/toggle POST to admin blueprint | this |
| ✅ FIX-SERVICES-NAV | hub/templates/base.html | Re-added Services nav link to SYSTEM sidebar section (dropped during PROXY-REMOVE) | this |
| ✅ FIX-DEVICE-NAME-2 | hub/jazzdrive.py, radd_hub.db settings | Fixed garbled JazzDrive device name: (1) set JAZZDRIVE_DEVICE_NAME=Infinix X680F in settings; (2) added X-devicename + corrected User-Agent in Strategy 2 OAuth2 refresh; (3) fixed get_auth_headers fallback | 91b3aef + this |
| PROXY-REMOVE | hub/app.py, hub/routes/settings.py, hub/templates/base.html, hub/templates/settings.html | Fully removed proxy/pool system: stripped proxy_pool_page blueprint + broken try/except from app.py; all 13 pool routes from settings.py; proxy-pool nav from base.html; JazzDrive Network/Services cards + pool panel include + JS from settings.html | 1473481 |
| DB-RECOVERY-01 | radd_hub.db accounts table | Recovered wiped DB: re-inserted JazzDrive account 03257719165 (role=flix, is_active=1) from jazzdrive_session.json | SQL |
| FIX-WG0-ENFORCE | hub/jazzdrive.py | Hard-block ALL JazzDrive network calls if wg0 not routing JD IPs. Added JDVPNRequired exception + require_wg0() — called from resolve_proxies(), _android_refresh_session_inner(), trigger_otp_flow(), resend_otp(), submit_otp(). No JD call ever leaks via Oracle direct IP. | 23988eb (GitHub); wg0v2 applied direct |
| FEAT-SERVICES-01 | admin.py, services.html (new), base.html, admin.html, settings.html, scan.html, upload.html | Consolidated all 8 service toggles to dedicated /admin/services page. Removed service cards from admin.html + settings.html. Updated paused-banners in scan.html + upload.html to link /admin/services. | b55df7f, 46122dc |
| PERF-01 | proxy_pool.py, hub/db | Diagnosed proxy-pool CPU spike (99.9%). Throttled ThreadPoolExecutors (40→8, 80→10), extended HC/discovery intervals, VACUUM'd SQLite DB | dde746e |
| PERF-02 | proxy_pool.py | Permanently removed all 4 background proxy threads (hc_loop, recovery_loop, disc_loop, test_seeds_bg) from ProxyPool.start() + _seed_if_empty(). CPU → ~2%, threads → 9 | 519f649 |
| PERF-03 | mirror.py, downloader.py, keepalive.py, scheduler.py, routes/admin.py, templates/admin.html | Added per-service DB-toggle system + admin UI card with live switches. 8 services controlled (including WA bot via supervisorctl) | 81f0300–d529b1e |
| PERF-05 | routes/admin.py, templates/admin.html | Service dependency logic: auto-enable deps when enabling a service, warnings when disabling a required service, visual missing/broken indicators in UI. Ordered services by dependency chain. | 2ba55de, 88be21e |
| PERF-04 | downloader.py | Fixed DOWNLOAD_ENABLED check: was before thread reaping (skip cleanup on disable), moved to just before new-job dispatch. Active jobs now finish cleanly; hang watchdog always runs | 62407f7 |

## Previous Completed Tasks

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-CATALOG-01 | Oracle DB | Bumped updated_at on 3 published titles to force Flutter re-sync | SQL |
| FIX-PLAYER-01 | player_screen.dart L2701 | Local video black screen: changed _position==Duration.zero to _duration==Duration.zero in AnimatedOpacity | 215bbc2055 |
| FIX-VAULT-01 | vault_service.dart L157 | Vault biometric: biometricOnly:true throws silently on Infinix Class 2 sensor; changed to false | 59fc97249c |
| FEAT-AUTOPUB-01 | scanner.py L600,L807,L820 | Auto-publish titles after scan: new SQL helper publishes any title with a linked file that has a share_url | Oracle only |
| FIX-CATALOG-02 | Oracle DB | Unpublished 3 ghost titles (Dune id=15, Animal id=16, Inception id=20) — is_published=1 but zero files linked | SQL |
| FIX-CATALOG-03 | Oracle DB | Regenerated db_update.json from scratch — stale June 2 version replaced with 4 real titles all with share_urls | Oracle file |

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

> Proxy scanning is **permanently OFF** (no DB toggle needed — threads removed from code in PERF-02).
> Manual triggers still available: /api/pool/healthcheck, /api/pool/discover in Settings page.

## Current Published Catalog (clean state)

| title_id | Title | Type | file_id | share_url |
|----------|-------|------|---------|-----------|
| 25 | Bhooth Bangla | movie | 18 | YES |
| 27 | Luka Chuppi | movie | 28 | YES |
| 28 | Spider-Noir | show | — | S1E1(f31) S1E2(f30) YES |
| 30 | Vincenzo | show | — | S1E1(f35) S1E2(f32) YES |

## APK Status

| Build | Status | Fixes included | Size | Expires |
|-------|--------|----------------|------|---------|
| 1023 | OLD — do not use | none of our fixes | 56MB | — |
| 1025 | LATEST — install this | FIX-PLAYER-01 + FIX-VAULT-01 | 56MB | 2026-07-07 |

GitHub Actions run: https://github.com/raddclub/raddflix-app/actions/runs/27100948120

## Backlog

_No open backlog items._

## Non-Negotiable Rules

- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- GitHub pushes via Contents API only — no git shell
- Oracle Python3 for large file GitHub API calls
- GitHub token in local Replit env GITHUB_TOKEN (Oracle .env empty)
- SSH key: reconstruct from ORACLE_SSH_KEY env var to /tmp/oracle_key on each session
- db.setting(k) not db.get_setting(k)
- DB: /opt/jazzmax/radd-hub/data/radd_hub.db
- Backend process: python3 radd_hub.py run --skip-setup in /opt/jazzmax/radd-hub/
- After ANY direct SQL change to is_published: regenerate db_update.json via Python script
- Add tasks to TASKS.md BEFORE making changes
- Proxy background scanning is permanently removed — do NOT re-add background threads to ProxyPool
- git stash && git pull && git stash pop before any Oracle-side git operations
