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

None known as of 2026-06-04.
