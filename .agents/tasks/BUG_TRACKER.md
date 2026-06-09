# BUG_TRACKER.md
Last updated: 2026-06-09

## Status Key
- ✅ FIXED — committed and verified on live server
- 🔄 IN PROGRESS
- ❌ OPEN
- 🚫 WONT FIX / INTENTIONAL

---

## Session 2026-06-04 — All bugs fixed

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-C01 | CRITICAL | Catalog always empty after fresh install | XOR decode: server strips base64 `=` padding; Dart `base64Url.decode` throws `FormatException` without it | Re-add padding: `b64 += '=' * ((4 - b64.length % 4) % 4)` before decode | `core/security/request_encoder.dart` |
| BUG-C02 | CRITICAL | Login always fails — "Login failed" toast on every attempt | `AuthApi.getMe()` called post-login on XOR path — same padding bug threw `TypeError` before response was parsed | Same padding fix | `core/security/request_encoder.dart` |
| BUG-C03 | CRITICAL | Premium plan shows as FREE after subscription | `_saveUserCache()` in auth_provider never executed (always threw before reaching it) | Same padding fix unblocked the call chain | `core/security/request_encoder.dart` |
| BUG-C04 | CRITICAL | App requires full login every restart — session not persisting | `checkAuth()` found no cached user (write to SharedPrefs never reached due to C02 exception) | Same padding fix | `core/security/request_encoder.dart` |
| BUG-C05 | HIGH | Plans/pricing screen completely empty | `GET /api/subscription/plans` is XOR-encoded — same padding bug silently dropped the response | Same padding fix | `core/security/request_encoder.dart` |
| BUG-P01 | HIGH | Black screen for 3–5 seconds before video plays | `androidAttachSurfaceAfterVideoParameters: true` causes surface re-attach failure on Android | Removed from `VideoController` config | `screens/player_screen.dart` |
| BUG-D01 | MEDIUM | TypeError in api_client: `response.data` not always a Map | XOR interceptor returns decoded JSON string; code assumed `Map` type without checking | Added type guard: `data is String ? jsonDecode(data) : data` | `core/api/api_client.dart` |
| BUG-S01 | MEDIUM | Catalog shows blank after sync fails (no internet) | `catalog_provider.dart` propagated sync exception without falling back to local DB | Added `await loadFromDb()` in the sync catch block | `providers/catalog_provider.dart` |

---

## Root Cause Summary

**5 of 8 bugs (BUG-C01 through BUG-C05) had a single root cause:**
Python's `base64.urlsafe_b64encode().rstrip(b"=")` strips 1–2 padding characters.
Dart's `base64Url.decode()` requires correct padding. Without the fix, every XOR decode
threw a `FormatException` that propagated silently up the call chain, making the entire
catalog, auth, and subscription systems appear broken.

Two characters (`==`) caused 5 critical bugs.

---

## Non-Bugs (intentional behavior)

| Item | Notes |
|------|-------|
| Frida tamper check (port 27042) | Correct security behavior — do not remove |
| sqflite_sqlcipher pinned at 3.1.0+1 | Must stay pinned — SQLCipher Dart API changed |
| No catalog on first cold start | Expected — sync takes a few seconds on first launch |

---

## Open Bugs

See DATA-01 below — all code bugs are fixed.

---

## Session 2026-06-04 (continued) — Additional bugs found and fixed

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-P02 | MEDIUM | Black flash before first frame of local video | `Video` widget at opacity 1.0 before first frame decoded | Wrapped in `AnimatedOpacity(0.0->1.0 at 400ms)` on `_playing` | `screens/player_screen.dart` |
| BUG-P03 | HIGH | planExpired redirect fires 1-3s into local file playback | `_checkQuota()` checked sub_expires_at for all paths including local files with empty fileId | Guard `&& widget.fileId.isNotEmpty` — local files skip quota | `screens/player_screen.dart` |
| BUG-J01 | CRITICAL | JazzDrive Pass 3 never matched — all folder shares played first file | Dart backslash-dollar in non-raw string = literal $, not interpolation. Pass 3 built literal text instead of `s01e04` | Replaced with concatenation `'s' + s + 'e' + e` | `core/services/jazzdrive_service.dart` |

### Root Cause Detail — BUG-J01

