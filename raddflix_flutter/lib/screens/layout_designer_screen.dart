import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/player/layout_prefs.dart';
import '../../core/player/player_prefs.dart';

/// Full-screen drag-and-drop layout designer.
/// Shows a 16:9 canvas; user drags control chips to reposition them.
class LayoutDesignerScreen extends StatefulWidget {
  final LayoutPrefs layoutPrefs;
  final PlayerPrefs playerPrefs;
  final ValueChanged<LayoutPrefs> onSave;

  const LayoutDesignerScreen({
    super.key,
    required this.layoutPrefs,
    required this.playerPrefs,
    required this.onSave,
  });

  @override
  State<LayoutDesignerScreen> createState() => _LayoutDesignerScreenState();
}

class _LayoutDesignerScreenState extends State<LayoutDesignerScreen> {
  late List<LayoutItem> _items;
  String? _selectedId;
  bool _showGrid      = true;
  bool _showLabels    = true;
  bool _snapToGrid    = false;
  double _gridSize    = 0.05; // 5% increments
  bool _dirty         = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.layoutPrefs.items);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _moveItem(String id, double dx, double dy, Size canvas) {
    setState(() {
      _items = _items.map((item) {
        if (item.id != id) return item;
        double nx = (item.xFrac + dx / canvas.width).clamp(0.04, 0.96);
        double ny = (item.yFrac + dy / canvas.height).clamp(0.04, 0.96);
        if (_snapToGrid) {
          nx = (nx / _gridSize).round() * _gridSize;
          ny = (ny / _gridSize).round() * _gridSize;
        }
        return item.copyWith(xFrac: nx, yFrac: ny);
      }).toList();
      _dirty = true;
    });
  }

  void _toggleVisibility(String id) {
    setState(() {
      _items = _items.map((item) =>
        item.id == id ? item.copyWith(visible: !item.visible) : item
      ).toList();
      _dirty = true;
    });
    HapticFeedback.lightImpact();
  }

  void _resizeItem(String id, double delta) {
    setState(() {
      _items = _items.map((item) {
        if (item.id != id) return item;
        final newSize = (item.sizeFrac + delta).clamp(0.5, 2.0);
        return item.copyWith(sizeFrac: newSize);
      }).toList();
      _dirty = true;
    });
  }

  void _resetLayout() {
    setState(() {
      _items = List.from(kDefaultLayout);
      _selectedId = null;
      _dirty = true;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _saveAndPop() async {
    final newPrefs = widget.layoutPrefs.copyWith(
      items: _items,
      useCustomLayout: true,
    );
    await newPrefs.save();
    widget.onSave(newPrefs);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.playerPrefs.accentColor;

    return Scaffold(
      backgroundColor: AppColors.layoutDeep,
      body: SafeArea(
        child: Column(children: [
          // ── Top toolbar ────────────────────────────────────────────────
          _buildToolbar(accent),

          // ── 16:9 canvas ────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(builder: (ctx, constraints) {
                  final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(children: [
                      // Background mockup
                      _buildMockupBg(),
                      // Grid overlay
                      if (_showGrid) _buildGrid(canvasSize, accent),
                      // Control items
                      ..._items.map((item) => _buildDraggableItem(item, canvasSize, accent)),
                    ]),
                  );
                }),
              ),
            ),
          ),

          // ── Bottom panel ───────────────────────────────────────────────
          _buildBottomPanel(accent),
        ]),
      ),
    );
  }

  Widget _buildToolbar(Color accent) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.layoutPanel,
      border: Border(bottom: BorderSide(color: Colors.white10)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: () {
          if (_dirty) {
            _showDiscardDialog();
          } else {
            Navigator.of(context).pop();
          }
        },
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.white10, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 18),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Layout Designer', style: TextStyle(color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w700)),
          Text('Drag buttons to reposition them',
              style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ),
      // Grid toggle
      _ToolbarBtn(
        icon: _showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
        label: 'Grid',
        active: _showGrid,
        accent: accent,
        onTap: () => setState(() => _showGrid = !_showGrid),
      ),
      const SizedBox(width: 6),
      // Snap toggle
      _ToolbarBtn(
        icon: Icons.push_pin_rounded,
        label: 'Snap',
        active: _snapToGrid,
        accent: accent,
        onTap: () {
          setState(() => _snapToGrid = !_snapToGrid);
          HapticFeedback.selectionClick();
        },
      ),
      const SizedBox(width: 6),
      // Labels toggle
      _ToolbarBtn(
        icon: Icons.label_rounded,
        label: 'Labels',
        active: _showLabels,
        accent: accent,
        onTap: () => setState(() => _showLabels = !_showLabels),
      ),
      const SizedBox(width: 8),
      // Reset
      GestureDetector(
        onTap: _resetLayout,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.4)),
          ),
          child: const Text('Reset', style: TextStyle(
              color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 8),
      // Save
      GestureDetector(
        onTap: _saveAndPop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _dirty ? accent : Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Save', style: TextStyle(
            color: _dirty ? Colors.white : Colors.white38,
            fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _buildMockupBg() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x88000000), Colors.transparent, Colors.transparent, Color(0x88000000)],
        stops: [0.0, 0.25, 0.75, 1.0],
      ),
    ),
    child: Center(
      child: Icon(Icons.movie_outlined,
          color: Colors.white.withOpacity(0.04), size: 80),
    ),
  );

  Widget _buildGrid(Size canvas, Color accent) => CustomPaint(
    size: canvas,
    painter: _GridPainter(gridFrac: _gridSize, color: accent.withOpacity(0.1)),
  );

  Widget _buildDraggableItem(LayoutItem item, Size canvas, Color accent) {
    final sel = _selectedId == item.id;
    final baseSize = 44.0 * item.sizeFrac;
    final x = item.xFrac * canvas.width  - baseSize / 2;
    final y = item.yFrac * canvas.height - baseSize / 2;

    return Positioned(
      left: x, top: y,
      child: GestureDetector(
        onTap: () => setState(() => _selectedId = sel ? null : item.id),
        onPanUpdate: (details) => _moveItem(item.id, details.delta.dx, details.delta.dy, canvas),
        child: Opacity(
          opacity: item.visible ? 1.0 : 0.3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: baseSize, height: baseSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sel ? accent.withOpacity(0.9) : Colors.black.withOpacity(0.55),
              border: Border.all(
                color: sel ? Colors.white : accent.withOpacity(0.5),
                width: sel ? 2 : 1),
              boxShadow: sel
                  ? [BoxShadow(color: accent.withOpacity(0.5), blurRadius: 12)]
                  : [],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(item.icon,
                  color: sel ? Colors.white : Colors.white70,
                  size: baseSize * 0.45),
              if (_showLabels && baseSize > 36) ...[
                Text(item.label,
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.white60,
                      fontSize: baseSize * 0.11,
                      fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center),
              ],
            ]),
          ).animate(target: sel ? 1 : 0)
            .scaleXY(begin: 1.0, end: 1.12, duration: 150.ms, curve: Curves.easeOut),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(Color accent) {
    final selected = _selectedId == null
        ? null
        : _items.firstWhere((i) => i.id == _selectedId,
            orElse: () => _items.first);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: selected != null ? 96 : 56,
      decoration: BoxDecoration(
        color: AppColors.layoutPanel,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: selected != null
          ? _buildItemControls(selected, accent)
          : _buildIdleFooter(),
    );
  }

  Widget _buildIdleFooter() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.touch_app_rounded, color: Colors.white38, size: 16),
      const SizedBox(width: 8),
      const Text('Tap a control to select it, then drag to move',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
    ]),
  );

  Widget _buildItemControls(LayoutItem item, Color accent) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(children: [
        // Icon label
        Icon(item.icon, color: accent, size: 20),
        const SizedBox(width: 8),
        Text(item.label, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        // Visibility toggle
        GestureDetector(
          onTap: () => _toggleVisibility(item.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: item.visible ? accent.withOpacity(0.2) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: item.visible ? accent : Colors.white24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(item.visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: item.visible ? accent : Colors.white54, size: 16),
              const SizedBox(width: 4),
              Text(item.visible ? 'Visible' : 'Hidden',
                  style: TextStyle(color: item.visible ? accent : Colors.white54,
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      // Size slider
      Row(children: [
        const Text('Size', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 8),
        Expanded(child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: accent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: accent.withOpacity(0.2),
          ),
          child: Slider(
            value: item.sizeFrac,
            min: 0.5, max: 2.0, divisions: 15,
            onChanged: (v) => _resizeItem(item.id, v - item.sizeFrac),
          ),
        )),
        SizedBox(width: 36, child: Text(
          '${(item.sizeFrac * 100).toInt()}%',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
          textAlign: TextAlign.right)),
      ]),
    ]),
  );

  Future<void> _showDiscardDialog() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.layoutSheet,
        title: const Text('Discard changes?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Your layout changes will be lost.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }
}

// ── Grid painter ──────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final double gridFrac;
  final Color color;
  const _GridPainter({required this.gridFrac, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.5;
    final cols = (1 / gridFrac).round();
    final rows = (9 / 16 / gridFrac).round();
    for (int c = 1; c < cols; c++) {
      final x = size.width * c * gridFrac;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int r = 1; r < rows; r++) {
      final y = size.height * r * gridFrac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.gridFrac != gridFrac || o.color != color;
}

// ── Toolbar button ────────────────────────────────────────────────────────────
class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.label,
      required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? accent.withOpacity(0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? accent : Color(0x33FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: active ? accent : Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          color: active ? accent : Colors.white54,
          fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
