---
name: Admin panel Dart anchor quirks
description: Lessons from surgical text substitution in show_detail_screen.dart for the admin episode status panel
---

## _showDetailScreenState setState block structure

The setState block in `_loadEpisodes()` has THREE consecutive assignment lines:
```dart
        _watchProgress = prog;
        _overrides = overrides;        // added in v18
        _resumeEpisodeIndex = resumeIdx;
        _loading = false;
```

When adding `_overrides = overrides` you must anchor to:
```
"        _watchProgress = prog;\n        _resumeEpisodeIndex = resumeIdx;\n        _loading = false;"
```
NOT just `_watchProgress + _loading` — the _resumeEpisodeIndex line is between them.

## _showAdminSheet method injection guard

The condition to skip inserting the method must check for the **method signature**,
not the call site — because the call site is added FIRST (step E) and a naive
`s.includes('_showAdminSheet')` then skips method insertion (step G).

Correct: `if (!s.includes('Future<void> _showAdminSheet'))`
Wrong:   `if (!s.includes('_showAdminSheet'))`

**Why:** Multi-step patch scripts can add a call before the definition. The skip guard
must be specific enough to distinguish call sites from definitions.

## check needle indentation

Check needles must match the actual indentation in the generated string, not some
guessed value. The Episodes header GestureDetector has 24 spaces of indentation:
```
                        GestureDetector(
                          onTap: () {
                            _adminTapCount++;
```
The check needle `"GestureDetector(\n          onTap:"` (10 spaces) will fail even
though the substitution was applied correctly. Use enough context from the actual file.
