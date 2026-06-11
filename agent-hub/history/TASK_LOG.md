# TASK_LOG.md
> Append-only session log. Most recent session at the bottom.

---

## Session 2026-06-04 — All Critical Bugs Fixed (imported from earlier)

See BUG_TRACKER.md for the complete bug table.

---

## Session 2026-06-05 — SAPI Proxy Pool: God-Level Upgrade + Upload Proxy-Chain Retry

### What was done

**proxy_pool.py — Full God-Level Rewrite:**
- Expanded seed list from 65 → 200+ proxies across 6 Pakistani ASNs
- WeightedScore rotation: score = (reliability × 80) + (speed × 20)
- CircuitBreaker class: if >80% proxies dead → auto-fallback to direct (never breaks)
- Fast recovery thread: re-tests disabled proxies every 5 min
- get_proxy_chain(n): returns ordered retry list for upload loops
- 8-source auto-discovery (was 5): geonode×3, proxyscrape×2, openproxy.space, pubproxy.com, proxy-list.download
- bulk_import(), test_proxy_by_id(), reset_dead(), export_list(), get_stats()
- _seed_or_merge(): always merges new built-in seeds into existing DB on startup (INSERT OR IGNORE)

**uploader.py — Proxy-Chain Retry:**
- Added `forced_proxy` param to `_upload_file()` — caller can inject a specific proxy per attempt
- In `_upload_file()`: connection-level failures immediately call `pool.mark_fail(proxy_url)` — dead proxy demoted instantly
- Added HTTP 407 handling (proxy auth/unreachable) — marks proxy bad and raises clear error
- Retry loop in `upload_to_jazzdrive()`: pre-fetches `get_proxy_chain(n=max_retries+2)` before the loop
- Each retry attempt uses a DIFFERENT proxy from the chain — if attempt 1 fails, attempt 2 uses next best proxy
- Log shows which proxy each attempt used, and success message on retry win

**routes/settings.py — 5 New API Endpoints:**
- GET  /settings/api/pool/stats
- POST /settings/api/pool/bulk-import
- POST /settings/api/pool/test/<id>
- POST /settings/api/pool/reset-dead
- GET  /settings/api/pool/export

**templates/settings.html — God-Level UI Wired In:**
- Replaced old 100-line inline proxy section with `{% include "_proxy_pool_panel.html" %}`
- New panel: stat cards, filter bar, sortable columns, score visualization, per-proxy test, bulk import, export, reset-dead, 10s auto-refresh

**templates/_proxy_pool_panel.html — God-Level Panel (new file):**
- Full god-level proxy management UI

**Docs + Coordination files updated:**
- AGENT_HANDOFF.md: added full proxy pool architecture section, updated Current State to 2026-06-05
- .agents/tasks/BUG_TRACKER.md: added Session 2026-06-05 entry (6 improvements, log analysis)
- radd-hub/agent-hub/AGENT_STATUS.md: created (current health dashboard, Oracle quick reference, open items)
- radd-hub/agent-hub/history/TASK_LOG.md: this file

### Verification results (2026-06-05 19:02 UTC)

| Test | Result |
|------|--------|
| Python syntax: proxy_pool.py | ✅ PASS |
| Python syntax: uploader.py | ✅ PASS |
| Python syntax: settings.py | ✅ PASS |
| App health: /healthz | ✅ {"ok":true,"version":"3.0.0"} |
| App startup logs | ✅ Clean — no errors |
| pool/list endpoint | ✅ Returns proxy list |
| pool/stats endpoint | ✅ {"alive":4,"circuit_open":false,...} |
| pool/export endpoint | ✅ Returns 65+ URL list |
| pool/reset-dead endpoint | ✅ {"ok":true,"reset":61} |
| pool/bulk-import endpoint | ✅ {"added":4,"duplicates":1,"ok":true} |
| pool/test/<id> endpoint | ✅ {"alive":true,"ping_ms":6259,"sapi_status":401} |
| pool/healthcheck trigger | ✅ {"message":"Health check started in background"} |
| pool/discover trigger | ✅ {"message":"Discovery started in background"} |
| uploader.py forced_proxy param | ✅ Line 639 confirmed on Oracle |
| uploader.py proxy_chain loop | ✅ Lines 1324-1348 confirmed on Oracle |
| uploader.py mark_fail on 407 | ✅ Lines 715, 727, 730 confirmed on Oracle |
| settings.html include | ✅ Line 515: {% include "_proxy_pool_panel.html" %} |

