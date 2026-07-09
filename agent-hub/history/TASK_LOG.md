# RaddFlix Task Log — Index

> This file is an INDEX only. Full session detail (root causes, code diffs, file lists) lives
> in the monthly archive files below — open the relevant month, or search across all of them,
> before re-deriving something that may already be documented.
>
> When starting a new month, create `agent-hub/history/YYYY-MM.md` and add a row here.

---

## Archives

| Month | File | Sessions |
|---|---|---|
| June 2026 | [`2026-06.md`](2026-06.md) | 34 |
| July 2026 | [`2026-07.md`](2026-07.md) | 10 |

---

## Session index (title only — full detail in the linked archive)

### June 2026 — see [`2026-06.md`](2026-06.md)

- Session 2026-06-29 — Phase 37: UI Bug Fixes
- Session 2026-06-07 — OPS-01 Session Expired Fix
- Session 2026-06-18 — Phase 19: A/B Pin Loop + Phase 20: Subtitle/Local Cleanup
- Session 2026-06-24 — Phase 21: Local Media Audio/Sort/Filter
- Session 2026-06-24 — Phase 22: Bug Fixes
- Session 2026-06-24 — Phase 23: Vault + Biometrics
- Session 2026-06-24 — Phase 24: Oracle Backend Fix (from previous agent's incomplete task)
- Session 2026-06-24 — Phase 25: Full Profile Edit Feature
- Session 2026-06-24 — Verification & Doc Sync
- Session 2026-06-26 — Build Fix: ModalRoute args in app.dart
- Session 2026-06-26B — Oracle downloader.py ZIP fix sync to GitHub
- Session 2026-06-28 — Agent Prompt & Push Helper Refactor
- Session 2026-06-28B — Prompt Token Optimisation
- Session 2026-06-28C — push.js Retry Logic
- Session 2026-06-28D — push.js validatePatch()
- Session 2026-06-28E — Prompt: validatePatch wired into examples
- Session 2026-06-28 — Build fix: edit_profile_screen corruption
- Session 2026-06-28 — Build fix: downloads_screen + content_card
- Session 2026-06-28 — Build fix: downloads_screen _savePrefs
- Session 2026-06-28 — Phase 35 UI/UX Completion Pass
- Session 2026-06-28 — Phase 35B Build Fix
- Session 2026-06-28 — Phase 36 Missing Features
- Session 2026-06-30 — Phase 38 UI/UX Polish
- Session 2026-06-30 — Phase 39 Download Audit
- Session 2026-06-30 — Phase 40 Downloads Feature Pack
- Session 2026-06-30 — Phase 41 Animation Infrastructure
- Session 2026-06-30 — Phase 42 Hero Poster Transition
- Session 2026-06-30 — Phase 43 Staggered Grid/List Entry
- Session 2026-06-30 — Phase 44 OpenContainer Morph
- Session 2026-06-30 — Phase 45 Neon/Glow Buttons
- Session 2026-06-30 — Phase 46 Typewriter & Animated Text
- Session 2026-06-30 — Phase 47 Frosted Glass Bottom Nav
- Session 2026-06-30 — Phase 48 3D Tilt Hero Banner
- Session 2026-06-30 — Phase 49 Ambient Particle Background + ANIM-45-05

### July 2026 — see [`2026-07.md`](2026-07.md)

- Session 2026-07-01 — Phase 56 Subscription Tier Badge
- Session 2026-07-01 — Full Audit: Guest/Free/Premium Logic
- Session 2026-07-01 — 5 Feature Batch
- Subtitle Audit Fixes · 4f568fc
- Session 2026-07-01 — Player Audit: Dual Subtitles, Track Bugs, EAC3, MKV
- Session 2026-07-01 — Phase 57 Implementation
- Session 2026-07-01 — Phase 58: Online Subtitle Search Overhaul
- Session 2026-07-01 — Phase 60: Remove Dub / Dub Active Indicator in Audio Panel
- Session 2026-07-01 — Build Fixes (Kotlin 2.2.0 + minSdkVersion 24)
- Session 2026-07-02-B — Subtitle + free-user fixes
- Session 2026-07-04 — Auto-Commit Workflow + UI/UX Plan Review
- Session 2026-07-04 — Icon migration: AppIcons coverage 100% (gesture_map_sheet.dart)
- Session 2026-07-04 — Test suite: all files run; SSL cert fix for Dart test in Nix env
- Session 2026-07-04 — Correct wrong info: TTL 110min, validationkey must NOT appear in CDN URL
- Session 2026-07-05 — Logger Secret Stripping (final gap closed)
- Session 2026-07-05 — Rebrand Zero-Rating Copy (hide JazzDrive)
- Session 2026-07-05 — CI Fix + Full UI Audit (4 fixes shipped)
- Session 2026-07-05 — Portrait-Player-V1: YouTube/Netflix portrait layout for video player
- Session 2026-07-05 — Player Panel Audit: panels responsive, info icon moved, codec display fixed, format support verified
- Session 2026-07-06 — Bottom Nav Redesign: Search replaces Local in nav, Downloads renamed Library, On Device access via Library AppBar, label font fixed, _navIndex drift fixed
- Session 2026-07-06 — Portrait-Player-V2: 7 layout issues fixed (16:9 video zone, sidebar removed, persistent back button, clean transport row, spaceEvenly controls, no scroll wrapper, Lock in quick actions)


- Session 2026-07-07 — Subtitle Panel Full Rewrite + Settings Panel Polish (G1, G2)
- Session 2026-07-07 — H1 Audio Lab Bugfix: A1 logging (_applyAllAf), A2+A3 merged EQ chain (no double-equalizer), A4 vocal-remover 0.5x scale (no clip), A5 postFrameCallback MPV sync on panel open. A6 verified OK. Commit e283978.
- Session 2026-07-07 — H1 verification: static simulation found firstMatch bug (Bass Boost gains dropped when Dialogue also on). Fixed to allMatches summing. Commit 9ee224d. All 25 scenarios pass.
- Session 2026-07-07 — I1 Audio Lab new features: Dialogue Only (centre-channel sum), Night Audio (acompressor soft compressor), Stereo Widener (extrastereo=m=2.5), Noise Reduction (afftdn=nf=-25). Also fixed vocal-remover 0.5-scale inconsistency in _loadPrefs AF rebuild. 7 touch points in player_screen.dart. Commit 6e4da14.
- Session 2026-07-07 — J1 Full player audit (66 working / 5 partial / 1 dead-code). Fixed all 5 bugs: silence-skip pipeline restore, Vivid persist, skip-btns persist, prev-next persist, compact layout real visual effect. Commit cd75b25.
- Session 2026-07-07 — J2 Code-trace verification of J1 fixes found 4 more bugs: _toggleSmartEnhance missing _savePrefs(), 3 Settings callbacks (showSkipBtns, showPrevNextBtns, showSeekPosition) missing _savePrefs(), _showSeekPositionLabel never persisted at all. Fixed all + added pref_seek_pos_label. Commit 26232d7.
- Session 2026-07-07 — K1 Save watch position on pause: added _saveWatchPos() to playing.listen when v=false. Frame thumbnails checked — not in code, not created per instruction. Commit 5408c98.
- Session 2026-07-07 — L1 Audio panel + subtitle style persistence: (1) Fixed audio track labels showing literal `${widget.tracks[i].language}` — was escaped `\${}` in double-quoted strings (Dart treats as literal). Fixed to single-quoted interpolation. Resolves "no audio" (users accidentally disabled audio via garbled track panel). (2) Subtitle style/position prefs were never saved — 11 state vars reset to defaults on every panel open. Added _loadSubPrefs()/_saveSubPrefs() to _SubtitlePanelState; prefs loaded+re-applied to MPV in initState; _saveSubPrefs() wired to all 13 onChanged sites. Commit 7d2c77e.
- Session 2026-07-07 — L6 MPV startup restore: `_loadPrefs` restored `_subSpeed`/`_videoRotation` from prefs into Dart state but never pushed to MPV — video started at wrong rotation and subtitle speed until user manually touched the control once. Fixed: guarded `setProperty('sub-speed',...)` + `setProperty('video-rotate',...)` calls added after existing speed-restore block in `_loadPrefs`. `_zoomMode` verified Flutter-only (BoxFit) — no MPV property. Commit 16de119.
- Session 2026-07-08 — PLAYER-DOCS-CORRECTION: `docs/design-system/09-migration-guide.md` and `IMPLEMENTATION_PLAN.md` wrongly described the Player as 24-50 external `widgets/player/*.dart` sheet/panel files. Live import trace found the real architecture is 7 private classes inline inside `player_screen.dart` (`_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel`, `_QuickShortcutsPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel`) plus 2 live external sheets used by `PlayerSettingsScreen` (`color_picker_sheet.dart`, `theme_picker_sheet.dart`) plus 2 shared helpers (`seek_bar_painter.dart`, `binge_guard.dart`). ~47 files in `widgets/player/` are confirmed dead code (never imported anywhere) — left over from an earlier torn-out architecture. Corrected both docs + `CHANGELOG.md`; added `PLAYER-DEAD-CODE-CLEANUP` (delete/audit the dead files) and re-scoped `PLAYER-CONSOLIDATION` to the real 7-panel architecture in `TASKS.md`, both still open, both blocked until token layer work lands. Docs/task-tracking only — no app code changed.
- Session 2026-07-08 — PLAYER-CONSOLIDATION steps 4–7 (DONE): Stripped self-contained headers (back-button row + title text) from `_SubtitlePanel`, `_AudioEffectPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel` build() methods; kept all internal tab bars in place. Converted all 4 matching call sites from legacy `_openRightPanel()` to `RaddSheet.show(style: list, title: '...', maxHeightFraction: 0.90, listBuilder: (_) => Panel(...))`. All 7 panels now use RaddSheet — `_openRightPanel()` has zero callers in the main player flow. Bounded-height analysis confirmed: RaddSheet's ConstrainedBox(maxHeight: 0.85×screen) gives Flexible a finite budget; inner panel Column with mainAxisSize.max fills that budget; Expanded children (EQ sliders, ListViews, ReorderableListView) resolve correctly. Commit 777df5a. CI run 28964526692 in progress.

## 2026-07-09 — MIGRATION-BLUEPRINT-2026-07-09

Follow-on to the same-day UI/UX audit, requested after external review feedback (fed back via the user) asked for a screen-by-screen compliance matrix, token mapping table, design-debt inventory, journey/heuristic review, and a phased execution plan rather than another descriptive audit.

Produced `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md`: release readiness dashboard (~15-20% overall), 33-screen compliance matrix with per-file literal counts, before/after token mapping (colors/radius/spacing/type/motion), design-debt inventory table, 12 user-journey reviews, UX heuristic evaluation (honest about what could/couldn't be measured from static code), dedicated player-experience section, 8-phase roadmap (Phase 0 unblock → Phase 7 re-audit) with effort/dependencies/risk, component migration plan, per-screen visual consistency checklist, and beyond-spec modernization ideas kept out of migration scope.

Key structural finding: `RaddColors` (BuildContext extension) reads directly from `AppColors` — they are not two competing value systems, so color migration is mostly a mechanical call-site swap, not a value reconciliation. Also confirmed zero direct call sites for `RaddSpace`/`RaddRadius`/`RaddType`/`RaddMotion`/`RaddLockPad` anywhere in screens/widgets — token layer is fully built but fully unconsumed.

Docs only, no app code changed.

## 2026-07-09 — Phase 2 completion: ContentCard token pass + dead-code clarification

Two remaining Phase 2 checklist items resolved:

**ContentCard radius token pass (commit `6457ab2`):** `content_card.dart` had 6 instances of
`BorderRadius.circular(AppRadius.sm/md)` (AppRadius.sm=10, AppRadius.md=14). Migrated all 6
to `RaddRadius.smRadius` (8) / `RaddRadius.mdRadius` (12) — intentional visual normalization to
the design system scale, per the migration blueprint. Added `import radd_radius.dart`. Full
call-site consolidation of ContentCard→RaddCard deferred: ContentCard has features not in RaddCard
(FREE/NEW/ONGOING/UPLOADING badges, long-press context menu, local-file poster). SimosaCard
excluded from RaddCard migration (it is a promotional widget, not a catalog content card).

**Player dead-code item closed as N/A:** `PLAYER-DEAD-CODE-CLEANUP` in TASKS.md records that
the user reviewed the full 50-file list and explicitly declined deletion — files are
intentionally-parked unshipped features. This Phase 2 item was already closed before this
session. Phase 4's matching prerequisite item also marked N/A.

**NOTE — revert of mistaken deletion:** this session initially deleted all 50 files before
reading the TASKS.md CLOSED note. The deletion was immediately reverted in commit `b1722c5`
(all 50 files restored from pre-deletion tree). No net change to the files. This is documented
here so future agents know the history if the commit log looks confusing.

## 2026-07-09 — Phase 3: Auth + small screens token pass

Six screens received a color + radius token pass:

| Screen | Commits | Token changes | Kept as-is |
|---|---|---|---|
| `history_screen.dart` | `39256ca` | `AppColors.primary` → `context.signalPrimary` | `AppColors.error` in const TextStyles |
| `splash_screen.dart` | `198af9e` | All 6 `AppColors.primary` → `context.signalPrimary` | `AppColors.background` in field init (no context) |
| `watchlist_screen.dart` | `f04b46b` | All `AppColors.primary` → `context.signalPrimary`; const TextStyle→TextStyle (2 occurrences) | `AppRadius.xl/round` (no RaddRadius equivalent) |
| `settings_screen.dart` | `9517719` | `AppColors.primary/warning`→`context.*`; `AppRadius.md`→`RaddRadius.mdRadius` | `AppColors.info/success` (no mapping) |
| `register_screen.dart` | `329738b` | primary/error→context.*; radius sm/md→RaddRadius | `AppColors.primaryGradient` |
| `login_screen.dart` | `8a84428` | primary/error→context.*; radius sm/md→RaddRadius; const TextStyle→TextStyle (3) | `AppColors.warningDark/primaryGradient` |

`SettingsRow` adoption + section taxonomy change deferred to Phase 4/5:
- `SettingsRow` lacks `subtitle` and `iconColor` parameters; direct adoption would cause visual regression
- Section taxonomy restructure requires PM input (new Privacy & Vault / Account / Accessibility sections)
- This is the same pattern as ContentCard/RaddCard — design system component needs extension first

CI queued/running on all 6 commits as of session end. Run IDs: b1722c5 (re-run), 39256ca→8a84428 (Phase 3).

## 2026-07-09 — Phase 3 CI fix: context.signalPrimaryGradient does not exist

Bootstrap session: cloned repo, read canonical docs, found Phase 3 CI failures on commits
`8a84428` (login_screen.dart) and `329738b` (register_screen.dart).

**Root cause:** the prior session introduced `context.signalPrimaryGradient` in both files.
This getter does not exist on BuildContext — `RaddColors` extension defines no gradient getter.
CI error: `The getter 'signalPrimaryGradient' isn't defined for the class 'BuildContext'`.

**Fix (commit `4ee0215`):** replaced both occurrences with `AppColors.primaryGradient` — the
static const LinearGradient used consistently throughout the rest of the codebase. Both files
already import `'../core/constants.dart'` (which defines `AppColors`), so no import change needed.
CI run on `4ee0215` confirmed **green**.

**Durable lesson:** `RaddColors` (the BuildContext extension) has no gradient getter. Any gradient
using the primary color must use `AppColors.primaryGradient` directly — not a context extension.

Phase 3 is now ✅ COMPLETE with CI green. Phase 4 (player_screen.dart token migration) is next.

## 2026-07-09 — Phase 4: player_screen.dart token migration (all CI green)

Three commits, all CI green. File: 9,280 lines — high-risk phase, done carefully one token type per commit.

**Commit d91cfd8 — color pass:**
- `Colors.orange` (15) → `AppColors.orange` (exact value `Color(0xFFFF9800)`)
- `Color(0xFF00A651)` (2) → `AppColors.jazzGreen` (exact value)
- Kept: `Colors.white/white38/white70/...` (intentional video-overlay colors), `Colors.black*`,
  `Colors.amber`, `Colors.redAccent`, most `Color(0xFF...)` hex values — player-specific accents
  (EQ, AI/dub indicators, etc.) with no exact design-token equivalent.

**Commit 164aca4 — radius pass:**
- Added `import '../design_system/radius/radd_radius.dart'`
- `BorderRadius.circular(8)` (20) → `RaddRadius.smRadius`
- `BorderRadius.circular(12)` (4) → `RaddRadius.mdRadius`
- `BorderRadius.circular(16)` (1) → `RaddRadius.lgRadius`
- 25 total replacements. Values 5/6/7/10/14/20/22/24/40 have no token — kept.

**Commit 969e0c3 — spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- SizedBox(h/w: 4/8/16/24/32) and EdgeInsets.all(4/8/16/24/32) → RaddSpace.xs/sm/md/lg/xl
- 81 total replacements. Values 2/3/5/6/10/12/14/20/28 have no token — kept.
- Type tokens deferred: player TextStyles are pixel-level control sizing (10/11/14/20px) outside
  the RaddType scale (12/13/15/18/24/34). Changing them would alter visual layout of controls.

**HUD compliance (static-code check):**
- Auto-hide ✅ 3s timer (Volume X compliant)
- 40% surface rule: pre-existing violation — `_openRightPanel` uses `initialChildSize: 0.62`
  portrait bottom sheet; 7 main panels via `RaddSheet.show()` use `maxHeightFraction: 0.90`.
  Full re-measurement needs Phase 1 (Flutter SDK + live device).
- File split: warranted (9,280 lines) but scoped as future architectural task.

Phase 4 ✅ COMPLETE. Phase 5 (large screens: show_detail, local_folder, home, etc.) is next.

**Commit 9914bf2 — show_detail_screen.dart color pass:**
- `Colors.green*` → `AppColors.success` (unifies with existing success-badge usages in same file)
- `Color(0xFF3B82F6)`→`AppColors.info`, `Color(0xFFF59E0B)`→`AppColors.warning`,
  `Color(0xFF22C55E)`→`AppColors.success`, `Color(0xFFEF4444)`→`AppColors.error`,
  `Color(0xFF1A1A2E)`→`AppColors.card` (exact value matches)
- Kept: `Colors.white*/black*/transparent` (overlay/text-on-poster, no exact token),
  `Color(0xFFFFB800)` (star rating gold), `Color(0xFFFFB300)` (premium/lock badge amber) —
  neither matches an existing AppColors value.
- Note: file already had partial `RaddRadius` usage from an earlier pass — radius pass skipped,
  remaining raw `BorderRadius.circular()` values (2/4/5/6/10/14/18/20) don't match the 8/12/16
  scale.

**Commit 12d0c63 — show_detail_screen.dart spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `SizedBox(height/width: 4/8/16/32)` and `EdgeInsets.all(8)` → `RaddSpace.xs/sm/md/lg`
- Remaining raw values (2/5/6/9/10/12/13/15/20/24/28/60) have no token — kept.

**Commit 9daff07 — build-break hotfix (local_folder_screen.dart):**
- A prior, uncommitted-to-plan session's Phase 5 pass on `local_folder_screen.dart` (commit
  6b7c3fb) shipped a broken build: `_menuTile` referenced the ambient `context` instead of its
  own `ctx` parameter (undefined getter on `_VideoListTile`), and a `const Text(...)` referenced
  `context.accentError` inside a const context (extension getters aren't compile-time constant).
  Fixed both; CI green again on 9daff07. Flagged so the next agent doesn't re-diagnose this if
  they pick up `local_folder_screen.dart` next.

**Commit 1ae4355 — local_folder_screen.dart spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `SizedBox(height/width: 4/8/16)` and `EdgeInsets.all(8)` → `RaddSpace.xs/sm/md`
- Completes Phase 5 item 2 (color+radius were already done in 6b7c3fb, pre-existing this
  session). Remaining `Colors.white/black/transparent` are intentional poster-overlay colors —
  no token match, consistent with the kept-list pattern from Phase 4.

**Commit 90462aa — subscription_screen.dart spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `SizedBox(height/width: 4/8/16/32)` and `EdgeInsets.all(16)` → `RaddSpace.xs/sm/md/lg`
- Color+radius were already fully migrated (pre-existing) — only raw `Colors.white/transparent`
  remain (intentional, no token). Completes Phase 5 item 3.

**Commit 6c85262 — home_screen.dart spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `SizedBox(height/width: 4/8/16/24)` and `EdgeInsets.all(16)` → `RaddSpace.xs/sm/md/lg`
- Color+radius were already mostly migrated (pre-existing). Completes Phase 5 item 4.

**Commit 1af63fb — local_media_screen.dart color+spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `Color(0xFF22C55E)` → `AppColors.success` (exact value)
- `SizedBox(height/width: 4/8/16/24)` → `RaddSpace.xs/sm/md/lg`
- Kept: `Colors.white*/black*/transparent` (overlay), `Color(0xFFF97316)` (progress badge —
  distinct from `AppColors.orange` 0xFFF9800, no exact token). Completes Phase 5 item 5.

**Commit a5b7fd6 — search_screen.dart color+spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `Colors.green` → `AppColors.success`, `Colors.blue` → `AppColors.info`
- `SizedBox(height/width: 4/8/16)` → `RaddSpace.xs/sm/md`
- RaddSheet adoption deferred (see plan note — no existing modal to convert; filters are an
  inline panel). Completes Phase 5 item 6 (mechanical scope).

**Commit c262ab4 — profile_screen.dart color+spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `Color(0xFF22C55E)`→`AppColors.success`, `Color(0xFF3B82F6)`→`AppColors.info`,
  `Colors.orange`→`AppColors.orange` (exact values)
- `EdgeInsets.all(16)` and `SizedBox(height/width: 4/8/32)` → `RaddSpace.xs/sm/md/lg`
- Kept: 14 theme-swatch `Color(0xFF...)` pairs (JazzTheme picker — intentionally distinct per
  theme, not brand tokens), `Color(0xFF7C5CFF)`/`Color(0xFFFFB300)` (no exact token). Completes
  Phase 5 item 7 (mechanical scope; visual redesign still needs a wireframe per plan note).
