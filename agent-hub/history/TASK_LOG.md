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
| July 2026 | [`2026-07.md`](2026-07.md) | 16 |

---

## Session index (title only — full detail in the linked archive)

### July 2026 — Session 21 (2026-07-22) — LOGO-AUDIT-2 (canvas.tamashaweb.com CDN migration, 75/84 logos updated)

**Task:** LOGO-AUDIT-2 — re-audit all 84 live-channel logo_url values in `radd-hub/hub/db.py`.

**Root cause:** Tamashaweb migrated their CDN from WordPress (`tamashaweb.com/wp-content/uploads/20xx/xx/*.png`) to `canvas.tamashaweb.com/jazzlive/uploads/channels/*.webp`. ALL old wp-content URLs now return `Content-Type: text/html; charset=UTF-8` at HTTP 200 — dead as image sources. New canvas URLs return HTTP 200 `binary/octet-stream` (actual image bytes).

**Changes:**
- `radd-hub/hub/db.py` — `_live_seed`: 75/84 `logo_url` values updated to `canvas.tamashaweb.com` URLs extracted from the tamashaweb.com/live-tv HTML source. 9 channels absent from live page (pak-ban, ten-sports, trt-world, dunya-news, awaz-news, capital-tv, urooj-tv, atv, srf-movies) kept with old wp-content URLs (no replacement source available).
- `_logo_patches` dict (41 entries) replaced with a self-maintaining `_live_seed` loop — on every boot, all 84 channel logo_url values are synced to the current seed values. This propagates future seed updates to existing Oracle rows automatically without maintaining a separate patch dict.
- Commit `c372e136`. No Flutter files touched. No CI APK build needed.

**Notes:**
- pnn (Aik News): canvas URL `AIKNEWS-LOGO.webp` requires `Referer: https://tamashaweb.com/` header — works with Referer (HTTP 200), 403 without. Flutter CachedNetworkImage doesn't send Referer by default — logo may fail in-app.
- Oracle deploy pending (not yet run) — live DB still has old wp-content URLs until `push_to_oracle.sh` is run.

### July 2026 — Session 20 (2026-07-22) — VERSION-BUMP-1.1.0 (launch-readiness audit, bump to 1.1.0+4, AGENT_HANDOFF update)

### July 2026 — Session 19 (2026-07-19) — BB-REVIEW (Phase BB audit, CI fix, disc-spin bug)

### July 2026 — Session 18 (2026-07-16) — VAULT-SPEED (parallel bulk-add)

**Task:** VAULT-SPEED-2026-07-16 — eliminate serial awaits in vault bulk-add operations.
Three files changed in commit `9cf5631f`.

Key changes:
- New `VaultService.moveFilesToVaultBatch`: resolves dir once, parallel chunks of 4, concurrent end-of-batch MediaStore notify.
- `vault_screen.dart`: `_importVideoFolder` and `_processPickedFiles` use batch; `_deleteSelected` uses `Future.wait`.
- `local_media_screen.dart`: `_addFolderToVault` uses batch; URIs pre-collected sync before async work starts.
- `moveFileToVault` (single-file path) left intact for `local_folder_screen._addToVault`.

### July 2026 — Session 17 (2026-07-16) — APP-LOCK (full app PIN/biometric gate)

**Task:** APP-LOCK-2026-07-16 — whole-app PIN/biometric lock, independent of the vault PIN.
Five files changed in commit `11950d5e`. No new pub packages — all dependencies already present.

Key decisions:
- `_AppLockGuard` inserted in `MaterialApp.builder` as a `StatefulWidget + WidgetsBindingObserver` — overlays `AppLockScreen` widget (not a route push) when `_locked && _pinSet`, covering 100 % of the screen regardless of active route.
- Cold start: `_AppLockGuard._init()` always calls `AppLockService.lock()` if a PIN is set, so every fresh launch requires authentication.
- Resumed-from-background: `_handleResumed()` re-checks `hasPin()` on every resume, so enabling/disabling PIN in Settings is always reflected without needing the guard to re-init.
- `FLAG_SECURE` added to existing `SECURITY_CHANNEL` in `MainActivity.kt` (+ `import android.view.WindowManager`). Toggled on PIN enable, cleared on PIN remove. Also temporarily cleared while setup/change PIN screens are open so digits are visible.
- Settings screen: App Lock section (staggerIndex 5, About bumped to 6) with enable toggle, Change PIN, Biometric toggle (hidden if device has no biometrics), and Auto-lock After dialog (RadioListTile: immediately/30s/1min/5min/never).
- `app_lock_screen.dart` contains three widgets: `AppLockScreen` (overlay), `AppLockSetupScreen` (setup route), `AppLockChangePinScreen` (change-PIN route, 3-step: verify old → enter new → confirm new).

### July 2026 — Session 16 (2026-07-15) — UX-BATCH-2 (Tasks 7-9: empty state consistency, shared-element transitions on Watchlist/History, miniplayer bar replacing Home-only ResumeFab; CI green)

### July 2026 — Session 15 (2026-07-14) — BACKEND-AUDIT (10 bugs fixed across 8 Python + 2 Flutter files; proxy_pool_page.py deleted; Oracle deployed; CI green)

### July 2026 — Session 14 (2026-07-14) — PLAYER-FIXES (full audit + 5 bugs fixed)

**Task:** Audit all player feature toggles and persistence, fix anything broken.
Bugs fixed: Vivid Mode fake matrix → real Rec.709 saturation+contrast; Vivid Mode, SW Decoder,
subtitle style each not applied at startup; SW Decoder pref not saved on toggle.
Commits: `04ddc47d`, `9bc539e8`, `e911085102bb`.

### July 2026 — Session 13 (2026-07-10) — SIMPLIFY-AUTH-FLOW (verification + docs only)

**Task:** User requested simpler login/register — no genre selection or extra onboarding steps.
Previous session had already completed all code changes (commits `0c9d2f61`–`eadc104c`).
This session bootstrapped the repo, verified the clean state, and updated task tracking docs.

### July 2026 — Session 12 (2026-07-10) — Phase 6 research (account limit hit, no code written)

**Task:** Phase 6 onboarding rebuild — investigation complete, implementation deferred (account
token limit reached mid-session).

**Research findings (fully documented in `AGENT_HANDOFF.md` "Phase 6 READY TO BUILD" section):**
- Current onboarding is a generic `PageView` of 4 marketing slides; `onboardingSeenKey` is
  SET on finish but **never read** — onboarding is an orphaned route never triggered by auth flow.
- Four files change: `constants.dart` (new key), `onboarding_screen.dart` (full rewrite to
  3-step reciprocity flow), `splash_screen.dart` (routing fix), `profile_provider.dart`
  (pending watchlist sync after login).
- Genre data source confirmed: `LocalDb.searchAdvanced(genre:, limit:)` → `List<SearchResult>`
  where `SearchResult.item` is `CatalogItem`. `CatalogItem.isFree` available for Free ⚡ badge.
- `SearchResult` class confirmed at `local_db.dart:1836`.
- Watchlist sync strategy: save selected item IDs to `SharedPreferences` during onboarding
  (before login), sync to `LocalDb.addToWatchlist` in `navigateAfterAuth` after auth.

**Next agent:** read `AGENT_HANDOFF.md` top section only — all Phase 6 detail is there.
Do NOT re-read `onboarding_screen.dart`, `splash_screen.dart`, `profile_provider.dart`,
`watchlist_provider.dart`, `local_db.dart`, or `catalog_item.dart` — already done.

---

### July 2026 — Session 11 (2026-07-10) — Phase 1 + Phase 7 (this session)

**Task:** UI-UX-MIGRATION Phase 1 (investigation gaps) + Phase 7 (final readiness re-audit).

**Phase 1 — code-fixable items completed:**

*RaddMotion duration token gap (commits `d3d793c`, `730d47d`, `1ac96b8` — all CI green):*
- Added 11 missing duration constants to `radd_motion.dart` from Volume III §table:
  `tuneDuration` 200ms, `sheetEnterDuration` 260ms, `sheetExitDuration` 200ms,
  `cardPressDown` 120ms, `cardPressUp` 160ms, `heroDuration` 320ms, `railItemDuration` 240ms,
  `railItemDelay` 40ms, `lockKeyDuration` 220ms, `bottomNavDuration` 180ms, `emptyStateDelay` 400ms.
- Corrected two wrong curves: `sheetEnter` `easeOutCubic` → `Cubic(0.16,1,0.3,1)`;
  `sheetExit` `easeInCubic` → `Cubic(0.4,0,1,1)`. These had been wrong since the file was written.
- Swept all raw `Duration(milliseconds:...)` literals out of design-system components:
  `RaddSheet` → `tuneDuration`; `RaddCard`/`RaddButton` → `cardPressDown`; `RaddChip` → `tuneDuration`;
  `RaddLockPad` key → `lockKeyDuration` (also corrected from 120ms → 220ms per spec — the key
  animation was running at card-press speed, not lock-key spring speed).

*Accessibility code-fixable subset (commits `730d47d`, `9b8d2a6` — all CI green):*
- `RaddSheet` close button: `GestureDetector+Icon+manual Semantics` → `IconButton(tooltip:)` —
  natively focusable, 48×48 touch target, proper screen-reader label.
- `RaddSheet`: added `FocusScope` focus trap + `SemanticsService.announce` on sheet open.
- Pre-existing ✅ confirmed: `RaddBanner` announce, `RaddButton` icon tooltip, `RaddCard` Semantics.

*Phase 1 items still needing live device:*
- Player HUD: center third clear ✅ and 3s auto-hide ✅ from static code. Panel height
  violations (62–90% vs 40% spec) and transport-row extras (Lock/Immersive/Settings vs spec's
  "⋯ More") need PM decision — not removable without product sign-off.
- TalkBack focus-order audit, `_RaddIconBtn` touch targets, caption-on-by-default: need device.

**Phase 7 — Design debt re-audit (2026-07-10):**

Grep re-run against `raddflix_flutter/lib/` (excl. `design_system/`, `core/`):

| Category | Baseline (2026-07-09) | Now (2026-07-10) | Δ |
|---|---|---|---|
| `Colors.*` | 2,563 | 2,305 | **−258 (−10.1%)** |
| `AppColors.*` | 603 | 524 | **−79 (−13.1%)** |
| `Color(0x...)` | 372 | 325 | **−47 (−12.6%)** |
| `Duration(ms...)` | 197 | 195 | **−2 (−1%)** |
| `Curves.*` | 92 | 92 | 0 |
| `RaddSpace` in screens/ | 0 | 265 | **+265 new** |
| `RaddRadius` in screens/ | 0 | 67 | **+67 new** |
| `context.signal*/context.t.*` in screens/ | ~0 | 125 | **+125 new** |
| `RaddSheet` usages | 1 | 14 | **+13** |
| `RaddLockPad` usages | 0 | 6 | **+6** |
| `RaddTextField` usages | 3 | 10 | **+7** |
| `RaddButton`/`RaddCard`/`RaddChip`/`RaddBanner` usages | 0 each | 0 each | 0 |

Note: `EdgeInsets.*`, `BorderRadius.circular()`, `TextStyle(` baselines used a different
grep scope — those rows have a methodology gap and are not compared numerically above. See
`docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` §1 for the full updated dashboard with flags.

**Overall Release Readiness: ~15–20% → ~25–30% (+~10%).**
Remaining gap dominated by: (1) `RaddButton`/`RaddCard` still 0 usages in screens;
(2) typography tokens (`context.radd*`) still 0 screen adoption; (3) Onboarding rebuild
(Phase 6) not started.

**Next open work:** Phase 6 — onboarding rebuild (new feature). Phases 1/7 are the only
remaining non-complete items; Phase 1's open sub-item needs a real device.

---

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

**Commit bb68f02 — downloads_screen.dart color+spacing pass:**
- Added `import '../design_system/spacing/radd_space.dart'`
- `Color(0xFF22C55E)` → `AppColors.success` (exact value)
- `EdgeInsets.all(16)` and `SizedBox(height/width: 4/8/24)` → `RaddSpace.xs/sm/md/lg`
- Kept: `Colors.white*/black*/transparent` (thumbnail overlay, no token). Completes Phase 5
  item 8.

---

## 2026-07-10 — PROFILE-FIELD-FOCUS + PLAYER-LANDSCAPE-PANELS

### Task
Two UX improvement areas: (1) profile edit screen field styling and avatar interactivity, (2) video player settings panels in landscape mode — whether video is visible while panels are open.

