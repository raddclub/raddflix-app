import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../providers/downloads_provider.dart';
import '../providers/auth_provider.dart';
import '../core/debug/debug_logger.dart';
import '../widgets/bottom_nav.dart';
import '../services/thumb_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
  import '../services/vault_service.dart';
import '../core/utils/anim_config.dart';

enum _SortMode { name, size, date }
enum _FilterMode { all, completed, downloading, failed }
enum _ViewMode { grid, list }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  RaddTheme get t => RaddTheme.of(context);

  _SortMode   _sort   = _SortMode.date;
  _FilterMode _filter = _FilterMode.all;
  _ViewMode   _view   = _ViewMode.grid;
  bool _selecting     = false;
  final Set<String> _selected = {};
  String? _activeFolder;

  // Phase-40: disk space display + offline banner
  double? _freeMB;
  bool    _isOnline = true;

  static const _folders = ['Movies', 'TV Shows', 'Dramas', 'Other'];

  static const _kPrefsSort   = 'dl_sort_v2';
  static const _kPrefsFilter = 'dl_filter_v2';
  static const _kPrefsView   = 'dl_view_v2';

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
      _sort   = _SortMode.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsSort) ?? ''), orElse: () => _SortMode.date);
      _filter = _FilterMode.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsFilter) ?? ''), orElse: () => _FilterMode.all);
      _view   = _ViewMode.values.firstWhere(
          (e) => e.name == (p.getString(_kPrefsView) ?? ''), orElse: () => _ViewMode.grid);
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsSort,   _sort.name);
    await p.setString(_kPrefsFilter, _filter.name);
    await p.setString(_kPrefsView,   _view.name);
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

  // BUG-C04 fix: check if subscription has expired before playing downloaded content.
  // If user had a subscription and it's now expired, redirect to PlanExpiredScreen.
  // Free users (subscription==null) and guests can still play their downloads.
  bool _isSubExpired() {
    final user = ref.read(authProvider).user;
    if (user == null || user.isGuest) return false;
    if (user.subscription == null) return false; // free user — no sub ever
    return !user.subscription!.isActive; // has sub record but it expired
  }

  bool _isComplete(Map m)    => _status(m) == 'completed';
  bool _isDownloading(Map m) => _status(m) == 'downloading' || _status(m) == 'pending';
  bool _isFailed(Map m)      => _status(m) == 'failed';

  String _fmtSize(int bytes) {
    if (bytes == 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _folderFor(Map m) {
    // Prefer stored content_type if available (set at download time)
    final ct = m['content_type'] as String?;
    if (ct == 'show' || ct == 'series' || ct == 'tv') return 'TV Shows';
    // BUG-FOLDER-01 FIX: handle legacy raw content_type values written before
    // CatalogItem.mediaType normalisation locked values to 'show'/'movie'.
    if (ct == 'anime' || ct == 'cartoon' || ct == 'donghua') return 'TV Shows';
    if (ct == 'drama') return 'Dramas';
    if (ct == 'movie') return 'Movies';
    // Fallback: heuristic on title
    final title = _title(m).toLowerCase();
    if (title.contains('drama')) return 'Dramas';
    if (title.contains('episode') || title.contains('season') ||
        title.contains(' s0') || title.contains('ep ') ||
        title.contains('series') || title.contains('show')) return 'TV Shows';
    return 'Movies';
  }

  /// Extracts show title from episode titles like "Show Name S01E01".
  String _showTitleFrom(String text) {
    final m = RegExp(r'\s+[Ss]\d{2}[Ee]\d{2}').firstMatch(text);
    if (m != null) return text.substring(0, m.start).trim();
    return text;
  }

  /// Total stored bytes for all items in a named folder.
  int _totalSizeForFolder(List<Map<String, dynamic>> all, String folder) =>
      all.where((d) => _folderFor(d) == folder)
          .fold<int>(0, (s, d) => s + _size(d));

  /// Poster URL stored at download time (may be null/empty).
  String? _posterUrl(Map m) => m['poster_url'] as String?;

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> items) {
    switch (_filter) {
      case _FilterMode.completed:   return items.where((m) => _isComplete(m)).toList();
      case _FilterMode.downloading: return items.where((m) => _isDownloading(m)).toList();
      case _FilterMode.failed:      return items.where((m) => _isFailed(m)).toList();
      default: return items;
    }
  }

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
            const Icon(Icons.download_done_rounded, color: Colors.white, size: 18)
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
        currentIndex: 2,
        onTap: (i) {
          if (i == 2) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          if (i == 1) Navigator.of(context).pushNamed(AppRoutes.localMedia);
          else if (i == 3) Navigator.of(context).pushNamed(AppRoutes.profile);
        },
      ),
      body: Column(children: [
        if (!_isOnline) _buildOfflineBanner(),
        _buildStorageBar(state),
        _buildFilterRow(),
        const Divider(height: 1),
        Expanded(child: state.loading
            ? _buildLoadingShimmer()
            : state.downloads.isEmpty
                ? _buildEmpty()
                : _activeFolder == null
                    ? _buildFolderView(state)
                    : _buildItemsView(state)),
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
          : Text(_activeFolder ?? 'Downloads',
              style: const TextStyle(fontWeight: FontWeight.w800)),
      leading: IconButton(
        icon: Icon(_activeFolder != null || _selecting
            ? Icons.arrow_back_ios_new_rounded : Icons.close_rounded, size: 20),
        onPressed: () {
          if (_selecting) {
            setState(() { _selecting = false; _selected.clear(); });
          } else if (_activeFolder != null) {
            setState(() => _activeFolder = null);
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      actions: [
        if (_selecting) ...[
          TextButton(
            onPressed: () => setState(() => _selected.addAll(state.downloads.map((d) => _id(d)))),
            child: const Text('All'),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
            tooltip: 'Add to Vault',
            onPressed: _selected.isEmpty ? null : _addSelectedToVault,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: _selected.isEmpty ? null : () => _bulkDelete(),
          ),
        ] else ...[
          IconButton(
            icon: Icon(_view == _ViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () { setState(() => _view = _view == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid); _savePrefs(); },
            tooltip: 'Toggle view',
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort_rounded),
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
        Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.error),
        const SizedBox(width: 8),
        const Expanded(child: Text('You are offline. Downloads are paused.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        GestureDetector(
          onTap: _checkConnectivity,
          child: Icon(Icons.refresh_rounded, size: 16, color: AppColors.error),
        ),
      ]),
    );
  }

  Widget _buildStorageBar(DownloadsState state) {
    final totalBytes = state.downloads.fold<int>(0, (sum, d) => sum + _size(d));
    final completed = state.downloads.where((d) => _isComplete(d)).length;
    final active    = state.downloads.where((d) => _isDownloading(d)).length;
    final freeStr   = _freeMB != null
        ? (_freeMB! >= 1024
            ? '${(_freeMB! / 1024).toStringAsFixed(1)} GB free'
            : '${_freeMB!.toStringAsFixed(0)} MB free')
        : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withOpacity(0.12),
            border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Icon(Icons.download_done_rounded, size: 20, color: AppColors.primary),
        ),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_fmtSize(totalBytes),
                style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(' stored', style: TextStyle(color: t.textMuted, fontSize: 12)),
            const Spacer(),
            if (active > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$active loading', style: TextStyle(
                    color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          SizedBox(height: 5),
          Row(children: [
            Text('${completed} done', style: TextStyle(color: t.textMuted, fontSize: 11)),
            Text(' · ', style: TextStyle(color: t.textMuted)),
            Text('${state.downloads.length} total', style: TextStyle(color: t.textMuted, fontSize: 11)),
            if (freeStr != null) ...[
              Text(' · ', style: TextStyle(color: t.textMuted)),
              Text(freeStr, style: TextStyle(
                  color: (_freeMB ?? 999) < 200
                      ? AppColors.error
                      : (_freeMB ?? 999) < 500
                          ? AppColors.warning
                          : t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ]),
        ])),
      ]),
    );
  }

  Widget _buildFilterRow() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: _FilterMode.values.map((f) {
          final selected = _filter == f;
          final labels = {_FilterMode.all:'All', _FilterMode.completed:'Done',
              _FilterMode.downloading:'Downloading', _FilterMode.failed:'Failed'};
          return GestureDetector(
            onTap: () { setState(() => _filter = f); _savePrefs(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                color: selected ? null : t.surface,
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: selected ? Colors.transparent : t.border),
                boxShadow: selected ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 10, offset: const Offset(0,3))] : null,
              ),
              child: Text(labels[f]!, style: TextStyle(
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
      padding: const EdgeInsets.all(16),
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
            child: Icon(Icons.download_for_offline_outlined,
                color: AppColors.primary.withOpacity(0.7), size: 48),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scaleXY(begin: 0.96, end: 1.0,
               duration: const Duration(milliseconds: 1800),
               curve: Curves.easeInOut),
          const SizedBox(height: 24),
          Text('No Downloads Yet',
              style: TextStyle(color: t.textPrimary,
                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Text(
            'Save movies and shows to watch offline — no internet needed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          // Feature pills
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _FeaturePill(icon: Icons.wifi_off_rounded, label: 'Works offline', t: t),
            const SizedBox(width: 8),
            _FeaturePill(icon: Icons.bolt_rounded, label: 'Fast resume', t: t),
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
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.explore_rounded, color: Colors.white, size: 16),
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

  Widget _buildFolderView(DownloadsState state) {
    // Phase 43: tier-aware stagger
    final animConfig = ref.read(animConfigProvider);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _folders.length,
      itemBuilder: (_, i) {
        final folder = _folders[i];
        final count = state.downloads.where((d) => _folderFor(d) == folder).length;
        final folderColor = _folderColor(folder, t.textMuted);
        return RepaintBoundary(child: GestureDetector(
          onTap: count > 0 ? () => setState(() => _activeFolder = folder) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: count > 0 ? folderColor.withOpacity(0.25) : t.border,
                width: count > 0 ? 1.0 : 0.5,
              ),
              boxShadow: count > 0 ? [
                BoxShadow(color: folderColor.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
              ] : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: folderColor.withOpacity(count > 0 ? 0.14 : 0.06),
                      border: Border.all(color: folderColor.withOpacity(count > 0 ? 0.3 : 0.1)),
                    ),
                    child: Icon(_folderIcon(folder),
                        color: count > 0 ? folderColor : t.textMuted, size: 22),
                  ),
                  const Spacer(),
                  if (count > 0) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: folderColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppRadius.round),
                    ),
                    child: Text('$count', style: TextStyle(
                        color: folderColor, fontSize: 12, fontWeight: FontWeight.w800))),
                ]),
                const Spacer(),
                Text(folder, style: TextStyle(
                    color: count > 0 ? t.textPrimary : t.textMuted,
                    fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text(count == 0 ? 'Empty' : '$count video${count == 1 ? '' : 's'}',
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
                if (count > 0) ...[SizedBox(height: 2),
                  Text(_fmtSize(_totalSizeForFolder(state.downloads, folder)),
                      style: TextStyle(color: t.textMuted, fontSize: 10))],
              ]),
            ),
          ),
        ).animate(delay: animConfig.stagger(i))
            .fadeIn(duration: animConfig.normal)
            .slideY(begin: 0.06, end: 0, duration: animConfig.normal,
                curve: AppCurves.enter));
      },
    );
  }

  Widget _buildItemsView(DownloadsState state) {
    var items = state.downloads.where((d) => _folderFor(d) == _activeFolder!).toList();
    items = _applyFilter(items);
    items = _applySort(items);

    if (items.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.filter_list_off_rounded, color: t.textMuted, size: 48),
        SizedBox(height: 12),
        Text('No ${_filter.name} downloads in $_activeFolder',
            style: TextStyle(color: t.textMuted)),
      ]));
    }

    // TV Shows: group episodes by show title for a cleaner browsing experience
    if (_activeFolder == 'TV Shows') return _groupedTvView(items, state);
    return _view == _ViewMode.grid ? _gridView(items, state) : _listView(items, state);
  }

  Widget _groupedTvView(List<Map<String, dynamic>> items, DownloadsState state) {
    // Group flat episode list by extracted show title
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final d in items) {
      groups.putIfAbsent(_showTitleFrom(_title(d)), () => []).add(d);
    }
    final showNames = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      physics: const BouncingScrollPhysics(),
      itemCount: showNames.length,
      itemBuilder: (_, i) {
        final show = showNames[i];
        final eps  = groups[show]!;
        eps.sort((a, b) => _title(a).compareTo(_title(b)));
        final poster = _posterUrl(eps.first);
        final total  = eps.fold<int>(0, (s, d) => s + _size(d));
        final done   = eps.where(_isComplete).length;
        final active = eps.where(_isDownloading).length;
        return _ShowGroup(
          showName:    show,
          episodes:    eps,
          posterUrl:   poster,
          totalSize:   _fmtSize(total),
          doneCount:   done,
          totalCount:  eps.length,
          activeCount: active,
          activeProgress: state.activeProgress,
          isSelecting: _selecting,
          selected:    _selected,
          onTapEp:     (d) {
            final id = _id(d);
            if (_selecting) {
              setState(() {
                _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
              });
            } else if (_isComplete(d)) {
              // BUG-C04 fix: block playback if subscription has expired
              if (_isSubExpired()) {
                Navigator.of(context).pushNamed(AppRoutes.planExpired);
                return;
              }
              final doneEps = eps.where(_isComplete).toList();
              final epIdx   = doneEps.indexOf(d as Map<String, dynamic>);
              final epList  = doneEps.asMap().entries.map((e) => <String, dynamic>{
                'file_id':    _id(e.value),
                'local_path': _path(e.value),
                'label':      _title(e.value),
                'episode':    e.key,
              }).toList();
              DebugLogger.logFeature('PlayDownloaded', 'from DownloadsScreen');
              Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                'file_id':      id,
                'title':        _title(d),
                'local_path':   _path(d),
                'episodes':     epList,
                'episode_index': epIdx < 0 ? 0 : epIdx,
                'content_type': d['content_type'] as String? ?? 'show',
              });
            }
          },
          onDeleteEp:  (d) => _deleteOne(_id(d), _title(d)),
          onLongPress: (d) => setState(() {
            _selecting = true; _selected.add(_id(d));
          }),
        ).animate(delay: (i * 50).ms).fadeIn(duration: 280.ms);
      },
    );
  }

  Widget _gridView(List<Map<String, dynamic>> items, DownloadsState state) {
    // Phase 43: tier-aware stagger
    final animConfig = ref.read(animConfigProvider);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final d = items[i];
        final id = _id(d);
        final liveProgress = state.activeProgress[id];
        final isActive = liveProgress != null;
        return _DownloadCard(
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
              // BUG-C04 fix: block playback if subscription has expired
              if (_isSubExpired()) {
                Navigator.of(context).pushNamed(AppRoutes.planExpired);
                return;
              }
              // BUG-7 fix: include content_type so player doesn't default all downloads to 'series'.
              Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                'file_id': id, 'title': _title(d), 'local_path': _path(d),
                'content_type': d['content_type'] as String? ?? 'movie'});
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
        ).animate(delay: animConfig.stagger(i))
            .fadeIn(duration: animConfig.normal)
            .slideY(begin: 0.06, end: 0, duration: animConfig.normal,
                curve: AppCurves.standard);
      },
    );
  }

  Widget _listView(List<Map<String, dynamic>> items, DownloadsState state) {
    // Phase 43: tier-aware stagger
    final animConfig = ref.read(animConfigProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (_, i) {
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
              // BUG-C04 fix: block playback if subscription has expired
              if (_isSubExpired()) {
                Navigator.of(context).pushNamed(AppRoutes.planExpired);
                return;
              }
              // BUG-7 fix: include content_type so player doesn't default all downloads to 'series'.
              Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                'file_id': id, 'title': _title(d), 'local_path': _path(d),
                'content_type': d['content_type'] as String? ?? 'movie'});
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
            .slideX(begin: 0.1, end: 0, duration: animConfig.normal,
                curve: AppCurves.standard);
      },
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

  IconData _folderIcon(String name) {
    switch (name) {
      case 'Movies':   return Icons.movie_rounded;
      case 'TV Shows': return Icons.live_tv_rounded;
      case 'Dramas':   return Icons.theater_comedy_rounded;
      default:         return Icons.folder_rounded;
    }
  }

  Color _folderColor(String name, Color fallback) {
    switch (name) {
      case 'Movies':   return const Color(0xFFE8002D);
      case 'TV Shows': return const Color(0xFF3B82F6);
      case 'Dramas':   return const Color(0xFF8B5CF6);
      default:         return fallback;
    }
  }
}

