import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/theme/radd_theme.dart';
import '../models/local_video.dart';
import '../services/local_media_service.dart';
import '../core/db/local_db.dart';
import 'player_screen.dart';

class LocalFolderScreen extends StatefulWidget {
  final LocalFolder folder;
  const LocalFolderScreen({super.key, required this.folder});
  @override
  State<LocalFolderScreen> createState() => _LocalFolderScreenState();
}

enum _SortBy    { name, date, size, duration, resolution, type }
enum _TypeFilter { all, video, audio }
enum _LayoutMode { list, grid }

class _LocalFolderScreenState extends State<LocalFolderScreen> {
  late List<LocalVideo> _videos;
  _SortBy      _sortBy       = _SortBy.date;
  bool         _sortAscending = false;
  _TypeFilter  _typeFilter   = _TypeFilter.all;
  _LayoutMode  _layout       = _LayoutMode.list;
  String _searchQuery = '';
  bool _searching   = false;
  bool _selecting   = false;
  final Set<String> _selected = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Map<String, Uint8List?> _thumbCache = {};
  bool _loadingThumbs = true;

  // Series grouping
  bool _groupingEnabled = true;
  final Map<String, bool> _groupExpanded = {};

  @override
  void initState() {
    super.initState();
    _videos = List.from(widget.folder.videos);
    _loadThumbnails();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnails() async {
    const batchSize = 4;
    for (int i = 0; i < _videos.length; i += batchSize) {
      if (!mounted) return;
      final batch = _videos.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((v) async {
        if (_thumbCache.containsKey(v.filePath)) return;
        // Audio files — no video thumbnail, show null (music icon)
        if (v.isAudio) {
          if (mounted) setState(() => _thumbCache[v.filePath] = null);
          return;
        }
        Uint8List? thumb;
        if (v.id > 0) {
          thumb = await LocalMediaService.getThumbnailById(v.id, size: 220);
        }
        thumb ??= await LocalMediaService.getThumbnail(v.filePath, quality: 55, maxDimension: 220);
        if (mounted) setState(() => _thumbCache[v.filePath] = thumb);
      }));
    }
    if (mounted) setState(() => _loadingThumbs = false);
  }

