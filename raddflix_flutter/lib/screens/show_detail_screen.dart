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
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import 'subscription_screen.dart';
import '../widgets/cast_rail.dart';
import '../core/debug/debug_logger.dart';

class ShowDetailScreen extends ConsumerStatefulWidget {
  final CatalogItem item;
  const ShowDetailScreen({super.key, required this.item});

  @override
  ConsumerState<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen>
    with TickerProviderStateMixin {
  RaddTheme get t => RaddTheme.of(context);

  late TabController? _seasonTab;
  List<Map<String, dynamic>> _episodes = [];
  bool _loading = true;
  int _selectedSeason = 1;
  List<int> _seasons = [];
  Map<String, double> _watchProgress = {};
  int? _resumeEpisodeIndex;  // episode index (in _episodes) to resume
  int? _nowPlayingIdx;       // episode index currently open in the player

  // Admin panel
  Map<String, String> _overrides = {};
  bool _adminMode = false;
  int _adminTapCount = 0;

  // Sort
  bool _sortAscending = true;
  // Tracks active "Download Season" batch to prevent duplicate triggers.
  bool _isDownloadingAll = false;

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('ShowDetail', 'initState id=${widget.item.id} title="${widget.item.title}" type=${widget.item.mediaType}');
    _seasonTab = null;
    _loadEpisodes();
  }

