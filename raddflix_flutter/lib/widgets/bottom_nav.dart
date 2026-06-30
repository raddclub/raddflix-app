import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../core/utils/anim_config.dart';

class RaddFlixBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const RaddFlixBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined,       active: Icons.home_rounded,       label: 'Home'),
    _NavItem(icon: Icons.folder_outlined,     active: Icons.folder_rounded,     label: 'Local'),
    _NavItem(icon: Icons.download_outlined,   active: Icons.download_rounded,   label: 'Downloads'),
    _NavItem(icon: Icons.person_outline_rounded, active: Icons.person_rounded,  label: 'Profile'),
  ];

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t          = RaddTheme.of(context);
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    // Phase 47 ANIM-47-01/02: Tier 2+ (API 28+) → frosted glass; Tier 0/1 → solid surface
    final animConfig = ref.watch(animConfigProvider);

    if (animConfig.canBlur) {
      // ── Tier 2+: BackdropFilter frosted glass ─────────────────────
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : t.surface).withOpacity(0.72),
              border: Border(top: BorderSide(color: t.border.withOpacity(0.4), width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: List.generate(_items.length, (i) => Expanded(
                    child: _NavButton(
                      item:     _items[i],
                      isActive: currentIndex == i,
                      onTap:    () => onTap(i),
                    ),
                  )),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── Tier 0/1 fallback: solid surface (unchanged) ────────────────
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.45 : 0.08),
          blurRadius: 24, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(_items.length, (i) => Expanded(
              child: _NavButton(
                item:     _items[i],
                isActive: currentIndex == i,
                onTap:    () => onTap(i),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Semantics(
      label: item.label,
      hint: isActive ? 'currently selected tab' : 'activate',
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
          // ── Top active line ──────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            height: 2.5,
            width: isActive ? 28.0 : 0.0,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              gradient: isActive ? AppColors.primaryGradient : null,
              color:    isActive ? null : Colors.transparent,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
              boxShadow: isActive
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 6, offset: const Offset(0, 1))]
                  : null,
            ),
          ),
          // ── Icon ──────────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve:  Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            child: Icon(
              isActive ? item.active : item.icon,
              key: ValueKey(isActive),
              color: isActive ? AppColors.primary : t.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          // ── Label ─────────────────────────────────────────────────────
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color:      isActive ? AppColors.primary : t.textMuted,
              fontSize:   10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Text(item.label, textScaler: TextScaler.noScaling),
          ),
        ]),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, active;
  final String label;
  const _NavItem({required this.icon, required this.active, required this.label});
}