### edit_profile_screen.dart — animated field focus

**Root cause / gap:** `_Field` was a `StatelessWidget` with no focus tracking — tapping a field gave zero visual feedback. Label was 11pt (spec says 12pt). Icon box radius hardcoded `9` (should be `RaddRadius.smRadius` = 8).

**Changes:**
- `_Field` → `StatefulWidget` with `FocusNode` created in `initState`, disposed in `dispose`
- `AnimatedContainer` wraps icon box: bg tints from `primary.withOpacity(0.08)` → `0.15` on focus
- `AnimatedDefaultTextStyle` wraps label: color transitions from `textMuted` → `AppColors.primary` on focus; `duration: RaddMotion.pulse` (300ms)
- Label `fontSize` fixed to `12` (was `11`)
- Icon box `borderRadius` changed to `RaddRadius.smRadius`

### player_screen.dart — landscape panel routing + barrier fix

**Root cause / gap:** `_openRightPanel()` used a 60% black barrier over the video — user couldn't see what was playing while adjusting settings. All 7 panel openers called `RaddSheet.show` unconditionally — in landscape this covers ~85% of screen height.

**Changes to `_openRightPanel`:**
- Barrier opacity: `0.38 → 0.12` (video clearly visible through the dim)
- Panel background: `Colors.black.withOpacity(0.60)` → `const Color(0xEA1C1C1E)` (solid dark surface, panel content stays readable)

**Landscape routing added to all 7 panel openers:**
Each function now checks orientation at the top. If landscape, constructs the panel widget as a `final panel` variable and calls `_openRightPanel(panel, widthFactor: N)` then returns. Portrait path unchanged (same `setState + RaddSheet.show`).

| Function | widthFactor |
|---|---|
| `_openSubtitlePanel` | 0.42 |
| `_openAudioPanel` | 0.38 |
| `_openZoomPanel` | 0.30 |
| `_openAudioEffectPanel` | 0.44 |
| `_openMoreMenu` | 0.40 |
| `_openSidebarCustomizer` | 0.40 |
| `_openSettingsPanel` | 0.42 |

**Files touched:** `raddflix_flutter/lib/screens/edit_profile_screen.dart`, `raddflix_flutter/lib/screens/player_screen.dart`

**Commit:** `72f93a8d589ff2f9f706c62936ec21ab28113293`

**Preflight:** passed (0 violations)

**CI:** `build-apk.yml` triggered on `72f93a8d` — verify run succeeds (Rule 46)

---

## 2026-07-11 — PHASE-A-2026-07-11

### Task
Phase A of TEN_POINT_PLAN.md: 9 fix categories, 15 discrete sub-tasks.

### Changes

**A1 — mounted guard** `edit_profile_screen.dart`
Added `if (mounted)` before `setState` in the `on Exception catch` block of `_save()`. Prevents `setState() called after dispose()` if user pops the screen while the updateProfile request is in-flight.

**A2 — delete dead file** `lib/screens/layout_designer_screen.dart`
Deleted the 484-line dead copy of layout_designer_screen.dart. `app.dart` already imports the live copy from `lib/screens/player/layout_designer_screen.dart`. The dead copy has caused at least one prior bug (agent edited wrong file).

**A3 — voice stub** `voice_commands_service.dart`
`requestPermission()` changed from `async => true` to `async => false`. The class is a stub with no real STT implementation — returning `true` was a lie that misled the UI into showing voice commands as available.

**A4 — fake KBPS** `n_series_network.dart`
`NetworkSpeedMonitor.start()` no longer emits fabricated kbps values derived from `now % 13500`. `_kbps` stays at 0 so `format()` returns `'—'`.

**A5 — session leaks** `watchlist_provider.dart`, `profile_provider.dart`, `auth_provider.dart`
Added `WatchlistNotifier.clear()` and `ProfileNotifier.reset()`. `AuthNotifier` now stores a `Ref` and calls all three providers' clear/reset in `logout()`. Prevents User A's watchlist/profile from persisting into User B's session.

**A6 — debounce** `search_screen.dart`
Debounce raised from 220ms to 400ms. Was firing on nearly every autocorrect keypress.

**A7 — RepaintBoundary** `particle_overlay.dart`, `eq_visualizer.dart`, `ambilight_glow_border.dart`
Added `RepaintBoundary` around each animated widget root. Each was triggering full ancestor-tree repaints on every animation frame — expensive on Snapdragon 400/600 devices.

**A8 — build() compute** `home_screen.dart`, `search_screen.dart`, `profile_screen.dart`
- home_screen: greeting cached in `late String _greetingTod` computed in `initState()`
- search_screen: `_cachedAllItems` field populated in `_loadFilterMeta()`; `build()` uses cache
- profile_screen: greeting cached in `late String _greetingTod` computed in `initState()`

**A9 — catalog select** `home_screen.dart`
`ref.watch(catalogProvider)` replaced with a Dart-3 record select over display-critical fields (counts + status). `totalCount` increments no longer trigger sliver-grid rebuilds.

### Outcome
All Phase A checkboxes marked `[x]` in `agent-hub/TEN_POINT_PLAN.md`. Ready for Phase B.


---

## 2026-07-11 — PHASE-B-2026-07-11

### Task
Phase B of TEN_POINT_PLAN.md: database performance — 7 items across local_db.dart, sync_service.dart, catalog_provider.dart, constants.dart.

### Changes

**B1 — N+1 → batch** `local_db.dart`, `catalog_provider.dart`
Added `LocalDb.getEpisodesForIds(List<int> ids)`: single `SELECT * FROM episodes WHERE title_id IN (?,...)` returns all shows' episodes in one round-trip. `CatalogNotifier._loadFromDb` updated to call this instead of one `getEpisodes(id)` per show. On a 200-show catalog: startup DB round-trips drop from 201 → 2.

**B2 — getTopFreeMovies device ID** `local_db.dart`
`getTopFreeMovies` now calls `DeviceIdentifier.getDeviceId()` once before the decode loop. `RequestEncoder.unscrambleUrl` is synchronous so each row's decode is now CPU-only (was: one async await per RF1-encoded URL).

**B3 — getPendingUsageBytes SUM** `local_db.dart`
Replaced Dart row-accumulation loop with `SELECT COALESCE(SUM(bytes), 0) AS total FROM usage_log WHERE flushed = 0`.

**B4 — Atomic sync transaction** `local_db.dart`, `sync_service.dart`
Added `LocalDb.persistBatch(List<CatalogItem> items)`: wraps all title + episode inserts in `db.transaction()`, gets device ID once for encode. `sync_service._persistItems` now delegates here. Partial-sync corruption on power loss is now impossible.

**B5 — Missing indexes** `local_db.dart`, `constants.dart`
- Fresh installs: `_createAll` gains `idx_episodes_file_id` and `idx_watch_positions_file_id`
- Upgraded devices: migration v22 adds all four indexes (`idx_episodes_title`, `idx_titles_type`, `idx_episodes_file_id`, `idx_watch_positions_file_id`) with `IF NOT EXISTS`
- `catalogDbVersion` bumped 21 → 22

**B6 — FTS rebuild delay** `local_db.dart`
`rebuildFtsIndex()` awaits `Future.delayed(5s)` so the calling widget tree renders its first frame before the heavy FTS rebuild begins. Full isolate approach deferred pending SQLCipher key-passing validation.

**B7 — Sync retry** `sync_service.dart`
Added `_withRetry<T>(fn, {attempts=3})` with exponential back-off (2 s, 4 s). `CatalogApi.syncFull()` and `CatalogApi.syncDelta()` are now wrapped.

### Outcome
All Phase B checkboxes marked `[x]` in `agent-hub/TEN_POINT_PLAN.md`. Ready for Phase C.

---

## 2026-07-12 — PHASE-F-2026-07-12

### Task
Phase F of TEN_POINT_PLAN.md: Design System Migration — remaining 70% of screens (28 tasks).
Mechanical token-swap pass: raw Color/spacing/radius/duration literals → AppColors/RaddSpace/RaddRadius/RaddMotion tokens; RaddButton/RaddChip/SettingsRow component adoption where applicable.

### Changes

**F01 — `home_screen.dart`**
`RaddButton` for primary action buttons; `RaddMotion.tuneDuration` for animated containers; `RaddSpace.*` spacing tokens throughout.

**F02 — `show_detail_screen.dart`**
`RaddMotion.tuneDuration` + `RaddRadius.smRadius/mdRadius/lgRadius` replacing raw `Duration(milliseconds:...)` and `BorderRadius.circular(...)` literals.

**F03 — `search_screen.dart`**
`RaddMotion.tuneDuration`; `RaddChip` for filter chips.

**F04 — `profile_screen.dart`**
`AppColors.simosaAccent` replacing SIMOSA-purple raw hex; `RaddButton`.

**F05–F07 — `downloads_screen.dart`, `local_folder_screen.dart`, `local_media_screen.dart`**
`RaddMotion.tuneDuration`; `Colors.*` → `AppColors.*` tokens.

**F08 — `settings_screen.dart`**
Full `SettingsRow` adoption for all settings items; raw spacing/radius literals replaced.

**F09 — `login_screen.dart`**
`RaddButton` replaces `_GradientButton` and OTP `OutlinedButton`s; `AppColors.warning` for orange; `_GradientButton` helper deleted.

**F10 — `register_screen.dart`**
`RaddButton` replaces inline gradient button + `OutlinedButton`.

**F11 — `subscription_screen.dart`**
`RaddMotion.tuneDuration` for animated expansions.

**F12 — `edit_profile_screen.dart`**
`RaddMotion.tuneDuration` for field focus animations.

**F13 — `vault_screen.dart`, `vault_settings_screen.dart`**
`AppColors.simosaAccent` replacing SIMOSA-purple hex; remaining radius/spacing tokens.

**F14 — `debug_diagnostics_screen.dart`**
`AppColors.success`/`AppColors.error`; `RaddRadius` tokens.

**F15–F17, F20–F24 — various screens**
`tid_status`, `add_edit_profile`, `profile_switcher`, `actor`, `admin_queue`, `plan_expired`, `quota_full`, `season_folder`, `onboarding`: literals with no exact token kept with `// intentional: no token` comments.

**F18 — `history_screen.dart`**, **F19 — `watchlist_screen.dart`**
`RaddRadius.mdRadius` replacing `BorderRadius.circular(12)`.

**F25 — `content_card.dart`**
`AppColors.success`/`AppColors.info` replacing `Colors.green`/`Colors.blue`.

**F26 — `simosa_card.dart`**
`AppColors.primary`/`AppColors.primaryDark` for gradient stops.

**F27 — `quick_settings_panel.dart`** (1,684 lines)
`RaddRadius.smRadius/mdRadius/lgRadius` + `RaddMotion.tuneDuration` across all panel sections.

**F28 — `player_hud_settings_sheet.dart`** (1,145 lines)
`RaddRadius.smRadius` + `RaddMotion.tuneDuration`.

**Fix — `radd_button.dart`**
`PhosphorIcons.dotsThreeBold` → `PhosphorIcons.dotsThreeVertical()` (non-existent member caught by CI).

### Outcome
All 28 Phase F checkboxes marked `[x]` in `agent-hub/TEN_POINT_PLAN.md`. CI green on `62867e45`.
Commits: `b7a26ba`, `3cbe121`, `7389e61`, `9614ee0`, `1d91c8ab`, `76ead2d3`, `62867e45`.
AGENT_HANDOFF.md and TASK_LOG.md were NOT updated by the executing agent — fixed this session.
Ready for Phase L (Production Hygiene).

---

## 2026-07-12 — PHASE-L-2026-07-12

### Task
Phase L of TEN_POINT_PLAN.md: Production Hygiene — remove developer artifacts from release builds.
Goal: nothing developer-only visible, reachable, or leaking in production APK.

### Verification findings (before coding)
- **L6** already fixed (BUG-C02 in `_openMediaForEpisode`) — `_isFree` correctly resets per episode.
- **L8** `actor_service.dart` has zero `DebugLogger` calls — finding was stale.
- **L4b** `subtitle_hunter_sheet.dart` not at expected path — finding was stale.
- **L4f** `add_edit_profile_screen.dart` already uses friendly strings (`'Could not save profile'`, etc.).
- **L5a–c** `_friendlyError()` and `AuthErrors.login/register()` already return generic final messages.

### Changes

