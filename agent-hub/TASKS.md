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

## Open Tasks
None — all phases 17–26 complete (including audit pass). Awaiting next task.

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
