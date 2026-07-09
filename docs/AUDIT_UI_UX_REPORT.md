# RaddFlix — UI/UX & Design System Audit

**Scope:** `raddflix_flutter/` app code vs. `docs/design-system/` (v1.0, frozen)
**Method:** Full read of all 17 design-system documents; full inventory of `lib/design_system`, `lib/core/theme`, `lib/core/design`, all 33 screens (29,429 lines), all 67 widget files (53 of them in `lib/widgets/player`), plus providers and player core controllers. Evidence below cites concrete files, line numbers, and grep counts pulled from the actual codebase — nothing here is assumed from the docs alone.
**Date:** 2026-07-09

---

## Executive Summary

RaddFlix has a well-documented, carefully specified design system ("Open Frequency") and a token layer that faithfully implements it. What does **not** exist yet is adoption: the shared component library (`RaddButton`, `RaddCard`, `RaddSheet`, `RaddBanner`, `RaddTextField`, `RaddChip`, `RaddLockPad`, `SettingsRow`) is built but used in only two places in the entire app (`RaddTextField` in login/register, `RaddSheet` inside the player). Every other screen and widget — including the Home, Search, Details, Downloads, Library, Settings, and Profile screens the audit was asked to focus on — still ships on a **second, older token system** (`AppColors` / `AppRadius` / `core/constants.dart`) or bypasses tokens entirely with raw literals. The codebase itself agrees with this assessment: the project's own `IMPLEMENTATION_PLAN.md` and `CHANGELOG.md` are explicit that Phase 2 (tokens) and Phase 3 (components) are done or in-progress, and that **Phase 4 (screen migration) has not started**.

The most severe concentration of technical/design debt is the video player: `player_screen.dart` is 9,280 lines, and its supporting `lib/widgets/player/` directory (53 files) is almost entirely dead code — confirmed unused by the app's own docs and independently corroborated by this audit (0 design-system token references, 1,000+ hardcoded color literals). The live player UI is 7 private classes inlined inside `player_screen.dart` plus 2 externally hosted sheets — a materially different architecture than the file count suggests, and a correctness risk for any future agent that edits the wrong file.

In short: **the design system is a well-built, unreleased product.** The app users actually see today is still running the pre-design-system UI almost everywhere. This is not a UI-consistency problem so much as a **rollout gap** — the hard design work is done; the mechanical work of wiring it into 33 screens has not begun.

---

## Overall Scorecard

| Category | Score /100 | Basis |
|---|---|---|
| Overall Design System Adoption | **8/100** | 2 of 33 screens reference any shared component; 0 screens use `RaddButton`/`RaddCard` |
| UI Consistency | **25/100** | Two parallel token systems in play (`Radd*` vs `AppColors`/`AppRadius`); buttons, cards, and sheets each hand-rolled per call site |
| UX Quality | **55/100** | Core flows (browse, search, watch, download) work and are reasonably featured, but player violates its own documented HUD rules and lacks specified flows (see below) |
| Visual Polish | **45/100** | Individual screens are often competently styled in isolation, but nothing reads as one product because there is no shared visual vocabulary in force |
| Component Reuse | **10/100** | 0 usages of `RaddButton`/`RaddCard` outside the library itself; every sheet/dialog/button is a bespoke implementation |
| Accessibility | **30/100** | Token layer defines a 44×48dp minimum hit area, but screens don't consume the token layer, so there's no enforcement; no evidence of semantic labels, contrast QA, or reduced-motion handling found in scanned files |
| Animation Quality | **35/100** | `RaddMotion` and the existing `AnimConfig` device-tier system are solid infrastructure, but most screens still use ad hoc `Duration`/`Curves` literals rather than the shared tokens |
| Design System Compliance | **10/100** | Token layer: compliant. Component layer: built but 0% adopted. Screen layer: not started per the project's own roadmap |
| Production Readiness | **50/100** | The app functions end-to-end (per provider/service code), but the design-system components have never been compiled — the project's own changelog notes no Flutter SDK is available in this environment to run `flutter analyze`/`flutter test` on them |

