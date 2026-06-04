# TASK_LOG.md — Agent Session History

> Newest session at top. Every agent must append here after completing work.
> Format: `## Session YYYY-MM-DD` followed by bullets.

---

## Session 2026-06-04

**Agent:** Replit Agent (main branch)
**Objective:** Fix all critical bugs, verify Oracle live, add debug diagnostics screen

### Oracle verification
- Server confirmed live at 92.4.95.252 — Flask v3.0.0, supervisord
- 24 titles available, 3 subscription plans (Basic PKR149 / Standard PKR249 / Premium PKR399)
- XOR encoding confirmed active on all `/api/*` routes
- Auth, catalog, plans API all responding correctly after padding fix

### Bugs fixed
- **BUG-C01 through BUG-C05** — root cause: XOR base64 padding strip
  - File: `raddflix_flutter/lib/core/security/request_encoder.dart`
  - Fix: `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;`
- **BUG-P01** — VideoController black screen
  - File: `raddflix_flutter/lib/screens/player_screen.dart`
  - Fix: removed `androidAttachSurfaceAfterVideoParameters: true`
- **BUG-D01** — api_client type error on XOR response
  - File: `raddflix_flutter/lib/core/api/api_client.dart`
  - Fix: type guard `data is String ? jsonDecode(data) : data`
- **BUG-S01** — catalog blank after sync failure
  - File: `raddflix_flutter/lib/providers/catalog_provider.dart`
  - Fix: `await loadFromDb()` in sync exception handler

### New files added
- `raddflix_flutter/lib/screens/debug_diagnostics_screen.dart`
  — Debug-only screen (kDebugMode-gated, absent from release APK)
  — Tab 1: 6 live checks (Oracle, XOR, DB, Auth, Sync, Device ID) with Copy Report
  — Tab 2: Live logcat viewer — color-coded, filterable, auto-scroll, share button
  — Entry: 7-tap on version text in ProfileScreen

### Documentation added
- `README.md` — updated with quick-links and architecture summary
- `AGENT_HANDOFF.md` — comprehensive agent onboarding document
- `ONBOARDING.md` — 4-step quick start for new agents
- `.agents/tasks/BUG_TRACKER.md` — all bugs with root causes
- `.agents/PROJECT_RULES.md` — 10 non-negotiable rules
- `AGENT_PROMPT.md` — universal copy-paste prompt for new Replit agents

### State at end of session
- No known open bugs
- All .MD documentation committed to GitHub main branch
- Debug screen reachable via 7-tap on version in Profile (debug APKs only)

---

## Session 2026-06-03

**Agent:** Previous agent
**Objective:** Initial bug discovery and triage

### Work done
- Discovered all 30 bugs across server and Flutter client
- Traced XOR encoding issues to single root cause (padding strip)
- Identified sqflite_sqlcipher version was incorrect in pubspec.yaml (4.0.1 → corrected to 3.1.0+1)
- Documented architecture and file map

### State at end of session
- Bug list complete, no fixes applied yet
- All bugs documented in handoff notes

---

## Session 2026-06-04 (second session)

**Agent:** Replit Agent (main branch)
**Objective:** Fix three major bugs in new APK — movies unplayable, episodes "link expired", black screen after 2-5s

### Root causes diagnosed

- **Bug 1 (movies no play):** `_playMovie()` correctly shows "Video not available yet" for movies with no file in Oracle `files` table (data gap, not code bug). For movies WITH files, failure falls through to Bug 2 path.
- **Bug 2 (stream link expired):** JazzDrive share tokens in Oracle `files.share_url` expired. All `stream_links` in Oracle DB expired 2 days ago (8h TTL, generated June 2). Flutter was calling JazzDrive API directly with these expired tokens → 401 Unauthorized → "Stream link expired" snackbar.
- **Bug 3 (black screen 2-5s):** `VideoController(_player)` created with no config, defaulting to `androidAttachSurfaceAfterVideoParameters: true` — causes surface detach/reattach cycle → blank screen on Android.

