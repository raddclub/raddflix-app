import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/anim_config.dart';

/// Animated glowing tier badge — FREE (grey) / STANDARD (blue) / PREMIUM (gold).
/// Tier-gated: basic+ (API 23+) gets a pulsing glow; potato gets a static badge.
/// Respects MediaQuery.disableAnimations.
class TierBadge extends ConsumerStatefulWidget {
  final String plan;
  const TierBadge({super.key, required this.plan});

  @override
  ConsumerState<TierBadge> createState() => _TierBadgeState();
}

class _TierBadgeState extends ConsumerState<TierBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  static Color _auraFor(String plan) {
    final p = plan.toUpperCase();
    if (p.contains('PREMIUM') || p.contains('GOLD')) return const Color(0xFFFFB300);
    if (p.contains('STANDARD') || p.contains('SILVER')) return const Color(0xFF2196F3);
    return const Color(0xFF9E9E9E);
  }

  static String _labelFor(String plan) {
    final p = plan.toUpperCase();
    if (p.contains('PREMIUM') || p.contains('GOLD')) return 'PREMIUM';
    if (p.contains('STANDARD') || p.contains('SILVER')) return 'STANDARD';
    return 'FREE';
  }

  static String _emojiFor(String plan) {
    final p = plan.toUpperCase();
    if (p.contains('PREMIUM') || p.contains('GOLD')) return '\u{1F451}';
    if (p.contains('STANDARD') || p.contains('SILVER')) return '\u2B50';
    return '\u{1F3AC}';
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aura  = _auraFor(widget.plan);
    final label = _labelFor(widget.plan);
    final emoji = _emojiFor(widget.plan);

    final animConfig   = ref.read(animConfigProvider);
    final disableAnim  = MediaQuery.of(context).disableAnimations;
    final shouldGlow   = animConfig.canStagger && !disableAnim;

    final inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: aura.withOpacity(0.13),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: aura.withOpacity(0.55), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            color: aura, fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      ]),
    );

    if (!shouldGlow) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: aura.withOpacity(0.18), blurRadius: 10)],
        ),
        child: inner,
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: aura.withOpacity(0.10 + 0.22 * _ctrl.value),
                blurRadius: 6 + 16 * _ctrl.value,
                spreadRadius: _ctrl.value * 2.5,
              ),
            ],
          ),
          child: child,
        ),
        child: inner,
      ),
    );
  }
}
