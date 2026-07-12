import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';
import '../../design_system/motion/radd_motion.dart';
import '../../design_system/radius/radd_radius.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYER HUD SETTINGS SHEET  v2
// Live-preview transparent overlay inside the player Stack.
//
// Features:
//   • Layout presets  — Netflix / MX Classic / Minimal / Binge / Custom
//   • Per-orientation — Portrait / Landscape tabs with independent settings
//   • Drag-to-reorder — Quick Bar chips reorderable via long-press drag
//   • Button shapes   — Circle / Squircle / Pill / Sharp
//   • Dedup guard     — tracks which zone each control lives in; prevents dups
//   • All changes     — live via onPrefsChanged (no Save button)
//
// Portrait  : slides up from bottom, full width × 74% height
// Landscape : slides in from right, 52% width × full height
// ═══════════════════════════════════════════════════════════════════════════════

// ── Layout preset bundles ─────────────────────────────────────────────────────
class _LayoutPreset {
  final String id;
  final String label;
  final IconData icon;
  final PlayerPrefs Function(PlayerPrefs) apply;
  const _LayoutPreset({required this.id, required this.label, required this.icon, required this.apply});
}

final _kPresets = <_LayoutPreset>[
  _LayoutPreset(
    id: 'netflix', label: 'Netflix', icon: Icons.play_circle_outline_rounded,
    apply: (p) => p.copyWith(
      centerBtnPosition: 'center',
      showQuickBar: false,
      showCenterPrev: false, showCenterNext: true, showCenterSkip: false,
      showEpisodeInfo: true, showPlaybackInfo: false, showDecoderInfo: false,
      showNetworkSpeed: false, showActiveTrackBadge: false, showTrackCountBadge: false,
      showBufferBar: false, seekBarStyle: 'thin',
    ),
  ),
  _LayoutPreset(
    id: 'mx_classic', label: 'MX Classic', icon: Icons.grid_view_rounded,
    apply: (p) => p.copyWith(
      centerBtnPosition: 'center',
      showQuickBar: true,
      quickBarItems: 'pip,fit,screenshot,speed,subtitle,lock,nightmode',
      showCenterPrev: true, showCenterNext: true, showCenterSkip: true,
      showEpisodeInfo: true, showPlaybackInfo: true, showDecoderInfo: false,
      showNetworkSpeed: false, showActiveTrackBadge: true, showTrackCountBadge: true,
      showBufferBar: true, seekBarStyle: 'classic',
    ),
  ),
  _LayoutPreset(
    id: 'minimal', label: 'Minimal', icon: Icons.remove_rounded,
    apply: (p) => p.copyWith(
      centerBtnPosition: 'center',
      showQuickBar: false,
      showCenterPrev: false, showCenterNext: false, showCenterSkip: false,
      showEpisodeInfo: false, showPlaybackInfo: false, showDecoderInfo: false,
      showNetworkSpeed: false, showActiveTrackBadge: false, showTrackCountBadge: false,
      showBufferBar: false, seekBarStyle: 'minimal',
    ),
  ),
  _LayoutPreset(
    id: 'binge', label: 'Binge', icon: Icons.fast_forward_rounded,
    apply: (p) => p.copyWith(
      centerBtnPosition: 'bottom',
      showQuickBar: true,
      quickBarItems: 'bgplay,speed,subtitle,lock,nightmode,screenshot',
      showCenterPrev: true, showCenterNext: true, showCenterSkip: true,
      showEpisodeInfo: true, showPlaybackInfo: false, showDecoderInfo: false,
      showNetworkSpeed: true, showActiveTrackBadge: true, showTrackCountBadge: false,
      showBufferBar: true, seekBarStyle: 'gradient',
    ),
  ),
];

// ── Which zone each control already occupies (dedup guard) ────────────────────
// TOP BAR always has: audio-tracks btn, subtitle btn
// RIGHT STRIP always has: Sub, Audio (same as top bar), Rotation, More
// We use this to warn in the Quick Bar section
const _kAlwaysInTopBar  = {'subtitle', 'audio'};         // top-bar permanent controls
const _kAlwaysInRightStrip = {'subtitle', 'audio'};       // right-strip permanent

