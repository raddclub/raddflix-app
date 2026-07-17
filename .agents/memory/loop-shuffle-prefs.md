---
name: Loop/shuffle persistence
description: Loop and shuffle state are now saved to SharedPreferences and restored to MPV on player startup.
---

## Rule
Both `_loopEnabled` and `_shuffleEnabled` must be persisted via `_scheduleSavePrefs()` when toggled, and restored in `_loadPrefs()` (including pushing `loop-file=inf` to MPV when loop is active on restore).

## Why
Before this fix, toggling loop/shuffle survived only for the current session. After backgrounding or killing the app, both states reset to false — a regression noticed after the Z1 audio-mode work added shuffle.

## How to apply
- `_savePrefs()` in `player_screen.dart` — `pref_loop` / `pref_shuffle` keys
- `_loadPrefs()` — restores both bools AND applies `loop-file=inf` to MPV if loop was active
- `_toggleLoop()` / `_toggleShuffle()` in `_ps_playback_mixin.dart` — both call `_scheduleSavePrefs()` after toggling state
