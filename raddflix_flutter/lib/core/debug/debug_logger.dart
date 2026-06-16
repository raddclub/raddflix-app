import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const bool kDebugLogging = true;

class DebugLogger {
  static File? _logFile;
  static final List<String> _memBuffer = [];
  static const int _maxMemLines = 3000;
  static DateTime? _startTime;

  static Future<void> init() async {
    if (!kDebugLogging) return;
    _startTime = DateTime.now();
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/raddflix_debug.log');
      if (await _logFile!.exists()) await _logFile!.delete();
      _raw('=' * 70);
      _raw('RADDFLIX DEBUG LOG  |  Session: ${DateTime.now().toIso8601String()}');
      _raw('=' * 70);
    } catch (e) {
      print('[DebugLogger] init error: $e');
    }
  }

  static Future<void> logDeviceInfo() async {
    if (!kDebugLogging) return;
    try {
      if (Platform.isAndroid) {
        final info = DeviceInfoPlugin();
        final a = await info.androidInfo;
        log('DEVICE', 'Manufacturer: ${a.manufacturer}  Model: ${a.model}');
        log('DEVICE', 'Android: ${a.version.release}  SDK: ${a.version.sdkInt}');
        log('DEVICE', 'Physical: ${a.isPhysicalDevice}  Brand: ${a.brand}');
        log('DEVICE', 'Fingerprint: ${a.fingerprint}');
      }
    } catch (e) {
      logError('DEVICE', 'Failed to get device info', e);
    }
  }

  static void log(String tag, String message) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [INFO ] [$tag] $message');
  }

  static void logWarn(String tag, String message) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [WARN ] [$tag] $message');
  }

  static void logError(String tag, String message,
      [dynamic error, StackTrace? stack]) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [ERROR] [$tag] $message');
    if (error != null) _raw('         └─ $error');
    if (stack != null) {
      for (final l in stack.toString().split('\n').take(8)) {
        _raw('            $l');
      }
    }
  }

  static void logCrash(String context, dynamic error, StackTrace? stack) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [CRASH] [$context] $error');
    if (stack != null) {
      for (final l in stack.toString().split('\n').take(15)) {
        _raw('   $l');
      }
    }
  }

  static void logApi({
    required String method,
    required String url,
    int? statusCode,
    String? responsePreview,
    dynamic error,
    int? durationMs,
    String? requestBody,
  }) {
    if (!kDebugLogging) return;
    final dur = durationMs != null ? ' ${durationMs}ms' : '';
    if (error != null) {
      _raw('[${_ts()}] [API  ] $method $url →$dur ERROR: $error');
    } else {
      _raw('[${_ts()}] [API  ] $method $url →$dur HTTP $statusCode');
      if (responsePreview != null && responsePreview.isNotEmpty) {
        final p = responsePreview.length > 700
            ? '${responsePreview.substring(0, 700)}…[truncated ${responsePreview.length} chars]'
            : responsePreview;
        _raw('         └─ $p');
      }
    }
    if (requestBody != null && requestBody.isNotEmpty) {
      _raw('         └─ REQ: $requestBody');
    }
  }

  static void logNav(String route, {String? args}) {
    if (!kDebugLogging) return;
    _raw(
        '[${_ts()}] [NAV  ] → $route${args != null && args.isNotEmpty ? "  args=$args" : ""}');
  }

  static void logDb(String op, String detail) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [DB   ] $op: $detail');
  }

  static void logSync(String stage, String detail) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [SYNC ] $stage: $detail');
  }

  static void logUi(String widget, String event) {
    if (!kDebugLogging) return;
    _raw('[${_ts()}] [UI   ] [$widget] $event');
  }

  static String _ts() {
    final now = DateTime.now();
    final up = _startTime != null
        ? '+${now.difference(_startTime!).inSeconds}s'
        : '';
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$h:$m:$s $up';
  }

  static void _raw(String line) {
    print(line);
    _memBuffer.add(line);
    if (_memBuffer.length > _maxMemLines) _memBuffer.removeAt(0);
    try {
      _logFile?.writeAsString('$line\n', mode: FileMode.append).ignore();
    } catch (_) {}
  }

  static String getLogPath() => _logFile?.path ?? 'in-memory only';

  static String getLastLines(int n) =>
      _memBuffer.length <= n
          ? _memBuffer.join('\n')
          : _memBuffer.sublist(_memBuffer.length - n).join('\n');

  /// Clears the in-memory log buffer (does not delete the log file).
  static void clearBuffer() => _memBuffer.clear();

  static Future<void> shareLogs() async {
    try {
      final path = _logFile?.path;
      if (path != null && await File(path).exists()) {
        await Share.shareXFiles([XFile(path)], subject: 'RaddFlix Debug Log');
        return;
      }
    } catch (_) {}
    await Share.share(getLastLines(500), subject: 'RaddFlix Debug Log');
  }
}
