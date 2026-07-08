// lib/design_system/components/radd_banner.dart
//
// RaddBanner — Volume IV / VIII contract. One shared shell with a fixed
// semantic palette per variant. Priority queue: error > subscription >
// offline > everything else — enforce ordering at the call site
// (RaddBannerQueue) rather than inside individual banner widgets.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/radd_colors.dart';
import '../spacing/radd_space.dart';

enum RaddBannerVariant {
  offline,
  downloading,
  subscription,
  freeData,
  updateAvailable,
  watchParty,
  sync,
  warning,
  error,
}

/// Priority used by any call-site queue: lower number = shown first.
const Map<RaddBannerVariant, int> raddBannerPriority = {
  RaddBannerVariant.error: 0,
  RaddBannerVariant.subscription: 1,
  RaddBannerVariant.offline: 2,
  RaddBannerVariant.warning: 3,
  RaddBannerVariant.downloading: 4,
  RaddBannerVariant.freeData: 4,
  RaddBannerVariant.updateAvailable: 4,
  RaddBannerVariant.watchParty: 4,
  RaddBannerVariant.sync: 4,
};

class RaddBanner extends StatefulWidget {
  final RaddBannerVariant variant;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dismissible;
  final VoidCallback? onDismissed;

  const RaddBanner({
    super.key,
    required this.variant,
    required this.message,
    this.actionLabel,
    this.onAction,
    bool? dismissible,
    this.onDismissed,
  }) : dismissible = dismissible ?? variant != RaddBannerVariant.error;

  @override
  State<RaddBanner> createState() => _RaddBannerState();
}

class _RaddBannerState extends State<RaddBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      SemanticsService.announce(widget.message, TextDirection.ltr);
    });
  }

  (Color, PhosphorIconData, bool) _paletteFor(BuildContext context, RaddBannerVariant v) {
    final t = context.t;
    return switch (v) {
      RaddBannerVariant.offline => (context.accentWarning.withOpacity(0.12), PhosphorIcons.wifiSlash(), false),
      RaddBannerVariant.downloading => (context.signalPrimary.withOpacity(0.12), PhosphorIcons.downloadSimple(), false),
      RaddBannerVariant.subscription => (context.accentWarning.withOpacity(0.12), PhosphorIcons.crown(), false),
      RaddBannerVariant.freeData => (context.accentDataFree.withOpacity(0.12), PhosphorIcons.lightning(), false),
      RaddBannerVariant.updateAvailable => (t.glass, PhosphorIcons.arrowUp(), false),
      RaddBannerVariant.watchParty => (context.signalPrimary.withOpacity(0.12), PhosphorIcons.usersThree(), true),
      RaddBannerVariant.sync => (t.glass, PhosphorIcons.arrowsClockwise(), false),
      RaddBannerVariant.warning => (context.accentWarning.withOpacity(0.16), PhosphorIcons.warning(), false),
      RaddBannerVariant.error => (context.accentError.withOpacity(0.16), PhosphorIcons.warningCircle(), false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (bg, icon, pulseIcon) = _paletteFor(context, widget.variant);

    Widget iconWidget = Icon(icon, size: 18, color: t.textPrimary);
    if (pulseIcon) {
      iconWidget = iconWidget
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(end: 1.15, duration: 900.ms);
    }

    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
          color: bg,
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: RaddSpace.sm),
              Expanded(
                child: Text(
                  widget.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.raddCaption.copyWith(color: t.textPrimary),
                ),
              ),
              if (widget.actionLabel != null)
                TextButton(
                  onPressed: widget.onAction,
                  child: Text(widget.actionLabel!, style: context.raddLabel.copyWith(color: context.signalPrimary)),
                ),
              if (widget.dismissible)
                GestureDetector(
                  onTap: () {
                    setState(() => _visible = false);
                    Future.delayed(const Duration(milliseconds: 220), widget.onDismissed);
                  },
                  child: Icon(PhosphorIcons.x(), size: 16, color: t.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
