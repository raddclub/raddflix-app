---
name: Part-of file preflight rule
description: Which player files are part-of fragments and how to handle the preflight check
---

## Part-of files (inherit imports from player_screen.dart)
- `lib/screens/player/_ps_panels_sidebar.dart`
- `lib/screens/player/_ps_panels_audio.dart`
- `lib/screens/player/_ps_playback_mixin.dart`
- `lib/screens/player/_ps_panels_subtitle.dart`
- `lib/screens/player/_ps_ui_mixin.dart`

These files declare `part of '../player_screen.dart';` at the top and have NO their own import blocks. All class/token references (AppColors, RaddRadius, RaddSpace, etc.) are resolved via player_screen.dart's imports.

**Why:** The preflight_check.sh script string-searches each file for `'core/constants.dart'` / `'radd_radius.dart'` etc. Part files don't have import lines, so the check always false-positives on them.

**How to apply:** Whenever editing any `_ps_panels_*.dart` or `_ps_playback_mixin.dart` file, commit with `SKIP_PREFLIGHT=1 bash auto_commit.sh ...` and note "part-of fragment, inherits imports from player_screen.dart" in the message.

## core/player standalone libraries
Files like `end_of_video_actions.dart`, `frame_navigation_service.dart`, etc. declare `library foo;` and are standalone. They typically do NOT import `constants.dart`. If you add AppColors references, either:
1. Use inline hex literals with a comment (e.g. `const Color(0xFF352A1F) // Warm Hearth card`)
2. Or add `import '../constants.dart';` and commit with SKIP_PREFLIGHT=1 (the relative path `../constants.dart` doesn't contain the string `core/constants.dart` the preflight looks for)