### Log observations (last 30 min)
- App clean — no errors, no import failures
- `ProxyPool: HC done — 2/69 alive` — expected (no Jazz SIM on Oracle; proxies alive = Jazz SIM required)
- `Session refresh failed for 03286829827` — stale OAuth token for that account, NOT a code bug; falls back to web auth path automatically. Needs OTP re-login on that account.

### Files changed (commits 3b9dbdc, 08a5673, 2273a0d, + seed-merge fix)
- radd-hub/hub/proxy_pool.py
- radd-hub/hub/uploader.py
- radd-hub/hub/routes/settings.py
- radd-hub/hub/templates/settings.html
- radd-hub/hub/templates/_proxy_pool_panel.html
- AGENT_HANDOFF.md
- .agents/tasks/BUG_TRACKER.md
- radd-hub/agent-hub/AGENT_STATUS.md
- radd-hub/agent-hub/history/TASK_LOG.md

### Open items
- DATA-01: All Of Us Are Dead — E03/E04/E05/E09 not in Oracle DB (need JazzDrive upload + sync)
- Account 03286829827: OAuth refresh_token expired (invalid_grant) — needs manual OTP re-login via Settings → JazzDrive Scan

---

## Session 2026-06-06 — Episode Playback Pipeline: All Bugs Fixed + Live-Tested

### Summary

Fixed all 5 bugs blocking episode playback and confirmed via live test that every episode
(including one with JazzDrive auto-renamed filename) returns a valid direct stream link.

### Bugs Fixed

**1. metadata.py — IMDb title always wins**
Before: title slug was overwritten by dirty filename after IMDb fetch.
Fix:    IMDb title locked in before slug generation, never overwritten.

**2. uploader.py — season/episode not saved on both paths**
Before: upload_pending path did not write season/episode; left NULL.
Fix:    Both the new-upload path AND upload_pending path now write season/episode.

**3. uploader.py — upload_pending did not propagate share_url**
Before: siblings in same folder were missing share_url after upload_pending.
Fix:    share_url propagated to all sibling files within same folder.

**4. zero_rating.py — bad episode filter**
Before: query had "WHERE season IS NOT NULL" — hid TV episodes.
Fix:    Removed that filter; TV episodes now visible in zero-rating flow.

**5. DB backfill**
- season/episode backfilled for 4 TV files
- Spider Noir S01E02 share_url propagated
- Vincenzo title slug corrected

### New Feature: remote_id as Pass 0

generate_direct_link(share_url, target_filename="", remote_id=0) in hub/jazzdrive.py
Pass 0: if remote_id > 0, iterate folder file list, match file.id == remote_id.
Returns direct link with zero filename logic — completely filename-independent.

_do_play() in hub/routes/catalog_api.py now SELECTs f.remote_id and passes it to generate_direct_link.

### Key Discovery: JazzDrive share key format

Full key:  hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA  -> 200 OK
Short key: hoIyg7SgSFiDPHltBZOl8                              -> 400

The suffix (zc1MjIwNTczNTg3NzFfMjYyMTAwMA) is IDENTICAL across all share URLs.
It encodes the JazzDrive account/tenant context. Never truncate share keys.

No proxies needed for JazzDrive share-link login from Oracle — direct connection works.

### Live Test Results

Test script: /tmp/test_direct_link2.py on Oracle server