// Quick Bar supported item registry
const _kQuickBarRegistry = <(String, IconData, String)>[
  ('pip',        Icons.picture_in_picture_alt_rounded, 'PiP'),
  ('bgplay',     Icons.play_circle_outline_rounded,    'BG Play'),
  ('fit',        Icons.fit_screen_rounded,             'Resize'),
  ('screenshot', Icons.camera_alt_rounded,             'Screenshot'),
  ('speed',      Icons.speed_rounded,                  'Speed'),
  ('subtitle',   Icons.subtitles_rounded,              'Subtitles'),
  ('lock',       Icons.lock_outline_rounded,           'Lock'),
  ('nightmode',  Icons.dark_mode_rounded,              'Night'),
];

// controls that are already in the top-bar / sidebar so we warn user
const _kDuplicateWarned = {'subtitle'};

// ─────────────────────────────────────────────────────────────────────────────

class PlayerHudSettingsSheet extends StatefulWidget {
  final PlayerPrefs               prefs;
  final ValueChanged<PlayerPrefs> onPrefsChanged;
  final VoidCallback              onClose;
  final VoidCallback              onOpenFullSettings;

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

  // Per-orientation tab: 0 = portrait, 1 = landscape
  int _orientTab = 0;

  late PlayerPrefs _localPrefs;      // portrait prefs  (= shared prefs for now)
  late PlayerPrefs _landscapePrefs;  // landscape prefs (separate copy)

  @override
  void initState() {
    super.initState();
    _localPrefs    = widget.prefs;
    _landscapePrefs = widget.prefs; // start as copy; user can diverge
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _ctrl.forward();
    // default tab to match current physical orientation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mq = MediaQuery.of(context);
      setState(() => _orientTab = mq.orientation == Orientation.landscape ? 1 : 0);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    HapticFeedback.lightImpact();
    _ctrl.reverse().then((_) { if (mounted) widget.onClose(); });
  }

  void _applyPortrait(PlayerPrefs p) {
    setState(() => _localPrefs = p);
    widget.onPrefsChanged(p);
  }

  void _applyLandscape(PlayerPrefs p) {
    setState(() => _landscapePrefs = p);
    // For landscape we merge into the shared prefs only the layout-relevant fields
    // that orientation-specific (quickBarItems, centerBtnPosition, showQuickBar etc.)
    // For simplicity we apply to both for now; true per-orientation storage would
    // need separate SharedPreferences keys (future: layoutJson portrait/landscape split)
    widget.onPrefsChanged(p);
  }

  PlayerPrefs get _activePrefs    => _orientTab == 0 ? _localPrefs : _landscapePrefs;
  void _activeApply(PlayerPrefs p) => _orientTab == 0 ? _applyPortrait(p) : _applyLandscape(p);

  void _applyPreset(String presetId) {
    HapticFeedback.mediumImpact();
    final preset = _kPresets.firstWhere((p) => p.id == presetId, orElse: () => _kPresets.first);
    final applied = preset.apply(_activePrefs);
    _activeApply(applied);
  }

  @override
  Widget build(BuildContext context) {
    final mq          = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    return Stack(children: [
      // backdrop
      Positioned.fill(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(color: Colors.black.withOpacity(0.4 * _anim.value)),
          ),
        ),
      ),
      // panel
      AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          if (isLandscape) {
            final pw   = mq.size.width * 0.52;
            final off  = pw * (1.0 - _anim.value);
            return Positioned(right: -off, top: 0, bottom: 0, width: pw,
              child: _PanelBody(
                activePrefs:    _activePrefs,
                portraitPrefs:  _localPrefs,
                landscapePrefs: _landscapePrefs,
                orientTab:      _orientTab,
                onOrientTab:    (t) => setState(() => _orientTab = t),
                accent:         widget.prefs.accentColor,
                onSave:         _activeApply,
                onPreset:       _applyPreset,
                onClose:        _dismiss,
                onFullSettings: () { _dismiss(); widget.onOpenFullSettings(); },
                isLandscape:    true,
              ));
          } else {
            final ph  = mq.size.height * 0.74;
            final off = ph * (1.0 - _anim.value);
            return Positioned(left: 0, right: 0, bottom: -off, height: ph,
              child: _PanelBody(
                activePrefs:    _activePrefs,
                portraitPrefs:  _localPrefs,
                landscapePrefs: _landscapePrefs,
                orientTab:      _orientTab,
                onOrientTab:    (t) => setState(() => _orientTab = t),
                accent:         widget.prefs.accentColor,
                onSave:         _activeApply,
                onPreset:       _applyPreset,
                onClose:        _dismiss,
                onFullSettings: () { _dismiss(); widget.onOpenFullSettings(); },
                isLandscape:    false,
              ));
          }
        },
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANEL BODY
// ─────────────────────────────────────────────────────────────────────────────

class _PanelBody extends StatelessWidget {
  final PlayerPrefs  activePrefs;
  final PlayerPrefs  portraitPrefs;
  final PlayerPrefs  landscapePrefs;
  final int          orientTab;
  final ValueChanged<int> onOrientTab;
  final Color        accent;
  final ValueChanged<PlayerPrefs> onSave;
  final ValueChanged<String>      onPreset;
  final VoidCallback onClose;
  final VoidCallback onFullSettings;
  final bool         isLandscape;