// ── Download Card (Grid) ────────────────────────���─────────────────────────────
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
                            child: Center(child: Icon(Icons.movie_outlined,
                                color: t.textMuted, size: 36))))
                    : Container(color: t.card,
                        child: Center(child: Icon(Icons.movie_outlined,
                            color: t.textMuted, size: 36)))),
            // Play overlay
            if (widget.isComplete && !widget.isSelecting)
              Center(child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black54,
                    border: Border.all(color: Colors.white30)),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24))),
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
                child: widget.isSelected ? Icon(Icons.check_rounded, color: Colors.white, size: 14) : null)),
            // Queue position badge (shown for #2 onwards so #1 = no badge = "currently downloading")
            if (widget.isActive && widget.queuePosition > 1)
              Positioned(top: 6, right: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black65,
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
              SizedBox(height: 4),
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
                          ? Icons.stop_circle_outlined
                          : widget.statusStr == 'failed'
                              ? Icons.refresh_rounded
                              : Icons.delete_outline_rounded,
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
                            Center(child: Icon(Icons.movie_outlined, color: t.textMuted, size: 24)))
                    : Center(child: Icon(Icons.movie_outlined, color: t.textMuted, size: 24)),
              if (widget.isComplete && !widget.isSelecting)
                Center(child: Container(width: 24, height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16))),
              if (widget.isSelecting)
                Positioned(top: 4, right: 4, child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 16, height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: widget.isSelected ? AppColors.primary : Colors.black38,
                      border: Border.all(color: Colors.white38)),
                  child: widget.isSelected ? Icon(Icons.check_rounded, color: Colors.white, size: 10) : null)),
            ])),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: 13,
                    fontWeight: FontWeight.w600, height: 1.3)),
            SizedBox(height: 4),
            Row(children: [
              Text(widget.sizeStr, style: TextStyle(color: t.textMuted, fontSize: 11)),
              if (widget.statusStr == 'failed') ...[
                SizedBox(width: 8),
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
                    icon: Icon(Icons.refresh_rounded, size: 18, color: AppColors.primary.withOpacity(0.85)),
                    tooltip: 'Retry download',
                    onPressed: widget.onRetry ?? widget.onDelete,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: t.textMuted),
                    tooltip: 'Remove',
                    onPressed: widget.onDelete,
                  ),
                ])
              : IconButton(
                  icon: Icon(
                    widget.isActive ? Icons.stop_circle_outlined : Icons.delete_outline_rounded,
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

// ── Grouped TV show row in Downloads screen ─────────────────────────────────
class _ShowGroup extends StatefulWidget {
  final String showName;
  final List<Map<String, dynamic>> episodes;
  final String? posterUrl;
  final String totalSize;
  final int doneCount, totalCount, activeCount;
  final Map<String, double> activeProgress;
  final bool isSelecting;
  final Set<String> selected;
  final void Function(Map) onTapEp;
  final void Function(Map) onDeleteEp;
  final void Function(Map) onLongPress;
  const _ShowGroup({
    required this.showName, required this.episodes, this.posterUrl,
    required this.totalSize, required this.doneCount, required this.totalCount,
    required this.activeCount, required this.activeProgress,
    required this.isSelecting, required this.selected,
    required this.onTapEp, required this.onDeleteEp, required this.onLongPress,
  });
  @override State<_ShowGroup> createState() => _ShowGroupState();
}

class _ShowGroupState extends State<_ShowGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border, width: 0.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // ── Show header row ──────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 50, height: 70,
                child: (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: widget.posterUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: t.card,
                            child: Icon(Icons.tv_rounded, color: t.textMuted, size: 22)))
                    : Container(color: t.card,
                        child: Icon(Icons.tv_rounded, color: t.textMuted, size: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.showName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _pill('${widget.doneCount}/${widget.totalCount} eps', AppColors.primary),
                _pill(widget.totalSize, t.textMuted),
                if (widget.activeCount > 0)
                  _pill('↓ ${widget.activeCount} loading', const Color(0xFF22C55E)),
              ]),
              const SizedBox(height: 8),
              // Progress bar: X of Y episodes complete
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: widget.totalCount > 0 ? widget.doneCount / widget.totalCount : 0.0,
                  backgroundColor: t.card,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      widget.doneCount == widget.totalCount
                          ? const Color(0xFF22C55E) : AppColors.primary),
                  minHeight: 4)),
            ])),
            const SizedBox(width: 8),
            Icon(_expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
                color: t.textMuted, size: 22),
          ])),
        ),
        // ── Episode rows ─────────────────────────────────────────────────
        if (_expanded) ...[
          Divider(height: 1, indent: 0, endIndent: 0, color: t.border.withOpacity(0.5)),
          ...widget.episodes.asMap().entries.map((entry) {
            final ep       = entry.value;
            final id       = ep['file_id'] as String? ?? '';
            final titleTxt = ep['title_text'] as String? ?? 'Unknown';
            final status   = ep['status'] as String? ?? 'pending';
            final isComp   = status == 'completed';
            final isAct    = widget.activeProgress.containsKey(id);
            final prog     = widget.activeProgress[id]
                ?? (ep['progress'] as num?)?.toDouble() ?? 0.0;
            final bytes    = ep['file_size'] as int? ?? 0;
            final isSel    = widget.selected.contains(id);
            return InkWell(
              onTap:      () => widget.onTapEp(ep),
              onLongPress: () => widget.onLongPress(ep),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: isSel ? AppColors.primary.withOpacity(0.07) : Colors.transparent,
                child: Row(children: [
                  // Status dot
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComp
                          ? AppColors.primary.withOpacity(0.12)
                          : isAct
                              ? const Color(0xFF22C55E).withOpacity(0.12)
                              : status == 'failed'
                                  ? AppColors.error.withOpacity(0.12)
                                  : RaddTheme.of(context).card,
                    ),
                    child: Icon(
                      isComp ? Icons.play_arrow_rounded
                          : isAct ? Icons.downloading_rounded
                          : status == 'failed' ? Icons.error_outline_rounded
                          : Icons.hourglass_top_rounded,
                      size: 14,
                      color: isComp ? AppColors.primary
                          : isAct ? const Color(0xFF22C55E)
                          : status == 'failed' ? AppColors.error
                          : RaddTheme.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_epCode(titleTxt),
                        style: TextStyle(color: RaddTheme.of(context).textPrimary,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    if (isAct) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: prog,
                          backgroundColor: RaddTheme.of(context).card,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                          minHeight: 2),
                      const SizedBox(height: 2),
                      Text('${(prog * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Color(0xFF22C55E),
                              fontSize: 10, fontWeight: FontWeight.w600)),
                    ] else if (bytes > 0)
                      Text(_fmtB(bytes),
                          style: TextStyle(color: RaddTheme.of(context).textMuted, fontSize: 10)),
                  ])),
                  if (!widget.isSelecting)
                    GestureDetector(
                      onTap: () => widget.onDeleteEp(ep),
                      child: Padding(padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 16, color: RaddTheme.of(context).textMuted))),
                  if (widget.isSelecting)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSel ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                            color: isSel ? AppColors.primary
                                : RaddTheme.of(context).textMuted, width: 1.5)),
                      child: isSel
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 11)
                          : null),
                ]),
              ),
            );
          }),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w700)));

  /// Extract episode code (e.g. "S01E03") from full title_text.
  String _epCode(String full) {
    final m = RegExp(r'[Ss]\d{2}[Ee]\d{2}.*').firstMatch(full);
    return m?.group(0) ?? full;
  }

  /// Compact file-size formatter for episode rows.
  String _fmtB(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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
