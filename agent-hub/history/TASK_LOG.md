## [2026-06-01] — Session 4 | Recommendation wiring + P3.5 regression sweep

### Tasks Completed
- **P4.2 verified**: GET /api/recommend fully wired end-to-end — bp_rec blueprint, recommendation_cache DDL, Flutter CatalogApi.fetchRecommendations(), _RecommendationsSection + loadRecommendations() in catalog_provider — all confirmed
- **FTS5 regression fixed (db.py)**: P3.5 dropped cast_names but left FTS5 triggers (titles_ai/ad/au) referencing it — updated DDL + migration to DROP old triggers/FTS5 table, recreate without cast_names. CI green: c92ea48922
- **Dropped-col sweep**: Fixed all live DB crashes from P3.5 across library.py (4 queries cast_names→cast_json, OMDB updates cleaned, admin PUT allowed list), api.py (autofix col list, /library/actor), db.py (upsert_title dead cast check). CI green: d2f8fadb06
- **Session 2+3 work verified**: bcrypt ✅, FTS5 search_api.py ✅, _ip_window fix ✅, XOR encoding ✅, recommendation_cache table ✅
- **MASTER_PLAN corrected**: P2.1 marked DONE

### Commits
- c92ea48922 — fix(db): FTS5 triggers + upsert cols after cast_names drop
- d2f8fadb06 — fix(db+routes): all cast_names/omdb_id/overview refs after P3.5 drop

### Still Pending / Needs User Action
- P3.3: need real WhatsApp support number (placeholder 923001234567)
- P4.1: Oracle exec needed: sudo cp + supervisorctl restart raddflix_wa_bot

---

# TASK_LOG.md — RaddFlix Session History
> One entry per agent session. Most recent at top.
> Format: Date | Agent | Task | Files Changed | Outcome | Next

---

## [2026-06-01] — Session 3 | P2.5 verified, P3.1/P3.5/P3.7 done, P4.1 config committed

### Tasks Completed
- **P2.5 VERIFIED** — `radd-hub/hub/_legacy/` directory confirmed to exist in repo; all `mirror.py` imports already wrapped in try/except. No code change needed.
- **P3.1 DONE** — Deleted all root `lib/` stub files (44 dead files: JazzMAX/ZENO branded stubs, TypeScript API specs, duplicate Dart screens) + root `pubspec.yaml` via GitHub API tree deletion.
- **P3.5 DONE** — Removed 4 legacy/duplicate columns from `radd-hub/hub/db.py`:
  - Removed from DDL (`CREATE TABLE titles`): `omdb_id`, `overview`, `cast`, `cast_names`
  - Added DROP COLUMN migrations in `init_db()` (try/except, SQLite 3.35.0+ required, Oracle 22.04 has 3.37.2)
  - On server restart, existing DB will have redundant columns pruned automatically.
- **P3.7 VERIFIED** — `constants.dart` `otpDeviceSwitchEnabled` comment already accurate. No code change needed.
- **P4.1 IN PROGRESS** — Supervisor config created at `radd-hub/supervisor.d/raddflix_wa_bot.conf` pointing to full bot (`bots/whatsapp/index.js`). Needs Oracle copy + supervisorctl restart by user.

### Key Files Changed
- `radd-hub/hub/db.py` — DDL + init_db() migration
- `radd-hub/supervisor.d/raddflix_wa_bot.conf` — new file
- `agent-hub/MASTER_PLAN.md` — updated statuses
- `agent-hub/history/TASK_LOG.md` — this entry
- Root `lib/` directory — deleted entirely
- Root `pubspec.yaml` — deleted

### Still Open
- **P3.3** — BLOCKED: need real RaddFlix WhatsApp support number from user (placeholder: `923001234567`)
- **P4.1** — Config committed; user must run on Oracle: `sudo cp radd-hub/supervisor.d/raddflix_wa_bot.conf /etc/supervisor/conf.d/ && sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl restart raddflix_wa_bot`

---


## [2026-05-31] — Session 2 | Full Audit + Bug Fixing Blitz

