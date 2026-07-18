// J5-part: Sidebar customizer & AI-dub widget classes extracted from player_screen.dart (Phase J)
// ignore_for_file: unused_import
part of '../player_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  SIDEBAR CUSTOMIZER PANEL
//  Lets the user reorder shortcuts and toggle which ones appear in the sidebar.
// ═════════════════════════════════════════════════════════════════════════════

class _SidebarCustomizerPanel extends StatefulWidget {
  final List<String> currentOrder;
  final List<String> allIds;
  final void Function(List<String>) onOrderChanged;

  const _SidebarCustomizerPanel({
    required this.currentOrder,
    required this.allIds,
    required this.onOrderChanged,
  });

  @override
  State<_SidebarCustomizerPanel> createState() => _SidebarCustomizerPanelState();
}

class _SidebarCustomizerPanelState extends State<_SidebarCustomizerPanel> {
  late List<String> _order;

  // Human-readable labels and icons for each shortcut ID
  static const _labels = <String, String>{
    'cc': 'Subtitles (CC)',  'audio': 'Audio Track',    'eq': 'Equalizer / EQ',
    'speed': 'Speed',        'loop': 'Loop',            'rotate': 'Rotate',
    'lock': 'Lock Screen',   'pip': 'Picture-in-Picture','screenshot': 'Screenshot',
    'immersive': 'Immersive Mode',
    'sleep': 'Sleep Timer',  'ab': 'A-B Repeat',        'episodes': 'Episodes',
    'settings': 'Settings',  'vivid': 'Vivid / Smart',  'mute': 'Mute',
    'frame': 'Frame Step',   'onehanded': 'One-Handed', 'zoom': 'Zoom & Crop',
    'silence': 'Silence Skip',
    'more': 'More (Quick Shortcuts)',
  };

