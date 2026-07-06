import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/theme/radd_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../models/catalog_item.dart';
import '../widgets/content_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/notification_banner.dart';
import '../core/services/notification_service.dart';
import '../widgets/simosa_card.dart';
import '../core/debug/debug_logger.dart';
import '../widgets/resume_fab.dart';
import '../core/utils/anim_config.dart';
import '../widgets/offline_banner.dart';
import 'package:animations/animations.dart';
import 'show_detail_screen.dart';
import '../core/api/api_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  RaddTheme get t => RaddTheme.of(context);

  int _navIndex = 0;
  String _selectedCategory = 'All';
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;
  Timer? _notifTimer;
  static const _categories = ['All', 'Movies', 'Shows', 'Dramas', 'Urdu', 'Punjabi', 'English'];

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('HomeScreen', 'initState');
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      final now = _scroll.offset > 50;
      if (now != _scrolled) setState(() => _scrolled = now);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(catalogProvider.notifier).initialize();
      NotificationService.instance.fetch();
      _checkForUpdates();
    });
    _notifTimer = Timer.periodic(const Duration(minutes: 5),
        (_) => NotificationService.instance.fetch());
  }

  @override
  void dispose() {
    DebugLogger.logLifecycle('HomeScreen', 'dispose');
    WidgetsBinding.instance.removeObserver(this);
    _notifTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _notifTimer?.cancel();
      _notifTimer = null;
    } else if (state == AppLifecycleState.resumed && _notifTimer == null) {
      _notifTimer = Timer.periodic(const Duration(minutes: 5),
          (_) => NotificationService.instance.fetch());
    }
  }

  /// Puts the most recent Continue Watching item first so users can resume immediately.
  List<CatalogItem> _heroItems(CatalogState catalog) {
    final base = (catalog.movies.isNotEmpty ? catalog.movies : catalog.shows).take(5).toList();
    if (catalog.recentlyWatched.isEmpty) return base;
    final resume  = catalog.recentlyWatched.first;
    final deduped = base.where((i) => i.id != resume.id).take(4).toList();
    return [resume, ...deduped];
  }

  /// Fetches /api/config and shows a non-dismissable update dialog when
  /// the installed build is older than min_version_code.
  Future<void> _checkForUpdates() async {
    try {
      final resp    = await ApiClient.instance.get('/api/config');
      final data    = resp.data as Map<String, dynamic>? ?? {};
      final minCode = (data['min_version_code'] as num?)?.toInt() ?? 0;
      if (minCode <= 0 || !mounted) return;
      final info      = await PackageInfo.fromPlatform();
      final buildCode = int.tryParse(info.buildNumber) ?? 0;
      if (buildCode >= minCode || !mounted) return;
      final updateUrl = (data['update_url'] as String?) ?? '';
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(updateUrl: updateUrl),
      );
    } catch (_) {
      // Offline or server error — skip silently; user is unaffected
    }
  }

  List<CatalogItem> _filtered(CatalogState s) {
    final all = [...s.movies, ...s.shows];
    switch (_selectedCategory) {
      case 'Movies':  return s.movies;
      case 'Shows':   return s.shows;
      case 'Dramas':  return all.where((i) => (i.genres ?? '').toLowerCase().contains('drama')).toList();
      case 'Urdu':    return all.where((i) => (i.language ?? '').toLowerCase().contains('urdu')).toList();
      case 'Punjabi': return all.where((i) => (i.language ?? '').toLowerCase().contains('punjabi')).toList();
      case 'English': return all.where((i) => (i.language ?? '').toLowerCase().contains('english')).toList();
      default:        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final catalog    = ref.watch(catalogProvider);
    final user       = ref.watch(authProvider).user;
    // Phase 43/44: tier-gated stagger + OpenContainer morph
    final animConfig = ref.watch(animConfigProvider);
    final canAnimate = animConfig.canStagger && animConfig.shouldAnimate(context);
    final canMorph   = animConfig.canMorph   && animConfig.shouldAnimate(context);

    return Scaffold(
      backgroundColor: null,
      extendBodyBehindAppBar: true,
      // Phase 47 ANIM-47-03: content renders behind frosted nav on Tier 2+
      extendBody: true,
      appBar: _buildAppBar(user),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: t.surface,
            onRefresh: () {
              HapticFeedback.lightImpact();
              return ref.read(catalogProvider.notifier).syncFromServer();
            },
            child: catalog.isEmpty && catalog.status == CatalogStatus.syncing
                ? _buildShimmer()
                : _buildContent(catalog, animConfig: animConfig, canAnimate: canAnimate, canMorph: canMorph),
          ),
        ),
      ]),
      floatingActionButton: const ResumeFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: RaddFlixBottomNav(
        currentIndex: _navIndex,
        onTap: (i) {
          setState(() => _navIndex = i);
          DebugLogger.logTap('Home', 'bottomNav tab=$i', i == 0 ? 'Home' : i == 1 ? 'Search' : i == 2 ? 'Library' : 'Profile');
          // M-01: pop to root before pushing so tapping the same icon repeatedly
          // doesn't build an unbounded back-stack (e.g. Profile → Profile → …).
          if (i == 1 || i == 2 || i == 3) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          if (i == 1) Navigator.of(context).pushNamed(AppRoutes.search);
          else if (i == 2) Navigator.of(context).pushNamed(AppRoutes.downloads);
          else if (i == 3) Navigator.of(context).pushNamed(AppRoutes.profile);
        },
      ),
    );
  }

  Color _userAvatarColor(dynamic user) {
    if (user == null) return AppColors.primary;
    final hex = ((user.avatarColor as String?) ?? '#8B002D').replaceAll('#', '');
    try { return Color(int.parse('FF$hex', radix: 16)); }
    catch (_) { return AppColors.primary; }
  }

  PreferredSizeWidget _buildAppBar(dynamic user) {
    return AppBar(
      backgroundColor: _scrolled ? t.surface.withOpacity(0.96) : Colors.transparent,
      elevation: 0,
      flexibleSpace: _scrolled
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [t.bg, Colors.transparent]),
              )),
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.8),
          children: [
            TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)),
            TextSpan(text: 'Flix', style: TextStyle(color: AppColors.primary)),
          ],
        ),
      ),
      actions: [
        const NotificationBell(),
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () { DebugLogger.logTap('Home', 'profileAvatar'); Navigator.of(context).pushNamed(AppRoutes.profile); },
              child: Stack(alignment: Alignment.center, children: [
                // Outer glow ring
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _userAvatarColor(user).withOpacity(0.35), width: 1.5),
                  ),
                ),
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_userAvatarColor(user), _userAvatarColor(user).withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(
                        color: _userAvatarColor(user).withOpacity(0.4),
                        blurRadius: 12, spreadRadius: 1)],
                  ),
                  child: Center(child: (user.avatarEmoji.isNotEmpty)
                      ? Text(user.avatarEmoji,
                          style: const TextStyle(fontSize: 18))
                      : Text(user.avatarInitial,
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 16))),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(CatalogState catalog, {required AnimConfig animConfig, required bool canAnimate, required bool canMorph}) {
    final filtered = _filtered(catalog);
    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Spacing for AppBar
        const SliverToBoxAdapter(child: SizedBox(height: 96)),

        // Personalized greeting row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Builder(builder: (_) {
              final u = ref.read(authProvider).user;
              final firstName = (u?.displayName?.isNotEmpty == true)
                  ? u!.displayName!.split(' ').first : null;
              final hour = DateTime.now().hour;
              final tod = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
              return RichText(text: TextSpan(children: [
                TextSpan(text: '$tod',
                    style: TextStyle(color: t.textMuted, fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (firstName != null) ...[
                  TextSpan(text: ', ',
                      style: TextStyle(color: t.textMuted, fontSize: 13)),
                  TextSpan(text: firstName,
                      style: TextStyle(color: t.textPrimary, fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
                TextSpan(text: ' 👋',
                    style: const TextStyle(fontSize: 13)),
              ]));
            }),
          ).animate().fadeIn(duration: 500.ms),
        ),

        // Sync banner
        if (catalog.status == CatalogStatus.syncing)
          SliverToBoxAdapter(
            child: Center(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 12)],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary))),
                  SizedBox(width: 8),
                  Text('Syncing catalog…', style: TextStyle(color: AppColors.primary,
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
                ]),
              ),
            ),
          ),

        // Hero spotlight (first 5 items)
        if (catalog.movies.isNotEmpty || catalog.shows.isNotEmpty)
          SliverToBoxAdapter(child: _HeroSpotlight(
            items: _heroItems(catalog),
          ).animate().fadeIn(duration: 500.ms)),

        // Category chips
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                // Phase 43: tier-gated chip stagger
                final chip = _CategoryChip(
                  label: _categories[i],
                  isSelected: _selectedCategory == _categories[i],
                  onTap: () { DebugLogger.logTap('Home', 'category ${_categories[i]}'); setState(() => _selectedCategory = _categories[i]); },
                );
                return RepaintBoundary(
                  child: canAnimate
                      // Phase 46 ANIM-46-05: shimmer runs once after slide-in (Tier 1+)
                      ? chip.animate(delay: animConfig.stagger(i)).fadeIn(duration: animConfig.normal)
                          .slideX(begin: 0.2, end: 0, duration: animConfig.normal, curve: AppCurves.standard)
                          .shimmer(duration: 500.ms, color: Colors.white24)
                      : chip,
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // SIMOSA daily MB reminder (Phase 9)
        const SliverToBoxAdapter(child: SimosaCard()),

        // Continue Watching (from history)
        if (catalog.recentlyWatched.isNotEmpty)
          SliverToBoxAdapter(child: _ContentSection(
            title: 'Continue Watching',
            items: catalog.recentlyWatched,
            showProgress: true,
            onRemove: (item) => ref.read(catalogProvider.notifier).removeFromContinueWatching(item),
          )),

        // New Episodes — shows with unread episodes (badge count > 0)
        if (catalog.shows.any((s) => (s.newEpisodeCount ?? 0) > 0))
          SliverToBoxAdapter(child: _ContentSection(
            title: 'New Episodes',
            titleIcon: AppIcons.newReleases,
            items: catalog.shows.where((s) => (s.newEpisodeCount ?? 0) > 0).toList(),
          ).animate().fadeIn(duration: 400.ms)),

        // Free to Watch
        if (catalog.freeContent.isNotEmpty)
          SliverToBoxAdapter(child: _ContentSection(
            title: 'Free to Watch',
            titleIcon: AppIcons.playCircle,
            items: catalog.freeContent,
          ).animate().fadeIn(duration: 400.ms)),

        // Ongoing Shows
        if (catalog.ongoingShows.isNotEmpty)
          SliverToBoxAdapter(child: _ContentSection(
            title: 'Ongoing Shows',
            titleIcon: AppIcons.liveTv,
            items: catalog.ongoingShows,
          ).animate().fadeIn(duration: 400.ms)),

        // Trending Now
        if (catalog.trending.isNotEmpty)
          SliverToBoxAdapter(child: _ContentSection(
            title: 'Trending Now',
            items: catalog.trending,
          ).animate().fadeIn(duration: 400.ms)),

        // Recommended for You — TMDB engine (BUG-A26 resolved)
        if (catalog.recommendations.isNotEmpty)
          SliverToBoxAdapter(child: _RecommendationsSection(
            recommendations: catalog.recommendations,
          ).animate().fadeIn(duration: 400.ms)),

        // Main content grid or rows
        if (_selectedCategory == 'All') ...[
          if (catalog.movies.isNotEmpty)
            SliverToBoxAdapter(child: _ContentSection(
              title: 'Movies',
              count: catalog.movies.length,
              items: catalog.movies,
            )),
          if (catalog.shows.isNotEmpty)
            SliverToBoxAdapter(child: _ContentSection(
              title: 'TV Shows & Dramas',
              count: catalog.shows.length,
              items: catalog.shows,
            )),
          // New Arrivals (highest db_version = most recently synced)
          if (catalog.newlyAdded.isNotEmpty)
            SliverToBoxAdapter(child: _ContentSection(
              title: 'New Arrivals',
              titleIcon: AppIcons.newReleases,
              items: catalog.newlyAdded,
            ).animate().fadeIn(duration: 400.ms)),

          if (catalog.movies.isEmpty && catalog.shows.isEmpty &&
              catalog.status != CatalogStatus.syncing)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(children: [
                  Icon(AppIcons.filmSlate,
                      color: t.textMuted.withOpacity(0.4), size: 64),
                  const SizedBox(height: 16),
                  Text('No content yet',
                      style: TextStyle(color: t.textPrimary, fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Pull down to sync the catalog',
                      style: TextStyle(color: t.textMuted, fontSize: 13)),
                ]),
              )),
        ] else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: filtered.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(children: [
                        Icon(AppIcons.search, color: t.textMuted, size: 48),
                        SizedBox(height: 12),
                        Text('No $_selectedCategory content yet',
                            style: TextStyle(color: t.textMuted)),
                      ]),
                    )))
                : SliverGrid(
                    delegate: SliverChildBuilderDelegate((_, i) =>
                        RepaintBoundary(
                          // Phase 44: Tier 2+ → OpenContainer morph (card expands to detail)
                          // Phase 43: Tier 1  → stagger; Tier 0 → raw widget
                          child: canMorph
                              ? OpenContainer<void>(
                                  closedColor: Colors.transparent,
                                  openColor: Colors.transparent,
                                  closedElevation: 0,
                                  openElevation: 0,
                                  transitionDuration: animConfig.slow,
                                  tappable: false,
                                  closedBuilder: (_, openFn) =>
                                      ContentCard(item: filtered[i], onTap: openFn),
                                  openBuilder: (_, __) =>
                                      ShowDetailScreen(item: filtered[i]),
                                )
                              : canAnimate
                                  ? ContentCard(item: filtered[i])
                                      .animate(delay: animConfig.stagger(i))
                                      .fadeIn(duration: animConfig.normal)
                                      .slideY(begin: 0.06, end: 0, duration: animConfig.normal,
                                          curve: AppCurves.standard)
                                  : ContentCard(item: filtered[i]),
                        ),
                        childCount: filtered.length),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, childAspectRatio: 2/3,
                        crossAxisSpacing: 10, mainAxisSpacing: 10),
                  ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        // Phase 47 ANIM-47-04: extra clearance so last card isn't hidden behind nav bar
        const SliverToBoxAdapter(child: SizedBox(height: 72)),
      ],
    );
  }

  Widget _buildShimmer() {
    // Local helper — inline shimmer section (title header + horizontal card row)
    Widget section() => Shimmer.fromColors(
      baseColor: t.surface, highlightColor: t.surfaceHigh,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(children: [
            Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: t.surfaceHigh,
                    borderRadius: BorderRadius.circular(2))),
            Container(height: 14, width: 130,
                decoration: BoxDecoration(color: t.surfaceHigh,
                    borderRadius: BorderRadius.circular(4))),
          ]),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (_, __) => Container(
              width: 126, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: t.surface),
                Positioned(bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, t.card],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, children: [
                        Container(height: 8, width: double.infinity,
                            decoration: BoxDecoration(color: t.surfaceHigh,
                                borderRadius: BorderRadius.circular(4))),
                        const SizedBox(height: 4),
                        Container(height: 6, width: 50,
                            decoration: BoxDecoration(color: t.surfaceHigh,
                                borderRadius: BorderRadius.circular(3))),
                      ]),
                  )),
              ]),
            ),
          ),
        ),
      ]),
    );

    return ListView(physics: const NeverScrollableScrollPhysics(), children: [
      const SizedBox(height: 96),
      // Hero banner skeleton
      Shimmer.fromColors(
        baseColor: t.surface, highlightColor: t.surfaceHigh,
        child: Container(
          height: 264, margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: t.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Stack(children: [
            // Page-indicator dots
            Positioned(bottom: 14, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => Container(
                  width: i == 0 ? 22 : 5, height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(3)),
                )))),
            // Title + buttons
            Positioned(bottom: 38, left: 16, right: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Container(height: 22, width: 180,
                    decoration: BoxDecoration(color: t.surfaceHigh,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 12),
                Row(children: [
                  Container(width: 120, height: 36, decoration: BoxDecoration(
                      color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.round))),
                  const SizedBox(width: 10),
                  Container(width: 90, height: 36, decoration: BoxDecoration(
                      color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.round))),
                ]),
              ])),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      // Category chips row skeleton
      Shimmer.fromColors(
        baseColor: t.surface, highlightColor: t.surfaceHigh,
        child: SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            itemCount: 7,
            itemBuilder: (_, __) => Container(
              width: 72, height: 32, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.round))),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Two full content sections
      section(),
      section(),
      const SizedBox(height: 24),
    ]);
  }
}

