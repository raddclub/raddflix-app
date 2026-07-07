# RaddFlix Tasks

> This is the single live task board. Start every session at `AGENT_PROMPT.md`.
> Add a row here (⏳ IN PROGRESS) before starting work, mark ✅ DONE + commit SHA when pushed.
>
> **This file is a lean INDEX, not a full history.** Every completed item below has its full
> write-up (root cause, implementation notes, testing checklist) already preserved in
> `agent-hub/history/TASK_LOG.md` — search that file by phase name or ID before re-deriving
> something that may already be documented. Keeping this file short means every future session
> reads less and starts working faster; nothing is lost, it's just filed correctly.
>
> See `agent-hub/ANIMATION_PLAN.md` for animation spec and acceptance criteria.

---

## Open Tasks

| Task | Description | Plan | Status |
|---|---|---|---|
| DOWNLOAD-TAB-V2 | 5-tab bottom nav (Home/Search/Local/Download/Profile, drops merged-Library idea); redesign Download tab UX for simplicity (Netflix/MoviBox/1DM+/Amazon Prime/Snaptube/MX Player research); Download tab gets Movies section (flat) + TV Shows section grouped by show → per-season folders → episodes | See `agent-hub/DOWNLOAD_TAB_REDESIGN_PLAN.md` | ✅ DONE — `094fd7d` |
| I1-LAB-FEATURES | Add 4 new Audio Lab features: Dialogue Only (centre-channel sum isolates speech), Night Audio (acompressor tames explosions), Stereo Widener (extrastereo=m=2.5), Noise Reduction (afftdn=nf=-25). Also fixed vocal-remover 0.5 scale inconsistency in `_loadPrefs` AF rebuild. | `player_screen.dart` — 7 touch points: state vars, loadPrefs restore, loadPrefs AF rebuild, savePrefs, onLabStateChanged call site + widget props, panel class typedef/fields/ctor, state class vars + _applyLabAf + initState + UI toggles | ✅ DONE — `6e4da14` |
| J1-PLAYER-BUGFIX | Full player audit (66 working, 5 partial bugs, 1 dead-code cast). Fixed all 5 bugs: (1) silence-skip _silenceInPipeline not restored from prefs, (2) Vivid/SmartEnhance not persisted, (3) _showSkipBtns not persisted, (4) _showPrevNextBtns not persisted, (5) Layout "compact" had no real visual effect — now applies tighter padding + shorter transport row. | `player_screen.dart` — _loadPrefs, _savePrefs, _buildBottomArea, _buildTransportRow | ✅ DONE — `cd75b25` |
| Portrait-Player-V1 | Fix video player portrait mode layout — YouTube/Netflix split (video top 38% + controls panel below), compact top bar, bottom-sheet settings panel, portrait-aware gesture zone, fix hardcoded offsets | `e851819`, `c1131ce` | ✅ DONE |
| Portrait-Player-V2 | 7 portrait layout issues fixed: 16:9 exact video zone (no black dead-band), sidebar suppressed in portrait, persistent always-visible back button, new clean `_buildPortraitTransportRow` (no Lock/Immersive/Settings clutter), `spaceEvenly` controls panel (no dead space on tall phones), `SingleChildScrollView` removed, Lock moved to quick actions row | `896ec06` | ✅ DONE — `896ec06` |
| BUG-FREE-PLAY-01 | Free content wrongly showed subscription paywall on online play (worked fine after download). Root cause: `onGenerateRoute`'s `PageRouteBuilder` for `AppRoutes.player` never forwarded `settings:`, so `ModalRoute.of(context)?.settings.arguments` inside `PlayerScreen` always resolved to null — `is_free` was silently lost on every online play, treating all streamed content as paid. | `app.dart` — added `settings: settings` to the player `PageRouteBuilder` | ✅ DONE — `a9d90c5` |

---

## 🛡️ Hard Rules for Every Animation Phase (ANIM-*)

