import 'dart:async';

/// Tracks real playback time (excludes paused periods).
/// Fires [onThreshold] once when [thresholdMinutes] of actual watch time accumulates.
class BingeGuardController {
  final int thresholdMinutes;
  final VoidCallback onThreshold;

  int _accumulatedSeconds = 0;
  Timer? _ticker;
  bool _fired = false;
  // L-05 FIX: track disposed state so onPlay() cannot restart a leaked timer
  // after the controller has been disposed.
  bool _isDisposed = false;

  BingeGuardController({
    required this.thresholdMinutes,
    required this.onThreshold,
  });

  void onPlay() {
    // L-05 FIX: guard against timer restart after dispose()
    if (_isDisposed || _fired) return;
    _ticker?.cancel();
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
    _isDisposed = true;
    _ticker?.cancel();
  }
}

typedef VoidCallback = void Function();
