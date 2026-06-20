// voice_commands_service.dart — RaddFlix Voice Command Engine
// Supports English + Urdu-English mix commands (Pakistani users)
// Uses speech_to_text package for on-device STT

import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

// ── Command types ─────────────────────────────────────────────────────────────

abstract class VoiceCommand {}

class VoiceCommandPlay extends VoiceCommand {}
class VoiceCommandPause extends VoiceCommand {}
class VoiceCommandTogglePlay extends VoiceCommand {}
class VoiceCommandMute extends VoiceCommand {}
class VoiceCommandUnmute extends VoiceCommand {}
class VoiceCommandScreenshot extends VoiceCommand {}
class VoiceCommandNextEpisode extends VoiceCommand {}
class VoiceCommandPrevEpisode extends VoiceCommand {}
class VoiceCommandSpeedUp extends VoiceCommand {}
class VoiceCommandSpeedDown extends VoiceCommand {}
class VoiceCommandUnknown extends VoiceCommand {}

class VoiceCommandForward extends VoiceCommand {
  final int seconds;
  VoiceCommandForward(this.seconds);
}

class VoiceCommandBack extends VoiceCommand {
  final int seconds;
  VoiceCommandBack(this.seconds);
}

class VoiceCommandSetSpeed extends VoiceCommand {
  final double speed;
  VoiceCommandSetSpeed(this.speed);
}

// ── Service ───────────────────────────────────────────────────────────────────

class VoiceCommandsService {
  VoiceCommandsService._();
  static final instance = VoiceCommandsService._();

  final _speech = SpeechToText();
  final _commandCtrl = StreamController<VoiceCommand>.broadcast();

  bool _initialized = false;
  bool _listening = false;
  String? _myId;

  Stream<VoiceCommand> get commandStream => _commandCtrl.stream;
  bool get isListening => _listening;
  String? get myId => _myId;

  // ── Init & permission ────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (e) {},
      onStatus: (status) {
        if (status == 'done' && _listening) {
          // Auto-restart continuous listening
          _startListening();
        }
      },
    );
    return _initialized;
  }

  // ── Start / stop ─────────────────────────────────────────────────────────

  Future<void> start() async {
    if (!_initialized) {
      _initialized = await _speech.initialize(onError: (_) {}, onStatus: (s) {
        if (s == 'done' && _listening) _startListening();
      });
    }
    if (!_initialized) return;
    _listening = true;
    _startListening();
  }

  void _startListening() {
    if (!_listening || !_initialized) return;
    _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
      cancelOnError: false,
      partialResults: false,
    );
  }

  void stop() {
    _listening = false;
    _speech.stop();
  }

  // ── Result parser ─────────────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    final text = result.recognizedWords.toLowerCase().trim();
    if (text.isEmpty) return;
    final cmd = _parse(text);
    if (cmd != null) _commandCtrl.add(cmd);
  }

  VoiceCommand? _parse(String text) {
    // ── Play / Pause ───────────────────────────────────────────────────────
    if (_matches(text, ['play', 'resume', 'chalao', 'chala', 'start'])) {
      return VoiceCommandPlay();
    }
    if (_matches(text, ['pause', 'stop', 'rok', 'ruk', 'band karo'])) {
      return VoiceCommandPause();
    }

    // ── Mute ──────────────────────────────────────────────────────────────
    if (_matches(text, ['mute', 'silent', 'khamosh', 'quiet'])) {
      return VoiceCommandMute();
    }
    if (_matches(text, ['unmute', 'sound on', 'awaz on', 'volume on'])) {
      return VoiceCommandUnmute();
    }

    // ── Screenshot ────────────────────────────────────────────────────────
    if (_matches(text, ['screenshot', 'capture', 'snap', 'photo le'])) {
      return VoiceCommandScreenshot();
    }

    // ── Navigation ────────────────────────────────────────────────────────
    if (_matches(text, ['next episode', 'next', 'agla', 'agli', 'skip episode'])) {
      return VoiceCommandNextEpisode();
    }
    if (_matches(text, ['previous episode', 'previous', 'pichla', 'back episode'])) {
      return VoiceCommandPrevEpisode();
    }

    // ── Speed ─────────────────────────────────────────────────────────────
    if (_matches(text, ['faster', 'speed up', 'tez karo', 'jaldi'])) {
      return VoiceCommandSpeedUp();
    }
    if (_matches(text, ['slower', 'slow down', 'slow', 'dheeray'])) {
      return VoiceCommandSpeedDown();
    }

    // ── Speed: "speed 1.5" / "speed 2" ────────────────────────────────────
    final speedMatch = RegExp(r'\bspeed\s+([\d.]+)\b').firstMatch(text);
    if (speedMatch != null) {
      final s = double.tryParse(speedMatch.group(1)!);
      if (s != null && s >= 0.25 && s <= 3.0) return VoiceCommandSetSpeed(s);
    }

    // ── Forward: "forward 30" / "aage 10" ─────────────────────────────────
    final fwdMatch = RegExp(r'\b(?:forward|skip|aage|agay)\s+(\d+)\b').firstMatch(text);
    if (fwdMatch != null) {
      final s = int.tryParse(fwdMatch.group(1)!);
      if (s != null && s > 0 && s <= 300) return VoiceCommandForward(s);
    }
    // Default: "forward" without number = 30s
    if (_matches(text, ['forward', 'aage', 'agay'])) return VoiceCommandForward(30);

    // ── Back: "back 10" / "peeche 30" ─────────────────────────────────────
    final backMatch = RegExp(r'\b(?:back|rewind|peeche|peechay)\s+(\d+)\b').firstMatch(text);
    if (backMatch != null) {
      final s = int.tryParse(backMatch.group(1)!);
      if (s != null && s > 0 && s <= 300) return VoiceCommandBack(s);
    }
    // Default: "back" without number = 10s
    if (_matches(text, ['back', 'rewind', 'peeche', 'peechay'])) return VoiceCommandBack(10);

    return null; // unknown command — silently ignore
  }

  bool _matches(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }

  void dispose() {
    _commandCtrl.close();
    _speech.stop();
  }
}
