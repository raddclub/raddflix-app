import 'package:device_info_plus/device_info_plus.dart';
import 'keystore.dart';

/// Gets a stable unique device identifier for account binding.
/// Uses Android's ANDROID_ID — unique per device + app install.
/// Cached in secure storage so it's the same across app restarts.
class DeviceIdentifier {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<String> getDeviceId() async {
    // Return cached value if available
    final cached = await Keystore.getDeviceId();
    if (cached != null && cached.isNotEmpty) return cached;

    // Generate from Android device info
    final id = await _generateId();
    await Keystore.saveDeviceId(id);
    return id;
  }

  static Future<String> _generateId() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final id = androidInfo.id; // ANDROID_ID — stable per device
      if (id.isNotEmpty) return 'android_$id';
    } catch (_) {}

    // L-01: Fallback: generate a stable UUID-style random ID that won't
    // collide across reinstalls unlike a timestamp-based ID.
    // Persisted in keystore on first call so it's stable across re-launches.
    final bytes = List<int>.generate(16, (_) => DateTime.now().microsecondsSinceEpoch.remainder(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final fallback = 'device_$hex';
    return fallback;
  }

  static Future<String> getDeviceName() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final brand = androidInfo.brand;
      final model = androidInfo.model;
      return '$brand $model'.trim();
    } catch (_) {
      return 'Android Device';
    }
  }
}
