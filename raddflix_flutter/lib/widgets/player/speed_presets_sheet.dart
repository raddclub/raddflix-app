/// Phase M1 — Custom Speed Presets
/// Long-press the speed button → speed dial with user's custom speeds.
/// Users can add/remove speeds; persisted in PlayerPrefs.
library speed_presets;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Default speed list
const List<double> _defaultSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
const List<double> _allowedSpeeds = [0.25, 0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0];

/// Parse user preset string "0.5,1.0,1.5,2.0" → [0.5, 1.0, 1.5, 2.0]
List<double> speedPresetsFromString(String s) {
  if (s.isEmpty) return _defaultSpeeds;
  try {
    return s.split(',').map(double.parse).toList()..sort();
  } catch (_) {
    return _defaultSpeeds;
  }
}

/// Encode speeds → "0.5,1.0,1.5,2.0"
String speedPresetsToString(List<double> speeds) =>
    speeds.map((s) => s.toString()).join(',');

// ─────────────────────────────────────────────────────────────────────────────
/// Speed dial overlay shown on long-press of speed button.
/// Returns the newly selected speed or null if dismissed.
class SpeedPresetsSheet extends StatefulWidget {
  final double currentSpeed;
  final List<double> presets;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<List<double>> onPresetsChanged;
  final Color accentColor;

  const SpeedPresetsSheet({
    super.key,
    required this.currentSpeed,
    required this.presets,
    required this.onSpeedSelected,
    required this.onPresetsChanged,
    required this.accentColor,
  });

  static Future<void> show(
    BuildContext context, {
    required double currentSpeed,
    required List<double> presets,
    required ValueChanged<double> onSpeedSelected,
    required ValueChanged<List<double>> onPresetsChanged,
    required Color accentColor,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeedPresetsSheet(
        currentSpeed: currentSpeed,
        presets: presets,
        onSpeedSelected: onSpeedSelected,
        onPresetsChanged: onPresetsChanged,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<SpeedPresetsSheet> createState() => _SpeedPresetsSheetState();
}

class _SpeedPresetsSheetState extends State<SpeedPresetsSheet> {
  late List<double> _presets;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _presets = List<double>.from(widget.presets);
  }

  void _select(double speed) {
    HapticFeedback.selectionClick();
    widget.onSpeedSelected(speed);
    Navigator.of(context).pop();
  }

  void _toggle(double speed) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_presets.contains(speed)) {
        if (_presets.length <= 2) return; // keep at least 2
        _presets.remove(speed);
      } else {
        _presets.add(speed);
        _presets.sort();
      }
    });
    widget.onPresetsChanged(_presets);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white10),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Playback Speed',
                      style: TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _editing = !_editing),
                    child: Text(_editing ? 'Done' : 'Customise',
                        style: TextStyle(
                            color: widget.accentColor, fontSize: 13)),
                  ),
                ],
              ),
            ),
            // Current speed display
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${widget.currentSpeed}×',
                style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            // Speed chips (my presets)
            if (!_editing) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _presets.map((s) {
                    final active = s == widget.currentSpeed;
                    return GestureDetector(
                      onTap: () => _select(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? widget.accentColor.withOpacity(0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: active
                                  ? widget.accentColor
                                  : Colors.white24)),
                        child: Text('${s}×',
                            style: TextStyle(
                                color: active
                                    ? widget.accentColor
                                    : Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              // Edit mode: all available speeds, toggle on/off
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: const Text('Tap to add/remove from your speed list',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _allowedSpeeds.map((s) {
                    final inList = _presets.contains(s);
                    return GestureDetector(
                      onTap: () => _toggle(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: inList
                              ? widget.accentColor.withOpacity(0.15)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: inList
                                  ? widget.accentColor.withOpacity(0.6)
                                  : Colors.white12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (inList)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.check_rounded,
                                  color: widget.accentColor, size: 14),
                            ),
                          Text('${s}×',
                              style: TextStyle(
                                  color: inList
                                      ? widget.accentColor
                                      : Colors.white54,
                                  fontSize: 13)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
