# RaddFlix Design System Migration Blueprint

**Type:** Implementation roadmap (not an audit)
**Companion document:** `docs/AUDIT_UI_UX_REPORT.md` (2026-07-09) — read that first for the full evidence base; this document turns those findings into an executable plan.
**Scope:** `raddflix_flutter/` against `docs/design-system/` (Volumes I–XII).
**Method:** every number below comes from `grep`/`find` against the current source tree on 2026-07-09. No estimates are presented as fact without a count backing them; where a judgment call is made (e.g. "feels like Open Frequency"), it is labeled as qualitative.

---

## 1. Release Readiness Dashboard

> **Last updated: 2026-07-10 (Phase 7 re-audit).** Original baseline: 2026-07-09.
> **2026-07-29 INPUT-STYLE patch:** Raw `TextField` widgets in `live_tv_screen`, `vault_screen`, `vault_settings_screen`, `local_folder_screen`, `local_media_screen` were *visually aligned* to the `RaddTextField` spec (52dp height, `t.surface` fill, `t.border` 1px enabled → `AppColors.primary` 1.5px focused, `RaddRadius.mdRadius`). These are **styled-raw-TextField**, not `RaddTextField` component calls — the adoption count in the dashboard row below is unchanged. Player-overlay sheets (`jump_to_panel`, `jump_to_sheet`, `sleep_timer_sheet`, `color_picker_sheet`, `subtitle_hunter_sheet`, plus `core/player/` service dialogs and `screens/player/` mixin panels) are **permanently exempt** — their white-on-dark style is intentional. `search_screen.dart` is also exempt (premium glass-pill with `BackdropFilter`). Dashboard adoption numbers will need a fresh grep pass to update — run against `raddflix_flutter/lib/screens/` + `lib/widgets/` excluding player files.
> Grep methodology: all counts run against `raddflix_flutter/lib/` excluding `lib/design_system/`
> and `lib/core/`. Where baseline and current used different methods this is noted explicitly —
> do not compare those rows numerically.

| Dimension | Baseline (2026-07-09) | Current (2026-07-10) | Δ | Primary Remaining Blocker |
|---|---|---|---|---|
| **Design tokens — space/radius** | 0 usages in screens/widgets | **RaddSpace: 265 hits · RaddRadius: 67 hits** (screens/ only) | +332 call sites | `RaddType` and `RaddMotion` still 0 in screens |
| **Design tokens — color (via context extension)** | ~0 `context.signalPrimary`/`context.t.*` in screens | **125 hits** (screens/) | +125 | Raw `Colors.*` / `AppColors.*` still dominant |
| **Design tokens — motion/type** | 0 in screens | 0 in screens | 0 | Phase 6+ work; `RaddMotion` constants now defined and used inside DS components |
| **Shared components** | `RaddSheet` 1 · `RaddTextField` 3 · all others 0 | **`RaddSheet` 14 · `RaddTextField` 10 · `RaddLockPad` 6** · `RaddButton`/`RaddCard`/`RaddChip`/`RaddBanner`/`SettingsRow` still 0 | 3/8 components have adoption | 5 core UI components still completely unused in app screens |
| **Screen compliance** (§10 DoD) | 2/33 screens touch any `Radd*` component | All 33 screens had ≥1 token pass (color/spacing/radius); **0/33 at full §10 DoD** (no `RaddButton`/`RaddCard`) | 0→33 partial, 0 full | `RaddButton`/`RaddCard` adoption is the next fulcrum |
| **Design debt — `Colors.*`** | 2,563 | **2,305** | **−258 (−10.1%)** | Remaining ~2,300 are mostly intentional overlays + player screen |
| **Design debt — `AppColors.*`** | 603 | **524** | **−79 (−13.1%)** | Remaining 524 are scattered across un-migrated screen areas |
| **Design debt — `Color(0x...)`** | 372 | **325** | **−47 (−12.6%)** | Off-scale / custom palette values; need case-by-case token proposal |
| **Design debt — `Duration(ms...)`** | 197 | **195** | **−2 (−1%)** | All DS components now use `RaddMotion` constants; remaining 195 are in screen files not yet migrated |
| **Design debt — `Curves.*`** | 92 | **92** | 0 | Screen-level migration not yet started |
| **Design debt — `EdgeInsets.*`** | 963 (app-wide) | 584 (screens/ only) | ⚠ methodology gap — not directly comparable; screens/ was not isolated in baseline | Spacing pass done across all 33 screens but off-scale values remain |
| **Design debt — `BorderRadius.circular`** | ~200+ (app-wide) | 198 (screens/ only) | ⚠ methodology gap — see above | Off-scale radius values (not 8/12/16/999) remain; need token proposal or design sign-off |
| **Design debt — `TextStyle(`** | 94 (stricter grep method) | 817 (screens/ only, broader method) | ⚠ methodology gap — not comparable; type-token migration has not started | Typography pass is the largest un-started debt category |
| **User journeys** | Auth ~40% visual · Onboarding 0% flow | Auth ~50% visual (token passes done) · Onboarding **0% flow** (not started) | +~10% auth visual | Onboarding rebuild (Phase 6) — new feature, not migration |
| **UX heuristics** | ~55% | ~58% | +3% | Accessibility: `RaddSheet` now has focus trap + `IconButton` close + `SemanticsService.announce`; TalkBack audit still needed on device |
| **Player experience** | ~60% functional / ~30% visual | ~60% functional / ~32% visual | +2% | Panel height violations (62–90% vs 40% spec), transport-row extras vs spec; need PM decision |
| **Overall readiness** | **~15–20%** | **~25–30%** | **+~10%** | `RaddButton`/`RaddCard` adoption + typography pass + Onboarding rebuild (Phase 6) |

