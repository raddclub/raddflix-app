// lib/core/theme/radd_colors.dart
//
// BuildContext extension — shorthand accessors for every RaddTheme token.
// Usage anywhere you have a BuildContext:
//   context.t.bg        → current theme background colour
//   context.t.textMuted → current theme muted text colour
//   context.t.border    → current theme border colour
//
// For hero gradient: context.t.heroGradient (LinearGradient)

import 'package:flutter/material.dart';
import 'radd_theme.dart';
import '../constants.dart' show AppColors;

extension RaddColors on BuildContext {
  // ── Quick access to the full token set ────────────────────────────────────
  /// Returns the RaddTheme for the current brightness (dark / amoled / light).
  RaddTheme get t => RaddTheme.of(this);

  // ── Keep existing named getters for backwards compat ──────────────────────
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get raddBg            => t.bg;
  Color get jazzText          => t.textPrimary;
  Color get raddTextSecondary => t.textSecondary;
  Color get raddTextMuted     => t.textMuted;
  Color get raddSurface       => t.surface;
  Color get raddCard          => t.card;
  Color get raddBorder        => t.border;

  LinearGradient get raddHeroGradient => t.heroGradient;

  // ── Semantic layer (Volume II) ────────────────────────────────────────────
  // The one "always on" interactive hue — CTAs, active states, live indicators.
  // Theme variants change background mood only; this stays constant.
  Color get signalPrimary     => AppColors.primary;
  Color get signalPrimaryGlow => AppColors.primaryGlow;

  /// Reserved EXCLUSIVELY for zero-rated/data-free indicators — never success,
  /// online, active, or downloaded states. See AI_RULES.md rule 7.
  Color get accentDataFree => AppColors.dataFree;
  Color get accentWarning  => AppColors.warning;
  Color get accentError    => AppColors.error;
}
