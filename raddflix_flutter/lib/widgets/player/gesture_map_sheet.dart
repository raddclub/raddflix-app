import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:raddflix/core/design/app_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase C — Full Gesture Action Remapping
/// Every gesture zone maps to any player action. Persisted in SharedPreferences.

// Gesture → (label, icon)
const kGestureActions = <String, (String, IconData)>{
  'play_pause':       ('Play / Pause',         Icons.play_arrow_rounded),
  'seek_back_5':      ('Seek Back 5s',          Icons.replay_5_rounded),
  'seek_fwd_5':       ('Seek Forward 5s',       Icons.forward_5_rounded),
  'seek_back_10':     ('Seek Back 10s',         Icons.replay_10_rounded),
  'seek_fwd_10':      ('Seek Forward 10s',      Icons.forward_10_rounded),
  'seek_back_30':     ('Seek Back 30s',         Icons.replay_30_rounded),
  'seek_fwd_30':      ('Seek Forward 30s',      Icons.forward_30_rounded),
  'volume_up':        ('Volume Up',             Icons.volume_up_rounded),
  'volume_down':      ('Volume Down',           Icons.volume_down_rounded),
  'brightness_up':    ('Brightness Up',         Icons.brightness_high_rounded),
  'brightness_down':  ('Brightness Down',       Icons.brightness_low_rounded),
  'speed_up':         ('Speed +0.25×',          Icons.fast_forward_rounded),
  'speed_down':       ('Speed −0.25×',          Icons.slow_motion_video_rounded),
  'lock':             ('Lock Controls',         Icons.lock_outline_rounded),
  'rotate':           ('Rotate Screen',         Icons.screen_rotation_rounded),
  'mode_cycle':       ('Cycle Mode (Cin/Imm)',  Icons.layers_rounded),
  'skip_intro':       ('Skip Intro',            Icons.skip_next_rounded),
  'next_episode':     ('Next Episode',          Icons.skip_next_rounded),
  'screenshot':       ('Screenshot',            Icons.photo_camera_rounded),
  'pip':              ('Picture-in-Picture',    Icons.picture_in_picture_alt_rounded),
  'rage_skip':        ('Rage Skip (+2min)',      Icons.double_arrow_rounded),
  'bookmark':         ('Add Bookmark',          Icons.bookmark_add_rounded),
  'nothing':          ('Nothing',               AppIcons.block),
};

// Default mapping
const kDefaultGestureMap = <String, String>{
  'left_swipe_v':    'brightness_up',
  'right_swipe_v':   'volume_up',
  'center_swipe_h':  'seek_fwd_10',
  'left_double_tap': 'seek_back_10',
  'right_double_tap':'seek_fwd_10',
  'center_double_tap':'play_pause',
  'long_press':      'speed_up',
  'triple_tap':      'rage_skip',
};

const _kPrefKey = 'player_gesture_action_map_v2';

class GestureMapSheet extends StatefulWidget {
  final Map<String, String> current;
  final ValueChanged<Map<String, String>> onChanged;
  final Color accentColor;

  const GestureMapSheet({
    super.key,
    required this.current,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  State<GestureMapSheet> createState() => _GestureMapSheetState();

  static Future<Map<String, String>> load() async {
    final s = await SharedPreferences.getInstance();
    final raw = s.getString(_kPrefKey);
    if (raw == null) return Map.from(kDefaultGestureMap);
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return Map.from(kDefaultGestureMap);
    }
  }

  static Future<void> save(Map<String, String> map) async {
    final s = await SharedPreferences.getInstance();
    await s.setString(_kPrefKey, jsonEncode(map));
  }
}

class _GestureMapSheetState extends State<GestureMapSheet> {
  late Map<String, String> _map;

  static const _zones = [
    ('left_swipe_v',     'Left side — swipe up/down',     Icons.swipe_up_rounded),
    ('right_swipe_v',    'Right side — swipe up/down',    Icons.swipe_up_alt_rounded),
    ('center_swipe_h',   'Center — swipe left/right',     Icons.swap_horiz_rounded),
    ('left_double_tap',  'Left side — double tap',        Icons.touch_app_rounded),
    ('right_double_tap', 'Right side — double tap',       Icons.touch_app_rounded),
    ('center_double_tap','Center — double tap',           Icons.ads_click_rounded),
    ('long_press',       'Anywhere — long press',         Icons.touch_app_outlined),
    ('triple_tap',       'Center — triple tap',           Icons.add_circle_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _map = Map.from(widget.current);
  }

  void _reset() {
    setState(() => _map = Map.from(kDefaultGestureMap));
    widget.onChanged(_map);
    GestureMapSheet.save(_map);
  }

  Future<void> _pickAction(String zone) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActionPicker(
          current: _map[zone] ?? 'nothing', accent: widget.accentColor),
    );
    if (res != null) {
      setState(() => _map[zone] = res);
      widget.onChanged(_map);
      GestureMapSheet.save(_map);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Icon(Icons.touch_app_rounded, color: widget.accentColor, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Customize Gestures',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: _reset,
              child: Text('Reset defaults',
                  style: TextStyle(color: widget.accentColor, fontSize: 12)),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Tap any gesture zone to change what it does.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
            itemCount: _zones.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (_, i) {
              final (key, label, icon) = _zones[i];
              final actionKey = _map[key] ?? 'nothing';
              final action = kGestureActions[actionKey];
              return InkWell(
                onTap: () => _pickAction(key),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(9)),
                      child: Icon(icon, color: Colors.white54, size: 19)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(action?.$2 ?? AppIcons.block,
                                color: widget.accentColor, size: 13),
                            const SizedBox(width: 5),
                            Text(action?.$1 ?? 'Nothing',
                                style: TextStyle(
                                    color: widget.accentColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white24, size: 18),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 200.ms);
  }
}

class _ActionPicker extends StatelessWidget {
  final String current;
  final Color accent;
  const _ActionPicker({required this.current, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Action',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700))),
        ),
        const Divider(color: Colors.white10, height: 1),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
            children: kGestureActions.entries.map((e) {
              final isSel = e.key == current;
              return InkWell(
                onTap: () => Navigator.pop(context, e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  color: isSel ? accent.withOpacity(0.1) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Icon(e.value.$2,
                        color: isSel ? accent : Colors.white54, size: 20),
                    const SizedBox(width: 14),
                    Expanded(child: Text(e.value.$1,
                        style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.normal))),
                    if (isSel)
                      Icon(Icons.check_rounded, color: accent, size: 18),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}
