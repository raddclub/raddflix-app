import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/theme/radd_theme.dart';
import '../core/constants.dart';
import '../core/design/app_icons.dart';
import '../core/utils/anim_config.dart';

// ── Nav item descriptors ──────────────────────────────────────────────────────
class _NavItem {
  final String label;
  final PhosphorIconData Function() icon;
  final PhosphorIconData Function() iconFill;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.iconFill,
  });
}

// ── Cinematic edge-to-edge nav bar ────────────────────────────────────────────
//
// Style: full-width flush bar — no floating pill.
//   • Icons only (no labels) — clean, cinema-native.
//   • Active tab: crimson filled icon + short glowing crimson indicator line
//     at the very top of the bar.
//   • Inactive tabs: muted icon at 45% opacity.
//   • Background: near-black frosted glass (BackdropFilter on Tier 2+),
//     solid #161618 on Tier 1 (no blur).
//   • Top edge: ultra-thin white separator (0.5 px, 6% opacity).
//   • Bottom padding: MediaQuery.padding.bottom so the bar always hugs the
//     device's home-indicator / gesture-bar area correctly.
//
class RaddFlixBottomNav extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const RaddFlixBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  ConsumerState<RaddFlixBottomNav> createState() => _RaddFlixBottomNavState();
}

class _RaddFlixBottomNavState extends ConsumerState<RaddFlixBottomNav> {
  static final _items = [
    _NavItem(
      label: 'Home',
      icon:     () => AppIcons.home,
      iconFill: () => AppIcons.homeFill,
    ),
    _NavItem(
      label: 'Live',
      icon:     () => AppIcons.liveTv,
      iconFill: () => AppIcons.liveTvFill,
    ),
    _NavItem(
      label: 'Local',
      icon:     () => AppIcons.localDevice,
      iconFill: () => AppIcons.localDeviceFill,
    ),
    _NavItem(
      label: 'Profile',
      icon:     () => AppIcons.profile,
      iconFill: () => AppIcons.profileFill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t          = RaddTheme.of(context);
    final animConfig = ref.watch(animConfigProvider);
    final bottomPad  = MediaQuery.of(context).padding.bottom;
    final isDark     = Theme.of(context).brightness == Brightness.dark;

    // ── Bar background ────────────────────────────────────────────────────────
    // Frosted glass on capable devices; solid surface fallback on Tier 1.
    Widget bar = Container(
      // Icon area (56 px) + safe-area inset at the bottom.
      height: 56 + bottomPad,
      decoration: BoxDecoration(
        color: isDark
            ? (animConfig.canBlur
                ? Colors.black.withOpacity(0.70)
                : t.surface)
            : (animConfig.canBlur
                ? Colors.white.withOpacity(0.88)
                : t.surface),
        // Top border — ultra-thin white line separates bar from content.
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Active indicator strip ──────────────────────────────────────────
          // Each tab owns an equal slice of the strip. The active tab's slice
          // shows a short crimson pill with a diffuse glow; inactive slices
          // are transparent. AnimatedContainer gives the pill a spring entrance.
          SizedBox(
            height: 3,
            child: Row(
              children: List.generate(_items.length, (i) {
                final active = widget.currentIndex == i;
                return Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: animConfig.normal,
                      curve: AppCurves.expressiveSpring,
                      // Pill width: wide when active, zero when not.
                      width:  active ? 36 : 0,
                      height: 3,
                      decoration: active
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: AppColors.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.72),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: AppColors.primaryGlow,
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            )
                          : const BoxDecoration(),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Tab icon row ────────────────────────────────────────────────────
          Expanded(
            child: Row(
              children: List.generate(_items.length, (i) {
                final active = widget.currentIndex == i;
                return Expanded(
                  child: _NavButton(
                    item:       _items[i],
                    isActive:   active,
                    animConfig: animConfig,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap(i);
                    },
                  ),
                );
              }),
            ),
          ),

          // ── Device safe-area spacer ─────────────────────────────────────────
          SizedBox(height: bottomPad),
        ],
      ),
    );

    // ── Tier 2+: frosted glass blur ───────────────────────────────────────────
    // ClipRect (not ClipRRect) — no rounded corners on the bar itself.
    if (animConfig.canBlur) {
      bar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: bar,
        ),
      );
    }

    return bar;
  }
}

// ── Individual tab button ─────────────────────────────────────────────────────
//
// Cinematic style: icon only, no label.
//   Active  → filled icon, crimson tint, 1.2× scale.
//   Inactive → outline icon, 45% white, 1.0× scale.
//
class _NavButton extends StatelessWidget {
  final _NavItem    item;
  final bool        isActive;
  final AnimConfig  animConfig;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.animConfig,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:    item.label,
      hint:     isActive ? 'currently selected tab' : 'activate',
      button:   true,
      selected: isActive,
      child: GestureDetector(
        onTap:    onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale:    isActive ? 1.20 : 1.0,
          duration: animConfig.normal,
          curve:    AppCurves.expressiveSpring,
          child: AnimatedOpacity(
            opacity:  isActive ? 1.0 : 0.45,
            duration: animConfig.fast,
            child: AnimatedSwitcher(
              duration:       animConfig.fast,
              switchInCurve:  AppCurves.expressiveEffect,
              switchOutCurve: AppCurves.expressiveExit,
              child: Icon(
                isActive ? item.iconFill() : item.icon(),
                key:   ValueKey('icon_${item.label}_$isActive'),
                color: isActive ? AppColors.primary : Colors.white,
                size:  26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
