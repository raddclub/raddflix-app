# RaddFlix — Vibe Modes + Critical Bug Fixes Plan
Last updated: 2026-07-30

This document is the authoritative task breakdown for:
1. **Phase 0 — Critical Bug Fixes** (first priority — ship before any Vibe work)
2. **Phases 1–5 — Vibe Modes feature** (new audio mood/vibe presets in the player)

Work top-to-bottom within each phase. Phase 0 is a hard prerequisite for everything after.
Follow Rule 42 (log → edit → auto_commit) for every single file change.
Check CI (`build-apk.yml`) after every push touching `raddflix_flutter/**`.

---

## PHASE 0 — Critical Bug Fixes (Ship First)

### 0A — SUB-GRAY-SCREEN: Subtitle overlay shows full-screen gray tint

**Symptom:** Whenever a subtitle line is due to appear, instead of the subtitle text
appearing cleanly, a transparent-gray overlay covers the entire video player. The video
is still visible underneath but the tint is distracting and the subtitle text may or may
not be readable on top of it.

**Root cause (confirmed by code analysis):**

`SubtitleOverlay.build()` returns `Positioned.fill(child: Align(...))` from inside its
own `build()` method. The parent already wraps `SubtitleOverlay` in its own
`Positioned.fill → IgnorePointer`. This means the `Positioned.fill` returned by
`SubtitleOverlay` is NOT a direct Stack child — it is inside `IgnorePointer`, which is
not a Stack. In Flutter release builds, a `Positioned` widget that is not a direct Stack
child silently fills its parent (behaves like `SizedBox.expand()`). This causes:

1. The inner `Positioned.fill` expands to cover the entire player area.
2. `Align` inside it also expands to fill (as it should when given full constraints).
3. The `GestureDetector` inside claims hit-test area for its entire layout bounding box.
4. The `Container` with `decoration: BoxDecoration(color: bgColor)` is rendered inside
   the full-area widget — even when `bgColor` has near-zero opacity, the Container still
   creates a composited layer that can appear as a faint gray overlay, especially on
   frames where `AnimatedSwitcher` is mid-transition.

Secondary cause: whitespace-only subtitle lines (`" "`, `"\n"`, `"\r\n"`) pass the
`currentLine!.isEmpty` guard, causing the Container to be built with no visible text
content. An empty Container inside `Align` inside the expanded `Positioned.fill` expands
to fill available space — the gray color then covers the full player.

**Files to change:**
- `raddflix_flutter/lib/widgets/player/subtitle_overlay.dart`

**Exact fix:**

Step 1 — Remove the outer `Positioned.fill` wrapper from `build()`. The method should
return `Align(alignment: _alignment, child: Padding(padding: _padding, child: ...))`.
The parent's `Positioned.fill` already provides the full-screen container; the inner one
is redundant and harmful.

Step 2 — Tighten the null/empty guard to use `.trim()`:
```dart
// BEFORE:
if (widget.currentLine == null || widget.currentLine!.isEmpty) {
  return const SizedBox.shrink();
}

// AFTER:
if (widget.currentLine == null || widget.currentLine!.trim().isEmpty) {
  return const SizedBox.shrink();
}
```

Step 3 — Wrap the `GestureDetector` in `UnconstrainedBox` or ensure `Container` has
`mainAxisSize: MainAxisSize.min` equivalent. The Container should size only to its
text content, not expand. Add `constraints: const BoxConstraints()` to the Container
or use `IntrinsicWidth(child: IntrinsicHeight(child: Container(...)))` — but the
simpler fix of removing the outer `Positioned.fill` should resolve the expansion issue
entirely.

Step 4 — Also check `DualSubtitleOverlay` widget (if it exists separately from
`SubtitleOverlay`) for the same `Positioned.fill` self-wrapping pattern. Apply the
same fix if present.

**Testing:** After the fix, enable any subtitle track on a video and confirm: (a) no
gray tint visible, (b) subtitle text appears at the correct position, (c) long-press
to copy still works, (d) dict lookup tap still works when dictEnabled is true.

