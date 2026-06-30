import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../core/debug/debug_logger.dart';
import '../providers/catalog_provider.dart';
import '../models/catalog_item.dart';
import '../widgets/content_card.dart';
import '../core/utils/anim_config.dart';
import 'package:animations/animations.dart';
import 'show_detail_screen.dart';

// ── Filter state ─────────────────────────────────────────────────────────────
class _FilterState {
  final String? type;       // null | 'Movies' | 'Shows'
  final String? genre;
  final int?    year;
  final String? language;
  final double? minRating;  // null | 6 | 7 | 8 | 9
  final bool?   isFree;     // null=any | true=free | false=premium
  final String? status;     // null | 'ongoing' | 'completed' | 'released'
  final bool    offlineOnly;
  final String  sortBy;     // 'relevance'|'rating'|'year_desc'|'year_asc'|'title'

  const _FilterState({
    this.type,
    this.genre,
    this.year,
    this.language,
    this.minRating,
    this.isFree,
    this.status,
    this.offlineOnly = false,
    this.sortBy = 'relevance',
  });

  _FilterState copyWith({
    Object? type      = _sentinel,
    Object? genre     = _sentinel,
    Object? year      = _sentinel,
    Object? language  = _sentinel,
    Object? minRating = _sentinel,
    Object? isFree    = _sentinel,
    Object? status    = _sentinel,
    bool?   offlineOnly,
    String? sortBy,
  }) => _FilterState(
    type:        type      == _sentinel ? this.type       : type      as String?,
    genre:       genre     == _sentinel ? this.genre      : genre     as String?,
    year:        year      == _sentinel ? this.year       : year      as int?,
    language:    language  == _sentinel ? this.language   : language  as String?,
    minRating:   minRating == _sentinel ? this.minRating  : minRating as double?,
    isFree:      isFree    == _sentinel ? this.isFree     : isFree    as bool?,
    status:      status    == _sentinel ? this.status     : status    as String?,
    offlineOnly: offlineOnly ?? this.offlineOnly,
    sortBy:      sortBy    ?? this.sortBy,
  );

  bool get hasAny =>
      type != null || genre != null || year != null || language != null ||
      minRating != null || isFree != null || status != null || offlineOnly ||
      sortBy != 'relevance';

  int get activeCount {
    int n = 0;
    if (type      != null) n++;
    if (genre     != null) n++;
    if (year      != null) n++;
    if (language  != null) n++;
    if (minRating != null) n++;
    if (isFree    != null) n++;
    if (status    != null) n++;
    if (offlineOnly)       n++;
    if (sortBy != 'relevance') n++;
    return n;
  }

  _FilterState clear() => const _FilterState();
}

