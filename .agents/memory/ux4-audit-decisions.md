---
name: UX4 audit decisions
description: Which audit findings are deferred or N/A, and why; confirmed locations of existing features
---

## Deferred — do not implement until dependency exists

**Forgot Password flow (#5 from audit)**
Rule: Do not add. No OTP service exists yet. When OTP is added in future, the forgot-password screen becomes viable.
**Why:** Building the UI now would show a non-functional flow to users. Defer until backend `/api/auth/forgot-password` + SMS OTP is ready.

## N/A — not a gap

**Video quality selector (#10 from audit)**
Rule: Do not add a quality picker. Each video has exactly one quality file on the server; there is no multi-bitrate CDN or adaptive streaming. A selector would be a fake control.
**Why:** The "Data Saver" toggle in Settings already exists for reduced buffering. That is the correct surface for bandwidth control.

## Confirmed existing features

**Theme toggle**
Location: `profile_screen.dart` — "Appearance" section, `_SectionTile(label: 'Theme', onTap: () => _showThemePicker(context))`.
The full picker is `_ThemePicker` (private class in that file), also `_ThemeTrailing` for the current-theme swatch.
Task UX4-05 promotes `_ThemePicker` to a shared widget and adds it to `settings_screen.dart` too.
