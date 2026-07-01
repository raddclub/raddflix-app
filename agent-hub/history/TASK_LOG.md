# RaddFlix Task Log

## Session 2026-06-29 — Phase 37: UI Bug Fixes

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-37-01 | Remove share button from show_detail_screen (import + SliverAppBar actions block) | DONE |
| BUG-37-02 | Remove quality picker from settings_screen (only one fixed video source exists) | DONE |
| BUG-37-03 | Remove defaultQuality storage key from constants.dart | DONE |
| BUG-37-04 | Fix free-content gate: 4 call sites in show_detail_screen now use `_parseFree(ep['is_free']) || widget.item.isFree` — free/guest users can watch free content without subscribe prompt | DONE |
| BUG-37-05 | Fix player transport row RenderFlex overflow — replaced fixed-width SizedBox(108) right zone with Stack approach: play/pause always pixel-centered, nav+utility buttons in single full-width Row | DONE |
| BUG-37-06 | Fix theme picker cut off — added isScrollControlled:true + DraggableScrollableSheet to showModalBottomSheet; all 10 themes (4 standard + 6 color) now visible | DONE |
| BUILD-FIX-37-01 | Re-add share_plus to pubspec.yaml (debug_logger.dart uses Share API for crash log sharing) | DONE |

### Root cause of free-content gate bug (BUG-37-04)
When the backend returns episodes without an explicit `is_free` field (null/absent), `_parseFree()` defaults to false (paid). If the parent CatalogItem has `isFree=true` (catalog sync sets this), the episodes inherited no free status. Fix: all 4 call sites in show_detail_screen now OR with `widget.item.isFree` so the parent's flag propagates to all episode-level gates.

