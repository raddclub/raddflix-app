import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/constants.dart' show AppColors;

/// Phase I — Equalizer Visualizer
/// Animated frequency bars + 13 presets + 10-band vertical sliders.

const List<String> kEqPresets = [
  'Flat', 'Bass Boost', 'Treble Boost', 'Vocal',
  'Podcast', 'Cinema', 'Club', 'Rock', 'Pop',
  'Classical', 'Dance', 'Lounge', 'Custom',
];

const Map<String, List<double>> kEqPresetBands = {
  'Flat':         [0,0,0,0,0,0,0,0,0,0],
  'Bass Boost':   [6,5,4,2,0,-1,-1,0,0,0],
  'Treble Boost': [0,0,0,0,0,1,2,3,5,6],
  'Vocal':        [-2,-1,0,2,4,4,3,1,0,-1],
  'Podcast':      [-1,0,1,3,4,3,1,0,-1,-2],
  'Cinema':       [2,1,0,-1,0,1,2,3,2,1],
  'Club':         [4,3,0,0,0,0,0,3,2,0],
  'Rock':         [5,3,1,0,-1,0,2,4,4,3],
  'Pop':          [-1,0,2,3,4,3,1,-1,-2,-2],
  'Classical':    [0,0,0,0,0,0,-2,-3,-3,-4],
  'Dance':        [5,4,1,0,0,-2,-2,0,2,3],
  'Lounge':       [-2,-1,0,2,4,3,2,0,-1,-2],
  'Custom':       [0,0,0,0,0,0,0,0,0,0],
};

const List<String> kBandLabels = ['31','62','125','250','500','1K','2K','4K','8K','16K'];

class EqVisualizer extends StatefulWidget {
  final String currentPreset;
  final List<double> bands;
  final bool enabled;
  final Color accentColor;
  final ValueChanged<String> onPresetChanged;
  final ValueChanged<List<double>> onBandsChanged;
  final ValueChanged<bool> onToggle;

  const EqVisualizer({
    super.key,
    this.currentPreset = 'Flat',
    required this.bands,
    this.enabled = false,
    required this.accentColor,
    required this.onPresetChanged,
    required this.onBandsChanged,
    required this.onToggle,
  });

  @override
  State<EqVisualizer> createState() => _EqVisualizerState();
}

class _EqVisualizerState extends State<EqVisualizer> {
  late List<double> _bands;
  late String _preset;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _bands  = List.from(widget.bands);
    _preset = widget.currentPreset;
    _enabled = widget.enabled;
  }

  void _applyPreset(String preset) {
    final b = List<double>.from(kEqPresetBands[preset] ?? kEqPresetBands['Flat']!);
    setState(() { _preset = preset; _bands = b; });
    widget.onPresetChanged(preset);
    widget.onBandsChanged(b);
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    // A7: RepaintBoundary isolates the setState-per-tick visualizer from ancestor tree
    return RepaintBoundary(child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Icon(Icons.equalizer_rounded, color: acc, size: 22),
            const SizedBox(width: 10),
            const Expanded(child: Text('Equalizer',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            Switch(value: _enabled, activeColor: acc,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) { setState(() => _enabled = v); widget.onToggle(v); }),
          ]),
        ),
        // Animated bars
        SizedBox(height: 60, child: _VisualizerBars(bands: _bands, enabled: _enabled, accentColor: acc)),
        const SizedBox(height: 4),
        Flexible(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(_bands.length, (i) => Expanded(child: _BandSlider(
                  label: kBandLabels[i], value: _bands[i],
                  enabled: _enabled, accentColor: acc,
                  onChanged: (v) {
                    setState(() { _bands[i] = v; _preset = 'Custom'; });
                    widget.onBandsChanged(List.from(_bands));
                  },
                ))),
              ),
            ),
            const Divider(color: Colors.white10, height: 20),
            const Text('PRESETS', style: TextStyle(
                color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: kEqPresets.map((p) {
              final sel = _preset == p;
              return GestureDetector(
                onTap: () => _applyPreset(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? acc : Colors.white12, width: sel ? 1.5 : 1)),
                  child: Text(p, style: TextStyle(
                      color: sel ? Colors.white : Colors.white60,
                      fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                ),
              );
            }).toList()),
          ],
        )),
      ]),
    ));
  }
}

class _VisualizerBars extends StatefulWidget {
  final List<double> bands;
  final bool enabled;
  final Color accentColor;
  const _VisualizerBars({required this.bands, required this.enabled, required this.accentColor});
  @override State<_VisualizerBars> createState() => _VisualizerBarsState();
}

class _VisualizerBarsState extends State<_VisualizerBars> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true)
      ..addListener(() { if (widget.enabled) setState(() {}); });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BarsPainter(bands: widget.bands, enabled: widget.enabled,
        accentColor: widget.accentColor, animValue: _ctrl.value));
}

class _BarsPainter extends CustomPainter {
  final List<double> bands;
  final bool enabled;
  final Color accentColor;
  final double animValue;
  const _BarsPainter({required this.bands, required this.enabled,
      required this.accentColor, required this.animValue});
  @override
  void paint(Canvas canvas, Size size) {
    final n = bands.length;
    final barW = size.width / n - 3;
    final maxH = size.height * 0.85;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < n; i++) {
      final x = i * (size.width / n);
      final jitter = ((i * 13 + animValue * 100).round() % 7) * 0.05;
      final normalized = ((bands[i] + 12) / 24).clamp(0.1, 1.0);
      final h = enabled ? (normalized + jitter) * maxH : maxH * 0.12;
      paint.shader = LinearGradient(
        begin: Alignment.bottomCenter, end: Alignment.topCenter,
        colors: enabled
            ? [accentColor.withOpacity(0.9), accentColor.withOpacity(0.4)]
            : [Colors.white24, Colors.white12],
      ).createShader(Rect.fromLTWH(x, size.height - h, barW, h));
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1.5, size.height - h, barW, h), const Radius.circular(3)), paint);
    }
  }
  @override bool shouldRepaint(_BarsPainter o) => o.animValue != animValue || o.enabled != enabled;
}

class _BandSlider extends StatelessWidget {
  final String label;
  final double value;
  final bool enabled;
  final Color accentColor;
  final ValueChanged<double> onChanged;
  const _BandSlider({required this.label, required this.value,
      required this.enabled, required this.accentColor, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text('${value > 0 ? '+' : ''}${value.toStringAsFixed(0)}',
        style: TextStyle(
          color: enabled ? (value != 0 ? accentColor : Colors.white54) : Colors.white24,
          fontSize: 9, fontWeight: FontWeight.w600)),
    Expanded(child: RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: enabled ? accentColor : Colors.white24,
          inactiveTrackColor: Colors.white12,
          thumbColor: enabled ? Colors.white : Colors.white38,
          overlayColor: accentColor.withOpacity(0.15),
        ),
        child: Slider(value: value.clamp(-12.0, 12.0), min: -12, max: 12, divisions: 24,
            onChanged: enabled ? onChanged : null),
      ),
    )),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8)),
  ]);
}
