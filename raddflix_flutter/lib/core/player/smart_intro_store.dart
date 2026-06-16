import 'package:shared_preferences/shared_preferences.dart';

/// Stores and retrieves the smart skip-intro position for each series episode.
///
/// Key format: `intro_pos_{seriesId}_{epIndex}`
/// A saved value of -1 means "user explicitly cleared it".
class SmartIntroStore {
  static const _prefix = 'intro_pos_';
  static const _clearedValue = -1;

  /// Content types for which skip-intro is applicable.
  static const Set<String> _introTypes = {
    'series', 'drama', 'anime', 'donghua', 'cartoon', 'show',
  };

  /// Whether skip-intro should be shown for this content type + duration.
  static bool shouldShow({
    required String contentType,
    required Duration totalDuration,
  }) {
    if (!_introTypes.contains(contentType.toLowerCase())) return false;
    if (totalDuration.inMinutes < 10) return false;
    return true;
  }

  /// Returns the saved intro-end position in seconds, or null if none saved.
  static Future<int?> getIntroEnd({
    required String seriesId,
    required int epIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix${seriesId}_$epIndex';
    final val = prefs.getInt(key);
    if (val == null || val == _clearedValue) return null;
    return val;
  }

  /// Saves the intro-end position when user taps Skip.
  static Future<void> saveIntroEnd({
    required String seriesId,
    required int epIndex,
    required int positionSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix${seriesId}_$epIndex', positionSeconds);
  }

  /// Clears the saved intro position (long-press Skip → "Clear saved time").
  static Future<void> clearIntroEnd({
    required String seriesId,
    required int epIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix${seriesId}_$epIndex', _clearedValue);
  }
}
