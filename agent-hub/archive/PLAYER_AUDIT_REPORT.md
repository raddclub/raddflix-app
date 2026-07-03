# 🔍 RaddFlix Player — Deep Hunter God Mode Audit
**Date:** 2026-06-20  
**Auditor:** Oracle Agent v3.0.0  
**Scope:** `player_screen.dart`, `player_prefs.dart`, `quick_settings_panel.dart`, `jazzdrive_service.dart`, all widget dependencies  
**Mode:** Pure analysis — zero code changes

---

## 📋 EXECUTIVE SUMMARY

The RaddFlix player is a **feature-rich but architecturally fragile monolith**. The core playback, gestures, and audio pipeline work well. However, roughly **20–25% of the visible UI surface is non-functional** — stubbed, hardcoded, or wired to dead callbacks. There are **6 critical silent bugs** where users change settings that look like they worked but have zero effect on actual playback. Two fully-implemented services (Watch Party, Voice Commands) are completely disconnected from the player. The dual preferences system creates a ticking time-bomb for data loss.

---

## PHASE 1 — CODEBASE DISCOVERY

### File Inventory

| File | Lines | Status |
|------|-------|--------|
| `screens/player_screen.dart` | 5,337 | PRIMARY — monolith, all panels inline |
| `screens/player_screen_v1_backup.dart` | 7,619 | **Backup/dead** — older version, NOT imported anywhere |
| `core/player/player_prefs.dart` | 1,158 | **ORPHANED** — rich prefs model, NEVER used by player |
| `widgets/player/quick_settings_panel.dart` | 1,685 | Secondary widget — imported by player |
| `core/services/jazzdrive_service.dart` | 608 | Active — Jazz SIM zero-rating |
| `core/services/watch_party_service.dart` | 476 | **DISCONNECTED** — full impl, zero integration |
| `core/services/voice_commands_service.dart` | ~300 | **DISCONNECTED** — full impl, zero integration |
| `widgets/player/cinematic_overlay.dart` | 6 | **TOMBSTONE** — empty stub, kept only to prevent compile errors |
| `widgets/player/seek_bar_painter.dart` | active | ✅ Only external widget imported by player |

### The 50+ "Series" Files
Files matching patterns `c_series_*.dart`, `d_series_*.dart`, `f/g/n/o/p/q/r/s/t/u/v series` etc. — **none are imported by `player_screen.dart`**. These are either:
- Ghost features from a previous architecture that was abandoned
- Pre-built components awaiting wiring
- Dead code bloating the repo

### Import Audit — player_screen.dart
```dart
// Only these are imported:
import 'package:flutter_riverpod/flutter_riverpod.dart';   // barely used
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/jazzdrive_service.dart';
import '../core/db/local_db.dart';
import '../core/api/catalog_api.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import '../widgets/player/seek_bar_painter.dart';  // ← only player widget imported
```

`quick_settings_panel.dart` is a **separate file** but ALL other panels (`_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel`, `_QuickShortcutsPanel`, `_SettingsPanel`) are **private classes inside `player_screen.dart` itself**.

---

## PHASE 2 — FEATURE INVENTORY

### ✅ REAL & WORKING Features

