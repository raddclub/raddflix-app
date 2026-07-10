// lib/design_system/components/radd_button.dart
//
// RaddButton — Volume IV / VIII contract. One button primitive for every
// variant in the app; never hand-roll an ElevatedButton/GestureDetector
// combo for a new action, extend the variant enum instead.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/radd_colors.dart';
import '../motion/radd_motion.dart';
import '../radius/radd_radius.dart';
import '../spacing/radd_space.dart';
import '../typography/radd_type.dart';

enum RaddButtonVariant { signal, ghost, tonal, icon, destructive, success, floating }

enum RaddButtonSize { small, medium, large }

class RaddButton extends StatefulWidget {
  final RaddButtonVariant variant;
  final RaddButtonSize size;
  final String? label;
  final PhosphorIconData? leadingIcon;
  final PhosphorIconData? trailingIcon;
  final bool loading;
  final bool enabled;
  final bool fullWidth;
  final bool pulse;
  final String? tooltip;
  final Object? heroTag;
  final VoidCallback? onPressed;

  const RaddButton({
    super.key,
    this.variant = RaddButtonVariant.signal,
    this.size = RaddButtonSize.medium,
    this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.pulse = false,
    this.tooltip,
    this.heroTag,
    this.onPressed,
  })  : assert(variant == RaddButtonVariant.icon || label != null,
            'RaddButton requires a label unless variant is icon'),
        assert(variant != RaddButtonVariant.icon || tooltip != null,
            'Icon-only RaddButton requires a tooltip for accessibility');

  double get _height => switch (size) {
        RaddButtonSize.small => 40,
        RaddButtonSize.medium => 48,
        RaddButtonSize.large => 52,
      };

  @override
  State<RaddButton> createState() => _RaddButtonState();
}

class _RaddButtonState extends State<RaddButton> {
  bool _pressed = false;
  bool _loadingLatched = false;

  bool get _isDisabled => !widget.enabled || widget.onPressed == null || widget.loading;

  Future<void> _handleTap() async {
    if (_isDisabled) return;
    setState(() => _loadingLatched = true);
    final start = DateTime.now();
    widget.onPressed?.call();
    // Minimum 400ms display for loading state to prevent flicker (Volume VIII).
    final elapsed = DateTime.now().difference(start);
    if (elapsed < const Duration(milliseconds: 400)) {
      await Future.delayed(const Duration(milliseconds: 400) - elapsed);
    }
    if (mounted) setState(() => _loadingLatched = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isIconOnly = widget.variant == RaddButtonVariant.icon;
    final showLoading = widget.loading || _loadingLatched;

    final (Color bg, Color fg, Border? border) = switch (widget.variant) {
      RaddButtonVariant.signal => (context.signalPrimary, Colors.white, null),
      RaddButtonVariant.ghost => (
          t.glass,
          t.textPrimary,
          Border.all(color: t.border, width: 1),
        ),
      RaddButtonVariant.tonal => (
          context.signalPrimary.withOpacity(0.12),
          context.signalPrimary,
          null,
        ),
      RaddButtonVariant.icon => (
          t.glass,
          t.textSecondary,
          null,
        ),
      RaddButtonVariant.destructive => (
          context.accentError.withOpacity(0.12),
          context.accentError,
          Border.all(color: context.accentError, width: 1),
        ),
      RaddButtonVariant.success => (
          context.accentDataFree.withOpacity(0.12),
          context.accentDataFree,
          null,
        ),
      RaddButtonVariant.floating => (context.signalPrimary, Colors.white, null),
    };

    Widget child;
    if (showLoading) {
      child = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
      );
    } else if (isIconOnly) {
      child = Icon(widget.leadingIcon ?? PhosphorIcons.dotsThreeBold, color: fg, size: 20);
    } else {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leadingIcon != null) ...[
            Icon(widget.leadingIcon, color: fg, size: 20),
            const SizedBox(width: RaddSpace.xs + 4),
          ],
          Flexible(
            child: Text(
              widget.label!,
              style: context.raddLabel.copyWith(color: fg, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: RaddSpace.xs + 4),
            Icon(widget.trailingIcon, color: fg, size: 20),
          ],
        ],
      );
    }

    final double dimension = widget.variant == RaddButtonVariant.floating ? 56 : widget._height;

    Widget button = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: RaddMotion.cardPressDown, // Volume III spec-exact (was hardcoded 120ms)
      curve: Curves.easeOutCubic,
      child: Opacity(
        opacity: _isDisabled && !showLoading ? 0.4 : 1.0,
        child: Container(
          height: dimension,
          width: isIconOnly || widget.variant == RaddButtonVariant.floating
              ? dimension
              : (widget.fullWidth ? double.infinity : null),
          padding: isIconOnly || widget.variant == RaddButtonVariant.floating
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: RaddSpace.lg),
          decoration: BoxDecoration(
            color: bg,
            shape: isIconOnly || widget.variant == RaddButtonVariant.floating
                ? BoxShape.circle
                : BoxShape.rectangle,
            borderRadius: isIconOnly || widget.variant == RaddButtonVariant.floating
                ? null
                : RaddRadius.pillRadius,
            border: border,
            boxShadow: widget.variant == RaddButtonVariant.floating
                ? [
                    BoxShadow(
                      color: context.signalPrimary.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );

    if (widget.pulse && !_isDisabled) {
      button = button
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(end: 1.04, duration: 900.ms, curve: Curves.easeInOutSine);
    }

    button = Semantics(
      button: true,
      enabled: !_isDisabled,
      label: widget.tooltip ?? widget.label,
      child: GestureDetector(
        onTapDown: _isDisabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: _isDisabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: _isDisabled ? null : () => setState(() => _pressed = false),
        onTap: _isDisabled ? null : _handleTap,
        child: button,
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    if (widget.heroTag != null) {
      button = Hero(tag: widget.heroTag!, child: button);
    }

    return button;
  }
}
