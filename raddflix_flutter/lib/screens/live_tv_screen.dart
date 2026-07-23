// lib/screens/live_tv_screen.dart
//
// Live TV tab — channels loaded from Oracle via API, cached in local SQLite.
//
// Layout:
//   • "All" view (no search): featured hero banner → recently watched row
//     → per-category horizontal rows (Netflix-style). Tapping "See all →"
//     or a category chip switches to single-category 2-col grid.
//   • Single-category / search view: 2-col grid with backdrop-tinted cards.
//
// Pull-to-refresh triggers a fresh fetch from Oracle.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/theme/radd_theme.dart';
import '../core/design/app_icons.dart';
import '../design_system/components/radd_button.dart';
import '../design_system/components/radd_chip.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';
import '../data/live_channels.dart';
import '../providers/live_channel_provider.dart';

// ── Hex → Color helper ────────────────────────────────────────────────────────

Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  return const Color(0xFF1A1A2E);
}

// ── Category accent colours (matches admin seed) ──────────────────────────────

Color _catAccent(String cat) {
  switch (cat) {
    case 'sports':        return const Color(0xFFFF6B35);
    case 'religious':     return const Color(0xFF00BFA5);
    case 'news':          return const Color(0xFF42A5F5);
    case 'entertainment': return const Color(0xFFAB47BC);
    case 'kids':          return const Color(0xFFFFCA28);
    case 'movies':        return const Color(0xFFFF7043);
    case 'docs':          return const Color(0xFF66BB6A);
    default:              return AppColors.primary;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  String _selectedCat = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  bool get _isAllView => _selectedCat == 'all' && _searchQuery.isEmpty;

  List<LiveChannel> _filteredAll(List<LiveChannel> all) {
    final base = _selectedCat == 'all'
        ? all
        : all.where((c) => c.cat == _selectedCat).toList();
    if (_searchQuery.isEmpty) return base;
    return base
        .where((c) =>
            c.name.toLowerCase().contains(_searchQuery) ||
            c.genre.toLowerCase().contains(_searchQuery))
        .toList();
  }

  List<LiveChannel> _forCategory(List<LiveChannel> all, String catId) =>
      all.where((c) => c.cat == catId).toList();

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _playChannel(LiveChannel ch) {
    HapticFeedback.lightImpact();
    ref.read(liveChannelProvider.notifier).recordWatched(ch.id);
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id':      'live_${ch.id}',
      'title':        ch.name,
      'stream_url':   ch.streamUrl,
      'content_type': 'live',
      'is_free':      ch.isFree,
      'poster_url':   ch.logoUrl,
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t       = RaddTheme.of(context);
    final lvState = ref.watch(liveChannelProvider);
    final all     = lvState.channels;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: t.surface,
        onRefresh: () => ref.read(liveChannelProvider.notifier).refresh(),
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Header row ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(t, lvState)),

              // ── Search bar ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildSearchBar(t)),

              // ── Category chips ────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildCategoryChips(t)),

              // ── Loading state ─────────────────────────────────────────────
              if (lvState.isLoading && all.isEmpty)
                SliverToBoxAdapter(child: _buildLoading(t)),

              // ── Error state ───────────────────────────────────────────────
              if (lvState.hasError && all.isEmpty)
                SliverToBoxAdapter(child: _buildError(t, lvState)),

              // ── Content ───────────────────────────────────────────────────
              if (all.isNotEmpty) ..._buildContent(t, lvState, all),

              // ── Bottom spacer ─────────────────────────────────────────────
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(RaddTheme t, LiveChannelState lvState) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Row(
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.55 + 0.45 * _pulseCtrl.value),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.45 * _pulseCtrl.value),
                  blurRadius: 10, spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('LIVE', style: TextStyle(
          color: AppColors.primary, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.5,
        )),
        const SizedBox(width: 10),
        Text('Live TV', style: TextStyle(
          color: t.textPrimary, fontSize: 22,
          fontWeight: FontWeight.w800, letterSpacing: -0.5,
        )),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.primary.withOpacity(0.35)),
          ),
          child: Text(
            lvState.channels.isEmpty ? '— CH' : '${lvState.channels.length} CH',
            style: TextStyle(
              color: AppColors.primary, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar(RaddTheme t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RaddRadius.mdRadius,
        border: Border.all(color: t.border.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(AppIcons.search, size: 18, color: t.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: t.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search channels…',
                hintStyle: TextStyle(color: t.textMuted, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              onPressed: _searchCtrl.clear,
              icon: Icon(AppIcons.close, size: 16, color: t.textMuted),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(),
              splashRadius: 16,
            ),
        ],
      ),
    ),
  );

  // ── Category chips ─────────────────────────────────────────────────────────

  Widget _buildCategoryChips(RaddTheme t) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: kLiveCategories.length,
      separatorBuilder: (_, __) => const SizedBox(width: RaddSpace.xs),
      itemBuilder: (_, i) {
        final cat    = kLiveCategories[i];
        final active = _selectedCat == cat.id;
        return RaddChip(
          label: cat.label,
          active: active,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCat = cat.id);
          },
        );
      },
    ),
  );

  // ── Loading / error states ──────────────────────────────────────────────────

  Widget _buildLoading(RaddTheme t) => SizedBox(
    height: 300,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('Loading channels…', style: TextStyle(color: t.textMuted, fontSize: 14)),
        ],
      ),
    ),
  );

  Widget _buildError(RaddTheme t, LiveChannelState lvState) => SizedBox(
    height: 300,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.liveTv, size: 48, color: t.textMuted.withOpacity(0.45)),
            const SizedBox(height: 16),
            Text(
              lvState.error ?? 'Could not load channels.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            RaddButton(
              variant: RaddButtonVariant.tonal,
              size: RaddButtonSize.small,
              label: 'Try again',
              leadingIcon: AppIcons.refresh,
              onPressed: () => ref.read(liveChannelProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Content dispatcher ─────────────────────────────────────────────────────

  List<Widget> _buildContent(
    RaddTheme t,
    LiveChannelState lvState,
    List<LiveChannel> all,
  ) {
    if (_isAllView) {
      return _buildAllView(t, lvState, all);
    }

    // Single-category or search: 2-col grid
    final filtered = _filteredAll(all);
    if (filtered.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 240,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.liveTv, size: 52, color: t.textMuted),
                const SizedBox(height: 14),
                Text('No channels found', style: TextStyle(
                  color: t.textMuted, fontSize: 15, fontWeight: FontWeight.w500,
                )),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final ch = filtered[i];
              return _GridCard(
                channel: ch,
                pulseCtrl: _pulseCtrl,
                onTap: () => _playChannel(ch),
              )
                  .animate()
                  .fadeIn(
                    delay: Duration(milliseconds: (i * 22).clamp(0, 280)),
                    duration: 260.ms,
                  )
                  .slideY(begin: 0.07, end: 0, duration: 260.ms, curve: Curves.easeOut);
            },
            childCount: filtered.length,
          ),
        ),
      ),
    ];
  }

  // ── All-view: hero + recently watched + per-category rows ──────────────────

  List<Widget> _buildAllView(
    RaddTheme t,
    LiveChannelState lvState,
    List<LiveChannel> all,
  ) {
    final featured   = all.where((c) => c.isFeatured).firstOrNull;
    final recents    = lvState.recentChannels;
    final slivers    = <Widget>[];

    // Featured hero banner
    if (featured != null) {
      slivers.add(SliverToBoxAdapter(
        child: _FeaturedHero(
          channel: featured,
          pulseCtrl: _pulseCtrl,
          onTap: () => _playChannel(featured),
        ).animate().fadeIn(duration: 350.ms),
      ));
    }

    // Recently watched row
    if (recents.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _buildRecentRow(t, recents),
      ));
    }

    // Per-category horizontal rows
    for (final cat in kLiveCategories.where((c) => c.id != 'all')) {
      final channels = _forCategory(all, cat.id);
      if (channels.isEmpty) continue;
      slivers.add(SliverToBoxAdapter(
        child: _CategoryRow(
          category: cat,
          channels: channels,
          pulseCtrl: _pulseCtrl,
          onChannelTap: _playChannel,
          onSeeAll: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCat = cat.id);
          },
        ).animate().fadeIn(duration: 300.ms),
      ));
    }

    if (slivers.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: Center(child: Text('No channels available', style: TextStyle(color: t.textMuted))),
        ),
      ));
    }

    return slivers;
  }

  // ── Recently watched row ───────────────────────────────────────────────────

  Widget _buildRecentRow(RaddTheme t, List<LiveChannel> recents) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Recently Watched', style: TextStyle(
            color: t.textPrimary, fontSize: 15,
            fontWeight: FontWeight.w700, letterSpacing: -0.2,
          )),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final ch = recents[i];
              return GestureDetector(
                onTap: () => _playChannel(ch),
                child: Container(
                  width: 72,
                  decoration: BoxDecoration(
                    color: _hexColor(ch.backdropColor).withOpacity(0.25),
                    borderRadius: RaddRadius.mdRadius,
                    border: Border.all(
                      color: _hexColor(ch.backdropColor).withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 38, height: 38,
                        child: ch.logoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: ch.logoUrl,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => Icon(AppIcons.tv, size: 20, color: t.textMuted.withOpacity(0.5)),
                                errorWidget: (_, __, ___) => Icon(AppIcons.tv, size: 20, color: t.textMuted.withOpacity(0.5)),
                              )
                            : Icon(AppIcons.tv, size: 20, color: t.textMuted.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: t.textMuted, fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(
                delay: Duration(milliseconds: i * 40),
                duration: 200.ms,
              );
            },
          ),
        ),
      ],
    ),
  );
}

