# Player Screen Architecture Guide
> Updated: 2026-06-22 | **⚠️ Stale — player was split in Phase J.**
> `player_screen.dart` is now ~1734 lines. Full player lives across 8 part files in
> `raddflix_flutter/lib/screens/player/` — see that directory for current structure.

---

## Overlay Stack (build order, bottom to top)

```
1.  Video surface (NativePlayer SurfaceView — MPV subtitle renderer DISABLED via SubtitleViewConfiguration(visible:false))
1b. Flutter SubtitleOverlay (IgnorePointer when dictEnabled=false; Consumer(playerPrefsProvider) for live style updates)
2.  Lock overlay (when _isLocked)
3.  AI Dub progress overlay (when _dubGenerating)
4.  Gesture layer (GestureDetector — tap/drag/scale/double-tap/long-press)
5.  Controls overlay (AnimatedOpacity — auto-hides) ← _buildControlsOverlay()
6.  Sidebar strip (right edge, _sidebarExpanded, hidden when _panelOpen=true)
7a. Brightness indicator pill (LEFT, amber, _showBrightnessIndicator)
7b. Volume indicator pill (LEFT, white/orange/red, _showVolumeIndicator)
8.  Long-press 2× badge
9a. Pinch-zoom indicator pill
9b. Reset zoom button
10. Seek preview label (during drag)
```

**SubtitleOverlay is present in BOTH landscape (player_screen.dart) and portrait (_ps_ui_mixin.dart `_buildPortraitLayout`) stacks.**
The overlay is hidden during audio-only mode (`if (!_isAudioOnly)` gate).

---

## Controls Overlay Sub-Stack (_buildControlsOverlay)
```
Top gradient (0xBB000000 → transparent, height 80)
Bottom gradient (transparent → 0xBB000000, height 100)
├── TOP BAR (_buildTopBar) — Positioned top:0
│   Back | Title | EpBadge | ZoomBadge | SubSyncBadge | AudioSyncBadge |
│   Replay | Clock | SleepBadge | RotationBadge | Info
│   (CC/Audio/PiP/Rotate/Lock removed — all in sidebar now)
│
├── CENTER — EMPTY (SizedBox.shrink() — cinematic, zero buttons)
│
└── BOTTOM AREA (_buildBottomArea) — Positioned bottom:0
    ├── Seek bar row (_buildHorizontalSeekBar)
    ├── Transport row (_buildTransportRow)  ← NEW in Phase 17
    │   ⏪skip · ⏮prev · ▶/⏸play/pause · ⏭next · skip⏩
    └── Icon row (_buildBottomIconRow)
        Vivid | Audio | Lab | Episodes | Speed | More
```

---

## Panel System
**Function:** `_openRightPanel(Widget content, {double widthFactor = 0.55})`  
**Mechanism:** `showGeneralDialog` with slide-from-right animation  
**Width:** 55% of screen (was 45%)  
**Background:** `Colors.black.withOpacity(0.60)`  
**Border:** left `Colors.white12` 0.8px  
**Sidebar hide:** Sets `_panelOpen=true` before dialog, resets via `.then()` on dialog future  

### Panels (all via _openRightPanel):
`_SubtitlePanel` | `_AudioTrackPanel` | `_VideoZoomPanel` | `_AudioEffectPanel` |  
`_QuickShortcutsPanel` | Speed | Loop | More | Screenshot | Sleep | A-B |  
`_SidebarCustomizerPanel` | `_SettingsPanel` | Episodes

---

## Sidebar Architecture
**Class:** rendered in `_buildSidebar(BoxConstraints)`  
**Position:** `Positioned(right:0, top:0, bottom:0)`  
**Visibility:** `_showControls && !_panelOpen`  
**Toggle state:** `_sidebarExpanded` (bool, persisted as `pref_sidebar_exp`)  
**Order:** `_sidebarOrder` (List<String>, persisted as `pref_sidebar_order`)  

**19 shortcut IDs:**
`cc, audio, eq, speed, loop, rotate, lock, pip, screenshot, sleep, ab, episodes, settings, vivid, mute, zoom, info, replay, onehanded`

**Sidebar hide logic:**
```dart
// Panel opens:
setState(() => _panelOpen = true);
showGeneralDialog(...).then((_) {
  if (mounted) setState(() => _panelOpen = false);
});

// Sidebar AnimatedOpacity:
opacity: _showControls && !_panelOpen ? 1.0 : 0.0

// Sidebar IgnorePointer:
ignoring: !_showControls || _panelOpen
// NOTE: _sidebarExpanded is checked inside _buildSidebar itself
// so manual close is always respected
```

---

