import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'api/api_client.dart';

/// Fetches server config from the Oracle server itself.
/// No GitHub dependency — works even when repo is private.
///
/// Priority:
///   1. Oracle server   → http://92.4.95.252/api/config   (primary)
///   2. Last cached config in SharedPreferences
///   3. Hardcoded AppConstants.apiBaseUrl (always works as final fallback)
///
/// Fields read from /api/config:
///   - api_base_url          → AppConstants.apiBaseUrl
///   - jd_delta_url          → AppConstants.jazzDriveDeltaUrl (zero-rating delta URL)
///   - brand_primary_color   → cached to SharedPreferences key 'brand_primary_color'
///   - brand_tagline         → cached to SharedPreferences key 'brand_tagline'
///   - brand_logo_url        → cached to SharedPreferences key 'brand_logo_url'
///   - brand_splash_color    → cached to SharedPreferences key 'brand_splash_color'
///   - brand_onboarding_pages → cached to SharedPreferences key 'brand_onboarding_pages'
///
/// To change the server URL: update the /api/config route in radd-hub/hub/routes/api.py
/// No APK rebuild needed — Flutter reads this on every startup.
class RemoteConfig {
  static const String _configUrl = 'http://92.4.95.252/api/config';
  static const String _prefsKey  = 'jm_remote_config';

  // Brand field keys (stored individually for easy access)
  static const String kBrandPrimaryColor    = 'brand_primary_color';
  static const String kBrandTagline         = 'brand_tagline';
  static const String kBrandLogoUrl         = 'brand_logo_url';
  static const String kBrandSplashColor     = 'brand_splash_color';
  static const String kBrandOnboardingPages = 'brand_onboarding_pages';

  static const List<String> _brandKeys = [
    kBrandPrimaryColor,
    kBrandTagline,
    kBrandLogoUrl,
    kBrandSplashColor,
    kBrandOnboardingPages,
  ];

  static Future<void> fetch() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try fetching fresh from Oracle server
    try {
      final dio = Dio();
      final res = await dio.get<dynamic>(
        _configUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout:    const Duration(seconds: 8),
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String
            ? jsonDecode(res.data as String) as Map<String, dynamic>
            : res.data as Map<String, dynamic>;
        final url = (data['api_base_url'] as String?)?.trim();
        if (url != null && url.isNotEmpty) {
          AppConstants.apiBaseUrl = url;
          ApiClient.updateBaseUrl(url);
        }
        // Read jd_delta_url — enables zero-rated catalog sync on Jazz SIM
        final deltaUrl = (data['jd_delta_url'] as String?)?.trim() ?? '';
        if (deltaUrl.isNotEmpty) {
          AppConstants.jazzDriveDeltaUrl = deltaUrl;
        }
        // Read support_whatsapp — admin can change without APK rebuild
        final supportWa = (data['support_whatsapp'] as String?)?.trim() ?? '';
        if (supportWa.isNotEmpty) {
          AppConstants.supportWhatsApp = supportWa;
        }
        // Read and cache all brand_ fields from Brand Studio admin panel
        for (final k in _brandKeys) {
          final v = (data[k] as String?)?.trim() ?? '';
          if (v.isNotEmpty) {
            await prefs.setString(k, v);
          }
        }
        // Cache full config for offline restarts
        await prefs.setString(_prefsKey, jsonEncode(data));
        return;
      }
    } catch (_) {}

    // 2. Fall back to last-cached config (survives offline restarts)
    final cached = prefs.getString(_prefsKey);
    if (cached != null) {
      try {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        final url = (data['api_base_url'] as String?)?.trim();
        if (url != null && url.isNotEmpty) {
          AppConstants.apiBaseUrl = url;
          ApiClient.updateBaseUrl(url);
        }
        final deltaUrl = (data['jd_delta_url'] as String?)?.trim() ?? '';
        if (deltaUrl.isNotEmpty) {
          AppConstants.jazzDriveDeltaUrl = deltaUrl;
        }
        final supportWa = (data['support_whatsapp'] as String?)?.trim() ?? '';
        if (supportWa.isNotEmpty) {
          AppConstants.supportWhatsApp = supportWa;
        }
        // Restore brand fields from cached config
        for (final k in _brandKeys) {
          final v = (data[k] as String?)?.trim() ?? '';
          if (v.isNotEmpty) {
            await prefs.setString(k, v);
          }
        }
        return;
      } catch (_) {}
    }

    // 3. Use hardcoded fallback (app always works even if server is unreachable)
    ApiClient.updateBaseUrl(AppConstants.apiBaseUrl);
  }

  // ── Convenience getters ────────────────────────────────────────────────────

  static Future<String> getBrandPrimaryColor({String fallback = '#E8002D'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandPrimaryColor) ?? fallback;
  }

  static Future<String> getBrandSplashColor({String fallback = '#0a0c11'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandSplashColor) ?? fallback;
  }

  static Future<String> getBrandTagline({String fallback = 'Zero-rated Pakistani streaming'}) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandTagline) ?? fallback;
  }

  static Future<String> getBrandLogoUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandLogoUrl) ?? '';
  }

  /// Returns the onboarding pages JSON string, or empty string if not set.
  /// Parse with jsonDecode to get a List of page maps.
  static Future<String> getBrandOnboardingPages() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kBrandOnboardingPages) ?? '';
  }
}
