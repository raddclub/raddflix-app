/// Phase H4 — Screen Wake Lock Options
/// Allows "allow screen to sleep after N minutes of inactivity" during playback.
/// Default: always on (wakelock held). User can set an inactivity timeout.
library wake_lock_h4;

import 'dart:async';
import 'package:flutter/services.dart';

// Inactivity timeout options (minutes). 0 = always on.
const List<int> wakeLockTimeoutOptions = [0, 5, 10, 15, 20, 30];

const _wakeLockLabels = {
  0:  'Always On',
  5:  '5 min',
  10: '10 min',
  15: '15 min',
  20: '20 min',
  30: '30 min',
};

String wakeLockLabel(int mins) => _wakeLockLabels[mins] ?? '${mins}m';

// ─────────────────────────────────────────────────────────────────────────────
class WakeLockService {
  WakeLockService._();
  static final instance = WakeLockService._();

  static const _ch = MethodChannel('com.raddflix/wake_lock');

  Timer? _sleepTimer;
  int _timeoutMinutes = 0; // 0 = always on

  void configure(int timeoutMinutes) {
    _timeoutMinutes = timeoutMinutes;
    _resetTimer();
  }

  /// Call this on any user interaction (tap, seek, gesture).
  void onUserActivity() {
    if (_timeoutMinutes == 0) return;
    _resetTimer();
  }

  void _resetTimer() {
    _sleepTimer?.cancel();
    if (_timeoutMinutes == 0) {
      _acquireWakeLock();
      return;
    }
    _acquireWakeLock();
    _sleepTimer = Timer(Duration(minutes: _timeoutMinutes), () {
      _releaseWakeLock();
    });
  }

  Future<void> _acquireWakeLock() async {
    try {
      await _ch.invokeMethod('acquireWakeLock');
    } catch (_) {}
  }

  Future<void> _releaseWakeLock() async {
    try {
      await _ch.invokeMethod('releaseWakeLock');
    } catch (_) {}
  }

  void dispose() {
    _sleepTimer?.cancel();
    _releaseWakeLock();
  }
}
