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
  vibeNext,          // cycle forward through vibe modes (none → slowed → … → club → none)
  vibeOff,           // immediately reset to PlaybackVibeMode.none
  // VIBE-5D: direct mode-by-name commands ─────────────────────────────────
  vibeSlowed,        // "slowed"
  vibeSlowedReverb,  // "slowed reverb" | "reverb"
  vibeNightcore,     // "nightcore" | "night core"
  vibeLofi,          // "lofi" | "lo-fi"
  vibeNone,          // "normal" | "original" | "no vibe"
  unknown,
}

// ── Service ───────────────────────────────────────────────────────────────────

class VoiceCommandsService {
  VoiceCommandsService._();
  static final instance = VoiceCommandsService._();

  final _commandCtrl = StreamController<VoiceCommand>.broadcast();

  // VIBE-5D direct voice phrases. Keep these exact phrases explicit so the
  // spec's five required mappings cannot get lost among the optional aliases.
  static const _directVibePhraseMappings = <String, VoiceCommand>{
    'slowed': VoiceCommand.vibeSlowed,
    'nightcore': VoiceCommand.vibeNightcore,
    'lofi': VoiceCommand.vibeLofi,
    'reverb': VoiceCommand.vibeSlowedReverb,
    'no vibe': VoiceCommand.vibeNone,
  };

  Stream<VoiceCommand> get commandStream => _commandCtrl.stream;
  bool get isListening => _listening;
  String get myId => 'local';

  bool _listening = false;

  /// Returns false — this is a stub pending a Flutter-3.22 / AGP-8-compatible
  /// STT package. No microphone permission dialog is shown until the real
  /// implementation replaces this stub.
  Future<bool> requestPermission() async => false;

  Future<void> start() async {
    _listening = true;
    // TODO: wire a Flutter-3.22 / AGP-8-compatible STT package here.
    // When ready, recognise text and emit: _commandCtrl.add(parse(recognisedText));
  }

  void stop() => _listening = false;

  void dispose() => _commandCtrl.close();

  // ── Phrase parser ─────────────────────────────────────────────────────────
  // Called by the STT implementation to convert raw recognised text into a
  // VoiceCommand.  All phrase matching is case-insensitive and trimmed.
  //
  // Usage (inside the future start() implementation):
  //   final text = await stt.recognise();          // from whatever STT package
  //   _commandCtrl.add(VoiceCommandsService.parse(text));
  //
  static VoiceCommand parse(String text) {
    final t = text.toLowerCase().trim();

    // ── Vibe modes — direct spec phrases before optional aliases ─────────
    final directVibeCommand = _directVibePhraseMappings[t];
    if (directVibeCommand != null) return directVibeCommand;
    if (t == 'slowed reverb')                             return VoiceCommand.vibeSlowedReverb;
    if (t == 'night core')                                return VoiceCommand.vibeNightcore;
    if (t == 'lo-fi' || t == 'lo fi')                    return VoiceCommand.vibeLofi;
    if (t == 'normal'        || t == 'original' ||
        t == 'vibe off')                                  return VoiceCommand.vibeNone;
    if (t == 'vibe next'     || t == 'next vibe')        return VoiceCommand.vibeNext;

    // ── Playback ─────────────────────────────────────────────────────────
    if (t == 'play'    || t == 'resume')                 return VoiceCommand.play;
    if (t == 'pause'   || t == 'stop')                   return VoiceCommand.pause;
    if (t == 'mute')                                     return VoiceCommand.mute;
    if (t == 'unmute'  || t == 'volume on')              return VoiceCommand.unmute;
    if (t == 'screenshot' || t == 'capture')             return VoiceCommand.screenshot;
    if (t == 'next'    || t == 'next episode')           return VoiceCommand.nextEpisode;
    if (t == 'previous'|| t == 'previous episode' ||
        t == 'prev'    || t == 'prev episode')           return VoiceCommand.prevEpisode;
    if (t == 'faster'  || t == 'speed up')               return VoiceCommand.speedUp;
    if (t == 'slower'  || t == 'speed down')             return VoiceCommand.speedDown;
    if (t == 'forward' || t == 'skip forward')           return VoiceCommand.forward;
    if (t == 'back'    || t == 'skip back' || t == 'rewind') return VoiceCommand.back;

    return VoiceCommand.unknown;
  }
}
