import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';

/// In-player quick settings — 5-tab MX Player-style layout.
/// Tabs: Style | Screen | Controls | Navigation | Text
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

  // ── Screen tab local state ─────────────────────────────────────────────────
  bool _autoSwitch     = true;
  bool _autoHide       = true;
  bool _softButtons    = false;
  double _brightness   = 1.0;
  bool _showBattery    = false;
  bool _showClock      = false;
  bool _showElapsed    = false;
  int _cornerOffset    = 20;
  String _background   = 'Black';

  // ── Controls tab local state ───────────────────────────────────────────────
  String _touchAction  = 'pause_resume';  // 'pause_resume' | 'lock'
  bool _showFwdBtn     = true;
  bool _showPrevNext   = false;

  // ── Navigation tab local state ────────────────────────────────────────────
  double _seekSpeed    = 10.0;
  double _moveInterval = 10.0;
  bool _showPosition   = true;

  // ── Style tab local state ─────────────────────────────────────────────────
  String _preset         = 'Default';
  String _progressPos    = 'above';   // 'above' | 'below'
  bool   _materialStyle  = true;
  String _controlsDensity = 'medium'; // 'small'/'medium'/'large'

  // ── Text tab local state ───────────────────────────────────────────────────
  double _subtitleScale    = 1.0;
  bool   _improveStroke    = false;
  bool   _fadeOut          = false;

  static const _accent = Color(0xFF1565C0);
  static const _bg     = Color(0xFF12121E);

  @override
  void initState() {
    super.initState();
    _p = widget.prefs;
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
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
          maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Handle ─────────────────────────────────────────────────────────
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            GestureDetector(
              onTap: widget.onDone,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Player Settings',
                style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: widget.onOpenFullSettings,
              icon: const Icon(Icons.tune_rounded, size: 14),
              label: const Text('Full', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: _accent.withOpacity(0.8)),
            ),
          ]),
        ),
        // ── Tab Bar ────────────────────────────────────────────────────────
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'Style'),
            Tab(text: 'Screen'),
            Tab(text: 'Controls'),
            Tab(text: 'Navigation'),
            Tab(text: 'Text'),
          ],
        ),
        const Divider(height: 1, color: Colors.white12),
        // ── Tab Content ─────────────────────────────────────────────────────
        Flexible(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildStyleTab(),
              _buildScreenTab(),
              _buildControlsTab(),
              _buildNavigationTab(),
              _buildTextTab(),
            ],
          ),
        ),
      ]),
    )
    .animate()
    .slideY(begin: 0.12, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
    .fadeIn(duration: 200.ms);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1 — STYLE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStyleTab() {
    const presets = ['Default', 'Float', 'Lock'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        // Preset
        _QsRow(
          label: 'Preset',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _preset,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              isDense: true,
              items: presets.map((p) => DropdownMenuItem(
                  value: p, child: Text(p))).toList(),
              onChanged: (v) { if (v != null) setState(() => _preset = v); },
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Frame style
        _QsRow(
          label: 'Frame',
          child: const Icon(Icons.open_in_full_rounded, color: Colors.white54, size: 20),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Controls (size/density)
        _QsRow(
          label: 'Controls',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _SizeChip('S', _controlsDensity == 'small',
                () => setState(() => _controlsDensity = 'small')),
            const SizedBox(width: 4),
            _SizeChip('M', _controlsDensity == 'medium',
                () => setState(() => _controlsDensity = 'medium')),
            const SizedBox(width: 4),
            _SizeChip('L', _controlsDensity == 'large',
                () => setState(() => _controlsDensity = 'large')),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Progress bar style  
        _QsLabel('Progress bar'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _StyleOption(label: 'Line', selected: !_materialStyle,
                onTap: () => setState(() => _materialStyle = false),
                child: Container(
                  width: 60, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft, widthFactor: 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8002D),
                        borderRadius: BorderRadius.circular(2))),
                  ),
                )),
            _StyleOption(label: 'Material', selected: _materialStyle,
                onTap: () => setState(() => _materialStyle = true),
                child: Container(
                  width: 60, height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft, widthFactor: 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8002D),
                        borderRadius: BorderRadius.circular(4))),
                  ),
                )),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Place progress bar below buttons
        _QsToggleRow(
          label: 'Place progress bar below buttons',
          value: _progressPos == 'below',
          onChanged: (v) => setState(() => _progressPos = v ? 'below' : 'above'),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Material design style
        _QsToggleRow(
          label: 'Material',
          value: _materialStyle,
          onChanged: (v) => setState(() => _materialStyle = v),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2 — SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildScreenTab() {
    final backgrounds = ['Black', 'Blur', 'Color', 'Off'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        // Orientation section
        _QsLabel('Orientation'),
        _QsRow(label: 'Use video orientation',
          child: const Text('', style: TextStyle(color: Colors.white70, fontSize: 13))),
        _QsToggleRow(label: 'Auto Switch', value: _autoSwitch,
            onChanged: (v) => setState(() => _autoSwitch = v)),
        const Divider(color: Colors.white10, height: 1),

        // Full screen
        _QsLabel('Full Screen'),
        _QsToggleRow(label: 'Auto hide', value: _autoHide,
            onChanged: (v) => setState(() => _autoHide = v)),
        _QsToggleRow(label: 'Soft buttons', value: _softButtons,
            onChanged: (v) => setState(() => _softButtons = v)),
        const Divider(color: Colors.white10, height: 1),

        // Brightness
        _QsLabel('Brightness'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            const Icon(Icons.brightness_low_rounded, color: Colors.white38, size: 18),
            Expanded(child: Slider(
              value: _brightness,
              min: 0, max: 1, divisions: 20,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _brightness = v),
            )),
            const Icon(Icons.brightness_high_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 4),
            SizedBox(width: 40, child: Text(
              '${(_brightness * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Status bar info toggles
        _QsLabel('Status bar'),
        _QsToggleRow(label: 'Battery', value: _showBattery,
            onChanged: (v) => setState(() => _showBattery = v)),
        _QsToggleRow(label: 'Clock', value: _showClock,
            onChanged: (v) => setState(() => _showClock = v)),
        _QsToggleRow(label: 'Elapsed time', value: _showElapsed,
            onChanged: (v) => setState(() => _showElapsed = v)),
        const Divider(color: Colors.white10, height: 1),

        // Corner offset
        _QsLabel('Corner offset'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: _cornerOffset.toDouble(),
              min: 0, max: 60, divisions: 60,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _cornerOffset = v.toInt()),
            )),
            SizedBox(width: 36, child: Text(
              '$_cornerOffset',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Background
        _QsLabel('Background'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(spacing: 8, children: backgrounds.map((b) {
            final isSel = b == _background;
            return GestureDetector(
              onTap: () => setState(() => _background = b),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? _accent.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel ? _accent : Colors.white12,
                    width: isSel ? 1.5 : 1),
                ),
                child: Text(b, style: TextStyle(
                  color: isSel ? Colors.white : Colors.white60,
                  fontSize: 12, fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList()),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3 — CONTROLS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        // Touch action
        _QsLabel('Touch action'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            _TouchActionBtn(
              icon: Icons.pause_circle_outline_rounded,
              label: 'Pause/resume',
              selected: _touchAction == 'pause_resume',
              onTap: () => setState(() => _touchAction = 'pause_resume'),
            ),
            const SizedBox(width: 12),
            _TouchActionBtn(
              icon: Icons.lock_outline_rounded,
              label: 'Lock',
              selected: _touchAction == 'lock',
              onTap: () => setState(() => _touchAction = 'lock'),
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Lock mode
        _QsLabel('Lock mode'),
        _QsRow(
          label: 'Touch controls when locked',
          child: Switch(
            value: false,
            activeColor: _accent,
            onChanged: (_) {},
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Gestures
        _QsLabel('Gestures'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            _GestureChip(icon: Icons.play_arrow_rounded,  label: 'Play/Pause\n(Double tap)'),
            _GestureChip(icon: Icons.volume_up_rounded,   label: 'Volume\n(Double tap)'),
            _GestureChip(icon: Icons.zoom_in_rounded,     label: 'Video zoom'),
            _GestureChip(icon: Icons.linear_scale_rounded,label: 'Seek position'),
            _GestureChip(icon: Icons.zoom_out_map_rounded,label: 'Zoom and Pan'),
            _GestureChip(icon: Icons.pan_tool_alt_rounded, label: 'Video pan'),
            _GestureChip(icon: Icons.brightness_medium_rounded, label: 'Brightness\n(Double tap)'),
            _GestureChip(icon: Icons.zoom_in_map_rounded, label: 'Video zoom\n(Double tap)'),
            _GestureChip(icon: Icons.fast_forward_rounded, label: 'Speed FF\n(Long press)'),
          ]),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 4 — NAVIGATION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildNavigationTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        // Seek speed
        _QsLabel('Seek Speed (sec./inch)'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: _seekSpeed,
              min: 1, max: 60, divisions: 59,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _seekSpeed = v),
            )),
            SizedBox(width: 36, child: Text(
              _seekSpeed.toInt().toString(),
              style: const TextStyle(color: Colors.white70, fontSize: 14,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Forward/backward moving button
        _QsRow(
          label: 'Forward/backward moving button',
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.fast_forward_rounded,
                color: Colors.white54, size: 18),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Move Interval
        _QsLabel('Move Interval (sec.)'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: _moveInterval,
              min: 1, max: 60, divisions: 59,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _moveInterval = v),
            )),
            SizedBox(width: 36, child: Text(
              _moveInterval.toInt().toString(),
              style: const TextStyle(color: Colors.white70, fontSize: 14,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Previous/next button
        _QsRow(
          label: 'Previous/next button',
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.skip_next_rounded,
                color: Colors.white54, size: 18),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Display current position while changing position
        _QsToggleRow(
          label: 'Display the current position while changing position',
          value: _showPosition,
          onChanged: (v) => setState(() => _showPosition = v),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 5 — TEXT (subtitle appearance)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTextTab() {
    const fonts = ['Sans Serif', 'Serif', 'Monospace', 'Cursive', 'Default'];
    final size = _p.subtitleFontSize;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
        // Font
        _QsRow(
          label: 'Font',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: fonts.contains(_p.subtitleFontFamily)
                  ? _p.subtitleFontFamily : 'Sans Serif',
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              isDense: true,
              items: fonts.map((f) => DropdownMenuItem(
                  value: f, child: Text(f))).toList(),
              onChanged: (v) {
                if (v != null) _update(_p.copyWith(subtitleFontFamily: v));
              },
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Size
        _QsLabel('Size'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: size.clamp(8, 60),
              min: 8, max: 60, divisions: 52,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => _update(_p.copyWith(subtitleFontSize: v)),
            )),
            SizedBox(width: 36, child: Text(size.toInt().toString(),
              style: const TextStyle(color: Colors.white70, fontSize: 14,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Scale
        _QsLabel('Scale'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(child: Slider(
              value: (scale * 100).clamp(50, 200),
              min: 50, max: 200, divisions: 150,
              activeColor: _accent,
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _subtitleScale = v / 100),
            )),
            SizedBox(width: 48, child: Text(
              '${(scale * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 14,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Color + Bold
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Text('Color',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Color(_p.subtitleTextColorValue),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
            ),
            const SizedBox(width: 24),
            const Text('Background Color',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
            ),
            const Spacer(),
            // Bold toggle button (MX Player: blue selected square)
            GestureDetector(
              onTap: () => _update(_p.copyWith(subtitleBold: !_p.subtitleBold)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _p.subtitleBold ? _accent : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _p.subtitleBold ? _accent : Colors.white24),
                ),
                child: Icon(Icons.format_bold_rounded,
                    color: _p.subtitleBold ? Colors.white : Colors.white54, size: 20),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Border + Shadow swatches
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Text('Border',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
            ),
            const SizedBox(width: 24),
            const Text('Shadow',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Improve stroke rendering
        _QsToggleRow(
          label: 'Improve stroke rendering',
          value: _improveStroke,
          onChanged: (v) => setState(() => _improveStroke = v),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Fade out
        _QsToggleRow(
          label: 'Fade out',
          value: _fadeOut,
          onChanged: (v) => setState(() => _fadeOut = v),
        ),
      ],
    );
  }
}

// ── Shared UI helpers ──────────────────────────────────────────────────────────

class _QsLabel extends StatelessWidget {
  final String text;
  const _QsLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: const TextStyle(
        color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600,
        letterSpacing: 0.4)),
  );
}

class _QsRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _QsRow({required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 13))),
      child,
    ]),
  );
}

class _QsToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _QsToggleRow({required this.label, required this.value,
      required this.onChanged});
  static const _accent = Color(0xFF1565C0);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Switch(
          value: value,
          activeColor: _accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ]),
    ),
  );
}

class _SizeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SizeChip(this.label, this.selected, this.onTap);
  static const _accent = Color(0xFF1565C0);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32, height: 28,
      decoration: BoxDecoration(
        color: selected ? _accent : Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? _accent : Colors.white24),
      ),
      child: Center(child: Text(label, style: TextStyle(
        color: selected ? Colors.white : Colors.white60,
        fontSize: 12, fontWeight: FontWeight.w600))),
    ),
  );
}

class _StyleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _StyleOption({required this.label, required this.selected,
      required this.onTap, required this.child});
  static const _accent = Color(0xFF1565C0);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? _accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _accent : Colors.white12,
            width: selected ? 1.5 : 1.0),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        const SizedBox(height: 6),
        Text(label, style: TextStyle(
          color: selected ? Colors.white : Colors.white54,
          fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ]),
    ),
  );
}

class _TouchActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TouchActionBtn({required this.icon, required this.label,
      required this.selected, required this.onTap});
  static const _accent = Color(0xFF1565C0);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _accent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _accent : Colors.white12,
            width: selected ? 1.5 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: selected ? Colors.white : Colors.white54, size: 24),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
          color: selected ? Colors.white : Colors.white60,
          fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ]),
    ),
  );
}

class _GestureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GestureChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    width: 86,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white54, size: 20),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, height: 1.3),
          textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );
}
