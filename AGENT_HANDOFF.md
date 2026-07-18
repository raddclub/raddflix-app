# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-18 — Subtitle system cleanup batch, CI ✅ `db73f4df`)

Three follow-up fixes to the subtitle system, three separate commits:

**Commit `d23fbb65` — Merge duplicate MPV colour helpers**
`_subMpvColor`/`_subMpvBackColor` (mixin) and `_toMpvColor`/`_toMpvBackColor` (panel) were exact duplicates with a "keep in sync" comment — a silent drift risk. Both are now deleted; replaced by two top-level private functions `_mpvSubColor`/`_mpvSubBackColor` at the bottom of `_ps_subtitle_mixin.dart`. Since both part-files belong to the same library (`player_screen.dart`), the top-level functions are accessible from both without any class prefix. All six call sites updated.

**Commit `360318c0` — Fix `onStyleSynced` missing shadow propagation**
`onStyleSynced` synced font/size/bold/colour to `PlayerPrefs` but not the shadow style. Flutter overlay widgets (`SubtitleOverlay`, `DualSubtitleOverlay`) read `subtitleOutlineThickness` from `PlayerPrefs` and always got the static default (2.0) regardless of what the user picked in the panel. Added `required int shadowIdx` to the callback signature; consumer maps idx → thickness using the same values as MPV (`0=None→0.0`, `1=Outline→2.0`, `2=Drop Shadow→0.5`, `3=Box→0.0`) and writes `subtitleOutlineThickness` to `PlayerPrefs`.

**Commit `4a1a8a28` — Unify shadow offset math between overlay widgets**
`SubtitleOverlay` used `outline` as shadow offset with `outline*2` blurRadius. `DualSubtitleOverlay._SubLine` used `outline/2` offset with `outline` blurRadius. Same setting, different visual result in single vs dual subtitle mode. Standardised both to `outline/2` offset + `outline` blurRadius — matches the dual overlay's existing (subtler) calculation.

**No Oracle push needed** — zero `radd-hub/**` files touched.

---

## Previous State (2026-07-18 — Subtitle defaults + bug fixes, CI ✅ `e3f3ea51`)

Two subtitle fixes in one commit (`e3f3ea514d`):

1. **Default shadow: Outline → Drop Shadow** — first-time users (and any user who has never touched the shadow setting) now get a soft directional shadow (3px offset, 0.5px outline) instead of a hard 2px black border around every character. Three fallback sites updated: `_subShadowIdx` field initializer in `_SubtitlePanelState`, plus `?? 1` → `?? 2` in both `_loadSubPrefs()` (`_ps_panels_subtitle.dart`) and `_applySubtitleStylePrefs()` (`_ps_subtitle_mixin.dart`).

2. **Bottom margin slider shows stale 100px on panel reopen** — `_loadSubPrefs()` never read `pref_sub_margin` back from SharedPrefs, so the position tab's Bottom Margin slider always showed 100px even after the user had moved it. Added `final margin = prefs.getDouble('pref_sub_margin') ?? 100.0` + `_subBottomMargin = margin` inside `setState` in `_loadSubPrefs()`.

**Other bugs found (not fixed — report only):**
- `onStyleSynced` doesn't sync shadow style to `PlayerPrefs.subtitleOutlineThickness` → Flutter overlay silently ignores the user's shadow choice (dual-sub mode only)
- `SubtitleOverlay` and `DualSubtitleOverlay._SubLine` use different shadow offset math (outline vs outline/2) → same setting, different look in dual-sub mode
- Duplicate MPV colour helper functions (`_subMpvColor`/`_subMpvBackColor` in mixin vs `_toMpvColor`/`_toMpvBackColor` in panel) — "keep in sync" comment is fragile

**No Oracle push needed** — zero `radd-hub/**` files touched.

---

## Previous State (2026-07-18 — Warm Hearth theme audit complete, CI ✅ `6febd59e`)

Comprehensive audit of every active theme's colour implementation. Warm Hearth (the `dark` default) was the primary focus; all other themes (`amoled`, `light`, `midnight`, `navy`, `forest`, `cobalt`, `rose`, `charcoal`) were verified as correct — their tokens live in `radd_theme.dart` and were already consistent.

**What was fixed (24 files, 1 commit):**
1. **Critical** — `sync_panel.dart` Reset button bg was still old-red `0x22E8002D` → `0x22D4784A` (Warm Hearth glow)
2. **High — cold player panels** — 15 player files (`player_settings_screen`, `video_enhance_panel/suite`, `speed_picker/presets_sheet`, `zoom_crop_overlay`, `word_definition_sheet`, `_ps_panels_sidebar/audio/subtitle`, `_ps_playback_mixin`, `resume_fab`, four `core/player/` services) were using Midnight-era darks (`0xFF0D0D1A`, `0xFF12121E`, `0xFF1C1C1C`, `0xFF0D1117`, etc.) → replaced with correct Warm Hearth tokens (`AppColors.background/surface/surfaceHigh/card`) or their inline hex equivalents
3. **Medium — hardcoded warm hexes** — `layout_designer_screen`, `debug_diagnostics_screen`, `app_lock_screen`, `home_screen`, `splash_screen` (logo gradient), `resume_fab` used correct values but as raw hex literals → now use `AppColors.*` named tokens
4. **Minor — semantic misses** — `profile_screen.dart` subscription countdown used literal `#FFB300`/`#00C853` → `AppColors.warning/success`; `login_screen.dart` "or" divider used `Color(0x33FFFFFF)` → `t.border`

**Intentionally left unchanged:** player overlay whites (`Colors.white12/24/38`), subtitle preset colour pickers, EQ blue selection indicator, WhatsApp green, Simosa brand purple, Vault purple, tier badge gold/silver, genre card gradients, log category colours.

**No Oracle push needed** — zero `radd-hub/**` files touched.

---

## Previous State (2026-07-17 — Z2: broad improvements, CI ✅ `90bf0a3`)

Completed the audio-mode music player UX:
1. **Embedded cover art** — `flutter_media_metadata: ^1.0.3` added to pubspec; `_scanCoverArt()` now falls back to `MetadataRetriever.fromFile()` after sidecar probe fails. Embedded bytes stored as `_embeddedArtBytes: Uint8List?`; passed as `MemoryImage` to disc, backdrop, and `_extractPalette()`. Sidecar path still wins when both exist.
2. **Prev / Next buttons** — flanking the play/pause circle in the glass card. `_SkipButton` widget with `AnimatedOpacity` dims to 0.35 when disabled. Wired to `_playEpisodeAt(_currentEpIdx - 1/+1)` via existing `_hasPrev`/`_hasNext` getters.
3. **Shuffle / Repeat toggles** — `_ToggleIcon` row above the seek bar; active state shows accent-coloured icon on a translucent accent circle. Repeat wired to `_toggleLoop()`. Shuffle adds `_shuffleEnabled` bool + `_toggleShuffle()` + `_randomEpIdx()` to `_PlayerPlaybackMixin`; auto-advance picks `_randomEpIdx()` instead of `+1` when active.
4. **No architectural changes** — `AudioModeBackdrop` widget signature extended with optional-default params; all existing call-sites compile unchanged.

See TASK_LOG.md (Z1 entry) for file-by-file details.

---

## Previous State (2026-07-16 — Y2: vault logic audit + 5 follow-up fixes, CI ✅ `4da50433`)

Deep audit of vault vs MX Player. Five logic bugs found and fixed:
1. **Sidecar stored FilePicker temp-cache paths** — `moveFileToVault`/`moveFilesToVaultBatch` now only write `.raddmeta` for paths starting with `/storage/` or `/sdcard/`; cache paths under `/data/` are skipped.
2. **`restoreFile(vaultPath, destDir)` orphan skipped sidecar cleanup** — added sidecar delete.
3. **`deleteFromMediaStore` result silently ignored** — all three callers now capture the `bool` and append "• May still appear in gallery" to the snackbar (5s duration) when the Android 11+ permission dialog is dismissed.
4. **`totalVaultSize()` counted `.raddmeta` files** — now skipped.
5. **`notifyMediaStore(vaultPath)` in `restoreFileToDownloads` was a no-op with wrong comment** — vault is app-internal, never in MediaStore; removed the call and corrected the comment.

See TASK_LOG.md (Y2 entry) for full MX Player comparison writeup.

---

## Previous State (2026-07-16 — Y1: player UI + vault bug-fix batch, CI ✅ `459244b5`)

Five bugs found in APK testing, all fixed in one commit:
1. **Duplicate reload icon** — "Replay from start" `_RaddIconBtn` was sitting in the title bar next to battery/clock; removed it. The skip-back button in the transport row is the only replay icon now.
2. **BG Audio shortcut missing** — added `'bgaudio'` to `_buildSidebar` defs; toggles background audio and persists with `_scheduleSavePrefs()`.
3. **Vaulted files still visible in file managers** — `restoreFileToDownloads` was deleting the vault source file but not calling `notifyMediaStore(vaultPath)`, leaving a stale MediaStore ghost. Fixed.
4. **Restore creates duplicate** — same root cause as #3; the ghost entry persisted alongside the newly restored Downloads entry. Fixed by the same `notifyMediaStore(vaultPath)` call.
5. **Restore always goes to Downloads** — vault never stored original path. Added `.raddmeta` sidecar on every import (`moveFileToVault` + `moveFilesToVaultBatch`). New `restoreToOriginal()` reads the sidecar and returns the file to its original folder, falling back to Downloads if the folder is gone. `listFiles` skips `.raddmeta` files; `deleteVaultFile` cleans them up.

No Oracle or backend changes this session.

---

## Previous State (2026-07-16 — PLANS-NO-JS-FIX: replaced JS modal with server-rendered form pages)

JS modal approach for create/edit was still failing after the previous fix — browser-side JavaScript blocking (extension or policy) prevented the modal from opening and setting the form's `action`. Replaced the entire modal with dedicated server-rendered pages (`GET /plans/new`, `GET /plans/<id>/edit_form`) so zero JavaScript is required for any CRUD operation. Edit buttons and Add New Plan card are now plain `<a>` links. Deployed as `e1cb9da3`. All four plans CRUD operations confirmed working server-side.

---

## Previous State (2026-07-16 — PLANS-ADMIN-FIX: admin panel plans, features_json, TID DB lookup)

Four backend bugs fixed and deployed to Oracle in commit `b545d78b`. No Flutter changes. No new packages.

**Root cause:** `plans` table was never seeded — `init_db()` seeds payment methods and settings but had no plan rows. The admin panel at `/plans/` queries the DB directly so showed 0 plans. The Flutter app appeared to work because `mobile_api.py` `/api/subscription/plans` has a hardcoded 4-plan fallback triggered when `plan_rows` is empty — meaning the app always showed the fallback cards, never the DB.

**4 fixes:**

1. **`db.py` — `init_db()` seeds default plans when table is empty** — Starter/Basic/Standard/Premium matching the fallback plans in `mobile_api.py`. Seeding is idempotent: only runs when `COUNT(*) FROM plans = 0`. After the server restart the plans table now has 4 rows; admin at `/plans/` shows them with full edit/toggle/delete/add CRUD.

2. **`mobile_api.py` — features read from correct field** — Line 730 was `json.loads(p.get("description") or "[]")`. Features are stored in `features_json` column (added in a prior migration). Fixed to `p.get("features_json")`. Previously features were always empty in the app even when set via the admin panel.

3. **`tid_panel.py` — TID approval uses DB duration/price, not hardcoded dicts** — `approve()` was hardcoded `PLAN_DURATIONS = {"basic": 30, "standard": 30, "premium": 30}` and `PLAN_PRICES = {"basic": 149, ...}`. Any duration_days or price_pkr change made in the admin panel was silently ignored on approval. Now does `SELECT duration_days, price_pkr FROM plans WHERE LOWER(name)=LOWER(?)` and falls back to the old hardcoded dicts only for legacy plan names not found in DB.

4. **`subscriptions.py` — dead `PLAN_DURATIONS` dict removed** — Line 11 had the same hardcoded dict but it was never referenced anywhere in the file. Removed.

**Smoke test:** `curl http://92.4.95.252/api/subscription/plans` returns 4 plans from DB (ids 1–4, real integer IDs) with correct features arrays, colors, and jazz savings messages.

---

## Previous State (2026-07-16 — VAULT-SPEED: parallel bulk-add + single dir resolve)

Vault bulk-add speed improvements in commit `9cf5631f`. No new packages, no API changes.

**Root cause:** every serial `for (final f in files) { await moveFileToVault(f.path); }` loop stacked 3 sequential IPC/IO calls per file: (1) `getVaultFolder()` — dir exist check + .nomedia check, (2) `File.rename()`, (3) `notifyMediaStore()` — one MethodChannel round-trip per file. A 50-episode season = 150 serial awaits.

**What changed:**

1. **`vault_service.dart`** — new `moveFilesToVaultBatch(sourcePaths, {folder, onProgress})`:
   - Resolves target directory **once** before the loop (eliminates N × `getVaultFolder` calls)
   - Moves files in **parallel chunks of 4** via `Future.wait` — same concurrency pattern already used for thumbnail loading
   - Per-file errors swallowed inside each chunk so one bad file never aborts the batch
   - Fires **all `notifyMediaStore` calls concurrently** (`Future.wait(paths.map(notifyMediaStore))`) at the end instead of one blocking IPC per file
   - `moveFileToVault` (single-file) unchanged — still used by `local_folder_screen._addToVault`

2. **`vault_screen.dart`**:
   - `_importVideoFolder` — serial loop replaced with `moveFilesToVaultBatch`
   - `_processPickedFiles` — paths + content URIs collected sync up-front, then `moveFilesToVaultBatch`; `deleteFromMediaStore` (already batched on Kotlin side) unchanged
   - `_deleteSelected` — `for-await` replaced with `Future.wait(_selected.map(deleteVaultFile))`

3. **`local_media_screen.dart`** — `_addFolderToVault`: content URIs pre-collected sync via collection-if, serial loop replaced with `moveFilesToVaultBatch`

**Expected impact:** for a 50-file season folder, folder-resolve overhead drops from 50 async calls → 1, MediaStore scans from 50 serial IPCs → concurrent batch. Rename operations (same filesystem) run 4-at-a-time instead of sequentially.

---

## Previous State (2026-07-16 — APP-LOCK: full app PIN / biometric gate)

Full app-level lock implemented in commit `11950d5e`. No new pub packages — `flutter_secure_storage`, `local_auth`, `shared_preferences`, `crypto` were already in `pubspec.yaml`.

**5 files changed:**

1. **`lib/services/app_lock_service.dart`** (new) — standalone service, independent of `VaultService`. SHA-256 + salt `raddflix_app_lock_salt_` PIN hash stored under key `app_lock_pin_hash` in `FlutterSecureStorage`. `onAppPaused()` records `_pausedAt`; `onAppResumed() → bool` compares elapsed time against cached timeout (0=immediately, -1=never, >0=seconds). `authenticateBiometric()` mirrors the Infinix/MediaTek Class 2 fix from VaultService (uses `getAvailableBiometrics()` not `canCheckBiometrics`). `setFlagSecure(bool)` calls `com.raddflix.app/security` channel.

2. **`lib/screens/app_lock_screen.dart`** (new) — three widgets in one file: `AppLockScreen` (overlay, `PopScope(canPop:false)`, auto-triggers biometric on open), `AppLockSetupScreen` (2-step route, returns bool), `AppLockChangePinScreen` (3-step: verify old → enter new → confirm new, returns bool). All use `RaddLockPad` with `RaddLockPadAccent.standard`.

3. **`lib/app.dart`** — new `_AppLockGuard` StatefulWidget + WidgetsBindingObserver inserted in `MaterialApp.builder` between MediaQuery and `_ForceUpdateGuard`. Locks on cold start (always, if PIN set). `_handleResumed()` re-checks `hasPin()` on every resume so enabling/disabling PIN in Settings takes effect without re-init.

4. **`lib/screens/settings_screen.dart`** — new "App Lock" section (staggerIndex 5; About shifted to 6). Rows: Enable toggle (setup on first enable, confirmation dialog on disable), Change PIN (temporarily removes FLAG_SECURE during entry), Biometric toggle (hidden if unavailable), Auto-lock After selector (RadioListTile dialog: immediately / 30s / 1min / 5min / never). Toggle optimistically updates then reverts if action is cancelled.

5. **`android/app/src/main/kotlin/…/MainActivity.kt`** — added `import android.view.WindowManager` and `"setFlagSecure"` case to `SECURITY_CHANNEL`: `window.addFlags` / `clearFlags(WindowManager.LayoutParams.FLAG_SECURE)`.

