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
  static const Curve pulse = Curves.easeInOutSine;

  /// On Air hero item swipe/settle transition.
  static const Curve tune = Curves.easeOutCubic;

  /// Bottom-sheet entrance (RaddSheet and friends).
  static const Curve sheetEnter = Curves.easeOutCubic;

  /// Bottom-sheet dismiss.
  static const Curve sheetExit = Curves.easeInCubic;

  /// Tier-aware duration for a sheet open/close — delegates to AnimConfig so
  /// potato-tier devices still get a fast, jank-free transition.
  static Duration sheetDuration(AnimConfig cfg) => cfg.normal;

  /// Tier-aware duration for an ambient pulse loop.
  static Duration pulseDuration(AnimConfig cfg) =>
      Duration(milliseconds: cfg.tierLevel == 0 ? 800 : 1200);
}
