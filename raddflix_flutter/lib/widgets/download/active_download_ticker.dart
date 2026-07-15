// lib/widgets/download/active_download_ticker.dart
//
// DOWNLOAD-TAB-V2: compact live ticker showing in-flight downloads.
// Phase-DS: upgraded with circular progress rings per active download.
// Ring animation is a TweenAnimationBuilder (no looping controller) —
// the value updates naturally as state changes drive rebuilds.
// BackdropFilter glass gated on animConfig.canBlur; solid fallback otherwise.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/design/app_icons.dart';
import '../../core/theme/radd_theme.dart';
import '../../core/utils/anim_config.dart';
import '../../providers/downloads_provider.dart';

class ActiveDownloadTicker extends ConsumerWidget {
  final DownloadsState state;
  final String Function(String fileId) titleFor;
  final VoidCallback Function(String fileId) onCancel;

  const ActiveDownloadTicker({
    super.key,
    required this.state,
    required this.titleFor,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIds = state.activeProgress.keys.toList();
    if (activeIds.isEmpty) return const SizedBox.shrink();
    final t = RaddTheme.of(context);
    final animConfig = ref.read(animConfigProvider);

    final items = activeIds.take(3).map((id) {
      final progress = state.progressOf(id);
      final speed    = state.speedOf(id);
      final eta      = state.etaOf(id);
      final title    = titleFor(id);
      final queuePos = state.queuePositionOf(id);
      return _TickerRow(
        id: id,
        title: title,
        progress: progress,
        speed: speed,
        eta: eta,
        queuePos: queuePos,
        t: t,
        animConfig: animConfig,
        onCancel: onCancel(id),
      );
    }).toList();

    final borderDecoration = BoxDecoration(
      color: animConfig.canBlur ? t.surface.withOpacity(0.72) : t.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.primary.withOpacity(0.18), width: 0.8),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.06),
          blurRadius: 20,
          spreadRadius: -4,
        ),
      ],
    );

    final content = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: borderDecoration,
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );

    if (animConfig.canBlur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: content,
        ),
      );
    }
    return content;
  }
}

// ── Single active download row ────────────────────────────────────────────────
class _TickerRow extends StatelessWidget {
  final String id;
  final String title;
  final double progress;
  final String speed;
  final String eta;
  final int queuePos;
  final RaddTheme t;
  final AnimConfig animConfig;
  final VoidCallback onCancel;

  const _TickerRow({
    required this.id,
    required this.title,
    required this.progress,
    required this.speed,
    required this.eta,
    required this.queuePos,
    required this.t,
    required this.animConfig,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(children: [
        // Circular progress ring
        _ProgressRing(progress: progress, animate: animConfig.canStagger, t: t),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          // Enhanced progress bar with glass-tinted track
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              // Glass track
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Progress fill
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.5),
                        blurRadius: 4,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 3),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%'
            '${speed.isNotEmpty ? "  ·  $speed" : ""}'
            '${eta.isNotEmpty ? "  ·  $eta" : ""}'
            '${queuePos > 1 ? "  ·  #$queuePos in queue" : ""}',
            style: TextStyle(color: t.textMuted, fontSize: 10),
          ),
        ])),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onCancel,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withOpacity(0.10),
              border: Border.all(
                  color: AppColors.error.withOpacity(0.25), width: 0.8),
            ),
            child: Icon(AppIcons.stopIcon,
                size: 14, color: AppColors.error.withOpacity(0.80)),
          ),
        ),
      ]),
    );
  }
}

// ── Circular progress ring ────────────────────────────────────────────────────
/// Small 36×36 circular ring showing download progress.
/// Uses TweenAnimationBuilder for a smooth value-driven arc —
/// no AnimationController means no looping concern.
class _ProgressRing extends StatelessWidget {
  final double progress;
  final bool animate;
  final RaddTheme t;

  const _ProgressRing({
    required this.progress,
    required this.animate,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate) {
      return _RingPainterWidget(fraction: progress, t: t);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) => _RingPainterWidget(fraction: val, t: t),
    );
  }
}

class _RingPainterWidget extends StatelessWidget {
  final double fraction;
  final RaddTheme t;
  const _RingPainterWidget({required this.fraction, required this.t});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, t: t),
        child: Center(
          child: Text(
            '${(fraction * 100).toStringAsFixed(0)}',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final RaddTheme t;
  _RingPainter({required this.fraction, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;
    const strokeWidth = 2.5;
    const startAngle = -math.pi / 2;

    // Track
    final trackPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (fraction > 0) {
      final progressPaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        math.pi * 2 * fraction.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}
