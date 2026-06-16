/// Phase Q — User Analytics & Stats (Privacy-first, all local)
/// Q1 — Watch History & Stats (hours watched, genres, avg session)
/// Q2 — Favourite Genres Chart (bar chart by genre)
/// Q3 — Watch Streak (daily login / watch streak tracker)
/// Q4 — Personal Year in Review (annual stats card)
library q_series;

import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Q1 — Watch Session
// ─────────────────────────────────────────────────────────────────────────────

class WatchSession {
  final String contentId;
  final String title;
  final String genre;
  final DateTime startTime;
  final int durationMs;
  final bool completed;

  const WatchSession({
    required this.contentId,
    required this.title,
    required this.genre,
    required this.startTime,
    required this.durationMs,
    required this.completed,
  });

  Map<String, dynamic> toJson() => {
    'contentId': contentId, 'title': title, 'genre': genre,
    'startTime': startTime.millisecondsSinceEpoch,
    'durationMs': durationMs, 'completed': completed,
  };

  factory WatchSession.fromJson(Map<String, dynamic> j) => WatchSession(
    contentId: j['contentId'], title: j['title'], genre: j['genre'],
    startTime: DateTime.fromMillisecondsSinceEpoch(j['startTime']),
    durationMs: j['durationMs'], completed: j['completed'],
  );
}

class WatchAnalytics {
  WatchAnalytics._();
  static final instance = WatchAnalytics._();

  final _sessions = <WatchSession>[];

  void record(WatchSession s) => _sessions.add(s);

  // Total watch time in hours
  double get totalHours =>
      _sessions.fold<int>(0, (t, s) => t + s.durationMs) / 3600000;

  // Sessions in last N days
  List<WatchSession> lastDays(int n) {
    final cutoff = DateTime.now().subtract(Duration(days: n));
    return _sessions.where((s) => s.startTime.isAfter(cutoff)).toList();
  }

  // Genre breakdown
  Map<String, double> genreHours() {
    final map = <String, double>{};
    for (final s in _sessions) {
      map[s.genre] = (map[s.genre] ?? 0) + s.durationMs / 3600000;
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  // Q3 Watch streak (consecutive days)
  int get watchStreak {
    if (_sessions.isEmpty) return 0;
    final days = _sessions.map((s) =>
        DateTime(s.startTime.year, s.startTime.month, s.startTime.day))
        .toSet().toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) return 0;
    var streak = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i-1].difference(days[i]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int get totalEpisodes => _sessions.where((s) => s.completed).length;

  String toJson() => jsonEncode(_sessions.map((s) => s.toJson()).toList());
  void loadFromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      _sessions.addAll(list.cast<Map<String, dynamic>>().map(WatchSession.fromJson));
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Q1+Q2 — Stats Card (shown in profile screen)
// ─────────────────────────────────────────────────────────────────────────────
class WatchStatsCard extends StatelessWidget {
  final Color accentColor;

  const WatchStatsCard({super.key, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final stats = WatchAnalytics.instance;
    final genres = stats.genreHours();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.insights_rounded, color: accentColor, size: 20),
          const SizedBox(width: 8),
          const Text('Watch Stats', style: TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _stat('${stats.totalHours.toStringAsFixed(1)}h', 'Total watched'),
          _divider(),
          _stat('${stats.totalEpisodes}', 'Completed'),
          _divider(),
          _stat('${stats.watchStreak}🔥', 'Day streak'),
        ]),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Top Genres', style: TextStyle(color: Colors.white54,
              fontSize: 11, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          ...genres.entries.take(4).map((e) => _genreBar(
            e.key, e.value, genres.values.first, accentColor)),
        ],
      ]),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(children: [
      Text(value, style: const TextStyle(color: Colors.white,
          fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]),
  );

  Widget _divider() => Container(width: 1, height: 40, color: Colors.white10);

  Widget _genreBar(String genre, double hours, double max, Color accent) {
    final pct = max > 0 ? hours / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 70, child: Text(genre,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
            overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 6,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(accent)),
        )),
        const SizedBox(width: 8),
        Text('${hours.toStringAsFixed(1)}h',
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Q3 — Watch Streak Badge (for profile/home screen)
// ─────────────────────────────────────────────────────────────────────────────
class WatchStreakBadge extends StatelessWidget {
  final int streak;
  final Color accentColor;

  const WatchStreakBadge({super.key, required this.streak, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    if (streak < 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.orange.shade700, Colors.deepOrange.shade400]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔥', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text('$streak day streak',
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
