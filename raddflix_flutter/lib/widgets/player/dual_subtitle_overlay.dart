import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';
import '../../core/player/word_dict.dart';
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

  const DualSubtitleOverlay({
    super.key,
    required this.primaryLine,
    required this.secondaryLine,
    required this.prefs,
    this.onPausedForLookup,
    this.onResumedAfterLookup,
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
    if (widget.primaryLine.isEmpty && widget.secondaryLine.isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor    = Color(widget.prefs.subtitleTextColorValue);
    final outlineColor = Color(widget.prefs.subtitleOutlineColorValue);
    final bgColor      = Color(widget.prefs.subtitleBackgroundColorValue)
        .withOpacity(widget.prefs.subtitleBackgroundOpacity);
    final fontSize     = widget.prefs.subtitleFontSize;
    final outline      = widget.prefs.subtitleOutlineThickness;

    return Positioned(
      left: 8, right: 8,
      bottom: (MediaQuery.of(context).size.height * widget.prefs.subtitleVerticalOffset)
          .clamp(48.0, 200.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Secondary track — smaller, slightly dimmer
          if (widget.secondaryLine.isNotEmpty)
            _SubLine(
              text: widget.secondaryLine,
              fontSize: (fontSize * 0.82).clamp(10, 22),
              textColor: textColor.withOpacity(0.75),
              outlineColor: outlineColor,
              bgColor: bgColor,
              bold: widget.prefs.subtitleBold,
              italic: widget.prefs.subtitleItalic,
              outline: outline,
              dictEnabled: widget.prefs.dictEnabled,
              accentColor: widget.prefs.accentColor,
              tappedWord: _tappedWord,
              onWordTap: (word) => _onWordTap(context, word, widget.secondaryLine),
            ),
          if (widget.secondaryLine.isNotEmpty && widget.primaryLine.isNotEmpty)
            const SizedBox(height: 4),
          // Primary track — full size
          if (widget.primaryLine.isNotEmpty)
            _SubLine(
              text: widget.primaryLine,
              fontSize: fontSize,
              textColor: textColor,
              outlineColor: outlineColor,
              bgColor: bgColor,
              bold: widget.prefs.subtitleBold,
              italic: widget.prefs.subtitleItalic,
              outline: outline,
              dictEnabled: widget.prefs.dictEnabled,
              accentColor: widget.prefs.accentColor,
              tappedWord: _tappedWord,
              onWordTap: (word) => _onWordTap(context, word, widget.primaryLine),
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

  static final _reTokenize = RegExp(r"[\w']+|[^\w']+");
  static final _reWord     = RegExp(r"^[\w']+$");

  const _SubLine({
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
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
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
