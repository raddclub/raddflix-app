# RaddFlix Design System — Changelog

## v1.0 — 2026-07-08
- Initial complete design system, produced through a four-stage process: codebase audit → UX analysis & modernization strategy → brand identity & redesign blueprint ("Open Frequency") → construction-level specification.
- All 12 volumes written: Brand Identity, Visual Language, Motion, Components, Layouts, Accessibility, Developer Guidelines, Component API Contracts, Migration Guide, Interaction Principles, Performance Standards, Quality Checklist.
- Documentation frozen at v1.0 by design decision — no further volumes planned; next steps move into implementation per `ROADMAP.md`.
- No app code changed as part of producing this documentation.

## 2026-07-08 — Psychology-principle addendum
- Volume I: added "Reciprocity — Value Before Ask" — first-run flow must show real free content before any login wall.
- Volume V: reworked onboarding wireframe into a 3-step taste-capture → starter-watchlist → signup flow; progress never starts at 0% (goal gradient effect); final CTA reads "Save & Continue," not "Sign Up" (endowment effect).
- Volume X: added Loss-Framing Rules (Plan Expired/Quota Full copy) and Price-Anchoring Rules (Subscription screen) — both content/ordering rules, no dark patterns.
- Source: external UX-psychology video review (smart defaults, goal gradient, reciprocity, IKEA/endowment effect, loss aversion, contrast effect) cross-checked against existing docs; smart-defaults principle judged not applicable (RaddFlix has few blank-form moments).

## 2026-07-08 — Implementation Plan added
- Added `IMPLEMENTATION_PLAN.md`: maps every token and component from v1.0 to the existing Flutter codebase (current files to modify, create-vs-refactor decisions, dependencies, complexity, breaking changes, recommended safest order). Planning only — no code changed.

## 2026-07-08 — Player architecture correction (docs error, not a code change)
- **Corrected a factual error in `09-migration-guide.md` and `IMPLEMENTATION_PLAN.md`.** Both previously described the Player as 24-50 external sheet/panel files under `widgets/player/`. A live import trace against the actual `raddflix_flutter` code found this was wrong: the app author had already removed those files from active use.
- **Verified real architecture:** the live Player UI is **7 private classes defined inline inside `player_screen.dart`** (`_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel`, `_QuickShortcutsPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel`), plus 2 externally-hosted sheets (`color_picker_sheet.dart`, `theme_picker_sheet.dart`) used by the separate `PlayerSettingsScreen`, plus 2 shared non-panel helpers (`seek_bar_painter.dart`, `binge_guard.dart`).
- **~47 files in `widgets/player/`** (full list in `09-migration-guide.md`) are confirmed dead code — never imported by `player_screen.dart` or any live screen. Left on disk as leftovers from an earlier architecture. Not part of the Player consolidation scope; tracked separately as a delete/audit task.
- No app code changed to produce this correction — docs only. See `agent-hub/TASKS.md` (PLAYER-DOCS-CORRECTION) and `agent-hub/history/TASK_LOG.md` for the task-tracking side of this fix.

## 2026-07-08 — Phase 2 implementation: Theme Tokens
- Implemented the token layer per Volume VII Build Order: `lib/design_system/spacing/radd_space.dart`, `radius/radd_radius.dart`, `typography/radd_type.dart`, `motion/radd_motion.dart`, `elevation/radd_elevation.dart`.
- `RaddType` exposed as a `BuildContext` extension so styles inherit the active brand font from `JazzThemeData.build()` rather than hardcoding a font family in the token layer.
- `RaddMotion` wraps the existing `AnimConfig` tier system rather than duplicating its device-tier gating logic.
- Added semantic color getters (`signalPrimary`, `signalPrimaryGlow`, `accentDataFree`, `accentWarning`, `accentError`) to the existing `RaddColors` `BuildContext` extension, plus `AppColors.dataFree` (`#3DDC97`, protected — see AI_RULES.md rule 7).
- 100% additive: legacy `AppRadius`/`AppColors`/`AppDurations`/`AppCurves` in `core/constants.dart` are untouched and still used by existing screens — no visual or behavioral change to the shipped app from this change alone.
- Component Status Dashboard (`07-developer-guidelines.md`) and `ROADMAP.md` updated to reflect Phase 2 done; Phase 3 (`RaddButton`, `RaddCard`, `RaddSheet`, etc.) can now consume these tokens.

## 2026-07-08 — Phase 3 implementation: Shared Components
- Implemented `lib/design_system/components/`: `RaddButton`, `RaddCard`, `RaddSheet`, `RaddBanner`, `RaddTextField`, `RaddChip`, `RaddLockPad`, `SettingsRow` — matching the Volume IV catalog and Volume VIII API contracts.
- Wrote the 4 previously-missing Volume VIII contracts (`RaddChip`, `RaddLockPad`, `SettingsRow`, `RaddTextField`) into `08-component-api-contracts.md`.
- `RaddSheet` includes a static open guard so a second `RaddSheet.show` call dismisses the first instead of stacking (Volume X rule). `RaddBanner` ships a `raddBannerPriority` map for call-site queuing (error > subscription > offline > rest).
- **Important caveat:** this Replit environment has no Flutter SDK installed (only a Dart-Tools module, which lacks the `material`/`widgets` libraries), so none of these components have been compiled or run through a widget test yet — only manually checked for brace/paren/bracket balance. Component Status Dashboard marks all eight 🚧 In Progress, not ✅ Production, until a real `flutter analyze`/`flutter test` pass (e.g. via CI or a local machine) confirms them.
- 100% additive: no existing screen imports or renders any of these yet — zero behavior change to the shipped app.

<!-- Add new entries above this line, newest first. Record principle overrides, token changes, and structural revisions here — not routine implementation progress, which belongs in ROADMAP.md. -->
