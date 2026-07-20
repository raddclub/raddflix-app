import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
//  DataUsageRing  — compact animated arc widget for the Profile screen.
//  Shows a ~100×100 animated arc gauge with used/left labels and a
//  "View Details" arrow. Tap delegates to [onTap].
// ─────────────────────────────────────────────────────────────────────────────

class DataUsageRing extends StatefulWidget {
  final double usedGb;
  final double limitGb;
  final VoidCallback? onTap;

  const DataUsageRing({
    super.key,
    required this.usedGb,
    required this.limitGb,
    this.onTap,
  });

  @override
  State<DataUsageRing> createState() => _DataUsageRingState();
}

class _DataUsageRingState extends State<DataUsageRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anim = CurvedAnimation(parent: _ctrl, curve: AppCurves.standard);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(DataUsageRing old) {
    super.didUpdateWidget(old);
    if (old.usedGb != widget.usedGb || old.limitGb != widget.limitGb) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _color(double pct) {
    if (pct < 0.60) return AppColors.success;
    if (pct < 0.85) {
      return Color.lerp(AppColors.success, AppColors.warning,
          (pct - 0.60) / 0.25)!;
    }
    return Color.lerp(AppColors.warning, AppColors.error,
        (pct - 0.85) / 0.15)!;
  }

  @override
  Widget build(BuildContext context) {
    final t       = RaddTheme.of(context);
    final pct     = widget.limitGb > 0
        ? (widget.usedGb / widget.limitGb).clamp(0.0, 1.0)
        : 0.0;
    final gc      = _color(pct);
    final rem     = (widget.limitGb - widget.usedGb).clamp(0.0, widget.limitGb);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              gc.withOpacity(0.10),
              gc.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: gc.withOpacity(0.28)),
        ),
        child: Row(children: [
          // Compact arc ring
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => SizedBox(
              width: 88, height: 88,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size(88, 88),
                  painter: _CompactArcPainter(
                    progress:    pct * _anim.value,
                    arcColor:    gc,
                    bgColor:     t.border.withOpacity(0.4),
                    strokeWidth: 8.5,
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    widget.usedGb.toStringAsFixed(1),
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        height: 1.1),
                  ),
                  Text('GB',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ),

          const SizedBox(width: 14),

          // Stats column
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Data Usage',
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(
                widget.limitGb > 0
                    ? '${rem.toStringAsFixed(1)} GB left'
                    : 'Unlimited',
                style: TextStyle(
                    color: gc, fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.usedGb.toStringAsFixed(1)} of '
                '${widget.limitGb > 0 ? "${widget.limitGb.toInt()} GB" : "∞"} used',
                style: TextStyle(color: t.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              // Progress bar (secondary visual)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 4,
                  backgroundColor: gc.withOpacity(0.13),
                  valueColor: AlwaysStoppedAnimation(gc),
                ),
              ),
            ]),
          ),

          // Chevron
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(AppIcons.caretRight,
                color: t.textMuted.withOpacity(0.6), size: 16),
          ),
        ]),
      ).animate().fadeIn(duration: 300.ms)
          .slideY(begin: 0.1, end: 0, duration: 300.ms, curve: AppCurves.standard),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compact arc painter (same math as ArcGaugePainter, smaller)
// ─────────────────────────────────────────────────────────────────────────────

class _CompactArcPainter extends CustomPainter {
  final double progress;
  final Color  arcColor;
  final Color  bgColor;
  final double strokeWidth;

  const _CompactArcPainter({
    required this.progress,
    required this.arcColor,
    required this.bgColor,
    required this.strokeWidth,
  });

  static const double _startDeg = 150.0;
  static const double _sweepDeg = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = cx - strokeWidth / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final startRad = _startDeg * pi / 180;
    final sweepRad = _sweepDeg * pi / 180;

    canvas.drawArc(rect, startRad, sweepRad, false,
        Paint()
          ..color       = bgColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap   = StrokeCap.round);

    if (progress <= 0) return;

    final fillRad = sweepRad * progress;
    canvas.drawArc(rect, startRad, fillRad, false,
        Paint()
          ..color       = arcColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap   = StrokeCap.round);

    if (progress > 0.03) {
      final endAngle = startRad + fillRad;
      final tx = cx + r * cos(endAngle);
      final ty = cy + r * sin(endAngle);
      canvas.drawCircle(
        Offset(tx, ty),
        strokeWidth * 0.6,
        Paint()
          ..color      = arcColor.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_CompactArcPainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}