// ── Hero Spotlight ────────────────────────────────────────────────────────────
class _HeroSpotlight extends StatefulWidget {
  final List<CatalogItem> items;
  const _HeroSpotlight({required this.items});
  @override
  State<_HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<_HeroSpotlight> {
  final PageController _ctrl = PageController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _autoScroll();
  }

  void _autoScroll() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final next = (_current + 1) % widget.items.length;
      _ctrl.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
      _autoScroll();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(children: [
      SizedBox(
        height: 264,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) => _HeroCard(item: widget.items[i]),
        ),
      ),
      SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(
        widget.items.length,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _current == i ? 22 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: _current == i ? AppColors.primary : t.textMuted.withOpacity(0.3),
            borderRadius: BorderRadius.circular(3)),
        ),
      )),
    ]);
  }
}

// Phase 48 ANIM-48-04: _HeroCard → ConsumerStatefulWidget with 3D auto-float tilt
// Real gyroscope (sensors_plus, ANIM-48-01) deferred — requires pubspec.yaml package add.
// Auto-float is the accepted Tier-2 fallback per spec and works for all tiers.
class _HeroCard extends ConsumerStatefulWidget {
  final CatalogItem item;
  const _HeroCard({required this.item});

  @override
  ConsumerState<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends ConsumerState<_HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _tiltX;
  late final Animation<double> _tiltY;

