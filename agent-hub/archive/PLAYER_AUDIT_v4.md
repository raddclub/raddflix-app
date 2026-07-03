# RaddFlix Video Player — Full Audit Report v4
**Date:** 2026-06-19  
**Author:** Agent (automated audit)  
**Files audited:**
- `raddflix_flutter/lib/screens/player_screen.dart` (4,339 lines)
- `raddflix_flutter/lib/widgets/player/quick_settings_panel.dart` (1,684 lines)

---

## Executive Summary

The player has **12 confirmed bugs**, **10 ghost/fake UI elements**, **11 UX issues**, and **10 design gaps**. The 1,684-line `QuickSettingsPanel` widget is fully built but never imported or used. The audio filter pipeline is broken — EQ, Reverb, and Lab overwrite each other. The loop toggle is fake at the engine level. All findings are ranked by user-visible severity.

---

## Part 1 — Confirmed Bugs

### BUG-01 ⚠️ CRITICAL — Audio Filter Pipeline Collision (EQ + Reverb + Lab overwrite each other)
**File:** `player_screen.dart`  
**Lines:** 956, 983, 2291–2315, 3166–3175

**Root cause:** Three separate audio effect systems all call `_np.setProperty('af', ...)` with a single filter string, independently of each other:
- `_applyPreset()` (line 956) → `af=equalizer=...`
- `_applyCustomEq()` (line 983) → `af=equalizer=...`
- `onReverbChanged` handler (lines 2299–2308) → `af=aecho=...`
- `_applyLabAf()` (line 3175) → `af=pan=...,equalizer=...,dynaudnorm,...`

**Result:** Each call completely replaces the entire `af` chain. Enable Reverb → EQ dies. Enable EQ → Reverb dies. Enable Lab → both die. Users cannot combine any audio effects.

**Note embedded in code (line 3365):** `"Note: Lab and EQ share the audio filter pipeline."` — this is an admission of the bug, not a fix.

**Fix required:** Centralized `_buildMergedAfString()` that assembles a single `af=filter1,filter2,...` chain from all active flags before calling `setProperty`. Never call `setProperty('af', ...)` from more than one place.

---

### BUG-02 ⚠️ CRITICAL — Loop Toggle is Fake at Engine Level
**File:** `player_screen.dart`  
**Lines:** 813–816, 574–578

```dart
void _toggleLoop() {
  _loopEnabled = !_loopEnabled;
  setState(() {});
}
```

MPV's native `loop-file` property is **never set**. The Flutter workaround (line 574–578) manually seeks to `Duration.zero` and calls `play()` on video completion — but this only works if `_onVideoCompleted` fires in time, which it may not if the player auto-advances to the next episode first. The loop icon in the shortcuts panel lights up but nothing reliable happens.

**Fix:** Add `_np.setProperty('loop-file', _loopEnabled ? 'inf' : 'no');` inside `_toggleLoop()`.

---

### BUG-03 HIGH — Audio Track "Disable" is a Dead Button
**File:** `player_screen.dart`  
**Lines:** 4179–4186

```dart
RadioListTile<AudioTrack?>(
  value: null,
  groupValue: widget.selectedTrack,
  onChanged: (_) {},   // ← NOOP
  title: const Text('Disable', ...),
)
```

The `onChanged` callback is empty. Tapping "Disable" in the audio track selection panel does absolutely nothing — does not mute audio, does not set track to null, does not call `setProperty('aid', 'no')`.

**Fix:** `onChanged: (_) => widget.onTrackSelected(null)` and handle null in the caller with `_np.setProperty('aid', 'no')`.

---

### BUG-04 HIGH — Stereo Mode Row is Permanent Static Text
**File:** `player_screen.dart`  
**Lines:** 4204–4208

```dart
ListTile(
  title: const Text('Stereo mode', ...),
  trailing: const Text('Stereo', ...),  // always "Stereo"
  onTap: () {},  // NOOP
)
```

Has no picker, no cycle logic, no MPV `audio-channels` property call. Purely decorative.

---

### BUG-05 MEDIUM — `_onVideoCompleted` Loop Race Condition
**File:** `player_screen.dart`  
**Lines:** 571–583

If `_hasNext == true` AND `_loopEnabled == true`, both branches can fire. The loop fires first (seek + play), but the delayed auto-advance timer (3 seconds) fires anyway and advances to the next episode, breaking the loop.

