/// Phase V — Advanced Video Tools
/// V1 — Picture-in-Picture (PiP) Manager
/// V2 — Background Audio Mode (audio-only with lock-screen controls)
/// V3 — Loop Section A-B (loop between two set points)
/// V4 — Variable Frame Rate Detection & Display
library v_series;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// V1 — PiP Manager
// ─────────────────────────────────────────────────────────────────────────────

class PipManager {
  PipManager._();
  static final instance = PipManager._();

  static const _channel = MethodChannel('raddflix/pip');

  bool _inPip = false;
  bool get isInPip => _inPip;

  final _ctrl = StreamController<bool>.broadcast();
  Stream<bool> get pipState => _ctrl.stream;

  Future<void> enterPip() async {
    try {
      await _channel.invokeMethod('enterPip');
      _inPip = true;
      _ctrl.add(true);
    } catch (_) {
      // PiP not supported on this device/platform
    }
  }

  Future<void> exitPip() async {
    try {
      await _channel.invokeMethod('exitPip');
      _inPip = false;
      _ctrl.add(false);
    } catch (_) {}
  }

  void dispose() => _ctrl.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 — Background Audio Mode
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundAudioService {
  BackgroundAudioService._();
  static final instance = BackgroundAudioService._();

  static const _channel = MethodChannel('raddflix/background_audio');

  bool _enabled = false;
  bool get isEnabled => _enabled;

  Future<void> enable({
    required String title,
    required String artist,
    required String? artworkUrl,
  }) async {
    try {
      await _channel.invokeMethod('enable', {
        'title': title, 'artist': artist, 'artworkUrl': artworkUrl ?? ''});
      _enabled = true;
    } catch (_) {}
  }

  Future<void> disable() async {
    try {
      await _channel.invokeMethod('disable');
      _enabled = false;
    } catch (_) {}
  }

  Future<void> updatePosition(Duration pos, Duration dur) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('updatePosition', {
        'posMs': pos.inMilliseconds, 'durMs': dur.inMilliseconds});
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// V3 — Loop A-B Section
// ─────────────────────────────────────────────────────────────────────────────

class LoopABController extends ChangeNotifier {
  Duration? _pointA;
  Duration? _pointB;
  bool _active = false;

  Duration? get pointA => _pointA;
  Duration? get pointB => _pointB;
  bool get active => _active && _pointA != null && _pointB != null;

  void setA(Duration pos) {
    _pointA = pos;
    if (_pointB != null && _pointB! <= _pointA!) _pointB = null;
    notifyListeners();
  }

  void setB(Duration pos) {
    if (_pointA == null || pos <= _pointA!) return;
    _pointB = pos;
    _active = true;
    notifyListeners();
  }

  void toggle() {
    _active = !_active;
    notifyListeners();
  }

  void clear() {
    _pointA = null; _pointB = null; _active = false;
    notifyListeners();
  }

  /// Returns true when [pos] has passed B — caller should seek back to A.
  bool shouldLoop(Duration pos) {
    if (!active) return false;
    return pos >= _pointB!;
  }

  String get label {
    if (_pointA == null) return 'Set A';
    if (_pointB == null) return 'Set B';
    return 'A ${_fmtMs(_pointA!)} → B ${_fmtMs(_pointB!)}';
  }

  static String _fmtMs(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class LoopABHud extends StatelessWidget {
  final LoopABController ctrl;
  final Duration position;
  final Color accentColor;
  final VoidCallback onSetA;
  final VoidCallback onSetB;

  const LoopABHud({
    super.key,
    required this.ctrl,
    required this.position,
    required this.accentColor,
    required this.onSetA,
    required this.onSetB,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ctrl.active ? accentColor : Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.loop_rounded,
            color: ctrl.active ? accentColor : Colors.white54, size: 16),
        const SizedBox(width: 8),
        Text(ctrl.label, style: const TextStyle(color: Colors.white,
            fontSize: 11.5, fontWeight: FontWeight.w500)),
        const SizedBox(width: 10),
        GestureDetector(onTap: onSetA,
            child: _pill('A', ctrl.pointA != null, accentColor)),
        const SizedBox(width: 6),
        GestureDetector(onTap: onSetB,
            child: _pill('B', ctrl.pointB != null, accentColor)),
        if (ctrl.pointA != null) ...[
          const SizedBox(width: 6),
          GestureDetector(onTap: ctrl.clear,
              child: const Icon(Icons.close_rounded,
                  color: Colors.white38, size: 14)),
        ],
      ]),
    );
  }

  Widget _pill(String label, bool set, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: set ? accent.withOpacity(0.25) : Colors.white10,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: set ? accent : Colors.white30)),
    child: Text(label, style: TextStyle(
        color: set ? accent : Colors.white54,
        fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 — Background Audio Mode Banner (visible when audio-only is on)
// ─────────────────────────────────────────────────────────────────────────────
class AudioOnlyBanner extends StatelessWidget {
  final String title;
  final String episode;
  final Color accentColor;
  final VoidCallback onExitAudioMode;

  const AudioOnlyBanner({
    super.key,
    required this.title,
    required this.episode,
    required this.accentColor,
    required this.onExitAudioMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.headphones_rounded, color: accentColor, size: 64),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white,
              fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(episode, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          const Text('Audio Only Mode — Screen Saver Active',
              style: TextStyle(color: Colors.white30, fontSize: 12)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onExitAudioMode,
            icon: Icon(Icons.videocam_rounded, color: accentColor, size: 18),
            label: Text('Show Video', style: TextStyle(color: accentColor, fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}
