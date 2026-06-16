/// Phase M2 — Jump To (Skip by Time)
/// Quick time-jump panel: -5m / -1m / -30s / +30s / +1m / +5m buttons.
/// Also allows typing a specific timestamp to jump to.
library jump_to_panel;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Compact overlay panel that lets user jump by fixed time intervals.
/// Appears as a centered floating card inside the player.
class JumpToPanel extends StatefulWidget {
  final Duration current;
  final Duration total;
  final ValueChanged<Duration> onJump;
  final Color accentColor;
  final VoidCallback onDismiss;

  const JumpToPanel({
    super.key,
    required this.current,
    required this.total,
    required this.onJump,
    required this.accentColor,
    required this.onDismiss,
  });

  @override
  State<JumpToPanel> createState() => _JumpToPanelState();
}

class _JumpToPanelState extends State<JumpToPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  final _textCtrl = TextEditingController();
  String? _errorMsg;

  // Jump buttons: label → seconds delta
  static const _jumps = [
    ('-5m', -300), ('-1m', -60), ('-30s', -30),
    ('+30s', 30), ('+1m', 60), ('+5m', 300),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _jump(int deltaSeconds) {
    HapticFeedback.selectionClick();
    Duration next = widget.current + Duration(seconds: deltaSeconds);
    if (next < Duration.zero) next = Duration.zero;
    if (next > widget.total) next = widget.total;
    widget.onJump(next);
  }

  void _jumpTo() {
    final text = _textCtrl.text.trim();
    // Parse HH:MM:SS, MM:SS, or raw seconds
    final parsed = _parseTime(text);
    if (parsed == null) {
      setState(() => _errorMsg = 'Use 1:30, 01:30:00, or 90');
      return;
    }
    setState(() => _errorMsg = null);
    Duration target = Duration(seconds: parsed);
    if (target > widget.total) target = widget.total;
    if (target < Duration.zero) target = Duration.zero;
    widget.onJump(target);
    _textCtrl.clear();
  }

  int? _parseTime(String s) {
    if (s.isEmpty) return null;
    if (!s.contains(':')) return int.tryParse(s);
    final parts = s.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
    if (parts.length == 3) return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
    return null;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // don't dismiss on panel tap
            child: ScaleTransition(
              scale: _anim,
              child: Container(
                width: 340,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 32, spreadRadius: 4)],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Row(children: [
                        const Icon(Icons.fast_forward_rounded,
                            color: Colors.white54, size: 18),
                        const SizedBox(width: 8),
                        const Text('Jump To',
                            style: TextStyle(color: Colors.white,
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white38, size: 20),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      // Current position
                      Text(
                        '${_fmt(widget.current)} / ${_fmt(widget.total)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 16),
                      // Jump buttons grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _jumps.map((j) {
                          final label = j.$1 as String;
                          final delta = j.$2 as int;
                          final isForward = delta > 0;
                          return GestureDetector(
                            onTap: () => _jump(delta),
                            child: Container(
                              width: 52,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isForward
                                    ? widget.accentColor.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: isForward
                                        ? widget.accentColor.withOpacity(0.4)
                                        : Colors.white12)),
                              child: Column(children: [
                                Icon(
                                  isForward
                                      ? Icons.fast_forward_rounded
                                      : Icons.fast_rewind_rounded,
                                  color: isForward
                                      ? widget.accentColor
                                      : Colors.white54,
                                  size: 18),
                                const SizedBox(height: 4),
                                Text(label,
                                    style: TextStyle(
                                        color: isForward
                                            ? widget.accentColor
                                            : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Type a timestamp
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _textCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            keyboardType: TextInputType.text,
                            decoration: InputDecoration(
                              hintText: 'e.g. 1:23:45 or 83',
                              hintStyle: const TextStyle(color: Colors.white30),
                              errorText: _errorMsg,
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.06),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _jumpTo(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _jumpTo,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
