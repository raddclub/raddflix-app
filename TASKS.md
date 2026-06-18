# RaddFlix Task Board
Last updated: 2026-06-18

## Completed Tasks — Player UX Session (2026-06-17)

### PLAYER-UX-01 through PLAYER-UX-08 ✅ — 8 MX Player Layout Improvements
**Files:** `raddflix_flutter/lib/screens/player_screen.dart`, `raddflix_flutter/lib/core/player/player_prefs.dart`
**Commits:** `01fc775f` (prefs) + `bd75f9d6` (screen)
**Status:** Completed 2026-06-17 | 25/25 verification checks passed

| # | Feature | Key Anchors |
|---|---------|-------------|
| 1 | Floating draggable ball | `_ballOffset`, `_sidebarMode`, play_circle_outline_rounded |
| 2 | Sidebar 3-state (full/icons/hidden) | chevron_right_rounded, `sidebarMode < 2` |
| 3 | Sidebar state persisted | `PlayerPrefs.sidebarMode`, SharedPrefs `sidebar_mode` |
| 4 | Clock overlay (top-right) | `_clockStr`, `_fmtTime()`, `_clockTimer` |
| 5 | Subtitle+Audio → right-side overlays | `width: 320`, black26 scrim |
| 6 | Speed picker → horizontal dot-rail | `_SpeedTrackPanel`, `#4DB6FF` |
| 7 | Default rotation → auto | `rotationMode = 'auto'` |
| 8 | `_MxSideBtn` icons-only | `iconsOnly` field, 36×36, icon 19px |

---

## Completed Tasks — 2026-06-17 Bug Fixes (commit 61f58908)

### BUG-BLACKSCREEN-LP ✅ — Long-press fast-forward leaves black frame
**File:** `raddflix_flutter/lib/screens/player_screen.dart`
**Priority:** HIGH
**Status:** Fixed 2026-06-17

**Root cause:** After `_player.setRate(2.5x)` on long-press, MPV drops frames during fast-forward to keep up. On long-press release, `setRate(1.0)` is called but MPV does not immediately decode a fresh frame — the surface stays black until the next natural keyframe arrives.

**Fix:** 80 ms after `onLongPressEnd`, seek to `_player.state.position` — this forces MPV to immediately decode and render a fresh frame, clearing the stale black surface.

---

### BUG-BLACKSCREEN-LOCAL ✅ — Local video black after ~2 seconds (hwdec race)
**File:** `raddflix_flutter/lib/screens/player_screen.dart`
**Priority:** CRITICAL
**Status:** Fixed 2026-06-17 (previous fix 2026-06-16 incomplete)

**Root cause:** `_loadPrefs()` runs async from `initState` and completes ~1-2 seconds after `_player.open()`. When it calls `_applyAudioPrefs()`, the guard was:
```dart
if (!_playing) { setProperty('hwdec', ...) }  // BROKEN
```
`_playing` is a Flutter state variable — it lags one `setState()` cycle behind actual MPV state. At the time `_loadPrefs` resolves, `_playing` is still `false` even though MPV already has an active decoder pipeline with a live GL surface. Setting `hwdec` mid-decode forces MPV to restart its decoder → GL surface destroyed → black screen.

**Fix:**
```dart
if (!_playing && !_player.state.playing && _player.state.duration == Duration.zero) {
  setProperty('hwdec', ...)
}
```
`_player.state.playing` and `_player.state.duration` are synchronous reads from MPV's actual state. `duration` becomes non-zero as soon as `_player.open()` is called — so the guard blocks any hwdec changes for the lifetime of any open media file.

---

### BUG-JAZZ-GENERIC-ERROR ✅ — Catalog movies always show "Jazz SIM Required"
**Files:** `raddflix_flutter/lib/screens/player_screen.dart`, `raddflix_flutter/lib/core/services/jazzdrive_service.dart`
**Priority:** HIGH
**Status:** Fixed 2026-06-17

**Root cause (2 stacked issues):**
1. **Dio threw on non-200 before code could inspect the body.** No `validateStatus` override on `_loginShare` or `_getMedia`. Any non-200 from JazzDrive (401, 403, 500) threw a `DioException` with no response body — the actual error reason was lost.
2. **HTML error pages crashed the JSON cast.** When the device is not on Jazz SIM mobile data, JazzDrive returns an HTML page. `_dio.post<Map<String, dynamic>>` tried to cast it and failed silently. The exception propagated as a meaningless Dart type error.
3. **All exceptions were shown as "Jazz SIM Required".** The `catch(e)` block in `_openMedia` discarded the exception and showed the same generic message regardless of whether the real cause was a bad share key, deleted content, timeout, or network error.

**Fixes applied:**
- `jazzdrive_service.dart` `_loginShare`: changed to `_dio.post<dynamic>` + `validateStatus: (s) => true`; added HTML-page detection (throws clear message); added safe JSON parse with try/catch
- `jazzdrive_service.dart` `_getMedia`: same treatment — `_dio.get<dynamic>` + `validateStatus` + HTML detection
- `player_screen.dart` `_openMedia`: capture exception as `_linkGenError`; pass to new `_buildJazzError()` helper
- `player_screen.dart` `_buildJazzError()`: translates raw exception strings into human-readable messages — MED-xxxx / FOL-xxxx error codes, HTTP 401/403, timeout, "no records", HTML page, invalid URL — each gets a specific message instead of the catch-all "Jazz SIM Required"

---

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

  ---

  ## Completed Tasks — PlaybackTimeline Diagnostics (2026-06-18)

  | ID | File | Summary |
  |----|------|---------|
  | ✅ FIX-VF-STARTUP | `player_screen.dart` | Synchronous `_videoOpened=true` before every `player.open()` — closes 200-500ms MediaTek race window |
  | ✅ FEAT-TIMELINE | `playback_timeline.dart`, `player_screen.dart`, `debug_diagnostics_screen.dart` | 10-probe startup tracer, 3s black screen auto-detector, Player tab in Diagnostics |
  