import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/local_video.dart';
import '../services/local_media_service.dart';
import 'local_folder_screen.dart';
import '../widgets/bottom_nav.dart';
import '../core/theme/radd_theme.dart';
import '../widgets/animated_empty_icons.dart';
import '../core/db/local_db.dart';
import '../services/vault_service.dart';

class LocalMediaScreen extends StatefulWidget {
  const LocalMediaScreen({super.key});
  @override
  State<LocalMediaScreen> createState() => _LocalMediaScreenState();
}

enum _SortBy { name, date, size, count, duration }
enum _LayoutMode { list, grid }
enum _WatchFilter { all, inProgress, watched }

class _LocalMediaScreenState extends State<LocalMediaScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<LocalFolder> _folders = [];
  bool _loading = true;
  bool _permissionDenied = false;
  _SortBy _sortBy = _SortBy.date;
  bool _sortAscending = false;
  _LayoutMode _layout = _LayoutMode.list;
  String _searchQuery = '';
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Map<String, Uint8List?> _thumbCache = {};
  static const _kThumbCacheMax = 80; // OOM guard — evict oldest when exceeded
  Timer? _searchDebounce;

  // Resume last local video
  String? _resumePath;
  String? _resumeTitle;

  // Watch progress filter & position map
  _WatchFilter _watchFilter = _WatchFilter.all;
  Map<String, int> _posMap = {};
  Map<String, int> _durMap = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadResume();
    _loadWatchPositions();
  }

  Future<void> _loadWatchPositions() async {
    try {
      final rows = await LocalDb.getWatchPositions();
      final pos = <String, int>{};
      final dur = <String, int>{};
      for (final r in rows) {
        final id = r['file_id'] as String? ?? '';
        if (id.isEmpty) continue;
        pos[id] = (r['position_ms'] as int? ?? 0);
        dur[id] = (r['duration_ms'] as int? ?? 0);
      }
      if (mounted) setState(() { _posMap = pos; _durMap = dur; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadResume() async {
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString('resume_local_path');
    final title = prefs.getString('resume_title');
    if (path != null && path.isNotEmpty && mounted) {
      setState(() {
        _resumePath  = path;
        _resumeTitle = title ?? path.split('/').last;
      });
    }
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final hasPermission = await LocalMediaService.checkPermission();
    if (!hasPermission) {
      final granted = await LocalMediaService.requestPermission();
      if (!granted) {
        setState(() { _loading = false; _permissionDenied = true; });
        return;
      }
    }
    final videos  = await LocalMediaService.queryAllVideos();
    final folders = LocalMediaService.groupByFolder(videos);
    final seen    = await LocalMediaService.getSeenPaths();
    for (final f in folders) {
      f.newCount = f.videos.where((v) => !seen.contains(v.filePath)).length;
    }
    setState(() { _folders = folders; _loading = false; _permissionDenied = false; });
    _loadThumbnails(folders);
  }

  // Evict the oldest half of _thumbCache when it exceeds _kThumbCacheMax entries.
  void _evictThumbCache() {
    if (_thumbCache.length <= _kThumbCacheMax) return;
    final toRemove = _thumbCache.keys.take(_thumbCache.length ~/ 2).toList();
    for (final k in toRemove) _thumbCache.remove(k);
  }

  Future<void> _loadThumbnails(List<LocalFolder> folders) async {
    const batchSize = 4;
    for (int i = 0; i < folders.length; i += batchSize) {
      if (!mounted) return;
      _evictThumbCache();
      final batch = folders.skip(i).take(batchSize).toList();
      // Collect all thumb results for this batch, then setState once per batch
      // (not once per thumbnail — avoids N full widget-tree rebuilds per batch).
      final batchResults = <String, Uint8List?>{};
      await Future.wait(batch.map((folder) async {
        if (_thumbCache.containsKey(folder.path)) return;
        if (folder.folderType == 'audio') { batchResults[folder.path] = null; return; }
        for (final video in folder.videos.where((v) => v.isVideo).take(3)) {
          Uint8List? thumb;
          if (video.id > 0) {
            thumb = await LocalMediaService.getThumbnailById(video.id, size: 160);
          }
          thumb ??= await LocalMediaService.getThumbnail(video.filePath, quality: 40, maxDimension: 160);
          if (thumb != null) { batchResults[folder.path] = thumb; return; }
        }
        batchResults[folder.path] = null;
      }));
      if (mounted && batchResults.isNotEmpty) {
        setState(() => _thumbCache.addAll(batchResults));
      }
    }
  }

  List<LocalFolder> get _sorted {
    List<LocalFolder> list = _searchQuery.isEmpty
        ? List.from(_folders)
        : _folders.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    switch (_sortBy) {
      case _SortBy.name:
        list.sort((a, b) => _sortAscending
            ? a.name.compareTo(b.name)
            : b.name.compareTo(a.name));
      case _SortBy.size:
        list.sort((a, b) => _sortAscending
            ? a.totalSizeBytes.compareTo(b.totalSizeBytes)
            : b.totalSizeBytes.compareTo(a.totalSizeBytes));
      case _SortBy.count:
        list.sort((a, b) => _sortAscending
            ? a.videos.length.compareTo(b.videos.length)
            : b.videos.length.compareTo(a.videos.length));
      case _SortBy.duration:
        list.sort((a, b) {
          final da = a.videos.fold(0, (s, v) => s + v.durationMs);
          final db = b.videos.fold(0, (s, v) => s + v.durationMs);
          return _sortAscending ? da.compareTo(db) : db.compareTo(da);
        });
      case _SortBy.date:
        list.sort((a, b) {
          final da = a.videos.isNotEmpty ? a.videos.first.dateModifiedMs : 0;
          final db = b.videos.isNotEmpty ? b.videos.first.dateModifiedMs : 0;
          return _sortAscending ? da.compareTo(db) : db.compareTo(da);
        });
    }
    return list;
  }

  int get _totalFiles => _folders.fold(0, (s, f) => s + f.videos.length);

  double _folderProgress(LocalFolder folder) {
    if (_posMap.isEmpty) return 0.0;
    double total = 0; int count = 0;
    for (final v in folder.videos) {
      final pos = _posMap[v.filePath] ?? 0;
      final dur = _durMap[v.filePath] ?? v.durationMs;
      if (dur > 0 && pos > 5000) {
        total += (pos / dur).clamp(0.0, 1.0);
        count++;
      }
    }
    return count > 0 ? (total / count) : 0.0;
  }

  bool _folderWatched(LocalFolder folder) {
    final vids = folder.videos.where((v) => v.isVideo).toList();
    if (vids.isEmpty) return false;
    for (final v in vids) {
      final pos = _posMap[v.filePath] ?? 0;
      final dur = _durMap[v.filePath] ?? v.durationMs;
      if (dur <= 0 || (pos / dur) < 0.9) return false;
    }
    return true;
  }

  bool _folderInProgress(LocalFolder folder) {
    for (final v in folder.videos) {
      final pos = _posMap[v.filePath] ?? 0;
      final dur = _durMap[v.filePath] ?? v.durationMs;
      if (pos > 5000 && dur > 0 && (pos / dur) < 0.9) return true;
    }
    return false;
  }

  List<LocalFolder> get _filtered {
    final s = _sorted;
    switch (_watchFilter) {
      case _WatchFilter.all: return s;
      case _WatchFilter.inProgress: return s.where((f) => _folderInProgress(f)).toList();
      case _WatchFilter.watched: return s.where((f) => _folderWatched(f)).toList();
    }
  }

  Widget _buildFilterChips() {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        _filterChip(t, _WatchFilter.all,        'All',      AppIcons.localMediaFill),
        const SizedBox(width: 8),
        _filterChip(t, _WatchFilter.inProgress, 'Watching', AppIcons.playCircle),
        const SizedBox(width: 8),
        _filterChip(t, _WatchFilter.watched,    'Watched',  AppIcons.successIcon),
      ]),
    );
  }

  Widget _filterChip(RaddTheme t, _WatchFilter filter, String label, IconData icon) {
    final active = _watchFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _watchFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primary : t.border, width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? AppColors.primary : t.textMuted),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? AppColors.primary : t.textMuted)),
        ]),
      ),
    );
  }

  Widget _buildFilterEmpty() {
    final t = RaddTheme.of(context);
    final msg = _watchFilter == _WatchFilter.inProgress
        ? 'No folders being watched right now'
        : 'No fully watched folders yet';
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(AppIcons.filter, size: 48, color: t.border),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: t.textSecondary, fontSize: 15)),
      ]).animate().fadeIn(duration: 300.ms),
    );
  }

  // ── Sort bottom sheet ──────────────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SortSheet(
        sortBy: _sortBy,
        ascending: _sortAscending,
        layout: _layout,
        onChanged: (sortBy, ascending, layout) {
          setState(() {
            _sortBy = sortBy;
            _sortAscending = ascending;
            _layout = layout;
          });
        },
      ),
    );
  }

  void _resumeLastVideo() {
    final path = _resumePath;
    if (path == null) return;
    final title = _resumeTitle ?? path.split('/').last;
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id': '',
      'title': title,
      'local_path': path,
      'content_type': 'local',
    });
  }

  void _showFolderMenu(LocalFolder folder) {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(folder.name, style: TextStyle(color: t.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(
            leading: Icon(AppIcons.lock, color: AppColors.primary),
            title: const Text('Add to Vault'),
            subtitle: const Text('Import all videos from this folder'),
            onTap: () { Navigator.pop(context); _addFolderToVault(folder); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _addFolderToVault(LocalFolder folder) async {
    final hasPin = await VaultService.hasPin();
    if (!hasPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Set up your vault PIN first (Profile → Vault)'),
        backgroundColor: RaddTheme.of(context).surface));
      return;
    }
    if (!VaultService.isUnlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Unlock your vault first (Profile → Vault → Unlock)'),
        backgroundColor: RaddTheme.of(context).surface));
      return;
    }
    final videos = folder.videos.where((v) => v.isVideo).toList();
    if (videos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No video files in this folder'),
        backgroundColor: RaddTheme.of(context).surface));
      return;
    }
    int count = 0;
    for (final v in videos) {
      try {
        await VaultService.moveFileToVault(v.filePath);
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0
          ? '$count video${count != 1 ? "s" : ""} moved to vault'
          : 'No accessible files to move'),
      backgroundColor: RaddTheme.of(context).surface,
      duration: const Duration(seconds: 3)));
    if (count > 0) _load(refresh: true);
  }

  void _openFolder(LocalFolder folder) async {
    await LocalMediaService.markSeen(folder.videos.map((v) => v.filePath).toList());
    if (!mounted) return;
    setState(() => folder.newCount = 0);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LocalFolderScreen(folder: folder),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    super.build(context);
    return Scaffold(
      backgroundColor: t.bg,
      floatingActionButton: _resumePath != null
          ? FloatingActionButton.extended(
              onPressed: _resumeLastVideo,
              backgroundColor: AppColors.primary,
              icon: Icon(AppIcons.playCircleFill, color: Colors.white, size: 22),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resume', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1)),
                  Text(
                    _resumeTitle ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          : null,
      bottomNavigationBar: RaddFlixBottomNav(
        currentIndex: 2,
        onTap: (i) {
          if (i == 2) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          if (i == 1) Navigator.of(context).pushNamed(AppRoutes.search);
          else if (i == 3) Navigator.of(context).pushNamed(AppRoutes.downloads);
          else if (i == 4) Navigator.of(context).pushNamed(AppRoutes.profile);
        },
      ),
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          if (_searching) _buildSearchBar(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  Widget _buildTopBar() {
    final t = RaddTheme.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        RichText(text: TextSpan(
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          children: [
            TextSpan(text: 'Local ', style: TextStyle(color: t.textPrimary)),
            TextSpan(text: 'Media', style: TextStyle(color: AppColors.primary)),
          ],
        )),
        const Spacer(),
        // File count badge
        if (!_loading && _folders.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.round),
              border: Border.all(color: t.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.videoLibrary, size: 11, color: AppColors.primary),
              const SizedBox(width: 4),
              Text('$_totalFiles',
                  style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(width: 6),
        // Search
        IconButton(
          icon: Icon(_searching ? AppIcons.close : AppIcons.search,
              color: t.textSecondary, size: 22),
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) { _searchQuery = ''; _searchCtrl.clear(); }
              else _searchFocus.requestFocus();
            });
          },
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Layout toggle (list/grid)
        IconButton(
          icon: Icon(
            _layout == _LayoutMode.list ? AppIcons.gridView : AppIcons.listView,
            color: t.textSecondary, size: 22),
          onPressed: () => setState(() =>
              _layout = _layout == _LayoutMode.list ? _LayoutMode.grid : _LayoutMode.list),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Sort & filter sheet
        IconButton(
          icon: Icon(AppIcons.sort, color: t.textSecondary, size: 22),
          onPressed: _showSortSheet,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: (v) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                    if (mounted) setState(() => _searchQuery = v);
                  });
                },
        style: TextStyle(color: t.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search folders…',
          hintStyle: TextStyle(color: t.textMuted),
          prefixIcon: Icon(AppIcons.search, color: t.textMuted, size: 20),
          filled: true,
          fillColor: t.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final t = RaddTheme.of(context);
    if (_loading) return _buildShimmer();
    if (_permissionDenied) return _buildPermissionError();
    if (_sorted.isEmpty) return _buildEmpty();
    final folders = _filtered;

    if (_layout == _LayoutMode.grid) {
      return Column(children: [
        _buildFilterChips(),
        Expanded(child: folders.isEmpty
          ? _buildFilterEmpty()
          : GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, childAspectRatio: 1.4,
                crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: folders.length,
            itemBuilder: (_, i) => _FolderGridCard(
              folder: folders[i],
              thumb: _thumbCache[folders[i].path],
              progress: _folderProgress(folders[i]),
              isWatched: _folderWatched(folders[i]),
              isInProgress: _folderInProgress(folders[i]),
              onTap: () => _openFolder(folders[i]),
              onLongPress: () => _showFolderMenu(folders[i]),
            ).animate(delay: (i * 25).ms).fadeIn(duration: 200.ms),
          )),
      ]);
    }

    return Column(children: [
      _buildFilterChips(),
      Expanded(child: folders.isEmpty
        ? _buildFilterEmpty()
        : RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: t.surface,
          onRefresh: () => _load(refresh: true),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
            itemCount: folders.length,
            itemBuilder: (_, i) => _FolderListTile(
              folder: folders[i],
              thumb: _thumbCache[folders[i].path],
              progress: _folderProgress(folders[i]),
              isWatched: _folderWatched(folders[i]),
              isInProgress: _folderInProgress(folders[i]),
              onTap: () => _openFolder(folders[i]),
              onLongPress: () => _showFolderMenu(folders[i]),
            ).animate(delay: (i * 20).ms).fadeIn(duration: 200.ms),
          ),
        )),
    ]);
  }

  Widget _buildPermissionError() {
    final t = RaddTheme.of(context);
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: AppColors.error.withOpacity(0.1)),
          child: Icon(AppIcons.folderX, color: AppColors.error, size: 40)),
        const SizedBox(height: 24),
        Text('Storage Permission Required',
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('RaddFlix needs permission to browse your files',
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () => MethodChannel('com.raddflix.app/media_store').invokeMethod('openAppSettings'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.round),
              boxShadow: AppShadows.primary,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.settings, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Open Settings', style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: _load, child: Text('Try Again', style: TextStyle(color: t.textSecondary))),
      ]),
    ));
  }

  Widget _buildEmpty() {
    final t = RaddTheme.of(context);
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 84, height: 84,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.surface,
            border: Border.all(color: t.border, width: 1.5)),
        child: Center(child: AnimatedWifiOffIcon(size: 46, color: t.textMuted))),
      const SizedBox(height: 18),
      Text(_searchQuery.isNotEmpty ? 'No folders match "$_searchQuery"' : 'No media files found',
          style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Videos and audio on your device will appear here.',
          style: TextStyle(color: t.textMuted, fontSize: 13)),
    ]));
  }

  Widget _buildShimmer() {
    final t = RaddTheme.of(context);
    return ListView.builder(
      itemCount: 7,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.surfaceHigh,
        child: Container(
          height: 72,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.md))),
      ),
    );
  }
}