| Episode                             | Match    | Matched JD filename        | HTTP   |
|-------------------------------------|----------|----------------------------|--------|
| Spider-Noir S01E02 (rid=242518530)  | remote_id| Spider Noir S01E02.mp4     | 200 OK |
| Spider-Noir S01E01 (rid=242518443)  | remote_id| Spider Noir S01E01.mp4     | 200 OK |
| Vincenzo S01E02 (rid=242527574)     | remote_id| Vncenz0 S01E02 (1).mp4     | 200 OK |
| Vincenzo S01E01 (rid=242518574)     | remote_id| Vncenz0 S01E01.mp4         | 200 OK |
| Spider-Noir S01E02 (no remote_id)   | filename | Spider Noir S01E02.mp4     | 200 OK |

Vincenzo S01E02 was auto-renamed by JazzDrive — remote_id found it; filename matching would have failed.

### Files Changed

- hub/metadata.py
- hub/uploader.py
- hub/routes/zero_rating.py
- hub/routes/catalog_api.py
- hub/jazzdrive.py
- data/radd_hub.db (backfill, share_url propagation, slug fix)

### Open Items Going Into Next Session

- NEXT-01: Regenerate + push delta.json to JazzDrive (Flutter catalog sync)
- DATA-01: All Of Us Are Dead missing episodes need upload
- OAUTH-01: Account 03286829827 needs manual OTP re-login


---

## Session: 2026-06-06 — db/reset catalog version bug fix

### Problem
Admin panel Reset Tables button appeared to do nothing. User wiped titles/files
from Oracle but Flutter app still showed old catalog data.

### Root Cause
db_reset() emptied the titles table but did NOT update catalog_forced_version
in the settings table. Since _catalog_version() returns MAX(titles.updated_at,
catalog_forced_version), the version stayed at the old timestamp. Flutter app
saw no catalog version change and kept showing its stale local cache.

### Fix Applied
hub/routes/admin.py — db_reset() now also:
1. Clears turbo_cache, recommendation_cache, media_index cache tables
2. Calls db.set_setting("catalog_forced_version", str(int(time.time()))) after
   clearing — forces every Flutter device to re-sync on next launch
3. Returns cleared/skipped table lists instead of a generic message

### DB State After This Session
Agent SSH test accidentally executed both db/reset AND db/full-delete.
DB is now wiped: 0 accounts, 0 titles, 0 files (392 KB empty schema).
User must re-add Jazz SIM account 03286829827 via admin panel, do OTP login,
set account to scan mode, then trigger a JazzDrive scan.

### Files Changed
- hub/routes/admin.py (db_reset route patched, Flask restarted)

### Non-Negotiable Rules (carry forward)
- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- No git shell commands — GitHub pushes via Contents/Trees API only

---

## Session: 2025-06-07 — Bug fixes: catalog sync, local video black screen, vault biometric

### Bugs Fixed

**FIX-CATALOG-01 — Published movies not showing play button (some)**
- Root cause: Flutter local DB was synced before all 3 movies were published; only 1 had file data. After publishing, catalog version must change to trigger auto-sync.
- Fix: Bumped  on all 3 published titles (Animal id=16, Bhooth Bangla id=25, Luka Chuppi id=27). Catalog version is MAX(updated_at), so this forces app to re-sync on next check. User must also tap Settings → Sync if auto-sync doesn't trigger.
- Note: Animal (id=16) has no file linked at all → play button will never show until a file is linked.

**FIX-PLAYER-01 — Local video black screen after 2-3s, audio continues**
- Root cause:  condition for the local-file fade-in guard was . On Infinix/MediaTek, the player internally resets  to  and emits  transiently during playback (~2-3s). This triggered opacity=0, making the video surface appear black. Opening the VideoDisplay settings panel forced a rebuild that saw position/playing correctly, restoring opacity=1.
- Fix: Changed condition to use  instead of . Duration is only zero before the file loads; it stays at the file's runtime throughout playback regardless of position resets.
- Commit: 215bbc2055 (player_screen.dart line 2700)