  @override
  void initState() {
    super.initState();
    // 3200ms sine-wave gives a slow, dreamy float without visual fatigue
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _tiltX = Tween<double>(begin: -0.025, end: 0.025)
        .animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _tiltY = Tween<double>(begin: 0.015, end: -0.015)
        .animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    // ANIM-48-05: always dispose — sensor/controller leaks drain battery
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Shorthand so every `item.` reference below works unchanged (was a field in StatelessWidget)
    final item       = widget.item;
    final t          = RaddTheme.of(context);
    final animConfig = ref.watch(animConfigProvider);
    final catalog    = ref.watch(catalogProvider);
    final isResume   = catalog.recentlyWatched.any((e) => e.id == item.id);
    // Phase 48: Tier 1+ and animations-enabled → start float; otherwise stop
    final shouldFloat = animConfig.canStagger &&
        !MediaQuery.of(context).disableAnimations;
    if (shouldFloat && !_floatCtrl.isAnimating) _floatCtrl.repeat(reverse: true);
    else if (!shouldFloat && _floatCtrl.isAnimating) _floatCtrl.stop();

    // Build the card widget (identical to old StatelessWidget.build, no renames needed)
    final card = GestureDetector(
      onTap: () {
        DebugLogger.logTap('Home', 'heroCard');
        Navigator.of(context).pushNamed(AppRoutes.showDetail, arguments: item);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(fit: StackFit.expand, children: [
            // Task 3.5: prefer local cached poster file; fallback to network URL
            // Phase 42: Hero tag matches show_detail_screen banner for smooth morph
            Hero(tag: 'poster_${item.id}', child: _buildPosterImage()),
            // Cinematic gradient overlay — bottom 70% fade
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: [0.0, 0.35, 0.7, 1.0],
                  colors: [Colors.transparent, Colors.transparent, Color(0xCC000000), Color(0xF5000000)],
                ),
              ),
            ),
            // Top badges: content type
            Positioned(top: 12, left: 16, child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(item.isShow ? 'SERIES' : 'MOVIE',
                    style: const TextStyle(color: Colors.white70, fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
              if (item.displayRating.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppIcons.starFill, color: Colors.amber, size: 10),
                    const SizedBox(width: 3),
                    Text(item.displayRating, style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ])),
            // Content
            Positioned(bottom: 0, left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900,
                      letterSpacing: -0.5, height: 1.15,
                      shadows: [Shadow(color: Colors.black, blurRadius: 12)])),
                  const SizedBox(height: 12),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppRadius.round),
                          boxShadow: AppShadows.primary),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          isResume ? AppIcons.playCircleFill : AppIcons.play,
                          color: Colors.white, size: 18),
                        const SizedBox(width: 5),
                        Text(isResume ? 'Resume' : 'Watch Now',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadius.round),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppIcons.add, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('My List', style: TextStyle(color: Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ]),
              )),
          ]),
        ),
      ),
    );
    // Phase 48: wrap card in 3D Transform with perspective depth (ANIM-48-02/03)
    if (!shouldFloat) return card;
    return AnimatedBuilder(
      animation: _floatCtrl,
      builder: (_, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective — needed for rotateX/Y to appear 3D
          ..rotateX(_tiltX.value) // pitch tilt  ±1.43°
          ..rotateY(_tiltY.value), // yaw tilt   ±0.86°
        child: child,
      ),
      child: card,
    );
  }

  Widget _buildPosterImage() {
    final item = widget.item; // Phase 48: shorthand; was a direct field in StatelessWidget
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.card),
      child: Center(child: Icon(AppIcons.movie, color: AppColors.textMuted, size: 48)),
    );

    // 1. Local file (permanent cached poster — zero network, instant load)
    if (item.posterPath != null) {
      return Image.file(
        File(item.posterPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => item.posterUrl != null
            ? CachedNetworkImage(
                imageUrl: item.posterUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => placeholder,
              )
            : placeholder,
      );
    }

    // 2. Network URL (TMDB/OMDB — requires internet)
    if (item.posterUrl != null) {
      return CachedNetworkImage(
        imageUrl: item.posterUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: AppColors.card,
          highlightColor: const Color(0xFF2A2A2A),
          child: Container(color: AppColors.card),
        ),
        errorWidget: (_, __, ___) => placeholder,
      );
    }

    // 3. No image available
    return placeholder;
  }
}

