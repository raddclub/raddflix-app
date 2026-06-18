/// Phase P — Parental Controls
/// P1 — Content Rating Locks (per-profile PIN + rating ceiling)
/// P2 — Watch Time Limits (daily cap per profile)
/// P3 — Bedtime Mode (auto-pause after time limit)
/// P4 — Parental Dashboard (admin view of what each profile watched)
library p_series;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// P1 — Content Rating
// ─────────────────────────────────────────────────────────────────────────────

enum ContentRating { g, pg, pg13, r, nc17 }

const ratingLabels = {
  ContentRating.g:     'G — All Ages',
  ContentRating.pg:    'PG — Parental Guidance',
  ContentRating.pg13:  'PG-13 — 13+',
  ContentRating.r:     'R — 17+',
  ContentRating.nc17:  'NC-17 — Adults Only',
};

ContentRating ratingFromString(String s) =>
    ContentRating.values.firstWhere((r) => r.name == s,
        orElse: () => ContentRating.r);

bool isRatingAllowed(ContentRating content, ContentRating ceiling) =>
    content.index <= ceiling.index;

// ─────────────────────────────────────────────────────────────────────────────
// P2+P3 — Watch Time Limit + Bedtime Mode
// ─────────────────────────────────────────────────────────────────────────────

class WatchTimeLimitService {
  WatchTimeLimitService._();
  static final instance = WatchTimeLimitService._();

  int _dailyLimitMinutes = 0; // 0 = unlimited
  int _watchedTodayMinutes = 0;
  Timer? _timer;

  final _warningCtrl = StreamController<int>.broadcast(); // seconds remaining
  Stream<int> get warnings => _warningCtrl.stream;

  void configure({required int dailyLimitMinutes}) {
    _dailyLimitMinutes = dailyLimitMinutes;
  }

  void startTracking() {
    if (_dailyLimitMinutes <= 0) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _watchedTodayMinutes++;
      final remaining = _dailyLimitMinutes - _watchedTodayMinutes;
      if (remaining == 10 || remaining == 5 || remaining == 3 || remaining == 1) {
        _warningCtrl.add(remaining * 60);
      }
    });
  }

  void stop() { _timer?.cancel(); }

  bool get isLimitReached =>
      _dailyLimitMinutes > 0 &&
      _watchedTodayMinutes >= _dailyLimitMinutes;

  int get remainingMinutes => (_dailyLimitMinutes - _watchedTodayMinutes).clamp(0, 9999);
}

// ─────────────────────────────────────────────────────────────────────────────
// P2 — Watch Time Warning overlay
// ─────────────────────────────────────────────────────────────────────────────
class WatchTimeWarningBanner extends StatelessWidget {
  final int remainingMinutes;
  final Color accentColor;
  final VoidCallback onDismiss;

  const WatchTimeWarningBanner({
    super.key,
    required this.remainingMinutes,
    required this.accentColor,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgent = remainingMinutes <= 3;
    return Positioned(
      top: 16, left: 16, right: 16,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUrgent ? Colors.red.withOpacity(0.9) : Colors.orange.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 4))],
        ),
        child: Row(children: [
          Icon(isUrgent ? Icons.warning_amber_rounded : Icons.access_time_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isUrgent ? 'Almost done for today!' : 'Watch time reminder',
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text('$remainingMinutes minute${remainingMinutes == 1 ? '' : 's'} remaining today',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// P3 — Bedtime Limit Reached Screen
// ─────────────────────────────────────────────────────────────────────────────
class BedtimeLimitScreen extends StatelessWidget {
  final String pinHash;
  final VoidCallback onUnlockWithPin;
  final Color accentColor;

  const BedtimeLimitScreen({
    super.key,
    required this.pinHash,
    required this.onUnlockWithPin,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🌙', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            const Text("Time's Up!", style: TextStyle(color: Colors.white,
                fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text("You've reached your daily watch limit.",
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: onUnlockWithPin,
              icon: Icon(Icons.lock_open_rounded, color: accentColor, size: 18),
              label: Text('Override with PIN',
                  style: TextStyle(color: accentColor, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }
}
