import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/animated_empty_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../providers/downloads_provider.dart';
import '../core/debug/debug_logger.dart';
import '../core/utils/episode_title_parser.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/download/download_storage_strip.dart';
import '../widgets/download/active_download_ticker.dart';
import '../services/thumb_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/vault_service.dart';
import '../core/utils/anim_config.dart';
import 'season_folder_screen.dart';

enum _SortMode { name, size, date }
enum _Section { all, movies, tv }
enum _ViewMode { grid, list }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  RaddTheme get t => RaddTheme.of(context);

  _SortMode _sort    = _SortMode.date;
  _Section  _section = _Section.all;
  _ViewMode _view    = _ViewMode.grid;
  bool _selecting    = false;
  final Set<String> _selected = {};

  // Phase-40: disk space display + offline banner
  double? _freeMB;
  bool    _isOnline = true;

  static const _kPrefsSort    = 'dl_sort_v2';
  static const _kPrefsSection = 'dl_section_v1';
  static const _kPrefsView    = 'dl_view_v2';

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('DownloadsScreen', 'initState');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(downloadsProvider.notifier).loadDownloads();
      await _loadPrefs();
      _refreshDiskSpace();
      _checkConnectivity();
    });
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sort    = _SortMode.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsSort) ?? ''), orElse: () => _SortMode.date);
      _section = _Section.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsSection) ?? ''), orElse: () => _Section.all);
      _view    = _ViewMode.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsView) ?? ''), orElse: () => _ViewMode.grid);
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsSort,    _sort.name);
    await p.setString(_kPrefsSection, _section.name);
    await p.setString(_kPrefsView,    _view.name);
  }

  void _refreshDiskSpace() {
    DiskSpacePlus.getFreeDiskSpace.then((mb) {
      if (mounted && mb != null) setState(() => _freeMB = mb);
    }).ignore();
  }

  Future<void> _checkConnectivity() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOnline = r != ConnectivityResult.none);
    } catch (_) {}
  }

  // ── Helpers on raw Map ────────────────────────────────────────────────────
  String _id(Map m)       => m['file_id']    as String? ?? '';
  String _title(Map m)    => m['title_text'] as String? ?? 'Unknown';
  String _path(Map m)     => m['local_path'] as String? ?? '';
  String _status(Map m)   => m['status']     as String? ?? 'pending';
  double _progress(Map m) => (m['progress']  as num?)?.toDouble() ?? 0.0;
  int    _size(Map m)     => m['file_size']  as int? ?? 0;
  int    _date(Map m)     => m['downloaded_at'] as int? ?? 0;

  // NOTE: downloaded content is intentionally always playable regardless of the
  // user's current subscription status (matches show_detail_screen.dart and
  // player_screen.dart, which bypass subscription checks for local/downloaded
  // files). A previous `_isSubExpired()` gate here was dead code that was never
  // wired into any tap handler — removed to avoid confusing future edits into
  // thinking downloads are subscription-gated.

  bool _isComplete(Map m)    => _status(m) == 'completed';
  bool _isDownloading(Map m) => _status(m) == 'downloading' || _status(m) == 'pending';
  bool _isFailed(Map m)      => _status(m) == 'failed';

  String _fmtSize(int bytes) {
    if (bytes == 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// DOWNLOAD-TAB-V2: only two buckets now — Movies stay flat, everything
  /// else (shows, anime, dramas, cartoons…) is grouped under TV Shows by
  /// show → season. No more separate "Dramas"/"Other" folders.
  bool _isMovie(Map m) {
    final ct = m['content_type'] as String?;
    if (ct == 'movie') return true;
    if (ct == 'show' || ct == 'series' || ct == 'tv' ||
        ct == 'anime' || ct == 'cartoon' || ct == 'donghua' || ct == 'drama') return false;
    // Fallback heuristic on title when content_type wasn't recorded.
    final title = _title(m).toLowerCase();
    if (title.contains('episode') || title.contains('season') ||
        title.contains(' s0') || title.contains('ep ') ||
        title.contains('series') || title.contains('show') ||
        title.contains('drama')) return false;
    return true;
  }

  /// Poster URL stored at download time (may be null/empty).
  String? _posterUrl(Map m) => m['poster_url'] as String?;

  List<Map<String, dynamic>> _applySort(List<Map<String, dynamic>> items) {
    final copy = [...items];
    switch (_sort) {
      case _SortMode.name: copy.sort((a, b) => _title(a).compareTo(_title(b)));
      case _SortMode.size: copy.sort((a, b) => _size(b).compareTo(_size(a)));
      case _SortMode.date: copy.sort((a, b) => _date(b).compareTo(_date(a)));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final state = ref.watch(downloadsProvider);

    // Show a SnackBar when a download finishes in the background.
    ref.listen(
      downloadsProvider.select((s) => s.recentlyCompleted),
      (_, next) {
        if (next.isEmpty) return;
        ref.read(downloadsProvider.notifier).clearRecentlyCompleted();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            // Phase 45 ANIM-45-05: shake+scale burst on download completion
            Icon(AppIcons.downloadDone, color: Colors.white, size: 18)
                .animate()
                .shake(duration: 400.ms)
                .scale(begin: const Offset(1.0, 1.0),
                       end: const Offset(1.15, 1.15), duration: 200.ms),
            const SizedBox(width: 10),
            Expanded(child: Text('Downloaded: ${next.last}',
                overflow: TextOverflow.ellipsis)),
          ]),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ));
      },
    );
    return Scaffold(
      backgroundColor: null,
      appBar: _buildAppBar(state),
      bottomNavigationBar: RaddFlixBottomNav(
        currentIndex: 3,
        onTap: (i) {
          if (i == 3) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          if (i == 1) Navigator.of(context).pushNamed(AppRoutes.search);
          else if (i == 2) Navigator.of(context).pushNamed(AppRoutes.localMedia);
          else if (i == 4) Navigator.of(context).pushNamed(AppRoutes.profile);
        },
      ),
      body: Column(children: [
        if (!_isOnline) _buildOfflineBanner(),
        DownloadStorageStrip(
          totalBytes:     state.downloads.fold<int>(0, (s, d) => s + _size(d)),
          completedCount: state.downloads.where(_isComplete).length,
          totalCount:     state.downloads.length,
          activeCount:    state.downloads.where(_isDownloading).length,
          freeMB:         _freeMB,
        ),
        ActiveDownloadTicker(
          state: state,
          titleFor: (id) {
            final d = state.downloads.firstWhere((d) => _id(d) == id, orElse: () => {});
            return _title(d);
          },
          onCancel: (id) => () => ref.read(downloadsProvider.notifier).cancelDownload(id).ignore(),
        ),
        _buildSectionRow(),
        const Divider(height: 1),
        Expanded(child: state.loading
            ? _buildLoadingShimmer()
            : state.downloads.isEmpty
                ? _buildEmpty()
                : _buildContent(state)),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(DownloadsState state) {
    return AppBar(
      backgroundColor: t.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: _selecting
          ? Text('${_selected.length} selected',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
          : const Text('Download', style: TextStyle(fontWeight: FontWeight.w800)),
      leading: _selecting
          ? IconButton(
              icon: Icon(AppIcons.close, size: 20),
              onPressed: () => setState(() { _selecting = false; _selected.clear(); }),
            )
          : null,
      automaticallyImplyLeading: false,
      actions: [
        if (_selecting) ...[
          TextButton(
            onPressed: () => setState(() => _selected.addAll(state.downloads.map((d) => _id(d)))),
            child: const Text('All'),
          ),
          IconButton(
            icon: Icon(AppIcons.lock, color: AppColors.primary),
            tooltip: 'Add to Vault',
            onPressed: _selected.isEmpty ? null : _addSelectedToVault,
          ),
          IconButton(
            icon: Icon(AppIcons.trash, color: AppColors.error),
            onPressed: _selected.isEmpty ? null : () => _bulkDelete(),
          ),
        ] else ...[
          IconButton(
            icon: Icon(_view == _ViewMode.grid ? AppIcons.listView : AppIcons.gridView),
            onPressed: () { setState(() => _view = _view == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid); _savePrefs(); },
            tooltip: 'Toggle view',
          ),
          PopupMenuButton<_SortMode>(
            icon: Icon(AppIcons.sort),
            tooltip: 'Sort',
            onSelected: (s) { setState(() => _sort = s); _savePrefs(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: _SortMode.date, child: Text('By Date')),
              const PopupMenuItem(value: _SortMode.name, child: Text('By Name')),
              const PopupMenuItem(value: _SortMode.size, child: Text('By Size')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(AppIcons.wifiOff, size: 16, color: AppColors.error),
        const SizedBox(width: RaddSpace.sm),
        const Expanded(child: Text('You are offline. Downloads are paused.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        GestureDetector(
          onTap: _checkConnectivity,
          child: Icon(AppIcons.refresh, size: 16, color: AppColors.error),
        ),
      ]),
    );
  }

  Widget _buildSectionRow() {
    final labels = {_Section.all: 'All', _Section.movies: 'Movies', _Section.tv: 'TV Shows'};
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: _Section.values.map((s) {
          final selected = _section == s;
          return GestureDetector(
            onTap: () { setState(() => _section = s); _savePrefs(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                color: selected ? null : t.surface,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: selected ? Colors.transparent : t.border),
                boxShadow: selected ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 10, offset: const Offset(0,3))] : null,
              ),
              child: Text(labels[s]!, style: TextStyle(
                  color: selected ? Colors.white : t.textMuted,
                  fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return GridView.builder(
      padding: EdgeInsets.all(RaddSpace.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: 6,
      itemBuilder: (_, __) => RepaintBoundary(
        child: Shimmer.fromColors(
          baseColor: t.surface, highlightColor: t.surfaceHigh,
          child: Container(decoration: BoxDecoration(color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm))))),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Animated download icon
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.surface,
              border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1.5),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withOpacity(0.08),
                    blurRadius: 24, spreadRadius: 4),
              ],
            ),
            child: Center(
              child: AnimatedCloudDownIcon(size: 52, color: AppColors.primary.withOpacity(0.75)),
            ),
          ),
          const SizedBox(height: RaddSpace.lg),
          Text('No Downloads Yet',
              style: TextStyle(color: t.textPrimary,
                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: RaddSpace.sm),
          Text(
            'Save movies and shows to watch offline — no internet needed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          // Feature pills
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _FeaturePill(icon: AppIcons.wifiOff, label: 'Works offline', t: t),
            const SizedBox(width: RaddSpace.sm),
            _FeaturePill(icon: AppIcons.lightning, label: 'Fast resume', t: t),
          ]),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.round),
                boxShadow: AppShadows.primary,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(AppIcons.gridView, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('Browse Content', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
          ),
        ]).animate().fadeIn(duration: 400.ms),
      ),
    );
  }

  /// DOWNLOAD-TAB-V2 main content: Movies flat grid/list + TV Shows grouped
  /// by show, both scrollable in one CustomScrollView. Section pill filter
  /// (_section) hides whichever bucket isn't wanted.
  Widget _buildContent(DownloadsState state) {
    final movies = _applySort(state.downloads.where(_isMovie).toList());
    final tvItems = state.downloads.where((d) => !_isMovie(d)).toList();

    final showGroups = <String, List<Map<String, dynamic>>>{};
    for (final d in tvItems) {
      final info = parseEpisodeTitle(_title(d));
      showGroups.putIfAbsent(info.showTitle, () => []).add(d);
    }
    final showNames = showGroups.keys.toList()..sort();

    final showMovies = _section != _Section.tv;
    final showTv     = _section != _Section.movies;

    if ((!showMovies || movies.isEmpty) && (!showTv || showNames.isEmpty)) {
      return Center(child: Text(
          _section == _Section.movies ? 'No movie downloads yet'
              : _section == _Section.tv ? 'No TV show downloads yet'
              : 'No downloads yet',
          style: TextStyle(color: t.textMuted)));
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (showMovies && movies.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('Movies', movies.length)),
          _view == _ViewMode.grid
              ? _moviesGrid(movies, state)
              : _moviesList(movies, state),
        ],
        if (showTv && showNames.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader('TV Shows', showNames.length)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) {
                final show = showNames[i];
                final eps  = showGroups[show]!;
                return _ShowSummaryCard(
                  showName: show,
                  episodes: eps,
                  isComplete: _isComplete,
                  isDownloading: _isDownloading,
                  sizeOf: _size,
                  posterUrl: _posterUrl(eps.first),
                  fmtSize: _fmtSize,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SeasonFolderScreen(showName: show))),
                ).animate(delay: (i * 40).ms).fadeIn(duration: 280.ms);
              },
              childCount: showNames.length,
            )),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Row(children: [
      Icon(label == 'Movies' ? AppIcons.movieFill : AppIcons.liveTv,
          size: 16, color: AppColors.primary),
      const SizedBox(width: 6),
      Text('$label ($count)', style: TextStyle(
          color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
    ]),
  );

  SliverGrid _moviesGrid(List<Map<String, dynamic>> items, DownloadsState state) {
    final animConfig = ref.read(animConfigProvider);
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final d = items[i];
          final id = _id(d);
          final liveProgress = state.activeProgress[id];
          final isActive = liveProgress != null;
          return Padding(
            padding: EdgeInsets.only(
                left: i.isEven ? 16 : 0, right: i.isOdd ? 16 : 0,
                bottom: 12, top: i < 2 ? 4 : 0),
            child: _DownloadCard(
              title: _title(d),
              sizeStr: _fmtSize(_size(d)),
              statusStr: _status(d),
              progress: liveProgress ?? _progress(d),
              isActive: isActive,
              isComplete: _isComplete(d),
              isSelected: _selected.contains(id),
              isSelecting: _selecting,
              onTap: () {
                if (_selecting) {
                  setState(() { _selected.contains(id) ? _selected.remove(id) : _selected.add(id); });
                } else if (_isComplete(d)) {
                  Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                    'file_id': id, 'title': _title(d), 'local_path': _path(d),
                    'content_type': d['content_type'] as String? ?? 'movie',
                    'is_free': true,
                  });
                }
              },
              onLongPress: () => setState(() { _selecting = true; _selected.add(id); }),
              onDelete: () => _deleteOne(id, _title(d)),
              onCancel: () => ref.read(downloadsProvider.notifier).cancelDownload(id).ignore(),
              onRetry:  () => ref.read(downloadsProvider.notifier).retryDownload(
                fileId: id, titleText: _title(d),
                posterUrl: _posterUrl(d), contentType: d['content_type'] as String?).ignore(),
              speedLabel:    state.speedOf(id),
              etaLabel:      state.etaOf(id),
              queuePosition: state.queuePositionOf(id),
              localPath: _path(d),
              posterUrl: _posterUrl(d),
            ),
          ).animate(delay: animConfig.stagger(i))
              .fadeIn(duration: animConfig.normal)
              .slideY(begin: 0.06, end: 0, duration: animConfig.normal, curve: AppCurves.standard);
        },
        childCount: items.length,
      ),
    );
  }

  SliverPadding _moviesList(List<Map<String, dynamic>> items, DownloadsState state) {
    final animConfig = ref.read(animConfigProvider);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverList(delegate: SliverChildBuilderDelegate(
        (context, i) {
          final d = items[i];
          final id = _id(d);
          final liveProgress = state.activeProgress[id];
          final isActive = liveProgress != null;
          return _DownloadListTile(
            title: _title(d),
            sizeStr: _fmtSize(_size(d)),
            statusStr: _status(d),
            progress: liveProgress ?? _progress(d),
            isActive: isActive,
            isComplete: _isComplete(d),
            isSelected: _selected.contains(id),
            isSelecting: _selecting,
            onTap: () {
              if (_selecting) {
                setState(() { _selected.contains(id) ? _selected.remove(id) : _selected.add(id); });
              } else if (_isComplete(d)) {
                Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                  'file_id': id, 'title': _title(d), 'local_path': _path(d),
                  'content_type': d['content_type'] as String? ?? 'movie',
                  'is_free': true,
                });
              }
            },
            onLongPress: () => setState(() { _selecting = true; _selected.add(id); }),
            onDelete: () => _deleteOne(id, _title(d)),
            onCancel: () => ref.read(downloadsProvider.notifier).cancelDownload(id).ignore(),
            onRetry:  () => ref.read(downloadsProvider.notifier).retryDownload(
              fileId: id, titleText: _title(d),
              posterUrl: _posterUrl(d), contentType: d['content_type'] as String?).ignore(),
            speedLabel: state.speedOf(id),
            etaLabel:   state.etaOf(id),
            localPath: _path(d),
            posterUrl: _posterUrl(d),
          ).animate(delay: animConfig.stagger(i))
              .fadeIn(duration: animConfig.normal)
              .slideX(begin: 0.1, end: 0, duration: animConfig.normal, curve: AppCurves.standard);
        },
        childCount: items.length,
      )),
    );
  }

  Future<void> _deleteOne(String id, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Download'),
      content: Text('Delete "$title"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (ok == true) ref.read(downloadsProvider.notifier).deleteDownload(id);
  }

  Future<void> _addSelectedToVault() async {
    final state = ref.read(downloadsProvider);
    final completed = state.downloads
        .where((d) => _selected.contains(_id(d)) && _isComplete(d))
        .toList();
    if (completed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Select completed downloads to add to vault'),
        backgroundColor: t.surface));
      return;
    }
    final hasPin = await VaultService.hasPin();
    if (!hasPin) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Set up your vault PIN first (Profile → Vault)'),
        backgroundColor: t.surface));
      return;
    }
    if (!VaultService.isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Unlock your vault first (Profile → Vault → Unlock)'),
        backgroundColor: t.surface));
      return;
    }
    int count = 0;
    for (final d in completed) {
      final path = _path(d);
      if (path.isNotEmpty && File(path).existsSync()) {
        try {
          await VaultService.moveFileToVault(path);
          count++;
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() { _selecting = false; _selected.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(count > 0
            ? '$count video${count != 1 ? "s" : ""} moved to vault'
            : 'No accessible files to move'),
        backgroundColor: t.surface));
      if (count > 0) ref.read(downloadsProvider.notifier).loadDownloads();
    }
  }

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Selected'),
      content: Text('Delete $count download${count == 1 ? '' : 's'}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (ok == true) {
      for (final id in _selected) ref.read(downloadsProvider.notifier).deleteDownload(id);
      setState(() { _selecting = false; _selected.clear(); });
    }
  }
}

