import 'package:flutter/material.dart';
import '../../../core/player/player_prefs.dart';

/// Phase F1 — Dual Subtitle Overlay
/// Shows two subtitle tracks simultaneously — stacked vertically.
/// Primary subtitle (larger) below, secondary (smaller) above it.

class DualSubtitleOverlay extends StatelessWidget {
  final String primaryLine;
  final String secondaryLine;
  final PlayerPrefs prefs;

  const DualSubtitleOverlay({
    super.key,
    required this.primaryLine,
    required this.secondaryLine,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    if (primaryLine.isEmpty && secondaryLine.isEmpty) return const SizedBox.shrink();

    final textColor    = Color(prefs.subtitleTextColorValue);
    final outlineColor = Color(prefs.subtitleOutlineColorValue);
    final bgColor      = Color(prefs.subtitleBackgroundColorValue)
        .withOpacity(prefs.subtitleBackgroundOpacity);
    final fontSize     = prefs.subtitleFontSize;

    return Positioned(
      left: 8, right: 8,
      bottom: (MediaQuery.of(context).size.height * prefs.subtitleVerticalOffset)
          .clamp(48.0, 200.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Secondary track — smaller, slightly dimmer
          if (secondaryLine.isNotEmpty)
            _SubLine(
              text: secondaryLine,
              fontSize: (fontSize * 0.82).clamp(10, 22),
              textColor: textColor.withOpacity(0.75),
              outlineColor: outlineColor,
              bgColor: bgColor,
              bold: prefs.subtitleBold,
              italic: prefs.subtitleItalic,
              outline: prefs.subtitleOutlineThickness,
            ),
          if (secondaryLine.isNotEmpty && primaryLine.isNotEmpty)
            const SizedBox(height: 4),
          // Primary track — full size
          if (primaryLine.isNotEmpty)
            _SubLine(
              text: primaryLine,
              fontSize: fontSize,
              textColor: textColor,
              outlineColor: outlineColor,
              bgColor: bgColor,
              bold: prefs.subtitleBold,
              italic: prefs.subtitleItalic,
              outline: prefs.subtitleOutlineThickness,
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

  const _SubLine({
    required this.text, required this.fontSize,
    required this.textColor, required this.outlineColor, required this.bgColor,
    required this.bold, required this.italic, required this.outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: bgColor.opacity > 0
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: bgColor.opacity > 0 ? bgColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
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
        ),
      ),
    );
  }
}
