import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Transparent Player Mode — mini opacity slider overlay.
/// Shows a vertical slider bottom-left when transparent mode is active.
class TransparentPlayerSlider extends StatelessWidget {
  final double opacity;
  final ValueChanged<double> onChanged;
  final VoidCallback onClose;

  const TransparentPlayerSlider({
    super.key,
    required this.opacity,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100, left: 12,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.opacity, color: Colors.white70, size: 16)),
        ),
        const SizedBox(height: 6),
        RotatedBox(
          quarterTurns: 3,
          child: SizedBox(
            width: 100,
            child: Slider(
              value: opacity.clamp(0.2, 1.0),
              min: 0.2, max: 1.0,
              activeColor: const Color(0xFFE8002D),
              inactiveColor: Colors.white24,
              onChanged: onChanged,
            ),
          ),
        ),
        Text('${(opacity * 100).toInt()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ]).animate().fadeIn(duration: 200.ms),
    );
  }
}
