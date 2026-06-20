# RaddFlix Flutter Player — Deep Audit Report
**Date:** June 20, 2026  
**Auditor:** AI Agent (8-Phase Deep Audit)  
**Scope:** Full player subsystem — player_screen.dart, quick_settings_panel.dart, player_prefs.dart, all core/player/ services, all widgets/player/ widgets  
**Platform:** Flutter 3.22.3 · media_kit/MPV (NativePlayer) · Android (Jazz SIM zero-rated)

---

## Table of Contents
1. [Phase 1 — Codebase Discovery](#phase-1--codebase-discovery)
2. [Phase 2 — Feature Inventory](#phase-2--feature-inventory)
3. [Phase 3 — Architecture Review](#phase-3--architecture-review)
4. [Phase 4 — UX/UI Audit](#phase-4--uxui-audit)
5. [Phase 5 — Competitive Research](#phase-5--competitive-research)
6. [Phase 6 — Gap Analysis](#phase-6--gap-analysis)
7. [Phase 7 — Bug Hunt](#phase-7--bug-hunt)
8. [Phase 8 — Improvement Roadmap](#phase-8--improvement-roadmap)

---

## Phase 1 — Codebase Discovery

### Repository Structure

```
raddflix_flutter/lib/
├── screens/
│   └── player_screen.dart              ← 5,105 lines (monolithic god widget)
├── widgets/player/                     ← ~60 widget files
│   ├── quick_settings_panel.dart       1,685 lines
│   ├── seek_bar_painter.dart           ~400 lines (10 seek bar styles)
│   ├── subtitle_overlay.dart           ~250 lines
│   ├── zoom_crop_overlay.dart          134 lines
│   ├── audio_lab_panel.dart
│   ├── audio_lab_sheet.dart
│   ├── audio_mixer_sheet.dart
│   ├── binge_guard.dart
│   ├── bookmark_panel.dart
│   ├── cast_panel.dart
│   ├── chapter_seek_bar.dart
│   ├── cinematic_overlay.dart
│   ├── cinematic_settings_sheet.dart
│   ├── clip_trimmer.dart
│   ├── color_picker_sheet.dart
│   ├── controls_background.dart
│   ├── dual_subtitle_overlay.dart
│   ├── end_action_sheet.dart
│   ├── eq_panel.dart / eq_visualizer.dart
│   ├── film_grain_overlay.dart
│   ├── gesture_hint_overlay.dart
│   ├── gesture_map_sheet.dart
│   ├── immersive_overlay.dart
│   ├── intro_skip_editor.dart
│   ├── jump_to_panel.dart / jump_to_sheet.dart
│   ├── karaoke_overlay.dart
│   ├── media_info_overlay.dart
│   ├── network_speed_overlay.dart
│   ├── picture_profiles_sheet.dart
│   ├── pip_overlay.dart
│   ├── playback_info_overlay.dart
│   ├── player_hud_settings_sheet.dart
│   ├── rage_skip_panel.dart
│   ├── reaction_stamps_overlay.dart
│   ├── scene_bookmarks_panel.dart
│   ├── screenshot_share_sheet.dart
│   ├── silence_skip_sheet.dart
│   ├── sleep_timer_sheet.dart
│   ├── smart_enhance_sheet.dart
│   ├── speed_picker_sheet.dart
│   ├── speed_presets_sheet.dart
│   ├── sync_panel.dart
│   ├── theme_picker_sheet.dart
│   ├── track_badges.dart
│   ├── transparent_player_layer.dart
│   ├── video_enhance_panel.dart
│   ├── video_enhance_suite.dart
│   ├── word_definition_sheet.dart
│   └── zoom_focus_overlay.dart
└── core/player/                        ← ~40 service/controller files
    ├── player_prefs.dart               1,158 lines (full settings model)
    ├── player_prefs_provider.dart
    ├── c_series_gestures.dart          143 lines
    ├── d_series_picture_profiles.dart
    ├── f_series_subtitles.dart         300 lines
    ├── g_series_features.dart          180 lines
    ├── n_series_network.dart
    ├── o_series_content.dart           170 lines
    ├── p_series_parental.dart          164 lines
    ├── q_series_analytics.dart         213 lines
    ├── r_series_social.dart            264 lines
    ├── s_series_accessibility.dart     158 lines
    ├── t_series_themes.dart            201 lines
    ├── u_series_urdu.dart              196 lines
    ├── v_series_video_tools.dart       245 lines
    ├── ab_loop_controller.dart
    ├── ambilight_controller.dart
    ├── audio_lab_service.dart          155 lines
    ├── binge_guard_controller.dart
    ├── color_blind_filter.dart
    ├── dyslexia_subtitle_style.dart
    ├── end_of_video_actions.dart       260 lines
    ├── enhanced_screenshot_service.dart
    ├── frame_navigation_service.dart   175 lines
    ├── haptic_service.dart
    ├── icon_packs.dart                 199 lines
    ├── intro_skip_store.dart           138 lines
    ├── layout_config.dart              193 lines
    ├── layout_prefs.dart
    ├── player_theme.dart
    ├── scene_bookmark_store.dart
    ├── shared_bookmarks_service.dart   304 lines
    ├── smart_enhance.dart
    ├── smart_intro_store.dart
    ├── smart_skip_service.dart         242 lines
    ├── subtitle_style.dart             227 lines
    ├── video_look_filter.dart
    ├── watch_party_service.dart        476 lines
    └── word_dict.dart                  475 lines
└── core/services/
    ├── jazzdrive_service.dart          608 lines (Oracle API client)
    ├── notification_service.dart
    ├── background_sync_service.dart
    ├── connectivity_sync_service.dart
    ├── dnd_service.dart
    ├── poster_service.dart             176 lines
    ├── usage_service.dart
    ├── voice_commands_service.dart     241 lines
    ├── wake_lock_service.dart
    └── app_update_service.dart
```

### Key Technology Stack
| Layer | Technology |
|---|---|
| Framework | Flutter 3.22.3 |
| Video engine | media_kit + MPV (NativePlayer) |
| Video surface | `androidAttachSurfaceAfterVideoParameters: false` (CRITICAL for HW decode) |
| Settings persistence | SharedPreferences |
| Screen brightness | screen_brightness package |
| Animation | flutter_animate |
| Backend API | Oracle Cloud VM (92.4.95.252:5000, v3.0.0) |

### Scale Metrics
| File | Lines |
|---|---|
| player_screen.dart | 5,105 |
| quick_settings_panel.dart | 1,685 |
| player_prefs.dart | 1,158 |
| jazzdrive_service.dart | 608 |
| watch_party_service.dart | 476 |
| **Total player subsystem** | **~15,000+** |

---

## Phase 2 — Feature Inventory

### 2A — Confirmed Working Features (code verified)

#### Core Playback
| # | Feature | Evidence |
|---|---|---|
| 1 | Video playback via MPV NativePlayer | `_initPlayer()`, `player.open(Media(...))` |
| 2 | HW/SW decoder toggle | `setProperty('hwdec', ...)` — NEVER mid-play (guarded by `_videoOpened`) |
| 3 | Playback speed control | `NativePlayer.setProperty('speed', v.toString())` |
| 4 | Resume watch position | `_saveWatchPos()` + `prefs.getDouble(key)` on init |
| 5 | Episode prev/next navigation | `_prevEpisode()` / `_nextEpisode()` with countdown overlay |
| 6 | Auto-play next episode | Countdown + auto-advance after configurable seconds |
| 7 | A-B loop | `ab_loop_controller.dart` + MPV `ab-loop-a/b` properties |
| 8 | Frame step | `frame_navigation_service.dart` |

#### Gesture Controls
| # | Feature | Evidence |
|---|---|---|
| 9 | Swipe brightness (left half) | `c_series_gestures.dart` |
| 10 | Swipe volume (right half) | `c_series_gestures.dart` |
| 11 | Double-tap seek (L=rewind, R=forward) | `_onDoubleTap()` in player_screen |
| 12 | Long-press 2× speed | `_onLongPressStart()` → `setProperty('speed', '2.0')` |
| 13 | Pinch-to-zoom | `pinchZoomEnabled` in PlayerPrefs |
| 14 | Rage skip | `rage_skip_panel.dart` |

#### Audio
| # | Feature | Evidence |
|---|---|---|
| 15 | Audio track selection | `_AudioTrackPanel` with `RadioListTile<AudioTrack>` |
| 16 | AV sync (audio delay) | `_sync += 0.1` → `widget.onSyncChanged(±0.1)` → MPV `audio-delay` |
| 17 | SW audio decoder toggle | `_useSW` → `onSWDecoderChanged` |
| 18 | 5-band EQ | Bands: 60Hz/230Hz/910Hz/3.6k/14k via `lavfi=equalizer=...` |
| 19 | Reverb presets | `_ReverbSelector` → MPV `aecho` filter |
| 20 | Audio Lab: Vocal Remover | `_applyLabAf()` → MPV `pan` filter for center-channel phase cancel |
| 21 | Audio Lab: Dialogue Boost | `anequalizer` 2–5kHz boost |
| 22 | Audio Lab: Audio Normalization | MPV `dynaudnorm` |
| 23 | Audio Lab: Bass Boost | MPV `equalizer=...` low-freq boost with level slider |
| 24 | L/R Balance | `pan=stereo|c0=...|c1=...` filter |
| 25 | Mute toggle | `player.setVolume(0)` |

#### Subtitles
| # | Feature | Evidence |
|---|---|---|
| 26 | Subtitle overlay | `subtitle_overlay.dart` |
| 27 | Dual subtitle overlay | `dual_subtitle_overlay.dart` |
| 28 | Subtitle font/size/color/outline | `PlayerPrefs.subtitleFontSize` etc. |
| 29 | Subtitle position offset | `subtitleVerticalOffset` |
| 30 | Subtitle encoding | `subtitleEncoding` pref |
| 31 | Subtitle timing offset (delay) | `subtitleTimingOffsetMs` |
| 32 | Word dictionary lookup | `word_dict.dart` + `word_definition_sheet.dart` |
| 33 | Karaoke subtitle overlay | `karaoke_overlay.dart` |

#### Video
| # | Feature | Evidence |
|---|---|---|
| 34 | Aspect ratio / crop modes | `ZoomCropOverlay` — 8 modes (Original/Fill/Fit/Stretch/16:9/4:3/21:9/1:1) |
| 35 | Zoom (1×–3×) | `ZoomCropOverlay` slider |
| 36 | Rotate video | Cycles 0°→90°→180°→270° via `onRotateVideo` |
| 37 | Smart Enhance | `smart_enhance.dart` + `smart_enhance_sheet.dart` |
| 38 | Night mode (warm overlay) | `nightModeEnabled` + warmth slider |
| 39 | Screen brightness | `ScreenBrightness().setScreenBrightness(v)` |
| 40 | Film grain overlay | `film_grain_overlay.dart` |
| 41 | Picture profiles | `d_series_picture_profiles.dart` |
| 42 | Video look filter | `video_look_filter.dart` |
| 43 | Color blind filter | `color_blind_filter.dart` |
| 44 | Ambilight glow border | `ambilight_controller.dart` + `ambilight_glow_border.dart` |
| 45 | Cinematic overlay | `cinematic_overlay.dart` |
| 46 | Transparent player layer | `transparent_player_layer.dart` |

#### UI / Controls
| # | Feature | Evidence |
|---|---|---|
| 47 | Quick settings panel (5 tabs) | `quick_settings_panel.dart` — Style/Screen/Controls/Navigation/Text |
| 48 | Theme picker | `theme_picker_sheet.dart` + `t_series_themes.dart` |
| 49 | Color picker (accent) | `color_picker_sheet.dart` |
| 50 | Seek bar style picker | 10 styles in `seek_bar_painter.dart` |
| 51 | Button shape picker | Circle/Squircle/Rounded/Sharp/Pill |
| 52 | Icon pack picker | `icon_packs.dart` |
| 53 | One-handed mode | Shifts controls to lower screen half |
| 54 | Screen lock | `_isLocked` → overlays gesture zone |
| 55 | Sleep timer | 15/30/45/60/90 min options |
| 56 | Binge guard | `binge_guard_controller.dart` |
| 57 | Playback info overlay | `playback_info_overlay.dart` |
| 58 | Network speed overlay | `network_speed_overlay.dart` |
| 59 | Media info overlay | `media_info_overlay.dart` |
| 60 | Jump-to panel | `jump_to_panel.dart` |
| 61 | Scene bookmarks | `scene_bookmark_store.dart` + panel |
| 62 | Screenshot share | `enhanced_screenshot_service.dart` |
| 63 | Cast panel | `cast_panel.dart` |
| 64 | PiP overlay | `pip_overlay.dart` |
| 65 | Clip trimmer | `clip_trimmer.dart` |
| 66 | Intro skip editor | `intro_skip_store.dart` |
| 67 | Chapter seek bar | `chapter_seek_bar.dart` |
| 68 | Reaction stamps overlay | `reaction_stamps_overlay.dart` |
| 69 | Voice commands | `voice_commands_service.dart` |
| 70 | Watch party | `watch_party_service.dart` |
| 71 | Parental controls | `p_series_parental.dart` |
| 72 | Accessibility (dyslexia fonts, color blind) | `s_series_accessibility.dart` |
| 73 | Urdu language support | `u_series_urdu.dart` |
| 74 | Analytics | `q_series_analytics.dart` |
| 75 | Social features | `r_series_social.dart` |
| 76 | Shared bookmarks | `shared_bookmarks_service.dart` |

### 2B — Fake / Stub Features (confirmed non-functional)

| # | Feature | Location | What Happens | Severity |
|---|---|---|---|---|
| F1 | Online subtitle search | `_fetchOnlineSubtitles()` in player_screen | Awaits 800ms then throws "Set OPENSUBTITLES_API_KEY env variable" error regardless of input | HIGH |
| F2 | Subtitle translation | Subtitle panel tab | Shows language list; `onTap: () => Navigator.of(ctx).pop()` — selects nothing, does nothing | HIGH |
| F3 | Subtitle "Customization" tab (tab 5) | `_SubtitlePanel` | 5 hardcoded static rows, zero callbacks wired | MEDIUM |
| F4 | Subtitle playback speed | `_SubtitlePanel` speed slider | Updates `_speed` in local state; `onSpeedChanged` bubbles up to `_PlayerScreenState._subSpeed` only; **no `setProperty('sub-speed', ...)` ever called on MPV** | HIGH |
| F5 | Battery level toggle | Settings > Screen tab | `value: true, onChanged: (_) {}` — hardcoded ON, user cannot toggle | MEDIUM |
| F6 | Controls tab "Touch action" | `_SettingsPanel._buildControlsTab()` | Static `Text('Pause / resume')` — no dropdown, no pref | LOW |
| F7 | Controls tab "Auto lock" | Same | Static text description only | LOW |
| F8 | Nav settings (skip/prevnext/position buttons) | `_SettingsPanel._buildNavigationTab()` | `onChanged: (v) => setState(...)` — state updated but no persistence callback and no effect on actual UI | MEDIUM |
| F9 | Audio channel mode | `_AudioTrackPanel` | `int _chIdx = 0` declared **inside `StatefulBuilder.builder`** — resets to 0 on every rebuild; cycling appears to work but reverts instantly | CRITICAL (bug) |
| F10 | Picture Profiles sheet | `picture_profiles_sheet.dart` | Likely stub (imported but functionality uncertain) | UNKNOWN |

---

## Phase 3 — Architecture Review

### 3.1 — The Monolithic God Widget Problem

`player_screen.dart` is 5,105 lines and the single `_PlayerScreenState` class manages:

- **~200+ state variables** — booleans, timers, streams, controllers all crammed into one state class
- **All MPV interactions** — every `setProperty`, `open`, `seek` call
- **All UI rendering** — build method delegates to dozens of inline sub-widget builders
- **All lifecycle** — `initState`, `dispose`, stream subscriptions, timer management
- **All business logic** — episode navigation, watch position, subtitle handling

**Impact:** Any change touches the entire widget tree. Risk of accidental regression is extremely high. Hot reload cycles are slow. Code review is near impossible.

### 3.2 — Timer Architecture

```
_clockDisplayTimer  → Timer.periodic(30s)   ← BUG: should be 10s (per TASK_LOG)
_posTimer           → Timer.periodic(10s)   → _saveWatchPos()
_savePositionTimer  → Timer.periodic(10s)   → _saveCurrentPosition()
_autoRetryTimer     → Timer.periodic(1s)    → retry logic
_scanLineTimer      → Timer.periodic(...)   → scan line effect
```

There are **two separate watch-position timers** (`_posTimer` and `_savePositionTimer`) running simultaneously at 10s — likely a refactoring artifact causing **double-writes to SharedPreferences** every 10 seconds.

### 3.3 — MPV Interaction Rules (Fragile Convention)

The following rules are documented in BUG_TRACKER.md and enforced only by convention, not code:

```dart
// MUST be set before every player.open()
_videoOpened = true;
await player.open(Media(url));
// NEVER: setProperty('vf', ...) mid-play
// NEVER: change hwdec mid-play
// ONLY: NativePlayer.setProperty('speed', v.toString()) for speed
```

There is **no compile-time or runtime enforcement**. A developer unfamiliar with these rules will break HW decode or crash playback.

### 3.4 — No State Management

Zero use of BLoC, Riverpod, Provider, or any observable pattern. All state is raw `setState()`. This means:
- No way to observe player state from outside `_PlayerScreenState`
- No testability
- Every rebuild re-evaluates all 200+ state variables

### 3.5 — PlayerPrefs Model

`player_prefs.dart` (1,158 lines) is a well-structured immutable data class with `copyWith()` and `SharedPreferences` serialization. This is the **best-architected part** of the codebase — a clean model layer. However, it is not connected to any reactive provider, so consumers must poll or rely on callback chains.

### 3.6 — Service / Series Naming Convention

Files follow a `x_series_*.dart` naming pattern (c_series_gestures, d_series_picture_profiles, etc.). This is a custom naming scheme with no documentation explaining the series letters. Onboarding new developers is impeded.

### 3.7 — Dependency on Oracle VM

The entire backend runs on a single Oracle Cloud VM at `92.4.95.252:5000`. There is no load balancing, no CDN, and no fallback. Single point of failure for all Pakistani Jazz SIM users.

---

## Phase 4 — UX/UI Audit

### 4.1 — Dual Settings UI (Redundancy Confusion)

There are **two overlapping settings systems**:

1. **`_SettingsPanel`** (inside player_screen.dart, ~lines 4365–4843) — 4-tab panel (Style/Screen/Controls/Navigation) instantiated as a `_panel == 'settings'` case
2. **`QuickSettingsPanel`** (quick_settings_panel.dart, 1,685 lines) — 5-tab sheet (Style/Screen/Controls/Navigation/Text) opened via `showModalBottomSheet`

Both expose Style, Screen, Controls, and Navigation tabs with **partially overlapping settings**. A user tapping "Settings" in one context gets a different UI than in another context. Persistence behavior differs between the two.

### 4.2 — Sleep Timer Display Bug

In `_QuickShortcutsPanel.build()`:
```dart
final remaining = sleepTimerEnd!.difference(DateTime.now());
sleepLabel = 'Sleep ${remaining.inMinutes}m';
```
This is calculated **once at build time**. The label shows a static remaining time and never updates while the panel is open. User sees e.g. "Sleep 29m" for the full duration of the panel.

### 4.3 — Duplicate Smart Enhance Toggle

In `_QuickShortcutsPanel`, Smart Enhance appears **twice**:
1. In the `_ShortcutGrid` Row 3 (shortcut tile)
2. As a standalone `ListTile` with `Switch` below the grid

Both wire to the same `onSmartEnhanceToggle` callback, so they stay in sync, but the visual redundancy is confusing.

### 4.4 — Speed Dialog Limited to 6 Presets

The speed picker in Quick Shortcuts shows `[0.5, 0.75, 1.0, 1.25, 1.5, 2.0]`. No custom input. Competitors (MX Player, VLC) offer 0.25× increments and custom entry. The `speed_presets_sheet.dart` exists separately — unclear if it exposes more options.

### 4.5 — Subtitle Panel Tab 5 "Customization" is Empty

`_SubtitlePanel` has 5 tabs. Tab 5 ("Customization") renders hardcoded static rows with no callbacks. Users who tap it expecting functionality receive a silently non-functional screen.

### 4.6 — Controls Tab Shows Only Prose

`_SettingsPanel._buildControlsTab()` has:
- "Touch action" → static `Text('Pause / resume')`
- "Lock mode" → static `Text('Auto lock controls when video plays')`

These read like placeholder documentation, not interactive controls.

### 4.7 — Navigation Settings Not Persisted

In `_SettingsPanel._buildNavigationTab()`, three `SwitchListTile` widgets:
- "Forward/backward buttons" → `onChanged: (v) => setState(() => _showSkipBtns = v)`
- "Previous/next episode buttons" → `onChanged: (v) => setState(() => _showPrevNextBtns = v)`
- "Show position while seeking" → `onChanged: (v) => setState(() => _showSeekPosition = v)`

None of them call any persistence callback. Settings are lost on panel close.

### 4.8 — Channel Mode Resets Instantly

See Bug #B1. The audio channel mode appears to cycle on tap but instantly resets because `_chIdx` is declared inside the builder function.

### 4.9 — Subtitle Translation Silently Fails

Users who open Subtitles → Translation, select a language, and tap it are returned to the previous screen with no feedback that nothing happened. No toast, no error, no indication it's not implemented.

### 4.10 — Online Subtitle Search Shows Misleading Error

"Set OPENSUBTITLES_API_KEY env variable" is a developer-facing message shown to end users after 800ms of fake loading. No user-friendly fallback.

### 4.11 — Good UX Patterns Observed

- Seek bar preview thumbnails (Chapter seek bar)
- A-B loop with clear visual states ("A set" / "●")
- Sleep timer with remaining time in label
- EQ band values shown as `+3` / `-2` below sliders
- Accent color glow on seek bar (BoxShadow)
- Panel animations via `flutter_animate` (slideY + fadeIn)
- One-handed mode (innovative for video apps)

---

## Phase 5 — Competitive Research

### 5.1 — Competitive Landscape (Video Player Apps)

| App | Platform | Key Differentiators |
|---|---|---|
| MX Player | Android | Industry standard; hardware decode, gestures, subtitle codecs, codec pack |
| VLC for Android | Android | Open source, every format, network streams, chromecast |
| Infuse (iOS) | iOS | Polish, metadata fetching, Trakt sync, AirPlay, direct play |
| Vimu Player | Android/TV | TV-optimized, game controller support |
| nPlayer | iOS | All-format, precise subtitle control, cloud storage |
| Kodi | Cross-platform | Plugin ecosystem, IPTV, PVR, full home theater |

### 5.2 — What RaddFlix Does Better Than Competitors

1. **Jazz SIM zero-rated streaming** — unique to Pakistani market, no competitor has this
2. **Audio Lab** (Vocal Remover, Dialogue Boost, Normalization, Bass Boost) — most players offer EQ only; this is more advanced
3. **One-handed mode** — not seen in MX Player, VLC, or Infuse
4. **L/R Balance** — rare in mobile video players
5. **Reverb presets** on video player audio — unique feature
6. **10 seek bar styles** — more visual customization than any competitor
7. **Theme + accent color system** — full visual personalization rare in video players
8. **Binge guard** — promotes healthy viewing habits; seen in Netflix web but not in local players
9. **Watch party** — real-time synchronized playback; only seen in Rave/Teleparty for streaming services
10. **Reaction stamps** — social layer on a local player, highly novel

### 5.3 — Where Competitors Are Stronger

| Gap | MX Player | VLC | RaddFlix |
|---|---|---|---|
| Subtitle codecs | SSA/ASS full rendering | Good | Basic |
| Network stream protocols | HLS/RTSP/SMB | Excellent | HTTP only |
| Chromecast | Yes | Yes | Cast panel (status unknown) |
| TV/remote support | Yes | Yes | No |
| Multiple audio language auto-selection | Yes | Yes | Yes (autoSelectAudioByLocale) |
| Custom speed (any value) | Yes | Yes | 6 presets only |
| Subtitle download (real) | Yes (integrated) | No | Fake/stub |
| Playlist management | Basic | Full | None visible |
| SMB/NFS/FTP browsing | Yes | Yes | No |

---

## Phase 6 — Gap Analysis

### 6.1 — Critical Gaps (P0 — Fix Before Next Release)

| ID | Gap | User Impact |
|---|---|---|
| G1 | Sub-speed never reaches MPV | Users think subtitle speed changes but nothing happens |
| G2 | Channel mode resets on rebuild | Audio channel switching is completely broken |
| G3 | Clock timer at 30s instead of 10s | Clock display up to 30s stale |
| G4 | Battery toggle hardcoded | Cannot disable battery display |
| G5 | Subtitle translation silently does nothing | Users misled; looks like a bug |
| G6 | Nav settings not persisted | Settings lost every time panel closes |

### 6.2 — High Priority Gaps (P1 — Next Sprint)

| ID | Gap | User Impact |
|---|---|---|
| G7 | Online subtitle search exposes API key error to users | Embarrassing UX; should say "coming soon" |
| G8 | Subtitle Customization tab entirely stub | Empty panel erodes trust |
| G9 | Dual settings systems (two overlapping UIs) | Confusing navigation, inconsistent behavior |
| G10 | Two watch-position timers running simultaneously | Double SharedPreferences writes, potential data race |
| G11 | No custom speed input | Power users limited to 6 presets |
| G12 | Sleep timer label not live-updating | Timer feels broken |

### 6.3 — Medium Priority Gaps (P2 — This Quarter)

| ID | Gap | User Impact |
|---|---|---|
| G13 | No playlist/queue management | Can't queue multiple titles |
| G14 | No real subtitle download | Major feature gap vs MX Player |
| G15 | No Chromecast integration (confirmed) | Growing smart TV market |
| G16 | No TV/game-controller support | TV side-loading growing in PK market |
| G17 | Smart Enhance duplicate toggle | Minor UX confusion |
| G18 | Controls tab is all static text | Dead settings UI |
| G19 | No custom speed entry | Power user feature |
| G20 | No SMB/NFS browsing | Local network playback gap |

### 6.4 — Low Priority Gaps (P3 — Future)

| ID | Gap | User Impact |
|---|---|---|
| G21 | No `x_series` naming documentation | Developer experience |
| G22 | No state management (BLoC/Riverpod) | Maintainability; no direct user impact |
| G23 | Single Oracle VM backend | Reliability risk for all users |
| G24 | No Trakt/Simkl sync | Niche but power users want it |
| G25 | Speed presets limited to 0.5–2.0 | Some users want 3×, 4× |

---

## Phase 7 — Bug Hunt

### CRITICAL Bugs

#### B1 — Audio Channel Mode Resets Instantly (CRITICAL)
**File:** `player_screen.dart` ~line 4962  
**Code:**
```dart
Builder(builder: (ctx) {
  const modes = ['Stereo', 'Mono', 'Left only', 'Right only'];
  return StatefulBuilder(builder: (ctx, setSt) {
    int _chIdx = 0;   // ← BUG: declared inside builder, resets every rebuild
    return ListTile(
      trailing: Text(modes[_chIdx], ...),
      onTap: () {
        setSt(() => _chIdx = (_chIdx + 1) % modes.length);  // increments then immediately resets
        widget.onChannelModeChanged(filters[_chIdx]);        // always sends filters[0] = ''
      },
    );
  });
}),
```
**Effect:** Every tap increments `_chIdx` to 1, calls `setSt()` which rebuilds, but since `_chIdx = 0` is always re-initialized, the trailing text shows "Stereo" and `filters[0] = ''` (empty/stereo filter) is sent. The mode **never actually changes**.  
**Fix:** Move `_chIdx` to be a field of `_AudioTrackPanelState`, not declared inside a builder.

---

#### B2 — Sub-Speed Never Sent to MPV (CRITICAL)
**File:** `player_screen.dart` lines 175, 2596–2599  
**Code:**
```dart
double _subSpeed = 1.0;                          // state var
// SubtitlePanel callback:
onSpeedChanged: (v) => setState(() => _subSpeed = v),  // updates state
// Nowhere in player_screen.dart is there:
// player.setProperty('sub-speed', ...) or similar
```
**Effect:** The subtitle speed slider in the subtitle panel appears responsive (moves, shows value) but has **zero effect on subtitle playback timing** in MPV.  
**Fix:** In the `onSpeedChanged` callback, add `(player.platform as NativePlayer).setProperty('sub-speed', v.toString())`.

---

### HIGH Bugs

#### B3 — Clock Display Timer at 30s (Wrong Interval)
**File:** `player_screen.dart` line 280  
**Code:**
```dart
_clockDisplayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
  if (mounted) setState(() => _clockStr = _fmtClock());
});
```
**TASK_LOG documents this should be 10s.** The clock in the player title area can be up to 30 seconds stale.  
**Fix:** Change `seconds: 30` → `seconds: 10`.

---

#### B4 — Double Watch-Position Timers
**File:** `player_screen.dart` lines 420, 779  
**Code:**
```dart
_posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());
// ...later in initState or _initPlayer:
_savePositionTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveCurrentPosition());
```
Two separate timers both writing watch position every 10 seconds. This doubles SharedPreferences writes and risks a data race if `_saveWatchPos()` and `_saveCurrentPosition()` write different keys or values for the same content.  
**Fix:** Consolidate to a single timer with a single save method. Cancel the duplicate in `dispose()`.

---

#### B5 — Battery Toggle Hardcoded
**File:** `player_screen.dart` ~line 4622  
**Code:**
```dart
SwitchListTile(
  title: const Text('Show battery level', ...),
  value: true,         // ← hardcoded
  onChanged: (_) {},   // ← no-op
  ...
),
```
**Effect:** User cannot disable battery display. Toggle appears interactive but does nothing.  
**Fix:** Wire to `PlayerPrefs.showBatteryLevel` (add if missing) with proper persistence.

---

#### B6 — Navigation Settings Lost on Panel Close
**File:** `player_screen.dart` `_buildNavigationTab()`  
**Code:**
```dart
SwitchListTile(
  value: _showSkipBtns,
  onChanged: (v) => setState(() => _showSkipBtns = v),  // no persist callback
  ...
),
```
Three toggles affected: showSkipBtns, showPrevNextBtns, showSeekPosition. Changes survive only while the settings panel is open.  
**Fix:** Add persistence callbacks (e.g., `widget.onShowSkipBtnsChanged(v)`) and save to PlayerPrefs.

---

### MEDIUM Bugs

#### B7 — Subtitle Translation Silently No-ops
**File:** `player_screen.dart` subtitle panel translate section  
**Code:** `onTap: () => Navigator.of(ctx).pop()`  
**Effect:** User selects a language, panel closes, nothing happens — no feedback, no error.  
**Fix (short term):** Show a `SnackBar('Subtitle translation coming soon')`. Long term: implement.

---

#### B8 — Online Subtitle Search Shows Developer Error to Users
**File:** `player_screen.dart` `_fetchOnlineSubtitles()`  
**Code:**
```dart
await Future.delayed(const Duration(milliseconds: 800));
throw Exception('Set OPENSUBTITLES_API_KEY env variable');
```
**Effect:** After 800ms of fake loading, users see an exception message.  
**Fix (short term):** Replace with `showDialog` saying "Online subtitle search is coming soon." Remove fake delay.

---

#### B9 — Sleep Timer Label Stale While Panel Open
**File:** `player_screen.dart` `_QuickShortcutsPanel.build()`  
**Code:**
```dart
final remaining = sleepTimerEnd!.difference(DateTime.now());
sleepLabel = 'Sleep ${remaining.inMinutes}m';
```
Calculated once at build time. Does not update while panel is visible.  
**Fix:** Use a `StatefulWidget` for the sleep label with its own 1-minute timer, or lift a ticker into the panel.

---

### LOW Bugs

#### B10 — Subtitle Customization Tab is Dead UI
All 5 rows in Subtitle Panel Tab 5 appear interactive but have no callbacks. Represents misleading UI.

#### B11 — `_ReverbSelectorState` Class Body Truncated
`_ReverbSelectorState` declaration appears at line 5076 but the file ends at 5105. The `build()` method was not visible in the read window — the file may be genuinely truncated or the state class exists in another file. Needs verification.

#### B12 — Smart Enhance Duplicate Control
In `_QuickShortcutsPanel`, Smart Enhance appears in both the shortcuts grid and as a standalone ListTile. The grid item's label is "Smart View" while the ListTile says "Smart Enhance" — inconsistent naming for the same feature.

---

## Phase 8 — Improvement Roadmap

### Sprint 1 — Critical Bug Fixes (1 week, ~14 story points)

| ID | Task | Effort | Files |
|---|---|---|---|
| R1 | Fix channel mode bug (move `_chIdx` out of builder) | 1h | player_screen.dart:4962 |
| R2 | Wire sub-speed to MPV `setProperty('sub-speed', ...)` | 1h | player_screen.dart |
| R3 | Fix clock timer 30s → 10s | 15min | player_screen.dart:280 |
| R4 | Fix battery toggle (wire to PlayerPrefs) | 2h | player_screen.dart + player_prefs.dart |
| R5 | Fix nav settings persistence (3 toggles) | 2h | player_screen.dart |
| R6 | Consolidate duplicate watch-position timers | 2h | player_screen.dart |
| R7 | Replace subtitle translation no-op with "coming soon" snackbar | 30min | player_screen.dart |
| R8 | Replace online subtitle fake error with friendly message | 30min | player_screen.dart |
| R9 | Fix sleep timer label to live-update | 2h | player_screen.dart |
| R10 | Remove or implement Subtitle Customization tab | 1h | player_screen.dart |

**Estimated: 12–14 hours of focused work**

---

### Sprint 2 — UX Polish (2 weeks)

| ID | Task | Effort |
|---|---|---|
| R11 | Unify dual settings UIs — deprecate `_SettingsPanel` inline, promote QuickSettingsPanel as single source of truth | 3 days |
| R12 | Add custom speed entry field (alongside 6 presets) | 4h |
| R13 | Fix Smart Enhance naming inconsistency (grid: "Smart View" → "Smart Enhance") | 30min |
| R14 | Remove duplicate Smart Enhance from QuickShortcutsPanel ListTile | 30min |
| R15 | Implement Controls tab properly (touch action dropdown, lock mode setting) | 1 day |
| R16 | Add Subtitle Translation skeleton with proper "coming soon" UI | 2h |
| R17 | Improve sleep timer label with live countdown in panel header | 3h |

---

### Sprint 3 — Architecture Refactor (1 month, ongoing)

| ID | Task | Effort | Priority |
|---|---|---|---|
| R18 | Extract `_PlayerCoreController` — all MPV calls, state, timers | 2 weeks | P1 |
| R19 | Introduce Riverpod (or BLoC) for player state | 1 week | P1 |
| R20 | Split player_screen.dart into: PlayerScreen (shell) + PlayerControls (UI) + PlayerGestures (input) | 2 weeks | P2 |
| R21 | Document and enforce MPV interaction rules in code (assertions, not just comments) | 3 days | P1 |
| R22 | Add PlayerPrefs reactive provider | 3 days | P1 |
| R23 | Document `x_series` naming convention in CONTRIBUTING.md | 1 day | P3 |

---

### Sprint 4 — Feature Completion (1–2 months)

| ID | Feature | Effort | Notes |
|---|---|---|---|
| R24 | Real subtitle download (OpenSubtitles API) | 2 weeks | Need API key management |
| R25 | Subtitle translation (LibreTranslate or Google Translate API) | 1 week | |
| R26 | Chromecast integration (flutter_cast_framework) | 2 weeks | |
| R27 | Custom playback speed entry | 3 days | |
| R28 | Playlist/queue management | 3 weeks | |
| R29 | Trakt.tv sync | 1 week | |

---

### Sprint 5 — Infrastructure (Ongoing)

| ID | Task | Priority |
|---|---|---|
| R30 | Oracle VM redundancy (load balancer + 2nd instance) | P0 |
| R31 | CDN for video content (Jazz CDN / Cloudflare) | P1 |
| R32 | Player analytics pipeline (q_series_analytics.dart → real backend) | P2 |
| R33 | CI/CD pipeline with automated APK builds | P2 |
| R34 | Unit tests for PlayerPrefs serialization | P2 |
| R35 | Widget tests for critical player interactions | P3 |

---

## Summary Scorecard

| Dimension | Score | Notes |
|---|---|---|
| **Feature Breadth** | 9/10 | 75+ features, many innovative |
| **Feature Depth** | 5/10 | ~10 features are stubs/broken |
| **Code Quality** | 4/10 | Monolith, no state mgmt, fragile conventions |
| **UX Consistency** | 6/10 | Good visual design, but 2 overlapping settings UIs |
| **Bug Count** | 12 confirmed | 2 Critical, 4 High, 4 Medium, 2 Low |
| **Architecture** | 3/10 | 5,105-line god widget, no tests, no state mgmt |
| **Competitive Position** | 8/10 | Jazz zero-rating + Audio Lab are strong moats |
| **Reliability Risk** | HIGH | Single Oracle VM, no redundancy |

### Top 5 Actions Right Now

1. **Fix B1** (channel mode reset) — 1 hour, completely broken feature
2. **Fix B2** (sub-speed never sent to MPV) — 1 hour, silent failure
3. **Fix B8** (replace OpenSubtitles error with friendly UI) — 30 min, embarrassing UX
4. **Fix B7** (subtitle translation no-op feedback) — 30 min, user trust
5. **Fix B6** (nav settings persistence) — 2 hours, user frustration

---

*Report generated: June 20, 2026*  
*Audit scope: Full player subsystem (~15,000 lines across 100+ files)*  
*Player file read in full: player_screen.dart (5,105 lines, 100% coverage)*