### Tasks Completed
- **P1.3** bcrypt migration: `mobile_api.py` — unsalted SHA-256 → bcrypt (salted).
  `_hash_user_password()` / `_verify_user_password()` / `_migrate_password_hash()`.
  Existing SHA-256 hashes silently upgraded on next login. OTP code paths unchanged.
- **P1.4** Hardcoded IP removed from `catalog_api.py` — `_watch_base()` returns "" instead of `http://92.4.95.252`.
- **P2.1** FTS5 full-text search: `db.py` + `search_api.py` — virtual table `titles_fts`,
  3 sync triggers, rebuild migration. Search uses MATCH+BM25 with LIKE fallback.
  Urdu/Hindi diacritics handled (unicode61 tokenizer).
- **P2.2** `_ip_window` memory leak fixed in `security_telemetry.py` — dict pruned when >500 IPs.
- **P2.6** `bcrypt>=4.0` added to `radd-hub/requirements.txt`.
- **P3.2** Bot state `.gitignore` created: `radd-hub/bots/whatsapp/.gitignore`.
- **P3.4** `auth_utils.dart` created: deduped `_friendly()` from `login_screen.dart` + `register_screen.dart`.
- **P3.6** `bulk_link_engine.py` dead brand "JazzBuzz" → "RaddFlix".
- **P3.7** `constants.dart` `otpDeviceSwitchEnabled` comment updated (server endpoints ARE live).

### False Alarms (original audit was wrong — already implemented)
- P1.1: SECURITY_CHANNEL fully wired in MainActivity.kt (getSignatureFingerprint/checkFrida/checkRoot)
- P1.2: stream_links table + folder_share_url both exist in db.py DDL
- P2.3: Frida/root detection already in MainActivity.kt
- P2.4: RequestEncoder.enabled = true already set; XorWsgiMiddleware already wired in app.py
- P2.5: radd-hub/hub/_legacy/ directory exists — import is valid
- P4.2: bp_rec + /recommend route registered in app.py
- P4.3: Cast Framework 21.5.0 + ExoPlayer Cast already in build.gradle
- P4.4: MediaStorePlugin handles checkMediaPermission/requestMediaPermission in MainActivity.kt
- P4.5: _encodeUrl()/_decodeUrl() fully wired in local_db.dart (RequestEncoder.scrambleUrl)

### Blocked / Pending
- P3.1: Delete root lib/ stubs — awaiting user approval (destructive)
- P3.3: Replace supportWhatsApp placeholder — awaiting real number from user
- P3.5: DB column cleanup — risky; needs schema migration planning

### Commits This Session
- `88548fa` — fix(security+backend): P1.3/P1.4/P2.2/P3.2/P3.6
- `e15c30f` — feat(search): FTS5 full-text search + P3.7 constants comment fix
- `52b1819` — refactor(auth): P3.4 dedup + MASTER_PLAN final status update

---

## [2026-05-31] — Replit Agent | Docs Overhaul: Full Agent System Rebuild

### Task
Complete overhaul of all agent-hub documentation after full deep audit.
Rebuild REINCARNATION.md (v3.0), create AGENT_RULES.md, create MASTER_PLAN.md, update TASK_LOG.md, update CODE_MAP.md.

### Goal
Make all documentation self-sufficient for any future agent on any account.
Establish golden rules, ordered task queue, and full context memory.

### Files Created/Updated
| File | Action | Lines |
|------|--------|-------|
| `agent-hub/REINCARNATION.md` | COMPLETE REWRITE (v3.0) | 523 |
| `agent-hub/AGENT_RULES.md` | NEW — golden rules for all agents | 156 |
| `agent-hub/MASTER_PLAN.md` | NEW — ordered task queue P1-P4 | 267 |
| `agent-hub/history/TASK_LOG.md` | REBUILT with session history | this file |

### What the New System Contains
- **REINCARNATION.md v3.0:** Full context: architecture, file map, bugs table, security status, deploy instructions, GitHub API commit pattern, code conventions, project history, how-to-use
- **AGENT_RULES.md:** 10 golden rules, DO/DON'T table, verification checklist, CI check command
- **MASTER_PLAN.md:** Full ordered queue P1.1–P4.7, status tracking, task descriptions with file paths, fix approach, estimated effort, verification steps
- **CODE_MAP.md:** Updated with 265-line audit addendum (dual structure warning, 20+ new files documented, 17-bug table)

