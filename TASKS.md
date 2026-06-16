# RaddFlix Task Board
Last updated: 2026-06-16

## Completed Tasks — Debug Diagnostics Screen

### TASK-DEBUG-01 ✅ — Add debug diagnostics screen accessible in release builds
**Files:** `raddflix_flutter/lib/screens/debug_diagnostics_screen.dart`, `profile_screen.dart`, `core/services/jazzdrive_service.dart`
**Priority:** HIGH
**Status:** Completed 2026-06-16 · Build 1053

**What was done:**
- Removed `if (!kDebugMode) return const SizedBox.shrink()` gate — screen now works in all builds (debug + release)
- Removed `if (!kDebugMode) return;` gate on version tap in `profile_screen.dart`
- Changed entry tap count from 7 → 5 (tap version text 5 times in Profile)
- Checks tab now auto-runs on open in all builds
- Changed AppBar badge from "DEBUG" to "DIAG"

**JazzDrive live test check added:**
- New `_checkJazzDrive()` check in Checks tab — picks first episode or movie from local SQLite, decodes share_url, runs the full `JazzDriveService.diagnosticTest()` chain live
- Shows each step: Login OK · VK= · .NODE= / Media OK · filename / URL prefix
- If any step fails, shows exact error message

**JazzDriveService.diagnosticTest() added:**
- New public static method in `jazzdrive_service.dart`
- Bypasses all caches — every step hits the actual JazzDrive API
- Returns `Map<String, dynamic>` with keys: `share_key`, `login`, `media`, `stream_url` (success) or `error` (failure)
- Called by `DebugDiagnosticsScreen._checkJazzDrive()`

**JAZZDRIVE log filter added:**
- `_filters` list updated: `['ALL', 'ERROR', 'WARN', 'JAZZDRIVE', 'API', 'SYNC', 'DB']`
- JAZZDRIVE filter uses `line.contains('[JAZZDRIVE]')` — special case (not padded to 5 chars)
- JAZZDRIVE log lines shown in green (`Color(0xFF34D399)`)

---

## Completed Tasks — JazzDrive Link Generation Fix

### TASK-JD-FIX-01 ✅ — Remove `validationkey=` from CDN stream URL
**File:** `raddflix_flutter/lib/core/services/jazzdrive_service.dart`
**Priority:** CRITICAL
**Status:** Fixed 2026-06-16

**Root cause:**
`_buildStreamUrl` was appending `&validationkey=<vk>` to the final CDN download URL.
The CDN authenticates via the self-signed `k=` token already embedded in the URL.
`validationkey` belongs only in SAPI calls (`/sapi/link/login`, `/sapi/media/video`).
Adding it to CDN URLs produced broken download/stream links.

**Fix applied:**
- Removed `validationKey` parameter from `_buildStreamUrl(rawUrl, filename)` — now 2 args not 3
- Removed `validationkey=` from URL construction
- Added `filename=` guard (no double-append if already present in rawUrl)

---

### TASK-JD-FIX-02 ✅ — Fix wrong comments in `jazzdrive_service.dart`
**File:** `raddflix_flutter/lib/core/services/jazzdrive_service.dart`
**Status:** Fixed alongside TASK-JD-FIX-01

---

### TASK-JD-FIX-03 ✅ — Correct `JAZZDRIVE_FLUTTER_AUDIT.md`
**File:** `agent-hub/JAZZDRIVE_FLUTTER_AUDIT.md`
**Status:** Fixed 2026-06-16

---

### TASK-JD-FIX-04 ✅ — Correct `JAZZDRIVE_STREAM_FLOW.md`
**File:** `agent-hub/JAZZDRIVE_STREAM_FLOW.md`
**Status:** Fixed 2026-06-16

---

### TASK-LOGIN-01 ✅ — Fix login screen: wrong password always navigated to home
**File:** `raddflix_flutter/lib/screens/login_screen.dart`
**Status:** Fixed 2026-06-16

**Root cause:** `auth_provider.login()` never throws. On wrong password it sets `state.error` and returns silently.
`_login()` only checked `isDeviceConflict`, not `state.error`, so it always reached `Navigator.pushReplacementNamed(home)`.

**Fix:** Added `if (s.error != null) { setState(() { _error = s.error; _loading = false; }); return; }` before navigation.

---

### TASK-CATALOG-STALE ✅ — Force full catalog re-sync on all devices
**Location:** Oracle DB `settings.catalog_forced_version`
**Status:** Done 2026-06-16

Bumped `catalog_forced_version` to `1781620750` — forces all devices to re-sync on next open,
overwriting stale share_urls and file_ids from old installs.

---

### TASK-JD-TEST-01 ✅ — JS logic test suite passes 27/27
**File:** `raddflix_flutter/test_suite/jazzdrive_logic_test.js`
**Result:** 27/27 ✅ (confirmed 2026-06-16)

---

### TASK-JD-LIVE ✅ — JazzDrive chain proven end-to-end with real video bytes
**Date:** 2026-06-16
**Evidence:**
- S01E01 (remote_id=242684631): HTTP 206, `video/mp4`, ftyp isom, 65536 bytes received ✅
- Euphoria movie (remote_id=242684377): HTTP 206, `video/mp4`, ftyp isom, 65536 bytes received ✅
- Both CDN URLs returned real streamable MP4 content — not redirects, not placeholders

---

## Architecture Reminder (for future agents)

```
Oracle server role:
  → Syncs content catalog (share URLs, metadata) to user's local SQLite DB
  → Handles JWT auth, history, quota
  → NO role in link generation or playback

Flutter app on-device (fully zero-rated on Jazz SIM):
  → Reads share_url from local SQLite (RF1-decoded)
  → POST /sapi/link/login  → validationkey + JSESSIONID   (cloud.jazzdrive.com.pk)
  → GET  /sapi/media/video → CDN URL with self-signed k=   (cloud.jazzdrive.com.pk)
  → Stream/download via k= CDN URL                         (cloud.jazzdrive.com.pk)
  → validationkey is ONLY used in the two SAPI calls above
  → validationkey is NEVER added to the final CDN stream URL
  → JSESSIONID .NODE suffix MUST be kept — LB uses it for sticky routing
```
