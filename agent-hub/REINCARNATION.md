# REINCARNATION.md — RaddFlix Full Agent Context
> **EVERY AGENT READS THIS FIRST. NO EXCEPTIONS.**
> Last Updated: 2026-05-31 | By: Replit Agent (Full Deep Audit)
> Version: 3.0 — Complete Rewrite

---

## ⚡ IMMEDIATE STATUS (READ THIS FIRST)

> **Last agent session: 2026-06-01 (Session 6)**
> **ALL tasks complete except P4.1 (needs Oracle restart). Nothing in backlog.**

### WHAT WAS DONE IN SESSION 6
- ✅ BUG-A32: `_secret()` hardcoded fallback → per-process random secret
- ✅ BUG-A20: `catalog_provider.dart` poster sync fires multiple times → static guard added
- ✅ BUG-A02: Verified N/A — `detail_screen.dart` was dead stub; `show_detail_screen.dart` works correctly
- ✅ BUG-A07: Verified DONE — device-switch endpoints fully implemented
- ✅ BUG-A26: Verified DONE — bp_rec registration fix confirmed
- ✅ BUG-A33: Verified DONE — `useMaterial3: true` already set
- ✅ P4.7: Domain Doctor admin panel — `/api/domain-doctor/health` + `/probe` + Settings card with live status
- ✅ P4.6: Telegram bot — `radd-hub/telegram-bot/bot.py` created (/search, /movie, /show, /trending, /help)
         (path fix: config.PROJECT_ROOT → radd-hub/, not repo root)

### WHAT WAS DONE IN SESSION 5
- ✅ P3.3: `supportWhatsApp` set to `923257719165`; made mutable; admin can change via Settings → WhatsApp panel; `/api/config` serves it; `RemoteConfig` reads it on startup (no APK rebuild needed)

### WHAT WAS DONE IN SESSION 3
- ✅ P3.1: Root `lib/` dead stubs deleted (44 files — JazzMAX/ZENO branded, TS api-specs, duplicate screens)
- ✅ P3.5: Legacy DB columns removed from `radd-hub/hub/db.py` DDL + DROP COLUMN migrations added (`omdb_id`, `overview`, `cast`, `cast_names`)
- ✅ P3.7: VERIFIED — `constants.dart` comment already accurate (no code change needed)
- ✅ P2.5: VERIFIED — `_legacy/` directory confirmed in repo; `mirror.py` imports already try/except protected (no code change needed)
- 🔄 P4.1: Supervisor config committed to `radd-hub/supervisor.d/raddflix_wa_bot.conf` — user must copy to Oracle

### OPEN ITEMS
1. **P4.1** Supervisor config ready — user must run on Oracle:
   ```
   sudo cp radd-hub/supervisor.d/raddflix_wa_bot.conf /etc/supervisor/conf.d/raddflix_wa_bot.conf
   sudo supervisorctl reread && sudo supervisorctl update
   sudo supervisorctl restart raddflix_wa_bot
   ```

### SESSION 6 COMMITS
- `b27f8297` — fix(p4.6): move telegram bot to radd-hub/telegram-bot/ (correct PROJECT_ROOT path)
- `120eb8f` — fix(bugs)+feat(p4.6,p4.7): BUG-A32 secure secret; BUG-A20 poster guard; domain doctor panel; Telegram bot

### SESSION 3 COMMITS
- `53c95e9` — chore(cleanup): P3.1 delete root lib/ dead stubs + pubspec.yaml
- `3c54ef3` — fix(db): P3.5 drop legacy titles cols; feat(bot): P4.1 supervisor config; docs: verified P2.5/P3.7


## 📁 REPOSITORY STRUCTURE

