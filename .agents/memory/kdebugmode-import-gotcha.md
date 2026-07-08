---
name: kDebugMode gating needs explicit import
description: Gating debugPrint/print calls with `if (kDebugMode)` silently broke the RaddFlix release APK build because two files lacked the foundation.dart import — a lesson about verifying builds, not just diffs, after this class of edit.
---

# kDebugMode Import Gotcha

## What happened
A prior session (Rule 21 cleanup) added `if (kDebugMode) debugPrint(...)` guards across
several Dart files. Two of them (`player_screen.dart`, `subscription_screen.dart`) did not
already import `package:flutter/foundation.dart`, so `kDebugMode` was an undefined getter.
This is **not** caught by casual reading/diff review — it only surfaces as a compile error
at `flutter build apk`. It silently broke the GitHub Actions APK build for an entire day
(two push-triggered CI runs both failed with `kernel_snapshot failed: Exception`) before
being caught.

## The rule
Any time `kDebugMode` (or any other symbol from `flutter/foundation.dart`, e.g. `kReleaseMode`,
`kIsWeb`, `defaultTargetPlatform`) is introduced into a Dart file, verify the file already has:
```dart
import 'package:flutter/foundation.dart' show kDebugMode;
```
Do not assume `package:flutter/material.dart` transitively exposes it in a way the analyzer
will accept in every context — check explicitly, per file, every time.

## How to apply
- After any Rule-21-style "gate debug prints" edit batch, treat it as incomplete until either:
  (a) a local `flutter analyze` / `flutter build` is run, or
  (b) every touched file is grepped for `flutter/foundation.dart` in its import block.
- For a Flutter project with CI (GitHub Actions `build-apk.yml` or similar), a broken build
  can go unnoticed for a long time if nobody watches workflow run status — proactively check
  `gh` / GitHub Actions API run conclusions after any push that touches `raddflix_flutter/**`,
  don't assume "pushed" means "builds".
