# Agent Prompt — Audio Lab Bug Fix
_Copy this entire file as your first message when starting a new session._

---

## Your Mission

Fix the **Audio Lab panel** in the Raddflix Flutter video player. The panel UI works perfectly (three tabs: Presets, Equalizer, Lab) but **no audio changes take effect during playback** — it behaves like a mockup. The MPV wiring exists but has specific bugs documented below. Your job is to fix them all, build an APK, and verify.

---

## Repo & Environment

- **Repo:** `https://github.com/raddclub/raddflix-app`
- **Main file:** `raddflix_flutter/lib/screens/player_screen.dart`
- **Build:** GitHub Actions (`.github/workflows/build.yml`) — push to `main`, workflow triggers automatically, APK uploaded as artifact
- **Commit method:** Use `auto_commit.sh` in `agent-hub/scripts/` — **one file at a time**, sequentially (never batch multiple files in one commit to avoid SHA race conditions)
- **Task log:** `agent-hub/TASKS.md` — add a row for each task you complete

---

## How the Audio Pipeline Works

```
UI toggle/slider
  → callback (onLabAfChanged / onEqBandChanged / onPresetSelected / etc.)
  → parent setState + updates _currentXxxAf string
  → _applyAllAf()
  → _buildMergedAfString()   ← assembles all filters into one comma-separated string
  → _np.setProperty('af', filterString)   ← sends to MPV
```

All audio effects go through `_np.setProperty('af', ...)`. If the string is malformed or the call throws silently, nothing happens.

---

## Bugs to Fix (in priority order)

### 🔴 Fix First — Logging (TASK A1)

**File:** `player_screen.dart` around line 1873

`_applyAllAf()` currently swallows all errors silently:
```dart
void _applyAllAf() {
  try { _np.setProperty('af', _buildMergedAfString()); } catch (_) {}
}
```

Add logging so you can see what's happening:
```dart
void _applyAllAf() {
  final filterStr = _buildMergedAfString();
  try {
    _np.setProperty('af', filterStr);
    debugPrint('[AudioLab] af set: $filterStr');
  } catch (e) {
    debugPrint('[AudioLab] _applyAllAf ERROR: $e | filter: $filterStr');
  }
}
```

After adding this, push and run `flutter logs` on a device while toggling Lab settings. Confirm the correct filter strings are appearing in the log.

---

### 🔴 Fix Second — Dual Equalizer Conflict (TASK A3, highest impact)

**File:** `player_screen.dart` around lines 1782-1797

**Problem:** `_buildMergedAfString()` can produce two `equalizer=` filters in the same chain — one from the main EQ bands, one from Lab's Dialogue Boost or Bass Boost (which are stored in `_currentLabAf`). MPV either applies them additively in wrong ways or the second overrides the first, making the main EQ sliders appear to do nothing when Lab effects are on.

**Fix — merge Lab EQ gains into the main chain:**

Inside `_buildMergedAfString()`, before computing the main EQ gain array, extract any `equalizer=` segment from `_currentLabAf` and add its gains to the main band gains:

```dart
String _buildMergedAfString() {
  final parts = <String>[];

  // Extract any equalizer contribution from Lab (Dialogue Boost / Bass Boost)
  List<int> labEqGains = List.filled(10, 0);
  final labEqMatch = RegExp(r'equalizer=([\d:.\-]+)').firstMatch(_currentLabAf);
  if (labEqMatch != null) {
    final rawGains = labEqMatch.group(1)!.split(':');
    labEqGains = rawGains.map((s) => int.tryParse(s) ?? 0).toList();
  }

  // Main EQ — merge with Lab EQ, clamp to valid MPV range
  if (_eqEnabled) {
    final b = _eqBands;
    final g = [
      b[0].round() + labEqGains[0],  b[0].round() + labEqGains[1],
      b[1].round() + labEqGains[2],  b[1].round() + labEqGains[3],
      b[2].round() + labEqGains[4],  b[2].round() + labEqGains[5],
      b[3].round() + labEqGains[6],  b[3].round() + labEqGains[7],
      b[4].round() + labEqGains[8],  b[4].round() + labEqGains[9],
    ].map((v) => v.clamp(-12, 12)).toList();
    // Always include so MPV clears any previous non-zero state
    parts.add('equalizer=${g.join(':')}');
  }

  // Reverb
  if (_currentReverbAf.isNotEmpty) parts.add(_currentReverbAf);

  // Lab — strip out the equalizer segment (already merged above)
  final labAfClean = _currentLabAf
      .replaceAll(RegExp(r'equalizer=[^,]+(,|$)'), '')
      .replaceAll(RegExp(r'^,|,$'), '')
      .trim();
  if (labAfClean.isNotEmpty) parts.add(labAfClean);

  if (_currentChannelModeAf.isNotEmpty) parts.add(_currentChannelModeAf);
  if (_currentBalanceAf.isNotEmpty) parts.add(_currentBalanceAf);

  if (_silenceInPipeline) {
    parts.add('lavfi=[silencedetect=noise=-50dB:d=${_silenceSkipThreshold.toStringAsFixed(1)}]');
  }

  return parts.join(',');
}
```

