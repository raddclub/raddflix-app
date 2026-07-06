# RaddFlix Library Screen — Unified Redesign Plan

> ⚠️ **SUPERSEDED — 2026-07-06.** The product decision was made to keep Local and Download as
> fully separate bottom-nav tabs (5-tab nav) instead of merging them into one "Library" shell
> with a mode switcher. Do not implement this plan. See
> `agent-hub/DOWNLOAD_TAB_REDESIGN_PLAN.md` for the current, active plan. This file is kept for
> historical reference only (some competitive research below is still reused there).

**Status:** ~~Planned — ready for implementation~~ SUPERSEDED, DO NOT IMPLEMENT
**Task:** Unified Library Screen  
**Research date:** 2026-07-06  
**Author:** Agent (deep research session)

---

## 1. Problem Statement

The current Library tab is a renamed Downloads screen with a small "On Device" AppBar button that
navigates separately to Local Media. This is:

- **Two separate user experiences** stitched together with a single button
- **Missing the most valuable UX** all leading media apps share: a "Continue Watching" surface
- **No unified search** across both sources
- **No active download visibility** unless you scroll down in Downloads
- **No quality or source context** on thumbnails

---

## 2. Competitive Research — What the Best Apps Do

### Netflix Downloads
- Storage meter at top of screen (exact GB used + available)
- Items grouped by show — one poster for the show, episodes listed below it
- **Download expiry countdown** badge ("Expires in 3 days") — urgent, glanceable
- Quality badge per item (Standard / High)
- "Find Something to Download" CTA on empty state — drives content discovery from the library
- Smart Downloads: auto-downloads next episode when current one is watched (inspiration for future)
- Simple filter: All / Series / Movies (not buried in a sort sheet)

### YouTube "You" Tab
- **Horizontal section rows**, not a flat vertical list — Continue Watching, Downloads, History,
  Playlists, Liked Videos all appear as separate rows with "See all" links
- Replaced the old "Library" tab — proved that a personal/curated view outperforms a raw file browser
- Profile info at the top — personalization cue
- Key lesson: **don't make users browse — surface what's next**

### Amazon Prime Video Offline
- Grouped by show with expandable episode lists (avoids 40 individual items for one season)
- Quality badges: HD / UHD / 4K prominent on each thumbnail
- Storage usage shown as both a number and a visual bar
- Sort: Most Recent / By Title / By Size — available without drilling into menus
- Days-remaining countdown on expiring content

### 1DM+ (Download Manager)
- **Type tabs at the top**: All / Video / Audio / Images / Docs / APK — instant category filter
- **Live active downloads widget** always visible at the top — file name, progress bar, speed (MB/s), ETA
- Pausing/resuming per item directly from the list without entering a detail screen
- Storage used broken down per category
- Key lesson: **always show what's happening** — active downloads should never be invisible

### MX Player
- **Recently Played section at the very top** — the single most-used action (resume) is one tap away
- Folder-based browsing below recent items
- Grid view with larger thumbnails than the current RaddFlix grid
- Inline search bar appears below the top bar on search icon tap (same as current Local Media)
- Sort accessible from toolbar, not buried in a sheet

### Snaptube
- Downloads grouped by source platform (YouTube, Instagram, TikTok) with platform logo badge
- **Quality badge prominently on thumbnail** (4K, 1080p, 720p, MP3)
- **Swipe left to delete** (with undo snackbar) — no need for batch mode for single-item delete
- **Swipe right to vault/move** — contextual, not requiring entering batch mode
- Convert to audio option inline per item

### VLC Android
- Sections: Videos / Audio / Streaming / Playlists / History — very clear content-type separation
- Breadcrumb navigation when inside a folder subfolder
- History section shows recently accessed files across all sources

### Infuse (iOS)
- **"Up Next" row** at the top — the #1 feature users cite; shows exactly what to watch next based on
  partial-watch progress
- "Recently Added" row — shows what arrived since the last session
- Smart Collections auto-tag content into Movies / TV Shows / Other
- Poster-first artwork — 3-column grid with large artwork as the primary UI element
- Watch progress overlay on each poster (small arc or bar in the bottom-left corner)

### Plex
- "Continue Watching" is the dominant section — takes up most of the "Home" screen
- Library sections (Movies / TV Shows) accessible from sidebar/nav
- Pinned libraries — user decides what appears first
- Downloads accessible as a dedicated section, not mixed with streamed content

