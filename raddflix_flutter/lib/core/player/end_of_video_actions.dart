/// Phase M3 — End-of-Video Actions
/// Configurable actions when the video ends:
/// play_next | loop | return_home | show_credits | countdown_next | do_nothing
/// Countdown auto-play is shown as an animated countdown ring.
library end_of_video;

import 'dart:async';
import 'package:flutter/material.dart';

// ── Action type ───────────────────────────────────────────────────────────────
enum EndAction {
  playNext,
  loop,
  returnHome,
  showCredits,
  countdownNext,
  doNothing,
}

EndAction endActionFromString(String s) {
  switch (s) {
    case 'loop':           return EndAction.loop;
    case 'return_home':    return EndAction.returnHome;
    case 'show_credits':   return EndAction.showCredits;
    case 'countdown_next': return EndAction.countdownNext;
    case 'do_nothing':     return EndAction.doNothing;
    default:               return EndAction.playNext;
  }
}

String endActionToString(EndAction a) {
  switch (a) {
    case EndAction.loop:          return 'loop';
    case EndAction.returnHome:    return 'return_home';
    case EndAction.showCredits:   return 'show_credits';
    case EndAction.countdownNext: return 'countdown_next';
    case EndAction.doNothing:     return 'do_nothing';
    default:                      return 'play_next';
  }
}

// ── Labels + icons for picker ─────────────────────────────────────────────────
const endActionMeta = [
  (EndAction.playNext,      'Play Next',         Icons.skip_next_rounded),
  (EndAction.countdownNext, 'Auto-play (10s)',   Icons.timer_rounded),
  (EndAction.loop,          'Loop',              Icons.loop_rounded),
  (EndAction.returnHome,    'Return to Home',    Icons.home_rounded),
  (EndAction.showCredits,   'Show Credits',      Icons.info_outline_rounded),
  (EndAction.doNothing,     'Do Nothing',        Icons.stop_rounded),
];

// ─────────────────────────────────────────────────────────────────────────────
/// Animated countdown overlay when `endAction == countdownNext`.
/// Shows a ring timer counting down from [seconds] to 0, then calls [onDone].
/// Tapping "Play Now" triggers [onDone] immediately; "Cancel" → [onCancel].
class CountdownNextOverlay extends StatefulWidget {
  final int seconds;
  final String? nextTitle;
  final Color accentColor;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const CountdownNextOverlay({
    super.key,
    this.seconds = 10,
    this.nextTitle,
    required this.accentColor,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<CountdownNextOverlay> createState() => _CountdownNextOverlayState();
}

class _CountdownNextOverlayState extends State<CountdownNextOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Timer _ticker;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _ctrl = AnimationController(
      duration: Duration(seconds: widget.seconds),
      vsync: this,
    )..forward();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _ticker.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Countdown ring
              SizedBox(
                width: 80, height: 80,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: 1.0 - _ctrl.value,
                          strokeWidth: 4,
                          backgroundColor: Colors.white12,
                          color: widget.accentColor,
                        ),
                      ),
                      Text('$_remaining',
                          style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 28, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Up Next',
                  style: TextStyle(color: Colors.white54,
                      fontSize: 12, letterSpacing: 0.8)),
              const SizedBox(height: 6),
              if (widget.nextTitle != null)
                Text(
                  widget.nextTitle!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 20),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Cancel
                  OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  // Play Now
                  ElevatedButton(
                    onPressed: widget.onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 18),
                        SizedBox(width: 4),
                        Text('Play Now'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// End action picker shown in QSP or settings.
class EndActionPicker extends StatelessWidget {
  final EndAction current;
  final ValueChanged<EndAction> onChanged;
  final Color accentColor;

  const EndActionPicker({
    super.key,
    required this.current,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: endActionMeta.map((meta) {
        final action = meta.$1;
        final label  = meta.$2;
        final icon   = meta.$3;
        final active = action == current;
        return InkWell(
          onTap: () => onChanged(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon,
                  color: active ? accentColor : Colors.white38, size: 22),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      color: active ? accentColor : Colors.white70,
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
              const Spacer(),
              if (active)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
