# RaddFlix Player — Full Feature Specification
> Last Updated: 2026-06-17 | **⚠️ Architecture stale — needs re-audit**
> Phase J split the monolithic `player_screen.dart` into 8 part/mixin files under
> `raddflix_flutter/lib/screens/player/`. The parent file is now ~1734 lines; the full
> player lives across `player_screen.dart` + `_ps_playback_mixin.dart`, `_ps_ui_mixin.dart`,
> `_ps_subtitle_mixin.dart`, `_ps_audiolab_mixin.dart`, `_ps_panels_audio.dart`,
> `_ps_panels_sidebar.dart`, `_ps_panels_subtitle.dart`. Feature list below remains accurate;
> file/line references and the architecture tree are pre-split and should not be trusted.

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

---

## Player UX Features Added 2026-06-17

### Floating Draggable Ball
- Visible when controls are hidden and `!_locked && !_immersiveMode`
- White 40×40 circle with `Icons.play_circle_outline_rounded` icon
- **Tap** → sets `_showControls = true`, calls `_scheduleHide()`
- **Drag** (`onPanUpdate`) → updates `_ballOffset` clamped to screen bounds
- Positioned via `Positioned(left: _ballOffset.dx, top: _ballOffset.dy)`

### Sidebar 3-State Cycle
- Triggered by chevron button at top of right rail in `_ControlsOverlay`
- State 0 (full): rail width 58px, buttons show icon + label (46×44)
- State 1 (icons-only): rail width 40px, buttons show icon only (36×36, 19px icon)
- State 2 (hidden): rail is removed from tree (`sidebarMode < 2` condition)
- Chevron icon: `chevron_right_rounded` (state 0) or `chevron_left_rounded` (state 1)
- Persisted: `_prefs.copyWith(sidebarMode: _nm).save()` on every toggle

### PlayerPrefs.sidebarMode
- **Type**: `int` (0=full, 1=icons-only, 2=hidden)
- **Default**: 0
- **SharedPrefs key**: `sidebar_mode`
- **copyWith**: `int? sidebarMode` param added
- **load**: `s.getInt('${_p}sidebar_mode') ?? 0`
- **save**: `s.setInt('${_p}sidebar_mode', sidebarMode)`

### Clock Overlay
- Positioned top-right (top: 10, right: 16), wrapped in `IgnorePointer`
- Visible when `!_showControls && !_locked`
- Style: white70, 12sp, medium weight, 4px blur shadow
- Helper `_fmtTime()`: returns `"H:MM AM/PM"` format
- `_clockTimer` (Timer.periodic 30s) calls `setState(() => _clockStr = _fmtTime())`
- Cancelled in `dispose()`

### Subtitle + Audio Panels (right-side overlays)
- **Before**: `Positioned(bottom:0, left:0, right:0)` (bottom sheet style)
- **After**: `Positioned(top:0, right:0, bottom:0, width:320)` (right-side panel)
- Scrim: `Colors.black26` (was `Colors.black54`) — lighter, less intrusive
- Both panels (`_MxSubPanel`, `_MxAudioPanel`) unchanged internally

### Speed Picker (_SpeedTrackPanel)
- Replaced `_SpeedPanel` (vertical right-side list) with `_SpeedTrackPanel` (horizontal top bar)
- Layout: `Positioned(top:0, left:0, right:0)` — spans full width at top
- Each speed in an `Expanded` column with dot + label
- Active: 13px `#4DB6FF` circle + 11sp bold blue label
- Inactive: 7px white38 circle + 9sp white54 label
- Footer: "${speed}× Speed Playing" with play arrow icon
- Animation: `fadeIn(150ms)`

### _MxSideBtn iconsOnly Mode
- New field: `final bool iconsOnly;` (default `false`)
- When `iconsOnly == true`:
  - Container: 36×36 (was 46×44)
  - Icon: 19px (was 17px)
  - Label `Text` and gap `SizedBox` are hidden (`if (!iconsOnly)`)
- All sidebar buttons use `iconsOnly: sidebarMode == 1`

### Default Rotation Change
- `PlayerPrefs.rotationMode` default: `'sensor_landscape'` → `'auto'`
- Affects new installs and users who haven't changed rotation setting
