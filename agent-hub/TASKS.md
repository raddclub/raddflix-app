# RaddFlix Task Tracker

## All Phases 17-20 Complete

| Task | Phase | Status |
|------|-------|--------|
| Empty center (cinematic clean) | 17 | DONE |
| Transport row below seek bar | 17 | DONE |
| Remove CC/Audio/PiP/Rotate/Lock from top bar | 17 | DONE |
| Panel width 55% | 17 | DONE |
| Sidebar auto-hides when panel open | 17 | DONE |
| Both indicators on LEFT | 17 | DONE |
| sub-opacity subtitle fix | 17 | DONE |
| Sidebar width 54->64px | 18 | DONE |
| Accent chevron tab (AnimatedContainer) | 18 | DONE |
| Remove counter badge | 18 | DONE |
| Thin item separators | 18 | DONE |
| Left-border active state | 18 | DONE |
| Icon 20->22px, label 9->10px | 18 | DONE |
| Fix sleep shortcut onTap | 18 | DONE |
| A pin (green draggable flag on seek bar) | 19 | DONE |
| B pin (red draggable flag on seek bar) | 19 | DONE |
| Loop region band between A and B | 19 | DONE |
| Drag to adjust A/B without opening menu | 19 | DONE |
| Double-tap to clear pin | 19 | DONE |
| Subtitle margin 90→140px (clears transport row) | 20 | DONE |
| ASS subtitle font/color live update (sub-ass-override=force) | 20 | DONE |
| _isLocal class field (tracks local vs streaming) | 20 | DONE |
| Sidebar fully hides with controls (opacity 0.4→0.0) | 20 | DONE |
| Lock / Immersive / Settings in transport row | 20 | DONE |
| Guard Find-in-Another-Language for local files | 20 | DONE |
| FAB Resume Last Video in Local Media screen | 20 | DONE |
| Series auto-grouping in Local Folder (collapse/expand) | 20 | DONE |


| isAudio/isVideo detection in LocalVideo model | 21 | DONE |
| LocalFolder.folderType (audio/mixed/video) | 21 | DONE |
| Audio folder icon (🎵) in folder list | 21 | DONE |
| Mixed folder icon in folder list | 21 | DONE |
| Audio track count label in folder tiles | 21 | DONE |
| MUSIC badge on grid cards | 21 | DONE |
| MX-style Sort sheet in LocalMediaScreen | 21 | DONE |
| Sort by: Name, Date, Size, Count, Duration | 21 | DONE |
| A→Z / Z→A direction toggle in sort sheet | 21 | DONE |
| List/Grid layout toggle in LocalMediaScreen | 21 | DONE |
| MX-style Sort sheet in LocalFolderScreen | 21 | DONE |
| Sort by: Name, Date, Size, Duration, Resolution, Type | 21 | DONE |
| Type filter: All / Videos / Audio | 21 | DONE |
| AUDIO badge + music icon for audio files in folder | 21 | DONE |
| Type filter pills in stats bar (mixed folders) | 21 | DONE |

## Phase 26 — GB Subscription System (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| SUB-26-01 | subscription.dart: replace downloadsPerDay/hdAccess → GB fields (dataGb, usagePercent, daysUntilExpiry) | ✅ DONE |
| SUB-26-02 | subscription_api.dart: add getQuota(), resubscribe/upgrade support | ✅ DONE |
| SUB-26-03 | subscription_provider.dart: add refreshQuota(), resetTidSubmitted(), clearError flag | ✅ DONE |
| SUB-26-04 | usage_service.dart: add addDownloadBytes(); document free/local skip rules | ✅ DONE |
| SUB-26-05 | download_service.dart: count actual fileSize bytes toward quota at download completion | ✅ DONE |
| SUB-26-06 | player_screen.dart: _isFree + _trackUsage flags; quota gate in _openMedia; 30s usage timer; _startUsageTimer/_stopUsageTimer | ✅ DONE |
| SUB-26-07 | show_detail_screen.dart: pass 'is_free' in player route args for both episode and movie | ✅ DONE |
| SUB-26-08 | subscription_screen.dart: GB-based plan cards (big GB number + approx hours + Jazz savings), active plan progress bar, resubscribe/upgrade UI, catchy messaging | ✅ DONE |
| SUB-26-09 | quota_full_screen.dart: GB used/limit bar, reset date, catchy "You've Hit Your Data Limit" messaging, SIMOSA correctly labeled | ✅ DONE |
| SUB-26-10 | profile_screen.dart: live GB usage progress bar in subscription card | ✅ DONE |
| SUB-26-11 | mobile_api.py: 4 new seed plans (10GB/150, 30GB/250, 60GB/400, 100GB/700); _compute_app_quota enriched with is_exceeded + resets_at in all response paths | ✅ DONE |