**Key design decisions:**
- Lock screen is an overlay widget (replaces child in builder), NOT a pushed route — always covers 100 % of screen regardless of which route is active, no race conditions with Navigator readiness.
- App lock PIN and vault PIN are fully independent: different SecureStorage keys, different salts, different services.
- FLAG_SECURE is cleared before PIN setup/change screens open so digits are visible; restored on pop.
- Auto-lock "Never" (-1): `onAppResumed()` returns false, so lock screen never shows after first unlock that session.

---

## Previous State (2026-07-15 — Vault UX Fixes: Restore + MediaStore + Progress + Unlock Gate)

Four vault bugs found and fixed in commits `4c3c2574` + `b91768e4` (CI ✅ green):

1. **Restore crash + file stuck in vault** — `_restoreToGallery` hardcoded `/storage/emulated/0/Download`. On Android 11+ (API 30+) `WRITE_EXTERNAL_STORAGE` is `maxSdkVersion=29` so `File.copy()` threw before `File.delete()`, leaving the file permanently stuck in vault while showing an error. Fix: added `copyToDownloads` native method to `MEDIA_CHANNEL` in `MainActivity.kt` that uses `MediaStore.Downloads` content provider on API 29+ (no permission needed) and direct copy on older versions. New `VaultService.restoreFileToDownloads()` calls it and deletes the vault source only after successful copy.

2. **Files still visible in MX Player / file managers after vault add** — `_addFolderToVault` (local_media_screen) and `_addToVault` (local_folder_screen) called `moveFileToVault()` but never called `deleteFromMediaStore()`. Fix: construct content URI from `LocalVideo.id` → `content://media/external/video/media/{id}` and call `deleteFromMediaStore()` after each move. Files now disappear from every media app immediately.

3. **No progress feedback (heavy/frozen feel)** — all vault-add operations blocked the UI with no indicator. Fix: non-dismissible `AlertDialog` with `LinearProgressIndicator` + live `X of Y files` counter via `ValueNotifier<int>` + `ValueListenableBuilder`. Shared via new `_VaultProgressDialog` widget in vault_screen.dart. Applied to all four paths: `_processPickedFiles`, `_importVideoFolder`, `_addFolderToVault`, `_addToVault`.

4. **Missing unlock gate in `local_folder_screen._addToVault`** — checked `hasPin()` but not `VaultService.isUnlocked`. A user with a configured-but-locked vault could silently move files without entering PIN. Fix: added `isUnlocked` check identical to the one in `local_media_screen`.

---

## Current State (2026-07-15 — UX-BATCH-3 All Complete + BUG-DL-EXT-01)

All 10 UX-BATCH-3 tasks (UX3-01 through UX3-10) were already done in code by a prior agent in this same session. TASKS.md was stale — all rows updated to ✅ DONE this session. CI green on all commits.

**BUG-DL-EXT-01 (commit `70334a63`, CI ✅):**
- Downloads hardcoded `.mp4` as the saved extension for every file regardless of actual container — an MKV saved as `.mp4` broke vault cover-art detection and the extension-gated open logic. Fixed in `download_service.dart` to preserve the real container extension from the stream URL.
- `LocalMediaService.getThumbnail` re-decoded a frame via MPV on every grid rebuild (no caching), causing scroll jank in Local Media/Local Folder screens. Fixed by routing through `ThumbService`'s existing mem+disk LRU cache.

**No open tasks remain.** The board is clean — all 10/10 plan phases (A–L), all UI/UX migration phases (2–7), and all UX-BATCH tasks (1–10) are ✅ DONE.

---

## Current State (2026-07-15 — Empty States + Shared-Element Transitions + Miniplayer)

### UX-BATCH-2 — Tasks 7-9 — 2026-07-15

Continuation of the direct-from-chat UX task list (tasks 1-5 were the prior batch: Show
Detail/Profile Switcher/Search/Settings/Downloads polish, commit `2b7f6672`).

1. **Empty states (Task 7):** `actor_screen.dart`'s "No titles in our catalog yet" state used a
   plain static `Icon(AppIcons.filmSlate)` while Search/Downloads/Local Media already used the
   animated `AnimatedSearchIcon` from `animated_empty_icons.dart`. Swapped it in for consistency.
   `admin_queue_screen.dart`/`debug_diagnostics_screen.dart` intentionally left as-is — internal
   dev tooling, not user-facing.
2. **Transitions (Task 8):** `watchlist_screen.dart` and `history_screen.dart` grids only had
   plain `Navigator.push` into the detail screen, while `home_screen.dart`/`search_screen.dart`
   already had a tier-gated `OpenContainer` shared-element morph (Tier 2+ devices via
   `animConfigProvider.canMorph`). Added the identical pattern to both screens so the grid→detail
   transition is consistent app-wide. `content_card.dart`'s internal detail sheet and
   `show_detail_screen.dart`'s "More Like This" rail were left untouched (lower priority, out of
   this batch's scope).
3. **Miniplayer (Task 9):** No background playback service exists in this app — playback state
   is local to `PlayerScreen`, so a "live" miniplayer (pause/resume audio while browsing) isn't
   architecturally supported without a much bigger change. Scoped honestly instead: new
   `lib/widgets/mini_player_bar.dart` (`MiniPlayerBar` + `MiniPlayerDock`) reuses the same
   `resume_*` SharedPreferences keys `ResumeFab` already wrote, rendered as a persistent glass bar
   docked above the bottom nav bar on all 5 top-level screens (Home/Search/Local/Downloads/
   Profile) instead of the old Home-only floating FAB. Swipe down or tap X to dismiss, tap to
   resume playback. `ResumeFab` class itself is untouched/still defined (in case a real miniplayer
   is built later) but no longer mounted anywhere.

**Commit:** `b7b74c20` — CI green: https://github.com/raddclub/raddflix-app/actions/runs/29411968550

---

## Current State (2026-07-14 — Billing 500 Fixed + Audio Panel Audit + Phase H/UI-UX-Migration Closed)

### BILLING-FIX — `/billing/` Internal Error — 2026-07-14

**Symptom:** `GET http://92.4.95.252/billing/` → `{"error":"internal error"}` (HTTP 500).

**Root cause:** `received_sms_payments` table was referenced in 3 route files
(`payment_gateway.py`, `tid_panel.py`, `db_mgmt.py`) but was never added to `db.py`'s
`_DDL` list. Table never existed in the live DB → SQLite `OperationalError` on every
page load. Live log confirmed: `Exception: OperationalError` immediately before the 500.

**Additional issues found and fixed in the same commit:**
- `payment_methods` table missing 5 columns (`account_name`, `icon`, `min_amount_pkr`,
  `amount_tolerance_pkr`, `updated_at`) that the update form writes to — silently broken.
- No POST endpoint for the admin phone-app SMS gateway despite the UI having a gateway key
  config and a "POST incoming SMS" description — gateway was non-functional.

**Fix (commit `90328920`, deployed to Oracle):**
1. Added `received_sms_payments` CREATE TABLE + 2 indexes to `_DDL` in `db.py`
2. Added ALTER TABLE migrations for 5 missing `payment_methods` columns
3. Added default method seeding (EasyPaisa/JazzCash/NayaPay/SadaPay) + auto-generated
   `sms_gateway_key` in `init_db()`
4. Added POST `/billing/api/sms/receive` with gateway-key auth, TID auto-matching,
   and configurable auto-approve (`sms_auto_approve_enabled` setting)
5. Deployed via `push_to_oracle.sh` — `GET /billing/ → 200` confirmed in live logs.

---

## Current State (2026-07-14 — Audio Panel Audit + Phase H/UI-UX-Migration Closed)

### AUDIO-PANEL-SAVE — EQ Preset Save Bug — 2026-07-14

Targeted audit of `_openAudioEffectPanel` in `_ps_ui_mixin.dart`: every callback
(`onEqBandChanged`, `onEqEnabledChanged`, `onReverbChanged`, `onLabAfChanged`,
`onLabStateChanged`, `onBalanceChanged`, `onPresetSelected`) checked for `_scheduleSavePrefs()`.

**One bug found:**
- `onPresetSelected` → `_applyPreset` — called directly (no lambda wrapper), applies the
  EQ preset to MPV immediately via `_applyAllAf()` but never calls `_scheduleSavePrefs()`.
  Selecting "Treble Boost", "Bass Boost", etc. was lost on next launch. Same class as the
  SW Decoder bug from the previous session.
- Fix: added `_scheduleSavePrefs();` after `_applyAllAf()` in `_applyPreset()` in
  `_ps_audiolab_mixin.dart`.

**All other callbacks confirmed correct:**
- `onEqBandChanged` — lambda calls `_applyCustomEq()` + `_scheduleSavePrefs()` ✅
- `onEqEnabledChanged` — lambda calls `_applyAllAf()` + `_scheduleSavePrefs()` ✅
- `onReverbChanged` — lambda calls `_applyAllAf()` + `_scheduleSavePrefs()` ✅
- `onLabAfChanged` — lambda calls `_applyAllAf()` only; no save call, but `_applyLabAf()`
  in the panel always fires `onLabStateChanged` immediately after, which does save ✅ (safe)
- `onLabStateChanged` — lambda calls `_scheduleSavePrefs()` ✅
- `onBalanceChanged` → `_applyBalance` — calls `_scheduleSavePrefs()` ✅

### PHASE-H + UI-UX-MIGRATION Closed — 2026-07-14

Both tasks closed at user direction:
- **PHASE-H**: H1/H4/H5 done (test/ structure, widget tests, prefs round-trip, CI-wired). Infrastructure goal is complete.
- **UI-UX-MIGRATION**: Phases 2–7 all complete + CI green. Phase 1 "Player HUD footprint"
  closed via static-code analysis (no 5-control violation confirmed); live-device measurement
  deferred (no SDK/emulator) and accepted as sufficient closure.

**Next session:** Consider Phase J3–J5 (AudioLab/Subtitle/UI mixin extraction from `_PlayerScreenState`) or any user-prioritised task.

---

## Current State (2026-07-13 — Phase J In Progress)

### PHASE-J — Player God Class Decomposition — 2026-07-13

**First pass done:** Panel widget classes extracted to `part` files.

- **J-prep** ✅ All top-level panel/widget classes (6,194–9,425 of original) extracted to three
  `part` files under `lib/screens/player/`. Main file reduced from 9,425 → 6,198 lines.
  Files: `_ps_panels_subtitle.dart` (1,187 lines), `_ps_panels_audio.dart` (1,691 lines),
  `_ps_panels_sidebar.dart` (366 lines). Zero behavioral change — `part`/`part of` keeps the
  same library namespace; all `_` private identifiers accessible cross-file.

- **J2** ✅ DONE 2026-07-13 — `_PlayerPlaybackMixin` extracted to `lib/screens/player/_ps_playback_mixin.dart`
  (~1,103 lines). Owns player lifecycle/init, stream resolution, episode nav + near-gapless
  prefetch, watch-position persistence, speed, mute/loop, orientation lock, sleep timer, usage
  tracking, auto-retry, and skip-editor check — 29 methods + ~40 state vars/getters moved.
  `class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver,
  _PlayerPlaybackMixin`. Main file now 5,187 lines (down from 6,198). CI green after one fixup
  (see gotcha below). Full method/field lists and the abstract cross-cluster declarations this
  mixin needed live in the commit diff — not reproduced here since they're derivable from the
  file itself; the durable lessons are:
  - **`part of` path is relative to the part file's own directory, not the library file's.**
    `_ps_playback_mixin.dart` lives in `screens/player/`, so it must say
    `part of '../player_screen.dart';` — writing `part of 'player_screen.dart';` (correct only
    for a part file sitting next to the library) fails whole-library resolution in
    `flutter build`/CI with one misleading root error (`Error when reading
    '.../player/player_screen.dart': No such file or directory`) that cascades into hundreds of
    unrelated "getter/method isn't defined" errors across the entire class — because the mixin
    type never resolves, Dart treats the whole class as broken. If you see a wall of "X isn't
    defined for the class '_PlayerScreenState'" errors touching fields that were never moved,
    check the `part of` path first before chasing individual symbols.
  - Confirmed via brace-depth counting (not indentation, which is unreliable in this file):
    `_checkSkipEditor`/`_loadSkipEditorPrefs` are genuine top-level `_PlayerScreenState` methods,
    not nested closures — safe to move as planned.
  - Same false-positive preflight issue as the panel files — used `SKIP_PREFLIGHT=1` since the
    mixin uses `AppRoutes` (imported by `player_screen.dart`, inherited via the shared part-file
    library scope) and `preflight_check.sh` only checks each file's own import list.

- **J3–J5** ⏳ PENDING — Remaining method-cluster extraction using mixins on `ConsumerState<PlayerScreen>`
  (AudioLab, Subtitle, UI/gesture clusters). Same pattern as J2: identify the cluster's methods/state,
  diff referenced identifiers against the moved set to find cross-cluster dependencies needing
  abstract getter/setter/method declarations, verify exact line ranges via brace-depth counting
  (not indentation) before cutting, then move as a `part` file and add to the `with` clause.

- **J6** ⏳ PENDING — Slim `_PlayerScreenState` to `initState` + `dispose` + `build` after J2–J5.

---

## Current State (2026-07-12 — Phase H In Progress)

### PHASE-H — Testing Infrastructure — 2026-07-12

H1/H4/H5 done.

- **H1** `test/` directory structure created; `mocktail` dep added; `flutter test` wired into CI
  as a **separate `ci-tests.yml` job** (this job did not exist before H1 — `build-apk.yml` never
  ran `flutter test`).
- **H4** Widget tests written for `RaddButton`, `RaddChip`, `RaddTextField`, `RaddCard`, `RaddSheet`.
- **H5** `PlayerPrefs` save/load round-trip tests (one field per settings category + defaults +
  derived getters). Commits: `809f537` (H1), `a022e48` (H4/H5).

**No tests were executed locally** — no Flutter/Dart SDK available in this Replit environment.
Correctness rests on source review + CI. After any push touching `test/`, `pubspec.yaml`, or
`.github/workflows/`, check **BOTH** CI job statuses (Rule 50):
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/runs?per_page=1"
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/ci-tests.yml/runs?per_page=1"
```

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- `kDebugMode` gate requires `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43)
- After any Flutter push, check BOTH `build-apk.yml` AND `ci-tests.yml` CI jobs (Rule 50)

---

## Current State (2026-07-12 — Phase G ✅ FULLY CLOSED)

### PHASE-G — Architecture Modernisation — 2026-07-12

All G items resolved and pushed. Commits: `58a0137` (G2), `c9974ac` (G3), `fb8e65d` (G5),
`2580b88` (G1 typed-args fix), `2f2a11d` (G1 close + G4 deletion).

- **G1** go_router literal package swap left undone by user decision (unverifiable runtime
  routing behaviour without device/CI coverage). Root cause it targeted — `ModalRoute.of(context)?
  .settings.arguments` reads in `player_screen.dart` — already fixed via typed `PlayerScreen`
  constructor params (commit `2580b88`). Marked complete (`2f2a11d`).
- **G2** `flutter_staggered_animations` + `animated_text_kit` removed (zero usages confirmed across
  all 67k lines). `animations` (OpenContainer) kept — used in `home_screen.dart` L481 +
  `search_screen.dart` L836 for Tier 2+ card morph. Commit `58a0137`.
- **G3** `video_thumbnail` → `media_kit`-based frame extraction:
  `services/media_kit_thumbnail_extractor.dart` added; `video_thumbnail` removed from pubspec.yaml.
  Commit `c9974ac`.
- **G4** 13 lettered stub files in `core/player/` (c/d/f/g/n/o/p/q/r/s/t/u/v_series_*) deleted
  after explicit user approval + zero-import re-verification across all `lib/`. Commit `2f2a11d`.
- **G5** `AppConstants` mutable statics (`apiBaseUrl`, `jazzDriveDeltaUrl`, `supportWhatsApp`) →
  `remoteValuesProvider` (Riverpod) + `appContainer` for non-widget access. Commit `fb8e65d`.

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- `kDebugMode` gate requires `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43)

---

## Current State (2026-07-12 — Phase L Complete)

### PHASE-L — Production Hygiene — 2026-07-12

All Phase L items resolved and pushed. CI pending on `7231766b`.

**What was done:**
- **L1** `profile_screen.dart`: "Debug Logs" `_SectionTile` (with `AppIcons.bugReport`) wrapped in
  `if (kDebugMode || (user?.isAdmin == true))` — invisible to regular users in release builds.
- **L2** `profile_screen.dart`: 5-tap version string easter egg wrapped same way — in release builds
  for non-admins, the counter resets silently with no navigation to `DebugDiagnosticsScreen`.
- **L3** `debug_diagnostics_screen.dart`: `DebugLogger.getLogPath()` replaced with `'Log stored on device'`
  — raw internal filesystem path no longer shown even to admins.
- **L4a** `vault_screen.dart`: 3 SnackBar catch blocks (`'Restore failed: $e'`, `'Could not import: $e'`,
  `'Could not import folder: $e'`) → friendly static strings + `kDebugMode` debug log.
- **L4b** `subtitle_hunter_sheet.dart`: file not at expected path — finding was stale, N/A.
- **L4c** `admin_queue_screen.dart`: `_error = e.toString()` → `'Could not load queue. Please try again.'`.
- **L4d** `edit_profile_screen.dart`: 2 raw exception paths → friendly strings + `kDebugMode` debug log.
  Added `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43).