// ── Featured hero banner ──────────────────────────────────────────────────────

class _FeaturedHero extends StatelessWidget {
  final LiveChannel channel;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;

  const _FeaturedHero({
    required this.channel,
    required this.pulseCtrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t          = RaddTheme.of(context);
    final bgColor    = _hexColor(channel.backdropColor);
    final accentSafe = bgColor.withOpacity(0.85);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: RaddRadius.lgRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [bgColor.withOpacity(0.95), bgColor.withOpacity(0.45)],
            ),
            boxShadow: [
              BoxShadow(
                color: bgColor.withOpacity(0.4),
                blurRadius: 24, spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: RaddRadius.lgRadius,
            child: Stack(
              children: [
                // Dark overlay on left side for text legibility
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // Content row
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      // Logo
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: channel.logoUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: channel.logoUrl,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => Icon(AppIcons.tv, color: Colors.white54, size: 32),
                                  errorWidget: (_, __, ___) => Icon(AppIcons.tv, color: Colors.white54, size: 32),
                                )
                              : Icon(AppIcons.tv, color: Colors.white54, size: 32),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Text + CTA
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // FEATURED badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC107).withOpacity(0.90),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('FEATURED', style: TextStyle(
                                color: Colors.black87, fontSize: 8,
                                fontWeight: FontWeight.w800, letterSpacing: 1.0,
                              )),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 20,
                                fontWeight: FontWeight.w800, letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              channel.genre,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.70),
                                fontSize: 12, fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Watch Now button
                            Row(
                              children: [
                                AnimatedBuilder(
                                  animation: pulseCtrl,
                                  builder: (_, __) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.85 + 0.15 * pulseCtrl.value),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7, height: 7,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text('Watch Now', style: TextStyle(
                                          color: Colors.white, fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        )),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Ripple tap effect
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: RaddRadius.lgRadius,
                      splashColor: Colors.white.withOpacity(0.06),
                      highlightColor: Colors.white.withOpacity(0.03),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Per-category horizontal row ───────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  final LiveCategory category;
  final List<LiveChannel> channels;
  final AnimationController pulseCtrl;
  final void Function(LiveChannel) onChannelTap;
  final VoidCallback onSeeAll;

  const _CategoryRow({
    required this.category,
    required this.channels,
    required this.pulseCtrl,
    required this.onChannelTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final t      = RaddTheme.of(context);
    final accent = _catAccent(category.id);

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 3, height: 16,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(category.label, style: TextStyle(
                  color: t.textPrimary, fontSize: 15,
                  fontWeight: FontWeight.w700, letterSpacing: -0.2,
                )),
                const Spacer(),
                GestureDetector(
                  onTap: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See all', style: TextStyle(
                          color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w500,
                        )),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 16, color: t.textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Horizontal channel scroll
          SizedBox(
            height: 155,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final ch = channels[i];
                return _HorizontalCard(
                  channel: ch,
                  pulseCtrl: pulseCtrl,
                  accent: accent,
                  onTap: () => onChannelTap(ch),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Horizontal card (used inside category rows) ───────────────────────────────

class _HorizontalCard extends StatelessWidget {
  final LiveChannel channel;
  final AnimationController pulseCtrl;
  final Color accent;
  final VoidCallback onTap;

  const _HorizontalCard({
    required this.channel,
    required this.pulseCtrl,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t       = RaddTheme.of(context);
    final bgTint  = _hexColor(channel.backdropColor);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: bgTint.withOpacity(0.18),
          borderRadius: RaddRadius.mdRadius,
          border: Border.all(color: bgTint.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo area
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft:  Radius.circular(RaddRadius.md),
                      topRight: Radius.circular(RaddRadius.md),
                    ),
                    child: Container(
                      color: bgTint.withOpacity(0.25),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: channel.logoUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: channel.logoUrl,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => Icon(AppIcons.tv, color: t.textMuted.withOpacity(0.5), size: 24),
                                  errorWidget: (_, __, ___) => _SmallLogoFallback(name: channel.name, muted: t.textMuted),
                                )
                              : _SmallLogoFallback(name: channel.name, muted: t.textMuted),
                        ),
                      ),
                    ),
                  ),
                  // LIVE badge
                  Positioned(
                    top: 5, right: 5,
                    child: AnimatedBuilder(
                      animation: pulseCtrl,
                      builder: (_, __) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.80 + 0.20 * pulseCtrl.value),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('LIVE', style: TextStyle(
                          color: Colors.white, fontSize: 7,
                          fontWeight: FontWeight.w800, letterSpacing: 0.6,
                        )),
                      ),
                    ),
                  ),
                  // Lock icon for non-free channels
                  if (!channel.isFree)
                    Positioned(
                      top: 5, left: 5,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.lock_rounded, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Name
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textPrimary, fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 20, height: 2,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid card (used in single-category / search views) ───────────────────────

class _GridCard extends StatelessWidget {
  final LiveChannel channel;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;

  const _GridCard({
    required this.channel,
    required this.pulseCtrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t       = RaddTheme.of(context);
    final accent  = _catAccent(channel.cat);
    final bgTint  = _hexColor(channel.backdropColor);

    return Material(
      color: Colors.transparent,
      borderRadius: RaddRadius.lgRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: RaddRadius.lgRadius,
        splashColor: AppColors.primary.withOpacity(0.10),
        highlightColor: AppColors.primary.withOpacity(0.05),
        child: Ink(
          decoration: BoxDecoration(
            color: bgTint.withOpacity(0.15),
            borderRadius: RaddRadius.lgRadius,
            border: Border.all(color: bgTint.withOpacity(0.40)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 14, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo area ─────────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft:  Radius.circular(RaddRadius.lg),
                        topRight: Radius.circular(RaddRadius.lg),
                      ),
                      child: Container(
                        color: bgTint.withOpacity(0.25),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: channel.logoUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: channel.logoUrl,
                                    fit: BoxFit.contain,
                                    fadeInDuration: const Duration(milliseconds: 300),
                                    placeholder: (_, __) => Icon(AppIcons.tv, color: t.textMuted.withOpacity(0.5), size: 34),
                                    errorWidget: (_, __, ___) => _LogoFallback(name: channel.name, muted: t.textMuted),
                                  )
                                : _LogoFallback(name: channel.name, muted: t.textMuted),
                          ),
                        ),
                      ),
                    ),
                    // LIVE badge
                    Positioned(
                      top: 7, right: 7,
                      child: AnimatedBuilder(
                        animation: pulseCtrl,
                        builder: (_, __) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.80 + 0.20 * pulseCtrl.value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LIVE', style: TextStyle(
                            color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8,
                          )),
                        ),
                      ),
                    ),
                    // Featured star badge
                    if (channel.isFeatured)
                      Positioned(
                        top: 7, left: 7,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC107).withOpacity(0.90),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('★', style: TextStyle(fontSize: 11, color: Colors.black, height: 1.1)),
                          ),
                        ),
                      ),
                    // Lock icon for non-free channels
                    if (!channel.isFree)
                      Positioned(
                        bottom: 7, right: 7,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.70),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Name + genre row ───────────────────────────────────────
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary, fontSize: 12.5,
                          fontWeight: FontWeight.w700, letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              channel.genre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textMuted, fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logo fallbacks ────────────────────────────────────────────────────────────

class _LogoFallback extends StatelessWidget {
  final String name;
  final Color  muted;
  const _LogoFallback({required this.name, required this.muted});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(AppIcons.tv, color: muted.withOpacity(0.45), size: 28),
      const SizedBox(height: 4),
      Text(
        name.split(' ').take(2).join('\n'),
        textAlign: TextAlign.center,
        maxLines: 2,
        style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w500),
      ),
    ],
  );
}

class _SmallLogoFallback extends StatelessWidget {
  final String name;
  final Color  muted;
  const _SmallLogoFallback({required this.name, required this.muted});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(AppIcons.tv, color: muted.withOpacity(0.45), size: 18),
      const SizedBox(height: 3),
      Text(
        name.split(' ').take(1).join(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted, fontSize: 8, fontWeight: FontWeight.w500),
      ),
    ],
  );
}