### Fixes applied

- **Bug 2 → Step 3b replacement** (`player_screen.dart`): Old code retried JazzDrive with a fresh `share_url` from Oracle (which was also expired). New code calls Oracle's `/api/catalog/play?file_id=<id>` endpoint instead — Oracle has its own JazzDrive session and generates a fresh CDN URL server-side.
- **Bug 1 → Step 2.5 added** (`player_screen.dart`): If shareUrl is null after local DB + inline + Oracle `share_url` checks, now tries Oracle direct play endpoint. Handles movies where `share_url` is missing but Oracle can generate a CDN link.
- **Bug 3** (`player_screen.dart`): `VideoController(_player, configuration: const VideoControllerConfiguration(androidAttachSurfaceAfterVideoParameters: false))` — prevents surface detach causing black screen.
- **`catalog_api.dart`**: Added `CatalogApi.getDirectPlayUrl(fileId)` — calls `/api/catalog/play?file_id=$id`, returns `direct_url` from Oracle response.
- **`constants.dart`**: Added `ApiPaths.directPlayUrl(fileId)` → `/api/catalog/play?file_id=$fileId`.

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart`
- `raddflix_flutter/lib/core/api/catalog_api.dart`
- `raddflix_flutter/lib/core/constants.dart`

### Architecture note
Oracle's `/api/catalog/play` endpoint (added in a previous session, BUG-A35) generates CDN stream links via Oracle's own JazzDrive admin credentials. This is the correct architecture: Oracle holds JazzDrive credentials centrally, Flutter app just fetches CDN URLs from Oracle. No JazzDrive API calls from the client needed.

### State at end of session
- All three critical bugs fixed in code; APK rebuild required
- If Oracle's JazzDrive session is also invalid, the user must refresh JazzDrive account credentials on Oracle (re-login to JazzDrive admin panel)

---

## Session — June 04, 2026

### What was done
Removed Oracle server entirely from the video playback path in `player_screen.dart`.

**Problem identified:** Previous session added Steps 2.5 and 3b which called Oracle's `/api/catalog/play` endpoint as a fallback during playback. This was architecturally wrong because:
1. The local SQLite DB already stores the `share_url` for every title/episode (synced once at install/update)
2. The `share_url` is a permanent JazzDrive folder/file share — it never expires
3. JazzDrive APIs (`cloud.jazzdrive.com.pk`) are zero-rated for Jazz SIM users — no data cost
4. Oracle's VPS is NOT zero-rated — calling it during playback costs the user data and requires a JWT
5. If JazzDrive is down, Oracle cannot help (it also calls JazzDrive internally)

**Fix applied to `raddflix_flutter/lib/screens/player_screen.dart`:**
- Removed Step 2.5 (Oracle direct play when share_url missing from local DB)
- Removed Step 3b (Oracle direct play when JazzDrive throws an error)
- Removed Oracle `CatalogApi.getShareUrl()` fallback in Step 2 (share_url must come from local DB or inline route args only)
- Updated error message: "Could not connect to JazzDrive. Make sure you are on a Jazz SIM."

**Correct playback flow (post-fix):**
1. Local file (downloaded)? → play immediately
2. Get share_url from local DB or inline route args (passed by detail screen)
3. Call JazzDrive directly (zero-rated) → get fresh CDN link → play
4. If JazzDrive fails → show "Check Jazz SIM connection"

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart` — _openMedia method

### Commits
- GitHub: `7fc67a1` — fix: remove Oracle from playback path — pure JazzDrive zero-rated flow
- Oracle: git pull confirmed, repo in sync

### State at end of session
- Playback path is now fully zero-rated, no Oracle dependency
- APK rebuild required for changes to reach users
- Oracle Flask server still needed for: initial catalog sync, user accounts, subscriptions

---