| # | Feature | Implementation Quality |
|---|---------|----------------------|
| 1 | Video playback (media_kit + NativePlayer) | Solid |
| 2 | Gesture: brightness (left half drag) | Working |
| 3 | Gesture: volume (right half drag) | Working |
| 4 | Gesture: seek (horizontal drag) | Working |
| 5 | Gesture: pinch zoom | Working |
| 6 | Gesture: double-tap rewind/forward | Working |
| 7 | Gesture: long-press → 2× speed | Working |
| 8 | Sleep timer (15/30/45/60/90 min) | Working |
| 9 | A-B loop | Working |
| 10 | Screen lock | Working |
| 11 | Frame step | Working |
| 12 | One-handed mode | Working |
| 13 | Subtitle panel: Open file, Sync, Speed, Settings | Working |
| 14 | Subtitle: font, size, scale, bold, text color | Working (wired to mpv) |
| 15 | Subtitle: bottom margin, fit-to-video | Working |
| 16 | Audio track selection + SW decoder toggle | Working |
| 17 | Audio channel mode cycling (Stereo/Mono/L/R) | Working (loses state on reopen — see bugs) |
| 18 | Audio A/V sync | Working |
| 19 | Video zoom: Fit/Stretch/Crop/100%/Pinch | Working |
| 20 | EQ (5-band: 60Hz/230Hz/910Hz/3.6k/14k) | Working |
| 21 | EQ enable/disable toggle | Working |
| 22 | Reverb room presets (None/SmallRoom/Hall/Cathedral/Stadium) | Working |
| 23 | Audio Lab: Vocal Remover, Dialogue Boost, Normalization, Bass Boost | Working |
| 24 | Audio L/R balance | Working |
| 25 | All audio effects merged via `_buildMergedAfString()` | Working — correct stacking |
| 26 | Background audio (PIP MethodChannel) | Implemented (needs Android native side) |
| 27 | Night mode warm filter overlay | Working |
| 28 | Screen brightness control | Working (screen_brightness package) |
| 29 | Watch position save/restore (SQLite via local_db) | Working |
| 30 | Jazz SIM zero-rating detection | Working |
| 31 | Progress bar styles (9 variants via SeekBarPainter) | Working |
| 32 | Accent color theming | Working |
| 33 | Skip interval configurability (5–60s) | Working |
| 34 | Skip/fwd buttons toggle | Working (wired, but init bug — see Phase 7) |
| 35 | Prev/next episode navigation | Working |
| 36 | Show remaining time toggle | Working |
| 37 | Keep screen on (WakeLock) | Working |
| 38 | Clock in title bar toggle | Working |
| 39 | Smart enhance (visual animation effect) | Working as an animation — no actual video processing |
| 40 | PiP enter via MethodChannel | Implemented (needs Android native side) |
| 41 | `_friendlyError()` Jazz error mapping | Working |
| 42 | Seek speed configurability (30–300s/swipe) | Working |
| 43 | Video rotation (0/90/180/270) | Working |

### ❌ STUB / FAKE / DISCONNECTED Features

| # | Feature | What the User Sees | What Actually Happens |
|---|---------|--------------------|-----------------------|
| 1 | Subtitle → Customization tab (tab 5) | Position, Shadow, Opacity, Edge padding, Line spacing controls | ALL `const` hardcoded widgets — tap nothing, nothing changes. No callbacks. |
| 2 | Online subtitle search | "🔍 Search online subtitles" link + OpenSubtitles.org description | Always shows "Online subtitle search coming soon." SnackBar |
| 3 | Subtitle translation | "🌐 Add Translation" → language picker for 6 languages | Every language shows "Subtitle translation to X coming soon." SnackBar |
| 4 | Watch Party | Not visible in player UI at all | `watch_party_service.dart` is 476 lines of complete WebSocket architecture with room models, sync logic, overlay widget — **never imported, never wired** |
| 5 | Voice Commands | Not visible in player UI at all | `voice_commands_service.dart` is full Android SpeechRecognizer bridge with intent parsing — **never imported, never wired** |
| 6 | QSP → Gesture Map | "Gesture Map" button in Quick Settings Panel | Fires `onOpenGestureMap` callback → player_screen.dart passes `() {}` (no-op) |
| 7 | QSP → Skip Editor | "Skip Editor" button | Fires `onOpenSkipEditor` → `() {}` no-op |
| 8 | QSP → Jump To | "Jump To" button | Fires `onOpenJumpTo` → `() {}` no-op |
| 9 | QSP → Speed Presets | "Speed Presets" button | Fires `onOpenSpeedPresets` → `() {}` no-op |
| 10 | QSP → Video End Action | "Video End Action" button | Fires `onOpenEndAction` → `() {}` no-op |
| 11 | QSP → Smart Skip (Silence) | "Smart Skip" button | Fires `onOpenSilenceSkip` → `() {}` no-op |
| 12 | QSP → Zoom & Crop | "Zoom & Crop" button | Fires `onOpenZoomCrop` → `() {}` no-op |
| 13 | QSP → Layout Designer | "Layout Designer" button | Fires `onOpenLayoutDesigner ?? () {}` → `() {}` no-op |
| 14 | Screenshot feature | `saver_gallery` in pubspec.yaml, fields in PlayerPrefs | Not implemented anywhere in active code |
| 15 | Settings → Controls tab | "Auto lock controls" text, gesture description text | Purely static text. No toggles, no interactivity. |
| 16 | Cinematic mode overlay | `cinematic_overlay.dart` exists | 6-line tombstone file. Code comment says overlay moved to Opacity in player_screen.dart, file kept to prevent compile errors. |

