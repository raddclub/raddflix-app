# TASK_LOG.md — Agent Session History

> Newest session at top. Every agent must append here after completing work.
> Format: `## Session YYYY-MM-DD` followed by bullets.

---

## Session 2026-06-07 (TASK-028 — player_prefs.dart schema audit)

**Agent:** Replit Agent (main branch)
**Task:** Full audit of `player_prefs.dart` for schema inconsistencies — missing fields, key collisions, default mismatches, duplicate fields. Also resolve BACKLOG-01 (`cinematicOpacity`).
**Commit:** `1b9b2e8f`

### Bugs found and fixed

| ID | Severity | Bug | Fix |
|----|----------|-----|-----|
| P01 | 🔴 HIGH | `endAction` and `endOfVideoAction` both saved/loaded from key `player_end_action` — `Future.wait()` runs saves concurrently so one field's value silently overwrites the other | Gave `endAction` its own isolated key `player_end_action_v2` in both `load()` and `save()` |
| P03 | 🟠 MED | `reactionsEnabled` default mismatch: constructor = `false`, `load()` = `true` — fresh install gets `true` but `const PlayerPrefs()` gives `false` | Changed `load()` fallback to `false` |
| P04 / BACKLOG-01 | 🟠 MED | `cinematicOpacity` was a local `_State` variable resetting to `0.5` on every launch — user's cinematic overlay setting was never persisted | Added `final double cinematicOpacity` to `PlayerPrefs` (key `player_cinematic_opacity`, default `0.5`) across all 5 sections (field, constructor, copyWith, load, save). Wired `player_screen.dart` to restore from prefs in `_loadPrefs()` and persist on slider change via `copyWith(cinematicOpacity: v) + save()` |

### False positive (audit script bug)

| ID | Original assessment | Reality |
|----|---------------------|---------|
| P02 | `transparentModeFrosted` missing from `save()` | Was already present in `save()` (line 1058); the audit script's regex missed it due to whitespace variation |

### Duplicate-field schema debt documented (no fix — no key collisions, need widget-coverage audit first)

| Pair | Fields | Status |
|------|--------|--------|
| D01 | `endOfVideoAction` vs `endAction` | Keys now different (P01 fixed); conceptually duplicate |
| D02 | `dualSubtitleEnabled` vs `dualSubtitlesEnabled` | Different keys; `dualSubtitleEnabled` confirmed used in player_screen.dart |
| D03 | `wakeTimeoutMins` vs `wakeLockTimeoutMinutes` | Different keys; both default 0 |
| D04 | `pictureProfile` ('natural') vs `pictureProfileId` ('standard') | Different keys AND different defaults — most dangerous |
| D05 | `gestureActionMapJson` vs `gestureMapData` | Different keys; `gestureActionMapJson` used in player_screen.dart |
| D06 | `customSpeedPresetsJson` (empty/JSON) vs `speedPresets` (CSV) | Different keys AND different formats |

### Files changed

| File | Change |
|------|--------|
| `raddflix_flutter/lib/core/player/player_prefs.dart` | P01 key fix, P03 default fix, P04 cinematicOpacity field added |
| `raddflix_flutter/lib/screens/player_screen.dart` | BACKLOG-01: restore + persist `cinematicOpacity` in `_loadPrefs` and `_showCinematicSettings` |
| `agent-hub/TASKS.md` | TASK-028 added to archive; BACKLOG-01 cleared |
| `agent-hub/history/TASK_LOG.md` | This session appended |

---

## Session 2026-06-07 (Pass 4 — full re-audit)

**Agent:** Replit Agent (main branch)
**Task:** TASK-025 — Full 6,252-line re-audit after Pass 3; find and fix any remaining bugs

### Bugs found and fixed

| ID | Severity | Fix |
|----|---------|-----|
| BUG-P-NEW-06 | MEDIUM | `_openVideoEnhanceSuite` `onChanged`: cinematic mode could only be toggled ON, never OFF. The handler checked `map['cinematicMode'] == true` and called `_toggleCinematic()`, but did nothing when the value was `false`. Fixed: compare new value against `_cinematicMode` and toggle only when they differ. |
| BUG-P-NEW-07 | HIGH | Quick Bar "Night Mode" button was wired to `onToggleCinematic` (a copy-paste error). Tapping "Night" silently toggled cinematic mode instead of night mode. Fixed: added `onToggleNightMode` callback to `_ControlsOverlay`, wired from `_buildPlayerBody` with the correct `_prefs.copyWith(nightMode:)` + save + `_applyVideoFilters()` lambda. |

