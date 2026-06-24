# RaddFlix Agent Task Log

## Session 2026-06-20 — Phase 15-19 Compile Fix

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| FIX-COMPILE-01 | Fix 15 compile errors from Phase 15-19 commit | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | SubtitlePanel ctor fix, QSP extended params, VideoZoomPanel, async observeProperty, SaverGallery positional arg, QSPState widget. fixes, ReverbSelector null-safe | 83395b5 |
| raddflix_flutter/lib/core/player/watch_party_service.dart | Added `String get myId` getter | 55914fb |

### Root cause
Phase 15-19 commit (97e5da1) introduced 15 compile errors:
1. `_SubtitlePanel` constructor had 12 extended-shortcut params (`onJumpTo`...`endAction`) that belonged in `_QuickShortcutsPanel` instead — they were added to the wrong class
2. `_QuickShortcutsPanel` missing those same 12 params in its own constructor
3. `_QuickShortcutsPanelState` used bare `onClose`, `endAction`, `silenceSkipEnabled`, `onSleepTimer`, `onSpeedSelected` without `widget.` prefix
4. `_VideoZoomPanel` (StatelessWidget) used `widget.onClose` which doesn't exist in StatelessWidget
5. `WatchPartyService` missing `myId` getter (used in player_screen.dart)
6. `_SubtitlePanel` missing `title` and `onSubtitleFilePicked` fields (used by `_SubtitlePanelState`)
7. `_SubtitlePanelState` missing `_showInfoSnackbar` method
8. `observeProperty` callback needed `async` for `Future<void>` return type
9. `SaverGallery.saveImage`: `name:` passed as named param but it's positional
10. `_ReverbSelectorState`: `_selected = v` where `v` is `String?`

### State at end of session
- Oracle Flask: RUNNING (healthz ok: {"ok":true,"version":"3.0.0"})
- APK Build: TRIGGERED (monitoring)
- Open tasks: Phase 15-19 compile fix DONE; DATA-01 (missing episodes) still open

## Session 2026-06-21 — Phase 20 Panel UI Fixes

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| UI-01 | Replace full-screen bottom sheets with right-side slide panels (45% width, 60% transparent) | ✅ DONE |
| UI-02 | Convert _showEpisodeSheet to side panel | ✅ DONE |
| UI-03 | Convert all QSP sub-sheets (7 sheets) to side panels | ✅ DONE |
| UI-04 | Fix subtitle default margin (22px → 100px) to prevent hiding behind seek bar | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | _openRightPanel: showModalBottomSheet→showGeneralDialog right-side; subtitle margin fix; 0 bottom sheets remaining | 2b477ac |

### Root cause
APK build#1210 reported 3 bugs:
1. All panels (subtitles, episodes, audio, etc.) opened as full-screen bottom sheets blocking the video — `_openRightPanel` was using `showModalBottomSheet` at 52% screen height instead of a right-side overlay
2. Subtitles hidden behind seek bar — `_subBottomMargin` default was 22px which is below the ~100px tall bottom controls bar
3. Episodes sheet used its own `showModalBottomSheet` call (not `_openRightPanel`) — same blocking behaviour

### Implementation
- `_openRightPanel`: replaced `showModalBottomSheet` with `showGeneralDialog` + `transitionBuilder` using `Positioned(right:0, width: w*0.45)` + `SlideTransition(Offset(1,0)→Offset.zero)` + `Material(color: Colors.black.withOpacity(0.60))`
- Transparent barrier with tap-to-dismiss on left 55% area so user sees live video
- `_showEpisodeSheet`: now calls `_openRightPanel(Column(...))` with header row + close button + scrollable list
- 7 QSP sub-sheets: each `showModalBottomSheet` replaced with `_openRightPanel(widget)`
- `_subBottomMargin`: default changed from 22.0 → 100.0

### State at end of session
- showModalBottomSheet calls in player_screen.dart: 0
- Commit: 2b477ac034cc6a9ab5bfd08d07426d98bc8e9b1f
- APK build needed: YES (trigger new build to verify)

## Session 2026-06-21 — MX Player-style Indicators + Full Audit

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| UI-05 | Audit entire panel/gesture/indicator system for correctness | ✅ DONE |
| UI-06 | Replace centered horizontal pill with MX Player vertical side indicators | ✅ DONE |
| UI-07 | Brightness indicator → LEFT side, Volume indicator → RIGHT side | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | MX Player-style vertical side indicators; both old centered pill methods removed | 42388f1 |

### Indicator design (now matches MX Player exactly)
- Swipe UP/DOWN on LEFT half → brightness → **amber vertical pill on LEFT edge**
- Swipe UP/DOWN on RIGHT half → volume → **white/orange vertical pill on RIGHT edge**
- Pill: 44×176px, rounded corners, 58% dark bg, bottom-to-top RotatedBox fill
- Both can show simultaneously (independent Positioned widgets)
- Auto-hide after 2s via _indicatorTimer

