import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// Phase G2 / M4 — Skip Silence & Black Frames Settings
/// Configures automatic silence detection and skip behavior.
/// MPV-side: silencedetect filter added to af= chain.
/// Dart-side: position monitoring can trigger auto-seek past detected gaps.

class SilenceSkipSheet extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final Color accentColor;

  const SilenceSkipSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  State<SilenceSkipSheet> createState() => _SilenceSkipSheetState();
}

class _SilenceSkipSheetState extends State<SilenceSkipSheet> {
  late PlayerPrefs _p;

  @override
  void initState() { super.initState(); _p = widget.prefs; }

  void _update(PlayerPrefs next) {
    setState(() => _p = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Icon(Icons.volume_off_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Text('Smart Skip',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('Auto-skip silent/blank segments — great for lectures and podcasts.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
            children: [

              // ── Skip Silence toggle ──────────────────────────────────
              _SettingTile(
                icon: Icons.voice_over_off_rounded,
                title: 'Skip Silence',
                subtitle: 'Jump over silent passages automatically.',
                accent: acc,
                value: _p.skipSilenceEnabled,
                onChanged: (v) => _update(_p.copyWith(skipSilenceEnabled: v)),
              ),

              if (_p.skipSilenceEnabled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Min silence duration:',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const Spacer(),
                        Text(
                          '${_p.skipSilenceThresholdSecs.toStringAsFixed(1)}s',
                          style: TextStyle(
                              color: acc, fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ]),
                      Slider(
                        value: _p.skipSilenceThresholdSecs,
                        min: 0.5, max: 5.0, divisions: 18,
                        activeColor: acc, inactiveColor: Colors.white12,
                        label: '${_p.skipSilenceThresholdSecs.toStringAsFixed(1)}s',
                        onChanged: (v) =>
                            _update(_p.copyWith(skipSilenceThresholdSecs: v)),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('0.5s — aggressive',
                              style: TextStyle(color: Colors.white24, fontSize: 9)),
                          Text('5s — conservative',
                              style: TextStyle(color: Colors.white24, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(color: Colors.white10, height: 1, indent: 16),

              // ── Skip Black Frames toggle ─────────────────────────────
              _SettingTile(
                icon: Icons.brightness_1_rounded,
                title: 'Skip Black Frames',
                subtitle: 'Skip silent/black intros, logos, and ad bumpers.',
                accent: acc,
                value: _p.skipBlackFramesEnabled,
                onChanged: (v) =>
                    _update(_p.copyWith(skipBlackFramesEnabled: v)),
              ),

              const Divider(color: Colors.white10, height: 1, indent: 16),

              // ── Color Blind Mode ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.palette_outlined, color: acc, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Color Vision',
                                style: TextStyle(color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Applies color-correction filter to video output.',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _ModeRow(
                      options: const ['none', 'deuteranopia', 'protanopia', 'tritanopia'],
                      labels:  const ['Off', 'Deuteranopia', 'Protanopia', 'Tritanopia'],
                      selected: _p.colorBlindMode,
                      accent: acc,
                      onTap: (v) => _update(_p.copyWith(colorBlindMode: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 220.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 180.ms);
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color accent;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingTile({required this.icon, required this.title,
      required this.subtitle, required this.accent, required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(
              color: value ? accent.withOpacity(0.15) : Colors.white10,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: value ? accent.withOpacity(0.4) : Colors.transparent)),
          child: Icon(icon, color: value ? accent : Colors.white54, size: 18)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(title, style: TextStyle(
            color: value ? Colors.white : Colors.white70,
            fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(
            color: Colors.white38, fontSize: 10)),
      ])),
      Switch(value: value, activeColor: accent, onChanged: onChanged),
    ]),
  );
}

class _ModeRow extends StatelessWidget {
  final List<String> options, labels;
  final String selected;
  final Color accent;
  final ValueChanged<String> onTap;
  const _ModeRow({required this.options, required this.labels,
      required this.selected, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8,
    children: List.generate(options.length, (i) {
      final sel = selected == options[i];
      return GestureDetector(
        onTap: () => onTap(options[i]),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: sel ? accent : Colors.white12, width: sel ? 1.5 : 1.0)),
          child: Text(labels[i],
              style: TextStyle(
                  color: sel ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
        ),
      );
    }),
  );
}