> An agent MUST verify these before marking any ANIM task as DONE:
> 1. ✅ Gated behind `AnimConfig.tier` check
> 2. ✅ Respects `MediaQuery.disableAnimations`
> 3. ✅ No `BackdropFilter` on API < 28 (Tier < 2)
> 4. ✅ No fragment shaders on API < 26 (Tier < 2)
> 5. ✅ `RepaintBoundary` on every isolated animated widget
> 6. ✅ All controllers/listeners disposed in `dispose()`
> 7. ✅ Tested on API-21 emulator — must not crash or jank
> 8. ✅ Duration ≤ 350ms on Tier 0/1

---

## Completed Work Index

Full detail for every row below (root cause, code diffs, testing notes) lives in
`agent-hub/history/TASK_LOG.md` — use the phase name or commit SHA to find it fast.

| Phase / Batch | Summary | Commit(s) | Status |
|---|---|---|---|
| Phase 41 | Performance infra — AnimConfig tiers, animation packages, RepaintBoundary audit | `8396c13` | ✅ DONE |
| Phase 42 | Hero poster transition (home/search → detail) | `50717ac` | ✅ DONE |
| Phase 43 | Staggered grid/list entry animations | `4f55fcd` | ✅ DONE |
| Phase 44 | Card → detail morph via OpenContainer | `2600a39` | ✅ DONE |
| Phase 45 | Neon/glow primary action buttons | `bec1909` | ✅ DONE |
| Phase 46 | Typewriter & animated text (synopsis, chips) | `647ac5c` | ✅ DONE |
| Phase 47 | Frosted glass bottom nav | `af27e1a` | ✅ DONE |
| Phase 48 | 3D tilt hero banner | `a8d4323` | ✅ DONE |
| Phase 49 | Ambient particle background (splash/login) | `f81b0cb` | ✅ DONE |
| Phase 56 | Subscription tier badge (animated glow) | `a34b5f9` | ✅ DONE |
| Audit Fixes | Guest/Free/Premium episode lock logic | `336dbb5` | ✅ DONE |
| 5-Feature Batch | Settings screen, search history, subtitle picker, update check, continue-watching | `1859ec1` / `a6d938b` / `2562512` / `d2f8146` | ✅ DONE |
| Phase 57 | Player audit + fix: dual subtitles (secondary-sid), fake track bugs, EAC3/DTS auto-fallback, codec badges, MKV embedded subtitle selector | audit: N/A · impl: see `TASK_LOG.md` "Phase 57 Implementation" | ✅ DONE |
| Phase 58 | Online subtitle search overhaul (OpenSubtitles XML-RPC, manual search, language chips) | see `TASK_LOG.md` "Phase 58" | ✅ DONE |
| Phase 60 | Remove-dub / dub-active indicator in Audio Panel | `803f09a` | ✅ DONE |
| Build Fix | Kotlin 2.2.0 bump (flutter_tts 4.2.5 compat) | `a8e5bf1` | ✅ DONE |
| Build Fix | minSdkVersion 21 → 24 (flutter_tts 4.2.5 requirement) | `98323a8` | ✅ DONE |
| Full-App Audit | 15 verified bugs fixed across 7 files (dispose leaks, mounted guards, static regex, OOM guard, etc.) | see `TASK_LOG.md` "Full-App Bug & Logic Audit" | ✅ DONE |
| Bug-Fix Batch 2026-07-02-B | Dub visibility, ASS subtitle margin override, free-user `isFree` bool parsing | `b0b01ff` / `7835605` | ✅ DONE |

---