Pass 3 compared JazzDrive record names against a literal string like
`s${em.group(1)!.padLeft(2,"0")}e...` instead of e.g. `s01e04`.
It never matched anything. All episode folder shares silently fell back to
`records[0]` (first file in the share), so every episode played the same video.

The bug was introduced when a Node.js automation script generated Dart source code
and escaped `$` to prevent shell variable substitution. The escape survived into
the committed Dart file undetected because the fallback always returned a playable URL.

**Rule:** Any Dart string built in a generator script must use concatenation for dynamic
parts, never `\$` — or use raw strings (`r'...'`).

---

## Data Gap (not a code bug)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | ❌ OPEN | Episodes not in Oracle DB episodes table. Need upload to JazzDrive + sync. |

---

## Session 2026-06-05 — Proxy Pool God-Level Upgrade

No new bugs found in app logs. App running cleanly (raddflix_radd via supervisorctl).

### Changes made (not bugs — improvements)

| ID | Type | Title | Action | File |
|----|------|-------|--------|------|
| IMP-P01 | IMPROVEMENT | Proxy pool had only 65 seeds with basic round-robin | Upgraded to 150+ seeds, weighted scoring, circuit breaker, 5-min fast recovery | `hub/proxy_pool.py` |
| IMP-P02 | IMPROVEMENT | Dead proxy recovery only ran every 10 min | Added fast recovery thread: re-tests disabled proxies every 5 min | `hub/proxy_pool.py` |
| IMP-P03 | IMPROVEMENT | If all proxies dead, upload would fail | CircuitBreaker: >80% dead → auto-fallback to direct connection | `hub/proxy_pool.py` |
| IMP-U01 | IMPROVEMENT | Settings proxy panel was old inline code | Replaced with `_proxy_pool_panel.html` include (stat cards, filter, sort, score, bulk import, export, per-proxy test, 10s refresh) | `hub/templates/settings.html` |
| IMP-U02 | IMPROVEMENT | No bulk import for proxies | Added bulk import panel: paste 100+ proxy URLs, auto-detect format | `hub/templates/_proxy_pool_panel.html` |
| IMP-A01 | IMPROVEMENT | Only 3 pool API endpoints | Added 5 new endpoints: stats, bulk-import, test-one, reset-dead, export | `hub/routes/settings.py` |

---

## Session 2026-06-05 (2nd session) — OTP Upload Page Investigation

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-O01 | CRITICAL | OTP not received from upload page | `scanner.send_otp()` called `resolve_proxies()` once with no retry; circuit open → direct → MED-1011 | Added proxy retry chain to `send_otp()` and `resend_otp()` | `hub/scanner.py` |
| BUG-O02 | HIGH | OTP always fails when proxy pool circuit is open | `resolve_proxies(purpose='otp')` returned `None` when circuit open | Added fallback to `get_proxy_chain(n=1)` | `hub/jazzdrive.py` |

Commit: `696890f`

---

## Session 2026-06-05 (3rd session) — OTP Verify Proxy Bug

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-V01 | CRITICAL | OTP verify always fails — "Connection aborted, RemoteDisconnected" | `verify_otp` used `resolve_proxies(purpose='sapi')` which returns `None` when circuit open → direct Oracle IP → Jazz drops connection | Changed to `purpose='otp'` + retry chain with `mark_fail` | `hub/scanner.py` |
| BUG-V02 | HIGH | Cascading session death after failed OTP verify | verify_otp failure → no tokens saved → keepalive can't recover | Fixed by BUG-V01 | `hub/scanner.py` |

Commit: `bd037a7`

### Cascading Failure Chain (BUG-V02)
```
verify_otp fails (no proxy) → no tokens saved
→ old refresh_token expires → invalid_grant (HTTP 400)
→ old raw_accesstoken expires → 401 Unauthorized
→ keepalive heartbeat fails repeatedly
→ account needs fresh OTP re-login → loop
```

---

## Session 2026-06-06 — Admin Panel db/reset Fix + db.get_setting Fix

