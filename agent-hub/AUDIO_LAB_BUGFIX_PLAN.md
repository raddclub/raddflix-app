# Audio Lab Bug-Fix Plan
_Written: 2026-07-07 | Target file: `raddflix_flutter/lib/screens/player_screen.dart`_

---

## Context

The Audio Lab panel (`_AudioEffectPanel` / `_AudioEffectPanelState`, lines ~7050-7465) is a fully-rendered UI — Presets, Equalizer, and Lab tabs all look correct — but changes have **no audible effect** on playback. The panel is NOT a pure mockup; the MPV wiring exists but has multiple bugs that together cause the filter chain to silently fail or conflict.

The audio pipeline works like this:
```
UI change → callback → setState + _currentXxxAf → _applyAllAf() → _buildMergedAfString() → _np.setProperty('af', filterString)
```
Every bug below breaks one or more links in that chain.

---

## Bug Registry

### 🔴 CRITICAL / HIGH — These break the feature entirely

---

#### BUG-01 — EQ filter not cleared when all bands are zero
**Lines:** ~1782-1793 (`_buildMergedAfString`)

**Root cause:**
```dart
if (g.any((v) => v != 0)) parts.add('equalizer=${g.join(':')}');
```
When the user drags all 5 sliders back to 0, the condition is false and the filter is **not added** to `parts`. That is correct so far. But in practice (verify via runtime logs after TASK A1), MPV may keep the previous non-zero EQ filter running when the new `af` string omits `equalizer` entirely — observed in some libmpv builds. Confirm with logs before applying the fix below. The fix is to explicitly include `equalizer=0:0:0:0:0:0:0:0:0:0` (flat) when EQ is enabled but all bands are zero, so MPV has a neutral reference rather than a stale boosted one.

**Fix:**
```dart
// Replace the guard:
if (_eqEnabled) {
  // always include the filter so MPV clears any previous non-zero state
  parts.add('equalizer=${g.join(':')}');
}
```

---

#### BUG-02 / BUG-04 — Double `equalizer` filter conflict (EQ + Lab)
**Lines:** ~1793 (main EQ), ~7114 (Dialogue Boost), ~7119-7122 (Bass Boost)

**Root cause:**
`_buildMergedAfString` assembles the filter chain as:
```
equalizer=... [from main EQ]  ,  equalizer=... [from Lab Dialogue/Bass inside _currentLabAf]
```
MPV allows chaining the same filter twice, but the two `equalizer` instances interfere. The second one applies its gains on top of the already-EQ'd signal, producing unpredictable gain, and in some MPV builds the second `equalizer` silently overrides the first entirely — making the main EQ sliders appear to do nothing when Dialogue or Bass Boost is also on.

**Fix — merge Lab EQ gains into the main EQ chain:**
`_buildMergedAfString` must detect any `equalizer=` segment inside `_currentLabAf`, extract its 10 gain values, add them to the main EQ gains, and output a single `equalizer` filter.

```dart
// In _buildMergedAfString, before building g[]:
List<int> labEqGains = List.filled(10, 0);
final labEqMatch = RegExp(r'equalizer=([\d:.-]+)').firstMatch(_currentLabAf);
if (labEqMatch != null) {
  labEqGains = labEqMatch.group(1)!.split(':').map(int.parse).toList();
}
final g = [
  b[0].round() + labEqGains[0],  b[0].round() + labEqGains[1],
  b[1].round() + labEqGains[2],  b[1].round() + labEqGains[3],
  b[2].round() + labEqGains[4],  b[2].round() + labEqGains[5],
  b[3].round() + labEqGains[6],  b[3].round() + labEqGains[7],
  b[4].round() + labEqGains[8],  b[4].round() + labEqGains[9],
].map((v) => v.clamp(-12, 12)).toList();

// Then strip the equalizer segment from _currentLabAf before appending it:
final labAfClean = _currentLabAf.replaceAll(RegExp(r'equalizer=[^,]+(,|$)'), '').trim().replaceAll(RegExp(r'^,|,$'), '');
if (labAfClean.isNotEmpty) parts.add(labAfClean);
```

---

#### BUG-03 — `_applyAllAf()` silently swallows MPV errors
**Lines:** ~1873-1875

**Root cause:**
```dart
void _applyAllAf() {
  try { _np.setProperty('af', _buildMergedAfString()); } catch (_) {}
}
```
The bare `catch (_) {}` means any failure (null `_np`, malformed filter string, MPV not ready) is invisible. The UI shows the user's setting as applied; audio is unchanged.

**Fix:**
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
At minimum log the error so a developer running with `flutter logs` can see what's wrong without a debugger.

---

### 🟡 MEDIUM — Degrade quality or cause edge-case failures

---

#### BUG-05 — Vocal Remover clips audio
**Lines:** ~7111

**Current filter:**
```
pan=stereo|c0=c0-c1|c1=c1-c0
```
Subtracting channels produces a signal that can peak at 2× the original amplitude → hard clipping on loud content.

**Fix:**
```
pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0
```

---

#### BUG-06 — initState loads stale defaults, not live MPV state
**Lines:** ~7141-7149