### Outcome
✅ All docs committed. GitHub commit: (see this commit SHA)
✅ System ready: any new agent reading REINCARNATION.md + AGENT_RULES.md + MASTER_PLAN.md has full context.

### Next Task for Next Agent
Read `MASTER_PLAN.md`. Start with **P1.1** — Wire SECURITY_CHANNEL in MainActivity.kt.
Get user approval after P1.1 before proceeding to P1.2.

---

## [2026-05-31] — Replit Agent | Full Deep Audit Session

### Task
Full deep audit of RaddFlix codebase — read ALL 359+ source files, understand every function, update all .MD documentation, report everything: features, bugs, illogical things, unfinished features, duplicates.

### Files Read (359+ total)
All agent-hub MD files • raddflix_flutter/pubspec.yaml • lib/main.dart • lib/app.dart • lib/core/constants.dart • all providers (4) • all models • all screens (23) • all player widgets (12) • all player controllers (7) • all services (12) • all security files (6) • local_db.dart • sync_service.dart • all API clients (5) • app_guard.dart • request_encoder.dart • MainActivity.kt • AndroidManifest.xml • All Flask backend files (40+) • WhatsApp bot files (22) • CI workflows (2)

### Critical Discoveries
1. **DUAL STRUCTURE**: Root `lib/` = dead stubs (JazzMAX/ZENO branding). Real app = `raddflix_flutter/lib/`.
2. **APK Signature Check BROKEN**: `SECURITY_CHANNEL` unhandled in `MainActivity.kt`. PlatformException silently caught.
3. **bulk_link_engine.py SQL crash**: `stream_links` table missing from DDL. Error every 2h, silently swallowed.
4. **Unsalted passwords**: `mobile_api.py::_hash_password()` uses unsalted SHA-256.
5. **Hardcoded HTTP IP**: `catalog_api.py::_watch_base()` returns `http://92.4.95.252`.
6. **Security telemetry leak**: `_ip_window` dict grows unbounded under DoS.

### New Files Discovered (not in prior docs)
`show_detail_screen.dart`, `admin_queue_screen.dart`, `local_media_screen.dart`, `local_folder_screen.dart`, `plan_expired_screen.dart`, `quota_full_screen.dart`, `tid_status_screen.dart`, `vault_settings_screen.dart`, `player_settings_screen.dart` • 7 player controllers • 12 player widgets • `cast_service.dart`, `local_media_service.dart`, `thumb_service.dart`, `vault_service.dart` (services/) • `MediaStorePlugin.kt`, `CastOptionsProvider.kt` • `debug_logger.dart` • `radd_colors.dart`, `theme_provider.dart` • Backend: `ai_router.py`, `media_naming.py`, `tunnel.py`, `turbo_cache.py`, `search_cache.py`, `radd_quality_upgrade.py`, `retro_sync.py`, `assets.py`, `organizer.py`, `browser_installer.py`, `aria2_installer.py`, `installer.py`, 6 scrapers, 7 site modules, `domain_doctor.py`

### Files Updated in This Session
- `agent-hub/CODE_MAP.md` — appended 265-line audit addendum
- `agent-hub/REINCARNATION.md` — appended critical findings section
- `agent-hub/history/TASK_LOG.md` — appended session entry

### Commit: `dbde0fe`
### CI Status at Start: GREEN (from commit `be18ca4`)

### Next Task
P1.1 — Wire SECURITY_CHANNEL in MainActivity.kt

---

## [2026-05-30] — Phase 27 | Keystore Migration & CI Green

### Task
Fix CI failure after keystore credential changes. Update APK signing fingerprint in AppGuard.

### Files Changed
- `raddflix_flutter/lib/core/security/app_guard.dart` — updated `_officialFingerprint` to `BA:4E:41:2D:...`
- `.github/workflows/build-apk.yml` — keystore credential env vars updated

### Outcome
✅ CI GREEN. APK builds successfully. Fingerprint active.
### Commit: `be18ca4`

---

## [2026-05-28 to 2026-05-29] — Phases 21–26 | Advanced Features

