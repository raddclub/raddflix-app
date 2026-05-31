# MASTER_PLAN.md — RaddFlix Task Queue
> **This is the single source of truth for what to work on next.**
> Always check this before starting any work. Update status when done.
> Last Updated: 2026-05-31 (Session 2: P1.1-P1.4, P2.2, P2.3, P2.6, P3.2, P3.6 completed)

---

## STATUS KEY
- `⏳ PENDING` — not started
- `🔄 IN PROGRESS` — currently being worked on
- `✅ DONE` — complete and verified (CI green, no regressions)
- `❌ BLOCKED` — waiting on external factor
- `⏸️ DEFERRED` — intentionally postponed

---

## ⚡ PRIORITY 1 — Critical Bugs (do these first, in order)

### P1.1 — Wire SECURITY_CHANNEL in MainActivity.kt
**Status:** ✅ DONE
**File:** `raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt`
**Problem:** `SECURITY_CHANNEL = "com.raddflix.app/security"` is declared but has NO `setMethodCallHandler`. `AppGuard._checkSignature()` throws `PlatformException` which is silently caught → APK signature enforcement is completely inactive. A cracked APK with different signing cert passes all checks freely.
**Fix:** Add handler responding to `getSignatureFingerprint` (SHA-256 of APK signing cert), `isFridaRunning`, `isRooted` in `configureFlutterEngine()`.
**Verification:** Build APK, check CI green. On a modified APK, `AppGuard.isTampered` should become `true`.
**Impact:** HIGH — entire security model depends on this working.
**Estimated effort:** 30 min

---

### P1.2 — Fix bulk_link_engine.py stream_links SQL crash
**Status:** ✅ DONE (was false alarm — stream_links table + folder_share_url both exist in DDL)
**File:** `radd-hub/hub/bulk_link_engine.py` + `radd-hub/hub/db.py`
**Problem:** `BulkLinkEngine.refresh_links()` runs `SELECT * FROM stream_links ...` but `stream_links` table is NOT in `db.py` DDL. Throws `OperationalError: no such table: stream_links` every 2 hours (silently caught). JazzDrive link pre-generation never works.
**Fix Option A (recommended):** Add `stream_links` table to `db.py` DDL:
```sql
CREATE TABLE IF NOT EXISTS stream_links (
  file_id TEXT PRIMARY KEY,
  share_url TEXT,
  refreshed_at REAL
)
```
Then verify `bulk_link_engine.py` query matches this schema.
**Fix Option B:** If stream_links is meant to be replaced by `files.share_url`, refactor `bulk_link_engine.py` to update `files` table directly.
**Verification:** Check error logs on Oracle after deploy — no more `stream_links` errors.
**Impact:** MEDIUM — link pre-gen silently failing, fallback still works.
**Estimated effort:** 20 min

---

### P1.3 — Migrate password hashing to bcrypt
**Status:** ✅ DONE
**File:** `radd-hub/hub/routes/mobile_api.py`
**Problem:** `_hash_password(pw)` returns `hashlib.sha256(pw.encode()).hexdigest()` — no salt. All identical passwords have identical hashes. Rainbow table attacks expose all passwords on any DB breach.
**Fix:**
```python
import bcrypt

def _hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()

def _verify_password(pw: str, hashed: str) -> bool:
    return bcrypt.checkpw(pw.encode(), hashed.encode())
```
**Migration:** Existing users have SHA-256 hashes. On next login: detect if hash starts with `$2b$` (bcrypt) or not. If not bcrypt, verify old SHA-256 hash, then re-hash with bcrypt and save.
**Verification:** Register new user, check `password_hash` in DB — should start with `$2b$`. Login should still work. Existing users should still be able to login (migration path).
**Impact:** HIGH — security vulnerability.
**Estimated effort:** 2h (including migration path)

---

### P1.4 — Remove hardcoded IP from catalog_api.py
**Status:** ✅ DONE
**File:** `radd-hub/hub/routes/catalog_api.py`
**Problem:** `_watch_base()` has `return "http://92.4.95.252"` as fallback — hardcoded production IP + HTTP not HTTPS.
**Fix:** Return empty string as fallback (or read from a required env var). Callers must handle empty base URL gracefully.
```python
def _watch_base() -> str:
    try:
        v = (db.setting("WATCH_SERVER_EXTERNAL_URL") or "").strip()
        return v.rstrip("/")
    except Exception:
        return ""  # No hardcoded fallback
```
**Verification:** `grep -r "92.4.95.252" radd-hub/` should return no results in Python files.
**Impact:** MEDIUM — wrong URLs if IP changes, HTTP exposure.
**Estimated effort:** 10 min

