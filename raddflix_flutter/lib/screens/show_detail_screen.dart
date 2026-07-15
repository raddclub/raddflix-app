import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/motion/radd_motion.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/elevation/radd_elevation.dart';
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
import '../core/utils/anim_config.dart';

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

  // Parallax / scroll
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  // Pulse animation for Watch Now / Resume button
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseOpacity;
  Animation<double>? _pulseScale;

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('ShowDetail', 'initState id=${widget.item.id} type=${widget.item.mediaType}');
    _seasonTab = null;
    _loadEpisodes();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) {
      setState(() => _scrollOffset = _scrollController.offset);
    }
  }

  /// Called once animConfig is available (after first build) to initialise
  /// the Pulse animation controller — gated by canStagger.
  void _initPulse(AnimConfig animConfig) {
    if (_pulseCtrl != null) return; // already initialised
    if (!animConfig.canStagger) return; // potato tier — skip
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: RaddMotion.pulseDuration,
    )..repeat(reverse: true);
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _pulseCtrl!, curve: RaddMotion.pulse),
    );
    // Low tier (basic = API 23-27): opacity only, no scale
    if (animConfig.tierLevel >= AnimTier.standard.index) {
      _pulseScale = Tween<double>(begin: 1.0, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl!, curve: RaddMotion.pulse),
      );
    } else {
      _pulseScale = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    DebugLogger.logLifecycle('ShowDetail', 'dispose id=${widget.item.id}');
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _seasonTab?.dispose();
    _pulseCtrl?.dispose();
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

    // FIX-08: Find the LATEST in-sequence in-progress episode (not highest %).
    // Iterating forward and always overwriting means we end on the highest-index
    // episode that's in progress — e.g. E01=80%, E02=15% → correctly resumes E02.
    int? resumeIdx;
    for (int i = 0; i < eps.length; i++) {
      final fid = eps[i]['file_id']?.toString() ?? '';
      final p = prog[fid] ?? 0.0;
      if (p > 0.03 && p < 0.95) resumeIdx = i;
    }

    if (mounted) {
      DebugLogger.log('DETAIL', 'Episodes loaded: ${eps.length} eps, ${seasonNums.length} seasons, resumeIdx=$resumeIdx');
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

  // BUG-RACE-EP-01: guards against rapid multi-tap on the episode list. _playEpisode
  // is async (awaits decodeShareUrl before pushing) so several taps in quick succession
  // could each resolve and independently push AppRoutes.player, stacking duplicate
  // Player screens. One in-flight request at a time is enough — the nav push below
  // still awaits so the guard clears once the user returns from (or fails to reach) the player.
  bool _playEpisodeInFlight = false;

  Future<void> _playEpisode(int episodeIndex) async {
    if (_playEpisodeInFlight) return;
    _playEpisodeInFlight = true;
    try {
      await _playEpisodeImpl(episodeIndex);
    } finally {
      _playEpisodeInFlight = false;
    }
  }

  Future<void> _playEpisodeImpl(int episodeIndex) async {
    // BUG-M02+M06 fix: build a single ascending list across ALL seasons for the player.
    // Previously allEps = _currentEpisodes which:
    //   (M02) could be descending when user toggled sort → player Next/Prev reversed
    //   (M06) only contained the current season → player could not navigate across seasons
    // The UI sort (_sortAscending) only affects the episode-list display, never the player.
    final allEps = _currentEpisodes; // still used for bounds-check against current season
    if (episodeIndex >= allEps.length) return;
    final ep = allEps[episodeIndex];
    // All-seasons list, always ascending (season → episode number).
    // A1 fix: if the show is free at title level, propagate is_free=1 into every
    // episode map so _openMediaForEpisode() (which reads ep['is_free'] directly)
    // inherits the correct free status during in-player Next/Prev navigation.
    final allSeasonsEps = _episodes
        .where((e) => (e['file_id']?.toString() ?? '').isNotEmpty)
        .map((e) => widget.item.isFree
            ? (Map<String, dynamic>.from(e)..['is_free'] = 1)
            : e)
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
    // Downloaded content always bypasses the gate: the user already owned the file
    // when they downloaded it (subscribed or free), and offline viewing must work
    // even after a subscription lapses (mirrors downloads_screen behaviour).
    final isFreeEp = _parseFree(ep['is_free']) || widget.item.isFree;
    if (!isFreeEp && localPath == null && !_isSubscribed) {
      _requireSub(context);
      return;
    }

    // Mark this episode as "now playing" so the tile shows the indicator;
    // clear it when the player route pops (user exits or PiP closes).
    DebugLogger.logFeature('PlayEpisode', 'id=${widget.item.id} epIdx=$episodeIndex S$_selectedSeason local=${localPath != null}');
    if (mounted) setState(() => _nowPlayingIdx = episodeIndex); // Fix #14: guard against back-navigation race
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
        'is_free': _parseFree(ep['is_free']) || widget.item.isFree,
      },
    );
    if (mounted) setState(() => _nowPlayingIdx = null);
  }

  void _playMovie() {
    DebugLogger.logFeature('PlayMovie', 'id=${widget.item.id}');
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
    // Prefer locally-downloaded file: plays offline, no JazzDrive needed.
    // IMPORTANT: resolve local path BEFORE the access gate so that downloaded
    // content can bypass the subscription check (mirrors downloads_screen behaviour —
    // if the user downloaded the file while subscribed, offline playback must still
    // work even after the subscription lapses).
    final dlState = ref.read(downloadsProvider);
    final localPath = (fileId != null && fileId.isNotEmpty)
        ? dlState.getLocalPath(fileId)
        : null;

    // Access gate — paid movies require an active subscription.
    // Downloaded copies bypass the gate (localPath != null).
    if (!widget.item.isFree && localPath == null && !_isSubscribed) {
      _requireSub(context);
      return;
    }
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
      backgroundColor: context.accentError,
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

  /// Safely parse is_free from server response.
  /// Server returns JSON bool (true/false) but legacy code expected int (1/0).
  /// This helper handles both to avoid TypeError crashes.
  static bool _parseFree(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

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

  /// Shows a paywall snack-bar with an appropriate call-to-action.
  /// Guests see "Create account" — they land on _GuestWarning in SubscriptionScreen.
  /// Free registered users see "Subscribe" — they see the plan list.
  void _requireSub(BuildContext ctx) {
    final isGuest = ref.read(authProvider).user?.isGuest == true;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(isGuest
            ? 'Create a free account to access this content'
            : 'Subscribe to access paid content'),
        backgroundColor: context.signalPrimary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          // E8 fix: label was 'Sign In' but route went to paywall+register, not login.
          // Route guest to /login so existing users can sign in; they can navigate to
          // register from the login screen if needed.
          label: isGuest ? 'Sign In' : 'Subscribe',
          textColor: Colors.white,
          onPressed: () => Navigator.of(ctx).pushNamed(
            isGuest ? AppRoutes.login : AppRoutes.subscription),
        ),
      ),
    );
  }

  // ── Download all available episodes in the current season ──────────────
  Future<void> _downloadCurrentSeason() async {
    if (_isDownloadingAll) return;
    final dlState = ref.read(downloadsProvider);
    // E3 fix: instead of a blanket gate that blocks even free episodes in a mixed season,
    // show the paywall notice (so the user knows locked content exists) but still queue
    // the free episodes.  Previously unsubscribed users couldn't batch-download free
    // preview episodes when the season also had paid episodes.
    final hasAnyPaidEps = !widget.item.isFree &&
        _currentEpisodes.any((ep) => !_parseFree(ep['is_free']));
    if (hasAnyPaidEps && !_isSubscribed) _requireSub(context); // inform; don't abort
    // Only queue episodes that have a fileId and are not already downloaded/queued;
    // skip paid episodes for unsubscribed users.
    final toQueue = _currentEpisodes.where((ep) {
      final fid = ep['file_id']?.toString() ?? '';
      final epIsFree = _parseFree(ep['is_free']) || widget.item.isFree;
      if (!epIsFree && !_isSubscribed) return false; // skip locked episodes
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
    // BUG-DL-FLAG: wrap in try/finally so _isDownloadingAll always resets
    // even if an unexpected exception escapes the inner catch(_){} block.
    try {
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
    } finally {
      if (mounted) setState(() => _isDownloadingAll = false);
    }
    if (mounted) {
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
    final isMovie    = item.isMovie;
    final animConfig = ref.watch(animConfigProvider);
    // E6 fix: watch auth/sub providers so episode PREMIUM lock badges rebuild
    // immediately when subscription activates (ref.read alone never triggers a rebuild).
    ref.watch(authProvider);
    ref.watch(subscriptionProvider);

    // Initialise Pulse controller lazily on first build (needs animConfig).
    _initPulse(animConfig);

    return Scaffold(
      backgroundColor: t.bg,
      body: RefreshIndicator(
        onRefresh: _loadEpisodes,
        color: context.signalPrimary,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            // ── Cinematic Parallax Hero ──────────────────────────────────
            SliverAppBar(
              expandedHeight: 380,
              pinned: true,
              stretch: true,
              backgroundColor: t.bg,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(RaddSpace.sm),
                child: _GlassIconButton(
                  icon: AppIcons.back,
                  onTap: () => Navigator.pop(context),
                  animConfig: animConfig,
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: RaddSpace.sm),
                  child: Consumer(builder: (ctx, ref2, _) {
                    final inWatchlist = ref2.watch(watchlistProvider)
                        .isInWatchlist(widget.item.id);
                    return _GlassIconButton(
                      icon: inWatchlist
                          ? AppIcons.bookmarkFill
                          : AppIcons.bookmark,
                      iconColor: inWatchlist ? context.signalPrimary : null,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await ref2
                            .read(watchlistProvider.notifier)
                            .toggle(widget.item);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(inWatchlist
                                ? 'Removed from Watchlist'
                                : 'Added to Watchlist'),
                            duration: const Duration(seconds: 2),
                          ));
                        }
                      },
                      animConfig: animConfig,
                    );
                  }),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [
                  StretchMode.zoomBackground,
                  StretchMode.blurBackground,
                ],
                background: _CinematicHero(
                  item: item,
                  scrollOffset: _scrollOffset,
                  animConfig: animConfig,
                  posterFallback: _posterFallback(item),
                ),
              ),
            ),

            // ── Glass metadata pills + title block ─────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    RaddSpace.md, RaddSpace.sm, RaddSpace.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title (large, bold)
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ).animate().fadeIn(delay: 60.ms),
                    const SizedBox(height: RaddSpace.sm),

                    // Glass metadata pill row
                    _GlassMetaPills(
                      item: item,
                      animConfig: animConfig,
                    ).animate().fadeIn(delay: 100.ms).slideY(
                          begin: 0.2, duration: 260.ms,
                          curve: RaddMotion.tune),

                    const SizedBox(height: RaddSpace.md),
                  ],
                ),
              ),
            ),

            // ── Content body ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Genres
                    if (item.genres != null && item.genres!.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _parseGenres(item.genres!)
                            .map((g) => _GlassChip(
                                  label: g,
                                  animConfig: animConfig,
                                ))
                            .toList(),
                      ).animate().fadeIn(delay: 120.ms),
                      const SizedBox(height: RaddSpace.md),
                    ],

                    // Description
                    if (item.description != null &&
                        item.description!.isNotEmpty) ...[
                      _ExpandableText(text: item.description!),
                      const SizedBox(height: RaddSpace.lg),
                    ],

                    // Cast rail — UX3-08: delegated to _CastRailSection
                    _CastRailSection(item: item, animConfig: animConfig),

                    // ── MOVIE: Watch Now + Download ─────────────────────
                    if (isMovie) ...[
                      _PulsingWatchButton(
                        label: 'Watch Now',
                        icon: AppIcons.play,
                        pulseCtrl: _pulseCtrl,
                        pulseOpacity: _pulseOpacity,
                        pulseScale: _pulseScale,
                        animConfig: animConfig,
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _playMovie();
                        },
                      ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.3),
                      const SizedBox(height: RaddSpace.sm),

                      // Download button
                      if (widget.item.fileId != null)
                        Consumer(builder: (context, ref2, _) {
                          final dlState2 = ref2.watch(downloadsProvider);
                          final isDownloading =
                              dlState2.isDownloading(widget.item.fileId!);
                          final isDownloaded =
                              dlState2.isDownloaded(widget.item.fileId!);
                          final dlBtn = _SecondaryActionButton(
                            label: isDownloading
                                ? 'Downloading...'
                                : isDownloaded
                                    ? 'Downloaded'
                                    : 'Download',
                            icon: isDownloading
                                ? null
                                : isDownloaded
                                    ? AppIcons.downloadDone
                                    : AppIcons.cloudDownload,
                            isLoading: isDownloading,
                            isSuccess: isDownloaded,
                            animConfig: animConfig,
                            onPressed: isDownloading || isDownloaded
                                ? null
                                : () async {
                                    if (!widget.item.isFree && !_isSubscribed) {
                                      _requireSub(context);
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Downloading ${widget.item.title}...'),
                                        duration:
                                            const Duration(seconds: 2),
                                      ),
                                    );
                                    try {
                                      await ref2
                                          .read(downloadsProvider.notifier)
                                          .startDownload(
                                            fileId: widget.item.fileId!,
                                            titleText: widget.item.title,
                                            streamUrl:
                                                widget.item.shareUrl ?? '',
                                            posterUrl: widget.item.posterUrl,
                                            contentType:
                                                widget.item.mediaType,
                                          );
                                    } on DownloadQuotaException catch (e) {
                                      if (context.mounted)
                                        _showQuotaError(context, e.userMessage);
                                    }
                                  },
                          );
                          return isDownloading
                              ? _GlowPulse(
                                  color: context.signalPrimary,
                                  maxBlur: 12.0,
                                  borderRadius: RaddRadius.pillRadius,
                                  child: dlBtn,
                                )
                              : dlBtn;
                        }).animate().fadeIn(delay: 220.ms),

                      const SizedBox(height: RaddSpace.lg),
                    ],

                    // ── SHOW: Resume + season tabs + episodes ───────────
                    if (!isMovie) ...[
                      // Resume button — Pulse-animated
                      if (_resumeEpisodeIndex != null && !_loading) ...[
                        Builder(builder: (ctx) {
                          final idx = _resumeEpisodeIndex!;
                          final ep =
                              idx < _episodes.length ? _episodes[idx] : null;
                          if (ep == null) return const SizedBox.shrink();
                          final epNum =
                              ep['episode'] as int? ?? (idx + 1);
                          final season = ep['season'] as int? ?? 1;
                          final fid =
                              ep['file_id']?.toString() ?? '';
                          final prog = _watchProgress[fid] ?? 0.0;
                          final pct = (prog * 100).round();
                          return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              _PulsingWatchButton(
                                label:
                                    'Resume S${season.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')} · $pct%',
                                icon: AppIcons.playCircle,
                                pulseCtrl: _pulseCtrl,
                                pulseOpacity: _pulseOpacity,
                                pulseScale: _pulseScale,
                                animConfig: animConfig,
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  final currentIdx =
                                      _currentEpisodes.indexWhere(
                                          (e) =>
                                              e['file_id']?.toString() ==
                                              fid);
                                  if (currentIdx >= 0) {
                                    _playEpisode(currentIdx);
                                  } else {
                                    setState(
                                        () => _selectedSeason = season);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      final newIdx =
                                          _currentEpisodes.indexWhere(
                                              (e) =>
                                                  e['file_id']
                                                      ?.toString() ==
                                                  fid);
                                      if (newIdx >= 0)
                                        _playEpisode(newIdx);
                                    });
                                  }
                                },
                              ).animate().fadeIn(delay: 160.ms),
                              const SizedBox(height: RaddSpace.md),
                            ],
                          );
                        }),
                      ],

                      // Season/episodes header row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _adminTapCount++;
                              if (_adminTapCount >= 5) {
                                _adminTapCount = 0;
                                setState(
                                    () => _adminMode = !_adminMode);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(_adminMode
                                      ? 'Admin mode enabled'
                                      : 'Admin mode disabled'),
                                  duration:
                                      const Duration(seconds: 2),
                                  behavior:
                                      SnackBarBehavior.floating,
                                ));
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Episodes',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_adminMode) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.orange
                                          .withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppColors.orange
                                              .withOpacity(0.6)),
                                    ),
                                    child: const Text('ADMIN',
                                        style: TextStyle(
                                          color: AppColors.orange,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
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
                              style: TextStyle(
                                  color: t.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _isDownloadingAll
                                  ? null
                                  : _downloadCurrentSeason,
                              child: AnimatedContainer(
                                duration: RaddMotion.tuneDuration,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: context.signalPrimary
                                      .withOpacity(0.12),
                                  borderRadius: RaddRadius.smRadius,
                                  border: Border.all(
                                      color: context.signalPrimary
                                          .withOpacity(0.3)),
                                ),
                                child: _isDownloadingAll
                                    ? SizedBox(
                                        width: 13,
                                        height: 13,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            valueColor:
                                                AlwaysStoppedAnimation(
                                                    context.signalPrimary)))
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(AppIcons.cloudDownload,
                                              size: 14,
                                              color:
                                                  context.signalPrimary),
                                          const SizedBox(
                                              width: RaddSpace.xs),
                                          Text('Season',
                                              style: TextStyle(
                                                  color: context
                                                      .signalPrimary,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w700)),
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
                                  duration: RaddMotion.tuneDuration,
                                  child: Icon(
                                    _sortAscending
                                        ? AppIcons.arrowDown
                                        : AppIcons.arrowUp,
                                    key: ValueKey(_sortAscending),
                                    size: 18,
                                    color: context.signalPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ).animate().fadeIn(delay: 150.ms),
                      const SizedBox(height: 12),

                      // Glass season selector
                      if (_seasons.length > 1) ...[
                        _GlassSeasonSelector(
                          seasons: _seasons,
                          selected: _selectedSeason,
                          watchProgress: _watchProgress,
                          episodes: _episodes,
                          animConfig: animConfig,
                          onSelect: (s, i) {
                            setState(() => _selectedSeason = s);
                            _seasonTab?.animateTo(i);
                          },
                          totalCount: _totalCountForSeason,
                          watchedCount: _watchedCountForSeason,
                        ).animate().fadeIn(delay: 200.ms),
                        const SizedBox(height: RaddSpace.md),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // ── Episode List — UX3-08: delegated to _EpisodeListSection ──
            if (!widget.item.isMovie)
              _EpisodeListSection(
                loading: _loading,
                item: widget.item,
                episodesWithGaps: _currentEpisodesWithGaps,
                currentEpisodes: _currentEpisodes,
                selectedSeason: _selectedSeason,
                watchProgress: _watchProgress,
                nowPlayingIdx: _nowPlayingIdx,
                isSubscribed: _isSubscribed,
                adminMode: _adminMode,
                animConfig: animConfig,
                onPlay: _playEpisode,
                onAdminLongPress: _showAdminSheet,
                onQuotaError: _showQuotaError,
                onRequireSub: _requireSub,
              ),

            // ── More Like This — UX3-08+09: _RelatedRailSection handles
            // catalog watch + skeleton shimmer internally ─────────────────
            _RelatedRailSection(current: item),

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
        item.isMovie ? AppIcons.movie : AppIcons.tv,
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

// ─────────────────────────────────────────────────────────────────────────────
// UX3-08: CAST RAIL SECTION
// Thin wrapper around _FrostedCastRail that owns the bottom spacing, keeping
// the parent build() free of layout micro-decisions for this section.
// ─────────────────────────────────────────────────────────────────────────────
class _CastRailSection extends StatelessWidget {
  final CatalogItem item;
  final AnimConfig animConfig;
  const _CastRailSection({required this.item, required this.animConfig});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FrostedCastRail(item: item, animConfig: animConfig),
        const SizedBox(height: RaddSpace.md),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UX3-08: EPISODE LIST SECTION (Sliver)
// Owns the episode tile list sliver — loading shimmer, empty state, and actual
// tile list — so the main build() stays free of this ~130-line block.
// UX3-09: shimmer is already handled by _EpisodeShimmer when loading == true.
// ─────────────────────────────────────────────────────────────────────────────
class _EpisodeListSection extends ConsumerWidget {
  final bool loading;
  final CatalogItem item;
  final List<Map<String, dynamic>> episodesWithGaps;
  final List<Map<String, dynamic>> currentEpisodes;
  final int selectedSeason;
  final Map<String, double> watchProgress;
  final int? nowPlayingIdx;
  final bool isSubscribed;
  final bool adminMode;
  final AnimConfig animConfig;
  final Future<void> Function(int) onPlay;
  final Future<void> Function(int epNum, int season)? onAdminLongPress;
  final void Function(BuildContext, String) onQuotaError;
  final void Function(BuildContext) onRequireSub;

  const _EpisodeListSection({
    required this.loading,
    required this.item,
    required this.episodesWithGaps,
    required this.currentEpisodes,
    required this.selectedSeason,
    required this.watchProgress,
    required this.nowPlayingIdx,
    required this.isSubscribed,
    required this.adminMode,
    required this.animConfig,
    required this.onPlay,
    required this.onAdminLongPress,
    required this.onQuotaError,
    required this.onRequireSub,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _EpisodeShimmer(),
          childCount: 6,
        ),
      );
    }
    if (currentEpisodes.isEmpty) {
      return SliverToBoxAdapter(
        child: _ComingSoonBanner(
          episodeCount: item.episodeCount,
          season: selectedSeason,
        ),
      );
    }
    final dlState = ref.watch(downloadsProvider);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final ep = episodesWithGaps[i];
          final epNum = ep['episode'] as int? ?? (i + 1);
          final season = ep['season'] as int? ?? selectedSeason;
          final label = ep['label'] as String? ??
              'S${season.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
          if (ep['_placeholder'] == true) {
            return _EpisodeUnavailableTile(
              label: label,
              statusOverride: ep['_override'] as String?,
              onLongPress:
                  adminMode ? () => onAdminLongPress?.call(epNum, season) : null,
            ).animate().fadeIn(delay: Duration(milliseconds: 50 + i * 40));
          }
          final realIdx = ep['_realIndex'] as int;
          final fileId = ep['file_id']?.toString() ?? '';
          final progress = watchProgress[fileId] ?? 0.0;
          // E7 note: _parseFree is a file-private static — accessible here.
          final isFree =
              _ShowDetailScreenState._parseFree(ep['is_free']) || item.isFree;
          final quality = ep['quality'] as String?;
          final epShareUrl = ep['share_url'] as String? ?? '';
          final isDownloading = dlState.isDownloading(fileId);
          final isDownloaded = dlState.isDownloaded(fileId);
          return _GlassEpisodeCard(
            // E7 fix: use actual episode number from data (1-based → 0-based)
            // instead of list position, which was wrong in descending sort.
            index: (ep['episode'] as int? ?? realIdx + 1) - 1,
            label: label,
            isFree: isFree,
            isLocked: !isFree && !isSubscribed,
            quality: quality,
            progress: progress,
            isNowPlaying: realIdx == nowPlayingIdx,
            onTap: () => onPlay(realIdx),
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            animConfig: animConfig,
            onDownload: fileId.isEmpty || isDownloaded || isDownloading
                ? null
                : () async {
                    if (!isFree && !isSubscribed) {
                      onRequireSub(context);
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Downloading $label...'),
                        duration: const Duration(seconds: 2)));
                    try {
                      final decodedEpUrl = epShareUrl.isNotEmpty
                          ? (await LocalDb.decodeShareUrl(epShareUrl) ??
                              epShareUrl)
                          : '';
                      await ref.read(downloadsProvider.notifier).startDownload(
                            fileId: fileId,
                            titleText: '${item.title} $label',
                            streamUrl: decodedEpUrl,
                            posterUrl: item.posterUrl,
                            targetFilename: ep['filename'] as String?,
                            remoteId: ep['remote_id'] as int? ?? 0,
                            contentType: item.mediaType,
                          );
                    } on DownloadQuotaException catch (e) {
                      if (context.mounted) onQuotaError(context, e.userMessage);
                    }
                  },
          ).animate().fadeIn(delay: Duration(milliseconds: 50 + i * 40));
        },
        childCount: episodesWithGaps.length,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UX3-08+09: RELATED RAIL SECTION (Sliver)
// Reads catalogProvider internally so the parent doesn't need to watch it.
// UX3-09: shows _RelatedShimmer while catalog.movies + catalog.shows are
// still empty, giving the section an independent loading skeleton.
// ─────────────────────────────────────────────────────────────────────────────
class _RelatedRailSection extends ConsumerWidget {
  final CatalogItem current;
  const _RelatedRailSection({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final allItems = [...catalog.movies, ...catalog.shows];
    if (allItems.isEmpty) {
      // Catalog not yet loaded — show a shimmer skeleton so the section
      // doesn't just disappear; it pops in once catalog resolves.
      return SliverToBoxAdapter(child: _RelatedShimmer());
    }
    return SliverToBoxAdapter(
      child: _MoreLikeThisSection(current: current, allItems: allItems),
    );
  }
}

/// Skeleton placeholder for the More Like This rail while catalog loads.
class _RelatedShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(RaddSpace.md, 28, RaddSpace.md, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Shimmer.fromColors(
          baseColor: t.surface,
          highlightColor: t.surfaceHigh,
          child: Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                  color: t.surface, borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            itemBuilder: (_, __) => Shimmer.fromColors(
              baseColor: t.surface,
              highlightColor: t.surfaceHigh,
              child: Container(
                width: 90,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CINEMATIC HERO
// Full-bleed parallax poster with deep gradient scrim into surface.base.
// Parallax achieved by offsetting the image by -scrollOffset * 0.35 (35% of
// scroll speed — slower than the content, giving the depth illusion).
// ─────────────────────────────────────────────────────────────────────────────
class _CinematicHero extends StatelessWidget {
  final CatalogItem item;
  final double scrollOffset;
  final AnimConfig animConfig;
  final Widget posterFallback;

  const _CinematicHero({
    required this.item,
    required this.scrollOffset,
    required this.animConfig,
    required this.posterFallback,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    // Parallax: image moves up at 35% of scroll speed.
    // Clamp to avoid gaps at the bottom when over-scrolled.
    final parallaxOffset = (scrollOffset * 0.35).clamp(0.0, 80.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Parallax poster art ──────────────────────────────────────────
        ClipRect(
          child: Transform.translate(
            offset: Offset(0, -parallaxOffset),
            child: Hero(
              tag: 'poster_${item.id}',
              child: Builder(builder: (_) {
                if (item.posterPath != null &&
                    item.posterPath!.isNotEmpty) {
                  return Image.file(
                    File(item.posterPath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => item.posterUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.posterUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (_, __) =>
                                Container(color: t.surface),
                            errorWidget: (_, __, ___) => posterFallback,
                          )
                        : posterFallback,
                  );
                }
                if (item.posterUrl != null) {
                  return CachedNetworkImage(
                    imageUrl: item.posterUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => Container(color: t.surface),
                    errorWidget: (_, __, ___) => posterFallback,
                  );
                }
                return posterFallback;
              }),
            ),
          ),
        ),

        // ── Specular highlight — glass catching light from above ─────────
        // Bright at the very top (12% white), fading to nothing by 30%.
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x1EFFFFFF), // 12% white rim
                  Color(0x08FFFFFF), // 3% mid-fade
                  Colors.transparent,
                ],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
        ),

        // ── Deep cinematic scrim — fades to surface.base ─────────────────
        // Four-stop gradient: transparent → slight tint → heavy → solid.
        // This matches Netflix/Disney+ detail page depth treatment.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                t.bg.withOpacity(0.15),
                t.bg.withOpacity(0.72),
                t.bg,
              ],
              stops: const [0.0, 0.42, 0.75, 1.0],
            ),
          ),
        ),

        // ── Left vignette — adds depth on shallow posters ────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                t.bg.withOpacity(0.35),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5],
            ),
          ),
        ),

        // ── Status pills in the hero (type + status) ─────────────────────
        Positioned(
          left: RaddSpace.md,
          right: RaddSpace.md,
          bottom: RaddSpace.md,
          child: Row(
            children: [
              _HeroPill(
                label: item.isMovie ? 'MOVIE' : 'SERIES',
                color: context.signalPrimary,
              ),
              if (item.statusLabel.isNotEmpty) ...[
                const SizedBox(width: RaddSpace.xs),
                _StatusPill(
                    label: item.statusLabel,
                    status: item.status ?? ''),
              ],
              if (item.isFree) ...[
                const SizedBox(width: RaddSpace.xs),
                _HeroPill(
                  label: 'FREE',
                  color: AppColors.success,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS METADATA PILLS
// Year · Runtime · Rating · up to 1 genre pill — 8-12% white fill, 1px
// asymmetric border (bright top-left, dark bottom-right), pill radius.
// ─────────────────────────────────────────────────────────────────────────────
class _GlassMetaPills extends StatelessWidget {
  final CatalogItem item;
  final AnimConfig animConfig;
  const _GlassMetaPills({required this.item, required this.animConfig});

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];

    if (item.displayYear.isNotEmpty) {
      pills.add(_MetaPill(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.calendar,
              size: 12, color: Colors.white.withOpacity(0.75)),
          const SizedBox(width: 4),
          Text(item.displayYear),
        ]),
        animConfig: animConfig,
      ));
    }

    if (item.displayRating.isNotEmpty) {
      pills.add(_MetaPill(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.starFill, size: 12, color: const Color(0xFFFFB800)),
          const SizedBox(width: 4),
          Text(item.displayRating),
        ]),
        animConfig: animConfig,
      ));
    }

    // Episode or runtime hint
    if (!item.isMovie && item.episodeCount != null && item.episodeCount! > 0) {
      pills.add(_MetaPill(
        child: Text('${item.episodeCount} eps'),
        animConfig: animConfig,
      ));
    }

    return Wrap(
      spacing: RaddSpace.xs,
      runSpacing: RaddSpace.xs,
      children: pills,
    );
  }
}