**L1 + L2 + L9 — `profile_screen.dart`** (commit `7035956`)
- Debug Logs `_SectionTile` wrapped: `if (kDebugMode || (user?.isAdmin == true)) ...[divider, tile]`.
- 5-tap easter egg navigation wrapped same condition — silently resets counter for non-admin release builds.
- Removed `// BUG-A23`, `// BUG-A21`, `// BUG-A22` tags from import lines.
- Removed `// BUG-A14:` comment block (fix was already in place).
- Rewrote inline BUG-A comments to plain English.

**L7 — `app.dart`** (commit `6f27ca0`)
- Added `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43).
- All 4 `_RaddNavObserver` methods gate their `DebugLogger.logNav(...)` with `if (kDebugMode)`.

**L3 — `debug_diagnostics_screen.dart`** (commit `e65617b`)
- `DebugLogger.getLogPath()` → `'Log stored on device'` (raw internal FS path removed).

**L4c + L4d + L4e — `admin_queue`, `edit_profile`, `subscription`** (commit `049dfaf`)
- `admin_queue_screen.dart`: `_error = e.toString()` → friendly + kDebugMode log.
- `edit_profile_screen.dart`: 2 catch paths → friendly + kDebugMode log; foundation import added.
- `subscription_screen.dart`: `e.toString().replaceFirst('Exception: ', '')` → friendly string.

**L4a — `vault_screen.dart`** (commit `7231766`)
- 3 SnackBar catch blocks: `'...: $e'` → friendly static strings + kDebugMode log; foundation import added.

### Deferred
- **L10** `ApiClient.isGuestMode` mutable static: belongs in Phase G/E3 Riverpod migration session.

### Outcome
All actionable L items complete. L10 deferred. CI green on `7231766b`.
Phase L marked ✅ DONE in TASKS.md. Ready for Phase G.

---

## 2026-07-12 — PHASE-G-2026-07-12 (partial)

### Task
Phase G of TEN_POINT_PLAN.md: Architecture Modernisation.
Session focused on G2 (animation package consolidation) with investigation of G1/G3/G4/G5 scope.

### Verification findings (before coding)

**G2:**
- `flutter_staggered_animations`: zero usages via grep across all lib/*.dart → safe to remove.
- `animated_text_kit`: zero usages → safe to remove.
- `animations` (OpenContainer): used in `home_screen.dart` L481 and `search_screen.dart` L836
  for Tier 2+ card-expand morph; non-trivial to replace → kept.

**G4 (dead file audit):**
- 13 lettered series files in `core/player/` all have zero imports (grep confirmed):
  c/d/f/g/n/o/p/q/r/s/t/u/v series files.
- Each file is 100–300 lines of feature stub code (planned features not yet connected).
- **Decision: defer deletion — requires user confirmation per TEN_POINT_PLAN G4 note.**

**G3 (video_thumbnail → media_kit):**
- 2 call sites: `thumb_service.dart` + `local_media_service.dart`.
- Platform channels cannot be used inside `compute()` isolates, so the plan's
  "media_kit in compute()" approach needs a different mechanism.
- **Decision: defer to dedicated investigation session.**

**G5 (AppConstants mutable statics → Riverpod):**
- `AppConstants.apiBaseUrl`, `jazzDriveDeltaUrl`, `supportWhatsApp` are `static var`.
- `RemoteConfig.fetch()` writes to them at startup; `ApiClient` reads `apiBaseUrl` repeatedly.
- Complex refactor; same session as L10 (`ApiClient.isGuestMode`).
- **Decision: defer to Phase G5 session.**

### Changes

**G2 — `pubspec.yaml`** (commit `58a0137`)
- Removed `flutter_staggered_animations: ^1.1.1` (zero usages).
- Removed `animated_text_kit: ^4.2.2` (zero usages).
- Kept `animations: ^2.0.11` with rationale comment (OpenContainer in 2 screens).
- Estimated APK size reduction: ~100–200KB from two removed packages.

### Deferred to next G session
- G1: go_router migration (large, all Navigator.pushNamed call sites).
- G3: video_thumbnail replacement (needs platform-safe frame extraction approach).
- G4: lettered series file deletion (user confirmation required first).
- G5 + L10: AppConstants + ApiClient.isGuestMode → Riverpod (complex, dedicated session).

### Outcome
G2 partial complete. CI pending on `58a01378`.
Phase G marked ⏳ IN PROGRESS in TASKS.md.


---

## 2026-07-14 — AUDIO-PANEL-SAVE-2026-07-14

### Task
Targeted audit of all `_openAudioEffectPanel` callbacks in `_ps_ui_mixin.dart` for the
"applies but doesn't save" bug class (same as SW Decoder / SmartEnhance bugs fixed in
the previous session). Also closed PHASE-H and UI-UX-MIGRATION at user direction.

### Audit findings

Every callback in `_openAudioEffectPanel` checked:

| Callback | Wired to | `_scheduleSavePrefs()` called? |
|---|---|---|
| `onEqBandChanged` | inline lambda | ✅ yes |
| `onEqEnabledChanged` | inline lambda | ✅ yes |
| `onReverbChanged` | inline lambda | ✅ yes |
| `onLabAfChanged` | inline lambda | ⚠️ no (but safe — `_applyLabAf()` always co-fires `onLabStateChanged` which saves) |
| `onLabStateChanged` | inline lambda | ✅ yes |
| `onBalanceChanged` | `_applyBalance` directly | ✅ yes |
| `onPresetSelected` | `_applyPreset` directly | ❌ **BUG — missing** |

### Bug fixed

**`_applyPreset` in `_ps_audiolab_mixin.dart`** — called directly as `onPresetSelected: _applyPreset`.
Applies the 10-band EQ preset to MPV via `_applyAllAf()` but never calls `_scheduleSavePrefs()`.
Selecting "Treble Boost", "Bass Boost", etc. was applied immediately but lost on next cold start.
Fix: added `_scheduleSavePrefs();` after `_applyAllAf();` inside `_applyPreset()`.

### PHASE-H closed (user direction)
H1/H4/H5 done (test/ structure, CI job, design-system widget tests, prefs round-trip).
H1/H4/H5 done — test/ structure, CI job, design-system widget tests, prefs round-trip. Infrastructure goal complete.

### UI-UX-MIGRATION closed (user direction)
Phases 2–7 complete, CI green on all commits. Phase 1 "Player HUD footprint" closed via
static-code analysis — no 5-control rule violation confirmed. Live-device pixel measurement
deferred indefinitely (no SDK/emulator in env) and accepted as sufficient closure.

### Outcome
Code fix: 1 line added to `_ps_audiolab_mixin.dart`. Docs updated: TASKS.md, AGENT_HANDOFF.md,
TEN_POINT_PLAN.md, UI_UX_MIGRATION_PLAN.md, TASK_LOG.md. CI pending.

---

## 2026-07-14 — BILLING-FIX-2026-07-14

### Task
`GET /billing/` returning HTTP 500 `{"error":"internal error"}` on the live Oracle server.

### Diagnosis
- SSHed to server, found logs: `Exception: OperationalError` immediately before the 500.
- Live DB checked via sqlite3: `received_sms_payments` table does not exist.
- Searched codebase: table referenced in `payment_gateway.py` (3×), `tid_panel.py` (4×),
  `db_mgmt.py` (2×) — but never added to `db.py`'s `_DDL` list. Never created.
- Also found: `payment_methods` has only 7 columns on live server; code uses 12 (5 missing).
- Also found: no POST `/billing/api/sms/receive` endpoint despite gateway-key UI.

### Fix
`radd-hub/hub/db.py`:
- Added `received_sms_payments` CREATE TABLE (8 columns: id, source, tid, amount_pkr,
  sender_phone, raw_sms, received_at, matched_payment_id) + 2 indexes to `_DDL`.
- Added 5 ALTER TABLE migrations for missing `payment_methods` columns.
- Added default payment method seeding (EasyPaisa/JazzCash/NayaPay/SadaPay) after init.
- Added auto-generation of `sms_gateway_key` in init_db() if not already set.

`radd-hub/hub/routes/payment_gateway.py`:
- Added POST `/billing/api/sms/receive` — gateway-key auth (body or X-Gateway-Key header),
  stores SMS in `received_sms_payments`, auto-matches by TID to pending `tid_payments`,
  auto-approves if `sms_auto_approve_enabled=1`.

### Outcome
Deployed via `push_to_oracle.sh`. `GET /billing/ → 200` confirmed in live server logs.
Commit: `90328920`.

---

## 2026-07-15 — UX3-10-CI-FIX-AND-BUG-AUDIT

### Task
`76a64295` (final commit of the UX-BATCH-3 session, "true background miniplayer") left
`build-apk.yml` red. Verify the failure, find root cause, then audit all 8 changed files for
further logic/UI/UX bugs and fix everything found.

### Root cause (CI break)
`_ps_ui_mixin.dart:1048: Error: The getter '_minimizePlayer' isn't defined for the class
'_PlayerUIMixin'.` These `player/_ps_*.dart` files are all `part of '../player_screen.dart'`,
composing several mixins onto `_PlayerScreenState`; each mixin's `on ConsumerState<PlayerScreen>`
clause means it only sees its own members plus an explicit abstract "cross-cluster members" block
declared at its top. `_minimizePlayer()` lives in `_PlayerPlaybackMixin` but the new minimize
button in `_PlayerUIMixin` called it without adding `void _minimizePlayer();` to that block —
every other cross-cluster call in the file (`_openMedia`, `_toggleMute`, etc.) had one, this one
was missed. Fix: added the missing declaration.

### Bugs found in the wider audit
1. **Usage/billing tracking silently stopped on minimize.** `_stopUsageTimer()` ran
   unconditionally in `PlayerScreen.dispose()`, including on the minimize path — but the 30s
   heartbeat (`UsageService.addWatchSession`) lived only on that timer. A minimized paid stream
   kept playing via `PlaybackService` completely untracked/unbilled until reopened.
2. **Resume position froze at minimize time.** Same problem for the 10s periodic
   `_saveWatchPos()` timer — `PlaybackService` never had an equivalent, so a session left
   minimized for a while (then killed before reattaching) would resume from the position at
   minimize time, not wherever it actually got to.
3. **Watch-party / voice commands killed on minimize.** `WatchPartyService.instance.leaveRoom()`
   and `VoiceCommandsService.instance.stop()` also ran unconditionally in `dispose()` — minimizing
   during a watch party silently dropped the user from the room even though playback continued.
4. **No confirmation on the mini-bar stop button.** A single un-confirmed tap on a small 16px
   icon ended a live (possibly paid) session outright, unlike other destructive controls in the
   same UX batch which do confirm.
5. **Back and Minimize were visually identical**, sitting adjacent in the top bar despite very
   different consequences (end session vs. keep it running).

### Fix
- `_ps_ui_mixin.dart`: added `void _minimizePlayer();` to the cross-cluster block; dimmed the
  minimize icon (`Colors.white70`) relative to Back.
- `player_screen.dart`: `_RaddIconBtn` now takes an optional `color`; `dispose()` gates
  `WatchPartyService.leaveRoom()`, `VoiceCommandsService.stop()`, and `_stopUsageTimer()` behind
  `if (!_handedOffToService)`.
- `services/playback_service.dart`: added `trackUsage`/`posKey` fields captured at `adopt()`
  time, plus its own 30s usage-heartbeat timer and 10s position-save timer (started in `adopt()`,
  stopped in `detachForReattach()`/`_disposeCurrent()`) so both keep running for as long as a
  session lives in the service, not just while `PlayerScreen` is mounted.
- `_ps_playback_mixin.dart`: `_minimizePlayer()` now passes `trackUsage: _trackUsage` and
  `posKey: _posKey` through to `adopt()`.
- `widgets/mini_player_bar.dart`: stop button now shows an `AlertDialog` confirmation
  (matching the existing dialog style used elsewhere in the player) before calling `service.stop()`.

### Note on ephemeral live-only state (checked, not a bug)
Considered whether reattaching after minimize loses in-memory-only settings (zoom, speed, EQ,
etc.) that hadn't yet been debounce-saved to prefs. Not an issue: `dispose()` already cancels the
save debounce and calls `_savePrefs()` synchronously on every dispose, including the minimize
path, before the pop — so prefs reflect the exact live state at minimize time by the time a
reattach's `_loadPrefs()` runs.

### Outcome
CI `5cf5c0e` confirmed green (`build-apk.yml`, run completed with `conclusion: success`).

---

## 2026-07-15 — PLAYER-FORMAT-COVERAGE-AUDIT

### Task
"Make sure the video player plays every audio track and video format."

### Investigation
Playback engine side (media_kit + `media_kit_libs_android_video`, i.e. mpv with a bundled
full ffmpeg) already handles essentially any container/codec it's handed, and the audio-track
layer was already solid: `_AudioTrackPanel` lists every real track (filtered only to exclude
the synthetic `auto`/`no` placeholder entries), track switching sets both the media_kit API and
the native `aid` mpv property as a belt-and-braces fallback for DASH/HLS streams where the
media_kit call has been observed to silently no-op, saved-language preference re-applies itself
on every new file load, and EAC3/DTS/TrueHD/MLP already auto-fall back to the SW audio decoder
(gated so `hwdec` is never flipped while frames are actively decoding — the MediaTek/Infinix
black-screen rule). No engine-level or track-selection gap found.

The real gap was upstream of the engine: three separately hand-maintained Dart extension
allowlists that gate whether a *local* file is even offered to the player, all recognizing only
~10 containers (`mp4/mkv/avi/mov/ts/m2ts/wmv/flv/webm/3gp`) despite mpv/ffmpeg supporting far
more:
- `VaultFile.isVideo` (`vault_service.dart`) — this one gated `_openFile` in `vault_screen.dart`
  directly, so a file outside its list could never be opened from the Vault at all, not even a
  "wrong format" error — the tap silently did nothing.
- Vault folder-import filter (`vault_screen.dart`) — its own separate, slightly different list.
- `local_media_service.dart` filesystem fallback scan — used when the MediaStore channel query
  throws; MediaStore itself is not extension-filtered (it trusts Android's own MIME detection),
  so this only affected the fallback path, but was still narrower than necessary.
Remote/streamed content isn't affected — `_openMedia` always calls `_player.open(Media(...))`
on whatever URL/path it's given regardless of extension, and downloads are byte-for-byte copies
(never transcoded) saved under a fixed `.mp4` name that mpv still content-sniffs correctly
regardless of the real container.

### Fix
Added `AppConstants.playableVideoExtensions` — one canonical set covering every container mpv/
ffmpeg actually demuxes (`mp4, m4v, mkv, webm, avi, mov, wmv, flv, f4v, 3gp, 3g2, ts, m2ts, mts,
mpg, mpeg, m2v, mpv, vob, ogv, ogm, divx, asf, rm, rmvb, y4m, mxf`). Repointed all three call
sites (`vault_service.dart`'s `isVideo`, the Vault folder-import filter, and the
`local_media_service.dart` fallback scan) at it so a file mpv can already decode is never hidden
as "not a video" by a narrower Dart-side gate.

### Outcome
CI `2d419f4` confirmed green.

---

## 2026-07-15 — Vault UX Fixes (Restore Crash + MediaStore Ghost + Progress + Unlock Gate)

### Task
User reported four vault issues: (1) no feedback when locking local media — app feels heavy, (2) files still visible in MX Player / file managers after vault add, (3) restore shows a bug warning and file stays in vault, (4) folder lock has no progress or feedback.

### Root Causes

**Bug 1 — Restore crash / file stuck:**
`_restoreToGallery` in `vault_screen.dart` hardcoded the destination as `/storage/emulated/0/Download`. On Android 11+ (API 30+), `WRITE_EXTERNAL_STORAGE` is declared `maxSdkVersion="29"` in the manifest. `File.copy()` to that path throws `Permission denied`. The exception was caught in the catch block — correct — but the catch block never called `File.delete()` on the vault source, so the file stayed in the vault permanently while showing an error snackbar. The file was stuck until the user manually deleted it from the vault.

**Bug 2 — MediaStore ghost entries:**
`local_media_screen._addFolderToVault()` and `local_folder_screen._addToVault()` both called `VaultService.moveFileToVault(v.filePath)` — which moves the file to internal private storage — but never called `deleteFromMediaStore()`. MediaStore keeps a database record even after the file is moved; file managers and video players (MX Player, VLC, Files by Google) read MediaStore, not the filesystem directly, so they kept showing the files as if they were still there. `moveFileToVault` does call `notifyMediaStore(sourcePath)` (scan-file), but on Android 11+ this isn't sufficient to remove entries — deletion by content URI is required.

**Bug 3 — No progress feedback:**
All four vault-add code paths (`_processPickedFiles`, `_importVideoFolder` in vault_screen; `_addFolderToVault` in local_media_screen; `_addToVault` in local_folder_screen) ran their file I/O loops with zero UI feedback. For a folder with many large video files (common on Pakistani handsets with 50–100+ movies stored locally), this felt like a freeze.

**Bug 4 — Missing unlock gate:**
`local_folder_screen._addToVault()` checked `VaultService.hasPin()` (PIN is configured) but not `VaultService.isUnlocked` (user currently authenticated). A user with a PIN set but vault currently locked could silently move files without entering the PIN.

### Fix

**Native layer (`MainActivity.kt`):** Added `"copyToDownloads"` case to the existing `MEDIA_CHANNEL`. On API 29+: inserts via `MediaStore.Downloads.EXTERNAL_CONTENT_URI` with `IS_PENDING=1`, streams bytes from the vault file, then clears `IS_PENDING=0` — returns the `content://` URI. On API <29: direct `File.copyTo` to `Environment.DIRECTORY_DOWNLOADS` + `MediaScannerConnection.scanFile`. No new permissions needed.

