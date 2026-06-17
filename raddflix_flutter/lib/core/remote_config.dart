import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'api/api_client.dart';
import 'debug/debug_logger.dart';

/// Remote config loader for RaddFlix.
///
/// Split into two separate operations so Jazz SIM users (no internet bundle)
/// never wait on startup:
///
///   loadCached()      — instant, reads SharedPreferences, no network.
///                       Always called in main() before runApp().
///   fetchBackground() — fires an Oracle HTTP call (short 4s timeout).
///                       Fire-and-forget: never blocks startup or UI.
///                       Silently no-ops when Oracle is unreachable.
///
/// Priority for loadCached():
///   1. SharedPreferences cache (written by last successful fetchBackground)
///   2. Hardcoded AppConstants.apiBaseUrl (built-in fallback, always valid)
class RemoteConfig {
  static const String _configUrl = 'http://92.4.95.252/api/config';
  static const String _prefsKey  = 'jm_remote_config';

  // ── Brand field keys ───────────────────────────────────────────────────────
  // Original 5
  static const String kBrandPrimaryColor    = 'brand_primary_color';
  static const String kBrandTagline         = 'brand_tagline';
  static const String kBrandLogoUrl         = 'brand_logo_url';
  static const String kBrandSplashColor     = 'brand_splash_color';
  static const String kBrandOnboardingPages = 'brand_onboarding_pages';
  // New 9 — full theme control
  static const String kBrandAccentColor     = 'brand_accent_color';
  static const String kBrandBackgroundColor = 'brand_background_color';
  static const String kBrandSurfaceColor    = 'brand_surface_color';
  static const String kBrandCardColor       = 'brand_card_color';
  static const String kBrandTextPrimaryColor = 'brand_text_primary_color';
  static const String kBrandAppName         = 'brand_app_name';
  static const String kBrandFont            = 'brand_font';
  static const String kBrandButtonRadius    = 'brand_button_radius';
  static const String kBrandStatusBarDark   = 'brand_status_bar_dark';

  static const List<String> _brandKeys = [
    kBrandPrimaryColor,
    kBrandTagline,
    kBrandLogoUrl,
    kBrandSplashColor,
    kBrandOnboardingPages,
    kBrandAccentColor,
    kBrandBackgroundColor,
    kBrandSurfaceColor,
    kBrandCardColor,
    kBrandTextPrimaryColor,
    kBrandAppName,
    kBrandFont,
    kBrandButtonRadius,
    kBrandStatusBarDark,
  ];

  /// Optional callback — set by BrandThemeNotifier to reload theme after fetch.
  static Future<void> Function()? onBrandConfigLoaded;

  /// Apply a config map to AppConstants + brand prefs.
  /// Shared by both loadCached() and fetchBackground().
  static Future<void> _applyData(
      Map<String, dynamic> data, SharedPreferences prefs) async {
    final url = (data['api_base_url'] as String?)?.trim();
    if (url != null && url.isNotEmpty) {
      AppConstants.apiBaseUrl = url;
      ApiClient.updateBaseUrl(url);
    }
    final deltaUrl = (data['jd_delta_url'] as String?)?.trim() ?? '';
    if (deltaUrl.isNotEmpty) AppConstants.jazzDriveDeltaUrl = deltaUrl;
    final supportWa = (data['support_whatsapp'] as String?)?.trim() ?? '';
    if (supportWa.isNotEmpty) AppConstants.supportWhatsApp = supportWa;
    for (final k in _brandKeys) {
      final v = (data[k] as String?)?.trim() ?? '';
      if (v.isNotEmpty) await prefs.setString(k, v);
    }
    await onBrandConfigLoaded?.call();
  }

  /// Load config instantly from SharedPreferences cache — no network call.
  ///
  /// Call this in main() before runApp(). Completes in < 10ms.
  /// Jazz SIM users with no internet bundle get their cached config
  /// (including jd_delta_url) immediately without any startup delay.
  static Future<void> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (cached != null) {
      try {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        await _applyData(data, prefs);
        return;
      } catch (e) {
        // L-07: log cache parse failures — JSON corruption causes silent fallback
        DebugLogger.logWarn('REMOTE_CONFIG', 'Cached config parse failed: $e');
      }
    }
    // No cache yet — use hardcoded fallback (first install, no internet yet)
    ApiClient.updateBaseUrl(AppConstants.apiBaseUrl);
  }

  /// Fetch fresh config from Oracle in the background — fire-and-forget.
  ///
  /// Use [unawaited(RemoteConfig.fetchBackground())] in main() after runApp().
  /// Uses a short 4s timeout so it fails fast on no-bundle Jazz SIM.
  /// On success: updates AppConstants + refreshes SharedPreferences cache.
  /// On failure: silently no-ops — cached values from loadCached() stay active.
  ///
  /// This is the ONLY place that makes a network call to Oracle for config.
  static Future<void> fetchBackground() async {
    try {
      final dio = Dio();
      final res = await dio.get<dynamic>(
        _configUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout:    const Duration(seconds: 4),
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String
            ? jsonDecode(res.data as String) as Map<String, dynamic>
            : res.data as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await _applyData(data, prefs);
        // Refresh cache for next app open
        await prefs.setString(_prefsKey, jsonEncode(data));
      }
    } catch (e) {
      // Oracle unreachable (no bundle, server down, etc.) — silently no-op.
      // L-07: log at WARN level so crash reports capture network failures.
      // loadCached() has already applied the last-known-good config.
      DebugLogger.logWarn('REMOTE_CONFIG', 'fetchBackground failed: $e');
    }
  }

  /// Legacy: loads cache then fires background fetch.
  /// Prefer calling loadCached() + unawaited(fetchBackground()) directly in main().
  static Future<void> fetch() async {
    await loadCached();
    fetchBackground().ignore();
  }

  // ── Convenience getters ─────────────────────────────────────────────────────

  static Future<String> getBrandPrimaryColor({String fallback = '#E8002D'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandPrimaryColor) ?? fallback;
  }

  static Future<String> getBrandAccentColor({String fallback = '#FF5C5C'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandAccentColor) ?? fallback;
  }

  static Future<String> getBrandSplashColor({String fallback = '#08080E'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandSplashColor) ?? fallback;
  }

  static Future<String> getBrandBackgroundColor({String fallback = '#08080E'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandBackgroundColor) ?? fallback;
  }

  static Future<String> getBrandSurfaceColor({String fallback = '#0E0E1C'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandSurfaceColor) ?? fallback;
  }

  static Future<String> getBrandCardColor({String fallback = '#1A1A2E'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandCardColor) ?? fallback;
  }

  static Future<String> getBrandTextPrimaryColor({String fallback = '#F2F2FF'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandTextPrimaryColor) ?? fallback;
  }

  static Future<String> getBrandTagline({String fallback = 'Zero-rated Pakistani streaming'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandTagline) ?? fallback;
  }

  static Future<String> getBrandAppName({String fallback = 'RaddFlix'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandAppName) ?? fallback;
  }

  static Future<String> getBrandFont({String fallback = 'inter'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandFont) ?? fallback;
  }

  static Future<double> getBrandButtonRadius({double fallback = 14}) async {
    final p = await SharedPreferences.getInstance();
    return double.tryParse(p.getString(kBrandButtonRadius) ?? '') ?? fallback;
  }

  static Future<String> getBrandLogoUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandLogoUrl) ?? '';
  }

  static Future<String> getBrandOnboardingPages() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandOnboardingPages) ?? '';
  }
}