- **L4e** `subscription_screen.dart`: `e.toString().replaceFirst('Exception: ', '')` → `'Payment submission failed. Please try again.'`.
- **L4f** `add_edit_profile_screen.dart`: already uses friendly messages — N/A.
- **L5a–c**: `_friendlyError()` and `AuthErrors.login/register()` already return generic final messages — N/A.
- **L6**: `_isFree` stuck-true bug already fixed (BUG-C02 fix in `_openMediaForEpisode`) — N/A.
- **L7** `app.dart`: All 4 `_RaddNavObserver` `DebugLogger.logNav(...)` calls wrapped in `if (kDebugMode)`.
  Added `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43).
- **L8** `actor_service.dart`: grep confirmed zero `DebugLogger` calls — finding was stale, N/A.
- **L9** `profile_screen.dart`: `// BUG-A23`, `// BUG-A21`, `// BUG-A22` removed from import lines;
  `// BUG-A14` comment block removed; inline BUG-A comments reworded to plain English.
- **L10** Deferred — `ApiClient.isGuestMode` mutable static belongs in the same session as Phase G/E3
  Riverpod migration. Left as `[ ]` in TEN_POINT_PLAN.md.

**Previous agent's doc omissions also fixed this session:**
- AGENT_HANDOFF.md had no Phase F entry — added.
- TASK_LOG.md had no Phase F entry — added.

**Commits:** `cb7734d` (docs), `7035956` (L1+L2+L9), `6f27ca0` (L7), `e65617b` (L3),
`049dfaf` (L4c+d+e), `7231766` (L4a).

**Next phase:** Phase G (Architecture Modernisation — go_router, package consolidation, folder reorg).
Recommended order: G2 (animation package consolidation) → G4 (dead player file audit) → G1 (go_router) → G5 (AppConstants).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- `kDebugMode` gate requires `import 'package:flutter/foundation.dart' show kDebugMode;` (Rule 43)
- TEN_POINT_PLAN.md dead-code/audit findings not guaranteed accurate — re-grep before trusting
- When a global variable is used before `runApp()`, migrating to Riverpod requires a manually-created
  `ProviderContainer` passed via `UncontrolledProviderScope`

---

## Current State (2026-07-12 — Phase F Complete)

### PHASE-F — Design System Migration: Remaining 70% of Screens — 2026-07-12

All 28 Phase F items from `agent-hub/TEN_POINT_PLAN.md` completed and pushed. CI green on `62867e45`.

**What was done:**
- **F01** `home_screen.dart`: `RaddButton` for primary action buttons; `RaddMotion.tuneDuration` for
  animated containers; `RaddSpace` tokens for spacing.
- **F02** `show_detail_screen.dart`: `RaddMotion.tuneDuration` + `RaddRadius.smRadius/mdRadius/lgRadius`
  replacing raw `Duration(milliseconds: 200/260)` and `BorderRadius.circular(...)` literals.
- **F03** `search_screen.dart`: `RaddMotion.tuneDuration`; `RaddChip` adoption for filter chips.
- **F04** `profile_screen.dart`: `AppColors.simosaAccent` replacing the SIMOSA-purple raw hex; `RaddButton`.
- **F05–F07** `downloads_screen.dart`, `local_folder_screen.dart`, `local_media_screen.dart`:
  `RaddMotion.tuneDuration`; remaining `Colors.*` → `AppColors.*` tokens.
- **F08** `settings_screen.dart`: Full `SettingsRow` adoption for all settings items (D5 SettingsRow
  params already added in Phase D); all raw spacing/radius literals replaced.
- **F09** `login_screen.dart`: `RaddButton` replaces `_GradientButton` and OTP `OutlinedButton`s;
  `AppColors.warning` replacing raw orange hex; `_GradientButton` helper class deleted.
- **F10** `register_screen.dart`: `RaddButton` replaces inline gradient + `OutlinedButton`.
- **F11** `subscription_screen.dart`: `RaddMotion.tuneDuration` for animated expansions.
- **F12** `edit_profile_screen.dart`: `RaddMotion.tuneDuration` for field focus animations.
- **F13** `vault_screen.dart` + `vault_settings_screen.dart`: `AppColors.simosaAccent` replacing
  SIMOSA-purple hex; remaining radius/spacing tokens.
- **F14** `debug_diagnostics_screen.dart`: `AppColors.success`/`AppColors.error`; `RaddRadius` tokens.
- **F15–F17, F20–F24** (`tid_status`, `add_edit_profile`, `profile_switcher`, `actor`, `admin_queue`,
  `plan_expired`, `quota_full`, `season_folder`, `onboarding`): remaining literals passed through with
  `// intentional: no token` comments where no exact token match exists (brand colors, off-scale values).
- **F18** `history_screen.dart`, **F19** `watchlist_screen.dart`: `RaddRadius.mdRadius` replacing raw
  `BorderRadius.circular(12)`.
- **F25** `content_card.dart`: `AppColors.success`/`AppColors.info` replacing `Colors.green`/`Colors.blue`.
- **F26** `simosa_card.dart`: `AppColors.primary`/`AppColors.primaryDark` for gradient stops.
- **F27** `quick_settings_panel.dart` (1,684 lines): `RaddRadius.smRadius/mdRadius/lgRadius` +
  `RaddMotion.tuneDuration` across all panel sections.
- **F28** `player_hud_settings_sheet.dart` (1,145 lines): `RaddRadius.smRadius` + `RaddMotion.tuneDuration`.
- **Fix commit** `62867e45`: `PhosphorIcons.dotsThreeBold` → `PhosphorIcons.dotsThreeVertical()` in
  `radd_button.dart` (non-existent member caught by CI, fixed immediately).

**What the last agent skipped (fixed this session):**
- AGENT_HANDOFF.md was not updated with Phase F summary — fixed now.
- TASK_LOG.md had no Phase F entry — fixed now.

**Next phase:** Phase L (Production Hygiene — remove developer artifacts from release builds).
Recommended before Phase G because it's low-risk and directly fixes real user-facing issues.
L6 (_isFree stuck true) and L8 (actor_service.dart DebugLogger) are already fixed in code —
confirmed by grep. Remaining items: L1, L2 (Debug Logs tile / easter egg gate), L3 (log path),
L4 (raw e.toString() in 6 screens), L5 (_friendlyError fallback), L7 (navigator observer logs),
L9 (BUG-Axx comment audit), L10 (ApiClient.isGuestMode mutable static).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- TEN_POINT_PLAN.md dead-code/audit findings are not guaranteed accurate — re-grep before trusting
- `kDebugMode` gate requires `import 'package:flutter/foundation.dart' show kDebugMode;` explicitly
  (Rule 43) — `package:flutter/material.dart` does NOT reliably re-export it
- When a global variable is used before `runApp()`, migrating to Riverpod requires a manually-created
  `ProviderContainer` passed via `UncontrolledProviderScope` (see E3 notes)

---

## Current State (2026-07-11 — Phase E Complete)

### PHASE-E — Provider Architecture: God Provider Split — 2026-07-11

All 4 Phase E items from `agent-hub/TEN_POINT_PLAN.md` completed and pushed.

**What was done:**
- **E1** Extracted `SyncNotifier` (`lib/providers/sync_provider.dart`) from `CatalogNotifier`. It
  owns `SyncStatus` (idle/syncing/error), `lastSyncAt`, and `error`, and calls
  `SyncService.sync()` directly. `CatalogNotifier.syncFromServer()` is now a one-line delegate
  (`_ref.read(syncProvider.notifier).sync()`) — kept deliberately so every existing call site
  (`settings_screen.dart`, `home_screen.dart`'s pull-to-refresh, plus this file's own
  `initialize()`/lifecycle/connectivity triggers) needed zero changes. `SyncNotifier.sync()` calls
  back into a new `CatalogNotifier.onSyncComplete({itemsSynced, failed})` once the server
  round-trip finishes; that method still decides whether `_loadFromDb()` needs to run (that
  decision depends on catalog state — `isEmpty` — not sync state, so it stays in CatalogNotifier)
  and resets the poster-sync flag. The old guard conditions (`state.status != syncing` in
  `didChangeAppLifecycleState` / the connectivity listener) now read `syncProvider`'s
  `isSyncing`. `home_screen.dart` had 3 UI reads of `catalog.status == CatalogStatus.syncing`
  (shimmer gate, sync banner, empty-state gate) — updated all 3 to `ref.watch(syncProvider).isSyncing`
  so the loading UI keeps working correctly now that sync status lives outside `CatalogState`.
- **E2** Extracted `PosterSyncNotifier` (`lib/providers/poster_sync_provider.dart`) — owns
  `PosterSyncStatus` (idle/running/done) and `pendingCount`, and the `_posterSyncDone` flag /
  3-second delayed background download that used to live as static state on `CatalogNotifier`.
  `_loadFromDb()` now calls `_ref.read(posterSyncProvider.notifier).scheduleSync(movies, shows)`;
  `onSyncComplete()` calls `.resetFlag()` instead of the old static `resetPosterSyncFlag()`.
- **E3** Moved `appNavigatorKey`, `pendingVideoUri`, `pendingVideoTitle`, `pendingSubtitleUri` —
  previously bare global mutable variables in `app.dart` — into providers in a new
  `lib/providers/app_navigation_provider.dart` (`navigatorKeyProvider`, `pendingVideoUriProvider`,
  etc.). The non-obvious part: `main.dart` reads/writes these **before the widget tree exists** —
  once synchronously before `runApp()` (writing the cold-start "Open with" intent values) and once
  in a `MethodChannel` handler registered after `runApp()` that has no `BuildContext`/`WidgetRef`.
  A naive `ref.read(...)` swap doesn't compile in either spot. Fixed by having `main.dart` create
  its own `ProviderContainer` (with the existing `animConfigProvider` override moved onto it) and
  pass that same container to `runApp(UncontrolledProviderScope(container: container, child: ...))`
  — so the widget tree's `ref.watch/read` see the exact same provider state `main.dart` wrote to.
  `splash_screen.dart` (a `ConsumerStatefulWidget`, so it has `ref`) swapped its 3 global reads +
  clears for `ref.read(...)`/`ref.read(...notifier).state = null`.
- **E4** `SubscriptionNotifier.submitTid()` now calls `unawaited(loadStatus())` right after a
  successful submission, so plan/quota updates reach the UI without the user leaving and
  reopening the subscription screen. Checked first that this is safe: `subscription_screen.dart`'s
  loading spinner is driven by its own local `_submitting` flag, not `subscriptionProvider.loading`,
  so `loadStatus()`'s own `loading: true/false` transitions cause no visible flicker.

**Next phase:** Phase F (Design System Migration: remaining 70% of screens).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- JS `String.replace`: escape `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

 as `$` when Dart code contains `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

 interpolation
- TEN_POINT_PLAN.md dead-code/audit findings (icon mappings, "matches exactly" claims, "just add
  a provider" globals migrations, etc.) are not guaranteed accurate or complete — re-grep/re-diff
  and trace every real call site before trusting them, per the C3/D4/D6/E3 near-misses.
- When a global variable is read/written from code that runs before `runApp()` or from a
  callback with no `BuildContext`/`WidgetRef` (native platform-channel handlers, background
  isolates), migrating it to a Riverpod provider requires a manually-created `ProviderContainer`
  passed to `runApp()` via `UncontrolledProviderScope` — plain `ProviderScope` alone doesn't give
  non-widget code a way to read/write providers.

## Current State (2026-07-11 — Phase D Complete)

### PHASE-D — Widget Layer: Duplicates, Tokens, API Gaps — 2026-07-11

All 6 Phase D items from `agent-hub/TEN_POINT_PLAN.md` completed and pushed.

**What was done:**
- **D1** Deleted `lib/widgets/radd_text_field.dart` (the inferior duplicate). Its 3 remaining
  importers (`login_screen.dart`, `register_screen.dart`, `subscription_screen.dart`) now import
  `design_system/components/radd_text_field.dart`. That component's API did not actually cover the
  call sites (no `prefixIcon`, `keyboardType`, or `validator`), so D1 also had to extend it —
  folded D2 in at the same time since both touch the same file.
- **D2** Added `prefixIcon`, `keyboardType`, `validator`, `maxLines`, and `focusNode` params to
  `design_system/components/radd_text_field.dart`. `validator` required wrapping the internal
  `TextField` in a `FormField<String>` (not just adding the parameter) so it participates in the
  ambient `Form.validate()` that login/register already gate submission on — a bare callback
  parameter would not have been wired to anything.
- **D3** `RaddSheet` tabbed body: replaced `AnimatedSwitcher` (which tears down the outgoing tab's
  subtree) with `IndexedStack` — all tab subtrees now stay alive, so switching tabs no longer
  resets scroll position on the subtitle/settings panels.
- **D4** Replaced hardcoded hex colors with tokens: `Color(0xFF12121E)` → `AppColors.background`
  in `eq_visualizer.dart` and `quick_settings_panel.dart`; `Color(0xFF1565C0)` → `AppColors.primary`
  (5 sites in `quick_settings_panel.dart`); `RaddLockPad`'s vault gradient's second stop
  (`0xFFE8002D`) → `AppColors.primary` (exact value match, zero visual change) — its purple first
  stop has no existing token so it stays a named local constant rather than being mismapped onto
  an unrelated one (checked: not the same value as `AppColors.simosaAccent`).
- **D5** Added `subtitle` and `iconColor` params to `SettingsRow` — renders a muted caption line
  below the label and tints the leading icon when set.
- **D6** Audited direct `PhosphorIcons.*` calls in `lib/screens/` and `lib/widgets/` (only
  `bottom_nav.dart` had any) and replaced them with `AppIcons.*`. Two of the five nav icons had no
  existing `AppIcons` equivalent that matched the actual glyph in use (`deviceMobile` for "Local",
  `downloadSimple` for "Download" — `AppIcons.downloads` uses the unrelated `arrowCircleDown`
  glyph), so added `AppIcons.localDevice`/`localDeviceFill` and `AppIcons.downloadActionFill`
  (paired with the pre-existing `downloadAction`) rather than swapping in a visually different icon.

**Next phase:** Phase E (Provider Architecture: God Provider Split).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- JS `String.replace`: escape `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

---

 as `$` when Dart code contains `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

---

 interpolation
- TEN_POINT_PLAN.md dead-code/audit findings (icon mappings, "matches exactly" claims, etc.) are
  not guaranteed accurate — re-grep/re-diff before trusting them, per the C3 and D4/D6 near-misses.

## Current State (2026-07-11 — Phase C Complete)

### PHASE-C — Player Screen Structural Fixes — 2026-07-11

All 4 Phase C items from `agent-hub/TEN_POINT_PLAN.md` addressed and pushed (C3 resolved as
"verified not dead" rather than a code change — see below).

**What was done:**
- **C1** `_openPanel()` helper: `player_screen.dart` had 7 near-identical panel openers
  (`_openSubtitlePanel`, `_openAudioPanel`, `_openZoomPanel`, `_openAudioEffectPanel`,
  `_openMoreMenu`, `_openSidebarCustomizer`, `_openSettingsPanel`), each repeating the same
  ~13-line landscape (`_openRightPanel`) vs portrait (`RaddSheet.show`) branch inline. Extracted
  to one `_openPanel({panel, title, widthFactor, maxHeightFraction})` method; all 7 now call it.
- **C2** Debounced `_savePrefs`: added `_scheduleSavePrefs()` (300ms `Timer`-based debounce) and
  switched all 53 non-dispose call sites from `_savePrefs()` to `_scheduleSavePrefs()`. Avoids a
  `SharedPreferences` disk write on every slider drag/toggle tap.
- **C3** Dead-variable audit: the plan flagged `_currentFramedrop` and `_labDialogueOnly` as dead.
  Re-verified with grep before touching anything — both are actively read/written (framedrop
  gates a real seek-flush in `_setSpeed`; dialogue-only drives a real audio-pan filter and is
  persisted to prefs). **No removal made** — the original plan finding did not hold up.
- **C4** `dispose()` still calls `_savePrefs()` directly (not the debounced version), now preceded
  by `_savePrefsDebounce?.cancel()` so no stray debounced write fires after teardown.

**Next phase:** Phase D (widget layer: duplicate RaddTextField, RepaintBoundary, RaddSheet IndexedStack).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- JS `String.replace`: escape `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

---

 as `$` when Dart code contains `# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

---

 interpolation
- TEN_POINT_PLAN.md dead-code findings are not guaranteed accurate — re-grep before deleting.

## Current State (2026-07-11 — Phase B Complete)

### PHASE-B — Database Performance — 2026-07-11

All 7 Phase B items from `agent-hub/TEN_POINT_PLAN.md` completed and pushed. CI run verifying.

**What was done:**
- **B1** N+1 → 1 query: Added `LocalDb.getEpisodesForIds(ids)` — single `IN (…)` query returns all episodes for all shows at once. `CatalogNotifier._loadFromDb` now calls this instead of one `getEpisodes(show.id)` per show. On a 200-show catalog startup DB round-trips drop from 201 → 2.
- **B2** `getTopFreeMovies` decode loop: Calls `DeviceIdentifier.getDeviceId()` once before the loop; `RequestEncoder.unscrambleUrl` is synchronous so each iteration is now pure CPU — no async waterfall per row.
- **B3** `getPendingUsageBytes`: Replaced Dart loop over all rows with `SELECT COALESCE(SUM(bytes), 0)` — one round-trip returns the aggregate directly from SQLite.
- **B4** Atomic sync transaction: Added `LocalDb.persistBatch(items)` which wraps the full title + episode batch in `db.transaction()`. `_persistItems` in `sync_service.dart` now delegates here. Partial syncs on power loss are now impossible — if any insert fails the transaction rolls back and the sync retries on next launch (M-17 timestamps are written after this call, so they're never committed for a failed batch).
- **B5** Missing indexes: Fresh installs gain `idx_episodes_file_id` and `idx_watch_positions_file_id` via `_createAll`. Upgraded devices get all four indexes (`idx_episodes_title`, `idx_titles_type`, `idx_episodes_file_id`, `idx_watch_positions_file_id`) via migration 22. `catalogDbVersion` bumped 21 → 22.
- **B6** FTS rebuild delay: `rebuildFtsIndex()` now awaits `Future.delayed(5s)` before executing so startup frame renders before the heavy `INSERT INTO catalog_fts VALUES('rebuild')` call.
- **B7** Sync retry: Added `_withRetry<T>(fn, attempts: 3)` with exponential back-off (2 s, 4 s). `CatalogApi.syncFull()` and `CatalogApi.syncDelta()` are now wrapped. Transient handoffs on Pakistani mobile networks no longer silently kill the full sync.

**Next phase:** Phase C (Player Screen: _openPanel helper, _savePrefs debounce, dead vars).

**Active rules (carry forward):**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition), ≥1.2 s apart
- JS `String.replace`: escape `$` as `$$` when Dart code contains `$` interpolation

## Current State (2026-07-11 — Phase A Complete)

### PHASE-A — Critical Bugs, Safety Nets, Quick Wins — 2026-07-11

All 9 Phase A items from `agent-hub/TEN_POINT_PLAN.md` completed and pushed. No CI breakage expected (all changes are isolated, no new imports to non-existent symbols). CI run should be verified after push.

**What was done:**
- **A1** `edit_profile_screen.dart`: Added `if (mounted)` guard in `_save()` catch block — prevents `setState() called after dispose()` crash when user navigates away mid-request.
- **A2** `lib/screens/layout_designer_screen.dart`: Deleted the dead duplicate (484 lines). Live copy remains at `lib/screens/player/layout_designer_screen.dart` (imported by `app.dart`). This duplicate has caused real bugs before (editing wrong file).
- **A3** `voice_commands_service.dart`: `requestPermission()` now returns `false` instead of lying with `true`. No real STT implementation exists; the app will correctly report voice commands as unavailable.
- **A4** `n_series_network.dart`: `NetworkSpeedMonitor.start()` no longer emits fabricated kbps values. `_kbps = 0` causes `format()` to return `'—'` — users no longer see fake Mbps numbers in the HUD.
- **A5** Session state leaks: Added `WatchlistNotifier.clear()` and `ProfileNotifier.reset()`. `AuthNotifier` now holds a `Ref` and calls all three providers' clear/reset methods in `logout()`. User A's watchlist and profile will no longer bleed into User B's session.
- **A6** `search_screen.dart`: Search debounce raised from 220ms to 400ms. Was firing on nearly every autocorrect keystroke.
- **A7** `RepaintBoundary` added to: `ParticleOverlay` (12s continuous animation loop), `EqVisualizer` (setState per animation tick), `AmbilightGlowBorder` (animated boxShadow). Critical on Snapdragon 400/600 target devices.
- **A8** Expensive `build()` computations cached: home_screen greeting cached in `_greetingTod` field (initState); search_screen `allItems` cached in `_cachedAllItems` (populated in `_loadFilterMeta`); profile_screen greeting cached in `_greetingTod` (initState).
- **A9** `home_screen.dart`: `ref.watch(catalogProvider)` replaced with a Dart-3 record select that only rebuilds on visible content count/status changes. `totalCount` increments during sync no longer trigger sliver-grid repaints.

**Next phase:** Phase B (DB Performance — N+1 catalog load, missing indexes, sync transaction).

**Key rules still in force:**
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race condition)
- JS `String.replace`: escape `$` as `$$` when Dart code contains `$`

