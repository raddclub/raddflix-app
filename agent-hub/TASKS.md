# RaddFlix Agent Task Board

_Last updated: 2026-06-18_

## Completed This Session (2026-06-18) — God-Level Debug Logging

| ID | Changed | Summary |
|----|---------|---------|
| ✅ DEBUG-LOG-01 | `debug_logger.dart` | **DebugLogger v2** (commit `613f686`, build ✅): buffer 5000 entries, 8MB rotation, session ID, auto-flush 30s, new methods: `logTap`, `logNav`, `logLifecycle`, `logFeature`, `logCrash`, `getFiltered`. |
| ✅ DEBUG-LOG-02 | `main.dart` | **Global crash handler** (commits `bb59f50` + `96f8cc1`): `PlatformDispatcher.instance.onError` catches all uncaught Dart errors. `DebugLogger.init()` called at app start. Requires `import 'dart:ui' show PlatformDispatcher;` (missing import was build-breaking — fixed in `96f8cc1`). |
| ✅ DEBUG-LOG-03 | `app.dart` | **Global nav observer** (commit `d5a449c`): `_RaddNavObserver` registered in MaterialApp — logs every push/pop/replace/remove with route name. |
| ✅ DEBUG-LOG-04 | `player_screen.dart` | **13 crash-path patches** (commit `2413c3f`): initPlayer, hwdec guard, vf= startup gate, setSpeed framedrop, open() LOCAL+JAZZ URLs, buffering stream changes, completed event, error stream, jazzAutoRetry, onSwDecoderChanged. |
| ✅ DEBUG-LOG-05 | `home_screen.dart` | **Lifecycle + tap logging** (commit `9c55499`): initState/dispose, bottom nav tabs, category filter chips, search icon, profile avatar, hero card taps (title+id). |
| ✅ DEBUG-LOG-06 | `show_detail_screen.dart` | **Lifecycle + play logging** (commit `69a7d63`): initState(item id+title)/dispose, play episode tap, download episode tap. |
| ✅ DEBUG-LOG-07 | `search_screen.dart` | **Full search logging** (commit `f739564`): lifecycle, query changes (debounced), filter changes, clearAll, suggestion taps, result card taps (title+id). |
| ✅ DEBUG-LOG-08 | `profile_screen.dart` | **Lifecycle + nav logging** (commit `198033b`): initState/dispose, subscription/watchlist/history/downloads tab taps. |
| ✅ DEBUG-LOG-09 | `downloads_screen.dart` | **Lifecycle + play logging** (commit `1e7128f`): initState, play downloaded file tap. |
| ✅ DEBUG-BUILD-FIX | `main.dart` | **Build fix** (commit `96f8cc1`, build ✅ SUCCESS): all 4 prior cascading build failures fixed by adding `import 'dart:ui' show PlatformDispatcher;`. |
| ✅ DEBUG-PLAYER-R1 | `player_screen.dart` | **43 player patches round 1** (commit `272ac0c`, build ✅ run#1131): Silent catch blocks → errors logged, episode nav, sleep timer, playback ended, watch position save, slow connection, duration stream, audio/subtitle track selection, volume boost/sync, cinematic/immersive, cycle fit, frame step, screenshot, voice commands, media button multi-press, subtitle picker, bookmark add, skip intro, cast, long-press restart, app lifecycle (pause/resume). |
| ✅ DEBUG-PLAYER-R2 | `player_screen.dart` | **48 player patches round 2** (commit `c4905b5`, build ❌ failed — 4 compile errors fixed in god-level): _logPlayerState() helper, dispose, 22 panel opens, _loadPrefs, _loadSmartIntro/Bookmarks/SkipSegments, _deleteBookmark, _toggleControls, _seekRelative, lock toggle, _applyRotation, _cycleRotation, _initAmbilight, _startWakeTimer, _shareTimestamp, _onSeekBarLongPress, _showJumpToTime, _handleCenterTap, _initBingeGuard, _initPipChannel, audio interruption, headphone unplug, _logWatchSession. |
| ✅ DEBUG-PLAYER-GOD | `player_screen.dart` | **GOD-LEVEL — 36 deep-engine patches** (commit `e98e620`, build ✅ run#1136): All r2 compile errors fixed (silenceSkipEnabled, bingeGuardThresholdMinutes, tracks.subtitle, nightMode fields) + position milestones 25/50/75/95%, AB loop A/B set + fire log, track list counts on stream update, subtitle text event log, skip segment active/clear, _openMedia entry + step1 DB log, _buildJazzError context, buffering cleared log, watch pos save %, seekRelative %, completed/playing enhanced, episode nav enhanced, binge guard threshold log, _logWatchSession seconds+quality, piTimer tick log, session start log, af= chain log, vf= detail log. |

## Completed This Session (2026-06-18) — Prior Work

| ID | Changed | Summary |
|----|---------|---------|
| ✅ DEBUG-ACCESS-SIMPLE | `profile_screen.dart`, `debug_diagnostics_screen.dart` | **Debug screen directly accessible via Profile → Account → Debug Logs. (commits 8c8f331 + 2b9e051)** |
| ✅ BUG-DEBUGLOGGER-MISSING | `debug_logger.dart` | **6 missing DebugLogger methods added (commit 426d78c, build ✅).** |
| ✅ HUNTER-AUDIT | 10 files | **10 bugs fixed across player (commit 4882ba1, build run#27730921492 ✅).** |
| ✅ FIX-PLAYER-REAUDIT | `player_screen.dart` | **4 additional bugs fixed (commit c099057, build run#27729363694 ✅).** |
| ✅ FIX-PLAYER-BUGS | `player_screen.dart` | **11 bugs fixed (commit 09760ca).** |
| ✅ FIX-VF-BLACKSCREEN | `player_screen.dart` | **ROOT CAUSE of local video black screen fixed (commit cd241fc).** |
| ✅ BUG-ICON-COMPAT | `player_screen.dart` | Icons.replay_15_rounded / forward_15_rounded not in Flutter 3.22.3 → replaced (commit 91e52dc, build ✅). |

## Completed This Session (2026-06-17)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ TASK-UI-13 | `simosa_card.dart`, `poster_service.dart`, `content_card.dart` | SimoSA fix + hidden image cache + popup redesign (commit b92ed63, build ✅). |
| ✅ TASK-UI-12 | 7 files | 12 UI/UX improvements (commits 65ff483+c3f3985, build ✅). |
| ✅ BUG-BUILD-COMPILE | 3 files | 3 Dart compile errors fixed (commit bebc343, build ✅). |
| ✅ BUG-BGPLAY-FOREGROUND | 4 files | Background play past screen-lock fixed. |
| ✅ BUG-PIP-EXIT | 2 files | PiP exit restores player controls. |
| ✅ BUG-PLAYER-TRIFECTA | `player_screen.dart` | 3 persistent player bugs fixed. |
| ✅ BUG-BLACKSCREEN-LOCAL | `player_screen.dart` | Local video black screen after 2s fixed. |
| ✅ BUG-JAZZ-GENERIC-ERROR | `player_screen.dart`, `jazzdrive_service.dart` | Jazz SIM error messages now specific. |

## Completed Previous Session (2026-06-16)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ BUG-LOGIN-01 | `login_screen.dart` | Wrong password always navigated to home as guest. Fixed. |
| ✅ BUG-CATALOG-STALE | Oracle DB | Bumped catalog_forced_version for full re-sync. |
| ✅ TASK-DEBUG-01 | `debug_diagnostics_screen.dart` | Debug screen via 5-tap on version. |
| ✅ TASK-JD-LIVE | Oracle + JazzDrive API | Full stream chain proven end-to-end. |
| ✅ TASK-BUTTONS-01 | `show_detail_screen.dart` | Separated Play + Download buttons on episodes. |

## Open / In Progress

| ID | Details |
|----|---------|
| ✅ FIX-BLACKSCREEN-LP2 | `player_screen.dart` | **Long-press START black screen**: `framedrop=decoder+vo`+`speed=2×` on active MediaTek HW decoder resets pipeline → GL surface destroyed. Existing `FIX-BLACKSCREEN-LP` only recovered at END. Fix: 150ms recovery seek after `_setSpeed` on longPressStart (commit `69824d79dbfb`). |
| ✅ FIX-VF-BLACKSCREEN-GAP | `player_screen.dart` | **Startup gate primed fix**: gate correctly blocked vf= when playing=true, but never updated `_lastAppliedVf` from sentinel — causing dedup bypass on 2nd call (ref.listen fires ~1-2s) → setProperty(vf) while playing → MediaTek GL surface destroyed → black screen. Fix: `_lastAppliedVf = _buildVfString(p)` before early return (commit `a7898f8f`). |
| ✅ FIX-SPEED-RECOVERY | `player_screen.dart` | **Speed change black screen (all callers)**: `_setSpeed` had no recovery seek when framedrop changed direction (vo→decoder+vo) — affected speed picker slider, speed presets, voice commands, quick settings. Added direction-tracker `_currentFramedrop` + built-in recovery seek (150ms, guard: only on direction change). Removed now-redundant explicit seek from `onLongPressStart`. |
| 📌 DATA-01 | All Of Us Are Dead missing E03/E04/E05/E09 — catalog data issue, not code |


## Completed This Session (2026-06-18)

| ID | Changed | Summary |
|----|---------|----------|
| ✅ FIX-VF-STARTUP | `player_screen.dart` | Black screen regression fix: _videoOpened gate. Commit 4d88e277. |
| ✅ FEAT-TIMELINE | `playback_timeline.dart`, `player_screen.dart`, `debug_diagnostics_screen.dart` | PlaybackTimeline: 10 probe points, black screen auto-detector, Player tab in Diagnostics. |
  ## FIX-VF-ABSOLUTE [DONE ✅ Build #1151]
  Hard 2-second block after _player.open() in _applyVideoFilters.
  _videoOpenedAtMs field timestamps every open(). Any vf= call within 2000ms
  of open() is blocked + logged. Covers episode-nav re-opens where startup gate is bypassed.
  
  ## FIX-VF-ROOT [DONE ✅ Build #1153]
  THE permanent fix. Root cause confirmed: Smart Enhance (commit 034938fb) added
  _applyVideoFilters(loaded) to _loadPrefs(). Both run concurrently from initState.
  _player.open() starts decoder immediately. _loadPrefs completes ~50-200ms later,
  calls setProperty('vf',...) while HW decoder active → GL surface destroyed.
  Fix: load PlayerPrefs inside _initPlayer() BEFORE _player.open(). Apply vf= and
  hwdec as initial config (decoder not running → safe). _firstVfApplied=true + 
  _lastAppliedVf primed so _loadPrefs._applyVideoFilters is a dedup no-op.
  
## Open / In Progress

| ID | Details |
|----|---------|
| ⏳ FEAT-SIMPLE-PLAYER | `player_screen.dart` | **Clean Player v2** — backup old 7500-line player as `player_screen_v1_backup.dart`, replace with minimal ~600-line player. No vf=, no hwdec mid-play, no video filters. Plays local + catalog + episodes correctly. |
