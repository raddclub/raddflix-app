/// RaddFlix Player Debug Logger
/// Keeps an in-memory ring buffer (2 000 entries) and writes to a temp file.
/// Activate the in-player debug overlay by tapping the clock (top-right) 5× rapidly.
/// Then press "Share Log" inside the overlay to send the log file.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class DebugLogger {
  static const int _maxEntries = 2000;
  static final List<String> _buffer = [];
  static IOSink? _sink;
  static String? _logPath;

  static Future<void> init() async {
    _write('INIT', '=== RaddFlix Debug Session Start ===');
    try {
      // Write to system temp — no storage permission needed, always writable.
      final tmp = Directory.systemTemp;
      _logPath = '${tmp.path}/raddflix_player.log';
      final f = File(_logPath!);
      // Rotate if file grows over 3 MB.
      if (f.existsSync() && f.lengthSync() > 3 * 1024 * 1024) {
        f.deleteSync();
      }
      _sink = f.openWrite(mode: FileMode.append);
      _sink?.writeln('[${_ts()}] [INIT] === RaddFlix Debug Session Start ===');
    } catch (e) {
      _write('INIT', 'File logger failed: $e (in-memory only)');
    }
  }

  static void log(String tag, String msg) => _write(tag, msg);

  static void logError(String tag, String msg, [Object? err]) =>
      _write('ERR/$tag', err != null ? '$msg | $err' : msg);

  static void logState(String tag, Map<String, dynamic> state) =>
      _write(tag, state.entries.map((e) => '${e.key}=${e.value}').join(' | '));

  static void _write(String tag, String msg) {
    final entry = '[${_ts()}] [$tag] $msg';
    _buffer.add(entry);
    if (_buffer.length > _maxEntries) _buffer.removeAt(0);
    try { _sink?.writeln(entry); } catch (_) {}
  }

  static String _ts() {
    final n = DateTime.now();
    final hh = n.hour.toString().padLeft(2, '0');
    final mm = n.minute.toString().padLeft(2, '0');
    final ss = n.second.toString().padLeft(2, '0');
    final ms = n.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }

  /// Returns up to [n] most recent log entries.
  static List<String> getRecent([int n = 150]) => _buffer.length <= n
      ? List.of(_buffer)
      : _buffer.sublist(_buffer.length - n);

  /// Copies entire log to clipboard.
  static Future<void> copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _buffer.join('\n')));
  }

  /// Flushes the file sink.
  static Future<void> flush() async {
    try { await _sink?.flush(); } catch (_) {}
  }

  /// Shares the log file via the system share sheet.
  static Future<void> share() async {
    try {
      await flush();
      if (_logPath != null && File(_logPath!).existsSync()) {
        await Share.shareXFiles(
          [XFile(_logPath!)],
          subject: 'RaddFlix Player Debug Log',
          text: 'Debug log — please share with RaddFlix support.',
        );
        return;
      }
    } catch (_) {}
    // Fallback: share as plain text.
    try {
      await Share.share(_buffer.join('\n'), subject: 'RaddFlix Player Debug Log');
    } catch (_) {}
  }

  static String? get logPath => _logPath;
  static int get entryCount => _buffer.length;
}
