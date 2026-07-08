// lib/design_system/components/radd_card.dart
//
// RaddCard — Volume IV / VIII contract. One base geometry (md radius,
// cardBorder outline, press scale) with content-driven variants. Never
// render a generic gray box while loading — always a geometry-matched
// shimmer skeleton.

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/radd_colors.dart';
import '../radius/radd_radius.dart';
import '../spacing/radd_space.dart';

enum RaddCardVariant {
  movie,
  episode,
  continueWatching,
  collection,
  actor,
  folder,
  recommendation,
  hero,
  compact,
  mini,
}

class RaddCard extends StatefulWidget {
  final RaddCardVariant variant;
  final String imageUrl;
  final String? title;
  final bool isDataFree;
  final double? progress;
  final VoidCallback onTap;
  final String? heroTag;

  const RaddCard({
    super.key,
    this.variant = RaddCardVariant.movie,
    required this.imageUrl,
    this.title,
    this.isDataFree = false,
    this.progress,
    required this.onTap,
    this.heroTag,
  });

  double get _aspectRatio => switch (variant) {
        RaddCardVariant.episode => 16 / 9,
        RaddCardVariant.collection => 3 / 2,
        RaddCardVariant.actor => 1,
        RaddCardVariant.folder => 1,
        RaddCardVariant.compact => 3 / 4.5,
        RaddCardVariant.hero => 16 / 9,
        RaddCardVariant.mini => 96 / 144,
        _ => 2 / 3,
      };

  @override
  State<RaddCard> createState() => _RaddCardState();
}

class _RaddCardState extends State<RaddCard> {
  bool _pressed = false;
  bool _loaded = false;
  bool _errored = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isBorderless = widget.variant == RaddCardVariant.hero;
    final isCircular = widget.variant == RaddCardVariant.actor;

    Widget art = AspectRatio(
      aspectRatio: widget._aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_loaded && !_errored)
            Shimmer.fromColors(
              baseColor: t.shimmerBase,
              highlightColor: t.shimmerHighlight,
              child: Container(color: t.shimmerBase),
            ),
          Image.network(
            widget.imageUrl,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null && !_loaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _loaded = true);
                });
              }
              return child;
            },
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_errored) setState(() => _errored = true);
              });
              return Container(
                color: t.surfaceHigh,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, color: t.textMuted),
              );
            },
          ),
          if (widget.isDataFree)
            Positioned(
              top: 6,
              right: 6,
              child: Semantics(
                label: 'Data-free',
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: context.accentDataFree,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
            ),
          if (widget.progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 3,
                color: t.glass,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widget.progress!.clamp(0.0, 1.0),
                  child: Container(color: context.signalPrimary),
                ),
              ),
            ),
        ],
      ),
    );

    if (isCircular) {
      art = ClipOval(child: art);
    } else if (!isBorderless) {
      art = ClipRRect(
        borderRadius: RaddRadius.mdRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: RaddRadius.mdRadius,
            border: Border.all(color: t.cardBorder, width: 0.5),
          ),
          child: art,
        ),
      );
    }

    if (widget.heroTag != null &&
        (widget.variant == RaddCardVariant.movie || widget.variant == RaddCardVariant.hero)) {
      art = Hero(tag: widget.heroTag!, child: art);
    }

    final semanticsLabel = widget.isDataFree
        ? '${widget.title ?? ''}, ${widget.variant.name}, data-free'
        : '${widget.title ?? ''}, ${widget.variant.name}';

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              art,
              if (widget.title != null && widget.variant != RaddCardVariant.mini) ...[
                const SizedBox(height: RaddSpace.xs),
                Text(
                  widget.title!,
                  maxLines: widget.variant == RaddCardVariant.episode ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.raddCaption.copyWith(color: t.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