---

### 🔴 Fix Third — EQ Not Cleared When All Bands Reset to Zero (TASK A2)

**File:** `player_screen.dart` around line 1793

**Problem:** When EQ is enabled but all sliders are at 0, the old code skips adding `equalizer` to the filter string. MPV keeps the previous non-zero EQ filter running.

**Fix:** Always include `equalizer` when EQ is enabled (the merged logic in TASK A3 already handles this — just make sure `_eqEnabled=true` always produces an `equalizer=` line, even if all gains are 0).

---

### 🟡 Fix Fourth — Vocal Remover Clips Audio (TASK A4)

**File:** `player_screen.dart` around line 7111

**Problem:** Current filter:
```
pan=stereo|c0=c0-c1|c1=c1-c0
```
Subtracting full-level channels can produce 2× amplitude → hard clipping.

**Fix:**
```
pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0
```

---

### 🟡 Fix Fifth — Force MPV Sync When Panel Opens (TASK A5)

**File:** `player_screen.dart` around lines 7141-7149 (`_AudioEffectPanelState.initState`)

**Problem:** When the panel opens, it shows values from SharedPreferences (saved at last session end). MPV may not have those filters applied yet (e.g., first open after fresh launch).

**Fix:** At the end of `initState()`, trigger `_applyAllAf()` from the parent so MPV immediately matches what the UI shows:

Find where `_AudioEffectPanel` is constructed (around line 4570) and add an `onPanelOpened` callback, OR:

Inside `_AudioEffectPanelState.initState()`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  // Sync MPV to current UI state immediately on panel open
  widget.onEqEnabledChanged?.call(widget.eqEnabled);
});
```

---

### 🟡 Verify — Lab returns empty string when all toggles off (TASK A6)

**File:** `player_screen.dart` around line 7108 (`_applyLabAf` inside `_AudioEffectPanelState`)

Read the function. Confirm that when `_labVocal=false`, `_labDialogue=false`, `_labNorm=false`, `_labBass=false`, it calls `widget.onLabAfChanged('')` (empty string). If it emits anything non-empty, it leaves stale filters running.

If broken, fix so that all-off correctly emits `''`.

---

### 🟢 Investigate — silencedetect compatibility (TASK A7)

**File:** `player_screen.dart` around line 1801

`lavfi=[silencedetect=...]` in the `af` property may cause the entire `setProperty('af', ...)` call to fail in some MPV builds, which would silently break ALL audio effects (the silent catch in A1 would hide this).

After adding the A1 logging, run with silence skip enabled and check if the logged filter string contains `lavfi=` and whether an error appears. If it errors, move silence detection out of the `af` chain.

---

## After All Fixes

1. **Build APK:** Push to `main`, wait for GitHub Actions to complete, download APK from artifacts.
2. **Manual test checklist:**
   - [ ] Drag EQ sliders → audible change in playback
   - [ ] Select a preset (e.g. Bass Boost) → audible bass increase
   - [ ] Enable Dialogue Boost → audible voice clarity change
   - [ ] Enable Vocal Remover → vocals reduced (centre channel removed)
   - [ ] Enable Audio Normalization → volume levels out
   - [ ] Enable Bass Boost in Lab → bass increase
   - [ ] Turn all Lab off → audio returns to normal (no residual filters)
   - [ ] EQ + Lab simultaneously → no conflict, both apply
3. **Update task log:** Mark tasks A1-A7 done in `agent-hub/TASKS.md`.

---

## Permanent Rules — Never Break These

| Rule | Detail |
|---|---|
| No `androidAttachSurfaceAfterVideoParameters: true` | Causes black screen on MediaTek devices |
| MPV colour format | `sub-color=#RRGGBB` (text), `sub-back-color=#RRGGBBAA` (bg, `AA=00`=opaque) |
| Commit method | `auto_commit.sh` per file, one at a time, sequentially |
| Oracle/Flask backend | No changes without explicit user approval |
| SHA race condition | Never push multiple files in one GitHub Trees API call |

---

## Reference: Key Symbols and Line Ranges

| Symbol | Approx. line |
|---|---|
| `_AudioEffectPanel` widget | ~7050 |
| `_AudioEffectPanelState` | ~7096 |
| `_applyLabAf()` (inside panel) | ~7108 |
| `_buildMergedAfString()` | ~1780 |
| `_applyAllAf()` | ~1873 |
| `_applyPreset()` | ~1756 |
| `_currentLabAf` (parent field) | ~192 |
| `onLabAfChanged` callback wire | ~4603 |
| `onPresetSelected` callback wire | ~4580 |
| `onReverbChanged` callback wire | ~4591 |

---

## Full Bug Reference

See `agent-hub/AUDIO_LAB_BUGFIX_PLAN.md` for the complete bug registry with exact line citations and root-cause analysis. Read it before touching any code.

---

_End of agent prompt._
