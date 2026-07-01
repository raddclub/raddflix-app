/// Phase 52 — Animated Empty States
/// Reusable looping CustomPainter animations for empty-state screens.
/// Tier-gated: below AnimTier.basic or when disableAnimations is set,
/// widgets render a single static frame with no AnimationController.
library animated_empty_icons;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/anim_config.dart';

bool _canAnimateEmptyState(BuildContext context, WidgetRef ref) {
  final animConfig = ref.watch(animConfigProvider);
  return animConfig.canStagger && animConfig.shouldAnimate(context);
}

// ── 1. Magnifying glass sweep — search empty state ──────────────────────────

class AnimatedSearchIcon extends ConsumerStatefulWidget {
  final double size;
  final Color color;
  const AnimatedSearchIcon({super.key, this.size = 64, required this.color});

  @override
  ConsumerState<AnimatedSearchIcon> createState() => _AnimatedSearchIconState();
}

class _AnimatedSearchIconState extends ConsumerState<AnimatedSearchIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  void _ensureController(bool animate) {
    if (animate && _ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat();
    } else if (!animate && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = _canAnimateEmptyState(context, ref);
    _ensureController(animate);
    if (_ctrl == null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SearchSweepPainter(t: 0, color: widget.color),
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl!,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _SearchSweepPainter(t: _ctrl!.value, color: widget.color),
        ),
      ),
    );
  }
}

class _SearchSweepPainter extends CustomPainter {
  final double t; // 0..1 loop
  final Color color;
  _SearchSweepPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.44, size.height * 0.44);
    final radius = size.width * 0.28;

    final glassPaint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.055
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Sweeping arc inside the lens — 0..2π loop, trims to a short arc segment.
    final sweepStart = t * 2 * math.pi;
    final sweepPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = size.width * 0.03
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.62),
      sweepStart, math.pi * 0.55, false, sweepPaint,
    );

    // Lens circle
    canvas.drawCircle(center, radius, glassPaint);

    // Handle
    final handleAngle = math.pi / 4;
    final handleStart = center + Offset(math.cos(handleAngle), math.sin(handleAngle)) * radius;
    final handleEnd = handleStart + Offset(math.cos(handleAngle), math.sin(handleAngle)) * (size.width * 0.26);
    canvas.drawLine(handleStart, handleEnd, glassPaint);

    // Gentle pulse ring — expands and fades, loops
    final pulseT = t; // 0..1
    final pulseRadius = radius * (1.0 + pulseT * 0.5);
    final pulsePaint = Paint()
      ..color = color.withOpacity((1 - pulseT) * 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, pulseRadius, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _SearchSweepPainter old) => old.t != t;
}

// ── 2. Cloud-down arrow — downloads empty state ─────────────────────────────

class AnimatedCloudDownIcon extends ConsumerStatefulWidget {
  final double size;
  final Color color;
  const AnimatedCloudDownIcon({super.key, this.size = 64, required this.color});

  @override
  ConsumerState<AnimatedCloudDownIcon> createState() => _AnimatedCloudDownIconState();
}

class _AnimatedCloudDownIconState extends ConsumerState<AnimatedCloudDownIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  void _ensureController(bool animate) {
    if (animate && _ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat();
    } else if (!animate && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = _canAnimateEmptyState(context, ref);
    _ensureController(animate);
    if (_ctrl == null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _CloudDownPainter(t: 0, color: widget.color),
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl!,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _CloudDownPainter(t: _ctrl!.value, color: widget.color),
        ),
      ),
    );
  }
}

class _CloudDownPainter extends CustomPainter {
  final double t;
  final Color color;
  _CloudDownPainter({required this.t, required this.color});

  Path _cloudPath(Size size) {
    final w = size.width, h = size.height;
    final path = Path();
    // Simple layered-bump cloud silhouette.
    path.moveTo(w * 0.22, h * 0.5);
    path.cubicTo(w * 0.05, h * 0.5, w * 0.05, h * 0.28, w * 0.24, h * 0.26);
    path.cubicTo(w * 0.28, h * 0.08, w * 0.58, h * 0.06, w * 0.66, h * 0.24);
    path.cubicTo(w * 0.88, h * 0.2, w * 0.95, h * 0.42, w * 0.8, h * 0.5);
    path.cubicTo(w * 0.95, h * 0.5, w * 0.95, h * 0.68, w * 0.78, h * 0.68);
    path.lineTo(w * 0.22, h * 0.68);
    path.cubicTo(w * 0.05, h * 0.68, w * 0.05, h * 0.5, w * 0.22, h * 0.5);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cloudPaint = Paint()..color = color.withOpacity(0.9)..style = PaintingStyle.fill;
    canvas.drawPath(_cloudPath(size), cloudPaint);

    // Arrow bobbing down below the cloud, looping with a fade on the drop.
    final arrowColor = color;
    final bobT = (t < 0.7) ? (t / 0.7) : 1.0; // 0..1 travel phase
    final fadeT = (t < 0.7) ? 1.0 : (1.0 - (t - 0.7) / 0.3); // fade out near end
    final startY = size.height * 0.74;
    final endY = size.height * 0.98;
    final y = startY + (endY - startY) * bobT;
    final cx = size.width * 0.5;

    final arrowPaint = Paint()
      ..color = arrowColor.withOpacity(fadeT.clamp(0.0, 1.0))
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(cx, size.height * 0.74), Offset(cx, y), arrowPaint);

    final headSize = size.width * 0.09;
    final headPaint = Paint()
      ..color = arrowColor.withOpacity(fadeT.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - headSize, y - headSize), Offset(cx, y), headPaint);
    canvas.drawLine(Offset(cx + headSize, y - headSize), Offset(cx, y), headPaint);
  }

  @override
  bool shouldRepaint(covariant _CloudDownPainter old) => old.t != t;
}

// ── 3. Wifi-off pulse — no-internet / local-media empty state ───────────────

class AnimatedWifiOffIcon extends ConsumerStatefulWidget {
  final double size;
  final Color color;
  const AnimatedWifiOffIcon({super.key, this.size = 64, required this.color});

  @override
  ConsumerState<AnimatedWifiOffIcon> createState() => _AnimatedWifiOffIconState();
}

class _AnimatedWifiOffIconState extends ConsumerState<AnimatedWifiOffIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  void _ensureController(bool animate) {
    if (animate && _ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();
    } else if (!animate && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = _canAnimateEmptyState(context, ref);
    _ensureController(animate);
    if (_ctrl == null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _WifiOffPulsePainter(t: 0, color: widget.color),
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl!,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _WifiOffPulsePainter(t: _ctrl!.value, color: widget.color),
        ),
      ),
    );
  }
}

class _WifiOffPulsePainter extends CustomPainter {
  final double t;
  final Color color;
  _WifiOffPulsePainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.72);
    final maxRadius = size.width * 0.42;

    // Three concentric arcs, each pulsing outward on a staggered phase.
    for (int i = 0; i < 3; i++) {
      final phase = ((t + i * 0.18) % 1.0);
      final opacity = (1.0 - phase) * 0.7;
      final radius = maxRadius * (0.35 + 0.22 * i) * (0.85 + phase * 0.3);
      final paint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.0, 1.0))
        ..strokeWidth = size.width * 0.045
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi + math.pi * 0.28,
        math.pi * 0.44,
        false,
        paint,
      );
    }

    // Dot
    canvas.drawCircle(center, size.width * 0.035, Paint()..color = color);

    // Slash through everything, static
    final slashPaint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.16),
      Offset(size.width * 0.84, size.height * 0.84),
      slashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WifiOffPulsePainter old) => old.t != t;
}