**`VaultService.restoreFileToDownloads()`:** New method that calls native `copyToDownloads`, waits for success, then and only then deletes the vault source. Replaces `restoreFile()` for the gallery restore path.

**`_VaultProgressDialog` widget (vault_screen.dart):** Shared `StatelessWidget` wrapping an `AlertDialog` with a `ValueListenableBuilder<int>` that drives a `LinearProgressIndicator`. Callers hold a `ValueNotifier<int>` and increment it from their async loop; single-file variant shows a spinner instead of a bar.

**`deleteFromMediaStore` calls added:** Content URI constructed from `LocalVideo.id` → `content://media/external/video/media/{id}`. Called after each batch of moves in both local screens.

**`isUnlocked` check added** to `local_folder_screen._addToVault`.

### Files Changed
- `MainActivity.kt` — `copyToDownloads` native method (+64 lines)
- `vault_service.dart` — `restoreFileToDownloads()` (+30 lines)
- `vault_screen.dart` — fix restore, add progress to import paths, add `_VaultProgressDialog` widget
- `local_media_screen.dart` — progress dialog + MediaStore cleanup in `_addFolderToVault`
- `local_folder_screen.dart` — progress dialog + MediaStore cleanup + unlock gate in `_addToVault`

### Outcome
Commit `4c3c2574` (main fixes) — CI failed: `setState` and `widget.folder` called inside `_VideoListTile extends StatelessWidget` where neither is available. Fix: removed the invalid `setState(() { widget.folder.videos.remove(video); })` call — the snackbar confirmation is sufficient; the tile is a StatelessWidget and cannot directly mutate parent state. Commit `b91768e4` — CI ✅ green.

**Lesson:** `_VideoListTile` in `local_folder_screen.dart` is a `StatelessWidget`. Any future method added to it that needs to update the parent list must use a VoidCallback (e.g. `onMoved`) passed in from `_LocalFolderScreenState`, not `setState`/`widget.folder` directly.

---

## 2026-07-15 — UX-BATCH-3 Docs Catch-Up (UX3-01 through UX3-10 + BUG-DL-EXT-01)

### Task
TASKS.md was stale — all 10 UX-BATCH-3 tasks and BUG-DL-EXT-01 were already done in code by a prior agent in this session but never marked ✅ DONE in the docs.

### Verification
Checked each task by:
1. `git log --oneline` — confirmed individual commits for every UX3 task exist on `main`.
2. Grepped target files to confirm the code changes are present (showDialog in settings_screen, SharedPreferences key in watchlist_screen, try/catch + `_syncError` banner in history_screen, subscriptionProvider gate in mini_player_bar, OpenContainer in actor_screen, no-PIN dialog in downloads_screen, FadeTransition in profile_switcher_screen, extracted widgets in show_detail_screen).
3. Checked GitHub Actions `build-apk.yml` for all commits — all green except `76a64295` (UX3-10 original, compile error) which was immediately fixed by `5cf5c0e0` (CI ✅).

### Commits and CI
| Commit | Task | CI |
|---|---|---|
| `613b6023` | UX3-01: Clear Image Cache confirmation dialog | ✅ |
| `722b360e` | UX3-02: Watchlist sort order persisted to SharedPreferences | ✅ |
| `f8f3ecbe` | UX3-03: History sync error banner with Retry | ✅ |
| `3cccc1df` | UX3-04: MiniPlayerBar subscription gate → dialog | ✅ |
| `dca97b15` | UX3-05: Actor filmography OpenContainer morph | ✅ |
| `cd4b0aa9` | UX3-06: Downloads vault no-PIN setup dialog | ✅ |
| `2c13acf0` | UX3-07: ProfileSwitcher Tier 0/1 fade transition | ✅ |
| `c73ef055` | UX3-08+09: ShowDetail widget extraction + skeleton shimmer | ✅ |
| `76a64295` | UX3-10: Background miniplayer + PlaybackService | ❌ (compile error) |
| `5cf5c0e0` | UX3-10-FIXES: missing abstract decl + 4 runtime bugs | ✅ |
| `70334a63` | BUG-DL-EXT-01: real extension in downloads + ThumbService cache | ✅ |

### Doc Changes
Updated `agent-hub/TASKS.md` (all UX3 rows → ✅ DONE with commit SHAs; BUG-DL-EXT-01 row added), `AGENT_HANDOFF.md` (new Current State section prepended), and this log.

---

## 2026-07-16 — PLANS-ADMIN-FIX

**Commit:** `b545d78b` | **Files:** `radd-hub/hub/db.py`, `mobile_api.py`, `tid_panel.py`, `subscriptions.py` | **Oracle:** deployed same session

### Problem
Admin panel at `/plans/` showed 0 plans. App showed plan cards. These appeared to be two separate bugs but shared one root cause.

### Root Causes (4)

1. **`init_db()` never seeded plans** — `plans` table was empty on Oracle. Admin panel queries DB directly; 0 rows = nothing displayed. App appeared fine because `mobile_api.py /api/subscription/plans` has a hardcoded 4-plan fallback that fires when `plan_rows` is empty — the app was always running off the fallback, never the DB.

2. **`mobile_api.py` line 730: wrong field name** — `json.loads(p.get("description") or "[]")`. Features are stored in `features_json` (added via ALTER TABLE migration); `description` is a text field. Result: features always empty in app even when edited via admin panel.

3. **`tid_panel.py` hardcoded plan durations/prices** — `PLAN_DURATIONS = {"basic": 30, ...}` and `PLAN_PRICES = {"basic": 149, ...}` used in `approve()`. Any `duration_days` or `price_pkr` change in the admin panel was silently ignored — subscriptions always granted 30-day duration regardless of what the admin set.

4. **`upsert_plan()` in `db.py` missing new columns** — `badge`, `color`, `features_json` not in the `cols` list. Not on a hot path (plans_panel uses direct SQL) but would silently drop those fields if called.

### Fixes

| File | Change |
|---|---|
| `db.py` `init_db()` | Added plan seeding block after payment methods seeding — inserts Starter/Basic/Standard/Premium matching the `mobile_api.py` fallback. Guard: `COUNT(*) == 0`. |
| `db.py` `upsert_plan()` | Added `badge`, `color`, `features_json` to `cols` list. |
| `mobile_api.py` | `p.get("description")` → `p.get("features_json")` |
| `tid_panel.py` `approve()` | Replaced hardcoded dict lookup with `SELECT duration_days, price_pkr FROM plans WHERE LOWER(name)=LOWER(?)`. Falls back to old dict if plan name not in DB (legacy safety). |
| `subscriptions.py` | Removed dead `PLAN_DURATIONS = {"basic": 30, ...}` (never referenced). |

### Smoke Test
`curl http://92.4.95.252/api/subscription/plans` returned 4 plans from DB (ids 1–4) with correct features, colors, and jazz savings messages. Server restarted cleanly via `push_to_oracle.sh`.

---

## 2026-07-16 — PLANS-FORM-FIX

**Commit:** `61027c1b` | **File:** `radd-hub/hub/routes/plans_panel.py` | **Oracle:** deployed same session