---

### 0B — PLAYER-PERF: Player is slow and hangs during playback

**Symptom:** The video player has become noticeably heavy — UI hangs during gestures,
controls are sluggish to appear/hide, and the overall feel is far below MX Player's
smoothness.

**Root cause (multi-factor):**

1. **Excessive `setState()` calls triggering full subtree rebuilds.** The player has
   several codepaths that call `setState()` frequently:
   - `_applySubtitleMargin(controlsVisible:)` — called on nearly every controls
     show/hide transition, triggers MPV property writes + setState
   - `_scheduleHide()` timer ticks that call setState
   - Subtitle stream listener (`player.stream.subtitle.listen`) emits on every subtitle
     change and calls setState, which rebuilds the entire player widget tree

2. **Consumer widgets watching `playerPrefsProvider` too broadly.** Multiple
   `Consumer(builder: (ctx, ref, _) { ... })` blocks rebuild the ENTIRE block when
   ANY field in PlayerPrefs changes. PlayerPrefs is a large immutable class — even
   changing a subtitle font triggers rebuilds of the video surface wrapper, the controls
   overlay, etc.

3. **`RepaintBoundary` missing around high-churn widgets.** The subtitle overlay and
   the seek-bar progress indicator rebuild frequently. Without `RepaintBoundary`,
   their repaints propagate to parent layers.

4. **`_buildMergedAfString()` string concatenation** called from `_applyAllAf()` on
   every Lab/EQ/balance toggle. This is not the primary perf issue but adds micro-pauses.

5. **God-class `player_screen.dart` (~9,500 lines)** — the ongoing Phase J
   decomposition is the right long-term fix. Short-term wins exist in points 1–4 above.

**Files to change:**
- `raddflix_flutter/lib/screens/player/_ps_subtitle_mixin.dart`
- `raddflix_flutter/lib/screens/player/_ps_ui_mixin.dart`
- `raddflix_flutter/lib/widgets/player/subtitle_overlay.dart`

**Exact fixes:**

Fix 0B-1 — `ValueNotifier` for subtitle line instead of `setState`.
In `_ps_playback_mixin.dart`, change `_currentSubLine` from a plain `String?` field
set via `setState()` to a `ValueNotifier<String?>`. Update the stream listener to
`_currentSubLineNotifier.value = raw`. In `_ps_ui_mixin.dart`, wrap only the
`SubtitleOverlay` Positioned.fill in a `ValueListenableBuilder<String?>` instead of
using the full Consumer rebuild. This removes the main-thread `setState()` on every
subtitle tick (~1-10 per second).

Fix 0B-2 — Scope Consumer rebuilds. Split the large Consumer blocks into smaller
`Consumer` widgets watching only the specific prefs fields they need, or use
`ref.select()` to filter:
```dart
// BEFORE:
Consumer(builder: (ctx, ref, _) {
  final prefs = ref.watch(playerPrefsProvider);
  return SubtitleOverlay(currentLine: ..., prefs: prefs);
})

// AFTER (ref.select limits rebuild to only when subtitleXxx fields change):
Consumer(builder: (ctx, ref, _) {
  final prefs = ref.watch(
    playerPrefsProvider.select((p) => (
      p.subtitleFontSize, p.subtitleTextColorValue, p.subtitleEnabled,
      p.subtitlePosition, p.subtitleVerticalOffset, p.dictEnabled,
    )),
  );
  ...
})
```

Fix 0B-3 — Add `RepaintBoundary` around the subtitle overlay Positioned.fill and the
seek-bar widget. These are the two highest-frequency-repaint widgets in the player.
The seek-bar already has one in some places — verify both landscape and portrait stacks.

Fix 0B-4 — Debounce `_applySubtitleMargin()`. It calls `_np.setProperty()` on every
controls show/hide. Add a 16ms debounce so rapid show/hide cycles don't hammer MPV
with redundant property writes.

---