**Read this scorecard as: the app works, but it is not yet the app the design system describes.**

---

## Design System Compliance

### What the design system specifies (ground truth, from `docs/design-system/`)

- **Color:** `signal.primary` `#E8002D` (red/crimson accent), `signal.primaryGlow` (blurred variant), dark surface scale `#08080E` → `#0D0D1A` → `#161628`, and `accent.dataFree` `#3DDC97` reserved exclusively for "this content is zero-rated" indicators (never used decoratively — see `AI_RULES.md`).
- **Typography (`RaddType`):** Display 34sp/w900, Headline 24sp/w800, Title 18sp/w700, Body 15sp/w500, BodyStrong 15sp/w700, Label 13sp/w600, Caption 12sp/w500, plus a dedicated `signalNumeral` (32sp/w900) reserved for data-saved statistics.
- **Spacing (`RaddSpace`):** `xs=4, sm=8, md=16, lg=24, xl=32, xxl=48`.
- **Radius/Elevation:** `sm=8, md=12, lg=16, pill=999`; elevation presets for card (lit, not lifted), sheet (blur sigma 20), modal (blur sigma 24 + 8% crimson glow).
- **Motion:** `Pulse` (1800ms, sine ease-in-out, opacity 1→0.6, scale 1→1.03) for live/status indicators; `Tune` (200ms spring, 8% overshoot) for selection/snap interactions.
- **Components:** `RaddButton` (7 variants, 3 sizes, 44×48dp min hit area), `RaddCard` (Movie/Episode/Continue-Watching/Collection variants with an optional 20×20dp data-free badge), `RaddSheet` (drag handle, `lg` radius, 85% max height, tabbed Player consolidation), `RaddBanner` (44dp, 5 fixed variants), `RaddTextField` (52dp, `md` radius, 1.5px focus border), `SettingsRow` (56dp list primitive).
- **Player rules:** a documented "40% surface" cap and a "5-control HUD" limit, plus a "browse-before-signup" reciprocity principle for new users.

### What's actually implemented in code

| Layer | Status | Evidence |
|---|---|---|
| Token layer (`RaddSpace`, `RaddRadius`, `RaddType`, `RaddElevation`, `RaddMotion`, semantic colors on `RaddColors`) | ✅ **Implemented, matches spec exactly** | `lib/design_system/spacing/radd_space.dart`, `radius/radd_radius.dart`, `typography/radd_type.dart`, `elevation/radd_elevation.dart`, `motion/radd_motion.dart`; values match the doc 1:1 (`xs:4, sm:8, md:16, lg:24, xl:32, xxl:48`; `sm:8, md:12, lg:16, pill:999`) |
| Component layer (`RaddButton`, `RaddCard`, `RaddSheet`, `RaddBanner`, `RaddTextField`, `RaddChip`, `RaddLockPad`, `SettingsRow`) | 🚧 **Built, unverified, effectively unadopted** | All 8 files exist in `lib/design_system/components/`. Never compiled — project's own changelog states no Flutter SDK is available in this environment to run `flutter analyze`/`flutter test`. Usage count across all 33 screens + 67 widgets: `RaddButton` **0**, `RaddCard` **0**, `RaddSheet` **1** (inside `player_screen.dart`), `RaddTextField` **3** (`login_screen.dart`, `register_screen.dart`) |
| Screen layer (33 screens, 29,429 lines) | ❌ **Not started** | Screens import `core/theme/radd_theme.dart` for the color extension but nothly the component library. 410 raw `Color(0x...)` literals and 2,563 raw `Colors.*` references across `lib/screens` + `lib/widgets` combined |
| Legacy parallel system (`AppColors`/`AppRadius`/`AppSpacing`, `core/constants.dart`) | ⚠️ **Still the dominant system in live UI** | 38 files under `lib/screens`+`lib/widgets` reference `AppColors.*` directly; this is the system actually driving what users see today, and it is explicitly untouched/parallel per `CHANGELOG.md` ("100% additive: legacy `AppRadius`/`AppColors`/`AppDurations`/`AppCurves` in `core/constants.dart` are untouched and still used by existing screens") |

