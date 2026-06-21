
# RaddFlix Agent Hub — Tasks

## Completed

### Phase 1-6 — Player Audit v4 (sha d8e4598c31)
- Audio filter pipeline AF fix, Loop/audio disable fixes, Buffered seek bar
- MX-style triple chevron seek flash, Ghost UI replacements, Design polish

### Phase 7 — Pinch-to-Zoom
- ScaleGestureDetector Transform.scale, Zoom indicator pill + reset button

### Phase 8 — New Player Features (sha 9c447cd68c)
- Frame step, Channel mode selector (pan= filter)
- Night mode, Clock overlay, Audio L/R balance, Subtitle to MPV, Video rotation, Video info dialog

### Phase 9 — Critical Bug Fixes (sha 8af737f)
- R-001 Compile error fix, R-002 Skip buttons, R-003 Save position timer
- R-004 Icon labels, R-006 Seek preview guard, R-007 Volume fill, R-008 BG audio pause

### Phase 9 — Medium/High Priority Fixes (sha bef96b2)
- R-010 Sleep timer badge, R-011 Sub margin MPV wiring, R-015 48dp seek bar
- R-017 SeekBarPainter 11 styles, R-022 RepaintBoundary, R-023 Pinch & Zoom rename, R-024 5s clock timer

### Phase 10 — Android Media Notification Shade Controls (sha 154f962)
- **PlaybackService.kt** — Full MediaStyle rewrite with MediaSessionCompat.
  Notification shade: -10s / Play-Pause / +30s in compact view.
  Lock screen + Bluetooth + Android Auto transport controls.
  State updated via onStartCommand extras; button taps sent as local broadcasts.
- **MainActivity.kt** — BroadcastReceiver (onStart/onStop) catches notification button
  broadcasts and forwards to Flutter as onNotificationAction on pip channel.
  Added updateBgNotification handler; startBgPlayback now accepts full play state.
  Stored pipMethodChannel reference for onPipExited events.
- **build.gradle** — Added androidx.media:media:1.7.0.
- **player_screen.dart** —
  Fixed wrong pip channel name in _enterPiP (raddclub.raddflix -> raddflix.app).
  _notifyBgState() pushes title/isPlaying/positionMs/durationMs to service.
  didChangeAppLifecycleState: paused+bgAudio -> start service; resumed -> stop.
  initState: pip channel handler routes onNotificationAction to play/pause/seek.
  dispose(): stops bg service and clears method call handler.

## Next Ideas
- Playlist / queue support
- Cast to Chromecast / AirPlay
- Download manager (background download, offline play)
### Phase 11 — Deep Hunter God Mode Player Audit (sha b7b4c69)
- **PLAYER_AUDIT_REPORT.md** pushed to agent-hub/ (534 lines, 7 phases)
- 43 real working features catalogued
- 16 stub/fake/disconnected features exposed (incl. Watch Party + Voice Commands: built but zero user access)
- 11 confirmed bugs: BUG-01 subtitle alignment silent no-op, BUG-02 subtitle background no-op, BUG-03 settings init hardcoded, BUG-04 Customization tab entirely fake, BUG-05 audio channel resets, BUG-06 dual-prefs data loss, BUG-07 sleep countdown frozen, BUG-08 speed label float noise, BUG-09 sync precision inconsistency, BUG-10 8 QSP dead buttons, BUG-11 lab state resets
- Architecture: 5337-line monolith, 3 parallel settings systems, PlayerPrefs class unused
- Overall score: 6.1/10 — strong engine, weak persistence + UI honesty

### Phase 12 — Sprint 1 Bug Fixes (sha c371876)
- **11 bugs fixed** in player_screen.dart (5337 → 5590 lines)
- BUG-01: Subtitle alignment fires sub-align-x to mpv (was silent no-op)
- BUG-02: Subtitle background color fires sub-back-color to mpv (was silent no-op)
- BUG-03: Settings panel nav toggles init from parent state — no longer hardcoded true
- BUG-04: Customization tab fully interactive — Position (sub-align-y), Shadow (sub-shadow-offset/sub-outline-size), Opacity slider, Edge padding (sub-margin-x), Line spacing (sub-spacing)
- BUG-05: Audio channel mode index tracked in parent (_channelModeIdx), passed as initialChannelModeIdx — persists across panel reopens
- BUG-06: EQ bands (5 keys) + eq_on + reverb + lab (vocal/dialogue/norm/bass/bassLevel) + channelMode persisted via SharedPreferences (11 new pref keys); AF pipeline rebuilt and deferred _applyAllAf() on player start
- BUG-07: _QuickShortcutsPanel → StatefulWidget with Timer.periodic(30s) — sleep countdown live-ticks while panel open
- BUG-08: Speed label uses toInt()/toStringAsFixed guard — no more float noise
- BUG-11: AudioEffectPanel lab state (vocal/dialogue/norm/bass/bassLevel) persists via widget props + initState; onLabStateChanged propagates to parent; initialReverbPreset wires reverb to parent state

### Phase 13 — Sprint 2 All Remaining Features (sha 77e08a1)
- **player_screen.dart** 5589 → 6529 lines (+940 lines)
- 8 QSP dead-button panels implemented:
  - Jump To: time dialog + 6 quick-chips (1m/5m/10m/15m/30m/45m)
  - Speed Presets: 10-speed grid bottom sheet (0.25x–3.0x)
  - End Action: 4 modes (play_next/loop/stop/ask) + _onVideoCompleted integration
  - Silence Skip: toggle + threshold slider + mpv silencedetect af filter
  - Zoom & Crop: 7 aspect ratio presets via video-aspect-override
  - Gesture Map: live SwitchListTiles for all 4 gesture groups
  - Skip Editor: intro start/end + outro timestamps → auto-skip via _checkSkipEditor()
  - Layout Designer: 3 presets (Default/Cinema/Compact) → affect _showSkipBtns
  - Watch Party: room code dialog (join/create room)
  - Screenshot: mpv screenshot-to-file + SaverGallery.saveImage → Pictures/RaddFlix
