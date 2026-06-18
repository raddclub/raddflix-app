import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase M2 — Jump To Panel
/// Quick time navigation buttons + manual timecode entry.
/// -5m  -1m  -30s  [pos]  +30s  +1m  +5m plus typed jump.
class JumpToSheet extends StatelessWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final ValueChanged<Duration> onJumpTo;
  final Color accentColor;

  const JumpToSheet({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.onJumpTo,
    required this.accentColor,
  });

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    if (d > totalDuration) d = totalDuration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Duration _clamp(Duration d) =>
      d < Duration.zero ? Duration.zero : d > totalDuration ? totalDuration : d;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // drag handle
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Icon(Icons.skip_next_rounded, color: accentColor, size: 20),
          const SizedBox(width: 10),
          const Text('Jump To',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '${_fmt(currentPosition)} / ${_fmt(totalDuration)}',
            style:
                const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ]),
        const SizedBox(height: 18),

        // ── Quick-jump buttons ────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _JumpBtn(label: '−5m',  color: accentColor,
              onTap: () { onJumpTo(_clamp(currentPosition - const Duration(minutes: 5))); Navigator.pop(context); }),
          _JumpBtn(label: '−1m',  color: accentColor,
              onTap: () { onJumpTo(_clamp(currentPosition - const Duration(minutes: 1))); Navigator.pop(context); }),
          _JumpBtn(label: '−30s', color: accentColor,
              onTap: () { onJumpTo(_clamp(currentPosition - const Duration(seconds: 30))); Navigator.pop(context); }),
          _JumpBtn(label: '+30s', color: accentColor, positive: true,
              onTap: () { onJumpTo(_clamp(currentPosition + const Duration(seconds: 30))); Navigator.pop(context); }),
          _JumpBtn(label: '+1m',  color: accentColor, positive: true,
              onTap: () { onJumpTo(_clamp(currentPosition + const Duration(minutes: 1))); Navigator.pop(context); }),
          _JumpBtn(label: '+5m',  color: accentColor, positive: true,
              onTap: () { onJumpTo(_clamp(currentPosition + const Duration(minutes: 5))); Navigator.pop(context); }),
        ]),

        const SizedBox(height: 16),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 12),

        // ── Manual timecode entry ─────────────────────────────────────
        _TimecodeEntry(
          currentPosition: currentPosition,
          totalDuration:   totalDuration,
          accentColor:     accentColor,
          onJump: (d) { onJumpTo(d); Navigator.pop(context); },
        ),

        const SizedBox(height: 8),

        // ── Chapter-style preset buttons ──────────────────────────────
        Row(children: [
          _PresetJump(label: 'Start',   icon: Icons.first_page_rounded,      color: accentColor, onTap: () { onJumpTo(Duration.zero); Navigator.pop(context); }),
          const SizedBox(width: 8),
          _PresetJump(label: '25%',     icon: Icons.looks_one_rounded,       color: accentColor, onTap: () { onJumpTo(totalDuration * 0.25); Navigator.pop(context); }),
          const SizedBox(width: 8),
          _PresetJump(label: 'Half',    icon: Icons.looks_two_rounded,       color: accentColor, onTap: () { onJumpTo(totalDuration * 0.50); Navigator.pop(context); }),
          const SizedBox(width: 8),
          _PresetJump(label: '75%',     icon: Icons.looks_3_rounded,         color: accentColor, onTap: () { onJumpTo(totalDuration * 0.75); Navigator.pop(context); }),
          const SizedBox(width: 8),
          _PresetJump(label: 'End',     icon: Icons.last_page_rounded,       color: accentColor, onTap: () { onJumpTo(totalDuration > const Duration(seconds: 10) ? totalDuration - const Duration(seconds: 5) : totalDuration); Navigator.pop(context); }),
        ]),
      ]),
    )
        .animate()
        .slideY(begin: 0.08, end: 0, duration: 220.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 180.ms);
  }
}

class _JumpBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool positive;
  final VoidCallback onTap;
  const _JumpBtn({required this.label, required this.color,
      this.positive = false, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: positive
            ? color.withOpacity(0.18)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: positive ? color.withOpacity(0.5) : Colors.white12,
            width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              color: positive ? color : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    ),
  );
}

class _PresetJump extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PresetJump({required this.label, required this.icon,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        ]),
      ),
    ),
  );
}

class _TimecodeEntry extends StatefulWidget {
  final Duration currentPosition, totalDuration;
  final Color accentColor;
  final ValueChanged<Duration> onJump;
  const _TimecodeEntry({required this.currentPosition,
      required this.totalDuration, required this.accentColor,
      required this.onJump});
  @override
  State<_TimecodeEntry> createState() => _TimecodeEntryState();
}

class _TimecodeEntryState extends State<_TimecodeEntry> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.currentPosition;
    final m = p.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = p.inSeconds.remainder(60).toString().padLeft(2, '0');
    _ctrl = TextEditingController(text: '$m:$s');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Duration? _parse(String txt) {
    final parts = txt.trim().split(':');
    try {
      if (parts.length == 2) {
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      } else if (parts.length == 3) {
        return Duration(hours: int.parse(parts[0]),
            minutes: int.parse(parts[1]), seconds: int.parse(parts[2]));
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          hintText: 'mm:ss or hh:mm:ss',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
          errorText: _error,
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (_) => setState(() => _error = null),
      ),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: () {
        final d = _parse(_ctrl.text);
        if (d == null) {
          setState(() => _error = 'Use mm:ss or hh:mm:ss');
          return;
        }
        if (d > widget.totalDuration) {
          setState(() => _error = 'Beyond video end');
          return;
        }
        widget.onJump(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: widget.accentColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Jump',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      ),
    ),
  ]);
}
