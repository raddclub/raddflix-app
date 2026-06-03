import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../core/constants.dart';
import '../core/remote_config.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _ctrl = PageController();
  int _page = 0;
  List<_PageData> _pages = _kDefaultPages;

  // ── Hardcoded fallback pages ───────────────────────────────────────────────
  static const List<_PageData> _kDefaultPages = [
    _PageData(
      icon: '📶',
      gradient: [Color(0xFF22C55E), Color(0xFF16A34A)],
      title: 'Zero-Rated Streaming',
      body: 'Watch movies & shows on Jazz SIM without spending any data. RaddFlix traffic is completely free of charge.',
    ),
    _PageData(
      icon: '📱',
      gradient: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      title: 'Offline Catalog',
      body: 'The full movie catalog downloads to your phone. Browse, search and explore 7000+ titles without any internet.',
    ),
    _PageData(
      icon: '🎬',
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
      title: 'Pakistani Content',
      body: 'Urdu, Punjabi, Pakistani dramas and international hits. New titles added every week.',
    ),
    _PageData(
      icon: '⭐',
      gradient: [Color(0xFFE8002D), Color(0xFFB5001F)],
      title: 'Subscribe to Unlock',
      body: 'Start free. Upgrade to Basic, Standard or Premium to unlock HD quality and all content.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadLivePages();
  }

  /// Load live-configured onboarding pages from SharedPreferences (set by
  /// remote_config.dart from the Brand Studio admin panel). Falls back to
  /// [_kDefaultPages] if not set or on any parse error.
  Future<void> _loadLivePages() async {
    try {
      final raw = await RemoteConfig.getBrandOnboardingPages();
      if (raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isEmpty) return;
      final parsed = list.map((e) {
        final m = e as Map<String, dynamic>;
        final gradRaw = (m['gradient'] as List<dynamic>?) ?? [];
        final grad = gradRaw.map((c) {
          final hex = (c as String).replaceFirst('#', '');
          return Color(int.parse('FF$hex', radix: 16));
        }).toList();
        return _PageData(
          icon:     (m['icon'] as String?) ?? '🎬',
          gradient: grad.length >= 2 ? [grad[0], grad[1]] : [const Color(0xFFE8002D), const Color(0xFFB5001F)],
          title:    (m['title'] as String?) ?? '',
          body:     (m['body'] as String?) ?? '',
        );
      }).toList();
      if (mounted) setState(() => _pages = parsed);
    } catch (_) {
      // Silent fallback — hardcoded pages remain
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingSeenKey, true);
    if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                colors: [
                  _pages[_page].gradient[0].withOpacity(0.15),
                  t.bg,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Skip
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                      onPressed: _finish,
                      child: Text('Skip',
                          style: TextStyle(color: t.textMuted, fontSize: 14)),
                    ),
                  ),
                ),
                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _ctrl,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _OnboardPage(data: _pages[i], isActive: i == _page),
                  ),
                ),
                // Indicator
                SmoothPageIndicator(
                  controller: _ctrl,
                  count: _pages.length,
                  effect: ExpandingDotsEffect(
                    dotWidth: 8,
                    dotHeight: 8,
                    expansionFactor: 3,
                    spacing: 6,
                    activeDotColor: AppColors.primary,
                    dotColor: t.textMuted.withOpacity(0.3),
                  ),
                ),
                const SizedBox(height: 32),
                // Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: _buildButton(isLast),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(bool isLast) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_pages[_page].gradient[0], _pages[_page].gradient[1]],
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: _pages[_page].gradient[0].withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            if (isLast) {
              _finish();
            } else {
              _ctrl.nextPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
              );
            }
          },
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: Text(
              isLast ? 'Get Started' : 'Next →',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final _PageData data;
  final bool isActive;
  const _OnboardPage({required this.data, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  data.gradient[0].withOpacity(0.2),
                  data.gradient[1].withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: data.gradient[0].withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(data.icon, style: TextStyle(fontSize: 56)),
            ),
          )
              .animate(target: isActive ? 1.0 : 0.0)
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
                  duration: 400.ms, curve: AppCurves.enter),
          SizedBox(height: 48),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          )
              .animate(target: isActive ? 1.0 : 0.0)
              .fadeIn(duration: 350.ms, delay: 100.ms)
              .slideY(begin: 0.3, end: 0, duration: 350.ms, curve: AppCurves.standard),
          SizedBox(height: 16),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 15,
              height: 1.65,
              letterSpacing: 0.1,
            ),
          )
              .animate(target: isActive ? 1.0 : 0.0)
              .fadeIn(duration: 350.ms, delay: 200.ms),
        ],
      ),
    );
  }
}

class _PageData {
  final String icon;
  final List<Color> gradient;
  final String title;
  final String body;
  const _PageData({required this.icon, required this.gradient, required this.title, required this.body});
}
