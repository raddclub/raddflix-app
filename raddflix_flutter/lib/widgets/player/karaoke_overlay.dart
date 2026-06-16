/// Phase E2 — Karaoke Overlay (UI companion to AudioLabService)
/// Shows lyrics-style bouncing ball / highlighted word display.
/// In the absence of synced lyric data, shows a "Karaoke Mode Active" indicator
/// + current audio enhancement level with animated waveform.
library karaoke_overlay;

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated sound wave bars indicating karaoke/vocal-reduce is active.
class KaraokeActiveIndicator extends StatefulWidget {
  final Color accentColor;
  final String levelLabel; // e.g. 'Reduce', 'Strong Reduce', 'Remove'
  final bool visible;

  const KaraokeActiveIndicator({
    super.key,
    required this.accentColor,
    required this.levelLabel,
    required this.visible,
  });

  @override
  State<KaraokeActiveIndicator> createState() => _KaraokeActiveIndicatorState();
}

class _KaraokeActiveIndicatorState extends State<KaraokeActiveIndicator>
    with TickerProviderStateMixin {
  final List<AnimationController> _bars = [];
  final List<Animation<double>> _anims = [];
  static const _barCount = 5;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _barCount; i++) {
      final ctrl = AnimationController(
        duration: Duration(milliseconds: 300 + _rng.nextInt(400)),
        vsync: this,
      )..repeat(reverse: true);
      _bars.add(ctrl);
      _anims.add(Tween<double>(begin: 0.2, end: 1.0).animate(
          CurvedAnimation(parent: ctrl, curve: Curves.easeInOut)));
    }
  }

  @override
  void dispose() {
    for (final c in _bars) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.accentColor.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Waveform bars
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_barCount, (i) => AnimatedBuilder(
              animation: _anims[i],
              builder: (_, __) => Container(
                width: 3,
                height: 16 * _anims[i].value,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Karaoke',
                style: TextStyle(color: widget.accentColor,
                    fontSize: 11, fontWeight: FontWeight.w700)),
            Text(widget.levelLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}
