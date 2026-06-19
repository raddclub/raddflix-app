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
  

  ## FIX-VF-ABSOLUTE (Build #1151, 2026-06-19)

  ### Problem discovered
  Even with FIX-VF-STARTUP + FIX-VF-GAP, episode navigation re-opens
  _player.open() when _firstVfApplied is already true. The startup gate is
  bypassed. If any of the 9 _applyVideoFilters callers fire within 2 seconds
  of the new open(), setProperty('vf',...) executes on a fresh MediaTek
  GL surface → black screen.

  ### Fix
  Added `_videoOpenedAtMs` (int) field. Both player.open() call paths set
  _videoOpenedAtMs = DateTime.now().millisecondsSinceEpoch alongside _videoOpened = true.
  _applyVideoFilters checks: if (now - _videoOpenedAtMs < 2000) → return (and log).
  This is an unconditional block, independent of all flag-based gates.

  ### Status
  Build #1151. Still WAITING for PlaybackTimeline data from user's device.
  

  ## FIX-VF-ROOT (Build #1153, 2026-06-19) — THE REAL FIX

  ### Confirmed Root Cause (from git history analysis)
  Smart Enhance feature (commit 034938fb, 2026-06-07) added `_applyVideoFilters(loaded)`
  to `_loadPrefs()`. Both `_initPlayer()` and `_loadPrefs()` are called from
  `initState` without await — they run concurrently.

  Timeline of the bug:
  - T=0ms: _initPlayer starts, creates Player + VideoController, calls _player.open()
  - T=0ms: _loadPrefs starts, awaits PlayerPrefs.load() (SharedPreferences, ~50-200ms)
  - T=50-200ms: _loadPrefs completes, calls _applyVideoFilters(loaded)
  - T=50-260ms: _applyVideoFilters 60ms debounce expires, calls setProperty('vf',...)
  - RESULT: vf= property changed WHILE HW decoder is active → GL surface destroyed → black screen

  Same race as the hwdec bug fixed in commit 3b56547a, but for vf= property.

  ### The Fix
  In `_initPlayer()`, BETWEEN VideoController construction and `_player.open()`:
  1. Await PlayerPrefs.load() directly
  2. Build initial vf string and prime _firstVfApplied=true + _lastAppliedVf
  3. Apply vf= now (safe: decoder not started)
  4. Apply hwdec='no' if disabled (safe: before decoder starts)

  When _loadPrefs fires its _applyVideoFilters call: _firstVfApplied=true → gate skip →
  dedup: vf unchanged → no setProperty call. Race eliminated at the root.

  ### What NOT to do in future
  - Do NOT add setProperty('vf',...) or setProperty('hwdec',...) to any function
    that can fire AFTER _player.open() without a gate checking _videoOpened
  - Any new player property that affects the decoder pipeline (audio/video filter,
    codec selection, etc.) should follow this same pattern: apply before open OR
    use a gate that checks _videoOpened/_player.state.playing
  