// ── Update Dialog ─────────────────────────────────────────────────────────────
/// Non-dismissable dialog shown when the installed build is below min_version_code.
class _UpdateDialog extends StatelessWidget {
  final String updateUrl;
  const _UpdateDialog({required this.updateUrl});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.systemUpdate, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('Update Required', style: TextStyle(
              color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'A new version of RaddFlix is available. Please update to keep streaming.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(AppIcons.downloadAction, size: 18),
              label: const Text('Update Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.round)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () async {
                if (updateUrl.isNotEmpty) {
                  await launchUrl(Uri.parse(updateUrl),
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Content Section ───────────────────────────────────────────────────────────
class _ContentSection extends StatelessWidget {
  final String title;
  final IconData? titleIcon;
  final int? count;
  final List<CatalogItem> items;
  final bool showProgress;
  final void Function(CatalogItem)? onRemove;
  const _ContentSection({required this.title, this.titleIcon, this.count, required this.items,
    this.showProgress = false, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(children: [
          // Red accent bar
          Container(
            width: 3, height: 20,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (titleIcon != null) ...[
            Icon(titleIcon!, color: AppColors.primary, size: 17),
            const SizedBox(width: 6),
          ],
          Text(title, style: TextStyle(color: t.textPrimary,
              fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Text(count.toString(),
                  style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () {
              String? filter;
              if (title == "Movies") filter = "Movies";
              else if (title.contains("Show") || title.contains("Drama")) filter = "Shows";
              Navigator.of(context).pushNamed(AppRoutes.search,
                  arguments: {"initialFilter": filter});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: t.border),
              ),
              child: const Text('See all', style: TextStyle(
                  color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
      SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(right: i < items.length - 1 ? 10 : 0),
            child: SizedBox(width: 126,
                child: Stack(children: [
                  ContentCard(
                      item: items[i],
                      showProgress: showProgress,
                      progress: showProgress ? (items[i].watchProgress ?? 0.5) : null,
                      onLongPress: onRemove != null
                          ? () => _showRemoveDialog(context, items[i])
                          : null),
                  if (onRemove != null)
                    Positioned(
                      top: 5, right: 5,
                      child: GestureDetector(
                        onTap: () => _showRemoveDialog(context, items[i]),
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Icon(AppIcons.close,
                              size: 13, color: Colors.white70),
                        ),
                      ),
                    ),
                ]))
                .animate(delay: (i * 30).ms).fadeIn(duration: 300.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, curve: AppCurves.standard),
          ),
        ),
      ),
    ]);
  }

  void _showRemoveDialog(BuildContext context, CatalogItem item) {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: t.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: t.textMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(children: [
              Row(children: [
                Icon(AppIcons.minusCircle,
                    color: AppColors.error, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Remove "${item.title}" from Continue Watching?',
                  style: TextStyle(color: t.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w600),
                )),
              ]),
              SizedBox(height: 16),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: t.border),
                    ),
                    child: Center(child: Text('Cancel',
                        style: TextStyle(color: t.textMuted, fontSize: 14))),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onRemove?.call(item);
                  },
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: const Center(child: Text('Remove',
                        style: TextStyle(color: AppColors.error,
                            fontSize: 14, fontWeight: FontWeight.w700))),
                  ),
                )),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Category Chip ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected
              ? AppColors.primaryGradient
              : null,
          color: isSelected ? null : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.round),
          border: Border.all(
            color: isSelected ? Colors.transparent : t.border, width: 1),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isSelected) ...[
            Icon(AppIcons.check, size: 11, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(
            color: isSelected ? Colors.white : t.textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: isSelected ? 0.1 : 0)),
        ]),
      ),
    );
  }
}