---

## 🔶 PRIORITY 2 — Important Fixes (do after P1 is complete)

### P2.1 — Add FTS5 full-text search to search_api.py
**Status:** ⏳ PENDING
**File:** `radd-hub/hub/routes/search_api.py` + `radd-hub/hub/db.py`
**Problem:** Search uses `WHERE title LIKE '%q%'` — full table scan. Will be noticeably slow at 500+ titles.
**Fix:** Add FTS5 virtual table in DDL, populate on insert/update, use FTS in search route.
**Effort:** 1h

### P2.2 — Fix _ip_window memory leak in security_telemetry.py
**Status:** ✅ DONE
**File:** `radd-hub/hub/routes/security_telemetry.py`
**Problem:** `_ip_window` dict grows without bound under DoS from rotating IPs.
**Fix:** Prune keys where all timestamps are older than `_RATE_LIMIT_WINDOW` during the cleanup pass.
**Effort:** 15 min

### P2.3 — Add Frida + root detection to MainActivity.kt
**Status:** ✅ DONE (implemented alongside P1.1 in MainActivity.kt — checkFrida + checkRoot handlers active)
**Problem:** `_checkFrida()` and `_checkRoot()` in `AppGuard` silently fail because Kotlin handlers are missing.
**Fix:** Wire handlers in the same SECURITY_CHANNEL handler added for P1.1.
**Effort:** 30 min (do same session as P1.1)

### P2.4 — Enable XOR request encoding
**Status:** ⏳ PENDING
**File:** `raddflix_flutter/lib/core/security/request_encoder.dart` (set `enabled = true`)
**Problem:** Both Flutter and server side fully implemented but Flutter side is disabled.
**Note:** Must coordinate — enable both sides simultaneously to avoid breaking existing requests.
**Effort:** 30 min

### P2.5 — Fix mirror.py BUG-A18 (_legacy import)
**Status:** ⏳ PENDING
**File:** `radd-hub/hub/mirror.py`
**Problem:** Imports from `_legacy` module that may not exist on Oracle.
**Effort:** 30 min

### P2.6 — Ensure bcrypt/cryptography in requirements.txt
**Status:** ✅ DONE (bcrypt>=4.0 added; cryptography>=42.0 was already present)
**File:** `radd-hub/hub/requirements.txt`
**Check:** `bcrypt` must be listed; `cryptography` must be listed for keys.py Fernet.
**Effort:** 5 min

---

## 🔷 PRIORITY 3 — Cleanup (do after P2 is complete)

### P3.1 — Delete root lib/ stub files
**Status:** ⏳ PENDING
**Files:** Root `lib/*.dart`, root `pubspec.yaml`, root `pubspec.lock`
**Problem:** Dead code with wrong branding (JazzMAX/ZENO). Confuses developers.
**Action:** Delete via GitHub API (set file content to empty in tree, or remove from tree).
**⚠️ Get user approval before deleting files.**
**Effort:** 15 min

### P3.2 — Add bot state files to .gitignore
**Status:** ✅ DONE
**Files:** `radd-hub/bots/whatsapp/.gitignore` (create or update)
**Add:**
```
bot-state.json
users.json
pairing-number.txt
*.session
auth_info/
```
**Effort:** 5 min

### P3.3 — Replace placeholder supportWhatsApp number
**Status:** ⏳ PENDING (BLOCKED: need real number from user)
**File:** `raddflix_flutter/lib/core/constants.dart`
**Current:** `supportWhatsApp = '923001234567'`
**Action:** Ask user for real RaddFlix support WhatsApp number.
**Effort:** 5 min

### P3.4 — Deduplicate _extract_error + _friendly_error
**Status:** ⏳ PENDING
**Files:** `login_screen.dart` + `register_screen.dart`
**Fix:** Move to `core/utils/auth_utils.dart`.
**Effort:** 30 min

### P3.5 — Clean up legacy DB columns
**Status:** ⏳ PENDING (BLOCKED: needs schema migration + mobile app migration)
**Problem:** `titles` table has 11 redundant/legacy columns.
**Redundant:** `cast`, `cast_names`, `cast_json` (keep only `cast_json`), `overview` (duplicate of `plot`), `omdb_id` (duplicate of `imdb_id`).
**Note:** This requires a DB schema migration. Bump `catalogDbVersion` in constants.dart and add `_migrate()` case in `local_db.dart`.
**Effort:** 2h

