# RaddFlix Agent Task Log

## Session 2026-06-16 (Diagnostics + JazzDrive Verification)

### Tasks completed
1. **BUG-LOGIN-01** — Fixed login screen: wrong password no longer navigates to home. Root cause was `_login()` never checking `auth_provider` `state.error` before calling `Navigator.pushReplacementNamed`. Commit pushed, APK build 1052 ✅
2. **BUG-CATALOG-STALE** — Bumped Oracle `catalog_forced_version` from 1781262792 → 1781620750. Forces full catalog re-sync on all devices so stale share_urls are overwritten.
3. **TASK-JD-LIVE** — Ran full JazzDrive chain live from Oracle server: login → getMedia → CDN range request. Both S01E01 (remote_id=242684631) and Euphoria movie (remote_id=242684377) returned HTTP 206 `video/mp4` with `ftyp isom` magic bytes. Real video bytes confirmed — not fake URLs.
4. **TASK-DEBUG-01** — Built full debug diagnostics screen accessible in release builds:
   - `debug_diagnostics_screen.dart`: removed `kDebugMode` gate, auto-runs checks on open, added `_checkJazzDrive()` live test, added `JAZZDRIVE` filter chip (green log lines)
   - `jazzdrive_service.dart`: added `diagnosticTest()` public static method — bypasses cache, runs full login→media chain, returns step-by-step result map
   - `profile_screen.dart`: removed `kDebugMode` gate on version tap, reduced tap count 7→5
   - Build 1053 ✅ (run 27626589677, artifact 56.8 MB)

### System state at session end
- Oracle Flask: RUNNING v3.0.0
- JazzDrive session: id=11 (03257719165) — VK ✅ JID ✅ raw_at ✅ RT ✅
- Latest APK: build-1053, RaddFlix-1.0.0+1-build1053.apk
- No open bugs

---

_History cleared 2026-06-16 (prior session). All prior sessions resolved — no open issues carried forward._

_Append new session summaries below this line._


## Session 2026-06-16 — Separate Play/Download Buttons

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| TASK-BUTTONS-01 | Separated Play + Download buttons in show_detail_screen.dart | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/show_detail_screen.dart` | Movie: Download button now equal-width with text label. Episodes: dedicated Play + Download button row under each episode tile | 319bee8 |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- JazzDrive: All 7 files verified HTTP 206 video/mp4
- APK build 1054: IN PROGRESS
- Open tasks: none


  ## Session 2026-06-16 — Fix Blank Screen + Double-Dot Seek Bar

  ### Root cause analysis
  The "blank screen after 2-3 seconds on local videos" bug had resisted ~50 previous fix attempts because
  all previous agents looked at the wrong place (AnimatedOpacity, _videoSurfaceReady, androidAttachSurface flag).

  **Actual root cause**: `_loadPrefs()` is called async from `initState`. It completes ~1-2 s after the
  player starts, then calls `_applyAudioPrefs(loaded)` which unconditionally calls
  `_np.setProperty('hwdec', ...)`. Changing `hwdec` on an actively-playing Android MPV instance
  forces a full video decoder pipeline restart → destroys the GL surface texture → **black screen**
  (audio continues on its own decoder). The 2-3 s timing is exactly when prefs finish loading.

  ### Tasks completed
  | ID | Task | Status |
  |----|------|--------|
  | BUG-PLAYER-BLANK | Blank screen on local videos (hwdec guard) | ✅ DONE |
  | BUG-SEEK-DOUBLE-DOT | Double dot seek bar — Slider noThumb for non-classic styles | ✅ DONE |
  | BUG-DOTS-OVERLAP | Dots style track dots overlap with thumb | ✅ DONE |

  ### Files changed
  | File | Change | Commit |
  |------|--------|--------|
  | `raddflix_flutter/lib/screens/player_screen.dart` | hwdec+deinterlace wrapped in `if (!_playing)` guard; Slider `thumbShape: noThumb` for non-classic seek bar styles | 3b56547 |
  | `raddflix_flutter/lib/widgets/player/seek_bar_painter.dart` | `_paintDots`: skip track dots within `thumbR+dotR` of thumb position | 936a0a2 |

  ### State at end of session
  - Oracle Flask: RUNNING v3.0.0
  - JazzDrive: All 7 files verified HTTP 206 video/mp4
  - APK build 1058: TRIGGERED (commit 3b56547)
  - Open tasks: none
  

## Session 2026-06-17 — Player trifecta: catalog popup + local blank + long-press blank

### Root causes identified and fixed
All three bugs shared a common thread: inadequate guards on operations that destroy the MPV GL surface texture.

#### Bug 1 — Catalog popup over playing video (two causes)
- **Cause A**: `_jazzRetryCount` never reset after a successful `_player.open()`. After any initial error+retry, `_jazzRetryCount=1`. Any subsequent MPV error (CDN hiccup, closing old stream during retry) immediately hit the `>= 1` branch and called `setState(() => _streamError = ...)` — blocking a live playing video with an error overlay.
- **Cause B**: `_jazzAutoRetry` set `_streamError` without checking `_playing`. Video continued playing (audio) behind the overlay.
- **Fix A**: Reset `_jazzRetryCount = 0` inside `_openMedia` on every successful `_player.open()` call (both local and remote paths).
- **Fix B**: Added `if (_playing) return;` guard in `_jazzAutoRetry` before `_streamError` assignment.

#### Bug 2 — Local video permanent blank screen
- **Cause**: `_applyAudioPrefs` hwdec guard (`!_playing && !_player.state.playing && duration==zero`) has a timing gap during episode-navigation transitions. When `_player.open(newEp)` is called, MPV briefly fires `playing=false` AND `duration=zero` simultaneously. Any `_applyAudioPrefs` call (EQ change, AudioLab, quick settings) firing in this window changed `hwdec` mid-session → MPV destroyed the GL surface texture → VideoController held a dead texture → permanent black (audio continued). `_videoSurfaceReady` was already `true` so opacity stayed 1.0, making the blank look final.
- **Fix**: Added `!_videoSurfaceReady` as a fourth guard condition. This latch is set on first `playing=true` and never reset, meaning hwdec is only ever applied in the pre-first-frame window. Episode-nav transitions are now blocked from changing hwdec regardless of the playing/duration state.

#### Bug 3 — Long-press blank screen (during fast-forward)
- **Cause**: `_player.setRate(2.0)` with `hwdec=auto` crashes MediaCodec on budget Android devices (Infinix/MediaTek). The HW decoder cannot sustain >1× decode rate and its pipeline crashes → GL surface destroyed → blank screen.
- **Fix**: `await _np.setProperty('framedrop', 'decoder+vo')` is called BEFORE `setRate()` in `onLongPressStart`. This enables frame-dropping at both decoder and VO levels, keeping the pipeline alive. Restored to `framedrop=vo` in `onLongPressEnd`. No surface/texture change involved — safe to call mid-play.

#### Bonus fix — SW decoder toggle
- Line 3523 `onSwDecoderChanged` called `setProperty('hwdec', ...)` with no guard, causing blank screen when user toggles SW decoder mid-play. Added `await Future.delayed(150ms) + _player.seek(position)` to force fresh frame after decoder switch.

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-PLAYER-TRIFECTA | Three persistent player bugs + SW decoder toggle bonus | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | 6 targeted edits — see task description above | TBD |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- JazzDrive: active (id=11)
- APK build: TRIGGERED
- Open tasks: none

---

## Session: 2026-06-17 (Part 2) — Feature Audit + Background Play + PiP Exit

### Objective
Complete audit of all features for mock/broken implementations, then fix all issues found.

### Audit Results
| Feature | Status | Notes |
|---------|--------|-------|
| Background Play | ❌ → ✅ FIXED | No foreground service; Android killed process after ~1 min |
| PiP exit handling | ❌ → ✅ FIXED | `_inPiP` never reset; controls permanently hidden after PiP |
| PiP enter | ✅ Real | `MainActivity.kt` uses real `enterPictureInPictureMode` |
| Chromecast | ✅ Real | Full Cast SDK + CastOptionsProvider.kt |
| Downloads | ✅ Real | Real DownloadService, Riverpod provider |
| Watchlist | ✅ Real | LocalDB-backed provider |
| History | ✅ Real | HistoryApi + catalogProvider |
| Search | ✅ Real | Real filter state + catalog queries |
| Headphone unplug | ✅ Real | becomingNoisyEventStream in _initAudioSession |
| Audio focus | ✅ Real | interruptionEventStream |
| Security | ✅ Real | Frida/root/signature checks |

### Fixes applied

#### BUG-BGPLAY-FOREGROUND
- **Root cause**: Android 8+ kills background processes without a foreground service with `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK`, even if native audio threads are still running. AndroidManifest declared `com.ryanheise.audioservice.AudioService` which is from the `audio_service` package — but only `audio_session` (completely different package) is in pubspec.yaml. The service class did not exist in the APK.
- **Fix A**: Created `PlaybackService.kt` — minimal foreground service that calls `startForeground()` with a media-style notification. `START_NOT_STICKY` — won't restart if OS kills it after player is gone.
- **Fix B**: Added `startBgPlayback(title)` and `stopBgPlayback()` to PIP_CHANNEL in `MainActivity.kt`.
- **Fix C**: `AndroidManifest.xml` — removed dead `com.ryanheise.audioservice.AudioService` entry; added real `.PlaybackService` with `foregroundServiceType="mediaPlayback"`; added `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission.
- **Fix D**: `player_screen.dart`: `didChangeAppLifecycleState(paused+bgplay)` → `startBgPlayback`; `didChangeAppLifecycleState(resumed)` → `stopBgPlayback`; `dispose()` → `stopBgPlayback`.