// ── Recommendations Section ───────────────────────────────────────────────────
class _RecommendationsSection extends StatelessWidget {
  final List<Map<String, dynamic>> recommendations;
  const _RecommendationsSection({required this.recommendations});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(children: [
          Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(2))),
          Text('You Might Like',
              style: TextStyle(color: t.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.round),
              border: Border.all(color: t.border),
            ),
            child: Text('TMDB',
                style: TextStyle(color: t.textMuted, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
        ]),
      ),
      SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: recommendations.length,
          itemBuilder: (_, i) {
            final rec    = recommendations[i];
            final title  = rec['title']      as String? ?? '';
            final poster = rec['poster_url'] as String? ?? '';
            final rating = (rec['rating'] as num?)?.toDouble() ?? 0.0;
            return RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.only(right: i < recommendations.length - 1 ? 10 : 0),
                child: SizedBox(
                  width: 126,
                  child: _RecommendCard(title: title, poster: poster, rating: rating),
                ).animate(delay: (i * 30).ms).fadeIn(duration: 300.ms)
                    .slideX(begin: 0.1, end: 0, duration: 300.ms,
                        curve: AppCurves.standard),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _RecommendCard extends StatelessWidget {
  final String title;
  final String poster;
  final double rating;
  const _RecommendCard({required this.title, required this.poster, required this.rating});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$title" is not in the RaddFlix library yet'),
          backgroundColor: t.surface,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Search',
            textColor: AppColors.primary,
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.search),
          ),
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Stack(fit: StackFit.expand, children: [
            poster.isNotEmpty
                ? CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover,
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor: t.card,
                      highlightColor: t.surfaceHigh,
                      child: Container(color: t.card)),
                    errorWidget: (_, __, ___) => Container(color: t.card,
                        child: Icon(AppIcons.movie,
                            color: t.textMuted, size: 28)))
                : Container(color: t.card,
                    child: Icon(AppIcons.movie,
                        color: t.textMuted, size: 28)),
            // Gradient overlay
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 32, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD000000)],
                  ),
                ),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
              )),
            // Rating
            if (rating > 0)
              Positioned(top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppIcons.starFill, color: Colors.amber, size: 10),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1), style: const TextStyle(
                        color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                  ]),
                )),
            // "Request" badge
            Positioned(top: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                ),
                child: const Text('COMING',
                    style: TextStyle(color: AppColors.primary, fontSize: 7,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              )),
          ]),
        ),
      ),
    );
  }
}