## Gesture System
| Gesture | Handler | Action |
|---------|---------|--------|
| Tap | `onTap` | Toggle controls |
| Double-tap left | `onDoubleTapDown` | Seek back `_skipInterval`s |
| Double-tap right | `onDoubleTapDown` | Seek forward `_skipInterval`s |
| Long press | `onLongPressStart/End` | 2× speed (if enabled) |
| Drag horizontal | `_onDragUpdate` intent='seek' | Seek through video |
| Drag vertical LEFT | `_onDragUpdate` intent='brightness' | Adjust brightness |
| Drag vertical RIGHT | `_onDragUpdate` intent='volume' | Adjust volume |
| Pinch | `_onScaleUpdate` (2 fingers) | Pinch-to-zoom |

**Drag intent** is decided in `_onDragStart` / first 12px threshold:
- `dx.abs() > dy.abs() && dx.abs() > 12` → 'seek' (if `_swipeSeekEnabled`)
- left half → 'brightness', right half → 'volume'

---

## Indicators
Both on **LEFT side** (`left: 20`), centered vertically.  
Never show simultaneously (brightness = left drag, volume = right drag).

**Brightness:** amber `0xFFFFD60A`, `sub-brightness`-style pill  
**Volume:** white / orange (>1.0) / red (>2.0), `left: 20`  

---

## Subtitle Rendering — Flutter Overlay (NOT MPV)

> ⚠️ **Updated 2026-07-29 (commit `defb61e`):** MPV's native subtitle renderer is
> **disabled**. All subtitle rendering is done by `SubtitleOverlay` (Flutter widget).
> See **Rule 51 in `RULES.md`** for the full architecture and why MPV native rendering
> can never be reliably customized.

### How the Flutter overlay works
| Property | Controlled by | Source |
|----------|--------------|--------|
| Current text | `_currentSubLine` (String?) | `player.stream.subtitle` stream → `_ps_playback_mixin.dart` |
| Font, size, bold, italic | `PlayerPrefs.subtitleFontIndex` etc. | `SubtitleOverlay.build()` |
| Text color, outline color | `PlayerPrefs.subtitleTextColorValue` etc. | Same |
| Background + opacity | `PlayerPrefs.subtitleBackgroundColorValue` etc. | Same |
| Position (top/center/bottom) | `PlayerPrefs.subtitlePosition` | `SubtitleOverlay._padding` |
| Vertical offset | `PlayerPrefs.subtitleVerticalOffset` | Multiplied ×60, added to padding |
| Word-tap dict lookup | `PlayerPrefs.dictEnabled` | `_onWordTap()`; IgnorePointer wrapper in stack |

### MPV timing properties — still active
`sub-delay` (sync) and `sub-speed` still affect *when* MPV emits subtitle text via
`player.stream.subtitle`. All other `sub-*` visual properties are no-ops (MPV renderer disabled).

### ⚠️ STALE — MPV sub-* Properties (kept for reference only, no longer rendered)
| Setting | MPV Property | Status |
|---------|-------------|--------|
| Font | `sub-font` | No-op (visual) |
| Size | `sub-font-size` | No-op (visual) |
| Bold | `sub-bold` | No-op (visual) |
| Color | `sub-color` | No-op (visual) |
| Background | `sub-back-color` | No-op (visual) |
| Opacity | `sub-opacity` | No-op (visual) |
| Align X/Y | `sub-align-x/y` | No-op (visual) |
| Margin Y | `sub-margin-y` | No-op (visual) |
| Shadow/Outline | `sub-shadow-offset/sub-outline-size` | No-op (visual) |
| **Speed** | **`sub-speed`** | **✅ Active — timing** |
| **Sync** | **`sub-delay`** | **✅ Active — timing** |

---

## DO NOT List
- ❌ `vf=` — crashes HW decoder
- ❌ Change `hwdec` while playing — only safe when paused + `_player.state.duration == Duration.zero`
- ❌ Local variable named `_np` — shadows the field
- ❌ `db.get_setting(k)` — use `db.setting(k)`
- ❌ `androidAttachSurfaceAfterVideoParameters: true` — black screen
- ❌ `sub-ass-fade-in-time` — fake property, use `sub-opacity`
- ❌ Panel width < 0.55 — user confirmed 55% minimum
- ❌ Remove `subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false)` from `Video(...)` — instant regression, MPV starts rendering subs inside the SurfaceView, uncontrollable styling returns
- ❌ Add subtitle visual styling via `NativePlayer.setProperty('sub-font'/'sub-color'/etc.)` as primary path — MPV renderer is disabled; property calls are no-ops for rendering (timing-only: `sub-delay`, `sub-speed` still work)
- ❌ Put `SubtitleOverlay` in only one of landscape/portrait stacks — subtitles disappear on rotation