---

## PHASE 3 — FLUTTER ARCHITECTURE REVIEW

### 3.1 The Monolith Problem

`player_screen.dart` is **5,337 lines** in a single file. It contains:
- The main `PlayerScreen` StatefulWidget and all its state
- `_SubtitlePanel` (private class, ~600 lines)
- `_AudioTrackPanel` + `_AudioTrackPanelState` (split — declared at line 3,857, State at line 5,106 — **1,249 lines apart**)
- `_VideoZoomPanel` (private class)
- `_AudioEffectPanel` + `_AudioEffectPanelState` (private class)
- `_QuickShortcutsPanel` (private StatelessWidget)
- `_SettingsPanel` + `_SettingsPanelState` (private class)
- `_ReverbSelector` + `_ReverbSelectorState` (private class)
- `_LabToggleRow` (private StatelessWidget)
- `_ShortcutItem` data class
- `_ShortcutGrid` widget
- `_SyncBtn` widget

**Impact:** Every `setState()` in any panel triggers a rebuild of the entire 5,337-line widget tree. Performance degrades as panels add state.

### 3.2 The Dual Preferences System (Critical Architecture Bug)

**System A:** Raw `SharedPreferences` in `player_screen.dart`  
Keys used: `pref_showrem`, `pref_wakelock`, `pref_skipint`, `pref_bgaudio`, `pref_seekswipe`, `pref_accentcol`, `pref_pbstyle`, `pref_nightmode`, `pref_nightwarmth`, `pref_showclock`, ~15 total

**System B:** `PlayerPrefs` class in `player_prefs.dart`  
Contains **100+ typed fields** including: `eqBands`, `reverbPreset`, `subtitleFont`, `subtitleSize`, `subtitleBold`, `subtitleColor`, `screenshotLockEnabled`, `screenshotWatermark`, `quickBarItems`, `watchPartyEnabled`, `silenceSkipEnabled`, `zoomCropMode`, `gestureLayout`, `skipIntroEnabled`, `skipOutroEnabled`, etc.

**The problem:** These two systems are **completely disconnected**. `player_screen.dart` never instantiates `PlayerPrefs`. All panel settings that the user changes (EQ bands, reverb, subtitle styling, zoom mode, audio effects, etc.) are stored **only in ephemeral widget state** — they are **lost on every player close**. Only the 15 SharedPreferences keys survive app restarts.

### 3.3 State Management

| Layer | Pattern Used |
|-------|-------------|
| Main player | `ConsumerStatefulWidget` (Riverpod) — but Riverpod is barely used, most state is `setState()` |
| All panels | Pure `StatefulWidget` with local state, callbacks up to parent |
| Quick Settings Panel | Has its **own internal PlayerPrefs state management** parallel to the parent |

The Riverpod import exists but the player primarily uses direct `setState()` — Riverpod is not leveraged for shared state.

### 3.4 MediaTek Safety Rules (Correctly Implemented)

The code correctly follows:
- ❌ No `vf=` mid-play
- ❌ No `hwdec` mid-play  
- ✅ `androidAttachSurfaceAfterVideoParameters=false`
- ✅ Speed via `NativePlayer.setProperty`
- ✅ Recovery-seek after framedrop/speed changes
- ✅ All audio effects merged via `_buildMergedAfString()` → single `af` property set

### 3.5 The `audio_session` Package — Dead Import

`audio_session: ^0.1.21` is in `pubspec.yaml` but there is **no import or usage** of `audio_session` in `player_screen.dart`. This was added (likely for background audio session management) but never wired. Background audio handling is done purely via MethodChannel to a custom Android native implementation.

---

## PHASE 4 — UX / UI AUDIT

### 4.1 Panel Navigation Model

The player uses a **right-side modal bottom sheet** (`_openRightPanel()`) with `widthFactor: 0.82`. All 6 panels slide in from the right. This is functional but:
- No breadcrumb/back navigation — only a chevron_left button
- No swipe-to-dismiss affordance
- Panels don't animate closed when another opens — the old one is popped before new one shows

### 4.2 Subtitle Panel Issues

