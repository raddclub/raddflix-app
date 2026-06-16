import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 10 seek bar visual styles.
enum SeekBarStyle {
  classic,
  materialBold,
  gradientGlow,
  waveform,
  neonRgb,
  filmstrip,
  chapters,
  dots,
  circular,
  minimal,
}

SeekBarStyle seekBarStyleFromString(String s) =>
    SeekBarStyle.values.firstWhere((e) => e.name == s,
        orElse: () => SeekBarStyle.classic);

/// CustomPainter that draws the seek bar according to [style].
class SeekBarPainter extends CustomPainter {
  final SeekBarStyle style;
  final double progress;
  final double buffered;
  final Color accentColor;
  final double neonPhase;
  final Color gradientColor1;
  final Color gradientColor2;
  final List<double> chapterFractions;
  final List<double> waveformAmplitudes;
  final bool moodEnabled; // Phase G4: content mood timeline colors

  SeekBarPainter({
    required this.style,
    required this.progress,
    required this.buffered,
    required this.accentColor,
    this.neonPhase = 0,
    Color? gradientColor1,
    Color? gradientColor2,
    this.chapterFractions = const [],
    this.waveformAmplitudes = const [],
    this.moodEnabled = false,
  })  : gradientColor1 = gradientColor1 ?? accentColor,
        gradientColor2 = gradientColor2 ?? accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case SeekBarStyle.classic:
        _paintClassic(canvas, size);
        break;
      case SeekBarStyle.materialBold:
        _paintMaterialBold(canvas, size);
        break;
      case SeekBarStyle.gradientGlow:
        _paintGradientGlow(canvas, size);
        break;
      case SeekBarStyle.waveform:
        _paintWaveform(canvas, size);
        break;
      case SeekBarStyle.neonRgb:
        _paintNeonRgb(canvas, size);
        break;
      case SeekBarStyle.filmstrip:
        _paintFilmstrip(canvas, size);
        break;
      case SeekBarStyle.chapters:
        _paintChapters(canvas, size);
        break;
      case SeekBarStyle.dots:
        _paintDots(canvas, size);
        break;
      case SeekBarStyle.circular:
        _paintClassic(canvas, size);
        break;
      case SeekBarStyle.minimal:
        _paintMinimal(canvas, size);
        break;
    }
  }


  // Phase G4: Content Mood Timeline — 4 narrative zones on the track
  static const _moodColors = [
    Color(0x331E90FF), // 0–25%: calm/intro — blue
    Color(0x3332CD32), // 25–50%: rising action — green
    Color(0x33FF8C00), // 50–75%: tension — orange
    Color(0x33DC143C), // 75–100%: climax — crimson
  ];
  void _paintMoodZones(Canvas canvas, Size size) {
    if (!moodEnabled) return;
    final cy = size.height / 2;
    const trackH = 4.0;
    const zones = 4;
    final zw = size.width / zones;
    for (int z = 0; z < zones; z++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(z * zw, cy - trackH / 2, zw, trackH),
          const Radius.circular(2)),
        Paint()..color = _moodColors[z]);
    }
  }
  void _paintClassic(Canvas canvas, Size size) {
    _paintMoodZones(canvas, size); // G4
    final cy = size.height / 2;
    const trackH = 3.0;
    final rr = Radius.circular(trackH / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH), rr),
        Paint()..color = Colors.white24);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width * buffered.clamp(0.0, 1.0), trackH), rr),
        Paint()..color = Colors.white30);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width * progress.clamp(0.0, 1.0), trackH), rr),
        Paint()..color = accentColor);
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 7, Paint()..color = accentColor);
    canvas.drawCircle(Offset(tx, cy), 7,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  void _paintMaterialBold(Canvas canvas, Size size) {
    _paintMoodZones(canvas, size); // G4
    final cy = size.height / 2;
    const trackH = 8.0;
    final rr = Radius.circular(trackH / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH), rr),
        Paint()..color = Colors.white12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width * buffered.clamp(0.0, 1.0), trackH), rr),
        Paint()..color = Colors.white24);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width * progress.clamp(0.0, 1.0), trackH), rr),
        Paint()..color = accentColor);
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 10, Paint()..color = accentColor);
    canvas.drawCircle(Offset(tx, cy), 10,
        Paint()..color = accentColor.withOpacity(0.3)..strokeWidth = 6..style = PaintingStyle.stroke);
  }

  void _paintGradientGlow(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 5.0;
    final rr = Radius.circular(trackH / 2);
    final pw = size.width * progress.clamp(0.0, 1.0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH), rr),
        Paint()..color = Colors.white12);
    if (pw > 0) {
      final gradient = LinearGradient(colors: [gradientColor1, gradientColor2]);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, pw, trackH), rr),
          Paint()
            ..shader = gradient.createShader(Rect.fromLTWH(0, 0, pw, trackH))
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4));
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, pw, trackH), rr),
          Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, pw, trackH)));
    }
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 7, Paint()..color = gradientColor2);
    canvas.drawCircle(Offset(tx, cy), 10,
        Paint()..color = gradientColor2.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final maxAmpH = size.height * 0.42;
    const segW = 4.0;
    const gap = 1.5;
    final count = (size.width / (segW + gap)).floor();
    final amps = waveformAmplitudes.isNotEmpty ? waveformAmplitudes : _fakeAmps(count);
    final playedPaint = Paint()..color = accentColor;
    final unpPaint = Paint()..color = const Color(0x33FFFFFF);
    for (int i = 0; i < count && i < amps.length; i++) {
      final x = i * (segW + gap);
      final amp = amps[i].clamp(0.0, 1.0);
      final barH = math.max(2.0, amp * maxAmpH);
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, cy - barH / 2, segW, barH), const Radius.circular(2));
      canvas.drawRRect(rect, ((i + 0.5) / count) <= progress ? playedPaint : unpPaint);
    }
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 6, Paint()..color = accentColor);
  }

  List<double> _fakeAmps(int count) {
    final rng = math.Random(42);
    return List.generate(count, (_) => 0.2 + rng.nextDouble() * 0.8);
  }

  void _paintNeonRgb(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 5.0;
    final rr = Radius.circular(trackH / 2);
    final pw = size.width * progress.clamp(0.0, 1.0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH), rr),
        Paint()..color = Colors.white10);
    if (pw > 0) {
      final colors = List.generate(6, (i) {
        final hue = ((i / 5 + neonPhase) % 1.0) * 360;
        return HSVColor.fromAHSV(1, hue, 1, 1).toColor();
      });
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, pw, trackH), rr),
          Paint()
            ..shader = LinearGradient(colors: colors).createShader(Rect.fromLTWH(0, 0, pw, trackH))
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4));
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - trackH / 2, pw, trackH), rr),
          Paint()..shader = LinearGradient(colors: colors).createShader(Rect.fromLTWH(0, 0, pw, trackH)));
    }
    final tx = size.width * progress.clamp(0.0, 1.0);
    final thumbColor = HSVColor.fromAHSV(1, (neonPhase * 360) % 360, 1, 1).toColor();
    canvas.drawCircle(Offset(tx, cy), 7, Paint()..color = thumbColor);
    canvas.drawCircle(Offset(tx, cy), 10,
        Paint()..color = thumbColor.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  void _paintFilmstrip(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const segW = 14.0;
    const segH = 10.0;
    const gap = 2.0;
    final count = (size.width / (segW + gap)).floor();
    const rr = Radius.circular(2);
    for (int i = 0; i < count; i++) {
      final x = i * (segW + gap);
      final played = ((i + 0.5) / count) <= progress;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, cy - segH / 2, segW, segH), rr),
          Paint()..color = played ? accentColor.withOpacity(0.9) : Colors.white.withOpacity(0.1));
      canvas.drawCircle(Offset(x + segW / 2, cy - segH / 2 - 3), 1.5, Paint()..color = Colors.white24);
      canvas.drawCircle(Offset(x + segW / 2, cy + segH / 2 + 3), 1.5, Paint()..color = Colors.white24);
    }
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 6, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(tx, cy), 6, Paint()..color = accentColor..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  void _paintChapters(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 6.0;
    final boundaries = [0.0, ...chapterFractions, 1.0];
    const chapterColors = [
      Color(0xFFE8002D), Color(0xFF9C27B0), Color(0xFF2196F3),
      Color(0xFF4CAF50), Color(0xFFFF9800), Color(0xFF00BCD4),
      Color(0xFFFF4081), Color(0xFFFFD700),
    ];
    for (int i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      final x = start * size.width;
      final w = (end - start) * size.width;
      final col = chapterColors[i % chapterColors.length];
      const rr = Radius.circular(3);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, cy - trackH / 2, w - 2, trackH), rr),
          Paint()..color = Colors.white12);
      if (progress >= end) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, cy - trackH / 2, w - 2, trackH), rr),
            Paint()..color = col);
      } else if (progress > start && progress < end) {
        final pw = (progress - start) / (end - start) * (w - 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, cy - trackH / 2, pw, trackH), rr),
            Paint()..color = col);
      }
    }
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 8, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(tx, cy), 6, Paint()..color = accentColor);
  }

  void _paintDots(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const dotR = 3.0;
    const gap = 7.0;
    final count = (size.width / (dotR * 2 + gap)).floor();
    final tx = size.width * progress.clamp(0.0, 1.0);
    const thumbR = 7.0;
    for (int i = 0; i < count; i++) {
      final x = i * (dotR * 2 + gap) + dotR;
      if ((x - tx).abs() < thumbR + dotR) continue; // skip dots hidden under thumb
      final played = (i / count) <= progress;
      canvas.drawCircle(Offset(x, cy), played ? dotR : dotR * 0.6,
          Paint()..color = played ? accentColor : Colors.white24);
    }
    canvas.drawCircle(Offset(tx, cy), 7, Paint()..color = accentColor);
    canvas.drawCircle(Offset(tx, cy), 7,
        Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  void _paintMinimal(Canvas canvas, Size size) {
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy),
        Paint()..color = Colors.white.withOpacity(0.20)..strokeWidth = 1);
    canvas.drawLine(Offset(0, cy), Offset(size.width * progress.clamp(0.0, 1.0), cy),
        Paint()..color = accentColor..strokeWidth = 1);
    final tx = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(Offset(tx, cy), 4, Paint()..color = accentColor);
  }

  @override
  // L-02: also check chapterFractions and waveformAmplitudes — without these,
  // switching chapters or loading waveform data won't trigger a repaint unless
  // the playback position also changes.
  bool shouldRepaint(SeekBarPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.accentColor != accentColor ||
      old.neonPhase != neonPhase ||
      old.style != style ||
      old.chapterFractions.length != chapterFractions.length ||
      old.waveformAmplitudes.length != waveformAmplitudes.length ||
      !_listEqual(old.chapterFractions, chapterFractions) ||
      !_listEqual(old.waveformAmplitudes, waveformAmplitudes);

  static bool _listEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }
}

/// Preview widget for the seek bar style picker strip.
class SeekBarStylePreview extends StatelessWidget {
  final SeekBarStyle style;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  const SeekBarStylePreview({
    super.key,
    required this.style,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  static String labelOf(SeekBarStyle s) {
    switch (s) {
      case SeekBarStyle.classic:      return 'Classic';
      case SeekBarStyle.materialBold: return 'Bold';
      case SeekBarStyle.gradientGlow: return 'Gradient';
      case SeekBarStyle.waveform:     return 'Waveform';
      case SeekBarStyle.neonRgb:      return 'Neon RGB';
      case SeekBarStyle.filmstrip:    return 'Filmstrip';
      case SeekBarStyle.chapters:     return 'Chapters';
      case SeekBarStyle.dots:         return 'Dots';
      case SeekBarStyle.circular:     return 'Circular';
      case SeekBarStyle.minimal:      return 'Minimal';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 110,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: selected ? accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? accentColor : Colors.white12,
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              width: double.infinity,
              child: CustomPaint(
                painter: SeekBarPainter(
                  style: style,
                  progress: 0.45,
                  buffered: 0.65,
                  accentColor: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(labelOf(style),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
