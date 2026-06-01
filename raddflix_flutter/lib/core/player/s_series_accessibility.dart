/// Phase S — Extended Accessibility
/// S1 — Screen Reader Optimisation (semantic labels on all player controls)
/// S2 — High Contrast Mode (system-aware + manual override)
/// S3 — Reduced Motion Mode (disable all animations)
/// S4 — Focus Ring Mode (keyboard/switch-access visible focus indicators)
library s_series;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// S2 — High Contrast
// ─────────────────────────────────────────────────────────────────────────────

enum ContrastMode { system, standard, high, max }

const contrastModeLabels = {
  ContrastMode.system:   '🤖 System Default',
  ContrastMode.standard: '⬜ Standard',
  ContrastMode.high:     '◼ High Contrast',
  ContrastMode.max:      '⬛ Maximum Contrast',
};

ContrastMode contrastModeFromString(String s) =>
    ContrastMode.values.firstWhere((v) => v.name == s,
        orElse: () => ContrastMode.system);

/// Apply contrast-mode overrides to widget colours.
Color applyContrast(Color base, ContrastMode mode) {
  switch (mode) {
    case ContrastMode.high:
      // Boost luminance toward white or black
      final hsl = HSLColor.fromColor(base);
      return hsl.lightness > 0.5
          ? hsl.withLightness(1.0).toColor()
          : hsl.withLightness(0.0).toColor();
    case ContrastMode.max:
      final lum = base.computeLuminance();
      return lum > 0.5 ? Colors.white : Colors.black;
    default:
      return base;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// S3 — Reduced Motion wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps an [AnimatedContainer] but instantly snaps when [reducedMotion] is on.
class AdaptiveAnimated extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final bool reducedMotion;
  final Decoration? decoration;
  final double? width;
  final double? height;

  const AdaptiveAnimated({
    super.key,
    required this.child,
    required this.duration,
    required this.reducedMotion,
    this.decoration,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final d = reducedMotion ? Duration.zero : duration;
    return AnimatedContainer(
      duration: d,
      decoration: decoration,
      width: width,
      height: height,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// S1 — Semantic player button wrapper
// ─────────────────────────────────────────────────────────────────────────────

class SemanticPlayerButton extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;

  const SemanticPlayerButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.hint,
    this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// S4 — Focus Ring (visible keyboard/switch focus indicator)
// ─────────────────────────────────────────────────────────────────────────────
class FocusRing extends StatefulWidget {
  final Widget child;
  final Color ringColor;
  final bool enabled;

  const FocusRing({
    super.key,
    required this.child,
    required this.ringColor,
    this.enabled = true,
  });

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? widget.ringColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
