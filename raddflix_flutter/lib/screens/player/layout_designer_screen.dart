/// Phase B — Drag & Drop Control Layout Designer
/// A full-screen editor where users can drag any player control tile
/// to any position on screen. Saves layout to PlayerPrefs.
library layout_designer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/layout_config.dart';
import '../../core/player/player_prefs.dart';

// ── Human-readable labels for each control ID ─────────────────────────────────
const _controlLabels = <String, String>{
  ControlId.playPause:      'Play / Pause',
  ControlId.seekBack:       'Seek Back',
  ControlId.seekForward:    'Seek Fwd',
  ControlId.lock:           'Lock',
  ControlId.pip:            'Picture-in-Picture',
  ControlId.rotate:         'Rotate',
  ControlId.subtitleToggle: 'Subtitles',
  ControlId.audioTrack:     'Audio Track',
  ControlId.settings:       'Settings',
  ControlId.speed:          'Speed',
  ControlId.more:           'More',
  ControlId.sleep:          'Sleep Timer',
  ControlId.bookmark:       'Bookmark',
  ControlId.screenshot:     'Screenshot',
  ControlId.nextEpisode:    'Next Episode',
  ControlId.skipIntro:      'Skip Intro',
};

const _controlIcons = <String, IconData>{
  ControlId.playPause:      Icons.play_arrow_rounded,
  ControlId.seekBack:       Icons.replay_10_rounded,
  ControlId.seekForward:    Icons.forward_10_rounded,
  ControlId.lock:           Icons.lock_outline_rounded,
  ControlId.pip:            Icons.picture_in_picture_alt_rounded,
  ControlId.rotate:         Icons.screen_rotation_outlined,
  ControlId.subtitleToggle: Icons.subtitles_rounded,
  ControlId.audioTrack:     Icons.audiotrack_rounded,
  ControlId.settings:       Icons.settings_rounded,
  ControlId.speed:          Icons.speed_rounded,
  ControlId.more:           Icons.more_horiz_rounded,
  ControlId.sleep:          Icons.bedtime_outlined,
  ControlId.bookmark:       Icons.bookmark_add_outlined,
  ControlId.screenshot:     Icons.camera_alt_outlined,
  ControlId.nextEpisode:    Icons.skip_next_rounded,
  ControlId.skipIntro:      Icons.fast_forward_rounded,
};

// ─────────────────────────────────────────────────────────────────────────────
class LayoutDesignerScreen extends StatefulWidget {
  final PlayerPrefs prefs;
  final void Function(PlayerPrefs updated) onSave;

  const LayoutDesignerScreen({
    super.key,
    required this.prefs,
    required this.onSave,
  });

  @override
  State<LayoutDesignerScreen> createState() => _LayoutDesignerScreenState();
}

class _LayoutDesignerScreenState extends State<LayoutDesignerScreen> {
  late List<ControlItem> _controls;
  String? _selectedId;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  void _loadLayout() {
    final preset = widget.prefs.layoutPreset;
    final json = widget.prefs.layoutJson;
    if (json.isNotEmpty) {
      try {
        _controls = PlayerLayout.fromJson(json).controls;
        return;
      } catch (_) {}
    }
    _controls = PlayerLayout.preset(preset).controls;
  }

  void _applyPreset(String presetId) {
    HapticFeedback.selectionClick();
    setState(() {
      _controls = PlayerLayout.preset(presetId).controls;
      _selectedId = null;
      _isDirty = true;
    });
  }

  void _onDragEnd(String id, Offset globalPos, Size canvasSize) {
    final x = (globalPos.dx / canvasSize.width).clamp(0.05, 0.95);
    final y = (globalPos.dy / canvasSize.height).clamp(0.05, 0.95);
    setState(() {
      _controls = _controls.map((c) {
        if (c.id == id) return c.copyWith(xFrac: x, yFrac: y);
        return c;
      }).toList();
      _isDirty = true;
    });
    HapticFeedback.lightImpact();
  }

  void _cycleSize(String id) {
    setState(() {
      _controls = _controls.map((c) {
        if (c.id != id) return c;
        final next = ControlSize.values[(c.size.index + 1) % ControlSize.values.length];
        return c.copyWith(size: next);
      }).toList();
      _isDirty = true;
    });
    HapticFeedback.selectionClick();
  }

