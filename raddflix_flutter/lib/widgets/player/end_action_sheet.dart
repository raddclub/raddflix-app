import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// Phase M3 — End-of-Video Action Picker
/// What happens when the current video finishes playing.

class EndActionSheet extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final Color accentColor;

  const EndActionSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  State<EndActionSheet> createState() => _EndActionSheetState();
}

class _EndActionSheetState extends State<EndActionSheet> {
  late PlayerPrefs _p;

  @override
  void initState() { super.initState(); _p = widget.prefs; }

  void _update(PlayerPrefs next) {
    setState(() => _p = next);
    widget.onChanged(next);
  }

  static const _actions = [
    _EndAction('play_next',    Icons.skip_next_rounded,        'Play Next',     'Automatically play the next episode or file.'),
    _EndAction('loop',         Icons.repeat_rounded,           'Loop',          'Restart and repeat the current video.'),
    _EndAction('return_home',  Icons.home_rounded,             'Return to Home','Close player and return to the library screen.'),
    _EndAction('nothing',      Icons.stop_circle_outlined,     'Do Nothing',    'Pause on last frame and wait for user input.'),
  ];

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // drag handle
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Icon(Icons.flag_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Text('When Video Ends',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('Choose what happens after the video finishes.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            itemCount: _actions.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.white10, height: 1, indent: 64),
            itemBuilder: (_, i) {
              final a = _actions[i];
              final selected = _p.endOfVideoAction == a.key;
              return ListTile(
                leading: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? acc.withOpacity(0.18)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: selected
                            ? acc.withOpacity(0.5)
                            : Colors.transparent),
                  ),
                  child: Icon(a.icon,
                      color: selected ? acc : Colors.white54, size: 20),
                ),
                title: Text(a.label,
                    style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal)),
                subtitle: Text(a.description,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10)),
                trailing: selected
                    ? Icon(Icons.check_circle_rounded, color: acc, size: 20)
                    : const Icon(Icons.radio_button_unchecked_rounded,
                        color: Colors.white24, size: 20),
                onTap: () =>
                    _update(_p.copyWith(endOfVideoAction: a.key)),
              );
            },
          ),
        ),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 220.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 180.ms);
  }
}

class _EndAction {
  final String key, label, description;
  final IconData icon;
  const _EndAction(this.key, this.icon, this.label, this.description);
}
