import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// In-player quick settings bottom sheet — 5-tab MX Player-style layout.
/// Tabs: Quality | Speed | Aspect Ratio | Subtitles | Audio
class QuickSettingsPanel extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final VoidCallback onDone;
  final VoidCallback onOpenFullSettings;
  final int subDelayMs;
  final int audioDelayMs;
  final ValueChanged<int> onSubDelay;
  final ValueChanged<int> onAudioDelay;
  final VoidCallback onOpenSubSync;
  final VoidCallback onOpenAudioSync;
  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final String fitMode;
  final ValueChanged<String> onFitChanged;
  final String selectedQuality;
  final ValueChanged<String> onQualityChanged;

  const QuickSettingsPanel({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onDone,
    required this.onOpenFullSettings,
    required this.subDelayMs,
    required this.audioDelayMs,
    required this.onSubDelay,
    required this.onAudioDelay,
    required this.onOpenSubSync,
    required this.onOpenAudioSync,
    required this.speed,
    required this.onSpeedChanged,
    this.fitMode = 'Fit',
    required this.onFitChanged,
    this.selectedQuality = 'Auto',
    required this.onQualityChanged,
  });

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel>
    with SingleTickerProviderStateMixin {
  late PlayerPrefs _p;
  late TabController _tab;
  final _customSpeedCtrl = TextEditingController();
  String? _customSpeedError;

  static const _accent = Color(0xFFE8002D);
  static const _bg     = Color(0xFF12121E);
  static const _card   = Color(0xFF1A1A2A);

  @override
  void initState() {
    super.initState();
    _p = widget.prefs;
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _customSpeedCtrl.dispose();
    super.dispose();
  }

  void _update(PlayerPrefs next) {
    setState(() => _p = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Handle ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        // ── Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            const Text('Player Settings',
              style: TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onOpenFullSettings,
              icon: const Icon(Icons.tune_rounded, size: 14),
              label: const Text('Full Settings',
                style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Done',
                style: TextStyle(color: Colors.white60, fontSize: 13))),
          ]),
        ),
        // ── Tab Bar ────────────────────────────────────────────────────
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'Quality'),
            Tab(text: 'Speed'),
            Tab(text: 'Aspect Ratio'),
            Tab(text: 'Subtitles'),
            Tab(text: 'Audio'),
          ],
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── Tab Content ────────────────────────────────────────────────
        Flexible(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildQualityTab(),
              _buildSpeedTab(),
              _buildAspectTab(),
              _buildSubtitleTab(),
              _buildAudioTab(),
            ],
          ),
        ),
      ]),
    ).animate()
     .slideY(begin: 0.15, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
     .fadeIn(duration: 200.ms);
  }

  // ── Tab 1: Video Quality ─────────────────────────────────────────────────

  Widget _buildQualityTab() {
    const qualities = [
      _QualityEntry('Auto',   Icons.auto_awesome_rounded,  'Best available'),
      _QualityEntry('1080p',  Icons.hd_rounded,            'Full HD · ~2.5 GB/hr'),
      _QualityEntry('720p',   Icons.hd_outlined,           'HD · ~1.5 GB/hr'),
      _QualityEntry('480p',   Icons.sd_rounded,            'SD · ~700 MB/hr'),
      _QualityEntry('360p',   Icons.sd_outlined,           'Low · ~350 MB/hr'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionLabel('Select Quality'),
        const SizedBox(height: 10),
        ...qualities.map((q) {
          final isSel = q.label == widget.selectedQuality;
          return _SelectionTile(
            icon: q.icon,
            label: q.label,
            sublabel: q.sublabel,
            selected: isSel,
            onTap: () => widget.onQualityChanged(q.label),
          );
        }),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.white38),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Quality auto-adjusts to your connection. '
              'Manual selection applies from next seek.',
              style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ),
      ],
    );
  }

  // ── Tab 2: Playback Speed ────────────────────────────────────────────────

  Widget _buildSpeedTab() {
    const presets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionLabel('Preset Speed'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: presets.map((s) => _SpeedChip(
            speed: s,
            selected: (widget.speed - s).abs() < 0.01,
            onTap: () => widget.onSpeedChanged(s),
          )).toList(),
        ),
        const SizedBox(height: 20),
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),
        _SectionLabel('Custom Speed'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _customSpeedCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. 1.3',
                hintStyle: const TextStyle(color: Colors.white38),
                errorText: _customSpeedError,
                errorStyle: const TextStyle(fontSize: 11),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(_customSpeedCtrl.text.trim());
              if (val == null || val < 0.1 || val > 4.0) {
                setState(() => _customSpeedError = 'Enter 0.1 – 4.0');
              } else {
                setState(() { _customSpeedError = null; });
                widget.onSpeedChanged(val);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Set',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Current: ×${widget.speed.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  // ── Tab 3: Aspect Ratio ──────────────────────────────────────────────────

  Widget _buildAspectTab() {
    const options = [
      _AspectEntry('Default',  Icons.fit_screen_rounded,
        'Auto-detect best fit'),
      _AspectEntry('Fit',      Icons.aspect_ratio_rounded,
        'Letterbox / pillarbox — no cropping'),
      _AspectEntry('Fill',     Icons.fullscreen_rounded,
        'Stretch to fill — may distort'),
      _AspectEntry('Zoom',     Icons.crop_rounded,
        'Crop edges to fill screen'),
      _AspectEntry('4:3',      Icons.crop_square_rounded,
        'Classic TV / vintage ratio'),
      _AspectEntry('16:9',     Icons.crop_16_9_rounded,
        'Widescreen ratio'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionLabel('Aspect Ratio'),
        const SizedBox(height: 10),
        ...options.map((opt) {
          final isSel = opt.label == widget.fitMode ||
              (opt.label == 'Default' && widget.fitMode == 'Default');
          return _SelectionTile(
            icon: opt.icon,
            label: opt.label,
            sublabel: opt.sublabel,
            selected: isSel,
            onTap: () => widget.onFitChanged(opt.label),
          );
        }),
      ],
    );
  }

  // ── Tab 4: Subtitles ─────────────────────────────────────────────────────

  Widget _buildSubtitleTab() {
    const encodings = [
      'auto', 'UTF-8', 'UTF-16', 'ISO-8859-1', 'ISO-8859-2',
      'Windows-1250', 'Windows-1252', 'Shift-JIS', 'GBK',
    ];
    const positions = ['bottom', 'center', 'top'];
    const textColors = [
      0xFFFFFFFF, 0xFFFFFF00, 0xFFFFA500, 0xFF00FF00,
      0xFF00FFFF, 0xFFFF6B6B, 0xFFCCCCCC,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Enable
        _QRow('Subtitles', Icons.subtitles_outlined,
          Switch(value: _p.subtitleEnabled, activeColor: _accent,
            onChanged: (v) => _update(_p.copyWith(subtitleEnabled: v)))),
        const Divider(color: Colors.white10, height: 20),

        // Font Size
        _SectionLabel('Font Size'),
        Row(children: [
          Expanded(child: Slider(
            value: _p.subtitleFontSize.clamp(10, 40),
            min: 10, max: 40, divisions: 30,
            activeColor: _accent, inactiveColor: Colors.white12,
            onChanged: (v) => _update(_p.copyWith(subtitleFontSize: v)),
          )),
          SizedBox(width: 44, child: Text(
            '${_p.subtitleFontSize.toInt()}px',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.right)),
        ]),

        // Style
        _SectionLabel('Style'),
        const SizedBox(height: 8),
        Row(children: [
          _ToggleChip('Bold', _p.subtitleBold,
            () => _update(_p.copyWith(subtitleBold: !_p.subtitleBold))),
          const SizedBox(width: 8),
          _ToggleChip('Italic', _p.subtitleItalic,
            () => _update(_p.copyWith(subtitleItalic: !_p.subtitleItalic))),
          const SizedBox(width: 8),
          _ToggleChip('Auto-Detect', _p.subtitleAutoDetect,
            () => _update(_p.copyWith(subtitleAutoDetect: !_p.subtitleAutoDetect))),
        ]),
        const SizedBox(height: 16),

        // Text Color
        _SectionLabel('Text Color'),
        const SizedBox(height: 8),
        Row(children: textColors.map((c) {
          final isSel = c == _p.subtitleTextColorValue;
          return GestureDetector(
            onTap: () => _update(_p.copyWith(subtitleTextColorValue: c)),
            child: Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? Colors.white : Colors.white24,
                  width: isSel ? 2.5 : 1,
                ),
              ),
              child: isSel
                ? const Icon(Icons.check, size: 14, color: Colors.black)
                : null,
            ),
          );
        }).toList()),
        const SizedBox(height: 16),

        // Background Opacity
        _SectionLabel('Background Opacity'),
        Row(children: [
          Expanded(child: Slider(
            value: _p.subtitleBackgroundOpacity,
            min: 0, max: 1, divisions: 10,
            activeColor: _accent, inactiveColor: Colors.white12,
            onChanged: (v) =>
                _update(_p.copyWith(subtitleBackgroundOpacity: v)),
          )),
          SizedBox(width: 44, child: Text(
            '${(_p.subtitleBackgroundOpacity * 100).toInt()}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.right)),
        ]),

        // Position
        _SectionLabel('Position'),
        const SizedBox(height: 8),
        Row(children: positions.map((pos) => Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: _ToggleChip(
            pos[0].toUpperCase() + pos.substring(1),
            _p.subtitlePosition == pos,
            () => _update(_p.copyWith(subtitlePosition: pos)),
            expand: true),
        ))).toList()),
        const SizedBox(height: 16),

        // Encoding
        _SectionLabel('Encoding'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: encodings.contains(_p.subtitleEncoding)
                  ? _p.subtitleEncoding : 'auto',
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              isExpanded: true,
              items: encodings.map((e) => DropdownMenuItem(
                value: e, child: Text(e))).toList(),
              onChanged: (v) {
                if (v != null) _update(_p.copyWith(subtitleEncoding: v));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Sync
        _SectionLabel('Sync'),
        const SizedBox(height: 8),
        _SyncRow(
          label: 'Sub Sync',
          delayMs: widget.subDelayMs,
          onReset: () => widget.onSubDelay(0),
          onFull: widget.onOpenSubSync,
        ),
      ],
    );
  }

  // ── Tab 5: Audio ─────────────────────────────────────────────────────────

  Widget _buildAudioTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Volume Boost
        _SectionLabel('Volume Boost'),
        Row(children: [
          Expanded(child: Slider(
            value: _p.volumeBoostMultiplier,
            min: 1.0, max: 3.0, divisions: 20,
            activeColor: _p.volumeBoostMultiplier > 2.0
                ? Colors.red
                : _p.volumeBoostMultiplier > 1.5
                    ? Colors.orange : _accent,
            inactiveColor: Colors.white12,
            onChanged: (v) =>
                _update(_p.copyWith(volumeBoostMultiplier: v)),
          )),
          SizedBox(width: 48, child: Text(
            '${(_p.volumeBoostMultiplier * 100).toInt()}%',
            style: TextStyle(
              color: _p.volumeBoostMultiplier > 2.0 ? Colors.red
                  : _p.volumeBoostMultiplier > 1.5 ? Colors.orange
                  : Colors.white70,
              fontSize: 12, fontWeight: FontWeight.w600),
            textAlign: TextAlign.right)),
        ]),
        if (_p.volumeBoostMultiplier > 2.0)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('⚠ May distort audio at 300%',
              style: TextStyle(color: Colors.red, fontSize: 11)))
        else if (_p.volumeBoostMultiplier > 1.5)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('⚠ High volume — use with caution',
              style: TextStyle(color: Colors.orange, fontSize: 11))),

        const Divider(color: Colors.white10, height: 24),
        _SectionLabel('Processing'),
        const SizedBox(height: 8),
        _QRow('Dialogue Boost', Icons.record_voice_over_rounded,
          Switch(value: _p.dialogueBoostEnabled, activeColor: _accent,
            onChanged: (v) =>
                _update(_p.copyWith(dialogueBoostEnabled: v)))),
        _QRow('Audio Normalization', Icons.equalizer_rounded,
          Switch(value: _p.audioNormalization, activeColor: _accent,
            onChanged: (v) =>
                _update(_p.copyWith(audioNormalization: v)))),
        _QRow('Deinterlace', Icons.blur_linear_rounded,
          Switch(value: _p.deinterlaceEnabled, activeColor: _accent,
            onChanged: (v) =>
                _update(_p.copyWith(deinterlaceEnabled: v)))),

        const Divider(color: Colors.white10, height: 24),
        _SectionLabel('Decoder'),
        const SizedBox(height: 8),
        _QRow('Hardware Decoder', Icons.memory_rounded,
          Switch(value: _p.hwDecoderEnabled, activeColor: _accent,
            onChanged: (v) =>
                _update(_p.copyWith(hwDecoderEnabled: v)))),
        const Padding(
          padding: EdgeInsets.only(left: 32, bottom: 4),
          child: Text('Disable if video stutters or crashes',
            style: TextStyle(color: Colors.white38, fontSize: 11))),

        const Divider(color: Colors.white10, height: 24),
        _SectionLabel('Sync'),
        const SizedBox(height: 8),
        _SyncRow(
          label: 'Audio Sync',
          delayMs: widget.audioDelayMs,
          onReset: () => widget.onAudioDelay(0),
          onFull: widget.onOpenAudioSync,
        ),
      ],
    );
  }
}