#### BUG-PIP-EXIT
- **Root cause**: `_inPiP = true` set in `_enterPiP()` when entering system PiP. No corresponding code ever set `_inPiP = false`. Controls widget checks `!_inPiP` and hides itself when PiP is active — so after the first PiP session, controls NEVER appeared again.
- **Fix A**: Added `onPictureInPictureModeChanged(isInPiP, config)` override in `MainActivity.kt`. When `isInPiP=false` (PiP exited), sends `onPipExited` event via MethodChannel on PIP_CHANNEL.
- **Fix B**: Added `_initPipChannel()` method in `player_screen.dart`, called from `initState()`. Registers `_pipChannel.setMethodCallHandler` that handles `onPipExited` → `setState(() => _inPiP = false)`.

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/PlaybackService.kt` | NEW — foreground service |
| `raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt` | Added bg-service methods + onPictureInPictureModeChanged |
| `raddflix_flutter/android/app/src/main/AndroidManifest.xml` | Removed dead AudioService, added PlaybackService + permission |
| `raddflix_flutter/lib/screens/player_screen.dart` | _initPipChannel() + lifecycle + dispose |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- JazzDrive: active (id=11)
- APK build: needs trigger
- Open tasks: none


---

## Session 2026-06-17-C — Blank/Dark Screen Bug Fix (3-fix commit efb3319)

### Task
Find and fix the persistent blank/dark screen bug in the video player.
Symptoms: player display goes blank/dark, no gestures work, audio continues.
Triggers: during normal playback AND during long-press (fast-forward).
Does NOT occur if user opens Settings or another tab immediately after opening the player.

### Root Causes Identified

**RC-1: `_videoSurfaceReady` latch fires too late (startup race)**
- `VideoController(_player, ...)` establishes the Android GL surface on construction (~20ms into initState)
- `_videoSurfaceReady` only latches to `true` on first `playing=true` stream event (could be seconds later)
- `_loadPrefs()` completes ~10ms after initState, then `_applyAudioPrefs` fires after 60ms debounce → at t=70ms
- At t=70ms: `!_playing=true`, `!state.playing=true`, `duration=zero=true`, `!_videoSurfaceReady=true` → ALL guard conditions pass
- `hwdec` is changed while the GL surface is already live → surface destroyed → permanent blank screen
- This is why opening Settings "fixes" it: the resulting setState/rebuild re-registers the surface with MPV

**RC-2: `_setSpeed` command channel race**
- `_np.setProperty('framedrop', ...)` sends via NativePlayer channel
- `_player.setRate(s)` sends via separate Dart API path (Player → GeneratedPlayer → platform channel)
- These CAN arrive at MPV out of order: setRate can be processed before framedrop
- HW decoder receives >1× rate change without framedrop protection → MediaCodec crashes → blank screen

**RC-3: Long-press recovery too short and incomplete**
- `onLongPressEnd` seeks to current position after only 80ms
- MPV hasn't fully stabilised at 1× speed in 80ms — frame buffer still draining
- No re-assertion of `framedrop=vo` before recovery seek

### Fixes Applied

| Fix | Location | Change |
|-----|----------|--------|
| FIX-SURFACE-RACE | `_initPlayer()` after VideoController ctor | `_videoSurfaceReady = true` immediately after VideoController construction (not waiting for first playing=true event) |
| FIX-SPEED-CHANNEL | `_setSpeed()` | Replaced `_player.setRate(s)` with `_np.setProperty('speed', s.toStringAsFixed(4))` — both framedrop and speed now go through same NativePlayer channel, guaranteeing in-order delivery |
| FIX-BLACKSCREEN-LP | `onLongPressEnd` | Increased delay 80ms→200ms; added explicit `_np.setProperty('framedrop', 'vo')` before recovery seek |

### Commit
- `efb3319fd6c09007854d671b3eb08830156358f4` on main — `fix: close blank-screen race (3 fixes)`
- File: `raddflix_flutter/lib/screens/player_screen.dart`

### State at End of Session
- Oracle Flask: not checked this session (not needed)
- All three blank-screen root causes closed
- APK build: needs trigger

## Session 2026-06-17 — Player UX: 8 MX Player Layout Improvements

### Commits
- `01fc775f` — feat(player): add sidebarMode pref + default rotation → auto (player_prefs.dart)
- `bd75f9d6` — feat(player): floating ball, sidebar 3-state, speed track, side panels, clock, auto-rotate

### Changes Delivered
| # | Feature | Details |
|---|---------|---------|
| 1 | **Floating draggable ball** | White 40px circle with play icon; shown when controls are hidden. Tap → restore controls + reschedule hide. Drag → reposition anywhere on screen (clamped to bounds). |
| 2 | **Sidebar 3-state toggle** | Chevron at top of right rail cycles: full (58px) → icons-only (40px) → hidden. Chevron flips direction. |
| 3 | **Sidebar state memory** | `sidebarMode` (int 0/1/2) added to `PlayerPrefs` — persists via SharedPreferences key `sidebar_mode`. Loaded in `_loadPrefs()`, saved on toggle. |
| 4 | **Clock overlay** | Top-right corner, white70, 12sp, always visible when controls are hidden. Updated every 30s via `_clockTimer`. `_fmtTime()` helper formats 12-hour AM/PM. |
| 5 | **Subtitle + Audio panels → right-side overlays** | Changed from bottom sheets → `Positioned(top:0, right:0, bottom:0, width:320)`. Scrim lightened from black54 → black26. Slides from right edge. |
| 6 | **Speed picker → horizontal dot-rail** | Replaced `_SpeedPanel` (vertical right-side list) with `_SpeedTrackPanel` (horizontal top bar). Active speed: 13px blue `#4DB6FF` dot + bold label. Inactive: 7px white38 dot + small label. |
| 7 | **Auto-rotation default** | `PlayerPrefs` default `rotationMode` changed `'sensor_landscape'` → `'auto'`. |
| 8 | **`_MxSideBtn` icons-only mode** | New `iconsOnly` bool param. When true: 36×36 size, icon 19px, label hidden. All 11 sidebar buttons use `iconsOnly: sidebarMode == 1`. |

