# RaddFlix — Reincarnation Prompt (2026-05-30 — Full Audit Edition)

> **Give this entire document to the next AI session. It is self-contained.**
> Read top to bottom before touching any code.

---

## Who You Are

You are the AI agent continuing development of **RaddFlix** — a Pakistani streaming platform where Jazz SIM users watch movies and dramas for **free** (zero data cost) via JazzDrive zero-rating.

- GitHub repo: `raddclub/raddflix-app`
- Oracle server: `ubuntu@92.4.95.252` (SSH **works** from Replit — see AGENT_NOTES.md for key reformat. GitHub Tree API for commits due to Replit git restrictions.)
- Flutter app package: `com.raddflix.app`
- Admin panel: Flask on port 5000 at `http://92.4.95.252`

Previous sessions built Phases 1–12. A full deep audit was completed on 2026-05-30. ⚠️ CI is FAILING as of `2a73e90` (Build release APK step fails). Fix CI before Flutter changes. Latest server-only changes are deployed and running.

---

## STEP 0 — Read These Files FIRST (in order)

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SKILLS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/MASTER_TASKLIST.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/CODE_MAP.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md"
```

**CODE_MAP.md is new as of 2026-05-30** — it maps every file in the repo to its purpose, key functions, and known issues. Use it to find anything instantly without reading source files.

---

## CRITICAL RULES — Violate any of these and you break production

1. **NEVER add a server-side stream URL resolver.** Stream URLs are generated LOCALLY in the app from SQLite. The server never serves or proxies streams. See STREAMING_ARCHITECTURE.md.
2. **NEVER touch `/opt/jazzmax/radd-hub/hub/_legacy/`** — scanner.py imports from there. Deleting it breaks the entire content pipeline.
3. **NEVER force-push** — always `"force": false` in GitHub API PATCH calls.
4. **NEVER write "JazzMAX" or "Zeno"** — the app is **RaddFlix** (capital R, capital F). Dead names.
5. **NEVER put JazzDrive share folder URLs in the delta JSON** — delta is metadata only (id, title, year, description, poster_url, genres, is_free, media_type, language, status, is_ongoing, rating, season_count, episode_count, db_version). NO file_id, NO share_url, NO folder_share_url.
6. **NEVER upgrade `sqflite_sqlcipher` above `3.1.0+1`** — stays pinned until CI upgrades to Flutter 3.27+. See Phase 4 in MASTER_TASKLIST.
7. **NEVER rename `oldV` in `_migrate(Database db, int oldV, int newV)`** — using `oldVersion` = compile error. Broke CI twice.
8. **ALWAYS update MASTER_TASKLIST.md** when completing or discovering tasks.
9. **ALWAYS append to TASK_LOG.md** at end of every session.
10. **ALWAYS read CODE_MAP.md before touching a file** — it tells you what's broken/stub/unwired in each file.

---

## GitHub API Commit Pattern (the ONLY way to push — no git commands)

```bash
# 1. Get HEAD SHA
HEAD_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main" \
  | jq -r '.object.sha')

# 2. Get tree SHA
TREE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/commits/$HEAD_SHA" \
  | jq -r '.tree.sha')

# 3. Create blob for each file (base64 for binary/large files)
BLOB=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/blobs" \
  -d "{\"encoding\":\"base64\",\"content\":\"$(base64 -w0 /tmp/yourfile)\"}" \
  | jq -r '.sha')

# 4. Create tree (multi-file: add more objects to array)
NEW_TREE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/trees" \
  -d "{\"base_tree\":\"$TREE_SHA\",\"tree\":[{\"path\":\"path/to/file\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB\"}]}" \
  | jq -r '.sha')

# 5. Commit
NEW_COMMIT=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/commits" \
  -d "{\"message\":\"your message\",\"tree\":\"$NEW_TREE\",\"parents\":[\"$HEAD_SHA\"]}" \
  | jq -r '.sha')

