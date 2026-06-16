/// Phase J5 — Haptic Feedback Patterns
/// Centralised service that respects the user's haptic level preference.
/// All player interactions call through here instead of directly calling
/// HapticFeedback.* — so the user can tune or disable haptics entirely.
library haptic_service;

import 'package:flutter/services.dart';

/// Haptic level from PlayerPrefs.hapticLevel.
/// 'none' = all silent
/// 'light' = only light impact for minor interactions
/// 'medium' = light + medium for seek/mode changes
/// 'heavy' = full feedback on all interactions (default MX Player feel)
enum HapticLevel { none, light, medium, heavy }

HapticLevel hapticLevelFromString(String s) {
  switch (s) {
    case 'none':   return HapticLevel.none;
    case 'light':  return HapticLevel.light;
    case 'medium': return HapticLevel.medium;
    default:       return HapticLevel.heavy;
  }
}

class HapticService {
  HapticService._();
  static final instance = HapticService._();

  HapticLevel _level = HapticLevel.heavy;

  /// Call when PlayerPrefs changes — keeps haptic level synced.
  void setLevel(String level) => _level = hapticLevelFromString(level);

  // ── Interaction categories ────────────────────────────────────────────────

  /// Minor interactions: chip tap, toggle, small button press.
  void minor() {
    if (_level == HapticLevel.none) return;
    HapticFeedback.selectionClick();
  }

  /// Standard interaction: play/pause, mode toggle, QSP row tap.
  void standard() {
    switch (_level) {
      case HapticLevel.none:  return;
      case HapticLevel.light: HapticFeedback.selectionClick(); return;
      default:                HapticFeedback.lightImpact();
    }
  }

  /// Seek / scrub feedback (called repeatedly during drag).
  void seek() {
    switch (_level) {
      case HapticLevel.none:
      case HapticLevel.light: return;
      default:                HapticFeedback.selectionClick();
    }
  }

  /// Strong feedback: lock engaged, error, chapter boundary.
  void strong() {
    switch (_level) {
      case HapticLevel.none:  return;
      case HapticLevel.light:
      case HapticLevel.medium: HapticFeedback.lightImpact(); return;
      case HapticLevel.heavy:  HapticFeedback.mediumImpact();
    }
  }

  /// Maximum feedback: sleep timer end, long-press speed activate, AB point set.
  void max() {
    if (_level == HapticLevel.none) return;
    if (_level == HapticLevel.heavy) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  /// Vibrate pattern: two quick pulses (error feedback).
  Future<void> error() async {
    if (_level == HapticLevel.none) return;
    await HapticFeedback.vibrate();
  }
}
