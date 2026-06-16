// lib/core/theme/radd_theme.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  MASTER THEME TOKEN FILE
//  One place to define every UI color for any theme.
//
//  To add a new theme:   add a static const RaddTheme below.
//  To change any color:  edit it here — every screen updates automatically.
//  To use in a screen:   final t = RaddTheme.of(context);  then t.bg, t.card…
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class RaddTheme {
  // ── Background stack ─────────────────────────────────────────────────────
  /// Page / scaffold background
  final Color bg;
  /// Slightly elevated background (nav bar behind areas, alt sections)
  final Color bgAlt;
  /// Bottom sheets, modals, elevated sections
  final Color surface;
  /// Higher elevation surface (hover states, pressed cards)
  final Color surfaceHigh;
  /// Card background
  final Color card;
  /// Card stroke / outline
  final Color cardBorder;

  // ── Glass / blur overlays ─────────────────────────────────────────────────
  /// Low-opacity fill for glass panels
  final Color glass;
  /// Stronger glass fill (active glass panel)
  final Color glassHigh;
  /// Universal border / dividing line between glass panels
  final Color border;

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  // ── Lines ─────────────────────────────────────────────────────────────────
  final Color divider;

  // ── Shimmer / skeleton loaders ────────────────────────────────────────────
  final Color shimmerBase;
  final Color shimmerHighlight;

  // ── Hero poster gradient ───────────────────────────────────────────────────
  /// Bottom colour of the poster-to-bg gradient (top is always transparent)
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

  // ── Resolve from current Flutter theme ────────────────────────────────────
  static RaddTheme of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light) return light;
    // Distinguish AMOLED by scaffoldBackgroundColor == pure black
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    if (scaffoldBg == const Color(0xFF000000)) return amoled;
    return dark;
  }

  // ── Computed helpers ───────────────────────────────────────────────────────
  LinearGradient get heroGradient => LinearGradient(
    colors: [Colors.transparent, heroStop],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0.3, 1.0],
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  DARK THEME  (default)
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme dark = RaddTheme(
    bg:               Color(0xFF08080E),
    bgAlt:            Color(0xFF0D0D1A),
    surface:          Color(0xFF0E0E1C),
    surfaceHigh:      Color(0xFF161628),
    card:             Color(0xFF1A1A2E),
    cardBorder:       Color(0xFF252540),
    glass:            Color(0x0DFFFFFF),
    glassHigh:        Color(0x1AFFFFFF),
    border:           Color(0x14FFFFFF),
    textPrimary:      Color(0xFFF2F2FF),
    textSecondary:    Color(0xFFB0B0CC),
    textMuted:        Color(0xFF6A6A90),
    textDisabled:     Color(0xFF404060),
    divider:          Color(0xFF1E1E35),
    shimmerBase:      Color(0xFF0E0E1C),
    shimmerHighlight: Color(0xFF161628),
    heroStop:         Color(0xFF08080E),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  AMOLED THEME  (pure black — zero battery drain on OLED)
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
    textPrimary:      Color(0xFFF2F2FF),
    textSecondary:    Color(0xFFB0B0CC),
    textMuted:        Color(0xFF6A6A90),
    textDisabled:     Color(0xFF333355),
    divider:          Color(0xFF141414),
    shimmerBase:      Color(0xFF0A0A0A),
    shimmerHighlight: Color(0xFF111111),
    heroStop:         Color(0xFF000000),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ══════════════════════════════════════════════════════════════════════════
  static const RaddTheme light = RaddTheme(
    bg:               Color(0xFFF0F0F7),
    bgAlt:            Color(0xFFE8E8F2),
    surface:          Color(0xFFFFFFFF),
    surfaceHigh:      Color(0xFFF5F5FA),
    card:             Color(0xFFF5F5FA),
    cardBorder:       Color(0xFFE0E0EC),
    glass:            Color(0x0A000000),
    glassHigh:        Color(0x14000000),
    border:           Color(0xFFE0E0EC),
    textPrimary:      Color(0xFF0A0A1A),
    textSecondary:    Color(0xFF444466),
    textMuted:        Color(0xFF888899),
    textDisabled:     Color(0xFFBBBBCC),
    divider:          Color(0xFFE0E0F0),
    shimmerBase:      Color(0xFFE8E8F4),
    shimmerHighlight: Color(0xFFF5F5FA),
    heroStop:         Color(0xFFF0F0F7),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  ADD NEW THEMES HERE
  //  Example:
  //    static const RaddTheme midnight = RaddTheme(bg: Color(0xFF0A0010), ...)
  // ══════════════════════════════════════════════════════════════════════════
}
