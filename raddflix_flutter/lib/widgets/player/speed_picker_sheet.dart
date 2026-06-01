import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase G — Enhanced Playback Speed Picker
/// Replaces the basic speed list with a premium sheet featuring:
/// custom speed dial, memory, per-content speed, pitch correction toggle.
class SpeedPickerSheet extends StatefulWidget {
  final double currentSpeed;
  final bool rememberSpeed;
  final bool pitchCorrection;
  final Color accentColor;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<bool> onRememberToggled;
  final ValueChanged<bool> onPitchToggled;

  const SpeedPickerSheet({
    super.key,
    required this.currentSpeed,
    this.rememberSpeed = false,
    this.pitchCorrection = true,
    required this.accentColor,
    required this.onSpeedChanged,
    required this.onRememberToggled,
    required this.onPitchToggled,
  });

  @override
  State<SpeedPickerSheet> createState() => _SpeedPickerSheetState();
}

class _SpeedPickerSheetState extends State<SpeedPickerSheet> {
  late double _speed;
  late bool   _remember;
  late bool   _pitch;
  bool _customMode = false;

  static const _presets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  @override
  void initState() {
    super.initState();
    _speed   = widget.currentSpeed;
    _remember = widget.rememberSpeed;
    _pitch    = widget.pitchCorrection;
    _customMode = !_presets.contains(_speed);
  }

  void _setSpeed(double v) {
    HapticFeedback.selectionClick();
    setState(() { _speed = v; _customMode = false; });
    widget.onSpeedChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Icon(Icons.speed_rounded, color: acc, size: 22),
            const SizedBox(width: 10),
            const Expanded(child: Text('Playback Speed',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            // Current speed badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: acc.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: acc.withOpacity(0.5))),
              child: Text('${_speed}×', style: TextStyle(
                color: acc, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 20),

        // Quick speed slider
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Text('0.25×', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Expanded(child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: acc,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: acc.withOpacity(0.2),
              ),
              child: Slider(
                value: _speed.clamp(0.25, 3.0),
                min: 0.25, max: 3.0,
                divisions: 55,
                onChanged: (v) {
                  setState(() { _speed = double.parse(v.toStringAsFixed(2)); });
                  widget.onSpeedChanged(_speed);
                },
              ),
            )),
            const Text('3.0×', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        ),

        // Preset grid
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ..._presets.map((s) {
              final sel = !_customMode && (_speed - s).abs() < 0.001;
              return GestureDetector(
                onTap: () => _setSpeed(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 60, height: 40,
                  decoration: BoxDecoration(
                    color: sel ? acc.withOpacity(0.22) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? acc : Colors.white12, width: sel ? 1.5 : 1)),
                  child: Center(child: Text('${s}×', style: TextStyle(
                    color: sel ? Colors.white : Colors.white60,
                    fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.normal))),
                ),
              );
            }),
            // Reset to 1x
            GestureDetector(
              onTap: () => _setSpeed(1.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 60, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12)),
                child: const Center(child: Icon(Icons.refresh_rounded,
                    color: Colors.white54, size: 18)),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Options
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(children: [
            _SpeedOption(
              icon: Icons.bookmark_added_rounded,
              label: 'Remember speed for this content',
              value: _remember,
              accent: acc,
              onChanged: (v) { setState(() => _remember = v); widget.onRememberToggled(v); }),
            const SizedBox(height: 4),
            _SpeedOption(
              icon: Icons.music_note_rounded,
              label: 'Pitch correction (keeps natural voice)',
              value: _pitch,
              accent: acc,
              onChanged: (v) { setState(() => _pitch = v); widget.onPitchToggled(v); }),
          ]),
        ),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 200.ms);
  }
}

class _SpeedOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _SpeedOption({required this.icon, required this.label, required this.value,
      required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: value ? accent : Colors.white38, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Switch(value: value, activeColor: accent, onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    ),
  );
}
