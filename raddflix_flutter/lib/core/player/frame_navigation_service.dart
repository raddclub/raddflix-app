/// Phase L2 — Frame-by-Frame Navigation (Enhanced)
/// Shows: frame counter (Frame: 1847 / 142,360)
/// Jump to specific frame by number
/// Export current frame as JPEG (via RepaintBoundary)
library frame_nav;

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Helper to convert duration → frame number and vice versa.
class FrameCounter {
  final double fps;

  const FrameCounter({this.fps = 24.0});

  int positionToFrame(Duration position) =>
      (position.inMilliseconds * fps / 1000).round();

  Duration frameToPosition(int frame) =>
      Duration(milliseconds: (frame * 1000 / fps).round());

  int totalFrames(Duration total) =>
      (total.inMilliseconds * fps / 1000).round();

  String format(Duration position, Duration total) {
    final current = positionToFrame(position);
    final tot = totalFrames(total);
    return 'Frame: ${_fmt(current)} / ${_fmt(tot)}';
  }

  String _fmt(int n) {
    // Format with thousands separator
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Frame counter HUD — shown in the player when frame-step mode is active.
class FrameCounterHud extends StatelessWidget {
  final Duration position;
  final Duration total;
  final double fps;
  final Color accentColor;
  final VoidCallback? onJumpToFrame;

  const FrameCounterHud({
    super.key,
    required this.position,
    required this.total,
    required this.accentColor,
    this.fps = 24.0,
    this.onJumpToFrame,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FrameCounter(fps: fps);
    return GestureDetector(
      onTap: onJumpToFrame,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.movie_outlined, color: accentColor, size: 14),
          const SizedBox(width: 6),
          Text(
            fc.format(position, total),
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500),
          ),
          if (onJumpToFrame != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.edit_rounded, color: Colors.white38, size: 12),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Jump to Frame dialog — user types a frame number.
Future<int?> showJumpToFrameDialog(
  BuildContext context, {
  required int currentFrame,
  required int totalFrames,
  required Color accentColor,
}) {
  final ctrl = TextEditingController(text: '$currentFrame');
  return showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Jump to Frame',
          style: TextStyle(color: Colors.white, fontSize: 16,
              fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Total: $totalFrames frames',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () {
            final frame = int.tryParse(ctrl.text);
            if (frame != null && frame >= 0 && frame <= totalFrames) {
              Navigator.of(context).pop(frame);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Jump'),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
/// Export current video frame as JPEG (2x resolution).
Future<Uint8List?> exportCurrentFrame(GlobalKey repaintKey) async {
  try {
    final boundary = repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    // Convert RGBA → JPEG via platform channel (dart:ui only outputs PNG/RGBA)
    // Return raw RGBA for now; platform side converts to JPEG
    return bytes?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
