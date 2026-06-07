import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYER HUD SETTINGS SHEET
// A live-preview layout & controls settings overlay that renders directly
// inside the player Stack so the video stays visible behind it at all times.
//
// Portrait  : slides up from bottom, full width, ~72% height
// Landscape : slides in from right, ~52% width, full height
// Background: 72% opaque dark + BackdropFilter blur → video visible through it
// Changes   : applied instantly via onPrefsChanged (no Save button)
// ═══════════════════════════════════════════════════════════════════════════════

class PlayerHudSettingsSheet extends StatefulWidget {
  final PlayerPrefs          prefs;
  final ValueChanged<PlayerPrefs> onPrefsChanged;
  final VoidCallback         onClose;
  final VoidCallback         onOpenFullSettings;

  const PlayerHudSettingsSheet({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onClose,
    required this.onOpenFullSettings,
  });

  @override
  State<PlayerHudSettingsSheet> createState() => _PlayerHudSettingsSheetState();
}

class _PlayerHudSettingsSheetState extends State<PlayerHudSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    HapticFeedback.lightImpact();
    _ctrl.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  void _save(PlayerPrefs p) => widget.onPrefsChanged(p);

  @override
  Widget build(BuildContext context) {
    final mq          = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    return Stack(children: [
      // ── backdrop: tap outside to dismiss ──────────────────────────────────
      Positioned.fill(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(
              color: Colors.black.withOpacity(0.38 * _anim.value),
            ),
          ),
        ),
      ),

      // ── the panel ─────────────────────────────────────────────────────────
      AnimatedBuilder(
        animation: _anim,
        builder: (ctx, _) {
          if (isLandscape) {
            // right-side panel: ~52% width, full height
            final panelW = mq.size.width * 0.52;
            final slideOff = panelW * (1.0 - _anim.value);
            return Positioned(
              right: -slideOff,
              top: 0, bottom: 0,
              width: panelW,
              child: _PanelContent(
                prefs:         widget.prefs,
                onSave:        _save,
                onClose:       _dismiss,
                onFullSettings: () { _dismiss(); widget.onOpenFullSettings(); },
                isLandscape:   true,
              ),
            );
          } else {
            // bottom panel: full width, ~72% height
            final panelH = mq.size.height * 0.72;
            final slideOff = panelH * (1.0 - _anim.value);
            return Positioned(
              left: 0, right: 0,
              bottom: -slideOff,
              height: panelH,
              child: _PanelContent(
                prefs:         widget.prefs,
                onSave:        _save,
                onClose:       _dismiss,
                onFullSettings: () { _dismiss(); widget.onOpenFullSettings(); },
                isLandscape:   false,
              ),
            );
          }
        },
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PanelContent extends StatelessWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onSave;
  final VoidCallback onClose;
  final VoidCallback onFullSettings;
  final bool isLandscape;

  const _PanelContent({
    required this.prefs,
    required this.onSave,
    required this.onClose,
    required this.onFullSettings,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final accent = prefs.accentColor;
    return ClipRRect(
      borderRadius: isLandscape
          ? const BorderRadius.horizontal(left: Radius.circular(20))
          : const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xB8080810),
            border: isLandscape
                ? const Border(left: BorderSide(color: Colors.white12))
                : const Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(children: [
            _Header(accent: accent, onClose: onClose),
            const Divider(height: 1, color: Colors.white10),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _QuickBarSection(prefs: prefs, accent: accent, onSave: onSave),
                    _SectionDivider(),
                    _CenterSection(prefs: prefs, accent: accent, onSave: onSave),
                    _SectionDivider(),
                    _OverlaysSection(prefs: prefs, accent: accent, onSave: onSave),
                    _SectionDivider(),
                    _SeekBarSection(prefs: prefs, accent: accent, onSave: onSave),
                    _SectionDivider(),
                    _BehaviorSection(prefs: prefs, accent: accent, onSave: onSave),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            _Footer(onFullSettings: onFullSettings),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Color accent;
  final VoidCallback onClose;
  const _Header({required this.accent, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(children: [
        Container(width: 3, height: 18,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        const Text('Layout & Controls',
          style: TextStyle(color: Colors.white, fontSize: 15,
              fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const Spacer(),
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOOTER
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final VoidCallback onFullSettings;
  const _Footer({required this.onFullSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onFullSettings(); },
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.settings_rounded, color: Colors.white54, size: 14),
            SizedBox(width: 6),
            Text('All Settings', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 10),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, color: Colors.white38, size: 13),
      const SizedBox(width: 6),
      Text(label.toUpperCase(),
        style: const TextStyle(color: Colors.white38, fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.1)),
    ]),
  );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool   value;
  final Color  accent;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onChanged(!value); },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white87, fontSize: 13, fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          )),
          _MiniSwitch(value: value, accent: accent, onChanged: onChanged),
        ]),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _MiniSwitch({required this.value, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onChanged(!value); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38, height: 22,
        decoration: BoxDecoration(
          color: value ? accent : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18, height: 18,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: ⚡ QUICK BAR
// ─────────────────────────────────────────────────────────────────────────────

class _QuickBarSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;

  const _QuickBarSection({required this.prefs, required this.accent, required this.onSave});

  static const _allItems = [
    ('pip',        Icons.picture_in_picture_alt_rounded,  'PiP'),
    ('bgplay',     Icons.play_circle_outline_rounded,      'BG Play'),
    ('fit',        Icons.fit_screen_rounded,               'Resize'),
    ('screenshot', Icons.camera_alt_rounded,               'Screenshot'),
    ('speed',      Icons.speed_rounded,                    'Speed'),
    ('subtitle',   Icons.subtitles_rounded,                'Subtitles'),
    ('lock',       Icons.lock_outline_rounded,             'Lock'),
    ('nightmode',  Icons.dark_mode_rounded,                'Night'),
  ];

  void _toggleItem(String id, BuildContext _) {
    HapticFeedback.selectionClick();
    final current = prefs.quickBarItems
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final List<String> updated;
    if (current.contains(id)) {
      updated = current.where((s) => s != id).toList();
    } else {
      // Maintain canonical order
      final canonical = _allItems.map((t) => t.$1).toList();
      updated = canonical.where((s) => current.contains(s) || s == id).toList();
    }
    onSave(prefs.copyWith(quickBarItems: updated.join(',')));
  }

  @override
  Widget build(BuildContext context) {
    final active = prefs.quickBarItems
        .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.flash_on_rounded, label: 'Quick Bar'),
      _ToggleRow(
        label: 'Show Quick Shortcuts Bar',
        subtitle: 'One-tap buttons above seek bar',
        value: prefs.showQuickBar,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showQuickBar: v)),
      ),
      if (prefs.showQuickBar) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _allItems.map((t) {
            final id    = t.$1;
            final icon  = t.$2;
            final label = t.$3;
            final on    = active.contains(id);
            return GestureDetector(
              onTap: () => _toggleItem(id, context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: on ? accent.withOpacity(0.6) : Colors.white.withOpacity(0.12),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: on ? accent : Colors.white54, size: 13),
                  const SizedBox(width: 5),
                  Text(label,
                    style: TextStyle(
                      color: on ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    )),
                ]),
              ),
            );
          }).toList(),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: 🎮 CENTER BUTTONS
// ─────────────────────────────────────────────────────────────────────────────

class _CenterSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _CenterSection({required this.prefs, required this.accent, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.gamepad_rounded, label: 'Center Buttons'),
      const Text('Position', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      _PositionChips(
        value: prefs.centerBtnPosition,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(centerBtnPosition: v)),
      ),
      const SizedBox(height: 10),
      _ToggleRow(
        label: 'Previous Episode',
        value: prefs.showCenterPrev,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterPrev: v)),
      ),
      _ToggleRow(
        label: 'Next Episode',
        value: prefs.showCenterNext,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterNext: v)),
      ),
      _ToggleRow(
        label: 'Skip Intro Button',
        value: prefs.showCenterSkip,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterSkip: v)),
      ),
    ]);
  }
}

