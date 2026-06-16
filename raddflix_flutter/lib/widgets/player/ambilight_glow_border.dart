import 'package:flutter/material.dart';
import '../../../core/player/ambilight_controller.dart';

/// Wraps [child] with a 4-side ambilight glow driven by [colors].
class AmbilightGlowBorder extends StatelessWidget {
  final Widget child;
  final AmbilightColors colors;
  final double intensity;
  final double blurRadius;

  const AmbilightGlowBorder({
    super.key,
    required this.child,
    required this.colors,
    this.intensity = 0.7,
    this.blurRadius = 40,
  });

  BoxShadow _glow(Color c, Offset offset) => BoxShadow(
    color: c.withOpacity(intensity * 0.85),
    blurRadius: blurRadius,
    spreadRadius: 4,
    offset: offset,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        boxShadow: [
          _glow(colors.top,    const Offset(0, -8)),
          _glow(colors.bottom, const Offset(0,  8)),
          _glow(colors.left,   const Offset(-8, 0)),
          _glow(colors.right,  const Offset( 8, 0)),
        ],
      ),
      child: child,
    );
  }
}
