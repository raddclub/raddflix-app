# RaddFlix Player — Full Feature Specification
> Last Updated: 2026-06-01 | Source: player_screen.dart (4521 lines)
> This document is the single truth for the video player. Read before touching any player file.

---

## Architecture Overview

The entire player lives in one state machine: `_PlayerScreenState` inside `player_screen.dart`.
Modes, gestures, UI layers, and all panels are managed here. No separate route/navigation.

```
player_screen.dart (4521 lines)
  ├── _PlayerScreenState        ← master state: mode, position, prefs, panels
  ├── _ControlsOverlay          ← all visible controls (top bar, seek bar, center buttons, right strip)
  ├── _MxMoreSheet              ← 16-item bottom sheet (long-tap = settings for that feature)
  ├── _MxAudioPanel             ← audio track selector + sync
  ├── _MxSubPanel               ← subtitle track selector + sync
  ├── _VideoDisplaySheet        ← 12 shortcut tiles (row×2)
  ├── _MxSeekBtn                ← vertical seek button (up=back, down=forward)
  ├── _MxSideBtn                ← right-strip icon button
  ├── _CircularDotsLoader       ← loading animation (ring of dots)
  ├── _DragIndicator            ← vol/brightness gesture HUD (full)
  ├── _ImmersiveDragNumber      ← vol/brightness gesture HUD (immersive — number only)
  └── helper widgets …

widgets/player/
  ├── quick_settings_panel.dart  ← 5-tab settings (Style/Screen/Controls/Navigation/Text)
  ├── eq_panel.dart              ← Audio Effect + Equalizer tabs
  ├── immersive_overlay.dart     ← Immersive mode: corner exit + time HUD
  ├── cinematic_overlay.dart     ← STUB (cinematic uses Opacity wrapper, not overlay)
  ├── cinematic_settings_sheet.dart ← Cinematic/Immersive settings + opacity slider
  ├── sync_panel.dart            ← Audio/subtitle delay adjustment
  ├── scene_bookmarks_panel.dart ← emoji bookmark timeline
  └── ab_loop_panel.dart         ← A-B repeat control
```

---

## Mode System (CRITICAL — read carefully)

Three mutually exclusive modes. All logic (gestures, long-press speed, seek) works in ALL modes.
The modes only control what is VISIBLE.

### Normal Mode (default)
- `_cinematicMode = false`, `_immersiveMode = false`
- Single tap → show/hide controls (with auto-hide timer)
- Long press → 2× speed (fires `_longPressFast`, plays at `_prefs.longPressSpeed`)
- All gesture feedback shown (drag indicator, seek label, zoom indicator)
- Auto-hide timer from `_prefs.autoHideSeconds`

### Cinematic Mode (`_cinematicMode = true`)
- Controls auto-hide/show EXACTLY like Normal mode
- Entire `_ControlsOverlay` wrapped in `Opacity(opacity: _cinematicOpacity)`
- `_cinematicOpacity` default = 0.5, range 0.15–1.0, user-adjustable via long-press Night Mode in More Sheet → CinematicSettingsSheet
- Live opacity slider: changes update `_cinematicOpacity` in real time via `onOpacityChanged` callback
- Subtitles SHOW (previously hidden — fixed 2026-06-01)
- Long press → 2× speed (unchanged)
- All gestures → full feedback at cinematic opacity level

### Immersive Mode (`_immersiveMode = true`)
- `_showControls` is forced false and blocked from becoming true
- `_scheduleHide()` returns immediately if `_immersiveMode`
- `_toggleControls()` returns immediately if `_immersiveMode`
- `_handleCenterTap()` → play/pause only, returns before `_toggleControls`
- Long press → 2× speed (unchanged — root GestureDetector fires regardless of mode)
- Gestures work silently:
  - Vol/brightness → `_ImmersiveDragNumber` (percentage only, no icon/bar, fades in 680ms)
  - Seek → values change, no label shown
  - Pinch → zoom works, zoom indicator not shown
- Always visible: bottom-left elapsed time + bottom-right remaining time (10px, 45% opacity)
- Exit: tap top-right corner → exit button appears for 5s, auto-hides → tap exit → Normal mode
- `ImmersiveOverlay` widget handles the corner exit zone and time HUD

---

## Gesture Map

| Gesture | Normal | Cinematic | Immersive |
|---------|--------|-----------|-----------|
| Single tap | toggle controls | toggle controls (dimmed) | play/pause only |
| Double tap left | -15s seek | -15s seek | -15s seek |
| Double tap right | +15s seek | +15s seek | +15s seek |
| Long press | 2× speed | 2× speed | 2× speed |
| Swipe left half vertical | brightness | brightness | brightness (silent) |
| Swipe right half vertical | volume | volume | volume (silent) |
| Swipe horizontal | seek scrub | seek scrub | seek scrub (silent) |
| Pinch | zoom | zoom | zoom |
| Triple tap | rage skip | rage skip | N/A |

