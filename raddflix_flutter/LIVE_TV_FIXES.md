# Live TV + Player Fix Backlog
> Created: 2026-07-29  
> Scope: Live TV screen UI/UX · Video player startup speed · Orientation logic · Channel image caching

---

## How to read this list

Each task has a short code, a priority (🔴 High / 🟡 Medium / 🟢 Low), the file(s) to touch, and an exact description of the change required. Tasks within a section are ordered by implementation dependency — complete them top-to-bottom where noted.

---

## SECTION 1 — Orientation (O)

### O-01 🔴 — Live TV should NOT force landscape; VOD/movies still must

**Problem:**  
`player_screen.dart` `initState` (line 222) unconditionally calls `_setNativeOrientation('sensor')`, which forces the device to auto-rotate. On Live TV this is jarring — users hold their phone in portrait to browse, tap a channel, and the screen violently rotates.

**Rule to implement:**
- `content_type == 'live'` → keep device in whatever orientation it is in (no forced rotate; `setPreferredOrientations` stays as all-4, `_setNativeOrientation` NOT called)
- `content_type == 'movie'` or `'series'` → keep current behaviour: `_setNativeOrientation('sensor')` so video auto-rotates to landscape once open

**Exact change — `player_screen.dart` initState (around line 212–223):**
```dart
// BEFORE
SystemChrome.setPreferredOrientations([...all four...]);
_setNativeOrientation('sensor');

// AFTER
SystemChrome.setPreferredOrientations([...all four...]);
if (!_isLive) {
  // VOD/movies: auto-rotate to match video dimensions
  _setNativeOrientation('sensor');
}
// Live TV: keep current device orientation — no forced rotate
```

**Also check disposal in `dispose()` (around line 342):**  
Ensure `_setNativeOrientation('unspecified')` and portrait restore are still called unconditionally on dispose (they already appear to be — confirm and leave them as-is).

**Files:** `lib/screens/player_screen.dart`  
**Depends on:** nothing — implement first

---

### O-02 🟡 — Auto-orient logic in `_ps_playback_mixin.dart` must also be gated for live

**Problem:**  
`_ps_playback_mixin.dart` line 1324 listens to video dimension changes and calls `_setNativeOrientation('sensor_landscape')` when `width >= height`. For live streams this fires as soon as the stream metadata arrives and forces landscape even if O-01 above is correctly fixed.

**Change:**
```dart
// Around line 1324, in the dimension-change listener:
if (_orientMode == 0 && !_isLive) {   // <-- add !_isLive guard
  if (width >= height) {
    _setNativeOrientation('sensor_landscape');
  } else {
    _setNativeOrientation('sensor_portrait');
  }
}
```

**Files:** `lib/screens/player/_ps_playback_mixin.dart`  
**Depends on:** O-01

---

## SECTION 2 — Video Startup Speed (V)

### V-01 🔴 — Pre-fetch stream URL BEFORE navigating to player (Live TV)

**Problem:**  
Currently `_playChannel` in `live_tv_screen.dart` (line 110) navigates to the player screen immediately, passing `stream_url: ch.streamUrl` from the channel model. For Live TV the `streamUrl` field is already available on the channel object (it comes from the catalog JSON), so this is actually not the bottleneck for Live TV.

**Actual bottleneck for Live TV:** The player's `_ps_playback_mixin.dart` `_openMedia` method calls `_generateLink()` which makes two sequential HTTP calls even for live streams (checking if a JazzDrive proxy URL is needed). For `content_type == 'live'`, skip `_generateLink()` entirely and call `player.open(Media(widget.streamUrl!))` directly.

**Change in `_ps_playback_mixin.dart` `_openMedia` (around line 568–580):**
```dart
// For live channels: stream URL is already resolved — open directly
if (_isLive && widget.streamUrl != null) {
  await _player.open(Media(widget.streamUrl!));
  return;
}
// For VOD: continue with existing _generateLink() logic below
```

**Files:** `lib/screens/player/_ps_playback_mixin.dart`  
**Depends on:** nothing — can implement standalone

---

### V-02 🔴 — Pre-fetch VOD stream URL on card tap (not after navigation)

**Problem:**  
For movies/shows the flow is: user taps → navigate to player screen → `initState` → `_generateLink()` → POST `_loginShare` → GET `_getMedia` → `player.open(url)`. The user watches a blank loading screen during the full round-trip (~800 ms – 2 s on slow networks).

