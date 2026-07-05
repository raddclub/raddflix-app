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
      _write('INIT', '--- re-init marker ---');
      return;
    }
    _initialized = true;
    _write('INIT', '=== App Start ${now.toString().substring(0, 19)} ===');
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
      _sink?.writeln('[${_ts()}] [INIT] === Session Start ===');
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
  ///
  /// SECURITY: requestBody/responsePreview/error may contain server-issued
  /// secrets (validationkey, k= HMAC tokens, JSESSIONID). These are redacted
  /// via [_redactBody] BEFORE truncation/storage — never store or export the
  /// raw values, even in-memory, since the ring buffer is user-shareable.
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
    if (requestBody != null && requestBody.isNotEmpty) {
      final redacted = _redactBody(requestBody);
      parts.add('req=$redacted');
    }
    if (responsePreview != null && responsePreview.isNotEmpty) {
      final redacted = _redactBody(responsePreview);
      parts.add('resp=${redacted.length > 200 ? redacted.substring(0, 200) + "…" : redacted}');
    }
    if (error != null && error.isNotEmpty) parts.add('err=${_redactBody(error)}');
    _write('API', parts.join(' | '));
  }

  /// Redacts server-issued secrets from a request/response body BEFORE it is
  /// truncated or written anywhere (buffer, file, share export).
  /// Covers: validationkey=, bare k= tokens, JSESSIONID (as a cookie/header
  /// value or JSON field), and Bearer/Authorization tokens.
  static String _redactBody(String body) => body
      .replaceAll(RegExp(r'validation[_\s-]?key\s*[=:]\s*[^\s&"' "'" r']+', caseSensitive: false), 'validationkey=[redacted]')
      .replaceAll(RegExp(r'\bk=[A-Za-z0-9%_\-+/=]{6,}'), 'k=[redacted]')
      .replaceAll(RegExp(r'jsessionid\s*[=:]\s*[^\s&;"' "'" r']+', caseSensitive: false), 'JSESSIONID=[redacted]')
      .replaceAll(RegExp(r'(authorization|bearer)\s*[=:]\s*[^\s&"' "'" r']+', caseSensitive: false), 'Authorization=[redacted]')
      .replaceAll(RegExp(r'refresh_token"?\s*[=:]\s*"?[^\s&,"' "'" r' }]+', caseSensitive: false), 'refresh_token=[redacted]')
      .replaceAll(RegExp(r'access_token"?\s*[=:]\s*"?[^\s&,"' "'" r' }]+', caseSensitive: false), 'access_token=[redacted]');

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

  /// Copies a sanitised diagnostics summary to clipboard.
  /// Never exposes raw log lines, service names, or internal identifiers.
  static Future<void> copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _sanitisedReport()));
  }

  static Future<void> flush() async {
    try { await _sink?.flush(); } catch (_) {}
  }

  /// Shares a sanitised diagnostics report only — never the raw log file.
  static Future<void> share() async {
    try {
      await Share.share(
        _sanitisedReport(),
        subject: 'RaddFlix Diagnostics Report',
      );
    } catch (_) {}
  }

  static Future<void> shareLogs() => share();

  /// Builds a sanitised diagnostics report suitable for clipboard / share.
  /// Contains only: entry count, error count, and last ≤10 normalised error
  /// summaries — no raw log lines, no IDs, no URLs, no token values.
  static String _sanitisedReport() {
    final errorEntries = _buffer.where((e) {
      final upper = e.toUpperCase();
      return upper.contains('] [ERR/') || upper.contains('] [CRASH/');
    }).toList();

    final buf = StringBuffer();
    buf.writeln('RaddFlix Diagnostics Report');
    buf.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buf.writeln('Log entries this session: ${_buffer.length}');
    buf.writeln('Errors this session: ${errorEntries.length}');
    buf.writeln('');
    if (errorEntries.isEmpty) {
      buf.writeln('No errors recorded.');
    } else {
      buf.writeln('Recent errors (last ${errorEntries.length > 10 ? 10 : errorEntries.length}):');
      final recent = errorEntries.length > 10
          ? errorEntries.sublist(errorEntries.length - 10)
          : errorEntries;
      for (final e in recent) {
        // Extract only the message portion (after the last '] ') and sanitise it
        final msgStart = e.lastIndexOf('] ');
        final raw = msgStart >= 0 ? e.substring(msgStart + 2) : e;
        buf.writeln('  - ${_sanitiseMessage(raw)}');
      }
    }
    return buf.toString();
  }

  /// Sanitises a single log message for export:
  /// - Strips internal service/provider names and crypto-method references
  /// - Redacts URLs, file paths, token-like strings, and numeric/hex IDs
  static String _sanitiseMessage(String msg) => msg
      // Internal service names and variants
      .replaceAll(RegExp(r'jazzdrive', caseSensitive: false), '[stream-provider]')
      .replaceAll(RegExp(r'oracle', caseSensitive: false), '[content-server]')
      .replaceAll(RegExp(r'validation[_\s-]?key', caseSensitive: false), '[token]')
      .replaceAll(RegExp(r'jsessionid', caseSensitive: false), '[session]')
      .replaceAll(RegExp(r'\bxor\b', caseSensitive: false), '[enc]')
      .replaceAll(RegExp(r'\bsapi\b', caseSensitive: false), '[api]')
      // URLs (http/https and bare cloud hostnames)
      .replaceAll(RegExp(r'https?://\S+'), '[url]')
      .replaceAll(RegExp(r'cloud\.\S+'), '[url]')
      // Token-like strings: long alphanumeric/base64 blobs, k= HMAC values
      .replaceAll(RegExp(r'\bk=[A-Za-z0-9%_\-+/=]{8,}'), 'k=[token]')
      .replaceAll(RegExp(r'\b[A-Za-z0-9+/=]{32,}\b'), '[token]')
      // Numeric IDs and file paths
      .replaceAll(RegExp(r'\b\d{5,}\b'), '[id]')
      .replaceAll(RegExp(r'/[^\s]+\.(mkv|mp4|avi|srt|json)'), '[file]');

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