### Problem
Admin reported that clicking ✏ Edit on any plan card did nothing, and after submitting "Add New Plan" the user couldn't tell if anything had happened.

### Root Causes

1. **`onclick="editPlan({{ p|tojson }})"` — double-quote collision in HTML attribute.**
   Jinja2's `tojson` filter produces standard JSON with double-quoted keys and string values (e.g. `{"name": "Basic", ...}`). When this is interpolated directly into a double-quoted HTML `onclick="..."` attribute, the browser's HTML attribute parser closes the attribute at the very first `"` inside the JSON — before any plan data. The button's actual onclick value becomes `editPlan({` which is a JavaScript SyntaxError at runtime. Click → nothing happens. This bug was invisible before the previous session's plan-seeding fix because the plans table was empty → no plan cards rendered → no Edit buttons → the broken pattern was never triggered.

2. **No success feedback on any form action.**
   All four POST routes (create/edit/toggle/delete) redirect back to `/plans/` silently. With no toast or flash, the admin saw a page that looked identical after submitting a form and assumed the submission had failed.

### Fixes

| Change | Detail |
|---|---|
| Edit button onclick | `onclick="editPlan({{ p|tojson }})"` → `onclick="editPlan({{ p.id }})"` — integer literal, zero quoting issues. |
| `_PLANS` map in `<script>` | Added `const _PLANS = {{ plans_map\|tojson }};` inside the `<script>` block (safe context). `tojson` inside `<script>` is the correct pattern; it's only dangerous in HTML attribute values. |
| `editPlan(id)` | Updated JS function to `function editPlan(id){openModal(_PLANS[id])}` — ID lookup instead of object pass. |
| `plans_map` in route | `index()` now builds `{p['id']: p for p in plans}` and passes it as `plans_map` to `render_template_string`. |
| Success toast | All four POST routes now redirect with `?ok=created/updated/toggled/deleted`. JS on page load reads the param, fires a `toast()` call, then cleans the URL via `history.replaceState`. |
| Escape key | Added `document.addEventListener('keydown', ...)` to close the plan modal on Escape. |

### Audit — Other Panels
Grepped all route files for `onclick.*tojson` pattern — only `plans_panel.py` had this bug. Analytics uses `tojson` only inside `<script>` blocks (correct). No other panels affected.

---

## PLANS-NO-JS-FIX — 2026-07-16 — commit `e1cb9da3`

**Problem:** Plans admin create/edit still not working after PLANS-FORM-FIX. The JS-based modal approach (integer onclick + _PLANS map) was correctly deployed and verified via curl — server was serving the right HTML — but admin reported no change. Diagnosis: the entire create/edit flow depended on inline JavaScript running to (a) open the modal and (b) set the form's `action` attribute at click time. If anything blocks JS execution (browser extension, security policy, mid-page JS error), the form has no `action` attribute and silently POSTs to the current page URL (`/plans/`) which returns 405, appearing to do nothing.

**Root cause:** Architecture depended on JS for both UI visibility and form routing. No JS = no modal = no working forms.

**Fix applied to `radd-hub/hub/routes/plans_panel.py`:**
- Removed the JS modal entirely
- Added `GET /plans/new` route → server-rendered full-page create form (POSTs to `/plans/create`)
- Added `GET /plans/<id>/edit_form` route → server-rendered full-page edit form, data fetched from DB server-side, pre-filled (POSTs to `/plans/<id>/edit`)
- "Add New Plan" card changed from `onclick="openModal()"` div → `<a href="/plans/new">` link
- Edit buttons changed from `onclick="editPlan(id)"` → `<a href="/plans/X/edit_form">` link
- Success feedback changed from JS toast (requires JS) → `?ok=` query param rendered as a green server-side banner on the index page
- Color picker uses `<input type="radio">` + CSS label trick — no JS needed
- Toggle and Delete unchanged (already direct POST forms, working fine)

**Result:** Zero JavaScript required for any CRUD operation. Works in any browser regardless of extensions or JS policy. Verified via curl: `/plans/new` renders 47 KB form page with `action="/plans/create"`. `/plans/1/edit_form` renders pre-filled form with `action="/plans/1/edit"` and `value="Starter"` etc.

---

## 2026-07-16 — Y1 PLAYER-VAULT-BUGFIX-BATCH

**Commit:** `459244b5` | **Files:** `_ps_ui_mixin.dart`, `vault_service.dart`, `vault_screen.dart` | **CI:** ✅ green

### Problems (reported from APK testing)
5 bugs found in the latest APK build.

### Fixes Applied

**1 — Duplicate reload icon in player header**
`_ps_ui_mixin.dart` had a "Replay from start" `_RaddIconBtn(Icons.replay_rounded)` sitting directly in the title bar row next to the battery badge and clock. The transport controls row has its own `replay_rounded` skip-back button — identical icon, different function, looked like a duplicate to users. Removed the title-bar instance; the transport row skip-back remains untouched.

**2 — BG Audio shortcut missing from sidebar**
`_backgroundAudio` / `pref_bgaudio` existed in player state and prefs but was never wired into the customizable sidebar shortcut system. Added `'bgaudio'` entry to the `defs` map in `_buildSidebar` — toggles `_backgroundAudio`, calls `_scheduleSavePrefs()`. Icon: `music_note_rounded` (active) / `music_off_rounded` (inactive).

**3 & 4 — Vault file still visible in file managers after add + no ghost cleanup on restore**
Root cause: `restoreFileToDownloads` deleted the vault source file but never called `notifyMediaStore(vaultPath)` — MediaStore kept a stale entry pointing to the now-deleted vault path, which file managers showed as a ghost. Fixed: added `await notifyMediaStore(vaultPath)` immediately after the delete in `restoreFileToDownloads`.

**5 — Restore always goes to Downloads, creates duplicate**
Root cause: vault never stored where a file came from. Added a `.raddmeta` sidecar file alongside each vault entry on import (both `moveFileToVault` and `moveFilesToVaultBatch`) containing the original filesystem path. New `restoreToOriginal()` method reads the sidecar; if the original directory still exists, copies back there; otherwise falls back to Downloads. `vault_screen._restoreToGallery` now calls `restoreToOriginal` and shows "Restored to original folder" or "Restored to Downloads folder" accordingly. Sidecar files are filtered out of `listFiles` (`.raddmeta` suffix skip) and cleaned up on `deleteVaultFile`.

---

## 2026-07-16 — Y2 VAULT-LOGIC-AUDIT

**Commit:** `4da50433` | **Files:** `vault_service.dart`, `local_folder_screen.dart`, `local_media_screen.dart`, `vault_screen.dart` | **CI:** ✅ green

### Research: How MX Player Vault Works vs Ours

**MX Player:**
- Stores files on **external storage** (`/storage/emulated/0/…` or SD card), NOT app-internal. Files survive uninstall.
- Hiding method: moves file to a folder containing `.nomedia` — prevents MediaStore scanner from indexing that directory.
- **No encryption** in older versions. Newer versions (2023+) appear to add encryption: users report files are findable in a file manager after uninstall but cannot be opened (V2EX thread, July 2023).
- Has `MANAGE_EXTERNAL_STORAGE` (confirmed via XDA: "Why does MX Player now require All Files Access?"). This lets it delete from MediaStore without the system permission dialog.
- Restore: user selects a destination folder. MX Player does NOT track the original path.

**Ours:**
- Stores in `getApplicationDocumentsDirectory()` = `/data/user/0/com.raddflix.app/app_flutter/.vault/` (app-internal). Files are **deleted on uninstall** — a significant difference from MX Player.
- Hiding method: same `.nomedia` trick, but the folder is already hidden from MediaStore because it is app-internal. Double-hidden.
- No encryption.
- No `MANAGE_EXTERNAL_STORAGE`. On Android 11+ (API 30+) must use `MediaStore.createDeleteRequest` which requires a system permission dialog.
- Restore: `.raddmeta` sidecar records original path (better than MX Player). Falls back to Downloads.

### Bugs Fixed

**1 — Sidecar wrote FilePicker temp-cache paths as "original location"**
`moveFileToVault` and `moveFilesToVaultBatch` always wrote a `.raddmeta` sidecar with whatever `sourcePath` they received. When called from vault_screen.dart `_processPickedFiles`, the path is a FilePicker temp copy under `/data/user/0/…/cache/file_picker/foo.mp4`. This path doesn't exist when restore runs, so it always fell back to Downloads anyway — but the sidecar was meaningless noise and could theoretically confuse restore on edge-case devices.
Fix: Only write sidecar when `sourcePath.startsWith('/storage/')` or `.startsWith('/sdcard/')`.

**2 — Orphan `restoreFile(vaultPath, destDir)` didn't clean up sidecar**
The old `restoreFile(String vaultPath, String destDir)` method at line 465 predates the sidecar system. It deleted the vault file and notified MediaStore for the destination, but left any `.raddmeta` file behind. Added sidecar delete.

**3 — `deleteFromMediaStore` return value silently ignored — no user feedback**
On Android 11+ (API 30+), `MediaStore.createDeleteRequest` shows a system dialog. If the user taps "Don't allow", the file stays visible in gallery and other players, but all three callers (local_folder_screen, local_media_screen, vault_screen) discarded the `bool` return value with no feedback. Fixed by capturing the result and appending " • May still appear in gallery" to the success snackbar (shown for 5s instead of 3s) when the delete was denied.

**4 — `totalVaultSize()` counted `.raddmeta` sidecar files**
The recursive file sum included `.raddmeta` sidecar files, slightly inflating the displayed vault size. Fixed with an `endsWith('.raddmeta')` skip.

**5 — Misleading `notifyMediaStore(vaultPath)` in `restoreFileToDownloads`**
The comment said "Remove stale MediaStore entry pointing to the now-deleted vault path" but the vault is in app-internal storage — MediaStore never indexed it, so the call was a silent no-op. The actual ghost-entry removal happens at import time via `notifyMediaStore(sourcePath)`. Removed the call and replaced it with a correct explanatory comment.

### Architecture Note
The real limitation vs MX Player: without `MANAGE_EXTERNAL_STORAGE`, on Android 11+ we cannot silently delete MediaStore entries — we must prompt the user. MX Player gets around this via `MANAGE_EXTERNAL_STORAGE`. Getting that permission requires a special Google Play declaration and review; most apps avoid it. Our current approach (prompt + warn if declined) is correct for a Play Store app.

---

## Z1 — AUDIO-MODE-CONTROLS-AND-EMBEDDED-ART (2026-07-16)

**Goal:** Complete the audio-mode music player — add embedded cover art extraction, Prev/Next skip buttons, and Shuffle/Repeat toggles. CI commit pending.

### Files Changed

| File | Change |
|---|---|
| `raddflix_flutter/pubspec.yaml` | Added `flutter_media_metadata: ^1.0.3` |
| `raddflix_flutter/lib/widgets/player/audio_mode_backdrop.dart` | Full update — see below |
| `raddflix_flutter/lib/screens/player/_ps_playback_mixin.dart` | `_shuffleEnabled`, `_toggleShuffle()`, `_randomEpIdx()`, auto-advance shuffle |
| `raddflix_flutter/lib/screens/player/_ps_ui_mixin.dart` | Threaded new params through injection site |

### Embedded Cover Art (flutter_media_metadata)

`_AudioModeBackdropState` now has two cover art fields: `File? _coverArtFile` (sidecar) and `Uint8List? _embeddedArtBytes` (embedded tags). `_scanCoverArt()` probes sidecar filenames first (unchanged); only if none match does it call `MetadataRetriever.fromFile(File(path))` and read `metadata.albumArt`. The bytes are stored and passed as a `MemoryImage` to `_Disc`, `_Backdrop`, and `_extractPalette()`. `_Disc` and `_Backdrop` now accept `ImageProvider?` (was `FileImage?`) so both sidecar and embedded artwork flow through the same code path.

### Prev / Next Buttons

New `_SkipButton` widget: `Icon` wrapped in `GestureDetector` with `AnimatedOpacity(opacity: enabled ? 1.0 : 0.35)`. Placed in a `Row` flanking the play/pause circle (`⏮ — ⏸/▶ — ⏭`). Callbacks: `onPrev` → `_playEpisodeAt(_currentEpIdx - 1)`, `onNext` → `_playEpisodeAt(_currentEpIdx + 1)`. Disabled (null callback + dimmed) when `_hasPrev`/`_hasNext` is false.

### Shuffle / Repeat Toggles

