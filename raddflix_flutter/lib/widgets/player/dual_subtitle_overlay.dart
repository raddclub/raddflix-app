import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // SUB-G3: Phase B font resolution
import '../../core/player/player_prefs.dart';
import '../../core/player/word_dict.dart';
import '../../core/player/subtitle_personality.dart'; // IDEA-06
import '../../core/player/phonetic_subtitle.dart';    // IDEA-08
import 'word_definition_sheet.dart';

/// Phase F1 — Dual Subtitle Overlay
/// Shows two subtitle tracks simultaneously — stacked vertically.
/// Primary subtitle (larger) below, secondary (smaller) above it.
///
/// BB10: both lines support word-tap dictionary lookup.

class DualSubtitleOverlay extends StatefulWidget {
  final String primaryLine;
  final String secondaryLine;
  final PlayerPrefs prefs;

  /// Called when a word is tapped and the definition sheet opens.
  final VoidCallback? onPausedForLookup;

  /// Called 800ms after the definition sheet is dismissed.
  final VoidCallback? onResumedAfterLookup;

  /// SUB-G2: raise both tracks above controls bar when controls are visible.
  /// Pass `_showControls ? 120.0 : 0.0` from the player.
  final double controlsRaiseDp;

  const DualSubtitleOverlay({
    super.key,
    required this.primaryLine,
    required this.secondaryLine,
    required this.prefs,
    this.onPausedForLookup,
    this.onResumedAfterLookup,
    this.controlsRaiseDp = 0,
  });

  @override
  State<DualSubtitleOverlay> createState() => _DualSubtitleOverlayState();
}

class _DualSubtitleOverlayState extends State<DualSubtitleOverlay> {
  String? _tappedWord;

  static final _reTokenize = RegExp(r"[\w']+|[^\w']+");
  static final _reWord     = RegExp(r"^[\w']+$");

  void _onWordTap(BuildContext ctx, String word, String contextLine) async {
    if (!widget.prefs.dictEnabled) return;
    setState(() => _tappedWord = word);
    HapticFeedback.selectionClick();

    widget.onPausedForLookup?.call();

    String targetLang = 'ur';
    try {
      // ignore: avoid_dynamic_calls
      targetLang = (widget.prefs as dynamic).dictTargetLanguage as String? ?? 'ur';
    } catch (_) {}

    await showWordDefinition(
      ctx, word,
      accentColor: widget.prefs.accentColor,
      contextLine: contextLine,
      dictTargetLanguage: targetLang,
    );

    if (mounted) setState(() => _tappedWord = null);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) widget.onResumedAfterLookup?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.primaryLine.trim().isEmpty && widget.secondaryLine.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor    = Color(widget.prefs.subtitleTextColorValue);
    final outlineColor = Color(widget.prefs.subtitleOutlineColorValue);
    final bgColor      = Color(widget.prefs.subtitleBackgroundColorValue)
        .withOpacity(widget.prefs.subtitleBackgroundOpacity);
    final fontSize     = widget.prefs.subtitleFontSize;
    final outline      = widget.prefs.subtitleOutlineThickness;

    // IDEA-06: apply personality style adjustments to each line independently.
    // Scale-bounce is skipped in dual mode (both lines animating simultaneously
    // would look chaotic). Gradient bg is approximated with accent tint.
    SubtitlePersonalityResult priP = SubtitlePersonalityResult.normal;
    SubtitlePersonalityResult secP = SubtitlePersonalityResult.normal;
    if (widget.prefs.subtitlePersonalityEnabled) {
      final intensity = widget.prefs.subtitlePersonalityIntensity;
      if (widget.primaryLine.trim().isNotEmpty) {
        priP = SubtitlePersonality.analyze(widget.primaryLine, intensity);
      }
      if (widget.secondaryLine.trim().isNotEmpty) {
        secP = SubtitlePersonality.analyze(widget.secondaryLine, intensity);
      }
    }

