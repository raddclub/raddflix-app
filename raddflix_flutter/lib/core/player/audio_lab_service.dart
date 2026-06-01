/// Phase E1–E4 — Audio Lab Service
/// Centralised audio post-processing controller.
///
/// E1 — Virtual Surround Sound (Binaural modes: Stadium / Theater / Small Room)
/// E2 — Karaoke Mode (vocal reduction via phase-cancellation simulation)
/// E3 — Dialogue Boost (boost 2kHz–5kHz frequency band)
/// E4 — Bluetooth Audio Delay Fix (0–500ms audio offset)
///
/// Implementation strategy:
///   • VLC-based players: apply via VLC audio filter chain & EQ preset API
///   • Fallback: communicate intent via platform channel for native audio engine
library audio_lab;

import 'package:flutter/services.dart';

// ── Surround modes (E1) ───────────────────────────────────────────────────────
enum SurroundMode { off, stadium, theater, smallRoom }

SurroundMode surroundModeFromString(String s) {
  switch (s) {
    case 'stadium':    return SurroundMode.stadium;
    case 'theater':    return SurroundMode.theater;
    case 'small_room': return SurroundMode.smallRoom;
    default:           return SurroundMode.off;
  }
}
String surroundModeToString(SurroundMode m) {
  switch (m) {
    case SurroundMode.stadium:    return 'stadium';
    case SurroundMode.theater:    return 'theater';
    case SurroundMode.smallRoom:  return 'small_room';
    default:                      return 'off';
  }
}

/// Human-readable labels for UI.
const surroundModeLabels = {
  SurroundMode.off:       'Off',
  SurroundMode.stadium:   '🏟 Stadium',
  SurroundMode.theater:   '🎭 Theater',
  SurroundMode.smallRoom: '🛋 Small Room',
};

// ── Karaoke levels (E2) ───────────────────────────────────────────────────────
enum KaraokeLevel { off, reduce, strongReduce, remove }

KaraokeLevel karaokeLevelFromString(String s) {
  switch (s) {
    case 'reduce':        return KaraokeLevel.reduce;
    case 'strong_reduce': return KaraokeLevel.strongReduce;
    case 'remove':        return KaraokeLevel.remove;
    default:              return KaraokeLevel.off;
  }
}
String karaokeLevelToString(KaraokeLevel l) {
  switch (l) {
    case KaraokeLevel.reduce:       return 'reduce';
    case KaraokeLevel.strongReduce: return 'strong_reduce';
    case KaraokeLevel.remove:       return 'remove';
    default:                        return 'off';
  }
}
const karaokeLevelLabels = {
  KaraokeLevel.off:          'Off',
  KaraokeLevel.reduce:       'Reduce',
  KaraokeLevel.strongReduce: 'Strong Reduce',
  KaraokeLevel.remove:       'Remove',
};

// ─────────────────────────────────────────────────────────────────────────────
/// Audio Lab state — all settings in one object.
class AudioLabConfig {
  // E1
  final SurroundMode surroundMode;
  // E2
  final KaraokeLevel karaokeLevel;
  // E3
  final bool dialogueBoost;
  // E4
  final int bluetoothDelayMs; // 0–500 ms

  const AudioLabConfig({
    this.surroundMode     = SurroundMode.off,
    this.karaokeLevel     = KaraokeLevel.off,
    this.dialogueBoost    = false,
    this.bluetoothDelayMs = 0,
  });

  AudioLabConfig copyWith({
    SurroundMode? surroundMode,
    KaraokeLevel? karaokeLevel,
    bool?         dialogueBoost,
    int?          bluetoothDelayMs,
  }) => AudioLabConfig(
    surroundMode:     surroundMode     ?? this.surroundMode,
    karaokeLevel:     karaokeLevel     ?? this.karaokeLevel,
    dialogueBoost:    dialogueBoost    ?? this.dialogueBoost,
    bluetoothDelayMs: bluetoothDelayMs ?? this.bluetoothDelayMs,
  );

  /// Encode as 'surround|karaoke|dialogueBoost|btDelayMs'
  String encode() =>
      '${surroundModeToString(surroundMode)}|'
      '${karaokeLevelToString(karaokeLevel)}|'
      '${dialogueBoost ? 1 : 0}|'
      '$bluetoothDelayMs';

  factory AudioLabConfig.decode(String s) {
    final p = s.split('|');
    if (p.length < 4) return const AudioLabConfig();
    return AudioLabConfig(
      surroundMode:     surroundModeFromString(p[0]),
      karaokeLevel:     karaokeLevelFromString(p[1]),
      dialogueBoost:    p[2] == '1',
      bluetoothDelayMs: int.tryParse(p[3]) ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Singleton that applies AudioLabConfig to the player via platform channel.
class AudioLabService {
  AudioLabService._();
  static final instance = AudioLabService._();

  static const _ch = MethodChannel('com.raddflix/audio_lab');

  AudioLabConfig _config = const AudioLabConfig();
  AudioLabConfig get config => _config;

  Future<void> apply(AudioLabConfig config) async {
    _config = config;
    try {
      await _ch.invokeMethod('applyAudioLab', {
        'surround':      surroundModeToString(config.surroundMode),
        'karaokeLevel':  karaokeLevelToString(config.karaokeLevel),
        'dialogueBoost': config.dialogueBoost,
        'btDelayMs':     config.bluetoothDelayMs,
      });
    } catch (_) {
      // Graceful fallback — UI state persists even if platform channel unavailable.
      // VLC audio filter IDs:
      //   surround → 'headphone_channel_mixer' or 'spatializer'
      //   karaoke  → 'karaoke' (VLC built-in; sets MixLev parameter 0.0–1.0)
      //   eq boost → VLC equalizer preset manipulation
      //   bt delay → VLC audio delay via libvlc_audio_set_delay
    }
  }

  /// Called from PlayerScreen.initState + on prefs change.
  void setFromPrefs(String encoded) {
    _config = AudioLabConfig.decode(encoded);
    apply(_config);
  }
}
