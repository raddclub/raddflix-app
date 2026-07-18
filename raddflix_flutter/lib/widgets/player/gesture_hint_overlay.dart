import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase F — Gesture Hint Overlay
/// Shows animated tutorials for swipe gestures the first time.
/// Dismisses after [displayDuration] or on tap.

enum GestureHint {
  volume,      // Left side swipe up/down
  brightness,  // Right side swipe up/down
  seekScrub,   // Horizontal swipe seek
  doubleTap,   // Double-tap to seek
  pinchZoom,   // Pinch to zoom
  longPress,   // Long press = speed boost
}

class GestureHintOverlay extends StatefulWidget {
  final GestureHint hint;
  final Color accentColor;
  final Duration displayDuration;
  final VoidCallback onDismissed;

  const GestureHintOverlay({
    super.key,
    required this.hint,
    required this.accentColor,
    this.displayDuration = const Duration(seconds: 3),
    required this.onDismissed,
  });

  @override
  State<GestureHintOverlay> createState() => _GestureHintOverlayState();
}

class _GestureHintOverlayState extends State<GestureHintOverlay>
    with TickerProviderStateMixin {
  late AnimationController _swipeCtrl;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    Future.delayed(widget.displayDuration, _dismiss);
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _dismiss() async {
    if (!mounted) return;
    await _fadeCtrl.forward();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _dismiss,
    child: FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.0).animate(_fadeCtrl),
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: _HintCard(
            hint: widget.hint,
            accentColor: widget.accentColor,
            swipeAnim: _swipeCtrl,
          ),
        ),
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  final GestureHint hint;
  final Color accentColor;
  final AnimationController swipeAnim;
  const _HintCard({required this.hint, required this.accentColor, required this.swipeAnim});

  @override
  Widget build(BuildContext context) {
    final info = _hintInfo(hint);
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF352A1F).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.15), blurRadius: 24)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Animated gesture icon
        AnimatedBuilder(
          animation: swipeAnim,
          builder: (_, __) {
            final v = swipeAnim.value;
            Offset offset = Offset.zero;
            switch (info.direction) {
              case Axis.vertical:
                offset = Offset(0, -16 * v + 8);
                break;
              case Axis.horizontal:
                offset = Offset(16 * v - 8, 0);
                break;
            }
            return Transform.translate(
              offset: offset,
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withOpacity(0.5))),
                child: Icon(info.icon, color: accentColor, size: 30),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Text(info.title, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(info.subtitle, style: const TextStyle(
            color: Colors.white54, fontSize: 11, height: 1.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Tap to dismiss', style: TextStyle(
            color: accentColor.withOpacity(0.6),
            fontSize: 10, fontWeight: FontWeight.w500)),
      ]),
    )
    .animate()
    .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
           duration: 300.ms, curve: Curves.easeOutBack)
    .fadeIn(duration: 200.ms);
  }

  _HintInfo _hintInfo(GestureHint h) {
    switch (h) {
      case GestureHint.volume:
        return const _HintInfo(
          icon: Icons.volume_up_rounded,
          title: 'Volume Control',
          subtitle: 'Swipe up/down on the\nleft side',
          direction: Axis.vertical);
      case GestureHint.brightness:
        return const _HintInfo(
          icon: Icons.brightness_6_rounded,
          title: 'Brightness',
          subtitle: 'Swipe up/down on the\nright side',
          direction: Axis.vertical);
      case GestureHint.seekScrub:
        return const _HintInfo(
          icon: Icons.swap_horiz_rounded,
          title: 'Seek',
          subtitle: 'Swipe left/right\nto jump through video',
          direction: Axis.horizontal);
      case GestureHint.doubleTap:
        return const _HintInfo(
          icon: Icons.touch_app_rounded,
          title: 'Double Tap',
          subtitle: 'Double-tap left/right\nto seek ±10 seconds',
          direction: Axis.horizontal);
      case GestureHint.pinchZoom:
        return const _HintInfo(
          icon: Icons.zoom_in_rounded,
          title: 'Pinch to Zoom',
          subtitle: 'Pinch to zoom in/out\non the video',
          direction: Axis.vertical);
      case GestureHint.longPress:
        return const _HintInfo(
          icon: Icons.speed_rounded,
          title: 'Long Press Speed',
          subtitle: 'Hold the play button\nfor 2× fast forward',
          direction: Axis.vertical);
    }
  }
}

class _HintInfo {
  final IconData icon;
  final String title, subtitle;
  final Axis direction;
  const _HintInfo({required this.icon, required this.title,
      required this.subtitle, required this.direction});
}
