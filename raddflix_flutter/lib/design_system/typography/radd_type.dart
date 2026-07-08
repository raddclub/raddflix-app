// lib/design_system/typography/radd_type.dart
//
// RaddType — the app-wide type scale (Volume II), exposed as a BuildContext
// extension so every style inherits the active brand font + text color from
// JazzThemeData.build() (see core/theme/app_theme.dart) instead of hardcoding
// a font family here.
//
// Usage: context.raddDisplay, context.raddHeadline, context.raddTitle, etc.
// Max three distinct type sizes visible within a single screen section
// (Volume II rule) — don't reach for `display` or `headline` casually.

import 'package:flutter/material.dart';

extension RaddType on BuildContext {
  TextStyle get _base => Theme.of(this).textTheme.bodyMedium ?? const TextStyle();

  /// Hero title on Home, splash wordmark. 34sp / w900, -0.5 tracking.
  TextStyle get raddDisplay =>
      _base.copyWith(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  /// Screen titles, Detail show title. 24sp / w800.
  TextStyle get raddHeadline =>
      _base.copyWith(fontSize: 24, fontWeight: FontWeight.w800);

  /// Section headers ("Trending", "Continue Watching"). 18sp / w700.
  TextStyle get raddTitle =>
      _base.copyWith(fontSize: 18, fontWeight: FontWeight.w700);

  /// Descriptions, synopsis. 15sp / w500.
  TextStyle get raddBody =>
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w500);

  /// Metadata emphasis (runtime, rating). 15sp / w700.
  TextStyle get raddBodyStrong =>
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700);

  /// Chips, badges, tab labels. 13sp / w600, +0.2 tracking, uppercase at call site.
  /// Never use for body text (Volume II rule: no uppercase body text).
  TextStyle get raddLabel =>
      _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  /// Timestamps, secondary metadata. 12sp / w500.
  TextStyle get raddCaption =>
      _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500);

  /// Reserved for the data-saved counter and quota numbers only — a distinct
  /// "big number" style used nowhere else. 32sp / w900, tabular figures.
  TextStyle get raddSignalNumeral => _base.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
