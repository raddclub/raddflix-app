---
name: Player Sidebar UX — iconsOnly, sidebarMode, speed track
description: Non-obvious lessons from the 2026-06-17 player UX session (sidebar 3-state, floating ball, speed track anchor)
---

## Sidebar 3-State (`sidebarMode`)
- Stored in `PlayerPrefs` as `int` (0=full, 1=icons-only, 2=hidden), SharedPrefs key `sidebar_mode`
- `_ControlsOverlay` receives `sidebarMode` + `onToggleSidebarMode` as required params
- Sidebar visibility gated by `sidebarMode < 2` (not a simple bool)
- Width: `sidebarMode == 1 ? 40 : 58`
- All `_MxSideBtn` calls in the sidebar column use `iconsOnly: sidebarMode == 1`

**Why:** User can collapse the rail to see more video without fully hiding it (icons remain as affordance).

## `_MxSideBtn` iconsOnly
- New `final bool iconsOnly;` field with default `false`
- Container shrinks to 36×36 (from 46×44), icon grows to 19px (from 17px), label + gap hidden with `if (!iconsOnly)`
- The S17 anchor in player_screen.dart must include the surrounding `GestureDetector → child: Container` context — the 6-space indent before `child:` is important (not 8-space)

**Why:** Padding trick — make icon larger when label is gone so the button still feels tappable.

## _SpeedPanel → _SpeedTrackPanel
- The `_SpeedPanel` class spans exactly 22 lines (from `class _SpeedPanel` to closing `}`)
- Both positioning changed: was `right:0, top:0, bottom:0` → now `top:0, left:0, right:0`
- Widget reference also changes from `_SpeedPanel(` to `_SpeedTrackPanel(`

**How to apply:** Always replace both the call site (Positioned child) AND the class definition in one commit.

## _clockTimer Cleanup
- `_clockTimer = Timer.periodic(30s, ...);` set in initState after `_scheduleHide()`
- `_clockTimer?.cancel();` MUST be in `dispose()` before HardwareKeyboard.instance.removeHandler
- `_clockStr` must be initialised with `_fmtTime()` in initState before first build

**Why:** Timer leak causes setState on disposed widget → Flutter assertion error in debug builds.