**Tab order and discovery:**
- 6 tabs: Open | Settings | Synchronization | Speed | Panel | Customization
- "Settings" (tab 1) handles font/size/bold/color — more logically named "Style" or "Appearance"
- "Customization" (tab 5) is entirely fake — see bug #1

**Redundant UI:**
- "Add Translation" appears in TWO places: once as text in the header area (when currentFile != null), and again as a tappable link in the Open tab — same "coming soon" behavior both times

**Missing subtitle background application:**
- Background color picker (`_subBgPresets`) is shown and responds to taps
- Selected color updates `_subBg` via setState
- BUT: the `onPick` callback does `setState(() => _subBg = col)` with **no call to `widget.onSubPropertyChanged()`** — background color is NEVER sent to MPV

### 4.3 Settings Panel — Navigation Tab Init Bug

```dart
class _SettingsPanelState extends State<_SettingsPanel> {
  bool _showSkipBtns = true;       // ← hardcoded, ignores widget.* value
  bool _showPrevNextBtns = true;   // ← hardcoded, ignores widget.* value  
  bool _showSeekPosition = true;   // ← hardcoded, ignores widget.* value
```

Even though the parent passes state and callbacks for these three toggles, the Settings panel **always initializes them to `true`**. If a user previously set "Forward/backward buttons" to OFF, reopening Settings shows them as ON.

### 4.4 Audio Track Panel — Channel Mode State Loss

`_AudioTrackPanelState._chIdx` is initialized to `0` (Stereo) in every new panel instance. Since the panel is recreated on every `_openRightPanel()` call:
- User opens panel, cycles to "Mono"
- User closes panel  
- User reopens panel → shows "Stereo" again
- The actual MPV `af` filter is still "Mono" but the UI disagrees

### 4.5 Sleep Timer Countdown Display

`_QuickShortcutsPanel` is a **StatelessWidget**. It computes sleep timer remaining time at build time:
```dart
final remaining = sleepTimerEnd!.difference(DateTime.now());
sleepLabel = 'Sleep ${remaining.inMinutes}m';
```
The countdown **never ticks** while the panel is open. The user sees a frozen "Sleep 29m" that never decrements until they close and reopen the panel. A `Timer.periodic` is needed in this widget's State.

### 4.6 Speed Label Floating Point Display

```dart
_ShortcutItem(Icons.speed_rounded, '${speed}×', speed != 1.0, ...)
```
`speed` is a `double`. Flutter will render `1.2500000001×` if floating point drift occurs. Should be `speed.toStringAsFixed(2)` or mapped through the speeds list.

### 4.7 Subtitle Alignment (Silent No-Op)

```dart
onTap: () => setState(() => _subAlignIdx = i),
```
The alignment buttons (Left/Center/Right) update the visual highlight but **never call** `widget.onSubPropertyChanged('sub-align', ...)`. Subtitle alignment changes are purely cosmetic in the panel — MPV receives nothing.

### 4.8 QuickSettingsPanel — Rich Exposed UI, All No-Ops

The QSP (`quick_settings_panel.dart`) is 1,685 lines with a sophisticated UI including:
- Picture Profiles picker
- Gesture Map editor entry
- Skip Editor entry  
- Jump To entry
- Speed Presets entry
- Video End Action
- Smart Skip (Silence)
- Zoom & Crop
- Layout Designer
- Sub Sync quick button
- Audio Sync quick button

All of these fire callbacks that `player_screen.dart` provides as `() {}` no-ops. The QSP also manages its own internal `PlayerPrefs` state independently from the parent — creating a **third parallel settings system**.

### 4.9 Cinematic Mode

`_cinematicOpacity` is managed in the player. The cinematic overlay is an empty file. The dimming effect works (via Opacity widget), but there's no actual "cinematic black bars" or theatrical crop effect — just opacity reduction of the UI controls.

---

## PHASE 5 — COMPETITIVE RESEARCH (vs. MX Player Pro, VLC, nPlayer)

### Where RaddFlix Player Exceeds Competitors
| Feature | Advantage |
|---------|-----------|
| Jazz SIM zero-rating | Unique to Pakistani market — killer feature |
| Audio Lab (vocal remover, dialogue boost, normalization) | Rare in mobile players |
| Watch position auto-resume | Table stakes, done well |
| Night mode warm filter | Present, works |
| Merged audio AF pipeline | Technically correct (stacking EQ + reverb + lab) |
| Custom seek bar styles (9 variants) | More than most |