## Session — June 04, 2026 (cont.)

### What was done

#### 1. Beautiful StreamErrorOverlay widget
Replaced hardcoded error overlay in `player_screen.dart` with `_StreamErrorOverlay`:
- Dynamic error message uses `_streamError` (not hardcoded text)
- Smart icon: Jazz SIM signal icon when error contains "Jazz", cloud_off otherwise
- Smart title: "Jazz SIM Required" vs "Video Unavailable"
- Glassmorphism card (BackdropFilter + blur + accent border)
- Pulsing shimmer animation on error icon
- "Retry clears the 3-hour cache" badge pill
- Spinner + "Refreshing JazzDrive cache…" text shown during retry
- `_isRetrying` state variable added for retry loading state
- Retry calls `JazzDriveService.invalidate(fileId)` then `_openMedia` — cache-clear before fresh JazzDrive call

#### 2. _openMedia try/finally safety fix
Wrapped Steps 1–3 in `_openMedia` with `try/catch/finally`:
- `finally` block guarantees `_isLinkLoading = false` even if LocalDb throws unexpectedly
- Prevents infinite spinner on DB corruption or unexpected exceptions

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart`

### Commits
- `90f299c` — feat: beautiful StreamErrorOverlay with cache-clear Retry button
- `ce127ea` — fix: wrap _openMedia in try/finally — _isLinkLoading always clears

### APK build
- GitHub Actions `Build RaddFlix APK` (workflow ID 282572869) triggered via workflow_dispatch
- Build runs on push to main when raddflix_flutter/** changes (auto-triggered by ce127ea)

### State at end of session
- All playback changes confirmed on GitHub main and Oracle
- APK build in progress on GitHub Actions

---
## Session: 2026-06-04 (continued) — Bug fixes, UI features, JazzDrive repair

**Agent:** Replit Agent (main branch)

### Bug fixes committed (6808fc1)

**BUG #3 FIXED — Black flash before first video frame** (`player_screen.dart`)
  Root cause: Video widget was visible at opacity 1.0 before the first frame decoded,
  causing a brief black flash on every local video open.
  Fix: Wrapped Video widget in `AnimatedOpacity` starting at 0.0, fades to 1.0 at
  400ms once `_playing` becomes true. Invisible while buffering, smooth fade-in on play.

**BUG #4 FIXED — planExpired redirect fires during local file playback** (`player_screen.dart`)
  Root cause: `_checkQuota()` called `sub_expires_at` checks for ALL playback paths,
  including local folder files where `widget.fileId` is an empty string.
  A stale quota cache entry fired `pushReplacementNamed(planExpired)` 1–3 seconds in,
  killing the player mid-playback for local files.
  Fix: Added guard `&& widget.fileId.isNotEmpty` — local files bypass quota entirely.

### UI Features added

**Episode gap placeholders** (`show_detail_screen.dart`, commit b412d47)
  Added `_currentEpisodesWithGaps` getter: compares consecutive episode numbers and
  inserts `_EpisodeGap` sentinel objects for missing entries (e.g. if E03–E05 are absent
  from DB while E02 and E06 exist). Renders as greyed-out `_EpisodeUnavailableTile`
  so users see the full season structure with "Not available" placeholders.

**CatalogItem.episodeCount field** (`catalog_item.dart`, commit a96f134)
  Added `final int? episodeCount` parsed from Oracle's `episode_count` column.
  Used by the Coming Soon banner to show accurate episode count ("has 12 episodes").

**Coming Soon banner** (`show_detail_screen.dart`, commit 0a52945)
  Replaced plain "No episodes in Season N" empty state with branded `_ComingSoonBanner`:
  gradient card, `upcoming_rounded` icon, message adapts:
  - If `episodeCount` known: "Season 1 has 12 episodes — uploading now. Check back soon!"
  - Generic fallback: "Episodes for Season 1 are on their way."

### JazzDrive repair

**JazzDrive Pass3 interpolation bug FIXED** (`jazzdrive_service.dart`, commit 778b33e)
  Root cause: In Dart non-raw strings, `\$` is an escaped literal dollar sign, NOT
  string interpolation. Pass 3 of the 3-pass filename match was building the literal
  string `s${em.group(1)!.padLeft(2,"0")}e...` instead of e.g. `s01e04`.
  This silently killed all folder-share episode matching — Pass 3 always returned null,
  fell back to `records[0]` (first file in share), so every episode played the same file.
  Fix: Replaced interpolation with explicit concatenation `'s' + s + 'e' + e`.
  Also added `DebugLogger.log` output of all record names and the computed code for
  live Jazz SIM debugging.

  Root of root cause: The bug was introduced when a Node.js script generated Dart source
  code and escaped `$` to prevent shell variable substitution. The escape survived into
  the committed Dart file. Rule: always use concatenation in generated Dart strings.

**JazzDrive test suite** (`test_suite/jazzdrive_logic_test.js`, commit 527f0b7)
  New 27-test Node.js suite — runs anywhere without Jazz SIM, no packages needed.
  Covers: URL parsing (7), 3-pass match incl. Pass3 (6), stream URL building (5),
  poster URL building (4), response shape parsing (5).
  Run: `node raddflix_flutter/test_suite/jazzdrive_logic_test.js`
  Full network test (Jazz SIM device): add `--live <shareUrl> [targetFilename]`

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart` — BUG #3 (AnimatedOpacity), BUG #4 (fileId guard)
- `raddflix_flutter/lib/screens/show_detail_screen.dart` — gap placeholders, Coming Soon banner
- `raddflix_flutter/lib/models/catalog_item.dart` — episodeCount field
- `raddflix_flutter/lib/core/services/jazzdrive_service.dart` — Pass3 fix + DebugLogger
- `raddflix_flutter/test_suite/jazzdrive_logic_test.js` — new: 27-test JazzDrive logic suite