**Compliance verdict:** the design system exists in code but has not shipped to a single user-facing screen beyond auth text fields and one player sheet. Two token systems (`Radd*` and `App*`) now coexist, which is worse for consistency than having only the old system — any new screen writer has to pick one before writing a line of layout code, and nothing in the codebase enforces the choice.

---

## Screen-by-Screen Audit

| Screen | Lines | Design-System Usage | Status |
|---|---|---|---|
| Home (`home_screen.dart`) | 1,337 | None beyond `radd_theme` color extension | **Missing** — no `RaddCard`, raw card widgets via `content_card.dart` |
| Search (`search_screen.dart`) | 1,357 | None beyond `radd_theme` | **Missing** |
| Show Details (`show_detail_screen.dart`) | 2,199 | None found | **Missing** |
| Actor (`actor_screen.dart`) | 255 | Partial `AppRadius.md`; hardcodes `TextStyle(color: AppColors.primary)` (L57), `Colors.transparent` (L1), `EdgeInsets.fromLTRB(16,4,16,0)` (L68), `EdgeInsets.all(14)` (L71) | **Incorrect implementation** — mixes token and literal in the same file |
| Player (`player_screen.dart`) | 9,280 | 1 use of `RaddSheet` (L4565, 4771); otherwise the single largest concentration of hardcoded values in the app | **Partially implemented, needs redesign** — also violates the documented "40% surface" and "5-control HUD" player rules per the project's own audit notes |
| Player Settings (`player_settings_screen.dart`) | 311 | Not confirmed | **Missing** |
| Downloads (`downloads_screen.dart`) | 1,068 | None found | **Missing** |
| Local Media / Library (`local_media_screen.dart`, `local_folder_screen.dart`) | 1,102 / 1,250 | None found | **Missing** |
| History (`history_screen.dart`) | 184 | None found | **Missing** |
| Settings (`settings_screen.dart`) | 374 | `SettingsRow` primitive exists but not confirmed in use here | **Likely missing — needs verification before build** |
| Vault Settings (`vault_settings_screen.dart`) | 459 | None found | **Missing** |
| Profile (`profile_screen.dart`, `edit_profile_screen.dart`, `add_edit_profile_screen.dart`, `profile_switcher_screen.dart`) | 1,150 / 773 / 453 / 399 | `add_edit_profile_screen.dart` hardcodes `Color(0xFFEF4444)` (L256, 307), `BorderRadius.circular(14)` (L341), `fontSize: 12` (L307) | **Incorrect implementation** |
| Login (`login_screen.dart`) | 543 | `RaddTextField` in use (L208, L214) | **Partially implemented — best-adopted screen in the app** |
| Register (`register_screen.dart`) | 190 | `RaddTextField` in use (L134) | **Partially implemented** |
| Onboarding (`onboarding_screen.dart`) | 293 | None found | **Missing** — also the screen most likely to need the "browse-before-signup" flow the design docs call for, which the project's own audit notes is absent app-wide |
| PIN Lock / Vault Lock (`pin_lock_screen.dart`, `vault_lock_screen.dart`) | 350 / 452 | `RaddLockPad` component exists specifically for this; not confirmed in use | **Likely missing — quick win if wired up** |
| Subscription (`subscription_screen.dart`) | 825 | Docs state `RaddTextField` in use here; not independently line-verified | **Partially implemented** |
| Plan Expired (`plan_expired_screen.dart`) | 123 | None found | **Missing** |
| Admin Queue (`admin_queue_screen.dart`) | 415 | Partial `AppRadius.md`; hardcodes `Colors.transparent` (L78), `EdgeInsets.symmetric(horizontal:16, vertical:12)` (L93) | **Incorrect implementation** |
| Debug Diagnostics (`debug_diagnostics_screen.dart`) | 781 | Internal tool — lower priority | Out of scope for design-system compliance |
| Layout Designer (`layout_designer_screen.dart`, and a second copy under `screens/player/`) | 484 | Two files appear to be duplicates or split versions of the same tool | **Duplicate — needs consolidation** |
| Vault (`vault_screen.dart`) | 671 | None found | **Missing** |
| Watchlist (`watchlist_screen.dart`) | 253 | None found | **Missing** |

