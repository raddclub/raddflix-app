import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/radd_colors.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import 'resume_fab.dart' show ResumeFab;

/// Persistent "continue watching" bar, docked above the bottom nav bar on
/// every top-level screen (Home / Search / Local / Downloads / Profile).
///
/// This is the premium miniplayer upgrade requested in place of the old
/// floating [ResumeFab]: instead of a small card that only appeared on the
/// Home tab, this bar is anchored above the nav bar everywhere, can be
/// swiped down to dismiss, and taps through to resume playback exactly
/// where [ResumeFab] left off. It reads the same `resume_*` keys written by
/// PlayerScreen — there is no separate background-audio session in this
/// app, so (like the FAB it replaces) this reflects "last watched position",
/// not a live playing/paused stream.
///
/// Drop this in via [MiniPlayerDock], which wraps a screen's existing
/// `RaddFlixBottomNav` so the bar always sits directly above it.
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  _MiniPlayerData? _data;
  bool _dismissed = false;
  late AnimationController _anim;
  late Animation<double> _slideIn;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _slideIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      _data = _MiniPlayerData(
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

  Future<void> _dismiss() async {
    if (!mounted) return;
    setState(() => _dismissed = true);
    await ResumeFab.clear();
  }

  void _expand() {
    final d = _data;
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
        _dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Active subscription required to continue watching.')),
        );
        return;
      }
    }
    DebugLogger.logTap('MiniPlayerBar', 'expand');
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
    if (_dismissed || _data == null) return const SizedBox.shrink();
    final d = _data!;
    final progress =
        d.durationMs > 0 ? (d.positionMs / d.durationMs).clamp(0.0, 1.0) : 0.0;

    return SizeTransition(
      sizeFactor: _slideIn,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _slideIn,
        child: Dismissible(
          key: ValueKey('mini_player_${d.fileId}'),
          direction: DismissDirection.down,
          onDismissed: (_) => _dismiss(),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _expand,
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
                                onTap: _dismiss,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      right: 10, left: 2),
                                  child: Icon(AppIcons.close,
                                      size: 16, color: Colors.white38),
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
        color: const Color(0xFF2A2A2A),
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
