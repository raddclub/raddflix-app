// IDEA-06 — Subtitle Personality Engine
// Analyzes subtitle text and returns visual style adjustments based on
// content patterns. Pure Dart — no Flutter dependency.
//
// Patterns detected (priority order):
//   music       — ♪ ♫ 🎵 🎶       → gradient bg pill, italic
//   whisper     — [whispering] etc. → smaller + faded + italic
//   exclamation — ?! !! !?          → bold + scale-bounce (caller gates on tier)
//   ellipsis    — trailing … or ... → italic + faded
//   allCaps     — ≥75% uppercase    → bold + slightly larger
//   normal      — no pattern        → no adjustment

/// Type of personality pattern detected in a subtitle line.
enum SubtitlePersonalityType { normal, allCaps, ellipsis, whisper, exclamation, music }

/// Style adjustments produced by [SubtitlePersonality.analyze].
class SubtitlePersonalityResult {
  final SubtitlePersonalityType type;

  /// Multiplier applied to the base subtitle font size. Default 1.0.
  final double fontScale;

  /// Multiplier applied to text color opacity (0.0–1.0). Default 1.0.
  final double opacityMultiplier;

  /// When true, force italic regardless of the subtitle style setting.
  final bool forceItalic;

  /// When true, force bold regardless of the subtitle style setting.
  final bool forceBold;

  /// When true, the caller should trigger a scale-bounce animation.
  /// Gate this on device tier (basic+ only) in the calling widget.
  final bool useScaleBounce;

  /// When true, replace the solid background container with a gradient pill.
  final bool useGradientBg;

  const SubtitlePersonalityResult({
    required this.type,
    this.fontScale = 1.0,
    this.opacityMultiplier = 1.0,
    this.forceItalic = false,
    this.forceBold = false,
    this.useScaleBounce = false,
    this.useGradientBg = false,
  });

  /// No-op result — callers can skip all adjustments when isNormal is true.
  static const SubtitlePersonalityResult normal =
      SubtitlePersonalityResult(type: SubtitlePersonalityType.normal);

  bool get isNormal => type == SubtitlePersonalityType.normal;
}

/// IDEA-06: Subtitle Personality Engine.
///
/// Call [SubtitlePersonality.analyze] on every incoming subtitle line.
/// The returned [SubtitlePersonalityResult] describes what visual adjustments
/// the subtitle overlay should apply.
class SubtitlePersonality {
  SubtitlePersonality._();

  static final _musicRe = RegExp(r'[♪♫🎵🎶]');

  static final _whisperRe = RegExp(
    r'\[(whispering?|quietly?|softly?|murmurs?|mutters?|faintly?)\]'
    r'|\((whispering?|quietly?)\)',
    caseSensitive: false,
  );

  /// Analyze [line] and return visual style adjustments.
  ///
  /// [intensity] (0.0–1.0) scales effect strength:
  ///   • 0.0 → returns [SubtitlePersonalityResult.normal] (no effect)
  ///   • 1.0 → full adjustment as specified per pattern
  static SubtitlePersonalityResult analyze(String line, double intensity) {
    if (intensity <= 0.0 || line.trim().isEmpty) {
      return SubtitlePersonalityResult.normal;
    }

    final t = line.trim();
    final s = intensity.clamp(0.0, 1.0);

    // 1. Music — highest priority; the whole line feels musical.
    if (_musicRe.hasMatch(t)) {
      return const SubtitlePersonalityResult(
        type: SubtitlePersonalityType.music,
        useGradientBg: true,
        forceItalic: true,
      );
    }

    // 2. Whisper — shrink font + fade opacity + italic.
    if (_whisperRe.hasMatch(t)) {
      return SubtitlePersonalityResult(
        type: SubtitlePersonalityType.whisper,
        fontScale: 1.0 - (0.20 * s),
        opacityMultiplier: 1.0 - (0.40 * s),
        forceItalic: true,
      );
    }

    // 3. Exclamation — bold + caller-triggered scale-bounce.
    if (_isExclamation(t)) {
      return SubtitlePersonalityResult(
        type: SubtitlePersonalityType.exclamation,
        fontScale: 1.0 + (0.08 * s),
        forceBold: true,
        useScaleBounce: true,
      );
    }

    // 4. Ellipsis — italic + fade.
    if (t.endsWith('...') || t.endsWith('…')) {
      return SubtitlePersonalityResult(
        type: SubtitlePersonalityType.ellipsis,
        opacityMultiplier: 1.0 - (0.30 * s),
        forceItalic: true,
      );
    }

    // 5. ALL CAPS — bold + slightly larger.
    if (_isAllCaps(t)) {
      return SubtitlePersonalityResult(
        type: SubtitlePersonalityType.allCaps,
        fontScale: 1.0 + (0.10 * s),
        forceBold: true,
      );
    }

    return SubtitlePersonalityResult.normal;
  }

  static bool _isExclamation(String t) =>
      t.endsWith('?!') || t.endsWith('!?') ||
      t.endsWith('!!') || t.endsWith('!!!');

  static bool _isAllCaps(String t) {
    // Need ≥4 alphabetic chars to avoid false-positives on short lines like "OK" or "I".
    final alpha = t.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (alpha.length < 4) return false;
    int upper = 0;
    for (final rune in alpha.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) upper++;
    }
    return upper / alpha.length >= 0.75;
  }
}
