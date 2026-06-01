import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase M1 — Custom Speed Presets
/// User edits their own speed list. Tap a speed to apply immediately.
/// Long-press a preset to delete it. Add button appends a new speed.

const List<double> kDefaultSpeedPresets = [
  0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0,
];

List<double> speedPresetsFromJson(String json) {
  if (json.isEmpty) return List.from(kDefaultSpeedPresets);
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => (e as num).toDouble()).toList();
  } catch (_) {
    return List.from(kDefaultSpeedPresets);
  }
}

class SpeedPresetsSheet extends StatefulWidget {
  final String presetsJson;
  final double currentSpeed;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<String> onPresetsChanged;
  final Color accentColor;

  const SpeedPresetsSheet({
    super.key,
    required this.presetsJson,
    required this.currentSpeed,
    required this.onSpeedSelected,
    required this.onPresetsChanged,
    required this.accentColor,
  });

  @override
  State<SpeedPresetsSheet> createState() => _SpeedPresetsSheetState();
}

class _SpeedPresetsSheetState extends State<SpeedPresetsSheet> {
  late List<double> _presets;
  double _adding = 1.5;

  @override
  void initState() {
    super.initState();
    _presets = speedPresetsFromJson(widget.presetsJson);
  }

  void _save() {
    _presets.sort();
    widget.onPresetsChanged(jsonEncode(_presets));
    setState(() {});
  }

  void _add(double v) {
    v = double.parse(v.toStringAsFixed(2));
    if (!_presets.contains(v)) {
      _presets.add(v);
      _save();
    }
  }

  void _remove(double v) {
    if (_presets.length <= 1) return;
    _presets.remove(v);
    _save();
  }

  void _reset() {
    setState(() => _presets = List.from(kDefaultSpeedPresets));
    widget.onPresetsChanged(jsonEncode(_presets));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(children: [
            Icon(Icons.speed_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Text('Speed Presets',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: _reset,
              child: const Text('Reset',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Text('Tap to set speed · Long-press to remove preset.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── Preset chips ─────────────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(spacing: 10, runSpacing: 10,
              children: _presets.map((s) {
                final active = (s - widget.currentSpeed).abs() < 0.01;
                return GestureDetector(
                  onTap: () {
                    widget.onSpeedSelected(s);
                    Navigator.pop(context);
                  },
                  onLongPress: () {
                    _remove(s);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Removed ${s}×'),
                        duration: const Duration(seconds: 1)));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? acc.withOpacity(0.25)
                          : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: active ? acc : Colors.white12,
                          width: active ? 1.5 : 1.0),
                    ),
                    child: Text(
                      '${s}×',
                      style: TextStyle(
                          color: active ? Colors.white : Colors.white60,
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.normal),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const Divider(color: Colors.white10, height: 1),

        // ── Add new preset ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Row(children: [
            const Text('Add:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _adding,
                min: 0.1, max: 4.0, divisions: 39,
                activeColor: acc, inactiveColor: Colors.white12,
                label: '${_adding.toStringAsFixed(2)}×',
                onChanged: (v) => setState(() => _adding = v),
              ),
            ),
            GestureDetector(
              onTap: () => _add(_adding),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                    color: acc, borderRadius: BorderRadius.circular(9)),
                child: Text('${_adding.toStringAsFixed(2)}×',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ),
          ]),
        ),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 220.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 180.ms);
  }
}
