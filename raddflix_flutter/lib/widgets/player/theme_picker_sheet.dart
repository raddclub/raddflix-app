import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/player/player_theme.dart';
import 'seek_bar_painter.dart';

/// Grid of 8 built-in player themes. Selecting one calls [onThemeSelected]
/// immediately so accent color + seek bar style update live.
class ThemePickerSheet extends StatefulWidget {
  final String currentThemeId;
  final ValueChanged<PlayerTheme> onThemeSelected;

  const ThemePickerSheet({
    super.key,
    required this.currentThemeId,
    required this.onThemeSelected,
  });

  @override
  State<ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<ThemePickerSheet> {
  late String _selectedId;
  static const _bg = Color(0xFF12121E);

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentThemeId;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          )),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text('Player Theme',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.3,
            ),
            itemCount: kBuiltInThemes.length,
            itemBuilder: (_, i) {
              final theme = kBuiltInThemes[i];
              final isSel = theme.id == _selectedId;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedId = theme.id);
                  widget.onThemeSelected(theme);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: isSel
                        ? theme.accentColor.withOpacity(0.14)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSel ? theme.accentColor : Colors.white12,
                      width: isSel ? 2 : 1,
                    ),
                    boxShadow: isSel
                        ? [BoxShadow(
                            color: theme.accentColor.withOpacity(0.22),
                            blurRadius: 12)]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(theme.emoji, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(theme.name,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.normal,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (isSel)
                          Icon(Icons.check_circle_rounded, color: theme.accentColor, size: 16),
                      ]),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 18,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: SeekBarPainter(
                            style: seekBarStyleFromString(theme.seekBarStyle),
                            progress: 0.4,
                            buffered: 0.62,
                            accentColor: theme.accentColor,
                            gradientColor1: theme.gradientColor1,
                            gradientColor2: theme.gradientColor2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    )
    .animate()
    .slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic)
    .fadeIn(duration: 200.ms);
  }
}

Future<void> showThemePicker({
  required BuildContext context,
  required String currentThemeId,
  required ValueChanged<PlayerTheme> onThemeSelected,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ThemePickerSheet(
      currentThemeId: currentThemeId,
      onThemeSelected: onThemeSelected,
    ),
  );
}
