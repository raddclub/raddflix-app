import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// A single positioned control in the drag-and-drop layout designer.
class LayoutItem {
  final String id;        // unique identifier e.g. 'play_pause', 'seek_back'
  final String label;     // display label
  final IconData icon;
  final double xFrac;     // 0.0–1.0 fraction of player width
  final double yFrac;     // 0.0–1.0 fraction of player height
  final bool   visible;
  final double sizeFrac;  // relative size scale (1.0 = default)

  const LayoutItem({
    required this.id,
    required this.label,
    required this.icon,
    this.xFrac = 0.5,
    this.yFrac = 0.5,
    this.visible = true,
    this.sizeFrac = 1.0,
  });

  LayoutItem copyWith({
    String? id, String? label, IconData? icon,
    double? xFrac, double? yFrac, bool? visible, double? sizeFrac,
  }) => LayoutItem(
    id:       id       ?? this.id,
    label:    label    ?? this.label,
    icon:     icon     ?? this.icon,
    xFrac:    xFrac    ?? this.xFrac,
    yFrac:    yFrac    ?? this.yFrac,
    visible:  visible  ?? this.visible,
    sizeFrac: sizeFrac ?? this.sizeFrac,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'xFrac': xFrac, 'yFrac': yFrac,
    'visible': visible, 'sizeFrac': sizeFrac,
  };

  static LayoutItem fromJson(Map<String, dynamic> j, LayoutItem def) => def.copyWith(
    xFrac:    (j['xFrac']    as num?)?.toDouble(),
    yFrac:    (j['yFrac']    as num?)?.toDouble(),
    visible:  j['visible']   as bool?,
    sizeFrac: (j['sizeFrac'] as num?)?.toDouble(),
  );
}

/// Default layout: positions mirroring MX Player landscape style.
const List<LayoutItem> kDefaultLayout = [
  LayoutItem(id: 'play_pause',   label: 'Play/Pause',   icon: Icons.play_arrow_rounded,      xFrac: 0.5,  yFrac: 0.5),
  LayoutItem(id: 'seek_back',    label: 'Seek Back',    icon: Icons.replay_10_rounded,        xFrac: 0.5,  yFrac: 0.32),
  LayoutItem(id: 'seek_forward', label: 'Seek Forward', icon: Icons.forward_10_rounded,       xFrac: 0.5,  yFrac: 0.68),
  LayoutItem(id: 'lock',         label: 'Lock',         icon: Icons.lock_rounded,             xFrac: 0.92, yFrac: 0.5),
  LayoutItem(id: 'settings',     label: 'Settings',     icon: Icons.settings_rounded,         xFrac: 0.08, yFrac: 0.88),
  LayoutItem(id: 'more',         label: 'More',         icon: Icons.more_horiz_rounded,       xFrac: 0.92, yFrac: 0.88),
  LayoutItem(id: 'subtitles',    label: 'Subtitles',    icon: Icons.subtitles_rounded,        xFrac: 0.92, yFrac: 0.20),
  LayoutItem(id: 'audio',        label: 'Audio',        icon: Icons.audiotrack_rounded,       xFrac: 0.92, yFrac: 0.35),
  LayoutItem(id: 'rotate',       label: 'Rotate',       icon: Icons.screen_rotation_rounded,  xFrac: 0.92, yFrac: 0.50),
  LayoutItem(id: 'pip',          label: 'PiP',          icon: Icons.picture_in_picture_rounded,xFrac: 0.08, yFrac: 0.12),
  LayoutItem(id: 'speed',        label: 'Speed',        icon: Icons.speed_rounded,            xFrac: 0.08, yFrac: 0.75),
  LayoutItem(id: 'bookmark',     label: 'Bookmark',     icon: Icons.bookmark_add_rounded,     xFrac: 0.08, yFrac: 0.60),
];

/// Persists the user's custom layout.
class LayoutPrefs {
  final List<LayoutItem> items;
  final bool useCustomLayout;
  static const _key = 'player_custom_layout_v1';

  const LayoutPrefs({
    this.items = kDefaultLayout,
    this.useCustomLayout = false,
  });

  LayoutPrefs copyWith({List<LayoutItem>? items, bool? useCustomLayout}) =>
      LayoutPrefs(
        items:           items           ?? this.items,
        useCustomLayout: useCustomLayout ?? this.useCustomLayout,
      );

  static Future<LayoutPrefs> load() async {
    final s = await SharedPreferences.getInstance();
    final raw = s.getString(_key);
    if (raw == null) return const LayoutPrefs();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedItems = (map['items'] as List<dynamic>).map((j) {
        final jm  = j as Map<String, dynamic>;
        final def = kDefaultLayout.firstWhere(
          (d) => d.id == jm['id'], orElse: () => kDefaultLayout.first);
        return LayoutItem.fromJson(jm, def);
      }).toList();
      return LayoutPrefs(
        items: savedItems,
        useCustomLayout: map['useCustomLayout'] as bool? ?? false,
      );
    } catch (_) {
      return const LayoutPrefs();
    }
  }

  Future<void> save() async {
    final s = await SharedPreferences.getInstance();
    await s.setString(_key, jsonEncode({
      'items': items.map((i) => i.toJson()).toList(),
      'useCustomLayout': useCustomLayout,
    }));
  }

  Future<void> reset() async {
    final s = await SharedPreferences.getInstance();
    await s.remove(_key);
  }
}