class _PositionChips extends StatelessWidget {
  final String value;
  final Color  accent;
  final ValueChanged<String> onChanged;
  const _PositionChips({required this.value, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = [
      ('center', Icons.center_focus_strong_rounded, 'Center'),
      ('bottom', Icons.vertical_align_bottom_rounded, 'Bottom'),
      ('hidden', Icons.visibility_off_outlined,     'Hidden'),
    ];
    return Row(children: opts.map((t) {
      final id    = t.$1;
      final icon  = t.$2;
      final label = t.$3;
      final sel   = value == id;
      return Expanded(child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onChanged(id); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: sel ? accent.withOpacity(0.20) : Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: sel ? accent : Colors.white54, size: 15),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              color: sel ? Colors.white : Colors.white60,
              fontSize: 10, fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      ));
    }).toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: 📺 INFO OVERLAYS
// ─────────────────────────────────────────────────────────────────────────────

class _OverlaysSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _OverlaysSection({required this.prefs, required this.accent, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.layers_rounded, label: 'Info Overlays'),
      _ToggleRow(
        label: 'Episode Info',
        subtitle: 'Title & episode number in top bar',
        value: prefs.showEpisodeInfo,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showEpisodeInfo: v)),
      ),
      _ToggleRow(
        label: 'Network Speed',
        subtitle: 'Live kbps readout on screen',
        value: prefs.showNetworkSpeed,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showNetworkSpeed: v)),
      ),
      _ToggleRow(
        label: 'Playback Info',
        subtitle: 'Resolution, codec, bitrate',
        value: prefs.showPlaybackInfo,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showPlaybackInfo: v)),
      ),
      _ToggleRow(
        label: 'Decoder Info',
        subtitle: 'HW/SW decoder status badge',
        value: prefs.showDecoderInfo,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showDecoderInfo: v)),
      ),
      _ToggleRow(
        label: 'Active Track Badge',
        subtitle: 'Shows current audio/sub track',
        value: prefs.showActiveTrackBadge,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showActiveTrackBadge: v)),
      ),
      _ToggleRow(
        label: 'Track Count Badge',
        subtitle: 'Number of audio/sub tracks',
        value: prefs.showTrackCountBadge,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showTrackCountBadge: v)),
      ),
      _ToggleRow(
        label: 'Frame Counter',
        subtitle: 'Frame number & timestamp (advanced)',
        value: prefs.frameCounterEnabled,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(frameCounterEnabled: v)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: 🎬 SEEK BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SeekBarSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _SeekBarSection({required this.prefs, required this.accent, required this.onSave});

  static const _styles = [
    ('classic',  'Classic'),
    ('bold',     'Bold'),
    ('gradient', 'Gradient'),
    ('wave',     'Wave'),
    ('neon',     'Neon'),
    ('dots',     'Dots'),
    ('thin',     'Thin'),
    ('glow',     'Glow'),
    ('retro',    'Retro'),
    ('minimal',  'Minimal'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.linear_scale_rounded, label: 'Seek Bar'),
      const Text('Style', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: _styles.map((t) {
          final id    = t.$1;
          final label = t.$2;
          final sel   = prefs.seekBarStyle == id;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onSave(prefs.copyWith(seekBarStyle: id)); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.12),
                ),
              ),
              child: Text(label, style: TextStyle(
                color: sel ? accent : Colors.white60,
                fontSize: 11, fontWeight: FontWeight.w600,
              )),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 10),
      _ToggleRow(
        label: 'Show Buffer Bar',
        subtitle: 'Buffered progress behind seek bar',
        value: prefs.showBufferBar,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showBufferBar: v)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: ⚙️ BEHAVIOR
// ─────────────────────────────────────────────────────────────────────────────

class _BehaviorSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _BehaviorSection({required this.prefs, required this.accent, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.tune_rounded, label: 'Controls Behavior'),

      // Auto-hide delay
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          const Expanded(child: Text('Auto-hide delay',
            style: TextStyle(color: Colors.white87, fontSize: 13, fontWeight: FontWeight.w500))),
          Text('${prefs.autoHideSeconds}s',
            style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white.withOpacity(0.12),
          thumbColor: accent,
          overlayColor: accent.withOpacity(0.16),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(
          value: prefs.autoHideSeconds.toDouble().clamp(2, 15),
          min: 2, max: 15,
          divisions: 13,
          onChanged: (v) => onSave(prefs.copyWith(autoHideSeconds: v.round())),
        ),
      ),

      // Controls opacity
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          const Expanded(child: Text('Controls opacity',
            style: TextStyle(color: Colors.white87, fontSize: 13, fontWeight: FontWeight.w500))),
          Text('${(prefs.controlBarOpacity * 100).round()}%',
            style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white.withOpacity(0.12),
          thumbColor: accent,
          overlayColor: accent.withOpacity(0.16),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(
          value: prefs.controlBarOpacity.clamp(0.3, 1.0),
          min: 0.3, max: 1.0,
          divisions: 14,
          onChanged: (v) {
            final rounded = (v * 100).round() / 100;
            onSave(prefs.copyWith(controlBarOpacity: rounded));
          },
        ),
      ),
    ]);
  }
}
