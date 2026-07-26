# RaddFlix Download Tab Redesign + 5-Tab Nav — Plan

**Status:** Planned — ready for implementation
**Task:** DOWNLOAD-TAB-V2
**Research date:** 2026-07-06
**Author:** Agent (deep research session)
**Supersedes:** `agent-hub/LIBRARY_REDESIGN_PLAN.md` (the "merge Local + Downloads into one
Library screen with a mode switcher" idea is **dropped** per explicit product decision below —
do not resurrect it. That file has been deleted.)

---

## 0. Product Decision (locked — do not re-litigate)

1. **Bottom nav goes from 4 tabs to 5 tabs**, keeping Local and Download fully separate
   screens/experiences (not merged, no shared mode-switcher shell):
   `Home · Search · Local · Download · Profile`
2. **Only the Download tab** gets the new "Movies folder + per-season folders" structure.
   The Local tab (on-device files) keeps its current folder-by-directory behavior unchanged
   in this task — do not touch `local_media_screen.dart` / `local_folder_screen.dart` logic.
3. **The Download tab's overall layout is also being simplified** — the current version
   (folder grid → tap folder → flat item list, with sort/filter/batch actions in overflow
   menus) is reportedly "very tough for a normal user." This plan redesigns it end-to-end,
   informed by deep research into Netflix, YouTube, MoviBox, Amazon Prime, 1DM+, Snaptube,
   and MX Player download/offline experiences.

---

## 1. Problem Statement

Current `downloads_screen.dart` (soon to be the dedicated **Download** tab):
- Groups everything into 4 fixed folders (Movies / TV Shows / Dramas / Other) with no
  season-level structure — a downloaded show with 3 seasons dumps all episodes into one
  "TV Shows" bucket, hard to navigate.
- Sort/filter/view-mode controls live in an AppBar overflow menu — not discoverable for a
  "normal user" (non-technical, Jazz-SIM data-saving audience).
- No always-visible active-download progress; user has to open the screen to see progress.
- No visual distinction between a movie folder and a show folder (same generic folder icon).
- The "On Device" button bolted onto this screen's AppBar goes away entirely once Local
  becomes its own bottom-nav tab (see Section 3).

---

## 2. Competitive Research — What the Best Apps Do for Downloads

### Netflix Downloads
- Storage meter pinned at the very top (GB used / GB available) — always visible, no drilldown.
- Shows are one row/tile with a poster; tapping expands the episode list beneath it — never a
  flat list of 20 episodes.
- Quality badge (Standard/High) per item, download-expiry countdown badge when applicable.
- Empty state has a single clear CTA: "Smart Downloads" / "Find Something to Download."
- Filter is a simple pill row: All / Series / Movies — never buried in a sort sheet.

### YouTube "You"/Downloads
- Horizontal "Continue" row up top so the most useful action (resume watching) is one tap away.
- Everything else below is a simple vertical list, not a folder-of-folders maze.

### MoviBox (Android streaming/download app, closest analogue to RaddFlix)
- Two clearly separated top-level destinations: **Downloads** and **My List** — never merged.
- Downloads screen: **Movies** section and **TV Series** section as two big tappable cards/rows
  at the top; tapping TV Series reveals each **show**, and tapping a show reveals **season
  folders** (Season 1, Season 2, …), and only then the episode list. This is the closest
  precedent to what the user asked for and is the primary structural reference for this plan.
- Minimal chrome: no sort/filter clutter on the main screen — search icon only.

### Amazon Prime Video Offline
- Grouped by show with **expandable episode lists** — avoids dumping 40 items in one screen.
- Quality badges (HD/UHD) prominent on thumbnails.
- Storage usage shown as both a number and a slim visual bar.
- Sort (Recent / Title / Size) is one tap from the toolbar, not nested in a sheet.

### 1DM+ (Download Manager)
- **Live active-downloads widget always pinned at the top of the list** — filename, progress
  bar, speed (MB/s), ETA — never requires opening a detail screen to see what's happening.
- Type tabs at the top (All/Video/Audio/etc.) for instant filtering — but kept to 2-3 max for
  a "normal user," not 6.
- Pause/resume per item directly from the row.

### Snaptube
- **Swipe left = delete (with undo snackbar)**, **swipe right = move/vault** — removes the need
  to enter a "select" / batch mode for common single-item actions.
- Quality badge directly on the thumbnail corner (4K/1080p/720p).

### MX Player
- Recently Played pinned at the very top — resume is always the first thing visible.
- Grid view with large thumbnails, folder browsing below.

### Key synthesis for "make it simple for a normal user"
1. Two big top-level sections only: **Movies** and **TV Shows** — no 4-way Movies/TV/Dramas/Other
   split that requires the user to guess which bucket a title landed in.
