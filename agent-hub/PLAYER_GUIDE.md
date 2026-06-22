# Player Screen Architecture Guide
> player_screen.dart — 7033 lines | Updated: 2026-06-22

---

## Overlay Stack (build order, bottom to top)

```
1. Video surface (NativePlayer texture)
2. Seek flash animation (double-tap ripple)
3. Gesture layer (GestureDetector — tap/drag/scale/double-tap/long-press)
4. Controls overlay (AnimatedOpacity — auto-hides) ← _buildControlsOverlay()
5. Sidebar strip (right edge, _sidebarExpanded, hidden when _panelOpen=true)
6a. Brightness indicator pill (LEFT, amber, _showBrightnessIndicator)
6b. Volume indicator pill (LEFT, white/orange/red, _showVolumeIndicator)
7. Long-press 2× badge
8a. Pinch-zoom indicator pill
8b. Reset zoom button
9. Lock overlay (when _isLocked)
10. Seek preview label (during drag)
```

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

## Subtitle Properties (MPV)
| Setting | MPV Property | Notes |
|---------|-------------|-------|
| Font | `sub-font` | 'sans-serif','serif','monospace' |
| Size | `sub-font-size` | Integer string |
| Scale | `sub-scale` | Float e.g. "1.50" |
| Bold | `sub-bold` | 'yes'/'no' |
| Color | `sub-color` | `#RRGGBB` format |
| Background | `sub-back-color` | `#00000000` transparent, `#ffRRGGBB` |
| Opacity | `sub-opacity` | Float 0.0–1.0 (fixed: was sub-ass-fade-in-time) |
| Align X | `sub-align-x` | 'left'/'center'/'right' |
| Align Y | `sub-align-y` | 0=top 1=center 2=bottom |
| Margin Y | `sub-margin-y` | 0–200px |
| Margin X | `sub-margin-x` | 0–60px |
| Shadow offset | `sub-shadow-offset` | '0','3' |
| Outline size | `sub-outline-size` | '0','1.5' |
| Line spacing | `sub-spacing` | Float |
| Speed | `sub-speed` | Float |
| Sync | `sub-delay` | Float seconds |

---

## DO NOT List
- ❌ `vf=` — crashes HW decoder
- ❌ Change `hwdec` while playing — only safe when paused + `_player.state.duration == Duration.zero`
- ❌ Local variable named `_np` — shadows the field
- ❌ `db.get_setting(k)` — use `db.setting(k)`
- ❌ `androidAttachSurfaceAfterVideoParameters: true` — black screen
- ❌ `sub-ass-fade-in-time` — fake property, use `sub-opacity`
- ❌ Panel width < 0.55 — user confirmed 55% minimum
