import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// Phase E — Audio Lab Sheet
/// Vocal Remover, Virtual Surround, Dialogue Boost, Audio Normalization.
/// Acts as an extension of the EQ panel — pure UI, actual DSP via MPV af= in player_screen.

class AudioLabSheet extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final Color accentColor;

  const AudioLabSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  State<AudioLabSheet> createState() => _AudioLabSheetState();
}

class _AudioLabSheetState extends State<AudioLabSheet> {
  late PlayerPrefs _p;

  @override
  void initState() {
    super.initState();
    _p = widget.prefs;
  }

  void _update(PlayerPrefs next) {
    setState(() => _p = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Icon(Icons.biotech_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Text('Audio Lab',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 5, 16, 12),
          child: Text('Advanced audio processing — karaoke, surround, clarity.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [

            // ── Vocal Remover ────────────────────────────────────────────
            _LabSection(
              icon: Icons.mic_off_rounded,
              title: 'Vocal Remover',
              subtitle: 'Phase-cancellation reduces centre-channel vocals.',
              accent: acc,
              enabled: _p.vocalRemoverEnabled,
              onToggle: (v) => _update(_p.copyWith(vocalRemoverEnabled: v)),
              child: _p.vocalRemoverEnabled ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Intensity', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _IntensityBtn(
                      label: 'Reduce', selected: _p.vocalRemoverIntensity < 0.7,
                      accent: acc, onTap: () => _update(_p.copyWith(vocalRemoverIntensity: 0.5)))),
                    const SizedBox(width: 8),
                    Expanded(child: _IntensityBtn(
                      label: 'Strong', selected: _p.vocalRemoverIntensity >= 0.7 && _p.vocalRemoverIntensity < 0.95,
                      accent: acc, onTap: () => _update(_p.copyWith(vocalRemoverIntensity: 0.75)))),
                    const SizedBox(width: 8),
                    Expanded(child: _IntensityBtn(
                      label: 'Remove', selected: _p.vocalRemoverIntensity >= 0.95,
                      accent: acc, onTap: () => _update(_p.copyWith(vocalRemoverIntensity: 1.0)))),
                  ]),
                ]),
              ) : const SizedBox.shrink(),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Virtual Surround ─────────────────────────────────────────
            _LabSection(
              icon: Icons.surround_sound_rounded,
              title: 'Virtual Surround',
              subtitle: 'Binaural simulation — makes stereo feel like 5.1.',
              accent: acc,
              enabled: _p.surroundEnabled,
              onToggle: (v) => _update(_p.copyWith(surroundEnabled: v)),
              child: _p.surroundEnabled ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Room Mode', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _IntensityBtn(
                      label: '🎭 Theater', selected: _p.surroundMode == 'theater',
                      accent: acc, onTap: () => _update(_p.copyWith(surroundMode: 'theater')))),
                    const SizedBox(width: 8),
                    Expanded(child: _IntensityBtn(
                      label: '🏟 Stadium', selected: _p.surroundMode == 'stadium',
                      accent: acc, onTap: () => _update(_p.copyWith(surroundMode: 'stadium')))),
                    const SizedBox(width: 8),
                    Expanded(child: _IntensityBtn(
                      label: '🏠 Room', selected: _p.surroundMode == 'room',
                      accent: acc, onTap: () => _update(_p.copyWith(surroundMode: 'room')))),
                  ]),
                ]),
              ) : const SizedBox.shrink(),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Dialogue Boost ───────────────────────────────────────────
            _LabSection(
              icon: Icons.record_voice_over_rounded,
              title: 'Dialogue Boost',
              subtitle: 'Boosts 2–5 kHz speech clarity without raising music.',
              accent: acc,
              enabled: _p.dialogueBoostEnabled,
              onToggle: (v) => _update(_p.copyWith(dialogueBoostEnabled: v)),
              child: const SizedBox.shrink(),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Audio Normalization ──────────────────────────────────────
            _LabSection(
              icon: Icons.graphic_eq_rounded,
              title: 'Audio Normalization',
              subtitle: 'Dynamic auto-normalize — evens out loud/quiet scenes.',
              accent: acc,
              enabled: _p.audioNormalization,
              onToggle: (v) => _update(_p.copyWith(audioNormalization: v)),
              child: const SizedBox.shrink(),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Bass Boost ───────────────────────────────────────────────
            _LabSection(
              icon: Icons.speaker_rounded,
              title: 'Bass Boost',
              subtitle: 'Enhances low-frequency response.',
              accent: acc,
              enabled: _p.bassBoostEnabled,
              onToggle: (v) => _update(_p.copyWith(bassBoostEnabled: v)),
              child: _p.bassBoostEnabled ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  const Icon(Icons.volume_down_rounded, color: Colors.white38, size: 16),
                  Expanded(child: Slider(
                    value: _p.bassBoostLevel,
                    min: 0, max: 1, divisions: 10,
                    activeColor: acc,
                    inactiveColor: Colors.white12,
                    onChanged: (v) => _update(_p.copyWith(bassBoostLevel: v)),
                  )),
                  const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 36, child: Text(
                    '${(_p.bassBoostLevel * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    textAlign: TextAlign.right)),
                ]),
              ) : const SizedBox.shrink(),
            ),


            const Divider(color: Colors.white10, height: 1),

            // ── Smart Volume Leveling ─────────────────────────────────────
            _LabSection(
              icon: Icons.auto_fix_high_rounded,
              title: 'Smart Volume Leveling',
              subtitle: 'Auto-ramps volume toward target — smooths loud/quiet transitions.',
              accent: acc,
              enabled: _p.smartVolumeLevelingEnabled,
              onToggle: (v) => _update(_p.copyWith(smartVolumeLevelingEnabled: v)),
              child: _p.smartVolumeLevelingEnabled
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          const Text('Target',
                              style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Expanded(
                            child: Slider(
                              value: _p.smartVolumeTarget,
                              min: 0.5, max: 1.0, divisions: 10,
                              activeColor: acc, inactiveColor: Colors.white12,
                              onChanged: (v) =>
                                  _update(_p.copyWith(smartVolumeTarget: v)),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${(_p.smartVolumeTarget * 100).toInt()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        const Text('Speed',
                            style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: _IntensityBtn(
                            label: 'Gentle',
                            selected: _p.smartVolumeMode == 'gentle',
                            accent: acc,
                            onTap: () =>
                                _update(_p.copyWith(smartVolumeMode: 'gentle')))),
                          const SizedBox(width: 8),
                          Expanded(child: _IntensityBtn(
                            label: 'Balanced',
                            selected: _p.smartVolumeMode == 'balanced',
                            accent: acc,
                            onTap: () =>
                                _update(_p.copyWith(smartVolumeMode: 'balanced')))),
                          const SizedBox(width: 8),
                          Expanded(child: _IntensityBtn(
                            label: 'Aggressive',
                            selected: _p.smartVolumeMode == 'aggressive',
                            accent: acc,
                            onTap: () =>
                                _update(_p.copyWith(smartVolumeMode: 'aggressive')))),
                        ]),
                      ]))
                  : const SizedBox.shrink(),
            ),
          ],
        )),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 200.ms);
  }
}

class _LabSection extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color accent;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;
  const _LabSection({required this.icon, required this.title, required this.subtitle,
      required this.accent, required this.enabled, required this.onToggle,
      required this.child});

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(width: 38, height: 38,
            decoration: BoxDecoration(
                color: enabled ? accent.withOpacity(0.15) : Colors.white10,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: enabled ? accent.withOpacity(0.4) : Colors.transparent)),
            child: Icon(icon, color: enabled ? accent : Colors.white54, size: 19)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white70,
              fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ])),
        Switch(value: enabled, activeColor: accent, onChanged: onToggle),
      ]),
    ),
    child,
  ]);
}

class _IntensityBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _IntensityBtn({required this.label, required this.selected,
      required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? accent : Colors.white12,
            width: selected ? 1.5 : 1.0)),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
    ),
  );
}