## Repo Consolidation & Resilience Work (2026-07-03)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| Docs consolidation | Archived 15 stale handoff docs, rewrote `AGENT_PROMPT.md` as single safe entry point | `5618f33` | ✅ DONE |
| Script hardening | `push_to_github.sh` / `push_to_oracle.sh` — `set -euo pipefail`, no token-to-disk, branch/merge guards, secret-leak guards, DRY_RUN | `7fed76c`, `c93d075` | ✅ DONE |
| Live push test | Verified real commit+push+revert in isolated `/tmp` clone; fixed lock-file-gets-committed bug | `a56d12c` | ✅ DONE |
| `agent-hub/OPERATIONS.md` | Full connect/edit/push guide for GitHub + Oracle | `1a656f7` | ✅ DONE |
| Bootstrap section | `AGENT_PROMPT.md` now walks a fresh session through secret checks + doc order before waiting for a task | `3c52e22` | ✅ DONE |
| `agent-hub/RESILIENCE.md` | Scaling/fallback playbook — local sub-agents vs. Project Tasks, fallback ladders, verify-before-success, hard boundary on safety | `c0cec01`, `62e46ad` | ✅ DONE |
| Oracle drift fix | Server was 281 commits behind + UU conflict markers + local edits. Backed up server files, `git checkout -f origin/main`, `git pull --ff-only`. Server now at `baf349f`, clean tree, healthz ✅ | — | ✅ DONE 2026-07-03 |
| Bug-Fix Batch 2026-07-03 | Free-content play gate + download failures: episode `is_free` inheritance in all 3 catalog API endpoints; movie/episode play gates bypass for local files; episode download URL decode; retryDownload URL decode; `_isSubExpired` live provider | `8176835` | ✅ DONE |
| MPV-Native Player Upgrades 2026-07-03 | Native `ab-loop-a/b` (removed Dart-side seek polling), background next-episode link prefetch for near-gapless transitions, screenshot-with-subtitles (long-press) | `4cda21c` | ✅ DONE |
| Full Audit Pass 2026-07-03 | Subtitles, player controls, access control, downloads — see `TASK_LOG.md` "Full Audit Pass 2026-07-03" | see below | ✅ DONE |

---

## Auto-Commit Workflow (2026-07-04)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| Auto-commit system | `auto_commit.sh` — lightweight GitHub API commit script; Rule 42 added to RULES.md; AGENT_PROMPT.md updated | `a0d2d9f` | ✅ DONE |
| Icon migration — gesture_map_sheet.dart | Replace 2× `Icons.block_rounded` with `AppIcons.block`; add `app_icons.dart` import — completes 100% AppIcons coverage across non-player files | `3ec3c81` | ✅ DONE |
| Test suite — complete run | All 4 test files executed: JS logic 27/27, Dart logic 69/69, Integration 71/71, JazzDrive Dart 0/8 (MED-1011 — Oracle session expired, not a code bug). SSL cert fix applied to `jazzdrive_dart_test.dart` for Nix/Replit Dart | `2ce6ab4` | ✅ DONE |
| Correct wrong info — TTL & validationkey | Fixed: `constants.dart` TTL 180min→110min; `jazzdrive_dart_test.dart` validationkey direction inverted (was claiming vk MUST be in URL, production says DO NOT add); `logic_tests.dart`/`run_tests.js`/`README.md`/`local_db.dart` stale 6h/180min references | `5d37e39`, `19fa4cf` | ✅ DONE |
| Logger secret stripping — final gap closed | `DebugLogger.logApi()` req/resp/error bodies now redacted via `_redactBody()` (validationkey, k= tokens, JSESSIONID, Authorization/Bearer, access_token/refresh_token) before truncation/storage; verified no unredacted secret patterns reach any log call | `015bcea` | ✅ DONE |
| Rebrand zero-rating copy (hide JazzDrive) | `subscription_screen.dart` "JazzDrive CDN" line now attributes zero-rating to RaddFlix; `debug_diagnostics_screen.dart` "Oracle Server"/"JazzDrive API" check labels renamed to "Content Server"/"Stream Service", `JAZZDRIVE` log filter renamed to `STREAM`; Jazz SIM requirement copy and SIMOSA/JazzCash/Easypaisa payment copy left untouched; global grep confirms zero JazzDrive/Oracle occurrences in any `Text()`/`SnackBar`/label visible to users | `f3f6453` | ✅ DONE |

---