# 6. Update ref (NEVER force)
curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/git/refs/heads/main" \
  -d "{\"sha\":\"$NEW_COMMIT\",\"force\":false}"
```

---

## What's Built (Phase Summary)

| Phase | What | Status |
|-------|------|--------|
| 1 | MX Player UI (ambilight, track badges, A-B loop, bookmarks, memory) | ✅ |
| 2 | Metadata 6-tier enrichment (TMDB→OMDB→AI→IMDbAPI→YouTube→Google KG) | ✅ |
| 3 | Poster image system (local cache, background sync, JazzDrive zero-rated saving) | ✅ |
| 4 | Security (SQLCipher AES-256, Android Keystore, flutter_secure_storage) | ✅ |
| 5 | Device binding (1 account = 1 device, 409 conflict, WhatsApp switch) | ✅ |
| 6 | Data usage tracking (byte estimate, quota cache, QuotaFullScreen) | ✅ |
| 7 | Delta JSON system (zero-rating catalog updates, 24h auto-generation) | ✅ |
| 8 | Subscription plans & TID payment flow | ✅ |
| 9 | SIMOSA integration (daily card, streak tracker, Jazz partner badge) | ✅ |
| 10 | WhatsApp Bot (managed via admin panel) | ✅ |
| 11 | Full integration audit (app check, PackageInfo version, notification bell) | ✅ |
| 12 | FTS5 full-text search (catalog_fts virtual table, prefix search, DB v13) | ✅ |

---

## KNOWN BROKEN THINGS (Full Audit — 2026-05-30)

These are confirmed bugs found by reading actual code logic. Fix these in Phase 13.

### 🔴 Critical (breaks functionality for users)

| ID | Where | Bug | Impact |
|----|-------|-----|--------|
| BUG-A01 | `radd-hub/hub/db.py` (titles table DDL) | `year` column stored as TEXT. Flutter `int?` cast returns null | Year never shown on any content card |
| BUG-A02 | `radd-hub/hub/library.py` (delta generation) | `media_type` returns `"tv"` or `"series"` depending on source. Flutter filter expects `"show"` | TV shows invisible or miscategorized in the app |
| BUG-A03 | `radd-hub/hub/routes/mobile_api.py` (auth endpoints) | `is_active` returned as Python `bool` (true/false). Flutter `UserSubscription` expects `int` (1/0) | Subscription status unreliable |
| BUG-A04 | `raddflix_flutter/lib/core/db/local_db.dart` (`mergeDeltaTitle`) | `ON CONFLICT(id) DO UPDATE SET...` is SQLite 3.24+ syntax. Android 8 ships SQLite 3.19–3.22 | Crashes on Android 8 and below during catalog sync |
| BUG-A05 | `raddflix_flutter/lib/screens/vault_lock_screen.dart` | `_expectedPinLength` = 6 but `_submit` allows length 4 in setup mode | User creates 4-digit PIN, 6-digit lock screen never accepts it |
| BUG-A06 | `radd-hub/hub/app.py` line ~166 | `session_err` variable used in `download_proxy()` but never defined | Runtime `NameError` crash on any download proxy call |
| BUG-A07 | `radd-hub/hub/routes/mobile_api.py` (`/api/app/check`) | Returns `package_id: "pk.jazzmax.app"` (old brand). Correct is `"com.raddflix.app"` | Force-update check compares wrong package ID — never triggers correctly |
| BUG-A08 | `raddflix_flutter/lib/core/api/watch_history` | Server has full `/api/history` and `/api/history/<file_id>` API. **No `HistoryApi` class exists in Flutter.** History is local-only, never synced to server | Watch history lost if user reinstalls app |

### 🟠 Data / Logic Errors

| ID | Where | Bug | Impact |
|----|-------|-----|--------|
| BUG-A09 | `radd-hub/hub/routes/mobile_api.py` (`/api/notifications/read`) | Accepts `{"ids": [...]}` but ignores array — marks ALL notifications read for user | Can't selectively read one notification |
| BUG-A10 | `radd-hub/hub/routes/mobile_api.py` (`POST /api/auth/device`) | Crashes HTTP 500 when called with a guest token | Guest users crash device binding |
| BUG-A11 | Server + Flutter | Server history API stores positions in **seconds**. Flutter `local_db.dart` stores in **milliseconds**. No conversion | History sync would be 1000x wrong when HistoryApi is added |
| BUG-A12 | `raddflix_flutter/lib/screens/subscription_screen.dart` | Fallback payment methods contain placeholder `03xxxxxxxxx` account numbers | Users see fake account numbers if `payment_methods` DB table is empty |
| BUG-A13 | `raddflix_flutter/lib/screens/register_screen.dart` | Phone validation only checks `length < 11`, no Pakistani prefix check | Accepts invalid numbers |
| BUG-A14 | `raddflix_flutter/lib/screens/profile_screen.dart` (`_loadExtras`) | Catches ALL exceptions silently — API failures, parse errors all swallowed | User sees stale data with no error indication |
| BUG-A15 | `raddflix_flutter/lib/providers/catalog_provider.dart` | `_staticTrending` is a hardcoded list in `search_screen.dart` — not from server | Trending suggestions are fake/static |
| BUG-A16 | `raddflix_flutter/lib/screens/search_screen.dart` (`_extractGenres`) | Genre splitting by comma doesn't trim whitespace in initial map key — "Action" and " Action" = two chips | Duplicate genre filter chips |
| BUG-A17 | `radd-hub/hub/jazzdrive.py` lines 27–45 | `jazzdrive_login`, `list_folders`, `create_folder`, `delete_file` accept `*args/**kwargs` and do nothing | Any JazzDrive operation hitting these silently fails |
| BUG-A18 | `radd-hub/hub/sync.py` | GSheets sync uses a `_legacy` import that may be missing | Sync to Google Sheets throws `ImportError` |

### 🟡 Missing Wiring / Unwired Features

| ID | Where | What's Missing |
|----|-------|---------------|
| BUG-A19 | `raddflix_flutter/lib/core/api/` | No `HistoryApi` class exists. Server has full history sync API. Client never calls it. |
| BUG-A20 | `raddflix_flutter/lib/core/services/poster_service.dart` | `syncPosters()` / `runBackgroundSync()` exist — not confirmed started in `main.dart` or `splash_screen.dart` |
| BUG-A21 | `raddflix_flutter/lib/core/player/player_prefs.dart` | `PlayerPrefs.reset()` defined — no UI button anywhere to call it |
| BUG-A22 | `raddflix_flutter/lib/core/db/local_db.dart` | `clearPosition(fileId)` defined — never called from history or settings UI |
| BUG-A23 | `raddflix_flutter/lib/core/player/scene_bookmark_store.dart` | `deleteAll()` defined — never called anywhere |
| BUG-A24 | `raddflix_flutter/lib/core/player/binge_guard_controller.dart` | `BingeGuardController` exists — no confirmed point where it interrupts playback |
| BUG-A25 | `raddflix_flutter/lib/core/player/smart_intro_store.dart` | `SmartIntroStore` exists — needs confirmation it's triggered in `player_screen.dart` |
| BUG-A26 | `radd-hub/hub/radd_recommend.py` | Full recommendation engine exists — no API endpoint exposes it to Flutter app |
| BUG-A27 | `raddflix_flutter/lib/core/api/auth_api.dart` | `AuthApi.bindDevice()` is a standalone function — device binding is already inside `login()`. This is dead code |
| BUG-A28 | Server | Download quota: server never returns `downloads_used_today`. Download quota tracked but never enforced |
| BUG-A29 | Server | Mid-stream usage cutoff doesn't exist. Quota only checked at stream start |

### 🔵 Infrastructure / Config Issues

| ID | Where | Issue |
|----|-------|-------|
| BUG-A30 | `raddflix_flutter/lib/core/remote_config.dart` | Points to hardcoded IP `92.4.95.252`. If IP changes, every installed app breaks permanently |
| BUG-A31 | Oracle server | No SSL — all API traffic unencrypted. `http://92.4.95.252` |
| BUG-A32 | `radd-hub/hub/config.py` | `FLASK_SECRET_KEY` auto-generated on first run. Server restart = new key = all JWTs invalidated = all users logged out |
| BUG-A33 | App + Server | UI uses Material Design 2. No Material 3 (`useMaterial3: true` not set). No dynamic color. No light theme. |
| BUG-A34 | `_watch_prototype/` directory | ✅ RESOLVED 2026-05-30 — catalog/search/poster migrated to radd-hub routes. `raddflix_watch` supervisor service decommissioned. |

---

## Full Review Checklist (Run Before Every Session)

### Step 0 — Orientation
- [ ] Read REINCARNATION.md (this file)
- [ ] Read MASTER_TASKLIST.md for current status
- [ ] Read TASK_LOG.md bottom entry for last session
- [ ] Read CODE_MAP.md for any file you're about to touch

### Step 1 — Verify CI Status
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" \
  | jq -r '.workflow_runs[] | "\(.name): \(.conclusion) (\(.head_sha[0:7]))"'
```

### Step 2 — Check Current DB Version
- File: `raddflix_flutter/lib/core/constants.dart`
- Look for: `catalogDbVersion`
- Current: **13** (FTS5)
- When adding new tables: increment to 14, add `if (oldV < 14)` block in `_migrate`
- **NEVER rename `oldV` parameter**

### Step 3 — Verify sqflite version
- File: `raddflix_flutter/pubspec.yaml`
- Must be: `sqflite_sqlcipher: 3.1.0+1` (no caret, no upgrade)

### Step 4 — Check Known Bugs Before Coding
Read the BUG-A01 through BUG-A34 list above. If your task touches a buggy file, fix the bug as part of your work.

### Step 5 — After Every Commit
- [ ] Verify CI green (both `Build RaddFlix APK` and `RaddFlix CI`)
- [ ] Update MASTER_TASKLIST.md
- [ ] Append to TASK_LOG.md

---

## Key Technical Facts

### DB Versions
| Version | Tables Added |
|---------|-------------|
| 1–11 | Core (titles, episodes, watch_positions, downloads, usage_log, quota_cache, simosa_streak) |
| 12 | show_ep_seen (new-episode badge), stream_cache (6h JazzDrive link TTL) |
| 13 | catalog_fts (FTS5 virtual table for search) |
| **Next: 14** | Add tables for: HistorySync, anything new |

### sqflite version lock
`sqflite_sqlcipher: 3.1.0+1` — pinned. Do not upgrade.

### `_migrate` parameter names
`_migrate(Database db, int oldV, int newV)` — always `oldV`, never `oldVersion`.

### media_type normalization (BUG-A02)
Server must return `"show"` for TV series. Flutter filters on `item.mediaType == "show"`. Currently returns `"tv"` or `"series"` which makes all TV content invisible.

### Continue Watching TV shows
`CatalogItem.fileId` is null for shows. Watch positions use episode file_ids. Must iterate `show.episodes` list to match. Fixed in catalog_provider.dart.

### FTS5 search
- Virtual table `catalog_fts` linked to `titles` via `content='titles'`
- Rebuild after every bulk insert: `LocalDb.rebuildFtsIndex()`
- Query: each word → `"word*"` prefix term, AND'd
- Falls back to LIKE if FTS fails

### JazzDrive / Streaming
- Stream links are generated LOCALLY in the app from SQLite share_url data
- Server NEVER proxies or serves streams
- `jazzdrive_service.dart` resolves direct CDN links client-side
- Links cached in `stream_cache` table (6h TTL, DB v12)

### OTP Device Switch
- `AppConstants.otpDeviceSwitchEnabled = false` — hidden
- UI exists in `_DeviceConflictPanel` (StatefulWidget with OTP step)
- Server endpoints **EXIST**: `POST /api/auth/device-switch/request` and `POST /api/auth/device-switch/verify` ✅ (implemented Phase 17)
- `AppConstants.otpDeviceSwitchEnabled = true` — enabled (Phase 17)
- WhatsApp delivery: wa-bot must be running on port 3000 (currently down)

### History Sync Gap
- Server: full `/api/history` (GET list) and `/api/history/<file_id>` (POST position) API implemented
- Flutter: **no HistoryApi class**. Local watch positions never sent to server.
- Server uses seconds, Flutter uses milliseconds — need unit conversion when implementing

---

## Architecture Quick Reference

```
raddflix_flutter/           ← Flutter Android app
  lib/
    app.dart                ← Routes, ForceUpdateGuard, MaterialApp
    main.dart               ← Entry point, ProviderScope
    core/
      api/                  ← Dio API clients (auth, catalog, subscription)
      db/local_db.dart      ← SQLite (encrypted), all queries
      db/sync_service.dart  ← Catalog sync orchestration
      constants.dart        ← ALL constants, routes, API paths
      remote_config.dart    ← Fetches base URL from server
      theme/                ← Dark theme, RaddColors
    models/                 ← CatalogItem, User, Subscription, LocalVideo
    providers/              ← Riverpod state (auth, catalog, downloads, subscription)
    screens/                ← All UI screens
    widgets/                ← Reusable UI + 12 player overlay widgets
    services/               ← Cast, local media, thumb, vault

radd-hub/hub/               ← Flask backend (admin panel + mobile API) — ALL on port 5000
  app.py                    ← Flask factory, blueprint registration, background threads
  db.py                     ← SQLite schema (25+ tables), all server-side queries
  routes/
    mobile_api.py           ← ALL mobile API endpoints (auth/sub/usage/notif/history/app/recommend)
    catalog_api.py          ← Flutter catalog sync (version/sync/posters/db_update) — SQLite live
    search_api.py           ← Flutter app search (no auth required)
    poster_proxy.py         ← TMDB/OMDB/IMDbAPI poster key rotation + 30d cache
    library.py              ← Admin catalog mgmt + delta JSON generation
    api.py                  ← JazzDrive OTP, scraper search (/api/scraper/search), metadata fix
    [admin routes]          ← analytics, app_users_panel, bots, broadcast, settings, etc.
  templates/                ← Jinja2 HTML admin panel (base.html + page templates)
  jazzdrive.py              ← JazzDrive API wrapper (partially stubbed)
  scheduler.py              ← APScheduler jobs (rescan, delta gen, scheduled downloads)

agent-hub/                  ← Agent documentation (NOT deployed to server)
  REINCARNATION.md          ← THIS FILE — full context for next agent
  SKILLS.md                 ← Rules every agent must follow
  MASTER_TASKLIST.md        ← All tasks with status
  CODE_MAP.md               ← Every file mapped to purpose/functions/bugs
  history/TASK_LOG.md       ← Session-by-session history
  history/API_FULL_AUDIT_2026_05_27.md ← Previous API audit
  history/UI_AUDIT_2026_05_28.md       ← Previous UI audit
```

---

## Recommended Next Tasks (Phase 13 — Audit Fixes)

Priority order based on user impact:

1. **BUG-A02** — Normalize `media_type` to `"show"` in `library.py` delta output → TV shows become visible
2. **BUG-A01** — Change `year` column to INTEGER in DB DDL → years appear on all cards
3. **BUG-A03** — Fix `is_active` serialization in `/api/auth/me` → subscription status reliable
4. **BUG-A19** — Create `HistoryApi` class in Flutter + wire to server → watch history survives reinstalls
5. **BUG-A05** — Fix vault PIN length mismatch (4 vs 6) in `vault_lock_screen.dart`
6. **BUG-A06** — Fix `session_err` NameError in `app.py` download_proxy
7. **BUG-A07** — Fix package ID in `/api/app/check` from `pk.jazzmax.app` → `com.raddflix.app`
8. **BUG-A11** — Add seconds↔ms conversion when HistoryApi is implemented
9. **BUG-A12** — Fix placeholder payment numbers in `subscription_screen.dart`
10. **BUG-A16** — Fix genre chip deduplication in `search_screen.dart`

---

## Addendum — Oracle Server State (2026-05-30)

### Catalog Migration Done
All API routes now served from **single radd-hub process on port 5000**.
`_watch_prototype` catalog service (`raddflix_watch`) decommissioned.

| Before | After |
|--------|-------|
| /api/catalog/ → port 6000 (_watch_prototype) | /api/catalog/ → port 5000 (radd-hub catalog_api.py) |
| /api/search → port 6000 | /api/search → port 5000 (radd-hub search_api.py) |
| /api/poster/ → port 6000 | /api/poster/ → port 5000 (radd-hub poster_proxy.py) |
| /api/auth/ → port 5000 | /api/auth/ → port 5000 (unchanged) |

### JazzMAX → RaddFlix Rename (Oracle server)
- nginx: `sites-available/jazzmax` → `raddflix`, `raddflix-ssl.conf`, `raddflix_security.conf`
- supervisor: `jazzmax_radd` → `raddflix_radd`; `jazzmax_watch` → removed
- systemd: `jazzmax_watch.service` → `raddflix_watch.service` (then removed)
- `/health` endpoint → returns `"RaddFlix Oracle OK"`

### Supervisor Status
```bash
sudo supervisorctl status
# raddflix_radd   RUNNING   # only service — all API on port 5000
```

### Git State
- Server at commit `2a73e90` (latest main)
- radd-hub Python changes at commit `46983977`
- All conflicts resolved

### SSH Key Pattern
See AGENT_NOTES.md — key is OPENSSH format with spaces instead of newlines.
Use `re.match(r'(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)', raw)` to reformat.


---

## Addendum — Verified Live State (2026-05-31 Full Audit)

### Server (Oracle 92.4.95.252) — Verified
| Item | Value |
|------|-------|
| Git HEAD | `2a73e90` (feat(settings): Getting Started card + setup-status API) |
| Supervisor | `raddflix_radd` RUNNING pid 488081 |
| Disk | 30 GB used / 193 GB total |
| Staging | EMPTY |
| Media folder | Off_Campus_S01 only |
| wa-bot | NOT running (port 3000 dead — OTP stored but not delivered) |

### Database — Verified
| Table | Count | Notes |
|-------|-------|-------|
| titles | **24** (16 movies, 8 shows) | All is_published=1 |
| files | 44 | |
| plans | 3 | Basic Rs.149/30GB, Standard Rs.249/50GB, Premium Rs.399/100GB |
| keys | 8 | 2 TMDB ✅, 2 OMDB ✅, 2 Gemini ✅, 2 Groq ✅ (all active, last_status=ok) |
| accounts | 1 | 03029688227, role=flix, is_active=1 |

Note: `plans` table columns are `monthly_limit_gb` / `daily_limit_gb` — NOT `data_gb`.

### CI Status — WARNING
Both `Build RaddFlix APK` and `RaddFlix CI` are **FAILING** at HEAD `2a73e90`.
Failure step: "Build release APK". Server-side changes still work fine.
**Fix CI before any new Flutter changes.**

### All 18 API Endpoints — Verified ✅
| Endpoint | Status |
|----------|--------|
| GET /health | 200 "RaddFlix Oracle OK" |
| GET /healthz | 200 {"ok":true,"version":"3.0.0"} |
| GET /api/ping | 200 |
| GET /api/catalog/version | 200 {"count":24} |
| GET /api/catalog/sync | 200 (24 titles, media_type normalized, poster_jd_url correct) |
| GET /api/catalog/delta | 200 |
| GET /api/search?q=test | 200 |
| POST /api/app/check | 200 {"ok":true,"blocked":false} |
| GET /api/payment-methods | 200 |
| GET /api/auth/me | 401 (auth required — correct) |
| GET /api/subscription/status | 401 |
| GET /api/usage/quota | 401 |
| GET /api/notifications/ | 401 |
| GET /api/history | 401 |
| GET /api/recommend | 401 |
| GET /api/subscription/plans | 200 (3 plans) |
| POST /api/ping | 405 (method guard working) |
| POST /api/auth/device-switch/request | 200 |
| POST /api/auth/device-switch/verify | 400 (bad OTP — correct) |

### Confirmed Bug Fixes (verified against live server)
| Bug | Fix Verified |
|-----|-------------|
| BUG-A01 year TEXT→INTEGER | ✅ years are integers in DB and API response |
| BUG-A02 media_type normalization | ✅ DB and sync show "movie"/"show" only |
| BUG-A32 Flask secret persisted | ✅ SESSION_SECRET in supervisor env + FLASK_SECRET_KEY in .env |
| BUG-B01 poster_proxy path | ✅ RADD_HUB_DATA_DIR in supervisor env |
| BUG-B02 405 handler | ✅ POST /api/ping → 405 |
| BUG-016 plan prices | ✅ Basic Rs.149, Standard Rs.249, Premium Rs.399 |
| BUG-017 /api/catalog/delta | ✅ returns 200 |
| BUG-018 poster_jd_url route | ✅ points to /api/catalog/poster/<id> |

### Phases Not in REINCARNATION.md (completed after last update)
- **Phase 15** — Server bug sweep (poster_proxy path, 405 handler, search media_type filter)
- **Phase 16** — Deep Flutter-backend route audit + 3 bug fixes
- **Phase 17** — WhatsApp OTP device switch + API contract audit + download pipeline
- **Phase 18** — Full system verification (delta bug, plans seeded, 15 titles discovered via scan)
- **Phase 19** — Flutter video player fixes, external player, system "Open With", vault thumbnails
- **Phase 20** — 2026 UI Polish (Home, Downloads, Profile screens)
- **Phase 21** — 2026 UI Polish (Search, Local Media, Vault) + full audit
- **Phase 22** — DB Studio smart bulk enrichment (IMDbAPI-first 6-source pipeline, SSE progress)
- **Phase 23** — Settings: Getting Started card + setup-status API