const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  RaddTheme get t => RaddTheme.of(context);

  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<SearchResult>? _results;
  String? _searchError; // M-03: expose search errors to user
  bool _loading = false;
  List<String> _history = [];
  bool _showFilters = false;

  _FilterState _filters = const _FilterState();

  // Meta for filter dropdowns (loaded once from DB)
  List<String> _availLanguages = [];
  List<int>    _availYears     = [];
  List<String> _availGenres    = [];

  // Focus glow
  late final AnimationController _glowCtrl;
  late final Animation<double>   _glowAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('SearchScreen', 'initState');
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut);
    _focus.addListener(() {
      if (_focus.hasFocus) _glowCtrl.forward(); else _glowCtrl.reverse();
    });
    _loadHistory();
    _loadFilterMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final f = args?['initialFilter'] as String?;
      if (f != null && f != 'All' && mounted) {
        setState(() => _filters = _filters.copyWith(type: f));
        // FIX-SEARCH-INIT: trigger search immediately so results appear
        // with the filter applied, not waiting for user to type.
        _doSearch();
      }
    });
  }

  @override
  void dispose() {
    DebugLogger.logLifecycle('SearchScreen', 'dispose query="${_ctrl.text}"');
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── Meta loaders ──────────────────────────────────────────────────────────

  Future<void> _loadFilterMeta() async {
    final [langs, years] = await Future.wait([
      LocalDb.getDistinctLanguages(),
      LocalDb.getDistinctYears(),
    ]);
    final catalog  = ref.read(catalogProvider);
    final allItems = [...catalog.movies, ...catalog.shows];
    final genres   = _extractGenres(allItems);
    if (mounted) setState(() {
      _availLanguages = langs as List<String>;
      _availYears     = years as List<int>;
      _availGenres    = genres;
    });
  }

  // ── History ────────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(StorageKeys.searchHistory) ?? [];
    if (mounted) setState(() => _history = raw);
  }

  Future<void> _saveToHistory(String q) async {
    if (q.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = [q, ..._history.where((h) => h != q)].take(10).toList();
    await prefs.setStringList(StorageKeys.searchHistory, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _removeFromHistory(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _history.where((h) => h != q).toList();
    await prefs.setStringList(StorageKeys.searchHistory, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.searchHistory);
    if (mounted) setState(() => _history = []);
  }

  // ── Search logic ──────────────────────────────────────────────────────────

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    setState(() {});
    final _dQ = q;
    _debounce = Timer(const Duration(milliseconds: 220), () {
      DebugLogger.logTap('Search', 'query "${_dQ}"');
      _doSearch();
    });
  }

  Future<void> _doSearch() async {
    if (!mounted) return;
    setState(() { _loading = true; _searchError = null; });
    try {
      final f = _filters;
      // Apply type filter via media_type — we do it in Dart after DB call for simplicity
      // because advanced search returns all types; type filter is a fast Dart pass
      final raw = await LocalDb.searchAdvanced(
        query:       _ctrl.text.trim(),
        genre:       f.genre,
        year:        f.year,
        language:    f.language,
        minRating:   f.minRating,
        isFree:      f.isFree,
        status:      f.status,
        offlineOnly: f.offlineOnly,
        sortBy:      f.sortBy,
        limit:       200,
      );
      List<SearchResult> results = raw;
      if (f.type == 'Movies') results = raw.where((r) => r.item.isMovie).toList();
      if (f.type == 'Shows')  results = raw.where((r) => r.item.isShow).toList();

      if (mounted) setState(() { _results = results; _loading = false; });
      DebugLogger.log('SEARCH', 'results ${results.length} q="${_ctrl.text.trim()}" type=${f.type} genre=${f.genre} lang=${f.language}');
      if (_ctrl.text.trim().isNotEmpty) await _saveToHistory(_ctrl.text.trim());
    } catch (_) {
      if (mounted) setState(() { _results = []; _loading = false; });
    }
  }

  void _applyFilter(_FilterState f) {
    DebugLogger.logTap('Search', 'filter type=${f.type} genre=${f.genre} year=${f.year} lang=${f.language} rating=${f.minRating} free=${f.isFree}');
    setState(() => _filters = f);
    _doSearch();
  }

  void _clearAll() {
    DebugLogger.logTap('Search', 'clearFilters');
    setState(() { _filters = const _FilterState(); });
    if (_ctrl.text.trim().isNotEmpty) _doSearch();
    else setState(() => _results = null);
  }

  void _tapSuggestion(String q) {
    DebugLogger.logTap('Search', 'suggestion "$q"');
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _doSearch();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _extractGenres(List<CatalogItem> all) {
    final counts = <String, int>{};
    for (final item in all) {
      final raw = item.genres ?? '';
      List<String> parts;
      if (raw.trimLeft().startsWith('[')) {
        final inner = raw.trim().replaceAll(RegExp(r'^\[|\]$'), '');
        parts = inner.split(',').map((s) => s.trim().replaceAll('"', '').replaceAll("'", '')).toList();
      } else {
        parts = raw.split(',');
      }
      for (final g in parts) {
        final t = g.trim();
        if (t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(20).map((e) => e.key).toList();
  }

  Map<String, List<CatalogItem>> _byGenre(List<CatalogItem> all) {
    final map = <String, List<CatalogItem>>{};
    for (final genre in _availGenres.take(8)) {
      final items = all
          .where((i) => (i.genres ?? '').toLowerCase().contains(genre.toLowerCase()))
          .toList();
      if (items.length >= 2) map[genre] = items;
    }
    return map;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final catalog   = ref.watch(catalogProvider);
    final allItems  = [...catalog.movies, ...catalog.shows];
    final hasQuery  = _ctrl.text.isNotEmpty;
    final hasFilter = _filters.hasAny;
    final showResultsArea = hasQuery || hasFilter;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          _buildSearchBar(),
          _buildTypeRow(),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            child: _showFilters ? _buildFilterPanel() : const SizedBox.shrink(),
          ),
          if (_filters.hasAny)
            _buildActiveFilterBar(),
          const SizedBox(height: 4),
          Expanded(
            child: showResultsArea
                ? _buildResults()
                : _buildDiscover(allItems, catalog.trending),
          ),
        ]),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: t.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: Color.lerp(t.border, AppColors.primary, _glowAnim.value)!,
                  width: 1 + _glowAnim.value * 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.18 * _glowAnim.value),
                    blurRadius: 20, spreadRadius: -2),
                ],
              ),
              child: child,
            ),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loading
                      ? SizedBox(key: const ValueKey('spin'), width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.primary)))
                      : Icon(key: const ValueKey('icon'),
                          Icons.search_rounded, color: t.textMuted, size: 22),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  style: TextStyle(color: t.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search movies, dramas, shows…',
                    hintStyle: TextStyle(color: t.textMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: false,
                  ),
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.clear_rounded, size: 18, color: t.textMuted),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() { _results = null; _loading = false; });
                    _focus.requestFocus();
                  },
                ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        // Filter toggle button with badge
        GestureDetector(
          onTap: () => setState(() => _showFilters = !_showFilters),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _showFilters || _filters.hasAny
                  ? AppColors.primary.withOpacity(0.15)
                  : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _showFilters || _filters.hasAny ? AppColors.primary : t.border,
                width: _showFilters || _filters.hasAny ? 1.5 : 1,
              ),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.tune_rounded, size: 20,
                  color: _showFilters || _filters.hasAny ? AppColors.primary : t.textMuted),
              if (_filters.activeCount > 0)
                Positioned(
                  top: -6, right: -6,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${_filters.activeCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0, duration: 250.ms);
  }

  // ── Type chips (All / Movies / Shows) ──────────────────────────────────────

  Widget _buildTypeRow() {
    final types  = [null, 'Movies', 'Shows'];
    final labels = ['All', 'Movies', 'Shows'];
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        itemCount: types.length,
        itemBuilder: (_, i) {
          final active = _filters.type == types[i];
          return GestureDetector(
            onTap: () {
              _applyFilter(_filters.copyWith(type: types[i]));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                gradient: active ? AppColors.primaryGradient : null,
                color: active ? null : t.surface,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: active ? Colors.transparent : t.border),
                boxShadow: active ? AppShadows.primary : null,
              ),
              child: Text(labels[i], style: TextStyle(
                color: active ? Colors.white : t.textMuted,
                fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  // ── Expanded filter panel ──────────────────────────────────────────────────

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Row 1: Genre ─────────────────────────────────────────────────────
        if (_availGenres.isNotEmpty) ...[
          _filterLabel('Genre'),
          const SizedBox(height: 6),
          _chipWrap(_availGenres, (g) => _filters.genre == g, (g) {
            _applyFilter(_filters.copyWith(genre: _filters.genre == g ? null : g));
          }),
          const SizedBox(height: 12),
        ],

        // ── Row 2: Language ──────────────────────────────────────────────────
        if (_availLanguages.isNotEmpty) ...[
          _filterLabel('Language'),
          const SizedBox(height: 6),
          _chipWrap(_availLanguages, (l) => _filters.language == l, (l) {
            _applyFilter(_filters.copyWith(language: _filters.language == l ? null : l));
          }, capitalize: true),
          const SizedBox(height: 12),
        ],

        // ── Row 3: Rating ────────────────────────────────────────────────────
        _filterLabel('Min Rating'),
        const SizedBox(height: 6),
        Row(children: [null, 6.0, 7.0, 8.0, 9.0].map((r) {
          final active = _filters.minRating == r;
          return GestureDetector(
            onTap: () => _applyFilter(_filters.copyWith(minRating: active ? null : r)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.accent.withOpacity(0.18) : t.bg,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(
                  color: active ? AppColors.accent : t.border,
                  width: active ? 1.5 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (r != null) ...[
                  Icon(Icons.star_rounded, size: 13,
                      color: active ? AppColors.accent : t.textMuted),
                  const SizedBox(width: 3),
                ],
                Text(r == null ? 'Any' : '${r.toInt()}+',
                    style: TextStyle(
                      fontSize: 12,
                      color: active ? AppColors.accent : t.textMuted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
              ]),
            ),
          );
        }).toList()),
        const SizedBox(height: 12),

        // ── Row 4: Year ──────────────────────────────────────────────────────
        if (_availYears.isNotEmpty) ...[
          _filterLabel('Year'),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [null, ..._availYears.take(15)].map((y) {
                final active = _filters.year == y;
                return GestureDetector(
                  onTap: () => _applyFilter(_filters.copyWith(year: active ? null : y)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary.withOpacity(0.15) : t.bg,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                      border: Border.all(
                        color: active ? AppColors.primary : t.border,
                        width: active ? 1.5 : 1),
                    ),
                    child: Text(y == null ? 'Any Year' : '$y',
                        style: TextStyle(
                          fontSize: 12,
                          color: active ? AppColors.primary : t.textMuted,
                          fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Row 5: Status ────────────────────────────────────────────────────
        _filterLabel('Status'),
        const SizedBox(height: 6),
        _chipWrap(['Ongoing', 'Completed', 'Released'],
          (s) => _filters.status == s.toLowerCase(), (s) {
          final v = s.toLowerCase();
          _applyFilter(_filters.copyWith(status: _filters.status == v ? null : v));
        }),
        const SizedBox(height: 12),

        // ── Row 6: Free / Offline / Sort ─────────────────────────────────────
        Row(children: [
          // Free toggle
          _toggleChip(
            label: 'Free Only',
            icon: Icons.local_offer_rounded,
            active: _filters.isFree == true,
            color: Colors.green,
            onTap: () => _applyFilter(
              _filters.copyWith(isFree: _filters.isFree == true ? null : true)),
          ),
          const SizedBox(width: 8),
          // Premium toggle
          _toggleChip(
            label: 'Premium',
            icon: Icons.workspace_premium_rounded,
            active: _filters.isFree == false,
            color: AppColors.accent,
            onTap: () => _applyFilter(
              _filters.copyWith(isFree: _filters.isFree == false ? null : false)),
          ),
          const SizedBox(width: 8),
          // Offline toggle
          _toggleChip(
            label: 'Downloaded',
            icon: Icons.download_done_rounded,
            active: _filters.offlineOnly,
            color: AppColors.primary,
            onTap: () => _applyFilter(_filters.copyWith(offlineOnly: !_filters.offlineOnly)),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Sort ──────────────────────────────────────────────────────────────
        _filterLabel('Sort By'),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ['relevance', 'Best Match', Icons.auto_awesome_rounded],
            ['rating',    'Top Rated',  Icons.star_rounded],
            ['year_desc', 'Newest',     Icons.new_releases_rounded],
            ['year_asc',  'Oldest',     Icons.history_rounded],
            ['title',     'A–Z',        Icons.sort_by_alpha_rounded],
          ].map((s) {
            final val   = s[0] as String;
            final label = s[1] as String;
            final icon  = s[2] as IconData;
            final active = _filters.sortBy == val;
            return GestureDetector(
              onTap: () => _applyFilter(_filters.copyWith(sortBy: val)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: active ? AppColors.primaryGradient : null,
                  color: active ? null : t.bg,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                  border: Border.all(color: active ? Colors.transparent : t.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 13, color: active ? Colors.white : t.textMuted),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(
                    fontSize: 12, color: active ? Colors.white : t.textMuted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                ]),
              ),
            );
          }).toList()),
        ),
      ]),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.05, end: 0, duration: 180.ms);
  }

  // ── Active filter summary bar ──────────────────────────────────────────────

  Widget _buildActiveFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (_filters.type      != null) _activePill(_filters.type!),
              if (_filters.genre     != null) _activePill(_filters.genre!),
              if (_filters.language  != null) _activePill(_filters.language!),
              if (_filters.year      != null) _activePill('${_filters.year}'),
              if (_filters.minRating != null) _activePill('${_filters.minRating!.toInt()}+ ★'),
              if (_filters.isFree == true)    _activePill('Free'),
              if (_filters.isFree == false)   _activePill('Premium'),
              if (_filters.status    != null) _activePill(_filters.status!),
              if (_filters.offlineOnly)       _activePill('Downloaded'),
              if (_filters.sortBy != 'relevance') _activePill('Sort: ${_filters.sortBy}'),
            ]),
          ),
        ),
        GestureDetector(
          onTap: _clearAll,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('Clear all',
                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _activePill(String label) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primary.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppRadius.round),
      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(
        color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  // ── Results ────────────────────────────────────────────────────────────────

  Widget _buildResults() {
    // Phase 43: stagger; Phase 44: OpenContainer morph on Tier 2+
    final animConfig = ref.read(animConfigProvider);
    final canAnimate = animConfig.canStagger;
    final canMorph   = animConfig.canMorph;
    final t          = RaddTheme.of(context);
    if (_loading && (_results == null)) {
      return _buildShimmer();
    }
    final res = _results ?? [];
    if (res.isEmpty && !_loading) {
      return _buildEmpty();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (res.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Text('${res.length} result${res.length == 1 ? "" : "s"}',
              style: TextStyle(color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          itemCount: res.length,
          // Phase 44: Tier 2+ → OpenContainer morph; Tier 1 → stagger; Tier 0 → raw
          itemBuilder: (_, i) {
            final item = res[i].item;
            if (canMorph) {
              return OpenContainer<void>(
                closedColor: t.surface,
                openColor: t.bg,
                closedElevation: 0,
                openElevation: 0,
                transitionDuration: animConfig.slow,
                tappable: false,
                closedBuilder: (_, openFn) =>
                    _SearchResultTile(result: res[i], onTap: openFn),
                openBuilder: (_, __) => ShowDetailScreen(item: item),
              );
            }
            return canAnimate
                ? _SearchResultTile(result: res[i])
                    .animate(delay: animConfig.stagger(i))
                    .fadeIn(duration: animConfig.normal)
                    .slideX(begin: 0.07, end: 0, duration: animConfig.normal,
                        curve: Curves.easeOut)
                : _SearchResultTile(result: res[i]);
          },
        ),
      ),
    ]);
  }

  Widget _buildEmpty() {
    final hasQuery = _ctrl.text.isNotEmpty;
    final hasFilters = _filters.hasAny;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Illustrated icon container
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(color: t.border),
            ),
            child: Icon(
              hasQuery
                  ? Icons.search_off_rounded
                  : Icons.filter_alt_off_rounded,
              size: 36,
              color: t.textMuted.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery
                ? 'No results for'
                : 'No titles match',
            style: TextStyle(color: t.textMuted,
                fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (hasQuery) ...[
            const SizedBox(height: 2),
            Text(
              '“${_ctrl.text}”',
              style: TextStyle(color: t.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w800,
                  letterSpacing: -0.3),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else ...[
            const SizedBox(height: 2),
            Text('your current filters',
                style: TextStyle(color: t.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 16),
          // Suggestions
          if (hasQuery) ...[
            Text('Try a different title, actor name, or shorter keywords.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                _ctrl.clear();
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                  border: Border.all(color: t.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 14, color: t.textMuted),
                  const SizedBox(width: 6),
                  Text('Clear search',
                      style: TextStyle(color: t.textSecondary,
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
          if (hasFilters && !hasQuery) ...[
            Text('Try adjusting or removing some filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: _clearAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.round),
                  ),
                  child: const Text('Clear all filters',
                      style: TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ]).animate()
          .fadeIn(duration: 320.ms)
          .slideY(begin: 0.12, end: 0, duration: 320.ms, curve: Curves.easeOut),
      ),
    );
  }

  // ── Discover (no query, no filter) ────────────────────────────────────────

  Widget _buildDiscover(List<CatalogItem> allItems, List<CatalogItem> trending) {
    final byGenre = _byGenre(allItems);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [

        // ── Search history ─────────────────────────────────────────────────
        if (_history.isNotEmpty) ...[
          _sectionHeader('Recent', trailing: TextButton(
            onPressed: _clearHistory,
            child: Text('Clear', style: TextStyle(color: t.textMuted, fontSize: 12)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(spacing: 8, runSpacing: 6, children: _history.map((h) {
              return GestureDetector(
                onLongPress: () => _removeFromHistory(h),
                child: GestureDetector(
                  onTap: () => _tapSuggestion(h),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history_rounded, size: 14, color: t.textMuted),
                      const SizedBox(width: 5),
                      Text(h, style: TextStyle(color: t.textSecondary, fontSize: 13)),
                    ]),
                  ),
                ),
              );
            }).toList()),
          ),
          const SizedBox(height: 8),
        ],

        // ── Trending ───────────────────────────────────────────────────────
        if (trending.isNotEmpty) ...[
          _sectionHeader('Trending Now'),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount: trending.take(15).length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i < trending.length - 1 ? 10 : 0),
                child: SizedBox(width: 110, child: ContentCard(item: trending[i])),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Browse by genre ────────────────────────────────────────────────
        if (byGenre.isNotEmpty) ...[
          _sectionHeader('Browse by Genre'),
          ...byGenre.entries.map((e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: GestureDetector(
                  onTap: () {
                    _applyFilter(_filters.copyWith(genre: e.key));
                    if (!_showFilters) setState(() => _showFilters = true);
                  },
                  child: Row(children: [
                    Container(width: 3, height: 16,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(2))),
                    Text(e.key, style: TextStyle(
                        color: t.textPrimary, fontSize: 14,
                        fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppRadius.round),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Text('${e.value.length}', style: const TextStyle(
                          color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 18, color: t.textMuted),
                  ]),
                ),
              ),
              SizedBox(
                height: 175,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  itemCount: e.value.take(10).length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(right: i < e.value.length - 1 ? 10 : 0),
                    child: SizedBox(width: 106, child: ContentCard(item: e.value[i])),
                  ),
                ),
              ),
            ],
          )),
        ],
      ],
    );
  }

  // ── Shimmer ────────────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: t.surface,
      highlightColor: t.border,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            // Poster thumbnail area
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.md)),
              child: Container(
                width: 56, height: 80, color: t.surfaceHigh)),
            const SizedBox(width: 14),
            // Text placeholder lines
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, width: double.infinity,
                    decoration: BoxDecoration(color: t.surfaceHigh,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 7),
                Container(height: 10, width: 110,
                    decoration: BoxDecoration(color: t.surfaceHigh,
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 5),
                Container(height: 8, width: 75,
                    decoration: BoxDecoration(color: t.surfaceHigh,
                        borderRadius: BorderRadius.circular(3))),
              ],
            )),
            const SizedBox(width: 16),
          ]),
        ),
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _filterLabel(String label) => Text(label,
      style: TextStyle(color: t.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.6));

  Widget _chipWrap(List<String> items, bool Function(String) isActive,
      void Function(String) onTap, {bool capitalize = false}) {
    return Wrap(spacing: 8, runSpacing: 6, children: items.map((item) {
      final active = isActive(item);
      final label  = capitalize
          ? item.substring(0, 1).toUpperCase() + item.substring(1)
          : item;
      return GestureDetector(
        onTap: () => onTap(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: active ? AppColors.primaryGradient : null,
            color: active ? null : t.bg,
            borderRadius: BorderRadius.circular(AppRadius.round),
            border: Border.all(color: active ? Colors.transparent : t.border),
            boxShadow: active ? [BoxShadow(
                color: AppColors.primary.withOpacity(0.3), blurRadius: 8)] : null,
          ),
          child: Text(label, style: TextStyle(
              color: active ? Colors.white : t.textMuted,
              fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
    }).toList());
  }

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : t.bg,
        borderRadius: BorderRadius.circular(AppRadius.round),
        border: Border.all(color: active ? color : t.border, width: active ? 1.5 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: active ? color : t.textMuted),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          fontSize: 12, color: active ? color : t.textMuted,
          fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ]),
    ),
  );

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Row(children: [
      Text(title, style: TextStyle(
          color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
      const Spacer(),
      if (trailing != null) trailing,
    ]),
  );
}

