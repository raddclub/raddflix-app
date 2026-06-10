# RaddFlix Agent Task Board

_Last updated: 2026-06-10_

---

## Completed — Session 2026-06-10 (6th)

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FEAT-DEVICE-ID-01 | hub/jazzdrive.py, hub/routes/admin.py, hub/templates/settings.html | Device Identity card in admin panel — Android ID `fcbf291eddd5d372` stored as DEFAULT_ANDROID_ID setting, fallback added to get_x_deviceid(), apply-default API to push to all accounts | GitHub 4f1fee3 |

---

## Completed — Session 2026-06-10 (5th)

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-SESSION-GUARDIAN-01 | hub/self_heal.py, hub/uploader.py, hub/routes/upload.py, hub/templates/upload.html | Session Guardian: 45-min read-only probe, WA alert on death/expiry, expiry countdown in UI, smart 401 WA alert | GitHub aeca7bc |

---

## Completed — Session 2026-06-10 (4th)

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-SUSPENSION-01 | hub/_legacy/scanner.py, hub/jazzdrive.py, hub/routes/settings.py, hub/templates/settings.html | Account suspension prevention: scan threads 10→3 (configurable), request delays 0.05→0.8s, SAPI backoff persisted to disk, Scan Safety settings card | GitHub 2296647 |

---

## Completed — Session 2026-06-10 (3rd)

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FEAT-LOG-DETAIL-01 | db.py, scanner.py, routes/settings.py, templates/settings.html, templates/scan.html, templates/upload.html | Clean+detailed logs with auto-delete: icon tags, elapsed time, error highlighting, 7-day retention setting, prune-now button | GitHub 8297829 |

---

## Completed — Session 2026-06-10 (2nd)

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FEAT-CLEAR-LOGS-01 | uploader.py, routes/scan.py, routes/upload.py, templates/scan.html, templates/upload.html, templates/organizer.html | Working Clear button in all 3 log panels — scan log deletes DB rows, upload log flushes in-memory ring buffer, organizer log clears UI div | GitHub 023ed6f |

---

## Completed — Session 2026-06-10

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| TASK-065 | settings.py, settings/scan/upload/organizer .html | Live worker health status bars — auto-refresh every 15s, show service latency/status | GitHub e0b0651d14 |
| BUG-ADMIN-JS-01 | hub/templates/admin.html | Removed dead Delta Sync section (HTML + nested script block left after TASK-063) that caused SyntaxError killing ALL admin JS including Reset Tables button | GitHub e804820b2da1 |
| FEAT-RESET-FEEDBACK-01 | hub/templates/admin.html, hub/routes/admin.py | 3-step live progress panel for Reset Tables: per-table row counts, auto Oracle restart, healthz polling until service back online | GitHub 2b2d44b3aa1c |

---

## Completed — Session 2026-06-09

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| BUG-STALE-IDS | catalog_service.dart, db_helper.dart, catalog_api.py | Flutter never re-synced after DB rebuild (same updated_at timestamp) — added pruneStaleIds(), force-bumped catalog_forced_version | GitHub e9107cb6, cb32f9ba, b523de28 |

---

## Completed — Session 2026-06-08

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| TASK-058 | All 27 route files audited | A-Z Admin Panel Bug Audit — found and fixed 2 real bugs | Oracle + GitHub |
| BUG-AUDIT-01 | app_users_panel.py | /api/stats used wrong column name → Active Subscribers always 0 | Oracle + GitHub |
| BUG-AUDIT-02 | library.py | /api/user/status returned 100% hardcoded fake data | Oracle + GitHub |
| TASK-059 | db.py, admin.py | Schema health check: validate_schema() + startup call + /admin/api/schema-health | Oracle + GitHub |
| BUG-PLANS-01 | db.py init_db() | plans table missing 3 columns (badge, color, features_json) — caught by schema check | Oracle + GitHub |
| TASK-060 | home.html | Pending TID alert banner on dashboard — auto-shows/hides based on pending_tids count | Oracle + GitHub |
| TASK-061 | home.py, home.html | TID inline Approve/Reject buttons on dashboard widget | Oracle + GitHub |
| FIX-CATALOG-02 | Oracle DB | Unpublished 3 ghost titles (Dune, Animal, Inception) that had no linked files | SQL |
| FIX-CATALOG-03 | Oracle DB | Regenerated db_update.json from scratch — version bumped, all 4 titles with real share_urls | Oracle file |