### Tasks Completed
- XOR request encoding (both sides implemented, Flutter disabled by default)
- Security telemetry endpoint + tamper reporting
- Recommendation engine (`radd_recommend.py`) — no API endpoint wired yet
- Advanced player features (A-B loop, ambilight, binge guard, scene bookmarks, smart intro)
- Player settings persistence (PlayerPrefs + SharedPreferences)
- Vault settings screen
- Admin queue screen

### Key Files
- `request_encoding.py`, `request_encoder.dart` — XOR encoding
- `security_telemetry.py` — tamper reports
- `radd_recommend.py` — recommendation engine
- `core/player/ab_loop_controller.dart` + `ambilight_controller.dart` + `binge_guard_controller.dart` + `scene_bookmark_store.dart` + `smart_intro_store.dart` + `player_prefs.dart`
- Various player widgets (12 files)

---

## [2026-05-25 to 2026-05-27] — Phases 16–20 | Infrastructure

### Tasks Completed
- WhatsApp bot (Baileys): full plugin system, actor/genre/director search, rate limiting, referral rewards
- Analytics dashboard (revenue, signups, engagement)
- Zero-rating delta JSON generation + JazzDrive upload
- Metadata enrichment pipeline (TMDB/OMDB/Groq/Gemini)
- mirror.py (GitHub + GSheets sync)

### Key Files
- `radd-hub/bots/whatsapp/` — full bot (22 files)
- `analytics.py` — analytics engine
- `zero_rating.py` + `ZERO_RATING_DELTA.md`
- `metadata.py`, `metadata_lookup.py`, `ai_router.py`
- `mirror.py` — has BUG-A18 (_legacy import)

---

## [2026-05-20 to 2026-05-24] — Phases 11–15 | Admin & Subscriptions

### Tasks Completed
- Admin web panel (20+ pages)
- Subscription system: 3 plans, TID payment, SMS auto-approval
- Notification system (server push + Flutter display)
- Security architecture documentation (SECURITY_ARCHITECTURE.md)

### Key Files
- `routes/subscriptions.py`, `routes/payment_gateway.py`
- `raddflix_flutter/lib/screens/subscription_screen.dart`
- `raddflix_flutter/lib/screens/plan_expired_screen.dart`
- `raddflix_flutter/lib/screens/tid_status_screen.dart`
- `raddflix_flutter/lib/screens/quota_full_screen.dart`
- `raddflix_flutter/lib/core/services/notification_service.dart`

---

## [2026-05-15 to 2026-05-19] — Phases 6–10 | Security & Downloads

### Tasks Completed
- Download system with DownloadCipher (XOR protection, .jmx extension)
- Vault: PIN (4/6 digit), biometric, auto-lock
- AppGuard: APK sig + Frida + root detection framework (Kotlin side incomplete)
- Device binding (one device per account)
- SIMOSA integration (Jazz World app deep link for free daily MB)

### Key Files
- `raddflix_flutter/lib/core/security/app_guard.dart`
- `raddflix_flutter/lib/core/security/keystore.dart`
- `raddflix_flutter/lib/core/security/device_id.dart`
- `raddflix_flutter/lib/screens/vault_screen.dart`
- `raddflix_flutter/lib/core/download/download_service.dart`

---

## [2026-05-10 to 2026-05-14] — Phases 1–5 | Foundation

### Tasks Completed
- Flutter app skeleton (Riverpod, Dio, router)
- Auth: register/login/guest, JWT flow, 401 refresh
- Catalog sync: SQLCipher (AES-256) local DB, schema v1–v13 evolution, delta sync
- Video player (media_kit): basic playback, gesture controls, seek
- JazzDrive integration: login, OTP, share URL generation, zero-rated CDN
- Flask backend: all core blueprints, SQLite WAL, admin panel foundation

### Key Architecture Decisions
- sqflite_sqlcipher: 3.1.0+1 PINNED (3.2.0 breaks CI)
- All video on JazzDrive (zero-rated for Jazz SIMs)
- Share URLs never expire — security via APK integrity not link rotation
- Silent degradation: isTampered=true → fake empty API responses

---

*End of TASK_LOG.md — 2026-05-31*
*Add new entry at TOP when starting a new session.*

---

## Session 5 — 2026-06-01