2. TV Shows → show poster → **season folders by name** ("Season 1", "Season 2", …) → episodes.
   This directly satisfies the user's request.
3. Storage + active-download progress always visible at the top, no drilldown required.
4. Swipe gestures replace the "select mode → toolbar action" pattern for single-item
   delete/vault — batch mode still exists for multi-select but is no longer the only way.
5. Sort/search reduced to one tap each in the main toolbar, not stacked in a dropdown chain.

---

## 3. Bottom Navigation Change — 5 Tabs

```
Home · Search · Local · Download · Profile
```

- `widgets/bottom_nav.dart`: `_items` list changes from 4 entries to 5. Insert `Local` (reuse
  `AppIcons.device` / `PhosphorIcons.deviceMobile`-style icon already used for the current
  "On Device" shortcut) and `Download` (`PhosphorIcons.downloadSimple` / existing
  `AppIcons.downloadDone` family) as tabs 2 and 3. Home=0, Search=1, Local=2, Download=3,
  Profile=4.
- `local_media_screen.dart`: becomes the direct destination for tab index 2. Remove its current
  `currentIndex: 2 // Library tab stays active` comment/logic — it now owns index 2 outright,
  no more "tapping Library pops back" special case.
- `downloads_screen.dart`: becomes the direct destination for tab index 3 (was 2, shared with
  Local). Remove the `AppIcons.device` "On Device" AppBar shortcut entirely — Local is now a
  first-class tab, not a sub-destination of Downloads.
- `home_screen.dart`, `search_screen.dart`, `profile_screen.dart`: update embedded
  `RaddFlixBottomNav.onTap` routing — index 2 now pushes `AppRoutes.localMedia` (was Library/
  Downloads), index 3 pushes `AppRoutes.downloads`, index 4 pushes `AppRoutes.profile` (was 3).
- `constants.dart` / route table: no new route needed — `AppRoutes.localMedia` and
  `AppRoutes.downloads` already exist; only the nav index wiring changes. **Do not** add the
  `AppRoutes.library` route from the old plan — that screen is no longer being built.
- Capsule width math in `bottom_nav.dart` (`itemWidth = totalWidth / _items.length`) already
  auto-adjusts for item count — no manual width tuning needed for 5 vs 4 items, but **must be
  visually verified** on a narrow device (320-360dp) since 5 labels is tighter than 4.

---

## 4. Download Tab — New Screen Layout

```
╔══════════════════════════════════════════════════════════════╗
║  Download                                    [🔍]  [↕]      ║  ← Simple AppBar, 2 actions max
╠══════════════════════════════════════════════════════════════╣
║ ┌──────────────────────────────────────────────────────────┐ ║
║ │  ⬇ 2.4 GB downloaded         8.2 GB free on device       │ ║  ← Storage strip (always visible)
║ └──────────────────────────────────────────────────────────┘ ║
║                                                              ║
║ ┌──────────────────────────────────────────────────────────┐ ║  ← Active Download ticker
║ │  ⬇  Breaking Bad S5E02  ██████████░░░░░  64%  1.8 MB/s  │ ║     (only rendered when >0 active,
║ └──────────────────────────────────────────────────────────┘ ║      tap → jumps to that item)
║                                                              ║
║  [ All ]   [ Movies ]   [ TV Shows ]                         ║  ← 3 simple filter pills, replaces
║                                                              ║     the old 4-folder grid tap-in
╠══════════════════════════════════════════════════════════════╣
║  🎬 Movies (12)                                              ║  ← Section header (only if >0 items)
║  ┌────────┐ ┌────────┐ ┌────────┐                          ║     poster-first grid, no
║  │ poster │ │ poster │ │ poster │  ...                      ║     intermediate "Movies folder"
║  │ 1080p⬇│ │ 720p ⬇│ │  HD ⬇ │                             ║     tap-through — movies are
║  └────────┘ └────────┘ └────────┘                          ║     always flat under this header
║                                                              ║
║  📺 TV Shows (4)                                             ║  ← Section header
║  ┌──────────────────────┐  ┌──────────────────────┐         ║
║  │ 🎭 Breaking Bad       │  │ 🎭 Money Heist        │         ║  ← one card per SHOW
║  │ 3 seasons · 24 eps    │  │ 2 seasons · 16 eps    │         ║
║  └──────────────────────┘  └──────────────────────┘         ║
║      tap → Season list screen:                               ║
║      ┌───────────────┐ ┌───────────────┐ ┌───────────────┐  ║
║      │ 📁 Season 1    │ │ 📁 Season 2    │ │ 📁 Season 3    │  ║
║      │ 8 episodes    │ │ 8 episodes    │ │ 8 episodes    │  ║
║      └───────────────┘ └───────────────┘ └───────────────┘  ║
║          tap season → flat episode list (existing item tile) ║
╠══════════════════════════════════════════════════════════════╣
║  [🏠 Home] [🔍 Search] [📱 Local] [⬇ Download●] [👤 Profile]║  ← 5-tab Bottom Nav
╚══════════════════════════════════════════════════════════════╝     ● = badge when download completes
```

