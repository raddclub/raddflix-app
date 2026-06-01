import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// Phase D1 — Picture Profiles Sheet
/// Built-in presets + custom save. Applies brightness/contrast/saturation/hue/sharpness/nightMode.

class PictureProfile {
  final String id;
  final String name;
  final String emoji;
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final bool nightMode;
  final double nightIntensity;
  final bool sharpnessEnabled;
  final double sharpness;

  const PictureProfile({
    required this.id,
    required this.name,
    required this.emoji,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.hue = 0,
    this.nightMode = false,
    this.nightIntensity = 0.5,
    this.sharpnessEnabled = false,
    this.sharpness = 0.3,
  });
}

const kBuiltInProfiles = [
  PictureProfile(id: 'natural', name: 'Natural', emoji: '🌿'),
  PictureProfile(
    id: 'cinema', name: 'Cinema', emoji: '🎬',
    contrast: 0.12, saturation: -0.08,
    sharpnessEnabled: true, sharpness: 0.2,
  ),
  PictureProfile(
    id: 'vivid', name: 'Vivid', emoji: '✨',
    contrast: 0.15, saturation: 0.22,
    sharpnessEnabled: true, sharpness: 0.35,
  ),
  PictureProfile(
    id: 'night', name: 'Night Mode', emoji: '🌙',
    brightness: 0.12, contrast: -0.05,
    nightMode: true, nightIntensity: 0.55,
  ),
  PictureProfile(
    id: 'anime', name: 'Anime', emoji: '🎌',
    saturation: 0.2, contrast: 0.1,
    sharpnessEnabled: true, sharpness: 0.4,
  ),
  PictureProfile(
    id: 'amoled', name: 'AMOLED Saver', emoji: '⚫',
    brightness: -0.18, contrast: 0.08,
  ),
];

class PictureProfilesSheet extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onApply;
  final Color accentColor;

  const PictureProfilesSheet({
    super.key,
    required this.prefs,
    required this.onApply,
    required this.accentColor,
  });

  @override
  State<PictureProfilesSheet> createState() => _PictureProfilesSheetState();
}

class _PictureProfilesSheetState extends State<PictureProfilesSheet> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.prefs.pictureProfile;
  }

  void _apply(PictureProfile p) {
    setState(() => _selectedId = p.id);
    widget.onApply(widget.prefs.copyWith(
      pictureProfile: p.id,
      brightness: p.brightness,
      contrast: p.contrast,
      saturation: p.saturation,
      hue: p.hue,
      nightMode: p.nightMode,
      nightModeIntensity: p.nightIntensity,
      sharpnessEnabled: p.sharpnessEnabled,
      sharpness: p.sharpness,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Icon(Icons.photo_filter_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Picture Profiles',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700))),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 5, 16, 12),
          child: Text('Choose a preset to instantly change brightness, contrast & color.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.15,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: kBuiltInProfiles.length,
            itemBuilder: (_, i) {
              final p = kBuiltInProfiles[i];
              final isSel = _selectedId == p.id;
              return GestureDetector(
                onTap: () => _apply(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSel
                        ? acc.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSel ? acc : Colors.white12,
                        width: isSel ? 2.0 : 1.0),
                    boxShadow: isSel
                        ? [BoxShadow(color: acc.withOpacity(0.25), blurRadius: 12)]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 6),
                      Text(p.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: isSel
                                  ? FontWeight.w700
                                  : FontWeight.normal)),
                      if (isSel)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(Icons.check_circle_rounded,
                              color: acc, size: 14),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Current settings summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _ProfileSummary(prefs: widget.prefs, accent: acc),
        ),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 200.ms);
  }
}

class _ProfileSummary extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color accent;
  const _ProfileSummary({required this.prefs, required this.accent});

  @override
  Widget build(BuildContext context) {
    final items = <(String, double)>[
      ('Brightness', prefs.brightness),
      ('Contrast',   prefs.contrast),
      ('Saturation', prefs.saturation),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(color: Colors.white10, height: 16),
      const Text('Current values', style: TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items.map((item) {
        final val = item.$2;
        return Column(children: [
          Text(_fmt(val), style: TextStyle(
              color: val == 0 ? Colors.white54 : accent,
              fontSize: 14, fontWeight: FontWeight.w700)),
          Text(item.$1, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]);
      }).toList()),
    ]);
  }

  String _fmt(double v) {
    if (v == 0) return '—';
    return v > 0 ? '+${(v * 100).toStringAsFixed(0)}%' : '${(v * 100).toStringAsFixed(0)}%';
  }
}
