import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // J3: Lexend dyslexia-friendly font
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';
import '../../core/player/word_dict.dart';
import '../../core/player/subtitle_personality.dart'; // IDEA-06
import '../../core/player/phonetic_subtitle.dart';    // IDEA-08
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

  /// SUB-A3: how many logical pixels to raise the subtitle block above the
  /// seekbar when player controls are visible.  Driven by a ValueNotifier
  /// outside so the transition animates without rebuilding the whole Consumer.
  /// Pass 0 when controls are hidden (default).
  final double controlsRaiseDp;

  const SubtitleOverlay({
    super.key,
    required this.currentLine,
    required this.prefs,
    this.onPausedForLookup,
    this.onResumedAfterLookup,
    this.controlsRaiseDp = 0,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay>
    with SingleTickerProviderStateMixin {
  String? _tappedWord;

  // IDEA-06: scale-bounce controller for exclamation personality.
  // Always present so the AnimatedBuilder in build() is tree-stable.
  late final AnimationController _bounceCtrl;
  late final Animation<double>   _scaleAnim;

  static final _reTokenize = RegExp(r"[\w']+|[^\w']+");
  static final _reWord     = RegExp(r"^[\w']+$");

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    // 0→1: scale up to 1.14 (25% of duration), then elastic-back to 1.0 (75%).
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.14), weight: 25),
      TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 75,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void didUpdateWidget(SubtitleOverlay old) {
    super.didUpdateWidget(old);
    // Trigger bounce when a new exclamation line arrives.
    if (widget.prefs.subtitlePersonalityEnabled &&
        widget.currentLine != old.currentLine &&
        widget.currentLine != null) {
      final p = SubtitlePersonality.analyze(
        widget.currentLine!, widget.prefs.subtitlePersonalityIntensity);
      if (p.useScaleBounce && !_bounceCtrl.isAnimating) {
        _bounceCtrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  // SUB-A4: combine vertical position with horizontal alignment
  Alignment get _alignment {
    final x = widget.prefs.subtitleHorizontalAlignment == 'left'  ? -1.0
             : widget.prefs.subtitleHorizontalAlignment == 'right' ?  1.0
             : 0.0;
    final y = widget.prefs.subtitlePosition == 'top'    ? -1.0
             : widget.prefs.subtitlePosition == 'center' ?  0.0
             : 1.0;
    return Alignment(x, y);
  }

  // SUB-A4: text/wrap alignment for left/center/right
  TextAlign get _textAlign {
    switch (widget.prefs.subtitleHorizontalAlignment) {
      case 'left':  return TextAlign.left;
      case 'right': return TextAlign.right;
      default:      return TextAlign.center;
    }
  }

  WrapAlignment get _wrapAlignment {
    switch (widget.prefs.subtitleHorizontalAlignment) {
      case 'left':  return WrapAlignment.start;
      case 'right': return WrapAlignment.end;
      default:      return WrapAlignment.center;
    }
  }

  /// SUB-A1: signed offset (no abs()) + SUB-A2: subtitleBottomMarginPx +
  /// SUB-A3: controlsRaiseDp so overlay clears the seekbar when visible.
  EdgeInsets get _padding {
    final offset = widget.prefs.subtitleVerticalOffset * 60; // signed
    switch (widget.prefs.subtitlePosition) {
      case 'top':
        return EdgeInsets.only(top: max(4.0, 20.0 + offset)); // positive = push down
      case 'center':
        return EdgeInsets.only(top: max(0.0, offset));
      default:
        return EdgeInsets.only(
          bottom: max(4.0,
            widget.prefs.subtitleBottomMarginPx.toDouble() // SUB-A2: px field
            + offset                                       // SUB-A1: signed
            + widget.controlsRaiseDp,                     // SUB-A3: raise
          ),
        );
    }
  }

  /// SUB-B2: resolve font family — subtitleFont (accessibility preset) takes
  /// priority over subtitleFontFamily (manual panel selection).
  String? get _resolvedFontFamily {
    switch (widget.prefs.subtitleFont) {
      case 'open_dyslexic':
        return 'OpenDyslexic'; // locally bundled font — not a Google Font
      case 'atkinson':
        return GoogleFonts.atkinsonHyperlegible().fontFamily;
      case 'lexend':
      case 'lexie_readable':
        return GoogleFonts.lexend().fontFamily;
      case 'roboto':
        return GoogleFonts.roboto().fontFamily;
      default:
        if (widget.prefs.subtitleFontFamily == 'Sans-Serif' ||
            widget.prefs.subtitleFontFamily == 'Sans Serif' ||
            widget.prefs.subtitleFontFamily == 'Default') {
          return null;
        }
        if (widget.prefs.subtitleFontFamily == 'Lexend') {
          return GoogleFonts.lexend().fontFamily;
        }
        return widget.prefs.subtitleFontFamily;
    }
  }

  /// SUB-B5: build outline + optional directional drop-shadow list.
  List<Shadow>? _buildShadows(double outline, Color outlineColor) {
    final shadows = <Shadow>[];
    if (widget.prefs.subtitleShadowBlurRadius > 0) {
      final blur = widget.prefs.subtitleShadowBlurRadius;
      switch (widget.prefs.subtitleShadowDirection) {
        case 'down_right':
          shadows.add(Shadow(
              offset: Offset(blur * 0.5, blur * 0.5),
              blurRadius: blur, color: Colors.black87));
          break;
        case 'down':
          shadows.add(Shadow(
              offset: Offset(0, blur * 0.5),
              blurRadius: blur, color: Colors.black87));
          break;
        case 'all':
          shadows.addAll([
            Shadow(offset: Offset(-blur * 0.4, -blur * 0.4), blurRadius: blur, color: Colors.black87),
            Shadow(offset: Offset( blur * 0.4, -blur * 0.4), blurRadius: blur, color: Colors.black87),
            Shadow(offset: Offset(-blur * 0.4,  blur * 0.4), blurRadius: blur, color: Colors.black87),
            Shadow(offset: Offset( blur * 0.4,  blur * 0.4), blurRadius: blur, color: Colors.black87),
          ]);
          break;
        default:
          break; // 'none'
      }
    }
    if (outline > 0) {
      shadows.addAll([
        Shadow(offset: Offset( outline / 2,  outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset(-outline / 2, -outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset( outline / 2, -outline / 2), blurRadius: outline, color: outlineColor),
        Shadow(offset: Offset(-outline / 2,  outline / 2), blurRadius: outline, color: outlineColor),
      ]);
    }
    return shadows.isEmpty ? null : shadows;
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
    if (widget.currentLine == null || widget.currentLine!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor    = Color(widget.prefs.subtitleTextColorValue);
    final outlineColor = Color(widget.prefs.subtitleOutlineColorValue);
    final bgColor      = Color(widget.prefs.subtitleBackgroundColorValue)
        .withOpacity(widget.prefs.subtitleBackgroundOpacity);
    final outline = widget.prefs.subtitleOutlineThickness;

    // IDEA-06: compute personality adjustments for the current line.
    final personality = widget.prefs.subtitlePersonalityEnabled
        ? SubtitlePersonality.analyze(
            widget.currentLine!, widget.prefs.subtitlePersonalityIntensity)
        : SubtitlePersonalityResult.normal;

    // Apply personality overrides: opacity, font size, bold, italic.
    final effectiveTextColor = personality.opacityMultiplier < 1.0
        ? textColor.withOpacity(
            ((textColor.alpha / 255.0) * personality.opacityMultiplier)
                .clamp(0.0, 1.0))
        : textColor;
    final effectiveFontSize = widget.prefs.subtitleFontSize * personality.fontScale;

    final baseStyle = TextStyle(
      fontSize:      effectiveFontSize,
      fontFamily:    _resolvedFontFamily,  // SUB-B2: accessibility font > panel selection
      color:         effectiveTextColor,
      fontWeight:    (personality.forceBold || widget.prefs.subtitleBold)
                         ? FontWeight.bold : FontWeight.normal,
      fontStyle:     (personality.forceItalic || widget.prefs.subtitleItalic)
                         ? FontStyle.italic : FontStyle.normal,
      letterSpacing: widget.prefs.subtitleLetterSpacing, // SUB-B4
      height:        widget.prefs.subtitleLineSpacing,    // SUB-B4
      shadows:       _buildShadows(outline, outlineColor), // SUB-B5
    );

    // IDEA-06: music lines get a gradient background pill instead of solid.
    final bool hasExplicitBg = bgColor.opacity > 0.02;
    final Decoration containerDecoration = personality.useGradientBg
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.prefs.accentColor.withOpacity(0.38),
                widget.prefs.accentColor.withOpacity(0.16),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
          )
        : BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          );

    // IDEA-08: offline phonetic overlay for Arabic/Devanagari lines.
    String? phoneticLine;
    TextStyle? phoneticStyle;
    if (widget.prefs.phoneticOverlayEnabled) {
      final roman = PhoneticSubtitle.romanize(widget.currentLine!);
      if (roman.isNotEmpty) {
        phoneticLine = roman;
        phoneticStyle = baseStyle.copyWith(
          fontSize: effectiveFontSize * widget.prefs.phoneticOverlayFontScale,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.normal,
          color: effectiveTextColor.withOpacity(
              ((effectiveTextColor.alpha / 255.0) * 0.80).clamp(0.0, 1.0)),
        );
      }
    }

    // AnimatedBuilder wraps the container so the scale-bounce animation
    // (if playing) is applied. When not animating, _scaleAnim.value == 1.0
    // and the transform is a no-op — no extra cost.
    //
    // SUB-GRAY-SCREEN fix: do NOT wrap in Positioned.fill here. The parent
    // already places this widget inside Positioned.fill → IgnorePointer.
    // A nested Positioned outside a Stack fills its parent in release builds,
    // causing the entire player area to be covered by a gray tint.
    // Return Align + Padding directly so sizing comes from the text content.
    return Align(
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
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (_, child) => Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
            child: Container(
              margin: EdgeInsets.symmetric(  // SUB-A5: use pref instead of hardcoded 24
                horizontal: widget.prefs.subtitleEdgePaddingPx.toDouble()),
              padding: (hasExplicitBg || personality.useGradientBg)
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                  : EdgeInsets.zero,
              decoration: containerDecoration,
              // BB8: crossfade when subtitle line changes — 150ms FadeTransition.
              // KeyedSubtree provides the key without changing _buildTappableText.
              // Tier-gate: AnimatedSwitcher is lightweight — safe on all tiers.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(widget.currentLine),
                  child: _buildContent(context, widget.currentLine!,
                      baseStyle, phoneticLine, phoneticStyle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// IDEA-08: builds main subtitle content plus optional phonetic row below.
  Widget _buildContent(BuildContext ctx, String line, TextStyle style,
      String? phoneticLine, TextStyle? phoneticStyle) {
    final Widget main = widget.prefs.dictEnabled
        ? _buildTappableText(ctx, line, style)
        : Text(line, textAlign: _textAlign, style: style); // SUB-A4: respect h-alignment

    if (phoneticLine == null || phoneticLine.isEmpty) return main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        main,
        const SizedBox(height: 2),
        Text(phoneticLine, textAlign: TextAlign.center, style: phoneticStyle),
      ],
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
      alignment: _wrapAlignment, // SUB-A4: respect h-alignment
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
