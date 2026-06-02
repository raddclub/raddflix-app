import 'package:flutter/services.dart';

enum CastDeviceType { chromecast, airplay, dlna, miracast, localScreen }

class CastDevice {
  final String id, name, model, host;
  final CastDeviceType type;
  final int signalStrength; // 0–4
  const CastDevice({
    required this.id,
    required this.name,
    this.model = '',
    this.host = '',
    this.type = CastDeviceType.chromecast,
    this.signalStrength = 3,
  });
}

class CastService {
  CastService._();
  static const _ch = MethodChannel('com.raddflix.app/cast');

  static Future<List<CastDevice>> discoverDevices() async {
    try {
      final raw = await _ch.invokeMethod<List>('discoverDevices');
      return (raw ?? []).map((d) => CastDevice(
        id: d['id'] as String,
        name: d['name'] as String,
        model: d['model'] as String? ?? '',
        host: d['host'] as String? ?? '',
        type: _parseDeviceType(d['type'] as String? ?? ''),
        signalStrength: (d['signalStrength'] as int?) ?? 3,
      )).toList();
    } catch (_) { return []; }
  }

  static Future<bool> castVideo({
    required String url,
    required String title,
    String posterUrl = '',
    int positionMs = 0,
  }) async {
    try {
      return await _ch.invokeMethod<bool>('castVideo', {
        'url': url, 'title': title,
        'posterUrl': posterUrl, 'positionMs': positionMs,
      }) ?? false;
    } catch (_) { return false; }
  }

  static Future<bool> isConnected() async {
    try { return await _ch.invokeMethod<bool>('isConnected') ?? false; }
    catch (_) { return false; }
  }

  static Future<void> pause()    async => _ch.invokeMethod('pause').catchError((_){});
  static Future<void> resume()   async => _ch.invokeMethod('resume').catchError((_){});
  static Future<void> stop()     async => _ch.invokeMethod('stop').catchError((_){});
  static Future<void> seek(int ms) async =>
      _ch.invokeMethod('seek', {'positionMs': ms}).catchError((_){});
  static Future<void> disconnect() async =>
      _ch.invokeMethod('disconnect').catchError((_){});

  static CastDeviceType _parseDeviceType(String t) {
    switch (t.toLowerCase()) {
      case 'airplay':     return CastDeviceType.airplay;
      case 'dlna':        return CastDeviceType.dlna;
      case 'miracast':    return CastDeviceType.miracast;
      case 'localscreen': return CastDeviceType.localScreen;
      default:            return CastDeviceType.chromecast;
    }
  }
}
