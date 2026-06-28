import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../app.dart' show pendingVideoUri, pendingVideoTitle, pendingSubtitleUri, appNavigatorKey;
import '../core/remote_config.dart';
import '../core/theme/brand_theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  RaddTheme get t => RaddTheme.of(context);

  late AnimationController _pulseCtrl;
  bool _started = false;
  Color _splashBg = AppColors.background;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    // Load brand splash color from SharedPreferences (set by main.dart RemoteConfig.fetch)
    _loadBrandSplashColor();
    // Start auth check after a short pause so the logo animation has time to play.
    // RemoteConfig was already fetched in main() — no duplicate network call here.
    Future.delayed(const Duration(milliseconds: 300), _start);
  }

  Future<void> _loadBrandSplashColor() async {
    try {
      final colorHex = await RemoteConfig.getBrandSplashColor(fallback: '');
      if (colorHex.isEmpty) return;
      final hex = colorHex.replaceFirst('#', '');
      final color = Color(int.parse('FF$hex', radix: 16));
      if (mounted) setState(() => _splashBg = color);
    } catch (_) {
      // Silent fallback — AppColors.background used
    }
  }

  Future<void> _start() async {
    // M-06: check mounted before any ref.read calls; _start() is called from
    // a post-frame callback that may fire after the widget is disposed.
    if (!mounted) return;
    // Reload brand theme (colors/font/radius) from prefs populated in main().
    // No network call needed — RemoteConfig.fetch() already ran in main.dart.
    ref.read(brandThemeProvider.notifier).reload();
    _loadBrandSplashColor();
    if (!mounted) return;
    // Trigger auth check — listener below routes to home or login.
    await ref.read(authProvider.notifier).checkAuth();
    // BUG-H05 fix: load subscription status immediately after auth so subscription
    // gates (show_detail, player) have current quota/plan data from the first frame.
    // Without this call, subscriptionProvider.status was always null on cold start
    // and all gates fell back to the stale authProvider cache.
    if (mounted) {
      final auth = ref.read(authProvider);
      if (auth.status == AuthStatus.authenticated &&
          auth.user != null && !auth.user!.isGuest) {
        ref.read(subscriptionProvider.notifier).loadStatus().ignore();
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    ref.listen<AuthState>(authProvider, (_, next) {
      if (!mounted || _started) return;
      if (next.status == AuthStatus.authenticated) {
        _started = true;
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
        // If app was opened via "Open with" intent, push player after home loads
        final uri = pendingVideoUri;
        if (uri != null && uri.isNotEmpty) {
          pendingVideoUri   = null;
          final String? resolvedTitle = pendingVideoTitle;
          pendingVideoTitle = null;
          final String? subtitlePath = pendingSubtitleUri;
          pendingSubtitleUri = null;
          Future.delayed(const Duration(milliseconds: 400), () {
            // H-02: widget may be disposed during the 400ms wait
            if (!mounted) return;
            // Prefer ContentResolver display name; fall back to fully-decoded URI segment.
            final String title = (resolvedTitle != null && resolvedTitle.isNotEmpty)
                ? resolvedTitle
                : Uri.decodeFull(Uri.parse(uri).pathSegments.isNotEmpty
                  ? Uri.parse(uri).pathSegments.last
                  : uri.split('/').last); // FIX-URI-01: pathSegments.last handles query params correctly
            // Normalise path: strip file:// prefix; content:// passed as-is for media_kit.
            final String localPath =
                uri.startsWith('file://') ? uri.substring(7) : uri;
            // Pop any stale player screen before pushing (cold-start edge case).
            appNavigatorKey.currentState
              ?..popUntil((route) => route.settings.name != '/player')
              ..pushNamed(
                '/player',
                arguments: {
                  'file_id': '',
                  'title': title,
                  'local_path': localPath,
                  'subtitle_path': subtitlePath,
                  'content_type': 'movie',
                },
              );
          });
        }
      } else if (next.status == AuthStatus.unauthenticated) {
        _started = true;
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    });

    return Scaffold(
      backgroundColor: _splashBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    _splashBg,
                  ],
                ),
              ),
            ),
          ),
          // Top-left accent glow
          Positioned(
            top: -80, left: -60,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withOpacity(0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          // Bottom-right complementary glow
          Positioned(
            bottom: -90, right: -50,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withOpacity(0.07),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                SizedBox(height: 8),
                Text(
                  AppConstants.tagline,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                )
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.3, end: 0, duration: 400.ms, curve: AppCurves.standard),
                const SizedBox(height: 80),
                const _ThreeDotsLoader()
                    .animate(delay: 500.ms)
                    .fadeIn(duration: 300.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFE8002D), Color(0xFF8B0000)],
            ),
            boxShadow: AppShadows.glow,
          ),
          child: const Center(
            child: Text(
              'R',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
          ),
        )
            .animate()
            .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1),
                duration: 500.ms, curve: AppCurves.enter)
            .fadeIn(duration: 300.ms),
        SizedBox(height: 20),
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              height: 1,
            ),
            children: [
              TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)),
              TextSpan(text: 'Flix', style: TextStyle(color: AppColors.primary)),
            ],
          ),
        )
            .animate(delay: 200.ms)
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.2, end: 0, duration: 400.ms, curve: AppCurves.standard),
      ],
    );
  }
}

// ── Three-dot branded loader ──────────────────────────────────────────────────
class _ThreeDotsLoader extends StatefulWidget {
  const _ThreeDotsLoader();
  @override
  State<_ThreeDotsLoader> createState() => _ThreeDotsLoaderState();
}

class _ThreeDotsLoaderState extends State<_ThreeDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
        final start = i / 4.0;
        final anim  = CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeInOut),
        );
        return AnimatedBuilder(
          animation: anim,
          builder: (_, __) => Container(
            width: 7, height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(
                  0.3 + 0.7 * (i % 2 == 0 ? anim.value : 1 - anim.value)),
            ),
          ),
        );
      })),
    );
  }
}
