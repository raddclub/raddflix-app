import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../remote_config.dart';

// ── Brand Theme State ─────────────────────────────────────────────────────────
class BrandThemeState {
  final Color primary;
  final Color accent;
  final Color darkBackground;
  final Color darkSurface;
  final Color darkCard;
  final Color darkTextPrimary;
  final Color splashColor;
  final String appName;
  final String fontFamily;
  final double buttonRadius;

  const BrandThemeState({
    required this.primary,
    required this.accent,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkCard,
    required this.darkTextPrimary,
    required this.splashColor,
    required this.appName,
    required this.fontFamily,
    required this.buttonRadius,
  });

  static const BrandThemeState defaults = BrandThemeState(
    primary:         Color(0xFFD4784A),
    accent:          Color(0xFFE8A070),
    darkBackground:  Color(0xFF130F0C),
    darkSurface:     Color(0xFF211A15),
    darkCard:        Color(0xFF352A1F),
    darkTextPrimary: Color(0xFFF5EFE6),
    splashColor:     Color(0xFF130F0C),
    appName:         'RaddFlix',
    fontFamily:      'inter',
    buttonRadius:    14,
  );

  LinearGradient get primaryGradient => LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Color get primaryGlow => primary.withOpacity(0.30);
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class BrandThemeNotifier extends StateNotifier<BrandThemeState> {
  BrandThemeNotifier() : super(BrandThemeState.defaults) {
    reload();
  }

  static Color _hex(String? raw, Color fallback) {
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final h = raw.replaceFirst('#', '');
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
      if (h.length == 8) return Color(int.parse(h, radix: 16));
    } catch (_) {}
    return fallback;
  }

  Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    state = BrandThemeState(
      primary:         _hex(p.getString(RemoteConfig.kBrandPrimaryColor),    const Color(0xFFD4784A)),
      accent:          _hex(p.getString(RemoteConfig.kBrandAccentColor),     const Color(0xFFE8A070)),
      darkBackground:  _hex(p.getString(RemoteConfig.kBrandBackgroundColor), const Color(0xFF130F0C)),
      darkSurface:     _hex(p.getString(RemoteConfig.kBrandSurfaceColor),    const Color(0xFF211A15)),
      darkCard:        _hex(p.getString(RemoteConfig.kBrandCardColor),       const Color(0xFF352A1F)),
      darkTextPrimary: _hex(p.getString(RemoteConfig.kBrandTextPrimaryColor),const Color(0xFFF5EFE6)),
      splashColor:     _hex(p.getString(RemoteConfig.kBrandSplashColor),     const Color(0xFF130F0C)),
      appName:      p.getString(RemoteConfig.kBrandAppName)     ?? 'RaddFlix',
      fontFamily:   p.getString(RemoteConfig.kBrandFont)        ?? 'inter',
      buttonRadius: double.tryParse(p.getString(RemoteConfig.kBrandButtonRadius) ?? '14') ?? 14,
    );
  }
}

final brandThemeProvider = StateNotifierProvider<BrandThemeNotifier, BrandThemeState>(
  (ref) => BrandThemeNotifier(),
);