    // IDEA-08: offline phonetic overlay for Arabic/Devanagari lines.
    String? priPhonetic;
    String? secPhonetic;
    if (widget.prefs.phoneticOverlayEnabled) {
      if (widget.primaryLine.trim().isNotEmpty) {
        final r = PhoneticSubtitle.romanize(widget.primaryLine);
        if (r.isNotEmpty) priPhonetic = r;
      }
      if (widget.secondaryLine.trim().isNotEmpty) {
        final r = PhoneticSubtitle.romanize(widget.secondaryLine);
        if (r.isNotEmpty) secPhonetic = r;
      }
    }
    TextStyle _phoneticStyle(double baseFontSize, Color baseColor) =>
        TextStyle(
          fontSize: baseFontSize * widget.prefs.phoneticOverlayFontScale,
          fontStyle: FontStyle.italic,
          color: baseColor.withOpacity(
              ((baseColor.alpha / 255.0) * 0.80).clamp(0.0, 1.0)),
          height: 1.2,
        );

    // Helper: compute per-line values from a personality result.
    Color _resolveColor(Color base, SubtitlePersonalityResult p) =>
        p.opacityMultiplier < 1.0
            ? base.withOpacity(((base.alpha / 255.0) * p.opacityMultiplier).clamp(0.0, 1.0))
            : base;

    // Music lines: use accent-tinted bg as gradient approximation in dual mode.
    Color _resolveBg(Color base, SubtitlePersonalityResult p) =>
        p.useGradientBg
            ? widget.prefs.accentColor.withOpacity(0.28)
            : base;

    // SUB-G3: resolve font family from PlayerPrefs — mirrors SubtitleOverlay._resolvedFontFamily
    String? resolvedFontFamily;
    switch (widget.prefs.subtitleFont) {
      case 'atkinson':
        resolvedFontFamily = GoogleFonts.atkinsonHyperlegible().fontFamily;
        break;
      case 'lexie_readable':
        resolvedFontFamily = GoogleFonts.lexend().fontFamily;
        break;
      case 'roboto':
        resolvedFontFamily = GoogleFonts.roboto().fontFamily;
        break;
      default:
        final fam = widget.prefs.subtitleFontFamily;
        if (fam == 'Sans-Serif' || fam == 'Sans Serif' || fam == 'Default') {
          resolvedFontFamily = null;
        } else if (fam == 'Lexend') {
          resolvedFontFamily = GoogleFonts.lexend().fontFamily;
        } else {
          resolvedFontFamily = fam;
        }
    }

