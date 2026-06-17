---
name: Player UX — sidebar 3-state, iconsOnly, speed track, clock
description: Lessons from 2026-06-17 player UX session; important anchors and patterns for future player_screen.dart edits
---

See `.agents/memory/player-sidebar-ux.md` for full detail.

## Quick Reference
- `sidebarMode` 0/1/2 in PlayerPrefs; ShPref key `sidebar_mode`; default 0
- `_ControlsOverlay` requires `sidebarMode` + `onToggleSidebarMode` (added 2026-06-17)
- `_MxSideBtn` has `iconsOnly` param; sidebar buttons all use `iconsOnly: sidebarMode == 1`
- S17 anchor: use 6-space indent for `child: Container(` inside GestureDetector (not 8-space)
- `_SpeedPanel` → `_SpeedTrackPanel`; positioning `right:0,top:0,bottom:0` → `top:0,left:0,right:0`
- `_clockTimer?.cancel()` must be in `dispose()` or setState-on-disposed error in debug
