import 'anim_config.dart';

/// Tier-aware duration constants — always use these instead of hard-coded ms values.
///
/// Usage inside a ConsumerWidget:
///   final anim = ref.watch(animConfigProvider);
///   .animate().fadeIn(duration: anim.normal)
///
/// Usage inside a builder where ref is not available:
///   AnimDurations.morph   // fixed morph duration for OpenContainer
class AnimDurations {
  AnimDurations._();

  /// Quick micro-interactions (button taps, icon swaps).
  static Duration fast(AnimConfig cfg) => cfg.fast;

  /// Standard transitions (page elements, card entry).
  static Duration normal(AnimConfig cfg) => cfg.normal;

  /// Slower hero or background animations.
  static Duration slow(AnimConfig cfg) => cfg.slow;

  /// Stagger delay between consecutive list/grid items.
  static Duration stagger(AnimConfig cfg, int index) => cfg.stagger(index);

  /// Fixed morph duration for OpenContainer (animations package, Tier 2+).
  static const Duration morph = Duration(milliseconds: 400);

  // BB7 — controls show/hide animation durations.
  // Potato tier: 0ms (instant opacity only, no slide).
  // Basic+: slide+fade.

  /// Controls appear: 180ms easeOutCubic on basic+, instant on potato.
  static Duration controlsShow(AnimConfig cfg) =>
      cfg.tierLevel >= AnimTier.basic.index
          ? const Duration(milliseconds: 180)
          : Duration.zero;

  /// Controls hide: 140ms easeIn on basic+, instant on potato.
  static Duration controlsHide(AnimConfig cfg) =>
      cfg.tierLevel >= AnimTier.basic.index
          ? const Duration(milliseconds: 140)
          : Duration.zero;
}
