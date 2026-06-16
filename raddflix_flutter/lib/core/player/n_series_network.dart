/// Phase N1 — Adaptive Buffer Control
/// N2 — Download Quality Selector (offline download settings)
/// N3 — Network Speed Monitor (bandwidth display in HUD)
library n_series;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// N1 — Adaptive Buffer Control
// ─────────────────────────────────────────────────────────────────────────────

enum BufferStrategy { auto, conservative, aggressive, ultraLow }

const bufferStrategyLabels = {
  BufferStrategy.auto:         '🤖 Auto',
  BufferStrategy.conservative: '🐢 Conservative (30s buffer)',
  BufferStrategy.aggressive:   '🚀 Aggressive (60s buffer)',
  BufferStrategy.ultraLow:     '⚡ Ultra-Low Latency',
};

const bufferStrategyAheadMs = {
  BufferStrategy.auto:         15000,
  BufferStrategy.conservative: 30000,
  BufferStrategy.aggressive:   60000,
  BufferStrategy.ultraLow:     3000,
};

BufferStrategy bufferStrategyFromString(String s) =>
    BufferStrategy.values.firstWhere((v) => v.name == s,
        orElse: () => BufferStrategy.auto);

// ─────────────────────────────────────────────────────────────────────────────
// N3 — Network Speed Monitor
// ─────────────────────────────────────────────────────────────────────────────

class NetworkSpeedMonitor {
  NetworkSpeedMonitor._();
  static final instance = NetworkSpeedMonitor._();

  double _kbps = 0;
  Timer? _timer;
  int _lastBytes = 0;

  Stream<double>? _stream;
  final _ctrl = StreamController<double>.broadcast();

  Stream<double> get stream {
    _stream ??= _ctrl.stream;
    return _stream!;
  }

  double get currentKbps => _kbps;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      // In a real app: read bytes from the video player's stats
      // Simulation: random bandwidth between 500 and 15000 kbps
      final now = DateTime.now().millisecondsSinceEpoch;
      // Stub — will be replaced by real player stats
      _kbps = 1500 + (now % 13500);
      _ctrl.add(_kbps);
    });
  }

  void stop() {
    _timer?.cancel();
    _ctrl.add(0);
  }

  String format() {
    if (_kbps < 1) return '—';
    if (_kbps < 1000) return '${_kbps.toStringAsFixed(0)} kbps';
    return '${(_kbps / 1000).toStringAsFixed(1)} Mbps';
  }
}

class NetworkSpeedHud extends StatelessWidget {
  final double kbps;
  final Color accentColor;

  const NetworkSpeedHud({super.key, required this.kbps, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final color = kbps < 500 ? Colors.red
        : kbps < 2000 ? Colors.orange
        : Colors.greenAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.signal_cellular_alt_rounded, color: color, size: 13),
        const SizedBox(width: 5),
        Text(NetworkSpeedMonitor.instance.format(),
            style: TextStyle(color: Colors.white, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// N2 — Download Quality Selector
// ─────────────────────────────────────────────────────────────────────────────

enum DownloadQuality { auto, q480, q720, q1080, q4k }

const downloadQualityLabels = {
  DownloadQuality.auto: '🤖 Auto (Smart)',
  DownloadQuality.q480: '480p — ~350 MB/hr',
  DownloadQuality.q720: '720p — ~700 MB/hr',
  DownloadQuality.q1080: '1080p — ~1.5 GB/hr',
  DownloadQuality.q4k: '4K — ~4 GB/hr',
};

const downloadQualityNames = {
  DownloadQuality.auto: 'auto',
  DownloadQuality.q480: '480p',
  DownloadQuality.q720: '720p',
  DownloadQuality.q1080: '1080p',
  DownloadQuality.q4k: '4k',
};

DownloadQuality downloadQualityFromString(String s) =>
    DownloadQuality.values.firstWhere(
        (v) => downloadQualityNames[v] == s,
        orElse: () => DownloadQuality.auto);