### Gesture code verified correct (no changes needed)
- `isLeftSide = _dragStart.dx < constraints.maxWidth / 2` ✅
- Swipe up (negative dy) → `_startX - dy * multiplier` → increases value ✅
- Brightness sensitivity: 1.5× (full swipe = 150% range, practical 0→100%) ✅
- Volume sensitivity: 3.0× (full swipe = 300%, covers 0→250% boost range) ✅
- `_swipeBVEnabled` toggle gates entire gesture ✅

### State at end of session
- showModalBottomSheet calls: 0
- Commit: 42388f138634c87095d7ffc747d152cc5e5542f2

## Session 2026-06-21 — Auto-Rotation Fix

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| ORI-01 | Fix _applyAutoOrientation: was locking to video dimensions, now uses physical sensor | ✅ DONE |
| ORI-02 | Add native Android orientation channel (com.raddflix.app/orient) | ✅ DONE |
| ORI-03 | _setNativeOrientation helper wired to initState, _cycleOrientation, dispose | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | _setNativeOrientation helper; fixed _applyAutoOrientation + _cycleOrientation + initState + dispose | fd9f8c33 |
| raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt | Added com.raddflix.app/orient channel with SCREEN_ORIENTATION_SENSOR support | 51e66362 |

### Root cause
`_applyAutoOrientation()` was LOCKING orientation to landscape or portrait based on VIDEO dimensions — not the physical sensor. So if a landscape video plays, the app locked to landscape-only and physically flipping to portrait did nothing. Additionally, `SystemChrome.setPreferredOrientations` respects the system auto-rotate toggle — if the user had it OFF, the app would never rotate regardless.

### Fix
- **Native Android API**: `Activity.setRequestedOrientation(SCREEN_ORIENTATION_SENSOR)` forces sensor-based rotation regardless of system auto-rotate setting
- **No new packages needed** — pure platform channel
- Mode 0 (auto) → `SCREEN_ORIENTATION_SENSOR` (physical sensor, ignores system toggle)
- Mode 1 (lock landscape) → `SCREEN_ORIENTATION_SENSOR_LANDSCAPE`  
- Mode 2 (lock portrait) → `SCREEN_ORIENTATION_SENSOR_PORTRAIT`
- Mode 3 (lock one side) → `SCREEN_ORIENTATION_LANDSCAPE`
- dispose() → `SCREEN_ORIENTATION_UNSPECIFIED` (lets home screen control its own orientation)


---

## Session 2026-06-21 — Player UI Overhaul Part 2: Sidebar + Rotation

### Build
- **#1218** ✅ SUCCESS — https://github.com/raddclub/raddflix-app/actions/runs/27904238382
- Run time: ~6 minutes

### Tasks Completed
| ID | Task | Status |
|----|------|--------|
| SIDEBAR-01 | Add persistent right-edge shortcut sidebar with toggle, scroll, count badge | ✅ DONE |
| SIDEBAR-02 | _SidebarCustomizerPanel: ReorderableListView reorder + add/remove + persist | ✅ DONE |
| SIDEBAR-03 | Wire 19 shortcuts to real state (CC, Audio, EQ, Speed, Loop, Rotate, Lock, PiP, Screenshot, Sleep, A-B, Episodes, Settings, Vivid, Mute, Frame, 1-Hand, Zoom, Silence) | ✅ DONE |
| SIDEBAR-04 | Fix _SidebarCustomizerPanel nested inside _ReverbSelectorState (brace bug) | ✅ DONE |
| QSP-01 | Fix dead PiP button in More menu row 6 → _enterPiP() | ✅ DONE |
| QSP-02 | Fix empty last slot in More menu → "Sidebar" customizer entry | ✅ DONE |
| ORI-01 | Fix _applyAutoOrientation: was locking to video dims, now uses physical sensor | ✅ DONE |
| ORI-02 | Add native Android orientation channel (com.raddflix.app/orient) in MainActivity.kt | ✅ DONE |

### Files Changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | All sidebar + QSP fixes | 9e8a1bf, d70ca1f |
| raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt | com.raddflix.app/orient channel | 51e66362 |