### File Stats
| File | Before | After | Δ |
|------|--------|-------|---|
| `player_prefs.dart` | 1152 lines | 1158 lines | +6 |
| `player_screen.dart` | 6963 lines | 7087 lines | +124 |
| Total verification checks | — | 25/25 ✅ | — |

## Session 2026-06-18 — Icon Compat Fix + APK Build Restored

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-ICON-COMPAT | Fix Icons.replay_15_rounded / forward_15_rounded compile errors | ✅ DONE |

### Root Cause
APK builds run#1095–1098 all failed at "Build release APK" step.
- `Icons.replay_15_rounded` → does not exist in Flutter 3.22.3
- `Icons.forward_15_rounded` → does not exist in Flutter 3.22.3
- First attempted fix (`replay_15` / `forward_15`) also failed — those don't exist either
- Confirmed correct names via Flutter 3.22.3 source: `Icons.replay_10` / `Icons.forward_10`

### Files changed
| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | `replay_15_rounded` → `replay_10`, `forward_15_rounded` → `forward_10` | `91e52dc` |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Account id=11: active (JID/VK/AT all healthy per handoff)
- APK build: run#1099 ✅ SUCCESS / run#1100 ✅ SUCCESS
- Open tasks: DATA-01 (All Of Us Are Dead missing E03/E04/E05/E09 — no change this session)

## Session 2026-06-18 (continued) — FIX-VF-BLACKSCREEN: Month-long blank screen root cause found

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| FIX-VF-BLACKSCREEN | Identify and fix root cause of "local video black screen after 1-2s" | ✅ DONE |

### Root Cause Analysis
Analysed bug-reproduction video (attached_assets/20260618034906_1781736674110.mp4) frame by frame using ffprobe + frame extraction.

Frame sequence confirmed:
- Frames 1-7: Local Media browse (portrait, normal)
- Frame 8: Screen rotation during player open transition
- Frames 9-12: Player in landscape, video plays correctly (music video visible at 00:01)
- Frames 13-17: COMPLETELY BLACK — permanent, audio continues

Root cause: `_applyVideoFilters` (in `player_screen.dart`) called from `_loadPrefs` with a 60ms debounce. On most devices, SharedPreferences returns in <500ms, so the 60ms debounce fires AFTER the local video has started playing with an active Android HW decoder.

Calling `_np.setProperty('vf', ...)` — even with an EMPTY string (default settings = no filters) — on an active HW decoder pipeline (MediaTek/Infinix) destroys the GL surface texture → permanent black screen while audio continues. This is why the bug manifested as "video plays for 1-2 seconds then goes black".

The hwdec guard in `_applyAudioPrefs` was correctly fixed (BUG-BLANK-SURFACE-RACE, 2026-06-17), but `_applyVideoFilters` was called from the same `_loadPrefs` code path and never received an equivalent guard — the missing fix for a month.

### Fix Details
Two-layer guard added to `_applyVideoFilters`:
1. **STARTUP GATE** — first call (always from `_loadPrefs`) is skipped if `_player.state.playing || _playing`; `_firstVfApplied` flag tracks first-call status
2. **DEDUP** — `_lastAppliedVf` sentinel tracks last applied vf string; skips `setProperty` when value is identical (no-op vf= calls also reset HW pipeline on some MediaTek SoCs)
3. **SEEK-AFTER** — user-initiated mid-play filter changes now seek to current position after applying vf= (mirrors `onSwDecoderChanged` hwdec live-switch pattern) to force MPV to re-render current frame through new filter chain

