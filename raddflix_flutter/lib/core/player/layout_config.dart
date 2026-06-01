/// Phase B — Drag & Drop Control Layout System
/// Every control in the player can be repositioned to any screen location.
library layout_config;

import 'dart:convert';

// ── Control IDs (all draggable tiles in the player) ───────────────────────────
class ControlId {
  static const playPause     = 'play_pause';
  static const seekBack      = 'seek_back';
  static const seekForward   = 'seek_forward';
  static const lock          = 'lock';
  static const pip           = 'pip';
  static const rotate        = 'rotate';
  static const subtitleToggle = 'subtitle_toggle';
  static const audioTrack    = 'audio_track';
  static const settings      = 'settings';
  static const speed         = 'speed';
  static const more          = 'more';
  static const sleep         = 'sleep';
  static const bookmark      = 'bookmark';
  static const screenshot    = 'screenshot';
  static const nextEpisode   = 'next_episode';
  static const skipIntro     = 'skip_intro';

  static const all = [
    playPause, seekBack, seekForward, lock, pip, rotate,
    subtitleToggle, audioTrack, settings, speed, more,
    sleep, bookmark, screenshot, nextEpisode, skipIntro,
  ];
}

// ── Control size presets ───────────────────────────────────────────────────────
enum ControlSize { small, medium, large }

// ── Single control item in the layout ─────────────────────────────────────────
class ControlItem {
  final String id;
  final double xFrac;     // 0.0–1.0 horizontal position (centre of control)
  final double yFrac;     // 0.0–1.0 vertical position (centre of control)
  final ControlSize size;
  final bool visible;

  const ControlItem({
    required this.id,
    required this.xFrac,
    required this.yFrac,
    this.size = ControlSize.medium,
    this.visible = true,
  });

  ControlItem copyWith({
    String? id,
    double? xFrac,
    double? yFrac,
    ControlSize? size,
    bool? visible,
  }) => ControlItem(
    id: id ?? this.id,
    xFrac: xFrac ?? this.xFrac,
    yFrac: yFrac ?? this.yFrac,
    size: size ?? this.size,
    visible: visible ?? this.visible,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': xFrac,
    'y': yFrac,
    'size': size.name,
    'visible': visible,
  };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
    id: j['id'] as String,
    xFrac: (j['x'] as num).toDouble(),
    yFrac: (j['y'] as num).toDouble(),
    size: ControlSize.values.firstWhere(
      (s) => s.name == j['size'], orElse: () => ControlSize.medium),
    visible: (j['visible'] as bool?) ?? true,
  );

  double get sizeMultiplier {
    switch (size) {
      case ControlSize.small:  return 0.7;
      case ControlSize.large:  return 1.35;
      case ControlSize.medium: return 1.0;
    }
  }
}

// ── Full layout: list of control items + a name ───────────────────────────────
class PlayerLayout {
  final String name;
  final List<ControlItem> controls;

  const PlayerLayout({required this.name, required this.controls});

  String toJson() => jsonEncode({
    'name': name,
    'controls': controls.map((c) => c.toJson()).toList(),
  });

  factory PlayerLayout.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final list = (m['controls'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ControlItem.fromJson)
        .toList();
    return PlayerLayout(name: m['name'] as String, controls: list);
  }

  factory PlayerLayout.preset(String presetId) =>
      _presets[presetId] ?? _presets['centered']!;

  // ── Built-in layout presets ───────────────────────────────────────────────
  static const _centeredLayout = [
    ControlItem(id: ControlId.seekBack,      xFrac: 0.30, yFrac: 0.50, size: ControlSize.medium),
    ControlItem(id: ControlId.playPause,     xFrac: 0.50, yFrac: 0.50, size: ControlSize.large),
    ControlItem(id: ControlId.seekForward,   xFrac: 0.70, yFrac: 0.50, size: ControlSize.medium),
    ControlItem(id: ControlId.subtitleToggle,xFrac: 0.87, yFrac: 0.25, size: ControlSize.small),
    ControlItem(id: ControlId.audioTrack,    xFrac: 0.87, yFrac: 0.40, size: ControlSize.small),
    ControlItem(id: ControlId.rotate,        xFrac: 0.87, yFrac: 0.55, size: ControlSize.small),
    ControlItem(id: ControlId.more,          xFrac: 0.87, yFrac: 0.70, size: ControlSize.small),
    ControlItem(id: ControlId.lock,          xFrac: 0.13, yFrac: 0.15, size: ControlSize.small),
    ControlItem(id: ControlId.pip,           xFrac: 0.87, yFrac: 0.15, size: ControlSize.small),
    ControlItem(id: ControlId.sleep,         xFrac: 0.13, yFrac: 0.85, size: ControlSize.small),
    ControlItem(id: ControlId.bookmark,      xFrac: 0.50, yFrac: 0.80, size: ControlSize.small),
    ControlItem(id: ControlId.screenshot,    xFrac: 0.87, yFrac: 0.85, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.nextEpisode,   xFrac: 0.70, yFrac: 0.70, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.skipIntro,     xFrac: 0.70, yFrac: 0.80, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.settings,      xFrac: 0.13, yFrac: 0.50, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.speed,         xFrac: 0.13, yFrac: 0.65, size: ControlSize.small, visible: false),
  ];

