// lib/design_system/motion/radd_motion.dart
//
// RaddMotion — named curves AND durations for the Volume III motion language.
// All Duration constants are spec-exact values from the Volume III §table.
// Use these everywhere instead of ad hoc `Duration(milliseconds: ...)` literals.
//
// Rule (Volume VII): only use these named curves/durations in screen code,
// never raw Duration(milliseconds: ...) literals for design-system transitions.

import 'package:flutter/animation.dart';
import '../../core/utils/anim_config.dart';

class RaddMotion {
  RaddMotion._();

  // ── Curves ───────────────────────────────────────────────────────────────────

  /// Ambient pulse ring (live indicators, data-saved counter tick).
  /// Volume III: 1800ms loop, sin ease-in-out, opacity 1↔0.6 / scale 1↔1.03.
  static const Curve pulse = Curves.easeInOutSine;

  /// "Changing channel" snap-settle (chip selection, tab switch, quality toggle).
  /// Volume III: 200ms, spring ~8% overshoot — like a dial catching its notch.
  static const Curve tune = Curves.easeOutBack;

  /// Bottom-sheet entrance. Volume III: cubic (0.16, 1, 0.3, 1) — no bounce,
  /// sheets feel solid. Previously easeOutCubic (corrected 2026-07-10).
  static const Curve sheetEnter = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Bottom-sheet dismiss (accelerate out).
  /// Volume III: cubic (0.4, 0, 1, 1). Previously easeInCubic (corrected 2026-07-10).
  static const Curve sheetExit = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Shared-element Hero card→detail navigation.
  /// Volume III: cubic (0.2, 0, 0, 1).
  static const Curve heroTransition = Cubic(0.2, 0.0, 0.0, 1.0);

  // ── Durations (spec-exact from Volume III §table) ─────────────────────────────

  /// Pulse loop — always 1800ms regardless of device tier.
  /// Tier gating affects the scale component (potato drops scale, keeps opacity).
  static const Duration pulseDuration = Duration(milliseconds: 1800);

  /// "Tune" snap: chip select, tab switch, quality toggle.
  static const Duration tuneDuration = Duration(milliseconds: 200);

  /// Sheet entrance. Use with [sheetEnter].
  static const Duration sheetEnterDuration = Duration(milliseconds: 260);

  /// Sheet dismiss. Use with [sheetExit].
  static const Duration sheetExitDuration = Duration(milliseconds: 200);

  /// Card press — finger-down phase (scale 1→0.96). Use with [tune].
  static const Duration cardPressDown = Duration(milliseconds: 120);

  /// Card press — finger-up / release phase (scale 0.96→1). Use with [tune].
  static const Duration cardPressUp = Duration(milliseconds: 160);

  /// Shared-element Hero navigation. Use with [heroTransition].
  static const Duration heroDuration = Duration(milliseconds: 320);

  /// Duration for each rail / stagger item entrance animation.
  static const Duration railItemDuration = Duration(milliseconds: 240);

  /// Stagger delay between consecutive rail items.
  /// Cap stagger at the first 6 visible items; beyond that use 0ms delay.
  static const Duration railItemDelay = Duration(milliseconds: 40);

  /// Lock-pad numpad key tap — deliberately more playful than sheets.
  /// Volume III: 220ms, spring 12% overshoot.
  static const Duration lockKeyDuration = Duration(milliseconds: 220);

  /// Bottom-nav active icon crossfade (outline→fill). Volume III: 180ms ease.
  static const Duration bottomNavDuration = Duration(milliseconds: 180);

  /// Delay before the empty-state icon begins pulsing after screen mount.
  /// Avoids visual clutter during initial content load.
  static const Duration emptyStateDelay = Duration(milliseconds: 400);

  // ── Tier-aware helpers ────────────────────────────────────────────────────────

  /// Tier-aware sheet open/close — use instead of [sheetEnterDuration] when
  /// AnimConfig is available, so potato-tier devices still get a snappy transition.
  static Duration sheetDuration(AnimConfig cfg) => cfg.normal;

  /// Pulse loop duration (tier-aware signature; loop length is fixed at 1800ms
  /// but [cfg] lets call sites branch on tier for scale/opacity without a
  /// separate lookup).
  static Duration pulseDurationOf(AnimConfig cfg) => pulseDuration;
}
