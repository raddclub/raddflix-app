/// Phase E1–E4 — Audio Lab Panel
/// QSP sub-panel for all 4 audio enhancement features.
library audio_lab_panel;

import 'package:flutter/material.dart';
import '../../core/player/audio_lab_service.dart';

class AudioLabPanel extends StatelessWidget {
  final AudioLabConfig config;
  final ValueChanged<AudioLabConfig> onChanged;
  final Color accentColor;

  const AudioLabPanel({
    super.key,
    required this.config,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [

      // ── E1: Virtual Surround ──────────────────────────────────────────────
      _label('Virtual Surround (E1)'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          children: SurroundMode.values.map((mode) {
            final active = config.surroundMode == mode;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(config.copyWith(surroundMode: mode)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? accentColor.withOpacity(0.18)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active ? accentColor : Colors.white12,
                        width: 1.2)),
                  child: Column(children: [
                    Text(
                      surroundModeLabels[mode] ?? mode.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: active ? accentColor : Colors.white54,
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w400),
                    ),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const Divider(color: Colors.white10, height: 1),

      // ── E2: Karaoke Mode ─────────────────────────────────────────────────
      _label('Karaoke / Vocal Remover (E2)'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          children: KaraokeLevel.values.map((level) {
            final active = config.karaokeLevel == level;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(config.copyWith(karaokeLevel: level)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? accentColor.withOpacity(0.18)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active ? accentColor : Colors.white12,
                        width: 1.2)),
                  child: Text(
                    karaokeLevelLabels[level] ?? level.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: active ? accentColor : Colors.white54,
                        fontSize: 10.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const Divider(color: Colors.white10, height: 1),

      // ── E3: Dialogue Boost ───────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(Icons.record_voice_over_rounded,
              color: config.dialogueBoost ? accentColor : Colors.white38,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dialogue Boost',
                  style: TextStyle(
                      color: config.dialogueBoost ? accentColor : Colors.white70,
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Text('Boosts 2kHz–5kHz speech frequencies',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          Switch(
            value: config.dialogueBoost,
            onChanged: (v) => onChanged(config.copyWith(dialogueBoost: v)),
            activeColor: accentColor,
            inactiveThumbColor: Colors.white38,
          ),
        ]),
      ),
      const Divider(color: Colors.white10, height: 1),

      // ── E4: Bluetooth Audio Delay ─────────────────────────────────────────
      _label('Bluetooth Audio Delay (E4)'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.bluetooth_audio_rounded,
                color: Colors.white38, size: 18),
            const SizedBox(width: 8),
            Text(
              '${config.bluetoothDelayMs} ms',
              style: TextStyle(
                  color: accentColor,
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (config.bluetoothDelayMs > 0)
              GestureDetector(
                onTap: () => onChanged(config.copyWith(bluetoothDelayMs: 0)),
                child: const Text('Reset',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
          ]),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              thumbColor: accentColor,
              inactiveTrackColor: Colors.white12,
              overlayColor: accentColor.withOpacity(0.12),
              trackHeight: 2,
            ),
            child: Slider(
              value: config.bluetoothDelayMs.toDouble(),
              min: 0, max: 500,
              divisions: 100,
              onChanged: (v) =>
                  onChanged(config.copyWith(bluetoothDelayMs: v.round())),
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0ms', style: TextStyle(color: Colors.white24, fontSize: 10)),
              Text('250ms', style: TextStyle(color: Colors.white24, fontSize: 10)),
              Text('500ms', style: TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ]),
      ),
    ]);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      Text(text.toUpperCase(),
          style: const TextStyle(
              color: Colors.white30,
              fontSize: 10, letterSpacing: 0.8,
              fontWeight: FontWeight.w600)),
    ]),
  );
}