**FIX-VAULT-01 — Vault biometric not working (fingerprint prompt never appeared)**
- Root cause:  in  throws a  on Infinix/MediaTek phones that lack Class 3 (strong) biometric. The exception was caught by  silently — no prompt, no error shown.
- Fix: Changed  → . The vault already has its own PIN keypad as the alternative, so the system biometric dialog also offering device-credential fallback is safe.
- Commit: 59fc97249c (vault_service.dart line 157)

### DB Changes
- titles.updated_at bumped for ids 16, 25, 27 (catalog version refresh)

### Non-Negotiable Rules (carry forward)
- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- No git shell commands — GitHub pushes via Contents/Trees API only
- No local Python3 — use Oracle SSH for Python3 GitHub API calls

---

## Session: 2026-06-07 — 3 Bug Fixes (catalog sync, local video black screen, vault biometric)

### Context
User reported 3 bugs seen in build1023:
1. Published movies missing play button (only 1 of 3 showed it)
2. Local video goes black after 2-3s; audio continues; opening settings restores video
3. Vault fingerprint unlock did not work

---

### FIX-CATALOG-01 — Play button missing on published movies
**Root cause:** Flutter app local SQLite synced before all movies were published;
local DB had stale/missing file_id + share_url for Bhooth Bangla and Luka Chuppi.
**Fix:** Bumped updated_at on all published titles (SQL):
  UPDATE titles SET updated_at = strftime(%s,now) WHERE is_published=1;
Catalog version = MAX(updated_at), so the app detects the change and re-syncs on next launch.
**Note:** Animal (id=16) has NO file linked — play button will not appear until a video
file is scanned/uploaded and linked to this title_id.

---

### FIX-PLAYER-01 — Local video black screen after 2-3s (commit 215bbc2055)
**File:** raddflix_flutter/lib/screens/player_screen.dart  L2701
**Root cause (proven from stream listener code):**
Two Dart stream listeners run microseconds apart:
  _player.stream.position fires  -> _position = Duration.zero  (NO setState, direct assign)
  _player.stream.playing  fires  -> setState(() => _playing = false)  (triggers rebuild)
  build() reads: _isLocalFile=true, !_playing=true, _position=Duration.zero -> opacity=0.0 -> BLACK

This is an Infinix/MediaTek quirk: content:// local URIs cause a transient internal
player reset (position=0, playing=false) at ~2-3s during MediaCodec initialization.
_position is a direct-assign (no setState), so build() sees the reset value exactly when
_playing fires its setState rebuild — a precise race condition.

**Fix:** Changed _position==Duration.zero to _duration==Duration.zero.
_duration is also direct-assign (no setState) but is set once at file-load and NEVER
resets during playback. Any subsequent rebuild sees _duration > 0, keeping opacity=1.0.
  OLD: opacity: (_isLocalFile && !_playing && _position == Duration.zero) ? 0.0 : 1.0,
  NEW: opacity: (_isLocalFile && !_playing && _duration == Duration.zero) ? 0.0 : 1.0,

**Why "opening settings restores video":** By the time the user opens the settings panel
(seconds later), the player has recovered (_playing=true, _position>0). The setState from
opening the panel rebuilds with the correct state, restoring opacity=1.0.

---

### FIX-VAULT-01 — Vault fingerprint prompt never appeared (commit 59fc97249c)
**File:** raddflix_flutter/lib/services/vault_service.dart  L157
**Root cause:** biometricOnly:true maps to Android BiometricPrompt BIOMETRIC_STRONG (Class 3).
Infinix fingerprint sensors are Class 2 (BIOMETRIC_WEAK). Android throws PlatformException
before the prompt appears. catch(_){return false} swallowed it silently — no prompt, no error.
User confirmed: fingerprint works in ALL other apps (those use biometricOnly:false or omit it).
**Fix:** biometricOnly:false — fingerprint still preferred; device PIN available as fallback
in the system dialog. Vault PIN keypad remains as the separate in-app fallback.
  OLD: biometricOnly: true,   // strict: no device PIN/pattern fallback
  NEW: biometricOnly: false,  // FIX-VAULT-01: Class 3 throws on Infinix; false still uses fingerprint

