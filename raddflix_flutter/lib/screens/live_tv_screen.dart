// lib/screens/live_tv_screen.dart
//
// Live TV tab — channels loaded from Oracle via API, cached in local SQLite.
// Category filter chips + search bar + 2-column animated channel grid.
// Pull-to-refresh fetches the latest list from Oracle.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/theme/radd_theme.dart';
import '../core/design/app_icons.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';
import '../data/live_channels.dart';
import '../providers/live_channel_provider.dart';

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

  List<LiveChannel> _filtered(List<LiveChannel> all) {
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

  void _playChannel(LiveChannel ch) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id':      'live_${ch.id}',
      'title':        ch.name,
      'stream_url':   ch.streamUrl,
      'content_type': 'live',
      'is_free':      true,
      'poster_url':   ch.logoUrl,
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t       = RaddTheme.of(context);
    final lvState = ref.watch(liveChannelProvider);
    final channels = _filtered(lvState.channels);
    final width    = MediaQuery.sizeOf(context).width;
    final cols     = width > 600 ? 3 : 2;

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
              // ── Header row ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary
                                .withOpacity(0.55 + 0.45 * _pulseCtrl.value),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary
                                    .withOpacity(0.45 * _pulseCtrl.value),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Live TV',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      // Channel count badge — total in current list
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.35)),
                        ),
                        child: Text(
                          lvState.channels.isEmpty
                              ? '— CH'
                              : '${lvState.channels.length} CH',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search bar ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: RaddRadius.mdRadius,
                      border:
                          Border.all(color: t.border.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(AppIcons.search,
                            size: 18, color: t.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: TextStyle(
                                color: t.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search channels…',
                              hintStyle: TextStyle(
                                  color: t.textMuted, fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: _searchCtrl.clear,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(AppIcons.close,
                                  size: 16, color: t.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Category chips ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: kLiveCategories.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: RaddSpace.xs),
                    itemBuilder: (_, i) {
                      final cat    = kLiveCategories[i];
                      final active = _selectedCat == cat.id;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCat = cat.id);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : t.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : t.border.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            cat.label,
                            style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : t.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Loading state ──────────────────────────────────────────
              if (lvState.isLoading && lvState.channels.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Loading channels…',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Error state ────────────────────────────────────────────
              if (lvState.hasError && lvState.channels.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(AppIcons.liveTv,
                                size: 48,
                                color: t.textMuted.withOpacity(0.45)),
                            const SizedBox(height: 16),
                            Text(
                              lvState.error ??
                                  'Could not load channels.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: t.textMuted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 18),
                            GestureDetector(
                              onTap: () => ref
                                  .read(liveChannelProvider.notifier)
                                  .refresh(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 9),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withOpacity(0.4)),
                                ),
                                child: Text(
                                  'Try again',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Empty search/filter result ─────────────────────────────
              if (!lvState.isLoading &&
                  !lvState.hasError &&
                  lvState.channels.isNotEmpty &&
                  channels.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 240,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.liveTv,
                            size: 52, color: t.textMuted),
                        const SizedBox(height: 14),
                        Text(
                          'No channels found',
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Channel grid ───────────────────────────────────────────
              if (channels.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final ch = channels[i];
                        return _ChannelCard(
                          channel: ch,
                          pulseCtrl: _pulseCtrl,
                          onTap: () => _playChannel(ch),
                        )
                            .animate()
                            .fadeIn(
                              delay: Duration(
                                  milliseconds: (i * 22).clamp(0, 280)),
                              duration: 260.ms,
                            )
                            .slideY(
                              begin: 0.07,
                              end: 0,
                              duration: 260.ms,
                              curve: Curves.easeOut,
                            );
                      },
                      childCount: channels.length,
                    ),
                  ),
                ),

              // ── Bottom spacer (clears the mini player bar) ─────────────
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Channel card ──────────────────────────────────────────────────────────────

class _ChannelCard extends StatelessWidget {
  final LiveChannel channel;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.pulseCtrl,
    required this.onTap,
  });

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

  @override
  Widget build(BuildContext context) {
    final t      = RaddTheme.of(context);
    final accent = _catAccent(channel.cat);

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
            color: t.card,
            borderRadius: RaddRadius.lgRadius,
            border: Border.all(color: t.border.withOpacity(0.30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.32),
                blurRadius: 14,
                offset: const Offset(0, 4),
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
                    // Logo background + image
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft:  Radius.circular(RaddRadius.lg),
                        topRight: Radius.circular(RaddRadius.lg),
                      ),
                      child: Container(
                        color: AppColors.backgroundAlt,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: channel.logoUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: channel.logoUrl,
                                    fit: BoxFit.contain,
                                    fadeInDuration:
                                        const Duration(milliseconds: 300),
                                    placeholder: (_, __) => Icon(
                                      AppIcons.tv,
                                      color: t.textMuted.withOpacity(0.5),
                                      size: 34,
                                    ),
                                    errorWidget: (_, __, ___) => _LogoFallback(
                                      name: channel.name,
                                      muted: t.textMuted,
                                    ),
                                  )
                                : _LogoFallback(
                                    name: channel.name,
                                    muted: t.textMuted,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    // LIVE badge (top-right)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: AnimatedBuilder(
                        animation: pulseCtrl,
                        builder: (_, __) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withOpacity(0.80 + 0.20 * pulseCtrl.value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Featured star badge (top-left)
                    if (channel.isFeatured)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC107).withOpacity(0.90),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '★',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black,
                                  height: 1.1),
                            ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              channel.genre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textMuted,
                                fontSize: 10.5,
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

// Logo fallback: TV icon + first two words of channel name
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
            style: TextStyle(
              color: muted,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}
