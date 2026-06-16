/// Phase J1 — Voice Commands
/// "Hey RaddFlix, skip 2 minutes" / "louder" / "subtitles off" / "speed 1.5"
/// Uses Android SpeechRecognizer via platform channel (on-device, no internet).
library voice_commands;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Recognised intent types ───────────────────────────────────────────────────
enum VoiceIntent {
  skip,          // "skip 2 minutes" / "skip forward 30 seconds"
  seekBack,      // "go back 1 minute"
  seekTo,        // "go to 45 minutes"
  speedSet,      // "speed 1.5" / "play faster" / "play slower"
  volumeUp,      // "louder" / "volume up"
  volumeDown,    // "quieter" / "volume down"
  subtitleOn,    // "subtitles on" / "show subtitles"
  subtitleOff,   // "subtitles off" / "hide subtitles"
  playPause,     // "play" / "pause" / "stop"
  unknown,
}

class VoiceCommand {
  final VoiceIntent intent;
  final double? value;    // for skip (seconds), speed, volume delta
  final String raw;

  const VoiceCommand({required this.intent, this.value, required this.raw});
}

// ─────────────────────────────────────────────────────────────────────────────
/// Platform channel bridge for Android SpeechRecognizer.
/// Call [listen] to start one-shot recognition, [stopListening] to abort.
class VoiceCommandService {
  VoiceCommandService._();
  static final instance = VoiceCommandService._();

  static const _ch = MethodChannel('com.raddflix/voice_commands');
  static const _events = EventChannel('com.raddflix/voice_commands_events');

  StreamSubscription<dynamic>? _sub;
  final _resultCtrl = StreamController<VoiceCommand>.broadcast();

  Stream<VoiceCommand> get results => _resultCtrl.stream;
  bool _listening = false;
  bool get isListening => _listening;

  Future<void> startListening() async {
    if (_listening) return;
    try {
      await _ch.invokeMethod('startListening');
      _listening = true;
      _sub = _events.receiveBroadcastStream().listen((data) {
        if (data is String) {
          _resultCtrl.add(_parse(data));
        }
      }, onDone: () => _listening = false);
    } catch (e) {
      _listening = false;
      // Voice recognition unavailable (iOS, emulator, no microphone)
    }
  }

  Future<void> stopListening() async {
    _sub?.cancel();
    _sub = null;
    _listening = false;
    try {
      await _ch.invokeMethod('stopListening');
    } catch (_) {}
  }

  void dispose() {
    stopListening();
    _resultCtrl.close();
  }

  // ── Command parser ──────────────────────────────────────────────────────────
  VoiceCommand _parse(String raw) {
    final text = raw.toLowerCase().trim();

    // Skip forward
    final skipFwd = RegExp(r'skip\s*(forward)?\s*(\d+)\s*(minute|min|second|sec)s?');
    final mFwd = skipFwd.firstMatch(text);
    if (mFwd != null) {
      final n = double.tryParse(mFwd.group(2)!) ?? 0;
      final unit = mFwd.group(3)!;
      final secs = unit.startsWith('min') ? n * 60 : n;
      return VoiceCommand(intent: VoiceIntent.skip, value: secs, raw: raw);
    }

    // Go back
    final goBack = RegExp(r'(go\s*back|rewind)\s*(\d+)\s*(minute|min|second|sec)s?');
    final mBack = goBack.firstMatch(text);
    if (mBack != null) {
      final n = double.tryParse(mBack.group(2)!) ?? 0;
      final unit = mBack.group(3)!;
      final secs = unit.startsWith('min') ? n * 60 : n;
      return VoiceCommand(intent: VoiceIntent.seekBack, value: secs, raw: raw);
    }

    // Speed
    final speedMatch = RegExp(r'(speed|play\s*at)\s*([\d.]+)').firstMatch(text);
    if (speedMatch != null) {
      return VoiceCommand(intent: VoiceIntent.speedSet,
          value: double.tryParse(speedMatch.group(2)!) ?? 1.0, raw: raw);
    }
    if (text.contains('faster') || text.contains('speed up')) {
      return VoiceCommand(intent: VoiceIntent.speedSet, value: -1, raw: raw); // -1 = increment
    }
    if (text.contains('slower') || text.contains('slow down')) {
      return VoiceCommand(intent: VoiceIntent.speedSet, value: -2, raw: raw); // -2 = decrement
    }

    // Volume
    if (text.contains('louder') || text.contains('volume up')) {
      return VoiceCommand(intent: VoiceIntent.volumeUp, raw: raw);
    }
    if (text.contains('quieter') || text.contains('volume down')) {
      return VoiceCommand(intent: VoiceIntent.volumeDown, raw: raw);
    }

    // Subtitles
    if (text.contains('subtitle') || text.contains('caption')) {
      final off = text.contains('off') || text.contains('hide') || text.contains('disable');
      return VoiceCommand(
          intent: off ? VoiceIntent.subtitleOff : VoiceIntent.subtitleOn, raw: raw);
    }

    // Play/Pause
    if (text.contains('pause') || text.contains('stop')) {
      return VoiceCommand(intent: VoiceIntent.playPause, raw: raw);
    }
    if (text == 'play' || text.contains('resume') || text.contains('continue')) {
      return VoiceCommand(intent: VoiceIntent.playPause, raw: raw);
    }

    return VoiceCommand(intent: VoiceIntent.unknown, raw: raw);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Mic button that sits in the player controls area when voice commands enabled.
/// Tap to start/stop listening. Shows animated ring while listening.
class VoiceCommandButton extends StatefulWidget {
  final Color accentColor;
  final ValueChanged<VoiceCommand> onCommand;

  const VoiceCommandButton({
    super.key,
    required this.accentColor,
    required this.onCommand,
  });

  @override
  State<VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<VoiceCommandButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  StreamSubscription<VoiceCommand>? _sub;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this)
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.15)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.stop();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final svc = VoiceCommandService.instance;
    if (svc.isListening) {
      await svc.stopListening();
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    } else {
      _sub = svc.results.listen((cmd) {
        widget.onCommand(cmd);
        svc.stopListening();
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        if (mounted) setState(() {});
        _showToast(cmd);
      });
      await svc.startListening();
      _pulseCtrl.repeat(reverse: true);
    }
    if (mounted) setState(() {});
  }

  void _showToast(VoiceCommand cmd) {
    // In production, show SnackBar or custom toast. Left for player to handle.
  }

  @override
  Widget build(BuildContext context) {
    final listening = VoiceCommandService.instance.isListening;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: listening ? _pulse.value : 1.0,
        child: child,
      ),
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening
                ? widget.accentColor.withOpacity(0.25)
                : Colors.white.withOpacity(0.12),
            border: Border.all(
              color: listening ? widget.accentColor : Colors.white30,
              width: 1.5,
            ),
          ),
          child: Icon(
            listening ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: listening ? widget.accentColor : Colors.white60,
            size: 20,
          ),
        ),
      ),
    );
  }
}
