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

/// Persistent resume-last-watched button.
///
/// Reads [ResumeFab.prefsKeys] from SharedPreferences and shows a compact
/// floating card when valid resume data exists.  Tapping it pushes the
/// player route with the saved arguments so playback resumes at the saved
/// position (the player's built-in resume dialog handles the exact seek).
///
/// Call [ResumeFab.clear] to wipe the stored data (e.g. after the user
/// dismisses the card or when a new video starts from scratch).
class ResumeFab extends StatefulWidget {
  const ResumeFab({super.key});

  // ── Shared pref keys (written by PlayerScreen) ──────────────────────────
  static const String kTitle       = 'resume_title';
  static const String kFileId      = 'resume_file_id';
  static const String kStreamUrl   = 'resume_stream_url';
  static const String kLocalPath   = 'resume_local_path';
  static const String kPosterUrl   = 'resume_poster_url';
  static const String kPositionMs  = 'resume_pos_ms';
  static const String kDurationMs  = 'resume_dur_ms';
  static const String kContentType = 'resume_content_type';
  // BUG-11 fix: track is_free so free-content resume doesn't hit subscription gate.
  static const String kIsFree      = 'resume_is_free';

  /// Wipe all resume data.  Call when the user explicitly dismisses the FAB
  /// or when you want to suppress it.
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [kTitle, kFileId, kStreamUrl, kLocalPath, kPosterUrl,
                     kPositionMs, kDurationMs, kContentType, kIsFree]) {
      await p.remove(k);
    }
  }

  @override
  State<ResumeFab> createState() => _ResumeFabState();
}

class _ResumeFabState extends State<ResumeFab> with SingleTickerProviderStateMixin {
  _ResumeData? _data;
  bool _dismissed = false;
  late AnimationController _anim;
  late Animation<double> _fadeScale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _fadeScale = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final title    = p.getString(ResumeFab.kTitle);
    final fileId   = p.getString(ResumeFab.kFileId) ?? '';
    final streamUrl = p.getString(ResumeFab.kStreamUrl);
    final localPath = p.getString(ResumeFab.kLocalPath);
    final poster   = p.getString(ResumeFab.kPosterUrl);
    final posMs    = p.getInt(ResumeFab.kPositionMs) ?? 0;
    final durMs    = p.getInt(ResumeFab.kDurationMs) ?? 0;
    final ctype    = p.getString(ResumeFab.kContentType) ?? 'movie';
    // BUG-11 fix: read is_free so free content skips the subscription gate in _play().
    final isFree   = p.getBool(ResumeFab.kIsFree) ?? false;

    // Only show if we have a title and meaningful progress
    if (title == null || title.isEmpty || posMs < 10000) return;
    if (!mounted) return;
    setState(() {
      _data = _ResumeData(
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
    await _anim.reverse();
    if (!mounted) return;
    setState(() => _dismissed = true);
    await ResumeFab.clear();
  }

  void _play() {
    final d = _data;
    if (d == null) return;
    // P28-02: Gate streaming content for guests and inactive subscribers.
    // Downloaded content (local_path non-empty) bypasses this check — users
    // keep offline access to files they downloaded while subscribed.
    // Gate paid streaming content only — free content (is_free=true) is open to all.
    // Local downloaded files always bypass (no network needed, no sub check).
    // BUG-11 fix: previously no is_free tracking, so guests were blocked from
    // resuming free-content streams even though they can watch them without sub.
    if (!d.isFree && (d.localPath == null || d.localPath!.isEmpty)) {
      final auth    = ProviderScope.containerOf(context).read(authProvider);
      final subState = ProviderScope.containerOf(context).read(subscriptionProvider);
      final isSubscribed = auth.user != null &&
          !(auth.user!.isGuest) &&
          (subState.status != null
              ? subState.status!.isActive
              : auth.user!.hasActiveSubscription);
      if (!isSubscribed) {
        _dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Active subscription required to continue watching.')),
        );
        return;
      }
    }
    DebugLogger.logTap('ResumeFab', 'play');
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: {
        'file_id':       d.fileId,
        'title':         d.title,
        'stream_url':    d.streamUrl,
        'local_path':    d.localPath,
        'episodes':      <Map<String, dynamic>>[],
        'episode_index': 0,
        'content_type':  d.contentType,
        'is_free':       d.isFree,  // BUG-11 fix: pass to player so _isFree/_trackUsage set correctly
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
    final progress = d.durationMs > 0 ? (d.positionMs / d.durationMs).clamp(0.0, 1.0) : 0.0;

    return ScaleTransition(
      scale: _fadeScale,
      child: FadeTransition(
        opacity: _fadeScale,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _play,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 16, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Thumbnail row ──────────────────────────────────────
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: Stack(
                        children: [
                          // Thumbnail
                          SizedBox(
                            height: 110,
                            width: double.infinity,
                            child: d.posterUrl != null && d.posterUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: d.posterUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _posterFallback(),
                                  )
                                : _posterFallback(),
                          ),
                          // Dark gradient at bottom
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.85),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Play icon overlay
                          const Positioned.fill(
                            child: Center(
                              child: Icon(AppIcons.playCircleFill,
                                  color: Colors.white70, size: 36),
                            ),
                          ),
                          // Dismiss X
                          Positioned(
                            top: 4, right: 4,
                            child: GestureDetector(
                              onTap: _dismiss,
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(AppIcons.close,
                                    size: 14, color: Colors.white70),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Progress bar ──────────────────────────────────────
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      minHeight: 2,
                    ),
                    // ── Title + time ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Continue from ${_fmtDuration(d.positionMs)}',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
    );
  }

  Widget _posterFallback() => Container(
    color: const Color(0xFF2A2A2A),
    child: const Center(
      child: Icon(AppIcons.movieFill, color: Colors.white24, size: 40),
    ),
  );
}

class _ResumeData {
  final String title;
  final String fileId;
  final String? streamUrl;
  final String? localPath;
  final String? posterUrl;
  final int positionMs;
  final int durationMs;
  final String contentType;
  // BUG-11 fix: track whether the content was free so _play() can skip sub gate.
  final bool isFree;

  const _ResumeData({
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