## UI Audit & CI Fix (2026-07-05)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| CI fix — PhosphorIcons.wifi | `app_icons.dart`: `PhosphorIcons.wifi()` → `PhosphorIcons.wifiHigh()` — icon renamed in phosphor_flutter 2.1.0; was the sole compile error blocking APK builds | `a4b946b` | ✅ DONE |
| UI audit — gate Server Downloads | `AppUser` model: add `isAdmin` field reading `is_admin` from JWT/JSON (defaults false). `profile_screen.dart`: "Server Downloads" row now guarded by `user?.isAdmin == true` instead of `user?.isGuest != true` — was visible to all paying users | `1e511a0` | ✅ DONE |
| UI audit — remove hardcoded prices | `tid_status_screen.dart`: plan label getter replaced `'Basic (₨149/month)'`/`Standard`/`Premium` with `'Basic Plan'`/`'Standard Plan'`/`'Premium Plan'` — hardcoded prices caused dispute risk if backend prices change | `22d1a93` | ✅ DONE |
| UI audit — fake→decoy wording | `vault_settings_screen.dart`: two user-visible strings changed from "fake vault / fake PIN" to "decoy vault / decoy PIN" — internal variable names unchanged | `ebf74b6` | ✅ DONE |
| ⚠️ OPEN — Flask send is_admin field | Flask `/me` endpoint (`radd-hub/hub/routes/mobile_api.py`) must add `is_admin` to the JSON response so the admin user can see "Server Downloads" in the app. Requires confirming `is_admin` column exists in `app_users` table (not currently in SELECT). Needs Oracle SSH + explicit user approval before touching production. | — | ⚠️ OPEN |

---

## Bug Fix Batch — Free/Paid Gate, Subtitle Panel, AI Dub, Misc (2026-07-05)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| D1 — subtitle download broken | `player_screen.dart` `_downloadOnlineSubtitle`: `'\${dir.path}/\$cleanName'` — backslash escapes kill interpolation, file written to literal path `${dir.path}/…`. Fix: remove backslashes. Same on snackbar line. | `71d9cb7` | ✅ DONE |
| A1 — BUG-FREE-PLAYER | `player_screen.dart` `_openMediaForEpisode` only reads `ep['is_free']` — ignores show-level `isFree`. Fix in `show_detail_screen.dart` `_playEpisodeImpl`: normalize every episode in `allSeasonsEps` to `is_free=1` when `widget.item.isFree==true` before passing to player. | `6f39440` | ✅ DONE |
| A2 — BUG-RESUME-MOVIE | `resume_fab.dart` `_play`: `?? false` default when `resume_is_free` key absent (old installs). Fix: treat absent key as `true` (free) for movies already in prefs — no key means it predates the BUG-11 write; safer to let them through than lock them out. | `55a2ab8` | ✅ DONE |
| B1+B2 — dub panel blocks settings | `player_screen.dart` `_SubtitlePanel`: AI Dub section pinned ABOVE tabs consumes ~213 dp — hides all settings in landscape. Fix: move into its own `AI Dub` tab; show tab only when `onDubRequested != null`. | `3d6cb2f` | ✅ DONE |
| C1 — TTS langResult=0 not caught | `subtitle_dubber.dart`: `langResult < 0` misses `0` (LANG_COUNTRY_AVAILABLE with no data). Add preflight: synthesize short string, check output file is non-empty. | `3d6cb2f` | ✅ DONE |
| C2 — TTS preflight test | `subtitle_dubber.dart`: after `setLanguage()`, synth `'test'` to temp file; if absent or zero bytes → `LANG_NOT_INSTALLED`. | `3d6cb2f` | ✅ DONE |
| C3 — TTS path fallback | `subtitle_dubber.dart`: try `getExternalStorageDirectory` then `getApplicationDocumentsDirectory` for clip lookup; already done in existing code. | — | ✅ DONE (pre-existing) |
| C4 — TTS better error snackbar | `player_screen.dart`: C1+C2 preflight now catches the failure early with `LANG_NOT_INSTALLED` status, so the existing prompt logic fires correctly without additional changes needed. | — | ✅ DONE (via C1/C2) |
| C5 — In-panel TTS install hint | `player_screen.dart` `_buildDubSection`: existing info row "Music + effects preserved via karaoke filter. 2-5 min first time." retained; TTS install guidance will display via the existing `LANG_NOT_INSTALLED` snackbar. | — | ⚠️ OPEN — add explicit "Install TTS pack" hint next to dub buttons in future pass |
| E1 — BUG-POSTER-WIPE | `local_db.dart` `upsertTitle`: `poster_path` missing from insert map — wiped to NULL on every full sync. Fix: add `'poster_path': item.posterPath`. | `6f39440` | ✅ DONE |
| E2 — BUG-IS_NEW-CAST | `catalog_item.dart`: `json['is_new'] as bool?` throws TypeError when server sends integer. Fix: `json['is_new'] == true \|\| json['is_new'] == 1`. | `6f39440` | ✅ DONE |
| E3 — BUG-MIXED-SEASON-DL | `show_detail_screen.dart` `_downloadCurrentSeason`: blanket gate blocks free episodes in mixed seasons. Fix: filter queue to free-only when unsubscribed instead of early-return. | `aa6d60c` | ✅ DONE |
| E4 — BUG-RESUME-MOUNTED | `show_detail_screen.dart`: cross-season resume uses `Future.microtask` — fires before rebuild, `_currentEpisodes` still old season, always returns -1. Fix: `addPostFrameCallback` + `mounted` guard. | `aa6d60c` | ✅ DONE |
| E5 — BUG-DL-ICON-DEAD-TERNARY | `show_detail_screen.dart` `_EpisodeTile`: `onDownload != null ? null : null` — disabled icon same color as enabled. Fix: use `t.textSecondary.withOpacity(0.35)` for disabled branch. | `aa6d60c` | ✅ DONE |
| E6 — BUG-SUB-NOT-REACTIVE | `show_detail_screen.dart`: added `ref.watch(authProvider)` + `ref.watch(subscriptionProvider)` at top of `build()` — PREMIUM lock badges now rebuild immediately when subscription activates. | `aa6d60c` | ✅ DONE |
| E7 — BUG-EPISODE-BADGE | `show_detail_screen.dart`: episode badge now uses `ep['episode']` actual number instead of list position `realIdx`. | `aa6d60c` | ✅ DONE |
| E8 — BUG-GUEST-CTA | `show_detail_screen.dart` `_requireSub`: guest now routed to `AppRoutes.login` instead of `AppRoutes.subscription` (which led to paywall+register). Label kept 'Sign In' as this now correctly routes to login. | `aa6d60c` | ✅ DONE |
| F1–F6 — zero-rated text cleanup | Removed/replaced JazzDrive brand text: subscription subtitle, `_JazzPartnerBadge` widget + class, `jazzSavingsMsg` plan card block, `_WhyRaddFlix` jazz item, onboarding slide, settings tile. | `2ccc373` | ✅ DONE |

