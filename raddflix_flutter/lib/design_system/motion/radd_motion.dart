// lib/design_system/motion/radd_motion.dart
//
// RaddMotion — named curves for the two Volume III motion signatures, plus
// sheet-entrance/dismiss curves. Wraps the existing AnimConfig tier/duration
// system (core/utils/anim_config.dart) rather than replacing it — that file
// already implements the device-tier gating logic.
//
// Rule (Volume VII): only use these named curves in screen code, no ad hoc
// `Duration(milliseconds: ...)` literals.

import 'package:flutter/animation.dart';
import '../../core/utils/anim_config.dart';

class RaddMotion {
  RaddMotion._();

  /// Ambient pulse ring (On Air "live" indicator, data-saved counter tick).
  /// Volume III: 1800ms loop, sin ease-in-out, opacity 1↔0.6 / scale 1↔1.03.
  static const Curve pulse = Curves.easeInOutSine;

  /// "Changing channel" snap-settle (chip selection, tab switch, quality
  /// toggle). Volume III: 200ms, spring with ~8% overshoot — "a dial
  /// catching its notch." `easeOutBack` is the app's existing spring-style
  /// curve (see `AppCurves.expressiveSpring` in core/constants.dart).
  static const Curve tune = Curves.easeOutBack;

  /// Bottom-sheet entrance (RaddSheet and friends).
  static const Curve sheetEnter = Curves.easeOutCubic;

  /// Bottom-sheet dismiss.
  static const Curve sheetExit = Curves.easeInCubic;

  /// Tier-aware duration for a sheet open/close — delegates to AnimConfig so
  /// potato-tier devices still get a fast, jank-free transition.
  static Duration sheetDuration(AnimConfig cfg) => cfg.normal;

  /// Duration for an ambient pulse loop. Volume III: always 1800ms — tier
  /// gating affects the scale component (potato tier drops scale, keeps
  /// opacity-only), not the loop duration itself. `cfg` is kept in the
  /// signature so call sites can still branch on tier for the scale/opacity
  /// split without a second lookup.
  static Duration pulseDuration(AnimConfig cfg) =>
      const Duration(milliseconds: 1800);
}