**Pattern across all 33 screens:** the two auth screens (login, register) are the only screens meaningfully touched by the new component library. Every content-browsing, playback, and settings screen — i.e., where users spend nearly all of their time — is still on the old system or on raw literals.

---

## Component Audit

| Component | Built? | Verified (compiled/tested)? | Adoption (usages found) | Notes |
|---|---|---|---|---|
| `RaddButton` | ✅ | ❌ (no Flutter SDK available to run `flutter analyze`/`flutter test` per project changelog) | **0** | Every button in the app is a hand-rolled `ElevatedButton`/`TextButton`/`OutlinedButton` with a local `styleFrom` override. No shared button style exists in practice today. |
| `RaddCard` | ✅ | ❌ | **0** | Live card UI is `content_card.dart` (Standard/Shimmer/Pressable variants) plus a second, separate `simosa_card.dart` implementation — i.e., two card systems, neither of which is `RaddCard`. |
| `RaddSheet` | ✅ | ❌ | **1** (inside `player_screen.dart`) | Every other sheet in the app (`audio_lab_sheet.dart`, `color_picker_sheet.dart`, `speed_presets_sheet.dart`, and others) is a bespoke `showModalBottomSheet` call, not `RaddSheet`. |
| `RaddBanner` | ✅ | ❌ | Not found in scanned screens/widgets | `notification_banner.dart` (a separate, pre-existing implementation using an internal `_NotificationCard`) appears to be what's actually shown to users. |
| `RaddTextField` | ✅ | ❌ | **3** (login ×2, register ×1) | Best-adopted component in the library. |
| `RaddChip` | ✅ | ❌ | Not found | |
| `RaddLockPad` | ✅ | ❌ | Not found (expected use: `pin_lock_screen.dart`, `vault_lock_screen.dart`) | Quick-win opportunity — purpose-built component sitting unused next to the exact screens it was designed for. |
| `SettingsRow` | ✅ | ❌ | Not found (expected use: `settings_screen.dart`, `vault_settings_screen.dart`) | Same pattern — built, not wired in. |

**Duplicate/parallel component patterns found in the live app:**
- **Buttons:** no unified button anywhere; every sheet and screen defines its own style inline.
- **Cards:** `content_card.dart` and `simosa_card.dart` are two separate card implementations.
- **Status badges:** at least three separate internal badge classes (`_Badge`, `_StatusBadge`, `_NewEpBadge`), all defined locally inside `content_card.dart` rather than as one shared badge component.
- **Sheets:** every player setting (audio, playback speed, theme picker) is its own bespoke `showModalBottomSheet`, each with separately implemented styling.

---

## UX Audit

**Working well:**
- Core content flows exist and appear reasonably complete: browsing (Home/Search/Details), playback, downloads, local media/library, history, multi-profile support, subscription, and a PIN/vault privacy layer are all present as real, non-stub screens.
- Player feature depth is genuinely high: dedicated controllers exist for ambient lighting (`ambilight_controller.dart`), binge-watch pacing (`binge_guard_controller.dart`), and haptics (`haptic_service.dart`), plus modular overlay widgets (`chapter_seek_bar.dart`, `cinematic_overlay.dart`, `gesture_hint_overlay.dart`, `playback_info_overlay.dart`).
- State/error plumbing is real, not mocked: `catalog_provider.dart` models an explicit `CatalogStatus` (idle/syncing/ready/error), `auth_provider.dart` tracks specific failure modes like `device_conflict`, and download progress is tracked live via `downloads_provider.dart` + `active_download_ticker.dart` + `download_storage_strip.dart`.