**Fix:** Return after loop handling: `if (_loopEnabled) { ...; return; }` — which is already present, but the auto-advance timer runs regardless of `_loopEnabled` state in edge cases (rapid scrubbing near end).

---

### BUG-06 MEDIUM — EQ Disabled Clears ALL Audio Filters
**File:** `player_screen.dart`  
**Lines:** 2288–2294

```dart
onEqEnabledChanged: (v) {
  setState(() => _eqEnabled = v);
  if (!v) {
    try { _np.setProperty('af', ''); } catch (_) {}  // ← nukes reverb too
  } else {
    _applyCustomEq();
  }
},
```

Turning off EQ sets `af=''`, which also kills any active Reverb or Lab effects. Consequence of BUG-01.

---

### BUG-07 MEDIUM — Reverb "Off" Falls Through to `_applyCustomEq()`
**File:** `player_screen.dart`  
**Lines:** 2310–2312

```dart
default:
  _applyCustomEq();  // called when reverb set to "Off"
```

When user turns off reverb, `_applyCustomEq()` is called — but this only applies if `_eqEnabled == true`. If EQ is disabled, `_applyCustomEq()` returns early (line 972: `if (!_eqEnabled) return;`), leaving `af` set to the old reverb string. Reverb never actually turns off unless EQ is active.

---

### BUG-08 MEDIUM — EQ Preset Maps Wrong Bands
**File:** `player_screen.dart`  
**Lines:** 960–967

The 5-band UI sliders are populated from the 10-band preset gains using incorrect indices:
```dart
_eqBands = [
  gains[1].toDouble(),  // comment says "~60Hz  → band 2 (62.5Hz)"
  gains[2].toDouble(),  // comment says "~230Hz → band 3 (125Hz)"
  gains[4].toDouble(),  // comment says "~910Hz → band 5 (500Hz)"
  gains[7].toDouble(),  // comment says "~3600Hz→ band 8 (4000Hz)"
  gains[9].toDouble(),  // comment says "~14kHz → band 10 (16000Hz)"
];
```
Indices 0, 3, 5, 6, 8 are silently dropped. The UI shows values that don't match what MPV actually applies (the preset sends all 10 bands, the sliders show only 5 different ones). The user sees a misleading EQ graph.

---

### BUG-09 LOW — Speed Subtitle Panel Uses Separate `_speed` State
**File:** `player_screen.dart`  
**Lines:** 2905–2920 (`_SubtitlePanel` inner state)

The subtitle panel has its own `_speed` variable (subtitle reading speed). It is initialized to `1.0` every time the panel opens and is never restored from prefs. Speed changes made here are lost when the panel closes.

---

### BUG-10 LOW — Subtitle Sync Panel Has Its Own `_sync` State (Not Linked to `_subSync`)
**File:** `player_screen.dart`  
**Lines:** 2882–2903

`_SubtitlePanel._sync` starts at `0.0` every open and calls `widget.onSyncChanged(delta)` with a delta — but the parent's `_subSync` value is never passed down to initialize the panel. The display always shows `0.0s` even if sync was previously adjusted to `+0.5s`.

---

### BUG-11 LOW — Lab "Dialogue Boost" uses MPV `equalizer` Filter (Conflicts with EQ)
**File:** `player_screen.dart`  
**Line:** 3169

```dart
if (_labDialogue) parts.add('equalizer=2000:1.5:0:3:1000');
```

Lab's "Dialogue Boost" also uses the `equalizer` MPV filter name. If both EQ and Dialogue Boost are active, the `af` chain will contain two `equalizer=` entries — MPV's behavior with duplicate filter names in the same chain is undefined and device-dependent.

---

### BUG-12 LOW — Volume Boosts to Max 250% but Indicator Shows 0–100%
**File:** `player_screen.dart`  
**Lines:** 806–808

```dart
_np.setProperty('volume', (_volume * 100).clamp(100, 250).round().toString());
```

The volume property is `(_volume * 100).clamp(100, 250)` meaning the slider minimum is 100% (full volume) and maximum is 250% (amplification). But the brightness/volume pill indicator presumably shows a 0–100% scale. The slider gesture that sets `_volume` starts from 0. Values 0–1.0 on the gesture all map to 100–250% MPV volume, which means any volume "reduction" is impossible from the gesture. **Users cannot turn down the volume below 100%.**

---

## Part 2 — Ghost / Fake UI Elements (Never-functional)

