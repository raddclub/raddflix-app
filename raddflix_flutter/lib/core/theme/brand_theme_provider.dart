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
    primary:         Color(0xFFC41E3A),
    accent:          Color(0xFFE8384F),
    darkBackground:  Color(0xFF0D0D0F),
    darkSurface:     Color(0xFF161618),
    darkCard:        Color(0xFF242428),
    darkTextPrimary: Color(0xFFF8F8FA),
    splashColor:     Color(0xFF0D0D0F),
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
      primary:         _hex(p.getString(RemoteConfig.kBrandPrimaryColor),    const Color(0xFFC41E3A)),
      accent:          _hex(p.getString(RemoteConfig.kBrandAccentColor),     const Color(0xFFE8384F)),
      darkBackground:  _hex(p.getString(RemoteConfig.kBrandBackgroundColor), const Color(0xFF0D0D0F)),
      darkSurface:     _hex(p.getString(RemoteConfig.kBrandSurfaceColor),    const Color(0xFF161618)),
      darkCard:        _hex(p.getString(RemoteConfig.kBrandCardColor),       const Color(0xFF242428)),
      darkTextPrimary: _hex(p.getString(RemoteConfig.kBrandTextPrimaryColor),const Color(0xFFF8F8FA)),
      splashColor:     _hex(p.getString(RemoteConfig.kBrandSplashColor),     const Color(0xFF0D0D0F)),
      appName:      p.getString(RemoteConfig.kBrandAppName)     ?? 'RaddFlix',
      fontFamily:   p.getString(RemoteConfig.kBrandFont)        ?? 'inter',
      buttonRadius: double.tryParse(p.getString(RemoteConfig.kBrandButtonRadius) ?? '14') ?? 14,
    );
  }
}

final brandThemeProvider = StateNotifierProvider<BrandThemeNotifier, BrandThemeState>(
  (ref) => BrandThemeNotifier(),
);
