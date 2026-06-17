# RaddFlix Agent Task Board

_Last updated: 2026-06-17_

## Completed This Session (2026-06-17)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ BUG-BUILD-COMPILE | `home_screen.dart`, `downloads_screen.dart`, `content_card.dart` | **APK builds broken since run#1079.** 3 Dart compile errors introduced by previous UX/feature commits: (1) `home_screen.dart:386` — stray `),` inside `Stack.children[...]` after Positioned closed. Fix: removed the stray line. (2) `downloads_screen.dart:452` — `doneEps.indexOf(d)` where `d` is `Map<dynamic,dynamic>` (onTapEp typed as `Function(Map)`). Fix: cast `d as Map<String, dynamic>`. (3) `content_card.dart:455` — `HapticFeedback.selectionClick()` used without `flutter/services.dart` import. Fix: added explicit import. All 3 fixed in commit bebc343. Build triggered (run#1084/1085). |
| ✅ BUG-BGPLAY-FOREGROUND | `PlaybackService.kt` (NEW), `MainActivity.kt`, `AndroidManifest.xml`, `player_screen.dart` | **Background play now works past screen-lock/app-switch.** Root cause: Android kills any process backgrounded >~1 min with no foreground service, regardless of native audio threads. AndroidManifest declared dead `com.ryanheise.audioservice.AudioService` (from `audio_service` package which is NOT in pubspec — only `audio_session` is). Fix: (1) Created `PlaybackService.kt` — minimal foreground service with FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK that keeps process alive and shows "RaddFlix playing" notification. (2) Added `startBgPlayback`/`stopBgPlayback` to PIP channel in `MainActivity.kt`. (3) Replaced dead service declaration with real `.PlaybackService` + added `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission in manifest. (4) `player_screen.dart`: call startBgPlayback on lifecycle-paused+bgplay, stopBgPlayback on lifecycle-resumed and dispose. |
| ✅ BUG-PIP-EXIT | `MainActivity.kt`, `player_screen.dart` | **PiP exit now restores controls.** Bug: `_inPiP` was set to `true` on entering system PiP but **never reset to `false`** — controls were permanently hidden after the first PiP session. Fix: (1) Added `onPictureInPictureModeChanged` override in `MainActivity.kt` — sends `onPipExited` event via PIP channel when system PiP window is dismissed. (2) Added `_initPipChannel()` in `player_screen.dart` that listens for `onPipExited` and calls `setState(() => _inPiP = false)`. |
| ✅ BUG-PLAYER-TRIFECTA | `player_screen.dart` | **3 persistent player bugs fixed in one commit.** (1) Catalog popup over playing video: `_jazzRetryCount` never reset on successful open + `_jazzAutoRetry` showed error overlay even when `_playing=true`. Fix: reset count on every successful `_player.open()`; guard `_streamError` assignment with `if (_playing) return`. (2) Local video blank screen: hwdec guard race — episode transitions briefly set playing=false AND duration=zero, allowing `_applyAudioPrefs` to change hwdec mid-session. Fix: add `!_videoSurfaceReady` to guard (latch never resets, closes episode-nav window). (3) Long-press blank screen: MediaCodec HW decoder crashes at 2× speed on MediaTek/Infinix. Fix: set `framedrop=decoder+vo` before `setRate()`, restore `vo` on release. Bonus: SW decoder toggle (line 3523) added post-seek refresh to prevent blank after live hwdec switch. |
| ✅ BUG-BLACKSCREEN-LOCAL | `player_screen.dart` | **CRITICAL** — Local video goes black after ~2 s. Root cause: `_applyAudioPrefs` hwdec guard used Flutter state var `_playing` which lags behind actual MPV state. Fix: added `!_player.state.playing && _player.state.duration == Duration.zero` to guard — uses synchronous MPV state, blocks hwdec change while any media is open. |
| ✅ BUG-BLACKSCREEN-LP | `player_screen.dart` | Long-press fast-forward leaves black frame after release. Fix: 80ms delayed seek to `_player.state.position` forces MPV to render fresh frame. |
| ✅ BUG-JAZZ-GENERIC-ERROR | `player_screen.dart`, `jazzdrive_service.dart` | Catalog movies always showed "Jazz SIM Required" regardless of actual error. Fix: `validateStatus: (s) => true` on Dio requests; HTML page detection; `_buildJazzError()` helper translates real exceptions (MED-/FOL- codes, HTTP 401/403, timeout, HTML) into specific messages. |

## Completed Previous Session (2026-06-16)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ BUG-LOGIN-01 | `login_screen.dart` | Wrong password always navigated to home as guest. Fixed. |
| ✅ BUG-CATALOG-STALE | Oracle DB | Bumped `catalog_forced_version` to force re-sync on all devices. |
| ✅ TASK-DEBUG-01 | `debug_diagnostics_screen.dart`, `profile_screen.dart`, `jazzdrive_service.dart` | Debug screen accessible in release builds via 5-tap on version. Build 1053 ✅ |
| ✅ TASK-JD-LIVE | Oracle + JazzDrive API | Full chain proven: HTTP 206 · `video/mp4` · ftyp magic bytes on all 7 files. |
| ✅ TASK-BUTTONS-01 | `show_detail_screen.dart` | Separated Play + Download into equal, labelled buttons. Movies: 50/50 row. Episodes: dedicated Play + Download button row under each tile. Build 1054 ✅ |
| ✅ BUG-PLAYER-BLANK | `player_screen.dart` | Partial fix — wrapped hwdec + deinterlace in `if (!_playing)`. Full fix in 2026-06-17 session above. |
| ✅ BUG-SEEK-DOUBLE-DOT | `player_screen.dart` | Double/overlapping dot on seek bar for non-classic styles. Root cause: Slider's own white thumb rendered on top of SeekBarPainter's custom thumb. Fix: `SliderComponentShape.noThumb` for non-classic styles. |
| ✅ BUG-DOTS-OVERLAP | `seek_bar_painter.dart` | Dots-style seek bar: track dots visible under thumb, creating stacked-circle look. Fix: skip drawing any dot within `thumbR + dotR` of the thumb position. |

## Open / In Progress

_No open tasks._

## Pending / Blocked

_Nothing blocked._
