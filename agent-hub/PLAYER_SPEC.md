# RaddFlix Player — Full Feature Specification
> Last Updated: 2026-06-07 | Source: player_screen.dart (6265 lines, commit 2ac9e8dc)
> This document is the single truth for the video player. Read before touching any player file.

---

## Architecture Overview

The entire player lives in one state machine: `_PlayerScreenState` inside `player_screen.dart`.
Modes, gestures, UI layers, and all panels are managed here. No separate route/navigation.

```
player_screen.dart (6265 lines)
  ├── _PlayerScreenState        ← master state: mode, position, prefs, panels
  ├── _ControlsOverlay          ← all visible controls (top bar, seek bar, center buttons, right strip)
  │     └── _QuickShortcutBar  ← icon-only shortcut row above seek bar (8 configurable slots)
  ├── _MxMoreSheet              ← 16-item bottom sheet (long-tap = settings for that feature)
  ├── _MxAudioPanel             ← audio track selector + sync
  ├── _MxSubPanel               ← subtitle track selector + sync
  ├── _VideoDisplaySheet        ← 12 shortcut tiles (2 rows × 6)
  ├── _SpeedPanel               ← playback speed picker (right-edge strip)
  ├── _SleepPanel               ← sleep timer options panel
  ├── _MxSeekBtn                ← seek ±15s button with seconds label
  ├── _MxSideBtn                ← right-strip icon button (label + icon)
  ├── _MxBadge                  ← top bar badge (A/V sync offset, zoom level)
  ├── _CenterAuxBtn             ← auxiliary center buttons (Prev ep, Skip Intro)
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

## CRITICAL: Two separate night-mode callbacks in _ControlsOverlay

`_ControlsOverlay` has two distinct callbacks that must NEVER be swapped:

| Callback | Toggles | Used by |
|----------|---------|---------|
| `onToggleCinematic` | `_cinematicMode` — dims the entire controls overlay | More Sheet "Night Mode" tile, cinematic settings |
| `onToggleNightMode` | `_prefs.nightMode` — applies a blue-light filter via `_applyVideoFilters()` | Quick Bar "nightmode" slot, Video Display Sheet |

The More Sheet item 11 ("Night Mode") toggles **cinematic mode**, not the colour filter.
The Quick Bar "Night" slot and Video Display Sheet "Night Mode" toggle the **actual night mode filter**.
Do NOT wire `onToggleNightMode` to `_toggleCinematic()` or vice versa.

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
- `_cinematicOpacity` default = 0.5, range 0.15–1.0, user-adjustable via CinematicSettingsSheet
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
- Exit: tap top-right corner → exit button appears for 5s → tap exit → Normal mode
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
| Triple tap center | rage skip | rage skip | N/A |

---

## AbLoopController API (`core/player/ab_loop_controller.dart`)

```dart
// Fields
Duration? pointA, pointB;

// Methods
void setA(Duration d);                      // set loop start
void setB(Duration d);                      // set loop end
void clear();                               // clear both points

// Getters
bool get isActive;                          // true when both A and B are set

// Loop enforcement (call on every position event)
Duration? maybeSeekBack(Duration current);  // returns pointA if current >= pointB, else null
```

**Rule:** Any UI that sets A-B points MUST call `_abLoop.setA()` / `_abLoop.setB()` in addition
to updating `_abLoopStart` / `_abLoopEnd` state vars. Updating only the state vars breaks
`maybeSeekBack()` enforcement and seek bar markers. (Was BUG-P-NEW-05.)

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

// Panels (all bottom sheets / overlays)
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
bool _showJumpPanel = false;
bool _showTransparentSlider = false;
bool _showBingeGuard = false;
```

---

## Quick Bar (`_QuickShortcutBar`)

Thin icon row (46×40px tiles) rendered above the seek slider when `showQuickBar = true`.
Configurable via `quickBarItems` pref (comma-separated IDs).

| Slot ID | Label | Action |
|---------|-------|--------|
| `pip` | PiP | `onPiP` |
| `bgplay` | BG Play | `onBgPlay(!bgPlayEnabled)` — toggleable |
| `fit` | Resize | `onFit` (cycle aspect ratio) |
| `screenshot` | Shot | `onScreenshot` |
| `speed` | Speed | `onSpeed` (open speed picker) |
| `subtitle` | Sub | `onSubtitle` (open subtitle panel) |
| `lock` | Lock | `onLock` (lock controls) |
| `nightmode` | Night | `onNightMode` → **must be `onToggleNightMode`** (night mode filter, NOT cinematic) |