```
raddflix-app/                         ← GitHub: raddclub/raddflix-app
│
├── raddflix_flutter/                 ← ⭐ REAL FLUTTER APP (build from here)
│   ├── lib/                          ← All Dart source (canonical)
│   ├── android/                      ← Android native (MainActivity.kt, Manifest)
│   └── pubspec.yaml                  ← REAL deps (sqflite_sqlcipher: 3.1.0+1)
│
├── radd-hub/                         ← Flask backend + WhatsApp bot
│   ├── hub/                          ← Flask app (app.py is entrypoint)
│   │   ├── app.py                    ← Flask factory + blueprint registration
│   │   ├── db.py                     ← ALL SQLite DDL (schema v13)
│   │   ├── auth.py                   ← JWT helpers
│   │   ├── config.py                 ← Flask config loader
│   │   ├── routes/                   ← 20 Blueprint files
│   │   ├── scrapers/                 ← 6 scraper modules
│   │   ├── sites/                    ← 7 CDN resolver modules
│   │   └── bots/whatsapp/            ← Simple bot (supervisor: raddflix_wa_bot)
│   └── bots/whatsapp/                ← Full-featured standalone bot (22 files)
│
├── agent-hub/                        ← 📚 AI AGENT DOCUMENTATION (this folder)
│   ├── REINCARNATION.md              ← THIS FILE — full context for every agent
│   ├── AGENT_RULES.md                ← Golden rules all agents must follow
│   ├── MASTER_PLAN.md                ← Ordered task queue with status
│   ├── CODE_MAP.md                   ← File-by-file reference
│   ├── PRODUCT_CONTEXT.md            ← Business/product context
│   ├── SECURITY_ARCHITECTURE.md      ← Security deep dive
│   ├── PLAYER_SPEC.md                ← Player feature specification
│   ├── STREAMING_ARCHITECTURE.md     ← JazzDrive / streaming architecture
│   ├── ZERO_RATING_DELTA.md          ← Delta sync specification
│   ├── AGENT_CONNECTIONS_GUIDE.md    ← How agents access GitHub/Oracle
│   ├── SETUP.md                      ← Oracle server setup
│   └── history/TASK_LOG.md           ← Per-session audit log
│
├── lib/                              ← ⛔ OLD STUBS — NEVER TOUCH (see warning)
├── pubspec.yaml                      ← ⛔ OLD — NEVER TOUCH (see warning)
└── .github/workflows/                ← CI: build-apk.yml + ci-tests.yml
```

### ⛔ CRITICAL: DUAL FILE STRUCTURE WARNING
```
Root lib/ = OLD STUBS (JazzMAX branding, ZENO comments, jmx_vault, plain sqflite)
raddflix_flutter/lib/ = REAL APP (RaddFlix branding, sqflite_sqlcipher encrypted)
```
**Never edit root `lib/` or root `pubspec.yaml`. They are dead code.** CI ignores them.

---

## 🏗️ ARCHITECTURE OVERVIEW

### How the App Works End-to-End

```
[User's Android Phone]
       │
       ▼
[Flutter App — raddflix_flutter/]
  • Riverpod state management
  • Dio HTTP client (auto JWT attach + 401 refresh)
  • SQLCipher local DB (AES-256, schema v13)
  • media_kit video player
  • AppGuard security shield (startup)
       │
       │  HTTPS (apiBaseUrl, updated by RemoteConfig on startup)
       ▼
[Flask Backend — radd-hub/hub/]  on Oracle 92.4.95.252:5000
  • 20 Blueprints (auth, catalog, stream, subscription, payment, etc.)
  • SQLite WAL (server-side, schema v13)
  • JazzDrive integration (zero-rated CDN)
  • Scheduler (rescan, delta gen, downloads)
  • Analytics + admin web panel
       │
       ▼
[JazzDrive CDN — cloud.jazzdrive.com.pk]
  • All video files stored here
  • Zero-rated for Jazz SIM users (data-free streaming)
  • Share URLs never expire (per owner confirmation)
  • Protected by: AppGuard + silent degradation on tamper
```

### Zero-Rating Flow (JazzDrive)
```
Server generates delta.json every 6h
  → Contains {file_id → share_url} for all library items
  → Uploaded to JazzDrive and hosted zero-rated
  → Flutter fetches delta.json on startup
  → Stores share_urls in local SQLCipher DB
  → Player reads share_url from DB → streams zero-rated
```

### Authentication Flow
```
Register/Login → POST /api/auth/register|login
  → Server: SHA-256 hash (⚠️ UNSALTED — BUG P1.3)
  → Returns: {access_token (15min JWT), refresh_token (90-day JWT)}
  → Flutter stores in flutter_secure_storage (Android Keystore backed)
  → Expired access token → auto-refresh via /api/auth/refresh
  → Device binding: device_id in JWT payload → one device per account
```

