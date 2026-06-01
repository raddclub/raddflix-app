import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';

/// Immersive Mode — pure video + subtitles experience.
///
/// What shows:
///   - Nothing by default — video and subtitles only.
///   - Tiny time HUD in bottom corners (start / end time), always visible.
///   - Exit icon in top-right corner: 50% opacity, hidden until tapped → shows
///     for 5 s then auto-hides again.
///   - Volume/brightness gesture: shows a minimal number-only indicator
///     briefly (no icon, no bar — just the % value), then fades out.
///
/// What does NOT show:
///   - No seek bar.
///   - No controls strip.
///   - No long-press-shows-controls behaviour (long press still triggers
///     2× speed from the parent gesture detector).
///
/// Single tap = play / pause (brief centre icon flash only).
/// Exit corner button → exits Immersive and returns to Normal mode.
class ImmersiveOverlay extends StatefulWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String Function(Duration) fmtDur;
  final VoidCallback onPlayPause;
  final VoidCallback onExit;

  const ImmersiveOverlay({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.fmtDur,
    required this.onPlayPause,
    required this.onExit,
  });

  @override
  State<ImmersiveOverlay> createState() => _ImmersiveOverlayState();
}

class _ImmersiveOverlayState extends State<ImmersiveOverlay> {
  // Brief play/pause flash icon
  bool _iconVisible = false;
  bool _iconWasPlaying = false;

  // Exit button — tapping it shows it for 5 s, then it hides again
  bool _exitVisible = false;
  Timer? _exitHideTimer;

  void _handleTap() {
    widget.onPlayPause();
    setState(() {
      _iconWasPlaying = widget.isPlaying;
      _iconVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _iconVisible = false);
    });
  }

  void _handleExitCornerTap() {
    _exitHideTimer?.cancel();
    setState(() => _exitVisible = true);
    _exitHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _exitVisible = false);
    });
  }

  @override
  void dispose() {
    _exitHideTimer?.cancel();
    super.dispose();
  }

  String get _remaining {
    final r = widget.duration - widget.position;
    return '-${widget.fmtDur(r < Duration.zero ? Duration.zero : r)}';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(children: [
        // ── Full-screen tap zone (play/pause) ──────────────────────────────
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _handleTap,
          child: const SizedBox.expand(),
        ),

        // ── Brief play/pause flash icon ────────────────────────────────────
        if (_iconVisible)
          IgnorePointer(
            child: Center(
              child: Container(
                width: 68, height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.40),
                ),
                child: Icon(
                  _iconWasPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white.withOpacity(0.88),
                  size: 36,
                ),
              )
                .animate()
                .fadeIn(duration: 80.ms)
                .then(delay: 520.ms)
                .fadeOut(duration: 300.ms),
            ),
          ),

        // ── Bottom-corner time HUD ─────────────────────────────────────────
        // Always visible — very small, unobtrusive
        Positioned(
          bottom: 10, left: 14,
          child: IgnorePointer(
            child: Text(
              widget.fmtDur(widget.position),
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 10, right: 14,
          child: IgnorePointer(
            child: Text(
              _remaining,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ),

        // ── Exit corner tap zone (top-right) ──────────────────────────────
        // Tapping this corner reveals the exit button for 5 s
        Positioned(
          top: 0, right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleExitCornerTap,
            child: const SizedBox(width: 72, height: 72),
          ),
        ),

        // ── Exit button — only visible for 5 s after corner tap ───────────
        if (_exitVisible)
          Positioned(
            top: 14, right: 14,
            child: GestureDetector(
              onTap: widget.onExit,
              child: AnimatedOpacity(
                opacity: _exitVisible ? 0.55 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fullscreen_exit_rounded,
                        color: Colors.white.withOpacity(0.75), size: 14),
                    const SizedBox(width: 5),
                    Text('Exit',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        )),
                  ]),
                ),
              ).animate().fadeIn(duration: 150.ms),
            ),
          ),
      ]),
    );
  }
}
