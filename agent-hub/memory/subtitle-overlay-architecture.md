---
name: Subtitle Overlay Architecture
description: Why Flutter SubtitleOverlay (not MPV native) must own all subtitle rendering — the root cause of 100+ failed subtitle-fix commits and the three-piece fix.
---

## The Problem — Why 100+ commits failed

Two subtitle rendering systems existed in parallel but were never properly connected:

1. **MPV native renderer** — always active, rendering inside the Android SurfaceView (video texture). No knowledge of Flutter layout. `NativePlayer.setProperty('sub-font', ...)` pushes style properties here.
2. **Flutter `SubtitleOverlay`** — a complete, well-built widget in `lib/widgets/player/subtitle_overlay.dart` that reads `PlayerPrefs` and renders subtitles as Flutter `Text` widgets. Built for the purpose. **Never wired up.**

The `subtitle_overlay.dart` file's own opening comment reads: *"The MPV subtitle track is set invisible via SubtitleViewConfiguration(visible:false)"* — describing the intended design. But `SubtitleViewConfiguration(visible:false)` was never added to the Video widget, and `SubtitleOverlay` was never placed in any player Stack. Every previous fix attempt adjusted MPV property calls inside the wrong system.

---

## Why MPV native rendering can never be reliably customized

**1. ASS inline override tags bypass `sub-ass-override: force`**
`force` overrides the *script style block* at the top of an ASS file. It does **not** strip inline tags embedded inside dialogue lines like `{\c&H0000FF&}` or `{\an8\pos(320,50)}`. Most Urdu/Hindi subtitle files from the internet contain these inline tags — they always win regardless of what MPV properties you set.

**2. Renderer recreates itself on track changes, discards properties**
`_reapplySubtitleStyleAfterLifecycle()` uses a 150ms delay after track changes to re-push properties. This is a race condition — if MPV takes 200ms on a slower device, the reapply fires into the old renderer, the new renderer loads with default styles.

**3. MPV renderer lives inside SurfaceView — no Flutter layout knowledge**
`sub-margin-y` is measured from the video frame edge, not the screen. Every device/aspect-ratio/letterboxing combination produces a different result. There's no way to query the Flutter seekbar's pixel position from MPV.

**4. `_applySubtitleMargin()` was the last writer of `sub-ass-override`**
This function ran on every controls show/hide (20+ call sites). It originally set `sub-ass-override: 'yes'` — which lets the embedded ASS style block win — and was called after every style panel change, undoing the user's customization within seconds. Fixed to `'force'` in BUG-SUB-STYLE-01, but this only partially helps due to point 1 above.

---

## The Fix (commit `defb61e`, 2026-07-29)

Three pieces. **All three must be present or the fix breaks.**

### Piece 1 — Disable MPV's native renderer
In `_buildVideoSurface()` (`_ps_ui_mixin.dart`):
```dart
Video(
  controller: _videoCtrl,
  controls: NoVideoControls,
  fit: _getBoxFit(),
  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false), // CRITICAL
)
```
MPV now decodes subtitle text but renders nothing. The SurfaceView texture never has subtitle content.

### Piece 2 — Listen to the subtitle text stream
In `_wirePlayerStreams()` (`_ps_playback_mixin.dart`), inside the existing `_subs.addAll([...])`:
```dart
_player.stream.subtitle.listen((lines) {
  if (!mounted) return;
  final raw = lines.isNotEmpty ? lines.first : null;
  setState(() => _currentSubLine = (raw != null && raw.isNotEmpty) ? raw : null);
}),
```
`player.stream.subtitle` emits `List<String>` — index 0 is the primary track line. Stored in `String? _currentSubLine` declared in `_ps_subtitle_mixin.dart`.

### Piece 3 — Place SubtitleOverlay in all player stacks
In **landscape** stack (`player_screen.dart`) and **portrait** stack (`_ps_ui_mixin.dart _buildPortraitLayout`), after the video surface `Positioned.fill`:
```dart
if (!_isAudioOnly)
  Positioned.fill(
    child: Consumer(
      builder: (ctx, ref, _) {
        final prefs = ref.watch(playerPrefsProvider);
        return IgnorePointer(
          ignoring: !prefs.dictEnabled,
          child: SubtitleOverlay(
            currentLine: _currentSubLine,
            prefs: prefs,
            onPausedForLookup: () { try { _player.pause(); } catch (_) {} },
            onResumedAfterLookup: () { try { _player.play(); } catch (_) {} },
          ),
        );
      },
    ),
  ),
```
`IgnorePointer(ignoring: !prefs.dictEnabled)` lets taps fall through to the gesture layer (play/pause) when dict lookup is off. When dict is on, `SubtitleOverlay` handles word taps itself.

---

## What This Makes Redundant (but harmless to leave)

- `_applySubtitleStylePrefs()` calls to `sub-font`, `sub-color`, `sub-bold`, etc. — MPV accepts them, renders nothing
- `_applySubtitleMargin()` / `sub-margin-y` — Flutter layout handles position without this
- `_reapplySubtitleStyleAfterLifecycle()` — SubtitleOverlay reads live from PlayerPrefs, no "reapply" needed

**Exception:** `sub-delay` (subtitle sync) and `sub-speed` still affect MPV's *timing* of when subtitle text is emitted via `player.stream.subtitle`, even with native rendering disabled. Keep those calls.

---

## How SubtitleOverlay Positions Subtitles

`SubtitleOverlay._padding` getter (in `subtitle_overlay.dart`):
- `'top'` → `EdgeInsets.only(top: 20 + offset.abs())`
- `'center'` → `EdgeInsets.zero`
- `'bottom'` (default) → `EdgeInsets.only(bottom: 80 + offset.abs())`

`80px` bottom clearance is enough to avoid the seekbar. If the user adjusts the vertical offset slider (`PlayerPrefs.subtitleVerticalOffset`), it multiplies by 60 and adds to the padding.

The overlay is a `Positioned.fill` widget containing an `Align`, so Flutter's own layout system handles all positioning — no pixel math against video dimensions needed.

**Why:**
MX Player, VLC, and every serious video player on Android take the same approach — they disable the codec's subtitle renderer and render their own Flutter/native overlay. The codec renderer cannot know where UI controls are. Only the UI framework can know that.

**How to apply:**
Any time a future feature needs to customize subtitle appearance (font, color, size, position, outline, background) — implement it in `PlayerPrefs` + `SubtitleOverlay.build()`. Never go back to `NativePlayer.setProperty('sub-*', ...)` for visual styling.
