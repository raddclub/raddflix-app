# RaddFlix Agent Task Board

_Last updated: 2026-06-10_

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
