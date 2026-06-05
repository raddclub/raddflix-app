# BUG_TRACKER.md
Last updated: 2026-06-04

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
and escaped `# BUG_TRACKER.md
Last updated: 2026-06-04

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

 to prevent shell variable substitution. The escape survived into
the committed Dart file undetected because the fallback always returned a playable URL.

**Rule:** Any Dart string built in a generator script must use concatenation for dynamic
parts, never `\# BUG_TRACKER.md
Last updated: 2026-06-04

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

 — or use raw strings (`r'...'`).

---

## Data Gap (not a code bug)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | OPEN | Episodes not in Oracle DB episodes table. Need upload to JazzDrive + sync. |


---

## Session 2026-06-05 — Proxy Pool God-Level Upgrade

No new bugs found in app logs. App running cleanly (raddflix_radd via supervisorctl).

### Changes made (not bugs — improvements)

| ID | Type | Title | Action | File |
|----|------|-------|--------|------|
| IMP-P01 | IMPROVEMENT | Proxy pool had only 65 seeds with basic round-robin | Upgraded to 150+ seeds, weighted scoring, circuit breaker, 5-min fast recovery | `hub/proxy_pool.py` |
| IMP-P02 | IMPROVEMENT | Dead proxy recovery only ran every 10 min | Added fast recovery thread: re-tests disabled proxies every 5 min | `hub/proxy_pool.py` |
| IMP-P03 | IMPROVEMENT | If all proxies dead, upload would fail | CircuitBreaker: >80% dead → auto-fallback to direct connection | `hub/proxy_pool.py` |
| IMP-U01 | IMPROVEMENT | Settings proxy panel was old inline code (basic table, no stats, no sort, 30s refresh) | Replaced with god-level `_proxy_pool_panel.html` include (stat cards, filter, sort, score, bulk import, export, per-proxy test, 10s refresh) | `hub/templates/settings.html` |
| IMP-U02 | IMPROVEMENT | No bulk import for proxies | Added bulk import panel: paste 100+ proxy URLs, auto-detect format | `hub/templates/_proxy_pool_panel.html` |
| IMP-A01 | IMPROVEMENT | Only 3 pool API endpoints (list, add, remove) | Added 5 new endpoints: stats, bulk-import, test-one, reset-dead, export | `hub/routes/settings.py` |

### Log analysis (last 30 min as of 2026-06-05 13:47 UTC)
- **No errors** in app logs
- App shows clean startup banner (Radd Hub v3.0 on port 5000)
- `raddflix_radd` uptime at log check: 22 min (was restarted cleanly ~13:24 UTC)
- No proxy failures, upload errors, or exception traces observed

### Open bugs (unchanged)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | ❌ OPEN | Episodes not in Oracle DB. Need JazzDrive upload + sync. |

---

## Session 2026-06-05 (2nd session) — OTP Upload Page Investigation

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-O01 | CRITICAL | OTP not received from upload page | `scanner.send_otp()` called `resolve_proxies()` once with no retry; `resolve_proxies(otp)` returned `None` when circuit open → direct connection → MED-1011 | Added proxy retry chain to `send_otp()` and `resend_otp()` (same pattern as `trigger_otp_flow`) | `hub/scanner.py` |
| BUG-O02 | HIGH | OTP always fails when proxy pool circuit is open | `resolve_proxies(purpose='otp')` called `pool.get_best()` which returns `None` when circuit open — designed for SAPI, wrong for OTP (direct = MED-1011) | Added fallback to `get_proxy_chain(n=1)` when `get_best()` returns `None`, so OTP always gets a proxy | `hub/jazzdrive.py` |

### Root Cause Summary
Two independent bugs both cause OTP to silently use direct connection from Oracle's non-PK IP:
1. Circuit breaker passthrough in `resolve_proxies(otp)` — designed for SAPI but affects OTP
2. No retry chain in `scanner.send_otp()` — Settings OTP path had retry, upload page path did not

Commit: `696890f`

---

## Session 2026-06-05 (3rd session) — OTP Verify Proxy Bug

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-V01 | CRITICAL | OTP verify always fails — "Connection aborted, RemoteDisconnected" | `verify_otp` used `resolve_proxies(purpose='sapi')` which returns `None` when pool circuit is open. Both standard flow AND mobile_direct fallback ran with zero proxy → direct Oracle IP → Jazz drops connection on verify.php | Changed to `purpose='otp'` + full retry chain with `mark_fail` (same pattern as send_otp/resend_otp). Both flows now retry up to 5 proxies before giving up. | `hub/scanner.py` |
| BUG-V02 | HIGH | Cascading session death after failed OTP verify | When verify_otp fails, no new tokens are saved. Old refresh_token eventually hits `invalid_grant`. Access token expires too. Keepalive cannot recover → account stuck needing OTP re-login | Fixed by BUG-V01 (verify succeeds → tokens saved → keepalive has valid tokens to refresh) | `hub/scanner.py` |

### Root Cause Detail — BUG-V01

`verify_otp` is an OTP web-portal flow (hits `jazzdrive.com.pk/verify.php`).
It must use `purpose='otp'` which has a circuit-open fallback to the least-dead proxy.
It was incorrectly using `purpose='sapi'` which has NO circuit-open fallback — returns `None`
when >80% of pool is dead. With `None` proxies, Jazz drops the connection immediately from
Oracle's non-PK IP. The mobile_direct fallback received the same `None` proxies and also failed.

**Pattern now unified across all OTP steps:**
- `send_otp` → `resolve_proxies('otp')` + chain(4) + mark_fail ✅ (fixed 2nd session)
- `resend_otp` → `resolve_proxies('otp')` + chain(4) + mark_fail ✅ (fixed 2nd session)
- `verify_otp` → `resolve_proxies('otp')` + chain(4) + mark_fail + mobile_direct retries ✅ (fixed 3rd session)

### Cascading Failure Chain (BUG-V02 observed in logs)
```
verify_otp fails (no proxy) → no tokens saved
→ old refresh_token expires → invalid_grant (HTTP 400)
→ old raw_accesstoken expires → 401 Unauthorized
→ keepalive heartbeat fails repeatedly
→ account needs fresh OTP re-login
→ verify_otp fails again (same bug) → loop
```
After BUG-V01 fix this loop is broken. Account 03286829827 needs one fresh OTP login to restore tokens.

Commit: `bd037a7`