### Where Competitors Win
| Feature | MX Player Pro | VLC | RaddFlix Status |
|---------|--------------|-----|-----------------|
| Real OpenSubtitles integration | ✅ | ✅ | ❌ Stub "coming soon" |
| Subtitle translation | ✅ (via external) | ✅ | ❌ Stub |
| Gesture customization | ✅ | ✅ | ❌ QSP button is no-op |
| Silence/black frame skip | ✅ | ❌ | ❌ QSP button is no-op |
| Screenshot with overlay | ✅ | ✅ | ❌ Package installed, not wired |
| Playlist management | ✅ | ✅ | ❌ Not present |
| Cast / DLNA | ✅ | ✅ | ❌ Not present |
| Watch Party / sync viewing | ❌ | ❌ | ⚠️ Full impl, not integrated |
| Voice control | ❌ | ❌ | ⚠️ Full impl, not integrated |
| HW/SW decoder toggle | ✅ | ✅ | ⚠️ SW audio decoder only (MediaTek safety) |
| Settings persistence | ✅ Full | ✅ Full | ❌ Only ~15 of 100+ prefs survive restart |

---

## PHASE 6 — GAP ANALYSIS

### P0 — Critical (Silent data loss / user trust)

| ID | Gap | Impact |
|----|-----|--------|
| G-01 | Subtitle alignment never applied to MPV | Every time user sets alignment, nothing happens |
| G-02 | Subtitle background color never applied to MPV | Same — silent failure |
| G-03 | Subtitle Customization tab entirely fake | 5 "settings" with no function — erodes user trust |
| G-04 | 99% of player settings lost on close | EQ, reverb, lab, zoom, audio track, subtitle style — all reset. PlayerPrefs class exists but is unused. |

### P1 — High (Visible bugs / broken promise)

| ID | Gap | Impact |
|----|-----|--------|
| G-05 | Navigation settings hardcoded to `true` in Settings panel | Toggle shows wrong state on reopen |
| G-06 | Online subtitle search is permanent "coming soon" | Advertised feature does nothing |
| G-07 | All 8 QSP navigation buttons fire no-ops | Gesture Map, Skip Editor, Jump To, Speed Presets, End Action, Silence Skip, Zoom Crop, Layout Designer |
| G-08 | Audio channel mode resets to Stereo on panel reopen | State/UI mismatch |
| G-09 | Watch Party (476 lines) fully built but zero user access | Major unreleased feature |
| G-10 | Voice Commands fully built but zero user access | Major unreleased feature |

### P2 — Medium (UX polish)

| ID | Gap | Impact |
|----|-----|--------|
| G-11 | Sleep timer countdown frozen while panel open | Misleading countdown |
| G-12 | Speed label may show floating point noise | Ugly display |
| G-13 | "Add Translation" appears twice in subtitle panel | Confusing redundancy |
| G-14 | Settings → Controls tab is pure static text | Users expect toggles |
| G-15 | Smart Enhance is visual-only (no actual video enhancement) | Mislabeled feature |
| G-16 | Subtitle sync precision inconsistency (1 decimal vs 2) | Polish |
| G-17 | `audio_session` package installed but unused | Wasted dependency |
| G-18 | `player_screen_v1_backup.dart` (7,619 lines) committed to main repo | Dead code, repo bloat |
| G-19 | 50+ "series" files unimported | Dead code, maintenance confusion |

### P3 — Low / Architecture

| ID | Gap | Impact |
|----|-----|--------|
| G-20 | Monolith 5,337 lines — full rebuild on every setState | Performance, maintainability |
| G-21 | Riverpod imported but unused — setState everywhere | Architecture debt |
| G-22 | `_AudioTrackPanelState` declared 1,249 lines below its widget | Readability |
| G-23 | Three parallel settings systems (raw prefs + PlayerPrefs + QSP internal) | Future data corruption risk |

---

## PHASE 7 — BUG HUNT

### 🔴 BUG-01: Subtitle Alignment — Silent No-Op
**Location:** `_SubtitlePanelState`, tab 4 (Panel), alignment row  
**Code:**
```dart
onTap: () => setState(() => _subAlignIdx = i),
// ← Missing: widget.onSubPropertyChanged('sub-align', ['left','center','right'][i]);
```
**Severity:** P0 — user changes alignment, MPV ignores it  
**Fix:** Add `widget.onSubPropertyChanged('sub-align', ['left','center','right'][i]);` inside the tap handler