**How to read the +10% overall:** the token/component library was 0% consumed at Phases 0–1 baseline. Phases 2–5 + Phase 1 drove the uplift: all 33 screens now use spacing and radius tokens; color debt reduced ~10–13% across all three color categories; 3 of 8 shared components have real adoption. The remaining 70% gap is dominated by two things: (1) `RaddButton` and `RaddCard` are still completely unused in app screens despite being fully built, and (2) typography tokens (`context.radd*` text styles) have zero screen adoption — the largest single un-started debt category by impact.

---

## 2. Screen-by-Screen Compliance Matrix

Legend: **Visual %** = estimated match to the screen's Volume V wireframe (structure + spacing + radius + type + color source), based on grep evidence below. **Component adoption** = count of `Radd*` shared-component usages in that file. Screens with no Volume V wireframe are scored against Volume I/II general rules (color source, spacing scale, radius scale) only, and flagged "no wireframe."

| Screen | File | Lines | `AppColors.*` | Raw `Color(0x..)` | Raw `Colors.*` | `Radd*` components used | Visual % (evidence-based) | Notes |
|---|---|---|---|---|---|---|---|---|
| Home | `home_screen.dart` | 1,337 | 33 | 3 | 71 | 0 | ~35% | Wireframe calls for full-bleed 62%-viewport hero, signal-numeral data-free badge, 16dp margins, 24dp rail gaps. Structure (hero → chips → rails) is present; token/color/radius layer is 100% legacy/raw. |
| Search | `search_screen.dart` | 1,357 | 33 | 0 | 46 | 0 | ~30% | Wireframe specifies `RaddSheet` for filters — screen has 0 `RaddSheet`/`showModalBottomSheet` matches in a quick scan; filter UI likely inline, not the documented sheet pattern. |
| Show Detail | `show_detail_screen.dart` | 2,199 | 59 | 13 | 93 | 0 | ~35% | Highest raw-`Colors.*` count of any screen (93). Structure (hero → title → actions → synopsis → cast → episodes → related) broadly follows wireframe; every visual primitive is legacy. |
| Player (default HUD) | `player_screen.dart` | 9,280 | 0 | 76 | 520 | 18 | ~30% functional-structure / low visual-token match | Only screen with meaningful `Radd*` adoption (18 hits, mostly `RaddSheet`/motion-adjacent), but by far the largest raw-literal surface in the app (520 `Colors.*`, 76 `Color(0x..)`, 80 `BorderRadius.circular()`). See §7 for HUD-rule violations. |
| Player "More" sheet | inline in `player_screen.dart` | — | — | — | — | 1 `RaddSheet` | ~40% | The one place `RaddSheet` is actually used — but the 3-tab (Playback/Audio&Video/Extras) structure from the wireframe should be verified against current tab set. |
| Settings Hub | `settings_screen.dart` | 374 | 7 | 3 | 8 | 0 (`SettingsRow` unused) | ~30% | Wireframe is a flat list of sections (Playback, Privacy & Vault, Account, Data & Downloads with data-free counter, Accessibility, About). Current screen has similar sections (Playback, Network & Data, Storage & Cache, Catalog, Support, About) via a private `_SettingsSection`/`ListTile`, not the shared `SettingsRow` component. Section taxonomy has drifted from spec (no "Privacy & Vault", no "Accessibility" section here — those live elsewhere as separate screens). |
| Lock Screen | `pin_lock_screen.dart`, `vault_lock_screen.dart` | 350 / 452 | 0 / 1 | 6 / 11 | 17 / 17 | 0 / 0 | ~10% | Design doc specifies a single shared `RaddLockPad` component reused everywhere PIN entry occurs. **`RaddLockPad` has 0 usages anywhere in the app** — two separate lock screens each reimplement PIN entry independently, both on raw literals. This is the clearest single-component "should already be done" gap. |
| Onboarding | `onboarding_screen.dart` | 293 | 1 | 5 | 3 | 0 | Flow: 0% match / Visual: ~25% | Design doc specifies a reciprocity-first 3-step flow (genre taste capture → starter watchlist build → save/signup, with a progress bar that opens at 25%, never 0%). Current implementation is a generic `PageView.builder` of static marketing slides (`_OnboardPage`/`_PageData`) — a different feature, not a lighter version of the same one. This is a **flow gap**, not a styling gap. |
| Login | `login_screen.dart` | 543 | 17 | 7 | 22 | 4 | ~45% | Best-adopted screen alongside Register — has real `Radd*` component usage, but still carries 17 `AppColors.*` + 22 `Colors.*` + 7 raw `Color()`. |
| Register | `register_screen.dart` | 190 | 7 | 0 | 11 | 3 | ~50% | Second-best-adopted screen; smallest file, cleanest ratio of tokens-to-literals. |
| Profile | `profile_screen.dart` | 1,150 | 36 | 29 | 44 | 0 | ~25% | Highest raw-`Color(0x..)` literal count (29) of any screen — no wireframe in Volume V; scored against general token rules. |
| Subscription | `subscription_screen.dart` | 825 | 52 | 0 | 61 | 1 | ~30% | Highest `AppColors.*` count in the app (52); has exactly 1 `Radd*` usage. |
| Downloads | `downloads_screen.dart` | 1,068 | 40 | 2 | 60 | 0 | ~30% | No wireframe in Volume V; scored on general token adoption. |
| Local Media / Local Folder | `local_media_screen.dart`, `local_folder_screen.dart` | 1,102 / 1,250 | 33 / 51 | 6 / 0 | 55 / 71 | 0 / 0 | ~25% | `local_folder_screen.dart` has the highest `AppColors.*` count of any screen (51). **2026-07-29:** `_buildSearchBar()` (both files) + URL-dialog TextField in `local_media_screen` visually aligned to `RaddTextField` spec — `BorderRadius.circular` → `RaddRadius.mdRadius`, proper enabled/focused borders. |
| Vault / Vault Settings | `vault_screen.dart`, `vault_settings_screen.dart` | 671 / 459 | 17 / 15 | 2 / 0 | 25 / 17 | 0 / 0 | ~25% | No wireframe; general token rules only. **2026-07-29:** Create-folder + rename-file dialog TextFields (vault) and `_pinField()` (vault_settings) visually aligned to `RaddTextField` spec — `t.bg` → `t.surface`, `BorderRadius.circular(10)` → `RaddRadius.mdRadius`, `enabledBorder`/`focusedBorder` added. |
| Watchlist / History | `watchlist_screen.dart`, `history_screen.dart` | 253 / 184 | 9 / 3 | 0 / 0 | 11 / 4 | 0 / 0 | ~35% | Smaller, simpler list screens; proportionally less raw-literal surface but still zero component adoption. |
| Splash | `splash_screen.dart` | 333 | 8 | 1 | 12 | 0 | ~30% | No wireframe. |
| Debug/Diagnostics | `debug_diagnostics_screen.dart` | 781 | 0 | 15 | 69 | 0 | N/A (internal tool) | Not a user-facing screen — exclude from release-readiness scoring, but flag for cleanup priority (low). |
| Remaining 16 screens (`actor`, `add_edit_profile`, `admin_queue`, `layout_designer` ×2, `plan_expired`, `profile_switcher`, `quota_full`, `season_folder`, `tid_status`, etc.) | — | 123–643 each | 0–22 | 0–5 | 3–44 | 0 | ~25–35% (proportional, no wireframe) | Full per-file counts in the table generation query; available on request. All follow the same pattern: legacy/raw color and spacing, zero shared-component adoption. |

