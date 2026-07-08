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

## 2026-07-08 — Full docs-vs-reality implementation audit
- Ran a full audit comparing every volume against the actual `raddflix_flutter` codebase (see `agent-hub/TASKS.md` DS-AUDIT-2026-07-08 for the complete findings and follow-up scope). Summary:
  - **Token layer (Volume II/III):** all 5 modules exist and mostly match spec, except `RaddMotion`'s `Pulse`/`Tune` durations/curves don't match the documented values (implementation: 1200ms/800ms-potato easeOutCubic vs. spec: 1800ms loop / 200ms spring+8% overshoot) — needs a decision on which is correct before either is called "done." Zero real screens/widgets outside `lib/design_system/` consume any token yet.
  - **Component library (Volume IV/VIII):** all 8 components are fully implemented. `RaddTextField` is already live in 3 screens (login, register, subscription) — corrected in the Component Status Dashboard (`07-developer-guidelines.md`), which previously said 0. The other 7 remain unused anywhere.
  - **Screens (Volume V):** Home, Search, Show Detail, Player, and Settings are all still on the pre-redesign implementation — 0% migrated, matching `ROADMAP.md`'s Phase 4-9 checkboxes (correctly unchecked). No design-system component or token is used in any of these screens' own code.
  - **Interaction principles (Volume X) — Player specifically found in active violation, not just "not yet migrated":** current HUD exposes 12-14 persistent controls (target: 5 + one "More" sheet); side panels open at 55% screen-width (target: ≤40%); opening a panel explicitly pauses video in several places (target: video must never be blocked by a sheet); auto-hide is 4s (target: 3s). These are documented as known gaps to close during the eventual Player consolidation, not new regressions.
  - **Reciprocity principle (Volume I):** currently violated — `splash_screen.dart` routes an unauthenticated user straight to the login screen; there's no browse-before-signup path yet. This is a product decision, not merely an unmigrated screen — needs explicit sign-off before implementing, since it changes real auth-gating behavior.
  - **Accessibility (Volume VI) & modal discipline (Volume XII):** `Semantics(`/`tooltip:` coverage is low and concentrated in a few files; 47 raw `showModalBottomSheet`/`showDialog`/`AlertDialog` call sites exist app-wide that the eventual `RaddSheet` migration is meant to replace.
- No app code was changed to produce this audit — docs-only, informational baseline for future migration planning.
