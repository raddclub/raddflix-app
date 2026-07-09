import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Phase W — Media Info Overlay
/// Displays detailed codec, resolution, bitrate, file info.

class MediaInfo {
  final String title;
  final String? year;
  final String? resolution;   // e.g. '3840x2160'
  final String? videoCodec;   // e.g. 'H.265/HEVC'
  final String? audioCodec;   // e.g. 'DTS-HD MA 7.1'
  final String? container;    // e.g. 'MKV'
  final int?    bitrateKbps;
  final String? hdrMode;      // e.g. 'HDR10', 'Dolby Vision'
  final String? frameRate;    // e.g. '23.976 fps'
  final int?    fileSizeMb;
  final Duration? duration;

  const MediaInfo({
    required this.title,
    this.year, this.resolution, this.videoCodec, this.audioCodec,
    this.container, this.bitrateKbps, this.hdrMode, this.frameRate,
    this.fileSizeMb, this.duration,
  });
}

class MediaInfoOverlay extends StatelessWidget {
  final MediaInfo info;
  final Color accentColor;
  final VoidCallback onClose;

  const MediaInfoOverlay({
    super.key,
    required this.info,
    required this.accentColor,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final acc = accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0,12,0,0),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Media Info', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: onClose,
              child: const Icon(Icons.close_rounded, color: Colors.white38, size: 22)),
          ])),
        const Divider(color: Colors.white10, height: 20),
        Flexible(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            // Title
            Text(info.title, style: const TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w700)),
            if (info.year != null)
              Text(info.year!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),

            // HDR / Quality badge row
            if (info.hdrMode != null || info.resolution != null)
              Row(children: [
                if (info.hdrMode != null) _Badge(info.hdrMode!, color: const Color(0xFFFF9800)),
                if (info.resolution != null) ...[
                  const SizedBox(width: 8),
                  _Badge(_resLabel(info.resolution!), color: acc),
                ],
              ]),
            const SizedBox(height: 16),

            // Info grid
            _InfoSection('Video', [
              if (info.videoCodec  != null) _Row('Codec',      info.videoCodec!),
              if (info.resolution  != null) _Row('Resolution', info.resolution!),
              if (info.frameRate   != null) _Row('Frame Rate', info.frameRate!),
              if (info.bitrateKbps != null) _Row('Bitrate',    _fmtBitrate(info.bitrateKbps!)),
              if (info.hdrMode     != null) _Row('HDR',        info.hdrMode!),
            ]),
            const SizedBox(height: 12),
            _InfoSection('Audio', [
              if (info.audioCodec != null) _Row('Codec', info.audioCodec!),
            ]),
            const SizedBox(height: 12),
            _InfoSection('File', [
              if (info.container   != null) _Row('Container', info.container!),
              if (info.fileSizeMb  != null) _Row('File Size', '${info.fileSizeMb} MB'),
              if (info.duration    != null) _Row('Duration',  _fmtDur(info.duration!)),
            ]),
          ],
        )),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic).fadeIn(duration: 180.ms);
  }

  String _resLabel(String res) {
    final parts = res.split('x');
    if (parts.length == 2) {
      final h = int.tryParse(parts[1]) ?? 0;
      if (h >= 2160) return '4K';
      if (h >= 1080) return '1080p';
      if (h >= 720)  return '720p';
      if (h >= 480)  return '480p';
      return '${h}p';
    }
    return res;
  }

  String _fmtBitrate(int kbps) =>
      kbps >= 1000 ? '${(kbps / 1000).toStringAsFixed(1)} Mbps' : '$kbps Kbps';

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m ${s}s' : '${m}m ${s}s';
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _InfoSection(this.title, this.rows);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title.toUpperCase(), style: const TextStyle(
        color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    const SizedBox(height: 8),
    Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10)),
      child: Column(children: rows)),
  ]);
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(
          color: Colors.white38, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))),
    ]));
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, {required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.5))),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 12, fontWeight: FontWeight.w700)));
}
