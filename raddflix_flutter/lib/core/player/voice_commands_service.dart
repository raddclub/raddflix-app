// voice_commands_service.dart — RaddFlix Voice Command Engine
// Stub implementation — real on-device STT pending AGP-8-compatible package.
// API is fully wired in player_screen.dart; swap start() body when ready.

import 'dart:async';

// ── Command enum ─────────────────────────────────────────────────────────────

enum VoiceCommand {
  play,
  pause,
  togglePlay,
  mute,
  unmute,
  screenshot,
  nextEpisode,
  prevEpisode,
  speedUp,
  speedDown,
  forward,
  back,
  unknown,
}

// ── Service ───────────────────────────────────────────────────────────────────

class VoiceCommandsService {
  VoiceCommandsService._();
  static final instance = VoiceCommandsService._();

  final _commandCtrl = StreamController<VoiceCommand>.broadcast();

  Stream<VoiceCommand> get commandStream => _commandCtrl.stream;
  bool get isListening => _listening;
  String get myId => 'local';

  bool _listening = false;

  Future<bool> requestPermission() async => true;

  Future<void> start() async {
    _listening = true;
    // TODO: wire a Flutter-3.22 / AGP-8-compatible STT package here.
    // Emit via: _commandCtrl.add(VoiceCommand.play);
  }

  void stop() => _listening = false;

  void dispose() => _commandCtrl.close();
}