---

### Verification (via GitHub API — bypasses CDN cache)
  player_screen.dart SHA bf614900e141 — _duration==Duration.zero confirmed at L2701
  vault_service.dart  SHA fc646586fa55 — biometricOnly: false confirmed at L157
  Oracle DB: updated_at=1780856421 (2026-06-07 18:20:21) for title ids 16, 25, 27

### Non-Negotiable Rules (carry forward)
- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart
- No git shell — GitHub Contents API only; use Oracle Python3 for large files
- GitHub token in local Replit env GITHUB_TOKEN (Oracle .env is empty)
- db.setting(k) not db.get_setting(k)

---

## Session: 2026-06-07 (continued) — FEAT-AUTOPUB-01: Auto-publish titles after scan

### Problem
Every time a new movie/show was scanned from JazzDrive, its title row sat in the DB
with is_published=0 (invisible to users). An admin had to manually run SQL to set
is_published=1. This caused: Bhooth Bangla + Luka Chuppi missing play buttons in build1023.

### Solution: _auto_publish_titled_files(account_id) in scanner.py
Added a new helper function that runs a single atomic SQL query:

  UPDATE titles SET is_published=1, updated_at=<now>
  WHERE id IN (
      SELECT DISTINCT title_id FROM files
      WHERE account_id=? AND title_id IS NOT NULL
        AND share_url IS NOT NULL AND share_url != 
  )
  AND is_published=0

This publishes any title that:
  - Has at least one file linked to it (for this account)
  - That file has a share_url (so the Flutter app can stream it)
  - Was not already published

Called from 3 locations in _scan_worker:
  L600 — function definition (after _assign_poster_share_urls)
  L807 — main scan completion path (after enrichment, before db.touch_account_scan)
  L820 — InterruptedError path (after _import_legacy_into_v3, if user stops scan early)

### Files changed (Oracle only — no app rebuild needed)
  /opt/jazzmax/radd-hub/hub/scanner.py
    L600: new _auto_publish_titled_files() function
    L807: call after enrichment in main scan flow
    L820: call in InterruptedError handler

### Verification
  python3 -m py_compile scanner.py → SYNTAX OK
  Backend restarted: PID 1020859, responding on :5000

### Impact
From now on: run a scan → titles with linked files are auto-published immediately.
No more manual SQL needed after scanning new content.

---

## Session: 2026-06-08 — INVESTIGATION: All streaming broken + local video still dark

### User report (post-build1023 install)
1. Local video still goes dark immediately on play
2. Movies → "video not available"
3. Season episodes → "retry link has expired" even on first play

### Root Cause 1: User installed build1023 (before our fixes)
Both FIX-PLAYER-01 (215bbc2055) and FIX-VAULT-01 (59fc97249c) were committed on June 7
AFTER build1023 was created. GitHub Actions automatically triggered:
  build1024 → FIX-VAULT-01 commit → completed success 2026-06-07T18:22:41
  build1025 → FIX-PLAYER-01 commit → completed success 2026-06-07T18:23:14
User must install build1025 (RaddFlix-1.0.0+1-build1025.apk, 56MB) to get both fixes.

### Root Cause 2: db_update.json was stale (June 2, 6 days old)
The db_update.json catalog file had:
  - version=1780400706 (June 2) while DB had current titles from June 7-8
  - ALL titles showed share_url="" (no share_urls in old file rows)
  - Did NOT contain Bhooth Bangla, Luka Chuppi, Spider-Noir, Vincenzo at all
  - Had OLD title_ids (e.g. Dune=9, Inception=14) that dont match current DB


