import 'package:flutter/material.dart';

/// Phase D — Advanced Subtitle Style Presets + Custom Config
/// Handles rendering parameters for subtitles.

enum SubtitlePreset {
  clean,       // White text, thin black outline
  cinema,      // Large semi-bold, drop shadow
  highContrast,// Black bg, white bold text
  karaoke,     // Bottom-center, yellow accent
  streaming,   // Netflix-style mid-bottom
  minimal,     // Small, light text, no bg
  neon,        // Coloured outline matching accent
  custom,      // User-defined values
}

class SubtitleStyle {
  final SubtitlePreset preset;
  final double fontSize;
  final Color  textColor;
  final Color  outlineColor;
  final double outlineWidth;
  final Color  bgColor;
  final double bgOpacity;
  final FontWeight fontWeight;
  final bool   italic;
  final bool   shadow;
  final double shadowBlur;
  final Color  shadowColor;
  final String position;  // 'bottom' | 'top' | 'middle'
  final double verticalOffset;
  final double letterSpacing;
  final double lineSpacing;

  const SubtitleStyle({
    this.preset       = SubtitlePreset.clean,
    this.fontSize     = 18.0,
    this.textColor    = Colors.white,
    this.outlineColor = Colors.black,
    this.outlineWidth = 1.5,
    this.bgColor      = Colors.black,
    this.bgOpacity    = 0.0,
    this.fontWeight   = FontWeight.normal,
    this.italic       = false,
    this.shadow       = true,
    this.shadowBlur   = 4.0,
    this.shadowColor  = Colors.black,
    this.position     = 'bottom',
    this.verticalOffset = 0.0,
    this.letterSpacing  = 0.0,
    this.lineSpacing    = 1.4,
  });

  SubtitleStyle copyWith({
    SubtitlePreset? preset, double? fontSize, Color? textColor,
    Color? outlineColor, double? outlineWidth, Color? bgColor,
    double? bgOpacity, FontWeight? fontWeight, bool? italic,
    bool? shadow, double? shadowBlur, Color? shadowColor,
    String? position, double? verticalOffset, double? letterSpacing,
    double? lineSpacing,
  }) => SubtitleStyle(
    preset:         preset        ?? this.preset,
    fontSize:       fontSize      ?? this.fontSize,
    textColor:      textColor     ?? this.textColor,
    outlineColor:   outlineColor  ?? this.outlineColor,
    outlineWidth:   outlineWidth  ?? this.outlineWidth,
    bgColor:        bgColor       ?? this.bgColor,
    bgOpacity:      bgOpacity     ?? this.bgOpacity,
    fontWeight:     fontWeight    ?? this.fontWeight,
    italic:         italic        ?? this.italic,
    shadow:         shadow        ?? this.shadow,
    shadowBlur:     shadowBlur    ?? this.shadowBlur,
    shadowColor:    shadowColor   ?? this.shadowColor,
    position:       position      ?? this.position,
    verticalOffset: verticalOffset ?? this.verticalOffset,
    letterSpacing:  letterSpacing ?? this.letterSpacing,
    lineSpacing:    lineSpacing   ?? this.lineSpacing,
  );

  TextStyle get textStyle => TextStyle(
    fontSize:      fontSize,
    color:         textColor,
    fontWeight:    fontWeight,
    fontStyle:     italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: letterSpacing,
    height:        lineSpacing,
    shadows: [
      if (shadow) Shadow(color: shadowColor, blurRadius: shadowBlur),
      // Multi-direction outline (4 shadows for outline effect)
      Shadow(color: outlineColor, offset: Offset(-outlineWidth, -outlineWidth)),
      Shadow(color: outlineColor, offset: Offset( outlineWidth, -outlineWidth)),
      Shadow(color: outlineColor, offset: Offset(-outlineWidth,  outlineWidth)),
      Shadow(color: outlineColor, offset: Offset( outlineWidth,  outlineWidth)),
    ],
  );
}