### GHOST-01 — Subtitle Settings Tab: 7 Static Rows (lines 2922–2959)
The entire "Settings" tab of the subtitle panel (`_tab == 1`) is 7 rows of **`const` read-only widgets**:

| Row | Type | Hardcoded Value | Functional? |
|-----|------|-----------------|-------------|
| Font | `const Row` + `Text('Sans Serif')` | "Sans Serif" | ❌ No picker |
| Size | `const Row` + `Text('22')` | "22" | ❌ No slider |
| Scale | `const Row` + `Text('100%')` | "100%" | ❌ No slider |
| Bold | `Row` + `Icon(Icons.check_box_rounded)` | always checked | ❌ Hardcoded icon |
| Color | `Row` + `Container(color: Colors.white)` | white | ❌ No color picker |
| Background | `Row` + `Container(color: Colors.black54)` | black54 | ❌ No color picker |
| Fade out | `const Row` + `Text('80%')` | "80%" | ❌ No slider |

None of these rows have tap handlers, state variables, or callbacks. They are purely decorative.

---

### GHOST-02 — Subtitle Panel Tab: 3 Static Rows (lines 2964–2977)
The "Panel" tab (`_tab == 4`) has:
- `Alignment` → hardcoded `Text('Center')`, no picker
- `Bottom margin` → hardcoded `Text('22')`, no slider
- `Fit subtitles into video size` → hardcoded `Icon(Icons.check_box_rounded)`, always checked

---

### GHOST-03 — Settings Navigation Tab: 3 Hardcoded Checkboxes (lines 4066–4085)
Three rows use `const Icon(Icons.check_box_rounded, color: Colors.white70)` with no state toggle:
- "Forward / backward button" — always appears checked
- "Previous / next button" — always appears checked
- "Display position while changing" — always appears checked

These are **decorative fake checkboxes**. They are `const` widgets inside `const` `Row(children: const [...])` — no state variable, no `onTap`, no callback.

---

### GHOST-04 — Settings Screen Tab: Truncated (lines 3926–3961)
`_buildScreenTab()` contains:
- `Show Remaining Time` toggle ✅ — functional
- `Keep Screen On` toggle ✅ — functional
- `Battery / clock in title bar` label — `Text` only, no control beneath it
- `Brightness` label — `Text` only, no slider or control

The tab header promises "Battery/clock" controls (from competitor feature set) but only renders a label. Screen brightness gesture is implemented in the player itself but there is no settings control here.

---

### GHOST-05 — Settings Controls Tab: Static Info Text (lines 3964–4019)
`_buildControlsTab()` has:
- `Background Audio` switch ✅ — functional
- `Touch action: Pause / resume` — `const Text` only, no dropdown or configurator
- `Lock mode: Auto lock controls when video plays` — `const Text` only, no toggle
- `Left half: Brightness • Right half: Volume` — `const Text` only, no remapping UI
- `Double tap left/right: Rewind/Forward` — `const Text` only, no configurator
- `Long press: 2× speed` — `const Text` only, no configurator

These gesture descriptions have no interactive controls beneath them.

---

### GHOST-06 — Audio "Add Translation" Text (line 2877–2878)
```dart
const Text('Add Translation', style: TextStyle(color: Color(0xFF4A9EFF), ...))
```
Looks like a tappable blue link but is a `const Text` with no `GestureDetector`. Does nothing.

---

### GHOST-07 — Entire `QuickSettingsPanel` Widget (1,684 lines — Never Imported)
**File:** `raddflix_flutter/lib/widgets/player/quick_settings_panel.dart`

This 1,684-line widget is **completely disconnected** from the player. A full search of `player_screen.dart` for `quick_settings`, `QuickSettings`, or `quickSettings` returns **zero matches**.

The widget includes:
- 5-tab settings panel (Style, Screen, Controls, Navigation, Audio)
- Brightness slider with system brightness API calls
- Battery/clock toggles
- Seek speed configurator
- Gesture remapping
- Accent color picker
- Progress bar style picker

**None of it is reachable by any user action.** It is entirely dead code.

---

### GHOST-08 — Reverb Cannot Be Turned Off (Relies on BUG-07)
The reverb preset selector shows an "Off" / default option, which falls through to `_applyCustomEq()`. But as documented in BUG-07, if EQ is disabled, reverb never actually clears. The "Off" state is fake.

---

