# Portrait Player Layout — Fix Plan

> **Task ID:** Portrait-Player-V1  
> **Priority:** High  
> **Files:** `raddflix_flutter/lib/screens/player_screen.dart`  
> **Approach:** Idea A (YouTube/Netflix split layout) + Idea C (bottom-sheet panel in portrait)

---

## Problem Summary

The video player was designed for landscape. In portrait mode:

| # | Problem | Root Cause |
|---|---|---|
| P1 | Video sits in a tiny letterboxed box (~35% of screen height) with ~65% pure black dead space | No portrait-aware layout — `SizedBox.expand` fills screen, video shows with massive black bars |
| P2 | Top bar overflows/squishes — title, codec badges, and 5+ icon buttons all fight for ~360 px | Single `Row` with no portrait width guard |
| P3 | Right-side settings panel is ~200 dp wide in portrait — too narrow to read sliders/chips | `widthFactor = 0.55` of portrait width, no orientation branch |
| P4 | Controls float over black void — seek bar and transport buttons feel lost | No dedicated content area below the video in portrait |
| P5 | Hardcoded pixel offsets (`bottom: 88`, `height * 0.22`) tuned for landscape proportions | MediaQuery values not portrait-aware |

---

## Solution Design

### Zone A — Portrait Video + Info Split Layout

Detect portrait using `MediaQuery.of(context).orientation == Orientation.portrait`.

**Portrait layout (new):**
```
┌──────────────────────────────┐
│                              │  ← Status bar (SafeArea top)
│    VIDEO  (16:9 aspect)      │  ← ~38% of screen height
│                              │
├──────────────────────────────┤
│  ← Back    Title      ⋯ More │  ← Compact top bar row
├──────────────────────────────┤
│  ████████████░░░░  00:34/1:20│  ← Full-width seek bar
│  ⏮  ⏪  ▶  ⏩  ⏭            │  ← Transport row (bigger tap targets)
│  🔒  ⛶  ⚙  ↕               │  ← Utility buttons row
├──────────────────────────────┤
│  Next episode card           │  ← (if series: next ep thumb + title)
│  ...                         │
└──────────────────────────────┘
         ↑ SafeArea bottom
```

**Landscape layout:** unchanged — existing full-screen overlay Stack stays as-is.

---

### Zone B — Portrait-Aware Top Bar

When in portrait:
- Keep: back button, title (ellipsis), single `⋯` overflow icon
- Move to overflow menu: zoom badge, sync badge, codec badge, audio/sub quick-access
- Result: top bar is always a clean 3-element Row in portrait, no overflow

---

### Zone C — Bottom Sheet Panel in Portrait

Replace `_openRightPanel` logic:

```dart
void _openRightPanel(Widget content, {double widthFactor = 0.55}) {
  if (MediaQuery.of(context).orientation == Orientation.portrait) {
    // Portrait → bottom sheet (full width, 75% height, draggable)
    showModalBottomSheet(...)
  } else {
    // Landscape → existing right-side slide panel (unchanged)
    showGeneralDialog(...)
  }
}
```

Bottom sheet: `DraggableScrollableSheet`, `initialChildSize: 0.75`, `minChildSize: 0.4`, `maxChildSize: 0.95`. Full screen width. Rounded top corners.

---

## Implementation Steps

### Step 1 — Add orientation helper (5 min)
Add a single getter at the top of `_PlayerScreenState`:
```dart
bool get _isPortrait =>
    MediaQuery.of(context).orientation == Orientation.portrait;
```
Use this everywhere instead of recalculating.

---

### Step 2 — Portrait video surface with aspect ratio box (20 min)

In `_buildVideoSurface()`, wrap the video in a portrait-aware container:

```dart
Widget _buildVideoSurface() {
  if (_isPortrait) {
    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Video(controller: _videoController, fit: BoxFit.contain),
      ),
    );
  }
  // landscape: existing SizedBox.expand unchanged
  return SizedBox.expand(child: Video(...));
}
```

---

### Step 3 — Portrait controls area below video (30 min)

In `_buildControlsOverlay`, when `_isPortrait`:
- Do NOT use `Positioned.fill` + floating Stack
- Use a `Column`:
  - `AspectRatio(16/9)` placeholder at top (same height as the video)
  - `Expanded` area below: compact top bar, seek bar, transport, utility buttons

```dart
Widget _buildPortraitControls(BoxConstraints constraints, Duration pos) {
  return Column(
    children: [
      // Transparent spacer matching video height
      AspectRatio(aspectRatio: 16 / 9, child: const SizedBox.shrink()),
      // Controls panel below
      Expanded(
        child: Container(
          color: const Color(0xFF0A0A0A),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildPortraitTopBar(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildHorizontalSeekBar(constraints, pos),
                ),
                const SizedBox(height: 4),
                _buildTransportRow(),
                const SizedBox(height: 4),
                _buildPortraitUtilityRow(),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
```

---

### Step 4 — Portrait compact top bar (15 min)

