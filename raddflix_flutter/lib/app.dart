import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'core/design/app_icons.dart';
import 'models/catalog_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/constants.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/brand_theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/search_screen.dart';
import 'screens/show_detail_screen.dart';
import 'screens/vault_lock_screen.dart';
import 'screens/player_settings_screen.dart';
import 'screens/player/layout_designer_screen.dart';
import 'screens/pin_lock_screen.dart'; // Phase K3
import 'core/player/player_prefs.dart';
import 'screens/vault_screen.dart';
import 'screens/local_media_screen.dart';
import 'screens/local_folder_screen.dart';
import 'screens/quota_full_screen.dart';
import 'screens/plan_expired_screen.dart';
import 'screens/watchlist_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_switcher_screen.dart';
import 'screens/add_edit_profile_screen.dart';
import 'models/profile.dart';
import 'core/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/debug/debug_logger.dart';
import 'providers/app_navigation_provider.dart';

/// Logs every Navigator push / pop / replace to DebugLogger.
/// Registered in MaterialApp.navigatorObservers so ALL screens are covered.
class _RaddNavObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (kDebugMode) {
      final from = previousRoute?.settings.name ?? 'root';
      DebugLogger.logNav('PUSH', route.settings.name ?? '(anon)', 'from=$from');
    }
  }
  @override
  void didPop(Route route, Route? previousRoute) {
    if (kDebugMode) {
      final to = previousRoute?.settings.name ?? 'root';
      DebugLogger.logNav('POP', route.settings.name ?? '(anon)', 'to=$to');
    }
  }
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (kDebugMode) {
      DebugLogger.logNav('REPLACE',
          '${oldRoute?.settings.name ?? "?"} → ${newRoute?.settings.name ?? "?"}');
    }
  }
  @override
  void didRemove(Route route, Route? previousRoute) {
    if (kDebugMode) {
      DebugLogger.logNav('REMOVE', route.settings.name ?? '(anon)');
    }
  }
}

class RaddFlixApp extends ConsumerWidget {
  const RaddFlixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final brandState = ref.watch(brandThemeProvider);
    Animate.restartOnHotReload = true;
    return MaterialApp(
      navigatorKey: ref.watch(navigatorKeyProvider),
      navigatorObservers: [_RaddNavObserver()],
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: JazzThemeData.build(themeState.mode, brandState),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash:       (_) => const SplashScreen(),
        AppRoutes.login:        (_) => const LoginScreen(),
        AppRoutes.register:     (_) => const RegisterScreen(),
        AppRoutes.home:         (_) => const HomeScreen(),
        AppRoutes.subscription: (_) => const SubscriptionScreen(),
        AppRoutes.profile:      (_) => const ProfileScreen(),
        AppRoutes.downloads:    (_) => const DownloadsScreen(),
        AppRoutes.search:       (_) => const SearchScreen(),
        AppRoutes.vault:         (_) => const VaultScreen(),
        // BUG-H01 fix: extract quota args from route settings so the screen
        // can display real numbers (used GB, limit, plan name, reset date).
        // Player pushes: {used_gb, limit_gb, plan_name, resets_at} as arguments.
        AppRoutes.quotaFull: (s) {
          final a = (ModalRoute.of(s)?.settings.arguments as Map<String, dynamic>?) ?? {};
          return QuotaFullScreen(
            usedGb:   (a['used_gb']   as num?)?.toDouble(),
            limitGb:  (a['limit_gb']  as num?)?.toDouble(),
            planName: a['plan_name']  as String?,
            resetsAt: a['resets_at']  as String?,
          );
        },
        AppRoutes.planExpired:   (_) => const PlanExpiredScreen(),
        AppRoutes.watchlist:     (_) => const WatchlistScreen(),
        AppRoutes.history:       (_) => const HistoryScreen(),
        AppRoutes.settings:      (_) => const SettingsScreen(),
        AppRoutes.localMedia:    (_) => const LocalMediaScreen(),
        AppRoutes.profileSwitcher: (_) => const ProfileSwitcherScreen(),
        AppRoutes.addProfile:      (_) => const AddEditProfileScreen(),
        '/player-settings':      (_) => const _PlayerSettingsLoader(),
        '/layout-designer':      (_) => const _LayoutDesignerLoader(),
        '/pin-lock':             (_) => PinLockScreen(),
        '/pin-setup':            (_) => const PinSetupScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.player) {
          // Guard: always produce a non-null map even if caller omitted arguments.
          final args = (settings.arguments as Map?)?.cast<String, dynamic>()
              ?? const <String, dynamic>{};
          // episodes may arrive as List<Map<String,Object>> when the caller used
          // an untyped map literal with int values (e.g. local_folder_screen).
          // Cast each element individually so the outer List is always typed.
          final rawEps = args['episodes'];
          // M-24: guard against wrong-type args['episodes'] — use 'is' check
          // instead of bare 'as List' to avoid a TypeError if caller passes wrong type.
          final episodes = (rawEps is List)
              ? rawEps.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : null;
          return PageRouteBuilder(
            // BUG-FREE-PLAY-01 fix: PageRouteBuilder does NOT forward `settings`
            // unless explicitly passed. PlayerScreen reads is_free (and other
            // flags) via `ModalRoute.of(context)?.settings.arguments` at runtime
            // (not just from the typed constructor params above), so omitting
            // `settings: settings` here silently dropped 'is_free' on every
            // online play — free content was wrongly treated as paid and sent
            // to the subscription paywall. Downloaded/local playback never hit
            // this path (it bypasses the route-args gate via localPath), which
            // is why the bug only showed up for online streaming, not downloads.
            settings: settings,
            pageBuilder: (_, __, ___) => PlayerScreen(
              fileId: args['file_id'] as String? ?? '',
              title: args['title'] as String? ?? '',
              localPath: args['local_path'] as String?,
              subtitlePath: args['subtitle_path'] as String?,
              episodes: episodes,
              episodeIndex: args['episode_index'] as int? ?? 0,
              contentType: args['content_type'] as String? ?? 'series',
              // G1: passed as typed constructor params instead of PlayerScreen
              // re-reading ModalRoute.of(context)?.settings.arguments at
              // runtime — see BUG-FREE-PLAY-01 and the comment on
              // PlayerScreen.isFree/streamUrl/posterUrl.
              isFree: args['is_free'] == true || args['is_free'] == 1,
              streamUrl: args['stream_url'] as String?,
              posterUrl: (args['poster_url'] as String?) ?? (args['poster'] as String?),
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: AppDurations.normal,
          );
        }
        if (settings.name == AppRoutes.showDetail) {
          final item = settings.arguments;
          return PageRouteBuilder(
            pageBuilder: (_, __, ___) => ShowDetailScreen(item: item as CatalogItem),
            // Phase 42: pure FadeTransition lets Hero poster morph animate freely.
            // SlideTransition was removed — it conflicts with Hero's flight animation.
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 350),
          );
        }
        if (settings.name == AppRoutes.editProfile) {
          final profile = settings.arguments as Profile?;
          return MaterialPageRoute(
            builder: (_) => AddEditProfileScreen(existing: profile),
          );
        }
        if (settings.name == AppRoutes.vaultLock) {
          final args = settings.arguments as Map<String, dynamic>?;
          final isSetup = args?['setup'] == true;
          return MaterialPageRoute(
            builder: (_) => VaultLockScreen(isSetup: isSetup),
          );
        }
        return null;
      },
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: _ForceUpdateGuard(child: child!),
        );
      },
    );
  }
}