## Phase 26 Bug Fixes — Audit Pass (2026-06-24)

| ID | Bug | Root Cause | Fix | Status |
|----|-----|-----------|-----|--------|
| BUG-26-A | GB usage bar always showed 0% in profile screen | `/status` backend response only returned plan limits, not usage data. `status.monthlyUsedGb` was always 0 | (1) `mobile_api.py` `/status` now includes full `quota` dict in response. (2) `profile_screen.dart` also calls `getQuota()` for guaranteed fresh data, with offline fallback | ✅ FIXED |
| BUG-26-B | Wrong variable name in `_startUsageTimer()` | `final h = _player.state.width ?? 0` — used `.width` but named it `h` (height) causing confusing quality detection logic | Renamed to `w` and updated comment to correctly say "from video width" | ✅ FIXED |
| BUG-26-C | `/status` guest response missing quota fields | Guest `_user_id==0` early-return didn't include quota — could cause null errors in `SubscriptionStatus.fromJson` | Added minimal quota dict to the guest early-return path | ✅ FIXED |

## Phase 38 — UI/UX Polish Pass (2026-06-30)

| ID | Task | Status |
|----|------|--------|
| UI-38-01 | profile_screen: double glow ring + bigger avatar (108px) + greeting "Good morning/afternoon/evening" | ✅ DONE |
| UI-38-02 | profile_screen: bigger name text (23px w800) + colored edit pencil badge | ✅ DONE |
| UI-38-03 | home_screen: personalized greeting row below app bar ("Good evening, Name 👋") | ✅ DONE |
| UI-38-04 | home_screen: app bar avatar upgraded (40px + outer ring + show emoji if set) | ✅ DONE |
| UI-38-05 | edit_profile_screen: bigger avatar (100px) + double glow ring + emoji in preview | ✅ DONE |
| UI-38-06 | edit_profile_screen: emoji row picker (20 emojis + None chip) | ✅ DONE |
| UI-38-07 | edit_profile_screen: pass avatarEmoji to updateProfile() | ✅ DONE |

## Phase 39 — Download Logic Audit & Fixes (2026-06-30)

### Bugs Found & Fixed

| ID | Bug | File | Status |
|----|-----|------|--------|
| BUG-39-01 | No duplicate-download guard in startDownload() — double-tap or batch loop starts two concurrent HTTP downloads writing to same .mp4 | downloads_provider.dart | ✅ DONE |
| BUG-39-02 | Episode tile onDownload null-guard missing isDownloading — second download triggerable while first in progress | show_detail_screen.dart | ✅ DONE |
| BUG-39-03 | Cancel left partial .mp4 on disk + stale 'cancelled' DB row forever; disk wasted until manual delete | download_service.dart | ✅ DONE |
| BUG-39-04 | cancelDownload() was sync/void — didn't reload downloads list → card stuck with 0% after cancel | downloads_provider.dart | ✅ DONE |
| BUG-39-05 | deleteDownload() called cancelDownload() without await (now async) → race condition | downloads_provider.dart | ✅ DONE |
| BUG-39-06 | _isDownloadingAll not in finally — uncaught exception left batch-download button permanently disabled | show_detail_screen.dart | ✅ DONE |
| BUG-39-07 | _DownloadCard/_DownloadListTile had no cancel action — only delete (cancel+delete combined) | downloads_screen.dart | ✅ DONE |
| BUG-39-08 | t.textSecondary used in _FeaturePill — field doesn't exist in RaddTheme → compile/runtime error | downloads_screen.dart | ✅ DONE |

### UI/UX Improvements