---

## State Variables (key ones)

```dart
// Modes
bool _cinematicMode = false;
bool _immersiveMode = false;
double _cinematicOpacity = 0.5;  // cinematic controls dimness

// Controls visibility
bool _showControls = true;
Timer? _hideTimer;

// Gesture
String? _dragIntent;           // 'brightness' | 'volume' | 'seek' | 'pinch'
bool _draggingBrightness = false;
bool _draggingVolume = false;
bool _draggingSeek = false;
bool _longPressFast = false;

// Panels (all bottom sheets)
bool _showQuickSettings = false;
bool _showMorePanel = false;
bool _showEqPanel = false;
bool _showAudioSyncPanel = false;
bool _showSubSyncPanel = false;
bool _showVideoDisplay = false;
bool _showAbPanel = false;
bool _showBookmarksPanel = false;
bool _showVideoEnhance = false;
bool _showSpeedPicker = false;
bool _showSubtitleMenu = false;
bool _showAudioMenu = false;
bool _showSleepMenu = false;
```

---

## Quick Settings Tabs (quick_settings_panel.dart)

| Tab | Key settings |
|-----|-------------|
| Style | Preset, Frame, Controls size (S/M/L), Progress bar style (Line/Material), place below toggle |
| Screen | Orientation, Brightness slider, Auto-hide, Corner offset, Elapsed time, Battery/clock display |
| Controls | Touch action (Pause/Lock), Gesture list (individual rows with toggle) |
| Navigation | Seek Speed, Move Interval, Forward/Backward buttons toggle, Previous/Next toggle |
| Text | Font, Size, Scale, Color, Bold, Background Color, Border, Shadow, Improve stroke, Fade out |

---

## More Sheet Items (16 items in 4×4 grid)

| # | Label | Icon | Active state |
|---|-------|------|-------------|
| 0 | Playing Queue | `queue_music_rounded` | queue not empty |
| 1 | Cut | `content_cut_rounded` | — |
| 2 | Share | `share_rounded` | — |
| 3 | Video Display Shortcuts | `display_settings_rounded` | — |
| 4 | Aspect Ratio | `aspect_ratio_rounded` | not 'Fit' |
| 5 | Favourite | `favorite_rounded` | favourited |
| 6 | Network Stream | `cast_rounded` | connected |
| 7 | PiP | `picture_in_picture_rounded` | in PiP |
| 8 | Add To Playlist | `playlist_add_rounded` | — |
| 9 | **Display Settings** (restored) | `tune_rounded` | — |
| 10 | Equalizer | `equalizer_rounded` | eq enabled |
| 11 | Night Mode (Cinematic) | `dark_mode_rounded` | `_cinematicMode` |
| 12 | Information | `info_outline_rounded` | — |
| 13 | Bookmark | `bookmark_rounded` | has bookmarks |
| 14 | Sleep Timer | `bedtime_rounded` | sleep active |
| 15 | A-B Repeat | `repeat_one_rounded` | AB active |

Long-press Night Mode → `CinematicSettingsSheet` (opacity slider + tap settings)
Long-press Immersive Mode → `ImmersiveModeSettingsSheet` (tap/icon/hide settings)

---

## Known Differences vs Screenshots (from deep analysis session)

These are items confirmed different from the MX Player screenshot reference. Fix in future sessions:

1. **More Sheet item 9**: Currently still shows "Immersive Mode" — should be "Display Settings" (revert the replacement done in previous session)
2. **Audio track chips**: Screenshots show radio-button circles (filled/empty), our code uses rectangular pill chips
3. **EQ Panel Audio Effect**: "Original" should be a full-width banner card, others in 2-column grid
4. **Loading animation**: All dots equal brightness, ~50-60 dots (our code: 40, fading tail), center icon different
5. **Video Display Shortcuts selected tile**: Screenshot: dark square + blue `<` chevron inside; our code: solid blue fill
6. **Quick Settings Controls tab**: Screenshots show gesture list as individual rows; our code uses chip Wrap
7. **Audio/Subtitle panel dismiss**: Screenshot shows back `<` at bottom-left; our code has X in header
8. **Subtitle panel**: "Online subtitles" is vertical text on right edge; our code has it as a small badge
9. **Right-side strip**: Screenshots show Screenshot/Rotate/HW+/More; our code shows Sub/Audio/Rotate/More
10. **Center play button**: Screenshots show smaller/less-glow button than our 68px red circle