  @override
  void dispose() {
    DebugLogger.logLifecycle('ShowDetail', 'dispose id=${widget.item.id}');
    _seasonTab?.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodes() async {
    // M-02: multiple DB awaits with no error handling — a LocalDb failure would
    // leave the detail screen in a permanent loading state with no user feedback.
    try {
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

    final overrides = await LocalDb.getEpisodeOverrides(widget.item.id);

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
      DebugLogger.log('DETAIL', '_loadEpisodes done: ${eps.length} eps, ${seasonNums.length} seasons, resumeIdx=$resumeIdx for id=${widget.item.id}');
      // H-01: dispose the old TabController BEFORE setState — disposing inside
      // setState risks destroying a controller the framework still reads during
      // the current build phase, causing a 'disposed controller' assertion.
      final willHaveMultipleSeasons = seasonNums.length > 1;
      if (willHaveMultipleSeasons) {
        _seasonTab?.dispose();
        _seasonTab = null;
      }
      setState(() {
        _episodes = eps;
        _seasons = seasonNums.isEmpty ? [1] : seasonNums;
        _selectedSeason = _seasons.first;
        _watchProgress = prog;
        _overrides = overrides;
        _resumeEpisodeIndex = resumeIdx;
        _loading = false;
        if (willHaveMultipleSeasons) {
          _seasonTab = TabController(length: _seasons.length, vsync: this);
          _seasonTab!.addListener(() {
            if (!_seasonTab!.indexIsChanging) {
              setState(() => _selectedSeason = _seasons[_seasonTab!.index]);
            }
          });
        }
      });
    }
    } catch (e) {
      DebugLogger.logError('DETAIL', 'Failed to load episodes', e);
      if (mounted) setState(() { _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _currentEpisodes {
    final eps = _episodes
        .where((e) => (e['season'] as int? ?? 1) == _selectedSeason)
        .toList();
    return _sortAscending ? eps : eps.reversed.toList();
  }

  int _totalCountForSeason(int s) =>
      _episodes.where((e) => (e['season'] as int? ?? 1) == s).length;

  int _watchedCountForSeason(int s) => _episodes
      .where((e) => (e['season'] as int? ?? 1) == s)
      .where((e) {
        final fid = e['file_id']?.toString() ?? '';
        return (_watchProgress[fid] ?? 0.0) >= 0.95;
      })
      .length;

  List<Map<String, dynamic>> get _currentEpisodesWithGaps {
    final eps = _currentEpisodes;
    if (eps.isEmpty) return eps;
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < eps.length; i++) {
      if (i > 0) {
        final prevNum = eps[i - 1]['episode'] as int? ?? 0;
        final thisNum = eps[i]['episode'] as int? ?? 0;
        for (int g = prevNum + 1; g < thisNum; g++) {
          result.add({
            '_placeholder': true,
            'episode': g,
            'season': eps[i]['season'] ?? _selectedSeason,
            'label': 'S${_selectedSeason.toString().padLeft(2, '0')}E${g.toString().padLeft(2, '0')}',
            '_override': _overrides['${_selectedSeason}_$g'],
          });
        }
      }
      result.add({...eps[i], '_realIndex': i});
    }
    return result;
  }

  Future<void> _playEpisode(int episodeIndex) async {
    // BUG-M02+M06 fix: build a single ascending list across ALL seasons for the player.
    // Previously allEps = _currentEpisodes which:
    //   (M02) could be descending when user toggled sort → player Next/Prev reversed
    //   (M06) only contained the current season → player could not navigate across seasons
    // The UI sort (_sortAscending) only affects the episode-list display, never the player.
    final allEps = _currentEpisodes; // still used for bounds-check against current season
    if (episodeIndex >= allEps.length) return;
    final ep = allEps[episodeIndex];
    // All-seasons list, always ascending (season → episode number)
    final allSeasonsEps = _episodes
        .where((e) => (e['file_id']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) {
        final sc = (a['season'] as int? ?? 1).compareTo(b['season'] as int? ?? 1);
        return sc != 0 ? sc : (a['episode'] as int? ?? 0).compareTo(b['episode'] as int? ?? 0);
      });
    final playerIdx = allSeasonsEps
        .indexWhere((e) => e['file_id']?.toString() == ep['file_id']?.toString());
    // fallback: if file_id not found, use position within current season
    final resolvedPlayerIdx = playerIdx >= 0 ? playerIdx : episodeIndex;
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

    // Access gate — free episodes play for everyone; paid episodes require subscription.
    final isFreeEp = (ep['is_free'] as int? ?? 0) == 1;
    if (!isFreeEp && !_isSubscribed) {
      _requireSub(context);
      return;
    }

    // Mark this episode as "now playing" so the tile shows the indicator;
    // clear it when the player route pops (user exits or PiP closes).
    DebugLogger.logFeature('PlayEpisode', 'id=${widget.item.id} title="${widget.item.title}" epIdx=$episodeIndex S$_selectedSeason fileId=${fileId ?? "null"} local=${localPath != null}');
    setState(() => _nowPlayingIdx = episodeIndex);
    await Navigator.pushNamed(
      context,
      AppRoutes.player,
      arguments: {
        'file_id': fileId ?? '',
        'title': ep['label'] ?? '${widget.item.title} S${_selectedSeason.toString().padLeft(2, '0')}E${(ep['episode'] as int? ?? 0).toString().padLeft(2, '0')}',
        'local_path': localPath,
        'stream_url': localPath != null ? null : epShareUrl,
        'episodes': allSeasonsEps,       // all seasons, ascending
        'episode_index': resolvedPlayerIdx, // index within allSeasonsEps
        'show_title': widget.item.title,
        'content_type': widget.item.mediaType,
        'is_free': (ep['is_free'] as int? ?? 0) == 1,
      },
    );
    if (mounted) setState(() => _nowPlayingIdx = null);
  }

  void _playMovie() {
    DebugLogger.logFeature('PlayMovie', 'id=${widget.item.id} title="${widget.item.title}" fileId=${widget.item.fileId ?? "null"}');
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
    // Access gate — paid movies require an active subscription.
    if (!widget.item.isFree && !_isSubscribed) {
      _requireSub(context);
      return;
    }

    // Prefer locally-downloaded file: plays offline, no JazzDrive needed.
    final dlState = ref.read(downloadsProvider);
    final localPath = (fileId != null && fileId.isNotEmpty)
        ? dlState.getLocalPath(fileId)
        : null;
    Navigator.pushNamed(
      context,
      AppRoutes.player,
      arguments: {
        'file_id': fileId ?? '',
        'title': widget.item.title,
        'local_path': localPath,
        'stream_url': localPath != null ? null : shareUrl,
        'episodes': <Map<String, dynamic>>[],
        'episode_index': 0,
        'content_type': 'movie',
        'is_free': widget.item.isFree,
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

  // ── Subscription access helpers ──────────────────────────────────────────

  /// True when the current user has an active paid subscription.
  /// Guests (isGuest=true) and free-plan users (subscription==null) return false.
  // BUG-H04 fix: prefer subscriptionProvider.status which is refreshed at
  // startup (H05 fix) and after every TID submission. authProvider.user.subscription
  // can lag: e.g. a just-renewed plan won't appear in auth cache until next /me call.
  bool get _isSubscribed {
    final user = ref.read(authProvider).user;
    if (user == null || user.isGuest) return false;
    final subStatus = ref.read(subscriptionProvider).status;
    if (subStatus != null) return subStatus.isActive;
    return user.subscription?.isActive == true; // fallback if provider hasn't loaded yet
  }

  /// Shows a paywall snack-bar with a Subscribe action button.
  /// Tapping Subscribe navigates to the subscription screen.
  void _requireSub(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: const Text('Subscribe to access paid content'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Subscribe',
          textColor: Colors.white,
          onPressed: () => Navigator.of(ctx).pushNamed(AppRoutes.subscription),
        ),
      ),
    );
  }

  // ── Download all available episodes in the current season ──────────────
  Future<void> _downloadCurrentSeason() async {
    if (_isDownloadingAll) return;
    // BUG-H03 fix: only require a subscription when the season contains paid episodes.
    // Previously ALL batch-downloads required a subscription, blocking free-episode
    // seasons for unsubscribed / free-plan users (unfair and incorrect UX).
    final hasPaidEps = _currentEpisodes.any((ep) => (ep['is_free'] as int? ?? 0) != 1);
    if (hasPaidEps && !_isSubscribed) { _requireSub(context); return; }
    final dlState = ref.read(downloadsProvider);
    // Only queue episodes that have a fileId and are not already downloaded/queued
    final toQueue = _currentEpisodes.where((ep) {
      final fid = ep['file_id']?.toString() ?? '';
      return fid.isNotEmpty
          && !dlState.isDownloaded(fid)
          && !dlState.isDownloading(fid);
    }).toList();
    if (toQueue.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All available episodes are already downloaded'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _isDownloadingAll = true);
    int queued = 0;
    for (final ep in toQueue) {
      final fid   = ep['file_id']?.toString() ?? '';
      final sNum  = (ep['season']   as int? ?? _selectedSeason).toString().padLeft(2, '0');
      final eNum  = (ep['episode']  as int? ?? 0).toString().padLeft(2, '0');
      final label = ep['label']    as String? ?? 'S${sNum}E${eNum}';
      final rawUrl = ep['share_url'] as String?;
      final shareUrl = await LocalDb.decodeShareUrl(rawUrl) ?? '';
      if (shareUrl.isEmpty) continue;
      try {
        await ref.read(downloadsProvider.notifier).startDownload(
          fileId:         fid,
          titleText:      '${widget.item.title} $label',
          streamUrl:      shareUrl,
          posterUrl:      widget.item.posterUrl,
          targetFilename: ep['filename'] as String?,
          remoteId:       ep['remote_id'] as int? ?? 0,
          contentType:    widget.item.mediaType,
        );
        queued++;
      } on DownloadQuotaException catch (e) {
        if (mounted) _showQuotaError(context, e.userMessage);
        break; // quota hit — stop queuing
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isDownloadingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(queued > 0
            ? 'Queued $queued episode${queued == 1 ? '' : 's'} for download'
            : 'Nothing new to download'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showAdminSheet(int episode, int season) async {
    final gaps = _currentEpisodesWithGaps
        .where((e) => e['_placeholder'] == true)
        .toList();
    if (gaps.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminEpisodePanel(
        showId: widget.item.id,
        showTitle: widget.item.title,
        season: season,
        gaps: gaps,
        overrides: Map<String, String>.from(_overrides),
        onChanged: (updated) => setState(() => _overrides = updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final item = widget.item;
    final cs = Theme.of(context).colorScheme;
    final isMovie = item.isMovie;

    return Scaffold(
      backgroundColor: null,
      body: RefreshIndicator(
        onRefresh: _loadEpisodes,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
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

                  // Cast & crew strip (TMDB — hidden when API key absent)
                  CastRail(item: item),
                  const SizedBox(height: 16),

                  // ── MOVIE: Play + Download buttons ─────────────────────────
                  if (isMovie) ...[
                    Row(children: [
                      // Play button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _playMovie,
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      // Download button — equal width, labelled
                      if (widget.item.fileId != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Consumer(builder: (context, ref2, _) {
                            final dlState2 = ref2.watch(downloadsProvider);
                            final isDownloading = dlState2.isDownloading(widget.item.fileId!);
                            final isDownloaded  = dlState2.isDownloaded(widget.item.fileId!);
                            return ElevatedButton.icon(
                              onPressed: isDownloading || isDownloaded ? null : () async {
                                // Access gate — paid movie downloads require subscription.
                                if (!widget.item.isFree && !_isSubscribed) {
                                  _requireSub(context);
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Downloading ${widget.item.title}…'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                try {
                                  await ref2.read(downloadsProvider.notifier).startDownload(
                                    fileId: widget.item.fileId!,
                                    titleText: widget.item.title,
                                    streamUrl: widget.item.shareUrl ?? '',
                                    posterUrl: widget.item.posterUrl,
                                    contentType: widget.item.mediaType,
                                  );
                                } on DownloadQuotaException catch (e) {
                                  if (context.mounted) _showQuotaError(context, e.userMessage);
                                }
                              },
                              icon: isDownloading
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : Icon(
                                    isDownloaded
                                      ? Icons.download_done_rounded
                                      : Icons.download_for_offline_outlined,
                                    size: 22,
                                    color: isDownloaded ? AppColors.success : null,
                                  ),
                              label: Text(
                                isDownloading ? 'Downloading…'
                                  : isDownloaded ? 'Downloaded'
                                  : 'Download',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.surface,
                                foregroundColor: t.textSecondary,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: t.border),
                                ),
                                elevation: 0,
                              ),
                            );
                          }),
                        ),
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
                        GestureDetector(
                          onTap: () {
                            _adminTapCount++;
                            if (_adminTapCount >= 5) {
                              _adminTapCount = 0;
                              setState(() => _adminMode = !_adminMode);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                  _adminMode ? 'Admin mode enabled' : 'Admin mode disabled'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Episodes',
                                style: TextStyle(
                                  color: t.textPrimary, fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_adminMode) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.withOpacity(0.6)),
                                  ),
                                  child: const Text('ADMIN', style: TextStyle(
                                    color: Colors.orange, fontSize: 9,
                                    fontWeight: FontWeight.w800, letterSpacing: 1,
                                  )),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (!_loading) ...[
                          Text(
                            '${_currentEpisodes.length} eps',
                            style: TextStyle(color: t.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          // Download all available episodes for this season
                          GestureDetector(
                            onTap: _isDownloadingAll ? null : _downloadCurrentSeason,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                              ),
                              child: _isDownloadingAll
                                  ? const SizedBox(width: 13, height: 13,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          valueColor: AlwaysStoppedAnimation(AppColors.primary)))
                                  : Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.download_for_offline_outlined,
                                          size: 14, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      const Text('Season', style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11, fontWeight: FontWeight.w700)),
                                    ]),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(
                                () => _sortAscending = !_sortAscending),
                            child: Tooltip(
                              message: _sortAscending
                                  ? 'Show newest first'
                                  : 'Show oldest first',
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _sortAscending
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  key: ValueKey(_sortAscending),
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
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
                                  _totalCountForSeason(s) > 0
                                      ? 'S$s · ${_watchedCountForSeason(s)}/${_totalCountForSeason(s)}'
                                      : 'Season $s',
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
                        child: _ComingSoonBanner(
                          episodeCount: widget.item.episodeCount,
                          season: _selectedSeason,
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final withGaps = _currentEpisodesWithGaps;
                            final ep = withGaps[i];
                            final epNum = ep['episode'] as int? ?? (i + 1);
                            final season = ep['season'] as int? ?? _selectedSeason;
                            final label = ep['label'] as String? ??
                                'S${season.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
                            if (ep['_placeholder'] == true) {
                              return _EpisodeUnavailableTile(
                                label: label,
                                statusOverride: ep['_override'] as String?,
                                onLongPress: _adminMode
                                    ? () => _showAdminSheet(epNum, season)
                                    : null,
                              ).animate()
                                  .fadeIn(delay: Duration(milliseconds: 50 + i * 40));
                            }
                            final realIdx = ep['_realIndex'] as int;
                            final fileId = ep['file_id']?.toString() ?? '';
                            final progress = _watchProgress[fileId] ?? 0.0;
                            final isFree   = (ep['is_free'] as int? ?? 0) == 1;
                            final quality  = ep['quality'] as String?;
                            final epShareUrl = ep['share_url'] as String? ?? '';
                            final dlState = ref.watch(downloadsProvider);
                            final isDownloading = dlState.isDownloading(fileId);
                            final isDownloaded  = dlState.isDownloaded(fileId);
                            return _EpisodeTile(
                              index: realIdx,
                              label: label,
                              isFree: isFree,
                              quality: quality,
                              progress: progress,
                              isNowPlaying: realIdx == _nowPlayingIdx,
                              onTap: () => _playEpisode(realIdx),
                              isDownloading: isDownloading,
                              isDownloaded: isDownloaded,
                              onDownload: fileId.isEmpty || isDownloaded ? null : () async {
                                // Access gate — paid episode downloads require subscription.
                                if (!isFree && !_isSubscribed) {
                                  _requireSub(context);
                                  return;
                                }
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
                                    remoteId: ep['remote_id'] as int? ?? 0,
                                    contentType: widget.item.mediaType,
                                  );
                                } on DownloadQuotaException catch (e) {
                                  if (context.mounted) _showQuotaError(context, e.userMessage);
                                }
                              },
                            ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 + i * 40),
                            );
                          },
                          childCount: _currentEpisodesWithGaps.length,
                        ),
                      ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
        ),
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
  final String? quality;
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
    this.quality,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
      Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                            if (quality != null && quality!.isNotEmpty && !isNowPlaying && !isDownloaded)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: AppColors.info.withOpacity(0.4)),
                                ),
                                child: Text(quality!.toUpperCase(), style: const TextStyle(
                                  color: AppColors.info, fontSize: 8,
                                  fontWeight: FontWeight.w800, letterSpacing: 0.5,
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
                ],
              ),
            ),
          ),
        ),
      ),
      ),
      // ── Play + Download button row ─────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            // Play button
            Expanded(
              child: SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Download button
            Expanded(
              child: SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: isDownloaded ? null : isDownloading ? null : onDownload,
                  icon: isDownloading
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Icon(
                        isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_for_offline_outlined,
                        size: 18,
                        color: isDownloaded
                          ? AppColors.success
                          : onDownload != null
                            ? null
                            : null,
                      ),
                  label: Text(
                    isDownloading ? 'Saving…'
                      : isDownloaded ? 'Saved'
                      : 'Download',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.surface,
                    foregroundColor: isDownloaded ? AppColors.success : t.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isDownloaded ? AppColors.success.withOpacity(0.5) : t.border,
                      ),
                    ),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ],
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

// ── Unavailable episode placeholder ──────────────────────────────────────────
class _EpisodeUnavailableTile extends StatelessWidget {
  final String label;
  /// null='not available'  |  'coming_soon'=amber  |  'uploading'=blue
  final String? statusOverride;
  final VoidCallback? onLongPress;
  const _EpisodeUnavailableTile({required this.label, this.statusOverride, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isComingSoon = statusOverride == 'coming_soon';
    final isUploading  = statusOverride == 'uploading';
    final hasOverride  = isComingSoon || isUploading;
    final accent = isUploading
        ? const Color(0xFF3B82F6)
        : isComingSoon
            ? const Color(0xFFF59E0B)
            : t.textSecondary;
    final statusText = isUploading
        ? 'Uploading now...'
        : isComingSoon ? 'Coming Soon' : 'Not available';
    final tileIcon = isUploading
        ? Icons.cloud_upload_rounded
        : isComingSoon ? Icons.schedule_rounded : Icons.block_rounded;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: hasOverride ? 0.78 : 0.38,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 68,
            decoration: BoxDecoration(
              color: hasOverride ? accent.withOpacity(0.08) : t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasOverride ? accent.withOpacity(0.45) : t.border,
                width: hasOverride ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: hasOverride ? accent.withOpacity(0.18) : t.border,
                      borderRadius: BorderRadius.circular(10),
                      border: hasOverride
                          ? Border.all(color: accent.withOpacity(0.4))
                          : null,
                    ),
                    child: Center(child: Icon(tileIcon, color: accent, size: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(statusText, style: TextStyle(
                          color: accent, fontSize: 12,
                          fontWeight: hasOverride ? FontWeight.w600 : FontWeight.normal)),
                      ],
                    ),
                  ),
                  if (onLongPress != null)
                    Icon(Icons.edit_rounded,
                        color: Colors.orange.withOpacity(0.7), size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Admin episode status panel ──────────────────────────────────────────────
class _AdminEpisodePanel extends StatefulWidget {
  final int showId;
  final String showTitle;
  final int season;
  final List<Map<String, dynamic>> gaps;
  final Map<String, String> overrides;
  final ValueChanged<Map<String, String>> onChanged;
  const _AdminEpisodePanel({
    required this.showId, required this.showTitle, required this.season,
    required this.gaps, required this.overrides, required this.onChanged,
  });
  @override
  State<_AdminEpisodePanel> createState() => _AdminEpisodePanelState();
}

class _AdminEpisodePanelState extends State<_AdminEpisodePanel> {
  late Map<String, String> _local;

  @override
  void initState() {
    super.initState();
    _local = Map<String, String>.from(widget.overrides);
  }

  Future<void> _set(int ep, String? status) async {
    await LocalDb.setEpisodeOverride(widget.showId, widget.season, ep, status);
    final key = '${widget.season}_$ep';
    setState(() {
      if (status == null) _local.remove(key);
      else _local[key] = status;
    });
    widget.onChanged(Map<String, String>.from(_local));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: t.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Episode Status', style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('Season ${widget.season} · ${widget.gaps.length} missing',
                        style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.gaps.length,
              itemBuilder: (_, i) {
                final ep = widget.gaps[i];
                final epNum = ep['episode'] as int;
                final padS = widget.season.toString().padLeft(2, '0');
                final padE = epNum.toString().padLeft(2, '0');
                final lbl = ep['label'] as String? ?? 'S${padS}E${padE}';
                final key = '${widget.season}_$epNum';
                final cur = _local[key];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(lbl, style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 14))),
                      const SizedBox(width: 8),
                      _AdminChip(
                        label: 'None', icon: Icons.block_rounded,
                        color: t.textSecondary, selected: cur == null,
                        onTap: () => _set(epNum, null)),
                      const SizedBox(width: 5),
                      _AdminChip(
                        label: 'Soon', icon: Icons.schedule_rounded,
                        color: const Color(0xFFF59E0B),
                        selected: cur == 'coming_soon',
                        onTap: () => _set(epNum, 'coming_soon')),
                      const SizedBox(width: 5),
                      _AdminChip(
                        label: 'Uploading', icon: Icons.cloud_upload_rounded,
                        color: const Color(0xFF3B82F6),
                        selected: cur == 'uploading',
                        onTap: () => _set(epNum, 'uploading')),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear all statuses'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  for (final ep in widget.gaps) {
                    await LocalDb.setEpisodeOverride(
                        widget.showId, widget.season, ep['episode'] as int, null);
                  }
                  final cleared = Map<String, String>.from(_local);
                  for (final ep in widget.gaps) {
                    cleared.remove('${widget.season}_${ep['episode']}');
                  }
                  setState(() => _local = cleared);
                  widget.onChanged(cleared);
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16,
                16 + MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Done'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _AdminChip({required this.label, required this.icon,
      required this.color, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: selected ? color : color.withOpacity(0.5)),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(
              color: selected ? color : color.withOpacity(0.5),
              fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── Coming Soon banner ───────────────────────────────────────────────────────
class _ComingSoonBanner extends StatelessWidget {
  final int? episodeCount;
  final int season;
  const _ComingSoonBanner({this.episodeCount, required this.season});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final hasCount = episodeCount != null && episodeCount! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withOpacity(0.06),
              AppColors.primary.withOpacity(0.02),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: const Center(
                child: Icon(Icons.upcoming_rounded,
                    color: AppColors.primary, size: 30),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Coming Soon',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasCount
                  ? 'Season $season has $episodeCount episode${episodeCount == 1 ? "" : "s"} — '
                    'uploading now. Check back soon!'
                  : 'Episodes for Season $season are on their way. Check back soon!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
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
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: TextStyle(color: t.textSecondary)),
    );
  }
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
      default:          return AppColors.textMuted;
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