### State at end of session
- All bugs fixed and committed to GitHub main
- APK rebuild triggered via GitHub Actions build-apk.yml
- .agents/memory/ updated with JazzDrive Pass3 lesson (topic file: jazzdrive-pass3-bug.md)
- Known open data gap: BUG #2 — All Of Us Are Dead E03/E04/E05/E09 not in Oracle DB
  (need to upload those episodes to JazzDrive and sync)

---
## Session: 2026-06-04 (continued) — Bug fixes, UI features, JazzDrive repair

**Agent:** Replit Agent (main branch)

### Bug fixes committed (6808fc1)

**BUG #3 FIXED — Black flash before first video frame** (`player_screen.dart`)
  Root cause: Video widget visible at opacity 1.0 before first frame decoded.
  Fix: Wrapped Video in `AnimatedOpacity` starting at 0.0, fades to 1.0 at 400ms
  once `_playing` becomes true. Invisible while buffering, smooth fade-in on play.

**BUG #4 FIXED — planExpired redirect fires during local file playback** (`player_screen.dart`)
  Root cause: `_checkQuota()` checked sub_expires_at for ALL playback including
  local folder files where `widget.fileId` is an empty string. Stale quota cache
  fired `pushReplacementNamed(planExpired)` 1-3 seconds in, killing the player.
  Fix: Guard `&& widget.fileId.isNotEmpty` — local files bypass quota entirely.

### UI Features added

**Episode gap placeholders** (`show_detail_screen.dart`, commit b412d47)
  Added `_currentEpisodesWithGaps` getter: compares consecutive episode numbers and
  inserts `_EpisodeGap` sentinel objects for missing entries (e.g. if E03-E05 absent
  from DB while E02 and E06 exist). Renders as greyed-out `_EpisodeUnavailableTile`
  so users see the full season structure with "Not available" placeholders.