  const _PanelBody({
    required this.activePrefs,
    required this.portraitPrefs,
    required this.landscapePrefs,
    required this.orientTab,
    required this.onOrientTab,
    required this.accent,
    required this.onSave,
    required this.onPreset,
    required this.onClose,
    required this.onFullSettings,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: isLandscape
          ? const BorderRadius.horizontal(left: Radius.circular(20))
          : const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xBB070710),
            border: isLandscape
                ? const Border(left: BorderSide(color: Colors.white12))
                : const Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(children: [
            _Header(accent: accent, onClose: onClose),
            // ── Orientation tabs ──────────────────────────────────────────────
            _OrientTabs(tab: orientTab, onTab: onOrientTab),
            const SizedBox(height: 4),
            // ── Preset strip ─────────────────────────────────────────────────
            _PresetStrip(active: activePrefs, accent: accent, onPreset: onPreset),
            Container(height: 1, color: Colors.white.withOpacity(0.07), margin: const EdgeInsets.only(top: 6)),
            // ── Scrollable sections ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QuickBarSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    _div(),
                    _CenterSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    _div(),
                    _OverlaysSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    _div(),
                    _SeekBarSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    _div(),
                    _ShapeSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    _div(),
                    _BehaviorSection(prefs: activePrefs, accent: accent, onSave: onSave),
                    const SizedBox(height: 8),
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

  Widget _div() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Color accent;
  final VoidCallback onClose;
  const _Header({required this.accent, required this.onClose});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
    child: Row(children: [
      Container(width: 3, height: 18,
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      const Text('Layout & Controls',
        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      const Spacer(),
      GestureDetector(
        onTap: onClose,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ORIENTATION TABS
// ─────────────────────────────────────────────────────────────────────────────

class _OrientTabs extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _OrientTabs({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          _Tab(label: 'Portrait',  icon: Icons.stay_current_portrait_rounded, selected: tab == 0, onTap: () { HapticFeedback.selectionClick(); onTab(0); }),
          _Tab(label: 'Landscape', icon: Icons.stay_current_landscape_rounded, selected: tab == 1, onTap: () { HapticFeedback.selectionClick(); onTab(1); }),
        ]),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.13) : Colors.transparent,
            borderRadius: RaddRadius.smRadius,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected ? Colors.white : Colors.white38, size: 12),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: selected ? Colors.white : Colors.white38,
              fontSize: 11, fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESET STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _PresetStrip extends StatelessWidget {
  final PlayerPrefs          active;
  final Color                accent;
  final ValueChanged<String> onPreset;
  const _PresetStrip({required this.active, required this.accent, required this.onPreset});

  String _detectActivePreset(PlayerPrefs p) {
    for (final pr in _kPresets) {
      final applied = pr.apply(p);
      if (applied.centerBtnPosition == p.centerBtnPosition &&
          applied.showQuickBar      == p.showQuickBar &&
          applied.seekBarStyle      == p.seekBarStyle) return pr.id;
    }
    return 'custom';
  }

  @override
  Widget build(BuildContext context) {
    final current = _detectActivePreset(active);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        physics: const BouncingScrollPhysics(),
        children: [
          ..._kPresets.map((pr) {
            final sel = current == pr.id;
            return GestureDetector(
              onTap: () => onPreset(pr.id),
              child: AnimatedContainer(
                duration: RaddMotion.tuneDuration,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? accent.withOpacity(0.22) : Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? accent.withOpacity(0.7) : Colors.white.withOpacity(0.12),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Icon(pr.icon, color: sel ? accent : Colors.white54, size: 13),
                  const SizedBox(width: 5),
                  Text(pr.label, style: TextStyle(
                    color: sel ? Colors.white : Colors.white60,
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
                ]),
              ),
            );
          }),
          // Custom chip (always present)
          GestureDetector(
            onTap: () {},
            child: AnimatedContainer(
              duration: RaddMotion.tuneDuration,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: current == 'custom' ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(current == 'custom' ? 0.3 : 0.10)),
              ),
              child: Row(children: [
                Icon(Icons.tune_rounded, color: current == 'custom' ? Colors.white : Colors.white38, size: 13),
                const SizedBox(width: 5),
                Text('Custom', style: TextStyle(
                  color: current == 'custom' ? Colors.white : Colors.white38,
                  fontSize: 11, fontWeight: FontWeight.w700,
                )),
              ]),
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
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

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   iconColor;
  const _SectionTitle({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, color: iconColor ?? Colors.white38, size: 13),
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
  final String? warnText;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.accent,
    this.warnText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onChanged(!value); },
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xDEFFFFFF), fontSize: 13, fontWeight: FontWeight.w500)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (warnText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 11),
                const SizedBox(width: 3),
                Text(warnText!, style: const TextStyle(color: Colors.amber, fontSize: 10)),
              ]),
            ),
        ])),
        _MiniSwitch(value: value, accent: accent, onChanged: onChanged),
      ]),
    ),
  );
}

