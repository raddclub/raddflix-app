# Volume XI — Performance Standards

## Home
- First meaningful paint: <800ms
- On Air hero ready (art + title visible): <1200ms
- Rail scroll: sustained 60fps, no single frame >16ms
- Pre-warm during splash so first Home paint has no loading state

## Player
- Controls open (tap-to-reveal): <150ms
- Quality/bitrate switch: <500ms to resume playback at new quality
- Resume-from-background: <300ms to first frame

## Search
- Keystroke-to-results update: <300ms (debounced), perceived as live typing, not a separate "search" action

## Animation
- Minimum 60fps for all `Tune`/`Pulse`/transition animations on mid-tier and above devices (per existing `AnimConfig` tiers)
- `BackdropFilter` blur disabled entirely on Potato tier — sheets fall back to solid `surfaceHigh` fill
- Hero shared-element transitions skipped (instant cut) on Potato tier

## Memory
- Maximum cached full-resolution poster images: 60 in memory at once (LRU eviction)
- Maximum simultaneous in-flight `Hero` image transitions: 1
- Thumbnail cache (rails/grids): disk-cached, capped at 150MB, evicted oldest-first
- Video buffer disposal: player releases decoder/buffer resources within 2s of navigating away from the Player screen, not on next garbage-collection cycle
