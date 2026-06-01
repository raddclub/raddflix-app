import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;

/// Phase U — Binge Guard
/// Appears after N episodes (or N hours) to encourage a break.
/// Shows health tips + animated watch-time ring.

class BingeGuard extends StatefulWidget {
  final int episodesWatched;
  final Duration totalWatchTime;
  final Color accentColor;
  final VoidCallback onContinue;
  final VoidCallback onTakeBreak;
  final Duration breakSuggestion;

  const BingeGuard({
    super.key,
    required this.episodesWatched,
    required this.totalWatchTime,
    required this.accentColor,
    required this.onContinue,
    required this.onTakeBreak,
    this.breakSuggestion = const Duration(minutes: 15),
  });

  @override State<BingeGuard> createState() => _BingeGuardState();
}

class _BingeGuardState extends State<BingeGuard> with SingleTickerProviderStateMixin {
  late AnimationController _ringCtrl;
  final _tips = [
    ('👁️', 'Look away from the screen every 20 minutes to rest your eyes.'),
    ('💧', 'Stay hydrated! Have a glass of water before the next episode.'),
    ('🚶', 'Stretch your legs. A short walk helps blood circulation.'),
    ('🌙', 'Quality sleep is important. Consider continuing tomorrow.'),
    ('🧠', 'Taking breaks improves content retention and enjoyment.'),
  ];
  late int _tipIndex;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _tipIndex = (widget.episodesWatched % _tips.length);
  }

  @override void dispose() { _ringCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final acc   = widget.accentColor;
    final hours = widget.totalWatchTime.inHours;
    final mins  = widget.totalWatchTime.inMinutes % 60;
    final tip   = _tips[_tipIndex];

    return Container(
      color: Colors.black.withOpacity(0.92),
      child: Center(child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: acc.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: acc.withOpacity(0.15), blurRadius: 32)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Animated watch-time ring
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (_, __) => SizedBox(
              width: 100, height: 100,
              child: CustomPaint(painter: _WatchRingPainter(
                hours: hours, mins: mins,
                pulse: _ringCtrl.value, accent: acc)),
            ),
          ),
          const SizedBox(height: 16),
          Text('You've watched ${widget.episodesWatched} episode${widget.episodesWatched > 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text('${hours > 0 ? "${hours}h " : ""}${mins}min total',
              style: TextStyle(color: acc, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          // Tip card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tip.$1, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text(tip.$2, style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.5))),
            ]),
          ),
          const SizedBox(height: 24),
          // Buttons
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: widget.onTakeBreak,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Take a Break', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('~${widget.breakSuggestion.inMinutes} min',
                    style: const TextStyle(fontSize: 10, color: Colors.white38)),
              ]))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: widget.onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Next Episode', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)))),
          ]),
        ]),
      ).animate().scale(begin: const Offset(0.85, 0.85), duration: 350.ms, curve: Curves.easeOutBack)
        .fadeIn(duration: 250.ms)),
    );
  }
}

class _WatchRingPainter extends CustomPainter {
  final int hours, mins;
  final double pulse;
  final Color accent;
  const _WatchRingPainter({required this.hours, required this.mins,
      required this.pulse, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 10) / 2;
    // Pulsing glow
    canvas.drawCircle(c, r + 4 * pulse, Paint()
      ..color = accent.withOpacity(0.1 * (1 - pulse))
      ..style = PaintingStyle.fill);
    // Track
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6);
    // Progress: treat 4h as full ring
    final totalMins = hours * 60 + mins;
    final frac = (totalMins / 240.0).clamp(0.0, 1.0);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
      -math.pi / 2, frac * 2 * math.pi, false,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round);
    // Center text
    final tp = TextPainter(
      text: TextSpan(text: hours > 0 ? '${hours}h' : '${mins}m',
          style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override bool shouldRepaint(_WatchRingPainter o) => o.pulse != pulse;
}
