---
name: Network contentType routing
description: How http/https URLs from intents and UI are routed to the player as contentType 'network'.
---

## Rule
Any `pendingVideoUri` or warm-start `onVideoUri` URI that starts with `http://` or `https://` must be pushed to `/player` with `content_type: 'network'` and `stream_url: uri` — NOT as `content_type: 'movie'` with `local_path: uri`.

**Why:** Local-file and JazzDrive paths use `local_path` + `content_type: 'movie'` which routes through JazzDrive resolution and quota tracking in `_openMedia()`. Network URLs must skip that entirely via the early-exit `contentType == 'network'` branch added in NET-STREAM-1.

**How to apply:**
- `main.dart` warm-start handler: `uri.startsWith('http')` → network branch.
- `splash_screen.dart` cold-start handler: same check.
- `_ps_playback_mixin.dart` `_openMedia()`: `contentType == 'network'` block calls `_player.open(Media(url))` directly, then `_fetchLiveRenditions()` fire-and-forget.
- `_friendlyError()`: 'network' block before Jazz-SIM checks to avoid false "Jazz SIM required" messages.
- Share-sheet entry: `AndroidManifest.xml` `ACTION_SEND text/plain` + `extractSharedText()` in `MainActivity.kt` → `pendingVideoUri` = URL → picked up by cold/warm-start Dart handlers above.
- UI entry: "Play from URL" row in `LocalMediaScreen._buildVideosTab()` → `_playNetworkUrl()` → push with `content_type: 'network'`.
