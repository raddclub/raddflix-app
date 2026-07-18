// lib/widgets/theme_picker_sheet.dart
//
// UX4-05: Extracted from profile_screen.dart so the theme picker can be
// reused across Profile and Settings without duplicating code.
//
// Public surface:
//   • ThemePickerTrailing  — color swatch dot + current theme name (row trailing)
//   • ThemePickerSheet     — the full scrollable picker widget (bottom sheet body)
//   • showThemePickerSheet — convenience function to open the sheet

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../core/theme/theme_provider.dart';
import '../core/constants.dart';
import '../design_system/spacing/radd_space.dart';

// ── Convenience opener ────────────────────────────────────────────────────────
void showThemePickerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        child: const ThemePickerSheet(),
      ),
    ),
  );
}

// ── Trailing widget: color swatch dot + current theme name ────────────────────
class ThemePickerTrailing extends ConsumerWidget {
  const ThemePickerTrailing({super.key});

  static Color _dotColor(JazzTheme mode) {
    switch (mode) {
      case JazzTheme.midnight: return const Color(0xFF181838);
      case JazzTheme.navy:     return const Color(0xFF162A4A);
      case JazzTheme.forest:   return const Color(0xFF152B1A);
      case JazzTheme.cobalt:   return const Color(0xFF18255A);
      case JazzTheme.rose:     return const Color(0xFF2E1822);
      case JazzTheme.charcoal: return const Color(0xFF272729);
      case JazzTheme.amoled:   return const Color(0xFF000000);
      case JazzTheme.light:    return const Color(0xFFFAF6F0);
      default:                 return const Color(0xFF352A1F);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t    = RaddTheme.of(context);
    final mode = ref.watch(themeProvider).mode;
    final name = ref.watch(themeProvider.notifier).displayName;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: _dotColor(mode),
          shape: BoxShape.circle,
          border: Border.all(color: t.textMuted.withOpacity(0.4), width: 1),
        ),
      ),
      const SizedBox(width: 6),
      Text(name, style: TextStyle(color: t.textMuted, fontSize: 13)),
    ]);
  }
}

// ── Full picker sheet body ────────────────────────────────────────────────────
class ThemePickerSheet extends ConsumerWidget {
  const ThemePickerSheet({super.key});

  static final _standard = [
    (JazzTheme.dark,   AppIcons.moon,       'Dark',   'Deep dark — easy on the eyes'),
    (JazzTheme.amoled, AppIcons.device,     'AMOLED', 'Pure black — zero drain on OLED'),
    (JazzTheme.light,  AppIcons.sun,        'Light',  'Bright background for daylight'),
    (JazzTheme.auto,   AppIcons.brightness, 'Auto',   'Switches dark/light by time of day'),
  ];

  static const _colorThemes = [
    (JazzTheme.midnight, Color(0xFF070712), Color(0xFF181838), 'Midnight'),
    (JazzTheme.navy,     Color(0xFF060D1A), Color(0xFF162A4A), 'Navy'),
    (JazzTheme.forest,   Color(0xFF060E09), Color(0xFF152B1A), 'Forest'),
    (JazzTheme.cobalt,   Color(0xFF060A1A), Color(0xFF18255A), 'Cobalt'),
    (JazzTheme.rose,     Color(0xFF100608), Color(0xFF2E1822), 'Rose'),
    (JazzTheme.charcoal, Color(0xFF0E0E0F), Color(0xFF272729), 'Charcoal'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t       = RaddTheme.of(context);
    final current = ref.watch(themeProvider).mode;

    void pick(JazzTheme m) {
      ref.read(themeProvider.notifier).setTheme(m);
      Navigator.pop(context);
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle
        Center(child: Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: t.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)))),

        Text('Choose Theme',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 4),
        Text('Pick one look — a color theme replaces Dark/Light instantly.',
            style: TextStyle(fontSize: 12, color: t.textMuted)),
        const SizedBox(height: 18),

        // ── Standard themes ───────────────────────────────────────────────
        _pickerLabel('Standard', t),
        const SizedBox(height: 10),
        ...List.generate(_standard.length, (i) {
          final opt = _standard[i];
          final sel = current == opt.$1;
          return Column(children: [
            if (i > 0) Divider(height: 1, color: t.border),
            InkWell(
              onTap: () => pick(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
                  borderRadius: i == 0
                      ? const BorderRadius.vertical(top: Radius.circular(AppRadius.md))
                      : i == _standard.length - 1
                          ? const BorderRadius.vertical(bottom: Radius.circular(AppRadius.md))
                          : BorderRadius.zero,
                  border: i == 0 || i == _standard.length - 1 ? null
                      : Border.all(color: Colors.transparent),
                ),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary.withOpacity(0.15) : t.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(opt.$2,
                        color: sel ? AppColors.primary : t.textMuted, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(opt.$3, style: TextStyle(
                        color: sel ? AppColors.primary : t.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(opt.$4, style: TextStyle(color: t.textMuted, fontSize: 12)),
                  ])),
                  if (sel) Icon(AppIcons.successIcon, color: AppColors.primary, size: 20),
                ]),
              ),
            ),
          ]);
        }),

        const SizedBox(height: 20),

        // ── Color themes grid ─────────────────────────────────────────────
        _pickerLabel('Color Themes', t),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: _colorThemes.map((opt) {
            final sel = current == opt.$1;
            return GestureDetector(
              onTap: () => pick(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  gradient: LinearGradient(
                    colors: [opt.$2, opt.$3],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: sel ? AppColors.primary : Colors.white10,
                    width: sel ? 2 : 0.5,
                  ),
                  boxShadow: sel
                      ? [BoxShadow(color: AppColors.primary.withOpacity(0.25),
                          blurRadius: 10, spreadRadius: 1)]
                      : null,
                ),
                child: Stack(children: [
                  Positioned(bottom: 8, left: 0, right: 0,
                    child: Text(opt.$4, textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11,
                            fontWeight: FontWeight.w600, letterSpacing: 0.2))),
                  if (sel)
                    Positioned(top: 6, right: 6,
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        child: Icon(AppIcons.check, color: Colors.white, size: 12),
                      )),
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: RaddSpace.sm),
      ]),
    );
  }

  static Widget _pickerLabel(String label, RaddTheme t) => Row(children: [
    Container(width: 12, height: 1.5,
        margin: const EdgeInsets.only(right: 6),
        color: AppColors.primary.withOpacity(0.5)),
    Text(label.toUpperCase(),
        style: TextStyle(color: t.textMuted, fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.2)),
  ]);
}
