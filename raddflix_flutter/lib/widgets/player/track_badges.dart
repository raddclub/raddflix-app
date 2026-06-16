import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';

/// Active audio track pill — e.g. "🎵 Urdu"
class AudioTrackBadge extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AudioTrackBadge({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.music_note_rounded, color: Colors.white70, size: 11),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.4, end: 0, duration: 200.ms),
    );
  }
}

/// Active subtitle track pill — e.g. "CC English" or "CC Off"
class SubTrackBadge extends StatelessWidget {
  final String label;
  final bool isOff;
  final VoidCallback onTap;

  const SubTrackBadge({
    super.key,
    required this.label,
    this.isOff = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOff ? Colors.transparent : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isOff ? Colors.white24 : Colors.white38, width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isOff ? Icons.closed_caption_disabled_rounded : Icons.closed_caption_rounded,
              color: isOff ? Colors.white38 : Colors.white70, size: 11),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
              color: isOff ? Colors.white38 : Colors.white,
              fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.4, end: 0, duration: 200.ms),
    );
  }
}

/// Track count badge — e.g. "3A · 2S"
class TrackCountBadge extends StatelessWidget {
  final int audioCount;
  final int subCount;

  const TrackCountBadge({
    super.key,
    required this.audioCount,
    required this.subCount,
  });

  @override
  Widget build(BuildContext context) {
    if (audioCount <= 1 && subCount <= 1) return const SizedBox.shrink();
    final parts = <String>[];
    if (audioCount > 1) parts.add('${audioCount}A');
    if (subCount > 1) parts.add('${subCount}S');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(parts.join(' · '), style: const TextStyle(
          color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