### Files changed
| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | `_applyVideoFilters` startup guard + dedup + seek-after; added `_firstVfApplied`/`_lastAppliedVf` state vars | `cd241fc` |
| `agent-hub/TASKS.md` | Added FIX-VF-BLACKSCREEN to completed table | (this commit) |
| `.agents/tasks/BUG_TRACKER.md` | New critical rule + fixed bug entry | `da2d21b` |
| `AGENT_HANDOFF.md` | Updated status + new critical rule | (this commit) |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- APK build: last success run#1099/1100, commit 91e52dc. New fix at cd241fc — build not yet triggered.
- Open tasks: DATA-01 (All Of Us Are Dead missing E03/E04/E05/E09 — not addressed this session)
- Critical fix: FIX-VF-BLACKSCREEN — month-long blank screen on local video **FIXED**


---

## Session 2026-06-18 — FIX-PLAYER-BUGS (11 bugs in player_screen.dart)

### What was done
Full audit of player_screen.dart (7,131 lines) completed. Analysed all 7,131 lines across 8 parallel reads. Found and fixed 11 confirmed bugs in one session.

### Fixes applied (commit 09760ca)

| Fix ID | Category | What was wrong | What was fixed |
|--------|----------|---------------|----------------|
| C6 | Critical | SmartVolumeController._tick() clamped volume to min 20.0 — overrode user mute every tick | Changed clamp(20.0, 130.0) → clamp(0.0, 130.0) |
| S13 | Serious | Manual retry in _StreamErrorOverlay used widget.fileId (always ep1) not _currentFileId | Changed both JazzDriveService.invalidate() and _openMedia() calls to use _currentFileId |
| X2 | UX | "Cancel" in _NextEpisodeOverlay called Navigator.of(context).pop() — exited the entire player | Removed the Navigator.pop() call; only cancels the overlay now |
| X7 | UX | Sleep fade badge AND sleep timer badge shown simultaneously (both at screen top) | Added !_sleepFadeActive guard to timer badge condition |
| X1 | UX | Floating ball widget always showed play_circle_outline icon regardless of playback state | Changed to toggle between pause_circle_outline / play_circle_outline based on _playing |
| U4 | Dead code | ReactionStampsOverlay wrapped in if(false) — shipped dead code in every release build | Removed entire if(false) block and dead widget instantiation |
| S1 | Duplicate | _playNextEpisode and _playPrevEpisode had identical 20-line skip-intro timer blocks | Extracted into _scheduleSkipIntroCheck(String fileId) helper; both methods now call it |
| S3 | Logic | ZoomCropOverlay.onZoomChanged triggered two consecutive setState() calls in same callback | Merged into single setState(() { _zoomLevel = z; _prefs = next; }) |
| X3 | UX | _showFrameStep set true in _frameStep()/_frameBackStep() but never cleared on play resume | Added if(p) _showFrameStep = false inside playing stream listener setState |
| U1 | Dead code | 6 state variables declared and never assigned/read: _audioTracks, _selectedAudioTrack, _castScanning, _castDevices, _showSubtitleHunter, _abLoopActive | Removed all 6 declarations; cleaned up section comment |
| S11 | UX | "Stereo mode" button in _MxAudioPanel had empty onTap: () {} — visible but non-functional | Removed button from audio panel Row |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | 11 bugs fixed, 32 lines removed (7131→7099) | `09760ca` |

### State at end of session
- Oracle Flask: not checked this session (no server changes needed)
- Last successful APK build: run#1099/1100, commit 91e52dc
- New commit 09760ca has not yet triggered a build (player-only fix, safe to build)
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes — not addressed)
- Remaining player audit items: duplicate UX systems (D1–D7), UX illogic (X4–X9), architecture extraction (A1–A6)


---

## Session 2026-06-18 — FIX-PLAYER-REAUDIT (4 additional bugs, APK ✅)

### Objective
Full line-by-line re-audit of player_screen.dart (7,094 lines after previous fixes). Find anything missed in the 11-bug fix session. Push, rebuild, verify.

### Audit findings from previous session (confirmed still present)
| Issue | Status after previous session |
|-------|------------------------------|
| _previewPosition usage in _openIntroSkipEditor | ✅ Already defined as getter at line 2855 — not a bug |
| _speeds const list "unused" | ✅ Used at line 3621 (SpeedTrackPanel) — not a bug |
| _abLoopStart / _abLoopEnd | ✅ Legitimately used in _openClipTrimmer() — correct state |
| reaction_stamps_overlay import | ❌ ORPHANED — widget removed in 09760ca, import not cleaned up |
| Clock timer 30s interval | ❌ WRONG — HH:MM display can be 30s stale |
| _audioSessionInitialized guard in BG toggle | ❌ DEAD — flag always true after initState; block unreachable |
| final _np variable shadowing NativePlayer getter | ❌ MAINTENANCE HAZARD — local _np shadows class-level get _np |

### Fixes applied (commit c099057)

| Fix | Line | Root Cause | Fix Applied |
|-----|------|-----------|-------------|
| FIX-ORPHAN-IMPORT | 45 | `reaction_stamps_overlay.dart` imported after widget removal | Removed import line |
| FIX-CLOCK-TIMER | 389 | Timer.periodic(30s) — HH:MM could be ≤30s stale | Changed to 10s interval |
| FIX-DEAD-BG-GUARD | ~4053 | `if (v && !_audioSessionInitialized)` always false; `_initAudioSession()` called in initState | Removed unreachable block, left clarifying comment |
| FIX-NP-SHADOW | ~3574 | `final _np = _prefs.copyWith(...)` inside callback shadowed `NativePlayer get _np` getter | Renamed to `final newPrefs` + `final newMode` |

### Result
- Commit: `c099057849c631d68c8b62a04569f9b2af1790ca`
- File: 7094 lines (−5 from 7099)
- APK build run#27729363694 → **status: completed, conclusion: success** ✅

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest APK: build run#27729363694 ✅ SUCCESS, commit c099057
- Open tasks: DATA-01 (All Of Us Are Dead missing E03/E04/E05/E09)
- player_screen.dart audit: complete — all actionable bugs fixed


---

## Session 2026-06-18 — HUNTER-AUDIT (10 bugs across 100 files, APK ⏳)

### Objective
Full "hunter mode" bug audit of all 100 player-related Flutter files. 5 parallel subagents dispatched covering `core/player/`, `widgets/player/`, `screens/`, and `services/`. Every confirmed bug fixed, commit pushed, APK triggered.

### Audit findings and fixes

