import 'dart:async';

/// Tracks real playback time (excludes paused periods).
/// Fires [onThreshold] once when [thresholdMinutes] of actual watch time accumulates.
class BingeGuardController {
  final int thresholdMinutes;
  final VoidCallback onThreshold;

  int _accumulatedSeconds = 0;
  Timer? _ticker;
  bool _fired = false;

  BingeGuardController({
    required this.thresholdMinutes,
    required this.onThreshold,
  });

  void onPlay() {
    _ticker?.cancel();
    if (_fired) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _accumulatedSeconds++;
      if (_accumulatedSeconds >= thresholdMinutes * 60) {
        _ticker?.cancel();
        _fired = true;
        onThreshold();
      }
    });
  }

  void onPause() {
    _ticker?.cancel();
  }

  void reset() {
    _ticker?.cancel();
    _accumulatedSeconds = 0;
    _fired = false;
  }

  int get watchedMinutes => _accumulatedSeconds ~/ 60;

  void dispose() {
    _ticker?.cancel();
  }
}

typedef VoidCallback = void Function();