// ── Sort bottom sheet ─────────────────────────────────────────────────────────
class _SortSheet extends StatefulWidget {
  final _SortBy sortBy;
  final bool ascending;
  final _LayoutMode layout;
  final void Function(_SortBy, bool, _LayoutMode) onChanged;

  const _SortSheet({
    required this.sortBy,
    required this.ascending,
    required this.layout,
    required this.onChanged,
  });

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late _SortBy _sortBy;
  late bool _ascending;
  late _LayoutMode _layout;

  @override
  void initState() {
    super.initState();
    _sortBy    = widget.sortBy;
    _ascending = widget.ascending;
    _layout    = widget.layout;
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: t.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 16),
              // Header
              Row(children: [
                Text('Sort & View', style: TextStyle(color: t.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    widget.onChanged(_sortBy, _ascending, _layout);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                    ),
                    child: const Text('Done', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Layout ──
              Text('Layout', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                _layoutBtn(context, t, _LayoutMode.list, AppIcons.listView, 'List'),
                const SizedBox(width: 10),
                _layoutBtn(context, t, _LayoutMode.grid, AppIcons.gridView, 'Grid'),
              ]),
              const SizedBox(height: 20),

              // ── Sort by ──
              Text('Sort By', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _sortChip(context, t, _SortBy.date,     AppIcons.clock,       'Date'),
                _sortChip(context, t, _SortBy.name,     AppIcons.sort,     'Name'),
                _sortChip(context, t, _SortBy.size,     AppIcons.storage,           'Size'),
                _sortChip(context, t, _SortBy.count,    AppIcons.videoLibrary,     'Count'),
                _sortChip(context, t, _SortBy.duration, AppIcons.timerIcon,            'Duration'),
              ]),
              const SizedBox(height: 20),

              // ── Direction ──
              Text('Order', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dirBtn(context, t, true,  AppIcons.arrowUp,   'A → Z  (Ascending)')),
                const SizedBox(width: 10),
                Expanded(child: _dirBtn(context, t, false, AppIcons.arrowDown, 'Z → A  (Descending)')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutBtn(BuildContext ctx, dynamic t, _LayoutMode mode, IconData icon, String label) {
    final active = _layout == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _layout = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : t.card,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? AppColors.primary : t.border, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
                color: active ? AppColors.primary : t.textMuted,
                fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _sortChip(BuildContext ctx, dynamic t, _SortBy mode, IconData icon, String label) {
    final active = _sortBy == mode;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: active ? AppColors.primary : t.textSecondary,
              fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _dirBtn(BuildContext ctx, dynamic t, bool asc, IconData icon, String label) {
    final active = _ascending == asc;
    return GestureDetector(
      onTap: () => setState(() => _ascending = asc),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: active ? AppColors.primary : t.textSecondary,
              fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

// ── Folder list tile ──────────────────────────────────────────────────────────
class _FolderListTile extends StatelessWidget {
  final LocalFolder folder;
  final Uint8List? thumb;
  final VoidCallback onTap;
  final double progress;
  final bool isWatched;
  final bool isInProgress;
  final VoidCallback? onLongPress;
  const _FolderListTile({required this.folder, required this.thumb, required this.onTap,
      this.progress = 0.0, this.isWatched = false, this.isInProgress = false, this.onLongPress});

  Widget _statusBadge(RaddTheme t) {
    if (isWatched) return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
      child: const Text('WATCHED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3)));
    if (isInProgress && progress > 0) return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFF97316).withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
      child: Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)));
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final t    = RaddTheme.of(context);
    final type = folder.folderType;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            // Thumbnail / type icon
            Container(
              width: 68, height: 58,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: t.border, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm - 0.5),
                    child: thumb != null
                        ? Image.memory(thumb!, fit: BoxFit.cover)
                        : Center(child: Icon(
                            type == 'audio' ? AppIcons.music
                                : type == 'mixed' ? AppIcons.videoLibrary
                                : AppIcons.localMediaFill,
                            color: type == 'audio' ? AppColors.primary : t.textMuted,
                            size: 28)),
                  ),
                  if (isInProgress && progress > 0 && !isWatched)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.black45,
                        color: const Color(0xFFF97316),
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      type == 'audio'
                          ? '${folder.audioCount} track${folder.audioCount == 1 ? '' : 's'}'
                          : '${folder.videos.length} file${folder.videos.length == 1 ? '' : 's'}',
                      style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  // Mixed indicator
                  if (type == 'mixed') ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: t.border),
                      ),
                      child: Text('${folder.audioCount}🎵 ${folder.videoCount}🎬',
                          style: TextStyle(color: t.textMuted, fontSize: 9)),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(folder.formattedTotalSize,
                      style: TextStyle(color: t.textMuted, fontSize: 11)),
                ]),
              ],
            )),
            // New badge
            if (folder.newCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                ),
                child: Text(folder.newCount > 99 ? '99+' : '${folder.newCount} new',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            Icon(AppIcons.caretRight, color: t.textMuted, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Folder grid card ──────────────────────────────────────────────────────────
class _FolderGridCard extends StatelessWidget {
  final LocalFolder folder;
  final Uint8List? thumb;
  final VoidCallback onTap;
  final double progress;
  final bool isWatched;
  final bool isInProgress;
  final VoidCallback? onLongPress;
  const _FolderGridCard({required this.folder, required this.thumb, required this.onTap,
      this.progress = 0.0, this.isWatched = false, this.isInProgress = false, this.onLongPress});

  Widget _statusBadge() {
    if (isWatched) return Positioned(top: 4, left: 4, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
      child: const Text('✓ WATCHED', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))));
    if (isInProgress && progress > 0) return Positioned(top: 4, left: 4, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFF97316).withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
      child: Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))));
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final t    = RaddTheme.of(context);
    final type = folder.folderType;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(fit: StackFit.expand, children: [
          thumb != null
              ? Image.memory(thumb!, fit: BoxFit.cover)
              : Container(
                  color: type == 'audio' ? AppColors.primary.withOpacity(0.1) : t.surface,
                  child: Icon(
                    type == 'audio' ? AppIcons.music
                        : type == 'mixed' ? AppIcons.videoLibrary
                        : AppIcons.localMediaFill,
                    color: type == 'audio' ? AppColors.primary : t.textMuted,
                    size: 36)),
          // Gradient scrim
          DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [0.0, 0.45, 1.0],
              colors: [Colors.transparent, Colors.black45, Colors.black87]),
          )),
          // Labels
          Positioned(bottom: 8, left: 10, right: 10, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                type == 'audio'
                    ? '${folder.audioCount} tracks  ${folder.formattedTotalSize}'
                    : '${folder.videos.length} files  ${folder.formattedTotalSize}',
                style: const TextStyle(color: Colors.white60, fontSize: 10)),
            ],
          )),
          if (folder.newCount > 0)
            Positioned(top: 6, right: 6,
              child: Container(
                width: 20, height: 20,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary),
                child: Center(child: Text('${folder.newCount}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w800))))),
          // Audio badge
          if (type == 'audio')
            Positioned(top: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('MUSIC', style: TextStyle(color: Colors.white,
                    fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              )),
          // WATCHED / WATCHING badge (top-left)
          _statusBadge(),
          // Watch progress bar (bottom edge)
          if (isInProgress && progress > 0 && !isWatched)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.black45,
                color: const Color(0xFFF97316),
                minHeight: 3,
              ),
            ),
        ]),
      ),
    );
  }
}