---

## Adding new work here

1. Add a row with ⏳ IN PROGRESS *before* starting.
2. When done and pushed, flip to ✅ DONE and fill in the commit SHA — verify the SHA is real by
   re-fetching it from GitHub, don't just paste what the push command echoed.
3. Write the full detail (root cause, files touched, testing notes) into
   `agent-hub/history/TASK_LOG.md`, not into this file — this file stays a one-line-per-item index.
4. If a task is blocked or intentionally not automated (e.g. needs human judgment, touches
   production), mark it ⚠️ OPEN with a one-line reason instead of silently dropping it.

| G1 — SUBTITLE-PANEL-REWRITE | `player_screen.dart` `_SubtitlePanelState`: fix `sub-back-color` hex format, Box shadow, dual opacity, 5-tab layout, live preview, `_toMpvColor`/`_toMpvBackColor` helpers, `_SubTrackTile`+`_BigStepBtn`. | `778f17c` | ✅ DONE |
| G2 — SETTINGS-PANEL-POLISH | `player_screen.dart` `_SettingsPanelState`: progress bar style chips (Wrap), Controls/Navigation card sections with icon rows. | `778f17c` | ✅ DONE |
| H1 — AUDIO-LAB-BUGFIX | `player_screen.dart` `_AudioEffectPanel`: A1 logging, A2/A3 merged EQ (allMatches sum, no double-equalizer), A4 vocal-remover 0.5× scale, A5 MPV sync on open, A6 verified, Lab EQ coupling fix. Final commit: `9ee224d`. | `9ee224d` | ✅ DONE |
