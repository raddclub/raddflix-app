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
///   - api_base_url     → AppConstants.apiBaseUrl
///   - jd_delta_url     → AppConstants.jazzDriveDeltaUrl (zero-rating delta URL)
///
/// To change the server URL: update the /api/config route in radd-hub/hub/routes/api.py
/// No APK rebuild needed — Flutter reads this on every startup.
class RemoteConfig {
  static const String _configUrl = 'http://92.4.95.252/api/config';
  static const String _prefsKey  = 'jm_remote_config';

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
        return;
      } catch (_) {}
    }

    // 3. Use hardcoded fallback (app always works even if server is unreachable)
    ApiClient.updateBaseUrl(AppConstants.apiBaseUrl);
  }
}