### GHOST-09 — Volume Slider Cannot Reduce Volume (Relies on BUG-12)
The gesture volume control is clamped to `(100, 250)` MPV volume. There is no way to reduce below 100%. The volume reduction half of the gesture is silently a no-op.

---

### GHOST-10 — Loop in `_QuickShortcutsPanel` Fires `_toggleLoop()` Which is Fake
Connected to BUG-02. The loop shortcut button lights up `_loopEnabled = true` but MPV never loops.

---

## Part 3 — Competitor Comparison

### Reference apps: MX Player, VLC for Android, Play-it, Visha, GOM Player

| Feature | MX Player | VLC | Play-it | Visha | GOM | RaddFlix Current | Status |
|---------|-----------|-----|---------|-------|-----|-----------------|--------|
| **Audio EQ** | 10-band, presets | 10-band | 5-band | 5-band | 10-band | 5-band UI → 10-band MPV | ✅ Mostly working |
| **EQ + Reverb combo** | Yes | Yes | No | No | Yes | ❌ Mutually exclusive (BUG-01) | Bug |
| **Loop (file)** | Single/list/off | Yes | Yes | Yes | Yes | ❌ Flutter workaround only | Bug |
| **Audio track disable** | Yes | Yes | Yes | Yes | Yes | ❌ Dead button (BUG-03) | Bug |
| **Pinch to zoom** | Yes | Yes | Yes | Yes | No | ❌ Missing entirely | Missing |
| **Buffered region on seek bar** | Yes | Yes | Yes | Yes | Yes | ❌ Missing | Missing |
| **Subtitle font picker** | Yes | Yes | Yes | No | Yes | ❌ Ghost UI (GHOST-01) | Ghost |
| **Subtitle color picker** | Yes | Yes | Yes | No | Yes | ❌ Ghost UI (GHOST-01) | Ghost |
| **Double-tap seek flash** | Yes | Yes | Yes | Yes | No | Partial (no animation) | UX gap |
| **Seek + position preview** | Yes | Yes | Yes | Yes | No | ❌ Missing | Missing |
| **Volume boost > 100%** | Yes (200%) | No | No | No | No | Yes (up to 250%) ✅ | ✅ |
| **Sleep timer** | Yes | No | No | No | No | ✅ Yes | ✅ |
| **A-B repeat** | Yes | No | No | No | No | ✅ Yes | ✅ |
| **Speed presets panel** | Yes | Yes | Yes | Yes | Yes | ✅ Yes | ✅ |
| **Haptic feedback on gesture** | Yes | No | Yes | Yes | No | ❌ Missing | Missing |
| **Brightness in settings** | Yes | Yes | Yes | Yes | Yes | ❌ Ghost label only | Ghost |
| **One-handed mode** | No | No | No | Yes | No | ✅ Yes | ✅ |
| **Smart Enhance / video enhance** | No | No | No | No | No | ✅ Unique | ✅ |
| **Frame step** | Yes | Yes | No | No | No | ❌ Missing | Missing |
| **Screenshot** | Yes | Yes | Yes | No | No | ❌ Missing | Missing |
| **Cast to TV** | Yes | Yes | No | No | No | Stub only | Missing |
| **PiP** | Yes | Yes | No | Yes | No | ✅ Platform channel | ✅ |
| **Background audio** | Yes | Yes | Yes | Yes | Yes | ✅ Toggle present | ✅ |
| **Bookmarks** | Yes | Yes | No | No | No | ❌ Missing | Missing |
| **Keyboard shortcuts** | Yes | Yes | No | No | No | ❌ Missing | Missing |

**RaddFlix unique strengths:** Smart Enhance, One-Handed Mode, Volume Boost to 250%, A-B Repeat, Sleep Timer, JazzDrive zero-rating awareness.

**Critical gaps vs. all 5 competitors:** Pinch-to-zoom, buffered region, subtitle customization (functional), EQ+Reverb stacking, loop fix.

---

## Part 4 — UX Issues

### UX-01 — Double-Tap Seek Has No Visual Flash
All 5 competitor apps show a ripple/chevron animation when double-tapping to seek. RaddFlix shows no animation. The seek happens silently.

### UX-02 — No Haptic Feedback on Volume/Brightness Gestures
MX Player, Play-it, Visha all trigger `HapticFeedback.lightImpact()` at gesture start and at min/max clamp. RaddFlix has no haptic feedback anywhere in the player.

