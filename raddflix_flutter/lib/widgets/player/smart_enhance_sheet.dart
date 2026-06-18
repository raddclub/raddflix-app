import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/player_prefs.dart';
import '../../core/player/smart_enhance.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SMART ENHANCE SHEET
// MX-style intelligent video enhancement panel.
// Slides in from right (landscape) or bottom (portrait) as a transparent
// overlay so the video is always visible live behind it.
//
// Features:
//   • Master ON/OFF toggle with glow ring feedback
//   • 8 content mode cards (Standard / Movie / Sports / Anime /
//     Low Light / AMOLED / Drama / Documentary)
//   • "What's applied" description card per mode
//   • Fine-tune intensity slider (multiplies the preset deltas)
//   • Before/After live toggle — hold to preview without enhance
//   • All changes apply instantly via onPrefsChanged
// ═══════════════════════════════════════════════════════════════════════════════

class SmartEnhanceSheet extends StatefulWidget {
  final PlayerPrefs               prefs;
  final ValueChanged<PlayerPrefs> onPrefsChanged;
  final VoidCallback              onClose;

  const SmartEnhanceSheet({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onClose,
  });

  @override
  State<SmartEnhanceSheet> createState() => _SmartEnhanceSheetState();
}

class _SmartEnhanceSheetState extends State<SmartEnhanceSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;
  bool _closing   = false;
  bool _beforeMode = false;  // holds "before" state while button held
  bool _prevEnabled = true;  // saved state restored when "Before" button released

  // Local copy of intensity multiplier (1.0 = preset default, 0.5 = subtle, 1.5 = strong)
  late double _intensity;

  @override
  void initState() {
    super.initState();
    _intensity = 1.0;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    HapticFeedback.lightImpact();
    _ctrl.reverse().then((_) { if (mounted) widget.onClose(); });
  }

  void _save(PlayerPrefs p) => widget.onPrefsChanged(p);

  void _handleBeforeHold(bool hold) {
    setState(() => _beforeMode = hold);
    if (hold) {
      _prevEnabled = widget.prefs.smartEnhanceEnabled;
      _save(widget.prefs.copyWith(smartEnhanceEnabled: false));
    } else {
      _save(widget.prefs.copyWith(smartEnhanceEnabled: _prevEnabled));
    }
  }

  void _toggleEnabled() {
    HapticFeedback.mediumImpact();
    _save(widget.prefs.copyWith(smartEnhanceEnabled: !widget.prefs.smartEnhanceEnabled));
  }

  void _selectMode(String id) {
    HapticFeedback.selectionClick();
    _save(widget.prefs.copyWith(
      smartEnhanceMode: id,
      smartEnhanceEnabled: true,  // auto-enable when mode selected
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mq          = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final accent      = widget.prefs.accentColor;

    return Stack(children: [
      // backdrop
      Positioned.fill(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(color: Colors.black.withOpacity(0.45 * _anim.value)),
          ),
        ),
      ),
      // panel
      AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          if (isLandscape) {
            final pw  = mq.size.width * 0.50;
            final off = pw * (1.0 - _anim.value);
            return Positioned(right: -off, top: 0, bottom: 0, width: pw,
              child: _Panel(
                prefs: widget.prefs, accent: accent,
                intensity: _intensity,
                beforeMode: _beforeMode,
                onToggle: _toggleEnabled,
                onMode: _selectMode,
                onIntensity: (v) => setState(() => _intensity = v),
                onBeforeHold: _handleBeforeHold,
                onClose: _dismiss,
                isLandscape: true,
              ));
          } else {
            final ph  = mq.size.height * 0.76;
            final off = ph * (1.0 - _anim.value);
            return Positioned(left: 0, right: 0, bottom: -off, height: ph,
              child: _Panel(
                prefs: widget.prefs, accent: accent,
                intensity: _intensity,
                beforeMode: _beforeMode,
                onToggle: _toggleEnabled,
                onMode: _selectMode,
                onIntensity: (v) => setState(() => _intensity = v),
                onBeforeHold: _handleBeforeHold,
                onClose: _dismiss,
                isLandscape: false,
              ));
          }
        },
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final PlayerPrefs prefs;
  final Color       accent;
  final double      intensity;
  final bool        beforeMode;
  final VoidCallback         onToggle;
  final ValueChanged<String> onMode;
  final ValueChanged<double> onIntensity;
  final ValueChanged<bool>   onBeforeHold;
  final VoidCallback onClose;
  final bool isLandscape;

  const _Panel({
    required this.prefs, required this.accent,
    required this.intensity, required this.beforeMode,
    required this.onToggle, required this.onMode,
    required this.onIntensity, required this.onBeforeHold,
    required this.onClose, required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final on     = prefs.smartEnhanceEnabled;
    final preset = getSmartEnhancePreset(prefs.smartEnhanceMode);

    return ClipRRect(
      borderRadius: isLandscape
          ? const BorderRadius.horizontal(left: Radius.circular(22))
          : const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xBB06060F),
            border: isLandscape
                ? const Border(left: BorderSide(color: Colors.white12))
                : const Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
              child: Row(children: [
                Container(width: 3, height: 20,
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFF10B981) : Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  )),
                const SizedBox(width: 10),
                const Text('Smart Enhance',
                  style: TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                if (on)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                    ),
                    child: const Text('ON',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 9,
                          fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                  ),
                ),
              ]),
            ),

            // ── Master toggle ────────────────────────────────────────────────
            _MasterToggle(on: on, accent: accent, onToggle: onToggle),

            Container(height: 1, color: Colors.white.withOpacity(0.07),
              margin: const EdgeInsets.only(top: 12, bottom: 4)),

            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode grid
                    _sectionLabel(Icons.auto_awesome_rounded, 'Content Mode'),
                    const SizedBox(height: 8),
                    _ModeGrid(
                      activeMode: prefs.smartEnhanceMode,
                      enhanceOn:  on,
                      onMode:     onMode,
                    ),

                    const SizedBox(height: 14),

                    // What's applied card
                    if (on) _WhatApplied(preset: preset, intensity: intensity),

                    const SizedBox(height: 14),

                    // Intensity slider
                    _sectionLabel(Icons.tune_rounded, 'Intensity'),
                    const SizedBox(height: 6),
                    _IntensitySlider(
                      value: intensity, accent: accent,
                      onChanged: onIntensity,
                    ),

                    const SizedBox(height: 18),

                    // Before / After compare button
                    _BeforeAfterBtn(
                      beforeMode: beforeMode,
                      enhanceOn:  on,
                      onHold:     onBeforeHold,
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionLabel(IconData icon, String label) => Row(children: [
    Icon(icon, color: Colors.white38, size: 12),
    const SizedBox(width: 6),
    Text(label.toUpperCase(),
      style: const TextStyle(color: Colors.white38, fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 1.1)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// MASTER TOGGLE
// ─────────────────────────────────────────────────────────────────────────────

class _MasterToggle extends StatelessWidget {
  final bool on;
  final Color accent;
  final VoidCallback onToggle;
  const _MasterToggle({required this.on, required this.accent, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: on
              ? const Color(0xFF10B981).withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on
                ? const Color(0xFF10B981).withOpacity(0.55)
                : Colors.white.withOpacity(0.10),
            width: on ? 1.5 : 1,
          ),
          boxShadow: on
              ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.15),
                  blurRadius: 14, spreadRadius: 2)]
              : [],
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: on
                  ? const Color(0xFF10B981).withOpacity(0.20)
                  : Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              on ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
              color: on ? const Color(0xFF10B981) : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                on ? 'Smart Enhance Active' : 'Smart Enhance Off',
                style: TextStyle(
                  color: on ? Colors.white : Colors.white60,
                  fontSize: 14, fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                on ? 'Video is being enhanced' : 'Tap to enable enhancement',
                style: TextStyle(
                  color: on ? const Color(0xFF10B981) : Colors.white30,
                  fontSize: 11,
                ),
              ),
            ],
          )),
          _BigSwitch(on: on),
        ]),
      ),
    );
  }
}