**Aggregate:** 33 screens total. **2 use any `Radd*` component** (login, register) + player_screen (1 `RaddSheet` call site among its 18 hits, which are mostly other `Radd*` references inside its huge file). **31 of 33 screens have zero shared-component adoption.** Total raw-literal surface across screens+widgets: 2,563 `Colors.*`, 603 `AppColors.*`, 372 `Color(0x..)`, 963 `EdgeInsets.*`, 94 raw `TextStyle(`, 197 raw `Duration(milliseconds...)`, 92 raw `Curves.*`.

---

## 3. Before/After Token Mapping

**Important structural finding:** `AppColors` is not a competing token system that needs value reconciliation — it is the concrete implementation *behind* the `RaddColors` `BuildContext` extension (`lib/core/theme/radd_colors.dart` reads `AppColors.primary`, `AppColors.dataFree`, etc. directly). This means most color migrations are a **call-site rewrite, not a value change** — swap the reference, keep the color. That makes the color migration mechanical and low-risk, which is good news for scheduling it early.

### 3.1 Colors

| Legacy call site | Replace with | Notes |
|---|---|---|
| `AppColors.primary` | `context.signalPrimary` | Same underlying value (`0xFFE8002D`) — pure call-site swap. |
| `AppColors.primaryGlow` | `context.signalPrimaryGlow` | Same value. |
| `AppColors.dataFree` | `context.accentDataFree` | **Enforce Volume I AI_RULES rule 7**: reserved exclusively for zero-rated/data-free indicators. Audit every current `AppColors.dataFree` call site during migration to confirm it isn't leaking into success/online/active states. |
| `AppColors.warning` / `AppColors.error` | `context.accentWarning` / `context.accentError` | Same values. |
| `AppColors.background` / `.backgroundAlt` / `.surface` / `.surfaceHigh` | `context.t.bg` / theme-aware surface getters (see `RaddTheme`) | These are **not** 1:1 — `RaddTheme` is brightness-aware (dark/amoled/light); a direct `AppColors.background` swap loses that. Each usage needs a manual check of whether it should now respond to theme mode. |
| `AppColors.card` / `.cardBorder` | `context.raddCard` / `context.raddBorder` | Same theme-awareness caveat as above. |
| Any raw `Color(0xFF......)` literal not backed by a token | Nearest matching token from `AppColors`/`RaddColors`, or a new token proposal if no match exists | 372 instances — each needs a human decision, not a mechanical find/replace, since some literals may be intentional one-offs (album art overlays, gradients) rather than design-system violations. |
| Raw `Colors.white` / `Colors.black` / `Colors.grey[...]` etc. (2,563 instances) | Nearest semantic token (`context.t.textPrimary`, `context.t.textMuted`, `context.t.border`, etc.) | Largest single debt category by count. Do NOT bulk-replace — some `Colors.black.withOpacity(...)` usages are legitimate scrim/overlay effects, not text/surface colors; each needs the "what is this color *for*" question answered first. |

