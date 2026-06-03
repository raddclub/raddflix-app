# BUG_TRACKER.md — RaddFlix Full Bug List
> Audit completed: 2026-06-03 (Session 35)
> 🔴 Open | 🟡 In Progress | 🟢 Fixed | ⚫ Won't Fix
> Fix in order: CRITICAL → HIGH → MEDIUM → LOW

---

## SERVER-SIDE BUGS (S01–S15)

| ID | File | Severity | Issue | Status | Fixed By |
|----|------|----------|-------|--------|----------|
| BUG-S01 | delta_push.py | 🔴 CRITICAL | delta.json version ignores force-bump → infinite re-sync loop | 🔴 Open | — |
| BUG-S02 | catalog_api.py | 🔴 HIGH | NULL updated_at titles returned in every delta sync (bandwidth waste) | 🔴 Open | — |
| BUG-S03 | catalog_api.py | 🔴 HIGH | GROUP BY with no ORDER on files → arbitrary file_id per sync (random 720p/1080p) | 🔴 Open | — |
| BUG-S04 | library.py | 🔴 HIGH | api_trending filters on t.poster_url (column doesn't exist) → always 0 results | 🔴 Open | — |
| BUG-S05 | library.py | 🔴 HIGH | epoch int vs datetime string compare → recent_views always 0, wrong sort order | 🔴 Open | — |
| BUG-S06 | app.py + request_encoding.py | 🔴 HIGH | XorWsgiMiddleware + decode_request() both decode same request → double-decode, body lost | 🔴 Open | — |
| BUG-S07 | subscriptions.py | 🟡 MEDIUM | Extending expired premium sub creates hardcoded "basic" plan (silent downgrade) | 🔴 Open | — |
| BUG-S08 | mobile_api.py | 🟡 MEDIUM | Race condition in register() → 500 instead of 409 on concurrent requests | 🔴 Open | — |
| BUG-S09 | mobile_api.py | 🟡 MEDIUM | app_config() hardcodes HTTP URL → breaks when HTTPS/domain added | 🔴 Open | — |
| BUG-S10 | catalog_api.py | 🟡 MEDIUM | force-version-bump can silently no-op if titles_max >= now_ts | 🔴 Open | — |
| BUG-S11 | mobile_api.py | 🟡 MEDIUM | watch_history UPSERT silently fails if UNIQUE(user_id, file_id) not in schema | 🔴 Open | — |
| BUG-S12 | delta_push.py | 🔵 LOW | Bulk-enrich triggers rapid consecutive JazzDrive re-uploads (SAPI rate risk) | 🔴 Open | — |
| BUG-S13 | library.py | 🔵 LOW | No delay/confirm before WhatsApp blast on publish — fires immediately | 🔴 Open | — |
| BUG-S14 | mobile_api.py | 🔵 LOW | Login rate-limit in-memory only → reset on every server restart | 🔴 Open | — |
| BUG-S15 | catalog_api.py | 🔵 LOW | Poster push job state in-memory → lost on server restart | 🔴 Open | — |

---

## FLUTTER APP BUGS (F01–F15)

| ID | File | Severity | Issue | Status | Fixed By |
|----|------|----------|-------|--------|----------|
| BUG-F01 | sync_service.dart | 🔴 CRITICAL | Device wall-clock used as `since` for delta → clock skew causes missed catalog updates | 🔴 Open | — |
| BUG-F02 | constants.dart | 🔴 CRITICAL | Color constants inside ApiPaths class, referenced as AppColors.* → compile error | 🔴 Open | — |
| BUG-F03 | local_db.dart | 🔴 CRITICAL | watch_positions v1→v2 migration missing `synced` column → crash on flushUnsynced() after upgrade | 🔴 Open | — |
| BUG-F04 | api_client.dart | 🔴 HIGH | _isRefreshing not atomic → concurrent 401 triggers double refresh → user logged out | 🔴 Open | — |
| BUG-F05 | remote_config.dart | 🔴 HIGH | Bootstrap config fetch is plain HTTP → MitM can redirect all API traffic | 🔴 Open | — |
| BUG-F06 | sync_service.dart + catalog_api.dart | 🔴 HIGH | Oracle sync expects data['episodes'] top-level key server never sends → shows have no episodes | 🔴 Open | — |
| BUG-F07 | local_db.dart | 🔴 HIGH | clearPendingUsage() never deletes rows → usage_log grows forever | 🔴 Open | — |
| BUG-F08 | local_db.dart | 🔴 HIGH | poster_share_url/folder_share_url not in schema → JazzDrive delta merge fails | 🔴 Open | — |
| BUG-F09 | catalog_provider.dart | 🟡 MEDIUM | Static _posterSyncDone flag never resets → new titles from delta syncs never get posters | 🔴 Open | — |
| BUG-F10 | api_client.dart | 🟡 MEDIUM | GET requests send X-Encoded:1 but session key can fail silently → XOR response never decoded | 🔴 Open | — |
| BUG-F11 | app_guard.dart | 🟡 MEDIUM | Fingerprint enforcement live — wrong signing key locks out all users with no error message | 🔴 Open | — |
| BUG-F12 | login_screen.dart | 🟡 MEDIUM | const TextSpan references runtime t.textPrimary → compile/runtime error in _Logo widget | 🔴 Open | — |
| BUG-F13 | connectivity_sync_service.dart | 🔵 LOW | Race between checkConnectivity() async and onConnectivityChanged — first flush may be skipped | 🔴 Open | — |
| BUG-F14 | local_db.dart | 🔵 LOW | No migration step ever adds `synced` column to upgraded watch_positions table (extends F03) | 🔴 Open | — |
| BUG-F15 | pubspec.yaml | 🔵 LOW | sqflite_sqlcipher pinned to old version with possibly unpatched SQLCipher vulnerabilities | 🔴 Open | — |

---

## RECOMMENDED FIX ORDER

### Round 1 — Compile errors first (app won't build without these)
1. **BUG-F02** — Move color constants from ApiPaths to AppColors in constants.dart
2. **BUG-F12** — Remove `const` from TextSpan referencing runtime t.textPrimary

### Round 2 — Crash bugs (existing users crash on upgrade)
3. **BUG-F03** — Add `synced INTEGER DEFAULT 0` to v2 migration ALTER TABLE
4. **BUG-F14** — Add same column in any subsequent migration step that touches watch_positions

### Round 3 — Core functionality broken
5. **BUG-S01 + BUG-F01** — Fix both together: delta.json version + since timestamp
6. **BUG-F06** — Fix episodes key mismatch between Oracle sync response and Flutter parser
7. **BUG-S04 + BUG-S05** — Fix trending: wrong column name + epoch vs datetime compare

### Round 4 — High severity
8. BUG-S02, BUG-S03, BUG-S06, BUG-F04, BUG-F05, BUG-F07, BUG-F08

### Round 5 — Medium severity
9. BUG-S07 through S11, BUG-F09 through F12

### Round 6 — Low severity
10. BUG-S12 through S15, BUG-F13 through F15

---

## HOW TO UPDATE THIS FILE

When fixing a bug, change its Status column:
- `🔴 Open` → `🟡 In Progress` (when you start working on it)
- `🟡 In Progress` → `🟢 Fixed` (after commit + CI green + server verified)
- Add the commit SHA and date in the "Fixed By" column
