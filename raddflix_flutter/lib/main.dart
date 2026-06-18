import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart' show RaddFlixApp, pendingVideoUri, pendingVideoTitle, pendingSubtitleUri, appNavigatorKey;
import 'core/remote_config.dart';
import 'core/services/app_update_service.dart';
import 'core/services/jazzdrive_service.dart';
import 'core/services/poster_service.dart';
import 'core/api/history_api.dart';
import 'core/db/local_db.dart';
import 'core/db/sync_service.dart';
import 'core/debug/debug_logger.dart';
import 'core/security/app_guard.dart';
import 'core/services/connectivity_sync_service.dart';
import 'core/services/usage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise logger immediately — before any other code so cold-start crashes
  // are written to the log file, not just the in-memory buffer.
  await DebugLogger.init();
  DebugLogger.log('MAIN', 'App start ${DateTime.now().toString().substring(0, 19)}');

  // L-15: Capture Flutter framework errors in release mode — these are normally
  // printed to console but lost in production. We route them through DebugLogger
  // so they are written to the local crash log file for post-mortem analysis.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // still shows red-screen in debug
    DebugLogger.logError(
      'FLUTTER',
      details.exceptionAsString(),
      details.exception,
    );
  };

  // Catch ALL uncaught Dart async errors at the platform level — this is the
  // last safety net before a silent crash. Captures errors in async callbacks,
  // plugin handlers, and isolates that Flutter's onError misses.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DebugLogger.logCrash('PLATFORM', error, stack);
    return true; // prevent default crash handler
  };

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

  // Run all independent startup tasks in parallel — reduces cold-start time
  // by avoiding sequential awaits on operations that have no dependencies.
  await Future.wait([
    // Load config from SharedPreferences cache — instant, no network call.
    // Jazz SIM users with no internet bundle see the app in < 10ms.
    // Oracle refresh fires in background AFTER runApp (see below).
    RemoteConfig.loadCached(),
    // Create poster storage directories on disk.
    PosterService.init(),
    // Evict expired JazzDrive CDN tokens from SQLite.
    LocalDb.cleanExpiredStreamCache(),
  ]);

  // Load warm JazzDrive token cache into memory (depends on SQLite being ready).
  await JazzDriveService.loadCacheFromDb();

  // Auto-resync: if the v17 schema migration just ran (filename column added to
  // episodes), reset sync timestamps so the next sync fetches full data.
  if (await LocalDb.consumeForceResyncFlag()) {
    await LocalDb.setLastSyncTimestamp(0);
    await LocalDb.setLastSyncVersion(0);
    unawaited(SyncService.sync());
    DebugLogger.log('MAIN', 'Schema v17 migration detected — forced catalog re-sync triggered');
  }

  // Background tasks — fire-and-forget, never block app launch.
  // Oracle config refresh: runs after the UI is up. On Jazz SIM with no bundle
  // this fails in ~4s and silently no-ops. loadCached() above already applied
  // the last-known-good config so nothing the user sees depends on this call.
  unawaited(RemoteConfig.fetchBackground());
  unawaited(JazzDriveService.warmTopFreeItems(8));   // pre-warm top free content CDN links
  unawaited(AppUpdateService.check());               // populate _ForceUpdateGuard result
  HistoryApi.flushUnsynced().ignore();               // push offline watch positions
  UsageService.flushPending().ignore();              // push pending data-usage bytes

  // Check for initial video URI + display name from "Open with" intent (cold start)
  try {
    const _ch = MethodChannel('com.raddflix.app/intent');
    pendingVideoUri    = await _ch.invokeMethod<String>('getPendingVideoUri');
    pendingVideoTitle  = await _ch.invokeMethod<String>('getPendingVideoTitle');
    pendingSubtitleUri = await _ch.invokeMethod<String?>('getPendingSubtitleUri');
  } catch (_) {}

  runApp(
    const ProviderScope(
      child: RaddFlixApp(),
    ),
  );

  // Start connectivity-triggered sync: flushes unsynced history + usage
  // immediately when device reconnects (not just on next cold start).
  ConnectivitySyncService.start();

  // Listen for new "Open with" intents while app is running (warm start).
  // MainActivity sends a Map {"uri": String, "title": String} so we get the
  // proper display name resolved by ContentResolver — not just the URI segment.
  const MethodChannel('com.raddflix.app/intent')
      .setMethodCallHandler((call) async {
    if (call.method == 'onVideoUri') {
      DebugLogger.log('MAIN', 'onVideoUri warm-start intent received');
      final args = call.arguments;
      final String? uri = args is Map ? args['uri'] as String? : args as String?;
      if (uri == null || uri.isEmpty) return;

      // Resolve title: prefer ContentResolver name, fall back to URI last segment (fully decoded)
      final String rawTitle = args is Map ? (args['title'] as String? ?? '') : '';
      final String title = rawTitle.isNotEmpty
          ? rawTitle
          : Uri.decodeFull(uri.split('/').last);

      // Normalise path: strip file:// prefix; pass content:// URIs as-is (media_kit handles them)
      final String localPath =
          uri.startsWith('file://') ? uri.replaceFirst('file://', '') : uri;

      final nav = appNavigatorKey.currentState;
      if (nav == null) return;

      // M-25: Only push player when the navigator is ready and app is past auth
      // screens. Pushing onto login/splash would show a player with no auth context.
      // canPop() is false on login/splash (only route on stack) — use that as guard.
      final topRoute = ModalRoute.of(nav.context)?.settings.name ?? '';
      final safeRoutes = ['/home', '/player', '/downloads', '/profile', '/search'];
      if (!safeRoutes.any((r) => topRoute.startsWith(r))) return;
      // Use popUntil to discard any stacked player screens before pushing a new one,
      // so repeated "Open with" taps don't accumulate player screens.
      nav.popUntil((route) => route.settings.name != '/player');
      // subtitle resolved by native (null if no sidecar found)
      final String? subtitlePath =
          args is Map ? (args['subtitle'] as String?) : null;

      nav.pushNamed(
        '/player',
        arguments: {
          'file_id': '',
          'title': title,
          'local_path': localPath,
          'subtitle_path': subtitlePath,
          'content_type': 'movie',
        },
      );
    }
  });
}