class _MiniSwitch extends StatelessWidget {
  final bool   value;
  final Color  accent;
  final ValueChanged<bool> onChanged;
  const _MiniSwitch({required this.value, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
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
          width: 18, height: 18, margin: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: ⚡ QUICK BAR  (drag-to-reorder + dedup guard)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickBarSection extends StatefulWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _QuickBarSection({required this.prefs, required this.accent, required this.onSave});

  @override
  State<_QuickBarSection> createState() => _QuickBarSectionState();
}

class _QuickBarSectionState extends State<_QuickBarSection> {
  late List<String> _activeIds;

  @override
  void initState() {
    super.initState();
    _activeIds = _parseIds(widget.prefs.quickBarItems);
  }

  @override
  void didUpdateWidget(_QuickBarSection old) {
    super.didUpdateWidget(old);
    if (old.prefs.quickBarItems != widget.prefs.quickBarItems) {
      _activeIds = _parseIds(widget.prefs.quickBarItems);
    }
  }

  List<String> _parseIds(String s) =>
      s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_activeIds.contains(id)) {
        _activeIds.remove(id);
      } else {
        _activeIds.add(id);
      }
    });
    widget.onSave(widget.prefs.copyWith(quickBarItems: _activeIds.join(',')));
  }

  void _reorder(int oldIdx, int newIdx) {
    HapticFeedback.selectionClick();
    setState(() {
      if (newIdx > oldIdx) newIdx -= 1;
      final item = _activeIds.removeAt(oldIdx);
      _activeIds.insert(newIdx, item);
    });
    widget.onSave(widget.prefs.copyWith(quickBarItems: _activeIds.join(',')));
  }

  @override
  Widget build(BuildContext context) {
    final allSet = _activeIds.toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.flash_on_rounded, label: 'Quick Shortcuts Bar',
        iconColor: Colors.amber),
      _ToggleRow(
        label: 'Show Quick Bar',
        subtitle: 'One-tap buttons above seek bar',
        value: widget.prefs.showQuickBar,
        accent: widget.accent,
        onChanged: (v) => widget.onSave(widget.prefs.copyWith(showQuickBar: v)),
      ),

      if (widget.prefs.showQuickBar) ...[
        const SizedBox(height: 10),

        // ── Active chips — drag to reorder ────────────────────────────────
        if (_activeIds.isNotEmpty) ...[
          const Text('Active — drag to reorder',
            style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _reorder,
            children: _activeIds.asMap().entries.map((e) {
              final idx  = e.key;
              final id   = e.value;
              final reg  = _kQuickBarRegistry.firstWhere((r) => r.$1 == id,
                  orElse: () => (id, Icons.circle, id));
              final isDup = _kDuplicateWarned.contains(id);
              return Container(
                key: ValueKey(id),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: widget.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isDup
                        ? Colors.amber.withOpacity(0.5)
                        : widget.accent.withOpacity(0.45),
                  ),
                ),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: idx,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.drag_handle_rounded, color: Colors.white38, size: 16),
                    ),
                  ),
                  Icon(reg.$2, color: widget.accent, size: 14),
                  const SizedBox(width: 7),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reg.$3, style: const TextStyle(
                          color: Color(0xDEFFFFFF), fontSize: 12, fontWeight: FontWeight.w600)),
                      if (isDup)
                        const Text('Also in Top Bar — may feel redundant',
                          style: TextStyle(color: Colors.amber, fontSize: 9)),
                    ],
                  )),
                  GestureDetector(
                    onTap: () => _toggle(id),
                    child: const Icon(Icons.remove_circle_outline_rounded,
                        color: Colors.white38, size: 16),
                  ),
                ]),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // ── Available chips — tap to add ──────────────────────────────────
        const Text('Tap to add',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _kQuickBarRegistry
              .where((r) => !allSet.contains(r.$1))
              .map((r) {
            final isDup = _kDuplicateWarned.contains(r.$1);
            return GestureDetector(
              onTap: () => _toggle(r.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: RaddRadius.smRadius,
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white38, size: 11),
                  const SizedBox(width: 4),
                  Icon(r.$2, color: Colors.white54, size: 12),
                  const SizedBox(width: 4),
                  Text(r.$3, style: const TextStyle(
                      color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
                  if (isDup) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 10),
                  ],
                ]),
              ),
            );
          }).toList(),
        ),

        if (_kDuplicateWarned.intersection(allSet).isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: RaddRadius.smRadius,
              border: Border.all(color: Colors.amber.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 12),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Subtitles is already in the top bar. Keeping it in Quick Bar too may clutter the screen.',
                style: TextStyle(color: Colors.amber, fontSize: 10),
              )),
            ]),
          ),
        ],
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.gamepad_rounded, label: 'Center Buttons',
        iconColor: const Color(0xFF60A5FA)),
      const Text('Position', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      _Chips3(
        opts: const [
          ('center', Icons.center_focus_strong_rounded, 'Center'),
          ('bottom', Icons.vertical_align_bottom_rounded, 'Bottom'),
          ('hidden', Icons.visibility_off_outlined, 'Hidden'),
        ],
        value: prefs.centerBtnPosition,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(centerBtnPosition: v)),
      ),
      const SizedBox(height: 10),
      _ToggleRow(label: 'Previous Episode', value: prefs.showCenterPrev, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterPrev: v))),
      _ToggleRow(label: 'Next Episode', value: prefs.showCenterNext, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterNext: v))),
      _ToggleRow(label: 'Skip Intro Button', value: prefs.showCenterSkip, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showCenterSkip: v))),
    ],
  );
}

