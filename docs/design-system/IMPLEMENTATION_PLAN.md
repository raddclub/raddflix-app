# Design System Implementation Plan

Maps every design-system item from `docs/design-system/` (v1.0, frozen) to the existing `raddflix_flutter` architecture. This is a **plan only** — no code has been created or modified as part of producing it. Line counts below are current-state snapshots (2026-07-08) to calibrate complexity, not targets.

Legend — **Complexity:** S (small, <1 day) · M (medium, 1-3 days) · L (large, 3-7 days) · XL (needs its own sub-plan). **Breaking:** whether existing call sites must change.

---

## 1. Token Layer

| Item | Create vs. Refactor | Current files touched | Dependencies | Complexity | Breaking? |
|---|---|---|---|---|---|
| `RaddSpace` (spacing scale) | Create new (`lib/design_system/spacing/radd_space.dart`) | None directly — additive | None | S | No |
| `RaddRadius` | Create new; consolidate existing ad hoc `BorderRadius.circular(...)` literals found across `widgets/*` and `screens/*` | Touches every screen/widget eventually, but each swap is independent and non-breaking (same visual radius, just token-backed) | None | S to create, M to roll out | No (visual no-op if values match current usage) |
| `RaddElevation` (card/sheet/modal presets) | Create new | `widgets/content_card.dart`, `widgets/simosa_card.dart`, plus the 7 inline panel classes in `player_screen.dart` (`_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel`, `_QuickShortcutsPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel`) — **note:** `widgets/player/*_sheet.dart`/`*_panel.dart` (~47 files) are verified dead code, not live UI; do not include them in this rollout, see `09-migration-guide.md` correction | None | M | No if values are matched to current output; visual risk if not |
| `RaddType` (typography scale) | Create new (`lib/design_system/typography/radd_type.dart`); refactor away from ad hoc `TextStyle(fontWeight: FontWeight.w800, ...)` literals | `core/theme/app_theme.dart` (225 lines, defines base `ThemeData.textTheme` — extend here), then every screen/widget using inline `TextStyle` | `RaddColors`/`RaddTheme` (for color) must exist first | M to define, L to roll out app-wide (large surface area) | No per-swap, but requires screen-by-screen QA to avoid visual drift |
| Semantic color additions (`signal.primary`, `accent.dataFree`, etc.) | Refactor `core/theme/radd_theme.dart` (281 lines, defines 8 `RaddTheme` static instances) — add new fields to the `RaddTheme` class and to all 8 theme variants; extend `core/theme/radd_colors.dart` (31 lines, the `BuildContext` extension) with new getters | `radd_theme.dart`, `radd_colors.dart` | None | M — mechanical but must be applied to all 8 variants (dark/amoled/light/midnight/navy/forest/cobalt/rose) consistently | **Yes, mildly** — `RaddTheme` is a `const` class; adding required fields breaks all 8 `const RaddTheme(...)` constructors until updated (compiler-enforced, not runtime-risky) |
| `accent.dataFree` protection (signal-green, single-purpose) | Convention only — no code enforcement beyond a lint/review rule | N/A | Depends on the color existing in `radd_theme.dart` | S | No |
| Motion tokens (`Pulse`, `Tune`, sheet-entrance/dismiss curves) | Create new (`lib/design_system/motion/radd_motion.dart`) wrapping `Curves`/`Duration` constants; wire into existing `core/utils/anim_config.dart` and `anim_durations.dart` (already implement the device-tier gating logic — reuse, don't replace) | `core/utils/anim_config.dart`, `anim_durations.dart` (read, extend — don't rewrite; tier system already works) | None | M | No — additive constants |
| Icon system rule (outline=inactive/fill=active) | Convention + spot-refactor | `core/design/app_icons.dart` (centralizes icon refs already — good foundation) | None | S | No |

**Safest order within this phase:** `RaddSpace`/`RaddRadius` (purely additive, zero risk) → `RaddElevation` → semantic color fields in `RaddTheme`/`RaddColors` (do all 8 variants in one PR, compiler will catch any missed variant) → motion tokens (wrap existing `AnimConfig`) → `RaddType` (biggest surface area, do last so it can reuse the color tokens already in place).

