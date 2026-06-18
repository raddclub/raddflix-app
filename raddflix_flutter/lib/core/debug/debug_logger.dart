/// RaddFlix Universal Debug Logger — v2
/// Captures EVERY user action, navigation, feature, crash, and API call.
/// Ring buffer: 5,000 entries. Written to temp file — no storage permission needed.
/// Access: Profile → Account → Debug Logs  |  Rotate: old file kept as .old

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class DebugLogger {
  static const int _maxEntries = 5000;
  static final List<String> _buffer = [];
  static IOSink? _sink;
  static String? _logPath;
  static bool _initialized = false;
  static String _sessionId = '??';
  static Timer? _autoFlushTimer;

  /// Call once at app start (main.dart) and once in PlayerScreen.initState.
  /// Safe to call multiple times — only initialises the file on the first call.
  static Future<void> init() async {
    final now = DateTime.now();
    _sessionId =
        '${now.hour.toString().padLeft(2, "0")}'
        '${now.minute.toString().padLeft(2, "0")}'
        '${now.second.toString().padLeft(2, "0")}';
    if (_initialized) {
      _write('INIT', '--- re-init marker sid=$_sessionId ---');
      return;
    }
    _initialized = true;
    _write('INIT', '=== RaddFlix Session Start sid=$_sessionId ${now.toString().substring(0, 19)} ===');
    try {
      final tmp  = Directory.systemTemp;
      _logPath   = '${tmp.path}/raddflix_debug.log';
      final f    = File(_logPath!);
      // Rotate when > 8 MB — keep one old copy
      if (f.existsSync() && f.lengthSync() > 8 * 1024 * 1024) {
        final old = File('${tmp.path}/raddflix_debug.log.old');
        try { if (old.existsSync()) old.deleteSync(); f.renameSync(old.path); } catch (_) { f.deleteSync(); }
      }
      _sink = f.openWrite(mode: FileMode.append);
      _sink?.writeln('[${_ts()}] [INIT] === Session Start sid=$_sessionId ===');
      // Auto-flush every 30 s — ensures log is flushed even if app crashes
      _autoFlushTimer?.cancel();
      _autoFlushTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        try { await _sink?.flush(); } catch (_) {}
      });
    } catch (e) {
      _write('INIT', 'File logger error: $e (in-memory only)');
    }
  }

  // ── Core log methods ────────────────────────────────────────────────────

  /// General purpose log
  static void log(String tag, String msg) => _write(tag, msg);

  /// Error with optional exception object
  static void logError(String tag, String msg, [Object? err]) =>
      _write('ERR/$tag', err != null ? '$msg | $err' : msg);

  /// Warning
  static void logWarn(String tag, String msg) => _write('WARN/$tag', msg);

  // ── Semantic helpers (appear with distinctive tag prefixes) ─────────────

  /// Button press / gesture tap — screen name + what was tapped + optional detail
  static void logTap(String screen, String action, [String? detail]) =>
      _write('TAP/$screen', detail != null ? '$action | $detail' : action);

  /// Screen navigation — push / pop / replace
  static void logNav(String action, String route, [String? detail]) =>
      _write('NAV', detail != null ? '$action $route | $detail' : '$action $route');

  /// Screen lifecycle — initState / dispose / resume / pause
  static void logLifecycle(String screen, String event) =>
      _write('LC/$screen', event);

  /// Feature invocation — which premium/core feature the user activated
  static void logFeature(String feature, [String? params]) =>
      _write('FEAT', params != null ? '$feature | $params' : feature);

  /// Uncaught exception with condensed stack trace (top 20 frames)
  static void logCrash(String tag, Object error, StackTrace stack) {
    final frames = stack.toString().split('\n').take(20).join('\n    ');
    _write('CRASH/$tag', '$error\n    $frames');
  }

  /// API call — method, URL, HTTP status, timing, optional preview
  static void logApi({
    required String method,
    required String url,
    String? requestBody,
    int? statusCode,
    String? responsePreview,
    String? error,
    int? durationMs,
  }) {
    final parts = <String>['$method $url'];
    if (statusCode != null) parts.add('HTTP $statusCode');
    if (durationMs != null) parts.add('${durationMs}ms');
    if (requestBody != null && requestBody.isNotEmpty) parts.add('req=$requestBody');
    if (responsePreview != null && responsePreview.isNotEmpty)
      parts.add('resp=${responsePreview.length > 200 ? responsePreview.substring(0, 200) + "…" : responsePreview}');
    if (error != null && error.isNotEmpty) parts.add('err=$error');
    _write('API', parts.join(' | '));
  }

  /// Structured key=value state snapshot
  static void logState(String tag, Map<String, dynamic> state) =>
      _write(tag, state.entries.map((e) => '${e.key}=${e.value}').join(' | '));

  // ── Buffer access ────────────────────────────────────────────────────────

  static String getLastLines([int n = 200]) {
    final recent = _buffer.length <= n ? List.of(_buffer) : _buffer.sublist(_buffer.length - n);
    return recent.join('\n');
  }

  static List<String> getRecent([int n = 200]) =>
      _buffer.length <= n ? List.of(_buffer) : _buffer.sublist(_buffer.length - n);

  /// Returns recent entries whose tag contains [tagFragment] (case-insensitive).
  static List<String> getFiltered(String tagFragment, [int n = 300]) {
    final frag = tagFragment.toUpperCase();
    final matched = _buffer.where((e) {
      final bracketEnd = e.indexOf(']', e.indexOf('[', 1) + 1);
      final tag = bracketEnd > 0 ? e.substring(0, bracketEnd + 1).toUpperCase() : e.toUpperCase();
      return tag.contains(frag);
    }).toList();
    return matched.length <= n ? matched : matched.sublist(matched.length - n);
  }

  static void clearBuffer() => _buffer.clear();
  static String getLogPath() => _logPath ?? '';
  static String? get logPath => _logPath;
  static int get entryCount => _buffer.length;
  static String get sessionId => _sessionId;

  // ── Share / clipboard ────────────────────────────────────────────────────

  static Future<void> copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _buffer.join('\n')));
  }

  static Future<void> flush() async {
    try { await _sink?.flush(); } catch (_) {}
  }

  static Future<void> share() async {
    try {
      await flush();
      if (_logPath != null && File(_logPath!).existsSync()) {
        await Share.shareXFiles(
          [XFile(_logPath!)],
          subject: 'RaddFlix Debug Log sid=$_sessionId',
          text: 'Debug log from RaddFlix — please send to support.',
        );
        return;
      }
    } catch (_) {}
    try {
      await Share.share(_buffer.join('\n'), subject: 'RaddFlix Debug Log');
    } catch (_) {}
  }

  static Future<void> shareLogs() => share();

  // ── Internal ─────────────────────────────────────────────────────────────

  static void _write(String tag, String msg) {
    final entry = '[${_ts()}] [$tag] $msg';
    _buffer.add(entry);
    if (_buffer.length > _maxEntries) _buffer.removeAt(0);
    try { _sink?.writeln(entry); } catch (_) {}
  }

  static String _ts() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, "0")}:${n.minute.toString().padLeft(2, "0")}:${n.second.toString().padLeft(2, "0")}.${n.millisecond.toString().padLeft(3, "0")}';
  }
}
