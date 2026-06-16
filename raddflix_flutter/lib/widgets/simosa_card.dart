import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/db/local_db.dart';
import '../core/constants.dart';

/// Phase 9 — SIMOSA daily reminder card.
///
/// Shows a compact card on the home screen reminding the subscriber
/// about their free daily Jazz MB allowance via the SIMOSA app.
/// Tracks the daily streak of dismissals to add gamification.
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
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
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
        _streak      = info['streak'] as int;
        _claimedToday = info['claimed_today'] as bool;
      });
    }
  }

  Future<void> _onClaim() async {
    await LocalDb.recordSimosaClaim();
    await _loadStreak();
    await _launchSimosa();
  }

  Future<void> _launchSimosa() async {
    final uri = Uri.parse(AppConstants.simosaPlayStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onDismiss() {
    setState(() => _dismissed = true);
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
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [AppColors.simosaBgDark, AppColors.simosaBgDark2]
                  : [AppColors.simosaBgLight, AppColors.simosaBgLight2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.simosaAccent.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Jazz logo / icon
                _JazzIcon(streak: _streak),
                const SizedBox(width: 12),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'FREE 100 MB',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.simosaAccent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (_streak >= 3) ...[
                            const SizedBox(width: 6),
                            _StreakBadge(streak: _streak),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _claimedToday
                            ? "Today's MBs claimed ✓"
                            : 'Claim today\'s free Jazz data via SIMOSA',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.white.withOpacity(0.75)
                              : Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // CTA / dismiss
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_claimedToday)
                      ScaleTransition(
                        scale: _scale,
                        child: ElevatedButton(
                          onPressed: _onClaim,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.simosaAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Claim'),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.success.withOpacity(0.4)),
                        ),
                        child: const Text(
                          'Claimed ✓',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      onPressed: _onDismiss,
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: isDark
                            ? Colors.white38
                            : Colors.black26,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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

class _JazzIcon extends StatelessWidget {
  final int streak;
  const _JazzIcon({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.simosaAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: streak >= 7
            ? const Text('🔥', style: TextStyle(fontSize: 22))
            : const Text('💜', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}

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
        border: Border.all(color: AppColors.orange.withOpacity(0.5)),
      ),
      child: Text(
        '🔥 $streak day streak',
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.orange,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