**CatalogItem.episodeCount field** (`catalog_item.dart`, commit a96f134)
  Added `final int? episodeCount` parsed from Oracle's `episode_count` column.
  Used by the Coming Soon banner to show accurate episode count.

**Coming Soon banner** (`show_detail_screen.dart`, commit 0a52945)
  Replaced plain "No episodes" empty state with branded `_ComingSoonBanner`:
  gradient card, `upcoming_rounded` icon, message adapts:
  - If episodeCount known: "Season 1 has 12 episodes — uploading now. Check back soon!"
  - Generic fallback: "Episodes for Season 1 are on their way."

### JazzDrive repair

**JazzDrive Pass3 interpolation bug FIXED** (`jazzdrive_service.dart`, commit 778b33e)
  Root cause: In Dart non-raw strings, backslash-dollar is an escaped literal dollar
  sign, NOT string interpolation. Pass 3 of the 3-pass filename match was building
  the literal string `s${em.group...}e...` instead of e.g. `s01e04`.
  This silently killed all folder-share episode matching — Pass 3 always returned null,
  fell back to `records[0]` (first file in share), so every episode played same file.
  Fix: String concatenation `'s' + s + 'e' + e` — no dollar signs, no ambiguity.
  Also added DebugLogger output of all record names + computed code for Jazz SIM debug.

  Root of root cause: Node.js script generating Dart source code escaped $ to prevent
  shell substitution. Escape survived into committed Dart file undetected because the
  fallback (records[0]) always returned a playable URL, masking the bug.