  List<LocalVideo> get _sorted {
    List<LocalVideo> list;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      list = _videos.where((v) =>
          v.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          v.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    } else {
      list = List.from(_videos);
    }

    // Type filter
    switch (_typeFilter) {
      case _TypeFilter.video: list = list.where((v) => v.isVideo).toList();
      case _TypeFilter.audio: list = list.where((v) => v.isAudio).toList();
      case _TypeFilter.all:   break;
    }

    // Sort
    switch (_sortBy) {
      case _SortBy.name:
        list.sort((a, b) => _sortAscending
            ? a.title.compareTo(b.title)
            : b.title.compareTo(a.title));
      case _SortBy.size:
        list.sort((a, b) => _sortAscending
            ? a.sizeBytes.compareTo(b.sizeBytes)
            : b.sizeBytes.compareTo(a.sizeBytes));
      case _SortBy.duration:
        list.sort((a, b) => _sortAscending
            ? a.durationMs.compareTo(b.durationMs)
            : b.durationMs.compareTo(a.durationMs));
      case _SortBy.date:
        list.sort((a, b) => _sortAscending
            ? a.dateModifiedMs.compareTo(b.dateModifiedMs)
            : b.dateModifiedMs.compareTo(a.dateModifiedMs));
      case _SortBy.resolution:
        list.sort((a, b) {
          final ra = (a.width < a.height ? a.width : a.height);
          final rb = (b.width < b.height ? b.width : b.height);
          return _sortAscending ? ra.compareTo(rb) : rb.compareTo(ra);
        });
      case _SortBy.type:
        list.sort((a, b) {
          // Audio first or video first based on direction
          final av = a.isAudio ? 0 : 1;
          final bv = b.isAudio ? 0 : 1;
          return _sortAscending ? av.compareTo(bv) : bv.compareTo(av);
        });
    }

    return list;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FolderSortSheet(
        sortBy: _sortBy,
        ascending: _sortAscending,
        typeFilter: _typeFilter,
        layout: _layout,
        onChanged: (sortBy, ascending, typeFilter, layout) {
          setState(() {
            _sortBy        = sortBy;
            _sortAscending = ascending;
            _typeFilter    = typeFilter;
            _layout        = layout;
          });
        },
      ),
    );
  }

  void _playVideo(LocalVideo video) {
    final sorted = _sorted;
    final idx = sorted.indexWhere((v) => v.filePath == video.filePath);
    final startIndex = idx < 0 ? 0 : idx;
    final episodes = sorted.map((v) => <String, dynamic>{
      'file_id': '',
      'title': v.title,
      'label': v.title,
      'local_path': v.filePath,
      'episode': sorted.indexOf(v) + 1,
    }).toList();
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id': '',
      'title': sorted[startIndex].title,
      'local_path': sorted[startIndex].filePath,
      'subtitle_path': video.subtitlePath,
      'episodes': episodes,
      'episode_index': startIndex,
      'content_type': 'local',
    });
  }

  void _playAll() async {
    if (_videos.isEmpty) return;
    final sorted = _sorted;
    final episodes = sorted.map((v) => <String, dynamic>{
      'file_id': '',
      'title': v.title,
      'label': v.title,
      'local_path': v.filePath,
      'episode': sorted.indexOf(v) + 1,
    }).toList();
    int startIndex = 0;
    try {
      final positions = await LocalDb.getWatchPositions();
      final posMap = <String, int>{
        for (final p in positions)
          (p['file_id'] as String? ?? ''): (p['position_ms'] as int? ?? 0),
      };
      for (int i = 0; i < sorted.length; i++) {
        if ((posMap[sorted[i].filePath] ?? 0) > 0) {
          startIndex = i;
          break;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
      'file_id': '',
      'title': sorted[startIndex].title,
      'local_path': sorted[startIndex].filePath,
      'episodes': episodes,
      'episode_index': startIndex,
      'content_type': 'local',
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) _selected.remove(path);
      else _selected.add(path);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _deleteSelected() async {
    final t = RaddTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Delete Files',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Delete ${_selected.length} file${_selected.length == 1 ? '' : 's'}? This cannot be undone.',
            style: TextStyle(color: t.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: t.textMuted))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.error,
                  fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    int deleted = 0;
    for (final path in _selected) {
      try { await File(path).delete(); deleted++; } catch (_) {}
    }
    setState(() {
      _videos.removeWhere((v) => _selected.contains(v.filePath));
      _selected.clear();
      _selecting = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Deleted $deleted file${deleted == 1 ? '' : 's'}'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final sorted = _sorted;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(child: Column(children: [
        _buildTopBar(sorted),
        if (_searching) _buildSearchBar(),
        if (!_selecting) _buildStatsBar(sorted),
        Expanded(child: _buildBody(sorted)),
      ])),
    );
  }

  Widget _buildTopBar(List<LocalVideo> sorted) {
    final t = RaddTheme.of(context);
    if (_selecting) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: t.surface,
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: t.textPrimary),
            onPressed: () => setState(() { _selected.clear(); _selecting = false; }),
          ),
          Expanded(child: Text('${_selected.length} selected',
              style: TextStyle(color: t.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700))),
          if (_selected.isNotEmpty) ...[
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.error),
              onPressed: _deleteSelected,
            ),
            IconButton(
              icon: Icon(Icons.share_rounded, color: t.textSecondary),
              onPressed: () {},
            ),
          ],
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == sorted.length) _selected.clear();
              else _selected.addAll(sorted.map((v) => v.filePath));
            }),
            child: Text(_selected.length == sorted.length ? 'Deselect All' : 'Select All',
                style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ]),
      );
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: t.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(child: Text(widget.folder.name, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
        // Search
        IconButton(
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded,
              color: t.textSecondary, size: 22),
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) { _searchQuery = ''; _searchCtrl.clear(); }
              else _searchFocus.requestFocus();
            });
          },
          constraints: const BoxConstraints(), padding: const EdgeInsets.all(8),
        ),
        // Layout toggle
        IconButton(
          icon: Icon(_layout == _LayoutMode.list
              ? Icons.grid_view_rounded : Icons.view_list_rounded,
              color: t.textSecondary, size: 22),
          onPressed: () => setState(() => _layout = _layout == _LayoutMode.list
              ? _LayoutMode.grid : _LayoutMode.list),
          constraints: const BoxConstraints(), padding: const EdgeInsets.all(8),
        ),
        // Sort & filter sheet
        IconButton(
          icon: Icon(Icons.sort_rounded, color: t.textSecondary, size: 22),
          onPressed: _showSortSheet,
          constraints: const BoxConstraints(), padding: const EdgeInsets.all(8),
        ),
        // More
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: t.textSecondary, size: 22),
          color: t.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          onSelected: (v) {
            if (v == 'select') setState(() => _selecting = true);
            else if (v == 'group') setState(() => _groupingEnabled = !_groupingEnabled);
            else if (v == 'play_all') _playAll();
          },
          itemBuilder: (_) => [
            _menuItem('play_all', Icons.play_circle_rounded,           'Play All',        false),
            _menuItem('group',   Icons.collections_bookmark_rounded,
                _groupingEnabled ? 'Ungroup Series' : 'Group by Series', _groupingEnabled),
            _menuItem('select',  Icons.check_box_outlined,             'Select Files',    false),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label, bool active) {
    final t = RaddTheme.of(context);
    return PopupMenuItem(
      value: val,
      child: Row(children: [
        Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
            color: active ? AppColors.primary : t.textPrimary, fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        if (active) ...[const Spacer(), Icon(Icons.check_rounded, color: AppColors.primary, size: 16)],
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
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: t.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search in ${widget.folder.name}…',
          hintStyle: TextStyle(color: t.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: t.textMuted, size: 20),
          filled: true, fillColor: t.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildStatsBar(List<LocalVideo> sorted) {
    final t = RaddTheme.of(context);
    final totalSize = sorted.fold(0, (s, v) => s + v.sizeBytes);
    final sizeStr = totalSize > 1024 * 1024 * 1024
        ? '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
        : '${(totalSize / (1024 * 1024)).toStringAsFixed(0)} MB';
    final audioCount = sorted.where((v) => v.isAudio).length;
    final videoCount = sorted.where((v) => v.isVideo).length;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        // Stats
        if (audioCount > 0 && videoCount > 0) ...[
          Icon(Icons.videocam_rounded, size: 13, color: t.textMuted),
          const SizedBox(width: 3),
          Text('$videoCount', style: TextStyle(color: t.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
          Icon(Icons.music_note_rounded, size: 13, color: AppColors.primary),
          const SizedBox(width: 3),
          Text('$audioCount', style: TextStyle(color: AppColors.primary, fontSize: 12)),
        ] else
          Text('${sorted.length} ${audioCount == sorted.length ? 'tracks' : 'files'}  •  $sizeStr',
              style: TextStyle(color: t.textMuted, fontSize: 12)),
        const Spacer(),
        // Type filter pills
        if (widget.folder.isMixedFolder) ...[
          _typePill(_TypeFilter.all,   'All'),
          const SizedBox(width: 4),
          _typePill(_TypeFilter.video, '🎬'),
          const SizedBox(width: 4),
          _typePill(_TypeFilter.audio, '🎵'),
        ],
        const SizedBox(width: 8),
        if (_loadingThumbs)
          SizedBox(width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(t.textMuted))),
      ]),
    );
  }

  Widget _typePill(_TypeFilter filter, String label) {
    final t = RaddTheme.of(context);
    final active = _typeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.round),
          border: Border.all(color: active ? AppColors.primary : t.border),
        ),
        child: Text(label, style: TextStyle(
          color: active ? Colors.white : t.textMuted,
          fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }

  Widget _buildBody(List<LocalVideo> sorted) {
    final t = RaddTheme.of(context);
    if (sorted.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam_off_rounded, color: t.textMuted, size: 48),
        const SizedBox(height: 12),
        Text(_searchQuery.isNotEmpty ? 'No results for "$_searchQuery"' : 'No files',
            style: TextStyle(color: t.textMuted)),
      ]));
    }

    // Grid view — no series grouping
    if (_layout == _LayoutMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 1.6,
            crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _VideoGridCard(
          video: sorted[i],
          thumb: _thumbCache[sorted[i].filePath],
          selected: _selected.contains(sorted[i].filePath),
          selecting: _selecting,
          onTap: () => _selecting
              ? _toggleSelect(sorted[i].filePath)
              : _playVideo(sorted[i]),
          onLongPress: () {
            setState(() { _selecting = true; _selected.add(sorted[i].filePath); });
          },
        ).animate(delay: (i * 20).ms).fadeIn(duration: 200.ms),
      );
    }

    // Plain list (grouping disabled)
    if (!_groupingEnabled) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _VideoListTile(
          video: sorted[i],
          thumb: _thumbCache[sorted[i].filePath],
          selected: _selected.contains(sorted[i].filePath),
          selecting: _selecting,
          onTap: () => _selecting
              ? _toggleSelect(sorted[i].filePath)
              : _playVideo(sorted[i]),
          onLongPress: () {
            setState(() { _selecting = true; _selected.add(sorted[i].filePath); });
          },
        ).animate(delay: (i * 15).ms).fadeIn(duration: 200.ms),
      );
    }

    // Grouped list — series auto-detected
    final groups = _groupVideosBySeries(sorted);
    final List<Widget> items = [];
    int animIdx = 0;

    for (final group in groups) {
      final isSeries = group.episodes.length > 1;
      final gKey     = group.seriesName;
      final expanded = _groupExpanded[gKey] ?? true;

      if (isSeries) {
        final epCount = group.episodes.length;
        items.add(
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _groupExpanded[gKey] = !expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Row(children: [
                  Icon(Icons.tv_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    group.seriesName.isEmpty ? 'Series' : group.seriesName,
                    style: TextStyle(color: RaddTheme.of(context).textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$epCount eps',
                        style: TextStyle(color: AppColors.primary,
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? 0.25 : 0,
                    child: Icon(Icons.chevron_right_rounded,
                        color: RaddTheme.of(context).textMuted, size: 18),
                  ),
                ]),
              ),
            ),
          ).animate(delay: Duration(milliseconds: animIdx * 15)).fadeIn(duration: const Duration(milliseconds: 200)),
        );
        animIdx++;

        if (expanded) {
          for (final vid in group.episodes) {
            items.add(
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: _VideoListTile(
                  video: vid,
                  thumb: _thumbCache[vid.filePath],
                  selected: _selected.contains(vid.filePath),
                  selecting: _selecting,
                  onTap: () => _selecting ? _toggleSelect(vid.filePath) : _playVideo(vid),
                  onLongPress: () {
                    setState(() { _selecting = true; _selected.add(vid.filePath); });
                  },
                ).animate(delay: Duration(milliseconds: animIdx * 15)).fadeIn(duration: const Duration(milliseconds: 200)),
              ),
            );
            animIdx++;
          }
        }
      } else {
        final vid = group.episodes.first;
        items.add(
          _VideoListTile(
            video: vid,
            thumb: _thumbCache[vid.filePath],
            selected: _selected.contains(vid.filePath),
            selecting: _selecting,
            onTap: () => _selecting ? _toggleSelect(vid.filePath) : _playVideo(vid),
            onLongPress: () {
              setState(() { _selecting = true; _selected.add(vid.filePath); });
            },
          ).animate(delay: Duration(milliseconds: animIdx * 15)).fadeIn(duration: const Duration(milliseconds: 200)),
        );
        animIdx++;
      }
    }

    return ListView(padding: const EdgeInsets.fromLTRB(0, 0, 0, 100), children: items);
  }
}