### Offline-First Sync
```
Startup: JazzDriveService.loadCacheFromDb() + LocalDb.cleanExpiredStreamCache()
Every 6h: SyncService fetches /api/catalog/sync?version=N
  → Delta JSON → inserts/updates titles + episodes in SQLCipher DB
  → Background poster download → cached to disk
  → FTS5 index updated for local search
```

---

## 📱 FLUTTER APP — KEY FILES REFERENCE

### Entry Points
| File | Role |
|------|------|
| `lib/main.dart` | Entry point: MediaKit init, AppGuard, RemoteConfig, runApp |
| `lib/app.dart` | MaterialApp, route table (18 routes + onGenerateRoute), ForceUpdateGuard |
| `lib/core/constants.dart` | ALL constants: API paths, routes, feature flags, DB version |

### Screens (14 main + 9 new)
| Screen | Purpose |
|--------|---------|
| `home_screen.dart` | Main feed: movies + shows grid, categories, search bar, notif banner |
| `detail_screen.dart` | Movie detail: info, cast, play/download/watchlist buttons |
| `show_detail_screen.dart` | Series detail: season tabs, episode list, resume detection, per-episode download |
| `player_screen.dart` | Full video player: 50+ features (see PLAYER_SPEC.md) |
| `player_settings_screen.dart` | Persistent player prefs (aspect, subtitles, ambilight, binge guard) |
| `login_screen.dart` | Login with device binding |
| `register_screen.dart` | Register + auto-login |
| `search_screen.dart` | Full-text search (local FTS5 + server fallback) |
| `vault_screen.dart` | Private media vault (PIN/biometric protected) |
| `vault_lock_screen.dart` | Vault authentication gate |
| `vault_settings_screen.dart` | Change vault PIN, toggle biometric, clear vault |
| `profile_screen.dart` | User info, subscription status, device switch, logout |
| `history_screen.dart` | Watch history with position indicators |
| `watchlist_screen.dart` | Saved titles |
| `subscription_screen.dart` | Plans + TID payment submission |
| `local_media_screen.dart` | Device video browser (MX Player style) |
| `local_folder_screen.dart` | Folder navigator for local videos |
| `admin_queue_screen.dart` | Download queue viewer (admin-only) |
| `plan_expired_screen.dart` | Subscription expired gate |
| `quota_full_screen.dart` | Daily quota exceeded gate |
| `tid_status_screen.dart` | Payment TID verification status |

### Core Services
| File | Role |
|------|------|
| `core/db/local_db.dart` | SQLCipher DB: titles, episodes, watch_positions, downloads, stream_cache, sync_meta |
| `core/api/api_client.dart` | Dio singleton: JWT attach, 401 refresh, AppGuard tamper check |
| `core/api/catalog_api.dart` | Catalog sync, episode fetch, stream URL resolution |
| `core/api/history_api.dart` | Watch history push/pull |
| `core/services/jazzdrive_service.dart` | JazzDrive link cache + CDN URL resolver |
| `core/services/sync_service.dart` | 6h delta sync orchestrator |
| `core/services/usage_service.dart` | Daily data quota tracking |
| `core/services/notification_service.dart` | Notification fetch + display |
| `core/services/poster_service.dart` | Background poster download + disk cache |
| `core/services/app_update_service.dart` | Force update / version block checker |
| `core/remote_config.dart` | Fetches apiBaseUrl + jazzDriveDeltaUrl from server on startup |
| `core/security/app_guard.dart` | APK sig + Frida + root detection (⚠️ Kotlin side broken) |
| `core/security/keystore.dart` | Android Keystore: DB key + JWT storage |
| `core/security/device_id.dart` | Stable device fingerprint (hardware IDs) |
| `core/security/request_encoder.dart` | XOR API encoding (disabled: .enabled = false) |
| `core/security/vault_service.dart` | Vault PIN/biometric auth |
| `services/vault_service.dart` | Vault file CRUD (⚠️ same name, different path) |
| `services/cast_service.dart` | Google Cast (Chromecast) |
| `services/local_media_service.dart` | MediaStorePlugin wrapper |
| `services/thumb_service.dart` | Video thumbnail generator |
| `core/debug/debug_logger.dart` | Debug log exporter via share_plus |