**Proposed fix:**  
Start the URL fetch on tap (before `Navigator.push`), pass the resolved URL into the player arguments, and have the player call `player.open()` immediately on arrive.

**Implementation sketch:**
1. In `show_detail_screen.dart` (and any other screen that taps to play a movie/episode), change the tap handler to:
   ```dart
   // Start fetching the URL immediately — do not await here
   final urlFuture = ref.read(jazzDriveServiceProvider).generateLink(fileId: item.id);
   // Navigate immediately (user sees player UI right away)
   Navigator.pushNamed(context, AppRoutes.player, arguments: {
     ...existingArgs,
     'stream_url_future': urlFuture,   // pass the in-flight Future
   });
   ```
2. In `PlayerScreen` / `_ps_playback_mixin.dart`: if `stream_url_future` is present in arguments, `await` it instead of calling `_generateLink()` again — the URL is likely already resolved by the time the player screen mounts.

**Files:** `lib/screens/show_detail_screen.dart`, `lib/screens/player/_ps_playback_mixin.dart`, `lib/screens/player_screen.dart`  
**Depends on:** V-01 (implement live TV fast path first so the two paths don't conflict)

---

### V-03 🟡 — Move track preference application to before `player.open()`

**Problem:**  
`_ps_playback_mixin.dart` line 444 applies preferred audio/subtitle language AFTER `player.open()` fires, inside the `tracks` stream listener. This causes a second reconfigure cycle: the player opens with the default track, then switches — users hear/see a brief flicker or delay.

**Change:**  
Build a `MediaConfiguration` with preferred tracks before calling `player.open()`:
```dart
await _player.open(
  Media(resolvedUrl),
  // If media_kit supports initial track selection, pass it here.
  // Otherwise set it synchronously before open() via player.setAudioTrack(preferred).
);
```
If `media_kit` does not support pre-open track selection, apply the preference inside the `onOpen` callback immediately, not in the streaming `tracks` listener.

**Files:** `lib/screens/player/_ps_playback_mixin.dart`  
**Depends on:** V-01

---

## SECTION 3 — Channel Image Permanent Caching (I)

> **Context:** `PosterService` already permanently caches VOD posters in `getApplicationDocumentsDirectory()/.raddflix_media/` with a SQLite `titles` table (`id`, `poster_url`, `poster_path`). Channel logos need the same treatment using the channel's string `id` field.

### I-01 🔴 — Add `logo_path` column to `live_channels` SQLite table

**Change in `lib/core/db/local_db.dart`:**
- Bump `catalogDbVersion` in `AppConstants` (currently `27` → set to `28`)
- Add migration: `ALTER TABLE live_channels ADD COLUMN logo_path TEXT`
- Update `LiveChannel.fromRow()` and `toRow()` in `lib/data/live_channels.dart` to include `logoPath` (nullable `String?`)

**Files:** `lib/core/db/local_db.dart`, `lib/data/live_channels.dart`, `lib/core/constants.dart`  
**Depends on:** nothing — implement first in this section

---

### I-02 🔴 — Extend `PosterService` to handle channel logos

**Add to `lib/core/services/poster_service.dart`:**
```dart
// Download and permanently cache a channel logo.
// Key format: 'channel_{id}.jpg'
Future<String?> cacheChannelLogo(String channelId, String logoUrl) async { ... }

// Get cached logo path for a channel (returns null if not cached yet).
Future<String?> getChannelLogoPath(String channelId) async { ... }
```

**Storage:**
- Same `.raddflix_media` folder, filename `channel_{id}.jpg`
- Use the existing `live_channels` table's new `logo_path` column (from I-01) as the index — do NOT use the `titles` table

**Files:** `lib/core/services/poster_service.dart`  
**Depends on:** I-01

---

### I-03 🔴 — Wire channel logo disk cache into `live_tv_screen.dart`

**Change:** Replace all three `CachedNetworkImage(imageUrl: channel.logoUrl, ...)` usages (lines 617, 873, 1015) with a helper widget `_ChannelLogo` that:

1. Checks `channel.logoPath` — if non-null and the file exists on disk → `Image.file(File(channel.logoPath!), fit: BoxFit.contain)`
2. Falls back to `CachedNetworkImage` and, on load success, triggers `posterService.cacheChannelLogo(channel.id, channel.logoUrl)` in the background (non-blocking `unawaited`)

```dart
class _ChannelLogo extends ConsumerWidget {
  final LiveChannel channel;
  final double? width, height;
  final BoxFit fit;
  // ...
  Widget build(BuildContext context, WidgetRef ref) {
    if (channel.logoPath != null) {
      final f = File(channel.logoPath!);
      // Synchronous existence check is fine for a local path
      if (f.existsSync()) return Image.file(f, fit: fit, ...);
    }
    return CachedNetworkImage(
      imageUrl: channel.logoUrl,
      fit: fit,
      imageBuilder: (ctx, provider) {
        // Trigger permanent save in background on first successful network load
        unawaited(ref.read(posterServiceProvider).cacheChannelLogo(
          channel.id, channel.logoUrl));
        return Image(image: provider, fit: fit);
      },
      placeholder: (_, __) => const _LogoPlaceholder(),
      errorWidget: (_, __, ___) => _LogoFallback(name: channel.name),
    );
  }
}
```

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** I-01, I-02

---

### I-04 🟡 — Add channel logo warm-up to `PosterSyncNotifier`

**Change in `lib/providers/poster_sync_provider.dart`:**  
Add a `syncChannelLogos(List<LiveChannel> channels)` method that runs after the existing VOD sync, rate-limited to 50 channels per run (logos are smaller than posters; 50 is safe).

Call it from wherever `scheduleSync()` is called (catalog provider), passing the live channels list.

**Files:** `lib/providers/poster_sync_provider.dart`  
**Depends on:** I-02

---

## SECTION 4 — Live TV UI Polish (UI)

### UI-01 🟡 — Fix search bar keyboard dismiss + missing `textInputAction`

**Problem:** Keyboard stays open when user scrolls. No `TextInputAction.search` on the keyboard.

**Changes in `live_tv_screen.dart`:**
1. Wrap the outer `CustomScrollView` (or `Column`) in a `NotificationListener<ScrollNotification>` that calls `FocusScope.of(context).unfocus()` on scroll start:
   ```dart
   NotificationListener<ScrollStartNotification>(
     onNotification: (_) { FocusScope.of(context).unfocus(); return false; },
     child: CustomScrollView(...)
   )
   ```
2. Add `textInputAction: TextInputAction.search` to the `TextField` in `_buildSearchBar`
3. Add `onSubmitted: (_) => FocusScope.of(context).unfocus()` to the same `TextField`

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing

---

### UI-02 🟡 — Add "Clear search" button to empty-results state

**Problem:** When no channels match, user sees only text. No way to clear query without manually deleting.

**Change in `_buildEmptySearch` / empty state widget:**  
Add a `TextButton('Clear search', onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })` below the "No channels found" text.

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing

---

### UI-03 🟡 — Replace `CircularProgressIndicator` loading with shimmer skeleton cards

**Problem:** `_buildLoading` uses a generic spinner. The `shimmer` package (`^3.0.0`) is already in `pubspec.yaml`.

**Change:** Replace `_buildLoading` with a `SliverGrid` of shimmer skeleton cards that match the `_GridCard` dimensions (`RaddRadius.lgRadius`, same aspect ratio):
```dart
Shimmer.fromColors(
  baseColor: AppColors.surface,
  highlightColor: AppColors.surfaceHigh,
  child: GridView.builder(
    itemCount: 12,
    itemBuilder: (_, __) => Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: RaddRadius.lgRadius,
      ),
    ),
  ),
)
```

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing

---

### UI-04 🟡 — Fix header text styles to use `RaddTheme` tokens

**Problem:** "Live TV" title and "LIVE" badge use hardcoded `fontWeight: FontWeight.w800` / `fontSize: 22` instead of design tokens.

**Changes in the header `Row` (around lines 176–224):**
- Replace hardcoded `TextStyle` for "Live TV" with `t.heading2` (or appropriate `RaddTheme` token)
- Replace the "LIVE" badge `TextStyle` with `t.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)`
- Replace hardcoded channel count badge container with a `RaddChip` (or the existing design-system chip component)

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing

---

### UI-05 🟢 — Unify card corner radius and fallback logo widgets

**Problem:**  
- `_GridCard` uses `RaddRadius.lgRadius`, `_HorizontalCard` uses `RaddRadius.mdRadius` — inconsistent in the same screen  
- `_GridCard` error uses `_LogoFallback`, `_HorizontalCard` error uses `_SmallLogoFallback`, Recent row uses raw `Icon`

**Changes:**
- Standardise both card types to `RaddRadius.lgRadius`
- Replace `_SmallLogoFallback` and `_LogoFallback` with a single `_ChannelLogoFallback({required String name, double iconSize = 28})` that adapts to its parent's available space
- Replace the raw `Icon(AppIcons.tv)` placeholder in `_buildRecentRow` with the same `_ChannelLogoFallback`

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** I-03 (since `_ChannelLogo` will own the fallback)

---

### UI-06 🟢 — Fix `_pulseCtrl` AnimatedBuilder performance anti-pattern

**Problem:** The live-dot pulse animation `_pulseCtrl` is wrapped in an `AnimatedBuilder` inside every `_GridCard` and `_HorizontalCard`. Each animation tick repaints every card in the grid — severe jank at 60 fps with 50+ channels.

**Fix:** Move the `AnimatedBuilder` to the outermost level and pass the current opacity value down as a plain `double` prop:
```dart
// In build(), once:
AnimatedBuilder(
  animation: _pulseCtrl,
  builder: (_, __) {
    final pulseOpacity = 0.5 + 0.5 * _pulseCtrl.value;
    return _buildChannelList(pulseOpacity: pulseOpacity);
  },
)

// _GridCard and _HorizontalCard accept pulseOpacity as a double, no animation widget inside
```

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing (but do after other UI tasks to avoid merge conflicts)

---

### UI-07 🟢 — Replace hardcoded `_catAccent` hex map with `AppColors` tokens

**Problem:** `_catAccent` (lines 38–49) maps genre names to raw hex strings like `'#FF6B6B'`, `'#4ECDC4'`. These are out of sync with the design system and will break in light mode.

**Change:** Replace with `AppColors` constants or `RaddTheme` surface/accent tokens. Where no exact match exists, use `AppColors.primary`, `AppColors.info`, `AppColors.success`, `AppColors.warning` as appropriate per genre.

**Files:** `lib/screens/live_tv_screen.dart`  
**Depends on:** nothing

---

## SECTION 5 — Summary Table

| Code | Priority | Section | One-liner |
|------|----------|---------|-----------|
| O-01 | 🔴 High | Orientation | Gate `_setNativeOrientation('sensor')` behind `if (!_isLive)` |
| O-02 | 🟡 Medium | Orientation | Gate dimension-change auto-rotate listener behind `!_isLive` |
| V-01 | 🔴 High | Startup Speed | Skip `_generateLink()` for live; call `player.open(streamUrl)` directly |
| V-02 | 🔴 High | Startup Speed | Pre-fetch VOD URL on card tap; pass in-flight `Future` to player |
| V-03 | 🟡 Medium | Startup Speed | Apply track prefs before/at open, not in post-open stream listener |
| I-01 | 🔴 High | Image Cache | Add `logo_path` column to `live_channels` table (DB version 28) |
| I-02 | 🔴 High | Image Cache | Extend `PosterService` with `cacheChannelLogo` / `getChannelLogoPath` |
| I-03 | 🔴 High | Image Cache | Replace all 3 `CachedNetworkImage` logo uses with `_ChannelLogo` widget |
| I-04 | 🟡 Medium | Image Cache | Add channel logo warm-up pass to `PosterSyncNotifier` |
| UI-01 | 🟡 Medium | UI Polish | Keyboard dismiss on scroll + `TextInputAction.search` |
| UI-02 | 🟡 Medium | UI Polish | "Clear search" CTA in empty-results state |
| UI-03 | 🟡 Medium | UI Polish | Shimmer skeleton loading instead of `CircularProgressIndicator` |
| UI-04 | 🟡 Medium | UI Polish | Header text to `RaddTheme` tokens; count badge to `RaddChip` |
| UI-05 | 🟢 Low | UI Polish | Unify card radius; single `_ChannelLogoFallback` widget |
| UI-06 | 🟢 Low | UI Polish | Move `_pulseCtrl` `AnimatedBuilder` out of per-card widgets |
| UI-07 | 🟢 Low | UI Polish | Replace `_catAccent` hex map with `AppColors` tokens |

**Implementation order for minimum conflict:**
1. O-01 → O-02
2. I-01 → I-02 → I-03 → I-04
3. V-01 → V-02 → V-03
4. UI-01, UI-02, UI-03, UI-04 (independent of each other)
5. UI-05, UI-06, UI-07 (do last — touch the most code)
