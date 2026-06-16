import 'package:flutter/material.dart';

/// Compact playback info overlay: codec, resolution, fps, bitrate, buffer.
class PlaybackInfoOverlay extends StatelessWidget {
  final String codec;
  final String resolution;
  final String fps;
  final String bitrate;
  final String buffer;
  final String decoder; // 'HW' or 'SW'

  const PlaybackInfoOverlay({
    super.key,
    required this.codec,
    required this.resolution,
    required this.fps,
    required this.bitrate,
    required this.buffer,
    required this.decoder,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80, right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white70, fontSize: 10.5,
              fontFamily: 'monospace'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Row('Decoder', decoder, decoder == 'HW' ? Colors.greenAccent : Colors.orangeAccent),
            _Row('Codec',   codec,   Colors.white70),
            _Row('Video',   resolution, Colors.white70),
            _Row('FPS',     fps,     Colors.white70),
            _Row('Bitrate', bitrate, Colors.white70),
            _Row('Buffer',  buffer,  Colors.lightBlueAccent),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String k, v;
  final Color vc;
  const _Row(this.k, this.v, this.vc);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 52, child: Text('$k:', style: const TextStyle(color: Colors.white38))),
      Text(v, style: TextStyle(color: vc)),
    ]),
  );
}
