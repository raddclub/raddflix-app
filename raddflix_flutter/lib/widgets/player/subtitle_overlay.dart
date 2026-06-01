import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // J3: Lexend dyslexia-friendly font
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';

/// Custom subtitle overlay rendered entirely from PlayerPrefs styles.
/// The MPV subtitle track is set invisible via SubtitleViewConfiguration(visible:false)
/// so we control every style property: font, size, bold, italic, colors, position, outline.
class SubtitleOverlay extends StatelessWidget {
  final String? currentLine;
  final PlayerPrefs prefs;

  const SubtitleOverlay({
    super.key,
    required this.currentLine,
    required this.prefs,
  });

  Alignment get _alignment {
    switch (prefs.subtitlePosition) {
      case 'top':    return Alignment.topCenter;
      case 'center': return Alignment.center;
      default:       return Alignment.bottomCenter;
    }
  }

  EdgeInsets get _padding {
    final offset = prefs.subtitleVerticalOffset * 60;
    switch (prefs.subtitlePosition) {
      case 'top':    return EdgeInsets.only(top: 20.0 + offset.abs());
      case 'center': return EdgeInsets.zero;
      default:       return EdgeInsets.only(bottom: 80.0 + offset.abs());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentLine == null || currentLine!.isEmpty) return const SizedBox.shrink();

    final textColor   = Color(prefs.subtitleTextColorValue);
    final outlineColor = Color(prefs.subtitleOutlineColorValue);
    final bgColor     = Color(prefs.subtitleBackgroundColorValue)
        .withOpacity(prefs.subtitleBackgroundOpacity);
    final outline     = prefs.subtitleOutlineThickness;

    return Positioned.fill(
      child: Align(
        alignment: _alignment,
        child: Padding(
          padding: _padding,
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: currentLine!));
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
              child: Text(
                currentLine!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: prefs.subtitleFontSize,
                  fontFamily: (prefs.subtitleFontFamily == 'Sans-Serif' ||
                      prefs.subtitleFontFamily == 'Sans Serif' ||
                      prefs.subtitleFontFamily == 'Default')
                    ? null
                    : prefs.subtitleFontFamily == 'Lexend'
                        ? GoogleFonts.lexend().fontFamily
                        : prefs.subtitleFontFamily,
                  color: textColor,
                  fontWeight: prefs.subtitleBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: prefs.subtitleItalic ? FontStyle.italic : FontStyle.normal,
                  shadows: outline > 0 ? [
                    Shadow(offset: Offset( outline,  outline), blurRadius: outline * 2, color: outlineColor),
                    Shadow(offset: Offset(-outline, -outline), blurRadius: outline * 2, color: outlineColor),
                    Shadow(offset: Offset( outline, -outline), blurRadius: outline * 2, color: outlineColor),
                    Shadow(offset: Offset(-outline,  outline), blurRadius: outline * 2, color: outlineColor),
                  ] : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
