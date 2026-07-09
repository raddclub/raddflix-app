---
name: RaddColors has no gradient getter
description: context.signalPrimaryGradient does not exist — use AppColors.primaryGradient instead for primary-color gradients.
---

## Rule

`RaddColors` (the `BuildContext` extension in `lib/core/theme/radd_colors.dart`) provides color
getters like `context.signalPrimary`, `context.accentError`, etc. **It has no gradient getter.**
There is no `context.signalPrimaryGradient` or similar.

**Why:** The `RaddColors` extension was built as a color accessor layer, not a gradient layer.
Gradient definitions live in `AppColors` as static consts.

**How to apply:** Any LinearGradient using the primary brand color must use:
```dart
AppColors.primaryGradient
```
Both files already import `'../core/constants.dart'` (where `AppColors` is defined), so no extra
import is needed in any screen that already uses `AppColors.*` or `AppCurves.*` or `AppShadows.*`.

**Evidence:** Prior session introduced `context.signalPrimaryGradient` in `login_screen.dart` and
`register_screen.dart` — caused 2 consecutive CI failures (`8a84428`, `329738b`). Fixed in
`4ee0215` by replacing with `AppColors.primaryGradient`.
