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

// ── Main widget ───────────────────────────────────────────────────────────────
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
  // NAV-RESTRUCTURE: 4-tab shell — Search moved to top-bar icon; Downloads
  // moved to top-bar icon with active-count badge (Vidmate/YouTube pattern).
  // Live TV added as tab 1 (between Home and Local).
  static final _items = [
    // D6: use the shared AppIcons source instead of raw PhosphorIcons calls,
    // so icon families can be swapped app-wide from one place.
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
    final isDark     = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth  = constraints.maxWidth;
            final itemWidth   = totalWidth / _items.length;
            const capsuleW    = 68.0;
            final capsuleLeft = widget.currentIndex * itemWidth +
                (itemWidth - capsuleW) / 2;

            Widget bar = Container(
              height: 62,
              decoration: BoxDecoration(
                color: isDark
                    ? (animConfig.canBlur
                        ? Colors.black.withOpacity(0.58)
                        : t.surface)
                    : (animConfig.canBlur
                        ? Colors.white.withOpacity(0.88)
                        : t.surface),
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(
                  color: t.border.withOpacity(animConfig.canBlur ? 0.22 : 0.55),
                  width: 0.75,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.48 : 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.05),
                      blurRadius: 48,
                    ),
                ],
              ),
              child: Stack(
                children: [
                  // ── Sliding capsule indicator ──────────────────────────
                  AnimatedPositioned(
                    duration: animConfig.normal,
                    curve: AppCurves.expressiveSpring,
                    left:   capsuleLeft,
                    top:    8,
                    bottom: 8,
                    width:  capsuleW,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.round),
                        gradient: AppGradients.navCapsule,
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.18),
                          width: 0.75,
                        ),
                      ),
                    ),
                  ),

                  // ── Tab buttons ────────────────────────────────────────
                  Positioned.fill(
                    child: Row(
                      children: List.generate(_items.length, (i) {
                        final active = widget.currentIndex == i;
                        return Expanded(
                          child: _NavButton(
                            item:     _items[i],
                            isActive: active,
                            animConfig: animConfig,
                            t:        t,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(i);
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );

            // ── Tier 2+: wrap with frosted glass blur ──────────────────
            if (animConfig.canBlur) {
              bar = ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.round),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: bar,
                ),
              );
            }

            return bar;
          },
        ),
      ),
    );
  }
}

// ── Individual tab button ─────────────────────────────────────────────────────
class _NavButton extends StatelessWidget {
  final _NavItem    item;
  final bool        isActive;
  final AnimConfig  animConfig;
  final RaddTheme   t;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.animConfig,
    required this.t,
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
        onTap:     onTap,
        behavior:  HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Spring-scaled icon ────────────────────────────────────
            AnimatedScale(
              scale:    isActive ? 1.18 : 1.0,
              duration: animConfig.normal,
              curve:    AppCurves.expressiveSpring,
              child: AnimatedSwitcher(
                duration:       animConfig.fast,
                switchInCurve:  AppCurves.expressiveEffect,
                switchOutCurve: AppCurves.expressiveExit,
                child: Icon(
                  isActive ? item.iconFill() : item.icon(),
                  key:   ValueKey('icon_${item.label}_$isActive'),
                  color: isActive ? AppColors.primary : t.textMuted,
                  size:  22,
                ),
              ),
            ),

            const SizedBox(height: 3),

            // ── Label ─────────────────────────────────────────────────
            AnimatedDefaultTextStyle(
              duration: animConfig.fast,
              style: TextStyle(
                color:       isActive ? AppColors.primary : t.textMuted,
                fontSize:    11.0,
                fontWeight:  isActive ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: isActive ? 0.25 : 0.0,
              ),
              // UX4-03: removed TextScaler.noScaling — nav labels now respect system font size
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
