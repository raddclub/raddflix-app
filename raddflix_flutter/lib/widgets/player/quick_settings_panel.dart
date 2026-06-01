import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/player_prefs.dart';
import '../../../core/player/video_look_filter.dart'; // D2
import '../../../core/player/end_of_video_actions.dart'; // M3
import '../../../core/player/smart_skip_service.dart'; // M4
import '../../../core/player/audio_lab_service.dart'; // E1-E4
import '../../../core/services/wake_lock_service.dart'; // H4
import 'voice_commands_service.dart'; // J1
import 'audio_lab_panel.dart'; // E1-E4
import '../../../core/player/speed_presets_sheet.dart'; // M1
import 'film_grain_overlay.dart'; // D3
import '../../../core/player/player_theme.dart';
import '../../../core/player/icon_packs.dart';
import 'color_picker_sheet.dart';
import 'seek_bar_painter.dart';
import 'theme_picker_sheet.dart';
import 'gesture_map_sheet.dart';
import 'picture_profiles_sheet.dart';

/// In-player quick settings — 5-tab MX Player-style layout.
/// Tabs: Style | Screen | Controls | Navigation | Text
class QuickSettingsPanel extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onChanged;
  final VoidCallback onDone;
  final VoidCallback onOpenFullSettings;
  final VoidCallback onOpenGestureMap;
  final VoidCallback onOpenPictureProfiles;
  final VoidCallback onOpenAudioLab;
  final VoidCallback onOpenSkipEditor;
  final VoidCallback onOpenJumpTo;
  final VoidCallback onOpenSpeedPresets;
  final VoidCallback onOpenEndAction;
  final VoidCallback onOpenSilenceSkip;
  final VoidCallback onOpenZoomCrop;
  final VoidCallback onOpenWakeDnd;   // opens wake lock / DND sheet
  final VoidCallback? onOpenLayoutDesigner; // Phase B: drag-drop layout editor
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
    required this.onOpenGestureMap,
    required this.onOpenPictureProfiles,
    required this.onOpenAudioLab,
    required this.onOpenSkipEditor,
    required this.onOpenJumpTo,
    required this.onOpenSpeedPresets,
    required this.onOpenEndAction,
    required this.onOpenSilenceSkip,
    required this.onOpenZoomCrop,
    required this.onOpenWakeDnd,
    this.onOpenLayoutDesigner,
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
  String _touchAction  = 'pause_resume';
  bool _showFwdBtn     = true;
  bool _showPrevNext   = false;

  // ── Navigation tab local state ────────────────────────────────────────────
  double _seekSpeed    = 10.0;
  double _moveInterval = 10.0;
  bool _showPosition   = true;

  // ── Style tab local state ─────────────────────────────────────────────────
  String _preset         = 'Default';
  String _progressPos    = 'above';
  bool   _materialStyle  = true;
  String _controlsDensity = 'medium';

  // ── Phase A3/A4 local state ───────────────────────────────────────────────
  // (driven by _p.buttonShape, _p.iconPack, _p.controlsBgStyle)

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
    final playerAccent = _p.accentColor;
    final currentTheme = themeById(_p.playerTheme);
    final currentSeekStyle = seekBarStyleFromString(_p.seekBarStyle);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [

        // ── THEME ────────────────────────────────────────────────────────
        _QsLabel('Theme'),
        InkWell(
          onTap: () => showThemePicker(
            context: context,
            currentThemeId: _p.playerTheme,
            onThemeSelected: (theme) {
              _update(_p.copyWith(
                playerTheme: theme.id,
                accentColorValue: theme.accentColor.value,
                seekBarStyle: theme.seekBarStyle,
              ));
            },
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Text(currentTheme.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Text(currentTheme.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ]),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── PLAYER COLOUR ─────────────────────────────────────────────────
        _QsLabel('Player Colour'),
        InkWell(
          onTap: () => showColorPicker(
            context: context,
            initialColor: playerAccent,
            onColorSelected: (c) {
              _update(_p.copyWith(accentColorValue: c.value));
            },
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: playerAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 2),
                  boxShadow: [BoxShadow(color: playerAccent.withOpacity(0.4), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(
                '#${playerAccent.value.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}',
                style: const TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'monospace'))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ]),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── SEEK BAR STYLE ────────────────────────────────────────────────
        _QsLabel('Seek Bar Style'),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: SeekBarStyle.values.map((style) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SeekBarStylePreview(
                  style: style,
                  accentColor: playerAccent,
                  selected: currentSeekStyle == style,
                  onTap: () => _update(_p.copyWith(seekBarStyle: style.name)),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── BUTTON SHAPE ─────────────────────────────────────────────────
        _QsLabel('Button Shape'),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: const [
              {'id': 'circle',   'label': 'Circle',   'radius': 34.0},
              {'id': 'squircle', 'label': 'Squircle', 'radius': 14.0},
              {'id': 'rounded',  'label': 'Rounded',  'radius': 8.0},
              {'id': 'sharp',    'label': 'Sharp',    'radius': 2.0},
              {'id': 'pill',     'label': 'Pill',     'radius': 24.0},
            ].map<Widget>((shape) {
              final id    = shape['id']    as String;
              final label = shape['label'] as String;
              final r     = shape['radius'] as double;
              return _buildShapeChip(id, label, r, playerAccent);
            }).toList(),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── ICON PACK ────────────────────────────────────────────────────
        _QsLabel('Icon Pack'),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: [
              {'id': 'mx',        'label': 'MX',       'icon': Icons.play_arrow_rounded},
              {'id': 'ios',       'label': 'iOS',      'icon': Icons.play_circle_outline},
              {'id': 'fluent',    'label': 'Fluent',   'icon': Icons.play_arrow},
              {'id': 'material3', 'label': 'M3',       'icon': Icons.play_arrow_rounded},
              {'id': 'cute',      'label': 'Cute',     'icon': Icons.play_circle_filled_rounded},
              {'id': 'minimal',   'label': 'Minimal',  'icon': Icons.play_arrow},
            ].map<Widget>((pack) {
              final id     = pack['id']    as String;
              final label  = pack['label'] as String;
              final icon   = pack['icon']  as IconData;
              final sel    = _p.iconPack == id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _update(_p.copyWith(iconPack: id)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 72,
                    decoration: BoxDecoration(
                      color: sel ? playerAccent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel ? playerAccent : Colors.white12,
                        width: sel ? 1.5 : 1),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: sel ? playerAccent : Colors.white54, size: 22),
                      const SizedBox(height: 4),
                      Text(label, style: TextStyle(
                        color: sel ? Colors.white : Colors.white54,
                        fontSize: 10, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── CONTROLS BACKGROUND ──────────────────────────────────────────
        // ── Phase D2: Color Look Presets ────────────────────────────────────
        _QsLabel('Color Look'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: videoLookIds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final id = videoLookIds[i];
                final active = _p.colorLook == id;
                return GestureDetector(
                  onTap: () => _update(_p.copyWith(colorLook: id)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _accent.withOpacity(0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: active ? _accent : Colors.white24, width: 1)),
                    child: Text(
                      videoLookLabel[id] ?? id,
                      style: TextStyle(
                          color: active ? _accent : Colors.white60,
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase D3: Film Grain / Film Look ─────────────────────────────────
        _QsLabel('Film Grain'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            ...filmGrainLevels.map((lvl) {
              final active = _p.filmGrainLevel == lvl;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _update(_p.copyWith(filmGrainLevel: lvl)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? _accent.withOpacity(0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: active ? _accent : Colors.white24)),
                    child: Text(
                      filmGrainLabels[lvl] ?? lvl,
                      style: TextStyle(
                          color: active ? _accent : Colors.white60,
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              );
            }),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        _QsLabel('Controls Background'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(spacing: 8, runSpacing: 8,
            children: [
              {'id': 'none',     'label': 'None'},
              {'id': 'glass',    'label': 'Glass'},
              {'id': 'gradient', 'label': 'Gradient'},
              {'id': 'solid',    'label': 'Solid'},
              {'id': 'mesh',     'label': 'Mesh'},
            ].map<Widget>((s) {
              final id    = s['id']!;
              final label = s['label']!;
              final sel   = _p.controlsBgStyle == id;
              return GestureDetector(
                onTap: () => _update(_p.copyWith(controlsBgStyle: id)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? playerAccent.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? playerAccent : Colors.white12,
                      width: sel ? 1.5 : 1),
                  ),
                  child: Text(label, style: TextStyle(
                    color: sel ? Colors.white : Colors.white60,
                    fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── PRESET ───────────────────────────────────────────────────────
        _QsLabel('Preset'),
        _QsRow(
          label: 'Layout',
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
        // Controls density
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
                        color: playerAccent,
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
                        color: playerAccent,
                        borderRadius: BorderRadius.circular(4))),
                  ),
                )),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        _QsToggleRow(
          label: 'Place progress bar below buttons',
          value: _progressPos == 'below',
          onChanged: (v) => setState(() => _progressPos = v ? 'below' : 'above'),
        ),
        const Divider(color: Colors.white10, height: 1),
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
        // ── Phase L1: Enhanced Screenshot ─────────────────────────────────────
        _QsToggleRow(
          label: 'Screenshot Watermark',
          sublabel: 'Title + timestamp overlay on captured frames',
          value: _p.screenshotWatermark,
          onChanged: (v) => _update(_p.copyWith(screenshotWatermark: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Picture Profiles ──────────────────────────────────────────────
        _QsLabel('Picture Profile'),
        InkWell(
          onTap: widget.onOpenPictureProfiles,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white10,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.photo_filter_rounded, color: Colors.white54, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Picture Profile', style: TextStyle(color: Colors.white, fontSize: 13)),
                Text(_p.pictureProfile[0].toUpperCase() + _p.pictureProfile.substring(1),
                    style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w500)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
            ]),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        _QsLabel('Orientation'),
        _QsRow(label: 'Use video orientation',
          child: const Text('', style: TextStyle(color: Colors.white70, fontSize: 13))),
        _QsToggleRow(label: 'Auto Switch', value: _autoSwitch,
            onChanged: (v) => setState(() => _autoSwitch = v)),
        const Divider(color: Colors.white10, height: 1),

        _QsLabel('Full Screen'),
        _QsToggleRow(label: 'Auto hide', value: _autoHide,
            onChanged: (v) => setState(() => _autoHide = v)),
        _QsToggleRow(label: 'Soft buttons', value: _softButtons,
            onChanged: (v) => setState(() => _softButtons = v)),
        const Divider(color: Colors.white10, height: 1),

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

        _QsLabel('Status bar'),
        _QsToggleRow(label: 'Battery', value: _showBattery,
            onChanged: (v) => setState(() => _showBattery = v)),
        _QsToggleRow(label: 'Clock', value: _showClock,
            onChanged: (v) => setState(() => _showClock = v)),
        _QsToggleRow(label: 'Elapsed time', value: _showElapsed,
            onChanged: (v) => setState(() => _showElapsed = v)),
        const Divider(color: Colors.white10, height: 1),

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

        const Divider(color: Colors.white10, height: 1),

        // ── Phase H4/H5: Wake & DND ────────────────────────────────────────
        _QsLabel('Sleep & Focus'),
        _QsRow(
          label: 'Screen Wake',
          child: DropdownButton<int>(
            value: _p.wakeTimeoutMins,
            dropdownColor: const Color(0xFF1A1A2E),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0,  child: Text('Always On')),
              DropdownMenuItem(value: 10, child: Text('10 min')),
              DropdownMenuItem(value: 20, child: Text('20 min')),
              DropdownMenuItem(value: 30, child: Text('30 min')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _update(_p.copyWith(wakeTimeoutMins: v));
            },
          ),
        ),
        _QsToggleRow(
          label: 'DND in Cinematic Mode',
          value: _p.dndOnCinematic,
          onChanged: (v) => _update(_p.copyWith(dndOnCinematic: v)),
        ),

        const Divider(color: Colors.white10, height: 1),

        // ── Phase H1: One-Handed Mode ─────────────────────────────────────
        _QsLabel('One-Handed Mode'),
        _QsToggleRow(
          label: 'Enable',
          value: _p.oneHandedModeEnabled,
          onChanged: (v) => _update(_p.copyWith(oneHandedModeEnabled: v)),
        ),
        if (_p.oneHandedModeEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
              const Text('Side: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              _ModeChip('Right', _p.oneHandedModeSide == 'right', _accent,
                () => _update(_p.copyWith(oneHandedModeSide: 'right'))),
              const SizedBox(width: 8),
              _ModeChip('Left',  _p.oneHandedModeSide == 'left',  _accent,
                () => _update(_p.copyWith(oneHandedModeSide: 'left'))),
            ]),
          ),
        const Divider(color: Colors.white10, height: 1),

        // ── Phase K2: Screenshot Lock ─────────────────────────────────────
        _QsLabel('Privacy'),
        _QsToggleRow(
          label: 'Screenshot Lock',
          value: _p.screenshotLockEnabled,
          onChanged: (v) => _update(_p.copyWith(screenshotLockEnabled: v)),
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

        // ── Phase M1: Speed Presets ────────────────────────────────────────
        _QsLabel('Speed Presets'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            children: speedPresetsFromString(_p.speedPresets).map((s) {
              return GestureDetector(
                onTap: () {
                  // directly set speed (player wires this externally)
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white20)),
                  child: Text('\${s}×',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ),
              );
            }).toList()
              ..add(GestureDetector(
                onTap: () => SpeedPresetsSheet.show(
                  context,
                  currentSpeed: 1.0,
                  presets: speedPresetsFromString(_p.speedPresets),
                  onSpeedSelected: (_) {},
                  onPresetsChanged: (l) => _update(_p.copyWith(
                      speedPresets: speedPresetsToString(l))),
                  accentColor: _accent,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withOpacity(0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_rounded, color: _accent, size: 14),
                    const SizedBox(width: 4),
                    Text('Edit', style: TextStyle(color: _accent, fontSize: 12)),
                  ]),
                ),
              )),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase M3: End-of-Video Action ────────────────────────────────────
        _QsLabel('When video ends'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: EndActionPicker(
            current: endActionFromString(_p.endAction),
            onChanged: (a) => _update(_p.copyWith(endAction: endActionToString(a))),
            accentColor: _accent,
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase M4: Smart Skip ───────────────────────────────────────────────
        _QsLabel('Smart Skip'),
        SmartSkipPanel(
          config: SmartSkipConfig.decode(_p.smartSkipConfig),
          onChanged: (c) => _update(_p.copyWith(smartSkipConfig: c.encode())),
          accentColor: _accent,
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase H4: Wake Lock Options ─────────────────────────────────────
        _QsLabel('Screen Wake Lock'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: wakeLockTimeoutOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final mins = wakeLockTimeoutOptions[i];
                final active = _p.wakeLockTimeoutMinutes == mins;
                return GestureDetector(
                  onTap: () => _update(_p.copyWith(wakeLockTimeoutMinutes: mins)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _accent.withOpacity(0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: active ? _accent : Colors.white24, width: 1)),
                    child: Text(wakeLockLabel(mins),
                        style: TextStyle(
                            color: active ? _accent : Colors.white60,
                            fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                );
              },
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase H5: Do Not Disturb ───────────────────────────────────────────
        _QsToggleRow(
          label: 'DND on Cinematic Mode',
          sublabel: 'Silence notifications when in Cinematic / Immersive mode',
          value: _p.dndOnCinematic,
          onChanged: (v) => _update(_p.copyWith(dndOnCinematic: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase J1: Voice Commands ───────────────────────────────────────────
        _QsToggleRow(
          label: 'Voice Commands',
          sublabel: '"skip 2 minutes" · "louder" · "speed 1.5" · "subtitles off"',
          value: _p.voiceCommandsEnabled,
          onChanged: (v) => _update(_p.copyWith(voiceCommandsEnabled: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase J4: Motor Impairment Mode ────────────────────────────────────
        _QsToggleRow(
          label: 'Motor Impairment Mode',
          sublabel: 'Larger touch targets · hold-to-seek · slow double-tap',
          value: _p.motorImpairmentMode,
          onChanged: (v) => _update(_p.copyWith(motorImpairmentMode: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase I2: Reaction Stamps ────────────────────────────────────────
        _QsToggleRow(
          label: 'Reaction Stamps',
          sublabel: 'Show emoji reaction panel during playback',
          value: _p.reactionsEnabled,
          onChanged: (v) => _update(_p.copyWith(reactionsEnabled: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase L3: Focus / Zoom Mode ──────────────────────────────────────
        _QsToggleRow(
          label: 'Focus Mode (Zoom Lens)',
          sublabel: 'Long-press to activate — drag to move magnifying lens',
          value: _p.focusModeEnabled,
          onChanged: (v) => _update(_p.copyWith(focusModeEnabled: v)),
        ),
        const Divider(color: Colors.white10, height: 1),
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
        const Divider(color: Colors.white10, height: 1),
        InkWell(
          onTap: widget.onOpenGestureMap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white10,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.touch_app_rounded, color: Colors.white54, size: 18)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Customize Gestures', style: TextStyle(color: Colors.white, fontSize: 13)),
                Text('Remap any gesture zone to any player action',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
            ]),
          ),
        ),
        InkWell(
          onTap: widget.onOpenSkipEditor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white10,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.content_cut_rounded, color: Colors.white54, size: 18)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Intro / Skip Editor', style: TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.skip_next_rounded,    label: 'Jump To',        onTap: onOpenJumpTo),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.speed_rounded,        label: 'Speed Presets',  onTap: onOpenSpeedPresets),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.flag_rounded,         label: 'Video End Action', onTap: onOpenEndAction),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.volume_off_rounded,   label: 'Smart Skip',     onTap: onOpenSilenceSkip),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.zoom_in_rounded,        label: 'Zoom & Crop',    onTap: onOpenZoomCrop),
          const SizedBox(height: 8),
          _NavButton(icon: Icons.dashboard_customize_rounded, label: 'Layout Designer', onTap: onOpenLayoutDesigner ?? () {}),
                Text('Set custom skip timestamps for this video',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
            ]),
          ),
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
        // ── Phase E1–E4: Audio Lab ─────────────────────────────────────────
        _QsLabel('Audio Lab'),
        AudioLabPanel(
          config: AudioLabConfig.decode(_p.audioLabConfig),
          onChanged: (cfg) => _update(_p.copyWith(audioLabConfig: cfg.encode())),
          accentColor: _accent,
        ),
        const Divider(color: Colors.white10, height: 1),
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

        _QsRow(
          label: 'Forward/backward moving button',
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.fast_forward_rounded, color: Colors.white54, size: 18),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

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

        _QsRow(
          label: 'Previous/next button',
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.skip_next_rounded, color: Colors.white54, size: 18),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

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
    const fonts = ['Sans Serif', 'Serif', 'Monospace', 'Cursive', 'Lexend', 'Default'];
    final size = _p.subtitleFontSize;
    final scale = _subtitleScale;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      children: [
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

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Text('Color', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
            const Text('Background Color', style: TextStyle(color: Colors.white70, fontSize: 13)),
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

        // Phase F2: Dictionary enable toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            const Icon(Icons.menu_book_rounded, color: Colors.white54, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Word Dictionary', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Tap subtitle words for Urdu translation', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ),
            Switch(
              value: _p.dictEnabled,
              onChanged: (v) => _update(_p.copyWith(dictEnabled: v)),
              activeColor: _accent,
            ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Text('Border', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
            const Text('Shadow', style: TextStyle(color: Colors.white70, fontSize: 13)),
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

        _QsToggleRow(
          label: 'Improve stroke rendering',
          value: _improveStroke,
          onChanged: (v) => setState(() => _improveStroke = v),
        ),
        const Divider(color: Colors.white10, height: 1),

        _QsToggleRow(
          label: 'Fade out',
          value: _fadeOut,
          onChanged: (v) => setState(() => _fadeOut = v),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ── Phase G4: Content Mood Timeline ───────────────────────────────
        _QsToggleRow(
          label: 'Content Mood Timeline',
          value: _p.contentMoodEnabled,
          onChanged: (v) => _update(_p.copyWith(contentMoodEnabled: v)),
        ),
        if (_p.contentMoodEnabled)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Colors the seek bar by narrative arc: calm → rising → tension → climax',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHAPE CHIP helper (used in Style tab Button Shape row)
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildShapeChip(String id, String label, double radius, Color accent) {
  final sel = _p.buttonShape == id;
  // Show the shape visually as a mini play-button silhouette
  Widget shape;
  if (id == 'circle') {
    shape = Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: sel ? accent : Colors.white24,
      ),
      child: Icon(Icons.play_arrow_rounded,
          color: sel ? Colors.white : Colors.white54, size: 18),
    );
  } else {
    shape = Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: sel ? accent : Colors.white24,
      ),
      child: Icon(Icons.play_arrow_rounded,
          color: sel ? Colors.white : Colors.white54, size: 18),
    );
  }

  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () => _update(_p.copyWith(buttonShape: id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        decoration: BoxDecoration(
          color: sel ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? accent : Colors.white12,
            width: sel ? 1.5 : 1.0),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          shape,
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            color: sel ? Colors.white : Colors.white54,
            fontSize: 10, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    ),
  );
}

// ── Shared UI helpers ───────────────────────────────────────────────────────────

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
