/// Phase F1 — Dual Subtitle Display
/// Two subtitle tracks shown simultaneously (one above the other).
/// F2 — Word Dictionary already done (word_dict.dart)
/// F3 — Subtitle Style Customisation (size, colour, background, shadow, outline)
/// F4 — Subtitle Timing Debug Mode (show start/end times next to each line)
library f_series;

import 'package:flutter/material.dart';
import '../core/player/dyslexia_subtitle_style.dart'; // J3

// ─────────────────────────────────────────────────────────────────────────────
// F1 — Dual Subtitle Display
// ─────────────────────────────────────────────────────────────────────────────

/// Displays two subtitle tracks stacked: primary (bottom) and secondary (above).
/// The secondary track is rendered at 85% size and 70% opacity.
class DualSubtitleOverlay extends StatelessWidget {
  final String? primaryText;
  final String? secondaryText;
  final SubtitleFont font;
  final double primaryFontSize;
  final Color primaryColor;
  final Color secondaryColor;
  final bool showBackground;
  final bool timingDebug;
  final Duration? primaryStart;
  final Duration? primaryEnd;

  const DualSubtitleOverlay({
    super.key,
    this.primaryText,
    this.secondaryText,
    this.font           = SubtitleFont.system,
    this.primaryFontSize = 18.0,
    this.primaryColor   = Colors.white,
    this.secondaryColor = const Color(0xFFFFDB58), // yellow
    this.showBackground = false,
    this.timingDebug    = false,
    this.primaryStart,
    this.primaryEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (primaryText == null && secondaryText == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Secondary subtitle (translated / second language)
        if (secondaryText != null)
          _SubLine(
            text: secondaryText!,
            style: subtitleTextStyle(
              font: font,
              fontSize: primaryFontSize * 0.82,
              color: secondaryColor,
              lineHeight: 1.3,
            ),
            showBg: showBackground,
          ),
        if (secondaryText != null && primaryText != null)
          const SizedBox(height: 4),
        // Primary subtitle
        if (primaryText != null) ...[
          _SubLine(
            text: primaryText!,
            style: subtitleTextStyle(
              font: font,
              fontSize: primaryFontSize,
              color: primaryColor,
            ),
            showBg: showBackground,
          ),
          // F4: timing debug
          if (timingDebug && primaryStart != null && primaryEnd != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${_fmt(primaryStart!)} → ${_fmt(primaryEnd!)}',
                style: const TextStyle(
                    color: Colors.orangeAccent, fontSize: 9.5,
                    fontFamily: 'monospace'),
              ),
            ),
        ],
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s.$ms' : '$m:$s.$ms';
  }
}

class _SubLine extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool showBg;

  const _SubLine({required this.text, required this.style, required this.showBg});

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      textAlign: TextAlign.center,
      style: style,
    );
    if (!showBg) return child;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// F3 — Subtitle Style Customisation
// ─────────────────────────────────────────────────────────────────────────────

class SubtitleStyle {
  final double fontSize;
  final Color color;
  final bool boldText;
  final bool showBackground;
  final double backgroundOpacity;
  final bool showOutline;
  final double outlineWidth;
  final Color outlineColor;
  final double shadowBlur;

  const SubtitleStyle({
    this.fontSize          = 18.0,
    this.color             = Colors.white,
    this.boldText          = false,
    this.showBackground    = false,
    this.backgroundOpacity = 0.6,
    this.showOutline       = false,
    this.outlineWidth      = 2.0,
    this.outlineColor      = Colors.black,
    this.shadowBlur        = 4.0,
  });

  SubtitleStyle copyWith({
    double? fontSize, Color? color, bool? boldText, bool? showBackground,
    double? backgroundOpacity, bool? showOutline, double? outlineWidth,
    Color? outlineColor, double? shadowBlur,
  }) => SubtitleStyle(
    fontSize:          fontSize          ?? this.fontSize,
    color:             color             ?? this.color,
    boldText:          boldText          ?? this.boldText,
    showBackground:    showBackground    ?? this.showBackground,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    showOutline:       showOutline       ?? this.showOutline,
    outlineWidth:      outlineWidth      ?? this.outlineWidth,
    outlineColor:      outlineColor      ?? this.outlineColor,
    shadowBlur:        shadowBlur        ?? this.shadowBlur,
  );

