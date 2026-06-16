import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Samples the edges of the current video frame and emits averaged colors
/// for top / bottom / left / right edges.
class AmbilightController {
  final Player player;
  final void Function(AmbilightColors colors) onUpdate;
  final int intervalMs;

  Timer? _timer;
  bool _running = false;

  AmbilightController({
    required this.player,
    required this.onUpdate,
    this.intervalMs = 400,
  });

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => _sample());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sample() async {
    try {
      final Uint8List? bytes = await player.screenshot();
      if (bytes == null || bytes.isEmpty) return;
      final colors = await _extractEdgeColors(bytes);
      if (_running) onUpdate(colors);
    } catch (_) {}
  }

  static Future<AmbilightColors> _extractEdgeColors(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120, targetHeight: 68);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return const AmbilightColors();

    Color avgStrip(List<Offset> pixels) {
      int r = 0, g = 0, b = 0, n = 0;
      for (final px in pixels) {
        final x = px.dx.toInt().clamp(0, w - 1);
        final y = px.dy.toInt().clamp(0, h - 1);
        final idx = (y * w + x) * 4;
        r += byteData.getUint8(idx);
        g += byteData.getUint8(idx + 1);
        b += byteData.getUint8(idx + 2);
        n++;
      }
      if (n == 0) return Colors.black;
      return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
    }

    final strip = 10; // px strip width
    // Top edge
    final topPx = [for (int x = 0; x < w; x++) for (int y = 0; y < strip.clamp(0,h); y++) Offset(x.toDouble(), y.toDouble())];
    // Bottom edge
    final botPx = [for (int x = 0; x < w; x++) for (int y = (h-strip).clamp(0,h-1); y < h; y++) Offset(x.toDouble(), y.toDouble())];
    // Left edge
    final leftPx = [for (int y = 0; y < h; y++) for (int x = 0; x < strip.clamp(0,w); x++) Offset(x.toDouble(), y.toDouble())];
    // Right edge
    final rightPx = [for (int y = 0; y < h; y++) for (int x = (w-strip).clamp(0,w-1); x < w; x++) Offset(x.toDouble(), y.toDouble())];

    return AmbilightColors(
      top:    avgStrip(topPx),
      bottom: avgStrip(botPx),
      left:   avgStrip(leftPx),
      right:  avgStrip(rightPx),
    );
  }

  void dispose() => stop();
}

class AmbilightColors {
  final Color top, bottom, left, right;
  const AmbilightColors({
    this.top    = Colors.black,
    this.bottom = Colors.black,
    this.left   = Colors.black,
    this.right  = Colors.black,
  });
}