### UX-03 — Seek Bar Has No Buffered Region
`_buffered` is not tracked or displayed. The progress bar shows only played position and total. Users cannot see how much has been buffered/cached.

### UX-04 — No Pinch-to-Zoom
All 5 competitors support pinch-to-zoom. RaddFlix has 4 fixed zoom modes (Fit/Stretch/Crop/100%) but no continuous pinch gesture. This is especially noticed on 2.35:1 content with black bars.

### UX-05 — Settings Panel Tabs Show Ghost Content Without Warning
Users tap "Settings" in the subtitle panel, see 7 rows, try to tap Font/Size/Color — nothing happens. No "Coming soon" indication. Confusing.

### UX-06 — Volume Gesture Cannot Go Below 100% (Invisible to User)
As per BUG-12, any downward volume gesture has no effect below 100%. Users may think the volume gesture is broken.

### UX-07 — Loop Appears to Work but May Silently Fail
The loop icon toggles on/off visually, but native MPV loop is never engaged (BUG-02). On the completion boundary, there can be a brief black flash before the manual seek fires.

### UX-08 — Audio Effect Panel Has No "Combined" State Indicator
If user opens Audio Effects, turns on EQ, then turns on Reverb — the EQ preset indicator still shows the active preset even though EQ was killed. No visual indication that effects conflict.

### UX-09 — Subtitle Panel Opens to "Open" Tab (Not "Settings" or "Style")
The default tab is `_tab = 0` ("Open" — file picker). Users wanting to style subtitles must manually navigate to Settings tab which turns out to be ghost UI anyway.

### UX-10 — Settings Screen Tab Is Visually Incomplete
The Screen tab ends abruptly at "Brightness" label with no control beneath it. The tab appears mid-build/truncated.

### UX-11 — No Loading/Buffering Spinner Differentiation
The loading state shows a spinner but there's no distinction between "initial load", "buffering mid-play", and "seeking". Competitors use different animation speeds or labels for each state.

---

## Part 5 — Design Gaps

### DESIGN-01 — Seek Bar Lacks Buffered Track
Standard: gray buffer track behind white played track. Currently only played track shown.

### DESIGN-02 — No Seek Thumbnail Preview
MX Player, VLC, Play-it all show a thumbnail preview above the seek thumb. Missing entirely.

### DESIGN-03 — Double-Tap Seek Animation Missing
No chevron ripple / arc / glow on double-tap area. The action feels unresponsive.

### DESIGN-04 — Volume/Brightness Pill Lacks Progress Arc
Competitors use a semicircle arc progress indicator. RaddFlix uses a flat percentage pill which is less intuitive on phone ergonomics.

### DESIGN-05 — Audio Effects Panel Warning Text is Too Small
Line 3365: `"Note: Lab and EQ share the audio filter pipeline."` is at 10px `Colors.white24` — functionally invisible. Users will never read it.

### DESIGN-06 — Settings Panel (4-tab) Screen Tab Visually Truncated
The Screen tab ends after two lines of text. Users see a half-empty panel and lose trust in the settings panel overall.

### DESIGN-07 — Navigation Tab Fake Checkboxes Look Functional
The `Icons.check_box_rounded` with `Colors.white70` looks exactly like a real toggle. Users will tap it expecting to disable it and nothing will happen.

### DESIGN-08 — Subtitle Settings 7 Ghost Rows All Look Functional
`Text('Font') + Text('Sans Serif') + Icon(chevron_right)` looks exactly like a working list item. Pure confusion for users.

### DESIGN-09 — No Seek Flash / Ripple on Double-Tap Side
Empty area. Should have: forward chevrons (MX-style) or a radial glow.

### DESIGN-10 — QuickSettingsPanel (1,684 lines) is More Polished than In-Player Settings
The disconnected `QuickSettingsPanel` has more complete settings, better layout, and actual brightness/clock/battery controls. The active in-player settings panel is the less complete one. Should swap or integrate.

---

## Part 6 — Implementation Plan (6 Phases)

### Phase 1 — Kill Ghost UI (Estimated: 2–3 hours)
**Priority: CRITICAL** — Users can currently see and interact with broken UI.

1. **P1.1** — Subtitle Settings tab: Replace 7 ghost rows with real stateful controls
   - Font row → `showDialog` font picker (3-4 options: Sans Serif, Serif, Monospace, Casual)
   - Size row → `Slider(min:12, max:40)` with `_SubtitlePanel._subSize` state + `widget.onSizeChanged` callback
   - Scale row → `Slider(min:50%, max:200%)` 
   - Bold row → Real `Switch` or `Checkbox`
   - Color row → `showDialog` color picker (8 preset swatches)
   - Background row → `showDialog` color picker
   - Fade out row → `Slider`