### Build status
- All 6 commits pushed, CI passed ✅ (run#1341+)
- Latest successful build: pubspec share_plus restore commit

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: PASSING ✅
- Open tasks: none

---


## Session 2026-06-07 — OPS-01 Session Expired Fix

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| OPS-01 | Fix JazzDrive session expiry / auto-re-auth | DONE |

### State at end of session
- Oracle Flask: RUNNING
- Account: ACTIVE
- Open tasks: none


---

## Session 2026-06-18 — Phase 19: A/B Pin Loop + Phase 20: Subtitle/Local Cleanup

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| P19-01 | A pin (green draggable flag) on seek bar | DONE |
| P19-02 | B pin (red draggable flag) on seek bar | DONE |
| P19-03 | Loop region band between A and B | DONE |
| P19-04 | Drag to adjust A/B without opening menu | DONE |
| P19-05 | Double-tap to clear pin | DONE |
| P20-01 | Subtitle margin 90→140px (clears transport row) | DONE |
| P20-02 | ASS subtitle font/color live update (sub-ass-override=force) | DONE |
| P20-03 | _isLocal class field (tracks local vs streaming) | DONE |
| P20-04 | Sidebar fully hides with controls (opacity 0.4→0.0) | DONE |
| P20-05 | Lock / Immersive / Settings in transport row | DONE |
| P20-06 | Guard Find-in-Another-Language for local files | DONE |
| P20-07 | FAB Resume Last Video in Local Media screen | DONE |
| P20-08 | Series auto-grouping in Local Folder (collapse/expand) | DONE |
| FIX-VF-BLACKSCREEN-GAP | _applyVideoFilters startup gate: set _lastAppliedVf even when blocked | DONE (a7898f8) |
| FIX-BLACKSCREEN-LP2 | Recovery seek on longPress START (framedrop+speed set) | DONE (69824d79) |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 21: Local Media Audio/Sort/Filter

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| P21-01 | isAudio/isVideo detection in LocalVideo model | DONE |
| P21-02 | LocalFolder.folderType (audio/mixed/video) | DONE |
| P21-03 | Audio folder icon in folder list | DONE |
| P21-04 | Mixed folder icon in folder list | DONE |
| P21-05 | Audio track count label in folder tiles | DONE |
| P21-06 | MUSIC badge on grid cards | DONE |
| P21-07 | MX-style Sort sheet in LocalMediaScreen | DONE |
| P21-08 | Sort by Name/Date/Size/Count/Duration | DONE |
| P21-09 | A→Z / Z→A direction toggle | DONE |
| P21-10 | List/Grid layout toggle in LocalMediaScreen | DONE |
| P21-11 | MX-style Sort sheet in LocalFolderScreen | DONE |
| P21-12 | Sort by Name/Date/Size/Duration/Resolution/Type | DONE |
| P21-13 | Type filter: All / Videos / Audio | DONE |
| P21-14 | AUDIO badge + music icon for audio files in folder | DONE |
| P21-15 | Type filter pills in stats bar (mixed folders) | DONE |
| BUILD-FIX-01 | Fix const MethodChannel compile error in local_media_screen.dart:378 | DONE (310016f) |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 22: Bug Fixes

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-22-01 | Remove red dot indicator from bottom nav | DONE (3d1b275) |
| BUG-22-02 | Fix grey screen opening local folder (invalid (?i) regex crash) | DONE (217f1e8) |
| BUG-22-03 | Add bottom nav to LocalMediaScreen | DONE (7ed61f7) |
| BUG-22-04 | Add bottom nav to DownloadsScreen | DONE (6a5e6e6) |
| BUG-22-05 | Add bottom nav to ProfileScreen | DONE (f938e67) |
| BUG-22-06 | Player sidebar default collapsed instead of expanded | DONE (493d842) |
| BUG-22-07 | Fix build: vault_service.dart imports local_auth/auth_strings.dart (removed in 2.x) | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 23: Vault + Biometrics

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-23-01 | Fix authenticateBiometric: use getAvailableBiometrics() (Infinix/MediaTek Class 2 fix) | DONE |
| BUG-23-02 | Add to Vault from Downloads screen (selection toolbar vault button) | DONE |
| BUG-23-03 | Add to Vault from Local Media screen (folder long-press menu) | DONE |
| BUG-23-04 | LinearProgressIndicator on folder cards in LocalMediaScreen | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered after fixes
- Open tasks: none


---

## Session 2026-06-24 — Phase 24: Oracle Backend Fix (from previous agent's incomplete task)

### Context
Previous agent session ran out of quota while fixing the JazzDrive auto-upload pipeline.
The agent had pushed Python fixes to GitHub but:
1. Never pulled them to the Oracle server
2. Left `hub/_legacy/scanner.py` with 3 git merge conflict markers → SyntaxError
3. Oracle Flask was in a crash-loop (schema-check spam in logs every 2s)

### Root cause of crash-loop
`hub/_legacy/scanner.py` had git conflict markers at lines 699, 1227, 1263 from a failed
`git stash pop`. Import chain: `hub.app` → `hub.routes.scan` → `hub.scanner` →
`hub._legacy.scanner` → **SyntaxError** → supervisord restart every 2s.

### What was already completed by previous agent
- `uploader.py` watcher_loop: `_release_stuck_uploads()` correctly moved before both
  JAZZDRIVE_ENABLED and UPLOAD_ENABLED toggle checks (working tree on server was already fixed)
- `upload.html`: stuck-banner, reset-incl-failed checkbox, 4s auto-poll for jobs table,
  split pending stats (queued vs uploading) — all in server's working tree

### Tasks completed this session
| ID | Task | Status |
|----|------|--------|
| ORA-24-01 | Resolve 3 conflict markers in _legacy/scanner.py (take stashed: DB device_id, cleaner Accept header) | DONE (dde7498) |
| ORA-24-02 | Push corrected uploader.py from Oracle server to GitHub | DONE (7974e8e) |
| ORA-24-03 | Push corrected upload.html from Oracle server to GitHub | DONE (39b532a) |
| ORA-24-04 | Restart Oracle Flask — verified {"ok":true,"version":"3.0.0"} | DONE |

### Files changed
| File | Change |
|------|--------|
| hub/_legacy/scanner.py | Resolved 3 conflict markers (stashed version: DB device_id/name, Accept: application/json) |
| hub/uploader.py | _release_stuck_uploads() before both toggle gates — pushed server's working version |
| hub/templates/upload.html | Stuck-banner + reset-failed checkbox + 4s poll — pushed server's working version |

### State at end of session
- Oracle Flask: RUNNING pid 780429, {"ok":true,"version":"3.0.0"}
- APK build: triggered (monitoring)
- Open tasks: none


---

## Session 2026-06-24 — Phase 25: Full Profile Edit Feature

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| PRO-25-01 | AppUser model — displayName, email, avatarColor, avatarEmoji + display getters | DONE |
| PRO-25-02 | AuthApi — updateProfile() PUT + changePassword() POST | DONE |
| PRO-25-03 | ApiPaths — /api/auth/profile, /api/auth/change-password | DONE |
| PRO-25-04 | EditProfileScreen — avatar color picker, name/email fields, change-password sheet | DONE |
| PRO-25-05 | ProfileScreen — colored avatar ring, displayName, edit pencil overlay | DONE |
| PRO-25-06 | Oracle db.py — display_name/email/avatar_color/avatar_emoji columns + safe migrations | DONE |
| PRO-25-07 | Oracle mobile_api.py — PUT /profile + POST /change-password + /me extended | DONE |

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/models/user.dart | +displayName, email, avatarColor, avatarEmoji, displayLabel, avatarInitial |
| raddflix_flutter/lib/core/api/auth_api.dart | +updateProfile(), +changePassword() |
| raddflix_flutter/lib/core/constants.dart | +ApiPaths.updateProfile, .changePassword |
| raddflix_flutter/lib/screens/edit_profile_screen.dart | NEW — full profile editor |
| raddflix_flutter/lib/screens/profile_screen.dart | Avatar uses color/name, edit pencil button |
| hub/routes/mobile_api.py | PUT /api/auth/profile, POST /api/auth/change-password, /me extended |
| hub/db.py | 4 new app_users columns + safe ALTER TABLE migrations |

### State at end of session
- Oracle Flask: restarted with new endpoints
- APK build: triggered
- Open tasks: none


---

## Session 2026-06-24 — Verification & Doc Sync

### Context
User requested verification that all previously logged tasks were completed.
Confirmed all phases 17–25 done, latest APK build run#1267 successful on commit e20a8df.

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| VER-01 | Verified all phases 17–25 marked DONE in TASKS.md | DONE |
| VER-02 | Confirmed latest APK build run#1267 success on commit e20a8df | DONE |
| VER-03 | Fixed duplicate Open Tasks section in TASKS.md | DONE |
| VER-04 | Created AGENT_HANDOFF.md with current state | DONE |
| VER-05 | Appended session summary to TASK_LOG.md | DONE |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- APK build: ✅ run#1267 success (e20a8df)
- Open tasks: none

---

## Session 2026-06-26 — Build Fix: ModalRoute args in app.dart

### Context
Last 5 APK builds (run#1306–1310) were all failing with a single Dart compile error:
  lib/app.dart:110:24: Error: The getter 'settings' isn't defined for the class 'BuildContext'.
The BUG-H01 fix in a previous session added a quotaFull route builder that used `s.settings.arguments`
where `s` is a `BuildContext` (Flutter `routes` map WidgetBuilders only receive BuildContext).
Fix: replaced with `ModalRoute.of(s)?.settings.arguments` which is the correct API.

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-28-01 | app.dart: ModalRoute.of(s) fix for quotaFull route args | DONE (1354ae5) |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/lib/app.dart | QuotaFull route: s.settings → ModalRoute.of(s)?.settings | 1354ae5 |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- Build: triggered (run#1311 in progress)
- Open tasks: see TASKS.md

---

## Session 2026-06-26B — Oracle downloader.py ZIP fix sync to GitHub

### Context
Previous agent applied ZIP extraction fix to Oracle live server but never pushed to GitHub.
Two bugs were fixed on Oracle but were missing from GitHub:
1. ZIP files were renamed by derive_media_plan before extraction (treated as movie).
   If extraction failed the code fell through to split_large_file, uploader rejected it.
   Fix: skip rename for .zip files.
2. extract_zip returns the original zip path on failure. Now skips upload with error log.

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| BUG-28-02 | Push Oracle live downloader.py (with ZIP fix) to GitHub | DONE (40fcbdc) |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| hub/downloader.py | ZIP extraction bugs fixed — pulled from Oracle live server | 40fcbdc |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- downloader.py: in sync between Oracle and GitHub
- APK build run#1311/1312: in progress on 1354ae5
- Open tasks: DATA-01 (All Of Us Are Dead missing episodes)

---

## Session 2026-06-28 — Agent Prompt & Push Helper Refactor

### Context
User requested AGENT_PROMPT.md be simplified and made more reliable for AI agents.
Key problem: Step 2.5 told agents to download files to /tmp/raddflix/ for editing,
but /tmp is ephemeral and gets wiped after a few hours — any long session risked pushing
stale or empty file content. Also the prompt was 349 lines with duplicated push boilerplate
appearing 3 times and a stale player_screen status table.

### Changes made
| ID | Task | Commit |
|----|------|--------|
| AGT-29-01 | Rewrote AGENT_PROMPT.md — no /tmp file dependency, push helper reference, condensed rules | 0709faa |
| AGT-29-02 | Created agent-hub/scripts/push.js — readFile/pushFile/pushTree/delay helper | fcf4af5 |

### What changed in the prompt
- Dropped Step 2.5 (local /tmp workspace) — replaced with read-from-GitHub-in-memory pattern
- push.js helper now lives in repo; agents download it once, reuse all session
- pushFile() signature changed: takes string content (not local file path) — no /tmp needed
- Removed player_screen.dart status table (goes stale every session — lives in AGENT_HANDOFF.md)
- 22 inline rules condensed to 12 critical ones in a clean table; pointer to RULES.md for rest
- Push boilerplate reduced from 3 duplicate blocks to 1 canonical example
- Prompt: 349 lines → ~185 lines

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- AGENT_PROMPT.md: 0709faa
- agent-hub/scripts/push.js: fcf4af5
- Open tasks: none

---

## Session 2026-06-28B — Prompt Token Optimisation

### Context
User asked to eliminate all remaining /tmp usage and avoid wasting tokens on repeat sessions.

### Changes
| ID | Change | Commit |
|----|--------|--------|
| AGT-29B-01 | Idempotent init block: [\ -f ] checks skip SSH key + push helper if already present | 5517cc3 |
| AGT-29B-02 | All /tmp refs removed — ~/.ssh/raddflix_oracle + workspace/.local/ | 5517cc3 |
| AGT-29B-03 | TASK_LOG curl opt-in only (saves ~60 lines of context when not needed) | 5517cc3 |
| AGT-29B-04 | Code examples tightened, obvious comments removed | 5517cc3 |
| AGT-29B-05 | Oracle file paths table condensed to one line | 5517cc3 |

### Result
- Prompt: 207 lines → 168 lines
- Repeat sessions: SSH key + push helper setup skipped if workspace already initialised
- TASK_LOG: only fetched when agent needs historical context

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- AGENT_PROMPT.md: 5517cc3
- TASKS.md: 1370da2
- Open tasks: none

---

## Session 2026-06-28C — push.js Retry Logic

### Context
Added exponential-backoff retry logic to agent-hub/scripts/push.js so agent sessions
survive transient GitHub API failures (5xx, 429 rate limits, network drops) without
failing the entire push script.

### Design decisions
- _request() handles one HTTP attempt and resolves { status, body, headers }
- api() wraps _request with a retry loop (max 3 attempts)
- Retryable: network errors (ECONNRESET/ETIMEDOUT/etc), HTTP 429, HTTP 5xx
- Never retried: HTTP 4xx — these are logic errors (wrong SHA = 422, missing file = 404)
- 429 respects Retry-After header; falls back to 60s if header absent
- 5xx uses exponential backoff: 1s, 2s, 4s
- All existing callers (readFile, pushFile, pushTree) get retry for free — no changes needed

### Files changed
| File | Commit |
|------|--------|
| agent-hub/scripts/push.js | a4e4395 |
| agent-hub/TASKS.md | 1da1053 |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- push.js: a4e4395
- Open tasks: none

---

## Session 2026-06-28D — push.js validatePatch()

### Context
Added validatePatch() helper to agent-hub/scripts/push.js to catch silent no-op patches
before they reach GitHub. Previously an agent could call content.replace(OLD, NEW) with
a wrong OLD string, get back the original content unchanged, and push it silently —
wasting a commit and leaving the intended change unapplied with no error.

### Design
- validatePatch(content, oldString, repoPath?) — call before every .replace()
- Throws immediately if oldString is not found in content
- Error message shows: first 120 chars of oldString (↵ for newlines)
- Nearest-line hints: scores every file line by word-overlap with first line of oldString,
  shows top 3 matches so agent can see what the code looks like now vs what it expected
- Recovery hint: "re-read the file — it may have changed since you fetched it"

### Usage pattern (add to all session scripts)
  validatePatch(dart, OLD_STRING, 'screens/player_screen.dart');
  dart = dart.replace(OLD_STRING, NEW_STRING);

### Files changed
| File | Commit |
|------|--------|
| agent-hub/scripts/push.js | b160b9a |
| agent-hub/TASKS.md | 5929d84 |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- push.js: b160b9a (retry logic + validatePatch)
- Open tasks: none

---

## Session 2026-06-28E — Prompt: validatePatch wired into examples

### Context
validatePatch() was added to push.js in session D but AGENT_PROMPT.md still showed the old
manual pattern (const before = dart; ... if (dart === before) throw new Error(...)).
Agents follow the example literally — so until the example shows validatePatch, they won't use it.

### Changes
- Step 3b require() line: added validatePatch to destructuring
- Step 3b main example: OLD/NEW defined as consts at top; validatePatch(dart, OLD, FILE) before replace()
- Step 3b: validatePatch also shown on TASKS.md replace (agents need it there too)
- Step 3c pushTree example: validatePatch before each .replace()
- Key file paths: push.js description updated to list validatePatch

### Files changed
| File | Commit |
|------|--------|
| AGENT_PROMPT.md | 6f172f1 |
| agent-hub/TASKS.md | d5b962d |

### State at end of session
- Oracle Flask: RUNNING (v3.0.0)
- push.js: b160b9a (retry logic + validatePatch)
- AGENT_PROMPT.md: 6f172f1
- Open tasks: none

---

## Session 2026-06-28 — Build fix: edit_profile_screen corruption

- Task: BUG-32-01 — Repaired broken raw-string regex (line 64) and removed 603-line duplicate class block (lines 663-1265) in edit_profile_screen.dart
- Root cause: Previous agent patch truncated the raw-string regex end, then re-appended the full second half of the file as a duplicate
- Files: raddflix_flutter/lib/screens/edit_profile_screen.dart
- Commit: e286322

---

## Session 2026-06-28 — Build fix: downloads_screen + content_card

- BUG-33-01: downloads_screen.dart lines 202/208/282 — arrow callbacks with semicolons converted to block syntax
- BUG-33-02: content_card.dart line 51 — missing comma after Text() in Column.children
- Commit: 0e44ecd

---

## Session 2026-06-28 — Build fix: downloads_screen _savePrefs

- BUG-34-01: Removed 3 calls to _savePrefs() which does not exist in _DownloadsScreenState — was added by a previous agent
- Commit: 0de6b07

---

## Session 2026-06-28 — Phase 35 UI/UX Completion Pass

- Task: Complete UI/UX improvements (continuing from run#1332)
- home_screen: _CategoryChip gets checkmark icon when selected
- search_screen: _SearchResultTile._buildPoster now uses local file first then CachedNetworkImage (was bare Image.network)
- search_screen: Browse-by-genre headers now have primary accent bar + count badge
- splash_screen: Added top-left and bottom-right corner glows; replaced CircularProgressIndicator with branded 3-dot pulsing loader
- Commit: 39f1d9f

---

## Session 2026-06-28 — Phase 35B Build Fix

- Bug: CachedNetworkImage uses errorWidget not errorBuilder — compile error in _buildNetworkPosterSR
- Commit: 9ed66e1

---

## Session 2026-06-28 — Phase 36 Missing Features

- Settings Screen (new): quality default, subtitle toggle, cache clear, version/about
- Share button on show detail using share_plus (already in pubspec)
- "More Like This" section: genre-match filter, horizontal poster scroll
- Profile → General → Settings tile wired to /settings route
- Tree commit: 2975c52

---

## Session 2026-06-30 — Phase 38 UI/UX Polish

- profile_screen: greeting text + double-glow avatar (108px) + colored edit badge + name 23px w800
- home_screen: greeting row below appbar + avatar ring + emoji display in appbar
- edit_profile_screen: bigger avatar preview + emoji row (20 emojis + None) + avatarEmoji saved
- Commit: fbc56ac

---

## Session 2026-06-30 — Phase 39 Download Audit

### Bugs Fixed
- BUG-39-01: startDownload() duplicate guard (isDownloading||isDownloaded early-return)
- BUG-39-02: Episode tile onDownload null-guard adds || isDownloading
- BUG-39-03: Cancel now deletes partial .mp4 + DB record (was: marked 'cancelled', file left)
- BUG-39-04: cancelDownload() async + loadDownloads() → UI clears after cancel
- BUG-39-05: deleteDownload() awaits async cancelDownload()
- BUG-39-06: _isDownloadingAll wrapped in try/finally
- BUG-39-07: _DownloadCard/_DownloadListTile get onCancel parameter + stop/sweep icons
- BUG-39-08: _FeaturePill t.textSecondary → t.textMuted
- Commit: e750398

---

## Session 2026-06-30 — Phase 40 Downloads Feature Pack

- F-40-01: download speed (MB/s) + ETA on cards/tiles (average-speed method, 500ms throttle)
- F-40-02/03: disk_space_plus free-space display + 200MB pre-flight abort
- F-40-04/05: LocalDb.getFileInfo() + retryDownload() — retry from downloads screen
- F-40-06: auto-retry on SocketException (1× after 4s)
- F-40-07: completion SnackBar via recentlyCompleted reactive list
- F-40-08: queue position badge on cards
- F-40-09: SharedPreferences persistence for sort/filter/view mode
- F-40-10: offline banner using connectivity_plus
- F-40-11: failed tile shows ↺ Retry + 🗑 Delete dual action
- Commit: f370635

---

## Session 2026-06-30 — Phase 41 Animation Infrastructure

- ANIM-41-01/02: Created lib/core/utils/anim_config.dart — AnimConfig singleton with AnimTier enum (potato/basic/standard/premium), detect() reads Android SDK, shouldAnimate() respects disableAnimations, canBlur/canStagger/canMorph flags, tier-aware fast/normal/slow durations, Riverpod animConfigProvider
- ANIM-41-06: Created lib/core/utils/anim_durations.dart — AnimDurations helpers + morph constant
- ANIM-41-04: pubspec.yaml — added animations ^2.0.11, flutter_staggered_animations ^1.1.1, animated_text_kit ^4.2.2
- ANIM-41-05: main.dart — AnimConfig.detect() before runApp, Animate.restartOnHotReload=kDebugMode, animConfigProvider.overrideWithValue in ProviderScope
- ANIM-41-03: RepaintBoundary added to home_screen (category chip itemBuilder, grid ContentCard itemBuilder, recommendation card itemBuilder) and downloads_screen (shimmer grid itemBuilder, folder GestureDetector cards)
- Commit: 8396c13

---

## Session 2026-06-30 — Phase 42 Hero Poster Transition

- ANIM-42-01: home_screen.dart — _buildPosterImage() in _HeroCard wrapped with Hero(tag: 'poster_${item.id}')
- ANIM-42-02: show_detail_screen.dart — FlexibleSpaceBar banner if/else if/else replaced with Hero(tag: 'poster_${item.id}', child: Builder(...)) — Builder collapses 3 branches into 1 Hero child
- ANIM-42-03: search_screen.dart — poster ClipRRect wrapped in Hero with same tag pattern
- ANIM-42-04: SKIPPED — downloads_screen navigates to player not show_detail so Hero tags would never match
- ANIM-42-05: app.dart — showDetail route transitionsBuilder changed from SlideTransition+Fade to pure FadeTransition; SlideTransition was fighting Hero's flight animation
- Commit: 50717ac

---

## Session 2026-06-30 — Phase 43 Staggered Grid/List Entry

- ANIM-43-01: home_screen — added import anim_config.dart + animConfig/canAnimate in main build(); category chips itemBuilder refactored to block syntax with ternary; grid ContentCard delegate uses canAnimate ternary; .scale() → .slideY(begin:0.06) everywhere
- ANIM-43-02: downloads_screen — added anim_config import; _buildFolderView + _gridView + _listView each get ref.read(animConfigProvider) at top; all .animate() chains now use animConfig.stagger(i) and animConfig.normal instead of hardcoded ms; folder .scale() → .slideY(0.06)
- ANIM-43-03: search_screen — added import; _buildResults() gets ref.read(animConfigProvider) + canAnimate; itemBuilder uses canAnimate ternary for tier-gated stagger
- Tier 0 policy: canStagger=false → raw widget (ternary); animConfig.stagger(i) returns Duration.zero on potato so even if animate() runs it is instant
- Commit: 4f55fcd

---

## Session 2026-06-30 — Phase 44 OpenContainer Morph

- Added import animations + show_detail_screen to home_screen + search_screen
- home_screen build(): added canMorph = animConfig.canMorph && shouldAnimate(context)
- home_screen grid delegate: 3-way tier branch — Tier2+ OpenContainer(tappable:false, ContentCard(onTap:openFn), ShowDetailScreen); Tier1 stagger; Tier0 raw
- search_screen _SearchResultTile: added VoidCallback? onTap field; GestureDetector uses onTap ?? defaultNavPush
- search_screen _buildResults: canMorph + t(RaddTheme) added; itemBuilder 3-way: OpenContainer(tile+openFn)/stagger/raw
- Hero conflict note: ContentCard in grid has no Hero; Hero only on _HeroSpotlight and _SearchResultTile poster (separate widget, compatible with OpenContainer)
- Commit: 2600a39

---

## Session 2026-06-30 — Phase 45 Neon/Glow Buttons

- Added import anim_config to show_detail_screen; animConfig = ref.watch(animConfigProvider) in build()
- _GlowPulse StatefulWidget added at end of show_detail_screen.dart; uses AnimationController (1400ms, repeat+reverse) + AnimatedBuilder + Container boxShadow; respects MediaQuery.disableAnimations
- Play button: Expanded > _GlowPulse(color:primary, maxBlur: tier>=2 ? 22 : 14, br:14) > ElevatedButton.icon
- Download button: Consumer return refactored — ElevatedButton → final dlBtn; return isDownloading ? _GlowPulse(maxBlur:12) : dlBtn
- ANIM-45-03 skipped: glow_effects package not in pubspec, would require new dep; Tier 2 shadow sufficient
- ANIM-45-05 deferred: SnackBar content animation requires custom SnackBar widget; not worth scope now
- Commit: bec1909

---

## Session 2026-06-30 — Phase 46 Typewriter & Animated Text

- show_detail: import animated_text_kit added; _typewriterReady bool added to state class; initState gets Future.delayed(300ms, setState(_typewriterReady=true))
- show_detail description section: if(_typewriterReady && animConfig.canStagger && !disableAnimations) → AnimatedTextKit(TypewriterAnimatedText, speed:18ms, cursor:'', cap 220 chars, totalRepeatCount:1, displayFullTextOnTap:true) else _ExpandableText
- home_screen chips: .shimmer(500ms, white24) appended after slideX in the entrance stagger chain (ANIM-46-05)
- ANIM-46-03: deferred — tagline not in CatalogItem model reliably
- ANIM-46-04: deferred — WavyAnimatedText on downloads bar low priority
- Commit: 647ac5c

---

## Session 2026-06-30 — Phase 47 Frosted Glass Bottom Nav

- bottom_nav: added dart:ui, flutter_riverpod, anim_config imports; StatelessWidget→ConsumerWidget; build() now reads animConfig; Tier 2+ (canBlur) → ClipRect>BackdropFilter(sigmaX/Y:12)>Container(opacity 0.72); Tier 0/1 → existing solid Container fallback
- home_screen Scaffold: extendBody:true (ANIM-47-03)
- home_screen slivers: SliverToBoxAdapter(72) appended after existing 24px bottom sliver (ANIM-47-04)
- ANIM-47-05 deferred: no measurable repaint issue with BouncingScrollPhysics
- Commit: af27e1a

---

## Session 2026-06-30 — Phase 48 3D Tilt Hero Banner

- _HeroCard converted from StatelessWidget → ConsumerStatefulWidget (_HeroCardState with SingleTickerProviderStateMixin)
- Added AnimationController _floatCtrl (3200ms); _tiltX (±0.025 rad), _tiltY (±0.015 rad) with easeInOut curves
- shouldFloat = animConfig.canStagger && !MediaQuery.disableAnimations; starts/stops controller in build()
- When shouldFloat: AnimatedBuilder wraps card in Transform with Matrix4 perspective (entry 3,2 = 0.001) + rotateX/Y
- final item = widget.item shorthand in build() + _buildPosterImage() avoids renaming all item. references
- ANIM-48-01: sensors_plus gyroscope deferred (needs pubspec edit + lock regen, risky without flutter pub get)
- Commit: a8d4323

---

## Session 2026-06-30 — Phase 49 Ambient Particle Background + ANIM-45-05

- NEW FILE: lib/widgets/particle_overlay.dart — ConsumerStatefulWidget, SingleTickerProviderStateMixin; AnimationController(12s repeat); CustomPainter (_ParticlePainter) draws 25 dots from fixed-seed Random(42); drift upward (modulo 1.0 wrap), sine horizontal offset; IgnorePointer wraps CustomPaint; tier gate: canParticle && !disableAnimations → SizedBox.shrink() fallback
- splash_screen: import particle_overlay added; Positioned.fill(ParticleOverlay()) inserted before Center in body Stack (ANIM-49-02)
- login_screen: import particle_overlay added; Positioned.fill(ParticleOverlay()) inserted before SafeArea in body Stack (ANIM-49-03)
- downloads_screen ANIM-45-05 (deferred from Phase 45): download-done SnackBar icon gets .animate().shake(400ms).scale(1.0→1.15, 200ms)
- ANIM-49-01 skipped: particles_flutter not added; pure CustomPainter achieves same visual
- Commit: f81b0cb

### ANIMATION ROADMAP PHASES 41–49 — ALL COMPLETE
Phase 41: AnimConfig infrastructure
Phase 42: Hero poster transition
Phase 43: Staggered grid/list entry
Phase 44: OpenContainer card-to-detail morph
Phase 45: Neon/Glow primary action buttons
Phase 46: Typewriter & animated text
Phase 47: Frosted glass bottom nav
Phase 48: 3D tilt hero banner
Phase 49: Ambient particle background

---

## Session 2026-07-01 — Phase 56 Subscription Tier Badge

- NEW FILE: lib/widgets/tier_badge.dart — ConsumerStatefulWidget, SingleTickerProviderStateMixin; AnimationController 1600ms repeat+reverse; tier-specific aura colors: FREE=grey(0xFF9E9E9E), STANDARD=blue(0xFF2196F3), PREMIUM=gold(0xFFFFB300); RepaintBoundary wraps AnimatedBuilder BoxShadow glow; canStagger gate (basic/API23+); respects disableAnimations
- profile_screen: import tier_badge.dart; replaced 21-line static Builder badge with TierBadge(plan: _remotePlan ?? user?.planName ?? 'FREE') + same .animate().fadeIn() wrapper
- subscription_screen: import tier_badge.dart; _ActivePlanCard plan name Text wrapped in Row with Flexible + TierBadge(plan: status.planName)
- Commit: a34b5f9

---

## Session 2026-07-01 — Full Audit: Guest/Free/Premium Logic

### Audit findings (phases 50–56 + all logic):
- Phases 50–55 already complete from previous session
- Phase 56 (TierBadge): pushed this session (e6a841e)
- Auth flow (guest/free/premium): CORRECT ✅
- Player Layer 2 subscription gate: CORRECT ✅
- show_detail isFreeEp = _parseFree(ep['is_free']) || item.isFree: CORRECT ✅
- Guest → _GuestWarning in SubscriptionScreen → Create Account: CORRECT ✅
- Downloads: guests blocked from paid, allowed for free: CORRECT ✅
- Content cards FREE badge (FIX-13): CORRECT ✅
- Oracle guest quota (always allowed): CORRECT ✅

### Bugs fixed:
- AUD-01: _EpisodeTile — added isLocked bool field + gold PREMIUM lock badge (🔒 PREMIUM) shown when !isFree && isLocked; FREE episodes still show green FREE badge; paid+unsubscribed episodes now visually communicate paywall before user taps
- AUD-02: _requireSub() — guests now see "Create a free account to access this content" / "Sign In" action; free registered users still see "Subscribe to access paid content" / "Subscribe" action
- AUD-03: episode builder now passes isLocked: !isFree && !_isSubscribed to each _EpisodeTile
- Commit: 336dbb5

---

## Session 2026-07-01 — 5 Feature Batch

### F01 — Settings screen (1859ec1)
- Added: Auto-play Next Episode toggle (jm_autoplay_next)
- Added: Download on WiFi Only toggle (jm_wifi_only)
- Added: Data Saver toggle (jm_data_saver)
- Added: Refresh Catalog tile → calls catalogProvider.syncFromServer()
- Added: Contact Support → opens WhatsApp wa.me link
- Added: Manage Downloads → navigates to /downloads
- Kept: Subtitles On By Default, Clear Image Cache, About section

### F02 — Search history UI (a6d938b)
- _loadHistory/_saveToHistory/_removeFromHistory/_clearHistory already existed
- Added: _buildHistorySection() widget — history chips with × remove + Clear all
- Shown when !showResultsArea && _history.isNotEmpty (above discover content)

### F03 — Subtitle file picker (2562512)
- Added FilePicker.platform.pickFiles() button in SubtitlePanel _tab==0 (Open tab)
- Supports .srt, .vtt, .ass, .ssa local files
- Calls widget.onSubtitleFilePicked → _np.setProperty('sub-file', path)
- Added import 'package:file_picker/file_picker.dart' to player_screen.dart

### F04 — In-app update check (d2f8146)
- _checkForUpdates() reads /api/config min_version_code on every app start
- Compares to PackageInfo.buildNumber; shows non-dismissable _UpdateDialog if behind
- Dialog has "Update Now" button → launchUrl(update_url)

### F05 — Continue Watching hero shortcut (d2f8146)
- _heroItems() inserts catalog.recentlyWatched.first at hero position 0
- _HeroCard reads catalogProvider to detect isResume
- Button shows "Resume" (play_circle_filled) vs "Watch Now" (play_arrow)

---

## Subtitle Audit Fixes · 4f568fc

### BUG1 — Customization tab Opacity slider corrupted text colour
- Was: `sub-color: #AAfffffff` (white with alpha) — overwrote user's chosen text colour
- Fix: use `sub-opacity` (correct mpv property); also syncs `_subFade` state so tab-1 Fade slider stays in sync

### BUG2 — sub-ass-override: force not set for background/scale/opacity/shadow
- Was: only applied for sub-font-size, sub-font, sub-bold, sub-color
- Fix: also applies for sub-back-color, sub-scale, sub-opacity, sub-outline-size, sub-shadow-offset
- Effect: ASS/SSA styled subtitle files now respect all visual setting changes

### Confirmed working correctly (no changes needed)
- Subtitle z-order vs controls: MPV sub-margin-y bumped +140px (base 100→240) when controls visible
- Called on every _toggleControls, _scheduleHide, _enterImmersive, _exitImmersive
- 240px clears the full bottom area (seek bar ~32px + transport ~48px + padding + SafeArea) on all devices

---

## Session 2026-07-01 — Player Audit: Dual Subtitles, Track Bugs, EAC3, MKV

- **Task:** Research + audit session (no code pushed). Findings written to TASKS.md Phase 57.
- **kisskh.la analysis:** Dual subtitle system uses MPV `secondary-sid` property. OST/signs track rendered at top natively by MPV. Can replicate exactly in our player.
- **Bugs found (7):**
  - P57-01: Fake subtitle track bug (SubtitleTrack.no() always present → button always active)
  - P57-02: No embedded MKV subtitle track selector in SubtitlePanel (AudioPanel has it, SubtitlePanel doesn't)
  - P57-03: Fake audio track bug (AudioTrack.auto() makes length always >= 1 even for no-audio files)
  - P57-04: SW decoder toggle silently does nothing during playback (guard exists but UI doesn't reflect it)
  - P57-05: EAC3/DTS no auto-fallback to SW decoder (user must know to toggle manually)
  - P57-06: No codec label shown in AudioPanel track list
  - P57-07: No secondary-sid / dual subtitle system (missing feature, OST/signs use case)
- **EAC3 status:** Supported by media_kit_libs_android_video (full ffmpeg) — no new package needed. Issue is auto-detection + fallback.
- **MKV status:** Format fully supported. Auto subtitle file detection works (MPV sub-auto=fuzzy default). Issue is UI track selector missing.
- **Commit:** N/A (audit only)

---

## Session 2026-07-01 — Phase 57 Implementation

- **Commit:** fix(player): Phase 57 — 7 bugs fixed in player_screen.dart (+165 lines)
- **P57-01 ✅** Fake subtitle track bug: added `_realSubtitleTracks` getter filtering `SubtitleTrack.no()` sentinel. Replaced in sidebar + top bar.
- **P57-02 ✅** Embedded MKV subtitle selector: added RadioListTile section in SubtitlePanel Open tab with all embedded tracks + Off option.
- **P57-03 ✅** Fake audio track bug: added `_realAudioTracks` getter filtering `AudioTrack.auto()` sentinel. Replaced in sidebar + top bar + AudioPanel call.
- **P57-04 ✅** SW decoder toggle disabled during playback: grayed out SwitchListTile with "Stop playback to apply" subtitle.
- **P57-05 ✅** EAC3/DTS auto SW fallback: after tracks load, delay 1s, read `audio-codec-name`, auto-enable SW decoder + snackbar if EAC3/DTS/AC3/TrueHD.
- **P57-06 ✅** Codec badge in AudioPanel: active track shows codec name (e.g. EAC3) in small grey badge.
- **P57-07 ✅** Dual subtitle / OST system: secondary-sid selector in SubtitlePanel Open tab. Blue radio buttons, sets MPV `secondary-sid` property. Shows OST/signs at top while dialogue at bottom.
- **EAC3 confirmed:** will play in app without any changes — mpv decodes audio via libavcodec (ffmpeg), not Android MediaCodec.