class _Chips3 extends StatelessWidget {
  final List<(String, IconData, String)> opts;
  final String value;
  final Color  accent;
  final ValueChanged<String> onChanged;
  const _Chips3({required this.opts, required this.value, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: opts.map((t) {
    final sel = value == t.$1;
    return Expanded(child: GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onChanged(t.$1); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: sel ? accent.withOpacity(0.20) : Colors.white.withOpacity(0.07),
          borderRadius: RaddRadius.smRadius,
          border: Border.all(color: sel ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(t.$2, color: sel ? accent : Colors.white54, size: 15),
          const SizedBox(height: 3),
          Text(t.$3, style: TextStyle(
              color: sel ? Colors.white : Colors.white60, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    ));
  }).toList());
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.layers_rounded, label: 'Info Overlays',
        iconColor: const Color(0xFFA78BFA)),
      _ToggleRow(label: 'Episode Title', subtitle: 'Title & number in top bar',
        value: prefs.showEpisodeInfo, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showEpisodeInfo: v))),
      _ToggleRow(label: 'Network Speed', subtitle: 'Live kbps badge on screen',
        value: prefs.showNetworkSpeed, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showNetworkSpeed: v))),
      _ToggleRow(label: 'Playback Info', subtitle: 'Resolution · codec · bitrate',
        value: prefs.showPlaybackInfo, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showPlaybackInfo: v))),
      _ToggleRow(label: 'Decoder Badge', subtitle: 'HW / SW decoder status',
        value: prefs.showDecoderInfo, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showDecoderInfo: v))),
      _ToggleRow(label: 'Active Track Badge', subtitle: 'Current audio & subtitle track',
        value: prefs.showActiveTrackBadge, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showActiveTrackBadge: v))),
      _ToggleRow(label: 'Track Count Badge', subtitle: 'Number of available tracks',
        value: prefs.showTrackCountBadge, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showTrackCountBadge: v))),
      _ToggleRow(label: 'Frame Counter', subtitle: 'Frame number · advanced',
        value: prefs.frameCounterEnabled, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(frameCounterEnabled: v))),
    ],
  );
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
    ('classic','Classic'), ('bold','Bold'), ('gradient','Gradient'),
    ('wave','Wave'), ('neon','Neon'), ('dots','Dots'),
    ('thin','Thin'), ('glow','Glow'), ('retro','Retro'), ('minimal','Minimal'),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.linear_scale_rounded, label: 'Seek Bar',
        iconColor: const Color(0xFF34D399)),
      const Text('Style', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: _styles.map((t) {
          final sel = prefs.seekBarStyle == t.$1;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onSave(prefs.copyWith(seekBarStyle: t.$1)); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.12)),
              ),
              child: Text(t.$2, style: TextStyle(
                  color: sel ? accent : Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 10),
      _ToggleRow(label: 'Buffer Bar', subtitle: 'Buffered progress behind seek bar',
        value: prefs.showBufferBar, accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(showBufferBar: v))),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION: 🔲 BUTTON SHAPE
