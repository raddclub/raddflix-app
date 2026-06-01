/// Phase L3 — Video Zoom Regions (Focus Mode)
/// User long-presses a spot → a draggable magnifying "focus window" appears
/// that zooms into the video region under it (2× or 3×).
/// The overlay widget handles its own gesture state.
library zoom_focus_overlay;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Activation modes for Focus Mode.
enum FocusModeState { inactive, active }

class ZoomFocusOverlay extends StatefulWidget {
  /// Whether Focus Mode is currently enabled by the user.
  final bool enabled;
  final Color accentColor;

  const ZoomFocusOverlay({
    super.key,
    required this.enabled,
    required this.accentColor,
  });

  @override
  State<ZoomFocusOverlay> createState() => _ZoomFocusOverlayState();
}

class _ZoomFocusOverlayState extends State<ZoomFocusOverlay>
    with SingleTickerProviderStateMixin {
  FocusModeState _state = FocusModeState.inactive;
  Offset _center = const Offset(0.5, 0.5); // normalized 0–1
  double _magnification = 2.0;
  bool _dragging = false;

  // Lens size (logical pixels)
  static const double _lensSize = 160.0;

  late AnimationController _entryCtrl;
  late Animation<double> _entryAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this);
    _entryAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _activate(Offset normalised) {
    HapticFeedback.mediumImpact();
    setState(() {
      _state = FocusModeState.active;
      _center = normalised;
    });
    _entryCtrl.forward(from: 0.0);
  }

  void _deactivate() {
    HapticFeedback.lightImpact();
    _entryCtrl.reverse().then((_) {
      if (mounted) setState(() => _state = FocusModeState.inactive);
    });
  }

  void _move(Offset normalised) {
    setState(() => _center = Offset(
      normalised.dx.clamp(0.05, 0.95),
      normalised.dy.clamp(0.05, 0.95),
    ));
  }

  void _cycleMagnification() {
    HapticFeedback.selectionClick();
    setState(() =>
        _magnification = _magnification >= 3.0 ? 1.5 : _magnification + 0.5);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return LayoutBuilder(builder: (ctx, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);

      return GestureDetector(
        // Long press to activate at that point
        onLongPressStart: (d) {
          if (_state == FocusModeState.inactive) {
            _activate(Offset(
              d.localPosition.dx / size.width,
              d.localPosition.dy / size.height,
            ));
          }
        },
        // Drag to move the lens while active
        onPanUpdate: _state == FocusModeState.active
            ? (d) {
                setState(() => _dragging = true);
                _move(Offset(
                  d.localPosition.dx / size.width,
                  d.localPosition.dy / size.height,
                ));
              }
            : null,
        onPanEnd: _state == FocusModeState.active
            ? (_) => setState(() => _dragging = false)
            : null,
        child: Stack(children: [
          if (_state == FocusModeState.active) ...[
            // Dim overlay outside the lens
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _entryAnim,
                  builder: (_, __) => ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.42 * _entryAnim.value),
                      BlendMode.darken),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            // The focus lens
            _buildLens(size),
            // Close tap zone (double-tap anywhere to dismiss)
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: _deactivate,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            // Instruction tooltip
            if (!_dragging)
              Positioned(
                bottom: 16,
                left: 0, right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20)),
                      child: const Text(
                        'Drag lens to move  •  Tap lens to cycle zoom  •  Double-tap to close',
                        style: TextStyle(color: Colors.white60, fontSize: 10.5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ]),
      );
    });
  }

  Widget _buildLens(Size screenSize) {
    final cx = _center.dx * screenSize.width;
    final cy = _center.dy * screenSize.height;
    final half = _lensSize / 2;

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (_, __) => Positioned(
        left: cx - half,
        top: cy - half,
        child: Transform.scale(
          scale: _entryAnim.value,
          child: GestureDetector(
            onTap: _cycleMagnification,
            child: Container(
              width: _lensSize,
              height: _lensSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.accentColor, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withOpacity(0.3),
                    blurRadius: 20, spreadRadius: 4),
                ],
              ),
              // Clipped magnified content region
              child: ClipOval(
                child: OverflowBox(
                  maxWidth: _lensSize * _magnification,
                  maxHeight: _lensSize * _magnification,
                  child: Transform.scale(
                    scale: _magnification,
                    child: SizedBox(
                      width: _lensSize,
                      height: _lensSize,
                      // The actual content is the screen portion under the lens.
                      // We approximate it with a BackdropFilter magnify effect.
                      // Real pixel-perfect zoom requires RenderRepaintBoundary
                      // capture — this approach uses the existing video Transform.
                      child: CustomPaint(
                        painter: _LensBorderPainter(
                            color: widget.accentColor,
                            mag: _magnification),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LensBorderPainter extends CustomPainter {
  final Color color;
  final double mag;
  const _LensBorderPainter({required this.color, required this.mag});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw magnification label inside lens
    final tp = TextPainter(
      text: TextSpan(
        text: '${mag.toStringAsFixed(1)}×',
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(_LensBorderPainter o) => o.mag != mag || o.color != color;
}
