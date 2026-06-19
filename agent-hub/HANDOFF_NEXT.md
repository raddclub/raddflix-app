# Handoff — Next Agent

  ## Status (2026-06-19): FIX-VF-ROOT deployed in build #1153

  ### Confirmed Root Cause
  The "local video black screen after 1-2s" bug was introduced by Smart Enhance
  (commit 034938fb) which added `_applyVideoFilters(loaded)` to `_loadPrefs()`.

  Both `_initPlayer()` and `_loadPrefs()` are called from `initState` without await.
  They race. `_player.open()` starts the HW decoder immediately. `_loadPrefs`
  completes ~50-200ms later and calls `setProperty('vf',...)` while the decoder
  is active → GL surface destroyed → permanent black screen (audio continues).

  Identical to the hwdec race fixed in commit 3b56547a, but for vf=.

  ### The Permanent Fix (FIX-VF-ROOT, player_screen.dart _initPlayer())
  In _initPlayer(), AFTER VideoController construction and BEFORE _player.open():
  1. `await PlayerPrefs.load()` — load prefs synchronously in this context
  2. Build initVf = _buildVfString(preloaded)
  3. Prime `_lastAppliedVf = initVf` and `_firstVfApplied = true`
  4. If initVf non-empty: `await _np.setProperty('vf', initVf)` (safe: no decoder)
  5. If hwdec disabled: `await _np.setProperty('hwdec', 'no')` (safe: before open)
  6. Then: `await _openMedia(...)` — decoder starts with correct settings

  When _loadPrefs fires from initState:
  - _applyVideoFilters: _firstVfApplied=true → gate bypassed → dedup: vf unchanged → no-op ✓
  - _applyAudioPrefs: _videoSurfaceReady=true → hwdec gate blocks → no-op ✓

  ### Defense-in-Depth (still present, not load-bearing)
  - FIX-VF-STARTUP (_videoOpened gate)
  - FIX-VF-GAP (_lastAppliedVf priming when gate blocks)
  - FIX-VF-ABSOLUTE (2s timestamp block after open)

  ### Critical Rules (NEVER violate)
  - Never name any local variable `_np` (shadows the getter)
  - Never add androidAttachSurfaceAfterVideoParameters:true
  - Never upgrade sqflite_sqlcipher past 3.1.0+1
  - GitHub pushes: fetch fresh SHA, wait ≥1.5s between pushes
  - Stack: Flutter 3.22.3, media_kit/MPV, SQLCipher 3.1.0+1, Oracle Flask 92.4.95.252:5000
  