# RaddFlix Agent Hub — Tasks
_Last updated: 2026-06-21_

---

## ✅ Completed

### Phase 1–6 — Player Audit v4 (sha d8e4598c)
- Audio filter pipeline AF fix, Loop/audio disable fixes, Buffered seek bar
- MX-style triple chevron seek flash, Ghost UI replacements, Design polish

### Phase 7 — Pinch-to-Zoom
- ScaleGestureDetector Transform.scale, Zoom indicator pill + reset button

### Phase 8 — New Player Features (sha 9c447cd6)
- Frame step, Channel mode selector (pan= filter)
- Night mode, Clock overlay, Audio L/R balance, Subtitle to MPV, Video rotation, Video info dialog

### Phase 9 — Critical Bug Fixes (sha 8af737f, bef96b2)
- R-001 Compile error fix, R-002 Skip buttons, R-003 Save position timer
- R-004 Icon labels, R-006 Seek preview guard, R-007 Volume fill, R-008 BG audio pause
- R-010 Sleep timer badge, R-011 Sub margin MPV wiring, R-015 48dp seek bar
- R-017 SeekBarPainter 11 styles, R-022 RepaintBoundary, R-023 Pinch & Zoom rename, R-024 5s clock timer

### Phase 10 — Android Media Notification Shade Controls (sha 154f962)
- **PlaybackService.kt** — Full MediaStyle rewrite with MediaSessionCompat
- Notification shade: -10s / Play-Pause / +30s in compact view
- Lock screen + Bluetooth + Android Auto transport controls
- **MainActivity.kt** — BroadcastReceiver catches notification button taps → Flutter
- **player_screen.dart** — _notifyBgState(), didChangeAppLifecycleState, PiP channel fix

### Phase 11 — Deep Hunter God Mode Player Audit (sha b7b4c69)
- **PLAYER_AUDIT_REPORT.md** pushed (534 lines, 7 phases)
- 43 real working features catalogued; 16 stub/fake features exposed; 11 confirmed bugs
- BUG-01 subtitle alignment silent no-op, BUG-02 subtitle background no-op,
  BUG-03 settings init hardcoded, BUG-04 Customization tab entirely fake,
  BUG-05 audio channel resets, BUG-06 dual-prefs data loss,
  BUG-07 sleep countdown frozen, BUG-08 speed label float noise,
  BUG-09 sync precision inconsistency, BUG-10 8 QSP dead buttons, BUG-11 lab state resets

### Phase 12 — Black Screen Root Cause Fix (Build #1153)
- FIX-VF-ROOT: pre-open vf= in _initPlayer() eliminates the vf= race condition
- SmartEnhance/ColorFiltered rewrite (no MPV vf= ever)
- Defense-in-depth layers: FIX-VF-STARTUP, FIX-VF-GAP, FIX-VF-ABSOLUTE all present

### Phase 13 — Player UI: Right-Side Panels (Build #1218 predecessor)
- All 10 showModalBottomSheet calls converted to showGeneralDialog right-side panels
- 45% screen width, 60% dark transparent background, slide-from-right animation
- Subtitle default margin bumped 22px → 100px

### Phase 14 — MX Player-Style Brightness/Volume Indicators
- Brightness pill on LEFT edge (amber, vertical, RotatedBox bottom-to-top fill)
- Volume pill on RIGHT edge (white/orange, vertical)
- Old centered pill removed

### Phase 15 — Auto-Rotation via Native Android Sensor (Build #1218)
- _setNativeOrientation(String mode) helper added
- _applyAutoOrientation now calls SCREEN_ORIENTATION_SENSOR (ignores system auto-rotate toggle)
- com.raddflix.app/orient platform channel in MainActivity.kt
- dispose() resets to SCREEN_ORIENTATION_UNSPECIFIED
- **Root cause fixed:** old code was LOCKING to video dimensions, not using sensor

### Phase 16 — Customizable Persistent Shortcut Sidebar (Build #1218)
- Persistent right-edge vertical icon strip, always visible when controls show
- Chevron toggle (‹/›) to expand/collapse — persisted to SharedPreferences
- Shortcut count badge (e.g. "8 shown")
- Scrollable (SingleChildScrollView — supports all 19 shortcuts)
- Active shortcuts glow with accent color; unavailable greyed at 35% opacity
- 19 available shortcuts: CC, Audio, EQ, Speed, Loop, Rotate, Lock, PiP,
  Screenshot, Sleep, A-B, Episodes, Settings, Vivid, Mute, Frame, 1-Hand, Zoom, Silence
- "Edit" button → opens _SidebarCustomizerPanel in right-side panel
- _SidebarCustomizerPanel: ReorderableListView drag reorder + × to hide + + to restore
- Counter badge "X shown" updates live
- Order + visibility persisted to pref_sidebar_order (JSON) + pref_sidebar_exp
- QSP dead slots fixed: PiP button wired to _enterPiP, empty slot → "Sidebar" customizer

---

## 🚧 Known Issues / Next Priorities

### HIGH — UI Polish
- [ ] Subtitle alignment still a silent no-op (BUG-01) — MPV `sub-margin-y` not applied properly
- [ ] Subtitle background style not applied (BUG-02)
- [ ] Settings panel init still has hardcoded defaults (BUG-03)
- [ ] Top bar overflow on small screens — too many icons (12+)

### MEDIUM — Features
- [ ] Watch Party — built but no UI entry point except More menu
- [ ] Voice Commands — built but no mic button visible on main UI
- [ ] Download manager (background download, offline play)
- [ ] Cast to Chromecast / AirPlay
- [ ] Playlist / queue support
- [ ] A-B repeat visual indicator on seek bar

### LOW — Nice to Have
- [ ] Long-press sidebar shortcut → quick swap picker (inline, no panel)
- [ ] Sleep timer visual countdown badge on player (Netflix-style)
- [ ] Silence skip visual indicator when skipping
