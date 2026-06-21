# RaddFlix Video Player — Agent Reference Guide
_Last updated: 2026-06-21 | Build #1218 ✅_

---

## TL;DR for Agents

| Question | Answer |
|----------|--------|
| Which file do I edit? | `raddflix_flutter/lib/screens/player_screen.dart` (7071 lines, 21 classes) |
| Can I use `vf=` property? | **NEVER.** Destroys GL surface on MediaTek. 15-day black screen bug. |
| Can I use `hwdec` mid-play? | **NEVER.** Only in initial player config before open(). |
| Can I use video filters? | Only `ColorFiltered` Flutter widget. No MPV `vf=` ever. |
| Can I use audio filters? | Yes — `af=equalizer` is safe (audio filter, not video). |
| How do I push changes? | `node /tmp/push.js` — fetches fresh SHA, pushes to GitHub |
| How do I trigger a build? | POST to /actions/workflows/282572869/dispatches |
| How do I open a panel? | `_openRightPanel(Widget)` — slides from right at 45% width |
| Local var named _np? | NEVER. Shadows the mpv player instance. |

---

## File Structure

```
player_screen.dart (7071 lines)
  ├── _PlayerScreenState          ← master state: all modes, prefs, position, panels
  │   ├── State variables (lines 75–320)
  │   ├── _initPlayer()           ← pre-loads prefs + sets vf BEFORE open()
  │   ├── _loadPrefs()            ← SharedPreferences load
  │   ├── _savePrefs()            ← SharedPreferences save
  │   ├── build() + _build*()     ← local widget builders
  │   │   ├── _buildVideoSurface()
  │   │   ├── _buildLockOverlay()
  │   │   ├── _buildControlsOverlay(constraints)
  │   │   ├── _buildTopBar()
  │   │   ├── _buildCenterControls()
  │   │   ├── _buildBottomArea(constraints, pos)
  │   │   ├── _buildBottomIconRow()
  │   │   ├── _buildSidebar(constraints)  ← NEW: persistent shortcut sidebar
  │   │   └── _buildSideIndicator(...)    ← MX-style brightness/volume pill
  │   └── Action methods (_cycleSpeed, _toggleLoop, _enterPiP, etc.)
  ├── _QuickShortcutsPanel        ← "More" right-side panel (6×4 grid)
  ├── _SettingsPanel              ← Settings right-side panel (4 tabs)
  ├── _SidebarCustomizerPanel     ← NEW: drag-reorder sidebar editor
  ├── _SidebarCustomizerPanelState
  ├── _ShortcutItem / _ShortcutGrid
  ├── _RaddIconBtn / _BottomIconBtn
  ├── _LabToggleRow, _ReverbSelector, _ReverbSelectorState
  └── WatchPartyOverlay (separate file)
```

---

## Overlay Stack Order (inside LayoutBuilder Stack)

| Layer | Widget | Condition |
|-------|--------|-----------|
| 1 | Video surface (RepaintBoundary) | always |
| 2 | Lock overlay | _isLocked |
| 3 | Voice cmd badge | _voiceCommandsEnabled && _lastVoiceCmd.isNotEmpty |
| 4 | WatchParty overlay | _watchPartyRoom != null |
| 5 | Gesture layer (GestureDetector) | !_isLocked |
| 6 | Controls overlay (AnimatedOpacity) | auto-hides |
| **7** | **Sidebar (AnimatedOpacity, right edge)** | **!_isLocked, new** |
| 8 | Brightness indicator (left pill) | _showBrightnessIndicator |
| 9 | Volume indicator (right pill) | _showVolumeIndicator |
| 10 | Long-press 2× badge | _longPressingSpeed |
| 11 | Zoom indicator pill | _zoomMode != 0 |
| 12 | Reset zoom button | _zoomMode != 0 |

---

## Panel System

All panels open via `_openRightPanel(Widget child)`:
- Slides in from right (300ms)
- Width: 45% of screen
- Background: black at 60% opacity
- Close: swipe right or tap backdrop

**Current panels:**
| Panel opener | Panel widget |
|---|---|
| _openMoreMenu() | _QuickShortcutsPanel |
| _openSettingsPanel() | _SettingsPanel |
| _openSubtitlePanel() | subtitle ListView |
| _openAudioPanel() | audio track ListView |
| _openAudioEffectPanel() | EQ panel |
| _openSidebarCustomizer() | _SidebarCustomizerPanel (NEW) |
| _showEpisodeSheet() | episode list |