    return Positioned(
      left: 8, right: 8,
      // SUB-G2: raise above seekbar/controls when visible, same as SubtitleOverlay.
      bottom: (MediaQuery.of(context).size.height * widget.prefs.subtitleVerticalOffset)
          .clamp(48.0, 200.0) + widget.controlsRaiseDp,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Secondary track — smaller, slightly dimmer
          // BB8: AnimatedSwitcher wraps each track so line transitions crossfade.
          if (widget.secondaryLine.trim().isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Column(
                key: ValueKey('sec_${widget.secondaryLine}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SubLine(
                    text: widget.secondaryLine,
                    fontSize: ((fontSize * 0.82) * secP.fontScale).clamp(10, 22),
                    textColor: _resolveColor(textColor.withOpacity(0.75), secP),
                    outlineColor: outlineColor,
                    bgColor: _resolveBg(bgColor, secP),
                    bold: secP.forceBold || widget.prefs.subtitleBold,
                    italic: secP.forceItalic || widget.prefs.subtitleItalic,
                    outline: outline,
                    dictEnabled: widget.prefs.dictEnabled,
                    accentColor: widget.prefs.accentColor,
                    tappedWord: _tappedWord,
                    onWordTap: (word) => _onWordTap(context, word, widget.secondaryLine),
                    fontFamily: resolvedFontFamily, // SUB-G3
                  ),
                  // IDEA-08: phonetic row below secondary line (if applicable).
                  if (secPhonetic != null) ...[
                    const SizedBox(height: 1),
                    Text(secPhonetic, textAlign: TextAlign.center,
                        style: _phoneticStyle(
                            (fontSize * 0.82).clamp(10, 22),
                            textColor.withOpacity(0.75))),
                  ],
                ],
              ),
            ),
          if (widget.secondaryLine.trim().isNotEmpty && widget.primaryLine.trim().isNotEmpty)
            const SizedBox(height: 4),
          // Primary track — full size
          if (widget.primaryLine.trim().isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Column(
                key: ValueKey('pri_${widget.primaryLine}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SubLine(
                    text: widget.primaryLine,
                    fontSize: fontSize * priP.fontScale,
                    textColor: _resolveColor(textColor, priP),
                    outlineColor: outlineColor,
                    bgColor: _resolveBg(bgColor, priP),
                    bold: priP.forceBold || widget.prefs.subtitleBold,
                    italic: priP.forceItalic || widget.prefs.subtitleItalic,
                    outline: outline,
                    dictEnabled: widget.prefs.dictEnabled,
                    accentColor: widget.prefs.accentColor,
                    tappedWord: _tappedWord,
                    onWordTap: (word) => _onWordTap(context, word, widget.primaryLine),
                    fontFamily: resolvedFontFamily, // SUB-G3
                  ),
                  // IDEA-08: phonetic row below primary line (if applicable).
                  if (priPhonetic != null) ...[
                    const SizedBox(height: 2),
                    Text(priPhonetic, textAlign: TextAlign.center,
                        style: _phoneticStyle(fontSize, textColor)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubLine extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color textColor, outlineColor, bgColor;
  final bool bold, italic;
  final double outline;
  final bool dictEnabled;
  final Color accentColor;
  final String? tappedWord;
  final void Function(String)? onWordTap;
  // SUB-G3: resolved font family from PlayerPrefs (null = system default)
  final String? fontFamily;

  static final _reTokenize = RegExp(r"[\w']+|[^\w']+");
  static final _reWord     = RegExp(r"^[\w']+$");

  // BB8: super.key so AnimatedSwitcher can key on line changes for crossfade.
  const _SubLine({
    super.key,
    required this.text,
    required this.fontSize,
    required this.textColor,
    required this.outlineColor,
    required this.bgColor,
    required this.bold,
    required this.italic,
    required this.outline,
    this.dictEnabled = false,
    required this.accentColor,
    this.tappedWord,
    this.onWordTap,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontFamily: fontFamily, // SUB-G3
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: 1.3,
      shadows: outline > 0
          ? [
              Shadow(color: outlineColor, offset: Offset(-outline / 2, -outline / 2), blurRadius: outline),
              Shadow(color: outlineColor, offset: Offset(outline / 2, -outline / 2), blurRadius: outline),
              Shadow(color: outlineColor, offset: Offset(-outline / 2, outline / 2), blurRadius: outline),
              Shadow(color: outlineColor, offset: Offset(outline / 2, outline / 2), blurRadius: outline),
            ]
          : null,
    );

    return Container(
      padding: bgColor.opacity > 0
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: bgColor.opacity > 0 ? bgColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: dictEnabled
          ? _buildTappable(baseStyle)
          : Text(text, textAlign: TextAlign.center, style: baseStyle),
    );
  }

  Widget _buildTappable(TextStyle style) {
    final tokens = <String>[];
    for (final m in _reTokenize.allMatches(text)) {
      tokens.add(m.group(0)!);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      children: tokens.map((token) {
        final isWord = _reWord.hasMatch(token);
        if (!isWord) return Text(token, style: style);

        final inDict  = WordDict.instance.contains(token) ||
                        WordDict.instance.hasOnlineCacheHit(token);
        final isSaved = WordDict.instance.isSaved(token);
        final isHL    = tappedWord == token;

        TextDecoration decoration = TextDecoration.none;
        TextDecorationStyle decorationStyle = TextDecorationStyle.dotted;
        double decorationThickness = 1.0;
        if (!isHL && inDict) {
          decoration = TextDecoration.underline;
          if (isSaved) {
            decorationStyle = TextDecorationStyle.solid;
            decorationThickness = 2.5;
          }
        }

        return GestureDetector(
          onTap: () { if (onWordTap != null) onWordTap!(token); },
          child: Container(
            decoration: isHL
                ? BoxDecoration(
                    color: accentColor.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(3))
                : null,
            child: Text(
              token,
              style: style.copyWith(
                decoration: decoration,
                decorationColor: accentColor.withOpacity(isSaved ? 0.85 : 0.55),
                decorationStyle: decorationStyle,
                decorationThickness: decorationThickness,
                color: isHL ? Colors.white : style.color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