- Online subtitle search LIVE (rest.opensubtitles.org REST v0):
  - Results rendered as tappable download cards with lang/count/rating
  - Download: GZip decompressed via ZLibDecoder → SRT loaded into player via onSubtitleFilePicked
  - Translation button now searches OpenSubtitles in chosen language (Urdu/Hindi/Arabic/French/Spanish/German)
- Settings Controls tab — 5 real toggles (was 3 static text lines)
  - Double-tap seek, long-press speed, swipe seek, swipe Br/Vol, voice commands
  - Wired bidirectionally: Settings ↔ parent state ↔ gesture guards
- 10 new SharedPreferences keys: pref_end_action, pref_silence_skip/thr, pref_layout, pref_gest_*, pref_skip_ed_on
- Skip editor timestamps persisted per content ID (pref_intro_s_X / pref_intro_e_X / pref_outro_s_X)
- Gesture guards: onDoubleTapDown + onLongPressStart/End/Cancel gated on bool flags
- Dead code deleted: player_screen_v1_backup.dart removed from repo

### Phase 14 — Sprint 2 Correctness Audit (sha 604e7de)
**"Do NOT assume anything works — verify from actual code"**
- Re-read original Deep Hunter God Mode mandate and cross-checked every claim

COMPILE-BLOCKERS fixed (file would not build at all):
- 5 missing imports added: dart:io, dart:convert, dart:typed_data, path_provider, saver_gallery
- 13 missing state variable declarations added to _PlayerScreenState:
  _endAction, _silenceSkipEnabled, _silenceSkipThreshold, _layoutPreset,
  _voiceCommandsEnabled, _doubleTapSeekEnabled, _longPressSpeedEnabled,
  _swipeSeekEnabled, _swipeBVEnabled, _skipEditorEnabled,
  _introStart, _introEnd, _outroStart
- 10 Sprint 2 pref keys added to _loadPrefs() (were only in _savePrefs):
  pref_end_action, pref_silence_skip/thr, pref_layout, pref_voice_cmd,
  pref_gest_dtap/lp/seek/bv, pref_skip_ed_on
- Gesture guards added to GestureDetector (toggles had no actual effect):
  onDoubleTapDown gated on _doubleTapSeekEnabled
  onLongPressStart/End/Cancel gated on _longPressSpeedEnabled

BUG FIXES:
- BUG-09: Audio sync panel toStringAsFixed(2) → toStringAsFixed(1) to match subtitle sync panel
- BUG-08 partial: Speed label float fallback now uses toStringAsFixed(2) not raw ${_speed}

REMAINING OUTSTANDING (genuine, verified from code):
- watch_party_service.dart (476 lines) still not imported or wired — dialog is UI-only stub
- voice_commands_service.dart still not imported — toggle has no backend
- PlayerPrefs class (1158 lines) still orphaned — raw SharedPreferences used instead
- Smart Enhance label misleading — visual animation only, no video processing
- audio_session package in pubspec.yaml but never imported or used
- cinematic_overlay.dart still a 6-line tombstone (harmless but dead)
- Monolith 6588 lines, Riverpod unused, _AudioTrackPanelState 1249 lines from widget

### Phase 15-19 Compile Fix (sha 83395b5)
- **15 compile errors fixed** across player_screen.dart + watch_party_service.dart
- _SubtitlePanel: removed spurious extended-shortcut params from ctor; added `title` + `onSubtitleFilePicked` fields
- _QuickShortcutsPanel: added 12 missing extended-shortcut params to constructor
- _QuickShortcutsPanelState: added `widget.` prefix to onClose/endAction/silenceSkipEnabled/onSleepTimer/onSpeedSelected
- _VideoZoomPanel (StatelessWidget): fixed `widget.onClose` → `onClose`
- WatchPartyService: added `String get myId` getter
- _SubtitlePanelState: added `_showInfoSnackbar` method
- observeProperty callback: added `async` to fix Future<void> return type error
- SaverGallery.saveImage: `name:` → positional arg
- _ReverbSelectorState: fixed `String?` nullable assignment

### Phase 20 — Player Panel UI Fixes (sha 2b477ac)
- **Bug 1 fixed**: All panels now slide from the RIGHT side (45% width) instead of full-screen bottom sheets
  - `_openRightPanel` rewritten: `showModalBottomSheet` → `showGeneralDialog` with right-side `SlideTransition`
  - Panel is 45% screen width, 60% dark transparent (`Colors.black.withOpacity(0.60)`)
  - Tap on left 55% (video) dismisses the panel — user can see live video behind panel
  - All panels route through: subtitle, audio, audio effect, zoom, more menu, settings
- **Bug 2 fixed**: `_showEpisodeSheet` converted from bottom sheet → `_openRightPanel` (side panel)
- **Bug 3 fixed**: All QSP sub-sheets also converted to side panels:
  Speed Presets, End Action, Silence Skip, Zoom & Crop, Gesture Map, Skip Editor, Layout Designer
- **Subtitle fix**: Default `_subBottomMargin` changed from 22px → 100px so subtitles always render above bottom controls/seek bar (no more hidden-under-controls bug)
- `showModalBottomSheet` calls in player_screen.dart: **0 remaining**