---

### 🔴 BUG-02: Subtitle Background Color — Silent No-Op
**Location:** `_SubtitlePanelState`, tab 1 (Settings), background color picker  
**Code:**
```dart
onTap: () => _showColorPicker(context, _subBgPresets, _subBg, (c) => setState(() => _subBg = c)),
// ← onPick callback only does setState — no onSubPropertyChanged call
```
**Severity:** P0 — background color is visually selected but never applied  
**Fix:** Callback should also call `widget.onSubPropertyChanged('sub-back-color', hex)` after setState

---

### 🔴 BUG-03: Settings Panel Navigation Toggles — Wrong Initial State
**Location:** `_SettingsPanelState` field declarations  
**Code:**
```dart
bool _showSkipBtns = true;       // should be: widget.showSkipBtns (prop not even in widget)
bool _showPrevNextBtns = true;   // same
bool _showSeekPosition = true;   // same
```
**Severity:** P1 — if user disables skip buttons, reopening Settings shows them as enabled  
**Fix:** Add these as widget properties initialized via `initState()` from `widget.*`

---

### 🔴 BUG-04: Subtitle Customization Tab (Tab 5) — Entirely Hardcoded
**Location:** `_SubtitlePanelState.build()`, `if (_tab == 5)` branch  
**Code:**
```dart
const Row(children: [
  Expanded(child: Text('Position', ...)),
  Text('Bottom', ...),     // ← hardcoded const
  Icon(Icons.chevron_right, ...),
]),
// + Shadow: "Outline", Opacity: "100%", Edge padding: "16 px", Line spacing: "1.2×"
// All const — no GestureDetector, no state, no callbacks
```
**Severity:** P0 (trust) — user taps items expecting them to work  
**Fix:** Implement actual shadow style picker, opacity slider, edge padding slider, line spacing control wired to `sub-shadow-color`, `sub-ass-override`, and related mpv properties

---

### 🔴 BUG-05: Audio Channel Mode — State Resets on Panel Reopen
**Location:** `_AudioTrackPanelState` field `int _chIdx = 0;`  
**Issue:** Panel is recreated on every `_openRightPanel()` call. `_chIdx` always starts at 0 (Stereo). The actual MPV filter may be "Mono" but panel shows "Stereo".  
**Severity:** P1 — persistent UI/state mismatch  
**Fix:** Pass current channel mode index as widget property, initialize `_chIdx` from widget in `initState()`

---

### 🔴 BUG-06: Settings Not Persisted — Dual Prefs System Disconnect
**Location:** Architecture-wide  
**Issue:** `PlayerPrefs` in `player_prefs.dart` has 100+ fields for every imaginable player setting. `player_screen.dart` ignores it entirely and uses raw SharedPreferences with ~15 keys. Result: EQ bands, reverb preset, subtitle font/size/bold/color, zoom mode, audio lab state, audio channel mode, accent color choice (partially), progress bar style — **all reset to defaults when the user closes the player**.  
**Severity:** P0 — users configure their preferred audio/subtitle setup and it disappears  
**Fix:** Wire `PlayerPrefs` load in `initState()` and `PlayerPrefs.copyWith().save()` in `_savePrefs()`, replacing the raw SharedPreferences calls

---

### 🟡 BUG-07: Sleep Timer Countdown Frozen in Panel
**Location:** `_QuickShortcutsPanel.build()` — StatelessWidget  
**Code:**
```dart
final remaining = sleepTimerEnd!.difference(DateTime.now());
sleepLabel = 'Sleep ${remaining.inMinutes}m';
```
**Issue:** StatelessWidget with no Timer — value frozen at time panel opened  
**Severity:** P2 — cosmetic but misleading  
**Fix:** Convert to StatefulWidget with `Timer.periodic(Duration(seconds: 30), ...)` calling `setState()`

---

### 🟡 BUG-08: Speed Label Floating Point Noise
**Location:** `_QuickShortcutsPanel.build()`  
**Code:** `'${speed}×'` — e.g. renders "1.2500000000000002×"  
**Severity:** P2  
**Fix:** `'${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 2)}×'` or map through preset list

