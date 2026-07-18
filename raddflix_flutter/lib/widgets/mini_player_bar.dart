import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/playback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/radd_colors.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import 'resume_fab.dart' show ResumeFab;

/// Persistent "continue watching" bar, docked above the bottom nav bar on
/// every top-level screen (Home / Search / Local / Downloads / Profile).
///
/// UX3-10 — this has two modes:
///  • Live: a [PlaybackService] session is active (the user minimized an
///    in-progress video via the player's minimize control). The bar shows
///    real play/pause + live position/duration and reopens the exact same
///    session — playback never stopped.
///  • Static fallback: no live session (e.g. the app was just relaunched),
///    so it falls back to the original behaviour — reading the `resume_*`
///    SharedPreferences keys PlayerScreen writes on every close, and
///    resuming from that saved position when tapped.
///
/// Drop this in via [MiniPlayerDock], which wraps a screen's existing
/// `RaddFlixBottomNav` so the bar always sits directly above it.
class MiniPlayerBar extends ConsumerStatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  _MiniPlayerData? _staticData;
  bool _staticDismissed = false;
  late AnimationController _anim;
  late Animation<double> _slideIn;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _slideIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _loadStatic();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadStatic() async {
    final p = await SharedPreferences.getInstance();
    final title = p.getString(ResumeFab.kTitle);
    final fileId = p.getString(ResumeFab.kFileId) ?? '';
    final streamUrl = p.getString(ResumeFab.kStreamUrl);
    final localPath = p.getString(ResumeFab.kLocalPath);
    final poster = p.getString(ResumeFab.kPosterUrl);
    final posMs = p.getInt(ResumeFab.kPositionMs) ?? 0;
    final durMs = p.getInt(ResumeFab.kDurationMs) ?? 0;
    final ctype = p.getString(ResumeFab.kContentType) ?? 'movie';
    final isFree = p.getBool(ResumeFab.kIsFree) ?? true;

    if (title == null || title.isEmpty || posMs < 10000) return;
    if (!mounted) return;
    setState(() {
      _staticData = _MiniPlayerData(
        title: title,
        fileId: fileId,
        streamUrl: streamUrl,
        localPath: localPath,
        posterUrl: poster,
        positionMs: posMs,
        durationMs: durMs,
        contentType: ctype,
        isFree: isFree,
      );
    });
    _anim.forward();
  }

  Future<void> _dismissStatic() async {
    if (!mounted) return;
    setState(() => _staticDismissed = true);
    await ResumeFab.clear();
  }

  void _expandStatic() {
    final d = _staticData;
    if (d == null) return;
    // Same subscription gate as ResumeFab — downloaded/local content and
    // free titles always resume; paid streams require an active session.
    if (!d.isFree && (d.localPath == null || d.localPath!.isEmpty)) {
      final auth = ProviderScope.containerOf(context).read(authProvider);
      final subState =
          ProviderScope.containerOf(context).read(subscriptionProvider);
      final isSubscribed = auth.user != null &&
          !(auth.user!.isGuest) &&
          (subState.status != null
              ? subState.status!.isActive
              : auth.user!.hasActiveSubscription);
      if (!isSubscribed) {
        // Don't dismiss the bar — show a dialog so the user understands
        // what's needed and can navigate to subscribe without losing context.
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C2E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: const Text('Subscription Required',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            content: const Text(
                'An active subscription is needed to continue watching '
                'this title.',
                style: TextStyle(color: Colors.white70, height: 1.5)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not Now',
                      style: TextStyle(color: Colors.white38))),
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context)
                        .pushNamed(AppRoutes.subscription);
                  },
                  child: const Text('Subscribe',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700))),
            ],
          ),
        );
        return;
      }
    }
    DebugLogger.logTap('MiniPlayerBar', 'expand_static');
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: {
        'file_id': d.fileId,
        'title': d.title,
        'stream_url': d.streamUrl,
        'local_path': d.localPath,
        'episodes': <Map<String, dynamic>>[],
        'episode_index': 0,
        'content_type': d.contentType,
        'is_free': d.isFree,
      },
    );
  }

  String _fmtDuration(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${sec.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    // Live session takes priority — if the user minimized an in-progress
    // video, that's what the bar should reflect, not stale resume prefs.
    final playbackService = ref.watch(playbackServiceProvider);
    if (playbackService.hasSession) {
      return _LiveMiniPlayerBar(service: playbackService);
    }

    if (_staticDismissed || _staticData == null) return const SizedBox.shrink();
    final d = _staticData!;
    final progress =
        d.durationMs > 0 ? (d.positionMs / d.durationMs).clamp(0.0, 1.0) : 0.0;

    return SizeTransition(
      sizeFactor: _slideIn,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _slideIn,
        child: Dismissible(
          key: ValueKey('mini_player_static_${d.fileId}'),
          direction: DismissDirection.down,
          onDismissed: (_) => _dismissStatic(),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _expandStatic,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              // ── Poster thumbnail ─────────────────────────
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: d.posterUrl != null &&
                                        d.posterUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: d.posterUrl!,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            _posterFallback(),
                                      )
                                    : _posterFallback(),
                              ),
                              const SizedBox(width: 10),
                              // ── Title + resume label ─────────────────────
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Continue from ${_fmtDuration(d.positionMs)}',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // ── Play affordance ──────────────────────────
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                child: Icon(AppIcons.playCircleFill,
                                    color: Colors.white70, size: 28),
                              ),
                              // ── Dismiss ───────────────────────────────────
                              GestureDetector(
                                onTap: _dismissStatic,
                                // UX4-09: 44×44 WCAG-compliant tap target
                                child: SizedBox(
                                  width: 44, height: 44,
                                  child: Center(
                                    child: Icon(AppIcons.close,
                                        size: 16, color: Colors.white38),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // ── Progress line along the bottom edge ──────────
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white12,
                              valueColor:
                                  AlwaysStoppedAnimation(AppColors.primary),
                              minHeight: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _posterFallback() => Container(
        color: const Color(0xFF2C2219),
        child: Center(
          child: Icon(AppIcons.movieFill, color: Colors.white24, size: 24),
        ),
      );
}

/// The "live" mini bar — rendered whenever [PlaybackService] has an active
/// minimized session. Unlike the static fallback above, every value here
/// (title/poster aside) is live: play/pause actually controls the running
/// player, and the progress bar/timestamp tick in real time.
class _LiveMiniPlayerBar extends StatelessWidget {
  final PlaybackService service;
  const _LiveMiniPlayerBar({required this.service});

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${sec.toString().padLeft(2, '0')}s';
  }

  void _expand(BuildContext context) {
    DebugLogger.logTap('MiniPlayerBar', 'expand_live');
    Navigator.of(context)
        .pushNamed(AppRoutes.player, arguments: service.buildResumeArgs());
  }

  // Bug fix: this used to call service.stop() directly — one mistap on a
  // small 16px icon killed a live paid stream outright, with no way back.
  // Every other destructive control in the player (episode skip past
  // unwatched content, exit during an active watch party, etc.) asks first;
  // this one should too.
  Future<void> _confirmStop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Stop Playback?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'This will end your session and close the mini player.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) service.stop();
  }

  @override
  Widget build(BuildContext context) {
    final progress = service.duration.inMilliseconds > 0
        ? (service.position.inMilliseconds / service.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _expand(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        // ── Poster thumbnail ─────────────────────────────
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: service.posterUrl != null &&
                                  service.posterUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: service.posterUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _posterFallback(),
                                )
                              : _posterFallback(),
                        ),
                        const SizedBox(width: 10),
                        // ── Title + live position ────────────────────────
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                service.buffering
                                    ? 'Buffering…'
                                    : '${_fmt(service.position)} / ${_fmt(service.duration)}',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Real play/pause control ──────────────────────
                        GestureDetector(
                          onTap: service.togglePlayPause,
                          // UX4-09: 44×44 WCAG-compliant tap target
                          child: SizedBox(
                            width: 44, height: 44,
                            child: Center(
                              child: Icon(
                                service.playing
                                    ? AppIcons.pause
                                    : AppIcons.play,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                        // ── End session ───────────────────────────────────
                        GestureDetector(
                          onTap: () => _confirmStop(context),
                          // UX4-09: 44×44 WCAG-compliant tap target
                          child: SizedBox(
                            width: 44, height: 44,
                            child: Center(
                              child: Icon(AppIcons.close,
                                  size: 16, color: Colors.white38),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ── Progress line along the bottom edge ──────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                        minHeight: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _posterFallback() => Container(
        color: const Color(0xFF2C2219),
        child: Center(
          child: Icon(AppIcons.movieFill, color: Colors.white24, size: 24),
        ),
      );
}

/// Wraps a screen's bottom nav bar so [MiniPlayerBar] always renders directly
/// above it, in the `bottomNavigationBar` slot. Usage:
///
/// ```dart
/// bottomNavigationBar: MiniPlayerDock(child: RaddFlixBottomNav(...)),
/// ```
class MiniPlayerDock extends StatelessWidget {
  final Widget child;
  const MiniPlayerDock({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayerBar(),
        child,
      ],
    );
  }
}

class _MiniPlayerData {
  final String title;
  final String fileId;
  final String? streamUrl;
  final String? localPath;
  final String? posterUrl;
  final int positionMs;
  final int durationMs;
  final String contentType;
  final bool isFree;

  const _MiniPlayerData({
    required this.title,
    required this.fileId,
    this.streamUrl,
    this.localPath,
    this.posterUrl,
    required this.positionMs,
    required this.durationMs,
    required this.contentType,
    this.isFree = false,
  });
}
