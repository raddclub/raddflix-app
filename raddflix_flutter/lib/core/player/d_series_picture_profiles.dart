/// Phase D1 — Picture Profiles
/// User creates named presets of video look settings (brightness, contrast,
/// saturation, color grading). Save/load/apply profiles.
/// D4 — Ambilight (already partially done — this extends it with custom colors)
library d_series;

import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// D1 — Picture Profile
// ─────────────────────────────────────────────────────────────────────────────

class PictureProfile {
  final String id;
  final String name;
  final double brightness;    // 0.0 – 2.0, 1.0 = normal
  final double contrast;      // 0.0 – 2.0, 1.0 = normal
  final double saturation;    // 0.0 – 3.0, 1.0 = normal
  final double warmth;        // -1.0 – 1.0, 0 = neutral
  final String colorLook;     // matches video_look_filter.dart videoLookIds
  final bool isBuiltIn;

  const PictureProfile({
    required this.id,
    required this.name,
    this.brightness  = 1.0,
    this.contrast    = 1.0,
    this.saturation  = 1.0,
    this.warmth      = 0.0,
    this.colorLook   = 'none',
    this.isBuiltIn   = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name,
    'brightness': brightness, 'contrast': contrast,
    'saturation': saturation, 'warmth': warmth,
    'colorLook': colorLook, 'isBuiltIn': isBuiltIn,
  };

  factory PictureProfile.fromJson(Map<String, dynamic> j) => PictureProfile(
    id: j['id'], name: j['name'],
    brightness: (j['brightness'] as num?)?.toDouble() ?? 1.0,
    contrast:   (j['contrast'] as num?)?.toDouble()   ?? 1.0,
    saturation: (j['saturation'] as num?)?.toDouble() ?? 1.0,
    warmth:     (j['warmth'] as num?)?.toDouble()     ?? 0.0,
    colorLook:  j['colorLook'] ?? 'none',
    isBuiltIn:  j['isBuiltIn'] ?? false,
  );

  PictureProfile copyWith({
    String? name, double? brightness, double? contrast,
    double? saturation, double? warmth, String? colorLook,
  }) => PictureProfile(
    id: id, name: name ?? this.name,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    colorLook: colorLook ?? this.colorLook,
    isBuiltIn: isBuiltIn,
  );

  static PictureProfile get standard => const PictureProfile(
      id: 'standard', name: '⬜ Standard', isBuiltIn: true);
  static PictureProfile get cinema => const PictureProfile(
      id: 'cinema', name: '🎬 Cinema', brightness: 0.88,
      contrast: 1.2, saturation: 1.1, warmth: -0.05,
      colorLook: 'teal-orange', isBuiltIn: true);
  static PictureProfile get vivid => const PictureProfile(
      id: 'vivid', name: '✨ Vivid', brightness: 1.05,
      contrast: 1.15, saturation: 1.4, isBuiltIn: true);
  static PictureProfile get night => const PictureProfile(
      id: 'night', name: '🌙 Night', brightness: 0.7,
      contrast: 0.9, saturation: 0.85, warmth: 0.1, isBuiltIn: true);
  static PictureProfile get documentary => const PictureProfile(
      id: 'documentary', name: '📷 Documentary', brightness: 0.95,
      contrast: 1.05, saturation: 0.9, colorLook: 'faded-film', isBuiltIn: true);
  static PictureProfile get anime => const PictureProfile(
      id: 'anime', name: '🎌 Anime', saturation: 1.5,
      contrast: 1.1, isBuiltIn: true);
  static PictureProfile get sports => const PictureProfile(
      id: 'sports', name: '⚽ Sports', brightness: 1.1,
      contrast: 1.2, saturation: 1.3, isBuiltIn: true);

  static List<PictureProfile> get builtIns => [
    standard, cinema, vivid, night, documentary, anime, sports];
}

// ── Profile store ─────────────────────────────────────────────────────────────
class PictureProfileStore {
  PictureProfileStore._();
  static final instance = PictureProfileStore._();

  final List<PictureProfile> _custom = [];
  List<PictureProfile> get all => [...PictureProfile.builtIns, ..._custom];

  void loadFromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      _custom.clear();
      _custom.addAll(list.cast<Map<String, dynamic>>()
          .map(PictureProfile.fromJson));
    } catch (_) {}
  }

  String toJson() =>
      jsonEncode(_custom.map((p) => p.toJson()).toList());

  void add(PictureProfile profile) => _custom.add(profile);
  void remove(String id) => _custom.removeWhere((p) => p.id == id);

  PictureProfile? findById(String id) {
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Picture Profile Quick Picker (horizontal chips for QSP)
// ─────────────────────────────────────────────────────────────────────────────
class PictureProfilePicker extends StatelessWidget {
  final String currentProfileId;
  final ValueChanged<PictureProfile> onSelected;
  final Color accentColor;

  const PictureProfilePicker({
    super.key,
    required this.currentProfileId,
    required this.onSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final profiles = PictureProfileStore.instance.all;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: profiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final p = profiles[i];
          final active = p.id == currentProfileId;
          return GestureDetector(
            onTap: () => onSelected(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? accentColor.withOpacity(0.2) : Colors.white10,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? accentColor : Colors.white24, width: 1.2)),
              child: Text(p.name,
                  style: TextStyle(
                      color: active ? accentColor : Colors.white60,
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          );
        },
      ),
    );
  }
}
