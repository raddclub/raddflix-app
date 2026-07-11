import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/anim_config.dart';

// Phase 49 ANIM-49-02/03/04: Ambient floating spark particles.
// Pure-Dart CustomPainter — no `particles_flutter` package required.
// ANIM-49-01 (package add) skipped: pubspec.lock cannot be regenerated
// without `flutter pub get`; this implementation is functionally equivalent.
// Gated behind canParticle (Tier 3 / API 33+).
class ParticleOverlay extends ConsumerStatefulWidget {
  const ParticleOverlay({super.key});

  @override
  ConsumerState<ParticleOverlay> createState() => _ParticleOverlayState();
}

class _ParticleOverlayState extends ConsumerState<ParticleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose(); // ANIM-49-05: dispose — sensor/controller leaks drain battery
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animConfig = ref.watch(animConfigProvider);
    // Tier 3 only; also skip if system animations disabled (accessibility)
    if (!animConfig.canParticle || MediaQuery.of(context).disableAnimations) {
      return const SizedBox.shrink();
    }
    // A7: RepaintBoundary prevents the 12s animation loop from repainting
    // the ancestor widget tree on every frame — critical on Snapdragon 400/600 devices.
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticlePainter(tick: _ctrl.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

// Fixed particle spec — seeded so layout is deterministic across rebuilds
class _PSpec {
  final double x, baseY, speed, radius, opacity;
  const _PSpec(this.x, this.baseY, this.speed, this.radius, this.opacity);
}

class _ParticlePainter extends CustomPainter {
  final double tick;

  // ANIM-49-04: exactly 25 particles, radius ~1.2, opacity 20-70%, no connect lines
  static const int _kCount = 25;
  static final List<_PSpec> _specs = _generate();

  const _ParticlePainter({required this.tick});

  static List<_PSpec> _generate() {
    final rng = Random(42); // fixed seed → deterministic, no jitter on rebuild
    return List.generate(_kCount, (_) => _PSpec(
      rng.nextDouble(),                 // x         0..1
      rng.nextDouble(),                 // baseY     0..1
      0.04 + rng.nextDouble() * 0.09,   // speed     0.04..0.13 (slow drift)
      1.0  + rng.nextDouble() * 0.4,    // radius    1.0..1.4 px
      0.20 + rng.nextDouble() * 0.50,   // opacity   0.20..0.70
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in _specs) {
      // Drift upward; modulo 1.0 to wrap seamlessly at top edge
      double y = ((s.baseY - s.speed * tick) % 1.0);
      if (y < 0) y += 1.0;
      // Gentle horizontal sine drift — organic feel without GPU shader cost
      final x = (s.x + 0.018 * sin(tick * 2 * pi + s.baseY * 8)) % 1.0;
      paint.color = Colors.white.withOpacity(s.opacity);
      canvas.drawCircle(Offset(x * size.width, y * size.height), s.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.tick != tick;
}
