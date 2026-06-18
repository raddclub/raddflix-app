# RaddFlix Agent Task Board

_Last updated: 2026-06-18_

## Completed This Session (2026-06-17)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ TASK-UI-13 | `simosa_card.dart`, `poster_service.dart`, `content_card.dart` | **SimoSA fix + hidden image cache + popup redesign (commit b92ed63, build run#1090 ✅).** (1) **SimoSA deep-link**: `_launchSimosa()` now opens `android-app://com.jazz.world` directly — launches the installed SIMOSA app without going to Play Store; falls back to Play Store only when app is not installed. (2) **SimoSA card redesign**: Jazz-branded red gradient square icon with bold "J" (🔥 fire at 7-day streak), purple gradient Claim CTA with glow shadow, FREE 100 MB pill badge, streak progress bar (X/7 🔥). (3) **Poster cache hidden**: `PosterService` moved storage from `raddflix_posters/` (visible in file manager) to `.raddflix_media/` (dot-prefix hides it from Android file managers); auto-migrates existing posters on first run. Cast photos already in `.cast_imgs/` (hidden). (4) **Quick-view popup (long-press)**: full 185px hero banner with poster backdrop + gradient overlay, title/year/⭐ overlaid at bottom, smart primary button (Browse Episodes for shows / Watch Now for movies), secondary Details outline button. |
| ✅ TASK-UI-12 | `actor_service.dart`, `cast_rail.dart`, `actor_screen.dart`, `watchlist_screen.dart`, `search_screen.dart`, `bottom_nav.dart`, `downloads_screen.dart` | **12 UI/UX improvements (commit 65ff483+c3f3985, build run#1088/1089 ✅).** Cast Rail TVMaze API, 84px cards, 10-shimmer, See All sheet, Wikipedia actor bio. Watchlist sort sheet. Richer search empty state. Animated bottom nav pill+dot. Downloads illustrated empty state. |
| ✅ BUG-BUILD-COMPILE | `home_screen.dart`, `downloads_screen.dart`, `content_card.dart` | 3 Dart compile errors fixed in commit bebc343 (run#1084/1085 ✅). |
| ✅ BUG-BGPLAY-FOREGROUND | `PlaybackService.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `player_screen.dart` | Background play past screen-lock fixed. |
| ✅ BUG-PIP-EXIT | `MainActivity.kt`, `player_screen.dart` | PiP exit now restores player controls. |
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

_No open tasks._

## Completed This Session (2026-06-18)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ FIX-PLAYER-BUGS | `player_screen.dart` | **11 bugs fixed in player_screen.dart (commit 09760ca).** (1) SmartVolumeController clamped volume min to 20 — overrode user mute every tick → fixed to 0. (2) Manual retry on stream error always retried episode 1 (widget.fileId) instead of current episode → fixed to _currentFileId. (3) "Cancel" on next-episode overlay called Navigator.pop() → exited the whole player instead of just dismissing overlay. (4) Two sleep badges (fade badge + timer badge) visible simultaneously — added !_sleepFadeActive guard. (5) Floating ball always showed play icon even while playing → now toggles play/pause icon. (6) ReactionStampsOverlay wrapped in if(false) — permanently dead code shipped in builds → removed entirely. (7) _playNextEpisode and _playPrevEpisode had identical 20-line skip-intro timer block copy-pasted → extracted into _scheduleSkipIntroCheck() helper. (8) ZoomCropOverlay.onZoomChanged triggered two consecutive setState calls → merged into one. (9) _showFrameStep set true in frameStep() but never cleared when play resumes → cleared in playing stream listener. (10) 6 never-used state variables (_audioTracks, _selectedAudioTrack, _castScanning, _castDevices, _showSubtitleHunter, _abLoopActive) removed. (11) "Stereo mode" button had empty onTap — visible but non-functional control → removed from audio panel. |
| ✅ FIX-VF-BLACKSCREEN | `player_screen.dart` | **ROOT CAUSE of month-long “local video black screen after 1-2s” fixed (commit cd241fc).** `_applyVideoFilters` called from `_loadPrefs` with 60ms debounce — fires AFTER local video starts playing with active Android HW decoder. `setProperty('vf', ...)` even with empty string destroys GL surface on MediaTek/Infinix → permanent black screen while audio continues. hwdec was guarded in `_applyAudioPrefs` but `_applyVideoFilters` had no equivalent guard — the missing fix. Two-layer fix: startup gate (`_firstVfApplied` flag skips first call if playing) + dedup (`_lastAppliedVf` sentinel prevents no-op pipeline resets) + seek-after for user-initiated mid-play filter changes. |
| ✅ BUG-ICON-COMPAT | `player_screen.dart` | Fixed 2 Dart compile errors breaking APK builds run#1095–1098: `Icons.replay_15_rounded` and `Icons.forward_15_rounded` do not exist in Flutter 3.22.3. Replaced with `Icons.replay_10` / `Icons.forward_10` (confirmed in Flutter 3.22.3 source). Commit `91e52dc` — builds run#1099/1100 ✅ SUCCESS. |