**JazzDrive test suite added** (`test_suite/jazzdrive_logic_test.js`, commit 527f0b7)
  New 27-test Node.js suite — runs anywhere without Jazz SIM, no packages needed.
  Covers: URL parsing (7), 3-pass match incl. Pass3 (6), stream URL building (5),
  poster URL building (4), response shape parsing (5).
  Run: `node raddflix_flutter/test_suite/jazzdrive_logic_test.js`
  Live network test (Jazz SIM): add `--live <shareUrl> [targetFilename]`

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart` — BUG #3 (AnimatedOpacity), BUG #4 (fileId guard)
- `raddflix_flutter/lib/screens/show_detail_screen.dart` — gap placeholders, Coming Soon banner
- `raddflix_flutter/lib/models/catalog_item.dart` — episodeCount field
- `raddflix_flutter/lib/core/services/jazzdrive_service.dart` — Pass3 fix + DebugLogger
- `raddflix_flutter/test_suite/jazzdrive_logic_test.js` — new: 27-test JazzDrive logic suite

### State at end of session
- All bugs fixed and committed to GitHub main
- APK rebuild triggered via GitHub Actions build-apk.yml
- .agents/memory/ updated with JazzDrive Pass3 lesson
- Known open data gap: BUG #2 / DATA-01 — All Of Us Are Dead E03/E04/E05/E09
  missing from Oracle DB (need upload to JazzDrive and sync)

---

## Session 2026-06-04 (continued) — Admin Episode Status Panel

**Agent:** Replit Agent (main branch)
**Objective:** Admin panel in show_detail_screen.dart — mark episode gap tiles as Coming Soon / Uploading

### DB layer (v18)
- `local_db.dart`: new `episode_overrides` table (PK: show_id + season + episode)
- `LocalDb.getEpisodeOverrides(int showId)` returns `Map<String,String>` keyed `'season_ep'`
- `LocalDb.setEpisodeOverride(showId, season, episode, status)` — null clears entry
- `constants.dart`: `catalogDbVersion` bumped 17 → 18

### UI layer (show_detail_screen.dart)
- State: `_overrides`, `_adminMode`, `_adminTapCount` added to `_ShowDetailScreenState`
- Overrides loaded from LocalDb on every `_loadEpisodes()` call
- Gap placeholder maps now carry `'_override'` key
- **`_EpisodeUnavailableTile`** — new `override` + `onLongPress` params:
  - `null` → grey/block/"Not available" (unchanged)
  - `'coming_soon'` → amber tint, schedule icon, "Coming Soon"
  - `'uploading'` → blue tint, cloud_upload, "Uploading now..."
  - Edit pencil icon visible when admin mode is active
- **5-tap unlock**: tap "Episodes" header 5× → toggles `_adminMode`; orange ADMIN badge
- **Long-press gap tile** → `_showAdminSheet()` → `_AdminEpisodePanel` bottom sheet
- **`_AdminEpisodePanel`**: lists all missing season episodes with [None|Soon|Uploading] chips;
  auto-saves to LocalDb on each tap; `onChanged` refreshes parent tile visuals instantly
- **`_AdminChip`**: animated toggle chip widget (reusable)

### Commits
- `3efaa4f` — feat: bump catalogDbVersion to 18 (episode_overrides table)
- `abe5667` — feat: add episode_overrides table + getEpisodeOverrides / setEpisodeOverride
- `e51b34c` — feat: admin episode status panel

### APK build
- Build #979 triggered (in progress)

### Notes
- Overrides are device-local only — not yet synced to Oracle (future feature)
- Substitution wrangling: the _resumeEpisodeIndex line sits between _watchProgress and
  _loading in the setState block — anchors must include it

---

## Session 2026-06-04 (continued) — show_detail_screen UX improvements

**Agent:** Replit Agent (main branch)
**Objective:** Implement 4 UX improvements planned by previous agent (cut off at quota limit)

### Changes made to `show_detail_screen.dart`

1. **Pull-to-refresh** — Wrapped `CustomScrollView` in `RefreshIndicator` (calls `_loadEpisodes`, uses `AlwaysScrollableScrollPhysics` so pull works even on short lists)

2. **Episode sort toggle** — Added `_sortAscending = true` state var; `_currentEpisodes` getter now reverses when false; animated sort icon (↓/↑) added to Episodes header with `AnimatedSwitcher` + tooltip

3. **Season progress chips** — Added `_totalCountForSeason(s)` and `_watchedCountForSeason(s)` helpers; chip text changes from `'Season $s'` to `'S$s · 2/8'` format when episodes are loaded (counts episodes with progress ≥ 95%)

4. **Admin "Clear all statuses"** — Added orange `OutlinedButton` above Done button in `_AdminEpisodePanel`; loops through all gap episodes and calls `LocalDb.setEpisodeOverride(..., null)` to reset them all at once

### Files changed
- `raddflix_flutter/lib/screens/show_detail_screen.dart` — commit `80d6a1b`

### APK build
- Build #983 triggered — in progress

### State at end of session
- All 4 planned improvements implemented and committed
- Oracle pulled successfully (17 files changed from previous sessions also landed)
- Build #981 (previous session) completed successfully

---

## Session 2026-06-04 — player_screen.dart bug fixes (6 bugs)

**Agent:** Replit Agent (main branch)
**Objective:** Fix all 6 bugs identified in full line-by-line analysis of player_screen.dart

### Bugs fixed

| ID | Line | Severity | Description |
|---|---|---|---|
| BUG-P01 | 1586 | 🔴 Critical | Position save fires 50–67×/sec at each 10s boundary. Fixed: checkpoint index (`p.inSeconds ~/ 10`) + `_lastSaveCheckpoint` state var — saves exactly once per 10s tick |
| BUG-P02 | 2253 | 🔴 Critical | Completed video saved position=duration on dispose — next open resumed from end, triggering instant next-ep countdown. Fixed: added `!_ended` guard |
| BUG-P03 | 2819 | 🔴 Critical | `CountdownNextOverlay` passed `widget.title` (current ep) as "next title" — showed "Up next: [episode already watched]". Fixed: changed to `_nextEpLabel` |
| BUG-P04 | 1565 | 🟡 Medium | `SmartVolumeController` created in `_initPlayer` before `_loadPrefs` completed — used default prefs, not user's saved settings. Fixed: moved SVC creation to end of `_loadPrefs()` |
| BUG-P05 | 2293 | 🟡 Medium | `_scheduleHide` missing `_showJumpPanel` guard — controls could hide while Jump To panel was open, leaving panel floating with no way back. Fixed: added `!_showJumpPanel` |
| BUG-P06 | 3295 | 🟡 Medium | `onQualityChanged` was a permanent no-op `(_) {}` — users tapped quality options with zero feedback. Fixed: shows "Quality selection coming soon" SnackBar |

### Files changed
- `raddflix_flutter/lib/screens/player_screen.dart` — commit `d39af21`

### APK build
- Build triggered after commit d39af21

---

## Session 2026-06-04 — Full codebase bug audit (5 bugs fixed)

**Agent:** Replit Agent (main branch)
**Objective:** Full line-by-line audit of all Flutter source files — find and fix all bugs

### Files audited
- `core/security/request_encoder.dart`
- `core/api/api_client.dart`
- `core/api/auth_api.dart`
- `core/api/catalog_api.dart`
- `core/db/local_db.dart`
- `core/db/sync_service.dart`
- `core/services/jazzdrive_service.dart`
- `core/constants.dart`
- `models/catalog_item.dart`
- `providers/auth_provider.dart`
- `providers/catalog_provider.dart`
- `providers/subscription_provider.dart`
- `providers/watchlist_provider.dart`
- `screens/player_screen.dart`
- `screens/show_detail_screen.dart`

### Bugs found and fixed

| ID | Severity | File | Description |
|----|----------|------|-------------|
| BUG-N01 | 🔴 High | `core/constants.dart` | `ApiPaths.fileShareUrl` used `\$fileId` (literal `$`) — Oracle always received `file_id=$fileId` instead of real value. `CatalogApi.getShareUrl()` calls this in production — share URL lookup always returned null. Fixed: changed to `${fileId}` |
| BUG-N02 | 🔴 High | `core/db/local_db.dart` | `mergeDeltaTitle` INSERT branch missing `file_id` — fresh JazzDrive delta installs had no `file_id` in DB → movies unplayable. Fixed: added `if (fileId.isNotEmpty) 'file_id': fileId` |
| BUG-N03 | 🟡 Medium | `models/catalog_item.dart` | `CatalogItem.copyWith()` silently dropped `episodeCount` field — Coming Soon banner lost episode count whenever badge was applied. Fixed: added `episodeCount: episodeCount` |
| BUG-N04 | 🟡 Medium | `screens/player_screen.dart` | `_VideoDisplaySheet` Loop button had `onTap: (_) {}` (no-op) — toggle showed active state but did nothing. Fixed: added `onLoop` callback parameter and wired to AB panel (consistent with `loopActive: _abLoop.isActive` state) |
| BUG-N05 | 🟡 Medium | `core/api/auth_api.dart` | `getMe()` used unsafe `response.data as Map<String, dynamic>` — throws `TypeError` if XOR decode produces String. Fixed: added type guard with `jsonDecode` fallback |

### Files changed
- `raddflix_flutter/lib/core/constants.dart` — commit `2dfbf37`
- `raddflix_flutter/lib/core/db/local_db.dart` — commit `2dfbf37`
- `raddflix_flutter/lib/models/catalog_item.dart` — commit `2dfbf37`
- `raddflix_flutter/lib/screens/player_screen.dart` — commit `2dfbf37`
- `raddflix_flutter/lib/core/api/auth_api.dart` — commit `2dfbf37`

### APK build
- Build #990 triggered after commit 2dfbf37 — in progress

### State at end of session
- All 5 bugs fixed in one atomic commit (2dfbf37)
- Oracle pulled successfully (5 files changed)
- No Python files changed — Flask restart not needed
- BUG-N01 + BUG-N02 together fix playback on fresh JazzDrive delta-only installs
- All prior bugs remain fixed
