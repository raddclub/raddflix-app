import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants.dart';

class AppUpdateResult {
  final bool forceUpdate;
  final bool blocked;
  final String message;
  final String updateUrl;
  final String currentVersion;

  const AppUpdateResult({
    required this.forceUpdate,
    required this.blocked,
    required this.message,
    required this.updateUrl,
    required this.currentVersion,
  });

  static const AppUpdateResult empty = AppUpdateResult(
    forceUpdate: false, blocked: false, message: '', updateUrl: '', currentVersion: '',
  );
}

class AppUpdateService {
  static AppUpdateResult lastResult = AppUpdateResult.empty;

  static Future<AppUpdateResult> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final versionCode = int.tryParse(info.buildNumber) ?? 1;
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final res = await dio.post('/api/app/check', data: {
        'version_code': versionCode,
        'version_name': info.version,
        'platform': 'android',
      });
      final data = res.data as Map<String, dynamic>;
      lastResult = AppUpdateResult(
        forceUpdate: data['force_update'] == true,
        blocked: data['blocked'] == true,
        message: (data['message'] as String?) ?? '',
        updateUrl: (data['update_url'] as String?) ?? '',
        currentVersion: (data['current_version'] as String?) ?? '',
      );
    } catch (_) {
      lastResult = AppUpdateResult.empty;
    }
    return lastResult;
  }
}