  String encode() =>
      '${fontSize.toStringAsFixed(1)}|'
      '${color.value}|${boldText ? 1 : 0}|'
      '${showBackground ? 1 : 0}|${backgroundOpacity.toStringAsFixed(2)}|'
      '${showOutline ? 1 : 0}|${outlineWidth.toStringAsFixed(1)}|'
      '${outlineColor.value}|${shadowBlur.toStringAsFixed(1)}';

  factory SubtitleStyle.decode(String s) {
    final p = s.split('|');
    if (p.length < 9) return const SubtitleStyle();
    return SubtitleStyle(
      fontSize:          double.tryParse(p[0]) ?? 18.0,
      color:             Color(int.tryParse(p[1]) ?? 0xFFFFFFFF),
      boldText:          p[2] == '1',
      showBackground:    p[3] == '1',
      backgroundOpacity: double.tryParse(p[4]) ?? 0.6,
      showOutline:       p[5] == '1',
      outlineWidth:      double.tryParse(p[6]) ?? 2.0,
      outlineColor:      Color(int.tryParse(p[7]) ?? 0xFF000000),
      shadowBlur:        double.tryParse(p[8]) ?? 4.0,
    );
  }

  TextStyle toTextStyle({SubtitleFont font = SubtitleFont.system}) {
    return subtitleTextStyle(
      font: font,
      fontSize: fontSize,
      color: color,
    ).copyWith(
      fontWeight: boldText ? FontWeight.bold : FontWeight.w400,
      shadows: [
        if (shadowBlur > 0)
          Shadow(color: Colors.black, blurRadius: shadowBlur, offset: const Offset(1, 1)),
        if (showOutline) ...[
          Shadow(color: outlineColor, blurRadius: 0, offset: Offset(-outlineWidth, -outlineWidth)),
          Shadow(color: outlineColor, blurRadius: 0, offset: Offset(outlineWidth, -outlineWidth)),
          Shadow(color: outlineColor, blurRadius: 0, offset: Offset(-outlineWidth, outlineWidth)),
          Shadow(color: outlineColor, blurRadius: 0, offset: Offset(outlineWidth, outlineWidth)),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// F3 — Subtitle Style Panel (QSP widget)
// ─────────────────────────────────────────────────────────────────────────────
class SubtitleStylePanel extends StatelessWidget {
  final SubtitleStyle style;
  final ValueChanged<SubtitleStyle> onChanged;
  final Color accentColor;

  const SubtitleStylePanel({
    super.key,
    required this.style,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Font size
      _row('Font Size', '${style.fontSize.toInt()}',
          Slider(
            value: style.fontSize,
            min: 10, max: 36,
            divisions: 26,
            activeColor: accentColor,
            inactiveColor: Colors.white12,
            onChanged: (v) => onChanged(style.copyWith(fontSize: v)),
          )),
      // Bold
      _toggle('Bold Subtitles', style.boldText,
          (v) => onChanged(style.copyWith(boldText: v))),
      const Divider(color: Colors.white10, height: 1),
      // Background
      _toggle('Background Box', style.showBackground,
          (v) => onChanged(style.copyWith(showBackground: v))),
      if (style.showBackground)
        _row('Background Opacity', '${(style.backgroundOpacity * 100).toInt()}%',
            Slider(
              value: style.backgroundOpacity,
              min: 0.1, max: 1.0,
              activeColor: accentColor,
              inactiveColor: Colors.white12,
              onChanged: (v) => onChanged(style.copyWith(backgroundOpacity: v)),
            )),
      const Divider(color: Colors.white10, height: 1),
      // Outline
      _toggle('Text Outline', style.showOutline,
          (v) => onChanged(style.copyWith(showOutline: v))),
      // Shadow
      _row('Shadow Blur', '${style.shadowBlur.toInt()}',
          Slider(
            value: style.shadowBlur,
            min: 0, max: 16,
            divisions: 16,
            activeColor: accentColor,
            inactiveColor: Colors.white12,
            onChanged: (v) => onChanged(style.copyWith(shadowBlur: v)),
          )),
    ]);
  }

  Widget _row(String label, String value, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(value, style: TextStyle(color: accentColor, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: control),
    ],
  );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Switch(value: value, onChanged: onChanged, activeColor: accentColor,
              inactiveThumbColor: Colors.white38),
        ]),
      );
}
