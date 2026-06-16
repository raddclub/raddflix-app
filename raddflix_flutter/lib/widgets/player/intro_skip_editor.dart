import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/player/intro_skip_store.dart';

/// Phase P — Intro / Credits Skip Editor
/// Visual timeline editor for setting custom skip segments per video.
/// Opened via long-press on the seek bar or from the More panel.

class IntroSkipEditor extends StatefulWidget {
  final String videoId;
  final Duration currentPosition;
  final Duration totalDuration;
  final Color accentColor;
  final VoidCallback onSaved;

  const IntroSkipEditor({
    super.key,
    required this.videoId,
    required this.currentPosition,
    required this.totalDuration,
    required this.accentColor,
    required this.onSaved,
  });

  @override
  State<IntroSkipEditor> createState() => _IntroSkipEditorState();
}

class _IntroSkipEditorState extends State<IntroSkipEditor> {
  List<SkipSegment> _segments = [];
  SkipSegmentType _addType = SkipSegmentType.intro;
  int? _pendingStartMs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final segs = await IntroSkipStore.load(widget.videoId);
    if (mounted) setState(() { _segments = segs; _loading = false; });
  }

  Duration get _pos => widget.currentPosition;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _setStart() async {
    setState(() => _pendingStartMs = _pos.inMilliseconds);
  }

  Future<void> _setEnd() async {
    final startMs = _pendingStartMs;
    if (startMs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap "Set Start" at the beginning first.'),
            duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
      return;
    }
    final endMs = _pos.inMilliseconds;
    if (endMs <= startMs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End must be after start.'),
            duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
      return;
    }
    final seg = SkipSegment(type: _addType, startMs: startMs, endMs: endMs);
    await IntroSkipStore.addSegment(widget.videoId, seg);
    setState(() => _pendingStartMs = null);
    await _load();
    widget.onSaved();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${seg.typeLabel} saved ✓'),
          duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  Future<void> _delete(SkipSegment seg) async {
    await IntroSkipStore.removeSegment(widget.videoId, seg);
    await _load();
    widget.onSaved();
  }

  Future<void> _clearAll() async {
    await IntroSkipStore.clearAll(widget.videoId);
    await _load();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    final total = widget.totalDuration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: Row(children: [
          Icon(Icons.content_cut_rounded, color: acc, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Skip Segment Editor',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          if (_segments.isNotEmpty)
            TextButton(onPressed: _clearAll,
                child: const Text('Clear all', style: TextStyle(color: Colors.redAccent, fontSize: 12))),
        ])),
        const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('Seek to a point in the video, set start then end to add a skip segment.',
              style: TextStyle(color: Colors.white38, fontSize: 11))),
        const Divider(color: Colors.white10, height: 1),

        // Current position badge
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: acc.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: acc.withOpacity(0.4))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.access_time_rounded, color: acc, size: 14),
              const SizedBox(width: 6),
              Text('Current: ${_fmt(_pos)}', style: TextStyle(color: acc,
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
          if (_pendingStartMs != null) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4))),
              child: Text('Start: ${_fmt(Duration(milliseconds: _pendingStartMs!))}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12))),
          ],
        ])),

        // Segment type selector
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: SkipSegmentType.values.map((t) {
            final isSel = _addType == t;
            return Padding(padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _addType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: isSel ? acc : Colors.white12,
                        width: isSel ? 1.5 : 1.0)),
                  child: Text(_segLabel(t), style: TextStyle(
                      color: isSel ? Colors.white : Colors.white54,
                      fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.normal)),
                ),
              ));
          }).toList())),

        // Action buttons
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
          Expanded(child: _ActionBtn(
            label: 'Set Start',
            icon: Icons.first_page_rounded,
            accent: acc,
            onTap: _setStart,
            filled: _pendingStartMs == null,
          )),
          const SizedBox(width: 12),
          Expanded(child: _ActionBtn(
            label: 'Set End & Save',
            icon: Icons.last_page_rounded,
            accent: acc,
            onTap: _pendingStartMs != null ? _setEnd : null,
            filled: _pendingStartMs != null,
          )),
        ])),

        const Divider(color: Colors.white10, height: 20),

        // Saved segments list
        if (_loading)
          const Padding(padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(strokeWidth: 2))
        else if (_segments.isEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text('No skip segments saved yet.',
                style: TextStyle(color: Colors.white38, fontSize: 13)))
        else
          Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Saved segments', style: TextStyle(color: Colors.white38, fontSize: 11)))),

            // Mini timeline
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child:
              Stack(children: [
                Container(height: 6, decoration: BoxDecoration(
                    color: Colors.white12, borderRadius: BorderRadius.circular(3))),
                ..._segments.map((seg) {
                  final left = (seg.startMs / total).clamp(0.0, 1.0);
                  final right = (seg.endMs / total).clamp(0.0, 1.0);
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: right - left,
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: left * (MediaQuery.of(context).size.width - 32)),
                      child: Container(height: 6, decoration: BoxDecoration(
                          color: _segColor(seg.type),
                          borderRadius: BorderRadius.circular(3)))));
                }),
              ])),

            Flexible(child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _segments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final seg = _segments[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: _segColor(seg.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _segColor(seg.type).withOpacity(0.35))),
                  child: Row(children: [
                    Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(color: _segColor(seg.type), shape: BoxShape.circle)),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(seg.typeLabel, style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${_fmt(seg.start)} → ${_fmt(seg.end)}  (${_fmt(seg.length)})',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ])),
                    GestureDetector(
                      onTap: () => _delete(seg),
                      child: const Padding(padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18))),
                  ]),
                );
              },
            )),
          ])),
      ]),
    ).animate().slideY(begin: 0.08, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 200.ms);
  }

  String _segLabel(SkipSegmentType t) {
    switch (t) {
      case SkipSegmentType.intro:   return 'Intro';
      case SkipSegmentType.recap:   return 'Recap';
      case SkipSegmentType.credits: return 'Credits';
      case SkipSegmentType.sponsor: return 'Sponsor';
      case SkipSegmentType.custom:  return 'Custom';
    }
  }

  Color _segColor(SkipSegmentType t) {
    switch (t) {
      case SkipSegmentType.intro:   return const Color(0xFF4FC3F7);
      case SkipSegmentType.recap:   return const Color(0xFFFFB74D);
      case SkipSegmentType.credits: return const Color(0xFFCE93D8);
      case SkipSegmentType.sponsor: return const Color(0xFF80CBC4);
      case SkipSegmentType.custom:  return const Color(0xFFA5D6A7);
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool filled;
  const _ActionBtn({required this.label, required this.icon, required this.accent,
      this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: filled && enabled ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: filled && enabled ? accent : Colors.white12,
              width: filled && enabled ? 1.5 : 1.0)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: enabled ? (filled ? accent : Colors.white70) : Colors.white24, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              color: enabled ? (filled ? Colors.white : Colors.white70) : Colors.white24,
              fontSize: 12, fontWeight: filled ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}
