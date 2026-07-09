import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

const _bandLabels = <String>['60', '170', '310', '600', '1k', '3k', '6k', '12k', '14k', '16k'];
const _presets = {
  'flat':  [0.0, 0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0],
  'rock':  [4.0, 3.0,  2.0, -1.0, -1.0,  2.0,  4.0,  5.0,  5.0,  4.0],
  'pop':   [-1.0,2.0,  4.0,  4.0,  2.0,  0.0, -1.0, -1.0,  0.0,  1.0],
  'bass':  [6.0, 5.0,  4.0,  2.0,  0.0, -1.0, -2.0, -3.0, -3.0, -3.0],
  'movie': [3.0, 2.0,  1.0,  0.0,  1.0,  3.0,  4.0,  4.0,  3.0,  2.0],
  'voice': [-2.0,-2.0, 2.0,  5.0,  5.0,  4.0,  2.0,  0.0, -1.0, -2.0],
};

// Audio effect presets matching MX Player screenshot 16
const _audioEffects = [
  {'label': 'Original',     'icon': Icons.equalizer,              'preset': 'flat',  'color': 0xFF1565C0},
  {'label': 'Treble Boost', 'icon': Icons.music_note,             'preset': 'rock',  'color': 0xFF1A237E},
  {'label': 'Clarity',      'icon': Icons.record_voice_over,      'preset': 'voice', 'color': 0xFF1A237E},
  {'label': 'Movie',        'icon': Icons.movie_filter,           'preset': 'movie', 'color': 0xFF1A237E},
  {'label': 'Music',        'icon': Icons.library_music,          'preset': 'pop',   'color': 0xFF1A237E},
  {'label': 'Bass Boost',   'icon': Icons.speaker,                'preset': 'bass',  'color': 0xFF1A237E},
];

class EqPanel extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final VoidCallback onDone;

  const EqPanel({super.key, required this.prefs, required this.onChanged, required this.onDone});

  @override
  State<EqPanel> createState() => _EqPanelState();
}

class _EqPanelState extends State<EqPanel> with SingleTickerProviderStateMixin {
  late List<double> _bands;
  late bool _enabled;
  late String _preset;
  late bool _dialogueBoost;
  late bool _normalization;
  late TabController _tabCtrl;

  static const _accent = Color(0xFFE8002D);
  static const _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _bands         = List<double>.from(widget.prefs.equalizerBands);
    _enabled       = widget.prefs.equalizerEnabled;
    _preset        = widget.prefs.equalizerPreset;
    _dialogueBoost = widget.prefs.dialogueBoostEnabled;
    _normalization = widget.prefs.audioNormalization;
    _tabCtrl       = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.prefs.copyWith(
      equalizerEnabled: _enabled,
      equalizerPreset: _preset,
      equalizerBands: _bands,
      dialogueBoostEnabled: _dialogueBoost,
      audioNormalization: _normalization,
    ));
  }

  void _applyPreset(String p) {
    if (_presets[p] == null) return;
    setState(() {
      _preset = p;
      _bands  = List<double>.from(_presets[p]!);
      _enabled = p != 'flat';
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.fromLTRB(0, 10, 0, 8),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),

        // Tab bar: Audio Effect | Equalizer
        TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: _blue,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Audio Effect'), Tab(text: 'Equalizer')],
        ),

        // Tab content
        Flexible(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // ── Tab 1: Audio Effect Presets (MX Player screenshot 16 style) ──
              _buildAudioEffectTab(),
              // ── Tab 2: Equalizer Sliders ──
              _buildEqualizerTab(),
            ],
          ),
        ),

        // Done button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Row(children: [
            _EqChip('Dialogue Boost', Icons.record_voice_over_rounded, _dialogueBoost, (v) {
              setState(() { _dialogueBoost = v; if (v) { _enabled = false; } });
              _notify();
            }),
            const SizedBox(width: 8),
            _EqChip('Normalize', Icons.graphic_eq_rounded, _normalization, (v) {
              setState(() => _normalization = v);
              _notify();
            }),
            const Spacer(),
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Done', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildAudioEffectTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
        ),
        itemCount: _audioEffects.length,
        itemBuilder: (_, i) {
          final effect = _audioEffects[i];
          final presetKey = effect['preset'] as String;
          final isSelected = _preset == presetKey && _enabled;
          final isOriginal = presetKey == 'flat';
          return GestureDetector(
            onTap: () => _applyPreset(presetKey),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isOriginal ? _blue : _blue.withOpacity(0.7))
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? _blue : Colors.white12,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 10, spreadRadius: 1),
                ] : null,
              ),
              child: Row(children: [
                const SizedBox(width: 14),
                Icon(
                  effect['icon'] as IconData,
                  color: isSelected ? Colors.white : Colors.white54,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  effect['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEqualizerTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Enable toggle + preset chips
        Row(children: [
          const Text('EQ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Switch(value: _enabled, activeColor: _accent, onChanged: (v) { setState(() => _enabled = v); _notify(); }),
          const Spacer(),
          // Preset chips horizontal scroll
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _presets.keys.map((p) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(p[0].toUpperCase() + p.substring(1)),
                  selected: _preset == p,
                  selectedColor: _accent,
                  labelStyle: TextStyle(
                    color: _preset == p ? Colors.white : Colors.white60,
                    fontSize: 11,
                  ),
                  backgroundColor: Colors.white12,
                  onSelected: (_) => _applyPreset(p),
                ),
              )).toList()),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // 10-band sliders
        if (_enabled) SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_bands.length, (i) => Expanded(child:
              Column(children: [
                Expanded(child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _bands[i].clamp(-12.0, 12.0),
                    min: -12, max: 12,
                    activeColor: _accent,
                    inactiveColor: Colors.white12,
                    onChanged: (v) {
                      setState(() { _bands[i] = v; _preset = 'custom'; });
                      _notify();
                    },
                  ),
                )),
                Text(
                  _bands[i] == 0 ? '0' : (_bands[i] > 0 ? '+${_bands[i].toStringAsFixed(0)}' : '${_bands[i].toStringAsFixed(0)}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
                Text(_bandLabels[i], style: const TextStyle(color: Colors.white38, fontSize: 9)),
              ]),
            )).toList(),
          ),
        ).animate().fadeIn(duration: 200.ms),
      ]),
    );
  }
}

class _EqChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final ValueChanged<bool> onChanged;
  const _EqChip(this.label, this.icon, this.active, this.onChanged);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!active),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x33E8002D) : Colors.white10,
        border: Border.all(color: active ? const Color(0xFFE8002D) : Colors.white12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: active ? const Color(0xFFE8002D) : Colors.white60),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          color: active ? const Color(0xFFE8002D) : Colors.white60,
          fontSize: 12,
        )),
      ]),
    ),
  );
}