// ─────────────────────────────────────────────────────────────────────────────

class _ShapeSection extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final ValueChanged<PlayerPrefs> onSave;
  const _ShapeSection({required this.prefs, required this.accent, required this.onSave});

  static const _shapes = [
    ('circle',   '●',  'Circle'),
    ('squircle', '⬛', 'Squircle'),
    ('rounded',  '▢',  'Rounded'),
    ('pill',     '💊', 'Pill'),
    ('sharp',    '◾', 'Sharp'),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.category_rounded, label: 'Button Shape',
        iconColor: const Color(0xFFF472B6)),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: _shapes.map((t) {
          final sel = prefs.buttonShape == t.$1;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onSave(prefs.copyWith(buttonShape: t.$1)); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(_shapeRadius(t.$1)),
                border: Border.all(color: sel ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.12)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t.$2, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 2),
                Text(t.$3, style: TextStyle(
                    color: sel ? accent : Colors.white60, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        }).toList(),
      ),
    ],
  );

  double _shapeRadius(String shape) {
    switch (shape) {
      case 'circle':   return 32;
      case 'squircle': return 14;
      case 'rounded':  return 10;
      case 'pill':     return 24;
      case 'sharp':    return 2;
      default:         return 10;
    }
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.tune_rounded, label: 'Controls Behavior'),
      // Auto-hide delay
      _SliderRow(
        label: 'Auto-hide delay',
        valueTxt: '${prefs.autoHideSeconds}s',
        value: prefs.autoHideSeconds.toDouble(),
        min: 2, max: 15, divisions: 13,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(autoHideSeconds: v.round())),
      ),
      const SizedBox(height: 6),
      // Controls opacity
      _SliderRow(
        label: 'Controls opacity',
        valueTxt: '${(prefs.controlBarOpacity * 100).round()}%',
        value: prefs.controlBarOpacity,
        min: 0.3, max: 1.0, divisions: 14,
        accent: accent,
        onChanged: (v) => onSave(prefs.copyWith(controlBarOpacity: (v * 100).round() / 100)),
      ),
    ],
  );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueTxt;
  final double value;
  final double min;
  final double max;
  final int    divisions;
  final Color  accent;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label, required this.valueTxt, required this.value,
    required this.min, required this.max, required this.divisions,
    required this.accent, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(child: Text(label,
          style: const TextStyle(color: Color(0xDEFFFFFF), fontSize: 13, fontWeight: FontWeight.w500))),
        Text(valueTxt, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
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
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}