// ── Data Classes ──────────────────────────────────────────────────────────────

class _QualityEntry {
  final String label, sublabel;
  final IconData icon;
  const _QualityEntry(this.label, this.icon, this.sublabel);
}

class _AspectEntry {
  final String label, sublabel;
  final IconData icon;
  const _AspectEntry(this.label, this.icon, this.sublabel);
}

// ── Shared Tile Widgets ───────────────────────────────────────────────────────

class _SelectionTile extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final bool selected;
  final VoidCallback onTap;
  const _SelectionTile({
    required this.icon, required this.label, required this.sublabel,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE8002D).withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFE8002D) : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 18,
            color: selected ? const Color(0xFFE8002D) : Colors.white38),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sublabel, style: const TextStyle(
                color: Colors.white38, fontSize: 11)),
            ])),
          if (selected)
            const Icon(Icons.check_circle_rounded,
              size: 18, color: Color(0xFFE8002D)),
        ]),
      ),
    );
  }
}

// ── Utility Row / Label Widgets ───────────────────────────────────────────────

class _QRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget trailing;
  const _QRow(this.label, this.icon, this.trailing);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 17, color: Colors.white54),
    const SizedBox(width: 10),
    Expanded(child: Text(label,
      style: const TextStyle(color: Colors.white, fontSize: 13))),
    trailing,
  ]);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(
      color: Colors.white54, fontSize: 11,
      letterSpacing: 0.8, fontWeight: FontWeight.w600));
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;
  const _ToggleChip(this.label, this.selected, this.onTap,
    {this.expand = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8002D) : Colors.white12,
        borderRadius: BorderRadius.circular(6)),
      alignment: expand ? Alignment.center : null,
      child: Text(label, style: TextStyle(
        color: selected ? Colors.white : Colors.white60,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
    ),
  );
}