## Current State (2026-07-11 — Full codebase audit + 10/10 master plan written)

### What was done
Full codebase audit + 10/10 master improvement plan written.

**Audit scope:** 22 parallel subagents read every .dart file in the codebase (67,988 lines total):
- `player_screen.dart` in 4 chunks (lines 1–9,458)
- All 25+ screens
- All providers (auth, catalog, connectivity, downloads, profile, subscription, watchlist, playerPrefs)
- All widgets (player/*, content_card, simosa_card, particle_overlay, etc.)
- All design_system components + token files
- All core/player/ series files (confirmed which are live vs dead code)
- All services (jazzdrive, vault, actor, subtitle_hunter, download, debug, security)
- `app.dart`, `main.dart`, `pubspec.yaml`, all models

**Output:** `agent-hub/TEN_POINT_PLAN.md` (43 KB) — 10 phases (A–K), ~80 discrete tasks,
each with exact file + line reference from actual code (no assumptions).

**Key findings confirmed from real code:**
- `VoiceCommandsService.requestPermission()` unconditionally returns `true` — never requests mic permission
- `n_series_network.dart` generates bandwidth figures from `Random()` — fake data shown to users
- 13 lettered series files (c/d/f/g/n/o/p/q/r/s/t/u/v) are NOT imported by player_screen.dart — dead code
- Dead duplicate: `lib/screens/layout_designer_screen.dart` (484 lines) — live copy is `screens/player/layout_designer_screen.dart`
- 3 session leaks: WatchlistNotifier, ProfileNotifier, PlayerPrefsNotifier not cleared on logout
- DB: no `db.transaction()` anywhere in sync_service._persistItems — partial sync corrupts DB
- DB: no index on episodes(title_id) — full table scan on every catalog load
- RaddSheet tab switching calls setState on whole sheet — not IndexedStack
- 4 animation packages (flutter_staggered_animations, animated_text_kit, animations, flutter_animate) — 3 redundant

### What's next
- **Start Phase A** of `agent-hub/TEN_POINT_PLAN.md` — all critical bug fixes, very low risk
- Last commit on CI: `72f93a8d` (landscape panels) — verify still green before starting edits
- Phase 1 HUD footprint measurement still blocked on real device/emulator (no Flutter SDK in Replit)

---

## Current State (2026-07-10 — Phase 6 READY TO BUILD, research complete)

### Phase 6 — Onboarding rebuild — research done, no code written yet

**Read this entire section before touching any file. All context is here — skip re-reading.**

**What to build:** Replace `lib/screens/onboarding_screen.dart` (generic `PageView` carousel)
with the Volume V 3-step reciprocity flow. Four files change total.

---

#### Files to change and exactly what to do in each

**1. `lib/core/constants.dart`** — add one constant:
```dart
static const String onboardingPendingItemsKey = 'jm_onboarding_pending_items';
```
(Put it alongside `onboardingSeenKey = 'jm_onboarding_seen'` in `AppConstants`.)

**2. `lib/screens/onboarding_screen.dart`** — full rewrite. Spec (Volume V §Onboarding):
- 3 steps: genres → content grid → summary. Progress bar: 25% / 60% / 100%.
  Progress **never starts at 0%** — step 0 opens at 25% (goal gradient effect).
- Step 0 headline: "What do you like to watch?" — genre chips from this exact list:
  `['Action', 'Drama', 'Comedy', 'Romance', 'Thriller', 'Anime', 'Urdu Dubbed', 'Kids', 'Sports', 'Horror']`
  Use `RaddChip` (already imported via design_system). Multi-select, no minimum.
- Step 1 headline: "Pick a few to start with" — 3-col `RaddCard` grid loaded from:
  `LocalDb.searchAdvanced(genre: firstSelectedGenre, limit: 18)` which returns
  `List<SearchResult>` where `SearchResult.item` is a `CatalogItem`. Show up to 18 items.
  If multiple genres selected, call `searchAdvanced` for each (max 3 genres, 6 items each)
  and deduplicate by `item.id`. Tap card = toggle selected; selected = filled border.
  Include data-free (⚡) indicator via `RaddCard(isDataFree: item.isFree)`.
- Step 2 headline: "Your watchlist is ready" — show up to 5 poster thumbnails of selected
  items + "+ N more" label if more. CTA button text: **"Save & Continue"** (NOT "Sign Up" —
  endowment effect per Volume V spec).
- `_finish()`: save selected item IDs to SharedPreferences as JSON int list under
  `AppConstants.onboardingPendingItemsKey`; set `onboardingSeenKey = true`; push login.
- Use `RaddMotion.sheetEnterDuration` / `RaddMotion.tuneDuration` for step transitions.
  Use `RaddSpace.*`, `RaddRadius.*`, `context.t.*` tokens throughout — no raw literals.
  Use `context.raddHeadline`, `context.raddTitle`, `context.raddBody` for text.

**3. `lib/screens/splash_screen.dart`** — routing fix. Currently when unauthenticated:
```dart
Navigator.of(context).pushReplacementNamed(AppRoutes.login);  // CURRENT
```
Change to:
```dart
final prefs = await SharedPreferences.getInstance();         // NEW
final seen = prefs.getBool(AppConstants.onboardingSeenKey) ?? false;
Navigator.of(context).pushReplacementNamed(
  seen ? AppRoutes.login : AppRoutes.onboarding,
);
```
`SharedPreferences` is already imported via `package:shared_preferences/shared_preferences.dart`
in `onboarding_screen.dart`; add the import to `splash_screen.dart`.
`AppConstants` and `AppRoutes` are already imported in `splash_screen.dart`.

**4. `lib/providers/profile_provider.dart`** — update `navigateAfterAuth` to sync pending
watchlist items after login. Current function (line 134):
```dart
Future<void> navigateAfterAuth(BuildContext context, WidgetRef ref) async {
  await ref.read(profileProvider.notifier).load();
  if (!context.mounted) return;
  final profiles = ref.read(profileProvider).profiles;
  if (profiles.length <= 1) {
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  } else {
    Navigator.of(context).pushReplacementNamed(AppRoutes.profileSwitcher);
  }
}
```
Add before the `Navigator.of(context).pushReplacementNamed(...)` call:
```dart
// Sync any watchlist items the user selected during onboarding (before login).
final prefs = await SharedPreferences.getInstance();
final pendingIds = prefs.getStringList(AppConstants.onboardingPendingItemsKey) ?? [];
if (pendingIds.isNotEmpty) {
  final idInts = pendingIds.map(int.tryParse).whereType<int>().toList();
  for (final id in idInts) {
    final item = await LocalDb.getItemById(id);  // see note below
    if (item != null) await LocalDb.addToWatchlist(item);
  }
  await prefs.remove(AppConstants.onboardingPendingItemsKey);
}
```
**NOTE on `LocalDb.getItemById`:** grep `local_db.dart` for a method that fetches a single
`CatalogItem` by id before writing this — it may be named `getById`, `fetchById`, or
similar. If no such method exists, query the titles table directly:
`final rows = await db.query('titles', where: 'id = ?', whereArgs: [id], limit: 1);`
and construct a `CatalogItem.fromJson(rows.first)`.

---

#### Key types / APIs confirmed from codebase reading

| Thing | Location | Notes |
|---|---|---|
| `SearchResult` | `local_db.dart:1836` | `final CatalogItem item; final String? snippet;` |
| `LocalDb.searchAdvanced(genre:, limit:)` | `local_db.dart:698` | Returns `List<SearchResult>` |
| `CatalogItem` fields | `models/catalog_item.dart` | `id`, `title`, `posterUrl`, `isFree`, `genres`, `mediaType` |
| `WatchlistNotifier.toggle(item)` | `providers/watchlist_provider.dart:54` | Optimistic add/remove; use after login |
| `LocalDb.addToWatchlist(item)` | `local_db.dart:1569` | Direct DB write; use in `navigateAfterAuth` sync |
| `AppConstants.onboardingSeenKey` | `core/constants.dart:10` | `'jm_onboarding_seen'` |
| `AppRoutes.onboarding` | `core/constants.dart:337` | `'/onboarding'` |
| `AppRoutes.login` | `core/constants.dart` | `'/login'` |
| `RaddChip` | `design_system/components/radd_chip.dart` | `active`, `onTap`, `label`, `isDataFreeVariant` |
| `RaddCard` | `design_system/components/radd_card.dart` | `variant`, `imageUrl`, `title`, `isDataFree`, `onTap` |

#### Critical discovery: onboarding is currently an orphaned route
`onboardingSeenKey` is SET in `onboarding_screen.dart._finish()` but **never read by any
routing logic** — the existing onboarding is never triggered from the normal auth flow.
The routing fix in `splash_screen.dart` (item 3 above) is what wires it in for new users.

#### Commit order (Rule 42 — one logical change per commit)
1. `constants.dart` — add `onboardingPendingItemsKey`
2. `onboarding_screen.dart` — full rewrite
3. `splash_screen.dart` — routing fix
4. `profile_provider.dart` — navigateAfterAuth sync

All 4 are Flutter files → verify `build-apk.yml` CI green after each push (Rule 46).

---

## Current State (2026-07-10 — Phase 7 COMPLETE, Phase 6 next)

### Phases 1 (partial) + 7 — complete — 2026-07-10

**Phase 7 (final audit) is complete.** All §4 grep queries re-run; dashboard updated in-place
in `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md §1`. Overall readiness: **~25–30%** (was ~15–20%).

**Design debt delta (key numbers):**
- `Colors.*`: 2,563 → 2,305 (−258, −10.1%)
- `AppColors.*`: 603 → 524 (−79, −13.1%)
- `Color(0x...)`: 372 → 325 (−47, −12.6%)
- `RaddSpace` in screens: 0 → 265 new usages
- `RaddRadius` in screens: 0 → 67 new usages
- `RaddSheet`/`RaddLockPad`/`RaddTextField` now have real adoption (14/6/10 usages)
- `RaddButton`, `RaddCard`, `RaddChip`, `RaddBanner`, `SettingsRow`: still 0 in screens

**Phases complete:** 2, 3, 4, 5, 7 ✅. Phase 1 mostly done (one live-device item open).

**Next:** Phase 6 — onboarding rebuild. Replacing the generic `PageView` carousel with the
Volume V 3-step reciprocity flow (genre taste → starter watchlist → save/signup, progress bar
opens at ~25%). This is a new feature build, not a migration. Before starting, the agent
should confirm: (a) what API provides genre/content data for the taste-capture step, and
(b) where `onboarding_screen.dart` is routed from (what triggers onboarding vs. going straight
to home for returning users).

**Workflow reminders:** `log_pending.sh` → edit → `auto_commit.sh` per code file. After any
push touching `raddflix_flutter/**`, verify `build-apk.yml` CI is green (Rule 40/46).

---

## Current State (2026-07-10 — Phase 1 IN PROGRESS)

### UI-UX-MIGRATION — Phase 1 partially complete — 2026-07-10

**Two of three Phase 1 items done; one still needs live device.**

**Item 2 — RaddMotion duration tokens (DONE, commits `d3d793c` + `730d47d`, CI pending):**
- Added all missing duration constants to `radd_motion.dart` from Volume III §table:
  `tuneDuration` (200ms), `sheetEnterDuration` (260ms), `sheetExitDuration` (200ms),
  `cardPressDown` (120ms), `cardPressUp` (160ms), `heroDuration` (320ms),
  `railItemDuration` (240ms), `railItemDelay` (40ms), `lockKeyDuration` (220ms),
  `bottomNavDuration` (180ms), `emptyStateDelay` (400ms).
- Fixed two wrong curves: `sheetEnter` → `Cubic(0.16, 1.0, 0.3, 1.0)` (was `easeOutCubic`);
  `sheetExit` → `Cubic(0.4, 0.0, 1.0, 1.0)` (was `easeInCubic`).
- Updated `RaddSheet` (tuneDuration) and `RaddCard` (cardPressDown) to consume spec constants.

**Item 3 — Accessibility code-fixable subset (DONE, commit `730d47d`, CI pending):**
- `RaddSheet` close button: added `Semantics(label: 'Close $title', button: true)`.
- `RaddSheet`: added `FocusScope` focus trap + `SemanticsService.announce` on open.
- Pre-existing coverage confirmed: `RaddBanner`, `RaddButton`, `RaddCard` already compliant.
- Still open: TalkBack focus-order audit, `_RaddIconBtn` touch-target check, caption defaults.

**Item 1 — HUD footprint (static analysis complete, live device still needed):**
- Center third ✅ clear; auto-hide ✅ 3s. Transport has 3 extras (Lock/Immersive/Settings) vs
  spec's single "⋯ More". Panel heights (62% + 90%) exceed 40% spec — needs PM decision.
- Full details in `agent-hub/UI_UX_MIGRATION_PLAN.md` Phase 1.

**Code-review fixes (after initial push):** `9b8d2a6` and `1ac96b8` pushed to address two
review findings: (a) close button switched from `GestureDetector` + manual `Semantics` to
native `IconButton` with `tooltip` (48×48 target, inherent focus); (b) motion-token consistency
sweep across `RaddButton`, `RaddChip`, `RaddLockPad` — all raw Duration literals now replaced.
`RaddLockPad` key duration corrected from 120ms → 220ms (`lockKeyDuration`, spec-exact).

**CI status:** `d3d793c` + `730d47d` confirmed ✅ green. `9b8d2a6` + `1ac96b8` in-progress as
of 2026-07-10; verify green before next Flutter-touching work (Rule 46).

**Next:** confirm CI green on `9b8d2a6`/`1ac96b8` → finish Phase 1 item 1 live measurement →
then Phase 6 (onboarding rebuild, currently blocked pending Phase 3 production validation per
plan file).

**Workflow reminders:** `log_pending.sh` → edit → `auto_commit.sh` per code file (sequential,
no batching, no local `git commit`/`push` — see `agent-hub/RULES.md` Rule 42). After any
push touching `raddflix_flutter/**`, verify the `build-apk.yml` CI run is green before
marking work done (Rule 40/46).

---

## Current State (2026-07-09 — Phases 2–5 COMPLETE)

### UI-UX-MIGRATION — Phase 5 complete — 2026-07-09

**Start here if you're a fresh agent/account picking this up:** read `AGENT_PROMPT.md` →
this section → `agent-hub/UI_UX_MIGRATION_PLAN.md`, then do the first unchecked checkbox in the
earliest open phase of that plan file. The plan file is the single source of truth for
progress — this section just orients you.

Executing the `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` roadmap phase-by-phase. **Phases 2,
3, 4, and 5 are now ✅ COMPLETE with CI confirmed green. Next open phase is Phase 6
(onboarding rebuild), which is blocked pending Phase 3 production validation per the plan file
— check `agent-hub/UI_UX_MIGRATION_PLAN.md` Phase 1 for any open investigation items first.**

**Phase 4 summary** (player_screen.dart, 9,280 lines — all CI green):
- Color pass (`d91cfd8`): `Colors.orange`→`AppColors.orange` (15), `Color(0xFF00A651)`→`AppColors.jazzGreen` (2). `Colors.white*/black*/amber/redAccent` kept (intentional video-overlay / no exact token).
- Radius pass (`164aca4`): added `radd_radius.dart`. `BorderRadius.circular(8/12/16)` → `RaddRadius.smRadius/mdRadius/lgRadius` (25 replacements). Values 5/6/7/10/14/20/22/24/40 kept.
- Spacing pass (`969e0c3`): added `radd_space.dart`. SizedBox/EdgeInsets.all(4/8/16/24/32) → `RaddSpace.xs/sm/md/lg/xl` (81 replacements). Type tokens deferred (player sizes 10/11/14/20px outside RaddType scale).
- HUD check: auto-hide ✅ (3s, Volume X). 40% surface: pre-existing violation in `_openRightPanel` (62% initial height) + RaddSheet calls (90%); needs Phase 1 live measurement to resolve.

**Phase 5 complete** (all remaining large screens, highest-literal-count first): show_detail →
local_folder → subscription → home → local_media → search → profile → downloads →
vault_screen/vault_settings/season_folder/edit_profile/add_edit_profile/profile_switcher/
tid_status/admin_queue/actor/plan_expired/quota_full/layout_designer/player_settings. See
`agent-hub/TASKS.md` (rows V1–V12) and `agent-hub/UI_UX_MIGRATION_PLAN.md` Phase 5 for the
full commit list and kept/off-scale rationale per file. Also fixed a pre-existing CI break
(from an earlier commit, not this pass) in `player_settings_screen.dart`,
`layout_designer_screen.dart`, and `profile_switcher_screen.dart` — see commit `64ec457`.
Confirmed `screens/player/layout_designer_screen.dart` is the live copy (imported by
`app.dart`); `screens/layout_designer_screen.dart` is dead/unreferenced code, left untouched.

**Next unchecked item:** first `[ ]` in Phase 1 (investigation gaps) of
`agent-hub/UI_UX_MIGRATION_PLAN.md` — Phase 6 (onboarding rebuild) is blocked on Phase 3
production validation, so Phase 1's open items are the next actionable work.

**Workflow reminders:** `log_pending.sh` → edit → `auto_commit.sh` per code file (sequential,
no batching, no local `git commit`/`push` — see `agent-hub/RULES.md` Rule 42). After any
push touching `raddflix_flutter/**`, verify the `build-apk.yml` CI run is green before
marking work done (Rule 40/46).

---

## Current State (2026-07-09 — MIGRATION-BLUEPRINT-2026-07-09 Complete)

### MIGRATION-BLUEPRINT-2026-07-09 — Design System Migration Blueprint — 2026-07-09

Follow-on to the same-day UI/UX audit, requested after external review feedback asked for a screen-by-screen compliance matrix, token mapping table, design-debt inventory, journey/heuristic review, and a phased execution plan rather than another descriptive audit.

Produced `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` (new file, does not modify the earlier audit report). Contents:
- Release Readiness Dashboard — overall estimate ~15–20% (tokens/components exist and are spec-correct but have ~0–2% adoption at call sites).
- 33-screen compliance matrix with per-file `AppColors`/`Color()`/`Colors.*`/`Radd*` counts and an evidence-based visual-match %.
- Before/after token mapping tables for colors, radius, spacing, typography, and motion.
- Design-debt inventory table with counts per category (2,563 raw `Colors.*`, 603 `AppColors.*`, 372 raw `Color()`, 963 raw `EdgeInsets.*`, 94 raw `TextStyle(`, 197 raw `Duration(milliseconds..)`, 92 raw `Curves.*`, ~200+ raw `BorderRadius.circular()`).
- 12 user-journey reviews (onboarding, auth, home→browsing, search→details, details→player, player, downloads→player, library, settings, subscription, profile).
- UX heuristic evaluation — explicitly flags which heuristics (accessibility, discoverability, feedback/error handling, responsiveness-at-breakpoints) were NOT measurable from static code and need a dedicated pass.
- Dedicated player-experience section (9,280-line file, only screen with real component adoption, also largest raw-literal surface in the app).
- 8-phase roadmap: Phase 0 (unblock — get Flutter SDK/tests running, none available in this environment), Phase 1 (fill heuristic gaps), Phase 2 (RaddLockPad + card-duplication consolidation, lowest risk), Phase 3 (auth + small screens, establishes pattern), Phase 4 (player, isolated), Phase 5 (remaining large screens), Phase 6 (onboarding rebuild — it's a missing *flow*, not a styling gap), Phase 7 (re-audit against same grep queries to prove readiness moved).
- Component migration plan (which screens should adopt each of the 8 `Radd*` components) and a per-screen visual-consistency checklist for use as Definition-of-Done during migration.
- Beyond-spec modernization ideas listed but explicitly kept out of migration scope (hero motion, skeleton shimmer, wider `RaddSignalNumeral` use, TV/foldable, AI discovery).

**Key structural finding surfaced by this pass:** `RaddColors` (the `BuildContext` extension used by new code) reads directly from `AppColors` under the hood (`lib/core/theme/radd_colors.dart`) — they are not two competing value systems. Most color migration is therefore a mechanical call-site swap (same value, different accessor), not a value-reconciliation exercise. This should make Phase 3/5 color migration meaningfully faster than the parallel-systems framing in the original audit implied.

Also newly confirmed: `RaddSpace`, `RaddRadius`, `RaddType`, `RaddMotion`, and `RaddLockPad` all have **zero** direct call sites anywhere in `lib/screens` or `lib/widgets` — the token layer is fully built and spec-correct but fully unconsumed outside `lib/design_system/` itself.

Docs only — no app code changed. All figures in the blueprint are grep-verified against the current source tree, not estimated.

**Open items surfaced by this blueprint (not yet scoped as individually tracked tasks):**
- Phase 0 (Flutter SDK/build tooling to actually compile and test the `Radd*` components) has no owner yet — recommended as the literal first step before any migration work begins.
- Motion tokens (`RaddMotion`) currently define curves only, no durations — a token-layer gap, not just an adoption gap; needs a design decision before Duration literals can be migrated.
- Two screens (Subscription, Profile) have no Volume V wireframe to migrate toward — flagged for design to produce one.

---

## Current State (2026-07-09 — UI-UX-AUDIT-2026-07-09 Complete)

### UI-UX-AUDIT-2026-07-09 — Full UI/UX & design-system audit — 2026-07-09

Produced `docs/AUDIT_UI_UX_REPORT.md`: a full audit of `raddflix_flutter` against `docs/design-system/`. Docs only — no app code changed.

**Headline finding:** the token layer (`RaddSpace`/`RaddRadius`/`RaddType`/`RaddElevation`/`RaddMotion`/semantic colors) is 100% spec-compliant, and all 8 shared components (`RaddButton`, `RaddCard`, `RaddSheet`, `RaddBanner`, `RaddTextField`, `RaddChip`, `RaddLockPad`, `SettingsRow`) are built — but adoption is effectively zero: `RaddButton`/`RaddCard` have **0** usages anywhere in `lib/screens`+`lib/widgets`, `RaddSheet` has 1 (inside `player_screen.dart`), `RaddTextField` has 3 (login/register). 31 of 33 screens are still on the legacy `AppColors`/`AppRadius` system or raw literals (410 hardcoded `Color()`, 2,563 `Colors.*` across screens+widgets combined; 38 files still reference `AppColors.*` directly).

Report includes: per-category scorecard (/100), design-system compliance table, 33-row screen-by-screen table, component audit (incl. duplicate `content_card.dart`/`simosa_card.dart`, 3 separate badge classes, duplicate `layout_designer_screen.dart`), UX/visual audit, gap-analysis table, prioritized roadmap (Critical/High/Medium/Low/Future), missing-features list, top-20 highest-impact improvements, final verdict.

**Reconfirms from PLAYER-DOCS-CORRECTION session:** ~47 files in `lib/widgets/player/` remain confirmed dead code; live player is 7 inline panel classes in `player_screen.dart` + 2 external sheets.

**Open items surfaced by this audit (not yet scoped as tasks):**
- Component layer has never been compiled/tested (no Flutter SDK in this environment) — recommended as the critical blocking item before any screen migration work consumes these components.
- Player HUD violates documented "40% surface"/"5-control" rules (previously known, reconfirmed).
- "Browse-before-signup" onboarding flow specified in design docs is missing app-wide.

---

## Current State (2026-07-08 — PLAYER-CONSOLIDATION Complete)

### PLAYER-CONSOLIDATION — ALL 7 PANELS DONE — 2026-07-08

All 7 inline player panel classes in `player_screen.dart` now open via `RaddSheet.show()`.

**Steps 1–3** (commits `d9da81f`, `dae6c3c`, `663f475`):
- `_VideoZoomPanel` removed; `_openZoomPanel` → `RaddSheet.show`
- `_AudioTrackPanel` header stripped; `_openAudioPanel` → `RaddSheet.show`
- `_QuickShortcutsPanel` header stripped; `_openMoreMenu` → `RaddSheet.show`

**Steps 4–7** (commit `777df5a`):
- `_SubtitlePanel`, `_AudioEffectPanel`, `_SettingsPanel`, `_SidebarCustomizerPanel` — title row + back-button stripped from each `build()`; internal tab bars preserved.
- All 4 matching call sites converted from `_openRightPanel(Panel(...))` to `RaddSheet.show(style: list, title: '...', maxHeightFraction: 0.90, listBuilder: (_) => Panel(...))`.
- `_openRightPanel()` now has zero callers in the main player flow (legacy landscape path intact).
- Bounded-height: confirmed safe — RaddSheet's `ConstrainedBox(maxHeight: 0.85×screen)` gives `Flexible` a finite budget; inner `Column(mainAxisSize.max)` fills it; `Expanded` children (EQ sliders, ListViews, `ReorderableListView`) resolve correctly.

**CI check (Rule 46):** Run `28964526692` triggered on commit `777df5a` — check conclusion before next Flutter-touching work.

**Open items (not this task):**
- ⚠️ Flask `/me` endpoint needs `is_admin` field — requires Oracle approval before touching production.
- ⚠️ C5: TTS install hint in dub panel — deferred.

---

## Current State (2026-07-08 — Q1 Docs Correctness Pass + Oracle Re-sync)

### Q1 — Docs correctness pass — 2026-07-08 (latest)
Docs-only, no app code changed. Triggered by a full re-verification session that found real gaps.

**Bug caught: Oracle was 1 commit behind `main`.** After the O1/O2/O3 deploy earlier in the day, two
more commits landed on `main` (the P1 build-fix + its docs) but nobody redeployed Oracle afterward.
Fixed by re-running `push_to_oracle.sh` against final HEAD; confirmed via SSH that Oracle's
`git rev-parse HEAD` now matches GitHub `main` exactly, then live-smoke-tested O1 (malformed param →
400), O2 (poster-push stop → 401 without auth), and O3 (bad OTP → clean 400) directly against the
running server, not just via code inspection.

**Also caught while verifying:** a wrong-path false negative — grepping `hub/app.py` on Oracle
returned nothing because there's a dead, unused `hub/` directory at the repo root (mirrored onto the
Oracle checkout too) separate from the real `radd-hub/hub/` that the `raddflix_radd` service actually
runs (confirmed via the supervisor config's `directory=` line). Re-ran the checks against the correct
path and got clean matches.

**Doc fixes made (`AGENT_PROMPT.md`, `agent-hub/RULES.md`, `.agents/PROJECT_RULES.md`):**
- Reconciled a real contradiction: `AGENT_PROMPT.md` told agents to "commit/push with normal git
  commands," while `RULES.md`/`PROJECT_RULES.md` said "no git commands, ever." Clarified: read-only
  local git (`status`/`log`/`diff`/`rev-parse`) is fine and expected for self-checks; the actual push
  to `main` always goes through `auto_commit.sh` (GitHub Trees API) — never a raw `git push`.
- Added Rule 43 (`kDebugMode` requires an explicit `foundation.dart` import — gating alone isn't
  enough, this already broke 2 CI builds).
- Added Rule 44 (Oracle does not auto-deploy; redeploy against final session HEAD, not a mid-session
  snapshot, and verify the SHA matches afterward).
- Added Rule 45 (dead `hub/` dir at repo root vs. real `radd-hub/hub/` — also trips up Oracle SSH
  checks, not just GitHub template pushes as the older Rule 39 implied).
- Added Rule 46 (a successful push/workflow trigger ≠ a successful build — always check the GitHub
  Actions run `conclusion` field before considering Flutter work done).

---

## Current State (2026-07-08 — P1 APK Build Break Fix + Deploy Verification)

### P1 — APK build break fix (N1 regression) — 2026-07-08
Commit: `8fd8fdf` → `player_screen.dart`, `subscription_screen.dart`.

The N1 session (2026-07-07) gated bare `debugPrint()` calls with `if (kDebugMode)` in 4 files, but only 2 of them (`profile_screen.dart`, `word_dict.dart`) already imported `package:flutter/foundation.dart`. `player_screen.dart` and `subscription_screen.dart` did not — `kDebugMode` was an undefined getter, causing `Target kernel_snapshot failed: Exception` and failing the release build. This broke the last 2 push-triggered GitHub Actions APK builds (`28886249595`, `28886554849`) without being noticed, since nobody checked CI run status after those pushes.

Fixed by adding `import 'package:flutter/foundation.dart' show kDebugMode;` to both files. Verified fix by triggering a fresh workflow run (`28935996207`) — completed successfully, produced `RaddFlix-1.0.0+3-build1488.apk` (58.4 MB).

**Full deploy verification this session:**
- GitHub: latest commit `8fd8fdf` confirmed live on `main`.
- Oracle (92.4.95.252): pulled latest, restarted `raddflix_radd` service, `/api/app/version` responding `{"ok":true,"version":"1.0.0"}`.
- APK: GitHub Actions build succeeded, artifact `RaddFlix-1.0.0+3-build1488.apk` available.

---

## Current State (2026-07-07 — O1/O2/O3 Flask Security Audit + Fixes)

### Flask Route Security Audit — COMPLETE — 2026-07-07

**Audit coverage:**
- All `request.json['key']` hard-subscripts → 0 found; every route uses `get_json(silent=True) or {}` ✅
- f-string SQL injection → all safe: `{order}` only "DESC"/"ASC", `sort_clause` uses `_SORT_MAP`, `{name}` validated vs `ALL_TABLES`, `{tbl}` from hardcoded `RESET_TABLES` ✅
- SSRF → `brand_studio.py` fetches GitHub API with hardcoded `_GITHUB_API`/`_GITHUB_REPO` URL templates ✅
- Open redirects → `subscriptions.py` uses `url_for` only ✅
- DB editor (admin) uses user-supplied column names but is `@auth.login_required`-gated — intentional risk ✅
- File uploads → `upload.py` uses `secure_filename`, configurable `max_size_gb` ✅
- Login rate limiting → `_login_rate_check()` DB-backed per-IP, sliding 15-min window ✅
- CSRF → all admin routes use HTTP Basic Auth (`@auth.login_required`), not sessions — CSRF inapplicable ✅
- Intentionally public (documented): `/ping`, `/config`, `/queue/status`, `/poster-push/status`, `/poster-push/job/<job_id>` (read-only polling)

**Three bugs fixed:**

### O1 — Flask ValueError → 400 — 2026-07-07
Commit: `a2943fd` → `radd-hub/hub/app.py`.

All 35 `int(request.args.get())` calls would raise `ValueError` on malformed params, bubbling as 500. Added global `@app.errorhandler(ValueError)` returning 400 with JSON body.

### O2 — poster-push stop auth — 2026-07-07
Commit: `20765be` → `radd-hub/hub/routes/catalog_api.py`.

`POST /api/catalog/poster-push/job/<job_id>/stop` had no auth guard despite docstring saying "admin auth required". Job IDs are Unix timestamps (guessable) — any caller could cancel running poster upload jobs. Added `if not _check_admin_auth(): return 401`.

### O3 — OTP brute-force guard — 2026-07-07
Commit: `bcbd41f` → `radd-hub/hub/routes/mobile_api.py`.

`POST /api/auth/device-switch/verify` had no attempt counter. A 6-digit OTP with 10-minute validity (600 s) left 1,000,000 combinations open to brute-force — wrong guesses did not consume the OTP. Added `_otp_attempts` dict (in-memory, phone-keyed): 5 wrong guesses burns the OTP record from DB and returns 429, forcing the user to re-request. Correct guess clears the counter. Matches `_login_ip_window` pattern already present for login rate-limiting.

---

## Current State (2026-07-07 — M1/M2 Template Rule-38 + N1/N2 Debug Rule-21 Fixes)

### M1 — Flask Templates confirm()/prompt() Elimination — 2026-07-07
Commit: `fb6992f` → 9 templates.

**What changed:**
- Rule 38 bans `confirm()`/`prompt()` in Flask templates (Cloudflare blocks them).
- Found 20 call sites across 9 templates: `admin.html`, `scan.html`, `library.html`, `bots.html`, `db_mgmt.html`, `home.html`, `stream.html`, `proxy_pool_page.html`, `_proxy_pool_panel.html`.
- All 20 replaced with the arm+fire toast pattern: first click warns ("⚠ ... click again to confirm"), second click within 4s fires the action. Arms tracked via `window._armed*` flags with `setTimeout` auto-clear.

### M2 — upload.html confirm() Elimination — 2026-07-07
Commit: `1ddbceb` → `upload.html`.

**What changed:**
- Two `confirm()` calls missed in M1: `deleteFlixAccount()` and `deleteAccountById()`.
- Both replaced with arm+fire toast pattern matching scan.html style.
- `deleteAccountById` uses per-id arm key (`_armedDelAcct_${id}`) so multiple rows can be armed independently.

### N1 — Profile Screen Escaped-Dollar Bug + kDebugMode Gating — 2026-07-07
Commit: `49a3b8e` → `profile_screen.dart`, `subscription_screen.dart`, `word_dict.dart`, `player_screen.dart`.

**What changed:**
- `profile_screen.dart`: `'v\${info.version}'` and `'\$e'` escape sequences (same class as L1 audio-label bug) — `_appVersion` showed the literal string `v${info.version}` in the UI; error catch blocks printed literal `$e`. Fixed: remove backslashes.
- All 6 bare `debugPrint()`/`print()` calls in these 4 files now gated by `if (kDebugMode)` (Rule 21 — stripped from release APK).
- `player_screen.dart` AudioLab logging (`_applyAllAf` success/error) gated.
- `word_dict.dart` saved-words error logging gated.
- `subscription_screen.dart` payment-methods error logging gated.

### N2 — local_db + subtitle_dubber bare print() Gating — 2026-07-07
Commit: `db54b45` → `local_db.dart`, `subtitle_dubber.dart`.

**What changed:**
- Two intentional `print()` calls (had `// ignore: avoid_print` comments) gated with `if (kDebugMode)`.
- Added `import 'package:flutter/foundation.dart' show kDebugMode;` to both files (neither previously imported `foundation.dart`).
- `print()` calls preserved in-place with `// ignore: avoid_print` comment kept on same line.

### Summary: All Rule 38 + Rule 21 violations resolved
- **Rule 38 (confirm/prompt):** 22 call sites across 10 templates — 100% eliminated.
- **Rule 21 (bare debug calls):** 9 bare calls across 6 files — 100% gated.
- No unresolved bugs found in async-setState audit, Timer disposal audit, hard-cast audit, or escaped-dollar sweep.

---

## Current State (2026-07-07 — L6 MPV Startup Restore)

### L6 — MPV Startup Restore — 2026-07-07 (latest)
Commit: `16de119` → `player_screen.dart`.

**What changed:**
- `_loadPrefs` correctly restored `_subSpeed` and `_videoRotation` from SharedPreferences into Dart state, but never pushed those values to MPV. On every app restart the UI showed the saved subtitle speed / rotation, but MPV ran at `sub-speed=1.0` and `video-rotate=0` — the user had to manually touch the control once to resync MPV to the visible setting.
- Fixed: added guarded `setProperty` calls after the existing speed restore block — `_np.setProperty('sub-speed', ...)` when `_subSpeed != 1.0`, and `_np.setProperty('video-rotate', ...)` when `_videoRotation != 0`. Both wrapped in `try/catch` so a cold-start before the player is ready doesn't crash.
- `_zoomMode` verified Flutter-only (`BoxFit` switch on the `Video` widget) — no MPV property needed, already correct.

---

## Current State (2026-07-07 — L4/L5 Sync Reset + SubSpeed + SavePrefs Gaps)

### L5 — ZoomMode Save Gap — 2026-07-07 (latest)
Commit: pending → `player_screen.dart`.

**What changed:**
- `_openZoomPanel` callback: `setState(() => _zoomMode = mode)` was called but `_savePrefs()` was never called after. Zoom mode preference (fit / fill / stretch / custom pinch) was lost on every app restart — MPV reverted to default fit. Added `_savePrefs()` immediately after the setState.

### L4 — Sync Reset + SubSpeed Persistence + SavePrefs Gaps — 2026-07-07
Commit: `68562849`.

**What changed (`player_screen.dart`):**

**1. Sub/Audio sync bleed between episodes:**
`_subSync` and `_audioSync` were never reset in `_playEpisodeAt`. MPV's `sub-delay` and `audio-delay` properties persist across `loadfile` calls — so episode N+1 inherited episode N's manual sync offset, which immediately desynced it. Fixed:
- Dart reset block: `_subSync = 0.0; _audioSync = 0.0; _subSpeed = 1.0`
- MPV reset block: `setProperty('sub-delay','0')`, `setProperty('audio-delay','0')`, `setProperty('sub-speed','1')`

**2. `_subSpeed` not persisted:**
Subtitle speed (0.5–2.0×) had no `pref_sub_speed` key in `_loadPrefs`/`_savePrefs` — reset to 1.0 on every restart. Added `pref_sub_speed` key to both. Added `_savePrefs()` call to `onSpeedChanged` callback in `_openSubtitlePanel` (which was also missing it).

**3. `_showRemainingTime` seek-bar tap not saved:**
The GestureDetector on the duration label toggled `_showRemainingTime` via `setState` but never called `_savePrefs()`. Added `_savePrefs()`.

**4. Settings panel missing `_savePrefs()` calls:**
Four callbacks in `_openSettingsPanel` only did `setState` — value was written to disk only on `dispose()`, meaning it was lost on force-kill:
- `onShowRemainingChanged` → added `_savePrefs()`
- `onKeepScreenChanged` → added `_savePrefs()`
- `onSkipIntervalChanged` → added `_savePrefs()`
- `onSeekSwipeSpeedChanged` → added `_savePrefs()`

**SharedPreferences key added:** `pref_sub_speed`

## Current State (2026-07-07 — L3 Audio Carry-Over + Language Preference)

### L3 — BUG-AUDIO-CARRY-01 + Language Preference Persistence — 2026-07-07 (latest)
Commit: `b896632`.

**What changed (`player_screen.dart`):**

- **BUG-AUDIO-CARRY-01 — Audio track carries over to next episode**: The `_playEpisodeAt` episode-change block already reset subtitle track state (`_selectedSubtitle = null`, `_selectedSecondSub = null`, MPV `sid → auto`, `secondary-sid → no`) as BUG-SUB-CARRY-01 fix. But `_selectedAudio` was never cleared and `aid` was never reset to `auto`. On episode N the user might have audio track #2 (Urdu). Episode N+1 has a different layout where track #2 is English — MPV re-applied `aid=2` and picked the wrong language silently. Fixed: added `_selectedAudio = null` to the Dart reset block and `_np.setProperty('aid', 'auto')` to the MPV property reset block.

- **Language preference not persisted**: When a user explicitly picked "English" audio or subtitles in the panel, that preference was lost every episode change (reset to MPV auto) and on app restart. There was no mechanism to re-apply it. Fixed with two new state vars:
  - `String? _prefSubLang` — preferred subtitle language code; `null` = let MPV auto-select
  - `String? _prefAudioLang` — preferred audio language code; `null` = let MPV auto-select
  - Saved to `pref_sub_lang` / `pref_audio_lang` in `_savePrefs`, loaded in `_loadPrefs`
  - Updated in `onSubtitleTrackSelected` / `onTrackSelected` callbacks when user picks a track with a non-empty `language` field (selecting "None" does not update the preference)
  - Re-applied in `stream.tracks.listen` via `Future.microtask` — after each new file's track list arrives, finds first matching-language track and selects it; falls back silently if no match (MPV's own auto-selection unchanged)
  - Added `_savePrefs()` call to both panel callbacks — neither previously called `_savePrefs()` at all, so the track selection wasn't triggering a prefs write

**SharedPreferences keys added:** `pref_sub_lang`, `pref_audio_lang`

## Current State (2026-07-07 — L2 Portrait Volume Fix + SW Decoder Persistence)

### L2 — Portrait Volume Indicator + SW Decoder Persistence — 2026-07-07 (latest)
Commit: `bb324c1`.

**What changed (`player_screen.dart`):**
- **Bug 1 — Portrait volume indicator on wrong side**: In `_buildPortraitLayout`, both the brightness indicator and the volume indicator were `Positioned(left: 20, ...)`. The gesture system correctly assigns brightness to left-half swipes and volume to right-half swipes (`_dragIntent = isLeftSide ? 'brightness' : 'volume'`), but both indicators rendered on the left — so they always overlapped, and the volume indicator appeared on the side where the user wasn't swiping. Fixed: volume indicator in portrait changed to `Positioned(right: 20, ...)`. Note: the landscape layout intentionally keeps volume also on the left (sidebar on the right leaves no room), so only the portrait copy was changed.
- **Bug 2 — SW decoder toggle not persisted**: `_useSWDecoder` (the manual software-decoder toggle in the Audio Track panel, used for EAC-3/DTS fallback) lived in `_PlayerScreenState` but was never written to or read from SharedPreferences — it always started `false`. If a user manually enabled SW decode for a problematic codec, it would reset on every app restart. Fixed: added `pref_sw_dec` to both `_loadPrefs` and `_savePrefs`.

**Panel persistence audit result**: Full audit confirms all other player panels (EQ/10-band, EQ enabled, reverb preset, channel mode, speed, all Audio Lab toggles, silence-skip, silence threshold, sidebar order) are state vars in main `_PlayerScreenState` and ARE correctly saved/loaded via `_savePrefs()`/`_loadPrefs()`. No other panel-level state leak exists.

**SharedPreferences key added:** `pref_sw_dec`.

## Current State (2026-07-07 — L1 Audio Panel + Subtitle Style Persistence)

### L1 — Audio Panel Interpolation + Subtitle Style Persistence — 2026-07-07 (latest)
Commit: `7d2c77e`.

**What changed (`player_screen.dart`):**
- **Bug 1 — Audio track labels showing literal template strings**: Lines 8638-8639 used double-quoted strings with escaped `\${}` (e.g. `"\${widget.tracks[i].language}"`) which Dart renders as literal text, not interpolated values. Fixed to single-quoted proper Dart interpolation. Audio track names now display correctly — this also resolves the "no audio" issue (users were accidentally selecting "Disable" because all track names appeared as garbled template strings).
- **Bug 2 — Subtitle style/position settings never persisted**: `_SubtitlePanelState` had 11 style/position state vars (`_subFontIdx`, `_subSize`, `_subBold`, `_subColor`, `_subBgColor`, `_subOpacity`, `_subShadowIdx`, `_subAlignX`, `_subAlignY`, `_subEdgePadding`, `_subFitToVideo`) initialised to hardcoded defaults and never saved. Every time the subtitle panel was opened (new widget instance), all settings reset to defaults even if the user had customised them. Fixed: added `_loadSubPrefs()` + `_saveSubPrefs()` methods to `_SubtitlePanelState`. `_loadSubPrefs()` is called via `addPostFrameCallback` in `initState` — it reads all 11 vars from SharedPreferences, does a `setState`, then re-applies every value to MPV (so live video immediately matches saved prefs). `_saveSubPrefs()` is called from all 13 `onChanged` handler sites: font chip tap, size slider, bold switch, opacity slider, text-color pick, bg-color pick, shadow style selector (inside `_applyShadow`), horizontal align, vertical position, bottom-margin slider, edge-padding slider, fit-to-video switch.

**SharedPreferences keys added:** `pref_sub_font_idx`, `pref_sub_size`, `pref_sub_bold`, `pref_sub_color`, `pref_sub_bg_color`, `pref_sub_opacity`, `pref_sub_shadow`, `pref_sub_align_x`, `pref_sub_align_y`, `pref_sub_edge_pad`, `pref_sub_fit`.

## Current State (2026-07-07 — J1 Player Bug Fixes)

### J1 — 5 Player Bug Fixes — 2026-07-07 (latest)
Commit: `cd75b25`.

**What changed (`player_screen.dart`):**
- **Bug 1 — Silence skip `_silenceInPipeline` not restored**: `_silenceSkipEnabled` was loaded from prefs but `_silenceInPipeline` (the flag that actually adds `lavfi=[silencedetect=...]` to the MPV AF chain) was always initialised to `false`. After restart the feature looked enabled in UI but did nothing until re-toggled. Fixed: `_silenceInPipeline = _silenceSkipEnabled` added after the prefs load.
- **Bug 2 — Vivid / Smart Enhance not persisted**: `_smartEnhanceEnabled` had no SharedPreferences save or load. State was lost every restart. Fixed: `pref_vivid` added to `_loadPrefs` and `_savePrefs`.
- **Bug 3 — Show skip buttons not persisted**: `_showSkipBtns` was toggled in Settings but reset to `true` every session. Fixed: `pref_skip_btns` added to both prefs blocks.
- **Bug 4 — Show prev/next buttons not persisted**: Same pattern. Fixed: `pref_prev_next_btns` added.
- **Bug 5 — Layout "compact" did nothing**: Claimed "smaller UI, condensed padding" but code only set `_showSkipBtns = true` (same as Default). Fixed: `isCompact` flag now drives real differences — `_buildBottomArea` uses `8px` side padding (vs `16px`), `6px` bottom padding (vs `10px`), zero gap between seek bar and transport row (vs `2px`), and `_buildTransportRow` is `48px` tall (Material tap-target minimum) vs default `52px`. (Initial fix used 44px; code review flagged accessibility risk — corrected to 48px in follow-up commit `52e99b29`.)

**K1 — Save on Pause — 2026-07-07**
Added `if (!v) _saveWatchPos();` inside `_player.stream.playing.listen` callback. Position is now saved the moment the user pauses — previously only saved every 10 seconds during playback, on background, on dispose, and on episode change. Frame thumbnails were checked (not in code) and not created per user instruction. Commit `5408c98`.

**J2 follow-up (same session):** Code-trace of J1 fixes found 4 more bugs. `_toggleSmartEnhance()` was missing `_savePrefs()` (Vivid state only saved on `dispose()` — force-kill lost it). Three Settings panel callbacks (`onShowSkipBtnsChanged`, `onShowPrevNextBtnsChanged`, `onShowSeekPositionChanged`) also only called `setState`, not `_savePrefs()`. And `_showSeekPositionLabel` had no prefs key at all — it was always resetting to `true`. Fixed in commit `26232d7` — added `_savePrefs()` to all three callbacks + `_toggleSmartEnhance()`, added `pref_seek_pos_label` load/save.

**Audit finding preserved here:** Cast feature (`cast_service.dart` + `cast_panel.dart`) exists as dead code — not wired into any player panel. Watch Party is UI + simulation only (no real WebSocket backend at `wss://party.raddflix.pk/ws`).

## Current State (2026-07-07 — I1 Audio Lab New Features)

### I1 — 4 New Audio Lab Features — 2026-07-07 (latest)
Commit: `6e4da14`.

**What changed (`player_screen.dart`):**
- **Dialogue Only** — `pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1`. The opposite of Vocal Remover — keeps the centre-channel sum (L+R), which isolates speech panned dead-centre and attenuates music/SFX spread across the stereo field.
- **Night Audio** — `acompressor=threshold=0.089:ratio=9:attack=200:release=1000`. Soft compressor that tames loud explosions/action peaks for late-night watching without crushing quiet dialogue.
- **Stereo Widener** — `extrastereo=m=2.5`. Enhances stereo separation — best with headphones.
- **Noise Reduction** — `afftdn=nf=-25`. Spectral denoising — cleans up old films, noisy streams, and low-quality encodes.
- **Vocal Remover `_loadPrefs` consistency fix** — the AF rebuild in `_loadPrefs` was still using the pre-A4 unscaled formula `pan=stereo|c0=c0-c1|c1=c1-c0`. Fixed to match `_applyLabAf`'s `0.5*` scale so prefs-restored state matches the live toggle.
- All 4 new features wired through all 7 touch points: state vars, loadPrefs restore, loadPrefs AF rebuild, savePrefs, onLabStateChanged call site + widget props, `_AudioEffectPanel` class (typedef, fields, constructor), `_AudioEffectPanelState` (late vars, `_applyLabAf`, `initState`, 4 new `_LabToggleRow` widgets).

## Current State (2026-07-07 — H1 Audio Lab Bugfix)

### H1 — Audio Lab Bugfix — 2026-07-07 (latest)
Commits: `9d0970e` (TASKS.md), `e283978` (player_screen.dart).

**What changed (`player_screen.dart`):**
- **A1 — `_applyAllAf()` logging** — replaced bare `catch (_) {}` with `debugPrint('[AudioLab] af set: ...')` on success and `debugPrint('[AudioLab] _applyAllAf ERROR: ...')` on failure. MPV errors are now visible in `flutter logs`.
- **A2+A3 — Merged EQ chain** — `_buildMergedAfString()` now extracts any `equalizer=` segment from `_currentLabAf` (Dialogue Boost / Bass Boost gains), adds its 10 values to the main EQ gains (clamped ±12), and emits a single `equalizer=` filter. The Lab chain has its `equalizer=` segment stripped before appending. Eliminates double-equalizer conflict that made main EQ sliders appear to do nothing when Lab effects were on.
- **A2 — Always emit `equalizer=` when enabled** — removed the `g.any((v) => v != 0)` guard. Even all-zero bands now emit `equalizer=0:0:0:0:0:0:0:0:0:0` so MPV explicitly clears any previous non-zero state.
- **A4 — Vocal Remover clip fix** — changed `pan=stereo|c0=c0-c1|c1=c1-c0` → `pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0`. The 0.5 scale prevents 2× amplitude clipping on loud content.
- **A5 — MPV sync on panel open** — `_AudioEffectPanelState.initState()` now calls `widget.onEqEnabledChanged(widget.eqEnabled)` via `addPostFrameCallback` so MPV is immediately synced to the panel's current state on open.
- **A6 verified** — `_applyLabAf()` correctly emits `''` when all toggles are off (`parts.isEmpty ? '' : parts.join(',')` — no fix needed).
- **A7 (silencedetect)** — `lavfi=[silencedetect=...]` left in chain; A1 logging will surface any MPV errors in the next test session.
- **Lab EQ coupling fix** — code-review found that merging Lab EQ gains into the main chain silenced Dialogue/Bass Boost when the EQ toggle was off. Fixed: condition changed from `if (_eqEnabled)` to `if (_eqEnabled || labEqGains.any((v) => v != 0))`. Commit `33a8a95`.
- **allMatches fix** — static simulation revealed that `firstMatch` silently dropped Bass Boost gains when Dialogue Boost was simultaneously on (both produce a separate `equalizer=` segment). Changed to `allMatches` with gain summing so Dialogue+Bass gains are always merged correctly. Commit `9ee224d`.

## Current State (2026-07-06 — Portrait-Player-V2)

### Portrait-Player-V2 — 2026-07-06 (latest)
Commit: `896ec06`. Fixed 7 portrait player layout issues found in audit.

**What changed:**
- **16:9 exact video zone** — `videoH` changed from fixed `constraints.maxHeight * 0.38` to `(constraints.maxWidth * 9.0 / 16.0).clamp(0.0, constraints.maxHeight * 0.50)`. Eliminates the ~100px black dead-band that appeared inside the video zone on typical phones because the 38% container was always taller than the actual 16:9 video frame.
- **Sidebar suppressed in portrait** — `_buildSidebar()` was rendering at the right edge of the video zone in portrait, obscuring content and duplicating the quick actions row below. Removed; replaced with comment.
- **Persistent back button** — Back button extracted from the `AnimatedOpacity` fade block into a separate always-visible `Positioned(top:0, left:0)` widget (`if (!_isLocked)`). Users can always exit the player without needing to tap the video to reveal controls first.
- **Fade-in title bar offset** — The remaining fade-in top bar (title + episode badge + rotate + PiP) is now `Positioned(left: 44)` so it never overlaps the persistent back button.
- **New `_buildPortraitTransportRow()`** — Portrait-specific transport row: replay / prev-episode / play-pause (centered) / next-episode / forward-skip only. Landscape's Lock + Immersive + Settings utility buttons removed from this row — they cluttered the transport row and duplicated the quick actions.
- **Lock moved to quick actions** — Replaced "Loop" slot in `_buildPortraitQuickActions` with "Lock". Quick actions are now: CC · Audio · EQ · Speed · Lock · More. Loop is accessible via the More (settings) panel.
- **`spaceEvenly` controls panel** — `_buildPortraitControlsPanel` now uses `Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly)`. Seek bar + transport + quick actions distribute naturally across the full panel height — no dead space below on tall phones.
- **`SingleChildScrollView` removed** — Portrait controls panel no longer wrapped in scroll view; it's a direct child of `Expanded`. Controls fill the available space cleanly.

## Current State (2026-07-06 — DOWNLOAD-TAB-V2)

### DOWNLOAD-TAB-V2 — 2026-07-06 (latest)
Commit: `094fd7d`. Full plan: `agent-hub/DOWNLOAD_TAB_REDESIGN_PLAN.md`.

**What changed:**
- **5 top-level tabs, no merged "Library"** — `bottom_nav.dart` now has Home,
  Search, Local, Download, Profile (indices 0-4). This supersedes the prior
  "Bottom Nav Redesign" entry below, which had merged Downloads+Local into a
  single "Library" tab — that idea was dropped in favor of keeping both as
  separate first-class destinations. All primary screens (`home_screen.dart`,
  `search_screen.dart`, `profile_screen.dart`, `local_media_screen.dart`,
  `downloads_screen.dart`) updated to the new index scheme and route names.
- **`downloads_screen.dart` fully redesigned** — old 4-folder grid
  (Movies/Shows/Dramas/Other with expandable inline groups) replaced with:
  Movies flat grid/list + TV Shows section where every non-movie item
  (shows, anime, dramas, cartoons) is grouped by show into a single "TV
  Shows" bucket — tapping a show pushes the new `SeasonFolderScreen`.
  Status pills (completed/downloading/failed) removed in favor of always-on
  live indicators — a `DownloadStorageStrip` (total size/count/free space)
  and `ActiveDownloadTicker` (per-item progress/speed/ETA) sit above the
  content, plus inline failed-badges/retry icons on each card.
- **`season_folder_screen.dart` (new)** — season grid (folder icon + done
  count) → tapping a season shows its episode list. Episode rows support
  swipe-to-delete (swipe left) and swipe-to-vault-prompt (swipe right);
  Movies keep long-press multi-select instead (grid layout doesn't suit
  Dismissible as well as a list does).
- **`episode_title_parser.dart` (new, `core/utils/`)** — pure regex-based
  parser (`parseEpisodeTitle()`) that extracts show title / season / episode
  number from a download's `title_text` (e.g. "S05E02") to build the show →
  season grouping. No schema change — this is derived purely from existing
  title strings.
- **Extracted widgets** — `widgets/download/download_storage_strip.dart` and
  `widgets/download/active_download_ticker.dart`, pulled out of
  `downloads_screen.dart` so the always-visible storage/progress UI can be
  reused/tested independently.

**New nav structure:** Home (0) · Search (1) · Local (2) · Download (3) · Profile (4)

### Bottom Nav Redesign — 2026-07-06
Two commits: `405f250`, `00f71cb`. **Superseded by DOWNLOAD-TAB-V2 above** —
the merged "Library" tab this section describes no longer exists; kept here
for historical context only.

**What changed:**
- **Tab 1: Local → Search** — `PhosphorIcons.magnifyingGlass` icon. Search was buried as an AppBar icon on Home only; now a primary nav destination reachable from every screen. Home AppBar search icon removed (no longer needed).
- **Tab 2: Downloads → Library** — `PhosphorIcons.files` icon. Renamed to signal "all your offline content," not just in-progress downloads.
- **Label font 9.5 → 11.0px** — accessibility fix (was below WCAG minimum).
- **Search screen gets bottom nav** — `RaddFlixBottomNav(currentIndex: 1)` added to `SearchScreen` Scaffold; it was the only primary screen without one.
- **Local Media stays reachable via Library** — `DownloadsScreen` AppBar gets an "On Device" button (`AppIcons.device`) that navigates to `LocalMediaScreen`. Local is no longer a top-level tab but remains easily accessible within Library context.
- **LocalMediaScreen nav updated** — `currentIndex: 2` (Library stays highlighted); tapping Library tab pops back to Downloads/Library instead of doing a full popUntil+push.
- **`_navIndex` drift fixed** — Home screen pushes now use `.then((_) => setState(() => _navIndex = 0))` so the capsule indicator resets correctly when user presses back from any tab.
- **All screens updated** — `downloads_screen.dart`, `local_media_screen.dart`, `profile_screen.dart` all have their embedded bottom nav `onTap` routing updated (i==1 → search, not localMedia).

**New nav structure:** Home (0) · Search (1) · Library (2) · Profile (3)

### Player Panel Audit — 2026-07-05
Full audit of all player panels + format support. Three commits: `303b9af`, `1bc5b7c`.

**What changed:**
- **Info icon removed** from landscape top bar — too small to be useful prime real estate. Video info moved to Settings panel → Style tab as a "Video information" ListTile (always accessible, less obtrusive).
- **Portrait quick actions overflow fixed** — 6 buttons now use `Expanded(Center(...))` per slot so they share width equally on any screen width (no more potential RenderFlex on 320dp devices).
- **Codec display fixed** — `_currentAudioCodec` state var now populated by the EAC-3/DTS/TrueHD/MLP auto-detection block; passed correctly to `_AudioTrackPanel` (was always `null`). Detection now maps codec names to human-readable display names (E-AC-3 Dolby Digital+, DTS-HD, Dolby TrueHD, MLP/TrueHD).
- **SW decoder toggle always enabled** (UX improvement) — the "disabled during playback" guard removed from the UI. Toggle is always interactive. Safety rule preserved: `hwdec` property change only applied when NOT playing (MediaTek/Infinix black-screen protection). When playing: state saved + snackbar "will apply after pause/next file".
- **AudioEffect panel header overflow fixed** — restructured from single Row (title + Spacer + 3 tab texts) to a Column with separate title Row and tabs Row. Prevents overflow on narrow portrait bottom sheets (~280–320dp).
- **`_SettingsPanel` gets `onVideoInfo`** optional callback, wired from `_openSettingsPanel`.

## Current State (2026-07-05 — Portrait-Player-V1)

### Portrait Player Layout — 2026-07-05 (latest)
`Portrait-Player-V1` task complete. `player_screen.dart` now has a full portrait-mode layout that activates automatically when `constraints.maxWidth < constraints.maxHeight`.

**What changed:**
- `build()`: detects portrait via LayoutBuilder constraints and routes to `_buildPortraitLayout()`
- `_buildPortraitLayout()`: YouTube/Netflix-style Column — top 38% video zone (Stack: video surface + gesture layer + overlays + compact top bar) + bottom 62% controls panel (dark `0xFF0D0D0D` background)
- Gesture zone is scoped to the video area only; swipe brightness/volume/seek all work within that zone
- `_buildPortraitTopBar()`: compact back button + title (ellipsis) + episode badge + rotate + PiP
- `_buildPortraitControlsPanel()` + `_buildPortraitQuickActions()`: seek bar, transport row (play/pause/skip/prev/next/lock/settings), quick action buttons (CC, Audio, EQ, Speed, Loop, More)
- `_buildPortraitActionBtn()`: icon+label tile with active-state accent highlight
- `_openRightPanel()`: adds portrait branch using `showModalBottomSheet` + `DraggableScrollableSheet` (62% initial, 35%–88% draggable, scroll controller wired via `PrimaryScrollController`) — landscape path unchanged
- All hardcoded portrait offsets (`0.22`, `0.88`, `75`) are superseded; one-handed mode still exists but is bypassed in portrait

Commits: `e851819`, `c1131ce`. CI will verify on next APK build.

## Current State (2026-07-05)

### UI Audit + CI fix — 2026-07-05 (latest)
Full UI audit of all screens. Four issues found and fixed:

1. **CI fix** (`a4b946b`): `PhosphorIcons.wifi()` → `PhosphorIcons.wifiHigh()` in `app_icons.dart`. This was the sole compile error blocking every APK build since the rebrand commits. Build is now **✅ GREEN**.
2. **Server Downloads gated** (`1e511a0`): "Server Downloads" row in Profile was visible to ALL non-guest users. Added `isAdmin` bool to `AppUser` model (reads `is_admin` from JSON, defaults false). Button now only shows when `user?.isAdmin == true`. ⚠️ **Pending**: Flask `/me` endpoint needs to add `is_admin` to its JSON response before admin can use it — separate task, needs Oracle approval.
3. **Hardcoded prices removed** (`22d1a93`): `tid_status_screen.dart` plan labels no longer embed `₨149/₨249/₨399` — now shows `'Basic Plan'` etc. Prevents stale-price disputes if backend pricing changes.
4. **Decoy wording** (`ebf74b6`): Vault Settings "fake PIN / fake vault" copy replaced with "decoy PIN / decoy vault" in all user-visible strings.

### Open item from this session
Flask `/me` endpoint must add `is_admin: true` to response for admin accounts so they can access "Server Downloads" in the app. Needs: (a) confirm `is_admin` column in `app_users` table, (b) add to SELECT + jsonify in `mobile_api.py`, (c) Oracle restart. Requires explicit user approval before touching production.

### Rebrand zero-rating copy — hide JazzDrive/Oracle from UI (2026-07-05)
`subscription_screen.dart`'s "JazzDrive CDN" line and `debug_diagnostics_screen.dart`'s
`'Oracle Server'`/`'JazzDrive API'` check labels were the only user-visible strings
naming internal infrastructure. Subscription copy now attributes zero-rating to
RaddFlix ("RaddFlix is 100% data-free on Jazz"); diagnostics labels renamed to
`'Content Server'`/`'Stream Service'` (screen stays intentionally ungated per prior
note below — labels renamed instead of adding new gating). Jazz SIM requirement
copy, and SIMOSA/JazzCash/Easypaisa payment copy, left untouched by design. Full-repo
grep confirms zero JazzDrive/Oracle occurrences in any `Text()`/`SnackBar`/label
reachable by a user. Commit `f3f6453`.

### Logger secret stripping — final gap closed (2026-07-05)
`DebugLogger.logApi()` previously wrote raw request/response bodies (and the
`onError` path's embedded response preview) straight into the shareable log
buffer with no redaction. Added `_redactBody()` to `debug_logger.dart` —
redacts `validationkey=`, bare `k=<token>`, `jsessionid=`,
`authorization`/`bearer`, and `access_token`/`refresh_token` before
truncation/storage. Method/URL/status/duration metadata untouched. Verified
via full-repo grep that no unredacted secret pattern reaches any
`DebugLogger`/`print()` call. Commit `015bcea`. This closes the last known gap
from the prior logger-cleanup session — the JazzDrive/Oracle string
sanitisation in the share/clipboard export (`_sanitiseMessage()`) and the
removed `print()` in `request_encoder.dart` were both re-verified intact.

### Icon migration complete — 2026-07-04
Replaced the last 2 raw `Icons.block_rounded` references in
`raddflix_flutter/lib/widgets/player/gesture_map_sheet.dart` with `AppIcons.block`
and added the `app_icons.dart` import. AppIcons coverage is now 100% across all
non-player-widget files. Commit `3ec3c81`.

### Full audit pass (subtitles, player controls, access control, downloads) — 2026-07-03
Found and fixed a critical bug: the backend `is_free` episode-inheritance fix from
commit `8176835` had been applied to a stray, never-deployed `hub/` directory at the
repo root instead of the real `radd-hub/hub/` that Oracle runs — production was still
showing free-show episodes as locked. Re-applied the fix to the correct file. Also
fixed a subtitle-track-carries-over-to-next-episode bug, a weak download-completion
size check, a rapid-multi-tap race on the episode list, and removed a dead/misleading
subscription-expiry check in the Downloads screen. Full detail in
`agent-hub/history/2026-07.md` → "Full Audit Pass 2026-07-03". See also the new
`agent-hub/CONTEXT.md` warning about the duplicate `hub/` directory.

### Oracle
- Flask: RUNNING ✅ healthz: {"ok":true,"version":"3.0.0"}
- DB: schema current (display_name/email/avatar_color/avatar_emoji + all Phase 26 columns)
- Endpoints: PUT /api/auth/profile, POST /api/auth/change-password, GET /api/quota all live

### Flutter / APK
- Latest successful build: Phase 60 (P60 + Kotlin 2.2.0 + minSdk 24 fixes) ✅ CI PASSING · commit 98323a8
- All compile errors resolved
- Phases 17–37 fully merged and building clean

### What was fixed in Phase 37 (2026-06-29)
1. **Share button removed** — `show_detail_screen.dart`: stripped import + SliverAppBar actions block
2. **Quality picker removed** — `settings_screen.dart`: only one fixed video source, no user choice
3. **Free-content gate bug fixed** — 4 call sites in `show_detail_screen.dart` now OR with `widget.item.isFree` so free content is always free even if API episodes lack explicit `is_free:1`
4. **Player transport row overlap fixed** — `player_screen.dart`: Stack centering replaces broken fixed SizedBox(108) right zone
5. **Theme picker cut off fixed** — `profile_screen.dart`: isScrollControlled:true + DraggableScrollableSheet; all 10 themes visible
6. **share_plus kept in pubspec** — `debug_logger.dart` uses `Share` API to export crash logs; only the UI share button was removed

### What was added in Phase 60 (2026-07-01)
1. **Dub Active indicator** — `_AudioTrackPanel` now shows a green-bordered card at the top of its list when `_isDubMode == true`, displaying the active language flag + label
2. **Remove Dub button** — single tap in the Audio Panel calls `_disableDubMode()` and dismisses the panel — no need to reopen the subtitle/dub panel
3. **New props** — `isDubMode`, `dubActiveLang`, `onRemoveDub` added to `_AudioTrackPanel` (all optional / have defaults)

### Build fixes applied alongside Phase 60 (2026-07-01)
- **Kotlin 2.2.0** — bumped `ext.kotlin_version` from `1.9.20` → `2.2.0` in `android/build.gradle` (flutter_tts 4.2.5 stdlib uses Kotlin 2.2.x metadata)
- **minSdkVersion 24** — bumped from 21 → 24 in `android/app/build.gradle` (flutter_tts 4.2.5 declares minSdk 24 in its manifest; Android 5/6 dropped — <2% of Pakistani market)
- Both fixes address a pre-existing break introduced in Phase 59 (flutter_tts was added but build never ran green)

### Auto-commit system (2026-07-04)
- `auto_commit.sh` added at repo root — lightweight GitHub API (Trees API) commit script, no git shell required
- Rule 42 added to `agent-hub/RULES.md` — every file edit must be followed immediately by `bash auto_commit.sh "message" file1 ...`
- `AGENT_PROMPT.md` updated to mention Rule 42 in the normal workflow section
- Commit `a0d2d9f`

### Test suite run — 2026-07-04
All 4 files in `raddflix_flutter/test_suite/` executed:

| File | Result | Notes |
|---|---|---|
| `jazzdrive_logic_test.js` | ✅ 27/27 passed | Pure JS logic, no network |
| `logic_tests.dart` | ✅ 69/69 passed | Pure Dart logic, no network; run via Nix Dart 3.0.0 |
| `run_tests.js` | ✅ 71 passed / 0 failed / 8 warnings | Full integration against Oracle port 80; all warnings are expected (firewalled ports, repeat-run 409, Jazz-SIM can't be verified from Replit) |
| `jazzdrive_dart_test.dart` | ⚠️ 0/8 — MED-1011 (Oracle JazzDrive session expired) | SSL cert fix applied (`badCertificateCallback=true` for Nix Dart); API is reachable, session needs OTP re-login from Oracle admin panel. Commit `2ce6ab4`. |

**Actionable item:** Oracle JazzDrive SAPI session is expired. To re-validate `jazzdrive_dart_test.dart`: log into Oracle admin panel → Settings → JazzDrive Login → complete OTP re-login. Then re-run the test.

### Corrections applied — 2026-07-04
Found and fixed wrong information in constants, tests, and comments discovered during the test run:

| Wrong | Correct | Files fixed |
|---|---|---|
| Cache TTL 180 min / 6h | **110 min** (source of truth: `jazzdrive_service.dart` `_cacheTtl`) | `constants.dart`, `logic_tests.dart`, `run_tests.js`, `local_db.dart`, `README.md` |
| `jazzdrive_dart_test.dart`: "validationkey MUST be in final URL" | **DO NOT append validationkey=** — k= token is self-authenticating | `jazzdrive_dart_test.dart` header, `_buildStreamUrl`, Validation 2 |

Commits: `5d37e39`, `19fa4cf`

**Minor server note:** TID validation threshold is `len < 5`; the test sends "SHORT" (5 chars) which passes. Not a critical bug — just a low threshold. No code change made.

### Open Tasks
None — awaiting next task.

### What was done 2026-07-14 — Backend Audit + Flutter Constants Fix

**BACKEND-AUDIT-2026-07-14** (commits `5861ff5`, `737d956`, `54cb17a` — CI ✅)

Previous agent ran a full backend audit and found 10 bugs, then hit quota before pushing any fixes. This session pushed all fixes and deployed to Oracle.

**Python fixes — commit `5861ff5` (8 files):**
1. `app.py` — registered `bp_catalog_secure` at `/api` (was missing; every `GET /api/catalog/share_url` returned 404)
2. `routes/mobile_api.py` — `get_catalog_share_url`: replaced broken loop over nonexistent tables with `SELECT f.share_url, t.is_free FROM files JOIN titles WHERE f.id=?`
3. `routes/app_users_panel.py` — watch history SQL columns corrected (`position_sec/duration_sec/updated_at` → `position_ms/duration_ms/watched_at`); JSON converts ms→sec so the JS template keeps working
4. `routes/settings.py` — added `APP_VERSION_KEYS` tuple (was a NameError at runtime); fixed stat query `overview IS NOT NULL` → `plot IS NOT NULL` (column dropped by earlier migration)
5. `db.py` — added `app_signatures` CREATE TABLE to `_DDL` (settings routes were already INSERT/SELECTing it — table was never created)
6. `routes/db_mgmt.py` — `catalog_fts`→`titles_fts` (×2); removed dropped columns `overview`/`cast_names` from nullsonly filter array; `out["original_lang"]`→`out["language"]`
7. `routes/analytics.py` — `NULL as name`→`COALESCE(u.device_name,'') as name` so analytics dashboard shows device name instead of permanent dash
8. `routes/poster_proxy.py` — `_mark_key_invalid`/`_mark_key_ok` both had `WHERE value_enc=<plaintext>` which never matched the Fernet-encrypted column; replaced with scan+decrypt loop updating by rowid

**Flutter fixes — commit `737d956` (2 files):**
1. `lib/screens/home_screen.dart` — `_checkForUpdates()` was calling `/api/config` (404); corrected to `/api/app/config` (`bp_app` is registered at `/api/app`)
2. `lib/core/constants.dart` — added `ApiPaths.adminQueue = '/stream/api/queue'` (compile-time reference in `admin_queue_screen.dart` was missing the constant)

**Deletion — commit `54cb17a`:**
- `radd-hub/hub/routes/proxy_pool_page.py` — deleted; proxy pool feature was intentionally removed from admin panel; file was orphaned (never imported or registered in `app.py`)

**Deployment:** `push_to_oracle.sh` ran cleanly; Oracle confirmed at `737d956`; `GET /api/app/version → {"ok":true}`.
**CI note:** The `737d956` build initially failed with `Archive is not a ZIP archive` on Android SDK Platform 31 — GitHub Actions infra issue (corrupted download), not a code problem. Re-running the same commit produced a clean green build.

### What was done 2026-07-07 — Subtitle Panel Full Rewrite + Settings Polish

**G1 — Subtitle Panel Full Rewrite** (`778f17c`)
Root-cause bugs all fixed in one pass:
1. `sub-back-color` hex format was `#ff000000` (opaque red in MPV) → new `_toMpvBackColor()` helper emits correct `#RRGGBBAA` where `AA=00`=opaque, `AA=FF`=transparent.
2. "Box" shadow mode was identical to "None" → now explicitly sets `sub-back-color` to `Colors.black87` if no background is set.
3. Dual opacity state (`_subFade` + `_subOpacity`) both writing `sub-opacity` → collapsed to single `_subOpacity`.
4. 7 fragile tabs with repeated `.indexOf()` → 5 clean tabs: Tracks | Style | Position | Sync | Online (+ AI Dub when available).
5. No live preview → `_buildPreview()` renders a Flutter widget showing exact font/size/bold/colour/shadow/position before the user closes the panel.
6. `_applyShadow` switch illegal fall-through → fixed as if/else chain.

New helper classes: `_SubTrackTile`, `_BigStepBtn` (below the state class).
MPV colour helpers: `_toMpvColor(Color)` → `#RRGGBB`, `_toMpvBackColor(Color)` → `#RRGGBBAA`.

**G2 — Settings Panel Polish** (`778f17c`)
- Progress bar style: radio list → `Wrap` of pill chips (easier to scan, all 11 styles visible at once).
- Controls tab: `_stgSection` card + `_stgSwitch` rows (icon container + two-line label).
- Navigation tab: same card treatment + `_stgSliderRow` for seek/skip sliders.
- Build triggered: https://github.com/raddclub/raddflix-app/actions/runs/28860032110

### What was added 2026-07-03 — MPV-Native Player Upgrades
1. **Native A-B loop** — replaced Dart position-listener seek with MPV's own `ab-loop-a`/`ab-loop-b`/`ab-loop-count` properties via new `_syncNativeAbLoop()`; frame-accurate, zero per-tick Dart overhead. Dart state now UI-only.
2. **Near-gapless episode transitions** — `_prefetchNextEpisode()` resolves the next episode's stream link ~20s before the current one ends (once per episode); `_openMediaForEpisode()` has a fast path that uses the cached URL directly, skipping the network round-trip when the user advances.
3. **Screenshot with subtitles** — `_takeScreenshot({withSubtitles})` uses MPV's `screenshot subtitles` command; wired to long-press on the Screenshot shortcut in the More panel.
- See `agent-hub/history/2026-07.md` → "MPV-Native Player Upgrades 2026-07-03" for full detail.
- No local Flutter build tool in that session — verified by code review only; watch first CI run closely.

### What was fixed 2026-07-03B
1. **AI dub failing** — `subtitle_dubber.dart`: `flutter_tts.synthesizeToFile()` on Android ignores directory prefix, always writes to `getExternalFilesDir(null)`. Fixed: pass plain filename to TTS, read clips back from `getExternalStorageDirectory()` (same path). Previously all clips were missing → `clips.isEmpty` → null.
2. **Pinch zoom gray screen** — `player_screen.dart`: `Transform.scale` on media_kit's `Video` widget (SurfaceView) produces gray area — Flutter cannot scale a SurfaceView via Transform. Fixed: removed `Transform.scale`; apply zoom via MPV native `video-zoom` property (log2 scale) in `_onScaleUpdate`, `_onScaleEnd`, and reset button. Commits: `8829d3d` (dubber), `2918655` (player).

### Known Data Issues

### Key Rules (NEVER BREAK)
- Never add `androidAttachSurfaceAfterVideoParameters: true` (black screen on MediaTek)
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Oracle git pull: always `git stash && git pull && git stash pop`
- Push files SEQUENTIALLY — never parallel (SHA race condition)
- Use `db.setting(k)` not `db.get_setting(k)`
- `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode`
- `ImageCache.clearLive()` does NOT exist in this Flutter version — use `PaintingBinding.instance.imageCache.clear()`
- CachedNetworkImage uses `errorWidget:` not `errorBuilder:`

---

## 2026-07-16 — PLANS-FORM-FIX — COMPLETE ✅

**Commit:** `61027c1b` | **Deployed to Oracle** ✅

### Problem
Admin reported Edit button did nothing; Add New Plan gave no feedback.

### Root Cause
`onclick="editPlan({{ p|tojson }})"` — tojson puts double-quoted JSON inside a double-quoted HTML attribute. Browser closes the attribute at the first `"` inside the JSON; clicking Edit executed `editPlan({` (SyntaxError). Silent fail. Bug was latent until the PLANS-ADMIN-FIX seeded real plans (previously no plans = no edit buttons = bug never triggered).

No feedback issue: all POST routes redirected silently — admin saw the same page and assumed nothing happened.

### Fixes Applied
- `onclick="editPlan({{ p.id }})"` (integer, no quoting issues) + `const _PLANS = {{ plans_map|tojson }};` in `<script>` block (safe context for tojson)
- `plans_map` dict passed from `index()` route
- `?ok=created/updated/toggled/deleted` redirect params + JS toast for all four actions
- Escape key closes modal

### Audit
Only `plans_panel.py` had the onclick+tojson pattern. All other panels confirmed clean.

---

## Bug-Fix Batch 2026-07-02 — COMPLETE ✅

All 15 verified issues from the full-app audit fixed. CI green on commit `3c38f31` (run #28588429103).

### Commits
| SHA | File | Fixes |
|---|---|---|
| `5fd4490` | player_screen.dart | #1 unobserveProperty leak, #6 voice-cmd snackbar, #24 silence-filter |
| `81a6d09` | debug_diagnostics_screen.dart | #3 _tlTimer cancel in dispose() |
| `535477e` | login_screen.dart | #7, #8, #20 mounted guards in catch blocks |
| `685673f` | show_detail_screen.dart | #14 mounted guard in _playEpisode |
| `be0174d` | subtitle_dubber.dart | #2 OOM guard, #12 cache integrity, #23 phase-2 progress |
| `69c3703` | subtitle_dubber.dart | #11 log synthesis errors |
| `26f8f48` | pubspec.yaml | #22 pin flutter_tts >=4.2.5 <5.0.0 |
| `ae85282` | TASKS.md | audit summary |
| `3c38f31` | search_screen.dart | RESTORED from clean base — JS $' replace-pattern corrupted previous attempt |

### Root-Cause: search_screen Corruption
Fix #10 replacement string contained `r'^\[|\]$'` — the `$'` is a JS special replacement pattern
("insert string suffix"), which doubled the file to 2424 lines. Fix: use `$$` in JS replacement
strings whenever Dart code contains `$` characters. Final file restored from commit 685673f baseline.

### Issues Not Fixed (by design)
#4, #5, #13, #15, #16, #17, #18, #19, #21 — see TASKS.md for rationale.

### Permanent Rules (never violate)
- No `androidAttachSurfaceAfterVideoParameters: true`
- No `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race)
- `_np` must remain a getter, never a local variable
- JS `String.replace(old, new)`: escape `$` as `$$` in replacement when Dart code contains `$`