| ID | Severity | Title | Root Cause | Fix Applied | File | Commit |
|----|---------|-------|-----------|-------------|------|--------|
| BUG-A01 | HIGH | Admin "Reset Tables" button shows success but nothing deleted | `db_reset()` used `db.conn()` shared wrapper; WAL-mode read locks from background threads silently blocked DELETE; inner `try/except: pass` swallowed all errors, always returned `ok:True` | Replaced with direct `sqlite3.connect()` + `BEGIN IMMEDIATE` (exclusive lock) + `PRAGMA wal_checkpoint(TRUNCATE)` after commit | `hub/routes/admin.py` | `f8affe1` |
| BUG-A02 | HIGH | `/api/app/config` crashes with `AttributeError` every ~2 min | `mobile_api.py` called `db.get_setting()` which does not exist; correct function name is `db.setting()` | Changed both occurrences to `db.setting("api_base_url", "")` | `hub/routes/mobile_api.py` | (this session) |

### Root Cause Details

**BUG-A01:** SQLite WAL mode allows concurrent readers but requires an exclusive write lock
for writes. Python's `sqlite3` via the shared `db.conn()` wrapper can silently fail to obtain
`BEGIN IMMEDIATE` when background threads hold open read transactions. The fix uses a fresh
direct connection which always succeeds in WAL mode.

**BUG-A02:** `db.py` exposes `setting(k, default)` and `set_setting(k, v)` — there is no
`get_setting()`. This caused an `AttributeError` on every call to `GET /api/app/config`,
returning an HTTP 500 instead of the app config. Flutter app fell back to hardcoded defaults.
The error appeared in logs every ~2 minutes (Flutter app polls this endpoint on cold start).

### Also investigated this session (not bugs — findings)

| Finding | Detail |
|---------|--------|
| Uploads use NO proxy/VPN | `JAZZDRIVE_PROXY_BYPASS=1` → all JazzDrive traffic goes direct from Oracle IP. WARP only routes 3 Jazz SAPI IPs for zero-rating; JazzDrive upload host is NOT in WARP tunnel. |
| Auto-delete is configured correctly | `upload_auto_delete=true` in DB settings. Delete only triggers if `share_url OR remote_id` exists after upload. Files stuck because account session expired → uploads fail → no share_url → no delete. |
| Leftover files in /data/media | `Pitt_Siyapa_2026.mp4` (682KB) and `Vncenz0.S01E02...mp4` (707KB) stuck since Jun 5. Empty folder `Off_Campus_S01/` also present. Root cause: account session expired, needs OTP re-login. |
| Account 03286829827 session | EXPIRED — needs fresh OTP re-login via Upload page. All keepalive heartbeats failing. |

---


## Session 2026-06-07 — BUG-A03: JazzDrive Geo-Restriction Root Cause

### Root Cause Summary
Session appeared "expired" (SAPI 401 on every restart) but raw_accesstoken was valid.
Our wg0 VPN exits through Cloudflare (162.159.192.1) — NOT a Pakistani IP.
JazzDrive /sapi/login/oauth is geo-restricted: Apache web server returns 401 HTML from
non-PK IPs before the request even reaches the SAPI application layer.
Normal SAPI calls (with JSESSIONID cookie) are NOT geo-restricted — these work fine direct.

### Bugs Fixed

| ID | Severity | Title | Root Cause | Fix | Commit |
|----|---------|-------|-----------|-----|--------|
| BUG-A03a | HIGH | _ar_chain in android_refresh_session tried dead proxy pool with PROXY_BYPASS=1 | Chain builder always queried pool (dead) even with bypass=1, wasting 4×25s timeouts before failing OAuth2 step | Added is_proxy_bypass() guard at top of _ar_chain builder | 54f2434 |
| BUG-A03b | CRITICAL | SAPI login blocked by geo-restriction (Cloudflare exit = non-PK IP) | wg0 exits via Cloudflare → Apache 401 HTML on /sapi/login/oauth | _s2_chain fetches proxy via proxy_pool.pool.get_best() directly, bypassing resolve_proxies() entirely — PK proxy used for login regardless of PROXY_BYPASS flag | 54f2434 |
| BUG-A03c | MEDIUM | Over-broad bypass fix routed ALL SAPI calls through PK proxy | Added purpose!='sapi' exception to resolve_proxies() bypass guard → all SAPI calls (keepalive, uploads) went through PK proxy, timing out | Reverted resolve_proxies() to original; scoped to _s2_chain direct pool access only | 54f2434 |
| BUG-A03d | MEDIUM | submit_otp _sub_chain: no PK proxy for geo-restricted OTP verify endpoint | cloud.jazzdrive.com.pk OTP verify is geo-restricted. _sub_chain used resolve_proxies() which returns None with PROXY_BYPASS=1 → Cloudflare exit → Apache 401 | _sub_chain now uses proxy_pool.pool.get_best() directly (mirrors _s2_chain fix). No is_proxy_bypass() short-circuit — this step MUST have PK proxy | bdea6d2 |

