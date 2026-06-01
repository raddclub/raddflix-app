import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';

/// Settings sheet for Cinematic Mode — customise tap behaviour and strip timer.
class CinematicSettingsSheet extends StatelessWidget {
  const CinematicSettingsSheet({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ModeSettingsSheet(isCinematic: true);
}

/// Settings sheet for Immersive Mode — customise tap, long-press, icon.
class ImmersiveModeSettingsSheet extends StatelessWidget {
  const ImmersiveModeSettingsSheet({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ModeSettingsSheet(isCinematic: false);
}

// ─── Shared preference keys ───────────────────────────────────────────────────
const _kCinTapShowsStrip = 'cin_tap_shows_strip';
const _kCinStripHideSec  = 'cin_strip_hide_sec';
const _kImTapPause       = 'im_tap_pause_resume';
const _kImLongPress      = 'im_longpress_controls';
const _kImHideSec        = 'im_controls_hide_sec';
const _kImShowIcon       = 'im_show_tap_icon';

// ─── Public static helpers to read prefs from player_screen ──────────────────
class ModePrefs {
  static Future<bool> cinTapShowsStrip() async =>
      (await SharedPreferences.getInstance()).getBool(_kCinTapShowsStrip) ?? true;
  static Future<int> cinStripHideSec() async =>
      (await SharedPreferences.getInstance()).getInt(_kCinStripHideSec) ?? 3;
  static Future<bool> imTapPause() async =>
      (await SharedPreferences.getInstance()).getBool(_kImTapPause) ?? true;
  static Future<bool> imLongPressControls() async =>
      (await SharedPreferences.getInstance()).getBool(_kImLongPress) ?? true;
  static Future<int> imControlsHideSec() async =>
      (await SharedPreferences.getInstance()).getInt(_kImHideSec) ?? 3;
  static Future<bool> imShowTapIcon() async =>
      (await SharedPreferences.getInstance()).getBool(_kImShowIcon) ?? true;
}

// ─── Internal sheet ───────────────────────────────────────────────────────────
class _ModeSettingsSheet extends StatefulWidget {
  final bool isCinematic;
  const _ModeSettingsSheet({required this.isCinematic});
  @override
  State<_ModeSettingsSheet> createState() => _ModeSettingsSheetState();
}

class _ModeSettingsSheetState extends State<_ModeSettingsSheet> {
  bool _cinTapShowsStrip = true;
  int  _cinStripHideSec  = 3;
  bool _imTapPause       = true;
  bool _imLongPress      = true;
  int  _imHideSec        = 3;
  bool _imShowIcon       = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cinTapShowsStrip = p.getBool(_kCinTapShowsStrip) ?? true;
      _cinStripHideSec  = p.getInt(_kCinStripHideSec)  ?? 3;
      _imTapPause       = p.getBool(_kImTapPause)       ?? true;
      _imLongPress      = p.getBool(_kImLongPress)      ?? true;
      _imHideSec        = p.getInt(_kImHideSec)         ?? 3;
      _imShowIcon       = p.getBool(_kImShowIcon)        ?? true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCinTapShowsStrip, _cinTapShowsStrip);
    await p.setInt(_kCinStripHideSec,   _cinStripHideSec);
    await p.setBool(_kImTapPause,       _imTapPause);
    await p.setBool(_kImLongPress,      _imLongPress);
    await p.setInt(_kImHideSec,         _imHideSec);
    await p.setBool(_kImShowIcon,        _imShowIcon);
  }

  @override
  Widget build(BuildContext context) {
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
                    color: widget.isCinematic
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF8B5CF6),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.isCinematic
                        ? 'Cinematic Mode Settings'
                        : 'Immersive Mode Settings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  widget.isCinematic
                      ? 'Pure video — no subtitles, no controls'
                      : 'Subtitles only — one tap pauses instantly',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 20),

                if (widget.isCinematic) ...[
                  _SettingToggle(
                    label: 'Tap shows controls strip',
                    subtitle: 'Tap screen to reveal seek bar and pause button',
                    value: _cinTapShowsStrip,
                    onChanged: (v) { setState(() => _cinTapShowsStrip = v); _save(); },
                  ),
                  const SizedBox(height: 16),
                  _SettingPicker(
                    label: 'Strip auto-hide after',
                    value: _cinStripHideSec,
                    options: const [2, 3, 5],
                    labels: const ['2 sec', '3 sec', '5 sec'],
                    onChanged: (v) { setState(() => _cinStripHideSec = v); _save(); },
                  ),
                ] else ...[
                  _SettingToggle(
                    label: 'One tap = pause / resume',
                    subtitle: 'Instantly pause or resume — no control UI appears',
                    value: _imTapPause,
                    onChanged: (v) { setState(() => _imTapPause = v); _save(); },
                  ),
                  const SizedBox(height: 12),
                  _SettingToggle(
                    label: 'Long press shows controls',
                    subtitle: 'Hold screen briefly to reveal seek bar and buttons',
                    value: _imLongPress,
                    onChanged: (v) { setState(() => _imLongPress = v); _save(); },
                  ),
                  const SizedBox(height: 12),
                  _SettingToggle(
                    label: 'Show icon on tap',
                    subtitle: 'Brief play/pause icon flashes at centre when tapping',
                    value: _imShowIcon,
                    onChanged: (v) { setState(() => _imShowIcon = v); _save(); },
                  ),
                  const SizedBox(height: 16),
                  _SettingPicker(
                    label: 'Controls hide after',
                    value: _imHideSec,
                    options: const [2, 3, 5],
                    labels: const ['2 sec', '3 sec', '5 sec'],
                    onChanged: (v) { setState(() => _imHideSec = v); _save(); },
                  ),
                ],
              ],
            ),
    );
  }
}

// ─── Reusable setting widgets ─────────────────────────────────────────────────

class _SettingToggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      )),
      Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ]);
  }
}

class _SettingPicker extends StatelessWidget {
  final String label;
  final int value;
  final List<int> options;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  const _SettingPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                color: sel
                    ? AppColors.primary.withOpacity(0.18)
                    : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? AppColors.primary : Colors.white12,
                ),
              ),
              child: Text(labels[i], style: TextStyle(
                color: sel ? AppColors.primary : Colors.white54,
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
