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
/// Phase F2: each word is individually tappable — shows offline Urdu dictionary.
class SubtitleOverlay extends StatefulWidget {
  final String? currentLine;
  final PlayerPrefs prefs;

  const SubtitleOverlay({
    super.key,
    required this.currentLine,
    required this.prefs,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  String? _tappedWord;

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
    await showWordDefinition(
      ctx, word,
      accentColor: widget.prefs.accentColor,
    );
    if (mounted) setState(() => _tappedWord = null);
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
        Shadow(offset: Offset( outline,  outline), blurRadius: outline * 2, color: outlineColor),
        Shadow(offset: Offset(-outline, -outline), blurRadius: outline * 2, color: outlineColor),
        Shadow(offset: Offset( outline, -outline), blurRadius: outline * 2, color: outlineColor),
        Shadow(offset: Offset(-outline,  outline), blurRadius: outline * 2, color: outlineColor),
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
    );
  }

  /// Splits the subtitle line into tokens (words + spaces/punctuation) and
  /// wraps each word in a [GestureDetector]. Punctuation is rendered inline
  /// without any tap target.
  Widget _buildTappableText(BuildContext ctx, String line, TextStyle style) {
    // Split into tokens: words and non-word characters
    final tokens = <String>[];
    final re = RegExp(r"[\w']+|[^\w']+");
    for (final m in re.allMatches(line)) {
      tokens.add(m.group(0)!);
    }

    return Wrap(
      alignment: WrapAlignment.center,
      children: tokens.map((token) {
        final isWord = RegExp(r"^[\w']+$").hasMatch(token);
        if (!isWord) {
          // Punctuation / spaces — render as-is
          return Text(token, style: style);
        }
        final inDict = WordDict.instance.contains(token);
        final isHighlighted = _tappedWord == token;
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
                // Underline words that exist in dictionary (subtle dotted)
                decoration: inDict && !isHighlighted
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: widget.prefs.accentColor.withOpacity(0.55),
                decorationStyle: TextDecorationStyle.dotted,
                // Highlight color on tap
                color: isHighlighted
                    ? Colors.white
                    : style.color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