### Audit completeness
- All 6,252 lines read in full across 4 passes (Pass 1 = TASK-022, Pass 2 = TASK-023, Pass 3 = TASK-024, Pass 4 = TASK-025)
- No additional functional bugs found
- BUG-P-NEW-05 fix confirmed present in the GitHub file (Pass 3 fix verified)

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | BUG-P-NEW-06: bidirectional cinematic toggle; BUG-P-NEW-07: Quick Bar night mode wired correctly |
| `agent-hub/TASKS.md` | Added TASK-025 to completed archive |
| `.agents/tasks/BUG_TRACKER.md` | Appended Pass 4 session with both new bugs |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-07 (Pass 3 — verification)

**Agent:** Replit Agent (main branch)
**Task:** TASK-024 — Re-audit after Pass 2 to confirm completeness

### What was done
- Full re-read of AbLoopController API (`ab_loop_controller.dart`) to verify ClipTrimmer sync
- Confirmed BUG-P-NEW-05: `ClipTrimmer.onTrimChanged` only set `_abLoopStart`/`_abLoopEnd` state vars but never called `_abLoop.setA()`/`_abLoop.setB()` — so A-B loop enforcement via `maybeSeekBack()` and seek bar markers were both broken when trim was set through the trimmer
- Fixed: added `_abLoop.setA(trim.start)` and `_abLoop.setB(trim.end)` after setState in `onTrimChanged`

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | BUG-P-NEW-05: sync ClipTrimmer points to _abLoop controller |
| `agent-hub/TASKS.md` | Added TASK-024 |
| `.agents/tasks/BUG_TRACKER.md` | Appended BUG-P-NEW-05 |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-07 (Pass 2)

**Agent:** Replit Agent (main branch)
**Task:** TASK-023 — Player Screen deep audit: find ALL remaining bugs not yet in tracker

### What was done

- Read all 6226 lines of `raddflix_flutter/lib/screens/player_screen.dart` in full
- Cross-referenced every function reference against definitions
- Found 4 new bugs (BUG-P-NEW-01 through BUG-P-NEW-04) not previously tracked
- Fixed all 4 bugs in single targeted patch; pushed atomically with updated docs

### Bugs Found and Fixed

| ID | Severity | Fix |
|----|---------|-----|
| BUG-P-NEW-01 | HIGH | `_audioSessionInitialized` never set to `true` in `initState()` → BG-play toggle triggers duplicate audio session listeners. Fixed: add `_audioSessionInitialized = true` in `initState()` after `_initAudioSession()` |
| BUG-P-NEW-02 | MEDIUM | `_MxMoreSheet` Night Mode tile `active` state used `cinematicMode` (wrong feature) instead of `_prefs.nightMode`. Fixed: added `nightModeActive` field, pass `_prefs.nightMode` at call site |
| BUG-P-NEW-03 | HIGH | Mid-stream errors after 3s of playback silently swallowed — blanket `return` caused infinite buffering with no user feedback on CDN expiry/network drop. Fixed: show "Connection lost — reconnecting…" SnackBar + soft `_jazzAutoRetry` |
| BUG-P-NEW-04 | CRITICAL | `_enterCast()` NPE — `_currentPlaybackUrl.isNotEmpty` called on nullable `String?` → crash when cast opened before first URL loaded. Fixed: null-safe check `(_currentPlaybackUrl != null && _currentPlaybackUrl!.isNotEmpty)` |

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | 4 targeted fixes (BUG-P-NEW-01→04) |
| `agent-hub/TASKS.md` | Added TASK-023 to completed archive |
| `.agents/tasks/BUG_TRACKER.md` | Appended Pass 2 session with all 4 new bugs |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-06

**Agent:** Replit Agent (main branch)
**Objective:** Complete server-side pipeline audit; fix last remaining bug where JD filenames leaked into Oracle `files.filename`

### Audit findings (no additional bugs beyond previously identified)