---

### 🟡 BUG-09: Sub Sync Precision Inconsistency
**Location:** Subtitle panel sync display vs audio track panel sync display  
**Issue:** Subtitle sync shows `${_sync.toStringAsFixed(1)}s` (1 decimal), Audio sync shows `${_sync.toStringAsFixed(2)}s` (2 decimals) — they should match  
**Severity:** P3

---

### 🟡 BUG-10: QSP Stub Callbacks — 8 Dead Buttons
**Location:** `player_screen.dart` → `_openRightPanel(_QuickShortcutsPanel(...))` call  
**Code (in the QSP instantiation):**
```dart
onOpenGestureMap:     () {},    // ← no-op
onOpenSkipEditor:     () {},    // ← no-op
onOpenJumpTo:         () {},    // ← no-op
onOpenSpeedPresets:   () {},    // ← no-op
onOpenEndAction:      () {},    // ← no-op
onOpenSilenceSkip:    () {},    // ← no-op
onOpenZoomCrop:       () {},    // ← no-op
onOpenLayoutDesigner: () {},    // ← no-op
```
**Severity:** P1 — visible buttons that do nothing  
**Fix:** Either implement the feature panels or hide the buttons until implemented

---

### 🟡 BUG-11: `_AudioEffectPanel` Lab State Resets on Reopen
**Location:** `_AudioEffectPanelState` fields  
**Code:**
```dart
bool _labVocal = false;
bool _labDialogue = false;
bool _labNorm = false;
bool _labBass = false;
double _labBassLevel = 0.5;
```
Panel is recreated on every open. Even if vocal remover was enabled, reopening the panel shows it as OFF.  
**Severity:** P1 — same pattern as audio channel mode bug  
**Fix:** Accept lab state as widget properties, initialize from widget in `initState()`

---

## SUMMARY SCORECARD

| Category | Score | Notes |
|----------|-------|-------|
| Core playback engine | 9/10 | Solid media_kit integration, correct MediaTek safety |
| Gesture handling | 9/10 | Complete, well-implemented |
| Audio pipeline | 8/10 | Correct stacking, but lab/EQ state resets on reopen |
| Subtitle system | 5/10 | 3 of 6 tabs broken/fake; 2 silent no-ops; background + alignment never applied |
| Settings persistence | 3/10 | Only 15 keys survive restart; PlayerPrefs class fully written but unused |
| UI truthfulness | 5/10 | ~20-25% of visible UI is non-functional |
| Architecture | 4/10 | Monolith, dual prefs, no MVVM, Riverpod unused |
| Feature completeness | 6/10 | Watch Party + Voice Commands built but invisible to users |
| **Overall** | **6.1/10** | Strong engine, weak persistence + UI honesty |

---

## RECOMMENDED FIX PRIORITY

### Sprint 1 — Restore User Trust (P0 fixes, ~3 days)
1. Wire `PlayerPrefs` to player_screen.dart — save/load all panel state
2. Fix subtitle alignment callback
3. Fix subtitle background color callback  
4. Either implement or hide Subtitle Customization tab
5. Fix Settings panel navigation toggle initialization

### Sprint 2 — Feature Honesty (P1 fixes, ~5 days)
6. Remove or implement online subtitle search (OpenSubtitles API)
7. Remove or implement subtitle translation
8. Hide QSP buttons that have no implementation (or scaffold the panels)
9. Fix lab state persistence (pass into panel, init in initState)
10. Fix audio channel mode state persistence
11. Fix sleep timer countdown (convert to StatefulWidget)

### Sprint 3 — Big Features (P1–P2, ~2 weeks)
12. Wire `watch_party_service.dart` into player (the service is done — needs UI entry point)
13. Wire `voice_commands_service.dart` (the service is done — needs UI entry point + Android native MethodChannel implementation)
14. Implement screenshot via `saver_gallery` (package already installed)
15. Implement silence skip (QSP button exists, service architecture TBD)

### Sprint 4 — Architecture (P3, ~1 week)
16. Extract panels to separate files
17. Replace raw SharedPreferences with full PlayerPrefs
18. Delete `player_screen_v1_backup.dart` and unimported series files
19. Leverage Riverpod for shared player state

---

*End of Deep Hunter God Mode Audit — RaddFlix Player v3.0.0*