---

## Session: 2026-06-08 — All streaming broken + local video still dark

### User report
1. Local video still goes dark on play
2. Movies: "video not available"
3. Episodes: "retry link has expired" even on first play

### Root Cause 1: Wrong APK installed (build1023, before our fixes)
FIX-PLAYER-01 commit 215bbc2055 and FIX-VAULT-01 commit 59fc97249c were pushed
AFTER build1023. GitHub Actions auto-triggered:
  build1024 success 2026-06-07T18:22:41
  build1025 success 2026-06-07T18:23:14
User must install build1025 (56MB) to get both fixes.

### Root Cause 2: db_update.json stale since June 2 (6 days old)
The catalog JSON had version=1780400706 and zero share_urls on any file.
It did not contain Bhooth Bangla, Luka Chuppi, Spider-Noir, or Vincenzo.
Old file_ids no longer existed in current DB stream_links.
When Flutter called the play endpoint with stale file_ids, the server returned
404 "file not found" or 404 "no share_url" which Flutter renders as errors.
The db_update.json regeneration trigger was not firing after direct SQL updates.

### Root Cause 3: Three ghost-published titles had no files
Titles 15 Dune, 16 Animal, 20 Inception were is_published=1 but had zero rows
in the files table. They were manually published before any scan linked files.

### Fixes Applied (server-side, no APK rebuild needed)
FIX-CATALOG-02: Unpublished 3 ghost titles via SQL:
  UPDATE titles SET is_published=0, updated_at=now WHERE id IN (15,16,20)
  AND NOT EXISTS (SELECT 1 FROM files WHERE title_id=titles.id)
  Result: 3 rows updated

FIX-CATALOG-03: Regenerated db_update.json from scratch via Python:
  version=1780915473 (fresh timestamp, Flutter will detect change and sync)
  4 published titles, all with real share_urls and valid file_ids
  4 episodes, all with real share_urls

### Final catalog state
  title_id=25  Bhooth Bangla  movie  file_id=18  share=YES
  title_id=27  Luka Chuppi   movie  file_id=28  share=YES
  title_id=28  Spider-Noir    show   S1E1 f31 S1E2 f30  share=YES
  title_id=30  Vincenzo       show   S1E1 f35 S1E2 f32  share=YES

### APK location for user
  Build: 1025  File: RaddFlix-1.0.0+1-build1025.apk  56MB
  GitHub Actions run ID: 27100948120
  Artifact ID: 7466792698  Expires: 2026-07-07
  URL: github.com/raddclub/raddflix-app/actions/runs/27100948120

### Notes for next session
  - db_update.json auto-regen does NOT trigger on direct SQL updates to titles.
    Always regenerate manually via Python script after any is_published change.
  - Ghost-published titles from old data: IDs 15, 16, 20 now set to is_published=0.
  - SSH key lives in ORACLE_SSH_KEY env var; reconstruct at /tmp/oracle_key on session start.

---

## Session: 2026-06-10 — PERF-01: Oracle CPU spike diagnosed + proxy pool throttled

### Problem
Admin panel was slow/unresponsive. Oracle CPU at 99.9%.

### Root Cause
ProxyPool was running 23,815 proxies across 161 threads:
- Healthcheck executor: 40 workers × continuous testing
- Discovery executor: 80 workers × 8 sources
- Both looping every 30–60 seconds with zero throttling

### Fix Applied
Throttled ThreadPoolExecutors (40→8, 80→10), extended HC interval to 300s,
discovery interval to 900s. VACUUM'd SQLite DB (radd_hub.db) to reclaim space.

### Result
CPU → normal, admin panel responsive.

### Commit: dde746e

---

## Session: 2026-06-10 — PERF-02: Proxy background scanning permanently removed

