// lib/core/theme/radd_theme.dart
import 'package:flutter/material.dart';

// ── ThemeExtension so any screen can read the active RaddTheme ───────────────
class RaddThemeExtension extends ThemeExtension<RaddThemeExtension> {
  final RaddTheme theme;
  const RaddThemeExtension(this.theme);
  @override
  ThemeExtension<RaddThemeExtension> copyWith({RaddTheme? theme}) =>
      RaddThemeExtension(theme ?? this.theme);
  @override
  ThemeExtension<RaddThemeExtension> lerp(
          covariant ThemeExtension<RaddThemeExtension>? other, double t) =>
      this;
}

class RaddTheme {
  final Color bg;
  final Color bgAlt;
  final Color surface;
  final Color surfaceHigh;
  final Color card;
  final Color cardBorder;
  final Color glass;
  final Color glassHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color divider;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color heroStop;

  const RaddTheme({
    required this.bg,
    required this.bgAlt,
    required this.surface,
    required this.surfaceHigh,
    required this.card,
    required this.cardBorder,
    required this.glass,
    required this.glassHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.divider,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.heroStop,
  });

  // ── Resolve active theme from ThemeData extension (set by JazzThemeData.build)
  static RaddTheme of(BuildContext context) {
    final ext = Theme.of(context).extension<RaddThemeExtension>();
    if (ext != null) return ext.theme;
    // Legacy fallback — no extension means app hasn't fully built yet
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light) return light;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    if (scaffoldBg == const Color(0xFF000000)) return amoled;
    return dark;
  }

  LinearGradient get heroGradient => LinearGradient(
        colors: [Colors.transparent, heroStop],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.3, 1.0],
      );

  // ══════════════════════════════════════════════════════════════════════════
  //  DARK  — default deep navy-black (richer depth + visible card borders)
  // ══════════════════════════════════════════════════════════════════════════
  // ── Warm Hearth dark: brown-black warmth, amber primary, cream text ──────────
  static const RaddTheme dark = RaddTheme(
    bg:               Color(0xFF130F0C),
    bgAlt:            Color(0xFF1A1410),
    surface:          Color(0xFF211A15),
    surfaceHigh:      Color(0xFF2C2219),
    card:             Color(0xFF352A1F),
    cardBorder:       Color(0xFF4A3828),
    glass:            Color(0x10FFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x15FFFFFF),
    textPrimary:      Color(0xFFF5EFE6),
    textSecondary:    Color(0xFFC8B5A0),
    textMuted:        Color(0xFF8A7060),
    textDisabled:     Color(0xFF5A4838),
    divider:          Color(0xFF2A2018),
    shimmerBase:      Color(0xFF211A15),
    shimmerHighlight: Color(0xFF2C2219),
    heroStop:         Color(0xFF130F0C),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  AMOLED  — pure black, zero battery on OLED
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme amoled = RaddTheme(
    bg:               Color(0xFF000000),
    bgAlt:            Color(0xFF080808),
    surface:          Color(0xFF0A0A0A),
    surfaceHigh:      Color(0xFF111111),
    card:             Color(0xFF111111),
    cardBorder:       Color(0xFF1E1E1E),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x12FFFFFF),
    textPrimary:      Color(0xFFF5EFE6),
    textSecondary:    Color(0xFFC8B5A0),
    textMuted:        Color(0xFF8A7060),
    textDisabled:     Color(0xFF5A4838),
    divider:          Color(0xFF141414),
    shimmerBase:      Color(0xFF0A0A0A),
    shimmerHighlight: Color(0xFF111111),
    heroStop:         Color(0xFF000000),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  LIGHT
  // ══════════════════════════════════════════════════════════════════════════
  // ── Warm Hearth light: linen/paper warmth — sunlit room, not sterile office ──
  static const RaddTheme light = RaddTheme(
    bg:               Color(0xFFFAF6F0),
    bgAlt:            Color(0xFFF0E8DC),
    surface:          Color(0xFFFFFFFF),
    surfaceHigh:      Color(0xFFFAF4EC),
    card:             Color(0xFFF0E8DC),
    cardBorder:       Color(0xFFE0CEB8),
    glass:            Color(0x0A000000),
    glassHigh:        Color(0x14000000),
    border:           Color(0xFFE0CEB8),
    textPrimary:      Color(0xFF1A110A),
    textSecondary:    Color(0xFF5A4435),
    textMuted:        Color(0xFF8A7060),
    textDisabled:     Color(0xFFC0A888),
    divider:          Color(0xFFE8D8C8),
    shimmerBase:      Color(0xFFF0E8DC),
    shimmerHighlight: Color(0xFFFAF4EC),
    heroStop:         Color(0xFFFAF6F0),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  MIDNIGHT  — deep cinematic purple-navy
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme midnight = RaddTheme(
    bg:               Color(0xFF070712),
    bgAlt:            Color(0xFF0C0C1F),
    surface:          Color(0xFF0C0C22),
    surfaceHigh:      Color(0xFF131335),
    card:             Color(0xFF181838),
    cardBorder:       Color(0xFF23234A),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x16FFFFFF),
    textPrimary:      Color(0xFFF0F0FF),
    textSecondary:    Color(0xFFB8B8E8),
    textMuted:        Color(0xFF6060A0),
    textDisabled:     Color(0xFF383865),
    divider:          Color(0xFF1E1E40),
    shimmerBase:      Color(0xFF0C0C22),
    shimmerHighlight: Color(0xFF131335),
    heroStop:         Color(0xFF070712),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  NAVY  — dark oceanic blue
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme navy = RaddTheme(
    bg:               Color(0xFF060D1A),
    bgAlt:            Color(0xFF0A1525),
    surface:          Color(0xFF0D1A2E),
    surfaceHigh:      Color(0xFF122240),
    card:             Color(0xFF162A4A),
    cardBorder:       Color(0xFF1E3A5F),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x14FFFFFF),
    textPrimary:      Color(0xFFEEF4FF),
    textSecondary:    Color(0xFFAAC4E8),
    textMuted:        Color(0xFF557AA0),
    textDisabled:     Color(0xFF334A65),
    divider:          Color(0xFF1A2D44),
    shimmerBase:      Color(0xFF0D1A2E),
    shimmerHighlight: Color(0xFF122240),
    heroStop:         Color(0xFF060D1A),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  FOREST  — deep emerald dark
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme forest = RaddTheme(
    bg:               Color(0xFF060E09),
    bgAlt:            Color(0xFF0A1A0D),
    surface:          Color(0xFF0C1A10),
    surfaceHigh:      Color(0xFF102216),
    card:             Color(0xFF152B1A),
    cardBorder:       Color(0xFF1E3D25),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x14FFFFFF),
    textPrimary:      Color(0xFFEEFFF2),
    textSecondary:    Color(0xFFAAD4B8),
    textMuted:        Color(0xFF507860),
    textDisabled:     Color(0xFF2E4835),
    divider:          Color(0xFF172C1E),
    shimmerBase:      Color(0xFF0C1A10),
    shimmerHighlight: Color(0xFF102216),
    heroStop:         Color(0xFF060E09),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  COBALT  — rich electric blue
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme cobalt = RaddTheme(
    bg:               Color(0xFF060A1A),
    bgAlt:            Color(0xFF0A1030),
    surface:          Color(0xFF0D1535),
    surfaceHigh:      Color(0xFF131E48),
    card:             Color(0xFF18255A),
    cardBorder:       Color(0xFF22316E),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x16FFFFFF),
    textPrimary:      Color(0xFFEEF2FF),
    textSecondary:    Color(0xFFAABBEE),
    textMuted:        Color(0xFF5060A8),
    textDisabled:     Color(0xFF303870),
    divider:          Color(0xFF181E48),
    shimmerBase:      Color(0xFF0D1535),
    shimmerHighlight: Color(0xFF131E48),
    heroStop:         Color(0xFF060A1A),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  ROSE  — warm wine / burgundy
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme rose = RaddTheme(
    bg:               Color(0xFF100608),
    bgAlt:            Color(0xFF1A0A0D),
    surface:          Color(0xFF1C0C10),
    surfaceHigh:      Color(0xFF25121A),
    card:             Color(0xFF2E1822),
    cardBorder:       Color(0xFF3D2030),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x15FFFFFF),
    textPrimary:      Color(0xFFFFF0F2),
    textSecondary:    Color(0xFFE8AABC),
    textMuted:        Color(0xFF905060),
    textDisabled:     Color(0xFF5A3040),
    divider:          Color(0xFF2A1520),
    shimmerBase:      Color(0xFF1C0C10),
    shimmerHighlight: Color(0xFF25121A),
    heroStop:         Color(0xFF100608),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  CHARCOAL  — warm slate grey
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme charcoal = RaddTheme(
    bg:               Color(0xFF0E0E0F),
    bgAlt:            Color(0xFF161617),
    surface:          Color(0xFF1A1A1C),
    surfaceHigh:      Color(0xFF222224),
    card:             Color(0xFF272729),
    cardBorder:       Color(0xFF333336),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x14FFFFFF),
    textPrimary:      Color(0xFFF5F5F6),
    textSecondary:    Color(0xFFBBBBBE),
    textMuted:        Color(0xFF707075),
    textDisabled:     Color(0xFF444448),
    divider:          Color(0xFF222224),
    shimmerBase:      Color(0xFF1A1A1C),
    shimmerHighlight: Color(0xFF222224),
    heroStop:         Color(0xFF0E0E0F),
  );
}
