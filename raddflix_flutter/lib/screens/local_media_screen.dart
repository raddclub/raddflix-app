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
import '../widgets/mini_player_bar.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/motion/radd_motion.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';
import '../widgets/animated_empty_icons.dart';
import '../core/db/local_db.dart';
import '../services/vault_service.dart';

class LocalMediaScreen extends StatefulWidget {
  // UX4-01: showBottomNav=false when embedded inside the HomeScreen IndexedStack shell
  final bool showBottomNav;
  const LocalMediaScreen({super.key, this.showBottomNav = true});
  @override
  State<LocalMediaScreen> createState() => _LocalMediaScreenState();
}

enum _SortBy { name, date, size, count, duration }
enum _MusicSortBy { title, artist, album, date, duration }
enum _LayoutMode { list, grid }
enum _WatchFilter { all, inProgress, watched }

class _LocalMediaScreenState extends State<LocalMediaScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final TabController _tabController;

  // ── Videos tab state ───────────────────────────────────────────────────────
  List<LocalFolder> _folders = [];
  bool _loading = true;
  bool _permissionDenied = false;
  _SortBy _sortBy = _SortBy.date;
  bool _sortAscending = false;
  _LayoutMode _layout = _LayoutMode.list;
  _WatchFilter _watchFilter = _WatchFilter.all;
  Map<String, int> _posMap = {};
  Map<String, int> _durMap = {};
  final Map<String, Uint8List?> _thumbCache = {};
  static const _kThumbCacheMax = 80;

  // ── Music tab state ────────────────────────────────────────────────────────
  List<LocalVideo> _musicTracks = [];
  bool _musicLoading = false;
  bool _audioPermissionDenied = false;
  _MusicSortBy _musicSortBy = _MusicSortBy.date;
  bool _musicSortAscending = false;
  final Map<int, Uint8List?> _albumArtCache = {};
  static const _kAlbumArtCacheMax = 120;

  // ── Shared state ───────────────────────────────────────────────────────────
  String _searchQuery = '';
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;

  // Resume last video
  String? _resumePath;
  String? _resumeTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _load();
    _loadMusic();
    _loadResume();
    _loadWatchPositions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Videos tab methods ─────────────────────────────────────────────────────
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

  // ── Music tab methods ──────────────────────────────────────────────────────
  Future<void> _loadMusic({bool refresh = false}) async {
    if (_musicLoading && !refresh) return;
    setState(() { _musicLoading = true; });
    final hasAudio = await LocalMediaService.checkAudioPermission();
    if (!hasAudio) {
      setState(() { _musicLoading = false; _audioPermissionDenied = true; });
      return;
    }
    final tracks = await LocalMediaService.queryAllAudio();
    setState(() { _musicTracks = tracks; _musicLoading = false; _audioPermissionDenied = false; });
    _loadAlbumArts(tracks);
  }

  void _evictAlbumArtCache() {
    if (_albumArtCache.length <= _kAlbumArtCacheMax) return;
    final toRemove = _albumArtCache.keys.take(_albumArtCache.length ~/ 2).toList();
    for (final k in toRemove) _albumArtCache.remove(k);
  }

  Future<void> _loadAlbumArts(List<LocalVideo> tracks) async {
    // Collect unique album IDs — one art request per album, not per track
    final seenIds = <int>{};
    final toFetch = <LocalVideo>[];
    for (final t in tracks) {
      final aid = t.albumId ?? 0;
      if (aid > 0 && !_albumArtCache.containsKey(aid) && seenIds.add(aid)) {
        toFetch.add(t);
      }
    }
    const batchSize = 6;
    for (int i = 0; i < toFetch.length; i += batchSize) {
      if (!mounted) return;
      _evictAlbumArtCache();
      final batch = toFetch.skip(i).take(batchSize).toList();
      final results = <int, Uint8List?>{};
      await Future.wait(batch.map((track) async {
        final aid = track.albumId!;
        results[aid] = await LocalMediaService.getAlbumArt(aid, size: 120);
      }));
      if (mounted && results.isNotEmpty) {
        setState(() => _albumArtCache.addAll(results));
      }
    }
  }

  // ── Computed lists ─────────────────────────────────────────────────────────
  List<LocalFolder> get _sorted {
    final isVideosTab = _tabController.index == 0;
    List<LocalFolder> list = (_searchQuery.isEmpty || !isVideosTab)
        ? List.from(_folders)
        : _folders.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    switch (_sortBy) {
      case _SortBy.name:
        list.sort((a, b) => _sortAscending ? a.name.compareTo(b.name) : b.name.compareTo(a.name));
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

  // Videos tab: exclude pure-audio folders — they live in the Music tab now
  List<LocalFolder> get _videoFolders =>
      _sorted.where((f) => f.folderType != 'audio').toList();

  List<LocalFolder> get _filtered {
    final s = _videoFolders;
    switch (_watchFilter) {
      case _WatchFilter.all: return s;
      case _WatchFilter.inProgress: return s.where(_folderInProgress).toList();
      case _WatchFilter.watched: return s.where(_folderWatched).toList();
    }
  }

  List<LocalVideo> get _musicFiltered {
    List<LocalVideo> list = List.from(_musicTracks);
    if (_searchQuery.isNotEmpty && _tabController.index == 1) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) =>
          t.title.toLowerCase().contains(q) ||
          (t.artist ?? '').toLowerCase().contains(q) ||
          (t.album  ?? '').toLowerCase().contains(q)).toList();
    }
    switch (_musicSortBy) {
      case _MusicSortBy.title:
        list.sort((a, b) => _musicSortAscending
            ? a.title.compareTo(b.title) : b.title.compareTo(a.title));
      case _MusicSortBy.artist:
        list.sort((a, b) => _musicSortAscending
            ? (a.artist ?? '').compareTo(b.artist ?? '')
            : (b.artist ?? '').compareTo(a.artist ?? ''));
      case _MusicSortBy.album:
        list.sort((a, b) => _musicSortAscending
            ? (a.album ?? '').compareTo(b.album ?? '')
            : (b.album ?? '').compareTo(a.album ?? ''));
      case _MusicSortBy.date:
        list.sort((a, b) => _musicSortAscending
            ? a.dateModifiedMs.compareTo(b.dateModifiedMs)
            : b.dateModifiedMs.compareTo(a.dateModifiedMs));
      case _MusicSortBy.duration:
        list.sort((a, b) => _musicSortAscending
            ? a.durationMs.compareTo(b.durationMs)
            : b.durationMs.compareTo(a.durationMs));
    }
    return list;
  }

  int get _totalVideoFiles => _videoFolders.fold(0, (s, f) => s + f.videoCount);

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

  // ── Actions ────────────────────────────────────────────────────────────────
  void _playMusic(LocalVideo track) {
    final list = _musicFiltered;
    final idx = list.indexWhere((t) => t.filePath == track.filePath);
    final startIndex = idx < 0 ? 0 : idx;
    final episodes = list.asMap().entries.map((e) => <String, dynamic>{
      'file_id': '',
      'title': e.value.title,
      'label': e.value.title,
      'local_path': e.value.filePath,
      'episode': e.key + 1,
    }).toList();
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id': '',
      'title': list[startIndex].title,
      'local_path': list[startIndex].filePath,
      'episodes': episodes,
      'episode_index': startIndex,
      'content_type': 'local',
      'is_free': true,
    });
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
          const SizedBox(height: RaddSpace.sm),
        ]),
      ),
    );
  }

  Future<void> _addFolderToVault(LocalFolder folder) async {
    final t = RaddTheme.of(context);
    final hasPin = await VaultService.hasPin();
    if (!hasPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Set up your vault PIN first (Profile → Vault)'),
        backgroundColor: t.surface));
      return;
    }
    if (!VaultService.isUnlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Unlock your vault first (Profile → Vault → Unlock)'),
        backgroundColor: t.surface));
      return;
    }
    final videos = folder.videos.where((v) => v.isVideo).toList();
    if (videos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No video files in this folder'),
        backgroundColor: t.surface));
      return;
    }
    final total = videos.length;
    final progress = ValueNotifier<int>(0);
    if (!mounted) { progress.dispose(); return; }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: t.surface,
          title: Text('Moving to Vault',
              style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, val, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total > 0 ? val / total : null,
                    backgroundColor: t.border,
                    color: AppColors.primary,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Text('$val of $total videos',
                    style: TextStyle(color: t.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    ).ignore();
    final contentUris = <String>[
      for (final v in videos)
        if (v.id > 0) 'content://media/external/video/media/${v.id}',
    ];
    int count = 0;
    bool mediaDeleted = true;
    try {
      await VaultService.moveFilesToVaultBatch(
        videos.map((v) => v.filePath).toList(),
        onProgress: (done, _) { count = done; progress.value = done; },
      );
      if (contentUris.isNotEmpty) {
        mediaDeleted = await VaultService.deleteFromMediaStore(contentUris);
      }
    } finally {
      progress.dispose();
      if (mounted) {
        try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
      }
    }
    if (!mounted) return;
    final baseMsg = count > 0
        ? '$count video${count != 1 ? "s" : ""} moved to vault'
        : 'No accessible files to move';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0 && !mediaDeleted
          ? '$baseMsg • May still appear in gallery'
          : baseMsg),
      backgroundColor: t.surface,
      duration: Duration(seconds: count > 0 && !mediaDeleted ? 5 : 3)));
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

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    super.build(context);
    final isMusic = _tabController.index == 1;
    return Scaffold(
      backgroundColor: t.bg,
      floatingActionButton: _resumePath != null && !isMusic
          ? FloatingActionButton.extended(
              onPressed: _resumeLastVideo,
              backgroundColor: AppColors.primary,
              icon: Icon(AppIcons.playCircleFill, color: Colors.white, size: 22),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resume', style: TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.w600, height: 1.1)),
                  Text(_resumeTitle ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.1),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            )
          : null,
      // UX4-01: nav bar hidden when embedded in HomeScreen's IndexedStack shell
      // NAV-RESTRUCTURE: Local is now tab 1 (was tab 2).
      bottomNavigationBar: widget.showBottomNav ? MiniPlayerDock(
        child: RaddFlixBottomNav(
          currentIndex: 1,
          onTap: (i) {
            if (i == 1) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
            if (i == 2) Navigator.of(context).pushNamed(AppRoutes.profile);
          },
        ),
      ) : null,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          _buildTabBar(),
          if (_searching) _buildSearchBar(),
          Expanded(
            // _permissionDenied (video) is handled inside _buildVideosTab() so
            // it does not mask the Music tab on API 33+ devices that granted
            // READ_MEDIA_AUDIO but denied READ_MEDIA_VIDEO.
            child: TabBarView(
              controller: _tabController,
              // Disable swipe — the folder list and track list are horizontal
              // scroll containers themselves; swipe-to-switch tabs would
              // conflict and mis-fire constantly while scrolling content.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildVideosTab(),
                _buildMusicTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final t = RaddTheme.of(context);
    final isMusic = _tabController.index == 1;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        RichText(text: TextSpan(
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          children: [
            TextSpan(text: 'Local ', style: TextStyle(color: t.textPrimary)),
            TextSpan(text: isMusic ? 'Music' : 'Media',
                style: TextStyle(color: AppColors.primary)),
          ],
        )),
        const Spacer(),
        // Count badge
        if (!_loading && (_folders.isNotEmpty || _musicTracks.isNotEmpty))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.round),
              border: Border.all(color: t.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isMusic ? AppIcons.music : AppIcons.videoLibrary,
                  size: 11, color: AppColors.primary),
              const SizedBox(width: RaddSpace.xs),
              Text(
                isMusic ? '${_musicFiltered.length}' : '$_totalVideoFiles',
                style: TextStyle(color: t.textMuted,
                    fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(width: 6),
        // Search
        IconButton(
          icon: Icon(_searching ? AppIcons.close : AppIcons.search,
              color: t.textSecondary, size: 22),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) { _searchQuery = ''; _searchCtrl.clear(); }
            else _searchFocus.requestFocus();
          }),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Layout toggle (videos tab only)
        if (!isMusic) IconButton(
          icon: Icon(
            _layout == _LayoutMode.list ? AppIcons.gridView : AppIcons.listView,
            color: t.textSecondary, size: 22),
          onPressed: () => setState(() =>
              _layout = _layout == _LayoutMode.list ? _LayoutMode.grid : _LayoutMode.list),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Sort sheet (videos tab only — music uses inline sort pills)
        if (!isMusic) IconButton(
          icon: Icon(AppIcons.sort, color: t.textSecondary, size: 22),
          onPressed: _showSortSheet,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Refresh (music tab)
        if (isMusic) IconButton(
          icon: Icon(AppIcons.refresh, color: t.textSecondary, size: 22),
          onPressed: () => _loadMusic(refresh: true),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
      ]),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    final t = RaddTheme.of(context);
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: t.textMuted,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.all(4),
        tabs: [
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(AppIcons.videoLibrary, size: 14),
            const SizedBox(width: 6),
            const Text('Videos'),
          ])),
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(AppIcons.music, size: 14),
            const SizedBox(width: 6),
            const Text('Music'),
          ])),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    final t = RaddTheme.of(context);
    final isMusic = _tabController.index == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(RaddMotion.tuneDuration, () {
            if (mounted) setState(() => _searchQuery = v);
          });
        },
        style: TextStyle(color: t.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: isMusic ? 'Search tracks, artists, albums…' : 'Search folders…',
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

  // ── Videos tab ─────────────────────────────────────────────────────────────
  Widget _buildVideosTab() {
    return Column(children: [
      _buildPlayFromUrlRow(),
      Expanded(child: _buildVideosContent()),
    ]);
  }

  Widget _buildVideosContent() {
    if (_permissionDenied) return _buildPermissionError();
    if (_loading) return _buildShimmer();
    if (_videoFolders.isEmpty) return _buildEmpty(isMusic: false);
    return Column(children: [
      _buildFilterChips(),
      Expanded(child: _filtered.isEmpty
          ? _buildFilterEmpty()
          : _buildFolderContent()),
    ]);
  }

  // NET-STREAM-1: "Play from URL" entry point at the top of the Videos tab.
  Widget _buildPlayFromUrlRow() {
    final t = RaddTheme.of(context);
    return InkWell(
      onTap: _showPlayFromUrlDialog,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RaddRadius.mdRadius,
          border: Border.all(color: t.border),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(AppIcons.link, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Play from URL',
                  style: TextStyle(color: t.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text('m3u8 · mp4 · mkv · any direct stream link',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
            ]),
          ),
          Icon(AppIcons.caretRight, size: 16, color: t.textMuted),
        ]),
      ),
    );
  }

  void _showPlayFromUrlDialog() {
    final t = RaddTheme.of(context);
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: RaddRadius.mdRadius),
        title: Text('Play from URL',
            style: TextStyle(color: t.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Paste a direct stream link (m3u8, mp4, mkv, etc.)',
              style: TextStyle(color: t.textMuted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            style: TextStyle(color: t.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://example.com/stream.m3u8',
              hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
              filled: true,
              fillColor: t.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: RaddRadius.smRadius,
                borderSide: BorderSide(color: t.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: RaddRadius.smRadius,
                borderSide: BorderSide(color: t.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: RaddRadius.smRadius,
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onSubmitted: (v) {
              Navigator.of(ctx).pop();
              _playNetworkUrl(v.trim());
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: t.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final url = ctrl.text.trim();
              Navigator.of(ctx).pop();
              _playNetworkUrl(url);
            },
            child: Text('Play', style: TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _playNetworkUrl(String url) {
    if (url.isEmpty) return;
    // Prepend https:// if the user omitted the scheme
    final resolved = (url.startsWith('http://') || url.startsWith('https://'))
        ? url
        : 'https://$url';
    final title = (() {
      try {
        final segs = Uri.parse(resolved).pathSegments;
        final last = segs.isNotEmpty ? segs.last : '';
        return last.isNotEmpty ? Uri.decodeFull(last) : resolved;
      } catch (_) { return resolved; }
    })();
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id': 'net_${resolved.hashCode}',
      'title': title,
      'stream_url': resolved,
      'content_type': 'network',
      'is_free': true,
    });
  }

  Widget _buildFolderContent() {
    final t = RaddTheme.of(context);
    final folders = _filtered;
    if (_layout == _LayoutMode.grid) {
      return GridView.builder(
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
      );
    }
    return RefreshIndicator(
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
    );
  }

  Widget _buildFilterChips() {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        _filterChip(t, _WatchFilter.all,        'All',      AppIcons.localMediaFill),
        const SizedBox(width: RaddSpace.sm),
        _filterChip(t, _WatchFilter.inProgress, 'Watching', AppIcons.playCircle),
        const SizedBox(width: RaddSpace.sm),
        _filterChip(t, _WatchFilter.watched,    'Watched',  AppIcons.successIcon),
      ]),
    );
  }

  Widget _filterChip(RaddTheme t, _WatchFilter filter, String label, IconData icon) {
    final active = _watchFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _watchFilter = filter),
      child: AnimatedContainer(
        duration: RaddMotion.tuneDuration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppColors.primary : t.border, width: active ? 1.5 : 1),
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

  // ── Music tab ──────────────────────────────────────────────────────────────
  Widget _buildMusicTab() {
    if (_musicLoading) return _buildMusicShimmer();
    if (_audioPermissionDenied) return _buildAudioPermissionError();
    final tracks = _musicFiltered;
    if (tracks.isEmpty) return _buildEmpty(isMusic: true);
    return Column(children: [
      _buildMusicSortBar(),
      Expanded(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: RaddTheme.of(context).surface,
          onRefresh: () => _loadMusic(refresh: true),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
            itemCount: tracks.length,
            itemBuilder: (_, i) => _buildMusicTrackTile(tracks[i], i),
          ),
        ),
      ),
    ]);
  }

  Widget _buildMusicSortBar() {
    final t = RaddTheme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          _musicSortPill(t, _MusicSortBy.date,     'Recent'),
          const SizedBox(width: 8),
          _musicSortPill(t, _MusicSortBy.title,    'Title'),
          const SizedBox(width: 8),
          _musicSortPill(t, _MusicSortBy.artist,   'Artist'),
          const SizedBox(width: 8),
          _musicSortPill(t, _MusicSortBy.album,    'Album'),
          const SizedBox(width: 8),
          _musicSortPill(t, _MusicSortBy.duration, 'Duration'),
        ],
      ),
    );
  }

  Widget _musicSortPill(RaddTheme t, _MusicSortBy mode, String label) {
    final active = _musicSortBy == mode;
    return GestureDetector(
      onTap: () => setState(() {
        if (_musicSortBy == mode) {
          _musicSortAscending = !_musicSortAscending;
        } else {
          _musicSortBy = mode;
          // Default to ascending for text sorts, descending for date/duration
          _musicSortAscending = mode == _MusicSortBy.title ||
              mode == _MusicSortBy.artist || mode == _MusicSortBy.album;
        }
      }),
      child: AnimatedContainer(
        duration: RaddMotion.tuneDuration,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppColors.primary : t.border, width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? AppColors.primary : t.textMuted)),
          if (active) ...[
            const SizedBox(width: 4),
            Icon(
              _musicSortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 12, color: AppColors.primary),
          ],
        ]),
      ),
    );
  }

  Widget _buildMusicTrackTile(LocalVideo track, int index) {
    final t = RaddTheme.of(context);
    final albumArt = track.albumId != null ? _albumArtCache[track.albumId!] : null;
    final artist = track.artist ?? '';
    final album  = track.album  ?? '';
    final subtitle = [artist, album].where((s) => s.isNotEmpty).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playMusic(track),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(children: [
            // Album art / placeholder
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: t.border, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: albumArt != null
                  ? Image.memory(albumArt, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.primary.withOpacity(0.08),
                      child: Center(child: Icon(AppIcons.music,
                          color: AppColors.primary.withOpacity(0.55), size: 24)),
                    ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 12)),
                  ],
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(track.formattedDuration,
                          style: TextStyle(color: AppColors.primary,
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Text(track.formattedSize,
                        style: TextStyle(color: t.textMuted, fontSize: 10)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(AppIcons.playCircle, color: t.textMuted, size: 20),
          ]),
        ),
      ),
    ).animate(delay: (index * 15).ms).fadeIn(duration: 200.ms);
  }

  // ── Shared empty / shimmer / permission ────────────────────────────────────
  Widget _buildEmpty({required bool isMusic}) {
    final t = RaddTheme.of(context);
    final hasSearch = _searchQuery.isNotEmpty;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 84, height: 84,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.surface,
            border: Border.all(color: t.border, width: 1.5)),
        child: Center(child: hasSearch
            ? Icon(AppIcons.search, size: 40, color: t.textMuted)
            : AnimatedWifiOffIcon(size: 46, color: t.textMuted))),
      const SizedBox(height: 18),
      Text(
        hasSearch
            ? 'No ${isMusic ? "tracks" : "folders"} match "$_searchQuery"'
            : isMusic ? 'No music found on device' : 'No media files found',
        style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        isMusic
            ? 'Audio files from your Music folder will appear here.'
            : 'Videos and audio on your device will appear here.',
        style: TextStyle(color: t.textMuted, fontSize: 13),
        textAlign: TextAlign.center),
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

  Widget _buildMusicShimmer() {
    final t = RaddTheme.of(context);
    return ListView.builder(
      itemCount: 10,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.surfaceHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
          child: Row(children: [
            Container(width: 52, height: 52,
                decoration: BoxDecoration(color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm))),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 14, width: double.infinity, color: t.surface),
                const SizedBox(height: 6),
                Container(height: 11, width: 160, color: t.surface),
                const SizedBox(height: 6),
                Container(height: 18, width: 80, color: t.surface),
              ],
            )),
          ]),
        ),
      ),
    );
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
        const SizedBox(height: RaddSpace.lg),
        Text('Storage Permission Required',
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('RaddFlix needs permission to browse your files',
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () => const MethodChannel('com.raddflix.app/media_store')
              .invokeMethod('openAppSettings'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.round),
              boxShadow: AppShadows.primary,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.settings, size: 18, color: Colors.white),
              const SizedBox(width: RaddSpace.sm),
              const Text('Open Settings', style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
            onPressed: _load,
            child: Text('Try Again', style: TextStyle(color: t.textSecondary))),
      ]),
    ));
  }

  Widget _buildAudioPermissionError() {
    final t = RaddTheme.of(context);
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.08)),
          child: Icon(AppIcons.music, color: AppColors.primary, size: 40)),
        const SizedBox(height: RaddSpace.lg),
        Text('Music Permission Required',
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Allow RaddFlix to read audio files so your music appears here.',
            style: TextStyle(color: t.textMuted, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () => const MethodChannel('com.raddflix.app/media_store')
              .invokeMethod('openAppSettings'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.round),
              boxShadow: AppShadows.primary,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.settings, size: 18, color: Colors.white),
              const SizedBox(width: RaddSpace.sm),
              const Text('Open Settings', style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
            onPressed: () => _loadMusic(refresh: true),
            child: Text('Try Again', style: TextStyle(color: t.textSecondary))),
      ]),
    ));
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
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: t.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: RaddSpace.md),
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
              Text('Layout', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                _layoutBtn(context, t, _LayoutMode.list, AppIcons.listView, 'List'),
                const SizedBox(width: 10),
                _layoutBtn(context, t, _LayoutMode.grid, AppIcons.gridView, 'Grid'),
              ]),
              const SizedBox(height: 20),
              Text('Sort By', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _sortChip(context, t, _SortBy.date,     AppIcons.clock,        'Date'),
                _sortChip(context, t, _SortBy.name,     AppIcons.sort,         'Name'),
                _sortChip(context, t, _SortBy.size,     AppIcons.storage,      'Size'),
                _sortChip(context, t, _SortBy.count,    AppIcons.videoLibrary, 'Count'),
                _sortChip(context, t, _SortBy.duration, AppIcons.timerIcon,    'Duration'),
              ]),
              const SizedBox(height: 20),
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
            border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 22),
            const SizedBox(height: RaddSpace.xs),
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
      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
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
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.black45,
                        color: const Color(0xFFF97316),
                        minHeight: 3,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Text info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  if (folder.newCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text('${folder.newCount}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 10, fontWeight: FontWeight.w800))),
                  ],
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  _statusBadge(t),
                  if (isWatched || (isInProgress && progress > 0)) const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      type == 'audio'
                          ? '${folder.audioCount} tracks  •  ${folder.formattedTotalSize}'
                          : type == 'mixed'
                              ? '${folder.videoCount} videos  ${folder.audioCount} audio  •  ${folder.formattedTotalSize}'
                              : '${folder.videos.length} files  •  ${folder.formattedTotalSize}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textMuted, fontSize: 11)),
                  ),
                ]),
              ],
            )),
            Icon(AppIcons.caretRight, color: t.textMuted, size: 16),
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
      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.9), borderRadius: BorderRadius.circular(4)),
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
          DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [0.0, 0.45, 1.0],
              colors: [Colors.transparent, Colors.black45, Colors.black87]),
          )),
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
          _statusBadge(),
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