class _ForceUpdateGuard extends StatefulWidget {
  final Widget child;
  const _ForceUpdateGuard({required this.child});
  @override
  State<_ForceUpdateGuard> createState() => _ForceUpdateGuardState();
}

class _ForceUpdateGuardState extends State<_ForceUpdateGuard> {
  bool _checked = false;
  bool _blocked = false;
  AppUpdateResult _result = AppUpdateResult.empty;

  @override
  void initState() {
    super.initState();
    // L-11: check on first render AND again after 3 s. AppUpdateService.check()
    // runs as unawaited from main.dart and may finish after the first post-frame
    // callback, so a force-update response would be silently missed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _checkUpdate(); });
    });
  }

  void _checkUpdate() {
    if (_blocked) return; // already showing update screen
    _checked = true;
    final r = AppUpdateService.lastResult;
    if ((r.forceUpdate || r.blocked) && mounted) {
      setState(() { _blocked = true; _result = r; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocked) return _ForceUpdateScreen(result: _result);
    return widget.child;
  }
}

// L-11: all hardcoded AppColors.primary replaced with AppColors.primary so
// theme changes and dark mode propagate correctly.
class _ForceUpdateScreen extends StatelessWidget {
  final AppUpdateResult result;
  const _ForceUpdateScreen({required this.result});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(text: const TextSpan(
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1),
                  children: [
                    TextSpan(text: 'Radd', style: TextStyle(color: Colors.white)),
                    TextSpan(text: 'Flix', style: TextStyle(color: AppColors.primary)),
                  ],
                )),
                const SizedBox(height: 56),
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.08),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.25), width: 2),
                  ),
                  child: Icon(
                    result.blocked
                        ? AppIcons.block
                        : AppIcons.systemUpdate,
                    color: AppColors.primary,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  result.blocked ? 'Access Blocked' : 'Update Required',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  result.message.isNotEmpty
                      ? result.message
                      : result.blocked
                          ? 'This version of RaddFlix is not authorized. Please download the official app.'
                          : 'A required update is available. Please update RaddFlix to continue watching.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 15, height: 1.65),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 52),
                if (!result.blocked && result.updateUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.tryParse(result.updateUrl);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 24, offset: const Offset(0, 10),
                        )],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.downloadAction, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text('Update Now',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Text('Contact Support',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                const SizedBox(height: 24),
                if (result.currentVersion.isNotEmpty)
                  Text('Latest version: ${result.currentVersion}',
                      style: const TextStyle(color: AppColors.textDisabled, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ── Route loader: opens PlayerSettingsScreen with persisted prefs ─────────────
class _PlayerSettingsLoader extends StatelessWidget {
  const _PlayerSettingsLoader();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlayerPrefs>(
      future: PlayerPrefs.load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return PlayerSettingsScreen(
          prefs: snap.data!,
          onSave: (p) => p.save(),
        );
      },
    );
  }
}

// ── Route loader: opens LayoutDesignerScreen with persisted prefs ─────────────
class _LayoutDesignerLoader extends StatelessWidget {
  const _LayoutDesignerLoader();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlayerPrefs>(
      future: PlayerPrefs.load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return LayoutDesignerScreen(
          prefs: snap.data!,
          onSave: (p) => p.save(),
        );
      },
    );
  }
}