- **titles.title** in Oracle: always TMDB-sourced ("Vincenzo" not "Vncenz0") — confirmed ✅
- **Episode labels** in all 3 sync endpoints (`/sync`, `/db_update`, `/delta`): always `"S{:02d}E{:02d}"` format — NEVER derived from any filename — confirmed ✅
- **`remote_id`**: JD permanent numeric file ID — stored in Oracle `files.remote_id`, selected and returned by all 3 catalog endpoints, stashed in Flutter SQLite, used by Pass 0 — confirmed ✅ (all fixed in previous session `b011e24`)
- **`share_url`**: folder-level share link — not filename-dependent — confirmed ✅
- **`_clean_filename()` in enricher.py**: strips junk tokens before TMDB lookup — garbled names like "Vncenz0" still match TMDB "Vincenzo" (SequenceMatcher ratio ~0.6 >> 0.35 threshold) — confirmed ✅
- **`enrich_and_save()` in `_legacy/scanner.py`**: groups by folder, calls TMDB on sample filename, stores TMDB-correct title in legacy `titles.title` — confirmed ✅

### Bug fixed: `files.filename` used garbled JD title, not TMDB title

**Root cause**: `_import_legacy_into_v3_for_account()` in `scanner.py` (~line 871) called `derive_media_plan(raw_filename)` without a TMDB lookup, so `files.filename` stored in Oracle reflected the dirty JD filename title (e.g. `"Vncenz0 S01E02.mkv"`) instead of the TMDB-correct one (`"Vincenzo S01E02.mkv"`).

**Impact**: The `filename` field is sent to Flutter and used by Passes 1-3 (filename-based CDN matching) when `remote_id=0`. Pass 0 (remote_id numeric match, primary path post-`b011e24`) was unaffected.


---

## Session 2026-06-07 — Player Screen Pass 5: 29-Bug Comprehensive Audit

**Agent:** Replit Agent (main branch)
**Objective:** Fix all 29 bugs from the full Pass 5 audit of player_screen.dart (6,265 lines). Applied as one atomic commit.

### Bugs fixed (26 of 29)

| ID | Sev | Title | Fix Summary |
|----|-----|-------|-------------|
| C-01 | CRITICAL | _applyVolumeBoost maxes system volume on every player open | Removed unconditional VolumeController().setVolume(1.0) from _applyVolumeBoost |
| C-02 | CRITICAL | Inner GestureDetector onScaleStart wins pinch arena | Removed onScaleStart:(_){} from inner GD; added pointerCount<2 guard |
| H-01 | HIGH | _applyVideoFilters/_applyAudioPrefs race on rapid changes | 60ms timestamp debounce on both functions |
| H-02 | HIGH | _jazzRetryCount not reset on episode change | Added _jazzRetryCount=0 at start of _playPrevEpisode and _playNextEpisode |
| H-03 | HIGH | _startWakeTimer uses default prefs | Added _startWakeTimer() at end of _loadPrefs() body |
| H-04 | HIGH | _cancelSleepTimer calls setState without mounted guard | Wrapped setState in if (mounted) |
| H-05 | HIGH | Playback info panel never refreshes | Added _piTimer (Timer.periodic 2s) while panel is open |
| H-06 | HIGH | Muting leaves MPV at full boost level | Mute now sets MPV volume=0; unmute restores (_volume * _volumeBoost * 100) |
| H-07 | HIGH | SleepTimerSheet.onStopAtEpisodeEnd dead | Wired to _setSleepTimer(-1) |
| H-08 | HIGH | Long-press badge auto-fades while still holding | Removed .then().fadeOut() chain |
| M-01 | MEDIUM | QuickShortcutBar nightmode never shows active | Added nightModeActive field threaded through _ControlsOverlay → _QuickShortcutBar |
| M-02 | MEDIUM | _SleepPanel shows nothing for episode-end sleep | Added sleepAtEpisodeEnd param + "Pausing at episode end" text |
| M-03 | MEDIUM | SW Decoder toggle has no effect | Added onSwDecoderChanged callback wired to _np.setProperty('hwdec') |
| M-04 | MEDIUM | CinematicSettingsSheet gets wrong opacity field | Changed _prefs.transparentModeOpacity to _cinematicOpacity |
| M-05 | MEDIUM | colorchannelmixer missing alpha row params | Added :ra=0 :ga=0 :ba=1 |
| M-06 | MEDIUM | Hue divided by 180 → near-zero | Removed /180.0 (MPV eq hue takes degrees) |
| M-07 | MEDIUM | Rage skip controls freeze on screen | Added _scheduleHide() after setting _rageSkipActive=true |
| M-08 | MEDIUM | Plan expiry check skips streaming users | Broadened to fileId.isNotEmpty && !_isLocalPath |
| M-09 | MEDIUM | _loadSmartIntro() always returns early in initState | Removed dead call |
| L-01 | LOW | Shuffle + Customise Items permanently dead | Removed both from VideoDisplaySheet row2 |
| L-02 | LOW | Loop and A-B Repeat identical callbacks | onLoop now calls _np.command(['cycle','loop-file']) |
| L-04 | LOW | lock_current uses raw physicalSize pixels | Replaced with MediaQuery.of(context).size |
| L-05 | LOW | Rage skip double-fires within animation window | Added _rageSkipActive guard at top of _handleCenterTap |
| L-06 | LOW | Settings pop doesn't restore SystemChrome | Added .then((_){SystemChrome.setEnabledSystemUIMode + _applyRotation}) |
| L-08 | LOW | Inconsistent 4-space indent for two field declarations | Fixed to 2-space |

