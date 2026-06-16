/// Phase C1 — Custom Gesture Mapping
/// User remaps swipe/tap gestures to any action.
/// C2 — Pinch Brightness (already partially present, this adds finer control)
/// C3 — Custom Long-Press Actions (long-press any zone → user-defined action)
library c_series;

import 'dart:convert';
import 'package:flutter/material.dart';

// ── Gesture zones ─────────────────────────────────────────────────────────────
enum GestureZone { left, center, right, topLeft, topRight, bottomLeft, bottomRight }

// ── Available actions per gesture ─────────────────────────────────────────────
enum GestureAction {
  seekForward, seekBackward, volumeUp, volumeDown, brightnessUp, brightnessDown,
  playPause, nextChapter, prevChapter, toggleSubtitles, toggleFullscreen,
  lockScreen, takeScreenshot, openSettings, none,
}

const gestureActionLabels = <GestureAction, String>{
  GestureAction.seekForward:     'Seek Forward',
  GestureAction.seekBackward:    'Seek Backward',
  GestureAction.volumeUp:        'Volume Up',
  GestureAction.volumeDown:      'Volume Down',
  GestureAction.brightnessUp:    'Brightness Up',
  GestureAction.brightnessDown:  'Brightness Down',
  GestureAction.playPause:       'Play / Pause',
  GestureAction.nextChapter:     'Next Chapter',
  GestureAction.prevChapter:     'Previous Chapter',
  GestureAction.toggleSubtitles: 'Toggle Subtitles',
  GestureAction.toggleFullscreen:'Toggle Fullscreen',
  GestureAction.lockScreen:      'Lock Screen',
  GestureAction.takeScreenshot:  'Screenshot',
  GestureAction.openSettings:    'Open Settings',
  GestureAction.none:            'None (disabled)',
};

const gestureActionIcons = <GestureAction, IconData>{
  GestureAction.seekForward:     Icons.fast_forward_rounded,
  GestureAction.seekBackward:    Icons.fast_rewind_rounded,
  GestureAction.volumeUp:        Icons.volume_up_rounded,
  GestureAction.volumeDown:      Icons.volume_down_rounded,
  GestureAction.brightnessUp:    Icons.brightness_high_rounded,
  GestureAction.brightnessDown:  Icons.brightness_low_rounded,
  GestureAction.playPause:       Icons.play_arrow_rounded,
  GestureAction.nextChapter:     Icons.skip_next_rounded,
  GestureAction.prevChapter:     Icons.skip_previous_rounded,
  GestureAction.toggleSubtitles: Icons.subtitles_rounded,
  GestureAction.toggleFullscreen:Icons.fullscreen_rounded,
  GestureAction.lockScreen:      Icons.lock_outline_rounded,
  GestureAction.takeScreenshot:  Icons.camera_alt_rounded,
  GestureAction.openSettings:    Icons.settings_rounded,
  GestureAction.none:            Icons.remove_rounded,
};

GestureAction gestureActionFromString(String s) =>
    GestureAction.values.firstWhere((a) => a.name == s, orElse: () => GestureAction.none);

// ── Gesture map config ────────────────────────────────────────────────────────
class GestureMap {
  final GestureAction swipeLeft;
  final GestureAction swipeRight;
  final GestureAction swipeUp;      // left-side swipe up
  final GestureAction swipeDown;    // left-side swipe down
  final GestureAction swipeUpRight; // right-side swipe up
  final GestureAction swipeDownRight;
  final GestureAction doubleTapLeft;
  final GestureAction doubleTapRight;
  final GestureAction doubleTapCenter;
  final GestureAction longPressLeft;
  final GestureAction longPressRight;
  final GestureAction longPressCenter;

  const GestureMap({
    this.swipeLeft          = GestureAction.seekBackward,
    this.swipeRight         = GestureAction.seekForward,
    this.swipeUp            = GestureAction.brightnessUp,
    this.swipeDown          = GestureAction.brightnessDown,
    this.swipeUpRight       = GestureAction.volumeUp,
    this.swipeDownRight     = GestureAction.volumeDown,
    this.doubleTapLeft      = GestureAction.seekBackward,
    this.doubleTapRight     = GestureAction.seekForward,
    this.doubleTapCenter    = GestureAction.playPause,
    this.longPressLeft      = GestureAction.prevChapter,
    this.longPressRight     = GestureAction.nextChapter,
    this.longPressCenter    = GestureAction.lockScreen,
  });

  String encode() => jsonEncode({
    'swL': swipeLeft.name, 'swR': swipeRight.name,
    'swU': swipeUp.name, 'swD': swipeDown.name,
    'swUR': swipeUpRight.name, 'swDR': swipeDownRight.name,
    'dtL': doubleTapLeft.name, 'dtR': doubleTapRight.name,
    'dtC': doubleTapCenter.name,
    'lpL': longPressLeft.name, 'lpR': longPressRight.name,
    'lpC': longPressCenter.name,
  });

  factory GestureMap.decode(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return GestureMap(
        swipeLeft:       gestureActionFromString(m['swL'] ?? ''),
        swipeRight:      gestureActionFromString(m['swR'] ?? ''),
        swipeUp:         gestureActionFromString(m['swU'] ?? ''),
        swipeDown:       gestureActionFromString(m['swD'] ?? ''),
        swipeUpRight:    gestureActionFromString(m['swUR'] ?? ''),
        swipeDownRight:  gestureActionFromString(m['swDR'] ?? ''),
        doubleTapLeft:   gestureActionFromString(m['dtL'] ?? ''),
        doubleTapRight:  gestureActionFromString(m['dtR'] ?? ''),
        doubleTapCenter: gestureActionFromString(m['dtC'] ?? ''),
        longPressLeft:   gestureActionFromString(m['lpL'] ?? ''),
        longPressRight:  gestureActionFromString(m['lpR'] ?? ''),
        longPressCenter: gestureActionFromString(m['lpC'] ?? ''),
      );
    } catch (_) {
      return const GestureMap();
    }
  }

  GestureMap copyWith({
    GestureAction? swipeLeft, GestureAction? swipeRight,
    GestureAction? swipeUp, GestureAction? swipeDown,
    GestureAction? swipeUpRight, GestureAction? swipeDownRight,
    GestureAction? doubleTapLeft, GestureAction? doubleTapRight,
    GestureAction? doubleTapCenter,
    GestureAction? longPressLeft, GestureAction? longPressRight,
    GestureAction? longPressCenter,
  }) => GestureMap(
    swipeLeft:       swipeLeft       ?? this.swipeLeft,
    swipeRight:      swipeRight      ?? this.swipeRight,
    swipeUp:         swipeUp         ?? this.swipeUp,
    swipeDown:       swipeDown       ?? this.swipeDown,
    swipeUpRight:    swipeUpRight    ?? this.swipeUpRight,
    swipeDownRight:  swipeDownRight  ?? this.swipeDownRight,
    doubleTapLeft:   doubleTapLeft   ?? this.doubleTapLeft,
    doubleTapRight:  doubleTapRight  ?? this.doubleTapRight,
    doubleTapCenter: doubleTapCenter ?? this.doubleTapCenter,
    longPressLeft:   longPressLeft   ?? this.longPressLeft,
    longPressRight:  longPressRight  ?? this.longPressRight,
    longPressCenter: longPressCenter ?? this.longPressCenter,
  );
}