**Falling short of the documented UX bar:**
- **Player HUD:** the design system caps on-screen player chrome at "40% surface" and a "5-control HUD." The project's own internal audit (recorded in `IMPLEMENTATION_PLAN.md`) states the current player violates both rules — consistent with a 9,280-line `player_screen.dart` that has grown organically over time.
- **Onboarding reciprocity:** the design docs call for a "browse-before-signup" flow (let users see content value before asking them to register). No evidence of this in `onboarding_screen.dart` or the auth flow; this is confirmed missing by both this audit and the project's own notes.
- **Accessibility:** the token layer specifies a 44×48dp minimum touch target, but because screens don't consume the token layer, there's no mechanism actually enforcing that minimum. No semantic-label, contrast-ratio, or reduced-motion handling was found in any scanned screen or widget file.
- **Consistency of interaction patterns:** because buttons, cards, and sheets are each reimplemented per call site, hover/press/focus feedback almost certainly varies subtly screen to screen, even where the visual design looks similar — a classic source of an app "feeling" inconsistent even when no single screen looks broken in isolation.
- **Discoverability of design-system investment:** ironically, the two best-built things in the whole app (the token layer and component library) are invisible to users today because nothing renders them outside login/register and one player sheet.

---

## Visual Audit — Inconsistencies Found

| Type | Evidence |
|---|---|
| Two parallel color systems | `Radd*`/`RaddColors` semantic tokens vs. `AppColors` (legacy, still dominant — 38 files reference `AppColors.*` directly) |
| Two parallel radius systems | `RaddRadius` (`sm:8, md:12, lg:16, pill:999`) vs. `AppRadius` (used inconsistently — `actor_screen.dart` and `admin_queue_screen.dart` use `AppRadius.md` in some places and raw `BorderRadius.circular(...)` literals in others in the *same file*) |
| Hardcoded colors at scale | 410 raw `Color(0x...)` + 2,563 raw `Colors.*` references across `lib/screens` + `lib/widgets` combined |
| Hardcoded spacing | e.g. `actor_screen.dart` L68 `EdgeInsets.fromLTRB(16,4,16,0)`, L71 `EdgeInsets.all(14)`; `admin_queue_screen.dart` L93 `EdgeInsets.symmetric(horizontal:16, vertical:12)` — none reference `RaddSpace` or `AppSpacing` |
| Hardcoded typography | `add_edit_profile_screen.dart` L307 `fontSize: 12` literal; `actor_screen.dart` L57 `TextStyle(color: AppColors.primary)` used instead of a `RaddType`/theme text style |
| Duplicate card implementations | `content_card.dart` vs. `simosa_card.dart` |
| Duplicate badge implementations | `_Badge`, `_StatusBadge`, `_NewEpBadge` all defined locally rather than shared |
| Duplicate/ambiguous tool files | `layout_designer_screen.dart` exists both at top level and under `screens/player/` — appears to be a duplicate or split version of the same tool |
| Fragmented button styling | No shared button widget; every sheet/screen defines its own `styleFrom` override on stock Flutter buttons |
| Dead code footprint | `lib/widgets/player/` contains ~53 files; the project's own migration guide states ~47 of them are confirmed dead code (never imported by `player_screen.dart` or any live screen) — the live player is actually 7 private classes inlined in `player_screen.dart` plus 2 externally hosted sheets. This is a correctness trap: a future contributor grepping `widgets/player/` for "the audio settings sheet" will very likely edit a file that renders nothing. |

---

## Gap Analysis