### Player Controllers (raddflix_flutter/lib/core/player/)
| Controller | Feature |
|-----------|---------|
| `ab_loop_controller.dart` | A-B loop (mark segment, loop it) |
| `ambilight_controller.dart` | Edge pixel color → glow border |
| `binge_guard_controller.dart` | Take-a-break overlay after N episodes |
| `player_prefs.dart` | Persistent player settings model |
| `player_prefs_provider.dart` | Riverpod provider for player prefs |
| `scene_bookmark_store.dart` | Named timestamps per file, stored in SQLite |
| `smart_intro_store.dart` | Learns intro timestamps from skip behavior |

### State Management (Riverpod)
| Provider | State |
|---------|-------|
| `auth_provider.dart` | Auth state, user info, JWT |
| `catalog_provider.dart` | Full catalog, movies, shows, CatalogStatus |
| `downloads_provider.dart` | Download queue, status per file |
| `watchlist_provider.dart` | Watchlist items |

### Android Native (raddflix_flutter/android/)
| File | Role |
|------|------|
| `MainActivity.kt` | 5 MethodChannels: PiP, Media, Cast, Intent, Security |
| `MediaStorePlugin.kt` | Local video scanner via Android MediaStore |
| `CastOptionsProvider.kt` | Google Cast SDK options provider |
| `AndroidManifest.xml` | Permissions, intent filters, services |

---

## 🐍 FLASK BACKEND — KEY FILES REFERENCE

### Core
| File | Role |
|------|------|
| `app.py` | Flask factory, blueprint registration, startup tasks |
| `db.py` | ALL SQLite DDL (schema v13), all table creation, migration |
| `auth.py` | JWT encode/decode, token validation helpers |
| `config.py` | Flask config class, env var loading |
| `keys.py` | Fernet-encrypted API key vault, key rotation |
| `scheduler.py` | 3 background loops: rescan, downloads, delta regen |
| `jazzdrive.py` | JazzDrive login, OTP, share URL generation, keepalive |
| `mirror.py` | GitHub sync, GSheets sync (BUG-A18: _legacy import) |
| `bulk_link_engine.py` | Link pre-gen every 2h (⚠️ BROKEN: stream_links table missing) |
| `radd_recommend.py` | Recommendation engine (no API endpoint wired yet) |
| `request_encoding.py` | Server-side XOR encoding layer |
| `security_telemetry.py` | Tamper reports, rate limiting (⚠️ memory leak) |
| `analytics.py` | Revenue, signup, engagement analytics |
| `downloader.py` | aria2 download orchestrator |
| `zero_rating.py` | Delta JSON generation + JazzDrive upload |

### Routes (Blueprints in radd-hub/hub/routes/)
| Blueprint | Prefix | Key Endpoints |
|-----------|--------|--------------|
| `auth.py` (bp_auth) | `/api/auth` | register, login, refresh, logout, device-switch |
| `mobile_api.py` (bp_mobile + bp_rec) | `/api` | catalog, config, notifications, watchlist, history, recommend |
| `catalog_api.py` (bp_catalog) | `/api/catalog` | sync, db_update, titles, episodes |
| `stream.py` (bp_stream) | `/stream` | admin stream panel, link resolve |
| `search_api.py` (bp_search) | `/api/search` | title search (LIKE queries — no FTS5) |
| `subscriptions.py` (bp_sub) | `/api/subscription` | plans, TID submit, status |
| `payment_gateway.py` (bp_pay) | `/api/payment-methods` | TID verification, SMS auto-approve |
| `analytics.py` (bp_analytics) | `/analytics` | dashboard, charts |
| `zero_rating.py` (bp_zr) | `/api/zero-rating` | delta status, force regen |

### Database Schema (SQLite WAL, v13)
```sql
titles (id, title, year, media_type, description, rating, genres,
        poster_url, poster_path, share_url, is_free, db_version,
        language, status, is_ongoing,
        ⚠️ + legacy: cast, cast_names, cast_json, overview, omdb_id, imdb_id)

episodes (id, title_id FK, file_id, season, episode, label,
          quality, is_free, share_url)

files (id, title_id FK, file_id, quality, language, size_mb, duration_s,
       share_url, is_active, created_at)

users (id, phone, password_hash, device_id, plan, quota_used_mb,
       quota_reset_at, created_at, is_admin)

subscriptions (id, user_id FK, plan, start_date, end_date, tid)

-- ⚠️ stream_links table MISSING from DDL — bulk_link_engine.py crashes without it
```

