---
name: UX4 task batch
description: 14 UX improvement tasks added 2026-07-17; priority order and implementation notes
---

## Priority order
P0 (critical/blocking): UX4-01, UX4-02, UX4-03
P1 (significant friction): UX4-04, UX4-05, UX4-06, UX4-07, UX4-08
P2 (polish/accessibility): UX4-09, UX4-10, UX4-11, UX4-12
P3 (minor consistency): UX4-13, UX4-14

## Key implementation notes

**UX4-01 (IndexedStack nav)**
The current architecture pushes all non-Home tabs as separate routes. To fix:
- `HomeScreen` must become a shell with an `IndexedStack` of 5 children.
- Each child (Home, Search, Local, Downloads, Profile) is kept alive with `AutomaticKeepAliveClientMixin`.
- The `MiniPlayerDock` and `RaddFlixBottomNav` live at the shell level, not inside each child.
- `Navigator.pushNamed` calls for tabs are replaced by `setState(() => _navIndex = i)`.
- Routes for those screens (AppRoutes.search etc.) still exist for deep links/other callers — don't remove them.

**UX4-03 (textScaler)**
Two locations:
1. `app.dart:203` — remove the `MediaQuery.copyWith(textScaler: TextScaler.linear(1.0))` line entirely.
2. `bottom_nav.dart:241` — remove `textScaler: TextScaler.noScaling` from the nav label Text widget.
Watch for overflow: after enabling scaling, test nav labels and small badge texts for overflow.

**UX4-04 (ShowDetail scroll)**
Replace `_scrollOffset` state var + `_onScroll` setState with `ValueNotifier<double>`.
Only the parallax hero image (`_buildHeroImage`) should listen via `ValueListenableBuilder`.
Everything else (episode list, cast rail, buttons) must NOT rebuild on scroll.

**UX4-05 (Theme toggle in Settings)**
`_ThemePicker` and `_ThemeTrailing` are private in `profile_screen.dart`.
Options:
A) Rename to `ThemePickerSheet`/`ThemeTrailing` (remove underscore) — breaks nothing since they're not exported.
B) Create `lib/widgets/theme_picker_sheet.dart` and move both classes there.
Option B is cleaner (shared widget, importable from both profile and settings).
`settings_screen.dart` needs `import '../core/theme/theme_provider.dart'` (already imported indirectly in profile).

**UX4-11 (GlintOverlay)**
Each `ContentCard` runs its own `AnimationController`. With 30–50 cards on screen, this is 30–50 concurrent timers.
Fix options:
A) Use a single `InheritedWidget` / `ChangeNotifier` tick that all visible cards share.
B) Gate `_GlintOverlay` only on `animConfig.canMorph` (Tier 3) instead of `canStagger` (Tier 1+).
Option B is a 2-line fix with immediate battery/CPU benefit on mid-range devices. Start with B.
