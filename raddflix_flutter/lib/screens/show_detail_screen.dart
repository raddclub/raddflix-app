import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../models/catalog_item.dart';
import '../providers/catalog_provider.dart';
import '../core/download/download_service.dart';
import '../providers/downloads_provider.dart';
import '../providers/watchlist_provider.dart';
import 'subscription_screen.dart';

class ShowDetailScreen extends ConsumerStatefulWidget {
  final CatalogItem item;
  const ShowDetailScreen({super.key, required this.item});

  @override
  ConsumerState<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen>
    with TickerProviderStateMixin {
  late TabController? _seasonTab;
  List<Map<String, dynamic>> _episodes = [];
  bool _loading = true;
  int _selectedSeason = 1;
  List<int> _seasons = [];
  Map<String, double> _watchProgress = {};
  int? _resumeEpisodeIndex;  // episode index (in _episodes) to resume
  int? _nowPlayingIdx;       // episode index currently open in the player

  @override
  void initState() {
    super.initState();
    _seasonTab = null;
    _loadEpisodes();
  }

  @override
  void dispose() {
    _seasonTab?.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodes() async {
    final eps = await LocalDb.getEpisodes(widget.item.id);
    // Clear the new-episode badge on the home screen card for this show
    if (widget.item.isShow) {
      LocalDb.markEpisodesSeen(widget.item.id).ignore();
    }
    final progList = await LocalDb.getWatchPositions();
    final prog = <String, double>{};
    for (final p in progList) {
      if (p['file_id'] != null && p['duration_ms'] != null && (p['duration_ms'] as int) > 0) {
        final pos = (p['position_ms'] as int? ?? 0); // BUG-005 fix
        final dur = (p['duration_ms'] as int? ?? 0); // BUG-005 fix
        prog[p['file_id'].toString()] = (pos / dur).clamp(0.0, 1.0);
      }
    }

    final seasonNums = eps
        .map((e) => (e['season'] as int? ?? 1))
        .toSet()
        .toList()
      ..sort();

    // Find the episode most recently watched but not finished, to show Resume button
    int? resumeIdx;
    double resumeHighProg = 0;
    for (int i = 0; i < eps.length; i++) {
      final fid = eps[i]['file_id']?.toString() ?? '';
      final p = prog[fid] ?? 0.0;
      if (p > 0.03 && p < 0.95 && p > resumeHighProg) {
        resumeHighProg = p;
        resumeIdx = i;
      }
    }

    if (mounted) {
      setState(() {
        _episodes = eps;
        _seasons = seasonNums.isEmpty ? [1] : seasonNums;
        _selectedSeason = _seasons.first;
        _watchProgress = prog;
        _resumeEpisodeIndex = resumeIdx;
        _loading = false;
        if (_seasons.length > 1) {
          _seasonTab = TabController(length: _seasons.length, vsync: this);
          _seasonTab!.addListener(() {
            if (!_seasonTab!.indexIsChanging) {
              setState(() => _selectedSeason = _seasons[_seasonTab!.index]);
            }
          });
        }
      });
    }
  }

  List<Map<String, dynamic>> get _currentEpisodes =>
      _episodes.where((e) => (e['season'] as int? ?? 1) == _selectedSeason).toList();

  Future<void> _playEpisode(int episodeIndex) async {
    final allEps = _currentEpisodes;
    if (episodeIndex >= allEps.length) return;
    final ep = allEps[episodeIndex];
    final fileId = ep['file_id']?.toString();
    // getEpisodes() returns raw SQLite rows — share_url is XOR-encoded; decode it.
    final rawEpShareUrl = ep['share_url'] as String?;
    final epShareUrl = await LocalDb.decodeShareUrl(rawEpShareUrl);

    // Prefer locally-downloaded file: plays offline, no JazzDrive needed.
    final dlState = ref.read(downloadsProvider);
    final localPath = (fileId != null && fileId.isNotEmpty)
        ? dlState.getLocalPath(fileId)
        : null;

    // Only block when ALL three are missing: no local file, no fileId, no share_url.
    if (localPath == null &&
        (fileId == null || fileId.isEmpty) &&
        (epShareUrl == null || epShareUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video not available yet. Please sync in Settings → Sync.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Mark this episode as "now playing" so the tile shows the indicator;
    // clear it when the player route pops (user exits or PiP closes).
    setState(() => _nowPlayingIdx = episodeIndex);
    await Navigator.pushNamed(
      context,
      AppRoutes.player,
      arguments: {
        'file_id': fileId ?? '',
        'title': ep['label'] ?? '${widget.item.title} S${_selectedSeason.toString().padLeft(2, '0')}E${(ep['episode'] as int? ?? 0).toString().padLeft(2, '0')}',
        'local_path': localPath,
        'stream_url': localPath != null ? null : epShareUrl,
        'episodes': allEps,
        'episode_index': episodeIndex,
        'show_title': widget.item.title,
        'content_type': widget.item.mediaType,
      },
    );
    if (mounted) setState(() => _nowPlayingIdx = null);
  }

  void _playMovie() {
    final fileId = widget.item.fileId;
    final shareUrl = widget.item.shareUrl;
    if (fileId == null && (shareUrl == null || shareUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video not available yet. Please try again later.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.player,
      arguments: {
        'file_id': fileId ?? '',
        'title': widget.item.title,
        'local_path': null,
        'stream_url': shareUrl,
        'episodes': <Map<String, dynamic>>[],
        'episode_index': 0,
        'content_type': 'movie',
      },
    );
  }

  void _showQuotaError(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Upgrade',
        textColor: Colors.white,
        onPressed: () => Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final item = widget.item;
    final cs = Theme.of(context).colorScheme;
    final isMovie = item.isMovie;

    return Scaffold(
      backgroundColor: null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero Poster SliverAppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            stretch: true,
            backgroundColor: t.surface,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster image — local cache first (zero-rated, works offline)
                  if (item.posterPath != null && item.posterPath!.isNotEmpty)
                    Image.file(
                      File(item.posterPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => item.posterUrl != null
                          ? CachedNetworkImage(
                              imageUrl: item.posterUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: t.surface),
                              errorWidget: (_, __, ___) => _posterFallback(item),
                            )
                          : _posterFallback(item),
                    )
                  else if (item.posterUrl != null)
                    CachedNetworkImage(
                      imageUrl: item.posterUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: t.surface),
                      errorWidget: (_, __, ___) => _posterFallback(item),
                    )
                  else
                    _posterFallback(item),
                  // Gradient overlay
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          t.bg.withOpacity(0.3),
                          t.bg.withOpacity(0.85),
                          t.bg,
                        ],
                        stops: const [0.0, 0.4, 0.75, 1.0],
                      ),
                    ),
                  ),
                  // Bottom info
                  Positioned(
                    left: 20, right: 20, bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800,
                            color: Colors.white, shadows: [Shadow(blurRadius: 8)],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (item.displayYear.isNotEmpty) ...[
                              Text(item.displayYear, style: TextStyle(color: Colors.white70, fontSize: 13)),
                              const _Dot(),
                            ],
                            if (item.displayRating.isNotEmpty) ...[
                              const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                              const SizedBox(width: 3),
                              Text(item.displayRating, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              const _Dot(),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.2),
                                border: Border.all(color: AppColors.primary.withOpacity(0.6)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isMovie ? 'MOVIE' : 'SERIES',
                                style: TextStyle(
                                  color: AppColors.primary, fontSize: 10,
                                  fontWeight: FontWeight.w700, letterSpacing: 1,
                                ),
                              ),
                            ),
                            if (item.statusLabel.isNotEmpty) ...[
                              const _Dot(),
                              _StatusPill(label: item.statusLabel, status: item.status ?? ''),
                            ],
                            if (item.isFree) ...[
                              const _Dot(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  border: Border.all(color: Colors.green.withOpacity(0.6)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('FREE', style: TextStyle(
                                  color: Colors.green, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                                )),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 4),

                  // Genres
                  if (item.genres != null && item.genres!.isNotEmpty) ...[
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: _parseGenres(item.genres!).map((g) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: t.border),
                        ),
                        child: Text(g, style: TextStyle(color: t.textSecondary, fontSize: 12)),
                      )).toList(),
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 16),
                  ],

                  // Description
                  if (item.description != null && item.description!.isNotEmpty) ...[
                    _ExpandableText(text: item.description!),
                    const SizedBox(height: 20),
                  ],

                  // ── MOVIE: Play + Download buttons ─────────────────────────
                  if (isMovie) ...[
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _playMovie,
                          icon: const Icon(Icons.play_arrow_rounded, size: 24),
                          label: const Text('Play Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      if (widget.item.fileId != null) ...[
                        const SizedBox(width: 10),
                        Consumer(builder: (context, ref2, _) {
                          final isDownloading = ref2.watch(downloadsProvider).isDownloading(widget.item.fileId!);
                          return SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isDownloading ? null : () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Downloading ${widget.item.title}…'),
                                    duration: const Duration(seconds: 2)),
                                );
                                try {
                                  await ref2.read(downloadsProvider.notifier).startDownload(
                                    fileId: widget.item.fileId!,
                                    titleText: widget.item.title,
                                    streamUrl: widget.item.shareUrl ?? '',
                                    posterUrl: widget.item.posterUrl,
                                  );
                                } on DownloadQuotaException catch (e) {
                                  if (context.mounted) _showQuotaError(context, e.userMessage);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.surface,
                                foregroundColor: t.textSecondary,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: t.border)),
                                elevation: 0,
                              ),
                              child: isDownloading
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : const Icon(Icons.download_for_offline_outlined, size: 22),
                            ),
                          );
                        }),
                      ],
                    ]).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
                    const SizedBox(height: 32),
                  ],

                  // ── Watchlist toggle button ───────────────────────────────────
                  Consumer(builder: (context, ref2, _) {
                    final inWatchlist = ref2.watch(watchlistProvider).isInWatchlist(widget.item.id);
                    return GestureDetector(
                      onTap: () async {
                        await ref2.read(watchlistProvider.notifier).toggle(widget.item);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(inWatchlist
                                ? 'Removed from Watchlist'
                                : 'Added to Watchlist'),
                            duration: const Duration(seconds: 2),
                          ));
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: inWatchlist
                              ? AppColors.primary.withOpacity(0.12)
                              : t.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inWatchlist ? AppColors.primary : t.border,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              inWatchlist
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_add_outlined,
                              color: inWatchlist ? AppColors.primary : t.textSecondary,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              inWatchlist ? 'In Watchlist' : 'Add to Watchlist',
                              style: TextStyle(
                                color: inWatchlist ? AppColors.primary : t.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 16),

                  // ── SHOW: Season Tabs + Episodes ───────────────────────────
                  if (!isMovie) ...[
                    // Resume button — only shown when a partially-watched episode exists
                    if (_resumeEpisodeIndex != null && !_loading) ...[
                      Builder(builder: (ctx) {
                        final idx  = _resumeEpisodeIndex!;
                        final ep   = idx < _episodes.length ? _episodes[idx] : null;
                        if (ep == null) return const SizedBox.shrink();
                        final epNum  = ep['episode'] as int? ?? (idx + 1);
                        final season = ep['season']  as int? ?? 1;
                        final fid    = ep['file_id']?.toString() ?? '';
                        final prog   = _watchProgress[fid] ?? 0.0;
                        final pct    = (prog * 100).round();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                // Find the index of this episode in _currentEpisodes
                                final currentIdx = _currentEpisodes.indexWhere(
                                  (e) => e['file_id']?.toString() == fid);
                                if (currentIdx >= 0) {
                                  _playEpisode(currentIdx);
                                } else {
                                  // Episode might be in another season — switch and play
                                  setState(() => _selectedSeason = season);
                                  Future.microtask(() {
                                    final newIdx = _currentEpisodes.indexWhere(
                                      (e) => e['file_id']?.toString() == fid);
                                    if (newIdx >= 0) _playEpisode(newIdx);
                                  });
                                }
                              },
                              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                              label: Text(
                                'Resume S${season.toString().padLeft(2,'0')}E${epNum.toString().padLeft(2,'0')} · $pct%',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                            SizedBox(height: 16),
                          ],
                        );
                      }),
                    ],

                    // Season header
                    Row(
                      children: [
                        Text(
                          'Episodes',
                          style: TextStyle(
                            color: t.textPrimary, fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (!_loading)
                          Text(
                            '${_currentEpisodes.length} episodes',
                            style: TextStyle(color: t.textSecondary, fontSize: 13),
                          ),
                      ],
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 12),

                    // Season selector
                    if (_seasons.length > 1)
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _seasons.length,
                          separatorBuilder: (_, __) => SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final s = _seasons[i];
                            final selected = s == _selectedSeason;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedSeason = s);
                                _seasonTab?.animateTo(i);
                              },
                              child: AnimatedContainer(
                                duration: AppDurations.fast,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.primary : t.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? AppColors.primary : t.border,
                                  ),
                                ),
                                child: Text(
                                  'Season $s',
                                  style: TextStyle(
                                    color: selected ? Colors.white : t.textSecondary,
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ).animate().fadeIn(delay: 200.ms),

                    if (_seasons.length > 1) const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),

          // ── Episode List ──────────────────────────────────────────────────
          if (!widget.item.isMovie)
            _loading
                ? SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _EpisodeShimmer(),
                      childCount: 6,
                    ),
                  )
                : _currentEpisodes.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.video_library_outlined,
                                    size: 48, color: t.textSecondary),
                                SizedBox(height: 12),
                                Text('No episodes in Season $_selectedSeason',
                                    style: TextStyle(color: t.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final ep = _currentEpisodes[i];
                            final fileId = ep['file_id']?.toString() ?? '';
                            final progress = _watchProgress[fileId] ?? 0.0;
                            final epNum = ep['episode'] as int? ?? (i + 1);
                            final season = ep['season'] as int? ?? _selectedSeason;
                            final label = ep['label'] as String? ??
                                'S${season.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
                            final isFree = (ep['is_free'] as int? ?? 0) == 1;

                            final epShareUrl = ep['share_url'] as String? ?? '';
                            final dlState = ref.watch(downloadsProvider);
                            final isDownloading = dlState.isDownloading(fileId);
                            final isDownloaded  = dlState.isDownloaded(fileId);
                            return _EpisodeTile(
                              index: i,
                              label: label,
                              isFree: isFree,
                              progress: progress,
                              isNowPlaying: i == _nowPlayingIdx,
                              onTap: () => _playEpisode(i),
                              isDownloading: isDownloading,
                              isDownloaded: isDownloaded,
                              onDownload: fileId.isEmpty || isDownloaded ? null : () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Downloading $label…'),
                                    duration: const Duration(seconds: 2)),
                                );
                                try {
                                  await ref.read(downloadsProvider.notifier).startDownload(
                                    fileId: fileId,
                                    titleText: '${widget.item.title} $label',
                                    streamUrl: epShareUrl,
                                    posterUrl: widget.item.posterUrl,
                                    targetFilename: ep['filename'] as String?,
                                  );
                                } on DownloadQuotaException catch (e) {
                                  if (context.mounted) _showQuotaError(context, e.userMessage);
                                }
                              },
                            ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 + i * 40),
                            );
                          },
                          childCount: _currentEpisodes.length,
                        ),
                      ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _posterFallback(CatalogItem item) => Container(
    color: t.surface,
    child: Center(
      child: Icon(
        item.isMovie ? Icons.movie_outlined : Icons.tv_outlined,
        size: 64, color: t.textSecondary,
      ),
    ),
  );

  List<String> _parseGenres(String raw) {
    try {
      raw = raw.trim();
      if (raw.startsWith('[')) {
        raw = raw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').replaceAll("'", '');
      }
      return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).take(5).toList();
    } catch (_) {
      return [];
    }
  }
}