---

## 🤖 WHATSAPP BOT

### Two Instances (only one runs in production)
| Instance | Path | Status |
|----------|------|--------|
| Full bot (22 files, plugins, rewards) | `radd-hub/bots/whatsapp/` | NOT in supervisor |
| Simple bot | `radd-hub/hub/bots/whatsapp/` | ✅ Running as `raddflix_wa_bot` |

**Task P4.1:** Deploy full bot to replace simple one.

### Full Bot Features (bots/whatsapp/)
Movie/show search, actor/genre/director/similar search, trailer links, account mgmt, referral codes, quota check, admin commands, rate limiting, plugin hot-reload.

---

## 🔐 SECURITY ARCHITECTURE

### Layers (what works vs broken)
| Layer | Status | Notes |
|-------|--------|-------|
| SQLCipher AES-256 (local DB) | ✅ ACTIVE | Key in Android Keystore |
| JWT HS256 (15min access + 90d refresh) | ✅ ACTIVE | Secret in server DB |
| APK signature check | ❌ BROKEN | Kotlin handler missing (P1.1) |
| Frida detection | ❌ NOT IMPL | Kotlin handler missing (P2.3) |
| Root detection | ❌ NOT IMPL | Kotlin handler missing (P2.3) |
| Password hashing | ⚠️ WEAK | Unsalted SHA-256 (P1.3) |
| XOR API encoding | ⏸️ DISABLED | Both sides ready, Flutter disabled |
| share_url scrambling at rest | ⏸️ NOT WIRED | Function exists, not called |
| CSRF protection | ✅ ACTIVE | On all admin routes |
| Silent degradation (tamper) | ✅ ACTIVE | AppGuard.isTampered → fake empty API |
| Rate limiting (security telemetry) | ⚠️ LEAK | _ip_window dict grows unbounded (P2.2) |

### Security Design Principle
JazzDrive share_urls NEVER expire (owner confirmed). Security must come from APK integrity, not link rotation. A cracked APK distributing those URLs freely would drain the service. This is why APK sig check (P1.1) is the highest priority fix.

---

## 🔧 KNOWN BUGS — FULL TABLE

### Priority 1 — Critical (production-impacting)
| ID | File | Description | Fix Ref |
|----|------|-------------|---------|
| P1.1 | `MainActivity.kt` | SECURITY_CHANNEL unhandled → APK sig check silent (PlatformException caught by AppGuard) | Add setMethodCallHandler for security channel |
| P1.2 | `bulk_link_engine.py` | queries `stream_links` table not in DDL → SQL error every 2h, silently swallowed | Add table to db.py DDL |
| P1.3 | `mobile_api.py` | `_hash_password()` unsalted SHA-256 → rainbow table attack on DB breach | Switch to bcrypt/PBKDF2 with per-user salt |
| P1.4 | `catalog_api.py` | `_watch_base()` hardcodes `http://92.4.95.252` fallback → wrong if IP changes, HTTP not HTTPS | Move to env var only, no hardcoded fallback |

### Priority 2 — Important
| ID | File | Description |
|----|------|-------------|
| P2.1 | `search_api.py` | LIKE queries, no FTS5 → slow at 500+ titles |
| P2.2 | `security_telemetry.py` | `_ip_window` dict never prunes old IPs → memory leak under DoS |
| P2.3 | `MainActivity.kt` | Frida + root detection handlers missing (complement to P1.1) |
| P2.4 | Flutter + server | XOR request encoding disabled (both sides ready, just need enable) |
| P2.5 | `mirror.py` | BUG-A18: `_legacy` import may fail at runtime |
| P2.6 | `keys.py` | Plaintext fallback if `cryptography` not installed |

