// Phase H5 — PlayerPrefs save()/load() round-trip test.
//
// PlayerPrefs.save() writes ~150 individually-keyed SharedPreferences
// entries and PlayerPrefs.load() reads them back by the same string keys.
// There is no compiler-checked link between the two — a typo'd key on
// either side silently falls back to the default value instead of failing,
// which has been the source of "my setting doesn't stick" bugs before.
//
// This test doesn't enumerate all ~150 fields (impractical to keep in sync
// by hand), but covers at least one field from every settings category so a
// systematic issue (e.g. a category's keys not matching between save/load)
// is caught. Extend this list when adding fields to a category not yet
// represented here.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raddflix/core/player/player_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh, empty mock SharedPreferences store for every test.
    SharedPreferences.setMockInitialValues({});
  });

  test('save() then load() returns the same non-default values (representative fields)', () async {
    const original = PlayerPrefs(
      // Gestures
      gestureEnabled: false,
      doubleTapSeekSeconds: 15,
      swipeSensitivity: 1.75,
      rageSkipSeconds: 90,
      // Controls bar
      controlBarOpacity: 0.6,
      autoHideSeconds: 5,
      // Subtitles
      subtitleFontSize: 22.5,
      subtitleEncoding: 'utf-8',
      subtitleTextColorValue: 0xFF00FF00,
      subtitlePosition: 'top',
      // Audio
      volumeBoostMultiplier: 1.5,
      equalizerPreset: 'bass',
      equalizerBands: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      // Track intelligence
      rememberAudioTrack: false,
      // Video enhancement
      brightness: 0.25,
      nightModeIntensity: 0.9,
      // Rotation
      rotationMode: 'landscape_locked',
      // Playback
      playbackSpeed: 1.75,
      nextEpisodeCountdown: 20,
      // Skip intro
      autoSkipIntroEnabled: true,
      // Transparent player
      transparentModeOpacity: 0.3,
      // Ambilight
      ambilightIntensity: 0.4,
      ambilightSampleIntervalMs: 250,
      // Binge guard
      bingeGuardThresholdMinutes: 60,
      // Sleep fade
      sleepFadeDurationSeconds: 45,
      // UI
      uiFontSize: 1.2,
      // Cinematic
      cinematicTapBehavior: 'lock_screen',
      cinematicOpacity: 0.75,
      // Appearance
      accentColorValue: 0xFF1E90FF,
      seekBarStyle: 'minimal',
      playerTheme: 'midnight_blue',
      buttonShape: 'squircle',
      iconPack: 'material3',
      controlsBgStyle: 'gradient',
      // Picture profile
      pictureProfile: 'vivid',
      // Audio lab
      vocalRemoverIntensity: 0.55,
      surroundMode: 'concert',
      bassBoostLevel: 0.8,
      // Dual subtitle / smart volume / skip
      smartVolumeTarget: 0.65,
      smartVolumeMode: 'aggressive',
      skipSilenceThresholdSecs: 2.0,
      // Colour blind / one-handed / wake
      colorBlindMode: 'deuteranopia',
      oneHandedModeSide: 'left',
      wakeTimeoutMins: 20,
      // Layout designer
      layoutPreset: 'left_handed',
      // Colour look / film grain / haptics
      colorLook: 'noir',
      filmGrainLevel: 'heavy',
      hapticLevel: 'light',
      // Speed presets / end action / smart skip
      speedPresets: '0.5,1.0,2.0',
      endAction: 'loop',
      smartSkipConfig: '5,5,80,10,100',
      // Subtitle font / secondary language
      subtitleFont: 'open_dyslexic',
      secondarySubtitleLanguage: 'ur',
      // Buffer / download quality
      bufferStrategy: 'aggressive',
      downloadQuality: 'high',
      // Channel balance / center buttons
      channelBalance: -0.5,
      centerBtnScale: 1.3,
      centerBtnPosition: 'bottom',
      quickBarItems: 'pip,speed',
      // Smart enhance
      smartEnhanceMode: 'anime',
      sidebarMode: 2,
    );

    await original.save();
    final loaded = await PlayerPrefs.load();

    expect(loaded.gestureEnabled, original.gestureEnabled);
    expect(loaded.doubleTapSeekSeconds, original.doubleTapSeekSeconds);
    expect(loaded.swipeSensitivity, original.swipeSensitivity);
    expect(loaded.rageSkipSeconds, original.rageSkipSeconds);
    expect(loaded.controlBarOpacity, original.controlBarOpacity);
    expect(loaded.autoHideSeconds, original.autoHideSeconds);
    expect(loaded.subtitleFontSize, original.subtitleFontSize);
    expect(loaded.subtitleEncoding, original.subtitleEncoding);
    expect(loaded.subtitleTextColorValue, original.subtitleTextColorValue);
    expect(loaded.subtitlePosition, original.subtitlePosition);
    expect(loaded.volumeBoostMultiplier, original.volumeBoostMultiplier);
    expect(loaded.equalizerPreset, original.equalizerPreset);
    expect(loaded.equalizerBands, original.equalizerBands);
    expect(loaded.rememberAudioTrack, original.rememberAudioTrack);
    expect(loaded.brightness, original.brightness);
    expect(loaded.nightModeIntensity, original.nightModeIntensity);
    expect(loaded.rotationMode, original.rotationMode);
    expect(loaded.playbackSpeed, original.playbackSpeed);
    expect(loaded.nextEpisodeCountdown, original.nextEpisodeCountdown);
    expect(loaded.autoSkipIntroEnabled, original.autoSkipIntroEnabled);
    expect(loaded.transparentModeOpacity, original.transparentModeOpacity);
    expect(loaded.ambilightIntensity, original.ambilightIntensity);
    expect(loaded.ambilightSampleIntervalMs, original.ambilightSampleIntervalMs);
    expect(loaded.bingeGuardThresholdMinutes, original.bingeGuardThresholdMinutes);
    expect(loaded.sleepFadeDurationSeconds, original.sleepFadeDurationSeconds);
    expect(loaded.uiFontSize, original.uiFontSize);
    expect(loaded.cinematicTapBehavior, original.cinematicTapBehavior);
    expect(loaded.cinematicOpacity, original.cinematicOpacity);
    expect(loaded.accentColorValue, original.accentColorValue);
    expect(loaded.seekBarStyle, original.seekBarStyle);
    expect(loaded.playerTheme, original.playerTheme);
    expect(loaded.buttonShape, original.buttonShape);
    expect(loaded.iconPack, original.iconPack);
    expect(loaded.controlsBgStyle, original.controlsBgStyle);
    expect(loaded.pictureProfile, original.pictureProfile);
    expect(loaded.vocalRemoverIntensity, original.vocalRemoverIntensity);
    expect(loaded.surroundMode, original.surroundMode);
    expect(loaded.bassBoostLevel, original.bassBoostLevel);
    expect(loaded.smartVolumeTarget, original.smartVolumeTarget);
    expect(loaded.smartVolumeMode, original.smartVolumeMode);
    expect(loaded.skipSilenceThresholdSecs, original.skipSilenceThresholdSecs);
    expect(loaded.colorBlindMode, original.colorBlindMode);
    expect(loaded.oneHandedModeSide, original.oneHandedModeSide);
    expect(loaded.wakeTimeoutMins, original.wakeTimeoutMins);
    expect(loaded.layoutPreset, original.layoutPreset);
    expect(loaded.colorLook, original.colorLook);
    expect(loaded.filmGrainLevel, original.filmGrainLevel);
    expect(loaded.hapticLevel, original.hapticLevel);
    expect(loaded.speedPresets, original.speedPresets);
    expect(loaded.endAction, original.endAction);
    expect(loaded.smartSkipConfig, original.smartSkipConfig);
    expect(loaded.subtitleFont, original.subtitleFont);
    expect(loaded.secondarySubtitleLanguage, original.secondarySubtitleLanguage);
    expect(loaded.bufferStrategy, original.bufferStrategy);
    expect(loaded.downloadQuality, original.downloadQuality);
    expect(loaded.channelBalance, original.channelBalance);
    expect(loaded.centerBtnScale, original.centerBtnScale);
    expect(loaded.centerBtnPosition, original.centerBtnPosition);
    expect(loaded.quickBarItems, original.quickBarItems);
    expect(loaded.smartEnhanceMode, original.smartEnhanceMode);
    expect(loaded.sidebarMode, original.sidebarMode);
  });

  test('load() with no prior save() returns the documented defaults', () async {
    final loaded = await PlayerPrefs.load();
    const defaults = PlayerPrefs();

    expect(loaded.gestureEnabled, defaults.gestureEnabled);
    expect(loaded.playbackSpeed, defaults.playbackSpeed);
    expect(loaded.subtitlePosition, defaults.subtitlePosition);
    expect(loaded.accentColorValue, defaults.accentColorValue);
    expect(loaded.playerTheme, defaults.playerTheme);
  });

  test('accentColor getter converts accentColorValue to a Color', () {
    const prefs = PlayerPrefs(accentColorValue: 0xFF112233);
    expect(prefs.accentColor.value, 0xFF112233);
  });

  test('audioDelay getter converts audioTimingOffsetMs to seconds', () {
    const prefs = PlayerPrefs(audioTimingOffsetMs: 250);
    expect(prefs.audioDelay, closeTo(0.25, 1e-9));
  });
}