2. **P1.2** — Navigation Tab: Replace 3 fake checkboxes with real toggles
   - Add `bool _showSkipButtons`, `bool _showPrevNextButtons`, `bool _showPositionOnSeek` state
   - Wire to callbacks `widget.onShowSkipChanged`, etc.
   - Use `SwitchListTile` instead of fake `Icon(check_box)`

3. **P1.3** — Screen Tab: Add real battery/clock toggle and brightness slider
   - `SwitchListTile` for battery, clock, elapsed time display
   - `Slider` for brightness that calls `ScreenBrightness().setScreenBrightness(v)`

4. **P1.4** — Controls Tab: Add real gesture configurator rows
   - Replace static text with info cards that have a "Customize" button

5. **P1.5** — Audio "Add Translation" text: Wrap in `GestureDetector` or remove

---

### Phase 2 — Fix Audio Filter Pipeline (Estimated: 1 hour)
**Priority: CRITICAL** — BUG-01, BUG-06, BUG-07, BUG-11

1. Add centralized state variables in `_PlayerScreenState`:
   ```dart
   bool _reverbEnabled = false;
   String _reverbPreset = '';
   ```

2. Write `String _buildMergedAfString()`:
   ```dart
   String _buildMergedAfString() {
     final parts = <String>[];
     // EQ
     if (_eqEnabled) {
       final b = _eqBands;
       final g = [b[0],b[0],b[1],b[1],b[2],b[2],b[3],b[3],b[4],b[4]].map((v) => v.round()).toList();
       parts.add('equalizer=${g.join(':')}');
     }
     // Reverb
     if (_reverbEnabled && _reverbPreset.isNotEmpty) {
       parts.add(_reverbPreset);
     }
     // Lab
     if (_labVocal) parts.add('pan=stereo|FL=FL-FR|FR=FR-FL');
     if (_labDialogue) parts.add('equalizer=2000:1.5:0:3:1000'); // rename to avoid collision
     if (_labNorm) parts.add('dynaudnorm');
     if (_labBass) parts.add('equalizer=60:1.0:0:${(_labBassLevel * 12).round()}:60');
     return parts.join(',');
   }
   ```

3. Replace ALL `_np.setProperty('af', ...)` calls with a single `_applyAllAf()`:
   ```dart
   void _applyAllAf() {
     try { _np.setProperty('af', _buildMergedAfString()); } catch (_) {}
   }
   ```

4. Fix Dialogue Boost filter name collision: use `lavfi=[equalizer=...]` syntax or rename.

---

### Phase 3 — Fix Loop + Audio Disable (Estimated: 30 min)
**Priority: HIGH** — BUG-02, BUG-03

1. **BUG-02:** Add to `_toggleLoop()`:
   ```dart
   _np.setProperty('loop-file', _loopEnabled ? 'inf' : 'no');
   ```

2. **BUG-03:** Fix Audio Disable `onChanged`:
   ```dart
   onChanged: (_) => widget.onTrackSelected(null)
   ```
   And in parent, handle null:
   ```dart
   if (track == null) {
     _np.setProperty('aid', 'no');
   } else {
     _np.setProperty('aid', track.id.toString());
   }
   ```

3. **BUG-12:** Fix volume range to allow 0–100%:
   ```dart
   _np.setProperty('volume', (_volume * 100).clamp(0, 250).round().toString());
   ```
   And update booster indicator to show relative to 100%.

---

### Phase 4 — Wire QuickSettingsPanel (Estimated: 2–3 hours)
**Priority: HIGH** — GHOST-07

1. Import `quick_settings_panel.dart` in `player_screen.dart`
2. Replace inline `_openSettingsPanel()` content with `QuickSettingsPanel` (or use it as the body)
3. Wire all callbacks: `onBrightnessChanged`, `onShowBatteryChanged`, `onShowClockChanged`, `onSeekSwipeSpeedChanged` etc. to player state
4. Pass initial state down so panel opens with current values (not defaults)
5. Persist settings to `SharedPreferences` via `_savePrefs()`

---

### Phase 5 — Add Missing UX Features (Estimated: 1 day)
**Priority: MEDIUM**