### 0C — THUMB-PERF: Local tab folder/video thumbnails are extremely slow to load

**Symptom:** Opening the Local tab or entering a video folder is very slow. Video
thumbnails take many seconds to appear. The UI may hang or jank during loading.
On folders with 30+ videos, the experience is unusable.

**Root cause (confirmed by code analysis):**

The current thumbnail pipeline:
1. Try `LocalMediaService.getThumbnailById(id)` → Kotlin `loadThumbnail()` (API 29+)
   or `ThumbnailUtils.createVideoThumbnail()` (API < 29)
2. If that fails → `ThumbService.getThumbnail(filePath)` → `MediaKitThumbnailExtractor.extractFrame()`

`MediaKitThumbnailExtractor.extractFrame()` does the following per thumbnail:
- Creates a full `Player()` instance (libmpv initialization, ~200ms)
- Opens the video file (`player.open()`) — involves format probing (~300ms)
- Waits for `player.stream.duration` to emit a non-zero value (up to 5s timeout)
- Seeks to 3000ms (`player.seek()`)
- Waits 150ms for frame to land
- Calls `player.screenshot()` (~50ms)
- Disposes the Player (`player.dispose()`) — important but adds time

Total per thumbnail on a mid-range Android device: **1.5–4 seconds**. With 30 videos
in a folder loaded in batches of 5: minimum 9–24 seconds just for thumbnails.

**What MX Player, VLC, and every major file manager does:**
Android's `MediaStore` pre-generates thumbnails asynchronously for all indexed media.
`ContentResolver.loadThumbnail()` (API 29+) reads from this pre-generated cache — it
is effectively instant (<50ms) for already-indexed files. For files not yet indexed
(e.g., just-copied files), the fallback should be `MediaMetadataRetriever.getFrameAtTime()`
running inside a **Kotlin coroutine on a background thread** — NOT a full libmpv Player.
`MediaMetadataRetriever` is part of Android's built-in media framework, requires no
extra native libraries, and runs the frame extraction entirely off the main thread
in ~100–400ms per file. It never causes ANRs because it is explicitly designed for
background use.

The current code switched from `video_thumbnail` to `MediaKitThumbnailExtractor` to
avoid ANRs (correct diagnosis) but chose the wrong replacement (full Player = way
heavier than needed). The right fix is `MediaMetadataRetriever` in a Kotlin coroutine.

**Files to change:**
- `android/app/src/main/kotlin/com/raddflix/app/MediaStorePlugin.kt` (Kotlin side)
- `raddflix_flutter/lib/services/media_kit_thumbnail_extractor.dart` (replace/wrap)
- `raddflix_flutter/lib/services/thumb_service.dart` (update fallback chain)
- `raddflix_flutter/lib/screens/local_folder_screen.dart` (concurrency + visibility)
- `raddflix_flutter/lib/screens/local_media_screen.dart` (concurrency + visibility)

**Exact fixes:**

Fix 0C-1 — Add `MediaMetadataRetriever` method to `MediaStorePlugin.kt`.
Add a new `"getFrameAtTime"` case to the MethodChannel handler:
```kotlin
"getFrameAtTime" -> {
    val filePath = call.argument<String>("path") ?: return result.success(null)
    val timeUs   = (call.argument<Int>("timeMs") ?: 3000).toLong() * 1000L
    val maxDim   = call.argument<Int>("maxDim") ?: 240
    CoroutineScope(Dispatchers.IO).launch {
        try {
            val mmr = MediaMetadataRetriever()
            mmr.setDataSource(filePath)
            val bmp = mmr.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            mmr.release()
            if (bmp == null) { withContext(Dispatchers.Main) { result.success(null) }; return@launch }
            val scaled = Bitmap.createScaledBitmap(
                bmp, maxDim, (bmp.height * maxDim / bmp.width).coerceAtLeast(1), true
            )
            bmp.recycle()
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 72, out)
            scaled.recycle()
            withContext(Dispatchers.Main) { result.success(out.toByteArray()) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.success(null) }
        }
    }
}
```