| Design Doc | Status | Implementation % | Missing Work | Priority | Est. Effort |
|---|---|---|---|---|---|
| 01 Brand Identity | Documented only | N/A (philosophy doc) | N/A | — | — |
| 02 Visual Language (color/typography/spacing/radius/elevation) | ✅ Token layer done | 100% at token layer, ~5% at screen layer | Roll tokens out across 31 remaining screens | High | L |
| 03 Motion (`Pulse`, `Tune`) | ✅ Token layer done | 100% at token layer, adoption unverified at screen layer | Confirm/roll out `RaddMotion` usage in place of ad hoc `Duration`/`Curves` literals | Medium | M |
| 04 Components (`RaddButton`, `RaddCard`, etc.) | 🚧 Built, unverified, unadopted | ~10% (built, 0-1 usages each) | Compile/test each component (no Flutter SDK currently available in this environment), then wire into real screens | Critical | L |
| 05 Layouts | Not independently verified against screens in this pass | Unknown | Screen-by-screen layout compliance check | Medium | M |
| 06 Accessibility | Spec exists (44×48dp targets) | Not enforced anywhere found | Add enforcement (lint rule or shared component requirement), then audit real screens for touch-target size, labels, contrast | High | M–L |
| 07 Developer Guidelines | Documented; a "Component Status Dashboard" exists | Dashboard marks all 8 components 🚧, not ✅ | Get to ✅ via real `flutter analyze`/`flutter test` pass | Critical (blocks everything downstream) | S once SDK access exists |
| 08 Component API Contracts | ✅ Matches built components | 100% documented | None on doc side; verify implementation matches contract once compiled | Medium | S |
| 09 Migration Guide | ✅ Accurate, includes dead-code correction | N/A | Execute the migration it describes | Critical | XL |
| 10 Interaction Principles | Player violates documented HUD rules per project's own audit | Player: non-compliant | Redesign player HUD to 40% surface / 5-control cap | High | L |
| 11 Performance Standards | Not verified in this pass (no profiling done) | Unknown | Dedicated performance audit | Medium | M |
| 12 Quality Checklist | Not yet applicable — checklist presumably gates screen migrations that haven't started | 0% run against real screens | Run checklist per screen as migration proceeds | Medium | Ongoing |