Default: `'pip,bgplay,fit,screenshot,speed'`

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

| # | Label | Icon | Active state | Notes |
|---|-------|------|-------------|-------|
| 0 | Playing Queue | `queue_music_rounded` | queue not empty | |
| 1 | Cut | `content_cut_rounded` | — | Opens ClipTrimmer |
| 2 | Share | `share_rounded` | — | |
| 3 | Video Display Shortcuts | `display_settings_rounded` | — | Opens _VideoDisplaySheet |
| 4 | Aspect Ratio | `aspect_ratio_rounded` | not 'Fit' | |
| 5 | Favourite | `favorite_rounded` | favourited | |
| 6 | Network Stream | `cast_rounded` | connected | |
| 7 | PiP | `picture_in_picture_rounded` | in PiP | |
| 8 | Add To Playlist | `playlist_add_rounded` | — | |
| 9 | Display Settings | `tune_rounded` | — | |
| 10 | Equalizer | `equalizer_rounded` | eq enabled | |
| 11 | Night Mode | `dark_mode_rounded` | `_cinematicMode` | Toggles CINEMATIC mode (not filter) |
| 12 | Information | `info_outline_rounded` | — | |
| 13 | Bookmark | `bookmark_rounded` | has bookmarks | |
| 14 | Sleep Timer | `bedtime_rounded` | sleep active | |
| 15 | A-B Repeat | `repeat_one_rounded` | AB active | |

**Note:** More Sheet item 11 "Night Mode" toggles `_cinematicMode` (dims the overlay).
The Quick Bar "Night" slot and Video Display Sheet "Night Mode" toggle the colour filter (`_prefs.nightMode`).
These are two different features with similar labels — keep them separate.

---

## PlayerPrefs fields (player_prefs.dart)

```dart
// Playback
final double playbackSpeed;
final String speedPresets;           // comma-sep: '0.25,0.5,...,3.0'
final double volumeBoostMultiplier;  // 1.0–3.0
final int    audioTimingOffsetMs;
final int    subtitleSyncOffsetMs;

// Modes & features
final bool   cinematicMode;          // persisted cinematic on/off
final double cinematicOpacity;       // 0.15–1.0
final bool   nightMode;              // blue-light reduction filter
final bool   immersiveMode;
final bool   rageSkipEnabled;
final int    rageSkipSeconds;
final bool   abLoopEnabled;
final bool   backgroundPlayEnabled;
final bool   bingeGuardEnabled;
final int    bingeGuardThresholdMinutes;
final bool   ambilightEnabled;

// Center button customization
final String centerBtnPosition;      // 'center' | 'bottom' | 'hidden'
final double centerBtnScale;
final double centerBtnVerticalOffset;
final bool   centerBtnIconOnly;
final double centerBtnBgOpacity;
final bool   showCenterPrev;
final bool   showCenterSkip;
final bool   showCenterNext;

// Quick bar
final bool   showQuickBar;
final String quickBarItems;          // comma-sep slot IDs

// UI
final Color  accentColor;
final String buttonShape;            // 'circle'|'squircle'|'rounded'|'sharp'|'pill'
final String seekBarStyle;           // 'classic'|'wave'|'film'|'minimal'
final String iconPack;               // 'mx'|'ios'|'fluent'|'material3'|'cute'|'minimal'
final String rotationMode;           // 'sensor_landscape'|'auto'|'lock_left'|'lock_right'|'lock_portrait'|'lock_current'
```

---

## Known Open Items (not bugs — UI polish)

1. **Audio track chips**: Screenshots show radio-button circles; code uses rectangular pill chips
2. **EQ Panel Audio Effect**: "Original" should be a full-width banner card; others in 2-column grid
3. **Loading animation**: Our code has 40 dots with fading tail; reference has ~50-60 equal-brightness dots
4. **Audio/Subtitle panel dismiss**: Reference shows back `<` at bottom-left; code has X in header
5. **Right-side strip**: Reference shows Screenshot/Rotate/HW+/More; code shows Sub/Audio/Rotate/More
6. **Quick bar overflow on small screens**: `_QuickShortcutBar` Row not wrapped in `SingleChildScrollView`
