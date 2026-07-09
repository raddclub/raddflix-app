import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;

/// Phase T — Clip Trimmer
/// Select start/end points for exporting a short clip or GIF.
class ClipTrimmer extends StatefulWidget {
  final Duration totalDuration;
  final Duration initialStart;
  final Duration initialEnd;
  final Color accentColor;
  final ValueChanged<({Duration start, Duration end})> onTrimChanged;
  final VoidCallback onExportClip;
  final VoidCallback onExportGif;

  const ClipTrimmer({
    super.key,
    required this.totalDuration,
    required this.initialStart,
    required this.initialEnd,
    required this.accentColor,
    required this.onTrimChanged,
    required this.onExportClip,
    required this.onExportGif,
  });

  @override State<ClipTrimmer> createState() => _ClipTrimmerState();
}

class _ClipTrimmerState extends State<ClipTrimmer> {
  late Duration _start;
  late Duration _end;
  static const _maxGifSeconds = 15;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end   = widget.initialEnd;
  }

  Duration get _clipLength => _end - _start;
  bool get _gifOk => _clipLength.inSeconds <= _maxGifSeconds && _clipLength > Duration.zero;

  void _emit() => widget.onTrimChanged((start: _start, end: _end));

  @override
  Widget build(BuildContext context) {
    final acc   = widget.accentColor;
    final total = widget.totalDuration;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0,12,0,0),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
          child: Row(children: [
            Icon(Icons.content_cut_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Clip Trimmer', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            Text(_fmt(_clipLength), style: TextStyle(
                color: _clipLength > Duration.zero ? acc : Colors.white38,
                fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          ])),
        const Divider(color: Colors.white10, height: 20),

        // Trim bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _TrimBar(
            total: total,
            start: _start,
            end: _end,
            accent: acc,
            onStartChanged: (v) { setState(() => _start = v); _emit(); },
            onEndChanged:   (v) { setState(() => _end   = v); _emit(); },
          ),
        ),
        const SizedBox(height: 12),

        // Start / End time chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _TimeChip('Start', _start, acc),
            const Spacer(),
            _TimeChip('End', _end, acc),
          ]),
        ),
        const SizedBox(height: 16),

        // GIF length warning
        if (!_gifOk && _clipLength > const Duration(seconds: _maxGifSeconds))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('GIF max is ${_maxGifSeconds}s — trim shorter to export as GIF',
                style: const TextStyle(color: Colors.orange, fontSize: 11)),
          ),

        // Export buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _gifOk ? () { HapticFeedback.mediumImpact(); widget.onExportGif(); } : null,
              icon: const Icon(Icons.gif_box_rounded, size: 18),
              label: const Text('Export GIF'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gifOk ? acc : Colors.white24,
                side: BorderSide(color: _gifOk ? acc : Colors.white12),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              onPressed: _clipLength > Duration.zero
                ? () { HapticFeedback.mediumImpact(); widget.onExportClip(); }
                : null,
              icon: const Icon(Icons.movie_creation_rounded, size: 18),
              label: const Text('Export Clip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          ]),
        ),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 180.ms);
  }

  Widget _TimeChip(String label, Duration d, Color acc) => Column(
    crossAxisAlignment: label == 'Start' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      Text(_fmt(d), style: TextStyle(color: acc, fontSize: 14,
          fontWeight: FontWeight.w700, fontFamily: 'monospace')),
    ]);

  String _fmt(Duration d) {
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}.${ms.toString().padLeft(2,'0')}';
  }
}

class _TrimBar extends StatelessWidget {
  final Duration total, start, end;
  final Color accent;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onEndChanged;

  const _TrimBar({required this.total, required this.start, required this.end,
      required this.accent, required this.onStartChanged, required this.onEndChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final totalMs = total.inMilliseconds.toDouble();
      if (totalMs <= 0) return const SizedBox(height: 40);
      final startFrac = start.inMilliseconds / totalMs;
      final endFrac   = end.inMilliseconds   / totalMs;

      return SizedBox(
        height: 40,
        child: Stack(alignment: Alignment.center, children: [
          // Track bg
          Container(height: 8, decoration: BoxDecoration(
              color: Colors.white12, borderRadius: BorderRadius.circular(4))),
          // Selected region
          Positioned(
            left: startFrac * w, width: (endFrac - startFrac) * w, top: 0, bottom: 0,
            child: Center(child: Container(height: 8, color: accent.withOpacity(0.5)))),
          // Start handle
          Positioned(left: startFrac * w - 10, child: GestureDetector(
            onPanUpdate: (d) {
              final newFrac = ((startFrac * w + d.delta.dx) / w).clamp(0.0, endFrac - 0.01);
              onStartChanged(Duration(milliseconds: (newFrac * totalMs).round()));
            },
            child: _Handle(accent: accent, icon: Icons.chevron_right_rounded))),
          // End handle
          Positioned(right: (1 - endFrac) * w - 10, child: GestureDetector(
            onPanUpdate: (d) {
              final newFrac = ((endFrac * w + d.delta.dx) / w).clamp(startFrac + 0.01, 1.0);
              onEndChanged(Duration(milliseconds: (newFrac * totalMs).round()));
            },
            child: _Handle(accent: accent, icon: Icons.chevron_left_rounded))),
        ]),
      );
    });
  }
}

class _Handle extends StatelessWidget {
  final Color accent;
  final IconData icon;
  const _Handle({required this.accent, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    width: 20, height: 40,
    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
    child: Icon(icon, color: Colors.white, size: 14));
}