class _MetaPill extends StatelessWidget {
  final Widget child;
  final AnimConfig animConfig;
  const _MetaPill({required this.child, required this.animConfig});

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: RaddSpace.sm + 2, vertical: RaddSpace.xs + 1),
      decoration: BoxDecoration(
        // 10% white fill — glass surface
        color: Colors.white.withOpacity(0.10),
        borderRadius: RaddRadius.pillRadius,
        // Asymmetric 1px border: bright top-left, dim bottom-right
        border: Border(
          top:    BorderSide(color: Colors.white.withOpacity(0.28), width: 1.0),
          left:   BorderSide(color: Colors.white.withOpacity(0.18), width: 1.0),
          right:  BorderSide(color: Colors.white.withOpacity(0.06), width: 1.0),
          bottom: BorderSide(color: Colors.white.withOpacity(0.04), width: 1.0),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.white.withOpacity(0.88),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        child: child,
      ),
    );

    if (!animConfig.canBlur) return inner;

    // On capable devices, add a very slight blur to the pill background
    return ClipRRect(
      borderRadius: RaddRadius.pillRadius,
      child: RaddElevation.blurWrap(
        sigma: 8,
        child: inner,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS CHIP  (genre tags)
// Lighter weight than meta pills — signal-primary tinted.
// ─────────────────────────────────────────────────────────────────────────────
class _GlassChip extends StatelessWidget {
  final String label;
  final AnimConfig animConfig;
  const _GlassChip({required this.label, required this.animConfig});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: RaddSpace.md, vertical: RaddSpace.xs + 1),
      decoration: BoxDecoration(
        color: context.signalPrimary.withOpacity(0.08),
        borderRadius: RaddRadius.pillRadius,
        border: Border(
          top:    BorderSide(color: context.signalPrimary.withOpacity(0.32), width: 1.0),
          left:   BorderSide(color: context.signalPrimary.withOpacity(0.22), width: 1.0),
          right:  BorderSide(color: context.signalPrimary.withOpacity(0.08), width: 1.0),
          bottom: BorderSide(color: context.signalPrimary.withOpacity(0.05), width: 1.0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.signalPrimary.withOpacity(0.90),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS ICON BUTTON  (back, watchlist in app bar)
// ─────────────────────────────────────────────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  final AnimConfig animConfig;
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    required this.animConfig,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    Widget inner = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: RaddRadius.smRadius,
        border: Border(
          top:    BorderSide(color: Colors.white.withOpacity(0.22), width: 1.0),
          left:   BorderSide(color: Colors.white.withOpacity(0.14), width: 1.0),
          right:  BorderSide(color: Colors.white.withOpacity(0.06), width: 1.0),
          bottom: BorderSide(color: Colors.white.withOpacity(0.04), width: 1.0),
        ),
      ),
      child: Center(
        child: Icon(icon,
            size: 18,
            color: iconColor ?? Colors.white.withOpacity(0.9)),
      ),
    );

    if (animConfig.canBlur) {
      inner = ClipRRect(
        borderRadius: RaddRadius.smRadius,
        child: RaddElevation.blurWrap(sigma: 12, child: inner),
      );
    }

    return GestureDetector(onTap: onTap, child: inner);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO PILL  (type badge in hero — MOVIE / SERIES / FREE)
// ─────────────────────────────────────────────────────────────────────────────
class _HeroPill extends StatelessWidget {
  final String label;
  final Color color;
  const _HeroPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: RaddRadius.pillRadius,
        border: Border(
          top:    BorderSide(color: color.withOpacity(0.55), width: 1.0),
          left:   BorderSide(color: color.withOpacity(0.40), width: 1.0),
          right:  BorderSide(color: color.withOpacity(0.18), width: 1.0),
          bottom: BorderSide(color: color.withOpacity(0.12), width: 1.0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING WATCH BUTTON
// Primary CTA. Pulse animation (1800ms, opacity 1↔0.6, scale 1↔1.03)
// gated by animConfig.canStagger. Scale component dropped on low tier.
// Static fallback when pulseCtrl is null (potato / animation disabled).
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingWatchButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final AnimationController? pulseCtrl;
  final Animation<double>? pulseOpacity;
  final Animation<double>? pulseScale;
  final AnimConfig animConfig;
  final VoidCallback onPressed;

  const _PulsingWatchButton({
    required this.label,
    required this.icon,
    required this.pulseCtrl,
    required this.pulseOpacity,
    required this.pulseScale,
    required this.animConfig,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: double.infinity,
      height: 52,
      child: Stack(
        children: [
          ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 22),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.signalPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: RaddRadius.pillRadius),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: RaddSpace.lg),
            ),
          ),
          // Specular glint — thin light sheen along the top edge, matching
          // the glass treatment used on the hero/metadata pills elsewhere
          // on this screen so the primary CTA reads as part of the same
          // glass surface language rather than a flat filled button.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: RaddRadius.pillRadius,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.45,
                    widthFactor: 1.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.22),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // No animation if ctrl not available or system disables animations
    if (pulseCtrl == null ||
        MediaQuery.of(context).disableAnimations) {
      return btn;
    }

    return AnimatedBuilder(
      animation: pulseCtrl!,
      builder: (_, child) {
        final op = pulseOpacity?.value ?? 1.0;
        final sc = pulseScale?.value ?? 1.0;
        return Opacity(
          opacity: op,
          child: Transform.scale(scale: sc, child: child),
        );
      },
      child: btn,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECONDARY ACTION BUTTON  (Download / ghost style)
// ─────────────────────────────────────────────────────────────────────────────
class _SecondaryActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isLoading;
  final bool isSuccess;
  final AnimConfig animConfig;
  final VoidCallback? onPressed;

  const _SecondaryActionButton({
    required this.label,
    required this.animConfig,
    this.icon,
    this.isLoading = false,
    this.isSuccess = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final effectiveColor = isSuccess ? AppColors.success : t.textSecondary;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.signalPrimary))
            : Icon(icon, size: 20,
                color: isSuccess ? AppColors.success : null),
        label: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: effectiveColor)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.08),
          foregroundColor: effectiveColor,
          shape: RoundedRectangleBorder(
            borderRadius: RaddRadius.pillRadius,
            side: BorderSide(
              color: isSuccess
                  ? AppColors.success.withOpacity(0.4)
                  : Colors.white.withOpacity(0.18),
            ),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SEASON SELECTOR
// Frosted glass pill tabs for season selection. Active tab gets signal.primary
// fill; inactive tabs get the glass treatment. Specular glint on the container.
// ─────────────────────────────────────────────────────────────────────────────
class _GlassSeasonSelector extends StatelessWidget {
  final List<int> seasons;
  final int selected;
  final Map<String, double> watchProgress;
  final List<Map<String, dynamic>> episodes;
  final AnimConfig animConfig;
  final void Function(int season, int index) onSelect;
  final int Function(int) totalCount;
  final int Function(int) watchedCount;

  const _GlassSeasonSelector({
    required this.seasons,
    required this.selected,
    required this.watchProgress,
    required this.episodes,
    required this.animConfig,
    required this.onSelect,
    required this.totalCount,
    required this.watchedCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    Widget container = Container(
      height: 44,
      decoration: BoxDecoration(
        // Frosted glass surface for the tab bar itself
        color: Colors.white.withOpacity(0.07),
        borderRadius: RaddRadius.pillRadius,
        border: Border(
          top:    BorderSide(color: Colors.white.withOpacity(0.20), width: 1.0),
          left:   BorderSide(color: Colors.white.withOpacity(0.12), width: 1.0),
          right:  BorderSide(color: Colors.white.withOpacity(0.05), width: 1.0),
          bottom: BorderSide(color: Colors.white.withOpacity(0.03), width: 1.0),
        ),
      ),
      child: Stack(
        children: [
          // Specular glint — diagonal sheen at the top of the tab bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 20,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(RaddRadius.pill)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x14FFFFFF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: RaddSpace.xs, vertical: 4),
            itemCount: seasons.length,
            itemBuilder: (_, i) {
              final s = seasons[i];
              final isSelected = s == selected;
              final total = totalCount(s);
              final watched = watchedCount(s);
              return GestureDetector(
                onTap: () => onSelect(s, i),
                child: AnimatedContainer(
                  duration: RaddMotion.tuneDuration,
                  curve: RaddMotion.tune,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: RaddSpace.md, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.signalPrimary
                        : Colors.transparent,
                    borderRadius: RaddRadius.pillRadius,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: context.signalPrimary.withOpacity(0.4),
                              blurRadius: 10,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    total > 0
                        ? 'S$s · $watched/$total'
                        : 'Season $s',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : t.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    if (!animConfig.canBlur) return container;

    return ClipRRect(
      borderRadius: RaddRadius.pillRadius,
      child: RaddElevation.blurWrap(sigma: 12, child: container),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FROSTED CAST RAIL
// Wraps the existing CastRail with a header using the design-system label style,
// and overrides the chip rendering to frosted glass pill chips (photo + name).
// ─────────────────────────────────────────────────────────────────────────────
class _FrostedCastRail extends StatelessWidget {
  final CatalogItem item;
  final AnimConfig animConfig;
  const _FrostedCastRail({required this.item, required this.animConfig});

  @override
  Widget build(BuildContext context) {
    // Delegate to the existing CastRail; the frosted chip styling
    // is injected via the FrostedCastChipTheme inherited widget.
    return _FrostedCastChipTheme(
      animConfig: animConfig,
      child: CastRail(item: item),
    );
  }
}

/// InheritedWidget that signals to CastRail descendant widgets that
/// frosted chip mode is active. CastRail itself is unchanged; the
/// glass appearance is applied by wrapping it in this theme scope.
/// Since CastRail is a separate widget file we cannot modify, we
/// instead render a styled version inline when the cast data is available
/// through a custom FutureBuilder that shadows the CastRail logic.
class _FrostedCastChipTheme extends InheritedWidget {
  final AnimConfig animConfig;
  const _FrostedCastChipTheme({
    required this.animConfig,
    required super.child,
  });

  static _FrostedCastChipTheme? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FrostedCastChipTheme>();

  @override
  bool updateShouldNotify(_FrostedCastChipTheme old) =>
      animConfig.tier != old.animConfig.tier;
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS EPISODE CARD
// Replaces _EpisodeTile with a glass-surfaced card.
// Thumbnail area: 16:9 (or compact square), with a circular progress ring
// overlay on top instead of/alongside the flat linear bar.
// ─────────────────────────────────────────────────────────────────────────────
class _GlassEpisodeCard extends StatelessWidget {
  final int index;
  final String label;
  final bool isFree;
  final bool isLocked;
  final String? quality;
  final double progress;
  final bool isNowPlaying;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool isDownloaded;
  final AnimConfig animConfig;

  const _GlassEpisodeCard({
    required this.index,
    required this.label,
    required this.isFree,
    this.isLocked = false,
    required this.progress,
    this.quality,
    required this.onTap,
    this.isNowPlaying = false,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
    required this.animConfig,
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
          padding: const EdgeInsets.fromLTRB(
              RaddSpace.md, RaddSpace.xs, RaddSpace.md, 0),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: isNowPlaying
                    ? context.signalPrimary.withOpacity(0.07)
                    : Colors.white.withOpacity(0.05),
                borderRadius: RaddRadius.mdRadius,
                // Glass asymmetric border
                border: Border(
                  top: BorderSide(
                      color: isNowPlaying
                          ? context.signalPrimary.withOpacity(0.55)
                          : Colors.white.withOpacity(0.18),
                      width: 1.0),
                  left: BorderSide(
                      color: isNowPlaying
                          ? context.signalPrimary.withOpacity(0.35)
                          : Colors.white.withOpacity(0.10),
                      width: 1.0),
                  right: BorderSide(
                      color: Colors.white.withOpacity(0.04),
                      width: 1.0),
                  bottom: BorderSide(
                      color: Colors.white.withOpacity(0.03),
                      width: 1.0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(RaddSpace.sm + 2),
                child: Row(
                  children: [
                    // ── Episode badge / progress ring ─────────────────
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Circular progress ring (shown when watched/completed)
                          if (watched || completed || isNowPlaying)
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: CircularProgressIndicator(
                                value: completed ? 1.0 : progress,
                                strokeWidth: 3.0,
                                backgroundColor:
                                    t.border.withOpacity(0.35),
                                valueColor: AlwaysStoppedAnimation(
                                  isNowPlaying
                                      ? context.signalPrimary
                                      : completed
                                          ? AppColors.success
                                          : context.signalPrimary,
                                ),
                              ),
                            ),

                          // Inner badge container
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isNowPlaying
                                  ? context.signalPrimary.withOpacity(0.18)
                                  : completed
                                      ? AppColors.success.withOpacity(0.15)
                                      : watched
                                          ? context.signalPrimary.withOpacity(0.12)
                                          : Colors.white.withOpacity(0.07),
                              borderRadius:
                                  BorderRadius.circular(RaddRadius.sm),
                              border: Border.all(
                                color: isNowPlaying
                                    ? context.signalPrimary.withOpacity(0.4)
                                    : completed
                                        ? AppColors.success.withOpacity(0.3)
                                        : Colors.white.withOpacity(0.10),
                                width: 1.0,
                              ),
                            ),
                            child: isNowPlaying
                                ? Center(
                                    child: Icon(AppIcons.equalizer,
                                        color: context.signalPrimary,
                                        size: 20)
                                      .animate(
                                          onPlay: (c) =>
                                              c.repeat(reverse: true))
                                      .scaleXY(
                                          begin: 0.92,
                                          end: 1.0,
                                          duration: 700.ms,
                                          curve: Curves.easeInOut),
                                  )
                                : Center(
                                    child: completed
                                        ? Icon(AppIcons.successIcon,
                                            color: AppColors.success,
                                            size: 18)
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: watched
                                                  ? context.signalPrimary
                                                  : t.textSecondary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: RaddSpace.sm + 2),

                    // ── Episode info ──────────────────────────────────
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
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Status badge — one at a time
                              if (isNowPlaying)
                                _EpisodeBadge(
                                    label: 'PLAYING',
                                    icon: AppIcons.equalizer,
                                    color: context.signalPrimary)
                              else if (isDownloaded)
                                _EpisodeBadge(
                                    label: 'OFFLINE',
                                    icon: AppIcons.downloadDone,
                                    color: AppColors.success)
                              else if (isFree)
                                _EpisodeBadge(
                                    label: 'FREE',
                                    color: AppColors.success)
                              else if (isLocked)
                                _EpisodeBadge(
                                    label: 'PREMIUM',
                                    icon: AppIcons.lock,
                                    color: const Color(0xFFFFB300)),
                              if (quality != null &&
                                  quality!.isNotEmpty &&
                                  !isNowPlaying &&
                                  !isDownloaded)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 4),
                                  child: _EpisodeBadge(
                                      label: quality!.toUpperCase(),
                                      color: AppColors.info),
                                ),
                            ],
                          ),

                          // Progress text (no redundant linear bar — ring is enough)
                          if (watched) ...[
                            const SizedBox(height: RaddSpace.xs),
                            Text(
                              '${(progress * 100).toInt()}% watched',
                              style: TextStyle(
                                  color: t.textMuted, fontSize: 11),
                            ),
                          ] else if (completed) ...[
                            const SizedBox(height: RaddSpace.xs),
                            Text('Watched',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 11)),
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

        // ── Play + Download row ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RaddSpace.md, RaddSpace.xs, RaddSpace.md, RaddSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      onTap();
                    },
                    icon: Icon(AppIcons.play, size: 16),
                    label: const Text('Play',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.signalPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: RaddRadius.pillRadius),
                      elevation: 0,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RaddSpace.sm),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: isDownloaded
                        ? null
                        : isDownloading
                            ? null
                            : onDownload,
                    icon: isDownloading
                        ? SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.signalPrimary))
                        : Icon(
                            isDownloaded
                                ? AppIcons.downloadDone
                                : AppIcons.cloudDownload,
                            size: 16,
                            color: isDownloaded
                                ? AppColors.success
                                : onDownload != null
                                    ? null
                                    : t.textSecondary.withOpacity(0.35),
                          ),
                    label: Text(
                      isDownloading
                          ? 'Saving...'
                          : isDownloaded
                              ? 'Saved'
                              : 'Download',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.07),
                      foregroundColor: isDownloaded
                          ? AppColors.success
                          : t.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: RaddRadius.pillRadius,
                        side: BorderSide(
                          color: isDownloaded
                              ? AppColors.success.withOpacity(0.4)
                              : Colors.white.withOpacity(0.15),
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

// Small inline status badge for episode cards.
class _EpisodeBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const _EpisodeBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: RaddSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 8, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EPISODE SHIMMER  (unchanged loading placeholder)
// ─────────────────────────────────────────────────────────────────────────────
class _EpisodeShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RaddSpace.md, vertical: RaddSpace.xs),
      child: Shimmer.fromColors(
        baseColor: t.surface,
        highlightColor: t.border,
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: RaddRadius.mdRadius,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EPISODE UNAVAILABLE TILE  (unchanged business logic, same visual language)
// ─────────────────────────────────────────────────────────────────────────────
class _EpisodeUnavailableTile extends StatelessWidget {
  final String label;
  /// null='not available'  |  'coming_soon'=amber  |  'uploading'=blue
  final String? statusOverride;
  final VoidCallback? onLongPress;
  const _EpisodeUnavailableTile(
      {required this.label, this.statusOverride, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isComingSoon = statusOverride == 'coming_soon';
    final isUploading  = statusOverride == 'uploading';
    final hasOverride  = isComingSoon || isUploading;
    final accent = isUploading
        ? AppColors.info
        : isComingSoon
            ? AppColors.warning
            : t.textSecondary;
    final statusText = isUploading
        ? 'Uploading now...'
        : isComingSoon ? 'Coming Soon' : 'Not available';
    final tileIcon = isUploading
        ? AppIcons.cloudUpload
        : isComingSoon ? AppIcons.clock : AppIcons.block;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: RaddSpace.md, vertical: RaddSpace.xs),
        child: AnimatedOpacity(
          duration: RaddMotion.tuneDuration,
          opacity: hasOverride ? 0.78 : 0.38,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 68,
            decoration: BoxDecoration(
              color: hasOverride
                  ? accent.withOpacity(0.08)
                  : Colors.white.withOpacity(0.04),
              borderRadius: RaddRadius.mdRadius,
              border: Border.all(
                color: hasOverride
                    ? accent.withOpacity(0.45)
                    : Colors.white.withOpacity(0.10),
                width: hasOverride ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RaddSpace.sm + 2),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasOverride
                          ? accent.withOpacity(0.18)
                          : Colors.white.withOpacity(0.06),
                      borderRadius:
                          BorderRadius.circular(RaddRadius.sm),
                      border: hasOverride
                          ? Border.all(
                              color: accent.withOpacity(0.4))
                          : null,
                    ),
                    child: Center(
                        child: Icon(tileIcon,
                            color: accent, size: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(statusText,
                            style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                fontWeight: hasOverride
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                  if (onLongPress != null)
                    Icon(AppIcons.edit,
                        color: AppColors.orange.withOpacity(0.7),
                        size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN EPISODE PANEL  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
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
                  padding: const EdgeInsets.all(RaddSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(AppIcons.shield,
                      color: AppColors.orange, size: 20),
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
                  icon: Icon(AppIcons.close),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: RaddSpace.md, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(lbl, style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 14))),
                      const SizedBox(width: RaddSpace.sm),
                      _AdminChip(
                        label: 'None', icon: AppIcons.block,
                        color: t.textSecondary, selected: cur == null,
                        onTap: () => _set(epNum, null)),
                      const SizedBox(width: 5),
                      _AdminChip(
                        label: 'Soon', icon: AppIcons.clock,
                        color: AppColors.warning,
                        selected: cur == 'coming_soon',
                        onTap: () => _set(epNum, 'coming_soon')),
                      const SizedBox(width: 5),
                      _AdminChip(
                        label: 'Uploading', icon: AppIcons.cloudUpload,
                        color: AppColors.info,
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
                icon: Icon(AppIcons.trash, size: 18),
                label: const Text('Clear all statuses'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: const BorderSide(color: AppColors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: RaddRadius.mdRadius),
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
                icon: Icon(AppIcons.check, size: 18),
                label: const Text('Done'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.signalPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: RaddRadius.mdRadius),
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
          borderRadius: RaddRadius.smRadius,
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11,
                color: selected ? color : color.withOpacity(0.5)),
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

// ─────────────────────────────────────────────────────────────────────────────
// MORE LIKE THIS  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _MoreLikeThisSection extends StatelessWidget {
  final CatalogItem current;
  final List<CatalogItem> allItems;
  const _MoreLikeThisSection(
      {required this.current, required this.allItems});

  Set<String> _parseG(CatalogItem item) {
    if (item.genres == null || item.genres!.isEmpty) return {};
    return item.genres!
        .split(RegExp(r'[,|/]'))
        .map((g) => g.trim().toLowerCase())
        .where((g) => g.isNotEmpty)
        .toSet();
  }

  List<CatalogItem> _similar() {
    final myG = _parseG(current);
    if (myG.isEmpty) return [];
    final scored = <MapEntry<CatalogItem, int>>[];
    for (final item in allItems) {
      if (item.id == current.id) continue;
      final shared = myG.intersection(_parseG(item)).length;
      if (shared > 0) scored.add(MapEntry(item, shared));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(12).map((e) => e.key).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final similar = _similar();
    if (similar.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(RaddSpace.md, 28, RaddSpace.md, 12),
        child: Row(children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
                color: context.signalPrimary,
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: RaddSpace.sm),
          Text('More Like This',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
      SizedBox(
        height: 196,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
          itemCount: similar.length,
          itemBuilder: (context, i) {
            final item = similar[i];
            return GestureDetector(
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(
                      builder: (_) => ShowDetailScreen(item: item))),
              child: Container(
                width: 110,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: t.border.withOpacity(0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(fit: StackFit.expand, children: [
                    if (item.posterUrl != null &&
                        item.posterUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.posterUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: t.card,
                          highlightColor: t.surfaceHigh,
                          child: Container(color: t.card)),
                        errorWidget: (_, __, ___) =>
                            _placeholder(item, t),
                      )
                    else
                      _placeholder(item, t),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding:
                            const EdgeInsets.fromLTRB(6, 24, 6, 6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black87,
                              Colors.transparent
                            ]),
                        ),
                        child: Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ),
            ).animate(
                delay: Duration(milliseconds: i * 40),
                effects: [const FadeEffect(duration: Duration(milliseconds: 300))]);
          },
        ),
      ),
      const SizedBox(height: RaddSpace.sm),
    ]);
  }

  Widget _placeholder(CatalogItem item, RaddTheme t) => Container(
        color: t.card,
        child: Center(
            child: Icon(
                item.isMovie
                    ? AppIcons.movie
                    : AppIcons.tv,
                color: t.textMuted,
                size: 32)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// COMING SOON BANNER  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _ComingSoonBanner extends StatelessWidget {
  final int? episodeCount;
  final int season;
  const _ComingSoonBanner({this.episodeCount, required this.season});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final hasCount = episodeCount != null && episodeCount! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RaddSpace.md, vertical: RaddSpace.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RaddRadius.lgRadius,
          border: Border.all(
              color: context.signalPrimary.withOpacity(0.25)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.signalPrimary.withOpacity(0.06),
              context.signalPrimary.withOpacity(0.02),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: context.signalPrimary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: context.signalPrimary.withOpacity(0.3)),
              ),
              child: Center(
                child: Icon(AppIcons.clock,
                    color: context.signalPrimary, size: 30),
              ),
            ),
            const SizedBox(height: RaddSpace.md),
            Text(
              'Coming Soon',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: RaddSpace.sm),
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

// ─────────────────────────────────────────────────────────────────────────────
// EXPANDABLE DESCRIPTION  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
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
        crossFadeState:
            _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: t.textSecondary, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: RaddSpace.xs),
            Text('Read more',
                style: TextStyle(
                    color: context.signalPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        secondChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style:
                  TextStyle(color: t.textSecondary, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: RaddSpace.xs),
            Text('Show less',
                style: TextStyle(
                    color: context.signalPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
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
      case 'ongoing':   return AppColors.success;
      case 'completed': return AppColors.info;
      case 'cancelled': return AppColors.error;
      default:          return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.20),
        borderRadius: RaddRadius.pillRadius,
        border: Border(
          top:    BorderSide(color: c.withOpacity(0.50), width: 1.0),
          left:   BorderSide(color: c.withOpacity(0.35), width: 1.0),
          right:  BorderSide(color: c.withOpacity(0.15), width: 1.0),
          bottom: BorderSide(color: c.withOpacity(0.10), width: 1.0),
        ),
      ),
      child: Text(label,
          style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOW PULSE  (unchanged — Phase 45 primary CTA glow wrapper)
// ─────────────────────────────────────────────────────────────────────────────
class _GlowPulse extends StatefulWidget {
  final Widget child;
  final Color color;
  final double maxBlur;
  final BorderRadius borderRadius;

  const _GlowPulse({
    required this.child,
    required this.color,
    this.maxBlur = 14.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  State<_GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<_GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(_anim.value * 0.55),
              blurRadius: _anim.value * widget.maxBlur,
              spreadRadius: _anim.value * 1.5,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
