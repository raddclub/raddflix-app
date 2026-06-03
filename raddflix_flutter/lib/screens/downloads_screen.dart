import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../providers/downloads_provider.dart';
import '../services/thumb_service.dart';

enum _SortMode { name, size, date }
enum _FilterMode { all, completed, downloading, failed }
enum _ViewMode { grid, list }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _SortMode   _sort   = _SortMode.date;
  _FilterMode _filter = _FilterMode.all;
  _ViewMode   _view   = _ViewMode.grid;
  bool _selecting     = false;
  final Set<String> _selected = {};
  String? _activeFolder;

  static const _folders = ['Movies', 'TV Shows', 'Dramas', 'Other'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        ref.read(downloadsProvider.notifier).loadDownloads());
  }

  // ── Helpers on raw Map ────────────────────────────────────────────────────
  String _id(Map m)       => m['file_id']    as String? ?? '';
  String _title(Map m)    => m['title_text'] as String? ?? 'Unknown';
  String _path(Map m)     => m['local_path'] as String? ?? '';
  String _status(Map m)   => m['status']     as String? ?? 'pending';
  double _progress(Map m) => (m['progress']  as num?)?.toDouble() ?? 0.0;
  int    _size(Map m)     => m['file_size']  as int? ?? 0;
  int    _date(Map m)     => m['downloaded_at'] as int? ?? 0;

  bool _isComplete(Map m)    => _status(m) == 'complete';
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
    return Scaffold(
      backgroundColor: null,
      appBar: _buildAppBar(state),
      body: Column(children: [
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
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: _selected.isEmpty ? null : () => _bulkDelete(),
          ),
        ] else ...[
          IconButton(
            icon: Icon(_view == _ViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _view = _view == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid),
            tooltip: 'Toggle view',
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            onSelected: (s) => setState(() => _sort = s),
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

  Widget _buildStorageBar(DownloadsState state) {
    final totalBytes = state.downloads.fold<int>(0, (sum, d) => sum + _size(d));
    final completed = state.downloads.where((d) => _isComplete(d)).length;
    final active    = state.downloads.where((d) => _isDownloading(d)).length;
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
            Text('$completed complete', style: TextStyle(color: t.textMuted, fontSize: 11)),
            Text(' · ', style: TextStyle(color: t.textMuted)),
            Text('${state.downloads.length} total', style: TextStyle(color: t.textMuted, fontSize: 11)),
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
            onTap: () => setState(() => _filter = f),
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
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: t.surface, highlightColor: t.surfaceHigh,
        child: Container(decoration: BoxDecoration(color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm)))),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.surface,
            border: Border.all(color: t.border, width: 1.5),
          ),
          child: Icon(Icons.download_for_offline_outlined,
              color: t.textMuted, size: 48),
        ),
        SizedBox(height: 24),
        Text('No Downloads Yet', style: TextStyle(
            color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w800,
            letterSpacing: -0.3)),
        SizedBox(height: 8),
        Text('Download videos to watch offline.',
            style: TextStyle(color: t.textMuted, fontSize: 14)),
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
            child: const Text('Browse Content', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildFolderView(DownloadsState state) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _folders.length,
      itemBuilder: (_, i) {
        final folder = _folders[i];
        final count = state.downloads.where((d) => _folderFor(d) == folder).length;
        final folderColor = _folderColor(folder);
        return GestureDetector(
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
              ]),
            ),
          ),
        ).animate(delay: (i * 60).ms).fadeIn(duration: 300.ms)
            .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1),
                duration: 350.ms, curve: AppCurves.enter);
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

    return _view == _ViewMode.grid ? _gridView(items, state) : _listView(items, state);
  }

  Widget _gridView(List<Map<String, dynamic>> items, DownloadsState state) {
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
              Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                'file_id': id, 'title': _title(d), 'local_path': _path(d)});
            }
          },
          onLongPress: () => setState(() { _selecting = true; _selected.add(id); }),
          onDelete: () => _deleteOne(id, _title(d)),
          localPath: _path(d),
        ).animate(delay: (i * 30).ms).fadeIn(duration: 250.ms);
      },
    );
  }

  Widget _listView(List<Map<String, dynamic>> items, DownloadsState state) {
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
              Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                'file_id': id, 'title': _title(d), 'local_path': _path(d)});
            }
          },
          onLongPress: () => setState(() { _selecting = true; _selected.add(id); }),
          onDelete: () => _deleteOne(id, _title(d)),
          localPath: _path(d),
        ).animate(delay: (i * 30).ms).fadeIn(duration: 250.ms)
            .slideX(begin: 0.1, end: 0, duration: 250.ms, curve: AppCurves.standard);
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

  Color _folderColor(String name) {
    switch (name) {
      case 'Movies':   return const Color(0xFFE8002D);
      case 'TV Shows': return const Color(0xFF3B82F6);
      case 'Dramas':   return const Color(0xFF8B5CF6);
      default:         return AppColors.textMuted;
    }
  }
}

// ── Download Card (Grid) ────────────────────────���─────────────────────────────
class _DownloadCard extends StatefulWidget {
  final String title, sizeStr, statusStr, localPath;
  final double progress;
  final bool isActive, isComplete, isSelected, isSelecting;
  final VoidCallback onTap, onLongPress, onDelete;
  const _DownloadCard({required this.title, required this.sizeStr,
      required this.statusStr, required this.progress, required this.isActive,
      required this.isComplete, required this.isSelected, required this.isSelecting,
      required this.onTap, required this.onLongPress, required this.onDelete,
      this.localPath = ''});
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
                Text(widget.sizeStr, style: TextStyle(color: t.textMuted, fontSize: 10)),
                const Spacer(),
                if (!widget.isSelecting)
                  GestureDetector(onTap: widget.onDelete,
                      child: Icon(Icons.delete_outline_rounded,
                          size: 16, color: t.textMuted)),
              ]),
              if (widget.isActive) ...[
                const SizedBox(height: 4),
                Text('${(widget.progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.primary,
                        fontSize: 10, fontWeight: FontWeight.w700)),
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
  final double progress;
  final bool isActive, isComplete, isSelected, isSelecting;
  final VoidCallback onTap, onLongPress, onDelete;
  const _DownloadListTile({required this.title, required this.sizeStr,
      required this.statusStr, required this.progress, required this.isActive,
      required this.isComplete, required this.isSelected, required this.isSelecting,
      required this.onTap, required this.onLongPress, required this.onDelete,
      this.localPath = ''});
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
              Text('${(widget.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ])),
          if (!widget.isSelecting)
            IconButton(icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: t.textMuted), onPressed: widget.onDelete),
        ]),
      ),
    );
  }
}
