---
name: Live mixin cross-cluster rule
description: _isLive getter is in _ps_ui_mixin.dart and is NOT accessible from _ps_playback_mixin.dart.
---

`_isLive` is defined as a getter in `_ps_ui_mixin.dart`:
```dart
bool get _isLive => widget.contentType == 'live';
```

`_PlayerPlaybackMixin` in `_ps_playback_mixin.dart` is a **separate mixin** with no cross-cluster declaration for `_isLive`. Using `_isLive` there causes `undefined_identifier` at analysis/CI time.

**Why:** The mixin architecture intentionally separates UI and playback concerns; the getter is UI-layer state.

**How to apply:** Any code added to `_ps_playback_mixin.dart` that needs the live check must inline it directly:
```dart
widget.contentType == 'live'
```
Never reference `_isLive` from `_ps_playback_mixin.dart`. This was the root cause of CI fail on commit `89bb581b` (corrected by `aa997d82`).
