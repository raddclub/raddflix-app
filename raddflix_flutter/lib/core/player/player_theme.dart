import 'package:flutter/material.dart';

/// A RaddFlix player skin — accent color + seek bar style + optional overrides.
class PlayerTheme {
  final String id;
  final String name;
  final String emoji;
  final Color accentColor;
  final String seekBarStyle;
  final Color? gradientColor1;
  final Color? gradientColor2;

  const PlayerTheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.accentColor,
    required this.seekBarStyle,
    this.gradientColor1,
    this.gradientColor2,
  });
}

const List<PlayerTheme> kBuiltInThemes = [
  PlayerTheme(
    id: 'raddflix_red',
    name: 'RaddFlix Amber',
    emoji: '🟠',
    accentColor: Color(0xFFD4784A),
    seekBarStyle: 'classic',
  ),
  PlayerTheme(
    id: 'midnight_purple',
    name: 'Midnight Purple',
    emoji: '🌙',
    accentColor: Color(0xFF9C27B0),
    seekBarStyle: 'gradientGlow',
    gradientColor1: Color(0xFF9C27B0),
    gradientColor2: Color(0xFF3F51B5),
  ),
  PlayerTheme(
    id: 'sakura_pink',
    name: 'Sakura Pink',
    emoji: '🌸',
    accentColor: Color(0xFFFF4081),
    seekBarStyle: 'waveform',
    gradientColor1: Color(0xFFFF4081),
    gradientColor2: Color(0xFFFF80AB),
  ),
  PlayerTheme(
    id: 'gold_class',
    name: 'Gold Class',
    emoji: '🏆',
    accentColor: Color(0xFFFFD700),
    seekBarStyle: 'materialBold',
  ),
  PlayerTheme(
    id: 'matrix_green',
    name: 'Matrix Green',
    emoji: '💚',
    accentColor: Color(0xFF00E676),
    seekBarStyle: 'neonRgb',
  ),
  PlayerTheme(
    id: 'ocean_cyan',
    name: 'Ocean Cyan',
    emoji: '🌊',
    accentColor: Color(0xFF00BCD4),
    seekBarStyle: 'gradientGlow',
    gradientColor1: Color(0xFF00BCD4),
    gradientColor2: Color(0xFF1565C0),
  ),
  PlayerTheme(
    id: 'sunset_orange',
    name: 'Sunset Orange',
    emoji: '🌅',
    accentColor: Color(0xFFFF6F00),
    seekBarStyle: 'materialBold',
  ),
  PlayerTheme(
    id: 'snow_white',
    name: 'Snow White',
    emoji: '❄️',
    accentColor: Color(0xFFFFFFFF),
    seekBarStyle: 'minimal',
  ),
];

PlayerTheme themeById(String id) =>
    kBuiltInThemes.firstWhere((t) => t.id == id,
        orElse: () => kBuiltInThemes.first);
