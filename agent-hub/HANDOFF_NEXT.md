# Handoff — Next Agent

  ## Current State (as of 2026-06-19)
  Build #1151 is ready. Three layers of vf= protection now in place:

  ### Layer 1: FIX-VF-STARTUP (_videoOpened flag)
  `_videoOpened = true` is set before both `_player.open()` calls.
  `_applyVideoFilters` startup gate checks this flag → blocks the first call from prefs.

  ### Layer 2: FIX-VF-GAP (_lastAppliedVf priming)
  When gate blocks, primes `_lastAppliedVf` so the dedup skips any subsequent call
  with the same vf string.

  ### Layer 3: FIX-VF-ABSOLUTE (_videoOpenedAtMs timestamp)
  `_videoOpenedAtMs` records ms of every `player.open()`. Any `vf=` property call
  within 2000ms of open() is unconditionally blocked, regardless of _firstVfApplied.
  Covers episode-nav re-opens where startup gate is bypassed.

  ## The Unsolved Mystery
  Bug may STILL be happening. User hasn't confirmed fix worked.
  PlaybackTimeline (build #1148+) captures what happened.
  **Need**: User installs #1151, plays local video that goes black, waits 5s,
  goes back, Profile → 5×tap version → Player tab → Copy → paste here.

  ## If Timeline Shows GREEN
  The vf= fix is working. Different cause for black screen. Possible culprits:
  - media_kit GL surface recreation on MediaTek (AndroidAttachSurfaceAfterVideoParameters)
  - MPV hw decoder init destroying surface
  - Check DebugLogger for any errors in the 0-2s window

  ## If Timeline Shows ORANGE/RED  
  Fix not working. Check which flag was false. _videoOpened should always be true.

  ## Critical Rules (DO NOT VIOLATE)
  - Never name any local variable `_np` (shadows the field, breaks setProperty calls)
  - Never add androidAttachSurfaceAfterVideoParameters:true to VideoController config
  - Never upgrade sqflite_sqlcipher past 3.1.0+1
  - GitHub pushes: always fetch fresh SHA, always wait ≥1.5s between pushes
  - Stack: Flutter 3.22.3, media_kit/MPV, SQLCipher 3.1.0+1, Oracle Flask at 92.4.95.252:5000
  - GitHub repo: raddclub/raddflix-app, token in .replit under GITHUB_TOKEN
  