---

## 3. Design Decisions — What RaddFlix Library Will Borrow

| Feature | Source App | Priority |
|---|---|---|
| Continue Watching horizontal row | Netflix · Infuse · Plex · MX Player | 🔴 High |
| Unified storage strip | Netflix · Amazon Prime | 🔴 High |
| Mode switcher pill (Downloads vs On Device) | — (own design) | 🔴 High |
| Active download ticker (always visible when active) | 1DM+ | 🔴 High |
| Type tabs (All / Video / Audio) | 1DM+ · VLC | 🟡 Medium |
| Quality + source badges on thumbnails | Amazon Prime · Snaptube | 🟡 Medium |
| Swipe-to-delete / swipe-to-vault | Snaptube · iOS Files | 🟡 Medium |
| Download completion badge on nav tab | Standard Android pattern | 🟡 Medium |
| "Find Something to Download" empty CTA | Netflix | 🟡 Medium |
| Expiry countdown badge | Netflix · Amazon Prime | 🟢 Low (if server sends expiry) |
| Pinned folders | Plex | 🟢 Low (Phase 2) |
| Breadcrumb navigation in folders | VLC | 🟢 Low (Phase 2) |

---

## 4. Screen Layout — Complete Design

```
╔══════════════════════════════════════════════════════════════╗
║  ←   Library                        [🔍]  [⊞]  [↕]        ║  ← Shared AppBar
║                                                              ║     Actions change per mode
╠══════════════════════════════════════════════════════════════╣
║ ┌──────────────────────────────────────────────────────────┐ ║
║ │  ⬇ 2.4 GB saved    ━━━━━━━━━━━━━━━━━━░░░░    8.2 GB free│ ║  ← Storage Strip
║ └──────────────────────────────────────────────────────────┘ ║     (always visible)
║                                                              ║
║ ┌──────────────────────────────────────────────────────────┐ ║  ← Active Download Ticker
║ │  ⬇  Breaking Bad S5E02  ██████████░░░░░  64%  1.8 MB/s  │ ║     (only when downloading)
║ └──────────────────────────────────────────────────────────┘ ║     animated slide-in/out
║                                                              ║
║    ╔════════════════════╗  ╔════════════════════╗           ║
║    ║  ⬇ Downloads  18  ║  ║  📱 On Device  47  ║           ║  ← Mode Switcher Pill
║    ╚════════════════════╝  ╚════════════════════╝           ║     gradient on active segment
║                                                              ║
║  [All 18] [✓ Done 14] [⬇ Downloading 2] [⚠ Failed 2]      ║  ← Filter chips (Downloads)
║  ─── or ────────────────────────────────────────────────   ║
║  [All 47] [▶ Watching 5] [✓ Watched 12]                    ║  ← Filter chips (On Device)
║                                         (animated crossfade) ║
╠══════════════════════════════════════════════════════════════╣
║  ▶  Continue Watching                             See all ›  ║  ← Horizontal section row
║  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                   ║     (only when ≥1 in-progress)
║  │▓▓▓▓▓│  │▓▓▓▓▓│  │▓▓▓▓▓│  │▓▓▓▓▓│                   ║     both sources mixed
║  │  43%│  │ Ep.2│  │S2E4 │  │1h20m│                   ║
║  └──────┘  └──────┘  └──────┘  └──────┘                   ║
║  BB S5E2   Squid Gm  The Bear  Shogun                       ║
╠══════════════════════════════════════════════════════════════╣
║  [ All ]   [ Video ]   [ Audio ]                            ║  ← Type Tabs
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  ┌──────────────────┐  ┌──────────────────┐                 ║
║  │  🎬              │  │  📺              │                 ║  ← Folder Grid
║  │  Movies          │  │  TV Shows        │                 ║     (Downloads mode)
║  │  12 items · 1.2G │  │  6 shows · 890M  │                 ║
║  │            [⬇ ⊞]│  │            [⬇ ⊞]│                 ║     source + quality badges
║  └──────────────────┘  └──────────────────┘                 ║
║                                                              ║
║  ┌──────────────────┐  ┌──────────────────┐                 ║
║  │  🎭              │  │  📁              │                 ║
║  │  Dramas          │  │  Other           │                 ║
║  │  2 items · 340M  │  │  1 item  · 120M  │                 ║
║  └──────────────────┘  └──────────────────┘                 ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║  [🏠 Home]  [🔍 Search]  [📁 Library●]  [👤 Profile]       ║  ← Bottom Nav
╚══════════════════════════════════════════════════════════════╝     ● = badge dot when download completes
```

