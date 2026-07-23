// lib/screens/onboarding_screen.dart
//
// Volume V — 3-step reciprocity onboarding flow. Replaces the old generic
// PageView marketing carousel. Steps: genre taste capture → starter
// watchlist build → save/signup. Progress bar opens at ~25% (never 0%) —
// deliberate "goal gradient" behavioral cue, not a bug.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../design_system/components/radd_button.dart';
import '../design_system/components/radd_chip.dart';
import '../design_system/components/radd_card.dart';
import '../design_system/motion/radd_motion.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/typography/radd_type.dart';
import '../models/catalog_item.dart';

const List<String> _kOnboardingGenres = [
  'Action',
  'Drama',
  'Comedy',
  'Romance',
  'Thriller',
  'Anime',
  'Urdu Dubbed',
  'Kids',
  'Sports',
  'Horror',
];

// Step progress never starts at 0% — step 0 opens at 25% (goal-gradient effect).
const List<double> _kStepProgress = [0.25, 0.60, 1.0];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final Set<String> _selectedGenres = {};
  List<CatalogItem> _candidateItems = [];
  final Set<int> _selectedItemIds = {};
  bool _loadingCandidates = false;

  Future<void> _loadCandidates() async {
    if (_selectedGenres.isEmpty) {
      setState(() => _candidateItems = []);
      return;
    }
    setState(() => _loadingCandidates = true);
    try {
      final genres = _selectedGenres.take(3).toList();
      final seen = <int>{};
      final results = <CatalogItem>[];
      for (final genre in genres) {
        final found = await LocalDb.searchAdvanced(genre: genre, limit: 6);
        for (final r in found) {
          if (seen.add(r.item.id)) results.add(r.item);
        }
      }
      if (!mounted) return;
      setState(() {
        _candidateItems = results.take(18).toList();
        _loadingCandidates = false;
      });
    } catch (_) {
      // DB failure — clear the spinner so the user is not stuck.
      if (mounted) setState(() { _candidateItems = []; _loadingCandidates = false; });
    }
  }

  Future<void> _goToStep(int step) async {
    if (step == 1) await _loadCandidates();
    setState(() => _step = step);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _selectedItemIds.map((id) => id.toString()).toList();
    await prefs.setStringList(AppConstants.onboardingPendingItemsKey, ids);
    await prefs.setBool(AppConstants.onboardingSeenKey, true);
    if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: RaddMotion.sheetEnterDuration,
                switchInCurve: RaddMotion.sheetEnter,
                switchOutCurve: RaddMotion.sheetExit,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    0 => _GenreStep(
                        selected: _selectedGenres,
                        onToggle: (g) => setState(() {
                          _selectedGenres.contains(g)
                              ? _selectedGenres.remove(g)
                              : _selectedGenres.add(g);
                        }),
                      ),
                    1 => _WatchlistStep(
                        items: _candidateItems,
                        loading: _loadingCandidates,
                        selectedIds: _selectedItemIds,
                        onToggle: (id) => setState(() {
                          _selectedItemIds.contains(id)
                              ? _selectedItemIds.remove(id)
                              : _selectedItemIds.add(id);
                        }),
                      ),
                    _ => _SummaryStep(
                        items: _candidateItems
                            .where((i) => _selectedItemIds.contains(i.id))
                            .toList(),
                      ),
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  RaddSpace.lg, 0, RaddSpace.lg, RaddSpace.lg),
              child: _buildCta(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final t = RaddTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(RaddSpace.lg, RaddSpace.md, RaddSpace.lg, RaddSpace.lg),
      child: ClipRRect(
        borderRadius: RaddRadius.pillRadius,
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Container(color: t.glass),
              AnimatedFractionallySizedBox(
                duration: RaddMotion.sheetEnterDuration,
                curve: RaddMotion.sheetEnter,
                widthFactor: _kStepProgress[_step],
                alignment: Alignment.centerLeft,
                child: Container(color: context.signalPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCta(RaddTheme t) {
    final isLast = _step == 2;
    final canAdvance = _step == 0 ? _selectedGenres.isNotEmpty : true;
    final label = isLast ? 'Save & Continue' : 'Continue';
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: canAdvance ? context.signalPrimary : t.glass,
        borderRadius: RaddRadius.mdRadius,
        child: InkWell(
          borderRadius: RaddRadius.mdRadius,
          onTap: !canAdvance
              ? null
              : () {
                  if (isLast) {
                    _finish();
                  } else {
                    _goToStep(_step + 1);
                  }
                },
          child: Center(
            child: Text(
              label,
              style: context.raddBodyStrong.copyWith(
                color: canAdvance ? Colors.white : t.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreStep extends StatelessWidget {
  final Set<String> selected;
  final void Function(String) onToggle;
  const _GenreStep({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: RaddSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: RaddSpace.lg),
          Text('What do you like to watch?', style: context.raddHeadline),
          SizedBox(height: RaddSpace.sm),
          Text(
            'Pick as many as you want — we\'ll use this to build your starter watchlist.',
            style: context.raddBody.copyWith(color: context.t.textMuted),
          ),
          SizedBox(height: RaddSpace.xl),
          Wrap(
            spacing: RaddSpace.sm,
            runSpacing: RaddSpace.sm,
            children: _kOnboardingGenres
                .map((g) => RaddChip(
                      label: g,
                      active: selected.contains(g),
                      onTap: () => onToggle(g),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _WatchlistStep extends StatelessWidget {
  final List<CatalogItem> items;
  final bool loading;
  final Set<int> selectedIds;
  final void Function(int) onToggle;
  const _WatchlistStep({
    required this.items,
    required this.loading,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: context.signalPrimary),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(RaddSpace.lg, RaddSpace.lg, RaddSpace.lg, RaddSpace.sm),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a few to start with', style: context.raddHeadline),
                SizedBox(height: RaddSpace.sm),
                Text(
                  'Tap the titles you\'re excited about — they\'ll be waiting in your watchlist.',
                  style: context.raddBody.copyWith(color: context.t.textMuted),
                ),
                SizedBox(height: RaddSpace.md),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(RaddSpace.lg),
              child: Text(
                'No matches yet — you can still continue and explore later.',
                style: context.raddBody.copyWith(color: context.t.textMuted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: RaddSpace.lg),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = items[i];
                  final selected = selectedIds.contains(item.id);
                  return Stack(
                    children: [
                      RaddCard(
                        variant: RaddCardVariant.compact,
                        imageUrl: item.posterUrl ?? '',
                        isDataFree: item.isFree,
                        onTap: () => onToggle(item.id),
                      ),
                      if (selected)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: RaddRadius.mdRadius,
                                border: Border.all(
                                  color: context.signalPrimary,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (selected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: context.signalPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: RaddSpace.xl)),
      ],
    );
  }
}

class _SummaryStep extends StatelessWidget {
  final List<CatalogItem> items;
  const _SummaryStep({required this.items});

  @override
  Widget build(BuildContext context) {
    final shown = items.take(5).toList();
    final extra = items.length - shown.length;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: RaddSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: RaddSpace.lg),
          Text('Your watchlist is ready', style: context.raddHeadline),
          SizedBox(height: RaddSpace.sm),
          Text(
            shown.isEmpty
                ? 'You can build your watchlist anytime from the home screen.'
                : 'These are saved and waiting for you right after you sign up.',
            style: context.raddBody.copyWith(color: context.t.textMuted),
          ),
          SizedBox(height: RaddSpace.xl),
          if (shown.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shown.length,
                separatorBuilder: (_, __) => SizedBox(width: RaddSpace.sm),
                itemBuilder: (context, i) => SizedBox(
                  width: 120,
                  child: RaddCard(
                    variant: RaddCardVariant.compact,
                    imageUrl: shown[i].posterUrl ?? '',
                    isDataFree: shown[i].isFree,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          if (extra > 0) ...[
            SizedBox(height: RaddSpace.sm),
            Text('+ $extra more', style: context.raddLabel.copyWith(color: context.t.textMuted)),
          ],
        ],
      ),
    );
  }
}
