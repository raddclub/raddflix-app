import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/remote_config.dart';
import 'core/services/app_update_service.dart';
import 'core/services/jazzdrive_service.dart';
import 'core/services/poster_service.dart';
import 'core/api/history_api.dart';
import 'core/db/local_db.dart';
import 'core/security/app_guard.dart';
import 'core/services/connectivity_sync_service.dart';
import 'core/services/usage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait (player screen overrides to landscape when needed)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize media_kit video engine
  MediaKit.ensureInitialized();

  // Security shield — must run before any network or DB calls.
  // If tampered (cracked APK / Frida detected), sets AppGuard.isTampered = true.
  // ApiClient silently returns fake empty data when tampered.
  await AppGuard.initialize();

  // Fetch server URL from Oracle server config — no APK rebuild needed when server changes.
  // Falls back to hardcoded AppConstants.apiBaseUrl if network/parse fails.
  await RemoteConfig.fetch();
  // Check for forced app updates / blocked APK on every cold start
  await AppUpdateService.check();

  // Boot zero-rated services
  await PosterService.init();
  await JazzDriveService.loadCacheFromDb();
  await LocalDb.cleanExpiredStreamCache();
  // Offline-first: push any positions saved while offline + pending usage bytes
  HistoryApi.flushUnsynced().ignore();
  UsageService.flushPending().ignore();

  // Check for initial video URI from "Open with" intent (cold start)
  try {
    const _ch = MethodChannel('com.raddflix.app/intent');
    pendingVideoUri = await _ch.invokeMethod<String>('getPendingVideoUri');
  } catch (_) {}

  runApp(
    const ProviderScope(
      child: RaddFlixApp(),
    ),
  );

  // Start connectivity-triggered sync: flushes unsynced history + usage
  // immediately when device reconnects (not just on next cold start).
  ConnectivitySyncService.start();

  // Listen for new "Open with" intents while app is running (warm start)
  const MethodChannel('com.raddflix.app/intent')
      .setMethodCallHandler((call) async {
    if (call.method == 'onVideoUri') {
      final uri = call.arguments as String?;
      if (uri != null && uri.isNotEmpty) {
        appNavigatorKey.currentState?.pushNamed(
          '/player',
          arguments: {
            'file_id': '',
            'title': uri.split('/').last.replaceAll(RegExp(r'%20'), ' '),
            'local_path': uri.startsWith('file://') ? uri.replaceFirst('file://', '') : uri,
          },
        );
      }
    }
  });
}
