# RaddFlix Agent Task Board

  _Last updated: 2026-06-16_

  ## Completed This Session (2026-06-16)

  | ID | Changed | Summary |
  |----|---------|---------|
  | ✅ BUG-LOGIN-01 | `login_screen.dart` | Wrong password always navigated to home as guest. Fixed. |
  | ✅ BUG-CATALOG-STALE | Oracle DB | Bumped `catalog_forced_version` to force re-sync on all devices. |
  | ✅ TASK-DEBUG-01 | `debug_diagnostics_screen.dart`, `profile_screen.dart`, `jazzdrive_service.dart` | Debug screen accessible in release builds via 5-tap on version. Build 1053 ✅ |
  | ✅ TASK-JD-LIVE | Oracle + JazzDrive API | Full chain proven: HTTP 206 · `video/mp4` · ftyp magic bytes on all 7 files. |
  | ✅ TASK-BUTTONS-01 | `show_detail_screen.dart` | Separated Play + Download into equal, labelled buttons. Movies: 50/50 row. Episodes: dedicated Play + Download button row under each tile. Build 1054 ✅ |
  | ✅ BUG-PLAYER-BLANK | `player_screen.dart` | **CRITICAL** — Local device videos went blank (dark screen, audio only) after 2-3 s. Root cause: `_applyAudioPrefs()` called after prefs loaded (~1-2 s), unconditionally setting `hwdec` on an already-playing video → MPV restarts video decoder pipeline → destroys GL surface texture. Fix: guard hwdec + deinterlace changes with `if (!_playing)`. |
  | ✅ BUG-SEEK-DOUBLE-DOT | `player_screen.dart` | Double/overlapping dot on seek bar for non-classic styles. Root cause: Slider's own white thumb rendered on top of SeekBarPainter's custom thumb. Fix: `SliderComponentShape.noThumb` for non-classic styles. |
  | ✅ BUG-DOTS-OVERLAP | `seek_bar_painter.dart` | Dots-style seek bar: track dots visible under thumb, creating stacked-circle look. Fix: skip drawing any dot within `thumbR + dotR` of the thumb position. |

  ## Open / In Progress

  _No open tasks._

  ## Pending / Blocked

  _Nothing blocked._
  