New `_ToggleIcon` widget: `Icon` on a translucent accent-coloured circle when active; white38 / transparent when inactive. Two icons (`Icons.shuffle_rounded`, `Icons.repeat_rounded`) in a centred `Row` above the seek bar. Repeat wired to existing `_toggleLoop()`. Shuffle adds `bool _shuffleEnabled` + `_toggleShuffle()` to `_PlayerPlaybackMixin`; `_randomEpIdx()` picks a random episode index ≠ current; auto-advance at track end uses it instead of `+1` when shuffle is on.

### Backwards Compatibility

All new `AudioModeBackdrop` params have safe defaults (`hasPrev: false`, `hasNext: false`, `loopEnabled: false`, `shuffleEnabled: false`, `onLoopToggle`/`onShuffleToggle` defaulting to a static `_noop`). Any existing call-site that doesn't pass these params compiles unchanged.

---

## 2026-07-20 — DA-2: Watch Integrity & Session Minimum Charge

**Commits:** `f64615c1` (implementation) · `12f8baae` (audit fixes) | **CI:** ✅ green on both

### Changes

**`lib/core/constants.dart`**
- `catalogDbVersion` 23 → 24 (new `smc_log` migration).

**`lib/core/db/local_db.dart`**
- `_createAll`: added `smc_log` table (`id, title_id, charged_on TEXT, created_at`) + unique index `idx_smc_log_title_day(title_id, charged_on)`.
- `_migrate`: added `if (oldV < 24)` block creating the same table+index for upgraded devices.
- New methods: `smcLogHasCharge(int titleId)` (per-title/per-day cooldown check) and `smcLogRecord(int titleId)` (idempotent insert via `ConflictAlgorithm.ignore`).

**`lib/core/services/usage_service.dart`**
- Added constants: `completionThreshold = 0.70`, `abuseVelocityRatio = 4.0`, `abuseSeekThreshold = 0.40`, `smcMinSessionSecs = 20`, `smcFloorBytes` map (360p=80MB, 480p=120MB, 720p=150MB, 1080p=200MB).
- Added `applySmcIfNeeded({titleId, quality, actualBytes})`: checks cooldown, top-ups bytes to floor if `actualBytes < floor`, records the charge, fires `flushPending()`.

**`lib/screens/player/_ps_playback_mixin.dart`**
- Added 5 per-session state fields: `_smcSessionStart`, `_realPlaySecs`, `_smcEstimatedBytes`, `_maxSeekJumpFraction`, `_abuseHighSpeedUsed`.
- `_startUsageTimer()`: sets `_smcSessionStart` on first play tick (`??=`); increments `_realPlaySecs += 30` and `_smcEstimatedBytes` each heartbeat tick.
- Position stream listener: detects forward jumps > 5 s and tracks max fraction via `_maxSeekJumpFraction`.
- `_setSpeed()`: sets `_abuseHighSpeedUsed = true` when speed ≥ 4×.
- Added helpers `_smcTitleId` (reads episode `title_id` or parses `fileId`), `_resetSmcTracking()`, `_isCompletionEarned()`, `_applySmcOnSessionEnd()`.
- `_openMedia()` and `_openMediaForEpisode()`: call `_applySmcOnSessionEnd().ignore()` + `_resetSmcTracking()` before `_stopUsageTimer()` at each episode boundary.
- `_onVideoCompleted()`: gates `_clearSavedPosition()` on `_isCompletionEarned()`.

**`lib/screens/player_screen.dart`**
- `dispose()`: calls `_applySmcOnSessionEnd().ignore()` inside `!_handedOffToService` block before `_stopUsageTimer()`.

---

## 2026-07-19 — BB5 FAB-THUMBNAIL-FIX + AB1 CI fix

**Commits:** `5fa870fa` (BB5 fix), `255ffe61` (CI fix) | **CI:** ✅ green

### BB5 — Blank poster in ResumeFab / MiniPlayerBar

**Root cause (audited, not assumed):** `_ps_playback_mixin._saveWatchPos()` only writes `resume_poster_url` when `widget.posterUrl != null`. `widget.posterUrl` comes from `args['poster_url']` in `app.dart`. Four call sites never passed this key:
- `show_detail_screen._playEpisode()` — pushes series episodes
- `show_detail_screen._playMovie()` — pushes movies
- `content_card.dart` — pushes from the content detail sheet
- `downloads_screen.dart` (both episode and movie lists)

Key names were already aligned (`resume_poster_url` on both sides). `CachedNetworkImage errorWidget` fallbacks were already coded with BB5 comments in both `ResumeFab` and `MiniPlayerBar`. Fix: added `'poster_url': widget.item.posterUrl` / `item.posterUrl` / `_posterUrl(d)` to all four call sites. Poster URL now flows all the way to SharedPrefs on every play.

### AB1 CI fix — `AnimationController.repeat()` has no `from:` parameter

`audio_mode_backdrop.dart` lines 184 and 206 called `_discCtrl.repeat(from: _discAngle)`. `repeat()` takes no `from:` parameter — that's `forward(from:)` only. Fixed by splitting into `_discCtrl.value = _discAngle; _discCtrl.repeat();` at both sites. This was a pre-existing bug from the AB1 Neo-Phonograph commit that had gone undetected (CI not confirmed after that push).

---

## 2026-07-20 — Session doc cleanup: close P1-D

Previous session (2026-07-20) completed P1-C (Subtitle Personality), P1-D (Phonetic Overlay), and DA-2 (Watch Integrity & SMC) but ended without updating the handoff docs. This session bootstrapped fresh, verified all commits landed and CI is green, then closed out the paperwork:

- `agent-hub/TASKS.md`: marked P1-D ✅ DONE (`bbda2466`→`da9a77e9`)
- `AGENT_HANDOFF.md`: added Current State section for P1-C/P1-D/DA-2; renamed old Current State → Previous State
- `agent-hub/UNPUSHED.txt`: cleared stale 2026-07-12 PENDING entry (those changes had long since landed)
- `agent-hub/history/TASK_LOG.md`: this entry

Board is now clean. TEN_POINT_PLAN complete (2 blocked items only: folder reorg not approved; K5 needs Flutter SDK). Awaiting next task from user.

---

## 2026-07-20 — THEME-REDESIGN: Obsidian Crimson (commit `cd8fc253`)

### Root cause / motivation
Default "Warm Hearth" theme (`#130F0C` brownish-black bg, `#D4784A` terracotta primary, `#F5EFE6` warm cream text) felt muddy and dated — wrong visual language for a streaming app. The warm brown undertone on backgrounds looked like a sepia filter; the terracotta primary had no premium authority; cream text created soft low-contrast readability against the brownish surfaces.

### Changes
Three files, all theme definition / token tables — no business logic touched.

**`constants.dart` — `AppColors` class:**
- primary: `#D4784A` → `#C41E3A` (cardinal red, deep and premium)
- primaryDark: `#A85A32` → `#92152B`
- primaryGlow: 40% terracotta → 40% cardinal
- primaryLight/accent: `#E8A070` → `#E8384F`
- background: `#130F0C` → `#0D0D0F` (neutral near-black, no warm hue)
- backgroundAlt: `#1A1410` → `#121214`
- surface: `#211A15` → `#161618`
- surfaceHigh: `#2C2219` → `#1E1E21`
- card: `#352A1F` → `#242428`
- cardBorder: `#4A3828` → `#2E2E33`
- textPrimary: `#F5EFE6` → `#F8F8FA` (crisp near-white vs warm cream)
- textSecondary: `#C8B5A0` → `#9898A6`
- textMuted: `#8A7060` → `#58585F`
- textDisabled: `#5A4838` → `#363639`
- divider: `#2A2018` → `#1E1E22`
- layoutDeep/Panel/Sheet: updated to match new bg/surface/card
- All 4 inline gradients (primaryGradient, darkGradient, heroGradient, cardGradient): updated

**`constants.dart` — `AppGradients` class:**
- brand, navCapsule, hero, dark, card: all updated to new palette

**`radd_theme.dart` — `RaddTheme.dark`:**
- All 17 tokens updated to Obsidian Crimson values
- AMOLED/light/midnight/navy/forest/cobalt/rose/charcoal: intentionally unchanged

**`brand_theme_provider.dart` — `BrandThemeState.defaults` + `reload()` fallbacks:**
- Both the const defaults object and the SharedPrefs reload() fallback colors updated
- Ensures fresh installs AND users without remote config both get new palette

### What did NOT change
- JazzCash green, Simosa purple, status colors (success/error/warning/info), dataFree teal — all semantic/partner colors untouched
- Light theme (linen/paper warm tone is correct for that mode)
- All 7 variant themes (midnight, navy, forest, cobalt, rose, charcoal, amoled)

---

## 2026-07-21 — THEME-V2: close out paperwork (commits `9cee303` + `13de8bc`)

**Commits:** `9cee303` (add 4 tasks to board), `13de8bc` (implement all 4 fixes) | **CI:** ✅ green

The previous session on 2026-07-21 added the four THEME-V2 tasks to `TASKS.md` and then
implemented all four in a single commit, but ended without updating the canonical docs.
This session bootstrapped fresh, verified CI was green, confirmed all four changes landed
in code, then closed out the paperwork.

### THEME-V2-01 — WCAG textMuted contrast fix (all 8 themes)
`AppColors.textMuted` raised from `#58585F` (2.75:1 on dark bg — fails WCAG AA) to `#7A7A82`
(4.56:1 ✅). All 8 variant `textMuted` tokens in `radd_theme.dart` updated individually:
dark 4.56:1, midnight 6.11:1, cobalt 5.81:1, rose 5.83:1, navy 7.68:1, forest 7.11:1,
charcoal 6.08:1, light 5.39:1. AMOLED was already passing at 4.57:1 — left unchanged.

