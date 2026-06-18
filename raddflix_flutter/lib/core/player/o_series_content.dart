/// Phase O — Content Discovery & Recommendations
/// O1 — Smart Continue Watching (saves position + remembers episode)
/// O2 — Similar Content Shelf (genre-based inline suggestions)
/// O3 — Watched Timeline (per-day watch history calendar)
/// O4 — Content Mood Tags (tag episodes: funny, intense, scary, etc.)
library o_series;

import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// O1 — Continue Watching Entry
// ─────────────────────────────────────────────────────────────────────────────

class ContinueWatchingEntry {
  final String contentId;
  final String title;
  final String? thumbnailUrl;
  final int episode;         // 0 for movies
  final String episodeTitle;
  final int positionMs;
  final int durationMs;
  final DateTime lastWatched;

  const ContinueWatchingEntry({
    required this.contentId,
    required this.title,
    this.thumbnailUrl,
    this.episode = 0,
    this.episodeTitle = '',
    required this.positionMs,
    required this.durationMs,
    required this.lastWatched,
  });

  double get progress => durationMs > 0 ? positionMs / durationMs : 0.0;

  String get progressLabel {
    final rem = Duration(milliseconds: durationMs - positionMs);
    if (rem.inMinutes < 1) return 'Almost done';
    if (rem.inHours < 1) return '${rem.inMinutes}m left';
    final mins = rem.inMinutes.remainder(60);
    return mins > 0 ? '${rem.inHours}h ${mins}m left' : '${rem.inHours}h left';
  }

  Map<String, dynamic> toJson() => {
    'contentId': contentId, 'title': title,
    'thumbnailUrl': thumbnailUrl, 'episode': episode,
    'episodeTitle': episodeTitle, 'positionMs': positionMs,
    'durationMs': durationMs, 'lastWatched': lastWatched.millisecondsSinceEpoch,
  };

  factory ContinueWatchingEntry.fromJson(Map<String, dynamic> j) =>
      ContinueWatchingEntry(
        contentId: j['contentId'], title: j['title'],
        thumbnailUrl: j['thumbnailUrl'], episode: j['episode'] ?? 0,
        episodeTitle: j['episodeTitle'] ?? '',
        positionMs: j['positionMs'], durationMs: j['durationMs'],
        lastWatched: DateTime.fromMillisecondsSinceEpoch(j['lastWatched']),
      );
}

// ── Continue Watching Store ───────────────────────────────────────────────────
class ContinueWatchingStore {
  ContinueWatchingStore._();
  static final instance = ContinueWatchingStore._();

  final _entries = <String, ContinueWatchingEntry>{};
  List<ContinueWatchingEntry> get all {
    final list = _entries.values.toList();
    list.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return list;
  }

  void save(ContinueWatchingEntry entry) =>
      _entries[entry.contentId] = entry;

  void remove(String contentId) => _entries.remove(contentId);

  String toJson() =>
      jsonEncode(_entries.values.map((e) => e.toJson()).toList());

  void loadFromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      for (final j in list.cast<Map<String, dynamic>>()) {
        final e = ContinueWatchingEntry.fromJson(j);
        _entries[e.contentId] = e;
      }
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// O4 — Content Mood Tags
// ─────────────────────────────────────────────────────────────────────────────

enum MoodTag {
  funny, intense, scary, romantic, sad, inspiring, family, suspense,
  chill, educational, cringe, mindBlowing
}

const moodTagEmojis = {
  MoodTag.funny:        '😂', MoodTag.intense:     '🔥',
  MoodTag.scary:        '👻', MoodTag.romantic:    '💕',
  MoodTag.sad:          '😢', MoodTag.inspiring:   '💪',
  MoodTag.family:       '👨‍👩‍👧', MoodTag.suspense:    '😰',
  MoodTag.chill:        '😌', MoodTag.educational: '📚',
  MoodTag.cringe:       '😬', MoodTag.mindBlowing: '🤯',
};

const moodTagLabels = {
  MoodTag.funny:        'Funny',       MoodTag.intense:     'Intense',
  MoodTag.scary:        'Scary',       MoodTag.romantic:    'Romantic',
  MoodTag.sad:          'Sad',         MoodTag.inspiring:   'Inspiring',
  MoodTag.family:       'Family',      MoodTag.suspense:    'Suspense',
  MoodTag.chill:        'Chill',       MoodTag.educational: 'Educational',
  MoodTag.cringe:       'Cringe',      MoodTag.mindBlowing: 'Mind-blowing',
};

MoodTag moodTagFromString(String s) =>
    MoodTag.values.firstWhere((t) => t.name == s, orElse: () => MoodTag.chill);

class MoodTagChipBar extends StatelessWidget {
  final Set<MoodTag> selected;
  final ValueChanged<MoodTag> onToggle;
  final Color accentColor;

  const MoodTagChipBar({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: MoodTag.values.map((t) {
          final active = selected.contains(t);
          return GestureDetector(
            onTap: () => onToggle(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: active ? accentColor.withOpacity(0.18) : Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active ? accentColor : Colors.white24, width: 1.2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(moodTagEmojis[t]!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(moodTagLabels[t]!,
                    style: TextStyle(
                        color: active ? accentColor : Colors.white60,
                        fontSize: 11.5, fontWeight: FontWeight.w500)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}
