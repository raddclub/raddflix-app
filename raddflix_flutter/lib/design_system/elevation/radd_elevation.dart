// lib/design_system/elevation/radd_elevation.dart
//
// RaddElevation — the three elevation presets from Volume II. Cards feel
// *lit*, not *lifted*: no drop shadow, border + subtle glass only. Sheets and
// modals use a real BackdropFilter blur, matching the existing player glass
// work — use RaddElevation.blurWrap to apply it.

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/radd_colors.dart';
import '../radius/radd_radius.dart';

class RaddElevation {
  RaddElevation._();

  static const double sheetBlurSigma = 20;
  static const double modalBlurSigma = 24;

  /// 0 blur, `cardBorder` outline only, subtle inner glass, no drop shadow.
  static BoxDecoration card(BuildContext context) => BoxDecoration(
        color: context.t.card,
        borderRadius: RaddRadius.mdRadius,
        border: Border.all(color: context.t.cardBorder, width: 0.5),
      );

  /// Pairs with `blurWrap(sigma: sheetBlurSigma, ...)` — 1px top border to
  /// match the existing player glass panels.
  static BoxDecoration sheet(BuildContext context) => BoxDecoration(
        color: context.t.surface.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(RaddRadius.lg)),
        border: Border(top: BorderSide(color: context.t.border, width: 1)),
      );

  /// Pairs with `blurWrap(sigma: modalBlurSigma, ...)` — soft signal-color
  /// tinted glow at 8% opacity ties dialogs to the brand identity even when
  /// their content is neutral.
  static BoxDecoration modal(BuildContext context) => BoxDecoration(
        color: context.t.surface,
        borderRadius: RaddRadius.lgRadius,
        boxShadow: [
          BoxShadow(
            color: context.signalPrimary.withOpacity(0.08),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      );

  /// Wraps `child` in a BackdropFilter blur at the given sigma. Use with
  /// `sheetBlurSigma` / `modalBlurSigma`. Callers on Tier < Standard should
  /// check `AnimConfig.canBlur` first and fall back to a solid surface.
  static Widget blurWrap({required double sigma, required Widget child}) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