### Deferred (4 of 29)
- **L-03** (LOW): Negative remaining time during intro skip — clamp in caller; no player_screen.dart change needed
- **L-07** (LOW): _openCinematicSettings accessible when cinematicMode=false — no harmful side-effects
- **L-09** (LOW): Duplicate _openJumpTo/_showJumpToTime — consolidate in next cleanup pass
- **L-10** (LOW): _cinematicOpacity not persisted — requires PlayerPrefs schema change (tracked in BACKLOG-01)

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | 26 fixes; +63 net lines (6,328 total) |
| agent-hub/TASKS.md | TASK-026 to completed archive; BACKLOG-01 added |
| .agents/tasks/BUG_TRACKER.md | Pass 5 session appended (all 29 bugs) |
| agent-hub/history/TASK_LOG.md | This entry |

---

## TASK-027 — Player screen Pass 6: full line-by-line audit (12 bugs)
**Date:** 2026-06-07
**Commit:** Pass 6 — 12 of 12 bugs fixed
**Status:** ✅ DONE

### Bugs fixed (N01–N12)

| ID | Sev | Bug | Fix |
|----|-----|-----|-----|
| N01 | HIGH | `ba=1` in night-mode colorchannelmixer — alpha bleeds into blue output | Changed to `ba=0` |
| N02 | HIGH | `_applyVolumeBoost` sets MPV volume = multiplier×100, ignores system `_volume` fraction | Fixed to `(_volume * multiplier * 100).toInt()` |
| N03 | MED | App resume seeks back but never calls `_player.play()` — player stays paused if OS paused it | Added `if (!_player.state.playing) _player.play()` on resume |
| N04 | MED | `_applyRotation` creates two separate `copyWith` objects; second save uses a throwaway copy | Refactored to save the single `copyWith` result |
| N05 | MED | Auto-skip intro flickers: sets `_skipIntroVisible = true` then `= false` in same frame | Check autoSkip BEFORE setting visible=true |
| N06 | MED | `_startSleepFade()` called inside `setState()` — nested setState anti-pattern | Moved `_startSleepFade()` call outside the setState block |
| N07 | MED | `_pickSubtitle` passes bare POSIX path to `SubtitleTrack.uri()` — MPV rejects without `file://` | Prefix with `file://` if not already present |
| N08 | MED | Inner zoom GestureDetector has no `onScaleStart` → `_zoomLevel * d.scale` on already-updated value → exponential drift | Added `_innerZoomStart` field; captured in outer `onScaleStart`; inner GD now uses `_innerZoomStart * d.scale` |
| N09 | LOW | `screenRotation` active = `rotationMode != 'auto'` — marks `sensor_landscape` as locked too | Exclude `sensor_landscape`: `!= 'auto' && != 'sensor_landscape'` |
| N10 | LOW | `loopActive` and `abRepeatActive` both use `_abLoop.isActive` — Loop uses MPV `loop-file` since FIX-L02 | Added `_loopFileActive` bool; toggled in `onLoop`; `loopActive` now uses it |
| N11 | LOW | `subLabels.isNotEmpty ? 'Sub' : 'Sub'` — dead ternary, both branches identical | Changed to `subLabels.length > 1 ? 'Sub (${subLabels.length})' : 'Sub'` |
| N12 | LOW | `audioLabels.length > 1 ? 'Audio' : 'Audio'` — dead ternary, both branches identical | Changed to `audioLabels.length > 1 ? 'Audio (${audioLabels.length})' : 'Audio'` |

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | 12 fixes; net +18 lines |
| agent-hub/TASKS.md | TASK-027 added to completed archive |
| agent-hub/history/TASK_LOG.md | Pass 6 session appended |

## TASK-029 — IDEA-01: Universal Subtitle Hunter
**Date:** 2026-06-07  **Status:** ✅ DONE

