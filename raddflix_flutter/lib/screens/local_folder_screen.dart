import 'dart:io';
import 'dart:typed_data';
  import 'package:flutter/material.dart';
  import 'package:flutter_animate/flutter_animate.dart';
  import 'package:shimmer/shimmer.dart';
  import '../core/constants.dart';
  import '../models/local_video.dart';
  import '../services/local_media_service.dart';
  import 'player_screen.dart';

  class LocalFolderScreen extends StatefulWidget {
    final LocalFolder folder;
    const LocalFolderScreen({super.key, required this.folder});
    @override
    State<LocalFolderScreen> createState() => _LocalFolderScreenState();
  }

  enum _VideoSortMode { date, name, size, duration }
  enum _VideoViewMode { list, grid }

  class _LocalFolderScreenState extends State<LocalFolderScreen> {
    late List<LocalVideo> _videos;
    _VideoSortMode _sort = _VideoSortMode.date;
    _VideoViewMode _view = _VideoViewMode.list;
    String _searchQuery = '';
    bool _searching = false;
    bool _selecting = false;
    final Set<String> _selected = {};
    final TextEditingController _searchCtrl = TextEditingController();
    final FocusNode _searchFocus = FocusNode();
    final Map<String, Uint8List?> _thumbCache = {};
    bool _loadingThumbs = true;

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

    // Loads video thumbnails in parallel batches of 4.
    // Prefers fast native MediaStore cache (API 29+); falls back to file decode.
    Future<void> _loadThumbnails() async {
      const batchSize = 4;
      for (int i = 0; i < _videos.length; i += batchSize) {
        if (!mounted) return;
        final batch = _videos.skip(i).take(batchSize).toList();
        await Future.wait(batch.map((v) async {
          if (_thumbCache.containsKey(v.filePath)) return;
          Uint8List? thumb;
          if (v.id > 0) {
            thumb = await LocalMediaService.getThumbnailById(v.id, size: 220);
          }
          thumb ??= await LocalMediaService.getThumbnail(
              v.filePath, quality: 55, maxDimension: 220);
          if (mounted) setState(() => _thumbCache[v.filePath] = thumb);
        }));
      }
      if (mounted) setState(() => _loadingThumbs = false);
    }

    List<LocalVideo> get _sorted {
      final list = _searchQuery.isEmpty
          ? List<LocalVideo>.from(_videos)
          : _videos.where((v) =>
              v.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              v.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      switch (_sort) {
        case _VideoSortMode.name:     list.sort((a, b) => a.title.compareTo(b.title));
        case _VideoSortMode.size:     list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        case _VideoSortMode.duration: list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        case _VideoSortMode.date:     list.sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));
      }
      return list;
    }

    void _playVideo(LocalVideo video) {
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
        'file_id': '',
        'title': video.title,
        'local_path': video.filePath,
        'subtitle_path': video.subtitlePath,
        'content_type': 'local',
      });
    }

    void _playAll() {
      if (_videos.isEmpty) return;
      final sorted = _sorted;
      // Build episodes list for sequential playback.
      // Explicit <String, dynamic> type required: the int value 'episode'
      // would otherwise make Dart infer Map<String, Object>, which cannot
      // be cast to List<Map<String, dynamic>> in app.dart's onGenerateRoute.
      final episodes = sorted.map((v) => <String, dynamic>{
        'file_id': '',
        'title': v.title,
        'local_path': v.filePath,
        'episode': sorted.indexOf(v) + 1,
      }).toList();
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
        'file_id': '',
        'title': sorted.first.title,
        'local_path': sorted.first.filePath,
        'episodes': episodes,
        'episode_index': 0,
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('Delete Files',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: Text('Delete ${_selected.length} file${_selected.length == 1 ? '' : 's'}? This cannot be undone.',
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete', style: TextStyle(color: AppColors.error,
                    fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (confirmed != true) return;

      int deleted = 0;
      for (final path in _selected) {
        try {
          await (await _fileFromPath(path)).delete();
          deleted++;
        } catch (_) {}
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

    Future<File> _fileFromPath(String path) async {
      return File(path);
    }

    @override
    Widget build(BuildContext context) {
      final sorted = _sorted;
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: Column(children: [
          _buildTopBar(sorted),
          if (_searching) _buildSearchBar(),
          if (!_selecting) _buildStatsBar(sorted),
          Expanded(child: _buildBody(sorted)),
        ])),
        // Floating play all button (MX Player style)
        floatingActionButton: (!_selecting && _videos.isNotEmpty)
            ? FloatingActionButton(
                backgroundColor: AppColors.primary,
                onPressed: _playAll,
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
              )
            : null,
      );
    }

    Widget _buildTopBar(List<LocalVideo> sorted) {
      if (_selecting) {
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: AppColors.surface,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
              onPressed: () => setState(() { _selected.clear(); _selecting = false; }),
            ),
            Expanded(child: Text('${_selected.length} selected',
                style: const TextStyle(color: AppColors.textPrimary,
                    fontSize: 16, fontWeight: FontWeight.w700))),
            if (_selected.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                onPressed: _deleteSelected,
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, color: AppColors.textSecondary),
                onPressed: () {/* share */},
              ),
            ],
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == sorted.length) _selected.clear();
                else _selected.addAll(sorted.map((v) => v.filePath));
              }),
              child: Text(_selected.length == sorted.length ? 'Deselect All' : 'Select All',
                  style: const TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ]),
        );
      }

      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(child: Text(widget.folder.name, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w700))),
          // Search
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded,
                color: AppColors.textSecondary, size: 22),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) { _searchQuery = ''; _searchCtrl.clear(); }
                else _searchFocus.requestFocus();
              });
            },
            constraints: const BoxConstraints(), padding: const EdgeInsets.all(8),
          ),
          // View toggle
          IconButton(
            icon: Icon(_view == _VideoViewMode.list
                ? Icons.grid_view_rounded : Icons.view_list_rounded,
                color: AppColors.textSecondary, size: 22),
            onPressed: () => setState(() =>
                _view = _view == _VideoViewMode.list
                    ? _VideoViewMode.grid : _VideoViewMode.list),
            constraints: const BoxConstraints(), padding: const EdgeInsets.all(8),
          ),
          // Sort + more menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 22),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            onSelected: (v) {
              if (v == 'select') setState(() => _selecting = true);
              else setState(() => _sort = _VideoSortMode.values
                  .firstWhere((m) => m.name == v, orElse: () => _sort));
            },
            itemBuilder: (_) => [
              _menuDivider('Sort by'),
              _menuItem('date',     Icons.access_time_rounded,   'Most Recent',   _sort.name == 'date'),
              _menuItem('name',     Icons.sort_by_alpha_rounded, 'Name',          _sort.name == 'name'),
              _menuItem('size',     Icons.storage_rounded,       'Largest First', _sort.name == 'size'),
              _menuItem('duration', Icons.timer_outlined,        'Longest First', _sort.name == 'duration'),
              _menuDivider('Actions'),
              _menuItem('select', Icons.check_box_outlined,      'Select Files',  false),
            ],
          ),
        ]),
      );
    }

    PopupMenuEntry<String> _menuDivider(String label) => PopupMenuItem<String>(
      enabled: false, height: 28,
      child: Text(label.toUpperCase(),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );

    PopupMenuItem<String> _menuItem(String val, IconData icon, String label, bool active) =>
      PopupMenuItem(
        value: val,
        child: Row(children: [
          Icon(icon, color: active ? AppColors.primary : AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
              color: active ? AppColors.primary : AppColors.textPrimary,
              fontSize: 14, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          if (active) ...[const Spacer(),
            const Icon(Icons.check_rounded, color: AppColors.primary, size: 16)],
        ]),
      );

    Widget _buildSearchBar() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search in ${widget.folder.name}…',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
            filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
    }

    Widget _buildStatsBar(List<LocalVideo> sorted) {
      final totalSize = sorted.fold(0, (s, v) => s + v.sizeBytes);
      final sizeStr = totalSize > 1024 * 1024 * 1024
          ? '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
          : '${(totalSize / (1024 * 1024)).toStringAsFixed(0)} MB';
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('${sorted.length} videos  •  $sizeStr',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          if (_loadingThumbs)
            const SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.textMuted))),
        ]),
      );
    }

    Widget _buildBody(List<LocalVideo> sorted) {
      if (sorted.isEmpty) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(_searchQuery.isNotEmpty ? 'No results for "$_searchQuery"' : 'No videos',
              style: const TextStyle(color: AppColors.textMuted)),
        ]));
      }

      if (_view == _VideoViewMode.grid) {
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
  }

  // ── Video list tile (MX Player style) ─────────────────────────────────────────
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
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          color: selected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(children: [
            // Selection checkbox
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
                      color: selected ? AppColors.primary : AppColors.textMuted, width: 2),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                      : null,
                ),
              ),
            // Thumbnail with duration overlay
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 116, height: 68,
                  child: thumb != null
                      ? Image.memory(thumb!, fit: BoxFit.cover)
                      : Container(color: AppColors.surface,
                          child: const Icon(Icons.play_circle_outline_rounded,
                              color: AppColors.textMuted, size: 32)),
                ),
              ),
              // Duration badge
              if (video.durationMs > 0)
                Positioned(bottom: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(video.formattedDuration,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 10, fontWeight: FontWeight.w600)),
                  )),
            ]),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.primary : AppColors.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 5),
                Row(children: [
                  // SRT badge
                  if (video.hasSrt)
                    _badge('SRT', AppColors.info),
                  if (video.hasSrt) const SizedBox(width: 5),
                  // Resolution badge
                  if (video.resolution.isNotEmpty)
                    _badge(video.resolution,
                        video.isHighRes ? AppColors.primary : AppColors.textMuted),
                  if (video.resolution.isNotEmpty) const SizedBox(width: 5),
                  // Size
                  Text(video.formattedSize,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
              ],
            )),
            // More button
            if (!selecting)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 20),
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
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    );

    void _showVideoMenu(BuildContext context) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 16),
              decoration: BoxDecoration(color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
          // Thumbnail header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 72, height: 44,
                  child: thumb != null
                      ? Image.memory(thumb!, fit: BoxFit.cover)
                      : Container(color: AppColors.card))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${video.formattedDuration}  •  ${video.formattedSize}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
        VoidCallback onPressed, {bool isDestructive = false}) =>
      ListTile(
        leading: Icon(icon,
            color: isDestructive ? AppColors.error : AppColors.textSecondary, size: 22),
        title: Text(label,
            style: TextStyle(
                color: isDestructive ? AppColors.error : AppColors.textPrimary,
                fontSize: 15)),
        onTap: onPressed,
        dense: true,
      );

    void _showFileInfo(BuildContext context) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('File Info', style: TextStyle(color: AppColors.textPrimary,
              fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Name',       video.displayName),
              _infoRow('Duration',   video.durationMs > 0 ? video.formattedDuration : 'Unknown'),
              _infoRow('Size',       video.formattedSize),
              _infoRow('Resolution', video.resolution.isNotEmpty ? '${video.width}×${video.height} (${video.resolution})' : 'Unknown'),
              _infoRow('Subtitle',   video.hasSrt ? 'SRT found' : 'None'),
              _infoRow('Path',       video.filePath),
            ]),
          actions: [TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.primary)),
          )],
        ),
      );
    }

    Widget _infoRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$label: ',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        TextSpan(text: value,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ])),
    );
  }

  // ── Video grid card ────────────────────────────────────────────────────────────
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
      return GestureDetector(
        onTap: onTap, onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Stack(fit: StackFit.expand, children: [
            thumb != null
                ? Image.memory(thumb!, fit: BoxFit.cover)
                : Container(color: AppColors.surface,
                    child: const Icon(Icons.play_circle_outline_rounded,
                        color: AppColors.textMuted, size: 32)),
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
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  if (video.hasSrt) ...[
                    _smallBadge('SRT', AppColors.info),
                    const SizedBox(width: 4),
                  ],
                  if (video.resolution.isNotEmpty) ...[
                    _smallBadge(video.resolution, Colors.white54),
                    const SizedBox(width: 4),
                  ],
                  Text(video.formattedSize,
                      style: const TextStyle(color: Colors.white54, fontSize: 9)),
                ]),
              ],
            )),
            // Duration
            if (video.durationMs > 0)
              Positioned(top: 5, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(video.formattedDuration,
                      style: const TextStyle(color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.w700)),
                )),
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
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                )),
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
      child: Text(text, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700)),
    );
  }
  