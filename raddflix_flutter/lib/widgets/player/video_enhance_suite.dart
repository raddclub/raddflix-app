import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase C — Video Enhancement Suite
/// Advanced colour, sharpness, noise, deband, and crop controls.
/// Shown as a side panel within the player.
class VideoEnhanceSuite extends StatefulWidget {
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final double sharpness;
  final bool sharpnessEnabled;
  final bool nightMode;
  final double nightModeIntensity;
  final bool cinematicMode;
  final double cinematicOpacity;
  final bool ambilightEnabled;
  final Color accentColor;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const VideoEnhanceSuite({
    super.key,
    this.brightness    = 1.0,
    this.contrast      = 1.0,
    this.saturation    = 1.0,
    this.hue           = 0.0,
    this.sharpness     = 0.5,
    this.sharpnessEnabled = false,
    this.nightMode        = false,
    this.nightModeIntensity = 0.4,
    this.cinematicMode    = false,
    this.cinematicOpacity = 0.5,
    this.ambilightEnabled = false,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  State<VideoEnhanceSuite> createState() => _VideoEnhanceSuiteState();
}

class _VideoEnhanceSuiteState extends State<VideoEnhanceSuite>
    with SingleTickerProviderStateMixin {
  late double _brightness;
  late double _contrast;
  late double _saturation;
  late double _hue;
  late double _sharpness;
  late bool   _sharpnessEnabled;
  late bool   _nightMode;
  late double _nightModeIntensity;
  late bool   _cinematicMode;
  late double _cinematicOpacity;
  late bool   _ambilight;

  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _brightness       = widget.brightness;
    _contrast         = widget.contrast;
    _saturation       = widget.saturation;
    _hue              = widget.hue;
    _sharpness        = widget.sharpness;
    _sharpnessEnabled = widget.sharpnessEnabled;
    _nightMode        = widget.nightMode;
    _nightModeIntensity = widget.nightModeIntensity;
    _cinematicMode    = widget.cinematicMode;
    _cinematicOpacity = widget.cinematicOpacity;
    _ambilight        = widget.ambilightEnabled;
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _emit() {
    widget.onChanged({
      'brightness': _brightness, 'contrast': _contrast,
      'saturation': _saturation, 'hue': _hue,
      'sharpness': _sharpness, 'sharpnessEnabled': _sharpnessEnabled,
      'nightMode': _nightMode, 'nightModeIntensity': _nightModeIntensity,
      'cinematicMode': _cinematicMode, 'cinematicOpacity': _cinematicOpacity,
      'ambilightEnabled': _ambilight,
    });
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Icon(Icons.auto_fix_high_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Video Enhancement',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: _resetAll,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Reset', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(foregroundColor: Colors.white38)),
          ]),
        ),
        TabBar(
          controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: acc, indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white, unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [Tab(text: 'Colour'), Tab(text: 'Effects'), Tab(text: 'Modes')],
        ),
        const Divider(height: 1, color: Colors.white12),
        Flexible(child: TabBarView(controller: _tab, children: [
          _buildColourTab(acc),
          _buildEffectsTab(acc),
          _buildModesTab(acc),
        ])),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 180.ms);
  }

  Widget _buildColourTab(Color acc) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      _EnhanceSlider(label: 'Brightness', icon: Icons.brightness_6_rounded,
        value: _brightness, min: 0.0, max: 2.0, neutral: 1.0, accent: acc,
        format: (v) => '${((v - 1.0) * 100).round():+}%',
        onChanged: (v) { setState(() => _brightness = v); _emit(); }),
      _EnhanceSlider(label: 'Contrast', icon: Icons.contrast_rounded,
        value: _contrast, min: 0.0, max: 3.0, neutral: 1.0, accent: acc,
        format: (v) => '${((v - 1.0) * 100).round():+}%',
        onChanged: (v) { setState(() => _contrast = v); _emit(); }),
      _EnhanceSlider(label: 'Saturation', icon: Icons.palette_rounded,
        value: _saturation, min: 0.0, max: 3.0, neutral: 1.0, accent: acc,
        format: (v) => '${((v - 1.0) * 100).round():+}%',
        onChanged: (v) { setState(() => _saturation = v); _emit(); }),
      _EnhanceSlider(label: 'Hue', icon: Icons.color_lens_rounded,
        value: _hue, min: -180.0, max: 180.0, neutral: 0.0, accent: acc,
        format: (v) => '${v.round()}°',
        onChanged: (v) { setState(() => _hue = v); _emit(); }),
      // Quick presets
      const SizedBox(height: 12),
      const Text('Quick Presets', style: TextStyle(
          color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _preset('Cinema',   () { setState(() { _brightness=0.85; _contrast=1.2; _saturation=1.1; _hue=0; }); _emit(); }, acc),
        _preset('Vivid',    () { setState(() { _brightness=1.1;  _contrast=1.3; _saturation=1.8; _hue=0; }); _emit(); }, acc),
        _preset('Night',    () { setState(() { _brightness=0.5;  _contrast=0.9; _saturation=0.8; _hue=0; }); _emit(); }, acc),
        _preset('Warm',     () { setState(() { _brightness=1.0;  _contrast=1.0; _saturation=1.2; _hue=10;}); _emit(); }, acc),
        _preset('Cool',     () { setState(() { _brightness=1.0;  _contrast=1.0; _saturation=1.1; _hue=-15;}); _emit(); }, acc),
        _preset('B & W',    () { setState(() { _brightness=1.0;  _contrast=1.3; _saturation=0.0; _hue=0; }); _emit(); }, acc),
      ]),
    ],
  );

  Widget _preset(String label, VoidCallback onTap, Color acc) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12)),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
  );

  Widget _buildEffectsTab(Color acc) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      _EnhanceToggle(
        label: 'Sharpness',
        subtitle: 'Edge enhancement filter',
        icon: Icons.grain_rounded,
        value: _sharpnessEnabled,
        accent: acc,
        onChanged: (v) { setState(() => _sharpnessEnabled = v); _emit(); },
      ),
      if (_sharpnessEnabled)
        _EnhanceSlider(label: 'Intensity', icon: Icons.settings_rounded,
          value: _sharpness, min: 0.0, max: 1.0, neutral: 0.5, accent: acc,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) { setState(() => _sharpness = v); _emit(); }),
      const Divider(color: Colors.white10, height: 24),
      _EnhanceToggle(
        label: 'Ambilight',
        subtitle: 'Glow effect matching video edges',
        icon: Icons.light_mode_rounded,
        value: _ambilight,
        accent: acc,
        onChanged: (v) { setState(() => _ambilight = v); _emit(); },
      ),
    ],
  );

  Widget _buildModesTab(Color acc) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      _EnhanceToggle(
        label: 'Night Mode',
        subtitle: 'Reduces blue light for night viewing',
        icon: Icons.nights_stay_rounded,
        value: _nightMode,
        accent: acc,
        onChanged: (v) { setState(() => _nightMode = v); _emit(); },
      ),
      if (_nightMode)
        _EnhanceSlider(label: 'Warmth', icon: Icons.thermostat_rounded,
          value: _nightModeIntensity, min: 0.1, max: 0.9, neutral: 0.4, accent: acc,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) { setState(() => _nightModeIntensity = v); _emit(); }),
      const Divider(color: Colors.white10, height: 24),
      _EnhanceToggle(
        label: 'Cinematic Mode',
        subtitle: 'Letterbox bars + atmospheric border',
        icon: Icons.movie_creation_rounded,
        value: _cinematicMode,
        accent: acc,
        onChanged: (v) { setState(() => _cinematicMode = v); _emit(); },
      ),
      if (_cinematicMode)
        _EnhanceSlider(label: 'Intensity', icon: Icons.crop_rounded,
          value: _cinematicOpacity, min: 0.1, max: 0.9, neutral: 0.5, accent: acc,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) { setState(() => _cinematicOpacity = v); _emit(); }),
    ],
  );

  void _resetAll() {
    setState(() {
      _brightness = 1.0; _contrast = 1.0; _saturation = 1.0; _hue = 0.0;
      _sharpness  = 0.5; _sharpnessEnabled = false;
      _nightMode  = false; _nightModeIntensity = 0.4;
      _cinematicMode = false; _cinematicOpacity = 0.5;
      _ambilight = false;
    });
    _emit();
  }
}

// ── Shared Enhancement Widgets ────────────────────────────────────────────────
class _EnhanceSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value, min, max, neutral;
  final Color accent;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _EnhanceSlider({
    required this.label, required this.icon, required this.value,
    required this.min, required this.max, required this.neutral,
    required this.accent, required this.format, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: value == neutral ? Colors.white10 : accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value == neutral ? Colors.white12 : accent.withOpacity(0.5))),
          child: Text(format(value), style: TextStyle(
            color: value == neutral ? Colors.white54 : Colors.white,
            fontSize: 10, fontFamily: 'monospace')),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white12,
          thumbColor: Colors.white,
          overlayColor: accent.withOpacity(0.2),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min, max: max,
          onChanged: onChanged,
        ),
      ),
    ]),
  );
}

class _EnhanceToggle extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _EnhanceToggle({
    required this.label, required this.subtitle, required this.icon,
    required this.value, required this.accent, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: value ? accent.withOpacity(0.18) : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: value ? accent : Colors.white12)),
          child: Icon(icon, color: value ? accent : Colors.white38, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Switch(value: value, activeColor: accent, onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    ),
  );
}
