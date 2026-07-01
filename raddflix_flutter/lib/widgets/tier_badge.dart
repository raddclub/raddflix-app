/// Phase 56 — Subscription tier badge with glow.
/// Reusable pill badge for FREE / STANDARD / PREMIUM plans, used on the
/// profile screen and the subscription/paywall screen so the tier styling
/// stays consistent everywhere it appears.
library tier_badge;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/utils/anim_config.dart';

enum SubscriptionTier { free, standard, premium }

SubscriptionTier tierFromPlanName(String planName) {
  final p = planName.toUpperCase();
  if (p.contains('PREMIUM') || p.contains('GOLD')) return SubscriptionTier.premium;
  if (p.contains('STANDARD') || p.contains('SILVER')) return SubscriptionTier.standard;
  return SubscriptionTier.free;
}

class _TierStyle {
  final String emoji;
  final Color color;
  final List<Color> glowGradient;
  const _TierStyle(this.emoji, this.color, this.glowGradient);
}

const _tierStyles = {
  SubscriptionTier.free: _TierStyle('🎬', Color(0xFF9CA3AF), [Color(0xFF9CA3AF), Color(0xFF9CA3AF)]),
  SubscriptionTier.standard: _TierStyle('⭐', Color(0xFF3B82F6), [Color(0xFF3B82F6), Color(0xFF60A5FA)]),
  SubscriptionTier.premium: _TierStyle('👑', Color(0xFFFBBF24), [Color(0xFFFBBF24), Color(0xFFF59E0B)]),
};

/// Pill badge showing the user's current plan name with a tier-appropriate
/// glow. Premium/Standard get a slow breathing glow pulse on Tier 1+ devices;
/// Free and low-end/reduced-motion devices get a static soft glow.
class TierBadge extends ConsumerStatefulWidget {
  final String planName;
  final double fontSize;
  final EdgeInsets padding;

  const TierBadge({
    super.key,
    required this.planName,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
  });

  @override
  ConsumerState<TierBadge> createState() => _TierBadgeState();
}

class _TierBadgeState extends ConsumerState<TierBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    final tier = tierFromPlanName(widget.planName);
    if (tier != SubscriptionTier.free) {
      final animConfig = ref.read(animConfigProvider);
      final shouldPulse = animConfig.tierLevel >= AnimTier.basic.index &&
          animConfig.shouldAnimate(context);
      if (shouldPulse) {
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2000))
          ..repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = tierFromPlanName(widget.planName);
    final style = _tierStyles[tier]!;

    Widget buildPill(double glowT) {
      final glowOpacity = 0.10 + glowT * 0.18;
      final glowBlur = 10.0 + glowT * 10.0;
      return Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            style.color.withOpacity(0.14),
            style.color.withOpacity(0.06),
          ]),
          borderRadius: BorderRadius.circular(AppRadius.round),
          border: Border.all(color: style.color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: style.color.withOpacity(glowOpacity),
              blurRadius: glowBlur,
              spreadRadius: tier == SubscriptionTier.premium ? 1.5 : 0.5,
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(style.emoji, style: TextStyle(fontSize: widget.fontSize + 2)),
          const SizedBox(width: 5),
          Text(
            widget.planName.toUpperCase(),
            style: TextStyle(
              color: style.color,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ]),
      );
    }

    if (_ctrl == null) return buildPill(0.5);

    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (_, __) => buildPill(_ctrl!.value),
    );
  }
}
