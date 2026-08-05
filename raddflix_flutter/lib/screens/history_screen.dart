import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animations/animations.dart';
import '../core/api/history_api.dart';
import '../core/constants.dart';
import '../core/utils/anim_config.dart';
import '../design_system/radius/radd_radius.dart';
import '../models/catalog_item.dart';
import '../providers/catalog_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/content_card.dart';
import 'show_detail_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _syncError = false;

  @override
  void initState() {
    super.initState();
    // Pull server history so cross-device positions appear in Continue Watching.
    // UI shows local data immediately; refreshes after merge.
    _mergeServerHistory();
  }

  Future<void> _mergeServerHistory() async {
    // Clear any prior error so the banner disappears while retrying.
    if (_syncError && mounted) setState(() => _syncError = false);
    // P28-04: Skip server sync for guest sessions — guests have no server history.
    if (ref.read(authProvider).user?.isGuest == true) return;
    try {
      await HistoryApi.mergeServerHistory();
      if (mounted) {
        await ref.read(catalogProvider.notifier).reloadRecentlyWatched();
      }
    } catch (_) {
      if (mounted) setState(() => _syncError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final catalog = ref.watch(catalogProvider);
    final items = catalog.recentlyWatched;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.back,
              color: t.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Watch History',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: t.card,
                    title: Text('Clear History',
                        style: TextStyle(color: t.textPrimary)),
                    content: Text(
                        'This will remove all items from your watch history.',
                        style: TextStyle(color: t.textSecondary)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear',
                              style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    // HIST-L6: await so errors surface to the user.
                    await ref.read(catalogProvider.notifier).clearAllContinueWatching();
                    // HIST-L5: best-effort server clear; fire-and-forget (offline is fine).
                    HistoryApi.clearServerHistory().ignore();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to clear history — try again'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Clear All',
                  style: TextStyle(color: AppColors.error, fontSize: 13)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_syncError)
            Material(
              color: AppColors.error.withOpacity(0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(children: [
                  // UX-04: use AppIcons design token, not raw Material icon
                  Icon(AppIcons.warning,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        "Couldn't sync watch history — showing local data",
                        style: TextStyle(
                            color: t.textSecondary, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: _mergeServerHistory,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Text('Retry',
                          style: TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? _buildEmpty(context)
                : _buildGrid(context, items),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final t = RaddTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(color: t.border),
            ),
            child: Icon(AppIcons.history,
                color: t.textMuted, size: 36),
          ),
          SizedBox(height: 20),
          Text(
            'No Watch History',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Movies and shows you watch\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: t.textMuted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: context.signalPrimary,
                borderRadius: RaddRadius.mdRadius,
              ),
              child: const Text(
                'Browse Content',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // HIST-L7: group items by recency using their watchedAt timestamp.
  Map<String, List<CatalogItem>> _groupByDate(List<CatalogItem> items) {
    final now = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo   = today.subtract(const Duration(days: 7));

    final groups = <String, List<CatalogItem>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Earlier': [],
    };
    for (final item in items) {
      final dt = item.watchedAt;
      if (dt == null) {
        groups['Earlier']!.add(item);
        continue;
      }
      final date = DateTime(dt.year, dt.month, dt.day);
      if (!date.isBefore(today)) {
        groups['Today']!.add(item);
      } else if (!date.isBefore(yesterday)) {
        groups['Yesterday']!.add(item);
      } else if (!date.isBefore(weekAgo)) {
        groups['This Week']!.add(item);
      } else {
        groups['Earlier']!.add(item);
      }
    }
    return groups;
  }

  Widget _buildGrid(BuildContext context, List<CatalogItem> items) {
    final t = RaddTheme.of(context);
    final animConfig = ref.watch(animConfigProvider);
    final canMorph = animConfig.canMorph && animConfig.shouldAnimate(context);
    final groups = _groupByDate(items);
    final sectionOrder = ['Today', 'Yesterday', 'This Week', 'Earlier'];

    // Build a flat list of section-header + row-of-cards entries for CustomScrollView.
    final slivers = <Widget>[];
    int globalIdx = 0;
    for (final section in sectionOrder) {
      final sectionItems = groups[section]!;
      if (sectionItems.isEmpty) continue;

      // Section header
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            section,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ));

      // Grid for this section
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2 / 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final item = sectionItems[i];
              final idx = globalIdx + i;
              // HIST-L6: swipe-to-dismiss each item.
              final card = canMorph
                  ? OpenContainer<void>(
                      closedColor: Colors.transparent,
                      openColor: Colors.transparent,
                      closedElevation: 0,
                      openElevation: 0,
                      transitionDuration: animConfig.slow,
                      tappable: false,
                      closedBuilder: (_, openFn) =>
                          ContentCard(item: item, onTap: openFn),
                      openBuilder: (_, __) => ShowDetailScreen(item: item),
                    )
                  : ContentCard(item: item)
                      .animate(delay: (idx * 30).ms)
                      .fadeIn(duration: 300.ms)
                      .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1, 1),
                          duration: 300.ms);
              return Dismissible(
                key: ValueKey('hist_${item.id}'),
                direction: DismissDirection.startToEnd,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(RaddRadius.sm),
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.white, size: 22),
                ),
                onDismissed: (_) {
                  ref
                      .read(catalogProvider.notifier)
                      .removeFromContinueWatching(item);
                },
                child: card,
              );
            },
            childCount: sectionItems.length,
          ),
        ),
      ));
      globalIdx += sectionItems.length;
    }

    // Bottom padding sliver to clear the nav bar.
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));

    return CustomScrollView(slivers: slivers);
  }
}