class _BigSwitch extends StatelessWidget {
  final bool on;
  const _BigSwitch({required this.on});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 46, height: 26,
    decoration: BoxDecoration(
      color: on ? const Color(0xFF10B981) : Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(13),
    ),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 22, height: 22, margin: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODE GRID — 3-column card grid
// ─────────────────────────────────────────────────────────────────────────────

class _ModeGrid extends StatelessWidget {
  final String activeMode;
  final bool   enhanceOn;
  final ValueChanged<String> onMode;
  const _ModeGrid({required this.activeMode, required this.enhanceOn, required this.onMode});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: kSmartEnhancePresets.length,
      itemBuilder: (_, i) {
        final p   = kSmartEnhancePresets[i];
        final sel = activeMode == p.id && enhanceOn;
        final col = Color(int.parse('FF${p.colorHex}', radix: 16));
        return GestureDetector(
          onTap: () => onMode(p.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: sel ? col.withOpacity(0.18) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel ? col.withOpacity(0.70) : Colors.white.withOpacity(0.10),
                width: sel ? 1.5 : 1,
              ),
              boxShadow: sel
                  ? [BoxShadow(color: col.withOpacity(0.18), blurRadius: 10, spreadRadius: 1)]
                  : [],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(p.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(p.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: sel ? Colors.white : Colors.white70,
                  fontSize: 11, fontWeight: FontWeight.w700,
                )),
              if (sel) ...[
                const SizedBox(height: 2),
                Container(
                  width: 16, height: 2,
                  decoration: BoxDecoration(
                    color: col, borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WHAT'S APPLIED CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WhatApplied extends StatelessWidget {
  final SmartEnhancePreset preset;
  final double intensity;
  const _WhatApplied({required this.preset, required this.intensity});

  @override
  Widget build(BuildContext context) {
    final col = Color(int.parse('FF${preset.colorHex}', radix: 16));
    final bStr = _fmt(preset.brightness * intensity);
    final cStr = _fmt(preset.contrast   * intensity);
    final sStr = _fmt(preset.saturation * intensity);
    final shStr = _fmtPct(preset.sharpness * intensity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: col.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withOpacity(0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(preset.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(preset.label,
            style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Expanded(child: Text(preset.description,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6, runSpacing: 4,
          children: [
            if (preset.contrast.abs() > 0.01)    _badge('Contrast $cStr',   Icons.tonality_rounded,            col),
            if (preset.saturation.abs() > 0.01)   _badge('Color $sStr',      Icons.color_lens_rounded,          col),
            if (preset.brightness.abs() > 0.01)   _badge('Brightness $bStr', Icons.brightness_6_rounded,        col),
            if (preset.sharpness > 0.01)           _badge('Detail $shStr',    Icons.details_rounded,             col),
            if (preset.hue != 0)                   _badge('Warm tone',        Icons.wb_sunny_rounded,            col),
            if (preset.noiseReduce)                _badge('Noise reduce',     Icons.noise_aware_rounded,          col),
          ],
        ),
      ]),
    );
  }

  Widget _badge(String label, IconData icon, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: col.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: col.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: col, size: 10),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w600)),
    ]),
  );

  String _fmt(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${(v * 100).round()}%';
  }

  String _fmtPct(double v) {
    if (v < 0.08)  return 'Subtle';
    if (v < 0.18)  return 'Light';
    if (v < 0.28)  return 'Medium';
    return 'Strong';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTENSITY SLIDER
// ─────────────────────────────────────────────────────────────────────────────

class _IntensitySlider extends StatelessWidget {
  final double             value;
  final Color              accent;
  final ValueChanged<double> onChanged;
  const _IntensitySlider({required this.value, required this.accent, required this.onChanged});

  String get _label {
    if (value < 0.65) return 'Subtle';
    if (value < 0.9)  return 'Soft';
    if (value < 1.1)  return 'Default';
    if (value < 1.35) return 'Strong';
    return 'Max';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Text('Subtle', style: TextStyle(color: Colors.white30, fontSize: 10)),
        Expanded(child: SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF10B981),
            inactiveTrackColor: Colors.white.withOpacity(0.12),
            thumbColor: const Color(0xFF10B981),
            overlayColor: const Color(0xFF10B981).withOpacity(0.16),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.clamp(0.5, 1.5),
            min: 0.5, max: 1.5, divisions: 10,
            onChanged: onChanged,
          ),
        )),
        const Text('Max', style: TextStyle(color: Colors.white30, fontSize: 10)),
      ]),
      Center(child: Text(_label,
        style: const TextStyle(color: Color(0xFF10B981), fontSize: 11,
            fontWeight: FontWeight.w700))),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BEFORE / AFTER BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _BeforeAfterBtn extends StatelessWidget {
  final bool beforeMode;
  final bool enhanceOn;
  final ValueChanged<bool> onHold;
  const _BeforeAfterBtn({required this.beforeMode, required this.enhanceOn, required this.onHold});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) { if (enhanceOn) { HapticFeedback.selectionClick(); onHold(true);  } },
      onTapUp:    (_) { if (enhanceOn) onHold(false); },
      onTapCancel:()  { if (enhanceOn) onHold(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: beforeMode
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: beforeMode
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              beforeMode ? Icons.compare_rounded : Icons.compare_outlined,
              color: beforeMode ? Colors.white : Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              beforeMode ? 'BEFORE (holding)' : 'Hold to Compare Before/After',
              style: TextStyle(
                color: beforeMode ? Colors.white : Colors.white38,
                fontSize: 12, fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          if (!beforeMode)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text('Hold button to temporarily see original',
                style: TextStyle(color: Colors.white24, fontSize: 10)),
            ),
        ]),
      ),
    );
  }
}
