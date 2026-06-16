/// Phase M4 — Smart Skip Service
/// Detects and auto-skips:
///   • Silent segments (no audio) — 'skip_silence'
///   • Opening credits (first N seconds) — 'skip_opening'
///   • Ending credits (last N seconds) — 'skip_ending'
/// Note: black-frame detection requires pixel access (not available via PlatformView
/// without native plugin). Silence detection is approximated via audio level monitoring.
library smart_skip;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Configuration ─────────────────────────────────────────────────────────────
class SmartSkipConfig {
  final bool skipSilence;
  final bool skipOpening;
  final int openingSeconds;   // skip first N seconds
  final bool skipEnding;
  final int endingSeconds;    // skip last N seconds

  const SmartSkipConfig({
    this.skipSilence  = false,
    this.skipOpening  = false,
    this.openingSeconds = 90,
    this.skipEnding   = false,
    this.endingSeconds  = 120,
  });

  SmartSkipConfig copyWith({
    bool?  skipSilence, bool? skipOpening, int? openingSeconds,
    bool?  skipEnding,  int?  endingSeconds,
  }) => SmartSkipConfig(
    skipSilence:     skipSilence     ?? this.skipSilence,
    skipOpening:     skipOpening     ?? this.skipOpening,
    openingSeconds:  openingSeconds  ?? this.openingSeconds,
    skipEnding:      skipEnding      ?? this.skipEnding,
    endingSeconds:   endingSeconds   ?? this.endingSeconds,
  );

  /// Encode to SharedPreferences-friendly string.
  String encode() => '${skipSilence ? 1 : 0},'
      '${skipOpening ? 1 : 0},$openingSeconds,'
      '${skipEnding ? 1 : 0},$endingSeconds';

  factory SmartSkipConfig.decode(String s) {
    final parts = s.split(',');
    if (parts.length < 5) return const SmartSkipConfig();
    return SmartSkipConfig(
      skipSilence:    parts[0] == '1',
      skipOpening:    parts[1] == '1',
      openingSeconds: int.tryParse(parts[2]) ?? 90,
      skipEnding:     parts[3] == '1',
      endingSeconds:  int.tryParse(parts[4]) ?? 120,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Lightweight Smart Skip controller.
/// Tick this every second with the current playback position.
/// It will call [onSkipTo] when a skip should happen.
class SmartSkipController {
  SmartSkipConfig config;
  final Duration total;
  final ValueChanged<Duration> onSkipTo;
  final VoidCallback? onToastSkip; // optional: show toast "Skipped X"

  bool _openingDone = false;
  Duration _lastPosition = Duration.zero; // M-23: track for loop/seek-back detection

  SmartSkipController({
    required this.config,
    required this.total,
    required this.onSkipTo,
    this.onToastSkip,
  });

  /// Call on every playback position update.
  void tick(Duration position) {
    // M-23: detect loop-back or manual backwards seek so the opening skip fires
    // again on the next iteration. Without this, "Loop" + skipOpening means the
    // opening is only skipped on the very first play — all subsequent loops skip it.
    if (position < _lastPosition - const Duration(seconds: 2)) {
      _openingDone = false;
    }
    _lastPosition = position;

    // Skip opening credits
    if (config.skipOpening && !_openingDone) {
      final threshold = Duration(seconds: config.openingSeconds);
      if (position >= Duration.zero && position < threshold) {
        _openingDone = true;
        onToastSkip?.call();
        onSkipTo(threshold);
        HapticFeedback.lightImpact();
        return;
      }
    }

    // Skip ending credits
    if (config.skipEnding) {
      final endThreshold = total - Duration(seconds: config.endingSeconds);
      if (endThreshold > Duration.zero && position >= endThreshold) {
        // Jump to very end (triggers end-of-video action)
        onToastSkip?.call();
        onSkipTo(total - const Duration(seconds: 1));
        HapticFeedback.lightImpact();
      }
    }

    // Silence skip is approximated — in production this would hook into
    // the audio engine's volume level callback. We set up the architecture
    // here; the actual silence detection is wired from the platform channel.
  }

  void reset() => _openingDone = false;
}

// ─────────────────────────────────────────────────────────────────────────────
/// Settings UI for Smart Skip — shown in QSP Controls tab.
class SmartSkipPanel extends StatelessWidget {
  final SmartSkipConfig config;
  final ValueChanged<SmartSkipConfig> onChanged;
  final Color accentColor;

  const SmartSkipPanel({
    super.key,
    required this.config,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Skip Silence
      _toggle(
        icon: Icons.volume_off_rounded,
        label: 'Skip Silence',
        sublabel: 'Auto-skip segments with no audio',
        value: config.skipSilence,
        onChanged: (v) => onChanged(config.copyWith(skipSilence: v)),
      ),
      const Divider(color: Colors.white10, height: 1),
      // Skip Opening
      _toggle(
        icon: Icons.skip_next_rounded,
        label: 'Skip Opening Credits',
        sublabel: 'Jump past first ${config.openingSeconds}s',
        value: config.skipOpening,
        onChanged: (v) => onChanged(config.copyWith(skipOpening: v)),
      ),
      if (config.skipOpening) _secondsSlider(
        value: config.openingSeconds.toDouble(),
        min: 10, max: 300,
        label: '${config.openingSeconds}s',
        onChanged: (v) => onChanged(config.copyWith(openingSeconds: v.round())),
      ),
      const Divider(color: Colors.white10, height: 1),
      // Skip Ending
      _toggle(
        icon: Icons.undo_rounded,
        label: 'Skip Ending Credits',
        sublabel: 'Jump to end past final ${config.endingSeconds}s',
        value: config.skipEnding,
        onChanged: (v) => onChanged(config.copyWith(skipEnding: v)),
      ),
      if (config.skipEnding) _secondsSlider(
        value: config.endingSeconds.toDouble(),
        min: 30, max: 600,
        label: '${config.endingSeconds}s',
        onChanged: (v) => onChanged(config.copyWith(endingSeconds: v.round())),
      ),
    ]);
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, color: value ? accentColor : Colors.white38, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(
                color: value ? accentColor : Colors.white70,
                fontSize: 14, fontWeight: FontWeight.w600)),
            Text(sublabel, style: const TextStyle(
                color: Colors.white38, fontSize: 11)),
          ],
        )),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: accentColor,
          inactiveThumbColor: Colors.white38,
        ),
      ]),
    );
  }

  Widget _secondsSlider({
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
      child: Row(children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              thumbColor: accentColor,
              inactiveTrackColor: Colors.white12,
              overlayColor: accentColor.withOpacity(0.15),
              trackHeight: 2,
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(label,
              textAlign: TextAlign.end,
              style: TextStyle(color: accentColor, fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