### Key Bug Found and Fixed
**Wrong closing brace insertion (build #1216-1217 failures):**
The `_SidebarCustomizerPanel` class was appended using `c.slice(0, lastIndexOf('\n}'))`
which cut off `_ReverbSelectorState`'s own closing brace. The class then appeared
to be nested inside `_ReverbSelectorState` causing ~30 compile errors.
Fix: inserted a separate `}` to close `_ReverbSelectorState` before the sidebar class,
then removed the orphan `}` that appeared at the very end of the file.

### Sidebar Architecture
```
_PlayerScreenState
  ├── bool _sidebarExpanded         ← persisted pref_sidebar_exp
  ├── List<String> _sidebarOrder    ← persisted pref_sidebar_order (JSON)
  ├── static const _allSidebarIds   ← master list of 19 shortcut IDs
  ├── _buildSidebar()               ← local fn in build(), renders the strip
  └── _openSidebarCustomizer()      ← opens _SidebarCustomizerPanel via _openRightPanel()

_SidebarCustomizerPanel             ← top-level StatefulWidget
  └── _SidebarCustomizerPanelState
        ├── ReorderableListView     ← drag handles for reorder
        ├── × button per item       ← remove from sidebar
        └── Hidden shortcuts list   ← + button to restore
```

### State at End of Session
- player_screen.dart: 7071 lines, 21 classes
- Build #1218: ✅ SUCCESS
- All 19 sidebar shortcuts wired to real state callbacks
- Drag-to-reorder fully functional via ReorderableListView
- Prefs: pref_sidebar_order (JSON string), pref_sidebar_exp (bool)

---

## Session 2026-06-23 — Fix build: const MethodChannel compile error

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUILD-FIX-01 | Remove `const` from `MethodChannel(...)` in local_media_screen.dart:378 | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/screens/local_media_screen.dart | Removed `const` before `MethodChannel(` (no const constructor) | 310016f |

### Root cause
Runs #1237–#1239 all failed on the same error: `Couldn't find constructor 'MethodChannel'` at local_media_screen.dart:378. `MethodChannel` has no `const` constructor so using `const MethodChannel(...)` is invalid Dart. Fix: removed the `const` keyword.

### State at end of session
- Oracle Flask: RUNNING
- Build: triggered after fix — monitoring
- Open tasks: none

---

## Session 2026-06-24 — Phase 22: UX Bug Fixes (6 bugs)

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-22-01 | Remove red dot from bottom nav | ✅ DONE (3d1b275) |
| BUG-22-02 | Fix grey screen on folder open — invalid (?i) regex crash | ✅ DONE (217f1e8) |
| BUG-22-03 | Bottom nav on LocalMediaScreen | ✅ DONE (7ed61f7) |
| BUG-22-04 | Bottom nav on DownloadsScreen | ✅ DONE (6a5e6e6) |
| BUG-22-05 | Bottom nav on ProfileScreen | ✅ DONE (f938e67) |
| BUG-22-06 | Player sidebar default collapsed | ✅ DONE (493d842) |

### Root causes
- **Grey folder screen**: `_seriesNameFrom()` used `RegExp(r'(?i)S\d+...')` — `(?i)` is invalid in Dart/V8 regex (throws `Invalid group`). Fixed with `caseSensitive: false` parameter.
- **Bottom nav hides**: Local/Downloads/Profile are pushed as separate named routes with no bottom nav. Added `RaddFlixBottomNav` to each with proper tap handler (popUntil root + pushNamed).
- **Dot on nav icon**: `AnimatedContainer` dot indicator removed from `_NavButton`.
- **Sidebar overlap**: `_sidebarExpanded` defaulted to `true` — changed to `false` so it starts collapsed.
- **"Open with" → home**: Handled in splash_screen (pre-existing, no code change needed).

### Files changed
| File | Change | Commit |
|------|--------|--------|
| lib/widgets/bottom_nav.dart | Remove dot indicator | 3d1b275 |
| lib/screens/local_folder_screen.dart | Fix (?i) regex | 217f1e8 |
| lib/screens/local_media_screen.dart | Add bottom nav | 7ed61f7 |
| lib/screens/downloads_screen.dart | Add bottom nav | 6a5e6e6 |
| lib/screens/profile_screen.dart | Add bottom nav | f938e67 |
| lib/screens/player_screen.dart | Sidebar default false | 493d842 |

### State at end of session
- Oracle Flask: RUNNING
- Build: triggered after fixes — monitoring
- Open tasks: none


---

## Session 2026-06-24 — Build Fix: vault_service.dart local_auth 2.x API removal

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-22-07 | Fix build: remove local_auth/auth_strings.dart import + AuthMessages usage (removed in local_auth 2.x) | ✅ DONE |

### Root cause
Builds #1250-#1254 all failed with:
- vault_service.dart:7: import 'package:local_auth/auth_strings.dart' — file does not exist in local_auth 2.x
- 'AuthMessages' is not a type
- Method not found: 'AndroidAuthMessages'

In local_auth 2.x, auth_strings.dart was removed. AuthMessages and AndroidAuthMessages no longer exist,
and the authMessages parameter was removed from authenticate(). Fix: removed the import and the
authMessages block from authenticateBiometric().

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/services/vault_service.dart | Removed auth_strings.dart import + authMessages block |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fix
- Open tasks: none