### Priority 3 — Cleanup
| ID | File | Description |
|----|------|-------------|
| P3.1 | Root `lib/` | Dead stub files with JazzMAX/ZENO branding — delete |
| P3.2 | `bots/whatsapp/` | `bot-state.json`, `users.json`, `pairing-number.txt` committed → add to .gitignore |
| P3.3 | `constants.dart` | `supportWhatsApp = '923001234567'` is placeholder — set real number |
| P3.4 | Login/Register screens | `_extract_error()` + `_friendly_error()` duplicated in both files |
| P3.5 | `db.py` | Legacy columns: `cast`/`cast_names`/`cast_json`, `plot`/`overview`, `omdb_id`/`imdb_id` |
| P3.6 | `bots/whatsapp/bulk_link_engine.py` | Dead product name "JazzBuzz" in docstring |
| P3.7 | Code docs | `constants.dart` `otpDeviceSwitchEnabled` is `true` but old docs say `false` |

### Priority 4 — Features / Incomplete
| ID | Description |
|----|-------------|
| P4.1 | Deploy full WhatsApp bot (`bots/whatsapp/`) to supervisor replacing simple bot |
| P4.2 | Wire `radd_recommend.py` to a real API endpoint (`GET /api/recommend`) |
| P4.3 | Fix Chromecast: add `play-services-cast-framework` to Gradle deps |
| P4.4 | Runtime permission request for `READ_MEDIA_VIDEO` in local_media_screen.dart |
| P4.5 | Complete Telegram bot skeleton |
| P4.6 | domain_doctor.py findings — add admin panel UI surface |
| P4.7 | Enable share_url scrambling at rest (function exists, not called) |
| P4.8 | Enable XOR request encoding (both sides ready) |

### Pre-existing Bugs (from prior phases, may still be open)
| ID | Description |
|----|-------------|
| BUG-A02 | detail_screen.dart doesn't pass title_id to player (series playback) |
| BUG-A07 | OTP device switch server endpoints missing |
| BUG-A18 | mirror.py _legacy import failure |
| BUG-A20 | Poster sync fires multiple times per session |
| BUG-A26 | bp_rec blueprint registration conflict |
| BUG-A32 | mobile_api.py hardcoded dev secret fallback |
| BUG-A33 | Material Design 2 only (useMaterial3 not set) |

---

## 🚀 HOW TO DEPLOY CHANGES

### ⚠️ ORACLE SSH DOES NOT WORK FROM REPLIT
All changes must go through GitHub. Oracle auto-pulls via webhook or `git pull` on server.

### Flutter App Changes (via GitHub API)
```
1. Make change in raddflix_flutter/
2. Commit via GitHub API (see AGENT_CONNECTIONS_GUIDE.md)
3. GitHub Actions CI auto-builds APK
4. CI must stay GREEN — check workflow status before calling task done
```

### Backend Changes (via GitHub API)
```
1. Make change in radd-hub/
2. Commit via GitHub API
3. Oracle server has a post-receive hook → auto git pull + supervisorctl restart raddflix_hub
4. If supervisor doesn't auto-restart: run `supervisorctl restart raddflix_hub` on Oracle
```

### How to Commit (GitHub API Pattern — always use this)
```bash
# Step 1: Get current HEAD + TREE SHA
HEAD_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN"   "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main"   | python3 -c "import json,sys; print(json.load(sys.stdin)['object']['sha'])")
TREE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN"   "https://api.github.com/repos/raddclub/raddflix-app/git/commits/$HEAD_SHA"   | python3 -c "import json,sys; print(json.load(sys.stdin)['tree']['sha'])")

# Step 2: Create blobs for each file
BLOB=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN"   -H "Content-Type: application/json"   "https://api.github.com/repos/raddclub/raddflix-app/git/blobs"   -d "{"encoding":"base64","content":"$(base64 -w0 /path/to/file)"}"   | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# Step 3: Create new tree
NEW_TREE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN"   -H "Content-Type: application/json"   "https://api.github.com/repos/raddclub/raddflix-app/git/trees"   -d "{"base_tree":"$TREE_SHA","tree":[{"path":"path/to/file","mode":"100644","type":"blob","sha":"$BLOB"}]}"   | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# Step 4: Create commit
NEW_COMMIT=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN"   -H "Content-Type: application/json"   "https://api.github.com/repos/raddclub/raddflix-app/git/commits"   -d "{"message":"your message","tree":"$NEW_TREE","parents":["$HEAD_SHA"]}"   | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# Step 5: Update branch ref
curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN"   -H "Content-Type: application/json"   "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main"   -d "{"sha":"$NEW_COMMIT"}"
```

