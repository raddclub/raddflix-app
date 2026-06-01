/// Phase T — App Themes & Branding
/// T1 — Dynamic Theme (system dark/light + 3 custom themes)
/// T2 — Accent Colour Presets (12 branded Pakistani palette colours)
/// T3 — AMOLED / True Black Mode
/// T4 — Gradient Backgrounds (profile header + home hero)
library t_series;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// T2 — Accent Colours (12 branded presets)
// ─────────────────────────────────────────────────────────────────────────────

const accentPresets = [
  // Name → Color
  ('Radd Red',      Color(0xFFE53935)),
  ('Emerald',       Color(0xFF00BFA5)),
  ('Royal Blue',    Color(0xFF1565C0)),
  ('Saffron',       Color(0xFFFF8F00)),
  ('Orchid',        Color(0xFF8E24AA)),
  ('Jasmine',       Color(0xFFFFD54F)),
  ('Turquoise',     Color(0xFF00ACC1)),
  ('Coral',         Color(0xFFFF7043)),
  ('Indigo',        Color(0xFF3949AB)),
  ('Lime',          Color(0xFF9CCC65)),
  ('Rose Gold',     Color(0xFFF48FB1)),
  ('Pure White',    Color(0xFFFFFFFF)),
];

Color accentFromHex(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFFE53935);
  }
}

String hexFromColor(Color c) =>
    '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

// ─────────────────────────────────────────────────────────────────────────────
// T1 — App theme builder
// ─────────────────────────────────────────────────────────────────────────────

enum AppThemeVariant { dark, amoled, oled60, system }

const themeVariantLabels = {
  AppThemeVariant.dark:   '🌑 Dark',
  AppThemeVariant.amoled: '⬛ AMOLED (True Black)',
  AppThemeVariant.oled60: '🌒 60% Dark (OLED Battery Saver)',
  AppThemeVariant.system: '📱 Follow System',
};

AppThemeVariant themeVariantFromString(String s) =>
    AppThemeVariant.values.firstWhere((v) => v.name == s,
        orElse: () => AppThemeVariant.dark);

ThemeData buildAppTheme({
  required Color accent,
  required AppThemeVariant variant,
  Brightness? systemBrightness,
}) {
  final isLight = variant == AppThemeVariant.system &&
      systemBrightness == Brightness.light;

  Color bg, surface, card;
  if (isLight) {
    bg = Colors.white; surface = const Color(0xFFF5F5F5); card = Colors.white;
  } else {
    switch (variant) {
      case AppThemeVariant.amoled:
        bg = Colors.black; surface = const Color(0xFF0A0A0A);
        card = const Color(0xFF111111);
      case AppThemeVariant.oled60:
        bg = const Color(0xFF191919); surface = const Color(0xFF212121);
        card = const Color(0xFF232323);
      default:
        bg = const Color(0xFF1A1A1A); surface = const Color(0xFF242424);
        card = const Color(0xFF2C2C2C);
    }
  }

  return ThemeData(
    brightness: isLight ? Brightness.light : Brightness.dark,
    colorSchemeSeed: accent,
    scaffoldBackgroundColor: bg,
    cardColor: card,
    primaryColor: accent,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: isLight ? Colors.black : Colors.white,
      elevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.white38),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withOpacity(0.5) : Colors.white12),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// T4 — Gradient Backgrounds
// ─────────────────────────────────────────────────────────────────────────────

class AccentGradientBox extends StatelessWidget {
  final Color accent;
  final Widget child;
  final double height;
  final bool bottom; // gradient from bottom or top

  const AccentGradientBox({
    super.key,
    required this.accent,
    required this.child,
    this.height = 200,
    this.bottom = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned(
        left: 0, right: 0,
        bottom: bottom ? 0 : null,
        top: bottom ? null : 0,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
              end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
              colors: [
                accent.withOpacity(0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Accent Colour Picker (QSP / Settings widget)
// ─────────────────────────────────────────────────────────────────────────────
class AccentColorPicker extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onSelected;

  const AccentColorPicker({
    super.key,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: accentPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (name, color) = accentPresets[i];
          final isSelected = color.value == current.value;
          return Tooltip(
            message: name,
            child: GestureDetector(
              onTap: () => onSelected(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: isSelected ? 38 : 32,
                height: isSelected ? 38 : 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.5),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