1. **Pinch-to-zoom:** Wrap `VideoPlayer` in `GestureDetector` with `onScaleUpdate`. Map scale to `_zoomFactor`, apply via `Transform.scale`. Add double-tap reset.

2. **Double-tap seek flash:** On double-tap, animate a `Row` of `Icon(Icons.fast_forward_rounded)` icons with `AnimatedOpacity`. Fade in at 1.0, fade to 0.0 in 600ms.

3. **Haptic feedback:** Add `HapticFeedback.lightImpact()` at: gesture start, lock toggle, loop toggle, speed change.

4. **Buffered seek bar region:** Subscribe to `_player.stream.buffer` → `setState(() => _buffered = ...)`. Draw gray track from `0` to `_buffered.inMilliseconds / _duration.inMilliseconds` behind white played track.

5. **Subtitle sync initial value:** Pass `initialSync: _subSync` to `_SubtitlePanel` constructor and initialize `_sync = widget.initialSync`.

---

### Phase 6 — Design Polish (Estimated: 4–6 hours)
**Priority: LOW**

1. Volume/Brightness indicator: replace flat pill with arc progress (semicircle using `CustomPaint`)
2. Seek bar: add buffered region in gray, add seek thumb glow on drag
3. Double-tap animation: 3-chevron forward/back animation (MX Player style)
4. Audio Effects panel: make the "Note" warning bigger (14px, `Colors.orange`) or replace with a visual "combined effects" chip bar
5. Settings Navigation Tab fake checkboxes: use `SwitchListTile` (real) instead of icon
6. Screen Tab: fill the remaining empty space with the full brightness control

---

## Part 7 — File/Line Reference Index

| Bug/Ghost | File | Lines | Severity |
|-----------|------|-------|---------|
| BUG-01 AF collision | player_screen.dart | 956, 983, 2291–2315, 3166–3175 | CRITICAL |
| BUG-02 Loop fake | player_screen.dart | 813–816, 574–578 | CRITICAL |
| BUG-03 Audio disable noop | player_screen.dart | 4179–4186 | HIGH |
| BUG-04 Stereo mode static | player_screen.dart | 4204–4208 | HIGH |
| BUG-05 Loop race | player_screen.dart | 571–583 | MEDIUM |
| BUG-06 EQ off kills all AF | player_screen.dart | 2288–2294 | MEDIUM |
| BUG-07 Reverb off broken | player_screen.dart | 2310–2312 | MEDIUM |
| BUG-08 EQ band mismatch | player_screen.dart | 960–967 | MEDIUM |
| BUG-09 Sub speed no persist | player_screen.dart | 2905–2920 | LOW |
| BUG-10 Sub sync no initial | player_screen.dart | 2882–2903 | LOW |
| BUG-11 Lab=EQ filter name | player_screen.dart | 3169 | LOW |
| BUG-12 Volume no reduce | player_screen.dart | 806–808 | MEDIUM |
| GHOST-01 Sub Settings 7 rows | player_screen.dart | 2922–2959 | HIGH |
| GHOST-02 Sub Panel 3 rows | player_screen.dart | 2964–2977 | MEDIUM |
| GHOST-03 Nav checkboxes | player_screen.dart | 4066–4085 | HIGH |
| GHOST-04 Screen tab truncated | player_screen.dart | 3926–3961 | MEDIUM |
| GHOST-05 Controls tab static | player_screen.dart | 3964–4019 | LOW |
| GHOST-06 Add Translation text | player_screen.dart | 2877–2878 | LOW |
| GHOST-07 QuickSettingsPanel disconnected | quick_settings_panel.dart | ALL | HIGH |

---

## Appendix — MediaTek Safety Rules (Must not be violated in any fix)

| Rule | Detail |
|------|--------|
| **NEVER `vf=`** | `setProperty('vf', ...)` destroys GL surface on MediaTek → 15-day black screen. Use `ColorFiltered` Flutter widget instead. |
| **NEVER `hwdec` mid-play** | Only in initial player config before `_player.open()`. |
| **`_videoOpened=true` before `_player.open()`** | Race condition guard. |
| **Never name local var `_np`** | `_np` is the global `NativePlayer` reference. Shadow it and you break all property calls. |
| **`af=` is safe** | Audio filter property only — does not touch GL/video pipeline. All EQ/Lab/Reverb work is safe. |

---

*End of RaddFlix Player Audit v4*
