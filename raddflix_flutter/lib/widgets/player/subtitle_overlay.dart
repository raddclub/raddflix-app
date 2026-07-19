import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // J3: Lexend dyslexia-friendly font
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';
import '../../core/player/word_dict.dart';
import '../player/word_definition_sheet.dart';

/// Custom subtitle overlay rendered entirely from PlayerPrefs styles.
/// The MPV subtitle track is set invisible via SubtitleViewConfiguration(visible:false)
/// so we control every style property: font, size, bold, italic, colors, position, outline.
///
/// Phase F2 / BB10: each word is individually tappable — shows dictionary lookup.
/// Video pauses on tap, resumes 800ms after the sheet is dismissed.
class SubtitleOverlay extends StatefulWidget {
  final String? currentLine;
  final PlayerPrefs prefs;

  /// Called when a word is tapped and the definition sheet opens.
  /// Implementations should pause the player.
  final VoidCallback? onPausedForLookup;

  /// Called 800ms after the definition sheet is dismissed.
  /// Implementations should resume the player.
  final VoidCallback? onResumedAfterLookup;

  const SubtitleOverlay({
    super.key,
    required this.currentLine,
    required this.prefs,
    this.onPausedForLookup,
    this.onResumedAfterLookup,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  String? _tappedWord;

  static final _reTokenize = RegExp(r"[\w']+|[^\w']+");
  static final _reWord     = RegExp(r"^[\w']+$");

  Alignment get _alignment {
    switch (widget.prefs.subtitlePosition) {
      case 'top':    return Alignment.topCenter;
      case 'center': return Alignment.center;
      default:       return Alignment.bottomCenter;
    }
  }

  EdgeInsets get _padding {
    final offset = widget.prefs.subtitleVerticalOffset * 60;
    switch (widget.prefs.subtitlePosition) {
      case 'top':    return EdgeInsets.only(top: 20.0 + offset.abs());
      case 'center': return EdgeInsets.zero;
      default:       return EdgeInsets.only(bottom: 80.0 + offset.abs());
    }
  }

  void _onWordTap(BuildContext ctx, String word) async {
    if (!widget.prefs.dictEnabled) return;
    // Briefly highlight the tapped word
    setState(() => _tappedWord = word);
    HapticFeedback.selectionClick();

    // Pause video so user can read without rushing.
    widget.onPausedForLookup?.call();

    // Resolve dict target language (added in BB10 to PlayerPrefs).
    // Falls back to 'ur' if the field is not yet present on this install.
    final targetLang = _dictTargetLanguage;

    await showWordDefinition(
      ctx, word,
      accentColor: widget.prefs.accentColor,
      contextLine: widget.currentLine ?? '',
      dictTargetLanguage: targetLang,
    );

    if (mounted) setState(() => _tappedWord = null);

    // Resume 800ms after dismiss so user can re-read the subtitle.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) widget.onResumedAfterLookup?.call();
    });
  }

  /// Safe accessor: reads dictTargetLanguage via dynamic cast so it compiles
  /// even on existing installs where the field may not yet exist on the prefs
  /// object (before a hot-restart).
  String get _dictTargetLanguage {
    try {
      // ignore: avoid_dynamic_calls
      return (widget.prefs as dynamic).dictTargetLanguage as String? ?? 'ur';
    } catch (_) {
      return 'ur';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentLine == null || widget.currentLine!.isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor    = Color(widget.prefs.subtitleTextColorValue);
    final outlineColor = Color(widget.prefs.subtitleOutlineColorValue);
    final bgColor      = Color(widget.prefs.subtitleBackgroundColorValue)
        .withOpacity(widget.prefs.subtitleBackgroundOpacity);
    final outline = widget.prefs.subtitleOutlineThickness;

    final baseStyle = TextStyle(
      fontSize:   widget.prefs.subtitleFontSize,
      fontFamily: (widget.prefs.subtitleFontFamily == 'Sans-Serif' ||
              widget.prefs.subtitleFontFamily == 'Sans Serif' ||
              widget.prefs.subtitleFontFamily == 'Default')
          ? null
          : widget.prefs.subtitleFontFamily == 'Lexend'
              ? GoogleFonts.lexend().fontFamily
              : widget.prefs.subtitleFontFamily,
      color:      textColor,
      fontWeight: widget.prefs.subtitleBold ? FontWeight.bold : FontWeight.normal,
      fontStyle:  widget.prefs.subtitleItalic ? FontStyle.italic : FontStyle.normal,
      shadows: outline > 0 ? [
        Shadow(offset: Offset( outline / 2,  outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset(-outline / 2, -outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset( outline / 2, -outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset(-outline / 2,  outline / 2), blurRadius: outline, color: outlineColor),
      ] : null,
    );

    return Positioned.fill(
      child: Align(
        alignment: _alignment,
        child: Padding(
          padding: _padding,
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: widget.currentLine!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: bgColor.opacity > 0.02
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              // BB8: crossfade when subtitle line changes — 150ms FadeTransition.
              // KeyedSubtree provides the key without changing _buildTappableText.
              // Tier-gate: AnimatedSwitcher is lightweight — safe on all tiers.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(widget.currentLine),
                  child: widget.prefs.dictEnabled
                      ? _buildTappableText(context, widget.currentLine!, baseStyle)
                      : Text(
                          widget.currentLine!,
                          textAlign: TextAlign.center,
                          style: baseStyle,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Splits the subtitle line into tokens (words + spaces/punctuation) and
  /// wraps each word in a [GestureDetector]. Punctuation is rendered inline
  /// without any tap target.
  ///
  /// BB10: solid underline for saved words; dotted underline for known-but-not-saved.
  Widget _buildTappableText(BuildContext ctx, String line, TextStyle style) {
    final tokens = <String>[];
    for (final m in _reTokenize.allMatches(line)) {
      tokens.add(m.group(0)!);
    }

    return Wrap(
      alignment: WrapAlignment.center,
      children: tokens.map((token) {
        final isWord = _reWord.hasMatch(token);
        if (!isWord) {
          return Text(token, style: style);
        }

        final inDict  = WordDict.instance.contains(token) ||
                        WordDict.instance.hasOnlineCacheHit(token);
        final isSaved = WordDict.instance.isSaved(token);
        final isHighlighted = _tappedWord == token;

        TextDecoration decoration = TextDecoration.none;
        TextDecorationStyle decorationStyle = TextDecorationStyle.dotted;
        double decorationThickness = 1.0;

        if (!isHighlighted && inDict) {
          decoration = TextDecoration.underline;
          if (isSaved) {
            // Solid, thicker underline for saved words — visible progress marker.
            decorationStyle = TextDecorationStyle.solid;
            decorationThickness = 2.5;
          } else {
            // Subtle dotted underline for known-but-not-saved words.
            decorationStyle = TextDecorationStyle.dotted;
            decorationThickness = 1.0;
          }
        }

        return GestureDetector(
          onTap: () => _onWordTap(ctx, token),
          child: Container(
            decoration: isHighlighted
                ? BoxDecoration(
                    color: widget.prefs.accentColor.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(3))
                : null,
            child: Text(
              token,
              style: style.copyWith(
                decoration: decoration,
                decorationColor: widget.prefs.accentColor
                    .withOpacity(isSaved ? 0.85 : 0.55),
                decorationStyle: decorationStyle,
                decorationThickness: decorationThickness,
                color: isHighlighted ? Colors.white : style.color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
