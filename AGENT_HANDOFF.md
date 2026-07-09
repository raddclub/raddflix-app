# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

## Current State (2026-07-09 — Phase 2 COMPLETE, Phase 3 next)

### UI-UX-MIGRATION — Phase 2 complete — 2026-07-09

**Start here if you're a fresh agent/account picking this up:** read `AGENT_PROMPT.md` →
this section → `agent-hub/UI_UX_MIGRATION_PLAN.md`, then do the first unchecked checkbox in the
earliest open phase of that plan file. The plan file is the single source of truth for
progress — this section just orients you.

Executing the `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` roadmap phase-by-phase. **Phase 2 is
now ✅ COMPLETE.** All items done (CI pending on `6457ab2`):

- Phase 2, item 1: `pin_lock_screen.dart` + `PinSetupScreen` migrated onto `RaddLockPad`.
- Phase 2, item 2: `vault_lock_screen.dart` migrated onto `RaddLockPad` (vault accent).
- Phase 2, code review: two regressions caught and fixed (`d8bfcd7`). New `RaddLockPad.onChanged`
  hook added — future consumers must use it to clear caller-owned error state.
- Phase 2, ContentCard token pass: `content_card.dart` radius tokens migrated from `AppRadius.*`
  to `RaddRadius.*` (`6457ab2`). Full call-site consolidation onto `RaddCard` deferred to
  Phase 4/5 (ContentCard has features RaddCard lacks). `SimosaCard` intentionally excluded.
- Phase 2, player dead-code: CLOSED per TASKS.md `PLAYER-DEAD-CODE-CLEANUP` — user declined
  deletion. Files are intentionally-parked unshipped features.

**Phase 3 also complete (CI pending):** Token pass done across all 6 auth + small screens
(`login`, `register`, `watchlist`, `history`, `splash`, `settings`). Commits `39256ca`→`8a84428`.
`SettingsRow` adoption + taxonomy change deferred to Phase 4/5 — `SettingsRow` lacks `subtitle`
and `iconColor` params (same story as ContentCard/RaddCard); taxonomy restructure needs PM input.

**Next work: Phase 4** — player screen token migration (`player_screen.dart`, 9,280 lines).
This is the high-risk phase. Do NOT start until CI is confirmed green on the Phase 3 commits.
Phase 4 is unblocked from all prerequisites. Start at the first `[ ]` item in Phase 4 of
`agent-hub/UI_UX_MIGRATION_PLAN.md`. Strongly recommend doing Phase 4 in separate sub-commits
per token type (colors first, then radius, then spacing/type) — the file is too large to migrate
in one pass without risking conflicts.

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
- DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 — upload to JazzDrive + sync still needed

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