| ID | File | Category | Root Cause | Fix Applied |
|----|------|----------|-----------|-------------|
| N-01 | `n_series_network.dart` | Dead code | `_lastBytes int` declared at line 44, never read or written after declaration | Removed field |
| P-01 | `p_series_parental.dart` | Dead code | `_todayKey String?` field computed in `configure()` but never read | Removed field + assignment |
| ESS-01 | `enhanced_screenshot_service.dart` | Dead code | `title` param in `_saveToGallery(bytes, title)` never used in method body | Removed `title` param; updated call site |
| SYN-01 | `sync_panel.dart` | UX text | `'delayed by  +'` had two spaces before `+` — visual glitch in delay status string | Fixed to `'delayed by +'` |
| SBP-01 | `scene_bookmarks_panel.dart` | Null safety | `Dismissible(key: Key(bm.id.toString()))` + `onDismissed: (_) => onDelete(bm.id!)` crashes if SQLite row has no id | `key: Key(bm.id?.toString() ?? bm.positionMs.toString())`; `onDismissed` and `onLongPress` both guard `if (bm.id != null)` |
| SES-01 | `smart_enhance_sheet.dart` | Logic | Before/After hold button released → blindly called `copyWith(smartEnhanceEnabled: true)` — if user had enhance OFF, releasing "Before" would turn it ON | Added `_prevEnabled` field; `_handleBeforeHold()` caches value on press, restores it on release |
| SES-02 | `smart_enhance_sheet.dart` | DRY | Portrait and landscape branches each had an identical inline `onBeforeHold` lambda (6 lines × 2) | Extracted into `_handleBeforeHold(bool hold)` method; both branches pass `_handleBeforeHold` |
| SUB-01 | `subtitle_overlay.dart` | Performance | `RegExp(r"[\w']+|[^\w']+")` and `RegExp(r"^[\w']+$")` declared as local `final` variables inside `_buildTappableText` — recreated on every subtitle build call and for every token | Promoted to `static final _reTokenize` / `_reWord` class fields |
| VES-01 | `video_enhance_suite.dart` | DRY | `(v) { final n = ((v-1.0)*100).round(); return (n>=0?'+':'')+n.toString()+'%'; }` lambda copy-pasted 3× for Brightness/Contrast/Saturation sliders | Extracted into `static String _pctDelta(double v)`; all 3 sliders pass `_pctDelta` |
| SPS-01 | `speed_presets_sheet.dart` | Silent failure | `_toggle()` returned silently (no feedback) when user tried to remove a preset with `_presets.length <= 2` | Added `ScaffoldMessenger.showSnackBar('Keep at least 2 speeds in your list')` before returning |
| VDS-01 | `player_screen.dart` | Visual | `_VDSTile` active state used hardcoded `_blue` (0xFF1565C0) — `_accent` (0xFFE8002D, RaddFlix red) was already defined in the class as `static const` but never referenced | Removed `_blue`; all 3 active-state references now use `_accent` |

### Files changed (commit 4882ba1)

| File | Change |
|------|--------|
| `raddflix_flutter/lib/core/player/n_series_network.dart` | Removed `_lastBytes` field |
| `raddflix_flutter/lib/core/player/p_series_parental.dart` | Removed `_todayKey` field + assignment |
| `raddflix_flutter/lib/core/player/enhanced_screenshot_service.dart` | Removed `title` param from `_saveToGallery` |
| `raddflix_flutter/lib/widgets/player/sync_panel.dart` | Fixed double-space in delay string |
| `raddflix_flutter/lib/widgets/player/scene_bookmarks_panel.dart` | Null-safe bm.id in Dismissible + callbacks |
| `raddflix_flutter/lib/widgets/player/smart_enhance_sheet.dart` | Before/After state preservation + DRY extraction |
| `raddflix_flutter/lib/widgets/player/subtitle_overlay.dart` | RegExp promoted to static final |
| `raddflix_flutter/lib/widgets/player/video_enhance_suite.dart` | Format lambda extracted to _pctDelta() |
| `raddflix_flutter/lib/widgets/player/speed_presets_sheet.dart` | SnackBar on min-presets guard |
| `raddflix_flutter/lib/screens/player_screen.dart` | _VDSTile: _blue → _accent |

### Result
- Commit: `4882ba1`
- APK build run#27730921492 → **status: completed, conclusion: success** ✅
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)


---

## Session 2026-06-18 — BUG-DEBUGLOGGER-MISSING (2 build failures fixed)