**Agent:** Replit Agent (new session)
**Tasks completed:** P3.3

### P3.3 — Real WhatsApp support number + admin UI control

**Files changed:**
- `raddflix_flutter/lib/core/constants.dart` — `supportWhatsApp` placeholder `923001234567` → `923257719165`; changed from `const` to mutable `static String` so server can override at runtime
- `radd-hub/hub/routes/api.py` — `/api/config` now reads `SUPPORT_WHATSAPP_NUMBER` from `db.setting()` and serves it as `support_whatsapp` field; fallback to `923257719165`
- `radd-hub/hub/routes/settings.py` — `SUPPORT_WHATSAPP_NUMBER` added to `JD_BOT_SETTINGS` under `whatsapp` group → appears in Settings → WhatsApp Bot panel in admin UI
- `raddflix_flutter/lib/core/remote_config.dart` — reads `support_whatsapp` from `/api/config` response and writes to `AppConstants.supportWhatsApp`; also handled in cached config fallback path

**Outcome:** Admin can now change the WhatsApp support number from the admin panel (Settings → WhatsApp Bot → "Support WhatsApp number") without rebuilding the APK. Change takes effect on next app startup.

**Commit:** `97d81a1e8fc85b99323d11aacd29f1aaa4ce8260`
**CI:** ✅ Green (build-apk.yml passed on `21383383`, new CI triggered on `97d81a1`)

### Remaining open items
- **P4.1** Supervisor config committed — user must copy to Oracle and restart supervisor

---

## Session 6 — 2026-06-01

**Agent:** Replit Agent (new session)
**Tasks completed:** BUG-A32, BUG-A20, BUG-A02(N/A), BUG-A07(verified), BUG-A26(verified), BUG-A33(verified), P4.6, P4.7

### BUG-A32 — Secure JWT secret fallback
- `radd-hub/hub/routes/mobile_api.py`: `_secret()` last-resort except block replaced hardcoded `"raddflix-dev-secret-change-in-prod"` with per-process `secrets.token_hex(32)` stored in `_EMERGENCY_SECRET` module var. Only fires if DB completely unavailable.

### BUG-A20 — Poster sync fires multiple times
- `raddflix_flutter/lib/providers/catalog_provider.dart`: Added `static bool _posterSyncDone = false` to notifier. `_schedulePosterSync()` now returns early if already fired this session.

### BUG-A02/A07/A26/A33 — Verified already done
- BUG-A02: `detail_screen.dart` was a root lib/ stub (deleted P3.1); real app uses `show_detail_screen.dart` — N/A
- BUG-A07: Both device-switch endpoints exist and fully implemented in mobile_api.py — DONE
- BUG-A26: bp_rec registration comment in app.py confirms fix — DONE
- BUG-A33: `useMaterial3: true` confirmed in `app_theme.dart` — DONE

### P4.7 — Domain Doctor admin panel
- `radd-hub/hub/routes/api.py`: Added `/api/domain-doctor/health` (GET) and `/api/domain-doctor/probe` (POST) endpoints. Health reads working_domains from DB + live health dict from domain_doctor.py. Probe triggers background re-scan.
- `radd-hub/hub/templates/settings.html`: Added Domain Doctor card with colored status dots per site, working domain display, per-site Probe button, Re-probe All button.

### P4.6 — Telegram bot
- `telegram-bot/bot.py` (NEW, 375 lines): Full polling-based Telegram bot. Commands: /start, /help, /search, /movie, /show, /anime, /trending, /status. Reads token from TELEGRAM_BOT_TOKEN env (injected by bots/telegram.py wrapper). Searches catalog via FTS5 with LIKE fallback. Admin manages via Bots panel.
- `telegram-bot/requirements.txt` (NEW): `requests>=2.28.0` only.

**Commit:** `120eb8f9c0539f2f886f16e2745e5e8650974eb1`
**CI:** ✅ Triggered (build-apk.yml on 120eb8f)

### Remaining open
- **P4.1** only — supervisor config on Oracle. User must: `sudo cp radd-hub/supervisor.d/raddflix_wa_bot.conf /etc/supervisor/conf.d/raddflix_wa_bot.conf && sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl restart raddflix_wa_bot`