New `_buildPortraitTopBar()`:
```dart
Widget _buildPortraitTopBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
    child: Row(
      children: [
        _RaddIconBtn(icon: Icons.arrow_back_ios_new_rounded, size: 20, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 6),
        Expanded(
          child: Text(_currentTitle,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        // Overflow menu: zoom, audio, subs, settings
        _RaddIconBtn(icon: Icons.more_vert_rounded, size: 22, onTap: _openSettingsPanel),
      ],
    ),
  );
}
```

---

### Step 5 — Portrait utility row (10 min)

New `_buildPortraitUtilityRow()` — sits below transport buttons:
```dart
Widget _buildPortraitUtilityRow() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _RaddIconBtn(icon: Icons.lock_outline_rounded, size: 20, onTap: ...),
      const SizedBox(width: 16),
      _RaddIconBtn(icon: Icons.subtitles_outlined, size: 20, onTap: _openSubtitlePanel),
      const SizedBox(width: 16),
      _RaddIconBtn(icon: Icons.audiotrack_rounded, size: 20, onTap: _openAudioPanel),
      const SizedBox(width: 16),
      _RaddIconBtn(icon: Icons.settings_rounded, size: 20, onTap: _openSettingsPanel),
      const SizedBox(width: 16),
      _RaddIconBtn(icon: _orientationIcon, size: 20, onTap: _cycleOrientation),
    ],
  );
}
```

---

### Step 6 — Bottom sheet panel for portrait (20 min)

Update `_openRightPanel`:
```dart
void _openRightPanel(Widget content, {double widthFactor = 0.55}) {
  setState(() => _panelOpen = true);
  if (MediaQuery.of(context).orientation == Orientation.portrait) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.40,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(children: [
            // Drag handle
            Padding(padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white30,
                  borderRadius: BorderRadius.circular(2)))),
            Expanded(child: SingleChildScrollView(
              controller: scrollCtrl, child: content)),
          ]),
        ),
      ),
    ).then((_) { if (mounted) setState(() => _panelOpen = false); });
  } else {
    // Existing landscape right-side panel — UNCHANGED
    showGeneralDialog( ... );
  }
}
```

---

### Step 7 — Fix hardcoded portrait offsets (10 min)

Replace:
```dart
// BEFORE
bottom: 88,                           // seek preview label
top: MediaQuery.of(context).size.height * 0.22,  // one-handed strip
```
With:
```dart
// AFTER
bottom: _isPortrait ? 140 : 88,
top: _isPortrait
    ? MediaQuery.of(context).size.height * 0.12
    : MediaQuery.of(context).size.height * 0.22,
```

---

### Step 8 — Gesture layer portrait awareness (10 min)

The gesture detector (`_buildGestureLayer`) uses full-screen swipe zones. In portrait, the bottom half of the screen is the controls panel — swipes there should not trigger seek/brightness/volume. Gate gesture handling:
```dart
// Skip gesture handling when touch is in the lower controls panel in portrait
if (_isPortrait && localPosition.dy > constraints.maxHeight * 0.40) return;
```

---

## Testing Checklist

Before marking DONE, verify all of the following on a real device or emulator:

- [ ] Portrait: video renders at correct 16:9 aspect ratio, no black side bars
- [ ] Portrait: controls panel is visible below video — no overlap
- [ ] Portrait: top bar shows back + title + overflow only — no overflow/clip
- [ ] Portrait: seek bar is full width with readable labels
- [ ] Portrait: transport buttons have comfortable tap targets (≥48 dp)
- [ ] Portrait: settings/subtitle panel opens as bottom sheet (not side drawer)
- [ ] Portrait: bottom sheet is draggable and full-width
- [ ] Portrait: tapping video area (top 38%) still shows/hides the controls
- [ ] Portrait: double-tap seek still works in video area
- [ ] Portrait → Landscape rotation: switches to full-screen overlay layout instantly
- [ ] Landscape → Portrait rotation: switches to split layout instantly
- [ ] Landscape: ZERO changes to existing layout — all panels, controls identical
- [ ] One-handed mode: only active in landscape (disable toggle in portrait)
- [ ] Lock overlay: still works correctly in portrait
- [ ] AI Dub progress overlay: still visible in portrait (pinned to video area top)

---

## Files to Edit

| File | Changes |
|---|---|
| `raddflix_flutter/lib/screens/player_screen.dart` | All 8 steps above |

No other files need changes. All modifications are isolated to `player_screen.dart`.

---

## Acceptance Criteria

1. A 16:9 movie playing in portrait shows the video filling the full width of the screen in a correct aspect-ratio box — not a tiny letterboxed window with massive black bars.
2. All player controls (seek, play/pause, prev/next, lock, subtitle, audio, settings) are reachable with one thumb in portrait without opening a menu.
3. The subtitle/audio/settings panel in portrait opens from the bottom as a draggable sheet — not a narrow 200 dp side drawer.
4. Rotating from portrait → landscape and back works without re-navigating or losing playback position.
5. Landscape mode is completely unchanged.