---

## 2. Core Components

| Component | Create vs. Refactor | Current equivalent / files | Dependencies | Complexity | Breaking? |
|---|---|---|---|---|---|
| `RaddButton` | Create new (`lib/design_system/components/radd_button.dart`) | No single existing equivalent — buttons are currently ad hoc `ElevatedButton`/`TextButton`/`GestureDetector`+`Container` per screen | Token layer (color, spacing, radius, motion) | M to build, L to roll out (every screen has bespoke button code today) | No per-screen (additive), but rollout touches most screens eventually |
| `RaddCard` (+ 10 variants) | Refactor existing `widgets/content_card.dart` (746 lines) into the new base + variant system; `widgets/simosa_card.dart` (374 lines) becomes the provider-strip variant | `content_card.dart`, `simosa_card.dart`, `widgets/resume_fab.dart` (335 lines, becomes `continueWatching` variant), `widgets/cast_rail.dart` (actor variant) | Token layer, `RaddButton` (cards may embed action buttons) | L — `content_card.dart` at 746 lines is doing a lot; splitting into variants without regressing Hero-transition behavior needs care | **Yes** — `ContentCard` is almost certainly instantiated across `home_screen.dart`, `search_screen.dart`, `show_detail_screen.dart`, `watchlist_screen.dart`, `history_screen.dart`, `downloads_screen.dart`; constructor signature changes require updating every call site |
| `RaddSheet` (list + tabbed) | Create new; **this is the highest-leverage item** since it directly replaces the "sheet fatigue" surface identified in the UX audit | **Corrected 2026-07-08** (see `09-migration-guide.md`): consolidates the **7 inline private panel classes actually live inside `player_screen.dart`** — `_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel`, `_QuickShortcutsPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel` — plus `color_picker_sheet.dart`/`theme_picker_sheet.dart` which live under `PlayerSettingsScreen`. The ~47 other files previously listed here (`eq_panel.dart`, `audio_lab_panel.dart`, `audio_lab_sheet.dart`, `audio_mixer_sheet.dart`, `video_enhance_panel.dart`, `video_enhance_suite.dart`, `speed_picker_sheet.dart`, `speed_presets_sheet.dart`, `bookmark_panel.dart`, `scene_bookmarks_panel.dart`, `jump_to_panel.dart`, `jump_to_sheet.dart`, `cinematic_settings_sheet.dart`, `player_hud_settings_sheet.dart`, `quick_settings_panel.dart`, `sleep_timer_sheet.dart`, `silence_skip_sheet.dart`, `smart_enhance_sheet.dart`, `end_action_sheet.dart`, `screenshot_share_sheet.dart`, `gesture_map_sheet.dart`, `sync_panel.dart`, `word_definition_sheet.dart`, and more) are **verified dead code** — never imported by `player_screen.dart` or any live screen — and are excluded from this consolidation; see `TASKS.md` PLAYER-DOCS-CORRECTION for the delete/audit follow-up | Token layer | **XL** — still the whole Player consolidation; needs its own sub-plan grouping the 7 real inline panels into the 3 target tabs (Playback / Audio & Video / Extras) one merge at a time, not a single PR | **Yes, significant** — `player_screen.dart` (9,372 lines) contains all 7 panels as inline classes with shared state; every merge requires extracting from and updating this one very large file, which is the single riskiest file in the entire codebase to touch |
| `SettingsRow` | Create new | Refactor `screens/settings_screen.dart` (374 lines), `screens/player_settings_screen.dart` (311 lines), `screens/vault_settings_screen.dart` (459 lines) — currently 3 separate list implementations | Token layer | M to build `SettingsRow`, L to refactor all 3 screens + build the unified hub | **Yes** — this is also an IA change (3 destinations → 1 hub + sub-pages), so navigation routes/deep-links to these screens need auditing, not just the widget internals |
| `RaddBanner` | Refactor `widgets/notification_banner.dart` (242 lines) and `widgets/offline_banner.dart` (54 lines) into one component with the 9 documented variants | `notification_banner.dart`, `offline_banner.dart` | Token layer | M | **Yes, moderate** — call sites passing ad hoc styling/config need to map to the new `variant` enum |
| `RaddLockPad` | Refactor: extract `screens/vault_lock_screen.dart`'s (452 lines) numpad UI as the shared base; `screens/pin_lock_screen.dart` (350 lines) adopts it | `vault_lock_screen.dart`, `pin_lock_screen.dart` | Token layer | M — logic (PIN validation, biometric hook) stays in each screen; only the numpad UI moves to the shared widget | No if extraction preserves each screen's existing callback contract |
| `RaddTextField` | Rename/align existing `widgets/radd_text_field.dart` (55 lines) — this one already exists and mostly matches spec | `radd_text_field.dart` | Token layer | S | No |
| `RaddChip` | Create new; refactor category-chip code likely inline in `home_screen.dart` and `search_screen.dart` | `home_screen.dart` (1,337 lines), `search_screen.dart` | Token layer | S to build, M to extract from the two large screen files | No if extracted as a drop-in replacement with matching API |