### SAPI Call Architecture (CRITICAL — memorise this)
```
CALL TYPE                  | EXIT IP              | GEO-RESTRICTED?
---------------------------|----------------------|----------------
Keepalive (JSESSIONID)     | wg0 → Cloudflare     | NO  ✅
Upload (JSESSIONID)        | wg0 → Cloudflare     | NO  ✅
OAuth2 /oauth2/refresh     | wg0 → Cloudflare     | NO  ✅
SAPI login /sapi/login     | Pakistani SOCKS proxy| YES ⚠️
```
PROXY_BYPASS=1 skips proxies in resolve_proxies() for all callers.
_s2_chain bypasses resolve_proxies() and reads pool directly — PK proxy always used for login.

### Verified Pakistani Proxies Added to sapi_proxies Table
| Proxy | Result |
|-------|--------|
| socks5://182.184.119.180:1080 | ✅ HTTP 200 from SAPI — primary |
| http://221.120.218.66:8080    | ⚠️ partial — fail_count=3 |

### Session State After Fix
```
✓ Heartbeat OK for 03286829827 (session alive, expiry rolled +30d)
startup_refresh: session restored — Android OAuth2 session refreshed (no OTP required)
```
OTP re-login no longer needed on Flask restart. Session auto-recovers via Android OAuth2 + PK proxy.

---

## Open Issues (requires user action, not code fixes)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | ❌ OPEN | Episodes not in Oracle DB. Need JazzDrive upload + sync. |
| OPS-01 | Account 03286829827 session | ✅ RESOLVED 2026-06-07 | BUG-A03 fixed. Session auto-recovers via Android OAuth2 + PK proxy. No OTP needed. |


---

## Session 2026-06-08 (TASK-057) — A-Z Full Audit + Fix + APK Build

### Oracle Python bugs fixed (commit 41fcc63)

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| FIX-ISONGOING | HIGH | Events never marked as not-ongoing | is_ongoing compared string "0" which is truthy in Python | Cast to int() before comparison | hub/routes/zero_rating.py |
| FIX-XOR-NEXTHR | MEDIUM | XOR decode fails near hour boundary | _candidate_keys() only tried current UTC hour | Added utc_hour + 1 as second candidate | hub/request_encoding.py |

### Flutter bugs fixed (commits 3a68806, bf50cd6)

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-TAB-01 | HIGH | TabController memory leak on pull-to-refresh | _initTabs() recreated controller without disposing old one | Dispose old controller before replacing | screens/show_detail_screen.dart |
| BUG-DL-THROTTLE | MEDIUM | SQLite DB flood during download | Progress updated on every byte callback — 100s writes/sec | Throttled to 5% boundary | core/download/download_service.dart |
| FIX-URI-01 | MEDIUM | Deep-link URI parse drops query params | uri.split('/').last discards ?queryParams | Uri.parse(uri).pathSegments.last with fallback | screens/splash_screen.dart |
| FIX-LIKE-01 | MEDIUM | Search LIKE matches wrong items | % and _ in search input act as SQL wildcards | Escape meta-chars before LIKE | core/db/local_db.dart |
| FIX-SEARCH-INIT | LOW | Search screen empty with initialFilter | initialFilter set text field but didn't call _doSearch() | Call _doSearch() in initState when initialFilter non-empty | screens/search_screen.dart |
| FIX-ID-CAST | LOW | TypeError crash on catalog item with null id | json['id'] as int throws TypeError when null | Safe cast: (json['id'] as int?) | models/catalog_item.dart |

### Build note
Initial commit 3a68806 had a Dart syntax error: semicolon placed AFTER an inline comment.
Rule: Dart semicolons MUST come BEFORE inline comments — expr); // comment (never after).
Fixed in commit bf50cd6. APK build1034 succeeded.

### APK
Build 1034 — RaddFlix-1.0.0+1-build1034.apk — run 27156269376 — 56.7 MB — expires 2026-07-08

---

