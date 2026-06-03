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

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
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
    // Reload brand theme (colors/font/radius) from prefs populated in main().
    // No network call needed — RemoteConfig.fetch() already ran in main.dart.
    ref.read(brandThemeProvider.notifier).reload();
    _loadBrandSplashColor();
    if (!mounted) return;
    // Trigger auth check — listener below routes to home or login.
    await ref.read(authProvider.notifier).checkAuth();
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
            // Prefer ContentResolver display name; fall back to fully-decoded URI segment.
            final String title = (resolvedTitle != null && resolvedTitle.isNotEmpty)
                ? resolvedTitle
                : Uri.decodeFull(uri.split('/').last);
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
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary.withOpacity(0.8)),
                    strokeCap: StrokeCap.round,
                  ),
                )
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