---

## Sidebar System (NEW — Phase 16)

### State Variables
```dart
bool _sidebarExpanded = true;       // pref: pref_sidebar_exp
List<String> _sidebarOrder = [...]; // pref: pref_sidebar_order (JSON)
static const _allSidebarIds = [     // master list
  'cc','audio','eq','speed','loop','rotate','lock','pip',
  'screenshot','sleep','ab','episodes','settings','vivid',
  'mute','frame','onehanded','zoom','silence',
];
```

### Shortcut ID → State Mapping
| ID | Icon | Active when | onTap |
|---|---|---|---|
| cc | subtitles | _subtitleTracks.isNotEmpty | _openSubtitlePanel |
| audio | headphones | _audioTracks.length > 1 | _openAudioPanel |
| eq | equalizer | _eqEnabled | _openAudioEffectPanel |
| speed | speed | _speed != 1.0 | _cycleSpeed |
| loop | loop | _loopEnabled | _toggleLoop |
| rotate | screen_rotation | _orientMode != 0 | _cycleOrientation |
| lock | lock_outline | never | sets _isLocked = true |
| pip | pip | never | _enterPiP |
| screenshot | camera_alt | never | _takeScreenshot |
| sleep | bedtime | _sleepTimerEnd != null | (sleep timer) |
| ab | repeat_one | _abActive | _handleAbRepeat |
| episodes | view_list | available if _eps.length > 1 | _showEpisodeSheet |
| settings | settings | never | _openSettingsPanel |
| vivid | auto_awesome | _smartEnhanceEnabled | _toggleSmartEnhance |
| mute | volume_off | _isMuted | _toggleMute |
| frame | skip_next | never | _np.command(['frame-step']) |
| onehanded | pan_tool_alt | _oneHandedMode | toggles _oneHandedMode |
| zoom | zoom_in | _zoomMode != 0 | _openZoomPanel |
| silence | volume_off_outlined | _silenceSkipEnabled | _showSilenceSkipSheet |

---

## Orientation System (NEW — Phase 15)

Auto-rotation via native Android API (ignores system auto-rotate toggle):
```dart
void _setNativeOrientation(String mode) async {
  // Calls com.raddflix.app/orient channel
  // mode: 'auto' | 'landscape' | 'portrait' | 'landscape_one' | 'default'
}
```

| _orientMode | _setNativeOrientation call | Android constant |
|---|---|---|
| 0 (auto) | 'auto' | SCREEN_ORIENTATION_SENSOR |
| 1 (landscape) | 'landscape' | SCREEN_ORIENTATION_SENSOR_LANDSCAPE |
| 2 (portrait) | 'portrait' | SCREEN_ORIENTATION_SENSOR_PORTRAIT |
| 3 (one side) | 'landscape_one' | SCREEN_ORIENTATION_LANDSCAPE |
| dispose | 'default' | SCREEN_ORIENTATION_UNSPECIFIED |

---

## Key Prefs Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pref_sidebar_order | String (JSON) | 8-item default list | Ordered shortcut IDs |
| pref_sidebar_exp | bool | true | Sidebar expanded/collapsed |
| pref_onehanded | bool | false | One-handed mode |
| pref_onehanded_left | bool | false | Left-hand preference |
| pref_speed | double | 1.0 | Playback speed |
| pref_loop | bool | false | Loop enabled |
| pref_eq_enabled | bool | false | EQ enabled |
| pref_smart_enhance | bool | false | Vivid/Smart Enhance |
| pref_muted | bool | false | Muted |
| pref_orient | int | 0 | Orientation mode |
| pref_sub_margin | double | 100 | Subtitle bottom margin px |
| pref_sleep_minutes | int? | null | Sleep timer |

---

## DO NOT Do These Things

```dart
// ❌ NEVER — black screen on MediaTek
await _np.setProperty('vf', 'eq=...');
// ❌ NEVER — GL surface destroyed
await _np.setProperty('hwdec', 'auto');  // mid-play
// ❌ NEVER — shadows mpv instance
final _np = SomethingElse();
// ❌ NEVER — wrong DB method
db.get_setting('key');
// ❌ NEVER — adds to AndroidManifest wrong surface
androidAttachSurfaceAfterVideoParameters: true
```