### Navigation depth
- **Movies:** Download tab → flat grid (no extra tap). Matches "it will show here all movies
  that we have downloaded" from the product request directly.
- **TV Shows:** Download tab → Show card → **Season folder screen (new)** → Season card →
  flat episode list (reuses existing item-tile UI/logic from current `_buildItemsView`).

---

## 5. Data Model / Grouping Changes

Current `downloads` table already has `content_type`. To build season folders we need the
season number, which today only lives inside the episode title string (e.g. "Breaking Bad
S05E02") via `_folderFor()` / `_showTitleFrom()` regex heuristics.

### Season extraction (new)
```dart
/// Extracts (showTitle, seasonNumber, episodeNumber) from a stored title like
/// "Breaking Bad S05E02" or "Breaking Bad - S5E2".
/// Falls back to seasonNumber = null (goes into an "Unsorted" season bucket) if no match.
({String show, int? season, int? episode}) parseEpisodeTitle(String text) {
  final m = RegExp(r'(.*?)[\s\-]+[Ss](\d{1,2})[Ee](\d{1,3})').firstMatch(text);
  if (m == null) return (show: text.trim(), season: null, episode: null);
  return (
    show: m.group(1)!.trim(),
    season: int.tryParse(m.group(2)!),
    episode: int.tryParse(m.group(3)!),
  );
}
```
- No DB migration required for v1 — season is derived at render time from `title_text`, same
  approach as the existing `_showTitleFrom()` heuristic already in `downloads_screen.dart`.
- **Future-proofing note (do this if touching the download-save path anyway):** when a download
  is enqueued from `show_detail_screen.dart`, persist `season_number` as an explicit column
  instead of re-parsing the title every render. Out of scope for v1 — flag as a fast-follow in
  `agent-hub/TASKS.md` once this plan starts, don't block v1 on a schema migration.

### Grouping logic replacing `_folderFor()` 4-way split
```
top-level buckets:
  content_type in {movie} → Movies section (flat)
  content_type in {show, series, tv, anime, cartoon, donghua, drama} → TV Shows section
    → group by parseEpisodeTitle(title).show  → one card per show
      → group by parseEpisodeTitle(title).season → one folder per season
        (season == null → "Unsorted" folder, still created so nothing is hidden)
```
- Drops the standalone "Dramas" and "Other" top-level folders from the old 4-way split —
  dramas/anime/etc. fold into TV Shows (still correctly grouped by show → season), which
  matches every reference app researched (none of them have a genre-specific top bucket).
  If Pakistani-drama content genuinely needs its own top filter later, add it as a 4th pill
  next to All/Movies/TV Shows — do not resurrect a folder-grid for it.

---

## 6. New/Changed Widgets

### `screens/downloads_screen.dart` (redesigned in place — no wrapper/body split needed
since the merge-with-Local plan is dropped)
- Remove `_folders` constant (`['Movies', 'TV Shows', 'Dramas', 'Other']`) and `_buildFolderView`.
- Remove the `AppIcons.device` "On Device" AppBar action (Local is now its own tab).
- Add `_buildFilterPills()` — 3 pills (All / Movies / TV Shows), replacing `_buildFilterRow()`'s
  4-way status filter as the *primary* filter. Status filter (Done/Downloading/Failed) moves
  into the sort/filter icon's bottom sheet — it's a secondary, less-used control per the
  simplicity goal.
- Add `_buildMoviesSection()` — flat poster grid under a "🎬 Movies (N)" header.
- Add `_buildShowsSection()` — grid of show cards under a "📺 TV Shows (N)" header; each card
  shows show poster (first episode's `poster_url`), season count, episode count.
- Add `_openShow(showTitle)` → pushes new `SeasonFolderScreen`.

### `screens/season_folder_screen.dart` (**new**)
- Takes `showTitle` + the list of that show's download rows.
- Groups by season, renders a folder-card grid (`📁 Season N · X episodes`), tapping a season
  card pushes the existing flat item list view (extract current `_buildItemsView` body from
  `downloads_screen.dart` into a reusable `_EpisodeListView` widget shared by both screens).

### `widgets/download/download_storage_strip.dart` (**new**, extracted from existing
`_buildStorageBar` in `downloads_screen.dart` — same visual, own file for reuse/testability)