  void _toggleVisible(String id) {
    setState(() {
      _controls = _controls.map((c) {
        if (c.id != id) return c;
        return c.copyWith(visible: !c.visible);
      }).toList();
      _isDirty = true;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _save() async {
    final layout = PlayerLayout(name: 'custom', controls: _controls);
    final updated = widget.prefs.copyWith(
      layoutJson: layout.toJson(),
      layoutPreset: 'custom',
    );
    await updated.save();
    widget.onSave(updated);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(children: [
        _buildTopBar(),
        Expanded(child: _buildCanvas()),
        _buildBottomPanel(),
      ]),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        color: Colors.black87,
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Layout Designer',
                    style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Drag tiles to reposition • Long-press to resize',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          if (_isDirty)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE8002D),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save', style: TextStyle(fontSize: 13)),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ),
        ]),
      ),
    );
  }

  // ── Drag canvas ─────────────────────────────────────────────────────────
  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Stack(children: [
        // Video background mockup
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0A0A14), Color(0xFF0D1424), Color(0xFF0A0A14)],
            ),
          ),
          child: const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.movie_creation_outlined,
                  color: Colors.white10, size: 80),
              SizedBox(height: 8),
              Text('Layout Preview',
                  style: TextStyle(color: Colors.white12, fontSize: 13)),
            ]),
          ),
        ),
        // Seek bar hint at bottom-left
        Positioned(
          left: 12, bottom: 20, top: 0,
          width: 36,
          child: Center(
            child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 50),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        // Draggable control tiles
        ..._controls.map((c) => _DraggableTile(
          key: ValueKey(c.id),
          item: c,
          canvasSize: size,
          selected: _selectedId == c.id,
          accentColor: widget.prefs.accentColor,
          onTap: () => setState(() =>
              _selectedId = _selectedId == c.id ? null : c.id),
          onLongPress: () => _cycleSize(c.id),
          onDragEnd: (pos) => _onDragEnd(c.id, pos, size),
        )),
        // Grid reference lines (faint)
        Positioned.fill(child: IgnorePointer(child: _GridOverlay())),
      ]);
    });
  }

  // ── Bottom panel: presets + selected control options ─────────────────────
  Widget _buildBottomPanel() {
    final selected = _selectedId != null
        ? _controls.firstWhere((c) => c.id == _selectedId,
            orElse: () => _controls.first)
        : null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF101018),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Preset chips
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: PlayerLayout.presetIds.map((pid) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PresetChip(
                    label: PlayerLayout.presetLabel(pid),
                    onTap: () => _applyPreset(pid),
                    accentColor: widget.prefs.accentColor,
                  ),
                );
              }).toList(),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),
            // Selected control options
            Row(children: [
              Icon(_controlIcons[selected.id] ?? Icons.circle,
                  color: widget.prefs.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                _controlLabels[selected.id] ?? selected.id,
                style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Size cycle button
              GestureDetector(
                onTap: () => _cycleSize(selected.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.open_in_full_rounded,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _sizeName(selected.size),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              // Visibility toggle
              GestureDetector(
                onTap: () => _toggleVisible(selected.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected.visible
                        ? widget.prefs.accentColor.withOpacity(0.2)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected.visible
                          ? widget.prefs.accentColor
                          : Colors.white24,
                      width: 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      selected.visible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: selected.visible
                          ? widget.prefs.accentColor : Colors.white38,
                      size: 14),
                    const SizedBox(width: 4),
                    Text(
                      selected.visible ? 'Visible' : 'Hidden',
                      style: TextStyle(
                        color: selected.visible
                            ? Colors.white : Colors.white38,
                        fontSize: 12),
                    ),
                  ]),
                ),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Tap a control to select it — drag to move — long-press to resize',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ]),
      ),
    );
  }

  static String _sizeName(ControlSize s) {
    switch (s) {
      case ControlSize.small:  return 'S';
      case ControlSize.medium: return 'M';
      case ControlSize.large:  return 'L';
    }
  }
}

// ── Draggable tile widget ─────────────────────────────────────────────────────
class _DraggableTile extends StatefulWidget {
  final ControlItem item;
  final Size canvasSize;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(Offset globalPos) onDragEnd;

  const _DraggableTile({
    super.key,
    required this.item,
    required this.canvasSize,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    required this.onLongPress,
    required this.onDragEnd,
  });

  @override
  State<_DraggableTile> createState() => _DraggableTileState();
}

class _DraggableTileState extends State<_DraggableTile> {
  bool _dragging = false;
  Offset? _dragOffset;

  double get _tileSize => 52 * widget.item.sizeMultiplier;

  @override
  Widget build(BuildContext context) {
    final x = widget.item.xFrac * widget.canvasSize.width;
    final y = widget.item.yFrac * widget.canvasSize.height;

    return Positioned(
      left: x - _tileSize / 2,
      top: y - _tileSize / 2,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) {
          if (!_dragging) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final global = box.localToGlobal(d.localPosition);
          // Find canvas ancestor position
          widget.onDragEnd(global);
        },
        onPanEnd: (_) => setState(() => _dragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: _tileSize,
          height: _tileSize,
          decoration: BoxDecoration(
            color: widget.item.visible
                ? (widget.selected
                    ? widget.accentColor.withOpacity(0.35)
                    : Colors.black.withOpacity(0.65))
                : Colors.black.withOpacity(0.28),
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.selected
                  ? widget.accentColor
                  : (widget.item.visible ? Colors.white38 : Colors.white.withOpacity(0.15)),
              width: widget.selected ? 2.0 : 1.0),
            boxShadow: _dragging
                ? [BoxShadow(
                    color: widget.accentColor.withOpacity(0.4),
                    blurRadius: 16, spreadRadius: 4)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _controlIcons[widget.item.id] ?? Icons.circle,
                color: widget.item.visible
                    ? (widget.selected ? widget.accentColor : Colors.white70)
                    : Colors.white24,
                size: _tileSize * 0.38,
              ),
              if (_tileSize > 40)
                Text(
                  (_controlLabels[widget.item.id] ?? widget.item.id)
                      .split(' ').take(1).join(),
                  style: TextStyle(
                    color: widget.item.visible ? Colors.white60 : Colors.white.withOpacity(0.20),
                    fontSize: 7,
                    fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Faint grid overlay ────────────────────────────────────────────────────────
class _GridOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int j = 1; j < 4; j++) {
      final y = size.height * j / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => false;
}

// ── Preset chip ───────────────────────────────────────────────────────────────
class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accentColor;

  const _PresetChip({
    required this.label,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.20))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.dashboard_customize_rounded,
            color: Colors.white54, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}