| ID | Change | Status |
|----|--------|--------|
| UI-39-01 | Active cards show ⬛ stop icon instead of 🗑 delete; tapping cancels without deleting the slot | ✅ DONE |
| UI-39-02 | Failed cards show 🗑 sweep icon + "Failed — delete & redownload" hint text | ✅ DONE |
| UI-39-03 | Active card progress % shown inline in info row (not separate line) | ✅ DONE |
| UI-39-04 | List tile active state shows "X% downloading…" text on progress row | ✅ DONE |

## Phase 40 — Downloads: Speed/ETA, Retry, Disk Space, Connectivity (2026-06-30)

### Features Added

| ID | Feature | Files | Status |
|----|---------|-------|--------|
| F-40-01 | Download speed (MB/s) + ETA display on active cards/tiles | download_service, downloads_provider, downloads_screen | ✅ |
| F-40-02 | Free disk space display in storage bar (colour-coded: red<200MB, amber<500MB) | downloads_provider, downloads_screen | ✅ |
| F-40-03 | Pre-download storage check: abort + user message if < 200 MB free | downloads_provider | ✅ |
| F-40-04 | In-screen retry for failed downloads (looks up share_url from catalog SQLite) | local_db, downloads_provider, downloads_screen | ✅ |
| F-40-05 | LocalDb.getFileInfo() — queries episodes then titles by file_id | local_db | ✅ |
| F-40-06 | Auto-retry on SocketException (network blip) after 4 s delay, 1 attempt | downloads_provider | ✅ |
| F-40-07 | Download completion SnackBar notification (green, title shown) | downloads_provider, downloads_screen | ✅ |
| F-40-08 | Queue position badge (#2, #3…) on active cards waiting to start | downloads_screen | ✅ |
| F-40-09 | Sort/filter/view mode persist via SharedPreferences (survive app restarts) | downloads_screen | ✅ |
| F-40-10 | Offline mode banner with ↺ refresh tap when connectivity lost | downloads_screen | ✅ |
| F-40-11 | Failed list-tile shows ↺ Retry + 🗑 Delete buttons side-by-side | downloads_screen | ✅ |

## Phase 41 — Animation Infrastructure (2026-06-30)

| ID | Task | Status |
|----|------|--------|
| ANIM-41-01 | Create AnimConfig singleton (anim_config.dart) — tier 0-3 detection via SDK version | ✅ DONE |
| ANIM-41-02 | shouldAnimate(ctx) — respects MediaQuery.disableAnimations accessibility setting | ✅ DONE |
| ANIM-41-03 | RepaintBoundary audit: home_screen (chips, grid, recommends) + downloads (shimmer, folders) | ✅ DONE |
| ANIM-41-04 | pubspec.yaml: add animations ^2.0.11, flutter_staggered_animations ^1.1.1, animated_text_kit ^4.2.2 | ✅ DONE |
| ANIM-41-05 | main.dart: Animate.restartOnHotReload = kDebugMode + animConfigProvider override in ProviderScope | ✅ DONE |
| ANIM-41-06 | Create anim_durations.dart — tier-aware fast/normal/slow/stagger/morph constants | ✅ DONE |

## Phase 42 — Hero Poster Transition (2026-06-30)

| ID | Task | Status |
|----|------|--------|
| ANIM-42-01 | home_screen: Hero(tag: 'poster_${item.id}') wraps _buildPosterImage() in _HeroCard | ✅ DONE |
| ANIM-42-02 | show_detail_screen: FlexibleSpaceBar banner replaced with Hero+Builder (collapses if/else) | ✅ DONE |
| ANIM-42-03 | search_screen: poster ClipRRect wrapped in Hero with matching tag | ✅ DONE |
| ANIM-42-04 | downloads_screen: skipped — downloads navigate to player not show_detail (no Hero path) | ⏭ SKIPPED |
| ANIM-42-05 | app.dart showDetail route: SlideTransition → FadeTransition (Hero-compatible) | ✅ DONE |

## Phase 43 — Staggered Grid/List Entry (2026-06-30)

| ID | Task | Status |
|----|------|--------|
| ANIM-43-01 | home_screen: animConfig + canAnimate in build(); chips + grid itemBuilder tier-gated | ✅ DONE |
| ANIM-43-02 | downloads_screen: _buildFolderView, _gridView, _listView — animConfig + tier-gated stagger | ✅ DONE |
| ANIM-43-03 | search_screen: _buildResults() — animConfig + tier-gated results stagger | ✅ DONE |
| ANIM-43-04 | Tier 0 policy: canStagger=false → raw widget; stagger(i)=0ms on potato tier | ✅ DONE |

## Phase 44 — Card → Detail Screen Morph (2026-06-30)

| ID | Task | Status |
|----|------|--------|
| ANIM-44-01 | home_screen: grid delegate → 3-way branch: OpenContainer (Tier2+) / stagger (Tier1) / raw (Tier0) | ✅ DONE |
| ANIM-44-02 | closedElevation: 0, openElevation: 0, transitionDuration: animConfig.slow | ✅ DONE |
| ANIM-44-03 | closedColor: Colors.transparent / openColor: Colors.transparent (no white flash) | ✅ DONE |
| ANIM-44-04 | Hero + OpenContainer conflict avoided: ContentCard in grid has no Hero; _SearchResultTile onTap overrides navigation | ✅ DONE |
| ANIM-44-05 | search_screen: _SearchResultTile gets VoidCallback? onTap; _buildResults canMorph branch; OpenContainer on Tier 2+ | ✅ DONE |

## Open Tasks
None — phases 17–44 complete. Phases 45–49 defined in agent-hub/ANIMATION_PLAN.md.

## Phase 37 — Bug Fixes (2026-06-29)

| ID | Task | Status |
|----|------|--------|
| BUG-37-01 | Remove share button from show_detail_screen (import + actions block) | ✅ DONE |
| BUG-37-02 | Remove quality picker from settings_screen (only one fixed video source) | ✅ DONE |
| BUG-37-03 | Remove defaultQuality storage key from constants.dart | ✅ DONE |
| BUG-37-04 | Fix free-content gate: guest/free users blocked on free content (4 call sites in show_detail_screen — isFreeEp, route args, downloadCurrentSeason, episode tile — now fall back to widget.item.isFree) | ✅ DONE |
| BUG-37-05 | Fix player transport row overlap: replace fixed SizedBox(108) right zone with Stack centering — play button always pixel-centered, nav+utility buttons share one full-width Row (no RenderFlex overflow) | ✅ DONE |
| BUG-37-06 | Fix theme picker cut off: showModalBottomSheet missing isScrollControlled:true + DraggableScrollableSheet — all 10 themes now visible | ✅ DONE |
| BUILD-FIX-37-01 | Re-add share_plus to pubspec (debug_logger.dart uses it to share crash logs — only UI button was removed) | ✅ DONE |


## Phase 22 — Bug Fixes (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| BUG-22-01 | Remove red dot indicator from bottom nav | ✅ DONE (3d1b275) |
| BUG-22-02 | Fix grey screen opening local folder (invalid (?i) regex → crash) | ✅ DONE (217f1e8) |
| BUG-22-03 | Add bottom nav to LocalMediaScreen | ✅ DONE (7ed61f7) |
| BUG-22-04 | Add bottom nav to DownloadsScreen | ✅ DONE (6a5e6e6) |
| BUG-22-05 | Add bottom nav to ProfileScreen | ✅ DONE (f938e67) |
| BUG-22-06 | Player sidebar default collapsed instead of expanded | ✅ DONE (493d842) |
| BUG-22-07 | Fix build: vault_service.dart imports local_auth/auth_strings.dart (removed in 2.x) | ✅ DONE |

## Phase 23 — Completing Task from Previous Session (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| BUG-23-01 | Fix authenticateBiometric: use getAvailableBiometrics() (Infinix/MediaTek Class 2 fix) | ✅ DONE |
| BUG-23-02 | Add to Vault from Downloads screen (selection toolbar vault button) | ✅ DONE |
| BUG-23-03 | Add to Vault from Local Media screen (folder long-press menu) | ✅ DONE |
| BUG-23-04 | LinearProgressIndicator on folder cards in LocalMediaScreen | ✅ DONE |

## Phase 24 — Oracle Backend Fixes (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| ORA-24-01 | Fix _legacy/scanner.py git conflict markers (SyntaxError crash-loop) | ✅ DONE (dde7498) |
| ORA-24-02 | Fix uploader.py: _release_stuck_uploads() before JAZZDRIVE+UPLOAD toggle gates | ✅ DONE (7974e8e) |
| ORA-24-03 | Admin upload.html: stuck-banner + reset-failed checkbox + 4s auto-poll + split stats | ✅ DONE (39b532a) |
| ORA-24-04 | Restart Oracle Flask + verify healthz {"ok":true,"version":"3.0.0"} | ✅ DONE |

## Phase 25 — Full Profile Edit Feature (2026-06-24)

| ID | Task | Status |
|----|------|--------|
| PRO-25-01 | AppUser model: displayName, email, avatarColor, avatarEmoji + displayLabel/avatarInitial getters | ✅ DONE (dc335f7) |
| PRO-25-02 | AuthApi: updateProfile() + changePassword() | ✅ DONE (dc335f7) |
| PRO-25-03 | ApiPaths: /api/auth/profile + /api/auth/change-password | ✅ DONE (dc335f7) |
| PRO-25-04 | EditProfileScreen: avatar color picker (8 colors), name/email fields, change-password bottom sheet | ✅ DONE (dc335f7) |
| PRO-25-05 | ProfileScreen: colored avatar, displayName label, edit pencil button | ✅ DONE (dc335f7) |
| PRO-25-06 | Oracle db.py: 4 new columns + additive migrations | ✅ DONE (dc335f7) |
| PRO-25-07 | Oracle mobile_api.py: PUT /profile + POST /change-password + /me returns new fields | ✅ DONE (dc335f7) |

## Phase 27 — Bug Audit Fixes (2026-06-25)

| ID | Task | Status |
|----|------|--------|
| BUG-C01 | player_screen: add sub+quota gate in _openMediaForEpisode | ✅ DONE |
| BUG-C02 | player_screen: update _isFree/_trackUsage in _openMediaForEpisode | ✅ DONE |
| BUG-C03 | auth_provider: fix _loadCachedUser hardcoded isActive:true | ✅ DONE |
| BUG-C04 | downloads_screen: add plan expiry check before playing downloaded content | ✅ DONE |
| BUG-H01 | quota_full_screen: read quota from provider instead of blank constructor | ✅ DONE |
| BUG-H02 | subscription_screen: block guest TID submission | ✅ DONE |
| BUG-H03 | show_detail: fix _downloadCurrentSeason to allow free episode batch-download | ✅ DONE |
| BUG-H04 | show_detail+player: gates check subscriptionProvider.status not stale auth | ✅ DONE |
| BUG-H05 | splash_screen: call loadStatus() after auth confirmed | ✅ DONE |
| BUG-M01 | home_screen: use user.avatarInitial not phone[0] | ✅ DONE |
| BUG-M02 | show_detail: pass episodes in ascending order to player regardless of sort | ✅ DONE |
| BUG-M03 | subscription_provider: set error state in refreshQuota() | ✅ DONE |
| BUG-M04 | subscription_provider: add loading flag to loadStatus() | ✅ DONE |
| BUG-M05 | player_screen: re-read is_free from episode map not stale route args | ✅ DONE |
| BUG-M06 | show_detail: pass all seasons episodes to player not just current season | ✅ DONE |

## Phase 28 — Build Fix (2026-06-26)

| ID | Task | Status |
|----|------|--------|
| BUG-28-01 | Fix app.dart: QuotaFull route used s.settings on BuildContext — must use ModalRoute.of(s) | ✅ DONE (1354ae5) |

## Phase 28B — Oracle Sync: downloader.py ZIP fix (2026-06-26)

| ID | Task | Status |
|----|------|--------|
| BUG-28-02 | Sync Oracle downloader.py ZIP extraction fix to GitHub (was live on server, not in repo) | ✅ DONE (40fcbdc) |

## Phase 29 — Agent Prompt & Push Helper Refactor (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| AGT-29-01 | Rewrite AGENT_PROMPT.md: eliminate /tmp file content dependency, condense 349→~185 lines, remove stale player_screen status table, trim 22 inline rules to 12 critical ones | ✅ DONE (0709faa) |
| AGT-29-02 | Create agent-hub/scripts/push.js: canonical readFile/pushFile/pushTree helper, downloaded once per session | ✅ DONE (fcf4af5) |

## Phase 29B — Prompt Token Optimisation (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| AGT-29B-01 | Idempotent session init: SSH key + push helper skip if already present | ✅ DONE (5517cc3) |
| AGT-29B-02 | All /tmp refs removed — ~/.ssh/raddflix_oracle + workspace/.local/ only | ✅ DONE (5517cc3) |
| AGT-29B-03 | TASK_LOG curl made opt-in (commented out) — skip when not needed | ✅ DONE (5517cc3) |
| AGT-29B-04 | Code examples tightened, rule descriptions shortened | ✅ DONE (5517cc3) |
| AGT-29B-05 | Oracle file paths condensed in key paths table | ✅ DONE (5517cc3) |

## Phase 30 — push.js Retry Logic (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| AGT-30-01 | Split api() into _request() (single attempt) + api() (retry wrapper) | ✅ DONE (a4e4395) |
| AGT-30-02 | Retry on network errors: ECONNRESET, ETIMEDOUT, ENOTFOUND, ECONNREFUSED, EPIPE | ✅ DONE (a4e4395) |
| AGT-30-03 | Retry on HTTP 429: respect Retry-After header, default 60s | ✅ DONE (a4e4395) |
| AGT-30-04 | Retry on HTTP 5xx: exponential backoff 1s/2s/4s (max 3 retries) | ✅ DONE (a4e4395) |
| AGT-30-05 | Never retry 4xx (SHA conflict, not found etc — logic errors, not transient) | ✅ DONE (a4e4395) |
| AGT-30-06 | Update download comment in push.js to workspace path (not /tmp) | ✅ DONE (a4e4395) |

## Phase 31 — push.js validatePatch() (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| AGT-31-01 | validatePatch(content, oldString, repoPath?): throws if oldString not in content | ✅ DONE (b160b9a) |
| AGT-31-02 | Error includes first 120 chars of oldString (newlines shown as ↵) | ✅ DONE (b160b9a) |
| AGT-31-03 | Error includes up to 3 nearest matching lines from the file (word-overlap scoring) | ✅ DONE (b160b9a) |
| AGT-31-04 | Error includes re-read hint so agent knows how to recover | ✅ DONE (b160b9a) |
| AGT-31-05 | validatePatch exported in module.exports | ✅ DONE (b160b9a) |

## Phase 31B — Prompt: validatePatch in examples (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| AGT-31B-01 | Step 3b: import validatePatch in require() line | ✅ DONE (6f172f1) |
| AGT-31B-02 | Step 3b: replace manual before/after check with validatePatch(dart, OLD, FILE) | ✅ DONE (6f172f1) |
| AGT-31B-03 | Step 3b: show validatePatch on TASKS.md replace too (agents always need this) | ✅ DONE (6f172f1) |
| AGT-31B-04 | Step 3c pushTree example: add validatePatch calls before each .replace() | ✅ DONE (6f172f1) |
| AGT-31B-05 | Key file paths: update push.js description to list validatePatch | ✅ DONE (6f172f1) |

## Phase 32 — Build Fix: edit_profile_screen corruption (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| BUG-32-01 | Fix broken regex + duplicate class defs in edit_profile_screen.dart (build error run#1320) | ✅ DONE (e286322) |

## Phase 33 — Build Fix: downloads_screen + content_card (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| BUG-33-01 | downloads_screen: fix 3 arrow-callback semicolon syntax errors | ✅ DONE (0e44ecd) |
| BUG-33-02 | content_card: add missing comma after Text() in Column children | ✅ DONE (0e44ecd) |

## Phase 34 — Build Fix: downloads_screen _savePrefs (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| BUG-34-01 | downloads_screen: remove 3 calls to non-existent _savePrefs() method | ✅ DONE (0de6b07) |

## Phase 35 — UI/UX Completion Pass (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| UI-35-01 | home_screen: _CategoryChip checkmark icon for selected state | ✅ DONE (39f1d9f) |
| UI-35-02 | search_screen: upgrade _SearchResultTile._buildPoster (local file + CachedNetworkImage) | ✅ DONE (39f1d9f) |
| UI-35-03 | search_screen: genre section headers with accent bar + count badge | ✅ DONE (39f1d9f) |
| UI-35-04 | splash_screen: corner glows + 3-dot branded loader | ✅ DONE (39f1d9f) |

## Phase 35B — Build Fix (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| BUG-35B-01 | search_screen: CachedNetworkImage errorWidget (not errorBuilder) | ✅ DONE (9ed66e1) |

## Phase 36 — Missing Features Pass (2026-06-28)

| ID | Task | Status |
|----|------|--------|
| FEAT-36-01 | settings_screen.dart: new screen (quality, subtitle default, cache clear, version, about) | ✅ DONE (2975c52) |
| FEAT-36-02 | constants.dart: AppRoutes.settings + StorageKeys.defaultQuality/subtitleDefault | ✅ DONE (975e62b) |
| FEAT-36-03 | app.dart: import + register /settings route | ✅ DONE (6fbeb10) |
| FEAT-36-04 | profile_screen.dart: General section with Settings tile | ✅ DONE (2975c52) |
| FEAT-36-05 | show_detail_screen.dart: share button in SliverAppBar (share_plus) | ✅ DONE (2975c52) |
| FEAT-36-06 | show_detail_screen.dart: "More Like This" horizontal scroll (genre-matched) | ✅ DONE (2975c52) |


---

## 🎬 Animation Roadmap — Phases 41–49
> Full spec: agent-hub/ANIMATION_PLAN.md
> Performance-first: every animation is gated by AnimConfig tier (0=potato → 3=premium).
> minSdkVersion = 21 (Android 5). Target audience: Pakistani low-end phones.

### Phase 41 — Performance Infrastructure *(START HERE — blocks all other phases)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-41-01 | Create `lib/core/utils/anim_config.dart` — AnimConfig class + AnimTier enum | ⏳ TODO |
| ANIM-41-02 | `AnimConfig.shouldAnimate(ctx)` checks `MediaQuery.disableAnimations` first | ⏳ TODO |
| ANIM-41-03 | Add `animConfigProvider` Riverpod provider; initialize in main.dart with `AnimConfig.detect()` | ⏳ TODO |
| ANIM-41-04 | Create `lib/core/utils/anim_durations.dart` — tier-aware duration constants | ⏳ TODO |
| ANIM-41-05 | Add `animations: ^2.x`, `flutter_staggered_animations: ^1.x`, `animated_text_kit: ^4.x` to pubspec.yaml | ⏳ TODO |
| ANIM-41-06 | Audit home_screen + downloads_screen: wrap isolated animated widgets with `RepaintBoundary` | ⏳ TODO |
| ANIM-41-07 | Set `Animate.restartOnHotReload = kDebugMode` in main.dart | ⏳ TODO |

### Phase 42 — Hero Poster Transition *(built-in Flutter, zero cost, API 21+)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-42-01 | Home screen grid cards: `Hero(tag: 'poster_${item.id}')` on poster image | ⏳ TODO |
| ANIM-42-02 | show_detail_screen banner: matching `Hero(tag: 'poster_${item.id}')` | ⏳ TODO |
| ANIM-42-03 | search_screen result cards: same Hero tag pattern | ⏳ TODO |
| ANIM-42-04 | downloads_screen grid cards: `Hero(tag: 'dl_poster_${fileId}')` | ⏳ TODO |
| ANIM-42-05 | Replace default MaterialPageRoute slide with `FadeTransition` page route in app.dart | ⏳ TODO |

### Phase 43 — Staggered Grid / List Entry *(flutter_staggered_animations, Tier 1+)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-43-01 | Home screen content grid: `AnimationLimiter` + `staggeredGrid` + `FadeIn` + `SlideAnimation` | ⏳ TODO |
| ANIM-43-02 | Downloads grid: replace current per-item `.animate(delay:)` with proper AnimationLimiter | ⏳ TODO |
| ANIM-43-03 | Search results grid/list: stagger with same config | ⏳ TODO |
| ANIM-43-04 | show_detail "More Like This" horizontal list: stagger | ⏳ TODO |
| ANIM-43-05 | All stagger gated: `anim.canStagger && anim.shouldAnimate(context)` | ⏳ TODO |

### Phase 44 — Card → Detail Morph *(animations package, Tier 2+)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-44-01 | Home screen cards: wrap with `OpenContainer` (Tier 2+) | ⏳ TODO |
| ANIM-44-02 | `closedColor: Colors.transparent`, `closedElevation: 0`, correct transition duration | ⏳ TODO |
| ANIM-44-03 | Remove Hero tags from OpenContainer cards (they conflict) | ⏳ TODO |
| ANIM-44-04 | Search result cards: same OpenContainer (Tier 2+) | ⏳ TODO |
| ANIM-44-05 | Tier 0/1 fallback: plain Navigator.push (no morph, identical behavior) | ⏳ TODO |

### Phase 45 — Glow on Primary Action Buttons *(flutter_animate, all tiers)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-45-01 | Play button: pulsing BoxShadow glow via flutter_animate `.boxShadow().animate(repeat)` | ⏳ TODO |
| ANIM-45-02 | Tier 2: stronger shadow + subtle scale breathing (1.0 → 1.03 → 1.0) | ⏳ TODO |
| ANIM-45-03 | Download button: glow pulses while download is actively running | ⏳ TODO |
| ANIM-45-04 | Download complete: shake + burst scale animation on SnackBar icon | ⏳ TODO |
| ANIM-45-05 | Tier 3: optionally add `glow_effects` NeonGlowEffect — only if no crash on test devices | ⏳ TODO |

### Phase 46 — Typewriter & Animated Text *(animated_text_kit, Tier 1+)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-46-01 | show_detail_screen synopsis: `TypewriterAnimatedText` (18ms/char, no cursor) | ⏳ TODO |
| ANIM-46-02 | Start typewriter only after page transition + 300ms delay (addPostFrameCallback) | ⏳ TODO |
| ANIM-46-03 | Hero banner tagline: `FadeAnimatedText` looping tagline + year + rating | ⏳ TODO |
| ANIM-46-04 | Downloads storage bar: `WavyAnimatedText` "loading" label when active > 0 | ⏳ TODO |
| ANIM-46-05 | Tier 0 fallback: plain `Text` widget everywhere | ⏳ TODO |

### Phase 47 — Frosted Glass Bottom Nav *(BackdropFilter, Tier 2+)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-47-01 | bottom_nav.dart: `BackdropFilter blur(12,12)` + semi-transparent bg on Tier 2+ | ⏳ TODO |
| ANIM-47-02 | Tier 0/1: solid background unchanged | ⏳ TODO |
| ANIM-47-03 | `extendBody: true` in Scaffold + bottom padding in all main screens | ⏳ TODO |
| ANIM-47-04 | Verify no layout clip/overlap on all screen sizes | ⏳ TODO |

### Phase 48 — 3D Tilt Hero Banner *(sensors_plus + Transform, Tier 3)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-48-01 | Add `sensors_plus` to pubspec (Tier 3 only) | ⏳ TODO |
| ANIM-48-02 | Home screen hero banner: gyroscope listener → `Matrix4` rotateX/Y (max ±8°, 0.08 lerp) | ⏳ TODO |
| ANIM-48-03 | Parallax layers: poster ×1.0, title text ×0.4 depth factor | ⏳ TODO |
| ANIM-48-04 | Tier 2 fallback: gentle sine-wave auto-float (no gyroscope needed) | ⏳ TODO |
| ANIM-48-05 | Sensor listener disposed in dispose() — no exceptions | ⏳ TODO |

### Phase 49 — Ambient Particle Background *(particles_flutter, Tier 3, splash/login only)*

| Task ID | Task | Status |
|---------|------|--------|
| ANIM-49-01 | Add `particles_flutter` to pubspec | ⏳ TODO |
| ANIM-49-02 | splash_screen: `ParticleField` bg (25 particles max, speed 0.3, opacity 0.3, NO connect lines) | ⏳ TODO |
| ANIM-49-03 | login screen (if applicable): same particle config | ⏳ TODO |
| ANIM-49-04 | Particle controller disposed in dispose() | ⏳ TODO |
| ANIM-49-05 | Tier 0/1/2: static background (no particles) | ⏳ TODO |

---

### 🛡️ Hard Rules for Every Animation Phase

> An agent MUST verify these before marking any ANIM task as DONE:
> 1. ✅ Gated behind `AnimConfig.tier` check
> 2. ✅ Respects `MediaQuery.disableAnimations`
> 3. ✅ No `BackdropFilter` on API < 28 (Tier < 2)
> 4. ✅ No fragment shaders on API < 26 (Tier < 2)
> 5. ✅ `RepaintBoundary` on every isolated animated widget
> 6. ✅ All controllers/listeners disposed in `dispose()`
> 7. ✅ Tested on API-21 emulator — must not crash or jank
> 8. ✅ Duration ≤ 350ms on Tier 0/1
