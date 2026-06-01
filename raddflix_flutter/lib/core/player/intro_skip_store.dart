import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Phase P — Intro/Outro Skip Timestamp Store
/// Stores per-series/episode skip segments (intro, recap, credits, sponsor).

enum SkipSegmentType { intro, recap, credits, sponsor, custom }

class SkipSegment {
  final SkipSegmentType type;
  final int startMs;
  final int endMs;
  final String? label;

  const SkipSegment({
    required this.type,
    required this.startMs,
    required this.endMs,
    this.label,
  });

  String get typeLabel {
    switch (type) {
      case SkipSegmentType.intro:   return 'Skip Intro';
      case SkipSegmentType.recap:   return 'Skip Recap';
      case SkipSegmentType.credits: return 'Skip Credits';
      case SkipSegmentType.sponsor: return 'Skip Sponsor';
      case SkipSegmentType.custom:  return label ?? 'Skip';
    }
  }

  Duration get start => Duration(milliseconds: startMs);
  Duration get end   => Duration(milliseconds: endMs);
  Duration get length => Duration(milliseconds: endMs - startMs);

  Map<String, dynamic> toJson() => {
    'type': type.name, 'startMs': startMs, 'endMs': endMs, 'label': label,
  };

  static SkipSegment fromJson(Map<String, dynamic> j) => SkipSegment(
    type: SkipSegmentType.values.firstWhere((t) => t.name == j['type'],
        orElse: () => SkipSegmentType.custom),
    startMs: j['startMs'] as int,
    endMs:   j['endMs']   as int,
    label:   j['label']   as String?,
  );
}

/// Stores skip segments per video ID (episodeId or content URL hash).
class IntroSkipStore {
  static const _prefix = 'intro_skip_v2_';

  static Future<List<SkipSegment>> load(String videoId) async {
    final s = await SharedPreferences.getInstance();
    final raw = s.getString(_prefix + videoId);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((j) => SkipSegment.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String videoId, List<SkipSegment> segments) async {
    final s = await SharedPreferences.getInstance();
    await s.setString(_prefix + videoId, jsonEncode(segments.map((s) => s.toJson()).toList()));
  }

  static Future<void> addSegment(String videoId, SkipSegment seg) async {
    final existing = await load(videoId);
    // Merge overlapping segments of same type
    final merged = existing.where((e) => e.type != seg.type || e.endMs < seg.startMs - 1000 || e.startMs > seg.endMs + 1000).toList();
    merged.add(seg);
    merged.sort((a, b) => a.startMs.compareTo(b.startMs));
    await save(videoId, merged);
  }

  static Future<void> removeSegment(String videoId, SkipSegment seg) async {
    final existing = await load(videoId);
    existing.removeWhere((e) => e.startMs == seg.startMs && e.type == seg.type);
    await save(videoId, existing);
  }

  static Future<void> clearAll(String videoId) async {
    final s = await SharedPreferences.getInstance();
    await s.remove(_prefix + videoId);
  }

  /// Returns the active skip segment at the given position (null if none).
  static SkipSegment? activeAt(List<SkipSegment> segments, Duration position) {
    for (final seg in segments) {
      if (position >= seg.start && position <= seg.end) return seg;
    }
    return null;
  }
}

/// Overlay button shown when player is inside a skip segment.
class SkipSegmentButton extends StatelessWidget {
  final SkipSegment segment;
  final Color accentColor;
  final VoidCallback onSkip;

  const SkipSegmentButton({
    super.key,
    required this.segment,
    required this.accentColor,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 100,
      child: GestureDetector(
        onTap: onSkip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accentColor, width: 1.5),
            boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 12)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(segment.typeLabel, style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(Icons.fast_forward_rounded, color: accentColor, size: 18),
          ]),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