### P3.6 — Fix dead product name in bulk_link_engine.py
**Status:** ✅ DONE (JazzBuzz → RaddFlix)
**File:** `radd-hub/hub/bulk_link_engine.py`
**Fix:** Replace "JazzBuzz" in docstring with "RaddFlix".
**Effort:** 2 min

### P3.7 — Update constants.dart documentation comment
**Status:** ⏳ PENDING
**File:** `raddflix_flutter/lib/core/constants.dart`
**Fix:** `otpDeviceSwitchEnabled` comment says "Set to true when..." but it's already `true`. Update comment to reflect actual state.
**Effort:** 5 min

---

## 🔹 PRIORITY 4 — Features / New Work (do after P3 is complete)

### P4.1 — Deploy full WhatsApp bot to production
**Status:** ⏳ PENDING
**Problem:** Supervisor runs `hub/bots/whatsapp/` (simple). Full-featured bot with plugins, rewards, actor/genre search is in `bots/whatsapp/` and not running.
**Action:** Update supervisor config to point to `bots/whatsapp/index.js`. Test.
**Effort:** 2h

### P4.2 — Wire recommendation API endpoint
**Status:** ⏳ PENDING
**File:** `radd-hub/hub/routes/mobile_api.py`
**Fix:** Add `GET /api/recommend?title_id=N` route that calls `radd_recommend.get_recommendations(title_id)`.
**Effort:** 30 min

### P4.3 — Fix Chromecast Gradle dependency
**Status:** ⏳ PENDING
**File:** `raddflix_flutter/android/app/build.gradle`
**Fix:** Add `implementation 'com.google.android.gms:play-services-cast-framework:21.4.0'`.
**Effort:** 15 min

### P4.4 — Runtime permission request for local media
**Status:** ⏳ PENDING
**File:** `raddflix_flutter/lib/screens/local_media_screen.dart`
**Fix:** Add `permission_handler` or use built-in `file_picker` permission flow to request `READ_MEDIA_VIDEO` at runtime before scanning.
**Effort:** 1h

### P4.5 — Enable share_url scrambling at rest
**Status:** ⏳ PENDING
**Files:** `local_db.dart` (write), `catalog_api.dart` (read + unscramble)
**Problem:** `RequestEncoder.scrambleUrl()` exists but is never called when writing to SQLite.
**Effort:** 2h

### P4.6 — Complete Telegram bot
**Status:** ⏸️ DEFERRED
**Files:** `radd-hub/hub/bots/telegram.py`, `radd-hub/hub/routes/bots.py`
**Effort:** 8h

### P4.7 — Surface domain_doctor.py findings in admin panel
**Status:** ⏸️ DEFERRED
**Effort:** 3h

---

## ✅ COMPLETED TASKS (historical)

| Phase | Task | Date | Notes |
|-------|------|------|-------|
| 1-5 | Flutter skeleton: auth, catalog, player, SQLCipher | 2026 early | Phases 1-5 |
| 6-10 | Downloads, vault, security, SIMOSA | 2026 | Phases 6-10 |
| 11-15 | Admin panel, subscriptions, TID, notifications | 2026 | Phases 11-15 |
| 16-20 | WhatsApp bot, analytics, zero-rating delta, metadata | 2026 | Phases 16-20 |
| 21-25 | XOR encoding, security telemetry, recommendations, player | 2026 | Phases 21-25 |
| 26-27 | Keystore migration (debug→release), CI green | 2026-05-30 | Commit be18ca4 |
| 28 | Full deep audit (359+ files), docs overhaul | 2026-05-31 | Commit dbde0fe |

---

## 📋 TASK WORKFLOW FOR AGENTS

```
1. Open this file
2. Find the first ⏳ PENDING task (top of P1)
3. Read the task description fully
4. Read CODE_MAP.md for the relevant files
5. Make the change
6. Commit via GitHub API
7. Verify CI passes
8. Change task status from ⏳ PENDING to ✅ DONE
9. Add entry to history/TASK_LOG.md
10. Update REINCARNATION.md "NEXT TASKS" section
11. Report to user: "P1.X done. [brief summary]. Proceed to P1.Y?"
12. Wait for user approval before starting next task
```

---

*End of MASTER_PLAN.md — 2026-05-31*
*Update this file after EVERY task completion.*

