import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Phase K — Network Speed Overlay
/// Real-time buffer health + bitrate + quality indicators.
class NetworkSpeedOverlay extends StatelessWidget {
  final double bufferFraction;      // 0.0–1.0
  final int    bitrateKbps;         // current bitrate
  final String quality;             // e.g. '1080p', '720p', 'Auto'
  final bool   isBuffering;
  final Color  accentColor;
  final bool   compact;             // compact mode: single line

  const NetworkSpeedOverlay({
    super.key,
    required this.bufferFraction,
    this.bitrateKbps = 0,
    this.quality = 'Auto',
    this.isBuffering = false,
    required this.accentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final health = bufferFraction;
    final healthColor = health > 0.5
        ? const Color(0xFF4CAF50)
        : health > 0.2
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);

    if (compact) return _buildCompact(healthColor);
    return _buildFull(healthColor);
  }

  Widget _buildCompact(Color healthColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.65),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(
          color: healthColor, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(quality, style: const TextStyle(
          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      if (bitrateKbps > 0) ...[
        const SizedBox(width: 6),
        Text(_fmtBitrate(bitrateKbps),
            style: const TextStyle(color: Colors.white54, fontSize: 9)),
      ],
    ]),
  );

  Widget _buildFull(Color healthColor) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.75),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.network_check_rounded, color: healthColor, size: 14),
          const SizedBox(width: 6),
          const Text('Network', style: TextStyle(color: Colors.white70,
              fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        // Buffer health bar
        Row(children: [
          const Text('Buffer', style: TextStyle(color: Colors.white38, fontSize: 9)),
          const SizedBox(width: 8),
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: bufferFraction.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(healthColor),
              minHeight: 4),
          )),
          const SizedBox(width: 6),
          Text('${(bufferFraction * 100).toInt()}%',
              style: TextStyle(color: healthColor, fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _statBadge('Quality', quality, Colors.white54),
          const SizedBox(width: 8),
          if (bitrateKbps > 0)
            _statBadge('Speed', _fmtBitrate(bitrateKbps), Colors.white54),
          const SizedBox(width: 8),
          if (isBuffering)
            _statBadge('Buffering', '⏳', Colors.orange),
        ]),
      ]),
  );

  Widget _statBadge(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(4)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(color: Colors.white24, fontSize: 7)),
      Text(value, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    ]),
  );

  String _fmtBitrate(int kbps) {
    if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    return '${kbps} Kbps';
  }
}

/// Mini circular buffer ring — shown on right side of seek bar.
class BufferRing extends StatelessWidget {
  final double fraction;
  final Color accentColor;
  final double size;

  const BufferRing({
    super.key,
    required this.fraction,
    required this.accentColor,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _RingPainter(fraction: fraction, color: accentColor)),
  );
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  const _RingPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 4) / 2;

    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);

    final healthColor = fraction > 0.5
        ? const Color(0xFF4CAF50)
        : fraction > 0.2
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      fraction.clamp(0.0, 1.0) * 2 * math.pi,
      false,
      Paint()
        ..color = healthColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.fraction != fraction;
}
