import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/db/local_db.dart';
import '../core/constants.dart';

/// Phase 9 — SIMOSA daily reminder card.
///
/// Shows a compact card on the home screen reminding the subscriber
/// about their free daily Jazz MB allowance via the SIMOSA app.
/// Deep-link fix: tries to open the SIMOSA app directly first (if installed),
/// falls back to Play Store only when the app is not on the device.
class SimosaCard extends StatefulWidget {
  const SimosaCard({super.key});

  @override
  State<SimosaCard> createState() => _SimosaCardState();
}

class _SimosaCardState extends State<SimosaCard>
    with SingleTickerProviderStateMixin {
  int _streak = 0;
  bool _claimedToday = false;
  bool _dismissed = false;
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _loadStreak();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadStreak() async {
    final info = await LocalDb.getSimosaStreak();
    if (mounted) {
      setState(() {
        _streak       = info['streak'] as int;
        _claimedToday = info['claimed_today'] as bool;
      });
    }
  }

  Future<void> _onClaim() async {
    await LocalDb.recordSimosaClaim();
    await _loadStreak();
    await _launchSimosa();
  }

  /// Deep-link fix: try opening the SIMOSA app directly first (android-app://).
  /// If the app is not installed, fall back to Play Store.
  Future<void> _launchSimosa() async {
    // 1. Try to open the installed SIMOSA app directly
    final appUri = Uri.parse('android-app://${AppConstants.simosaAppPackage}');
    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
        return;
      }
    } catch (_) {}

    // 2. App not installed — open Play Store
    final storeUri = Uri.parse(AppConstants.simosaPlayStoreUrl);
    try {
      if (await canLaunchUrl(storeUri)) {
        await launchUrl(storeUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _onDismiss() => setState(() => _dismissed = true);

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1C0B32), const Color(0xFF2A1260)]
                  : [const Color(0xFFEDE7FF), const Color(0xFFD8C8FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.simosaAccent.withOpacity(isDark ? 0.35 : 0.5),
              width: 1,
            ),
            boxShadow: isDark
                ? [BoxShadow(
                    color: AppColors.simosaAccent.withOpacity(0.12),
                    blurRadius: 16, offset: const Offset(0, 4))]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Jazz/SimoSA icon ────────────────────────────────
                _JazzBadgeIcon(streak: _streak),
                const SizedBox(width: 12),

                // ── Text content ────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C5CFF), Color(0xFF9B7DFF)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'FREE 100 MB',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (_streak >= 3) ...[
                            const SizedBox(width: 6),
                            _StreakBadge(streak: _streak),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _claimedToday
                            ? "Today's data claimed! Come back tomorrow."
                            : 'Claim your free Jazz data via SIMOSA',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withOpacity(0.78)
                              : Colors.black.withOpacity(0.75),
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                      if (_streak >= 1 && !_claimedToday)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _StreakBar(streak: _streak, isDark: isDark),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // ── CTA + dismiss ───────────────────────────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_claimedToday)
                      ScaleTransition(
                        scale: _scale,
                        child: GestureDetector(
                          onTap: _onClaim,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C5CFF), Color(0xFF5B3FE0)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C5CFF).withOpacity(0.45),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Claim',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.success.withOpacity(0.4)),
                        ),
                        child: const Text(
                          'Claimed ✓',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: _onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Jazz-branded icon with gradient square + J logo / fire for high streaks.
class _JazzBadgeIcon extends StatelessWidget {
  final int streak;
  const _JazzBadgeIcon({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: streak >= 7
            ? const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFE8002D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFE8002D), Color(0xFFB5001F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8002D).withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: streak >= 7
            ? const Text('🔥', style: TextStyle(fontSize: 22))
            : const Text(
                'J',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

/// Compact streak badge.
class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.orange.withOpacity(0.45)),
      ),
      child: Text(
        '🔥 $streak day streak',
        style: const TextStyle(
          fontSize: 9.5,
          color: AppColors.orange,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Mini progress bar showing streak towards 7-day fire badge.
class _StreakBar extends StatelessWidget {
  final int streak;
  final bool isDark;
  const _StreakBar({required this.streak, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final progress = (streak / 7).clamp(0.0, 1.0);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: isDark ? Colors.white12 : Colors.black12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF7C5CFF)),
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        '${streak}/7 🔥',
        style: TextStyle(
          fontSize: 9,
          color: isDark ? Colors.white38 : Colors.black38,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]);
  }
}
