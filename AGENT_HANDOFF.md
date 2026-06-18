# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — Exhaustive debug logging added to player_screen.dart (91 patches across 2 rounds), build ✅ r1 / ⏳ r2_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last passing APK build | ✅ SUCCESS — commit `272ac0c` (player debug r1, run#1131) |
| Pending build | run#1132 ⏳ — commit `c4905b5` (player debug r2) |
| Latest commit | `c4905b5` — 48 more DebugLogger patches round 2 |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## Rules (MUST follow — from AGENT_PROMPT.md)

- **NEVER use git shell** — GitHub Contents API only for file pushes
- **Sequential pushes** — never push files in parallel
- **Never use `Icons.replay_15_rounded` / `Icons.forward_15_rounded`** — not in Flutter 3.22.3
- **Never name a local variable `_np`** in player_screen.dart — shadows class getter
- **Never add `androidAttachSurfaceAfterVideoParameters:true`**
- **Never remove XOR padding fix** in request_encoder.dart
- **Update TASKS.md before AND after work** (Rule 0)

## What was done this session (2026-06-18) — Debug logging

### Overall: 91 DebugLogger patches to player_screen.dart across 2 rounds

#### Round 1 — commit `272ac0c` (build ✅ run#1131)
43 patches: All silent `catch (_) {}` → named errors, app lifecycle (background/resume), episode nav (prev/next with fileId), sleep timer lifecycle (set/cancel/fire/fade start), full playback-ended decision tree (loop/return_home/nothing/next-ep countdown), watch-position periodic save, slow connection detection, duration stream, audio+subtitle track selection with language names, volume boost, audio/subtitle sync, cinematic mode, immersive mode, cycle fit (aspect ratio), frame step fwd/back, screenshot, voice commands, hardware media button multi-press, subtitle file picker, bookmark add, skip intro visibility + auto-skip, cast enter, long-press-play restart.

#### Round 2 — commit `c4905b5` (build ⏳ run#1132)
48 patches: `_logPlayerState()` state-snapshot helper (12 fields in one line), dispose() with final position+ep, ALL 22 panel-open functions (every showModalBottomSheet, Navigator.push, and setState-toggle panel), _loadPrefs with all key settings, _loadSmartIntro/Bookmarks/SkipSegments counts, _deleteBookmark, _toggleControls show/hide with reason, _seekRelative from/to, lock toggle, _applyRotation + _cycleRotation, _initAmbilight, _startWakeTimer with wakeTimer FIRED, _shareTimestamp, _onSeekBarLongPress, _showJumpToTime, _handleCenterTap, _initBingeGuard, _initPipChannel, audio interruption (type logged), headphone unplug, _logWatchSession, _logPlayerState called at jazz-retry exhaustion. Fixed `_nextIdx` lint issue.

### Log tags now available for filtering in debug screen

| Tag | What it captures |
|-----|-----------------|
| `STATE` | Full snapshot: pos/dur/playing/buffering/ep/local/loading/speed/hwdec/pip/locked/ended/err |
| `LIFECYCLE` | App foreground/background, dispose, wake timer |
| `EPISODE` | Prev/next nav, playback ended, countdown start |
| `SLEEP` | Timer set/cancel/fire, end-of-episode mode |
| `SAVE` | Watch position saves and logWatchSession |
| `QUOTA` | Plan expiry redirect, data quota exceeded |
| `PIP` | PiP enter/exit |
| `TRACK` | Audio/subtitle selection, restore, auto-select |
| `INTRO` | Skip intro visibility, auto-skip, editor |
| `SEEK` | seekRelative from/to, seekBar long press |
| `PANEL` | Every panel/sheet open |
| `VOICE` | Voice command intent+value |
| `HW` | Hardware media button press count |
| `CAST` | Cast device discovery |
| `GESTURE` | Long-press play restart |
| `TAP/MODE` | Cinematic, immersive, rotation |
| `TAP/VIDEO` | Frame step, screenshot, cycle fit |
| `TAP` | Controls show/hide, lock toggle, bookmark add/delete, share |
| `AUDIO` | Volume boost, audio/sub sync, interruption, headphone unplug |
| `BUF` | Slow connection detected |
| `INIT` | All init functions with key param values |

## What was done this session — Prior work

| Commit | Summary |
|--------|---------|
| `8c8f331`+`2b9e051` | Debug screen via Profile → Account → Debug Logs |
| `426d78c` | 6 missing DebugLogger methods added |
| `4882ba1` | 10 bugs fixed across player files |
| `c099057` | 4 additional player bugs (orphan import, clock drift, dead guard, shadowed var) |
| `09760ca` | 11 player bugs fixed |
| `cd241fc` | ROOT CAUSE local video black screen (vf= during HW decode) |
| `91e52dc` | Icon compat fix (replay_15/forward_15 not in Flutter 3.22.3) |
| `96f8cc1` | dart:ui import fix — PlatformDispatcher |

## Architecture pointers

- **player_screen.dart**: 7280 lines, ~320KB. All subsystems are now logged.
- **debug_logger.dart**: `lib/core/debug/debug_logger.dart` — buffer 5000, 8MB rotation, session ID, auto-flush 30s
- **Debug screen**: Profile → Account → Debug Logs (opens on Logs tab)
- **Oracle**: Flask v3.0.0 at 92.4.95.252:5000 — proxy for JazzDrive + catalog
- **JazzDrive retry**: max 1 retry; if playing at retry-exhaustion, error overlay is suppressed (live stream stays alive)
- **vf= black screen fix**: never call setProperty('vf',...) while HW decoder is active on first play — guarded by `_firstVfApplied` flag

## For next agent

1. **Check if run#1132 passed** — if failed, look at build log for Dart compile errors and fix
2. **DATA-01** — All Of Us Are Dead missing E03/E04/E05/E09: catalog issue, requires Oracle DB update
3. **Now that all logging is in place**, the next step is to actually TEST the player and collect logs to find real bugs. Ask user to reproduce the issue, retrieve logs via debug screen, and analyze.