---

## Completed — Session 2026-06-07

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| FIX-CATALOG-01 | Oracle DB | Bumped updated_at on 3 published titles to force Flutter re-sync | SQL |
| FIX-PLAYER-01 | player_screen.dart L2701 | Local video black screen: changed _position==Duration.zero to _duration==Duration.zero | GitHub 215bbc2055 |
| FIX-VAULT-01 | vault_service.dart L157 | Vault biometric: biometricOnly:true throws silently on Infinix Class 2 sensor → changed to false | GitHub 59fc97249c |
| FEAT-AUTOPUB-01 | scanner.py L600,L807,L820 | Auto-publish titles after scan: any title with a linked file that has a share_url is auto-published | Oracle only |

---

## Completed — Session 2026-06-06

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| BUG-DB-RESET-01 | admin.py db_reset() | Reset did not bump catalog_forced_version → Flutter kept showing stale cache | Oracle + GitHub |
| PLAYBACK-01..05 | metadata.py, uploader.py, zero_rating.py, catalog_api.py, jazzdrive.py | All 5 episode playback bugs fixed + remote_id pass-0 matching added | Oracle only |

---

## Completed — Session 2026-06-05

| ID | Changed | Summary | Ref |
|----|---------|---------|-----|
| PROXY-UPGRADE | proxy_pool.py, uploader.py, settings.py, templates | God-level proxy pool rewrite: 150+ seeds, WeightedScore rotation, CircuitBreaker, proxy-chain retry in uploader | GitHub |

---

## Current DB State (as of 2026-06-10)

> DB is EMPTY after reset testing. Run JazzDrive scan to rebuild.

| Table | Rows |
|-------|------|
| titles | 0 |
| files | 0 |
| accounts | 1 |

---

## APK Status

| Build | Status | Fixes included |
|-------|--------|----------------|
| 1023 | ❌ OLD — do not use | none of our fixes |
| 1025 | ✅ LATEST | FIX-PLAYER-01 + FIX-VAULT-01 |

---

## Open Backlog

| ID | Issue | Priority |
|----|-------|----------|
| DB-REBUILD | DB is empty after reset test — need JazzDrive scan | HIGH |
| DATA-01 | All Of Us Are Dead: E03/E04/E05/E09 not scanned | MEDIUM |
| OAUTH-01 | Account 03286829827: refresh_token expired (invalid_grant) — needs OTP re-login | LOW |

---

## Non-Negotiable Rules

- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- XOR padding fix must stay in `request_encoder.dart`
- GitHub pushes via Trees API only — no git shell
- Oracle Python3 for large file GitHub API calls
- GitHub token in local Replit env `GITHUB_TOKEN` (Oracle `.env` empty)
- SSH key: reconstruct from `ORACLE_SSH_KEY` env var to `/tmp/oracle_key` on each session
- `db.setting(k)` not `db.get_setting(k)`
- DB: `/opt/jazzmax/radd-hub/data/radd_hub.db`
- Backend process: `python3 radd_hub.py run --skip-setup` in `/opt/jazzmax/radd-hub/`
- After ANY direct SQL change to `is_published`: regenerate `db_update.json` via Python script
- Always append session summary to `agent-hub/history/TASK_LOG.md` before ending session
| PERF-01 | ✅ DONE | Oracle proxy pool CPU fix — throttled HC/recovery/disc workers (40→8, 80→10), capped HC batch to 300/run, spaced intervals (10min→30min HC, 5min→15min recovery, 15min→60min disc), VACUUM'd DB | 2026-06-10 |
| PERF-02 | ✅ DONE | Permanently disable all proxy background threads (HC/recovery/discovery/seed-test) — admin triggers manually via settings page | 2026-06-10 |
