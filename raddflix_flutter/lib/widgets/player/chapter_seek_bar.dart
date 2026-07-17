import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Phase Q — Chapter Markers on Seek Bar
/// Renders chapter boundaries + currently-active chapter label above seek bar.

class Chapter {
  final String title;
  final Duration start;
  final Duration? end;
  const Chapter({required this.title, required this.start, this.end});
}

class ChapterSeekBar extends StatefulWidget {
  final List<Chapter> chapters;
  final Duration position;
  final Duration totalDuration;
  final Color accentColor;
  final bool showLabel;
  final ValueChanged<Duration>? onSeek;
  final bool moodEnabled; // Phase G4: narrative-arc colour zones

  const ChapterSeekBar({
    super.key,
    required this.chapters,
    required this.position,
    required this.totalDuration,
    required this.accentColor,
    this.showLabel = true,
    this.onSeek,
    this.moodEnabled = false,
  });

  @override
  State<ChapterSeekBar> createState() => _ChapterSeekBarState();
}

class _ChapterSeekBarState extends State<ChapterSeekBar> {
  late List<Chapter> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = _sortChapters(widget.chapters);
  }

  @override
  void didUpdateWidget(ChapterSeekBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.chapters, widget.chapters) ||
        old.chapters.length != widget.chapters.length) {
      _sorted = _sortChapters(widget.chapters);
    }
  }

  static List<Chapter> _sortChapters(List<Chapter> chapters) =>
      List<Chapter>.of(chapters)..sort((a, b) => a.start.compareTo(b.start));

  Chapter? get _current {
    if (_sorted.isEmpty) return null;
    for (int i = _sorted.length - 1; i >= 0; i--) {
      if (widget.position >= _sorted[i].start) return _sorted[i];
    }
    return _sorted.first;
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.showLabel && current != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 4),
          child: Text(current.title, style: TextStyle(
              color: widget.accentColor, fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      SizedBox(
        height: 24,
        child: GestureDetector(
          onTapDown: (details) {
            if (widget.onSeek == null || widget.totalDuration.inMilliseconds == 0) return;
            final frac = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
            widget.onSeek!(Duration(milliseconds: (frac * widget.totalDuration.inMilliseconds).round()));
          },
          child: CustomPaint(
            size: const Size(double.infinity, 24),
            painter: _ChapterPainter(
              chapters: _sorted,
              position: widget.position,
              totalDuration: widget.totalDuration,
              accentColor: widget.accentColor,
              moodEnabled: widget.moodEnabled,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _ChapterPainter extends CustomPainter {
  final List<Chapter> chapters;
  final Duration position;
  final Duration totalDuration;
  final Color accentColor;
  final bool moodEnabled;

  const _ChapterPainter({
    required this.chapters,
    required this.position,
    required this.totalDuration,
    required this.accentColor,
    this.moodEnabled = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration.inMilliseconds == 0) return;

    final totalMs = totalDuration.inMilliseconds.toDouble();
    final posMs   = position.inMilliseconds.toDouble();
    final posX    = (posMs / totalMs * size.width).clamp(0.0, size.width);
    final trackY  = size.height / 2;
    const trackH  = 4.0;

    final sorted = chapters; // pre-sorted by _ChapterSeekBarState

    if (sorted.isEmpty) {
      // Plain track
      _drawTrack(canvas, size, posX, trackY, trackH);
      return;
    }

    // Draw chapter segments
    for (int i = 0; i < sorted.length; i++) {
      final segStartMs = sorted[i].start.inMilliseconds.toDouble();
      final segEndMs   = i + 1 < sorted.length
          ? sorted[i + 1].start.inMilliseconds.toDouble()
          : totalMs;

      final x1 = segStartMs / totalMs * size.width + 1;
      final x2 = segEndMs   / totalMs * size.width - 1;

      final isActive = posMs >= segStartMs && posMs < segEndMs;
      final isPassed = posMs >= segEndMs;

      final paint = Paint()
        ..color = isPassed
            ? accentColor.withOpacity(0.9)
            : isActive
                ? accentColor.withOpacity(0.7)
                : Colors.white24
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x1, trackY - trackH / 2, (x2 - x1).clamp(0, size.width), trackH),
          const Radius.circular(2)),
        paint);

      // Active segment fill up to current position
      if (isActive) {
        final fillX = (posMs / totalMs * size.width).clamp(x1, x2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x1, trackY - trackH / 2, fillX - x1, trackH),
            const Radius.circular(2)),
          Paint()..color = accentColor);
      }

      // Chapter boundary tick
      if (i > 0) {
        canvas.drawRect(
          Rect.fromLTWH(x1 - 0.5, trackY - 6, 1.5, 12),
          Paint()..color = Colors.black.withOpacity(0.6));
      }
    }

    // G4: Mood zones (painted below thumb so thumb stays readable)
    _paintMoodZones(canvas, size, trackY, trackH);

    // Thumb
    canvas.drawCircle(Offset(posX.toDouble(), trackY), 7,
        Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(posX.toDouble(), trackY), 7,
        Paint()..color = accentColor.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2);
  }


  static const _moodZoneColors = [
    Color(0x281E90FF), // 0-25%  calm/intro — blue
    Color(0x2832CD32), // 25-50% rising action — green
    Color(0x28FF8C00), // 50-75% tension — orange
    Color(0x28DC143C), // 75-100% climax — crimson
  ];

  void _paintMoodZones(Canvas canvas, Size size, double trackY, double trackH) {
    if (!moodEnabled) return;
    final zw = size.width / 4;
    for (int z = 0; z < 4; z++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(z * zw, trackY - trackH / 2, zw, trackH),
          const Radius.circular(2)),
        Paint()..color = _moodZoneColors[z]);
    }
  }

  void _drawTrack(Canvas canvas, Size size, double posX, double trackY, double trackH) {
    _paintMoodZones(canvas, size, trackY, trackH); // G4
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY - trackH/2, size.width, trackH), const Radius.circular(2)),
        Paint()..color = Colors.white24);
    if (posX > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, trackY - trackH/2, posX, trackH), const Radius.circular(2)),
          Paint()..color = accentColor);
    }
    canvas.drawCircle(Offset(posX, trackY), 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ChapterPainter o) =>
      o.position != position || o.chapters.length != chapters.length || o.moodEnabled != moodEnabled;
}

/// Horizontal chapter list shown above the seek bar.
class ChapterList extends StatelessWidget {
  final List<Chapter> chapters;
  final Duration position;
  final Color accentColor;
  final ValueChanged<Duration> onSeek;

  const ChapterList({
    super.key,
    required this.chapters,
    required this.position,
    required this.accentColor,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: sorted.length,
        itemBuilder: (ctx, i) {
          final ch   = sorted[i];
          final next = i + 1 < sorted.length ? sorted[i + 1] : null;
          final endMs = next?.start.inMilliseconds ?? double.maxFinite.toInt();
          final active = position >= ch.start &&
              (next == null || position < next.start);
          return GestureDetector(
            onTap: () => onSeek(ch.start),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? accentColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: active ? accentColor : Colors.white12,
                    width: active ? 1.5 : 1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${i + 1}', style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text(ch.title, style: TextStyle(
                    color: active ? Colors.white : Colors.white60,
                    fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
