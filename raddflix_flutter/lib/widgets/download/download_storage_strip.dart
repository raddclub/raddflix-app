// lib/widgets/download/download_storage_strip.dart
//
// DOWNLOAD-TAB-V2: always-visible storage summary strip for the Download tab.
// Phase-DS: upgraded with an animated arc/radial storage meter showing used vs
// free space. Arc entrance is a one-shot TweenAnimationBuilder sweep (no
// controller needed). BackdropFilter gated on animConfig.canBlur via
// ConsumerWidget; solid fallback for low-tier devices.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/design/app_icons.dart';
import '../../core/theme/radd_theme.dart';
import '../../core/utils/anim_config.dart';

class DownloadStorageStrip extends ConsumerWidget {
  final int totalBytes;
  final int completedCount;
  final int totalCount;
  final int activeCount;
  final double? freeMB;

  const DownloadStorageStrip({
    super.key,
    required this.totalBytes,
    required this.completedCount,
    required this.totalCount,
    required this.activeCount,
    this.freeMB,
  });

  static String _fmtSize(int bytes) {
    if (bytes == 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Fraction of device storage used by downloads: usedBytes / totalDeviceBytes.
  /// If freeMB is null we fall back to a usage-only visual (no free context).
  double _usedFraction() {
    if (freeMB == null || freeMB! <= 0) return 0;
    final usedMB = totalBytes / (1024 * 1024);
    final totalMB = usedMB + freeMB!;
    if (totalMB <= 0) return 0;
    return (usedMB / totalMB).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RaddTheme.of(context);
    final animConfig = ref.read(animConfigProvider);

    final freeStr = freeMB != null
        ? (freeMB! >= 1024
            ? '${(freeMB! / 1024).toStringAsFixed(1)} GB free'
            : '${freeMB!.toStringAsFixed(0)} MB free')
        : null;

    final usedFraction = _usedFraction();
    final freeColor = (freeMB ?? 999) < 200
        ? AppColors.error
        : (freeMB ?? 999) < 500
            ? AppColors.warning
            : t.textMuted;

    // Glass decoration (blur gated on canBlur)
    final decoration = BoxDecoration(
      color: animConfig.canBlur
          ? t.surface.withOpacity(0.72)
          : t.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: t.border, width: 0.8),
      boxShadow: AppShadows.glassCard,
    );

    Widget stripContent = Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: decoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // ── Animated arc meter ─────────────────────────────────────────────
          _ArcMeter(
            fraction: usedFraction,
            animate: animConfig.canStagger,
            t: t,
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_fmtSize(totalBytes),
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              Text(' downloaded',
                  style: TextStyle(color: t.textMuted, fontSize: 12)),
              const Spacer(),
              if (activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.22), width: 0.5),
                  ),
                  child: Text('$activeCount loading',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Text('$completedCount done',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
              Text(' · ', style: TextStyle(color: t.textMuted)),
              Text('$totalCount total',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
              if (freeStr != null) ...[
                Text(' · ', style: TextStyle(color: t.textMuted)),
                Text(freeStr,
                    style: TextStyle(
                        color: freeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ]),
          ])),
        ]),
      ),
    );

    if (animConfig.canBlur) {
      stripContent = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            decoration: decoration,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                _ArcMeter(
                  fraction: usedFraction,
                  animate: animConfig.canStagger,
                  t: t,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(_fmtSize(totalBytes),
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(' downloaded',
                        style: TextStyle(color: t.textMuted, fontSize: 12)),
                    const Spacer(),
                    if (activeCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.22),
                              width: 0.5),
                        ),
                        child: Text('$activeCount loading',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [
                    Text('$completedCount done',
                        style: TextStyle(color: t.textMuted, fontSize: 11)),
                    Text(' · ', style: TextStyle(color: t.textMuted)),
                    Text('$totalCount total',
                        style: TextStyle(color: t.textMuted, fontSize: 11)),
                    if (freeStr != null) ...[
                      Text(' · ', style: TextStyle(color: t.textMuted)),
                      Text(freeStr,
                          style: TextStyle(
                              color: freeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                  ]),
                ])),
              ]),
            ),
          ),
        ),
      );
    }

    return animConfig.canStagger
        ? stripContent
            .animate()
            .fadeIn(duration: 350.ms)
            .slideY(begin: -0.05, end: 0, duration: 350.ms, curve: AppCurves.standard)
        : stripContent;
  }
}

// ── Arc Meter ─────────────────────────────────────────────────────────────────
/// A 48×48 circular arc progress meter. One-shot entrance via
/// TweenAnimationBuilder (no AnimationController — lightweight).
/// When animate=false renders the final state immediately.
class _ArcMeter extends StatelessWidget {
  final double fraction; // 0..1
  final bool animate;
  final RaddTheme t;

  const _ArcMeter({
    required this.fraction,
    required this.animate,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate) {
      return _ArcPainterWidget(fraction: fraction, t: t);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => _ArcPainterWidget(fraction: value, t: t),
    );
  }
}

class _ArcPainterWidget extends StatelessWidget {
  final double fraction;
  final RaddTheme t;
  const _ArcPainterWidget({required this.fraction, required this.t});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: CustomPaint(
        painter: _ArcPainter(fraction: fraction, t: t),
        child: Center(
          child: Icon(AppIcons.downloadDone, size: 18, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double fraction;
  final RaddTheme t;
  _ArcPainter({required this.fraction, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 5;
    const strokeWidth = 3.5;
    const startAngle = -math.pi / 2; // top

    // Track arc (background)
    final trackPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      math.pi * 2,
      false,
      trackPaint,
    );

    if (fraction > 0) {
      // Progress arc
      final progressPaint = Paint()
        ..color = fraction > 0.85
            ? AppColors.error
            : fraction > 0.65
                ? AppColors.warning
                : AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        math.pi * 2 * fraction,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.fraction != fraction;
}

// Allow BoxDecoration.copyWith with no margin (margin is on the Container above)
extension _DecorationCopy on BoxDecoration {
  BoxDecoration copyWith({EdgeInsets? margin}) => BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: border,
        boxShadow: boxShadow,
        gradient: gradient,
        image: image,
        shape: shape,
      );
}