### AppBar Action Matrix

| Mode | Normal actions | Batch mode actions |
|---|---|---|
| Downloads | [🔍 Search] [⊞ Grid/List] [↕ Sort] | [☑ Select All] [🔒 Vault] [🗑 Delete] |
| On Device | [🔍 Search] [⊞ Grid/List] [↕ Sort] | — (no batch in Local yet) |

---

## 5. New Widgets to Create

### `lib/widgets/library/library_storage_strip.dart`
- Reads `downloadsProvider` for total downloaded bytes
- Reads device free space via `DiskSpacePlus` (already used in Downloads screen)
- Renders as a slim `Surface` card with gradient fill bar
- Color thresholds: normal → orange (<500 MB free) → red (<200 MB free)

### `lib/widgets/library/library_mode_switcher.dart`
- Two-segment animated pill
- `AnimatedContainer` for the sliding capsule — same animation curve as the nav bar capsule
- Reads live counts from `downloadsProvider` and `localMediaProvider`
- Emits `onModeChanged(int index)` callback

### `lib/widgets/library/library_active_download_ticker.dart`
- `AnimatedSize` + `ClipRect` for slide-in/out behaviour
- Reads first active download from `downloadsProvider`
- Shows: file name (truncated to 1 line), `LinearProgressIndicator`, speed string, ETA string
- Tapping switches mode to Downloads
- Auto-hides with animation when no active downloads

### `lib/widgets/library/library_continue_watching_row.dart`
- `SizedBox(height: 160)` horizontal `ListView.builder`
- Queries `LocalDb.getWatchPositions()` (already available)
- Merges results from `downloadsProvider` (completed items) and `LocalMediaService.queryAllVideos()`
- Filters: position > 5 s AND position < 90% of duration
- Each card: poster thumbnail + gradient overlay + progress arc/bar + title
- "See all" navigates to a future full-screen continue-watching list

### `lib/widgets/library/library_type_tab_bar.dart`
- Three `ChoiceChip`-style pills: All / Video / Audio
- Passes `LibraryContentType` enum down into `DownloadsBody` and `LocalMediaBody` via constructor
- Audio chip hidden if count == 0 in current mode

---

## 6. Existing Screens — Extraction Plan

### Step A: `DownloadsScreen` → `DownloadsBody`
```
downloads_screen.dart (before):
  DownloadsScreen (Scaffold + all logic)

downloads_screen.dart (after):
  DownloadsScreen    (thin wrapper — Scaffold + bottomNav + DownloadsBody())
  DownloadsBody      (ConsumerStatefulWidget — all existing _build* methods + state)

Constructor additions to DownloadsBody:
  final LibraryContentType contentTypeFilter;   // from type tabs
  final VoidCallback? onBatchModeChanged;        // tells LibraryScreen to swap AppBar
```

### Step B: `LocalMediaScreen` → `LocalMediaBody`
```
local_media_screen.dart (after):
  LocalMediaScreen   (thin wrapper)
  LocalMediaBody     (ConsumerStatefulWidget — all existing logic)

Constructor additions to LocalMediaBody:
  final LibraryContentType contentTypeFilter;
  final bool searchActive;    // LibraryScreen search button drives this
```

---

## 7. Routing Changes

```dart
// constants.dart — add:
static const String library = '/library';

// app.dart — add:
AppRoutes.library: (_) => const LibraryScreen(),
// Keep existing:
AppRoutes.downloads: (_) => const DownloadsScreen(),
AppRoutes.localMedia: (_) => const LocalMediaScreen(),

// home_screen.dart, search_screen.dart, profile_screen.dart — change:
// i==2 → pushNamed(AppRoutes.library)   (was AppRoutes.downloads)
```

---

## 8. Download Completion Badge