/// 8 built-in subtitle style presets.
final Map<SubtitlePreset, SubtitleStyle> kSubtitlePresets = {
  SubtitlePreset.clean: const SubtitleStyle(
    preset: SubtitlePreset.clean,
    fontSize: 18, textColor: Colors.white,
    outlineColor: Colors.black, outlineWidth: 1.5,
    bgOpacity: 0.0, shadow: true, shadowBlur: 3),

  SubtitlePreset.cinema: const SubtitleStyle(
    preset: SubtitlePreset.cinema,
    fontSize: 22, textColor: Colors.white,
    fontWeight: FontWeight.w600,
    outlineColor: Colors.black, outlineWidth: 2,
    bgOpacity: 0.0, shadow: true, shadowBlur: 8,
    shadowColor: Colors.black),

  SubtitlePreset.highContrast: const SubtitleStyle(
    preset: SubtitlePreset.highContrast,
    fontSize: 18, textColor: Colors.white,
    fontWeight: FontWeight.bold,
    outlineColor: Colors.black, outlineWidth: 0,
    bgColor: Colors.black, bgOpacity: 0.85,
    shadow: false),

  SubtitlePreset.karaoke: const SubtitleStyle(
    preset: SubtitlePreset.karaoke,
    fontSize: 20, textColor: Color(0xFFFFEB3B),
    fontWeight: FontWeight.w700,
    outlineColor: Colors.black, outlineWidth: 2,
    bgOpacity: 0.0, shadow: true, shadowBlur: 6),

  SubtitlePreset.streaming: const SubtitleStyle(
    preset: SubtitlePreset.streaming,
    fontSize: 19, textColor: Colors.white,
    fontWeight: FontWeight.w500,
    outlineColor: Color(0xFF111111), outlineWidth: 1.5,
    bgOpacity: 0.0, shadow: true, shadowBlur: 4),

  SubtitlePreset.minimal: const SubtitleStyle(
    preset: SubtitlePreset.minimal,
    fontSize: 15, textColor: Color(0xCCFFFFFF),
    outlineColor: Colors.black, outlineWidth: 0.8,
    bgOpacity: 0.0, shadow: false),

  SubtitlePreset.neon: SubtitleStyle(
    preset: SubtitlePreset.neon,
    fontSize: 18, textColor: Colors.white,
    fontWeight: FontWeight.w600,
    outlineColor: const Color(0xFFD4784A), outlineWidth: 2,
    bgOpacity: 0.0, shadow: true, shadowBlur: 10,
    shadowColor: const Color(0xFFD4784A).withOpacity(0.6)),

  SubtitlePreset.custom: const SubtitleStyle(
    preset: SubtitlePreset.custom),
};

/// Returns a human-readable preset name.
String subtitlePresetName(SubtitlePreset p) {
  switch (p) {
    case SubtitlePreset.clean:        return 'Clean';
    case SubtitlePreset.cinema:       return 'Cinema';
    case SubtitlePreset.highContrast: return 'High Contrast';
    case SubtitlePreset.karaoke:      return 'Karaoke';
    case SubtitlePreset.streaming:    return 'Streaming';
    case SubtitlePreset.minimal:      return 'Minimal';
    case SubtitlePreset.neon:         return 'Neon';
    case SubtitlePreset.custom:       return 'Custom';
  }
}

/// Quick Settings subtitle preset picker — shown as horizontal strip cards.
class SubtitlePresetPicker extends StatelessWidget {
  final SubtitlePreset current;
  final Color accentColor;
  final ValueChanged<SubtitlePreset> onSelected;

  const SubtitlePresetPicker({
    super.key,
    required this.current,
    required this.accentColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: SubtitlePreset.values.where((p) => p != SubtitlePreset.custom).map((preset) {
        final style = kSubtitlePresets[preset]!;
        final sel = current == preset;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onSelected(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 96,
              decoration: BoxDecoration(
                color: sel ? accentColor.withOpacity(0.18) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? accentColor : Colors.white12,
                  width: sel ? 1.5 : 1.0),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Mini subtitle text preview
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: style.bgColor.withOpacity(style.bgOpacity),
                    borderRadius: BorderRadius.circular(2)),
                  child: Text('Abc',
                    style: style.textStyle.copyWith(
                      fontSize: 11, height: 1.1),
                    maxLines: 1),
                ),
                const SizedBox(height: 5),
                Text(subtitlePresetName(preset), style: TextStyle(
                  color: sel ? Colors.white : Colors.white54,
                  fontSize: 9, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
              ]),
            ),
          ),
        );
      }).toList(),
    ),
  );
}