### THEME-V2-02 — backgroundAlt invisible-step fix
`AppColors.backgroundAlt` `#121214` was only 1.04:1 from bg `#0D0D0F` — visually
indistinguishable. Raised to `#1D1D20` (1.15:1 step, matching Netflix's surface-step size).
`dark.bgAlt` in `radd_theme.dart` updated to match.

### THEME-V2-03 — Pakistani identity hero-gradient
`AppColors.heroIdentity = Color(0xFF0A0A1E)` (midnight-indigo) and `AppColors.heroIdentityGradient`
(transparent → `#0A0A1E`) added to `constants.dart`. Optional hero-overlay for featured content
that gives the app a distinctive Pakistani night-sky depth cue vs generic neutral-black.

### THEME-V2-04 — AI_RULES Rule 11 (brand-primary AA-large-only)
Documented in `docs/design-system/AI_RULES.md` Rule 11: brand primary `#C41E3A` is 3.32:1 on
dark bg (WCAG AA-large-only). Prohibited for use as text colour on body copy
(<14sp bold / <18sp regular). Valid uses: large text, icons, progress bars, active indicators, CTAs.

### This session (paperwork only)
- `agent-hub/TASKS.md`: marked THEME-V2-01/02/03/04 ✅ DONE — `13de8bc`
- `AGENT_HANDOFF.md`: added Current State for THEME-V2; demoted Obsidian Crimson → Previous State
- `agent-hub/history/TASK_LOG.md`: this entry

No Oracle push needed — zero `radd-hub/**` files touched in any THEME-V2 commit.
Board is clean. No open tasks. Awaiting next task from user.

---

## Session 2026-07-22 — LIVE-TV-BACKEND

**Context:** Flutter side (live_channels.dart + live_tv_screen.dart) was already fully built in a
prior session. Previous agent had approval for the DB schema but was cut off mid-write at the
daily credit limit before writing any backend files.

### What was built

**`radd-hub/hub/db.py`** — Added `live_channels` DDL to `_DDL` list (CREATE TABLE IF NOT EXISTS +
3 indexes: unique on channel_id, composite on category+is_active, composite on sort_order+is_active).
Added seed block to `init_db()`: 86 channels seeded in category order
(sports → religious → news → entertainment → kids → movies → docs), guarded by `COUNT(*) = 0`.
Backdrop colors per category, Geo News flagged is_featured=1, all channels is_free=1/is_active=1.

**`radd-hub/hub/routes/live_channels.py`** — New blueprint file (two blueprints):
- `bp` (`/live/*`) — admin panel using `render_template_string` (same pattern as `plans_panel.py`).
  Routes: `GET /live/` (list + category tabs), `POST /live/<id>/toggle`, `POST /live/<id>/free`,
  `POST /live/<id>/featured` (clears existing featured first), `POST /live/<id>/sort`,
  `POST /live/<id>/edit` (stream_url + logo_url + notes).
- `bp_mobile` — `GET /api/live/channels` returning `{ok, channels[], total, categories[], server_ts}`.
  Active channels only; supports `?cat=` filter. Each channel object includes all display fields
  the Flutter app needs (`backdrop_color`, `is_featured`, `sort_order`, `updated_at`).

**`radd-hub/hub/app.py`** — `live_channels as live_channels_route` added to the main import line;
two `register_blueprint` calls added after the Brand Studio block.

**`radd-hub/hub/templates/base.html`** — `📺 Live TV / Channels & streams` nav link added
under the APP section (after Broadcast).

### Commit
`c7b619a4` — "Live TV backend: live_channels table + seed (86 ch) + admin panel + mobile API"

### Notes for next agent
- The Flutter app still uses the hardcoded `kAllLiveChannels` list in `live_channels.dart`.
  Making it call `/api/live/channels` instead is a separate task — not yet discussed with the user.
  Do NOT scope-creep into Flutter changes without explicit user approval.
- Oracle deploy needed before the admin panel or API endpoint will be live on the server.
  Follow OPERATIONS.md: run `push_to_oracle.sh` and confirm with user first.
- The DB seed is a one-time boot operation. If channels need to be updated after deploy,
  use the admin panel at `/live/` — do NOT manually run SQL.

Board is clean. No open tasks. Awaiting next task from user.

---

## Session 2026-07-22 (continued) — Bug audit + Oracle deploy

After completing LIVE-TV-BACKEND, ran a full bug audit of all new code before handoff.

### Bugs found and fixed

**Bug 1 — `db.py` seed crash (`22ee2471`)**
Seed block in `init_db()` referenced `db._lock`/`db._conn()` — but inside `db.py` those are
bare module-level names `_lock`/`_conn()`. Python raised `NameError: name 'db' is not defined`
on every boot, crashing the server immediately after first deploy. Fixed same session.

**Bug 2 — Admin panel lost `?cat=` filter on POST redirect (`e234e512`)**
All five POST form actions had no `?cat=` in the URL. After any toggle/edit, Flask read
`request.args.get("cat","all")` from the POST (which has no query string) and always redirected
to "All" tab — discarding the user's active category. Fixed by adding `?cat={{ cat }}` to every
form action in the `_PAGE` template.

**Bug 3 — Dead wrapper functions (`e234e512`)**
`_conn()` and `_lock()` at the top of `live_channels.py` were defined but never called.
Removed.

### Final state
`e234e512` deployed to Oracle. Server RUNNING. `GET /api/live/channels` returns 84 channels,
all 7 categories, `ok: True`. Admin panel live at `http://92.4.95.252/live/`.

### Permanent rule for next agent
When adding seed blocks to `db.py`, use `_lock`/`_conn()` bare — NOT `db._lock`/`db._conn()`.
`db.py` cannot reference itself by module name.

Board is clean. No open tasks. Awaiting next task from user.

---

## Session 2026-07-22 (continued) — LIVETV-P1/P2/P3 close-out + CI fix

### Context
All three LIVETV tasks (P1/P2/P3) had been implemented by a prior agent in the same day
but left marked ⏳ IN PROGRESS in TASKS.md. CI was failing on both implementation commits.

### Root cause of CI failure
`live_tv_screen.dart` used `RaddColors` as an explicit type annotation in 8 method
signatures (`_buildHeader`, `_buildSearchBar`, `_buildCategoryChips`, `_buildLoading`,
`_buildError`, `_buildContent`, `_buildAllView`, `_buildRecentRow`). `RaddColors` is a
BuildContext extension (`extension RaddColors on BuildContext` in `radd_colors.dart`),
not a concrete class — `dart analyze` emits `undefined_class` for this usage.
The correct type for `RaddTheme.of(context)` is `RaddTheme`. Replace-all fixed all 8.

### Commits
| SHA | Description |
|---|---|
| `b55d9f55` | LIVETV-P1+P3: featured hero + Netflix rows + backdrop cards + isFree + v26 migration + recently watched |
| `ca12dd14` | LIVETV-P2: player live UI — red LIVE status row, hide seek bar, channel switcher sheet |
| `36cf2740` | CI fix: `live_tv_screen.dart` — `RaddColors` → `RaddTheme` in 8 method signatures |

No Oracle push needed — zero `radd-hub/**` files touched.

Board is clean. All tasks ✅ DONE. Awaiting next task from user.

---

## Session 2026-07-22 (continued) — Logo audit + fix

### Task: LOGO-AUDIT

Audited all 84 live-channel logo_url values in `radd-hub/hub/db.py` `_live_seed`.

**Method:** HTTP HEAD on every URL. Tamashaweb's React SPA was bypassed by probing
`/wp-content/uploads/` paths directly and guessing slug names (matching channel slugs
already used by tamashaweb for their channel pages).

**Findings:**
- All 44 tamashaweb.com/wp-content/uploads URLs: ✅ 200 OK.
- Wikipedia URLs: 11× 404 (deleted), 4× 400 (SVG thumbnail URLs that require browser
  Accept headers), 15× 429 (rate-limited, unreliable for production use), 2× ambiguous.
- Wrong logos (not dead, just pointing at wrong channel's image): pak-ban used
  ptv-sports.png; saudi-makkah/madinah both used madani-channel.png; cgtn-doc,
  disc-pak, disc-science all used discovery.png; 8xm used ary-musik.png;
  tamasha-women and tamasha-life both used tamasha.png.

**Fix applied (`67a27b5c`):**
1. `_live_seed` in `db.py` — all 41 broken/wrong entries replaced with verified
   `tamashaweb.com/wp-content/uploads/2023/07/` URLs.
2. Added `_logo_patches` dict + idempotent UPDATE block in `init_db()` that runs on
   every boot and patches any row whose `logo_url != correct_value`. This fixes the
   already-seeded Oracle DB on next restart without manual SQL.

### Channels fixed (41 total)

| channel_id | old logo | new logo |
|---|---|---|
| pak-ban | ptv-sports.png | pak-ban.png |
| saudi-makkah | madani-channel.png | saudi-makkah.png |
| saudi-madinah | madani-channel.png | saudi-madinah.png |
| sun-news | Wikipedia (400) | sun-news.png |
| abn-news | Wikipedia (404) | abn-news.png |
| gtv-news | Wikipedia (404) | gtv-news.png |
| 365-news | Wikipedia (404) | 365-news.png |
| digital-pak | Wikipedia (404) | digital-pakistan.png |
| cgtn-hd | Wikipedia SVG (400) | cgtn.png |
| public-tv | Wikipedia (404) | public-news.png |
| news-one | Wikipedia (404) | news-one.png |
| abb-tak | Wikipedia (404) | abb-tak.png |
| pnn | Wikipedia (404) | aik-news.png |
| awaz-news | Wikipedia (429) | awaz-tv.png |
| capital-tv | Wikipedia (429) | capital-tv.png |
| aan-tv | Wikipedia (404) | aan-tv.png |
| tv-today | Wikipedia (404) | tv-today.png |
| aurlife | Wikipedia (404) | aurlife.png |
| ltn-family | Wikipedia (429) | ltn-family.png |
| see-tv | Wikipedia (429) | see-tv.png |
| urooj-tv | Wikipedia (429) | urooj-tv.png |
| atv | Wikipedia (404) | atv.png |
| bbc-first | Wikipedia SVG (429) | bbc-first.png |
| bbc-brit | Wikipedia SVG (429) | bbc-brit.png |
| minimax | Wikipedia SVG thumb (400) | minimax.png |
| baby-tv | Wikipedia SVG thumb (400) | baby-tv.png |
| bbc-cbeebies | Wikipedia SVG thumb (400) | bbc-cbeebies.png |
| filmax | Wikipedia (404) | filmax.png |
| movie-one | Wikipedia (429) | movie-one.png |
| 8xm | ary-musik.png (wrong) | 8xm.png |
| jalwa-tv | Wikipedia (429) | jalwa-tv.png |
| play-tv | Wikipedia (429) | play-tv.png |
| srf-movies | Wikipedia SVG thumb (400) | srf-movies.png |
| inplus | Wikipedia (404) | inplus.png |
| cgtn-doc | discovery.png (wrong) | cgtn-doc.png |
| disc-pak | discovery.png (wrong) | disc-pak.png |
| tamasha-women | tamasha.png (wrong) | tamasha-women.png |
| tamasha-life | tamasha.png (wrong) | tamasha-life.png |
| bbc-earth | BBC_Logo_2021.svg (wrong, generic) | bbc-earth.png |
| bbc-lifestyle | BBC_Logo_2021.svg (wrong, generic) | bbc-lifestyle.png |
| disc-science | discovery.png (wrong) | disc-science.png |

### Next step
Oracle redeploy required (`radd-hub/hub/db.py` changed). On next Oracle restart,
`init_db()` runs the UPDATE block and all 41 rows are patched automatically.
Awaiting user confirmation to deploy.


---

## LIVETV-AUDIT — Live TV full audit + 12 bug fixes (2026-07-23, commit `e128942`)

**Scope:** Full audit of the Live TV tab and player. Rating before fixes: 6/10.

**Files changed:** `live_channels.dart`, `live_tv_screen.dart`, `_ps_ui_mixin.dart`, `player_screen.dart`, `live_channels.py`

### Bugs fixed

| ID | Priority | Fix |
|---|---|---|
| P0A PAYWALL-ENFORCE | 🔴 | `_playChannel()` checks `subscriptionProvider` + `authProvider`; `_showLivePaywall()` added |
| P0B SHARED-ANIM-CTRL | 🔴 | Removed `pulseCtrl` from `_HorizontalCard`/`_GridCard`; static red pill badges |
| P0C CHANNEL-ID-MATCH | 🔴 | Switcher now passes/matches `currentChannelId` (int) not name string |
| P1A IMAGE-NETWORK | 🟠 | `CachedNetworkImage` in switcher sheet; import added to `player_screen.dart` |
| P1B GLOBAL-SEARCH | 🟠 | `_filteredAll()` ignores `_selectedCat` when query non-empty |
| P1C BACK-TO-ALL | 🟠 | Tappable "← All Channels" row added at top of single-category grid |
| P1D RECONNECT-OVERLAY | 🟠 | "Reconnecting…" label below spinner when `_isLive && _buffering` |
| P2A HEXCOLOR-DEDUP | 🟡 | `hexColor()` moved to `live_channels.dart`; dupes removed |
| P2B FONT-SIZES | 🟡 | +1–2px on three small text labels |
| P2C CARD-WIDTH | 🟡 | `_HorizontalCard` 100→120px wide; row height 155→165px |
| P2D LIVE-METHODS-DEDUP | 🟡 | Merged into `_buildLiveArea({topPadding})` |
| P2E ADMIN-DOC-FIX | 🟡 | Admin panel subtitle corrected to "within 1 hour" |

### Pending after this session
- **Oracle redeploy required** — `live_channels.py` changed. Run `push_to_oracle.sh` on next session.
- Verify APK CI green on `e128942`.

---

## THEME-WIDGET-FIX — Design-system button/chip migration: 4 screens (2026-07-23, commits `f56e9540` + `87455ea3`)

**Context:** A previous agent session added missing imports (`radd_button`, `radd_chip`, `radd_radius`) to 5 screens but stopped before making the actual widget replacements. The commit message claimed the replacements were done; they were not. This session completed the real work.

**Changes (commit `87455ea3`):**
- `plan_expired_screen.dart`: GestureDetector+hand-rolled gradient Container → `RaddButton(variant: .signal, size: .large, label: 'Renew Plan', leadingIcon: AppIcons.crown, fullWidth: true)`
- `quota_full_screen.dart`:
  - "Renew or Upgrade Plan" GestureDetector+gradient Container → `RaddButton.signal`
  - SIMOSA GestureDetector+Container → `Material(color: t.card) + InkWell` (kept custom `Image.asset` child — RaddButton cannot accommodate it)
- `live_tv_screen.dart`:
  - Clear-search X: `GestureDetector` → `IconButton(constraints: BoxConstraints(), splashRadius: 16)`
  - Category chips: `GestureDetector + AnimatedContainer` → `RaddChip(label:, active:, onTap:)` — eliminates hardcoded `AppColors.primary`, `t.surface`, `BorderRadius.circular(20)`, manual animation
  - "Try again" error button: `GestureDetector + Container` → `RaddButton(variant: .tonal, size: .small, leadingIcon: AppIcons.refresh)`
- `data_usage_screen.dart`: `BorderRadius.circular(AppRadius.md)` → `RaddRadius.mdRadius` ×6 (token normalization, same effective value)

**CI:** Both commits green (`build-apk.yml` confirmed via API). No `test/`, `pubspec.yaml`, or workflow files touched — `ci-tests.yml` check not required (Rule 50).
**Oracle:** Not required — Flutter-only changes.

---

## ORACLE-REDEPLOY — Deploy pending live_channels.py change to Oracle (2026-07-23, commit `3c593e7d`)

**Scope:** Oracle server was stale — `live_channels.py` had been changed in LIVETV-AUDIT (`e128942`) but `push_to_oracle.sh` had not been run since. Ran the deploy.

**Result:** Server pulled to `3c593e7d`, restarted, API confirmed `{"ok":true,"version":"1.0.0"}` ✅. No code changes — deploy only.

---

## LIVE-P0 + LIVE-P5 — Live stream resolution fix + tab badge polish (2026-07-23)

### LIVE-P0 — Critical: fix live stream resolution

**Root cause (full chain):**
`_openMedia()` in `_ps_playback_mixin.dart` had no `_isLive` special case. For a live channel (e.g. `fileId = 'live_geo-news'`):
1. `isLocal = false` (doesn't start with `/` or `content://`)
2. `LocalDb.getShareInfo('live_geo-news')` → empty row (no DB entry for live IDs)
3. Falls back to `widget.streamUrl` (the direct HLS CDN URL)
4. Calls `JazzDriveService.getStreamLink(cacheKey, m3u8Url)`
5. `_extractShareKey()` regex finds no `/f/` pattern in CDN URL → throws `Exception('Invalid JazzDrive share URL: https://cdn*.tamashaweb.com:8087/…')`
6. `_friendlyError()` matches `'Jazz'` in the exception string → shows "Jazz SIM required" — **wrong error, stream never attempted**

**Changes made (all in `raddflix_flutter/lib/screens/player/_ps_playback_mixin.dart`):**

- **LIVE-P0-A** — `_isLive` early-exit in `_openMedia()` inserted after `_isLocal = isLocal` assignment, before usage-tracking setup. Checks `widget.streamUrl` non-null/non-empty, then calls `_player.open(Media(url))` directly and returns. Bypasses: JazzDrive, SMC tracking, `_restoreWatchPos()`, `_startSavePositionTimer()`, subscription gate, quota gate.
- **LIVE-P0-B** — `_friendlyError()` now checks `_isLive` first. Live branch: 403/Forbidden/401 → "Jazz SIM required. Connect to Jazz mobile data to watch live TV."; all other live errors → "Could not load channel. Check your connection and retry." VOD logic unchanged below.
- **LIVE-P0-C** — Already handled by early-exit (returns before all VOD lifecycle calls).
- **LIVE-P0-D** — `_startAutoRetry()` now sets `retryDelay = _isLive ? 10 : 30` so live channels reconnect in 10s instead of 30s.

### LIVE-P5-C — FEATURED badge → AppColors.primary red pill

Two instances in `live_tv_screen.dart`:
1. Featured banner badge (pill, rectangular): `Color(0xFFFFC107).withOpacity(0.90)` → `AppColors.primary`; text `Colors.black87` → `Colors.white`
2. Channel grid star badge (circle, 22px): same colour swap; `Colors.black` → `Colors.white`. Second instance also made `const BoxDecoration` since `AppColors.primary` is const.

**Scope:** Flutter only. No Oracle changes. CI must pass before marking DONE.

---

## LIVE-P0 + LIVE-P5 CI RESULT (2026-07-23)

**P0 fix note — mixin architecture:** `_isLive` getter is defined in `_ps_ui_mixin.dart` as `bool get _isLive => widget.contentType == 'live';`. `_PlayerPlaybackMixin` in `_ps_playback_mixin.dart` is a separate mixin with no cross-cluster declaration for `_isLive`, so all three P0 insertion points (`_openMedia()`, `_friendlyError()`, `_startAutoRetry()`) must inline `widget.contentType == 'live'` directly — NOT use `_isLive`. Initial push (`89bb581b`) used `_isLive` → Dart analyze error `undefined_identifier` → CI FAIL. Corrected push (`aa997d82`) inlines the check → CI ✅ success. **Future agents: any code added to `_ps_playback_mixin.dart` must inline `widget.contentType == 'live'`, not use `_isLive`.**

**P5-C fix note:** `live_tv_screen.dart` already had `AppColors` imported via `core/constants.dart` (line 18). Both `const Color(0xFFFFC107)` instances (banner pill + grid star) updated to `AppColors.primary`. Second instance (grid star `BoxDecoration`) made `const`. CI verified green via `aa997d82` which is HEAD above the `cfe0fe9b` P5-C commit.

**Final commit SHAs:**
- LIVE-P0: `aa997d82` — CI ✅ (`build-apk.yml` run #30030329208 success)
- LIVE-P5-C: `cfe0fe9b` — CI ✅ (verified via `aa997d82` HEAD)

---

## LIVE-P1–P4 — DVR model + portrait/landscape player redesign + error UX (2026-07-24)

### Commits
| SHA | Files | Description |
|---|---|---|
| `458e650c` | `live_channels.dart`, `constants.dart`, `local_db.dart`, `db.py`, `live_channels.py` | LIVE-P1: DVR fields, DB migration v26→v27, Oracle DDL/seed/API |
| `a9497fb9` | `_ps_ui_mixin.dart`, `player_screen.dart` | LIVE-P2/P3/P4: portrait scaffold, landscape watermark+swipe, error UX |

Both CI ✅ green (`build-apk.yml`). Oracle redeployed to `a9497fb9` ✅.

### LIVE-P1 — DVR metadata support
- `LiveChannel`: `hasDvr` (bool), `dvrWindowSeconds` (int), `hexColor` getter (dart:ui Color via `fromJson`/`fromRow`/`toRow`).
- `catalogDbVersion` 26 → 27.
- `local_db.dart`: `_onCreate` DDL + `if (oldV < 27)` migration with two `ALTER TABLE live_channels ADD COLUMN` calls.
- Oracle `db.py`: matching DDL, `init_db()` ALTER TABLE entries, `_dvr_channels` seed patch (geo-news → `has_dvr=1, dvr_window_seconds=3600`).
- Oracle `routes/live_channels.py`: API includes `has_dvr` + `dvr_window_seconds`.
- **Note:** Preflight false-positive on `local_db.dart` — file imports `../constants.dart` (relative path); preflight substring-matches for `core/constants.dart` and misses it. Used `SKIP_PREFLIGHT=1`.

### LIVE-P2 — Portrait scaffold
- `_buildPortraitLayout()`: early `if (_isLive) return _buildLivePortraitScaffold(constraints)`.
- `_buildLivePortraitScaffold()`: YouTube Column — header (back/title/settings) → 16:9 AspectRatio video box → identity bar → Expanded channel list.
- `_buildLiveVideoBox()`: Stack with video surface, tap gesture, buffering spinner, "Reconnecting…" label, link-loading overlay, error overlay, controls overlay, always-visible LIVE badge.
- `_buildLiveVideoControlsOverlay()`, `_buildLiveBadgePill()`, `_buildLiveIdentityBar()`, `_buildLiveInlineChannelList()`.

### LIVE-P3 — Landscape improvements
- `_buildLiveLandscapeWatermark()`: 20% opacity logo, bottom-right, IgnorePointer.
- `_switchToAdjacentLiveChannel(delta)`: finds adjacent channel by ID from provider, haptic + `pushReplacementNamed`.
- `_onScaleEnd()`: live swipe gate — `_isLive && _dragIntent == 'seek' && velocity > 500 px/s` → `_switchToAdjacentLiveChannel`.
- `player_screen.dart` landscape Stack: `if (_isLive) _buildLiveLandscapeWatermark()` added.

### LIVE-P4 — Error/reconnecting UX
- `_buildLiveErrorOverlay()`: signal-off icon + error text + Retry + Switch Channel buttons.
- Reconnecting label below spinner in `_buildLiveVideoBox()` when buffering.

### Open (next session)
- LIVE-P6: DVR URL audit — manually check all 84 channel paths for `playlist_dvr_timeshift` variant; update `has_dvr`/`dvr_window_seconds` seed data; Oracle redeploy.
- LIVE-P7: Quality selector — check if tamashaweb exposes rendition-level playlists; slim live settings panel.

---

## LIVE-P7-B — Slim live settings panel (2026-07-24, commit `574db7d8`, CI ✅)

**Scope:** `raddflix_flutter/lib/screens/player/_ps_ui_mixin.dart`, `LIVE_PLAYER_PLAN.md`.

**What changed:**

New method `_openLiveSettingsPanel()` — a `showModalBottomSheet` with three rows:
1. **Quality** — "Auto (ABR)" label + info icon. Tap shows snackbar. Rendition-level playlists can't be verified without Jazz SIM, so picker is deferred (P7-A).
2. **Audio Track** — visible only if `_realAudioTracks.length > 1`; opens `_openAudioPanel()`. Shows current track title/language as subtitle.
3. **Sleep Timer** — shows remaining time or "Off". Tap opens `_showLiveSleepTimerSheet()` (15/30/60/90 min). Active timer shows inline "Cancel" chip that calls `_setSleepTimer(null)`.

New helper method `_showLiveSleepTimerSheet()` — secondary bottom sheet with 15/30/60/90 min options.

**Wire-ups:**
- `_buildLivePortraitHeader()` settings icon: `_openSettingsPanel` → `_openLiveSettingsPanel`.
- `_buildLiveVideoControlsOverlay()` bottom row: added settings icon button between channel-list (left) and lock (right).

**Not changed:** `_openSettingsPanel()` (still used by all VOD paths and sidebar). `_buildLiveBottomArea()` / `_buildLivePortraitPanel()` (landscape controls bottom area — no settings icon there).

**LIVE_PLAYER_PLAN.md:** P1–P4, P7-B, P7-C checkboxes all marked `[x]`. P7-A and P6 remain `[ ]` (Jazz SIM dependent).

**Outstanding (Jazz SIM gated):**
- LIVE-P6: Audit all 84 channel stream URLs for `playlist_dvr_timeshift` variant; update has_dvr seed; Oracle redeploy.
- LIVE-P7-A: Check if tamashaweb CDN has rendition-level playlists (`playlist_720p.m3u8` etc.); build quality picker if available.

---

## LIVE-P6 — DVR URL audit (2026-07-24, commit `3b373164`)

**Scope:** `radd-hub/hub/db.py`, `LIVE_PLAYER_PLAN.md`. Oracle deploy required.

**Context:** LIVE-P6 was previously marked deferred (Jazz SIM needed). User confirmed tamashaweb CDN is accessible over regular wifi — no Jazz SIM gate on the DVR endpoint check. Audit unblocked.

**Method:** Node.js parallel fetch of `playlist_dvr_timeshift-0-3600.m3u8` substituted into each of the 84 channel stream URL paths (replacing `playlist.m3u8` or `chunks.m3u8`). 10-channel batches, 8s timeout per request. Checked HTTP status + `#EXTM3U` in response body.

**Results — 3 DVR confirmed:**
| channel_id  | Name        | DVR URL |
|-------------|-------------|---------|
| geo-news    | Geo News    | cdn07isb vsat-geonews-abr/playlist_dvr_timeshift-0-3600.m3u8 (known) |
| ary-news    | ARY News    | cdn07isb vsat-arynews-abr/playlist_dvr_timeshift-0-3600.m3u8 (NEW) |
| ary-digital | ARY Digital | cdn07lhr vsat-arydigital-abr/playlist_dvr_timeshift-0-3600.m3u8 (NEW) |

All 81 others: HTTP 404 (no DVR path exists) or 403 (CDN auth blocks DVR).

**Changes:**
- `_live_seed` stream_url for `ary-news` → DVR variant URL
- `_live_seed` stream_url for `ary-digital` → DVR variant URL
- `_dvr_channels` extended with `ary-news: (1, 3600)` and `ary-digital: (1, 3600)`
- `LIVE_PLAYER_PLAN.md` P6-A/B/C checked ✅; P6-D pending Oracle deploy

**Oracle deploy:** pending user confirmation (`push_to_oracle.sh` restarts raddflix_radd).