### Components implemented
| Component | Detail |
|-----------|--------|
| SubtitleHunter (compute isolate) | Walks device storage recursively; collects .srt/.ass/.ssa/.vtt/.sub/.sbv |
| ZIP extraction | archive package peeks inside .zip files, extracts matching subtitle entries to temp cache |
| Fuzzy scoring | Token overlap 70% + Levenshtein similarity 30% → 0-100 confidence |
| 60s result cache | Second open of same video returns instantly |
| SubtitleHunterSheet | Bottom sheet: ranked list, confidence bar, ZIP badge, collapsible preview (5 lines), one-tap Load |
| URL loader | Download .srt/.ass/.vtt from any HTTP URL → auto-loads into player |
| _MxSubPanel integration | Replaced dead “+ Add Translation” with “Search” button; → _openSubtitleHunter() |

### Files changed
| File | Change |
|------|--------|
| lib/core/subtitles/subtitle_hunter.dart | NEW |
| lib/core/subtitles/subtitle_hunter_sheet.dart | NEW |
| lib/screens/player_screen.dart | +imports, +_openSubtitleHunter(), +onHunt wiring, +Search button |
| pubspec.yaml | +archive: ^3.4.0 |
| agent-hub/TASKS.md | TASK-029 added |
| agent-hub/history/TASK_LOG.md | This entry |

---

## TASK-030 — PlayerHudSettingsSheet (HUD Layout & Controls Settings Overlay)

**Date:** 2026-06-07
**Status:** ✅ Complete
**Commit:** `cd8bcd83327e752d0d256ae6bb918740c7835af1`

### Summary
Created a comprehensive, live-preview, semi-transparent settings overlay panel
that renders inside the player Stack so the video is always visible behind it.

### Behavior
| Mode | Position | Size | Effect |
|------|----------|------|--------|
| Portrait | Slides up from bottom | Full width × 72% height | 72% dark + blur → video visible above |
| Landscape | Slides in from right | 52% width × full height | Video visible on left 48% |

- **Animation:** 300ms easeOutCubic slide in / easeInCubic slide out
- **Background:** `Color(0xB8080810)` + `BackdropFilter(blur: 10)` — live video shows through
- **Live changes:** every toggle → `onPrefsChanged` callback → `setState` + `prefs.save()` in player_screen — no Save button
- **Dismiss:** X button or tap on backdrop outside panel

### Sections (5 organized groups)
1. **⚡ Quick Bar** — master show/hide toggle + 8 shortcut item chips (pip, bgplay, fit, screenshot, speed, subtitle, lock, nightmode) — tap chip to add/remove from bar
2. **🎮 Center Buttons** — 3-way position selector (Center / Bottom / Hidden) + Prev/Next episode + Skip Intro toggles
3. **📺 Info Overlays** — 7 individual toggles: Episode info, Network speed, Playback info, Decoder info, Active track badge, Track count badge, Frame counter
4. **🎬 Seek Bar** — 10 style chips (classic/bold/gradient/wave/neon/dots/thin/glow/retro/minimal) + buffer bar toggle
5. **⚙️ Controls Behavior** — auto-hide delay slider (2–15s) + controls opacity slider (30–100%)

### Files changed
| File | Change |
|------|--------|
| lib/widgets/player/player_hud_settings_sheet.dart | NEW (758 lines) — full overlay widget |
| lib/screens/player_screen.dart | +import, `_showHudSettings` state, `_openHudSettings()`, HudSettingsSheet overlay in Stack, `_MxMoreSheet.onLayoutSettings` field+ctor+call, new "Layout & HUD" button in More grid |
| agent-hub/TASKS.md | TASK-030 added |
| agent-hub/history/TASK_LOG.md | This entry |

---

## TASK-031 — PlayerHudSettingsSheet v2 (Presets + Orientation Tabs + Drag-Reorder + Shapes + MX Rotation)

**Date:** 2026-06-07
**Status:** ✅ Complete
**Commit:** `0a4c3c584b7c9d0ff93b3b8b4820fb0012d8daf9`

### Changes

#### player_hud_settings_sheet.dart — full rewrite (1145 lines)