class _SpeedChip extends StatelessWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;
  const _SpeedChip({required this.speed, required this.selected,
    required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8002D) : Colors.white12,
        borderRadius: BorderRadius.circular(8)),
      child: Text(speed == 1.0 ? '×1.0' : '×$speed',
        style: TextStyle(
          color: selected ? Colors.white : Colors.white60,
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
    ),
  );
}

class _SyncRow extends StatelessWidget {
  final String label;
  final int delayMs;
  final VoidCallback onReset;
  final VoidCallback onFull;
  const _SyncRow({required this.label, required this.delayMs,
    required this.onReset, required this.onFull});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label,
      style: const TextStyle(color: Colors.white70, fontSize: 13))),
    Text(delayMs == 0 ? '+0ms' : '${delayMs > 0 ? '+' : ''}${delayMs}ms',
      style: TextStyle(
        color: delayMs == 0 ? Colors.white38 : const Color(0xFFE8002D),
        fontWeight: FontWeight.w600, fontSize: 12)),
    if (delayMs != 0) ...[
      const SizedBox(width: 4),
      GestureDetector(onTap: onReset,
        child: const Icon(Icons.refresh_rounded,
          size: 14, color: Color(0xFFE8002D))),
    ],
    const SizedBox(width: 8),
    TextButton(onPressed: onFull,
      child: const Text('Full Sync →',
        style: TextStyle(color: Color(0xFFE8002D), fontSize: 11))),
  ]);
}
