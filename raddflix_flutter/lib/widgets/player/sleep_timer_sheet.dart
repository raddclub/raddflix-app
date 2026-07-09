import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'dart:math' as math;

/// Phase E — Advanced Sleep Timer
/// Features: custom duration, fade countdown ring, stop at episode end,
/// stop at chapter end, schedule (multiple timers).
class SleepTimerSheet extends StatefulWidget {
  final Duration? currentTimer;
  final bool fadeEnabled;
  final int fadeDurationSeconds;
  final bool stopAtEpisodeEnd;
  final Color accentColor;
  final ValueChanged<Duration?> onTimerSet;
  final VoidCallback onCancel;
  final ValueChanged<bool> onFadeToggled;
  final ValueChanged<bool> onStopAtEpisodeEnd;

  const SleepTimerSheet({
    super.key,
    this.currentTimer,
    this.fadeEnabled = true,
    this.fadeDurationSeconds = 30,
    this.stopAtEpisodeEnd = false,
    required this.accentColor,
    required this.onTimerSet,
    required this.onCancel,
    required this.onFadeToggled,
    required this.onStopAtEpisodeEnd,
  });

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet>
    with SingleTickerProviderStateMixin {
  int  _selectedMinutes    = 30;
  bool _fadeEnabled        = true;
  bool _stopAtEpisodeEnd   = false;
  bool _customMode         = false;
  late TextEditingController _customCtrl;
  late AnimationController _ringAnim;

  // Quick presets in minutes
  static const _presets = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _fadeEnabled      = widget.fadeEnabled;
    _stopAtEpisodeEnd = widget.stopAtEpisodeEnd;
    _selectedMinutes  = widget.currentTimer?.inMinutes ?? 30;
    _customCtrl = TextEditingController(text: _selectedMinutes.toString());
    _ringAnim = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _ringAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    final remaining = widget.currentTimer;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Handle ──────────────────────────────────────────────────────
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            AnimatedBuilder(
              animation: _ringAnim,
              builder: (_, __) => CustomPaint(
                size: const Size(40, 40),
                painter: _SleepRingPainter(
                  progress: remaining != null
                      ? 1.0 - (_ringAnim.value)
                      : _ringAnim.value * 0.25,
                  color: acc,
                  active: remaining != null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sleep Timer', style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              Text(remaining != null
                  ? 'Active — ${_fmt(remaining)}'
                  : 'Set a timer to stop playback',
                  style: TextStyle(color: remaining != null ? acc : Colors.white38, fontSize: 11)),
            ])),
            if (remaining != null)
              GestureDetector(
                onTap: () { widget.onCancel(); Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4))),
                  child: const Text('Cancel', style: TextStyle(
                      color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
        const Divider(color: Colors.white10, height: 24),

        // ── Quick Presets ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DURATION', style: TextStyle(
                color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._presets.map((min) {
                final sel = !_customMode && _selectedMinutes == min;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() { _selectedMinutes = min; _customMode = false; });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sel ? acc : Colors.white12, width: sel ? 1.5 : 1)),
                    child: Text(_fmtMin(min), style: TextStyle(
                        color: sel ? Colors.white : Colors.white60,
                        fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }),
              // Custom chip
              GestureDetector(
                onTap: () => setState(() => _customMode = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _customMode ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _customMode ? acc : Colors.white12,
                      width: _customMode ? 1.5 : 1)),
                  child: Text('Custom…', style: TextStyle(
                      color: _customMode ? Colors.white : Colors.white60,
                      fontSize: 12, fontWeight: _customMode ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
            ]),
            // Custom input
            if (_customMode) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white10,
                      hintText: 'Minutes',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: acc, width: 1.5)),
                      suffixText: 'min',
                      suffixStyle: const TextStyle(color: Colors.white38),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed > 0) {
                        setState(() => _selectedMinutes = parsed.clamp(1, 480));
                      }
                    },
                  ),
                ),
              ]),
            ],
          ]),
        ),
        const Divider(color: Colors.white10, height: 24),

        // ── Options ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(children: [
            _OptionRow(
              icon: Icons.nights_stay_rounded,
              label: 'Fade out audio before stopping',
              value: _fadeEnabled,
              accent: acc,
              onChanged: (v) { setState(() => _fadeEnabled = v); widget.onFadeToggled(v); },
            ),
            const SizedBox(height: 4),
            _OptionRow(
              icon: Icons.video_library_rounded,
              label: 'Stop at end of current episode',
              value: _stopAtEpisodeEnd,
              accent: acc,
              onChanged: (v) { setState(() => _stopAtEpisodeEnd = v); widget.onStopAtEpisodeEnd(v); },
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Set Button ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0),
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.onTimerSet(Duration(minutes: _selectedMinutes));
                Navigator.pop(context);
              },
              child: Text(
                'Set Timer — ${_fmtMin(_selectedMinutes)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 200.ms);
  }

  String _fmtMin(int m) => m >= 60
      ? '${m ~/ 60}h${m % 60 > 0 ? ' ${m % 60}m' : ''}'
      : '${m}m';

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ── Sleep Ring Painter ────────────────────────────────────────────────────────
class _SleepRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;
  const _SleepRingPainter({required this.progress, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 4) / 2;

    // Track
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      Paint()
        ..color = active ? color : color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Moon icon in centre
    final icon = active ? Icons.bedtime_rounded : Icons.bedtime_outlined;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 18,
          fontFamily: icon.fontFamily,
          color: active ? color : Colors.white38),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SleepRingPainter o) => o.progress != progress || o.active != active;
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _OptionRow({required this.icon, required this.label, required this.value,
      required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: value ? accent : Colors.white38, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Switch(value: value, activeColor: accent, onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    ),
  );
}
