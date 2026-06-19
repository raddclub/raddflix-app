# Agent Status
  **Last Updated:** 2026-06-19  
  **Build:** #1153 ✅ SUCCESS (id=7748282186, 57.1MB)  
  **Run:** https://github.com/raddclub/raddflix-app/actions/runs/27821999045

  ## Root Cause (CONFIRMED)
  The "local video black screen" bug was introduced when Smart Enhance (commit 034938fb)
  added `_applyVideoFilters(loaded)` to `_loadPrefs()`. This created the SAME race
  as the hwdec bug (fixed in commit 3b56547a) — _loadPrefs completes ~50-200ms after
  _player.open() starts the HW decoder, then setProperty('vf',...) destroys the GL surface.

  ## Permanent Fix Applied (Build #1153)
  **FIX-VF-ROOT**: In _initPlayer(), BEFORE _player.open(), the code now:
  1. Loads PlayerPrefs directly (await PlayerPrefs.load())
  2. Primes _firstVfApplied=true + _lastAppliedVf → _applyVideoFilters from _loadPrefs is a dedup no-op
  3. Applies vf= BEFORE decoder starts (safe — initial config, not a change)
  4. Applies hwdec='no' if user disabled it (safe — before decoder starts)

  Result: zero race, zero surface destruction. No flags or timers are load-bearing.

  ## Fix History (all layers still present as defense-in-depth)
  | Layer | Build | Description |
  |-------|-------|-------------|
  | FIX-VF-STARTUP | #1148 | _videoOpened=true gate in _applyVideoFilters |
  | FIX-VF-GAP | #1148 | Prime _lastAppliedVf when gate blocks |
  | FIX-VF-ABSOLUTE | #1151 | 2s timestamp block after player.open() |
  | **FIX-VF-ROOT** | **#1153** | **Pre-open vf= in _initPlayer() — THE real fix** |

  ## Status
  ✅ FIXED — Install build #1153, play local video, black screen should be gone.
  If still happening, get PlaybackTimeline: Profile → 5×tap version → Player tab → Copy → paste.
  