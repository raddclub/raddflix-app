import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase J — Screenshot Share Sheet
/// Shows captured frame with watermark options before sharing.
class ScreenshotShareSheet extends StatefulWidget {
  final Uint8List imageBytes;
  final String videoTitle;
  final Duration position;
  final Color accentColor;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const ScreenshotShareSheet({
    super.key,
    required this.imageBytes,
    required this.videoTitle,
    required this.position,
    required this.accentColor,
    required this.onShare,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  State<ScreenshotShareSheet> createState() => _ScreenshotShareSheetState();
}

class _ScreenshotShareSheetState extends State<ScreenshotShareSheet> {
  bool _showTimestamp  = true;
  bool _showTitle      = true;
  bool _showWatermark  = false;
  String _watermarkText = 'RaddFlix';

  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Icon(Icons.screenshot_monitor_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Screenshot',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(
              onTap: widget.onDiscard,
              child: const Icon(Icons.close_rounded, color: Colors.white38, size: 22)),
          ]),
        ),
        const SizedBox(height: 12),

        // Image preview
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(alignment: Alignment.bottomLeft, children: [
                Image.memory(widget.imageBytes, fit: BoxFit.contain),
                // Overlay: timestamp
                if (_showTimestamp)
                  Positioned(
                    bottom: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(_fmt(widget.position),
                          style: const TextStyle(color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                    ),
                  ),
                // Overlay: title
                if (_showTitle)
                  Positioned(
                    bottom: 10, left: 10,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(widget.videoTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                // Watermark
                if (_showWatermark)
                  Positioned(
                    top: 10, right: 10,
                    child: Opacity(
                      opacity: 0.6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: acc.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text(_watermarkText,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        // Options
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(children: [
            Row(children: [
              _ToggleChip('Timestamp', _showTimestamp, acc,
                  () => setState(() => _showTimestamp = !_showTimestamp)),
              const SizedBox(width: 8),
              _ToggleChip('Title', _showTitle, acc,
                  () => setState(() => _showTitle = !_showTitle)),
              const SizedBox(width: 8),
              _ToggleChip('Watermark', _showWatermark, acc,
                  () => setState(() => _showWatermark = !_showWatermark)),
            ]),
          ]),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onSave,
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: const Text('Save to Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 180.ms);
  }

  Widget _ToggleChip(String label, bool on, Color acc, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? acc.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? acc : Colors.white12, width: on ? 1.5 : 1)),
        child: Text(label, style: TextStyle(
          color: on ? Colors.white : Colors.white60,
          fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.normal)),
      ),
    );

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }
}
