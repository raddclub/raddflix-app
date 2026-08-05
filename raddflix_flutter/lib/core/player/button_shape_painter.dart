/// Phase A3 — Button Shape System
/// Provides shape variants for player control buttons (play/pause, seek, etc.).
/// Shapes: circle (default), squircle, rounded, sharp, pill.
library button_shape_painter;

import 'package:flutter/material.dart';

/// Shape options for player control buttons.
/// Stored in [PlayerPrefs.buttonShape] as a string (e.g. 'circle', 'squircle').
enum ButtonShape { circle, squircle, rounded, sharp, pill }

ButtonShape buttonShapeFromString(String s) =>
    ButtonShape.values.firstWhere((e) => e.name == s,
        orElse: () => ButtonShape.circle);

/// Returns the [BoxDecoration] for a player button of the given [shape] and [size].
///
/// For [ButtonShape.squircle] the decoration uses a rounded rect — the true
/// squircle clip is applied by [wrapWithButtonShape] via [SquircleClipper].
BoxDecoration playerBtnDecoration({
  required ButtonShape shape,
  required double size,
  Color? fillColor,
  Color? borderColor,
}) {
  final fill   = fillColor   ?? Colors.white.withOpacity(0.12);
  final border = borderColor ?? Colors.white.withOpacity(0.35);
  switch (shape) {
    case ButtonShape.circle:
      return BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: 1.2),
      );
    case ButtonShape.squircle:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.30),
        color: fill,
        border: Border.all(color: border, width: 1.2),
      );
    case ButtonShape.rounded:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: fill,
        border: Border.all(color: border, width: 1.2),
      );
    case ButtonShape.sharp:
      return BoxDecoration(
        borderRadius: BorderRadius.zero,
        color: fill,
        border: Border.all(color: border, width: 1.2),
      );
    case ButtonShape.pill:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(size),
        color: fill,
        border: Border.all(color: border, width: 1.2),
      );
  }
}

/// Wraps [child] in a [size]×[size] container with the chosen button [shape].
///
/// Squircle: applies a [ClipPath] with [SquircleClipper] for the iOS-style
/// continuous-corner curve.  All other shapes are handled by [BoxDecoration].
Widget wrapWithButtonShape({
  required ButtonShape shape,
  required double size,
  required Widget child,
  Color? fillColor,
  Color? borderColor,
}) {
  final decoration = playerBtnDecoration(
    shape: shape,
    size: size,
    fillColor: fillColor,
    borderColor: borderColor,
  );

  final container = Container(
    width: size,
    height: size,
    decoration: decoration,
    alignment: Alignment.center,
    child: child,
  );

  if (shape == ButtonShape.squircle) {
    return ClipPath(
      clipper: SquircleClipper(size: size),
      child: container,
    );
  }
  return container;
}

/// Custom clipper that approximates the iOS continuous-corner squircle shape.
///
/// Uses cubic Bézier segments with a control-point offset of ≈ 0.552 * r
/// (the standard tangent approximation for a quarter-circle arc).  The
/// result closely matches Apple's home-screen icon rounding.
class SquircleClipper extends CustomClipper<Path> {
  final double size;
  const SquircleClipper({required this.size});

  @override
  Path getClip(Size s) {
    final r = size * 0.275; // corner radius — ~27.5% of size matches iOS icons
    final c = r * 0.552;    // bézier control-point offset ≈ 0.552 * r
    final w = s.width;
    final h = s.height;

    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..cubicTo(w - c, 0,   w,   c,   w,   r)
      ..lineTo(w, h - r)
      ..cubicTo(w,   h - c, w - c, h,   w - r, h)
      ..lineTo(r, h)
      ..cubicTo(c,   h,   0,   h - c, 0,   h - r)
      ..lineTo(0, r)
      ..cubicTo(0,   c,   c,   0,   r,   0)
      ..close();
  }

  @override
  bool shouldReclip(SquircleClipper o) => o.size != size;
}
