import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase N — Rage Skip Panel
/// Rapidly skip through annoying segments (intros, recaps, sponsorships).
class RageSkipPanel extends StatefulWidget {
  final Duration position;
  final Duration totalDuration;
  final Color accentColor;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onClose;

  const RageSkipPanel({
    super.key,
    required this.position,
    required this.totalDuration,
    required this.accentColor,
    required this.onSeek,
    required this.onClose,
  });

  @override
  State<RageSkipPanel> createState() => _RageSkipPanelState();
}

class _RageSkipPanelState extends State<RageSkipPanel> {
  // How many seconds to skip per tap
  static const _taps = [30, 60, 90, 120, 180, 300];
  int _tapCount = 0;
  Duration? _lastSkip;

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    final remaining = widget.totalDuration - widget.position;

    return Positioned(
      bottom: 120, right: 16,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Close button
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white54, size: 14)),
          ),
          const SizedBox(height: 8),
          // Skip buttons
          ..._taps.where((s) => Duration(seconds: s) < remaining).map((s) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  final skipTo = widget.position + Duration(seconds: s);
                  widget.onSeek(skipTo.clamp(Duration.zero, widget.totalDuration));
                  setState(() { _tapCount++; _lastSkip = Duration(seconds: s); });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: acc.withOpacity(0.5)),
                    boxShadow: [BoxShadow(color: acc.withOpacity(0.2), blurRadius: 8)]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fast_forward_rounded, color: acc, size: 14),
                    const SizedBox(width: 5),
                    Text('+${_fmtSec(s)}', style: TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ).toList().reversed.toList(),
          // Rage meter
          if (_tapCount > 0) ...[
            const SizedBox(height: 4),
            _RageMeter(count: _tapCount, accent: acc),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.2, end: 0, duration: 250.ms);
  }

  Duration _clamp(Duration d, Duration total) {
    if (d < Duration.zero) return Duration.zero;
    if (d > total) return total;
    return d;
  }

  String _fmtSec(int s) {
    if (s >= 60) return '${s ~/ 60}m';
    return '${s}s';
  }
}

class _RageMeter extends StatelessWidget {
  final int count;
  final Color accent;
  const _RageMeter({required this.count, required this.accent});

  @override
  Widget build(BuildContext context) {
    final emojis = ['😤', '😠', '🤬', '💀', '🔥'];
    final idx = (count - 1).clamp(0, emojis.length - 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emojis[idx], style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 5),
        Text('×$count', style: TextStyle(
            color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