Fix 0C-2 — Update `ThumbService` fallback chain. Replace `MediaKitThumbnailExtractor`
call with the new MethodChannel `getFrameAtTime` call. Keep MediaKit extractor as a
third-tier fallback (for containers MMR can't handle) with a short 3s timeout.
```dart
// New fallback order in ThumbService.getThumbnail():
// 1. Memory cache (already done)
// 2. Disk cache (already done)
// 3. MediaMetadataRetriever via MethodChannel (NEW — fast, no ANR)
// 4. MediaKitThumbnailExtractor (existing — slow, last resort)
```

Fix 0C-3 — Lazy/visibility-gated loading in folder screens. Only generate thumbnails
for items currently visible in the grid. Use a `ScrollController` + `VisibilityDetector`
pattern (or simpler: only load thumbnails for items within index range of current
`_firstVisibleIndex` to `_firstVisibleIndex + 20`). Load in batches of 2 (not 5)
to avoid creating multiple heavy decoders simultaneously.

Fix 0C-4 — Persistent disk cache across sessions. `ThumbService` already writes to
`$appDocDir/.thumbs/<md5_hash>.jpg`. Verify the disk cache path persists across app
restarts (it does — `getApplicationDocumentsDirectory()` is stable). Add cache size
limit: delete files older than 30 days if total `.thumbs/` directory size > 200MB.

Fix 0C-5 — Show skeleton placeholder immediately. In `local_folder_screen.dart` and
`local_media_screen.dart`, while a thumbnail is loading show a `Container` with a
shimmer effect (use existing shimmer infrastructure from home screen) rather than a
gray box. This makes the UI feel responsive even before thumbnails load.

---

## PHASE 1 — Vibe Modes: Foundation

> Works for BOTH video and audio files. On video: speed-affecting modes (Slowed,
> NightCore, Phonk) also slow/speed the video track, which looks intentional on music
> videos but may look odd on dialogue scenes. 8D, Club Mix, and Lofi (mild) are audio-
> only effect changes — video speed is unchanged. UI cards show a "Video slows too"
> warning chip for speed-affecting modes.

### 1A — Add `asetrate` and `apulsator` primitives to the af pipeline

**File:** `raddflix_flutter/lib/screens/player/_ps_audiolab_mixin.dart`

Add `String _currentVibeAf = '';` state variable alongside the existing
`_currentReverbAf`, `_currentLabAf`, etc.

In `_buildMergedAfString()`, insert the vibe af segment in the correct filter order:
after format normalization but BEFORE the reverb chain and lab chain. The vibe filter
affects the audio stream that ALL subsequent filters receive. Example order:
```
aformat → EQ equalizer → [vibe af: asetrate / apulsator] → reverb (aecho) → lab chain → balance pan
```

Important: `asetrate` changes the audio sample rate. If another filter downstream
expects a specific sample rate, pair it with `aresample=44100` immediately after. The
existing `aformat` guard (added in AUDIO-FIX-3) already handles multi-channel normalization.

`apulsator` (for 8D): `apulsator=hz=0.18:type=sine:width=1.0` — pans the audio
left-right in a slow sine wave. No sample rate change, so no aresample needed.

### 1B — Add `PlaybackVibeMode` enum and `PlayerPrefs` field

**File:** `raddflix_flutter/lib/core/player/player_prefs.dart`

Add enum:
```dart
enum PlaybackVibeMode {
  none,
  slowed,
  slowedReverb,
  nightcore,
  lofi,
  eightD,
  phonk,
  club,
}
```

Add to `PlayerPrefs`:
```dart
final PlaybackVibeMode vibeMode;       // default: PlaybackVibeMode.none
final bool rememberVibeMode;           // default: false — reset on new file
```

Add to `copyWith()`, `save()`, `load()`. Use int index for persistence:
`s.setInt('${_p}vibe_mode', vibeMode.index)`.

### 1C — Add `_applyVibeMode(PlaybackVibeMode mode)` to the audiolab mixin

**File:** `raddflix_flutter/lib/screens/player/_ps_audiolab_mixin.dart`

```dart
void _applyVibeMode(PlaybackVibeMode mode) {
  setState(() => _currentVibe = mode);

  // Speed-affecting modes: change playback speed AND disable pitch correction
  // so pitch drops/rises naturally with the speed (the "vinyl" effect).
  // For audio-only files, asetrate is used in the af chain instead of speed,
  // giving a purer vinyl slowdown without affecting any video track.
  switch (mode) {
    case PlaybackVibeMode.none:
      _currentVibeAf = '';
      _setSpeed(1.0);              // restore normal speed
      // restore pitch correction to its saved state
      break;

    case PlaybackVibeMode.slowed:
      if (_isAudioOnly) {
        _currentVibeAf = 'asetrate=44100*0.82,aresample=44100';
      } else {
        _currentVibeAf = '';
        _setSpeed(0.82);           // video + audio both slow
        // disable pitch correction → pitch drops with speed (vinyl feel)
      }
      break;

    case PlaybackVibeMode.slowedReverb:
      final slowPart = _isAudioOnly
          ? 'asetrate=44100*0.82,aresample=44100,'
          : '';         // speed handled via _setSpeed below
      _currentVibeAf = '${slowPart}aecho=0.8:0.88:300|600|900:0.4|0.25|0.12';
      if (!_isAudioOnly) _setSpeed(0.82);
      break;

    case PlaybackVibeMode.nightcore:
      if (_isAudioOnly) {
        _currentVibeAf = 'asetrate=44100*1.25,aresample=44100';
      } else {
        _currentVibeAf = '';
        _setSpeed(1.25);
        // disable pitch correction → pitch rises with speed (NightCore feel)
      }
      break;

    case PlaybackVibeMode.lofi:
      // Very mild speed change (0.93×) — barely noticeable on video.
      // lowpass=f=9000 gives the warm, slightly muffled cassette feel.
      final lofiSlow = _isAudioOnly ? 'asetrate=44100*0.93,aresample=44100,' : '';
      _currentVibeAf = '${lofiSlow}lowpass=f=9000,aecho=0.65:0.75:80|200:0.2|0.12';
      if (!_isAudioOnly) _setSpeed(0.93);
      break;

    case PlaybackVibeMode.eightD:
      // Pure panning LFO — no speed change. Works on both video and audio.
      _currentVibeAf = 'apulsator=hz=0.18:type=sine:width=1.0';
      break;

    case PlaybackVibeMode.phonk:
      final phonkSlow = _isAudioOnly ? 'asetrate=44100*0.90,aresample=44100,' : '';
      _currentVibeAf = '${phonkSlow}aecho=0.78:0.88:200|400:0.4|0.2';
      if (!_isAudioOnly) _setSpeed(0.90);
      // Also apply heavy bass EQ boost via _applyPreset or direct band override
      _applyVibeBassBoost(intensity: 0.8);   // helper defined below
      break;

    case PlaybackVibeMode.club:
      // No speed change — pure audio effect. extrastereo + acompressor.
      _currentVibeAf =
          'extrastereo=m=2.5,acompressor=threshold=0.4:ratio=4:attack=20:release=250';
      _applyVibeBassBoost(intensity: 0.5);
      break;
  }

  _applyAllAf();
  _adjustSubSyncForVibe(mode);   // Phase 1D
  _scheduleSavePrefs();
}
```

### 1D — Subtitle sync compensation for speed-affecting vibe modes

**File:** `raddflix_flutter/lib/screens/player/_ps_subtitle_mixin.dart`

When a vibe mode changes playback speed, subtitle timing is unaffected (subtitles are
still indexed to real-time timestamps). Add `_adjustSubSyncForVibe(PlaybackVibeMode mode)`:
- For Slowed (0.82×): `sub-speed` stays at 1.0 but the timestamps effectively drift.
  MPV's `sub-delay` can compensate for a fixed drift, but variable content makes this
  impractical. Instead: set `sub-speed` to match the vibe mode's speed ratio so subtitle
  timing tracks the slowed audio. `_np.setProperty('sub-speed', '0.82')` for Slowed.
- Restore `sub-speed` to '1' when vibe mode is set back to `none`.

### 1E — Reset vibe mode on new file load

**File:** `raddflix_flutter/lib/screens/player/_ps_playback_mixin.dart`

In `_onMediaChanged()` / episode reset logic: if `!prefs.rememberVibeMode`,
call `_applyVibeMode(PlaybackVibeMode.none)` before loading the new file.
This prevents slowed+reverb bleeding into the next episode accidentally.

---

## PHASE 2 — Vibe Modes: Core 4 Modes (Shippable MVP)

These four modes are the high-impact, high-demand ones. Phase 2 = shipping the
_applyVibeMode implementations defined in Phase 1C above for:

| ID | Mode | Speed | af filters | Pitch |
|---|---|---|---|---|
| 2A | **Slowed** | 0.82× | none beyond speed | drops with speed |
| 2B | **Slowed + Reverb** | 0.82× | `aecho=0.8:0.88:300\|600\|900:0.4\|0.25\|0.12` | drops with speed |
| 2C | **NightCore** | 1.25× | none beyond speed | rises with speed |
| 2D | **Lofi** | 0.93× | `lowpass=f=9000` + soft `aecho` | drops slightly |

After Phase 2 the feature is usable even without Phase 3–5 UI (can be tested via
the AudioLab toggle or a quick debug toggle). Phase 4 (UI) is needed for user-facing release.

---

## PHASE 3 — Vibe Modes: Extended Modes

| ID | Mode | Speed | af filters | Notes |
|---|---|---|---|---|
| 3A | **8D Audio** | 1.0× | `apulsator=hz=0.18:type=sine:width=1.0` | Headphones-only warning |
| 3B | **Phonk** | 0.90× | `aecho=0.78:0.88:200\|400:0.4\|0.2` + bass boost | Heavy bass preset |
| 3C | **Club Mix** | 1.0× | `extrastereo=m=2.5` + `acompressor` + mild bass | Replaces "DJ Mode" concept |

---

## PHASE 4 — Vibe Modes: UI

### 4A — "Vibe" tab in the Audio Effect panel

**File:** `raddflix_flutter/lib/screens/player/_ps_panels_audio.dart`

Add a 4th tab alongside Presets / Equalizer / Lab. Tab label: "Vibe" with a
`Icons.auto_awesome_rounded` or `Icons.graphic_eq_rounded` icon.

Content: a 2-column `GridView` of `_VibeModeCard` widgets (see 4B).

### 4B — `_VibeModeCard` widget

Each card shows:
- Icon (distinct per mode — e.g. `Icons.snooze` for Slowed, `Icons.bolt` for NightCore)
- Mode name (bold)
- One-line vibe description ("dreamy & deep", "energetic & hyped", "warm & muffled")
- Active state: accent-red glow border + filled red indicator dot

Chips below the name for modes that have side effects:
- Speed-affecting modes on video: `"Video slows too"` chip (orange, only when `!_isAudioOnly`)
- 8D Audio: `"🎧 Best with headphones"` chip

Tapping an active card deactivates it (sets mode back to `none`).

### 4C — Quick bar integration

**File:** `raddflix_flutter/lib/screens/player/_ps_ui_mixin.dart` (quick bar section)

Add `"vibe"` as a valid quick bar item ID. When active, the quick bar button shows the
current mode name (e.g. "Slowed") as a text badge. Tapping opens the Vibe tab of the
Audio Effect panel directly (pass `initialTabIndex: 3` to the panel open method).

### 4D — Audio-only (vinyl disc) integration

**File:** `raddflix_flutter/lib/screens/player/audio_mode_backdrop.dart`

Add a "Vibe" icon button to the frosted-glass controls card, next to the existing
playback controls. Tapping cycles through: None → Slowed → Slowed+Reverb → Lofi →
8D Audio → (back to None).

When a vibe mode is active:
- Show the mode name as a subtle label below the album title
- Adjust disc rotation speed to match the audio tempo:
  - Slowed/Phonk: reduce `_rotationCtrl.animationSpeed` multiplier to 0.82×
  - NightCore: increase to 1.25×
  - 8D: keep normal speed but add a subtle left-right oscillation to the disc widget

---

## PHASE 5 — Vibe Modes: Polish

### 5A — "Remember Vibe" user preference

**File:** `raddflix_flutter/lib/screens/settings_screen.dart`

Add a toggle under the Playback section: "Remember vibe mode between videos."
Default: OFF (reset to Original on each new file). Stored in `PlayerPrefs.rememberVibeMode`.

### 5B — Vibe mode in player info HUD

**File:** `raddflix_flutter/lib/screens/player/_ps_ui_mixin.dart` (HUD section)

When `showPlaybackInfo` is true and a vibe mode is active, show the mode name alongside
speed/codec info in the diagnostics HUD (e.g., "[Slowed + Reverb]").

### 5C — Filter stacking safety rules

In `_buildMergedAfString()`:
- If a vibe mode has its own reverb (`slowedReverb`, `phonk`) AND the user also has
  the main reverb preset active (`_currentReverbAf` non-empty): use only the vibe's
  reverb (the stronger one), skip `_currentReverbAf`. Combining two `aecho` filters
  causes double-echo chaos.
- If `club` mode is active AND `_labStereoWide` is on: `extrastereo` is already in
  the vibe chain — skip the lab's `extrastereo` segment to avoid double widening.
- Document these rules in `_buildMergedAfString()` comments.

### 5D — Voice command support

**File:** `raddflix_flutter/lib/screens/player/player_screen.dart` (voice command handler)

Add vibe mode commands to the existing voice command parser:
- `"slowed"` → `PlaybackVibeMode.slowed`
- `"slowed reverb"` or `"reverb"` → `PlaybackVibeMode.slowedReverb`
- `"nightcore"` or `"night core"` → `PlaybackVibeMode.nightcore`
- `"lofi"` or `"lo-fi"` → `PlaybackVibeMode.lofi`
- `"normal"` or `"original"` or `"no vibe"` → `PlaybackVibeMode.none`

---

## Files Touched Summary

| File | Phases |
|---|---|
| `widgets/player/subtitle_overlay.dart` | 0A, 0B |
| `screens/player/_ps_subtitle_mixin.dart` | 0A, 0B, 1D |
| `screens/player/_ps_ui_mixin.dart` | 0B, 4C, 5B |
| `screens/player/_ps_playback_mixin.dart` | 0B, 1E |
| `screens/player/_ps_audiolab_mixin.dart` | 1A, 1C, 5C |
| `core/player/player_prefs.dart` | 1B |
| `screens/player/_ps_panels_audio.dart` | 4A, 4B |
| `screens/player/audio_mode_backdrop.dart` | 4D |
| `screens/settings_screen.dart` | 5A |
| `screens/player/player_screen.dart` | 5D |
| `android/.../MediaStorePlugin.kt` | 0C |
| `services/media_kit_thumbnail_extractor.dart` | 0C |
| `services/thumb_service.dart` | 0C |
| `screens/local_folder_screen.dart` | 0C |
| `screens/local_media_screen.dart` | 0C |

## Build order

```
Phase 0A (SUB-GRAY-SCREEN)   →  independent, ship immediately
Phase 0B (PLAYER-PERF)       →  after 0A (shares subtitle files)
Phase 0C (THUMB-PERF)        →  independent of 0A/0B, can run in parallel
Phase 1 (Foundation)         →  after 0A/0B complete
Phase 2 (Core 4 modes)       →  after Phase 1
Phase 3 (Extended modes)     →  after Phase 2
Phase 4 (UI)                 →  after Phase 2 (needs modes to exist)
Phase 5 (Polish)             →  after Phase 4
```
