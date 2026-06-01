import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';

/// Settings sheet for Cinematic Mode.
/// Pass [initialOpacity] and [onOpacityChanged] to get live opacity control.
class CinematicSettingsSheet extends StatelessWidget {
  final double initialOpacity;
  final ValueChanged<double>? onOpacityChanged;
  const CinematicSettingsSheet({
    super.key,
    this.initialOpacity = 0.5,
    this.onOpacityChanged,
  });
  @override
  Widget build(BuildContext context) => _ModeSettingsSheet(
        isCinematic: true,
        initialOpacity: initialOpacity,
        onOpacityChanged: onOpacityChanged,
      );
}

/// Settings sheet for Immersive Mode.
class ImmersiveModeSettingsSheet extends StatelessWidget {
  const ImmersiveModeSettingsSheet({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ModeSettingsSheet(isCinematic: false);
}

// ─── Shared preference keys ───────────────────────────────────────────────────
const _kCinTapShowsStrip = 'cin_tap_shows_strip';
const _kCinStripHideSec  = 'cin_strip_hide_sec';
const _kCinOpacity       = 'cin_controls_opacity';
const _kImTapPause       = 'im_tap_pause_resume';
const _kImLongPress      = 'im_longpress_controls';
const _kImHideSec        = 'im_controls_hide_sec';
const _kImShowIcon       = 'im_show_tap_icon';

// ─── Public static helpers ────────────────────────────────────────────────────
class ModePrefs {
  static Future<bool>   cinTapShowsStrip()  async => (await SharedPreferences.getInstance()).getBool(_kCinTapShowsStrip) ?? true;
  static Future<int>    cinStripHideSec()   async => (await SharedPreferences.getInstance()).getInt(_kCinStripHideSec)   ?? 3;
  static Future<double> cinOpacity()        async => (await SharedPreferences.getInstance()).getDouble(_kCinOpacity)     ?? 0.5;
  static Future<bool>   imTapPause()        async => (await SharedPreferences.getInstance()).getBool(_kImTapPause)       ?? true;
  static Future<bool>   imLongPressControls() async => (await SharedPreferences.getInstance()).getBool(_kImLongPress)   ?? true;
  static Future<int>    imControlsHideSec() async => (await SharedPreferences.getInstance()).getInt(_kImHideSec)         ?? 3;
  static Future<bool>   imShowTapIcon()     async => (await SharedPreferences.getInstance()).getBool(_kImShowIcon)       ?? true;
}

// ─── Internal sheet ───────────────────────────────────────────────────────────
class _ModeSettingsSheet extends StatefulWidget {
  final bool isCinematic;
  final double initialOpacity;
  final ValueChanged<double>? onOpacityChanged;
  const _ModeSettingsSheet({
    required this.isCinematic,
    this.initialOpacity = 0.5,
    this.onOpacityChanged,
  });
  @override
  State<_ModeSettingsSheet> createState() => _ModeSettingsSheetState();
}

class _ModeSettingsSheetState extends State<_ModeSettingsSheet> {
  bool   _cinTapShowsStrip = true;
  int    _cinStripHideSec  = 3;
  double _cinOpacity       = 0.5;
  bool   _imTapPause       = true;
  bool   _imLongPress      = true;
  int    _imHideSec        = 3;
  bool   _imShowIcon       = true;
  bool   _loading          = true;

  static const _blue   = Color(0xFF3B82F6);
  static const _purple = Color(0xFF8B5CF6);

  @override
  void initState() {
    super.initState();
    _cinOpacity = widget.initialOpacity;
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cinTapShowsStrip = p.getBool(_kCinTapShowsStrip) ?? true;
      _cinStripHideSec  = p.getInt(_kCinStripHideSec)   ?? 3;
      _cinOpacity       = p.getDouble(_kCinOpacity)      ?? widget.initialOpacity;
      _imTapPause       = p.getBool(_kImTapPause)        ?? true;
      _imLongPress      = p.getBool(_kImLongPress)       ?? true;
      _imHideSec        = p.getInt(_kImHideSec)          ?? 3;
      _imShowIcon       = p.getBool(_kImShowIcon)        ?? true;
      _loading          = false;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCinTapShowsStrip, _cinTapShowsStrip);
    await p.setInt(_kCinStripHideSec,   _cinStripHideSec);
    await p.setDouble(_kCinOpacity,     _cinOpacity);
    await p.setBool(_kImTapPause,       _imTapPause);
    await p.setBool(_kImLongPress,      _imLongPress);
    await p.setInt(_kImHideSec,         _imHideSec);
    await p.setBool(_kImShowIcon,       _imShowIcon);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isCinematic ? _blue : _purple;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0101018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: _loading
          ? const SizedBox(height: 120,
              child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                Row(children: [
                  Icon(
                    widget.isCinematic
                        ? Icons.dark_mode_rounded
                        : Icons.visibility_off_rounded,
                    color: accent, size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.isCinematic
                        ? 'Cinematic Mode Settings'
                        : 'Immersive Mode Settings',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  widget.isCinematic
                      ? 'Controls dim to your chosen opacity — all gestures still work'
                      : 'Subtitles only — one tap pauses instantly',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 20),

                if (widget.isCinematic) ...[
                  // ── Controls Opacity Slider ──────────────────────────────────
                  _SectionLabel('Controls Transparency'),
                  const SizedBox(height: 8),
                  // Live preview bar
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(children: [
                        // Preview: dimmed controls bar
                        Opacity(
                          opacity: _cinOpacity.clamp(0.15, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.6),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Icon(Icons.skip_previous_rounded,
                                    color: Colors.white70, size: 20),
                                Container(
                                  width: 34, height: 34,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFE8002D),
                                  ),
                                  child: const Icon(Icons.pause_rounded,
                                      color: Colors.white, size: 18),
                                ),
                                Icon(Icons.skip_next_rounded,
                                    color: Colors.white70, size: 20),
                                const Spacer(),
                                Text(
                                  '${(_cinOpacity * 100).toInt()}%',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                ),
                                const SizedBox(width: 10),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                      activeTrackColor: _blue,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      overlayColor: _blue.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _cinOpacity,
                      min: 0.15,
                      max: 1.0,
                      divisions: 17,
                      label: '${(_cinOpacity * 100).toInt()}%',
                      onChanged: (v) {
                        setState(() => _cinOpacity = v);
                        widget.onOpacityChanged?.call(v);
                      },
                      onChangeEnd: (v) => _save(),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('15%  (Ghost)',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                      Text('50%  (Dim)',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                      Text('100%  (Full)',
                          style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),

                  _SettingToggle(
                    label: 'Tap shows controls strip',
                    subtitle: 'Tap screen to reveal seek bar and pause button',
                    value: _cinTapShowsStrip,
                    accent: _blue,
                    onChanged: (v) { setState(() => _cinTapShowsStrip = v); _save(); },
                  ),
                  const SizedBox(height: 16),
                  _SettingPicker(
                    label: 'Strip auto-hide after',
                    value: _cinStripHideSec,
                    options: const [2, 3, 5],
                    labels: const ['2 sec', '3 sec', '5 sec'],
                    accent: _blue,
                    onChanged: (v) { setState(() => _cinStripHideSec = v); _save(); },
                  ),
                ] else ...[
                  _SettingToggle(
                    label: 'One tap = pause / resume',
                    subtitle: 'Instantly pause or resume — no control UI appears',
                    value: _imTapPause,
                    accent: _purple,
                    onChanged: (v) { setState(() => _imTapPause = v); _save(); },
                  ),
                  const SizedBox(height: 12),
                  _SettingToggle(
                    label: 'Long press shows controls',
                    subtitle: 'Hold screen briefly to reveal seek bar and buttons',
                    value: _imLongPress,
                    accent: _purple,
                    onChanged: (v) { setState(() => _imLongPress = v); _save(); },
                  ),
                  const SizedBox(height: 12),
                  _SettingToggle(
                    label: 'Show icon on tap',
                    subtitle: 'Brief play/pause icon flashes at centre when tapping',
                    value: _imShowIcon,
                    accent: _purple,
                    onChanged: (v) { setState(() => _imShowIcon = v); _save(); },
                  ),
                  const SizedBox(height: 16),
                  _SettingPicker(
                    label: 'Controls hide after',
                    value: _imHideSec,
                    options: const [2, 3, 5],
                    labels: const ['2 sec', '3 sec', '5 sec'],
                    accent: _purple,
                    onChanged: (v) { setState(() => _imHideSec = v); _save(); },
                  ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white60,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}

class _SettingToggle extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _SettingToggle({
    required this.label, required this.subtitle,
    required this.value, required this.accent, required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ])),
      Switch(
        value: value, onChanged: onChanged,
        activeColor: accent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ],
  );
}

class _SettingPicker extends StatelessWidget {
  final String label;
  final int value;
  final List<int> options;
  final List<String> labels;
  final Color accent;
  final ValueChanged<int> onChanged;
  const _SettingPicker({
    required this.label, required this.value,
    required this.options, required this.labels,
    required this.accent, required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      const SizedBox(height: 10),
      Row(children: List.generate(options.length, (i) {
        final sel = options[i] == value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(options[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? accent.withOpacity(0.18) : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? accent : Colors.white12),
              ),
              child: Text(labels[i], style: TextStyle(
                color: sel ? accent : Colors.white54,
                fontSize: 13,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          ),
        );
      })),
    ]);
  }
}