### Problem
Even throttled, proxy threads caused periodic CPU spikes. Background scanning
provides zero benefit on Oracle (no Jazz SIM → all proxies test as dead anyway).

### Fix Applied
Removed all 4 background threads from ProxyPool:
- `hc_loop` (healthcheck loop)
- `recovery_loop` (re-test disabled proxies)
- `disc_loop` (proxy discovery)
- `test_seeds_bg` (seed testing on startup)

Patched `ProxyPool.start()` and `_seed_if_empty()` — no threads started at all.
Manual triggers remain: `/api/pool/healthcheck`, `/api/pool/discover` in Settings.

### Result
9 threads total, ~2% CPU, 85MB RAM. Permanent — no DB toggle needed.

### Commit: 519f649

---

## Session: 2026-06-10 — PERF-03: Per-service DB toggle system + Admin UI

### What was built

**DB toggle guards added to 4 service loop files:**
- `hub/mirror.py` — MIRROR_ENABLED check at top of retry_loop()
- `hub/downloader.py` — DOWNLOAD_ENABLED check before new-job dispatch in queue_loop()
- `hub/keepalive.py` — KEEPALIVE_ENABLED check with 60s sleep-wait in loop()
- `hub/scheduler.py` — SCHEDULER_ENABLED check with 60s sleep-wait in scheduler_loop()

**Admin API routes added to `routes/admin.py`:**
- `GET  /admin/api/services` — returns all 8 services with enabled state
- `POST /admin/api/services/toggle` — sets a DB key or calls supervisorctl (WA bot)

**Admin UI card added to `templates/admin.html`:**
- "Background Services" card at top of admin panel
- Live toggle switches for all 8 services
- Labels + descriptions for each service
- JavaScript auto-updates toggle state from API response

**Services controlled:**
| Service | Mechanism |
|---------|-----------|
| Upload Watcher | UPLOAD_ENABLED DB key |
| Download Queue | DOWNLOAD_ENABLED DB key |
| Mirror Retry | MIRROR_ENABLED DB key |
| JazzDrive Keepalive | KEEPALIVE_ENABLED DB key |
| Scanner | SCAN_ENABLED DB key |
| Smart Scheduler | SCHEDULER_ENABLED DB key |
| Domain Doctor | DOMAIN_DOCTOR_ENABLED DB key |
| WhatsApp Bot | supervisorctl start/stop raddflix_wa_bot |

**Behaviour when disabled:** service loop skips all work and sleeps dormant.
Re-enable takes effect within one loop cycle — no Flask restart needed.

### Verification
- All 8 toggles tested live: logs show "Service X set to DISABLED by admin"
- Services go completely silent in logs immediately after toggle
- WA bot confirmed STOPPED via `supervisorctl status` after toggle OFF
- Re-enable confirmed for all services

### Commits: 81f0300 through d529b1e

---

## Session: 2026-06-10 — PERF-04: Fix downloader thread-reaping bug

### Problem
DOWNLOAD_ENABLED check was placed BEFORE thread reaping and hang watchdog in
`queue_loop()`. When downloads were disabled:
- Finished download threads were never reaped from `active_threads` dict
- Hang watchdog never ran → stuck jobs not detected or re-queued

### Fix Applied
Moved the check to just before new-job dispatch (after thread reaping + hang watchdog):

```
while loop:
  ├── Thread reaper       ← always runs (cleans finished jobs)
  ├── Hang watchdog       ← always runs (kills stuck jobs)
  ├── Max-parallel check  ← skip if at capacity
  ├── DOWNLOAD_ENABLED?   ← check is HERE (skip new dispatch only)
  └── Dispatch new job
```

### Result
Disabling downloads now stops only NEW job dispatch. Active jobs finish cleanly
and get properly cleaned up. Hang watchdog runs regardless of toggle state.

### Commit: 62407f7

---

## Session: 2026-06-10 — PERF-05: Service dependency logic + Oracle restart

### What was built