### `widgets/download/active_download_ticker.dart` (**new**)
- Reads first in-progress item from `downloadsProvider`.
- Shows filename (1 line), `LinearProgressIndicator`, speed, ETA — mirrors 1DM+ pattern.
- `AnimatedSize` slide-in/out; hidden entirely when no active downloads.
- Speed/ETA: check `download_service.dart` / `downloads_provider.dart` for whether per-item
  speed is already tracked (throttled UI updates every 500ms are mentioned in existing code) —
  if not currently exposed, add `speedBytesPerSec` + `etaSeconds` fields to the provider state
  during implementation.

### Swipe actions (Snaptube pattern)
- Wrap episode/movie tiles in `Dismissible`:
  - Swipe left → delete (red bg, trash icon, undo snackbar, same delete call as existing
    batch-delete logic).
  - Swipe right → vault (purple bg, lock icon, same `VaultService` flow as existing batch
    vault action).
- List view only (existing constraint — grid keeps long-press context menu, no swipe).

---

## 7. AppBar Simplification

| Old (4-icon overflow-prone) | New |
|---|---|
| On Device shortcut, Grid/List toggle, Sort popup (3 options), search absent from Download tab | Search icon, single Sort/Filter bottom sheet (contains view mode + status filter + sort order) |

Batch mode (multi-select) is retained but demoted to long-press → "Select" entry point rather
than a persistent selection affordance, since swipe now covers the single-item case.

---

## 8. Files Touched Summary

| File | Change |
|---|---|
| `widgets/bottom_nav.dart` | `_items` 4→5, insert Local + Download tabs |
| `screens/home_screen.dart` | bottom nav `onTap` index routing updated for 5 tabs |
| `screens/search_screen.dart` | bottom nav `onTap` index routing updated for 5 tabs |
| `screens/profile_screen.dart` | bottom nav `onTap` index routing updated for 5 tabs |
| `screens/local_media_screen.dart` | becomes direct tab-2 destination; drop "pop to Library" special case |
| `screens/downloads_screen.dart` | redesigned: drop 4-folder grid, add Movies/TV Shows sections, season grouping, swipe actions, simplified AppBar |
| `screens/season_folder_screen.dart` | **New** — season folder grid → episode list per show |
| `widgets/download/download_storage_strip.dart` | **New** — extracted storage bar |
| `widgets/download/active_download_ticker.dart` | **New** — live progress ticker |
| `providers/downloads_provider.dart` | Add per-item speed/ETA fields if not already exposed |
| `agent-hub/LIBRARY_REDESIGN_PLAN.md` | Deleted (superseded) |
| `AGENT_HANDOFF.md` | Update after implementation |
| `agent-hub/history/TASK_LOG.md` | Update after implementation |
| `agent-hub/TASKS.md` | Row added for DOWNLOAD-TAB-V2 (this plan) |

---

## 9. Risk Assessment

| Risk | Level | Mitigation |
|---|---|---|
| Season parsing regex misses non-standard titles (e.g. no `SxxExx` pattern) | Medium | Fallback "Unsorted" season bucket — nothing hidden, no crash |
| 5-tab nav feels cramped on 320-360dp screens | Medium | Verify capsule/label layout on small-width emulator before marking done; shrink label font if needed (already 11px per prior accessibility fix — do not go below WCAG minimum again) |
| Removing "On Device" button breaks any deep link / onboarding tooltip pointing at it | Low | Grep whole repo for `AppRoutes.localMedia` push sites and `AppIcons.device` usage before deleting the button, update any references |
| Dismissible swipe conflicts with existing scroll/long-press gestures | Medium | List view only, matches existing constraint already accepted in the prior plan |
| Batch-delete / batch-vault regressions from AppBar restructuring | Medium | Keep exact same underlying delete/vault functions — only entry point (long-press vs persistent button) changes |
| MediaTek black-screen / player regressions | None | No player code touched in this task |

---

## 10. Implementation Rules (carry forward from repo conventions)

- Every file change → `bash log_pending.sh "msg" files` → edit → `bash auto_commit.sh "msg" files`
  from `raddflix-app/` (only if the user has opted into the auto-commit workflow for that
  session — otherwise use normal reviewed commits).
- ≥1.2s between sequential commits/pushes (Rule 41 — no parallel GitHub pushes).
- Never add `androidAttachSurfaceAfterVideoParameters: true`.
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`.
- Never change `hwdec` mid-play.
- After all edits: run a code review pass and fix severe issues before marking DONE.
- After review: update `AGENT_HANDOFF.md` and `agent-hub/history/TASK_LOG.md`, mark the
  `agent-hub/TASKS.md` row ✅ DONE with commit SHA(s).

---

*Plan generated after deep research of: Netflix, YouTube, MoviBox, Amazon Prime Video, 1DM+,*
*Snaptube, MX Player — July 2026. Product decisions (5-tab nav, Download-tab-only season*
*folders) confirmed directly with the project owner before writing this plan.*
