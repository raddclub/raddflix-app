# RaddFlix Agent Hub — Tasks

## Completed

### Phase 1-6 — Player Audit v4 (sha d8e4598c31)
- Audio filter pipeline AF fix
- Loop/audio disable fixes  
- Buffered seek bar
- MX-style triple chevron seek flash
- Ghost UI replacements
- Design polish

### Phase 7 — Pinch-to-Zoom
- ScaleGestureDetector, Transform.scale
- Zoom indicator pill, reset button

### Phase 8 — New Player Features (sha 9c447cd68c)
- Frame step (frame-step MPV command)
- Channel mode selector (Stereo/Mono/Left/Right via pan= filter)
- **Night mode** — ColorFilter.matrix warm eye-comfort filter; toggle + warmth slider in Settings > Screen tab
- **Clock overlay** — HH:mm in top bar, persisted, toggleable in Settings > Screen tab
- **Audio L/R balance** — pan= filter in AF pipeline; slider + reset in Audio Effect panel Lab tab
- **Subtitle → MPV** — size/bold/color/font wired to MPV setProperty live
- **Video rotation** — _rotateVideo() cycles 0→90→180→270 via video-rotate property; badge in top bar
- **Video info dialog** — resolution, duration, position, speed, rotation, pinch scale

### Phase 9 — Critical Bug Fixes (player-critical-fixes-1)
- **R-001** — Removed duplicate `_showSkipBtns` + `_showPrevNextBtns` state variable declarations (Dart compile error)
- **R-002** — Added skip ±N second buttons (replay/forward icons) flanking prev/next episode buttons in center controls, guarded by `_showSkipBtns` setting
- **R-003** — `_startSavePositionTimer()` now called after every `_restoreWatchPos()` so position auto-saves every 10s
- **R-004** — `_BottomIconBtn` now renders its `label` text below the icon (Enhance, Audio, Lab, Episodes, etc. are now visible)
- **R-006** — Seek preview label now correctly hidden when `_showSeekPositionLabel = false` (setting now takes effect)
- **R-007** — Volume bar fill fixed: bar reaches 100% at OS volume 100% instead of 40%; boost >100% keeps bar full with orange→red colour signal
- **R-008** — Background audio toggle now actually pauses the player when toggled off and app is backgrounded

## Next Ideas
- Playlist / queue support
- Cast to Chromecast / AirPlay
- Download manager (background download, offline play)
| player-ux-fixes-2 | fix: 22 player UI/UX bugs (V2,V3,V6,V9,V16,U1,U2,U10,B2,B3,B5,B6,G1-G6,G9,G11,D2-D4) | 2d9b2c8 | ✅ DONE | 2026-06-20 |
