import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/local_video.dart';
import '../services/local_media_service.dart';
import 'local_folder_screen.dart';
import '../widgets/bottom_nav.dart';
import '../core/theme/radd_theme.dart';

class LocalMediaScreen extends StatefulWidget {
  const LocalMediaScreen({super.key});
  @override
  State<LocalMediaScreen> createState() => _LocalMediaScreenState();
}

enum _SortBy { name, date, size, count, duration }
enum _LayoutMode { list, grid }

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

  // Resume last local video
  String? _resumePath;
  String? _resumeTitle;

  @override
  void initState() {
    super.initState();
    _load();
    _loadResume();
  }

  @override
  void dispose() {
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

  Future<void> _loadThumbnails(List<LocalFolder> folders) async {
    const batchSize = 4;
    for (int i = 0; i < folders.length; i += batchSize) {
      if (!mounted) return;
      final batch = folders.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((folder) async {
        if (_thumbCache.containsKey(folder.path)) return;
        // For audio folders, skip video thumbnail — will show music icon
        if (folder.folderType == 'audio') {
          if (mounted) setState(() => _thumbCache[folder.path] = null);
          return;
        }
        for (final video in folder.videos.where((v) => v.isVideo).take(3)) {
          Uint8List? thumb;
          if (video.id > 0) {
            thumb = await LocalMediaService.getThumbnailById(video.id, size: 160);
          }
          thumb ??= await LocalMediaService.getThumbnail(video.filePath, quality: 40, maxDimension: 160);
          if (thumb != null) {
            if (mounted) setState(() => _thumbCache[folder.path] = thumb);
            return;
          }
        }
        if (mounted) setState(() => _thumbCache[folder.path] = null);
      }));
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
              icon: const Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 22),
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
              Icon(Icons.video_library_rounded, size: 11, color: AppColors.primary),
              const SizedBox(width: 4),
              Text('$_totalFiles',
                  style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(width: 6),
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
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Layout toggle (list/grid)
        IconButton(
          icon: Icon(
            _layout == _LayoutMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded,
            color: t.textSecondary, size: 22),
          onPressed: () => setState(() =>
              _layout = _layout == _LayoutMode.list ? _LayoutMode.grid : _LayoutMode.list),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        // Sort & filter sheet
        IconButton(
          icon: Icon(Icons.sort_rounded, color: t.textSecondary, size: 22),
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
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: t.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search folders…',
          hintStyle: TextStyle(color: t.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: t.textMuted, size: 20),
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
    final sorted = _sorted;
    if (sorted.isEmpty) return _buildEmpty();

    if (_layout == _LayoutMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 1.4,
            crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _FolderGridCard(
          folder: sorted[i],
          thumb: _thumbCache[sorted[i].path],
          onTap: () => _openFolder(sorted[i]),
        ).animate(delay: (i * 25).ms).fadeIn(duration: 200.ms),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: t.surface,
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _FolderListTile(
          folder: sorted[i],
          thumb: _thumbCache[sorted[i].path],
          onTap: () => _openFolder(sorted[i]),
        ).animate(delay: (i * 20).ms).fadeIn(duration: 200.ms),
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
          child: Icon(Icons.folder_off_rounded, color: AppColors.error, size: 40)),
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
              const Icon(Icons.settings_rounded, size: 18, color: Colors.white),
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
        child: Icon(Icons.video_library_outlined, color: t.textMuted, size: 40)),
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
                _layoutBtn(context, t, _LayoutMode.list, Icons.view_list_rounded, 'List'),
                const SizedBox(width: 10),
                _layoutBtn(context, t, _LayoutMode.grid, Icons.grid_view_rounded, 'Grid'),
              ]),
              const SizedBox(height: 20),

              // ── Sort by ──
              Text('Sort By', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _sortChip(context, t, _SortBy.date,     Icons.access_time_rounded,       'Date'),
                _sortChip(context, t, _SortBy.name,     Icons.sort_by_alpha_rounded,     'Name'),
                _sortChip(context, t, _SortBy.size,     Icons.storage_rounded,           'Size'),
                _sortChip(context, t, _SortBy.count,    Icons.video_library_rounded,     'Count'),
                _sortChip(context, t, _SortBy.duration, Icons.timer_outlined,            'Duration'),
              ]),
              const SizedBox(height: 20),

              // ── Direction ──
              Text('Order', style: TextStyle(color: t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dirBtn(context, t, true,  Icons.arrow_upward_rounded,   'A → Z  (Ascending)')),
                const SizedBox(width: 10),
                Expanded(child: _dirBtn(context, t, false, Icons.arrow_downward_rounded, 'Z → A  (Descending)')),
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
  const _FolderListTile({required this.folder, required this.thumb, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t    = RaddTheme.of(context);
    final type = folder.folderType;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm - 0.5),
                child: thumb != null
                    ? Image.memory(thumb!, fit: BoxFit.cover)
                    : Center(child: Icon(
                        type == 'audio' ? Icons.music_note_rounded
                            : type == 'mixed' ? Icons.perm_media_rounded
                            : Icons.folder_rounded,
                        color: type == 'audio' ? AppColors.primary : t.textMuted,
                        size: 28)),
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
            Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20),
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
  const _FolderGridCard({required this.folder, required this.thumb, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t    = RaddTheme.of(context);
    final type = folder.folderType;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(fit: StackFit.expand, children: [
          thumb != null
              ? Image.memory(thumb!, fit: BoxFit.cover)
              : Container(
                  color: type == 'audio' ? AppColors.primary.withOpacity(0.1) : t.surface,
                  child: Icon(
                    type == 'audio' ? Icons.music_note_rounded
                        : type == 'mixed' ? Icons.perm_media_rounded
                        : Icons.folder_rounded,
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
        ]),
      ),
    );
  }
}