// ── TV show summary card (Download tab) ─────────────────────────────────────
// Tapping opens SeasonFolderScreen — the show itself is no longer expandable
// inline, matching how MoviBox/Amazon Prime keep the top-level list short.
class _ShowSummaryCard extends StatelessWidget {
  final String showName;
  final List<Map<String, dynamic>> episodes;
  final bool Function(Map) isComplete;
  final bool Function(Map) isDownloading;
  final int Function(Map) sizeOf;
  final String? posterUrl;
  final String Function(int) fmtSize;
  final VoidCallback onTap;

  const _ShowSummaryCard({
    required this.showName, required this.episodes, required this.isComplete,
    required this.isDownloading, required this.sizeOf, this.posterUrl,
    required this.fmtSize, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final seasons = episodes.map((d) =>
        parseEpisodeTitle(d['title_text'] as String? ?? '').seasonOrDefault).toSet().length;
    final done   = episodes.where(isComplete).length;
    final active = episodes.where(isDownloading).length;
    final total  = episodes.fold<int>(0, (s, d) => s + sizeOf(d));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 52, height: 74,
                child: (posterUrl != null && posterUrl!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: posterUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: t.card,
                            child: Icon(AppIcons.tv, color: t.textMuted, size: 22)))
                    : Container(color: t.card,
                        child: Icon(AppIcons.tv, color: t.textMuted, size: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(showName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text('$seasons season${seasons == 1 ? '' : 's'}',
                      style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(5)),
                  child: Text('$done/${episodes.length} eps',
                      style: TextStyle(color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w700))),
                if (active > 0)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('↓ $active', style: const TextStyle(
                        color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: RaddSpace.xs),
              Text(fmtSize(total), style: TextStyle(color: t.textMuted, fontSize: 10)),
            ])),
            Icon(AppIcons.caretRight, size: 18, color: t.textMuted),
          ]),
        ),
      ),
    );
  }
}

