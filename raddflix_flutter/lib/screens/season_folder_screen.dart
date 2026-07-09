// lib/screens/season_folder_screen.dart
//
// DOWNLOAD-TAB-V2: second level of the TV Shows drill-down.
// Show -> Season folders -> Episodes, matching the MoviBox/Amazon Prime
// offline-content pattern researched for this feature.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../core/utils/episode_title_parser.dart';
import '../providers/downloads_provider.dart';
import '../services/vault_service.dart';

class SeasonFolderScreen extends ConsumerStatefulWidget {
  final String showName;
  const SeasonFolderScreen({super.key, required this.showName});

  @override
  ConsumerState<SeasonFolderScreen> createState() => _SeasonFolderScreenState();
}

class _SeasonFolderScreenState extends ConsumerState<SeasonFolderScreen> {
  int? _activeSeason;
  bool _selecting = false;
  final Set<String> _selected = {};

  String _id(Map m)       => m['file_id']    as String? ?? '';
  String _title(Map m)    => m['title_text'] as String? ?? 'Unknown';
  String _path(Map m)     => m['local_path'] as String? ?? '';
  String _status(Map m)   => m['status']     as String? ?? 'pending';
  int    _size(Map m)     => m['file_size']  as int? ?? 0;
  bool _isComplete(Map m)    => _status(m) == 'completed';
  bool _isDownloading(Map m) => _status(m) == 'downloading' || _status(m) == 'pending';

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final state = ref.watch(downloadsProvider);
    final episodes = state.downloads.where((d) =>
        parseEpisodeTitle(_title(d)).showTitle == widget.showName).toList();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(
          _selecting ? '${_selected.length} selected'
              : (_activeSeason == null ? widget.showName : 'Season $_activeSeason'),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: Icon(AppIcons.back, size: 20),
          onPressed: () {
            if (_selecting) {
              setState(() { _selecting = false; _selected.clear(); });
            } else if (_activeSeason != null) {
              setState(() => _activeSeason = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: _selecting ? [
          IconButton(
            icon: Icon(AppIcons.trash, color: AppColors.error),
            onPressed: _selected.isEmpty ? null : () => _bulkDelete(episodes),
          ),
        ] : null,
      ),
      body: episodes.isEmpty
          ? Center(child: Text('No downloads for this show',
              style: TextStyle(color: t.textMuted)))
          : _activeSeason == null
              ? _buildSeasonGrid(episodes, state)
              : _buildEpisodeList(episodes, state),
    );
  }

  Widget _buildSeasonGrid(List<Map<String, dynamic>> episodes, DownloadsState state) {
    final t = RaddTheme.of(context);
    final bySeason = <int, List<Map<String, dynamic>>>{};
    for (final d in episodes) {
      bySeason.putIfAbsent(parseEpisodeTitle(_title(d)).seasonOrDefault, () => []).add(d);
    }
    final seasons = bySeason.keys.toList()..sort();

    return GridView.builder(
      padding: EdgeInsets.all(RaddSpace.md),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: seasons.length,
      itemBuilder: (_, i) {
        final season = seasons[i];
        final eps = bySeason[season]!;
        final done = eps.where(_isComplete).length;
        return GestureDetector(
          onTap: () => setState(() => _activeSeason = season),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: t.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(RaddSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.14),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Icon(AppIcons.folder2, color: AppColors.primary, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppRadius.round)),
                    child: Text('$done/${eps.length}', style: TextStyle(
                        color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800))),
                ]),
                const Spacer(),
                Text('Season $season', style: TextStyle(
                    color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${eps.length} episode${eps.length == 1 ? '' : 's'}',
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
              ]),
            ),
          ),
        ).animate(delay: (i * 40).ms).fadeIn(duration: 260.ms).slideY(begin: 0.06, end: 0);
      },
    );
  }

  Widget _buildEpisodeList(List<Map<String, dynamic>> episodes, DownloadsState state) {
    final t = RaddTheme.of(context);
    final eps = episodes.where((d) =>
        parseEpisodeTitle(_title(d)).seasonOrDefault == _activeSeason).toList()
      ..sort((a, b) => (parseEpisodeTitle(_title(a)).episode ?? 0)
          .compareTo(parseEpisodeTitle(_title(b)).episode ?? 0));
    final doneEps = eps.where(_isComplete).toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      physics: const BouncingScrollPhysics(),
      itemCount: eps.length,
      itemBuilder: (_, i) {
        final d = eps[i];
        final id = _id(d);
        final isComp = _isComplete(d);
        final isAct  = state.isDownloading(id);
        final prog   = state.progressOf(id) != 0 ? state.progressOf(id)
            : (d['progress'] as num?)?.toDouble() ?? 0.0;
        final status = _status(d);
        final isSel  = _selected.contains(id);

        return Dismissible(
          key: ValueKey(id),
          direction: isComp ? DismissDirection.horizontal : DismissDirection.none,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(AppIcons.lock, color: AppColors.primary),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(AppIcons.trash, color: AppColors.error),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart) {
              return await _confirmDelete(_title(d));
            }
            // startToEnd: vault — handled without actually removing the tile.
            await _moveToVault(d);
            return false;
          },
          onDismissed: (_) => ref.read(downloadsProvider.notifier).deleteDownload(id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary.withOpacity(0.08) : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: isSel ? AppColors.primary : t.border, width: isSel ? 1.5 : 0.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                if (_selecting) {
                  setState(() { isSel ? _selected.remove(id) : _selected.add(id); });
                } else if (isComp) {
                  final epIdx = doneEps.indexOf(d);
                  final epList = doneEps.asMap().entries.map((e) => <String, dynamic>{
                    'file_id':    _id(e.value),
                    'local_path': _path(e.value),
                    'label':      _title(e.value),
                    'episode':    e.key,
                  }).toList();
                  DebugLogger.logFeature('PlayDownloaded', 'from SeasonFolderScreen');
                  Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
                    'file_id':      id,
                    'title':        _title(d),
                    'local_path':   _path(d),
                    'episodes':     epList,
                    'episode_index': epIdx < 0 ? 0 : epIdx,
                    'content_type': d['content_type'] as String? ?? 'show',
                    'is_free':      true,
                  });
                }
              },
              onLongPress: () => setState(() { _selecting = true; _selected.add(id); }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComp ? AppColors.primary.withOpacity(0.12)
                          : isAct ? const Color(0xFF22C55E).withOpacity(0.12)
                          : status == 'failed' ? AppColors.error.withOpacity(0.12)
                          : t.card,
                    ),
                    child: Icon(
                      isComp ? AppIcons.play
                          : isAct ? AppIcons.cloudDownload
                          : status == 'failed' ? AppIcons.errorIcon
                          : AppIcons.hourglass,
                      size: 15,
                      color: isComp ? AppColors.primary
                          : isAct ? const Color(0xFF22C55E)
                          : status == 'failed' ? AppColors.error
                          : t.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(episodeDisplayCode(_title(d)), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (isAct) ...[
                      const SizedBox(height: 5),
                      ClipRRect(borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: prog, backgroundColor: t.card,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                            minHeight: 3)),
                      const SizedBox(height: 3),
                      Text(
                        '${(prog * 100).toStringAsFixed(0)}%'
                        '${state.speedOf(id).isNotEmpty ? "  ${state.speedOf(id)}" : ""}'
                        '${state.etaOf(id).isNotEmpty ? "  ${state.etaOf(id)}" : ""}',
                        style: const TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.w600)),
                    ] else
                      Text(_fmtSize(_size(d)), style: TextStyle(color: t.textMuted, fontSize: 11)),
                  ])),
                  if (!_selecting)
                    status == 'failed'
                        ? IconButton(
                            icon: Icon(AppIcons.refresh, size: 18, color: AppColors.primary.withOpacity(0.85)),
                            onPressed: () => ref.read(downloadsProvider.notifier).retryDownload(
                                fileId: id, titleText: _title(d),
                                posterUrl: d['poster_url'] as String?,
                                contentType: d['content_type'] as String?).ignore(),
                          )
                        : isAct
                            ? IconButton(
                                icon: Icon(AppIcons.stopIcon, size: 18, color: AppColors.error.withOpacity(0.75)),
                                onPressed: () => ref.read(downloadsProvider.notifier).cancelDownload(id).ignore(),
                              )
                            : IconButton(
                                icon: Icon(AppIcons.trash, size: 18, color: t.textMuted),
                                onPressed: () async {
                                  if (await _confirmDelete(_title(d))) {
                                    ref.read(downloadsProvider.notifier).deleteDownload(id);
                                  }
                                },
                              ),
                  if (_selecting)
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: isSel ? AppColors.primary : Colors.transparent,
                          border: Border.all(color: isSel ? AppColors.primary : t.textMuted, width: 1.5)),
                      child: isSel ? Icon(AppIcons.check, color: Colors.white, size: 12) : null,
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(String title) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Download'),
      content: Text('Delete "$title"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    ));
    return ok == true;
  }

  Future<void> _moveToVault(Map<String, dynamic> d) async {
    if (!_isComplete(d)) return;
    final hasPin = await VaultService.hasPin();
    if (!hasPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Set up your vault PIN first (Profile → Vault)')));
      return;
    }
    if (!VaultService.isUnlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unlock your vault first (Profile → Vault → Unlock)')));
      return;
    }
    final path = _path(d);
    if (path.isEmpty || !File(path).existsSync()) return;
    try {
      await VaultService.moveFileToVault(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${_title(d)}" moved to vault')));
      ref.read(downloadsProvider.notifier).loadDownloads();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move to vault')));
    }
  }

  Future<void> _bulkDelete(List<Map<String, dynamic>> episodes) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Selected'),
      content: Text('Delete $count episode${count == 1 ? '' : 's'}?'),
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
