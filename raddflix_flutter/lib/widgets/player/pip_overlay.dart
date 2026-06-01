import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase R — PiP (Picture-in-Picture) Overlay Controls
/// Floating window with drag-to-move, pinch-to-resize, corner snap.

class PiPOverlay extends StatefulWidget {
  final Widget videoWidget;
  final bool playing;
  final Color accentColor;
  final VoidCallback onPlayPause;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  const PiPOverlay({
    super.key,
    required this.videoWidget,
    required this.playing,
    required this.accentColor,
    required this.onPlayPause,
    required this.onExpand,
    required this.onClose,
  });

  @override State<PiPOverlay> createState() => _PiPOverlayState();
}

class _PiPOverlayState extends State<PiPOverlay> {
  Offset _position = const Offset(16, 100);
  Size   _size     = const Size(200, 112); // 16:9
  bool   _showControls = true;
  double _scale    = 1.0;

  static const _minW = 140.0;
  static const _maxW = 320.0;

  void _snapToCorner(Size screen) {
    const margin = 12.0;
    final cx = _position.dx + _size.width / 2;
    final cy = _position.dy + _size.height / 2;
    final left   = cx < screen.width / 2;
    final top    = cy < screen.height / 2;
    setState(() {
      _position = Offset(
        left ? margin : screen.width - _size.width - margin,
        top  ? margin + 60 : screen.height - _size.height - 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Positioned(
      left: _position.dx, top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _position = Offset(
            (_position.dx + d.delta.dx).clamp(0, screen.width  - _size.width),
            (_position.dy + d.delta.dy).clamp(0, screen.height - _size.height),
          );
        }),
        onPanEnd: (_) => _snapToCorner(screen),
        onScaleUpdate: (d) {
          setState(() {
            final newW = (_size.width * d.scale).clamp(_minW, _maxW);
            _size = Size(newW, newW * 9 / 16);
          });
        },
        onTap: () => setState(() => _showControls = !_showControls),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _size.width, height: _size.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16)],
            border: Border.all(color: widget.accentColor.withOpacity(0.4), width: 1.5)),
          clipBehavior: Clip.hardEdge,
          child: Stack(children: [
            // Video
            SizedBox.expand(child: widget.videoWidget),
            // Controls overlay
            if (_showControls) _buildControls().animate().fadeIn(duration: 200.ms),
            // Close X
            Positioned(top: 4, right: 4, child: _CircleBtn(
              icon: Icons.close_rounded, size: 22,
              color: Colors.black.withOpacity(0.7),
              onTap: widget.onClose)),
          ]),
        ),
      ),
    );
  }

  Widget _buildControls() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withOpacity(0.6)])),
    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _CircleBtn(icon: widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 28, color: widget.accentColor.withOpacity(0.85), onTap: widget.onPlayPause),
        _CircleBtn(icon: Icons.open_in_full_rounded, size: 22,
            color: Colors.black.withOpacity(0.6), onTap: widget.onExpand),
      ]),
      const SizedBox(height: 6),
    ]),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.size, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size + 12, height: size + 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: size)));
}