// ── Download Card (Grid) ─────────────────────────────────────────────────────
class _DownloadCard extends StatefulWidget {
  final String title, sizeStr, statusStr, localPath;
  final String? posterUrl;
  final double progress;
  final bool isActive, isComplete, isSelected, isSelecting;
  final VoidCallback onTap, onLongPress, onDelete;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final String speedLabel;
  final String etaLabel;
  final int    queuePosition;
  const _DownloadCard({required this.title, required this.sizeStr,
      required this.statusStr, required this.progress, required this.isActive,
      required this.isComplete, required this.isSelected, required this.isSelecting,
      required this.onTap, required this.onLongPress, required this.onDelete,
      this.onCancel, this.onRetry, this.speedLabel = '', this.etaLabel = '',
      this.queuePosition = 0, this.localPath = '', this.posterUrl});
  @override State<_DownloadCard> createState() => _DownloadCardState();
}
class _DownloadCardState extends State<_DownloadCard> {
  Uint8List? _thumb;
  @override void initState() {
    super.initState();
    if (widget.localPath.isNotEmpty && widget.isComplete) _loadThumb();
  }
  Future<void> _loadThumb() async {
    final t = await ThumbService.getThumbnail(widget.localPath, timeMs: 3000, maxWidth: 240);
    if (mounted) setState(() => _thumb = t);
  }
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: widget.onTap, onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.isSelected ? AppColors.primary.withOpacity(0.1) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
              color: widget.isSelected ? AppColors.primary : t.border,
              width: widget.isSelected ? 1.5 : 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Thumbnail area
          Expanded(child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sm - 1)),
              child: _thumb != null
                ? Image.memory(_thumb!, fit: BoxFit.cover)
                : (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: widget.posterUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: t.card,
                            child: Center(child: Icon(AppIcons.movie,
                                color: t.textMuted, size: 36))))
                    : Container(color: t.card,
                        child: Center(child: Icon(AppIcons.movie,
                            color: t.textMuted, size: 36)))),
            // Play overlay
            if (widget.isComplete && !widget.isSelecting)
              Center(child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black54,
                    border: Border.all(color: Colors.white30)),
                child: Icon(AppIcons.play, color: Colors.white, size: 24))),
            // Download widget.progress bar
            if (widget.isActive || (!widget.isComplete && widget.statusStr != 'failed'))
              Positioned(bottom: 0, left: 0, right: 0,
                child: LinearProgressIndicator(value: widget.progress,
                    backgroundColor: Colors.black38,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 3)),
            // Selection checkbox
            if (widget.isSelecting)
              Positioned(top: 6, right: 6, child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: widget.isSelected ? AppColors.primary : Colors.black38,
                    border: Border.all(color: widget.isSelected ? AppColors.primary : Colors.white38, width: 1.5)),
                child: widget.isSelected ? Icon(AppIcons.check, color: Colors.white, size: 14) : null)),
            // Queue position badge (shown for #2 onwards so #1 = no badge = "currently downloading")
            if (widget.isActive && widget.queuePosition > 1)
              Positioned(top: 6, right: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(4)),
                child: Text('#${widget.queuePosition}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w800)))),
            // Failed badge
            if (widget.statusStr == 'failed')
              Positioned(top: 6, left: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: AppColors.error,
                    borderRadius: BorderRadius.circular(3)),
                child: Text('FAILED', style: TextStyle(
                    color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)))),
          ])),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontSize: 11,
                      fontWeight: FontWeight.w600, height: 1.3)),
              SizedBox(height: RaddSpace.xs),
              Row(children: [
                if (widget.isActive)
                  Flexible(child: Text(
                    '${(widget.progress * 100).toStringAsFixed(0)}%'
                    '${widget.speedLabel.isNotEmpty ? "  ${widget.speedLabel}" : ""}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.primary,
                        fontSize: 10, fontWeight: FontWeight.w700)))
                else
                  Text(widget.sizeStr, style: TextStyle(color: t.textMuted, fontSize: 10)),
                const Spacer(),
                if (!widget.isSelecting)
                  GestureDetector(
                    onTap: widget.isActive
                        ? (widget.onCancel ?? widget.onDelete)
                        : widget.statusStr == 'failed'
                            ? (widget.onRetry ?? widget.onDelete)
                            : widget.onDelete,
                    child: Icon(
                      widget.isActive
                          ? AppIcons.stopIcon
                          : widget.statusStr == 'failed'
                              ? AppIcons.refresh
                              : AppIcons.trash,
                      size: 16,
                      color: widget.isActive
                          ? AppColors.error.withOpacity(0.75)
                          : widget.statusStr == 'failed'
                              ? AppColors.primary.withOpacity(0.8)
                              : t.textMuted,
                    ),
                  ),
              ]),
              if (widget.isActive && widget.etaLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(widget.etaLabel, style: TextStyle(color: t.textMuted, fontSize: 8)),
              ],
              if (widget.statusStr == 'failed') ...[
                const SizedBox(height: 2),
                Text('Tap ↺ to retry download',
                    style: TextStyle(color: AppColors.error.withOpacity(0.65),
                        fontSize: 8, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Download List Tile ────────────────────────────────────────────────────────
class _DownloadListTile extends StatefulWidget {
  final String title, sizeStr, statusStr;
  final String localPath;
  final String? posterUrl;
  final double progress;
  final bool isActive, isComplete, isSelected, isSelecting;
  final VoidCallback onTap, onLongPress, onDelete;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final String speedLabel;
  final String etaLabel;
  const _DownloadListTile({required this.title, required this.sizeStr,
      required this.statusStr, required this.progress, required this.isActive,
      required this.isComplete, required this.isSelected, required this.isSelecting,
      required this.onTap, required this.onLongPress, required this.onDelete,
      this.onCancel, this.onRetry, this.speedLabel = '', this.etaLabel = '',
      this.localPath = '', this.posterUrl});
  @override State<_DownloadListTile> createState() => _DownloadListTileState();
}
class _DownloadListTileState extends State<_DownloadListTile> {
  Uint8List? _thumb;
  @override void initState() {
    super.initState();
    if (widget.localPath.isNotEmpty && widget.isComplete) _loadThumb();
  }
  Future<void> _loadThumb() async {
    final t = await ThumbService.getThumbnail(widget.localPath, timeMs: 3000, maxWidth: 120);
    if (mounted) setState(() => _thumb = t);
  }
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: widget.onTap, onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.isSelected ? AppColors.primary.withOpacity(0.08) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
              color: widget.isSelected ? AppColors.primary : t.border,
              width: widget.isSelected ? 1.5 : 0.5)),
        child: Row(children: [
          // Thumbnail
          Container(width: 64, height: 48,
            decoration: BoxDecoration(color: t.card,
                borderRadius: BorderRadius.circular(AppRadius.xs)),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              _thumb != null
                ? Image.memory(_thumb!, fit: BoxFit.cover)
                : (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: widget.posterUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Center(child: Icon(AppIcons.movie, color: t.textMuted, size: 24)))
                    : Center(child: Icon(AppIcons.movie, color: t.textMuted, size: 24)),
              if (widget.isComplete && !widget.isSelecting)
                Center(child: Container(width: 24, height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                    child: Icon(AppIcons.play, color: Colors.white, size: 16))),
              if (widget.isSelecting)
                Positioned(top: 4, right: 4, child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 16, height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: widget.isSelected ? AppColors.primary : Colors.black38,
                      border: Border.all(color: Colors.white38)),
                  child: widget.isSelected ? Icon(AppIcons.check, color: Colors.white, size: 10) : null)),
            ])),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: 13,
                    fontWeight: FontWeight.w600, height: 1.3)),
            SizedBox(height: RaddSpace.xs),
            Row(children: [
              Text(widget.sizeStr, style: TextStyle(color: t.textMuted, fontSize: 11)),
              if (widget.statusStr == 'failed') ...[
                SizedBox(width: RaddSpace.sm),
                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3)),
                    child: Text('FAILED', style: TextStyle(
                        color: AppColors.error, fontSize: 9, fontWeight: FontWeight.w700))),
              ],
            ]),
            if (widget.isActive) ...[
              SizedBox(height: 6),
              LinearProgressIndicator(value: widget.progress,
                  backgroundColor: t.card,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 2),
              SizedBox(height: 3),
              Text(
                '${(widget.progress * 100).toStringAsFixed(0)}%'
                '${widget.speedLabel.isNotEmpty ? "  ${widget.speedLabel}" : "  downloading..."}'
                '${widget.etaLabel.isNotEmpty ? "  ${widget.etaLabel}" : ""}',
                style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
            if (widget.statusStr == 'failed') ...[
              SizedBox(height: 3),
              Text('Failed — tap ↺ to retry or 🗑 to remove',
                  style: TextStyle(color: AppColors.error.withOpacity(0.7),
                      fontSize: 10, fontWeight: FontWeight.w500)),
            ],
          ])),
          if (!widget.isSelecting)
            widget.statusStr == 'failed'
              // Failed: show Retry + Delete side by side
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(AppIcons.refresh, size: 18, color: AppColors.primary.withOpacity(0.85)),
                    tooltip: 'Retry download',
                    onPressed: widget.onRetry ?? widget.onDelete,
                  ),
                  IconButton(
                    icon: Icon(AppIcons.trash, size: 18, color: t.textMuted),
                    tooltip: 'Remove',
                    onPressed: widget.onDelete,
                  ),
                ])
              : IconButton(
                  icon: Icon(
                    widget.isActive ? AppIcons.stopIcon : AppIcons.trash,
                    size: 18,
                    color: widget.isActive ? AppColors.error.withOpacity(0.75) : t.textMuted,
                  ),
                  onPressed: widget.isActive
                      ? (widget.onCancel ?? widget.onDelete)
                      : widget.onDelete,
                ),
        ]),
      ),
    );
  }
}

/// Small icon+label pill for the downloads empty state feature hints.
class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final RaddTheme t;
  const _FeaturePill({required this.icon, required this.label, required this.t});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: t.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.primary),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: t.textMuted,
          fontSize: 12, fontWeight: FontWeight.w500)),
    ]),
  );
}