// ── Search result tile with snippet ──────────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  // Phase 44: optional override — OpenContainer passes openFn here on Tier 2+
  final VoidCallback? onTap;
  const _SearchResultTile({required this.result, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t    = RaddTheme.of(context);
    final item = result.item;

    // Parse snippet: FTS5 marks matches with [ ] — we render them highlighted
    final rawSnippet = result.snippet;
    final hasSnippet = rawSnippet != null && rawSnippet.isNotEmpty;

    return GestureDetector(
      // Phase 44: if onTap provided (OpenContainer), use it; otherwise default push
      onTap: onTap ?? () {
        DebugLogger.logTap('Search', 'result id=${item.id} "${item.title}"');
        Navigator.of(context).pushNamed(AppRoutes.showDetail, arguments: item);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: t.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Poster — Hero tag matches home grid and show_detail banner (Phase 42)
          Hero(
            tag: 'poster_${item.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: _buildPoster(item, t),
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  style: TextStyle(color: t.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.w700),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              // Metadata row
              Wrap(spacing: 6, runSpacing: 2, children: [
                if (item.year != null)
                  _metaTag('${item.year}', t, color: t.textMuted),
                if (item.language != null && item.language!.isNotEmpty)
                  _metaTag(item.language!.toUpperCase(), t,
                      color: AppColors.accent, border: true),
                if (item.rating != null && item.rating! > 0)
                  _metaTag('★ ${item.rating!.toStringAsFixed(1)}', t,
                      color: Colors.amber[700]!),
                if (item.isFree)
                  _metaTag('FREE', t, color: Colors.green, border: true),
                _metaTag(item.isMovie ? 'Movie' : 'Show', t,
                    color: t.textMuted),
                if (item.statusLabel.isNotEmpty && item.statusLabel != 'Released')
                  _metaTag(item.statusLabel, t,
                      color: item.isOngoing == true ? Colors.blue : t.textMuted),
              ]),
              // Description snippet (highlighted matches)
              if (hasSnippet) ...[
                const SizedBox(height: 5),
                _SnippetText(raw: rawSnippet!, textStyle: TextStyle(
                    color: t.textMuted, fontSize: 12, height: 1.4)),
              ] else if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(item.description!,
                    style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPoster(CatalogItem item, RaddTheme t) {
    const w = 64.0; const h = 90.0;
    // Local cached poster first (zero network, works offline)
    if (item.posterPath != null && item.posterPath!.isNotEmpty) {
      final f = File(item.posterPath!);
      if (f.existsSync()) {
        return Image.file(f, width: w, height: h, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildNetworkPosterSR(item, t, w, h));
      }
    }
    return _buildNetworkPosterSR(item, t, w, h);
  }

  Widget _buildNetworkPosterSR(CatalogItem item, RaddTheme t, double w, double h) {
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.posterUrl!,
        width: w, height: h, fit: BoxFit.cover,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: t.card, highlightColor: t.surfaceHigh,
          child: Container(width: w, height: h, color: t.card)),
        errorWidget: (_, __, ___) => _posterPlaceholder(item, t, w, h),
      );
    }
    return _posterPlaceholder(item, t, w, h);
  }

  Widget _posterPlaceholder(CatalogItem item, RaddTheme t, double w, double h) =>
      Container(
        width: w, height: h,
        color: t.bg,
        child: Center(child: Icon(
            item.isMovie ? Icons.movie_outlined : Icons.tv_outlined,
            color: t.textMuted, size: 28)),
      );

  Widget _metaTag(String label, RaddTheme t, {Color? color, bool border = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: (color ?? t.textMuted).withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: border ? Border.all(color: (color ?? t.textMuted).withOpacity(0.4)) : null,
        ),
        child: Text(label, style: TextStyle(
            color: color ?? t.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

// ── Snippet renderer: [ and ] around matched tokens → highlighted ─────────────

class _SnippetText extends StatelessWidget {
  final String raw;
  final TextStyle textStyle;
  const _SnippetText({required this.raw, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\[([^\]]*)\]');
    int cursor = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, m.start), style: textStyle));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: textStyle.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: AppColors.primary.withOpacity(0.12),
        ),
      ));
      cursor = m.end;
    }
    if (cursor < raw.length) {
      spans.add(TextSpan(text: raw.substring(cursor), style: textStyle));
    }
    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

