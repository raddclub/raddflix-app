import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/content_card.dart';

enum _SortBy { dateAdded, alphabetical, rating, type }

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});
  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  _SortBy _sortBy = _SortBy.dateAdded;

  List<CatalogItem> _sorted(List<CatalogItem> items) {
    final list = [...items];
    switch (_sortBy) {
      case _SortBy.dateAdded:
        return list; // already in insertion order
      case _SortBy.alphabetical:
        list.sort((a, b) => a.title.compareTo(b.title));
        return list;
      case _SortBy.rating:
        list.sort((a, b) =>
            (b.rating ?? 0).compareTo(a.rating ?? 0));
        return list;
      case _SortBy.type:
        list.sort((a, b) => a.mediaType.compareTo(b.mediaType));
        return list;
    }
  }

  String get _sortLabel {
    switch (_sortBy) {
      case _SortBy.dateAdded:   return 'Date Added';
      case _SortBy.alphabetical: return 'A–Z';
      case _SortBy.rating:      return 'Rating';
      case _SortBy.type:        return 'Type';
    }
  }

  void _showSortSheet() {
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
          Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                  color: t.textMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Text('Sort By', style: TextStyle(color: t.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 4),
          ..._SortBy.values.map((s) {
            final selected = _sortBy == s;
            final labels = {
              _SortBy.dateAdded:    ('Date Added',    AppIcons.clock),
              _SortBy.alphabetical: ('A–Z',           AppIcons.sort),
              _SortBy.rating:       ('Highest Rating', AppIcons.starFill),
              _SortBy.type:         ('Type',           AppIcons.category),
            };
            final (label, icon) = labels[s]!;
            return ListTile(
              leading: Icon(icon,
                  color: selected ? context.signalPrimary : t.textMuted, size: 20),
              title: Text(label,
                  style: TextStyle(
                    color: selected ? context.signalPrimary : t.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 14,
                  )),
              trailing: selected
                  ? Icon(AppIcons.check, color: context.signalPrimary, size: 18)
                  : null,
              onTap: () {
                setState(() => _sortBy = s);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final state = ref.watch(watchlistProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.back, color: t.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('My Watchlist',
            style: TextStyle(color: t.textPrimary,
                fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          if (state.items.isNotEmpty) ...[
            // Sort button
            GestureDetector(
              onTap: _showSortSheet,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                  border: Border.all(color: t.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(AppIcons.sort, size: 15,
                      color: context.signalPrimary),
                  const SizedBox(width: 4),
                  Text(_sortLabel,
                      style: TextStyle(color: context.signalPrimary,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            // Count badge
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.signalPrimary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${state.items.length}',
                      style: TextStyle(color: context.signalPrimary,
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ],
      ),
      body: state.loading
          ? Center(child: CircularProgressIndicator(color: context.signalPrimary))
          : state.items.isEmpty
              ? _buildEmpty(context)
              : _buildGrid(context, ref, _sorted(state.items)),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final t = RaddTheme.of(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: t.surface, shape: BoxShape.circle,
            border: Border.all(color: t.border),
          ),
          child: Icon(AppIcons.bookmark,
              color: t.textMuted, size: 36),
        ),
        const SizedBox(height: 20),
        Text('Your Watchlist is Empty',
            style: TextStyle(color: t.textPrimary,
                fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Tap the bookmark icon on any\nmovie or show to save it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.5)),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () => Navigator.of(context)
              .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: context.signalPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Browse Content',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildGrid(
      BuildContext context, WidgetRef ref, List<CatalogItem> items) {
    final t = RaddTheme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2 / 3,
        crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        return Stack(children: [
          ContentCard(item: items[i])
              .animate(delay: (i * 30).ms)
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.9, 0.9),
                  end: const Offset(1, 1), duration: 300.ms),
          Positioned(
            top: 4, right: 4,
            child: GestureDetector(
              onTap: () async => await ref
                  .read(watchlistProvider.notifier)
                  .toggle(items[i]),
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: t.bg.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.close,
                    color: t.textMuted, size: 15),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
