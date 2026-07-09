/// Phase D3 — Film Grain / Film Look Overlay
/// An animated `CustomPaint` widget that draws randomized pixel noise over the video.
/// 3 intensity levels: subtle / medium / heavy.
/// Uses a ticker to update every 50 ms for a natural, flickering grain effect.
library film_grain_overlay;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Returns the grain opacity for a given level string.
/// 'none' → 0.0, 'subtle' → 0.028, 'medium' → 0.06, 'heavy' → 0.12
double filmGrainOpacity(String level) {
  switch (level) {
    case 'subtle': return 0.028;
    case 'medium': return 0.060;
    case 'heavy':  return 0.120;
    default:       return 0.0;
  }
}

const filmGrainLevels = ['none', 'subtle', 'medium', 'heavy'];
const filmGrainLabels = <String, String>{
  'none':   'Off',
  'subtle': 'Subtle',
  'medium': 'Medium',
  'heavy':  'Heavy',
};

/// Overlay widget. Wrap inside a `Positioned.fill` in the player Stack.
/// Renders nothing when [level] is 'none' or [opacity] is 0.
class FilmGrainOverlay extends StatefulWidget {
  final String level;

  const FilmGrainOverlay({super.key, required this.level});

  @override
  State<FilmGrainOverlay> createState() => _FilmGrainOverlayState();
}

class _FilmGrainOverlayState extends State<FilmGrainOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frame = 0;
  // 50 ms ≈ 20 fps grain — fast enough to feel real, slow enough for perf
  static const _interval = Duration(milliseconds: 50);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (elapsed - _last >= _interval) {
        _last = elapsed;
        setState(() => _frame++);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = filmGrainOpacity(widget.level);
    if (opacity <= 0.0) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GrainPainter(frame: _frame, opacity: opacity),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _GrainPainter extends CustomPainter {
  final int frame;
  final double opacity;

  const _GrainPainter({required this.frame, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(frame * 0x9e3779b9);
    // Draw ~0.3% of pixels as grain — balances perf and appearance
    final pixelCount = (size.width * size.height * 0.003).toInt().clamp(200, 3000);
    final paint = Paint()..strokeWidth = 1.4;

    for (int i = 0; i < pixelCount; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      // Alternating bright/dark grains for silver-halide look
      final bright = rng.nextBool();
      final grain = bright
          ? Colors.white.withOpacity(opacity * (0.6 + rng.nextDouble() * 0.4))
          : Colors.black.withOpacity(opacity * (0.4 + rng.nextDouble() * 0.6));
      paint.color = grain;
      canvas.drawCircle(Offset(x, y), 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.frame != frame || old.opacity != opacity;
}
