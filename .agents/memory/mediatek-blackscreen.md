---
  name: RaddFlix MediaTek black screen bug
  description: Root cause, fix history, and key rules for the MediaTek/Infinix GL surface destruction (black screen, audio continues) in player_screen.dart
  ---

  # MediaTek GL Surface Destruction — Black Screen Bug

  ## The Bug
  On MediaTek/Infinix devices: local video goes black 1-3s after playback starts. Audio continues. Opening any UI panel (settings, etc.) prevents or recovers it.

  ## Root Cause (definitively identified 2026-06-18)
  `_applyVideoFilters()` has a startup gate that checks `_player.state.playing || _playing`.  
  On MediaTek fast local files:
  - `player.open()` returns quickly (sync file open)
  - `playing=true` event fires **~200-500ms** later (MPV demux + decoder init)
  - Gate runs at **~90ms** (SharedPrefs load ~30ms + 60ms debounce): both flags still FALSE
  - Gate passes → `setProperty('vf', '')` called on uninitialized HW decoder pipeline
  - Recovery seek (150ms delayed) fires when video IS playing → **GL surface destroyed**

  **Why opening settings panel "fixes" it:** Navigator.push triggers setState flush → `_playing = true` applied before gate runs → gate sees playing=true → blocks correctly.

  ## Fix History
  1. **FIX-VF-BLACKSCREEN-GAP** (commit a7898f8f) — startup gate + dedup + primed `_lastAppliedVf`
  2. **FIX-BLACKSCREEN-LP2** (commit 69824d79) — long-press speed change recovery seek
  3. **FIX-SPEED-RECOVERY** (commit 1d50a31) — `_currentFramedrop` tracker + built-in recovery seek in `_setSpeed` ⚠️ MADE STARTUP BUG WORSE
  4. **FIX-VF-STARTUP** (commit 4d88e277) — CURRENT, DEFINITIVE FIX
  5. **FEAT-TIMELINE** (commits 5dd1ffde/4454e04f/ff40236a) — PlaybackTimeline diagnostics

  ## The Definitive Fix (FIX-VF-STARTUP)
  Add `bool _videoOpened = false;` field. Set `_videoOpened = true` immediately before EVERY `_player.open()` call. Include in startup gate:
  ```dart
  if (_videoOpened || _player.state.playing || _playing) {
  ```

  **Why:** `_videoOpened` is set synchronously before `player.open()`, so by the time `_applyVideoFilters` runs (60ms+ later), the flag is always true → gate always blocks during startup window → no `vf=` call, no recovery seek, no surface destruction.

  ## PlaybackTimeline Diagnostics (added 2026-06-18)
  - New file: `raddflix_flutter/lib/core/debug/playback_timeline.dart`
  - 10 probe points in player_screen.dart: startSession, surface_ready, video_opened_local/jazz, player_open_called, prefs_loaded, vf_debounce_fired, recordGate, recordHwdecGate, recordMpvPlaying, recordFirstFrame
  - 3s black screen auto-detector: if `hadVfGatePassed=true` AND playing at T=3s → `BLACK_SCREEN_SUSPECTED` event
  - New "Player" tab in Diagnostics screen (Profile → 5×tap version): per-session startup timeline, green/orange/red status banner, copy button
  - Persists 20 sessions to `/tmp/raddflix_timeline.log`

  ## Rules
  - NEVER rely solely on `_player.state.playing` for startup gates on Android — MediaTek has ~200-500ms window
  - Recovery seeks during decoder init window (0-500ms from open) destroy the GL surface on MediaTek
  - The `_firstVfApplied` flag gates on FIRST CALL ONLY; subsequent calls use dedup (`_lastAppliedVf`)
  - If a new `_player.open()` call is ever added anywhere, MUST also set `_videoOpened = true` before it

  ## Critical DO NOTs (player_screen.dart)
  - DO NOT use local var named `_np` (shadows the NativePlayer getter)
  - DO NOT set `androidAttachSurfaceAfterVideoParameters: true`
  - DO NOT upgrade `sqflite_sqlcipher` past 3.1.0+1
  