  static const _leftHandedLayout = [
    ControlItem(id: ControlId.playPause,     xFrac: 0.20, yFrac: 0.50, size: ControlSize.large),
    ControlItem(id: ControlId.seekBack,      xFrac: 0.20, yFrac: 0.30, size: ControlSize.medium),
    ControlItem(id: ControlId.seekForward,   xFrac: 0.20, yFrac: 0.70, size: ControlSize.medium),
    ControlItem(id: ControlId.subtitleToggle,xFrac: 0.10, yFrac: 0.25, size: ControlSize.small),
    ControlItem(id: ControlId.audioTrack,    xFrac: 0.10, yFrac: 0.40, size: ControlSize.small),
    ControlItem(id: ControlId.rotate,        xFrac: 0.10, yFrac: 0.55, size: ControlSize.small),
    ControlItem(id: ControlId.more,          xFrac: 0.10, yFrac: 0.70, size: ControlSize.small),
    ControlItem(id: ControlId.lock,          xFrac: 0.10, yFrac: 0.15, size: ControlSize.small),
    ControlItem(id: ControlId.pip,           xFrac: 0.10, yFrac: 0.85, size: ControlSize.small),
    ControlItem(id: ControlId.sleep,         xFrac: 0.30, yFrac: 0.85, size: ControlSize.small),
    ControlItem(id: ControlId.bookmark,      xFrac: 0.30, yFrac: 0.15, size: ControlSize.small),
    ControlItem(id: ControlId.screenshot,    xFrac: 0.90, yFrac: 0.85, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.nextEpisode,   xFrac: 0.90, yFrac: 0.50, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.skipIntro,     xFrac: 0.90, yFrac: 0.65, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.settings,      xFrac: 0.90, yFrac: 0.15, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.speed,         xFrac: 0.90, yFrac: 0.30, size: ControlSize.small, visible: false),
  ];

  static const _minimalLayout = [
    ControlItem(id: ControlId.seekBack,      xFrac: 0.38, yFrac: 0.50, size: ControlSize.small),
    ControlItem(id: ControlId.playPause,     xFrac: 0.50, yFrac: 0.50, size: ControlSize.large),
    ControlItem(id: ControlId.seekForward,   xFrac: 0.62, yFrac: 0.50, size: ControlSize.small),
    ControlItem(id: ControlId.lock,          xFrac: 0.05, yFrac: 0.10, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.pip,           xFrac: 0.95, yFrac: 0.10, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.subtitleToggle,xFrac: 0.87, yFrac: 0.25, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.audioTrack,    xFrac: 0.87, yFrac: 0.40, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.rotate,        xFrac: 0.87, yFrac: 0.55, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.more,          xFrac: 0.87, yFrac: 0.70, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.sleep,         xFrac: 0.13, yFrac: 0.85, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.bookmark,      xFrac: 0.50, yFrac: 0.80, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.screenshot,    xFrac: 0.87, yFrac: 0.85, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.nextEpisode,   xFrac: 0.70, yFrac: 0.70, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.skipIntro,     xFrac: 0.70, yFrac: 0.80, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.settings,      xFrac: 0.13, yFrac: 0.50, size: ControlSize.small, visible: false),
    ControlItem(id: ControlId.speed,         xFrac: 0.13, yFrac: 0.65, size: ControlSize.small, visible: false),
  ];

  static final Map<String, PlayerLayout> _presets = {
    'centered':    const PlayerLayout(name: 'Centered',    controls: _centeredLayout),
    'left_handed': const PlayerLayout(name: 'Left Handed', controls: _leftHandedLayout),
    'right_handed': PlayerLayout(name: 'Right Handed',
      controls: _leftHandedLayout.map((c) => c.copyWith(xFrac: 1.0 - c.xFrac)).toList()),
    'minimal':     const PlayerLayout(name: 'Minimal',     controls: _minimalLayout),
  };

  static const presetIds = ['centered', 'left_handed', 'right_handed', 'minimal'];

  static String presetLabel(String id) {
    switch (id) {
      case 'centered':    return 'Centered';
      case 'left_handed': return 'Left Handed';
      case 'right_handed':return 'Right Handed';
      case 'minimal':     return 'Minimal';
      default:            return 'Custom';
    }
  }
}
