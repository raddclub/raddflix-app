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

### Phase 9 — Critical Bug Fixes (sha 8af737f)
- **R-001** Removed duplicate state variable declarations (compile error fix)
- **R-002** Added skip +/-N second buttons in center controls
- **R-003** _startSavePositionTimer() wired after every _restoreWatchPos()
- **R-004** _BottomIconBtn label text now rendered below icons
- **R-006** Seek preview label guard fixed (setting now takes effect)
- **R-007** Volume bar fill fixed — 100% at OS volume 100%
- **R-008** Background audio pause implemented

### Phase 9 — Medium/High Priority Fixes (sha bef96b2)
- **R-010** Sleep timer badge in top bar — shows remaining minutes when sleep timer active, updates on 5s clock tick
- **R-011** Sub bottom margin slider wired to MPV `sub-margin-y` via onChangeEnd; Sub fit toggle wired to `sub-ass-scale-with-window`
- **R-015** Seek bar touch target expanded to 48dp (SizedBox wrapper around 28dp visual CustomPaint)
- **R-017** SeekBarPainter wired — import added, _seekBarStyleFromIdx() helper added; styles 0-2 use _HorizontalSeekPainter (preserves A-B markers), styles 3-10 use SeekBarPainter (Gradient/Bold/Waveform/Neon/Filmstrip/Chapters/Dots/Minimal); Settings Style tab shows all 11 options
- **R-022** RepaintBoundary wrapped around seek bar CustomPaint to prevent unnecessary full-UI repaints
- **R-023** Zoom panel "Custom" renamed to "Pinch & Zoom"; explicit case 4 in _getBoxFit(); snackbar hint shown on selection
- **R-024** Clock display timer interval reduced 10s to 5s (faster sleep badge countdown updates)

## Next Ideas
- Playlist / queue support
- Cast to Chromecast / AirPlay
- Download manager (background download, offline play)
