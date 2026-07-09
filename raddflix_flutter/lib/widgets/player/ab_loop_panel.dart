import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../core/player/ab_loop_controller.dart';

class AbLoopPanel extends StatelessWidget {
  final AbLoopController controller;
  final Duration currentPosition;
  final String Function(Duration) fmtDur;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  const AbLoopPanel({
    super.key,
    required this.controller,
    required this.currentPosition,
    required this.fmtDur,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final aSet = controller.pointA != null;
    final bSet = controller.pointB != null;
    final looping = aSet && bSet;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Row(children: [
          const Icon(Icons.loop_rounded, color: Color(0xFFE8002D), size: 18),
          const SizedBox(width: 8),
          const Text('A-B Loop', style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          if (looping) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8002D),
                borderRadius: BorderRadius.circular(10)),
              child: const Text('LOOPING', style: TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
        ]),
        const SizedBox(height: 20),

        // A / B buttons
        Row(children: [
          // Set A button
          Expanded(child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              controller.setA(currentPosition);
              onChanged();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: aSet ? Colors.orange.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: aSet ? Colors.orange : Colors.white24,
                  width: aSet ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('A', style: TextStyle(
                    color: aSet ? Colors.orange : Colors.white54,
                    fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(aSet ? fmtDur(controller.pointA!) : 'Tap to set',
                    style: TextStyle(
                        color: aSet ? Colors.orange : Colors.white38,
                        fontSize: 11)),
              ]),
            ),
          )),
          const SizedBox(width: 12),

          // Arrow
          Icon(Icons.arrow_forward_rounded,
              color: looping ? const Color(0xFFE8002D) : Colors.white24, size: 20),
          const SizedBox(width: 12),

          // Set B button
          Expanded(child: GestureDetector(
            onTap: () {
              if (!aSet) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Set point A first'),
                  duration: Duration(seconds: 2)));
                return;
              }
              HapticFeedback.selectionClick();
              controller.setB(currentPosition);
              onChanged();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: bSet ? const Color(0xFFE8002D).withOpacity(0.15) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: bSet ? const Color(0xFFE8002D) : Colors.white24,
                  width: bSet ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('B', style: TextStyle(
                    color: bSet ? const Color(0xFFE8002D) : Colors.white54,
                    fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(bSet ? fmtDur(controller.pointB!) : 'Tap to set',
                    style: TextStyle(
                        color: bSet ? const Color(0xFFE8002D) : Colors.white38,
                        fontSize: 11)),
              ]),
            ),
          )),
        ]),
        const SizedBox(height: 16),

        // Clear button
        if (aSet || bSet)
          TextButton.icon(
            onPressed: () {
              controller.clear();
              onChanged();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Clear A-B Loop'),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),

        if (!aSet)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('💡 Tap A to mark start point, then B to mark end.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center),
          ),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 220.ms, curve: AppCurves.standard);
  }
}
