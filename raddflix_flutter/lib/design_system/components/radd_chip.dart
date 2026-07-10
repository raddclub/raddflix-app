// lib/design_system/components/radd_chip.dart
//
// RaddChip — Volume IV. Height 36dp, pill radius, 16dp horizontal padding.
// `isDataFreeVariant` swaps the active fill to accent.dataFree — the one
// deliberate exception ("Free tonight" mood chip) to keep signal-green
// meaningful; never set it true for a generic active chip.

import 'package:flutter/material.dart';
import '../../core/theme/radd_colors.dart';
import '../radius/radd_radius.dart';
import '../motion/radd_motion.dart';

class RaddChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool isDataFreeVariant;
  final VoidCallback? onTap;

  const RaddChip({
    super.key,
    required this.label,
    this.active = false,
    this.isDataFreeVariant = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final Color activeFill = isDataFreeVariant ? context.accentDataFree : context.signalPrimary;
    final Color bg = active ? activeFill : t.glass;
    final Color fg = active ? Colors.white : t.textSecondary;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: RaddMotion.tuneDuration, // Volume III spec-exact (was hardcoded 200ms)
          curve: RaddMotion.tune,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: bg, borderRadius: RaddRadius.pillRadius),
          alignment: Alignment.center,
          child: Text(
            label,
            style: context.raddLabel.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