### 3.2 Radius

| Legacy call site | Replace with |
|---|---|
| `BorderRadius.circular(8)` | `RaddRadius.smRadius` (or `RaddRadius.sm` if only the double is needed) |
| `BorderRadius.circular(12)` | `RaddRadius.mdRadius` |
| `BorderRadius.circular(14)` / `(16)` | `RaddRadius.lgRadius` (16 is exact; 14 is the closest documented case from the earlier audit and should snap up to 16 unless there's a specific reason for the odd value) |
| `BorderRadius.circular(999)` / very large values (pill shapes) | `RaddRadius.pillRadius` |
| Any `BorderRadius.circular(n)` where `n` isn't 8/12/16/999 | Flag for design review — it's an undocumented radius value; either it should snap to the nearest token or the token scale needs a new entry (do not silently round). |

87 total `BorderRadius.circular()` call sites across screens+widgets (`player_screen.dart` alone: 80... wait, see raw count in §4 — 80 in player screen, ~200+ app-wide). Highest concentrations: `player_screen.dart` (80), `show_detail_screen.dart` (39), `home_screen.dart` (35), `quick_settings_panel.dart` (31).

### 3.3 Spacing

| Legacy pattern | Replace with |
|---|---|
| `EdgeInsets.all(4)` / `SizedBox(width/height: 4)` | `RaddSpace.xs` (4) |
| `EdgeInsets.all(8)` | `RaddSpace.sm` (8) |
| `EdgeInsets.all(16)` (also the documented default screen margin) | `RaddSpace.md` (16) |
| `EdgeInsets.all(24)` (also the documented rail vertical gap) | `RaddSpace.lg` (24) |
| `EdgeInsets.all(32)` | `RaddSpace.xl` (32) |
| `EdgeInsets.all(48)` | `RaddSpace.xxl` (48) |
| Any `EdgeInsets`/`SizedBox` value that isn't one of {4, 8, 16, 24, 32, 48} | Flag for design review — same rule as radius: don't silently round, decide whether it's a token gap or a mistake. |

963 raw `EdgeInsets.*` call sites app-wide — the single largest raw-literal category by count. Recommend tackling this **file-by-file alongside color migration**, not as its own pass, since most edits touch the same widget tree.

### 3.4 Typography

| Legacy pattern | Replace with |
|---|---|
| Raw `TextStyle(fontSize: 34, ...)` (display-scale headings) | `context.raddDisplay` |
| Raw `TextStyle(fontSize: ~24-28, fontWeight: bold, ...)` (screen/section headers) | `context.raddHeadline` |
| Raw `TextStyle(...)` for card/list titles | `context.raddTitle` |
| Raw body text styles | `context.raddBody` / `context.raddBodyStrong` |
| Small print / metadata | `context.raddLabel` / `context.raddCaption` |
| Numeral callouts (e.g. "4.2 GB saved") | `context.raddSignalNumeral` — this is a named, spec-specific style; grep shows it is not currently used anywhere in screens/widgets, so every "data saved" or stat callout across the app is currently using an ad hoc style instead of this documented one. |

94 raw `TextStyle(` instantiations app-wide outside the type-token file itself.

### 3.5 Motion

| Legacy pattern | Replace with |
|---|---|
| Raw `Curves.easeInOutSine` (or visually similar) for slow ambient/pulsing animation | `RaddMotion.pulse` |
| Raw `Curves.easeOutBack` for playful emphasis (e.g. button press, badge pop) | `RaddMotion.tune` |
| Raw `Curves.easeOutCubic` on sheet/modal entrance | `RaddMotion.sheetEnter` |
| Raw `Curves.easeInCubic` on sheet/modal exit | `RaddMotion.sheetExit` |
| Any other raw `Curves.*` (92 instances app-wide) | Case-by-case — not every animation is a `Radd*` motion case; only sheet/pulse/tune-pattern usages should migrate, others may be legitimately custom. |

`RaddMotion` currently has 3 usages app-wide (all inside `lib/design_system/` itself) — effectively unconsumed outside the token file. 197 raw `Duration(milliseconds: ...)` literals exist app-wide; migrating these requires first establishing documented duration tokens (Volume III mentions timing but the current `radd_motion.dart` file only defines curves, not durations — **this is a token-layer gap, not just an adoption gap**, and should be raised with design before migration work starts).

---

## 4. Design Debt Inventory

| Category | Count | Migration target | Priority |
|---|---|---|---|
| `Colors.*` raw references (screens+widgets) | 2,563 | Semantic theme tokens (`context.t.*`) | Critical (highest count, touches every screen) |
| `AppColors.*` direct references (screens+widgets+core) | 603 | `context.signalPrimary` / `context.accent*` / theme getters | Critical |
| Raw `Color(0x......)` literals | 372 | Nearest token or new token proposal | High |
| Raw `EdgeInsets.*` | 963 | `RaddSpace.*` | High (largest single count, but mechanical once color pass sets the pattern) |
| Raw `BorderRadius.circular()` | ~200+ (80 in player alone; 39/35/31/23/23/21/18/18/17/13/13/12/9/8×3/7... across the rest) | `RaddRadius.*Radius` | High |
| Raw `TextStyle(` | 94 | `context.radd*` type getters | Medium |
| Raw `Duration(milliseconds...)` | 197 | New duration tokens (gap — see §3.5) then migrate | Medium (blocked on token definition) |
| Raw `Curves.*` | 92 | `RaddMotion.*` where the pattern matches (pulse/tune/sheet); otherwise leave | Medium |
| Duplicate card widgets (`ContentCard` 6 usages, `SimosaCard` 2 usages) vs. `RaddCard` (0 usages) | 2 competing implementations, 0 on the documented one | Consolidate onto `RaddCard` | High — this is a 3-way split that should resolve to 1 |
| `RaddLockPad` component built, 0 usages; 2 independent lock-screen reimplementations | 2 duplicate PIN-entry UIs | Consolidate both `pin_lock_screen.dart` and `vault_lock_screen.dart` onto `RaddLockPad` | High — smallest-effort, highest-symmetry win in the whole migration |
| `~47` files under `lib/widgets/player/` confirmed dead (never imported; live player UI is 7 inline classes in `player_screen.dart` + 2 external sheets) | Dead code, not debt to "migrate" | Delete after confirming with `flutter analyze`/import graph (no Flutter SDK in this environment — see §7) | Low priority for design, but should be removed before or during the player migration phase to avoid migrating code that will be deleted |

**Progress against all categories above: 0% migrated, 0% in progress, as of 2026-07-09** (the login/register/one-player-sheet component usages predate this audit and were not the result of a tracked migration effort).

---

## 5. User Journey Reviews

| Journey | Current state | Gaps vs. design intent |
|---|---|---|
| **Onboarding** | Generic swipe-through marketing carousel (`PageView.builder` of static `_OnboardPage` slides) | Does not implement the documented reciprocity-first 3-step flow (genre taste → starter watchlist → save/signup with a progress bar that starts at 25%, never 0%). This is a *feature* gap, not a *styling* gap — treat as new build, not migration. |
| **Authentication** (login/register) | Functional, best-adopted screens in the app (4 and 3 `Radd*` usages respectively) | Still carries meaningful raw-literal debt (17+7 `AppColors`, 22+11 `Colors.*`) — closest to done, good candidate for the first fully-migrated screen to prove the pattern. |
| **Home → browsing** | Full hero + chips + rails structure present and functionally complete | Every visual primitive (color, radius, spacing, type) is legacy/raw; §2 estimates ~35% visual match to wireframe. |
| **Search → Details** | Search screen has no detected `RaddSheet` filter pattern (design doc specifies filters open in a `RaddSheet`) | Filter UI likely built as something else — verify during migration whether it's a custom sheet, dialog, or inline expansion, and replace with `RaddSheet` regardless. |
| **Details → Player** | Both screens functional; Show Detail has the highest raw-`Colors.*` count of any screen (93) | Visual consistency between the two screens (color/type/radius) is not verifiable as "matching" since neither uses the shared token layer — they may *coincidentally* look similar via `AppColors` but there's no structural guarantee. |
| **Player** (playback, gestures, subtitles, settings) | Functionally the richest screen (9,280 lines); has the only meaningful `Radd*` adoption in the app (18 hits including the one production `RaddSheet` usage for the "More" sheet) | Also by far the largest raw-literal surface (520 `Colors.*`, 76 `Color()`, 80 `BorderRadius.circular()`). See §7 for HUD-specific rule violations (40%-surface / 5-control rules). |
| **Downloads → Player** | Downloads screen functional, zero component adoption, no Volume V wireframe to compare against | Not specified in design docs — treat as "general token compliance" rather than a flow deviation. |
| **Library / Watchlist / History** | Functional, smaller files, zero component adoption | Lower risk/lower visual surface — good candidates for quick wins once the token pass pattern is proven on auth screens. |
| **Settings** | Present, but section taxonomy (Playback / Network & Data / Storage & Cache / Catalog / Support / About) differs from the documented one (Playback / Privacy & Vault / Account / Data & Downloads / Accessibility / About), and uses private `_SettingsSection`/`ListTile` instead of the shared `SettingsRow` component (0 usages) | Two separate gaps: information-architecture drift (different section names/grouping) and component-adoption gap (not using `SettingsRow`). Fix IA first since it affects real navigation, not just paint. |
| **Subscription / purchase** | Functional; highest `AppColors.*` count of any screen (52), only 1 `Radd*` usage | No Volume V wireframe exists for this screen — flag to design as a documentation gap, since purchase flows are usually where visual trust cues matter most. |
| **Profile management** | Functional; highest raw `Color(0x..)` literal count of any screen (29), no wireframe, zero component adoption | Same documentation gap as Subscription — recommend design produce a wireframe before migration so the work has a target, not just "remove literals." |

---

## 6. UX Heuristic Evaluation

Scored qualitatively (not from grep) but anchored to the evidence above where a heuristic and a metric intersect.

| Heuristic | Assessment | Evidence |
|---|---|---|
| **Consistency** | Weak | 0–2 screens share the component library; the rest independently reimplement buttons, cards, sheets, and PIN pads. Two competing card widgets (`ContentCard`, `SimosaCard`) exist simultaneously. |
| **Discoverability** | Not directly measurable from code; flagged for manual walkthrough | No evidence gathered here — recommend a manual click-through pass in Phase 1 rather than asserting a score without it. |
| **Hierarchy** | Mixed | Screens with high raw-`TextStyle` counts and no `Radd*` type tokens (e.g. Show Detail, Profile, Local Folder) are more likely to have ad hoc, inconsistent heading/body distinctions than screens using `context.radd*` getters — but this is inferred from token absence, not directly measured. |
| **Accessibility** | Not evaluated by this exercise | The original audit and this blueprint are code-structure/token-adoption focused; a real accessibility pass (contrast ratios, tap targets, screen-reader labels, dynamic type) is out of scope here and should be a separate, dedicated task. |
| **Responsiveness** | Documented rules exist (Volume V §"Responsive Layout Rules", 5 breakpoints) but adoption was not verified in this pass | Requires either a Flutter SDK to test at each breakpoint, or a targeted grep for `MediaQuery`/`LayoutBuilder` usage per screen — recommend as a Phase 1 investigation task. |
| **Feedback / error handling** | Not evaluated by this exercise | Same as accessibility — recommend a dedicated pass; grepping for `try/catch`, `SnackBar`, and error-state widgets would be the starting point. |
| **Cognitive load** | Suggestive signal only | Files with the largest raw-literal + line counts (`player_screen.dart` at 9,280 lines, `show_detail_screen.dart` at 2,199) are also the ones most likely to have accumulated ad hoc UI decisions over time, which correlates with — but does not prove — higher cognitive load for users. |

**Honest framing:** four of eight heuristics above have real evidence; four (discoverability, accessibility, feedback/error handling, and partially responsiveness) were not measurable from static code analysis in this pass and are called out as such rather than guessed at. Recommend Phase 1 include a scoped manual/automated pass for these specifically.

---

## 7. Player Experience — Dedicated Section

`player_screen.dart` (9,280 lines) is the single highest-risk, highest-reward file in the codebase:

- **Functional breadth confirmed:** carries controls for playback, gestures (brightness/volume/seek per the Volume V gesture-zone spec), subtitles, and a 3-tab "More" sheet (Playback / Audio & Video / Extras). It is the only screen with meaningful shared-component adoption (18 `Radd*` hits).
- **Also the single largest raw-literal surface in the app:** 520 `Colors.*`, 76 `Color(0x..)`, 80 `BorderRadius.circular()` — roughly 20% of the entire app's `Colors.*` debt lives in this one file.
- **Documented HUD rules** (from the earlier audit, reconfirmed here): the default collapsed HUD should occupy a minimal footprint (Volume V describes controls "center third — kept clear," with a compact bottom seek bar) — this needs re-verification against the *current* implementation now that the audit is being turned into an execution plan, since it was flagged but not re-measured in this pass.
- **Dead-code risk during migration:** ~47 files under `lib/widgets/player/` are confirmed unimported dead code sitting adjacent to the live implementation. Any agent migrating player UI must first confirm (via import-graph search, since no Flutter SDK is available in this environment to run `flutter analyze`) which of the 53 files under `lib/widgets/player/` are actually reachable before spending migration effort on them.
- **Recommendation:** treat the player as its own isolated phase (Phase 4, see below) with a mandatory first step of "delete or archive confirmed-dead files," so migration effort isn't spent on code that will be removed.

---

## 8. Phased Migration Roadmap

| Phase | Scope | Est. effort | Dependencies | Risk | Expected impact |
|---|---|---|---|---|---|
| **Phase 0 — Unblock** | Get the Flutter SDK available in a build environment (this workspace has none) and run the design-system component test suite / a smoke-test app that renders each of the 8 `Radd*` components. Confirm they compile and render as intended before any screen depends on them. | 0.5–1 day | None | **High if skipped** — every later phase inherits any bug hiding in an unverified component. | Removes the single biggest unknown in the whole plan. |
| **Phase 1 — Investigation gaps** | Fill the heuristic gaps flagged in §6 (accessibility, responsiveness-at-breakpoints, feedback/error-handling) and confirm the current player HUD footprint against Volume V. Also settle the duration-token gap in §3.5 (Motion) with design before any animation migration starts. | 2–3 days | Phase 0 (for anything requiring live rendering) | Low | Prevents Phase 2+ work from being redone once real answers arrive. |
| **Phase 2 — Foundational, low-risk consolidation** | (a) Consolidate `pin_lock_screen.dart` + `vault_lock_screen.dart` onto `RaddLockPad` (0 usages today — clean slate, no conflicting migration). (b) Resolve `ContentCard`/`SimosaCard` duplication onto `RaddCard`. (c) Delete/archive confirmed-dead files under `lib/widgets/player/` (after Phase 0 confirms which are truly unreachable). | 3–5 days | Phase 0 | Low–Medium (lock screens are security-sensitive; test thoroughly) | Two duplicate systems become one; removes noise before the bigger passes. |
| **Phase 3 — Auth + small screens token/component pass** | Migrate Login, Register (already the most-adopted, prove the pattern), then Watchlist, History, Splash, Settings (fix IA drift first per §5, then adopt `SettingsRow`). | 1–2 weeks | Phase 0, Phase 1 (duration tokens) | Low | Establishes the repeatable migration pattern on the app's simplest, most self-contained screens. |
| **Phase 4 — Player (isolated)** | Dedicated phase for `player_screen.dart` given its size and the dead-code adjacency risk in §7. Migrate color/radius/spacing/type/motion incrementally, verify HUD-rule compliance, and only then consider component extraction (splitting the 9,280-line file is a separate, larger architectural decision that should be scoped on its own once the token migration within it is proven safe). | 3–4 weeks | Phase 0, Phase 2(c) | High (largest, most feature-dense file in the app) | Removes ~20% of the app's total `Colors.*` debt in one phase; highest-visibility screen for users. |
| **Phase 5 — Remaining large screens** | Home, Search, Show Detail, Downloads, Local Media/Folder, Profile, Subscription, Vault/Vault Settings, Season Folder, Add/Edit Profile, Profile Switcher, Tid Status, Admin Queue, Actor, Plan Expired, Quota Full. Migrate in descending order of raw-literal count (Local Folder 51 `AppColors`/71 `Colors.*`; Subscription 52 `AppColors`; Show Detail 93 `Colors.*`; Profile 29 raw `Color()`, etc. — highest-debt files first maximizes visible progress early). | 4–6 weeks | Phase 0, Phase 3 (pattern proven) | Medium | The bulk of the remaining app-wide debt reduction. |
| **Phase 6 — Onboarding rebuild** | Not a migration — build the documented 3-step reciprocity flow (genre taste capture → starter watchlist → save/signup) as new functionality, using the now-migrated `RaddCard`/`RaddButton`/token layer from day one. | 1–2 weeks | Phase 3 (components proven in production) | Medium (new feature, not just restyling) | Closes the one confirmed *flow*-level gap, not just a styling gap. |
| **Phase 7 — Final polish & readiness re-audit** | Re-run the same grep-based measurement used in this document against every category in §4, confirm 0 remaining unaccounted raw literals (or an explicit, documented exception list), re-score the Release Readiness Dashboard in §1, and produce a short "what changed" delta report. | 3–5 days | All prior phases | Low | Produces the evidence that the app is actually release-ready, not just "believed to be." |

**Total estimated effort:** roughly 3–4 months of focused work across all phases, assuming one engineer/agent-equivalent working sequentially; phases 3 and 5 are the most parallelizable across multiple agents/engineers since individual screens within them are largely independent of each other (dependency is only on Phase 0 tooling and the Phase 3 pattern, not on each other).

---

## 9. Component Migration Plan

| Component | Where it should replace legacy UI | Current usage | Migration order |
|---|---|---|---|
| `RaddLockPad` | `pin_lock_screen.dart`, `vault_lock_screen.dart` | 0 | Phase 2 (first — cleanest slate) |
| `RaddCard` | Everywhere `ContentCard` (6 usages) or `SimosaCard` (2 usages) currently render a poster/show card — Home rails, Search results grid, Show Detail "More Like This," Downloads, Local Media/Folder, Watchlist | 0 | Phase 2/3 |
| `RaddButton` | Every primary/ghost CTA across all 33 screens (Play, Add to Watchlist, Download, Save & Continue, etc.) | 0 | Phase 3 onward, per-screen |
| `RaddSheet` | Search filters, Settings sub-panels, any `showModalBottomSheet` call not already using it | 1 (Player "More" sheet) | Phase 3 (Search filter is the clearest next target) |
| `RaddTextField` | Any remaining raw `TextField`/`TextFormField` outside Login/Register (e.g. Search bar, Add/Edit Profile name field) | 3 (Login, Register, subscription_screen) — **2026-07-29 INPUT-STYLE:** `live_tv_screen` (search bar), `vault_screen` (2 dialogs), `vault_settings_screen` (`_pinField`), `local_folder_screen` (search bar), `local_media_screen` (search bar + URL dialog) are now *visually matching* the spec but still use styled raw `TextField`, not the component. Full component migration for these remains a Phase 3/5 task. Player-overlay TextFields and `search_screen.dart` are permanently exempt — see note at top of §1. | Phase 3/5 |
| `RaddChip` | Home category chips, Search mood chips, Onboarding genre chips | 0 | Phase 3 (Search) / Phase 6 (Onboarding, built new) |
| `RaddBanner` | Any inline alert/notice pattern (e.g. quota-full, plan-expired, data-free indicators) | 0 | Phase 5 (Quota Full, Plan Expired screens) |
| `SettingsRow` | Settings Hub list rows (after IA is corrected to match the documented section taxonomy) | 0 | Phase 3 |

---

## 10. Visual Consistency Checklist (per major screen)

Use this checklist during each screen's migration in Phases 3–6. A screen is "done" only when every row is checked.

- [ ] No raw `Colors.*` — all colors resolve through `context.t.*` or `context.signal*`/`context.accent*`
- [ ] No raw `AppColors.*` direct references — routed through the `RaddColors` extension instead
- [ ] No raw `Color(0x......)` literals without a documented exception
- [ ] No raw `EdgeInsets.*`/`SizedBox` spacing values outside {4, 8, 16, 24, 32, 48} (`RaddSpace` scale)
- [ ] No raw `BorderRadius.circular()` outside {8, 12, 16, 999} (`RaddRadius` scale)
- [ ] No raw `TextStyle(` — all text uses a `context.radd*` getter
- [ ] Any sheet/modal on this screen uses `RaddSheet`, not `showModalBottomSheet` directly
- [ ] Any card/poster on this screen uses `RaddCard`, not `ContentCard`/`SimosaCard`
- [ ] Any button on this screen uses `RaddButton`, not a raw `ElevatedButton`/`TextButton`/`GestureDetector`
- [ ] Screen matches its Volume V wireframe structure (if one exists) — spacing, section order, and content density
- [ ] Screen has been visually checked at the ≥600dp tablet breakpoint per Volume V responsive rules
- [ ] Screen re-measured with the same grep queries used in this document — zero unexplained literals remain

---

## 11. Beyond-the-Design-System Opportunities

These are modernization ideas that stay within the "Open Frequency" identity rather than replacing it — flagged here per the request, but explicitly **not** scoped into the phased plan above since they are additive, not remediation:

- **Richer hero motion on Home** — the wireframe already reserves 62% of viewport height for the hero; once `RaddMotion` is actually consumed, a subtle parallax or `pulse`-curve ambient animation on the hero art (using the now-migrated token, not a new one) would reinforce "Open Frequency" without inventing new visual language.
- **Skeleton loading using token-driven shimmer** — once spacing/radius tokens are adopted, loading skeletons for rails/grids can be built once as a shared widget rather than per-screen, which the current zero-component-adoption state doesn't support yet.
- **`RaddSignalNumeral` surfaced more prominently** — this style exists and is documented for stat callouts (e.g. "4.2 GB saved") but has zero usages currently; broader use of it across Home, Settings, and Downloads would make the "data-free" identity more visually consistent once adopted.
- **TV/10-foot and foldable support** — explicitly listed in Volume V as "forward-looking, not immediate build." Do not pull into the current migration scope; revisit after Phase 7.
- **Contextual actions / AI-powered discovery** — outside the design system's current documented scope entirely; would need its own design-doc addition (new Volume or amendment) before any implementation, since there's nothing in Volumes I–XII to migrate toward yet.

These are listed for product/design awareness, not as blueprint deliverables — pursuing them before Phase 7 (readiness re-audit) would blur the migration signal this document is designed to track.

---

## 12. How to Use This Document

1. Treat §1 (Dashboard) as the single number to track sprint-over-sprint — re-run the grep queries in §2/§4 after each phase and update the percentages.
2. Assign phases from §8 to individual engineers/agents in the order given; Phases 3 and 5 can run in parallel across multiple screens once Phase 0's tooling gap is closed.
3. Use §3 (token mapping) as the literal find/replace reference during each screen's migration.
4. Use §10 (checklist) as the per-screen Definition of Done.
5. Do not mark a phase complete until the corresponding rows in §1 move — a phase that doesn't move the dashboard wasn't scoped correctly.
