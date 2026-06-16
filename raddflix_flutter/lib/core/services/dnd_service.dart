/// Phase H5 — Do Not Disturb Mode
/// When entering Immersive or Cinematic mode → enable Android DND (all except alarms).
/// Restores DND state when player exits or mode changes back.
library dnd_h5;

import 'package:flutter/services.dart';

class DoNotDisturbService {
  DoNotDisturbService._();
  static final instance = DoNotDisturbService._();

  static const _ch = MethodChannel('com.raddflix/dnd');

  bool _active = false;
  bool get isActive => _active;

  /// Enable DND — call when entering Immersive/Cinematic mode.
  Future<void> enable() async {
    if (_active) return;
    try {
      final granted = await _ch.invokeMethod<bool>('enableDnd') ?? false;
      _active = granted;
    } catch (_) {
      // DND access not granted or not available on this Android version / iOS
    }
  }

  /// Disable DND — call on player dismiss or mode exit.
  Future<void> disable() async {
    if (!_active) return;
    try {
      await _ch.invokeMethod('disableDnd');
      _active = false;
    } catch (_) {}
  }

  Future<bool> hasPermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasDndPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _ch.invokeMethod('requestDndPermission');
    } catch (_) {}
  }
}
