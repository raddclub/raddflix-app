import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';

class RaddFlixBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const RaddFlixBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.folder_outlined, active: Icons.folder_rounded, label: 'Local'),
    _NavItem(icon: Icons.download_outlined, active: Icons.download_rounded, label: 'Downloads'),
    _NavItem(icon: Icons.person_outline_rounded, active: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
          blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) => _NavButton(
              item: _items[i],
              isActive: currentIndex == i,
              onTap: () => onTap(i),
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
        child: SizedBox(
          width: 72,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Icon + animated pill background
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: isActive ? 52 : 44,
              height: 30,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withOpacity(0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                boxShadow: isActive
                    ? [BoxShadow(
                        color: AppColors.primary.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2))]
                    : null,
              ),
              child: Icon(
                isActive ? item.active : item.icon,
                color: isActive ? AppColors.primary : t.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isActive ? AppColors.primary : t.textMuted,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              ),
              child: Text(item.label),
            ),

          ]),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, active;
  final String label;
  const _NavItem({required this.icon, required this.active, required this.label});
}