// ── Episode Tile ─────────────────────────────────────────────────────────────
class _EpisodeTile extends StatelessWidget {
  final int index;
  final String label;
  final bool isFree;
  final double progress;
  final bool isNowPlaying;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool isDownloaded;

  const _EpisodeTile({
    required this.index,
    required this.label,
    required this.isFree,
    required this.progress,
    required this.onTap,
    this.isNowPlaying = false,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final watched = progress > 0.05 && progress < 0.95;
    final completed = progress >= 0.95;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: isNowPlaying ? AppColors.primary.withOpacity(0.06) : t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isNowPlaying ? AppColors.primary.withOpacity(0.55) : t.border,
                width: isNowPlaying ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Episode number badge — replaced by animated ▶ while playing
                  isNowPlaying
                      ? Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: Center(
                            child: Icon(Icons.graphic_eq_rounded,
                                color: AppColors.primary, size: 22),
                          ),
                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                         .scaleXY(begin: 0.92, end: 1.0, duration: 700.ms, curve: Curves.easeInOut)
                      : Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: completed
                                ? Colors.green.withOpacity(0.15)
                                : watched
                                    ? AppColors.primary.withOpacity(0.15)
                                    : t.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: completed
                                ? Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: watched ? AppColors.primary : t.textSecondary,
                                      fontWeight: FontWeight.w700, fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                  SizedBox(width: 12),
                  // Episode info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w600, fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isNowPlaying)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.graphic_eq_rounded,
                                        color: AppColors.primary, size: 9),
                                    SizedBox(width: 3),
                                    Text('NOW PLAYING', style: TextStyle(
                                      color: AppColors.primary, fontSize: 9,
                                      fontWeight: FontWeight.w800, letterSpacing: 0.5,
                                    )),
                                  ],
                                ),
                              )
                            else if (isDownloaded)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.download_done_rounded, color: AppColors.success, size: 9),
                                    SizedBox(width: 3),
                                    Text('OFFLINE', style: TextStyle(
                                      color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                                    )),
                                  ],
                                ),
                              )
                            else if (isFree)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('FREE', style: TextStyle(
                                  color: Colors.green, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                                )),
                              ),
                          ],
                        ),
                        if (watched) ...[
                          SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: t.border,
                              valueColor: AlwaysStoppedAnimation(AppColors.primary),
                              minHeight: 3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '${(progress * 100).toInt()}% watched',
                            style: TextStyle(color: t.textSecondary, fontSize: 11),
                          ),
                        ] else if (completed) ...[
                          const SizedBox(height: 4),
                          Text('Watched', style: TextStyle(color: Colors.green, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 4),
                  // Download + Play icons
                  if (isDownloaded)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.download_done_rounded,
                          color: AppColors.success, size: 22))
                  else if (isDownloading)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary)))
                  else if (onDownload != null)
                    GestureDetector(
                      onTap: onDownload,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.download_for_offline_outlined,
                            color: t.textSecondary, size: 22))),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    color: AppColors.primary, size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shimmer loading tile ──────────────────────────────────────────────────────
class _EpisodeShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.border,
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ── Expandable description text ───────────────────────────────────────────────
class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText({required this.text});
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedCrossFade(
        duration: AppDurations.fast,
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textSecondary, height: 1.5, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text('Read more', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        secondChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: TextStyle(color: t.textSecondary, height: 1.5, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text('Show less', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────
class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text('·', style: TextStyle(color: t.textSecondary)),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final String status;
  const _StatusPill({required this.label, required this.status});

  Color get _color {
    switch (status) {
      case 'ongoing':   return const Color(0xFF22C55E);
      case 'completed': return const Color(0xFF3B82F6);
      case 'cancelled': return const Color(0xFFEF4444);
      default:          return t.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.18),
        border: Border.all(color: c.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
        style: TextStyle(color: c, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
    );
  }
}
