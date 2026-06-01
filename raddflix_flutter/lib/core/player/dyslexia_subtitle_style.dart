/// Phase J3 — Dyslexia-Friendly Subtitle Font
/// Option to use OpenDyslexic or Lexie Readable for subtitle text.
/// Since custom font files are bundled in assets, we register a TextStyle factory.
library dyslexia_subtitle;

import 'package:flutter/material.dart';

enum SubtitleFont {
  system,       // default (whatever the OS uses)
  openDyslexic, // OpenDyslexic (bundled in assets/fonts/)
  lexieReadable,// Lexie Readable (bundled in assets/fonts/)
  roboto,       // Roboto Slab — clean, readable
  atkinson,     // Atkinson Hyperlegible — designed for low vision
}

SubtitleFont subtitleFontFromString(String s) {
  switch (s) {
    case 'open_dyslexic':   return SubtitleFont.openDyslexic;
    case 'lexie_readable':  return SubtitleFont.lexieReadable;
    case 'roboto':          return SubtitleFont.roboto;
    case 'atkinson':        return SubtitleFont.atkinson;
    default:                return SubtitleFont.system;
  }
}

String subtitleFontToString(SubtitleFont f) {
  switch (f) {
    case SubtitleFont.openDyslexic:  return 'open_dyslexic';
    case SubtitleFont.lexieReadable: return 'lexie_readable';
    case SubtitleFont.roboto:        return 'roboto';
    case SubtitleFont.atkinson:      return 'atkinson';
    default:                         return 'system';
  }
}

const subtitleFontLabels = {
  SubtitleFont.system:       'System Default',
  SubtitleFont.openDyslexic: 'OpenDyslexic',
  SubtitleFont.lexieReadable:'Lexie Readable',
  SubtitleFont.roboto:       'Roboto Slab',
  SubtitleFont.atkinson:     'Atkinson Hyperlegible',
};

/// Returns the font family name for the given SubtitleFont.
/// Must match the family name registered in pubspec.yaml assets/fonts.
String? fontFamilyFor(SubtitleFont f) {
  switch (f) {
    case SubtitleFont.openDyslexic:  return 'OpenDyslexic';
    case SubtitleFont.lexieReadable: return 'LexieReadable';
    case SubtitleFont.roboto:        return 'RobotoSlab';
    case SubtitleFont.atkinson:      return 'AtkinsonHyperlegible';
    default:                         return null;
  }
}

/// Returns a TextStyle for subtitles with the requested font applied.
TextStyle subtitleTextStyle({
  required SubtitleFont font,
  required double fontSize,
  required Color color,
  double letterSpacing = 0.0,
  double wordSpacing   = 0.0,
  double lineHeight    = 1.4,
}) {
  final family = fontFamilyFor(font);
  return TextStyle(
    fontFamily:    family,
    fontSize:      fontSize,
    color:         color,
    height:        lineHeight,
    letterSpacing: letterSpacing,
    wordSpacing:   wordSpacing,
    // Accessibility font flags
    fontFeatures:  font == SubtitleFont.atkinson
        ? const [FontFeature.enable('kern')]
        : null,
    shadows: const [
      Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
    ],
  );
}