// ── Series auto-grouping helpers ──────────────────────────────────────────────
class _SeriesGroup {
  final String seriesName;
  final List<LocalVideo> episodes;
  _SeriesGroup({required this.seriesName, required this.episodes});
}

String _seriesNameFrom(String title) {
  return title
      .replaceAll(RegExp(r'S\d+\s*E\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'Episode\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'Ep\.?\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\d+x\d+'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

List<_SeriesGroup> _groupVideosBySeries(List<LocalVideo> videos) {
  final Map<String, List<LocalVideo>> byName = {};
  for (final v in videos) {
    final key = _seriesNameFrom(v.title);
    (byName[key] ??= []).add(v);
  }
  final groups = byName.entries
      .map((e) => _SeriesGroup(seriesName: e.key, episodes: e.value))
      .toList();
  groups.sort((a, b) => b.episodes.length.compareTo(a.episodes.length));
  return groups;
}

// ── Folder sort + filter bottom sheet ────────────────────────────────────────
class _FolderSortSheet extends StatefulWidget {
  final _SortBy sortBy;
  final bool ascending;
  final _TypeFilter typeFilter;
  final _LayoutMode layout;
  final void Function(_SortBy, bool, _TypeFilter, _LayoutMode) onChanged;

  const _FolderSortSheet({
    required this.sortBy,
    required this.ascending,
    required this.typeFilter,
    required this.layout,
    required this.onChanged,
  });

  @override
  State<_FolderSortSheet> createState() => _FolderSortSheetState();
}

class _FolderSortSheetState extends State<_FolderSortSheet> {
  late _SortBy      _sortBy;
  late bool         _ascending;
  late _TypeFilter  _typeFilter;
  late _LayoutMode  _layout;

  @override
  void initState() {
    super.initState();
    _sortBy     = widget.sortBy;
    _ascending  = widget.ascending;
    _typeFilter = widget.typeFilter;
    _layout     = widget.layout;
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
                    widget.onChanged(_sortBy, _ascending, _typeFilter, _layout);
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
                _layoutBtn(t, _LayoutMode.list, Icons.view_list_rounded, 'List'),
                const SizedBox(width: 10),
                _layoutBtn(t, _LayoutMode.grid, Icons.grid_view_rounded, 'Grid'),
              ]),
              const SizedBox(height: 18),

              // ── Sort by ──
              Text('Sort By', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _sortChip(t, _SortBy.date,       Icons.access_time_rounded,     'Date'),
                _sortChip(t, _SortBy.name,       Icons.sort_by_alpha_rounded,   'Name'),
                _sortChip(t, _SortBy.size,       Icons.storage_rounded,         'Size'),
                _sortChip(t, _SortBy.duration,   Icons.timer_outlined,          'Duration'),
                _sortChip(t, _SortBy.resolution, Icons.hd_rounded,              'Resolution'),
                _sortChip(t, _SortBy.type,       Icons.perm_media_rounded,      'Type'),
              ]),
              const SizedBox(height: 18),

              // ── Type filter ──
              Text('Show', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                _filterBtn(t, _TypeFilter.all,   Icons.apps_rounded,            'All Files'),
                const SizedBox(width: 8),
                _filterBtn(t, _TypeFilter.video, Icons.videocam_rounded,        'Videos'),
                const SizedBox(width: 8),
                _filterBtn(t, _TypeFilter.audio, Icons.music_note_rounded,      'Audio'),
              ]),
              const SizedBox(height: 18),

              // ── Direction ──
              Text('Order', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dirBtn(t, true,  Icons.arrow_upward_rounded,   'A → Z')),
                const SizedBox(width: 10),
                Expanded(child: _dirBtn(t, false, Icons.arrow_downward_rounded, 'Z → A')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutBtn(dynamic t, _LayoutMode mode, IconData icon, String label) {
    final active = _layout == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _layout = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : t.card,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: active ? AppColors.primary : t.textMuted,
                fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _sortChip(dynamic t, _SortBy mode, IconData icon, String label) {
    final active = _sortBy == mode;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 15),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: active ? AppColors.primary : t.textSecondary,
              fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _filterBtn(dynamic t, _TypeFilter filter, IconData icon, String label) {
    final active = _typeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : t.card,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 18),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: active ? AppColors.primary : t.textMuted,
                fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _dirBtn(dynamic t, bool asc, IconData icon, String label) {
    final active = _ascending == asc;
    return GestureDetector(
      onTap: () => setState(() => _ascending = asc),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : t.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: active ? AppColors.primary : t.border, width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: active ? AppColors.primary : t.textMuted, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: active ? AppColors.primary : t.textSecondary,
              fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

// ── Video list tile ───────────────────────────────────────────────────────────
class _VideoListTile extends StatelessWidget {
  final LocalVideo video;
  final Uint8List? thumb;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _VideoListTile({required this.video, required this.thumb,
      required this.selected, required this.selecting,
      required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                      color: selected ? AppColors.primary : t.textMuted, width: 2),
                ),
                child: selected ? Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
              ),
            ),
          // Thumbnail / audio icon
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 116, height: 68,
                child: video.isAudio
                    ? Container(
                        color: AppColors.primary.withOpacity(0.08),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.music_note_rounded, color: AppColors.primary, size: 28),
                          if (video.durationMs > 0)
                            Text(video.formattedDuration,
                                style: TextStyle(color: AppColors.primary,
                                    fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      )
                    : thumb != null
                        ? Image.memory(thumb!, fit: BoxFit.cover)
                        : Container(color: t.surface,
                            child: Icon(Icons.play_circle_outline_rounded,
                                color: t.textMuted, size: 32)),
              ),
            ),
            // Duration badge (video only)
            if (video.isVideo && video.durationMs > 0)
              Positioned(bottom: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(video.formattedDuration,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 10, fontWeight: FontWeight.w600)))),
            // Audio badge
            if (video.isAudio)
              Positioned(top: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AUDIO', style: TextStyle(color: Colors.white,
                      fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.4)))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.primary : t.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
              const SizedBox(height: 5),
              Row(children: [
                if (video.hasSrt) ...[
                  _badge('SRT', AppColors.info),
                  const SizedBox(width: 5),
                ],
                if (video.isVideo && video.resolution.isNotEmpty) ...[
                  _badge(video.resolution,
                      video.isHighRes ? AppColors.primary : t.textMuted),
                  const SizedBox(width: 5),
                ],
                Text(video.formattedSize,
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
              ]),
            ],
          )),
          if (!selecting)
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: t.textMuted, size: 20),
              onPressed: () => _showVideoMenu(context),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color,
        fontSize: 9, fontWeight: FontWeight.w700)),
  );

  void _showVideoMenu(BuildContext context) {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(color: t.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 72, height: 44,
                child: thumb != null
                    ? Image.memory(thumb!, fit: BoxFit.cover)
                    : Container(color: t.card,
                        child: Icon(video.isAudio
                            ? Icons.music_note_rounded
                            : Icons.videocam_rounded,
                            color: video.isAudio ? AppColors.primary : t.textMuted)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${video.formattedDuration}  •  ${video.formattedSize}',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
            ])),
          ]),
        ),
        _menuTile(context, Icons.play_arrow_rounded, 'Play', () {
          Navigator.pop(context);
          onTap();
        }),
        _menuTile(context, Icons.info_outline_rounded, 'File Info', () {
          Navigator.pop(context);
          _showFileInfo(context);
        }),
        _menuTile(context, Icons.share_rounded, 'Share', () { Navigator.pop(context); }),
        _menuTile(context, Icons.delete_outline_rounded, 'Delete',
            () { Navigator.pop(context); }, isDestructive: true),
        const SizedBox(height: 8),
      ])),
    );
  }

  ListTile _menuTile(BuildContext ctx, IconData icon, String label,
      VoidCallback onPressed, {bool isDestructive = false}) {
    final t = RaddTheme.of(ctx);
    return ListTile(
      leading: Icon(icon, color: isDestructive ? AppColors.error : t.textSecondary, size: 22),
      title: Text(label, style: TextStyle(
          color: isDestructive ? AppColors.error : t.textPrimary, fontSize: 15)),
      onTap: onPressed,
      dense: true,
    );
  }

  void _showFileInfo(BuildContext context) {
    final t = RaddTheme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('File Info', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(ctx, 'Name',     video.displayName),
            _infoRow(ctx, 'Type',     video.isAudio ? 'Audio' : 'Video'),
            _infoRow(ctx, 'Duration', video.durationMs > 0 ? video.formattedDuration : 'Unknown'),
            _infoRow(ctx, 'Size',     video.formattedSize),
            if (video.isVideo) _infoRow(ctx, 'Resolution',
                video.resolution.isNotEmpty ? '${video.width}x${video.height} (${video.resolution})' : 'Unknown'),
            _infoRow(ctx, 'Subtitle', video.hasSrt ? 'SRT found' : 'None'),
            _infoRow(ctx, 'Path',     video.filePath),
          ]),
        actions: [TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: AppColors.primary)),
        )],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$label: ',
            style: TextStyle(color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        TextSpan(text: value, style: TextStyle(color: t.textSecondary, fontSize: 12)),
      ])),
    );
  }
}