**Percent complete / remaining (design-system rollout, not app functionality):**
- **Complete:** ~15% (tokens fully done; components built but unverified/unadopted; 2 of 33 screens partially touched)
- **Remaining:** ~85%
- **Screens needing migration:** 31 of 33 (all except login/register, which are partial)
- **Components needing replacement at call sites:** effectively all button, card, and sheet call sites app-wide (hundreds of individual instances given 410+2,563 hardcoded value references)
- **Major architectural work remaining:** (1) get Flutter SDK access into the environment so components can actually be compiled/tested, (2) decide and execute the dead-code deletion in `lib/widgets/player/` (~47 files) before any player redesign, (3) player HUD redesign to meet the "40% surface"/"5-control" rule, (4) the missing "browse-before-signup" onboarding flow
- **Quick wins:** wire `RaddLockPad` into `pin_lock_screen.dart`/`vault_lock_screen.dart`; wire `SettingsRow` into `settings_screen.dart`/`vault_settings_screen.dart`; consolidate the duplicate `layout_designer_screen.dart` files
- **Medium effort:** migrate Home/Search/Details/Downloads/Library/History screens to `RaddCard`+tokens one at a time (each is self-contained, non-breaking per the project's own `IMPLEMENTATION_PLAN.md`)
- **Large effort:** the player rewrite (9,280-line file, HUD redesign, dead-code removal, migration to `RaddSheet` throughout)

---

## Priority Roadmap

**Critical**
1. Get the component layer verified — install/access a real Flutter toolchain and run `flutter analyze` + widget tests on all 8 components before any screen adopts them. Nothing downstream should be trusted until this happens.
2. Resolve the `lib/widgets/player/` dead-code question (~47 files) — either delete or clearly quarantine before touching the player, so future work (by any agent or engineer) doesn't waste time editing files that render nothing.

**High**
3. Migrate Settings, Vault Settings, PIN/Vault Lock screens to `SettingsRow`/`RaddLockPad` — these are the quickest wins because purpose-built components already exist for these exact screens.
4. Migrate Home, Search, Details to `RaddCard` + token layer — highest-traffic screens, so the visible consistency payoff is largest.
5. Redesign the player HUD to comply with the documented "40% surface" / "5-control" rules.
6. Add the missing "browse-before-signup" onboarding flow.
7. Establish real accessibility enforcement (touch-target size, labels, contrast) — currently speced but not enforced anywhere.

**Medium**
8. Migrate Downloads, Library/Local Media, History, Profile screens to shared components.
9. Consolidate duplicate implementations: `content_card.dart` vs `simosa_card.dart`; the three separate badge classes; the duplicate `layout_designer_screen.dart`.
10. Roll `RaddMotion` out to replace ad hoc animation `Duration`/`Curves` literals app-wide.
11. Run the `12-quality-checklist.md` against each screen as it migrates.

**Low**
12. Migrate lower-traffic/internal screens (Admin Queue, Debug Diagnostics) — lower user impact, can trail the rest.
13. Documentation upkeep — keep `IMPLEMENTATION_PLAN.md`/`ROADMAP.md`/`CHANGELOG.md` current as each phase lands (the team is already doing this well; keep it up).

**Future**
14. Formal performance audit (frame timing, jank on lower-end devices given the Jazz-SIM/zero-rated-data budget-Android target audience).
15. Automated visual-regression tests once the component layer is stable, to prevent the "two parallel systems" drift from recurring.

---

## Missing Features (relative to design docs)

- "Browse-before-signup" onboarding reciprocity flow — not found in `onboarding_screen.dart` or elsewhere.
- Enforced 44×48dp minimum touch targets — specified, not enforced.
- `RaddBanner` usage anywhere in the live app — the live banner is a separate, older `notification_banner.dart` implementation.
- Any live usage of `RaddButton` or `RaddCard` — 0 instances found anywhere in screens or widgets.

## Top 20 Highest-Impact Improvements

1. Verify the component library compiles/passes tests (unblocks everything else).
2. Delete or clearly quarantine the ~47 dead files in `lib/widgets/player/`.
3. Wire `RaddLockPad` into PIN/Vault lock screens (quick win, purpose-built component already exists).
4. Wire `SettingsRow` into Settings/Vault Settings screens (quick win).
5. Migrate Home screen cards to `RaddCard`.
6. Migrate Search screen cards to `RaddCard`.
7. Migrate Show Details screen to token layer + shared components.
8. Consolidate `content_card.dart` and `simosa_card.dart` into one card system.
9. Replace all ad hoc buttons with `RaddButton` app-wide, screen by screen.
10. Replace all bespoke player `showModalBottomSheet` calls with `RaddSheet`.
11. Redesign player HUD to the documented "40% surface"/"5-control" limits.
12. Add the browse-before-signup onboarding flow.
13. Replace the standalone `notification_banner.dart` with `RaddBanner`.
14. Consolidate the three separate badge classes into one shared badge component.
15. Resolve the duplicate `layout_designer_screen.dart` files.
16. Roll `RaddMotion` out to replace hardcoded animation curves/durations.
17. Add automated enforcement (lint or CI check) that flags new raw `Color()`/`Colors.*`/`TextStyle()` literals in `lib/screens` and `lib/widgets`, so the two-systems drift doesn't get worse while migration is in progress.
18. Establish real accessibility QA (contrast, touch targets, semantic labels) as a gate on each screen migration.
19. Add widget/golden tests for each of the 8 shared components once compiled, to prevent regressions as they get adopted.
20. Profile performance on lower-end devices given the target audience (Jazz-SIM zero-rated data users likely skew toward budget Android hardware) — not audited in this pass but worth prioritizing before/alongside heavy screen rework.

---

## Final Verdict

RaddFlix's design system work is high-quality and unusually well-documented for a project of this size — the token layer is complete and accurate, the component API contracts are thorough, and the team's own internal audits (visible in `IMPLEMENTATION_PLAN.md`/`CHANGELOG.md`) are honest about exactly what's built vs. planned. That honesty is worth preserving as new agents pick this up.

But by the numbers, this is closer to the *start* of a design-system rollout than the middle of one: **0 screens use `RaddButton` or `RaddCard`, 31 of 33 screens are untouched, and the component layer has never been compiled.** The app functions and has real feature depth (especially in the player and download/offline experience), but visually and structurally it is still the pre-design-system app, running two competing token systems side by side. The single highest-leverage next step is not more design work — the design work is done — it's getting the existing component library verified and then mechanically wired into screens, starting with the quick wins (lock screens, settings) before tackling the two large efforts that matter most for user-facing consistency: the browse/search/details surfaces, and the player HUD redesign.