In `RaddFlixBottomNav`:
```
// listen to downloadsProvider
final recentlyCompleted = ref.watch(downloadsProvider.select((s) => s.recentlyCompleted));
final hasBadge = ref.watch(libraryBadgeProvider);  // new simple StateProvider<bool>

// On Library tab icon (index 2):
Stack(children: [
  Icon(AppIcons.files),
  if (hasBadge) Positioned(top:0, right:0, child: _BadgeDot()),
])

// Badge clears when user taps Library tab (i==2 onTap resets libraryBadgeProvider)
```

---

## 9. Swipe Actions

Wrap list-view tiles in `Dismissible` (Flutter built-in):

```
Swipe LEFT  → Delete  (red background, trash icon)
             Shows undo snackbar ("Deleted [title]" + Undo button)
             Same delete logic as existing batch delete

Swipe RIGHT → Vault   (purple gradient, lock icon)
             Triggers existing VaultService.moveFileToVault flow
             Requires PIN unlock — same as existing batch vault action
```

Grid view: no swipe (use existing long-press context menu).

---

## 10. Quality + Source Badges

```
Thumbnail Stack (top of existing thumbnail widget):
  └── Positioned(bottom: 4, right: 4)
       └── Row(mainAxisSize: min, children: [
             _QualityBadge(resolution),   // '4K' / '1080p' / '720p' / 'SD'
             SizedBox(width: 3),
             _SourceBadge(source),         // '⬇' downloaded / '📱' local
           ])

_QualityBadge derives from video width:
  >= 3840 → '4K'
  >= 1920 → '1080p'
  >= 1280 → '720p'
  else    → 'SD'

Resolution comes from:
  Downloads: metadata already stored with download record
  Local:     video_thumbnail package or MediaInfo already used for duration
```

---

## 11. Files Touched Summary

| File | Change |
|---|---|
| `screens/downloads_screen.dart` | Extract `DownloadsBody`, thin wrapper remains |
| `screens/local_media_screen.dart` | Extract `LocalMediaBody`, thin wrapper remains |
| `screens/library_screen.dart` | **New** — unified shell |
| `screens/home_screen.dart` | i==2 → `AppRoutes.library` |
| `screens/search_screen.dart` | i==2 → `AppRoutes.library` |
| `screens/profile_screen.dart` | i==2 → `AppRoutes.library` |
| `widgets/bottom_nav.dart` | Download completion badge dot on Library tab |
| `widgets/library/library_storage_strip.dart` | **New** |
| `widgets/library/library_mode_switcher.dart` | **New** |
| `widgets/library/library_active_download_ticker.dart` | **New** |
| `widgets/library/library_continue_watching_row.dart` | **New** |
| `widgets/library/library_type_tab_bar.dart` | **New** |
| `core/constants.dart` | Add `AppRoutes.library` |
| `main.dart` / `app.dart` | Register `/library` route |
| `AGENT_HANDOFF.md` | Update after implementation |
| `agent-hub/history/TASK_LOG.md` | Update after implementation |

---

## 12. Risk Assessment

| Risk | Level | Mitigation |
|---|---|---|
| Body extraction breaks existing standalone routes | Low | Thin wrapper keeps exact same Scaffold; routes unchanged |
| `Continue Watching` row performance (two providers + DB query) | Medium | Cache in `libraryProvider`; lazy-load thumbnails; row only builds when visible |
| `IndexedStack` memory (both bodies alive simultaneously) | Medium | Both screens already cache thumbnails with eviction; acceptable tradeoff vs. re-scan cost |
| Swipe actions conflicting with existing scroll gestures | Medium | Use Flutter `Dismissible` threshold; list-only (not grid) |
| Quality badge missing for some files | Low | Omit badge gracefully; never show placeholder |
| MediaTek black-screen (hwdec mid-play) | None | No player code changed in this task |

---

## 13. Implementation Rules (carry forward)

- Every file change → `bash log_pending.sh "msg" files` → edit → `bash auto_commit.sh "msg" files` from `raddflix-app/`
- ≥1.2 s between sequential commits (`sleep 1.3`)
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Never change `hwdec` mid-play
- After all edits: run architect code review and fix severe issues
- After code review: update `AGENT_HANDOFF.md` and `TASK_LOG.md` and commit

---

*Plan generated after deep research of: Netflix, YouTube "You" tab, Amazon Prime Video, 1DM+,*
*MX Player, Snaptube, VLC Android, Infuse 7, Plex — July 2026.*