---

## 🔑 SECRETS & ACCESS

| Secret | Where Stored | Used For |
|--------|-------------|----------|
| `GITHUB_TOKEN` | Replit Secrets | All GitHub API calls |
| `SESSION_SECRET` | Oracle `.env` | JWT signing key |
| `VAULT_MASTER_KEY` | Oracle `.env` | Fernet API key encryption |
| `TMDB_KEY` | Oracle DB via keys.py | TMDB metadata |
| `OMDB_KEY` | Oracle DB via keys.py | OMDB metadata |
| `GROQ_API_KEY` | Oracle DB via keys.py | AI metadata enrichment |
| `GEMINI_API_KEY` | Oracle DB via keys.py | AI metadata enrichment |
| `RADD_ADMIN_USER` | Oracle `.env` | Admin panel login |
| `RADD_ADMIN_PASS` | Oracle `.env` | Admin panel login |

**NEVER hardcode secrets in source code. Always read from env or via keys.py.**

---

## 📐 CODE CONVENTIONS

### Flutter (Dart)
- State management: **Riverpod only** (no setState except in Stateful scaffolding)
- HTTP: **Dio via ApiClient.instance** (never raw http package)
- Local storage: **local_db.dart** for persistent data, **SharedPreferences** for flags/prefs only
- Error handling: **never silent catch-all** — log to DebugLogger or rethrow
- Constants: **AppConstants.*** and **ApiPaths.*** — no magic strings
- Routes: **AppRoutes.*** named routes via Navigator.pushNamed — no direct MaterialPageRoute unless player
- Imports: use relative imports (../core/...) not package: imports for internal code
- Theme: use **AppColors.*** and **RaddColors.*** — no hardcoded Color(0x...)

### Flask (Python)
- Blueprint pattern for all routes — never add routes directly to `app`
- DB access: **db.get_db()** connection (never direct sqlite3 connection)
- Error responses: always return JSON `{"error": "message"}` with appropriate HTTP status
- Auth required: use `@require_auth` decorator — never manually decode JWT in routes
- Config: always from `config.py` or env vars via `os.environ.get()` — no hardcoded values
- Logging: `app.logger.info/error` — never print()

### Git Commit Messages
```
type(scope): short description

Types: feat, fix, docs, refactor, security, test, ci
Examples:
  fix(android): wire SECURITY_CHANNEL handler in MainActivity.kt
  fix(backend): add stream_links table to DDL
  security(auth): migrate password hashing to bcrypt
  docs(agent-hub): update MASTER_PLAN task status
```

---

## 📜 PROJECT HISTORY SUMMARY

| Phase | What Was Done |
|-------|--------------|
| 1–5 | Flutter skeleton: auth, catalog, player, local DB (SQLCipher), JazzDrive integration |
| 6–10 | Download system, vault, security (AppGuard, device binding), SIMOSA integration |
| 11–15 | Admin panel, subscription system, TID payments, notification system |
| 16–20 | WhatsApp bot, analytics, zero-rating delta, metadata enrichment pipeline |
| 21–25 | XOR encoding, security telemetry, recommendation engine, advanced player features |
| 26–27 | Keystore migration (debug→release signing), CI green, APK fingerprint update |
| 28 | Full deep audit: 359+ files read, 17 new bugs found, all docs overhauled |
| 29 | P4.2 verified; FTS5 regression fixed; dropped-col sweep across library/api/db; all 3 sessions fully verified |

---

## 🔄 HOW TO USE THIS FILE

**When you start a new session:**
1. Read this file top-to-bottom
2. Read `AGENT_RULES.md` (mandatory)
3. Check `MASTER_PLAN.md` for the next task
4. Read the specific `CODE_MAP.md` entry for files you'll touch
5. Make your change
6. Verify: CI green + no regressions
7. Update `MASTER_PLAN.md` task status
8. Append to `history/TASK_LOG.md`
9. Ask user for approval before starting next task

**If something is unclear:** Check `PRODUCT_CONTEXT.md`, `SECURITY_ARCHITECTURE.md`, or `PLAYER_SPEC.md`.

---

*End of REINCARNATION.md — v3.1 — 2026-06-01*
*Next update: after P3.3 (real WhatsApp number) and P4.1 (Oracle bot restart) are resolved*
