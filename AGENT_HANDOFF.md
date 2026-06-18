# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — GOD-LEVEL debug logging complete in player_screen.dart (91+36 patches, build ✅ run#1136 commit e98e620)_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last passing APK build | ✅ SUCCESS — commit `e98e620` (god-level debug logger, run#1136) |
| Latest commit | `e98e620` — fix 2 compile errors + complete god-level logger |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## Rules (MUST follow — from AGENT_PROMPT.md)

- **NEVER use git shell** — GitHub Contents API only for file pushes
- **Sequential pushes** — never push files in parallel
- **Never use `Icons.replay_15_rounded` / `Icons.forward_15_rounded`** — not in Flutter 3.22.3
- **Never name a local variable `_np`** in player_screen.dart — shadows class getter
- **Never add `androidAttachSurfaceAfterVideoParameters:true`**
- **Never remove XOR padding fix** in request_encoder.dart
- **Update TASKS.md before AND after work** (Rule 0)

## What was done this session (2026-06-18) — God-Level Debug Logging

### Overall: 127 DebugLogger patches to player_screen.dart across 3 rounds

#### Round 1 — commit `272ac0c` (build ✅ run#1131)
43 patches: All silent `catch (_) {}` → named errors, app lifecycle, episode nav, sleep timer, playback-ended tree, watch-position save, slow connection, duration stream, audio/subtitle track selection, volume boost, audio/subtitle sync, cinematic/immersive, cycle fit, frame step, screenshot, voice commands, hardware media button multi-press, subtitle file picker, bookmark add, skip intro, cast enter, long-press restart.

#### Round 2 — commit `c4905b5` (build ❌ — 4 compile errors fixed in round 3)
48 patches: `_logPlayerState()` state-snapshot helper, dispose(), ALL 22 panel-open functions, _loadPrefs, _loadSmartIntro/Bookmarks/SkipSegments counts, _deleteBookmark, _toggleControls, _seekRelative, lock toggle, _applyRotation, _cycleRotation, _initAmbilight, _startWakeTimer, _shareTimestamp, _onSeekBarLongPress, _showJumpToTime, _handleCenterTap, _initBingeGuard, _initPipChannel, audio interruption, headphone unplug, _logWatchSession.

#### Round 3 (God-Level) — commit `e98e620` (build ✅ run#1136)
Fixes all 4 r2 compile errors (silenceSkipEnabled→skipSilenceEnabled, bingeGuardIntervalMins→bingeGuardThresholdMinutes, _ratioLabels→inline BoxFit comparison, debandingEnabled→nightMode, tracks.sub→tracks.subtitle) + 36 new deep-engine patches:
- Position milestones at 25/50/75/95% of duration
- AB loop A set / B set / loop fire log
- Track list counts on stream.tracks update (audio/subtitle/video counts)
- Subtitle text event log (first 60 chars of subtitle line)
- Skip segment active/cleared state log
- _openMedia entry log + step1 DB fetch timing
- _buildJazzError context log (fileId, error, url)
- Buffering cleared log (was buffering→playing)
- Watch position save % of duration
- seekRelative as % of duration
- Completed event: episodes remaining, loop mode
- Playing event: speed, position, hwdec decoder name
- Episode nav: prev/next with fileId + title
- Binge guard threshold log
- _logWatchSession: total seconds + quality label
- piTimer tick: pos + codec/res/fps/buffer/decoder
- Session start: fileId, title, epIdx, isLocal, Jazz/LOCAL
- af= audio chain: full filter string logged
- vf= video filter: colorblind/sharpness/brightness/contrast/saturation/night/smartEnhance

### Log tags for filtering in debug screen

| Tag | What it captures |
|-----|-----------------|
| `STATE` | Full snapshot: pos/dur/playing/buffering/ep/local/loading/speed/hwdec/pip/locked/ended/err |
| `LIFECYCLE` | App foreground/background, dispose, wake timer |
| `EPISODE` | Prev/next nav, playback ended, countdown start |
| `SLEEP` | Timer set/cancel/fire, end-of-episode mode |
| `SAVE` | Watch position saves % and _logWatchSession seconds+quality |
| `QUOTA` | Plan expiry redirect, data quota exceeded |
| `PIP` | PiP enter/exit |
| `TRACK` | Audio/subtitle/video track counts + selection + restore |
| `INTRO` | Skip intro visibility, auto-skip, editor |
| `SEEK` | seekRelative from/to as % of duration |
| `PANEL` | Every panel/sheet open |
| `VOICE` | Voice command intent+value |
| `HW` | Hardware media button press count |
| `CAST` | Cast device discovery |
| `MILESTONE` | 25/50/75/95% watched milestones |
| `AB` | AB loop A set, B set, loop fire |
| `SUB` | Subtitle text events |
| `SKIP` | Skip segment active/cleared |
| `GESTURE` | Long-press play restart |
| `TAP/MODE` | Cinematic, immersive, rotation |
| `TAP/VIDEO` | Frame step, screenshot, cycle fit |
| `TAP` | Controls show/hide, lock toggle, bookmark add/delete, share |
| `AUDIO` | Volume boost, audio/sub sync, interruption, headphone unplug |
| `BUF` | Slow connection detected, buffering cleared |
| `INIT` | All init functions with key param values |
| `LOAD` | openMedia entry, step1 DB, JAZZ/LOCAL session start, success |

## Architecture pointers

- **player_screen.dart**: ~7300 lines, ~323KB. Every subsystem is now logged.
- **debug_logger.dart**: `lib/core/debug/debug_logger.dart` — buffer 5000, 8MB rotation, session ID, auto-flush 30s
- **Debug screen**: Profile → Account → Debug Logs (opens on Logs tab)
- **Oracle**: Flask v3.0.0 at 92.4.95.252:5000 — proxy for JazzDrive + catalog
- **JazzDrive retry**: max 1 retry; if playing at retry-exhaustion, error overlay suppressed
- **vf= black screen fix**: never call setProperty('vf',...) while HW decoder is active on first play — guarded by `_firstVfApplied` flag
- **_ratioLabels**: does NOT exist; aspect ratio cycling uses `_ratios` (List<BoxFit>) directly — compare with `BoxFit.contain/cover/fill`
- **debandingEnabled**: does NOT exist in PlayerPrefs — use `nightMode`, `sharpnessEnabled`, `smartEnhanceEnabled`
- **tracks.subtitle** (not .sub) — Tracks class has .audio, .subtitle, .video

## For next agent

1. **DATA-01** — All Of Us Are Dead missing E03/E04/E05/E09: catalog issue, requires Oracle DB update
2. **Now that all logging is in place**: Test the player, collect logs via Profile → Account → Debug Logs, and analyze to find real runtime bugs
3. **run#1137** was also triggered for e98e620 — it may also pass or may show duplicate-trigger warning; ignore it, run#1136 is the confirmed success
