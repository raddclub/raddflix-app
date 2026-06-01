import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';

/// Immersive Mode overlay — subtitles stay visible, everything else hidden.
/// One tap = instant play/pause (no controls appear).
/// Long press = brief controls strip for 3 seconds.
/// Exit button (top-right corner) to leave the mode.
class ImmersiveOverlay extends StatefulWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String Function(Duration) fmtDur;
  final VoidCallback onPlayPause;
  final VoidCallback onExit;
  final ValueChanged<double> onSeekTo;
  final VoidCallback? onShowControls;
  final int controlsHideSeconds;
  final bool showTapIcon;

  const ImmersiveOverlay({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.fmtDur,
    required this.onPlayPause,
    required this.onExit,
    required this.onSeekTo,
    this.onShowControls,
    this.controlsHideSeconds = 3,
    this.showTapIcon = true,
  });

  @override
  State<ImmersiveOverlay> createState() => _ImmersiveOverlayState();
}

class _ImmersiveOverlayState extends State<ImmersiveOverlay> {
  bool _iconVisible = false;
  bool _iconIsPlaying = false;
  bool _stripVisible = false;

  void _handleTap() {
    widget.onPlayPause();
    if (widget.showTapIcon) {
      setState(() {
        _iconIsPlaying = widget.isPlaying; // icon shows what we switched FROM
        _iconVisible = true;
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _iconVisible = false);
      });
    }
  }

  void _handleLongPress() {
    setState(() => _stripVisible = true);
    widget.onShowControls?.call();
    Future.delayed(Duration(seconds: widget.controlsHideSeconds), () {
      if (mounted) setState(() => _stripVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(children: [
        // Full-screen invisible tap/long-press area
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _handleTap,
          onLongPress: _handleLongPress,
          child: Container(color: Colors.transparent),
        ),

        // Brief play/pause flash icon at center
        if (_iconVisible)
          IgnorePointer(
            child: Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.45),
                ),
                child: Icon(
                  _iconIsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white.withOpacity(0.9),
                  size: 38,
                ),
              )
                .animate()
                .fadeIn(duration: 80.ms)
                .then(delay: 550.ms)
                .fadeOut(duration: 270.ms),
            ),
          ),

        // Long-press controls strip
        if (_stripVisible)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _ImmersiveStrip(
              isPlaying: widget.isPlaying,
              position: widget.position,
              duration: widget.duration,
              fmtDur: widget.fmtDur,
              onPlayPause: widget.onPlayPause,
              onSeekTo: widget.onSeekTo,
              onDismiss: () => setState(() => _stripVisible = false),
            )
              .animate()
              .slideY(begin: 1, end: 0, duration: 200.ms, curve: Curves.easeOutCubic)
              .fadeIn(duration: 150.ms),
          ),

        // Exit button — top-right corner, small + unobtrusive
        Positioned(
          top: 16, right: 16,
          child: GestureDetector(
            onTap: widget.onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.48),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_off_rounded, color: Colors.white60, size: 13),
                SizedBox(width: 5),
                Text('Exit', style: TextStyle(
                  color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500,
                )),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ImmersiveStrip extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String Function(Duration) fmtDur;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeekTo;
  final VoidCallback onDismiss;

  const _ImmersiveStrip({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.fmtDur,
    required this.onPlayPause,
    required this.onSeekTo,
    required this.onDismiss,
  });

  double get _progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: Colors.white24,
            thumbColor: AppColors.primary,
          ),
          child: Slider(value: _progress, onChanged: onSeekTo),
        ),
        Row(children: [
          Text(fmtDur(position),
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          GestureDetector(
            onTap: onPlayPause,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDismiss,
            child: const Text('Dismiss',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ]),
      ]),
    );
  }
}