**Root cause:**
On panel open, `_AudioEffectPanelState.initState()` reads values from `widget.eqBands`, `widget.eqEnabled`, etc. — which are the parent's Dart state variables, initialised from SharedPreferences at app start. If the user changed audio settings in a previous session or the prefs are out of sync, the UI sliders show the **saved** values while MPV is actually playing with different (or no) filters applied.

**Fix:**
On panel open, call `_np.getProperty('af')` to read the live filter string, parse it, and pre-populate the UI accordingly. If `getProperty` isn't available, at minimum call `_applyAllAf()` immediately on `initState` to force MPV to match the UI state.

```dart
@override
void initState() {
  super.initState();
  // ... existing init ...
  // Force MPV to match whatever the panel is showing on open:
  WidgetsBinding.instance.addPostFrameCallback((_) => widget.onEqEnabledChanged?.call(widget.eqEnabled));
}
```
Or better, expose an `onPanelOpened` callback that triggers `_applyAllAf()` from the parent.

---

#### BUG-07 — EQ band 5→10 mapping is musically wrong (cosmetic but misleading)
**Lines:** ~1784-1792

The 5 UI bands (60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz) are each duplicated into two adjacent MPV bands:
```dart
b[0].round(), b[0].round(),   // pair for ~31+62 Hz
```
MPV's `equalizer` filter has fixed center frequencies: 31.25 Hz, 62.5 Hz, 125 Hz, 250 Hz, 500 Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz. By duplicating each band value into two consecutive slots, the bass band is actually boosting both 31 Hz and 62 Hz (close but not identical to the labelled "60 Hz"). This is a low-severity accuracy issue but can surprise users who expect precise boosts.

**Fix (optional improvement):** Map each UI band to its closest single MPV band and leave the other at 0, or relabel the UI bands to match MPV's actual frequencies.

---

#### BUG-08 — Lab `_currentLabAf` never reset when Lab toggles are all turned off
**Lines:** ~4603-4606

**Root cause:**
```dart
onLabAfChanged: (afStr) {
  _currentLabAf = afStr;
  _applyAllAf();
},
```
`_currentLabAf` is set to whatever string the Lab panel emits. If the Lab panel correctly emits `''` when all toggles are off, this is fine. But if `_applyLabAf()` (inside the panel) returns a non-empty string even when all toggles are false (e.g., it still appends a neutral filter), `_currentLabAf` is never truly cleared. **Verify** that `_applyLabAf()` returns `''` when `_labVocal=false && _labDialogue=false && _labNorm=false && _labBass=false`.

---

### 🟢 LOW — Polish / lint

---

#### BUG-09 — `silencedetect` in the audio filter chain
**Lines:** ~1801-1803

`lavfi=[silencedetect=...]` is a detection filter with no audio output — it only fires events. Placing it in the `af` chain is technically valid but some MPV versions reject the `lavfi=` wrapper in the `af` property (vs. `vf`). If this is causing `setProperty('af', ...)` to throw, the silent catch (BUG-03) hides it. 

**Fix:** Move silence detection to a separate `_np.setProperty('af-command', ...)` call, or use `_np.command(['vf', 'add', 'lavfi=[silencedetect=...]'])` — verify correct MPV API for silence detection.

---

## Task List for Next Agent

```
TASK A1 — Add debug logging to _applyAllAf()            [30 min]  ← do this first
TASK A3 — Merge dual equalizer filters (BUG-02/04)      [90 min]  ← highest impact, do before A2
TASK A2 — Fix silent EQ-clear bug (BUG-01)              [30 min]  ← verify via runtime logs first
TASK A4 — Fix Vocal Remover clipping (BUG-05)           [15 min]
TASK A5 — Force MPV sync on panel open (BUG-06)         [30 min]
TASK A6 — Verify _applyLabAf returns '' when all off    [20 min]
TASK A7 — Investigate silencedetect af compatibility    [30 min]
TASK A8 — Build APK + confirm audio effects audible     [20 min]
```

**Do A1 first** — once logging is in place, run `flutter logs` while toggling Lab settings and confirm which `af` strings are actually reaching MPV. This will immediately show whether the bugs above match the real runtime behaviour.

---

## Key File Reference

| Symbol | Location |
|---|---|
| `_AudioEffectPanel` | line ~7050 |
| `_AudioEffectPanelState` | line ~7096 |
| `_buildMergedAfString()` | line ~1780 |
| `_applyAllAf()` | line ~1873 |
| `_applyPreset()` | line ~1756 |
| `_applyLabAf()` (inside panel) | line ~7108 |
| `_currentLabAf` (parent field) | line ~192 |
| `onLabAfChanged` callback | line ~4603 |
| `onPresetSelected` callback | line ~4580 |

---

## Permanent Rules (never break)

- Never add `androidAttachSurfaceAfterVideoParameters: true` (black screen on MediaTek).
- MPV colour: `#RRGGBB` for text, `#RRGGBBAA` for background (`AA=00`=opaque).
- Rule 42: `log_pending.sh` → edit → `auto_commit.sh` per file; never batch across files.
- Push files **sequentially** (SHA race condition in GitHub Trees API).
- Oracle/Flask backend: no changes without explicit user approval.
