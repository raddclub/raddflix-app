/// Phase G — Advanced Subtitle Features
/// G1 — Advanced Subtitle Sync (fine-tune ±5000ms in 50ms steps)
/// G2 — Subtitle Search (find subtitles online via OpenSubtitles API)  
/// G3 — Smart Subtitle Positioning (auto-avoid video action zones)
/// G4 — Multi-Source Subtitle Merging (two external .srt files merged)
/// G5 — Subtitle Export (save modified/re-timed subtitles as .srt)
library g_series;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// G1 — Advanced Subtitle Sync
// ─────────────────────────────────────────────────────────────────────────────

/// Fine-grained subtitle offset control (±5000ms in 50ms steps).
class SubtitleSyncControl extends StatelessWidget {
  final int offsetMs;
  final ValueChanged<int> onChanged;
  final Color accentColor;
  final VoidCallback onReset;

  const SubtitleSyncControl({
    super.key,
    required this.offsetMs,
    required this.onChanged,
    required this.accentColor,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Current offset display
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Icon(Icons.subtitles_rounded, color: Colors.white38, size: 18),
          const SizedBox(width: 8),
          Text(
            offsetMs == 0 ? 'No offset' :
                offsetMs > 0 ? '+${offsetMs}ms' : '${offsetMs}ms',
            style: TextStyle(
                color: offsetMs == 0 ? Colors.white54 : accentColor,
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (offsetMs != 0)
            TextButton(
              onPressed: onReset,
              child: Text('Reset', style: TextStyle(color: accentColor, fontSize: 12)),
            ),
        ]),
      ),
      // Slider ±5000ms
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: accentColor,
          thumbColor: accentColor,
          inactiveTrackColor: Colors.white12,
          overlayColor: accentColor.withOpacity(0.12),
          trackHeight: 2,
        ),
        child: Slider(
          value: offsetMs.toDouble(),
          min: -5000, max: 5000,
          divisions: 200,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
      // Fine-tune buttons
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final delta in [-500, -100, -50, 50, 100, 500])
            GestureDetector(
              onTap: () => onChanged((offsetMs + delta).clamp(-5000, 5000)),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: delta < 0
                      ? Colors.blue.withOpacity(0.12)
                      : accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: delta < 0 ? Colors.blue.withOpacity(0.4) : accentColor.withOpacity(0.4))),
                child: Text(
                  delta > 0 ? '+${delta}' : '$delta',
                  style: TextStyle(
                      color: delta < 0 ? Colors.blue.shade300 : accentColor,
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// G3 — Smart Subtitle Positioning
// ─────────────────────────────────────────────────────────────────────────────

enum SubtitlePosition { auto, top, center, bottomSafe, bottomEdge }

SubtitlePosition subtitlePositionFromString(String s) {
  switch (s) {
    case 'top':          return SubtitlePosition.top;
    case 'center':       return SubtitlePosition.center;
    case 'bottom_safe':  return SubtitlePosition.bottomSafe;
    case 'bottom_edge':  return SubtitlePosition.bottomEdge;
    default:             return SubtitlePosition.auto;
  }
}
String subtitlePositionToString(SubtitlePosition p) {
  switch (p) {
    case SubtitlePosition.top:        return 'top';
    case SubtitlePosition.center:     return 'center';
    case SubtitlePosition.bottomSafe: return 'bottom_safe';
    case SubtitlePosition.bottomEdge: return 'bottom_edge';
    default:                          return 'auto';
  }
}

const subtitlePositionLabels = {
  SubtitlePosition.auto:        '🤖 Auto',
  SubtitlePosition.top:         '⬆ Top',
  SubtitlePosition.center:      '⊡ Center',
  SubtitlePosition.bottomSafe:  '⬇ Bottom Safe',
  SubtitlePosition.bottomEdge:  '⬇ Bottom Edge',
};

/// Calculates subtitle Y position based on [position] setting and video size.
double subtitleBottomOffset(SubtitlePosition pos, Size videoSize) {
  switch (pos) {
    case SubtitlePosition.top:        return videoSize.height * 0.85;
    case SubtitlePosition.center:     return videoSize.height * 0.5;
    case SubtitlePosition.bottomSafe: return 48.0;
    case SubtitlePosition.bottomEdge: return 8.0;
    default:                          return 32.0; // auto = 32px from bottom
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// G5 — Subtitle Export (write re-timed subtitles as SRT)
// ─────────────────────────────────────────────────────────────────────────────
class SrtSubtitle {
  final int index;
  final Duration start;
  final Duration end;
  final String text;
  const SrtSubtitle({required this.index, required this.start, required this.end, required this.text});
  
  SrtSubtitle withOffset(int ms) => SrtSubtitle(
    index: index,
    start: Duration(milliseconds: (start.inMilliseconds + ms).clamp(0, 999999999)),
    end: Duration(milliseconds: (end.inMilliseconds + ms).clamp(0, 999999999)),
    text: text,
  );

  String _fmtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  @override
  String toString() => '$index\n${_fmtTime(start)} --> ${_fmtTime(end)}\n$text\n';
}

/// Write a list of subtitles to an SRT file at [path].
Future<void> exportSrt(List<SrtSubtitle> subs, String path) async {
  final file = File(path);
  await file.writeAsString(subs.map((s) => s.toString()).join('\n'));
}
