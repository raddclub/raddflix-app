# RaddFlix Agent Status
**Last updated:** 2026-06-22  
**Build:** #1219 — `0748417f` — `in_progress` ⏳  
**File:** `raddflix_flutter/lib/screens/player_screen.dart` — 7033 lines

---

## Latest Session Summary

### Changes in Build #1219 (`0748417f`)
| Area | Change |
|------|--------|
| Center controls | **All removed** — zero buttons in center, cinematic clean screen |
| Transport row | **New row below seek bar** — skip·prev·play/pause·next·skip |
| Top bar | **5 buttons removed** — CC, Audio, PiP, Rotate, Lock (all now sidebar-only) |
| Panel width | **45% → 55%** (all 18 panels wider automatically) |
| Sidebar | **Auto-hides when any panel opens**, restores when panel closes; respects manual close state |
| Volume indicator | **Moved LEFT** (was right: 20, now left: 20) — sidebar on right was blocking it |
| Subtitle `sub-opacity` | Fixed: was calling fake `sub-ass-fade-in-time`, now `sub-opacity` (valid MPV property) |
| Subtitle margin | Fixed: max was 80px, now 200px with 40 divisions |

### Previous Build #1218 (`a031b005`)
- Sidebar: right-edge strip, chevron toggle, 19 shortcuts, drag-reorder, accent-color states, persisted prefs
- Orientation: auto-rotation via native SCREEN_ORIENTATION_SENSOR channel
- Brightness: LEFT amber pill | Volume: RIGHT (now moved LEFT in #1219)

---

## Critical Rules (NEVER violate)
| Rule | Reason |
|------|--------|
| NO `vf=` property | Crashes HW decoder |
| NO `hwdec` mid-play | Only safe when paused and duration==0 |
| NO `_np` local var | Use `_np` field only, never shadow it |
| db.setting(k) not db.get_setting(k) | API naming |
| NO androidAttachSurfaceAfterVideoParameters:true | Causes black screen |
| sub-opacity range 0.0–1.0 | Pass as toStringAsFixed(2) |

---

## Key State Variables
| Variable | Purpose |
|----------|---------|
| `_sidebarExpanded` | User's manual sidebar toggle state |
| `_panelOpen` | True while any right-panel is open → sidebar hides |
| `_showControls` | Controls overlay visibility (auto-hides) |
| `_panelOpen` resets via `.then()` on `showGeneralDialog` | |

## Sidebar Shortcut IDs (persistent prefs)
`cc, audio, eq, speed, loop, rotate, lock, pip, screenshot, sleep, ab, episodes, settings, vivid, mute, zoom, info, replay, onehanded`