## Open Data Gaps (need admin action, not code fixes)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | OPEN | Need JazzDrive upload + sync |
| DATA-02 | 9 movies with deleted JD files (Animal, Dune, Inception, Interstellar, Inuyashiki, Oppenheimer, Reborn, The Ninth Gate, Super Mario Galaxy) | OPEN | JD files deleted. Need manual re-upload to JazzDrive by admin |


## Session 2026-06-09 — BUG-STALE-IDS: Flutter stale catalog after DB rebuild

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-STALE-IDS | CRITICAL | Spider-Noir "Jazz SIM Required", Animal/Interstellar no play button, downloads FAILED | Oracle DB rebuilt with new title IDs (1-20), but Flutter's cached localVersion (1780929441) exactly matched server version → Flutter skipped re-sync → kept stale entries (id=28 file_id=31 → 404) | Server: force-bumped catalog_forced_version to 1781003205 (all devices full-sync on next open). Added valid_title_ids to /sync. Flutter (build1035): syncFull returns SyncFullResult; pruneStaleIds() deletes stale title IDs after full sync | catalog_api.py / catalog_api.dart / local_db.dart / sync_service.dart |
| BUG-PRUNE-SQL | CRITICAL | pruneStaleIds SQL had empty NOT IN () — would delete ALL titles | Dart $placeholders variable in pruneStaleIds SQL was stripped by bash heredoc variable expansion (bash double-quoted the SSH command) | Rewrote push via Python file + scp to avoid bash expansion. Restored NOT IN ($placeholders) | lib/core/db/local_db.dart (commit 338ad31b) |

### Encryption/Decryption Audit (2026-06-09) — All PASS

| Component | Check | Result |
|-----------|-------|--------|
| Flutter RequestEncoder | XOR encode/decode symmetric, padding restoration, RF1: passthrough | ✅ PASS |
| Flutter _XorInterceptor | Session key stored before body encode, auth paths excluded, octet-stream decode, error body decode | ✅ PASS |
| Server request_encoding.py | XOR symmetric, ±1h candidate keys, padding re-add, device_id from header/JWT fallback | ✅ PASS |
| CatalogItem.fromJson | All fields safe-cast, no TypeError on null id | ✅ PASS |
| scrambleUrl/unscrambleUrl | RF1: prefix guard, passthrough for legacy plain URLs, deviceId key fallback | ✅ PASS |

---

## Session 2026-06-08 — All bugs fixed


---

## Session 2026-06-09 (2nd) — JD File ID Audit (AUDIT-JD-ID)

### Investigation: Does JazzDrive use a permanent file ID? Are we using it correctly?

**Trigger:** User question — how does JazzDrive identify files for delete/rename, and are we using the right ID?

### Findings

| Finding | Detail |
|---------|--------|
| JD permanent file ID | `id` field in SAPI responses = Oracle `files.remote_id` (e.g. 242518443). Never changes on rename/move. |
| Oracle server ops | `rename_video(account_id, video_id, ...)` and `delete_files_permanent(account_id, file_ids)` both accept `remote_id` — **CORRECT** |
| Oracle `/sync` | Returns `remote_id` per episode in response body — **CORRECT** |
| Flutter `_persistItems` | Explicitly passes `'remote_id': ep['remote_id'] as int? ?? 0` to `upsertEpisode` — **CORRECT** |
| Flutter SQLite | `episodes` table has `remote_id INTEGER DEFAULT 0` column (via ALTER TABLE migration) — **CORRECT** |
| Flutter `getShareInfo` | Reads `remote_id` from DB and returns in result map — **CORRECT** |
| Flutter player | Reads `remoteId` from shareInfo and passes to `getStreamLink(remoteId: remoteId)` — **CORRECT** |
| Flutter Pass 0 | `_getMedia()` checks `m['id'] == remoteId` before filename fallback — **CORRECT** |
| Folder shares | Spider-Noir S01E01 (242518443) and S01E02 (242518530) share same folder URL — Pass 0 disambiguates correctly |

### Verdict: NO BUGS — system already correct

**No code changes were required.** The `remote_id` (JD permanent file ID) is correctly
stored in Oracle, returned via `/sync`, persisted in Flutter SQLite, read by the player,
and used as Pass 0 in `_getMedia()` for exact file matching.

| ID | Status | Title |
|----|--------|-------|
| AUDIT-JD-ID | ✅ CLOSED — NO BUGS | JazzDrive file identification audit — full chain verified correct |
