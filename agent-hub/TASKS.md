
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