// ── Video grid card ───────────────────────────────────────────────────────────
class _VideoGridCard extends StatelessWidget {
  final LocalVideo video;
  final Uint8List? thumb;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _VideoGridCard({required this.video, required this.thumb,
      required this.selected, required this.selecting,
      required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap, onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Stack(fit: StackFit.expand, children: [
          video.isAudio
              ? Container(
                  color: AppColors.primary.withOpacity(0.08),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.music_note_rounded, color: AppColors.primary, size: 36),
                    const SizedBox(height: 4),
                    Text(video.formattedDuration,
                        style: TextStyle(color: AppColors.primary,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ]))
              : thumb != null
                  ? Image.memory(thumb!, fit: BoxFit.cover)
                  : Container(color: t.surface,
                      child: Icon(Icons.play_circle_outline_rounded,
                          color: t.textMuted, size: 32)),
          // Scrim
          DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.75)]),
          )),
          // Title + meta
          Positioned(bottom: 6, left: 8, right: 8, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                if (video.hasSrt) ...[
                  _smallBadge('SRT', AppColors.info),
                  const SizedBox(width: 4),
                ],
                if (video.isVideo && video.resolution.isNotEmpty) ...[
                  _smallBadge(video.resolution, Colors.white54),
                  const SizedBox(width: 4),
                ],
                if (video.isAudio) ...[
                  _smallBadge('AUDIO', AppColors.primary),
                  const SizedBox(width: 4),
                ],
                Text(video.formattedSize,
                    style: const TextStyle(color: Colors.white54, fontSize: 9)),
              ]),
            ],
          )),
          // Duration (video only)
          if (video.isVideo && video.durationMs > 0)
            Positioned(top: 5, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(video.formattedDuration,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w700)))),
          // Selection overlay
          if (selecting)
            Positioned(top: 6, left: 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.black45,
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 14) : null)),
        ]),
      ),
    );
  }

  Widget _smallBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text, style: TextStyle(color: color,
        fontSize: 8, fontWeight: FontWeight.w700)),
  );
}
