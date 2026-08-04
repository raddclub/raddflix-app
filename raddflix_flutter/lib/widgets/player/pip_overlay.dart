import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase R — PiP (Picture-in-Picture) Overlay Controls
/// Floating window with drag-to-move, pinch-to-resize, corner snap.
///
/// Fixes applied:
///   PIP-J1: Scale no longer compounds — _baseSize captured at onScaleStart.
///   PIP-J2: Pan clamp respects MediaQuery.padding (status/nav bar safe-area).
///   PIP-J3: Controls auto-hide after 3 s; reset on each tap.
///   PIP-J4: Close/expand/play buttons wrapped in opaque GestureDetector so
///           tapping them does NOT also toggle the controls-visibility state.

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
  // PIP-J1: base size at scale-gesture start — prevents exponential compounding
  Size   _baseSize = const Size(200, 112);
  bool   _showControls = true;
  // PIP-J3: auto-hide timer
  Timer? _hideTimer;

  static const _minW = 140.0;
  static const _maxW = 320.0;

  @override
  void initState() {
    super.initState();
    _startHideTimer(); // PIP-J3: auto-hide on initial show
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  // PIP-J3: (re)starts a 3-second countdown to hide controls.
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _snapToCorner(Size screen) {
    const margin = 12.0;
    final padding = MediaQuery.of(context).padding;
    final cx = _position.dx + _size.width / 2;
    final cy = _position.dy + _size.height / 2;
    final left   = cx < screen.width / 2;
    final top    = cy < screen.height / 2;
    setState(() {
      _position = Offset(
        left ? margin : screen.width - _size.width - margin,
        top  ? padding.top + margin : screen.height - _size.height - padding.bottom - margin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen  = MediaQuery.of(context).size;
    // PIP-J2: read safe-area insets for clamp bounds
    final padding = MediaQuery.of(context).padding;
    return Positioned(
      left: _position.dx, top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _position = Offset(
            (_position.dx + d.delta.dx).clamp(0.0, screen.width  - _size.width),
            // PIP-J2: respect status-bar top and nav-bar bottom safe-area
            (_position.dy + d.delta.dy).clamp(padding.top, screen.height - _size.height - padding.bottom),
          );
        }),
        onPanEnd: (_) => _snapToCorner(screen),
        // PIP-J1: store base size when the pinch begins so updates stay linear
        onScaleStart: (_) { _baseSize = _size; },
        onScaleUpdate: (d) {
          setState(() {
            final newW = (_baseSize.width * d.scale).clamp(_minW, _maxW);
            _size = Size(newW, newW * 9 / 16);
          });
        },
        onTap: () {
          setState(() => _showControls = !_showControls);
          // PIP-J3: restart hide timer each time controls are revealed
          if (_showControls) _startHideTimer();
        },
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
            // Close X — PIP-J4: opaque GestureDetector absorbs tap so outer
            // onTap (controls toggle) does not also fire.
            Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: _CircleBtn(
                  icon: Icons.close_rounded, size: 22,
                  color: Colors.black.withOpacity(0.7)),
              ),
            ),
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
        // PIP-J4: opaque GestureDetectors absorb taps so they don't bubble
        // up to the outer GestureDetector's onTap (which toggles controls).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onPlayPause();
            _startHideTimer(); // PIP-J3: reset hide timer on interaction
          },
          child: _CircleBtn(
            icon: widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 28, color: widget.accentColor.withOpacity(0.85)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onExpand,
          child: _CircleBtn(
            icon: Icons.open_in_full_rounded,
            size: 22, color: Colors.black.withOpacity(0.6)),
        ),
      ]),
      const SizedBox(height: 6),
    ]),
  );
}

// _CircleBtn no longer owns its own GestureDetector — callers wrap it with
// the correct behavior instead (prevents double-firing in the PiP overlay).
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _CircleBtn({required this.icon, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size + 12, height: size + 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Icon(icon, color: Colors.white, size: size));
}
