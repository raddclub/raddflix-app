# RaddFlix Agent Task Board

_Last updated: 2026-06-17_

## Completed This Session (2026-06-17)

| ID | Changed | Summary |
|----|---------|---------|
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
