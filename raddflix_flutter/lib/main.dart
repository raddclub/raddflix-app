import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart' show pendingVideoUri, pendingVideoTitle, pendingSubtitleUri, appNavigatorKey;
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
    // Fetch server config (brand theme, feature flags, API URL override).
    // SplashScreen reads from cached prefs — no second network call needed.
    RemoteConfig.fetch(),
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

      // Only push player when the navigator is ready and app is past auth screens.
      // Pushing onto login/splash would show a player with no auth context.
      final currentRoute = nav.widget.pages.isNotEmpty
          ? null
          : ModalRoute.of(nav.context)?.settings.name;
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
