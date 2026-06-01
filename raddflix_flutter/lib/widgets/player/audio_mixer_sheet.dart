import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase S — Audio Track & Channel Mixer
/// Select audio tracks, adjust channel balance, delay sync.

class AudioTrack {
  final int id;
  final String title;
  final String language;
  final String codec;
  final int channels; // 1=mono, 2=stereo, 6=5.1, 8=7.1
  final bool isDefault;

  const AudioTrack({
    required this.id,
    required this.title,
    required this.language,
    this.codec = 'AAC',
    this.channels = 2,
    this.isDefault = false,
  });

  String get channelLabel {
    switch (channels) {
      case 1: return 'Mono';
      case 2: return 'Stereo';
      case 6: return '5.1';
      case 8: return '7.1';
      default: return '${channels}ch';
    }
  }
}

class AudioMixerSheet extends StatefulWidget {
  final List<AudioTrack> tracks;
  final int selectedTrackId;
  final double audioDelay;      // seconds (can be negative)
  final double channelBalance;  // -1.0 (left) … +1.0 (right)
  final bool boostDialogue;
  final Color accentColor;
  final ValueChanged<int> onTrackSelected;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onBalanceChanged;
  final ValueChanged<bool> onBoostDialogueToggled;

  const AudioMixerSheet({
    super.key,
    required this.tracks,
    required this.selectedTrackId,
    this.audioDelay = 0.0,
    this.channelBalance = 0.0,
    this.boostDialogue = false,
    required this.accentColor,
    required this.onTrackSelected,
    required this.onDelayChanged,
    required this.onBalanceChanged,
    required this.onBoostDialogueToggled,
  });

  @override State<AudioMixerSheet> createState() => _AudioMixerSheetState();
}

class _AudioMixerSheetState extends State<AudioMixerSheet> {
  late int    _selectedId;
  late double _delay;
  late double _balance;
  late bool   _boostDialogue;

  @override
  void initState() {
    super.initState();
    _selectedId   = widget.selectedTrackId;
    _delay        = widget.audioDelay;
    _balance      = widget.channelBalance;
    _boostDialogue= widget.boostDialogue;
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0,12,0,0),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
          child: Row(children: [
            Icon(Icons.audiotrack_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Audio', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          ])),
        const Divider(color: Colors.white10, height: 20),

        // Track list
        if (widget.tracks.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16,0,16,8),
            child: Text('AUDIO TRACKS', style: TextStyle(
                color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
          ...widget.tracks.map((t) => _TrackRow(
            track: t,
            selected: _selectedId == t.id,
            accent: acc,
            onTap: () {
              setState(() => _selectedId = t.id);
              widget.onTrackSelected(t.id);
            },
          )),
          const Divider(color: Colors.white10, height: 16),
        ],

        Flexible(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            // Dialogue boost
            InkWell(
              onTap: () {
                setState(() => _boostDialogue = !_boostDialogue);
                widget.onBoostDialogueToggled(_boostDialogue);
              },
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(Icons.record_voice_over_rounded,
                      color: _boostDialogue ? acc : Colors.white38, size: 18),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Dialogue Boost', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('Enhance voice clarity in noisy content',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ])),
                  Switch(value: _boostDialogue, activeColor: acc,
                      onChanged: (v) { setState(() => _boostDialogue = v); widget.onBoostDialogueToggled(v); },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ])),
            ),
            const Divider(color: Colors.white10, height: 16),

            // Channel Balance
            const Text('Channel Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              const Text('L', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Expanded(child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: acc, inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white, overlayColor: acc.withOpacity(0.2)),
                child: Slider(value: _balance, min: -1.0, max: 1.0, divisions: 20,
                  onChanged: (v) { setState(() => _balance = v); widget.onBalanceChanged(v); }))),
              const Text('R', style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text(
                _balance == 0 ? 'C' : (_balance < 0 ? 'L${(-_balance*100).toInt()}' : 'R${(_balance*100).toInt()}'),
                style: TextStyle(color: acc, fontSize: 11, fontWeight: FontWeight.w700),
                textAlign: TextAlign.right)),
            ]),
            const SizedBox(height: 4),
            Center(child: GestureDetector(
              onTap: () { setState(() => _balance = 0); widget.onBalanceChanged(0); },
              child: const Text('Reset to centre',
                  style: TextStyle(color: Colors.white38, fontSize: 10)))),
            const Divider(color: Colors.white10, height: 20),

            // Audio Delay
            const Text('Audio Sync Delay', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              const Text('-3s', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Expanded(child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: _delay.abs() > 0.05 ? Colors.orange : acc,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white, overlayColor: acc.withOpacity(0.2)),
                child: Slider(value: _delay.clamp(-3.0, 3.0), min: -3.0, max: 3.0, divisions: 60,
                  onChanged: (v) { setState(() => _delay = v); widget.onDelayChanged(v); }))),
              const Text('+3s', style: TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 8),
              SizedBox(width: 44, child: Text(
                '${_delay > 0 ? '+' : ''}${(_delay*1000).round()}ms',
                style: TextStyle(color: _delay.abs() > 0.05 ? Colors.orange : acc,
                    fontSize: 11, fontWeight: FontWeight.w700),
                textAlign: TextAlign.right)),
            ]),
            Center(child: GestureDetector(
              onTap: () { setState(() => _delay = 0); widget.onDelayChanged(0); },
              child: const Text('Reset delay',
                  style: TextStyle(color: Colors.white38, fontSize: 10)))),
          ],
        )),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 180.ms);
  }
}

class _TrackRow extends StatelessWidget {
  final AudioTrack track;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _TrackRow({required this.track, required this.selected,
      required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        AnimatedContainer(duration: const Duration(milliseconds: 150),
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.2) : Colors.white10,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? accent : Colors.white24, width: selected ? 2 : 1)),
          child: Icon(Icons.audiotrack_rounded,
              color: selected ? accent : Colors.white38, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(track.title, style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
          Row(children: [
            Text(track.language, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
              child: Text('${track.codec} · ${track.channelLabel}',
                  style: const TextStyle(color: Colors.white38, fontSize: 9))),
            if (track.isDefault) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3)),
                child: Text('DEFAULT', style: TextStyle(color: accent, fontSize: 8, fontWeight: FontWeight.w700))),
            ],
          ]),
        ])),
        if (selected)
          Icon(Icons.check_circle_rounded, color: accent, size: 20),
      ])),
  );
}