  static const _icons = <String, IconData>{
    'cc': Icons.subtitles_rounded,            'audio': Icons.headphones_rounded,
    'eq': Icons.equalizer_rounded,            'speed': Icons.speed_rounded,
    'loop': Icons.loop_rounded,               'rotate': Icons.screen_rotation_rounded,
    'lock': Icons.lock_outline_rounded,       'pip': Icons.picture_in_picture_alt_rounded,
    'immersive': Icons.theaters_rounded,
    'screenshot': Icons.camera_alt_rounded,   'sleep': Icons.bedtime_rounded,
    'ab': Icons.repeat_one_rounded,           'episodes': Icons.view_list_rounded,
    'settings': Icons.settings_rounded,       'vivid': Icons.auto_awesome_rounded,
    'mute': Icons.volume_off_rounded,         'frame': Icons.skip_next_rounded,
    'onehanded': Icons.pan_tool_alt_rounded,  'zoom': Icons.zoom_in_rounded,
    'silence': Icons.volume_off_outlined,
    'more': Icons.more_horiz_rounded,
  };

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.currentOrder);
  }

  List<String> get _hidden =>
      widget.allIds.where((id) => !_order.contains(id)).toList();

  void _remove(String id) {
    setState(() => _order.remove(id));
    widget.onOrderChanged(List.from(_order));
  }

  void _add(String id) {
    setState(() => _order.add(id));
    widget.onOrderChanged(List.from(_order));
  }

  void _reorder(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    final item = _order.removeAt(oldIdx);
    _order.insert(newIdx, item);
    widget.onOrderChanged(List.from(_order));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hint row (title 'Sidebar Shortcuts' provided by RaddSheet)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(children: [
            const Text('Drag to reorder • tap × to hide',
                style: TextStyle(color: Colors.white38, fontSize: 10)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_order.length} shown',
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        // Reorderable visible list
        Expanded(
          child: Column(children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _order.length,
                onReorder: _reorder,
                itemBuilder: (ctx, i) {
                  final id = _order[i];
                  return ListTile(
                    key: ValueKey(id),
                    dense: true,
                    leading: Icon(_icons[id] ?? Icons.star_rounded,
                        color: Colors.white70, size: 20),
                    title: Text(_labels[id] ?? id,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Remove button
                      GestureDetector(
                        onTap: () => _remove(id),
                        child: Container(
                          padding: const EdgeInsets.all(RaddSpace.xs),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white38, size: 16),
                        ),
                      ),
                      const SizedBox(width: RaddSpace.xs),
                      // Drag handle
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded,
                            color: Colors.white38, size: 20),
                      ),
                    ]),
                  );
                },
              ),
            ),

            // ── Hidden shortcuts — tap to add back ───────────────────────
            if (_hidden.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(children: [
                  const Text('Hidden shortcuts',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  Text('tap + to show',
                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ]),
              ),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _hidden.length,
                  itemBuilder: (ctx, i) {
                    final id = _hidden[i];
                    return ListTile(
                      dense: true,
                      leading: Opacity(
                        opacity: 0.45,
                        child: Icon(_icons[id] ?? Icons.star_rounded,
                            color: Colors.white, size: 18),
                      ),
                      title: Opacity(
                        opacity: 0.45,
                        child: Text(_labels[id] ?? id,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      trailing: GestureDetector(
                        onTap: () => _add(id),
                        child: Container(
                          padding: const EdgeInsets.all(RaddSpace.xs),
                          child: const Icon(Icons.add_circle_outline_rounded,
                              color: Colors.white60, size: 20),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Dub language button
// ─────────────────────────────────────────────────────────────────────────────
class _DubLangBtn extends StatelessWidget {
  final String flag;
  final String label;
  final String sublabel;
  final Color  color;
  final VoidCallback? onTap;
  const _DubLangBtn({required this.flag, required this.label,
      required this.sublabel, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.40), width: 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: RaddSpace.xs),
          Text(label, style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w700)),
          Text(sublabel, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Dub progress card (shown as full-screen overlay during generation)
// ─────────────────────────────────────────────────────────────────────────────
class _DubProgressCard extends StatelessWidget {
  final String lang;
  final double progress;
  final int    currentLine;
  final int    totalLines;
  final String statusText;

  const _DubProgressCard({
    required this.lang,
    required this.progress,
    required this.currentLine,
    required this.totalLines,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final isUrdu   = lang == 'ur-PK';
    final flag     = isUrdu ? '🇵🇰' : '🇮🇳';
    final langName = isUrdu ? 'Urdu' : 'Hindi';
    final barColor = isUrdu ? AppColors.jazzGreen : const Color(0xFFFF9933);
    final pct      = (progress * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Flag + title
        Text(flag, style: const TextStyle(fontSize: 48))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(1,1), end: const Offset(1.08,1.08),
                   duration: 900.ms, curve: Curves.easeInOut),
        const SizedBox(height: 14),
        Text('Generating $langName Dub',
            style: const TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Using on-device TTS · Music will be preserved',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 28),

        // Animated waveform bars
        const _WaveformBars(),
        const SizedBox(height: 28),

        // Progress bar
        ClipRRect(
          borderRadius: RaddRadius.smRadius,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 12),

        // Percentage + line counter
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$pct%',
              style: TextStyle(color: barColor,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          Text(totalLines > 0 ? 'Line $currentLine of $totalLines' : statusText,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
        const SizedBox(height: RaddSpace.sm),
        Text(statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Animated waveform bars
// ─────────────────────────────────────────────────────────────────────────────
class _WaveformBars extends StatelessWidget {
  const _WaveformBars();

  @override
  Widget build(BuildContext context) {
    const bars = 7;
    const barW = 5.0;
    const maxH = 36.0;
    const minH = 8.0;
    const barColor = Color(0xFF4A9EFF);
    return SizedBox(
      height: maxH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bars, (i) {
          final delay = Duration(milliseconds: i * 100);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(width: barW, height: minH,
                    decoration: BoxDecoration(
                      color: barColor.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ))
                .animate(onPlay: (c) => c.repeat(reverse: true), delay: delay)
                .scaleY(begin: 1, end: maxH / minH,
                        duration: 500.ms, curve: Curves.easeInOut,
                        alignment: Alignment.bottomCenter)
                .then()
                .custom(
                  duration: 0.ms,
                  builder: (ctx, val, child) => ColorFiltered(
                    colorFilter: ColorFilter.mode(
                        barColor.withOpacity(0.4 + val * 0.5),
                        BlendMode.srcATop),
                    child: child,
                  ),
                ),
          );
        }),
      ),
    );
  }
}
