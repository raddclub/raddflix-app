import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class _SimosaCardState extends State<SimosaCard> {
  int _streak = 0;
  bool _claimedToday = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadStreak();
    _loadDismissed();
  }

  @override
  void dispose() {
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

  /// HS-01: load persisted dismiss state; auto-expires after 24 h.
  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt('simosa_dismissed_until') ?? 0;
    if (!mounted) return;
    setState(() {
      _dismissed = DateTime.now().millisecondsSinceEpoch < until;
    });
  }

  Future<void> _onClaim() async {
    await LocalDb.recordSimosaClaim();
    // Clear any active dismissal so the card shows "Claimed ✓" immediately.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('simosa_dismissed_until');
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

  /// HS-01: persist dismissal for 24 h so card stays gone across cold starts.
  Future<void> _onDismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now()
        .add(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await prefs.setInt('simosa_dismissed_until', until);
    if (mounted) setState(() => _dismissed = true);
  }

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
         child: InkWell(
           onTap: _launchSimosa,
           child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1C0B32), const Color(0xFF2A1260)]
                  : [const Color(0xFFEDE7FF), const Color(0xFFD8C8FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
             borderRadius: BorderRadius.circular(12),
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
             padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Jazz/SimoSA icon ────────────────────────────────
                 _JazzBadgeIcon(streak: _streak),
                 const SizedBox(width: 10),

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
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.simosaAccent,
                                  AppColors.simosaAccent.withOpacity(0.65),
                                ],
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
                      // HS-02: single-line with ellipsis prevents wrapping on
                      // narrow (360 dp) screens.
                      Text(
                        _claimedToday
                            ? "Today's data claimed! Come back tomorrow."
                            : 'Claim your free Jazz data via SIMOSA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!_claimedToday)
                       GestureDetector(
                          onTap: _onClaim,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.simosaAccent,
                                  AppColors.simosaAccent.withOpacity(0.75),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                       ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.simosaAccent.withOpacity(0.45),
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
                          AppIcons.close,
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
    ),
  );
  }
}

/// SIMOSA app icon (real brand logo), with a small fire badge overlay once
/// the user hits a 7-day streak.
class _JazzBadgeIcon extends StatelessWidget {
  final int streak;
  const _JazzBadgeIcon({required this.streak});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
             width: 36,
             height: 36,
            decoration: BoxDecoration(
               borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
               borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/brand/simosa_logo.jpg',
                fit: BoxFit.cover,
                // Fallback if the asset is ever missing — keeps the card
                // from breaking instead of throwing.
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Text('S',
                        style: TextStyle(
                            color: Colors.white,
                             fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
          ),
          if (streak >= 7)
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C0B32),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1C0B32), width: 2),
                ),
                child: const Center(
                  child: Text('🔥', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
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
            valueColor: const AlwaysStoppedAnimation(AppColors.simosaAccent),
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