**Problem:** Services had no awareness of each other. Turning on Smart Scheduler
while Keepalive was off would leave it running broken silently. No way to know
which services depended on which.

**Backend changes — routes/admin.py:**

Added dependency metadata to each service definition:


Three new helper functions:
-  — lookup service by name
-  — reads DB setting for a service
-  — writes DB setting + logs

 now returns per-service:
-  — what this service needs
-  — what depends on this service
-  — deps that are currently OFF while this is ON
-  — dependents that are ON while this is OFF

 now:
- ON: auto-enables all deps (depth-first) before enabling the target; returns  list
- OFF: returns  list for any enabled service that depends on this one

**Frontend changes — templates/admin.html:**

- Service cards show needs: X, Y pills under each service
- Orange warning badge if service is ON but a required dep is OFF
- Red warning badge if service is OFF but another service depends on it that is ON
- Border color reflects health state (orange = missing dep, red = breaking dependents)
- Toast notifications: Auto-enabled first: Keepalive, Scanner on enable
- Toast warnings: Scanner is ON and needs Keepalive — it will stop working on disable

Services reordered from top to bottom by dependency chain:
  Keepalive (foundation) → Scanner → Upload → Scheduler → Download → Mirror → Domain Doctor

### Live Test Results

Test 1: Enable Scheduler (scan=OFF, keepalive=ON)
  auto_enabled: ['scan']  <- scan auto-enabled first automatically
  warnings: []

Test 2: Disable Keepalive (while scheduler+scan are ON)
  auto_enabled: []
  warnings: ['Scanner is ON and needs JazzDrive Keepalive — it will stop working',
             'Smart Scheduler is ON and needs JazzDrive Keepalive — it will stop working']

Both correct.

### Also in this session
- Full Oracle server restart (raddflix_radd + raddflix_wa_bot)
- Confirmed CPU ~1.2%, threads=9, Flask healthy after restart

### Commits: 2ba55de (admin.py), 88be21e (admin.html)

---

## Session 2026-06-10 — Backlog cleanup

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| CLEANUP-01 | Dropped DATA-01, DATA-02, BUG-CATALOG-REGEN, BUG-DELTA-PUSH, BUG-DUNE-FILE from backlog per user request | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| agent-hub/TASKS.md | Removed all 5 backlog items — backlog now empty | 1853f91 |
| .agents/tasks/BUG_TRACKER.md | Moved DATA-01, DATA-02, BUG-CATALOG-REGEN, BUG-DELTA-PUSH, BUG-DUNE-FILE to Dropped/Won't Fix section | 1853f91 |

### State at end of session
- Oracle Flask: RUNNING (`{"ok":true,"version":"3.0.0"}`)
- Account: ACTIVE (auto-recovers via Android OAuth2 + PK proxy)
- Open tasks: none — backlog is clean

---

## Session 2026-06-11 — Upload JazzDrive 8.0.1 XAPK to GitHub

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| UPLOAD-XAPK-01 | Upload Jazz_Drive_8.0.1.xapk (41.8 MB) to jazzdrive_research/ | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| jazzdrive_research/README.md | New file — links to release asset download | bc1eebe |
| GitHub Release: jazzdrive-apks-v1 | Created release, uploaded Jazz_Drive_8.0.1.xapk as asset | release id 337923458 |

### Notes
GitHub tree/blob API rejects base64 payloads over ~50 MB. Used GitHub Releases API (upload.github.com) instead — supports up to 2 GB. README.md added to jazzdrive_research/ folder with direct download link.

### State at end of session
- Oracle Flask: RUNNING (`{"ok":true,"version":"3.0.0"}`)
- Account: ACTIVE (auto-recovers via Android OAuth2 + PK proxy)
- Open tasks: none — backlog clean
- APK: https://github.com/raddclub/raddflix-app/releases/download/jazzdrive-apks-v1/Jazz_Drive_8.0.1.xapk
