import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase V — Zoom & Crop Overlay
/// Shows zoom percentage, aspect ratio mode, crop presets.

enum AspectMode { original, fill, fit, stretch, crop169, crop43, crop21_9, crop1_1 }

extension AspectModeExt on AspectMode {
  String get label {
    switch (this) {
      case AspectMode.original:  return 'Original';
      case AspectMode.fill:      return 'Fill';
      case AspectMode.fit:       return 'Fit';
      case AspectMode.stretch:   return 'Stretch';
      case AspectMode.crop169:   return '16:9';
      case AspectMode.crop43:    return '4:3';
      case AspectMode.crop21_9:  return '21:9';
      case AspectMode.crop1_1:   return '1:1';
    }
  }
  String get icon {
    switch (this) {
      case AspectMode.original:  return '□';
      case AspectMode.fill:      return '▣';
      case AspectMode.fit:       return '⊡';
      case AspectMode.stretch:   return '⬛';
      default:                   return '⬜';
    }
  }
}

class ZoomCropOverlay extends StatefulWidget {
  final double currentZoom;
  final AspectMode currentMode;
  final Color accentColor;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<AspectMode> onModeChanged;
  final VoidCallback onReset;

  const ZoomCropOverlay({
    super.key,
    this.currentZoom = 1.0,
    this.currentMode = AspectMode.original,
    required this.accentColor,
    required this.onZoomChanged,
    required this.onModeChanged,
    required this.onReset,
  });

  @override State<ZoomCropOverlay> createState() => _ZoomCropOverlayState();
}

class _ZoomCropOverlayState extends State<ZoomCropOverlay> {
  late double _zoom;
  late AspectMode _mode;

  @override
  void initState() {
    super.initState();
    _zoom = widget.currentZoom;
    _mode = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.zoom_in_rounded, color: acc, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Zoom & Crop',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(
            onTap: () {
              setState(() { _zoom = 1.0; _mode = AspectMode.original; });
              widget.onReset();
            },
            child: Text('Reset', style: TextStyle(color: acc, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        const Divider(color: Colors.white10, height: 20),

        // Zoom slider
        Row(children: [
          const Text('1×', style: TextStyle(color: Colors.white38, fontSize: 10)),
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: acc, inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white, overlayColor: acc.withOpacity(0.2)),
            child: Slider(value: _zoom.clamp(1.0, 3.0), min: 1.0, max: 3.0, divisions: 20,
              onChanged: (v) { setState(() => _zoom = v); widget.onZoomChanged(v); }))),
          const Text('3×', style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 8),
          SizedBox(width: 36, child: Text('${_zoom.toStringAsFixed(1)}×',
              style: TextStyle(color: acc, fontSize: 14, fontWeight: FontWeight.w800),
              textAlign: TextAlign.right)),
        ]),
        const Divider(color: Colors.white10, height: 20),

        // Aspect mode grid
        const Align(alignment: Alignment.centerLeft,
          child: Text('ASPECT RATIO', style: TextStyle(
              color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: AspectMode.values.map((m) {
          final sel = _mode == m;
          return GestureDetector(
            onTap: () { setState(() => _mode = m); widget.onModeChanged(m); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? acc : Colors.white12, width: sel ? 1.5 : 1)),
              child: Text(m.label, style: TextStyle(
                  color: sel ? Colors.white : Colors.white60,
                  fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal))));
        }).toList()),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic).fadeIn(duration: 180.ms);
  }
}
