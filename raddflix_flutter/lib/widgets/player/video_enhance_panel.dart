import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../core/player/player_prefs.dart';

class VideoEnhancePanel extends StatelessWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final VoidCallback onClose;

  const VideoEnhancePanel({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onClose,
  });

  Widget _slider(String label, double value, double min, double max,
      String Function(double)? display, ValueChanged<double> onChange) {
    final disp = display != null ? display(value) : value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(child: Slider(
          value: value.clamp(min, max),
          min: min, max: max,
          activeColor: const Color(0xFFE8002D),
          inactiveColor: Colors.white12,
          onChanged: onChange,
        )),
        SizedBox(width: 44,
            child: Text(disp, style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.right)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(children: [
            const Icon(Icons.tune_rounded, color: Color(0xFFE8002D), size: 18),
            const SizedBox(width: 8),
            const Text('Video Enhancement', style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: () => onChanged(prefs.copyWith(
                brightness: 0.0, contrast: 0.0, saturation: 0.0, hue: 0.0,
                nightMode: false, sharpnessEnabled: false, sharpness: 0.3)),
              child: const Text('Reset', style: TextStyle(color: Colors.white54, fontSize: 12))),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        Flexible(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('ADJUSTMENTS', style: TextStyle(
                    color: Color(0xFFE8002D), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
              _slider('Brightness', prefs.brightness, -0.5, 0.5,
                  (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}',
                  (v) => onChanged(prefs.copyWith(brightness: v))),
              _slider('Contrast', prefs.contrast, -0.5, 0.5,
                  (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}',
                  (v) => onChanged(prefs.copyWith(contrast: v))),
              _slider('Saturation', prefs.saturation, -0.5, 0.5,
                  (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}',
                  (v) => onChanged(prefs.copyWith(saturation: v))),
              _slider('Hue', prefs.hue, -180, 180,
                  (v) => '${v.toInt()}°',
                  (v) => onChanged(prefs.copyWith(hue: v))),

              const Divider(color: Colors.white12, height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('MODES', style: TextStyle(
                    color: Color(0xFFE8002D), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Night Mode 🌙',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('Warm tint, easier on eyes',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                value: prefs.nightMode,
                activeColor: const Color(0xFFE8002D),
                onChanged: (v) => onChanged(prefs.copyWith(nightMode: v)),
              ),
              if (prefs.nightMode)
                _slider('Night Intensity', prefs.nightModeIntensity, 0.1, 1.0,
                    (v) => '${(v * 100).toInt()}%',
                    (v) => onChanged(prefs.copyWith(nightModeIntensity: v))),
              SwitchListTile(
                dense: true,
                title: const Text('Sharpness', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: prefs.sharpnessEnabled,
                activeColor: const Color(0xFFE8002D),
                onChanged: (v) => onChanged(prefs.copyWith(sharpnessEnabled: v)),
              ),
              if (prefs.sharpnessEnabled)
                _slider('Sharpness Level', prefs.sharpness, 0.0, 1.0,
                    (v) => v.toStringAsFixed(2),
                    (v) => onChanged(prefs.copyWith(sharpness: v))),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 220.ms, curve: AppCurves.standard);
  }
}