**Safest order within this phase:** `RaddTextField` (near-zero risk, already exists) → `RaddChip` → `RaddButton` → `RaddBanner` → `SettingsRow` → `RaddLockPad` → `RaddCard` (highest call-site count, do after the simpler ones establish the pattern) → `RaddSheet` (XL, do last, and only after `player_screen.dart` has been read in full and its 9,372 lines mapped in detail — see Phase 3 caution below).

---

## 3. Screen Migration

| Screen | Files | Complexity | Breaking? | Notes |
|---|---|---|---|---|
| Home | `home_screen.dart` (1,337 lines) | L | Internal only (no other screen depends on Home's internals) | On Air hero redesign + componentization can land incrementally: extract rail widgets first (low risk), redesign hero last (highest visual-risk item) |
| Search | `search_screen.dart` | M | Internal only | Mostly additive (mood chips); core search/filter logic untouched |
| Show Detail | `show_detail_screen.dart` (2,199 lines) | L | Internal only | Second-largest screen file; componentize before reordering hierarchy, don't do both in one pass |
| Player | `player_screen.dart` (9,372 lines, contains the 7 live inline panels) + `player_settings_screen.dart` (311 lines, uses `color_picker_sheet.dart`/`theme_picker_sheet.dart`) — **corrected 2026-07-08**: `widgets/player/*` has 58 files total but only ~5 are live (`seek_bar_painter.dart`, `color_picker_sheet.dart`, `theme_picker_sheet.dart`, `binge_guard.dart`, plus the dead-but-still-on-disk rest); see `09-migration-guide.md` | **XL, highest risk in the entire plan** | Yes — `player_screen.dart` has intertwined state management across all 7 inline panels being consolidated | Do not attempt in one pass. Recommend: (1) run the dead-code audit/cleanup first (delete or archive the ~47 orphaned files so they stop appearing in searches and confusing future migration work); (2) build `RaddSheet` shell in isolation and prove it with one of the simpler live inline panels (e.g. `_VideoZoomPanel`, the shortest) before touching the audio/video cluster; (3) only after that pattern is validated, tackle the `_AudioTrackPanel`/`_AudioEffectPanel` merge; (4) `_SidebarCustomizerPanel`-to-Extras-tab restructuring last, since it touches the most existing keybindings/shortcuts logic |
| Settings (unified hub) | `settings_screen.dart`, `player_settings_screen.dart`, `vault_settings_screen.dart` | L | Yes (navigation/IA change) | Audit all `Navigator.push`/route-name references to these 3 screens before restructuring |
| Downloads | `downloads_screen.dart` | S | No | Badge-only addition per the design spec; no structural change |
| Profile Switcher | `profile_switcher_screen.dart` | M | No | Additive (photo avatars, Pulse ring) |
| Lock Screens | `pin_lock_screen.dart`, `vault_lock_screen.dart` | M | No if `RaddLockPad` extraction preserves callbacks (see above) | |
| Onboarding | `onboarding_screen.dart` | M | No | Additive (taste-capture step) |

---

## 4. Recommended Safest Overall Order

1. **Token layer** (Section 1) — everything downstream depends on this; low risk, mostly additive except the `RaddTheme` constructor change (compiler-caught, not a runtime risk).
2. **Low-risk components first**: `RaddTextField` → `RaddChip` → `RaddButton` → `RaddBanner` → `RaddLockPad` — each is independently shippable and low call-site count.
3. **`RaddCard`** — higher call-site count; do once the simpler components have validated the token layer works end-to-end in production.
4. **`SettingsRow` + Settings hub migration** — an IA change, but contained to 3 files; do before touching the Player so the team has practice with a "3 screens → 1" consolidation on a smaller surface first.
5. **Home and Show Detail componentization** — internal-only risk, can proceed in parallel with Settings once `RaddCard`/`RaddButton` exist.
6. **Player consolidation (`RaddSheet` + the 7-inline-panel merge, after the dead-code cleanup)** — deliberately last. This is the largest, riskiest, and most valuable item in the whole plan (it's the #1 structural finding from the original UX audit), and it should only be attempted after every other component has been proven in production, since `player_screen.dart` (9,372 lines) is the single highest blast-radius file in the codebase. Do the dead-code audit/cleanup of `widgets/player/` (see `TASKS.md` PLAYER-DOCS-CORRECTION) before starting the real merge, so the working file set is accurate.
7. **Polish phase** (Volume VI/XI compliance pass, Volume XII checklist run against every migrated screen).

## Estimating Note

This plan intentionally does not commit to calendar time — "S/M/L/XL" complexity is relative, not a schedule. The Player phase (step 6) alone likely represents more implementation effort than everything else in this plan combined, given `player_screen.dart`'s size; it deserves its own detailed sub-plan (merge order for the 7 real inline panels, after the dead-code cleanup) once the team is ready to start it, rather than being scoped further here.

**Correction note (2026-07-08):** earlier drafts of this plan said the Player consolidation covered 24-50 external sheet/panel files. A live import trace found that's wrong — the real Player UI is 7 private classes inline inside `player_screen.dart`, plus 2 externally-hosted sheets used by the separate `PlayerSettingsScreen`. 50 files under `widgets/player/` are dead code (never imported anywhere), left over from an earlier architecture the app author already tore out. See `09-migration-guide.md`'s "Player — corrected 2026-07-08" section for the full verified inventory.

**Re-verification note (2026-07-08, later same day):** the dead-file list was re-audited (`TASKS.md` PLAYER-DEAD-CODE-CLEANUP). Two corrections to the original 47-file list: (1) `binge_guard.dart` was mis-classified as "referenced, keep as-is" — it is actually unimported dead code, moved to the dead list; (2) `picture_profiles_sheet.dart` and `film_grain_overlay.dart` (newer files, part of the same dead `quick_settings_panel.dart` sub-chain) were missing from the original list and have been added. Corrected total: 50. The user reviewed the full list and **declined to delete any of it** — several files look like intentionally-parked unshipped features (Sleep Timer, Cast, Zoom/Crop, etc.), not confirmed junk. This is now a closed decision, not an open cleanup task — do not re-propose deleting these files without new instruction from the user, and do not re-derive this inventory from scratch; read it here and in `09-migration-guide.md` first.

## What This Plan Does Not Cover

- Exact Dart code/diffs (that's implementation, not planning).
- Automated test strategy for each migration step (should be added per Volume VII's testing convention once implementation starts).
- Whether to migrate `Radd*` components into a separate local package vs. keeping them in `lib/design_system/` within the app — recommend keeping them in-app for now given this is a single-app monorepo target, revisit only if a second Flutter client is ever added.

No code was modified to produce this plan — see `CHANGELOG.md` for when this document was added.