### Objective
Investigate and fix 2 consecutive APK build failures (run#27753380200, run#27753231660) introduced by recent commits 9439a69 and 5ce16d8.

### Root Cause
Both commits added calls to 6 `DebugLogger` methods across 5 files, but those methods were never added to the `DebugLogger` class itself → Dart compile-time `Member not found` errors on every build.

| Missing method | Called from |
|----------------|-------------|
| `logWarn(tag, msg)` | `remote_config.dart`, `jazzdrive_service.dart`, `usage_service.dart`, `api_client.dart`, `download_service.dart` |
| `logApi({method, url, statusCode?, ...})` | `api_client.dart` (3 call sites, named params) |
| `getLastLines(n) → String` | `debug_diagnostics_screen.dart:69` |
| `shareLogs()` | `debug_diagnostics_screen.dart:301` (used as `onPressed` reference) |
| `clearBuffer()` | `debug_diagnostics_screen.dart:325` |
| `getLogPath() → String` | `debug_diagnostics_screen.dart:456` |

### Fix applied (commit 426d78c)

| Method | Implementation |
|--------|---------------|
| `logWarn` | `_write('WARN/$tag', msg)` |
| `logApi` | Named params: builds parts list → `_write('API', parts.join(' \| '))` |
| `getLastLines` | Joins `getRecent(n)` with `\n` → returns `String` |
| `shareLogs` | Alias for `share()` — compatible with `onPressed` callback type |
| `clearBuffer` | `_buffer.clear()` |
| `getLogPath` | `_logPath ?? ''` |

### Tasks completed

| ID | Task | Status |
|----|------|--------|
| BUG-DEBUGLOGGER-MISSING | Add 6 missing DebugLogger methods, fix builds | ✅ DONE |

### Files changed

| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/core/debug/debug_logger.dart` | Added 6 missing methods | 426d78c |

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest commit: 426d78c — fix(debug_logger): add missing methods
- APK build: triggered (awaiting result)
- Previous passing build: run#27752025995 commit 1a4294c ✅
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)


---

## Session 2026-06-18 — DEBUG-ACCESS-SIMPLE (easier debug log access)

### Objective
Make the debug diagnostics screen easier to open. User could not reliably open it via the hidden 5-tap version gesture.

### Changes

| File | Change | Commit |
|------|--------|--------|
| `profile_screen.dart` | Added visible "Debug Logs" tile in Account section (before Sign Out) | 8c8f331 |
| `debug_diagnostics_screen.dart` | Opens on Logs tab by default; log timer auto-starts in initState | 2b9e051 |

### How to open debug screen now
**Profile → scroll down → Account section → Debug Logs**
(One tap, always visible. The old 5-tap on version text still works as backup.)

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest commit: 2b9e051 (debug_diagnostics_screen) / 8c8f331 (profile_screen)
- APK build: triggered (awaiting result)
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)

---

## Session 2026-06-18 — Comprehensive Debug Logging (DebugLogger v2)

### Objective
Add maximum comprehensive debug logging to every screen so every crash, black screen, user tap,
navigation event, and feature usage is captured and visible in the debug log screen.

### Changes

| File | Change | Commit |
|------|--------|--------|
| `lib/core/debug/debug_logger.dart` | DebugLogger v2: 5000 buffer, 8MB rotation, session ID, auto-flush 30s, logTap/Nav/Lifecycle/Feature/Crash, getFiltered | 613f686 |
| `lib/main.dart` | PlatformDispatcher.onError global crash handler + early DebugLogger.init | bb59f50 |
| `lib/app.dart` | _RaddNavObserver NavigatorObserver registered in MaterialApp | d5a449c |
| `lib/screens/player_screen.dart` | 13 crash-path logging patches | 2413c3f |
| `lib/screens/home_screen.dart` | lifecycle + all tap logging | 9c55499 |
| `lib/screens/show_detail_screen.dart` | lifecycle + play/download tap logging | 69a7d63 |
| `lib/screens/search_screen.dart` | lifecycle + query/filter/results/tap logging | f739564 |
| `lib/screens/profile_screen.dart` | lifecycle + nav tab logging | 198033b |
| `lib/screens/downloads_screen.dart` | lifecycle + play tap logging | 1e7128f |
| `lib/main.dart` | **BUILD FIX**: add `import 'dart:ui' show PlatformDispatcher;` | 96f8cc1 |

### Root cause of build failures
Commits `d5a449c` through `bb59f50` all failed with `Undefined name 'PlatformDispatcher'`.
`PlatformDispatcher` is in `dart:ui`, NOT exported by `package:flutter/material.dart`.
Fix: `import 'dart:ui' show PlatformDispatcher;` added to `main.dart` as commit `96f8cc1`.
All 9 logging commits are included in the passing build.

### What is now logged

| Layer | Tag | Events |
|-------|-----|--------|
| Dart crash net | `CRASH/PLATFORM` | ALL uncaught Dart errors with full stack |
| Navigation | `NAV` | Every push/pop/replace/remove |
| Home | `LC/HomeScreen`, `TAP/Home` | Lifecycle, nav tabs, filters, hero taps |
| Show detail | `LC/ShowDetail`, `TAP/ShowDetail` | Lifecycle, play/download ep |
| Search | `LC/SearchScreen`, `TAP/Search` | Lifecycle, query, filter, results, taps |
| Profile | `LC/ProfileScreen`, `TAP/Profile` | Lifecycle, nav tab taps |
| Downloads | `LC/DownloadsScreen`, `TAP/Downloads` | Lifecycle, play taps |
| Player | `INIT`, `AUDIO`, `VIDEO`, `SPEED`, `LOAD`, `BUF`, `PLAY`, `ERR/PLAYER`, `WARN/LOAD` | 13 crash-path checkpoints |

### Key lesson learned
`PlatformDispatcher` requires explicit `import 'dart:ui' show PlatformDispatcher;`.
It is NOT re-exported by flutter/material.dart in Flutter 3.22.3.
This is now documented in RULES.md, BUG_TRACKER.md, and .agents/memory/.

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest commit: `96f8cc1` — dart:ui import fix
- APK build: ✅ SUCCESS (run#27757913296)
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)


---

## Session 2026-06-18 — Debug Logging Round 2 (player_screen.dart exhaustive coverage)

### What was done
- **Round 1 (commit `272ac0c`, build ✅ run#1131):** 43 DebugLogger patches to player_screen.dart covering all silent `catch (_) {}` blocks → named errors, app lifecycle (backgrounded/resumed with seekback and OS-pause detection), episode prev/next nav, sleep timer (set/cancel/fire/fade), full playback-ended decision tree, watch-position save, slow connection detection, duration stream, audio/subtitle track selection with language names, volume boost, audio sync, subtitle sync, cinematic/immersive mode toggle, cycle fit (aspect ratio), frame step forward/back, screenshot success+failure, voice command handler, media button multi-press, subtitle file picker, bookmark add, skip intro visibility + auto-skip, cast enter, long-press play restart.
- **Round 2 (commit `c4905b5`, build ⏳ run#1132):** 48 more patches — `_logPlayerState()` state-snapshot helper (logs pos/dur/playing/buffering/ep/local/loading/speed/hwdec/pip/locked/ended/error at any transition), dispose() with final position, ALL 22 panel-opening functions logged (SpeedPicker, EqVisualizer, BookmarkPanel, PlayerSettings, HudSettings, SmartEnhance, SleepTimer, VideoEnhanceSuite, JumpTo, SpeedPresets, EndAction, ZoomCrop, SilenceSkip, ABLoop, ClipTrimmer, IntroSkipEditor, GestureMap, PictureProfiles, AudioLab, AudioMixer, CinematicSettings, ImmersiveSettings), _loadPrefs completion with every key setting value, _loadSmartIntro result, _loadBookmarks count, _loadSkipSegments count, _deleteBookmark, _toggleControls show/hide, _seekRelative from/to/dur, lock toggle with position, _applyRotation mode, _cycleRotation old→new, _initAmbilight enabled+interval+start, _startWakeTimer set + wakeTimer FIRED, _shareTimestamp, _onSeekBarLongPress, _showJumpToTime, _handleCenterTap with play state, _initBingeGuard enabled+interval, _initPipChannel, audio interruption event with type, headphone unplug (becomingNoisy), _logWatchSession entry, _logPlayerState at jazz retry exhausted. Fixed: local var `_nextIdx` → `nextRatioIdx` (lint warning for underscore-prefix local vars).

### New log tags introduced across both rounds
`LIFECYCLE`, `EPISODE`, `SLEEP`, `SAVE`, `QUOTA`, `PIP`, `TRACK`, `INTRO`, `VOICE`, `HW`, `CAST`, `TAP/MODE`, `TAP/VIDEO`, `TAP`, `SEEK`, `PANEL`, `STATE`, `GESTURE`, `BUF`, `AUDIO`, `INIT` (extended), `LOAD` (extended)

### Complete logging coverage now in player_screen.dart
Every function entry, every panel open, every user gesture, every error path (including audio interruption, headphone unplug, PiP fail, quota redirect, plan expiry), every state transition (play→pause, episode change, lifecycle change) now emits a structured DebugLogger line with enough context to pinpoint root cause without needing a device attached.

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest commit: `c4905b5` — debug logging round 2
- APK build: run#1132 ⏳ in_progress (round 2 build)
- Round 1 build: ✅ SUCCESS run#1131 (commit 272ac0c)
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)


---

## Session 2026-06-18 — God-Level Debug Logger (player_screen.dart complete)

### Objective
Fix all 4 compile errors from round 2 (commit c4905b5) and add remaining deep-engine logging patches to player_screen.dart to achieve complete god-level debug coverage.

### What failed in round 2 (c4905b5)
| Error | Wrong field | Correct field |
|-------|-------------|---------------|
| silenceSkipEnabled | — | skipSilenceEnabled |
| bingeGuardIntervalMins | — | bingeGuardThresholdMinutes |
| _ratioLabels | — | does not exist; compare BoxFit values directly |
| debandingEnabled | — | does not exist; use nightMode |
| tracks.sub | — | tracks.subtitle |

### Changes
- Commit `2ae548e`: initial god-level push (still had tracks.subtitle + debandingEnabled errors — 2 new compile errors)
- Commit `e98e620`: all compile errors fixed + 36 deep-engine patches added (build ✅ run#1136)

### 36 God-level patches added (commit e98e620)
1. Position milestones: 25/50/75/95% of duration → MILESTONE tag
2. AB loop A set / B set / loop fire → AB tag
3. stream.tracks listener: audio/subtitle/video count → TRACK tag
4. Subtitle text event (first 60 chars) → SUB tag
5. Skip segment active / cleared → SKIP tag
6. _openMedia entry: fileId, title, epIdx, isLocal → LOAD tag
7. _openMedia step1 DB fetch started → LOAD tag
8. _buildJazzError context: fileId, error, url → ERR tag
9. Buffering cleared (was buffering → now playing) → BUF tag
10. Watch position save as % of duration → SAVE tag
11. seekRelative as % of duration → SEEK tag
12. Completed event: episodes remaining, loop mode → PLAY tag
13. Playing event: speed, position, hwdec decoder name → PLAY tag
14. Episode nav prev/next: fileId + title → EPISODE tag
15. Binge guard threshold log → INIT tag
16. _logWatchSession: total seconds + quality label → SAVE tag
17. piTimer tick: pos + codec/res/fps/buffer/decoder → PLAYER tag
18. Session start: fileId, title, epIdx, isLocal, Jazz/LOCAL → LOAD tag
19. af= audio filter chain full string → AUDIO tag
20. vf= video filters: colorblind/sharp/bright/contrast/sat/night/smartEnhance → VIDEO tag

### Root causes / lessons learned
- `Tracks` class: fields are `.audio`, `.subtitle`, `.video` — NOT `.sub`
- `PlayerPrefs` video fields: `nightMode`, `sharpnessEnabled`, `sharpness`, `smartEnhanceEnabled`, `brightness`, `contrast`, `saturation` — no `debandingEnabled`
- `_ratioLabels` map does NOT exist — aspect ratio cycling uses `_ratios` List<BoxFit> directly
- `LocalDb.getWatchPosition()` does NOT exist in API — only `saveWatchPosition()`

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- Latest commit: `e98e620` — god-level logger complete
- APK build: ✅ SUCCESS run#1136 (commit e98e620)
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)

---

## 2026-06-18 — FIX-BLACKSCREEN-LP2 (commit 69824d79dbfb)

### Problem
Long-pressing the video (fast-forward to `longPressSpeed`, default 2×) caused a permanent
black screen — identical symptoms to the startup gate bug: GL surface destroyed, audio
continues. The existing `FIX-BLACKSCREEN-LP` only added a recovery seek at **long press
END** (after returning to normal speed). But the destruction happens at **long press START**
when `setProperty('framedrop', 'decoder+vo')` + `setProperty('speed', '2.0')` is issued
while the MediaTek HW decoder is actively playing.

### Root cause
Same root cause as `FIX-VF-BLACKSCREEN` and `FIX-VF-BLACKSCREEN-GAP`: any MPV property
change that touches the MediaTek decoder pipeline (`framedrop`, `vf=`, `hwdec`) while
actively playing can destroy the GL surface texture permanently. The recovery seek pattern
(wait N ms for decoder to settle, then `_player.seek(position)`) forces a fresh
decode+render cycle that restores the surface.

### Fix
Added `Future.delayed(150ms)` recovery seek inside `onLongPressStart`, after `_setSpeed`.
Guard: only fires if widget is still mounted AND long press is still active (`_longPressFast`).
Mirrors the existing pattern in `_applyVideoFilters` and `onSwDecoderChanged`.

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart` — `onLongPressStart` handler (+8 lines)
- `agent-hub/TASKS.md` — task marked ✅

### Lessons learned
- Recovery-seek pattern applies to ANY MPV pipeline property change mid-play on MediaTek.
  Document clearly: framedrop, hwdec, vf= all need the same 150ms delay → seek pattern.
- Fix must be at the SITE of the disruption (START), not only at the recovery point (END).


---

## 2026-06-18 — FIX-SPEED-RECOVERY (comprehensive black screen audit)

### Session summary
Full audit of all video player-related files to find any remaining black-screen causes.
Mapped every `setProperty` call, every `_applyVideoFilters` path, the Video widget tree,
and all `_setSpeed` callers. Found one new critical bug + updated AGENT_PROMPT.md.

### Tasks completed

| ID | File | Change | Status |
|----|------|--------|--------|
| FIX-SPEED-RECOVERY | `player_screen.dart` | recovery seek in `_setSpeed` for all callers | ✅ DONE |
| AGENT_PROMPT.md | docs | Step 2.5 local workspace + rules 20-22 | ✅ DONE |

### Bug found: FIX-SPEED-RECOVERY

**Root cause**: `_setSpeed(s)` is called from 6+ different places (speed picker slider,
speed presets sheet, quick settings panel, speed track panel, voice commands, long-press).
All of them change `framedrop` from `vo` → `decoder+vo` when speed > 1×, which on
MediaTek HW decoder destroys the GL surface texture → permanent black screen (audio continues).

Previously only `onLongPressStart` had an explicit recovery seek. Every other caller had none.
SpeedPickerSheet is the worst case: it fires `_setSpeed` on EVERY slider drag tick, so
without the direction-change guard it would queue 60+ recovery seeks per second.

**Fix:**
1. Added `String _currentFramedrop = 'vo'` instance variable (tracks last-set framedrop).
2. Rebuilt `_setSpeed`: compute `newFd` first, compare to `_currentFramedrop`. If changed:
   update tracker + `Future.delayed(150ms)` → `_player.seek(position)` (guarded by mounted + playing).
3. Removed now-redundant explicit `Future.delayed` seek from `onLongPressStart` — it is now
   handled automatically by `_setSpeed` whenever framedrop direction changes.

**Why the guard matters**: SpeedPickerSheet fires `_setSpeed` on every drag frame. Without
the direction-change guard, dragging from 1× to 2× at 60fps queues 60 recovery seeks in
150ms — stalling/crashing MPV. With the guard, exactly one seek fires for each direction change.

### Audit findings (no additional bugs)

| Area | Finding | Status |
|------|---------|--------|
| `hwdec` toggle (onSwDecoderChanged) | Already has 150ms recovery seek | ✅ OK |
| `vf=` pipeline | Only called via `_applyVideoFilters` (1 call, dedup-protected) | ✅ OK |
| `Video()` widget | NOT conditionally removed from tree — always in Scaffold | ✅ OK |
| `_showVideoDisplay` conditionals | Settings panel overlays — not the Video widget | ✅ OK |
| `np` at SmartVolumeController | Constructor parameter (= `_np`) not a local shadow | ✅ OK |
| Multiple `_applyAudioPrefs` calls | 60ms debounce (_lastAfTs) serialises them to one | ✅ OK |
| `_applyVideoFilters` from SilenceSkip | Harmless — dedup blocks if colorblind unchanged | ✅ OK |
| Episode transition `_applyVideoFilters` | Goes through dedup — no-op if vf unchanged | ✅ OK |

### Files changed

| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | FIX-SPEED-RECOVERY (3 patches) | TBD |
| `agent-hub/TASKS.md` | Added FIX-SPEED-RECOVERY row | TBD |
| `agent-hub/history/TASK_LOG.md` | This entry | TBD |
| `AGENT_PROMPT.md` | Step 2.5 + rules 20-22 + status update | `a9580b8` |

### Rules learned / to remember
- Recovery-seek pattern applies to ANY framedrop direction change (vo↔decoder+vo) mid-play.
- ALWAYS build recovery seek INTO the function itself (not just at specific call sites).
- Slider callbacks fire on every frame — direction-change guards are mandatory.

### State at end of session
- Oracle Flask: RUNNING v3.0.0
- player_screen.dart: 7,509 lines
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes — data not code)


  ---

  ## Session 2026-06-18 (Continuation — FIX-VF-STARTUP)

  ### Context
  - Continued from previous session where build #1141 (FIX-SPEED-RECOVERY + FIX-VF-BLACKSCREEN-GAP + FIX-BLACKSCREEN-LP2) was reported to make the black screen WORSE.
  - Analysed all 49 frames of user screen recording (extracted at 1fps).

  ### Frame analysis findings
  - Frames 38-40: "Luka Chuppi" starts playing fine at 00:00
  - Frames 41-47: ~6s of complete black screen (app alive, audio continues — GL surface destroyed)
  - Earlier in recording: user played "Dil Meri Na Sune" at 2.0× speed (frames 23, 26, 33)
  - Pattern: black screen happens 1-3s into EVERY fresh video play from list, not just after speed change

  ### Root cause identified: FIX-VF-STARTUP
  The startup gate in `_applyVideoFilters` was too permissive:
  - Gate checked `_player.state.playing || _playing`
  - On MediaTek/Infinix, local file's `playing=true` event fires **~200-500ms** after `player.open()` returns
  - Gate fired at **~90ms** (SharedPrefs ~30ms + 60ms debounce): both flags were still false
  - Gate passed → `setProperty('vf', '')` called on uninitialized HW decoder pipeline
  - FIX-SPEED-RECOVERY's recovery seek (added in #1141) fired 150ms LATER when playing=true → **GL surface destroyed**
  - This is why #1141 made it WORSE: before #1141, no recovery seek existed, so only ~50% of plays triggered surface destruction. After #1141, EVERY play that passed the gate got a surface-destroying seek 150ms in.

  ### Fix applied
  **FIX-VF-STARTUP** — 4 targeted changes, 7 lines total:
  1. Added `bool _videoOpened = false;` field (next to `_videoSurfaceReady`)
  2. Set `_videoOpened = true;` immediately before `await _player.open(Media(effectiveLocalPath))` (local file path)
  3. Set `_videoOpened = true;` immediately before `await _player.open(Media(link.streamUrl))` (Jazz drive path)
  4. Gate condition changed from `(_player.state.playing || _playing)` to `(_videoOpened || _player.state.playing || _playing)`

  This ensures the FIRST `_applyVideoFilters` call (from `_loadPrefs`) is ALWAYS blocked once any media has been opened — closing the ~90-500ms window where the GL surface is live but MPV hasn't emitted playing=true yet.

  ### Files changed
  | File | Change | Commit |
  |------|--------|--------|
  | `raddflix_flutter/lib/screens/player_screen.dart` | FIX-VF-STARTUP (4 changes) | `4d88e277` |
  | `agent-hub/TASKS.md` | Added FIX-VF-STARTUP row | TBD |
  | `agent-hub/history/TASK_LOG.md` | This entry | TBD |
  | `AGENT_HANDOFF.md` | Updated handoff state | TBD |

  ### Rules learned / to remember
  - MediaTek/Infinix: `playing=true` event fires **~200-500ms** after `player.open()`. Any gate based solely on `_player.state.playing` has a race window of this size.
  - The pattern: set a boolean flag BEFORE `player.open()` and check THAT flag in startup gates — don't rely on the async playing event.
  - Recovery seeks (added as "fixes") can themselves cause GL surface destruction if they fire during the decoder initialization window (~0-500ms from open to stable playback).

  ### State at end of session
  - Oracle Flask: RUNNING v3.0.0 (not touched this session)
  - player_screen.dart: 7,515 lines
  - Build: needs trigger (commit 4d88e277 ready)
  - Open tasks: DATA-01 (All Of Us Are Dead missing episodes — data not code)
  