1. **Layout Preset Strip** — Netflix / MX Classic / Minimal / Binge / Custom chips at top of panel. Auto-detects which preset matches current prefs; one-tap applies a full bundle of settings at once.
2. **Per-Orientation Tabs** — Portrait / Landscape tabs at top of panel. Each tab shows and edits independent layout prefs for that orientation so a user can have Quick Bar visible only in landscape.
3. **Drag-to-Reorder Quick Bar** — `ReorderableListView` with `ReorderableDragStartListener` drag handles. Active items shown as ordered list; inactive items shown as "Tap to add" chips below.
4. **Dedup Guard** — Subtitle chip shows amber warning + info banner if added to Quick Bar (it's already permanently in the top bar). `_kDuplicateWarned` set defines permanently-placed controls.
5. **Button Shape Switcher** — Circle / Squircle / Rounded / Pill / Sharp chips. Each chip renders with its own `borderRadius` so user sees the actual shape before tapping.
6. **Animated Preset Detection** — `_detectActivePreset()` compares centerBtnPosition + showQuickBar + seekBarStyle to identify which preset is active; updates the strip highlight live.

#### player_screen.dart

7. **MX-style auto-rotation** (`didChangeMetrics` override) — tracks which physical side user flipped to via safe-area padding heuristic (`padding.left > padding.right → landscapeRight`). When `rotationMode == 'sensor_landscape'`, snaps `setPreferredOrientations` to that exact side. `_lastLandscapeSide` state var persists between flips.

### Files changed
| File | Change |
|------|--------|
| lib/widgets/player/player_hud_settings_sheet.dart | Full rewrite (758→1145 lines) |
| lib/screens/player_screen.dart | +_lastLandscapeSide, +didChangeMetrics override, MX rotation snap |
| agent-hub/TASKS.md | TASK-031 added |
| agent-hub/history/TASK_LOG.md | This entry |

---

## TASK-032 — Smart Enhance (MX-style AI Video Enhancement Suite)

**Date:** 2026-06-07
**Status:** ✅ Complete
**Commit:** `034938fbbc43aadd38b75565190387d571a85ebf`

### New Files

#### lib/core/player/smart_enhance.dart (96 lines)
- `SmartEnhancePreset` data class — brightness/contrast/saturation/hue deltas + sharpness + noiseReduce + colorHex
- `kSmartEnhancePresets` — 8 content modes:

| Mode | Key Enhancement |
|------|----------------|
| Standard | Subtle all-round boost |
| Movie | Cinematic warmth, rich shadows (hue +4°) |
| Sports | Vivid colors (+32%), razor sharpness (+0.38) |
| Anime | Bold palette (+42% sat), clean linework |
| Low Light | Brightness lift (+15%), hqdn3d noise reduction |
| AMOLED | Deep blacks (−10% bright), vivid punch |
| Drama | Warm amber tones (hue +7°), mood contrast |
| Documentary | Natural, neutral, highly detailed |

#### lib/widgets/player/smart_enhance_sheet.dart (655 lines)
- Transparent overlay panel — slides from bottom (portrait) / right (landscape), blurred glass
- `_MasterToggle` — animated ON/OFF switch with green glow ring; shows "Smart Enhance Active" status
- `_ModeGrid` — 3-column card grid, 8 modes with emoji + label + accent underbar; selecting a mode auto-enables
- `_WhatApplied` — info card showing contrast/color/brightness/sharpness/warmth/noise badge chips with actual percentage values
- `_IntensitySlider` — Subtle → Max (0.5×–1.5× multiplier on preset deltas, labels: Subtle/Soft/Default/Strong/Max)
- `_BeforeAfterBtn` — hold to temporarily bypass enhance and see original video live; release to restore (same as MX Player compare mode)

### Modified Files

#### player_prefs.dart
- Added `smartEnhanceEnabled` (bool, default: false)
- Added `smartEnhanceMode` (String, default: 'standard')
- Wired in: field decls, constructor defaults, copyWith params + body, load(), save()
- SharedPrefs keys: `${_p}smart_enhance_enabled`, `${_p}smart_enhance_mode`

#### player_screen.dart
- `_buildVfString` extended: Smart Enhance merges preset deltas with user eq values
  - brightness/contrast/saturation/hue stacked + clamped (−1..+1, −2..+2, −3..+3)
  - sharpness = (user + se delta) clamped 0–1.5
  - `hqdn3d` noise filter appended when `preset.noiseReduce == true` (Low Light mode)
- `_showSmartEnhance` state bool + `_openSmartEnhance()` method
- `SmartEnhanceSheet` overlay added to player Stack
- "Smart Enhance" button (violet, `auto_awesome` icon) added to `_MxMoreSheet` grid
