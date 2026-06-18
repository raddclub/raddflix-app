# RaddFlix Agent Handoff

  ## Project
  Pakistani Flutter streaming app (Jazz SIM zero-rated). Local video player on MediaTek/Infinix.

  ## Last Updated
  2026-06-18 (Session: FIX-VF-STARTUP black screen regression fix)

  ## Critical Rules (DO NOT VIOLATE)
  - Never name a local variable `_np` (shadows the getter)
  - Never add `androidAttachSurfaceAfterVideoParameters: true` (causes blank frames)
  - Never upgrade `sqflite_sqlcipher` past 3.1.0+1 (breaks encryption)
  - GitHub pushes: Contents API ONLY (Node.js), 1.5s between pushes, always fetch fresh SHA in pushFile()
  - player_screen.dart is ~7,515 lines — edit with targeted string/line replacement only
  - Add TASKS.md row BEFORE starting work, mark done AFTER

  ## Architecture
  - Flutter 3.22.3 + media_kit/MPV (NativePlayer for low-level MPV properties)
  - VideoController: `androidAttachSurfaceAfterVideoParameters: false` (critical, don't change)
  - Oracle Flask v3.0.0 at 92.4.95.252:5000 — SSH via /tmp/oracle_key
  - SQLCipher 3.1.0+1 for encrypted local DB

  ## Black Screen Bug History (MediaTek/Infinix)
  The long-running "local video goes black after 1-2s, audio continues" has been through 4 fix iterations:

  ### Fix 1: FIX-VF-BLACKSCREEN-GAP (commit a7898f8f)
  - Added startup gate in `_applyVideoFilters` + dedup
  - Primed `_lastAppliedVf` in gate to prevent dedup bypass on 2nd call

  ### Fix 2: FIX-BLACKSCREEN-LP2 (commit 69824d79)  
  - Long-press START black screen: 150ms recovery seek after `_setSpeed` on longPressStart

  ### Fix 3: FIX-SPEED-RECOVERY (commit 1d50a31)
  - Speed change black screen: `_currentFramedrop` direction tracker, built-in recovery seek in `_setSpeed`
  - ⚠️ This made the original startup black screen WORSE (see Fix 4)

  ### Fix 4: FIX-VF-STARTUP (commit 4d88e277) ← CURRENT
  - **Root cause of regression**: startup gate checked `_player.state.playing||_playing` at ~90ms, but `playing=true` fires ~200-500ms after `player.open()` on MediaTek. Gate passed, vf= + recovery seek destroyed GL surface on EVERY play.
  - **Fix**: `_videoOpened=true` before each `_player.open()` call; gate condition: `_videoOpened||playing||_playing`
  - **Key insight**: Never rely solely on `_player.state.playing` for startup gates — use a flag set synchronously before `player.open()`

  ## Key Files
  - `raddflix_flutter/lib/screens/player_screen.dart` — main player (7,515 lines)
  - `agent-hub/TASKS.md` — task board
  - `agent-hub/history/TASK_LOG.md` — session history
  - `.agents/tasks/BUG_TRACKER.md` — bug registry
  - `agent-hub/CONTEXT.md` — system architecture

  ## Open Tasks
  - DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 — catalog data, not code

  ## Current Build Status
  - Last code commit: 773a26b8 (add missing PlaybackTimeline import to player_screen.dart)
  - Other commits this session: 5dd1ffde (playback_timeline.dart new), ff40236a (debug_diagnostics_screen.dart + Player tab)
  - Build #1148 ✅ SUCCESS — artifact: RaddFlix-1.0.0+1-build1148.apk (57.1 MB)
  - Oracle: RUNNING v3.0.0

  ## Next Agent Instructions
  1. Read TASKS.md, TASK_LOG.md, BUG_TRACKER.md at session start
  2. Add task row to TASKS.md before starting work
  3. Check Oracle alive: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "curl -s http://localhost:5000/health"`
  4. If user reports black screen: read this handoff + Fix 4 notes above first
  5. FIX-VF-STARTUP should have eliminated the startup black screen — if it still happens, open Diagnostics → Player tab — the timeline will show exactly which flag failed and at what ms
  