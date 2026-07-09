import 'package:flutter/material.dart';
import '../design_system/spacing/radd_space.dart';
import '../core/player/player_prefs.dart';
import '../core/player/player_theme.dart';
import '../widgets/player/seek_bar_painter.dart';
import '../widgets/player/color_picker_sheet.dart';
import '../widgets/player/theme_picker_sheet.dart';

/// Phase L: Full Player Settings Screen (7 sections, 35+ options).
class PlayerSettingsScreen extends StatefulWidget {
  final PlayerPrefs prefs;
  final ValueChanged<PlayerPrefs> onSave;
  const PlayerSettingsScreen({super.key, required this.prefs, required this.onSave});
  @override State<PlayerSettingsScreen> createState() => _State();
}

class _State extends State<PlayerSettingsScreen> {
  late PlayerPrefs _p;
  bool _dirty = false;
  @override void initState() { super.initState(); _p = widget.prefs; }
  void _u(PlayerPrefs n) => setState(() { _p = n; _dirty = true; });
  Future<void> _save() async {
    await _p.save(); widget.onSave(_p);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Settings saved'), backgroundColor: _p.accentColor,
      duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext ctx) {
    final a = _p.accentColor;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121E), foregroundColor: Colors.white,
        title: const Text('Player Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [if (_dirty) TextButton(onPressed: _save, child: Text('Save',
            style: TextStyle(color: a, fontSize: 14, fontWeight: FontWeight.w700)))],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Colors.white10))),
      body: ListView(children: [
        _sec('Appearance', [
          _tap(ctx, Icons.palette_rounded, 'Theme',
              sub: '${themeById(_p.playerTheme).emoji} ${themeById(_p.playerTheme).name}',
              onTap: () => showThemePicker(context: ctx, currentThemeId: _p.playerTheme,
                  onThemeSelected: (t) => _u(_p.copyWith(playerTheme: t.id,
                    accentColorValue: t.accentColor.value, seekBarStyle: t.seekBarStyle)))),
          _tap(ctx, Icons.color_lens_rounded, 'Accent Color',
              sub: '#${a.value.toRadixString(16).toUpperCase().padLeft(8,'0').substring(2)}',
              trail: Container(width: 22, height: 22, decoration: BoxDecoration(
                  color: a, shape: BoxShape.circle, border: Border.all(color: Colors.white24))),
              onTap: () => showColorPicker(context: ctx, initialColor: a,
                  onColorSelected: (c) => _u(_p.copyWith(accentColorValue: c.value)))),
          _choices(Icons.rounded_corner_rounded, 'Button Shape',
              ['circle','squircle','rounded','sharp','pill'],
              ['Circle','Squircle','Rounded','Sharp','Pill'],
              _p.buttonShape, a, (v) => _u(_p.copyWith(buttonShape: v))),
          _choices(Icons.grid_view_rounded, 'Icon Pack',
              ['mx','ios','fluent','material3','cute','minimal'],
              ['MX','iOS','Fluent','M3','Cute','Min'],
              _p.iconPack, a, (v) => _u(_p.copyWith(iconPack: v))),
          _choices(Icons.blur_on_rounded, 'Controls BG',
              ['none','glass','gradient','solid','mesh'],
              ['None','Glass','Gradient','Solid','Mesh'],
              _p.controlsBgStyle, a, (v) => _u(_p.copyWith(controlsBgStyle: v))),
          _choices(Icons.linear_scale_rounded, 'Seek Bar',
              SeekBarStyle.values.map((s) => s.name).toList(),
              const ['Classic','Bold','Gradient','Wave','Neon','Film','Chapters','Dots','Arc','Minimal'],
              _p.seekBarStyle, a, (v) => _u(_p.copyWith(seekBarStyle: v))),
        ]),
        _sec('Subtitles', [
          _tog(Icons.subtitles_rounded, 'Enable', _p.subtitleEnabled, a,
              (v) => _u(_p.copyWith(subtitleEnabled: v))),
          _sld(ctx, Icons.text_fields_rounded, 'Font Size',
              _p.subtitleFontSize, 10, 48, 38, a, (v) => '${v.toInt()}px',
              (v) => _u(_p.copyWith(subtitleFontSize: v))),
          _tog(Icons.format_bold_rounded, 'Bold', _p.subtitleBold, a,
              (v) => _u(_p.copyWith(subtitleBold: v))),
        ]),
        _sec('Gestures', [
          _tog(Icons.swipe_rounded, 'Volume swipe', _p.swipeVolumeEnabled, a,
              (v) => _u(_p.copyWith(swipeVolumeEnabled: v))),
          _tog(Icons.brightness_medium_rounded, 'Brightness swipe', _p.swipeBrightnessEnabled, a,
              (v) => _u(_p.copyWith(swipeBrightnessEnabled: v))),
          _tog(Icons.fast_forward_rounded, 'Horizontal seek', _p.swipeSeekEnabled, a,
              (v) => _u(_p.copyWith(swipeSeekEnabled: v))),
          _tog(Icons.touch_app_rounded, 'Double-tap seek', _p.doubleTapSeekEnabled, a,
              (v) => _u(_p.copyWith(doubleTapSeekEnabled: v))),
          _sld(ctx, Icons.replay_10_rounded, 'Double-tap secs',
              _p.doubleTapSeekSeconds.toDouble(), 5, 60, 11, a, (v) => '${v.toInt()}s',
              (v) => _u(_p.copyWith(doubleTapSeekSeconds: v.toInt()))),
          _tog(Icons.zoom_in_rounded, 'Pinch to zoom', _p.pinchZoomEnabled, a,
              (v) => _u(_p.copyWith(pinchZoomEnabled: v))),
          _tog(Icons.speed_rounded, 'Long-press speed', _p.longPressSpeedEnabled, a,
              (v) => _u(_p.copyWith(longPressSpeedEnabled: v))),
        ]),
        _sec('Playback', [
          _tog(Icons.play_arrow_rounded, 'Auto-play next', _p.autoPlayNext, a,
              (v) => _u(_p.copyWith(autoPlayNext: v))),
          _tog(Icons.location_history_rounded, 'Remember position', _p.rememberPosition, a,
              (v) => _u(_p.copyWith(rememberPosition: v))),
          _tog(Icons.speed_rounded, 'Remember speed', _p.rememberSpeed, a,
              (v) => _u(_p.copyWith(rememberSpeed: v))),
          _tog(Icons.hardware_rounded, 'Hardware decoder', _p.hwDecoderEnabled, a,
              (v) => _u(_p.copyWith(hwDecoderEnabled: v))),
          _tog(Icons.audiotrack_rounded, 'Remember audio track', _p.rememberAudioTrack, a,
              (v) => _u(_p.copyWith(rememberAudioTrack: v))),
        ]),
        _sec('Interface', [
          _sld(ctx, Icons.tune_rounded, 'Button size', _p.buttonSize, 0.7, 1.5, 16, a,
              (v) => '${(v*100).toInt()}%', (v) => _u(_p.copyWith(buttonSize: v))),
          _sld(ctx, Icons.opacity_rounded, 'Controls opacity', _p.controlBarOpacity, 0.3, 1.0, 14, a,
              (v) => '${(v*100).toInt()}%', (v) => _u(_p.copyWith(controlBarOpacity: v))),
          _sld(ctx, Icons.timer_rounded, 'Auto-hide delay',
              _p.autoHideSeconds.toDouble(), 2, 15, 13, a, (v) => '${v.toInt()}s',
              (v) => _u(_p.copyWith(autoHideSeconds: v.toInt()))),
          _tog(Icons.wifi_rounded, 'Show network speed', _p.showNetworkSpeed, a,
              (v) => _u(_p.copyWith(showNetworkSpeed: v))),
          _tog(Icons.info_outline_rounded, 'Show playback info', _p.showPlaybackInfo, a,
              (v) => _u(_p.copyWith(showPlaybackInfo: v))),
        ]),
        _sec('Center Controls', [
          // ── Position ─────────────────────────────────────────────────────
          _choices(Icons.my_location_rounded, 'Controls Position',
              ['center', 'bottom', 'hidden'],
              ['Center (Classic)', 'Bottom (Modern)', 'Hidden'],
              _p.centerBtnPosition, a, (v) => _u(_p.copyWith(centerBtnPosition: v))),
          // ── Button style ─────────────────────────────────────────────────
          _sld(ctx, Icons.zoom_in_rounded, 'Button scale',
              _p.centerBtnScale, 0.6, 2.0, 14, a, (v) => '${(v * 100).toInt()}%',
              (v) => _u(_p.copyWith(centerBtnScale: v))),
          if (_p.centerBtnPosition == 'center')
            _sld(ctx, Icons.vertical_align_center_rounded, 'Vertical position',
                _p.centerBtnVerticalOffset, -150.0, 150.0, 30, a,
                (v) => '${v.toInt()}px', (v) => _u(_p.copyWith(centerBtnVerticalOffset: v))),
          _tog(Icons.hide_image_outlined, 'Icon only (no background)', _p.centerBtnIconOnly, a,
              (v) => _u(_p.copyWith(centerBtnIconOnly: v))),
          if (!_p.centerBtnIconOnly)
            _sld(ctx, Icons.opacity_rounded, 'Button bg opacity',
                _p.centerBtnBgOpacity, 0.0, 1.0, 10, a, (v) => '${(v * 100).toInt()}%',
                (v) => _u(_p.copyWith(centerBtnBgOpacity: v))),
          _tog(Icons.skip_previous_rounded, 'Show Prev episode button', _p.showCenterPrev, a,
              (v) => _u(_p.copyWith(showCenterPrev: v))),
          _tog(Icons.skip_next_rounded, 'Show Next episode button', _p.showCenterNext, a,
              (v) => _u(_p.copyWith(showCenterNext: v))),
          _tog(Icons.fast_forward_rounded, 'Show Skip Intro button', _p.showCenterSkip, a,
              (v) => _u(_p.copyWith(showCenterSkip: v))),
        ]),
        // ── Quick Shortcut Bar ─────────────────────────────────────────────
        _sec('Quick Shortcut Bar', [
          _info('One-tap icons shown above the seek bar — instant access to the most-used features without opening any menu.'),
          _tog(Icons.view_timeline_rounded, 'Show Quick Bar', _p.showQuickBar, a,
              (v) => _u(_p.copyWith(showQuickBar: v))),
          if (_p.showQuickBar) ...[
            _qbItem(ctx, Icons.picture_in_picture_alt_rounded, 'PiP (Picture-in-Picture)', 'pip', a),
            _qbItem(ctx, Icons.play_circle_outline_rounded, 'Background Play', 'bgplay', a),
            _qbItem(ctx, Icons.fit_screen_rounded, 'Resize / Fit', 'fit', a),
            _qbItem(ctx, Icons.camera_alt_rounded, 'Screenshot', 'screenshot', a),
            _qbItem(ctx, Icons.speed_rounded, 'Speed', 'speed', a),
            _qbItem(ctx, Icons.subtitles_rounded, 'Subtitles', 'subtitle', a),
            _qbItem(ctx, Icons.lock_outline_rounded, 'Lock Controls', 'lock', a),
            _qbItem(ctx, Icons.dark_mode_rounded, 'Night Mode', 'nightmode', a),
          ],
        ]),
        _sec('Advanced', [
          _tog(Icons.skip_next_rounded, 'Rage skip', _p.rageSkipEnabled, a,
              (v) => _u(_p.copyWith(rageSkipEnabled: v))),
          _tog(Icons.light_mode_rounded, 'Ambilight', _p.ambilightEnabled, a,
              (v) => _u(_p.copyWith(ambilightEnabled: v))),
          _tog(Icons.health_and_safety_outlined, 'Binge guard', _p.bingeGuardEnabled, a,
              (v) => _u(_p.copyWith(bingeGuardEnabled: v))),
          _tog(Icons.vibration_rounded, 'Vibrate on gesture', _p.vibrateOnGesture, a,
              (v) => _u(_p.copyWith(vibrateOnGesture: v))),
          _tog(Icons.loop_rounded, 'A-B loop', _p.abLoopEnabled, a,
              (v) => _u(_p.copyWith(abLoopEnabled: v))),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E2E),
                  title: const Text('Reset all?', style: TextStyle(color: Colors.white)),
                  content: const Text('Resets to defaults.',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                    TextButton(onPressed: () => Navigator.pop(c, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        child: const Text('Reset'))]));
              if (ok == true) { await PlayerPrefs.reset(); _u(const PlayerPrefs()); await const PlayerPrefs().save(); }
            },
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Reset all player settings'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent,
                side: const BorderSide(color: AppColors.error, width: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
      ]),
    );
  }

  Widget _sec(String t, List<Widget> ch) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16,20,16,8),
        child: Text(t.toUpperCase(), style: const TextStyle(
            color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0))),
    Container(
      decoration: BoxDecoration(color: const Color(0xFF12121E),
          border: Border(top: BorderSide(color: Colors.white10),
              bottom: BorderSide(color: Colors.white10))),
      child: Column(children: [...ch.map((c) => Column(children: [c,
          const Divider(height:1, color:Colors.white10)]))])),
  ]);

  Widget _info(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)));

  Widget _tog(IconData icon, String label, bool value, Color accent, ValueChanged<bool> onC) =>
    InkWell(onTap: () => onC(!value), child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [Icon(icon, color: Colors.white38, size: 18), const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Switch(value: value, activeColor: accent, onChanged: onC,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)])));

  Widget _sld(BuildContext ctx, IconData icon, String label, double value,
      double min, double max, int div, Color accent, String Function(double) fmt,
      ValueChanged<double> onC) =>
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [Icon(icon, color: Colors.white38, size: 18), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
            Text(fmt(value), style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700))]),
          SliderTheme(
            data: SliderThemeData(trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: accent, inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white, overlayColor: accent.withOpacity(0.15)),
            child: Slider(value: value.clamp(min,max), min: min, max: max,
                divisions: div, onChanged: onC))]))]));

  Widget _tap(BuildContext ctx, IconData icon, String label,
      {String? sub, Widget? trail, required VoidCallback onTap}) =>
    InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [Icon(icon, color: Colors.white38, size: 18), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (sub != null) Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11))])),
        if (trail != null) trail, const SizedBox(width: RaddSpace.sm),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20)])));

  Widget _choices(IconData icon, String label, List<String> choices, List<String> labels,
      String value, Color accent, ValueChanged<String> onC) =>
    Padding(padding: const EdgeInsets.fromLTRB(16,10,16,10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: Colors.white38, size: 18), const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))]),
        const SizedBox(height: RaddSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, children: List.generate(choices.length, (i) {
          final sel = value == choices[i];
          return GestureDetector(onTap: () => onC(choices[i]),
            child: AnimatedContainer(duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sel ? accent : Colors.white12,
                    width: sel ? 1.5 : 1)),
              child: Text(labels[i], style: TextStyle(
                  color: sel ? Colors.white : Colors.white60,
                  fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.normal))));
        }))]));

  Widget _qbItem(BuildContext ctx, IconData icon, String label, String id, Color accent) {
    final items = _p.quickBarItems.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final active = items.contains(id);
    return InkWell(
      onTap: () {
        final next = List<String>.from(items);
        if (active) next.remove(id); else next.add(id);
        _u(_p.copyWith(quickBarItems: next.join(',')));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, color: active ? accent : Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? accent.withOpacity(0.2) : Colors.transparent,
              border: Border.all(color: active ? accent : Colors.white24, width: 1.5),
            ),
            child: active ? Icon(Icons.check_rounded, color: accent, size: 14) : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }
}
