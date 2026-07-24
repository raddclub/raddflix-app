# LIVE_PLAYER_PLAN.md — RaddFlix Live TV Player Redesign
Last updated: 2026-07-23 | P0 done `aa997d82` CI ✅ | P5-C done `cfe0fe9b` CI ✅ via `aa997d82`

> **This is the active plan for the Live TV player overhaul.**
> Work phase-by-phase, top-to-bottom. Check each checkbox only after push + CI green.
> For task-board rows see `agent-hub/TASKS.md` (LIVE-P0 through LIVE-P7).
> Full session write-ups go in `agent-hub/history/TASK_LOG.md`.

---

## Background — What we found (2026-07-23 audit)

### How live streams work

Live channels are served as direct HLS streams from the tamashaweb CDN:
```
https://cdn*.tamashaweb.com:8087/jazzauth/<channel-path>/playlist.m3u8
```
These URLs require **Jazz mobile data** to access — the CDN checks the source IP.
They are NOT JazzDrive share URLs and must be opened directly by the player.

### Critical bug: live TV is completely broken

`_openMedia()` in `_ps_playback_mixin.dart` has NO `_isLive` special case.
For a live channel with `file_id = 'live_geo-news'`:

1. `isLocal = false` (doesn't start with `/` or `content://`)
2. `LocalDb.getShareInfo('live_geo-news')` → empty (no DB entry for live IDs)
3. Falls back to `widget.streamUrl` (the m3u8 CDN URL)
4. Calls `JazzDriveService.getStreamLink(cacheKey, m3u8Url)`
5. `_generateLink()` → `_extractShareKey()` regex finds no `/f/` pattern → returns `null`
6. Throws `Exception('Invalid JazzDrive share URL: https://cdn...jazzauth/...')`
7. `_friendlyError()` matches `'Jazz'` in `'Invalid JazzDrive share URL'` →
   shows **"Jazz SIM required to stream"** (wrong reason — stream never even attempted)

**Fix is 5 lines**: add `_isLive` early-exit in `_openMedia()` to call
`_player.open(Media(widget.streamUrl!))` directly.

### DVR / seeking capability

Audited all 84 channel stream URLs in `radd-hub/hub/db.py`:

| DVR? | Count | Example |
|---|---|---|
| ✅ DVR 1-hour | **1** | Geo News — `playlist_dvr_timeshift-0-3600.m3u8` |
| ❌ No DVR | **83** | All others — `playlist.m3u8` / `chunks.m3u8` |

- Geo News: MPV/media_kit CAN seek up to 60 minutes back using the DVR window.
- All other channels: pure live HLS, `EXT-X-PLAYLIST-TYPE: LIVE`, no seeking at all.
- Forward-seeking to "future" content is impossible on any channel (this is live TV).
- `has_dvr` flag needs to be added to the `LiveChannel` model so the player knows
  whether to show a seek bar.

### Current player portrait layout (wrong for live TV)

Full-height VOD player with a tiny `_buildLivePortraitPanel()` at the bottom:
- `_buildLiveStatusRow()` — red dot + LIVE + channel name
- `_buildLiveTransportRow()` — channel list, play/pause, lock, immersive, settings

Problems:
- Takes up full screen height for a content-less black box
- No channel info / logo visible
- No channel browsing without opening a bottom sheet
- All VOD controls (EQ, speed, subtitles, A-B loop) still accessible in sidebar
- Seek bar entirely absent — even for Geo News DVR

---

## Phase 0 — CRITICAL: Fix live stream resolution (currently all live TV broken)

**Scope**: `_ps_playback_mixin.dart` only. No UI changes.

### Tasks

- [x] **LIVE-P0-A** — Add `_isLive` early-exit in `_openMedia()`:
  ```dart
  // At the top of _openMedia(), after isLocal check:
  if (_isLive) {
    final url = widget.streamUrl;
    if (url == null || url.isEmpty) {
      setState(() { _streamError = 'No stream URL for this channel.'; });
      return;
    }
    if (mounted) setState(() { _streamError = null; _isLinkLoading = false; _ended = false; });
    _videoOpened = true;
    await _player.open(Media(url));
    _scheduleHide();
    return;
  }
  ```
  This bypasses JazzDrive resolution entirely for live channels.

- [x] **LIVE-P0-B** — Fix `_friendlyError()` for live:
  Add live-specific clause before the generic Jazz check:
  ```dart
  String _friendlyError(String raw) {
    if (_isLive) {
      if (raw.contains('403') || raw.contains('Forbidden') || raw.contains('401')) {
        return 'Jazz SIM required. Connect to Jazz mobile data to watch live TV.';
      }
      return 'Could not load channel. Check your connection and retry.';
    }
    // existing VOD logic unchanged below...
  }
  ```

- [x] **LIVE-P0-C** — Skip VOD-only lifecycle for live in `_openMedia()`:
  After the early-exit opens the stream, do NOT call:
  - `_restoreWatchPos()` — no saved position for live
  - `_startSavePositionTimer()` — nothing to save
  - `_applySmcOnSessionEnd()` — live is zero-rated
  (Already achieved by early-exit returning before these calls.)

- [x] **LIVE-P0-D** — Auto-retry interval for live:
  Live streams disconnect frequently. Change `_startAutoRetry()` to retry every
  **10 seconds** when `_isLive`, vs the current 30s for VOD. Add `_isLive` branch
  in `_startAutoRetry()`.

- [x] **LIVE-P0-E** — CI green confirmed.

**Acceptance**: Open any live channel → video plays. Error only appears when
actually on non-Jazz network (403/Forbidden from CDN), not due to JazzDrive failure.

---

## Phase 1 — DVR metadata: model + DB + API

**Scope**: `live_channels.dart`, `local_db.dart`, `radd-hub/hub/db.py`,
`radd-hub/hub/routes/live_channels.py`.

### Tasks

- [x] **LIVE-P1-A** — Add DVR fields to `LiveChannel` model (`live_channels.dart`):
  ```dart
  final bool hasDvr;             // true only for channels with DVR window
  final int  dvrWindowSeconds;   // 0 if no DVR, 3600 for Geo News, etc.
  ```
  Update `fromJson`, `fromRow`, `toRow`. Default: `hasDvr=false`, `dvrWindowSeconds=0`.

- [x] **LIVE-P1-B** — DB migration: add columns to `live_channels` table (`local_db.dart`):
  ```sql
  ALTER TABLE live_channels ADD COLUMN has_dvr INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE live_channels ADD COLUMN dvr_window_seconds INTEGER NOT NULL DEFAULT 0;
  ```
  Bump schema version (currently v26 → v27). Add migration in `_onUpgrade`.

- [x] **LIVE-P1-C** — Oracle DB: update `live_channels` seed in `radd-hub/hub/db.py`:
  - Add `has_dvr` and `dvr_window_seconds` columns to `CREATE TABLE live_channels`
  - Update seed tuple for `geo-news`: set `has_dvr=1, dvr_window_seconds=3600`
  - All other 83 channels: `has_dvr=0, dvr_window_seconds=0`
  - Add ALTER TABLE migration in `init_db()` so existing Oracle DB gets the columns

- [x] **LIVE-P1-D** — Oracle API: update `/api/live/channels` response
  (`radd-hub/hub/routes/live_channels.py`) to include `has_dvr` and
  `dvr_window_seconds` in the channel JSON. Flutter already deserialises
  unknown fields safely, but the new fields must be present for the app to use them.

- [x] **LIVE-P1-E** — Oracle deploy (`push_to_oracle.sh`) + API verify.
  CI check for Flutter (`build-apk.yml`) after Flutter files change.

---

## Phase 2 — Portrait player: YouTube/Tamasha inline layout

**Scope**: `_ps_ui_mixin.dart`. This is the largest phase.

### Layout target (portrait)

```
┌──────────────────────────┐
│ ←  Channel Name    [PiP] │  thin AppBar (always visible)
├──────────────────────────┤
│                          │
│   16:9 video box         │  AspectRatio(16/9) — tappable for controls overlay
│   [controls overlay]     │
│                          │
├──────────────────────────┤
│ 🔴 LIVE  [Logo]  Name    │  channel identity bar
│ HD · Jazz Zero-Rated     │
├──────────────────────────┤
│ ←─── channel switcher ──→│  horizontal scrollable row of channel logos
│ [ARY][PTV][HumTV][Geo].. │  tap to switch; current channel highlighted
├──────────────────────────┤
│  [☰ All Channels]  [⚙]  │  footer row
└──────────────────────────┘
```

Controls overlay on the video box (tap to show/hide, auto-hides 3s):
- Gradient scrim (top+bottom)
- Play/pause button (center, 56px circle)
- Fullscreen button (bottom-right corner)
- Buffering spinner (center, replaces play/pause)
- Reconnecting label (below spinner when `_isLive && _buffering`)
- DVR seek bar (bottom, ONLY if `hasDvr == true`)
- Brightness/volume swipe gestures (same as VOD)
- Tap to show/hide (same as VOD)

Channel identity bar below video:
- 48px channel logo (`CachedNetworkImage`, circular)
- Channel name (16sp bold)
- 🔴 LIVE badge (red pill, pulsing dot)
- "HD · Jazz Zero-Rated" subtitle (12sp, textMuted)

Channel switcher row:
- Horizontal `ListView` of all channels (same category first, then others)
- Each item: 64px logo card with border highlight on current channel
- Tap → switch channel immediately (same as channel switcher bottom sheet)

Footer row:
- "☰ All Channels" button → opens full channel switcher bottom sheet
- ⚙ Settings → opens audio/quality settings (live-relevant only: quality, audio track)

### Tasks

- [x] **LIVE-P2-A** — New `_buildLivePortraitScaffold()` method that replaces the
  full-height player scaffold for live content. Returns a `Column`:
  `[AppBar] + [AspectRatio video box] + [identity bar] + [Expanded switcher] + [footer]`

- [x] **LIVE-P2-B** — `_buildLiveVideoBox()`: `AspectRatio(16/9)` wrapping the
  `Video` widget + the controls overlay stack. Handles gestures (tap, swipe for
  brightness/volume) and the `_showControls` auto-hide logic.

- [x] **LIVE-P2-C** — `_buildLiveControlsOverlay()`: gradient scrim + play/pause +
  fullscreen button + DVR seek bar (gated on `hasDvr`). Does NOT include: speed,
  EQ, subtitles, A-B loop, episode nav — those are VOD-only.

- [x] **LIVE-P2-D** — `_buildLiveIdentityBar()`: logo + name + LIVE badge + subtitle.

- [x] **LIVE-P2-E** — `_buildLiveChannelRow()`: horizontal `ListView.builder` of
  channel logo cards. Reads from `ref.watch(liveChannelProvider).channels`. Tapping
  a channel calls `_switchLiveChannel(ch)`.

- [x] **LIVE-P2-F** — `_switchLiveChannel(LiveChannel ch)`: stops current stream,
  updates `widget` args (via `Navigator.pushReplacementNamed`), records watch history.
  Reuse existing `_openChannelSwitcher → onSelect` logic.

- [x] **LIVE-P2-G** — Wire new scaffold into player: in `build()`, gate on `_isLive &&
  isPortrait` to return `_buildLivePortraitScaffold()` instead of the standard
  `Scaffold` + `Stack`.

- [x] **LIVE-P2-H** — CI verify. No Oracle push needed.

---

## Phase 3 — Landscape player: TV-style fullscreen

**Scope**: `_ps_ui_mixin.dart`.

### Layout target (landscape / fullscreen)

```
┌──────────────────────────────────────────────┐
│ ← [Logo] Geo News   🔴 LIVE   HD        ⚙  │  top bar (fades with controls)
│                                              │
│                                              │
│              VIDEO FULLSCREEN                │
│                                              │
│                                [Logo 32px]  │  watermark (always visible, 20% opacity)
│ [DVR seek bar — only if hasDvr]              │
│ [☰ Channels]  [◀10s]  [▶/⏸]  [▶10s]  [🔒] │  bottom bar (fades with controls)
└──────────────────────────────────────────────┘
```

- Channel logo watermark: bottom-right, 32px, `opacity: 0.20`, always visible
  (disappears only in immersive mode)
- DVR seek bar: shows only if `channel.hasDvr == true` (currently Geo News only)
- Skip 10s buttons: show only if `hasDvr == true`
- Channel switcher panel: slides in from LEFT as a semi-transparent overlay
  (replaces the bottom-sheet approach in landscape)
- Swipe left/right on video → previous/next channel in current category

### Tasks

- [x] **LIVE-P3-A** — `_buildLiveLandscapeTopBar()`: back button + logo + name +
  LIVE badge + quality badge + settings. Auto-hides with `_showControls`.

- [x] **LIVE-P3-B** — `_buildLiveLandscapeBottomBar()`: channel list button, optional
  back-10s (if DVR), play/pause, optional fwd-10s (if DVR), lock. Fades with controls.

- [x] **LIVE-P3-C** — Channel logo watermark: `Positioned` bottom-right, `Opacity(0.20)`,
  `CachedNetworkImage` 32px, hidden in `_isImmersive`.

- [x] **LIVE-P3-D** — Landscape channel switcher: instead of `showModalBottomSheet`,
  slide in a `Positioned` left panel (width 280px, full height, semi-transparent dark
  bg). Triggered by the `☰ Channels` button. Closes on tap-outside or channel select.

- [x] **LIVE-P3-E** — Swipe-to-switch gesture: `HorizontalDragEnd` on the video area
  (velocity threshold > 500). Swipe left → next channel in same category; swipe right
  → previous. Show a channel-name toast for 1.5s after switching.

- [x] **LIVE-P3-F** — Wire new landscape controls into `_buildBottomArea()` /
  `_buildControlsOverlay()` behind `_isLive && isLandscape` gate.

- [x] **LIVE-P3-G** — CI verify.

---

## Phase 4 — Error screen + retry UX

**Scope**: `_ps_ui_mixin.dart`, `_ps_playback_mixin.dart`.

### Tasks

- [x] **LIVE-P4-A** — Dedicated live error widget `_buildLiveErrorOverlay()`:
  - Channel logo (64px) at top
  - Error icon + message (friendly, not raw exception text)
  - "Retry" button → calls `_openMedia(_currentFileId)` immediately
  - "Choose Another Channel" button → calls `_openChannelSwitcher()`
  - Subtle "Auto-retrying in Xs…" countdown label

- [x] **LIVE-P4-B** — Reconnecting state: when `_isLive && _buffering && _videoOpened`,
  show a "Reconnecting…" overlay (spinner + label) distinct from the error state.
  This is different from the initial loading spinner.

- [x] **LIVE-P4-C** — Error screen in portrait: shown in the video box area only,
  not full-screen. Below video, the identity bar and channel row remain visible.

- [x] **LIVE-P4-D** — Auto-retry for live: already planned in LIVE-P0-D (10s interval).
  Here: add visible countdown in the error overlay ("Retrying in 8s…").

- [x] **LIVE-P4-E** — CI verify.

---

## Phase 5 — Live TV tab UI fixes (from 2026-07-23 audit)

**Scope**: `live_tv_screen.dart` only. Small targeted fixes.

### Tasks

- [x] **LIVE-P5-A** — Search box border: already uses `t.border` (theme-aware). ✓ Already correct.

- [x] **LIVE-P5-B** — Sports category icon: `'🏏 Sports'` (cricket emoji) — correct. ✓ Already correct.

- [x] **LIVE-P5-C** — "FEATURED" badge: replace amber `Color(0xFFFFC107)` Container with
  `AppColors.primary` red pill — matches design system primary colour.

- [x] **LIVE-P5-D** — Featured banner background: already uses `ch.backdropColor`. ✓ Already correct.

- [x] **LIVE-P5-E** — Section header accent bar: uses per-category `_catAccent()` colours
  (better than a single colour). ✓ Already correct.

- [x] **LIVE-P5-F** — Recently-watched labels: already have `maxLines: 1, overflow: TextOverflow.ellipsis`. ✓ Already correct.

- [x] **LIVE-P5-G** — CI green confirmed.

---

## Phase 6 — Oracle: DVR URL audit + channel updates

**Scope**: `radd-hub/hub/db.py`. Oracle deploy required.

### Tasks

- [ ] **LIVE-P6-A** — Audit all 84 stream URLs manually for DVR capability:
  Check URL pattern (`playlist_dvr_timeshift` → DVR, plain `playlist.m3u8` / `chunks.m3u8` → no DVR).
  Current known DVR channels: **only Geo News** (`playlist_dvr_timeshift-0-3600.m3u8`).

- [ ] **LIVE-P6-B** — Add DVR URLs for other channels if available from tamashaweb:
  Some channels may have DVR variants at `playlist_dvr_timeshift-0-3600.m3u8`.
  Check by substituting the pattern into other channel paths (requires Jazz SIM).
  Update `stream_url` in seed data if DVR variants are confirmed working.

- [ ] **LIVE-P6-C** — Update `has_dvr` + `dvr_window_seconds` in seed data for all
  confirmed DVR channels. Push to Oracle + redeploy.

- [ ] **LIVE-P6-D** — CI verify + Oracle health check.

---

## Phase 7 — Quality selector for live streams

**Scope**: `_ps_ui_mixin.dart`, `_ps_panels_sidebar.dart`.

HLS ABR streams (`-abr/playlist.m3u8`) select quality automatically. But the player
can offer a quality selector by loading a specific rendition playlist.

### Tasks

- [ ] **LIVE-P7-A** — Research: check if tamashaweb CDN exposes rendition-level
  playlists (e.g. `playlist_720p.m3u8`) alongside the ABR master. If yes, build a
  quality picker sheet. If no, show "Auto (ABR)" label only.

- [x] **LIVE-P7-B** — Live settings panel: replace the full VOD settings panel with a
  slim live-only panel containing: Quality (Auto/720p/480p if available), Audio track
  (if multi-audio stream), Sleep timer.

- [x] **LIVE-P7-C** — CI verify.

---

## Phase ordering + dependencies

```
P0 (fix resolution) → P2 (portrait UI) → P3 (landscape UI) → P4 (error UX)
                   ↘
                    P1 (DVR model+DB) → P2 (DVR seek bar needs hasDvr flag)
                                      → P6 (Oracle DVR audit)

P5 (tab UI fixes) — independent, can run any time
P7 (quality selector) — depends on P2/P3 being done (uses same settings panel)
```

**Start with P0 — it unblocks all live TV testing and is the smallest change.**

---

## Files touched per phase

| Phase | Flutter files | Backend files |
|---|---|---|
| P0 | `_ps_playback_mixin.dart` | — |
| P1 | `live_channels.dart`, `local_db.dart` | `db.py`, `live_channels.py` |
| P2 | `_ps_ui_mixin.dart` | — |
| P3 | `_ps_ui_mixin.dart` | — |
| P4 | `_ps_ui_mixin.dart`, `_ps_playback_mixin.dart` | — |
| P5 | `live_tv_screen.dart` | — |
| P6 | — | `db.py` |
| P7 | `_ps_ui_mixin.dart`, `_ps_panels_sidebar.dart` | — |

---

## Rules for working on this plan

1. Follow Rule 42 (log → edit → push) for every file change.
2. After any push touching `raddflix_flutter/**`: check `build-apk.yml` CI (Rule 46).
3. After any push touching `test/`, `pubspec.yaml`, or `.github/workflows/`: also
   check `ci-tests.yml` (Rule 50).
4. After any push touching `radd-hub/**`: run `push_to_oracle.sh` and confirm final
   HEAD SHA matches Oracle (Rule 44).
5. Never skip the CI check between phases — a broken P0 will cascade into P2 failures.
6. Check `[x]` boxes only after push confirmed green, not after local edit.
