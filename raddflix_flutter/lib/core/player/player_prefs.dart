import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All player settings — loaded from SharedPreferences, saved on every change.
/// Defaults are sensible for first-time users.
class PlayerPrefs {
  static const _p = 'player_';

  // ── GESTURES ─────────────────────────────────────────────────────────────
  final bool gestureEnabled;
  final bool swipeBrightnessEnabled;
  final bool swipeVolumeEnabled;
  final bool swipeSeekEnabled;
  final bool doubleTapSeekEnabled;
  final int  doubleTapSeekSeconds;
  final bool longPressSpeedEnabled;
  final double longPressSpeed;
  final bool pinchZoomEnabled;
  final double swipeSensitivity;
  final double seekSensitivity;
  final bool rageSkipEnabled;
  final int  rageSkipSeconds;

  // ── CONTROLS BAR ─────────────────────────────────────────────────────────
  final double buttonSize;
  final double controlBarOpacity;
  final int    autoHideSeconds;
  final bool   tapTimeToToggleRemaining;
  final bool   showBufferBar;

  // ── SUBTITLES ─────────────────────────────────────────────────────────────
  final bool   subtitleEnabled;
  final double subtitleFontSize;
  final int    subtitleTimingOffsetMs;
  final String subtitleEncoding;
  final bool   subtitleBold;
  final bool   subtitleItalic;
  final String subtitleFontFamily;
  final double subtitleOutlineThickness;
  final int    subtitleTextColorValue;
  final int    subtitleOutlineColorValue;
  final int    subtitleBackgroundColorValue;
  final double subtitleBackgroundOpacity;
  final String subtitlePosition;
  final double subtitleVerticalOffset;
  final bool   subtitleAutoDetect;

  // ── AUDIO ─────────────────────────────────────────────────────────────────
  final int    audioTimingOffsetMs;
  final double volumeBoostMultiplier;
  final bool   equalizerEnabled;
  final String equalizerPreset;
  final List<double> equalizerBands;
  final bool   dialogueBoostEnabled;
  final bool   audioNormalization;
  final bool   deinterlaceEnabled;

  // ── TRACK INTELLIGENCE ───────────────────────────────────────────────────
  final bool rememberAudioTrack;
  final bool rememberSubtitleTrack;
  final bool autoSelectAudioByLocale;
  final bool showActiveTrackBadge;
  final bool showTrackCountBadge;

  // ── VIDEO ENHANCEMENT ────────────────────────────────────────────────────
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final bool   nightMode;
  final double nightModeIntensity;
  final bool   sharpnessEnabled;
  final double sharpness;

  // ── ROTATION ─────────────────────────────────────────────────────────────
  final String rotationMode;

  // ── PLAYBACK ─────────────────────────────────────────────────────────────
  final double playbackSpeed;
  final bool   rememberSpeed;
  final bool   rememberPosition;
  final bool   autoPlayNext;
  final int    nextEpisodeCountdown;
  final bool   hwDecoderEnabled;
  final bool   backgroundPlayEnabled;
  final int    seekBackOnResumeSeconds;
  final bool   longPressPlayRestart;

  // ── SKIP INTRO ───────────────────────────────────────────────────────────
  final bool autoSkipIntroEnabled;
  final bool showSkipIntroButton;

  // ── TRANSPARENT PLAYER ───────────────────────────────────────────────────
  final bool   transparentModeEnabled;
  final double transparentModeOpacity;

  // ── AMBILIGHT ────────────────────────────────────────────────────────────
  final bool   ambilightEnabled;
  final double ambilightIntensity;
  final int    ambilightSampleIntervalMs;
  final double ambilightBlurRadius;

  // ── BINGE GUARD ──────────────────────────────────────────────────────────
  final bool bingeGuardEnabled;
  final int  bingeGuardThresholdMinutes;

  // ── SLEEP FADE ───────────────────────────────────────────────────────────
  final bool sleepFadeEnabled;
  final int  sleepFadeDurationSeconds;

  // ── UI ───────────────────────────────────────────────────────────────────
  final bool   showNetworkSpeed;
  final bool   showDecoderInfo;
  final bool   showPlaybackInfo;
  final bool   showEpisodeInfo;
  final bool   vibrateOnGesture;
  final double uiFontSize;

  // ── BOOKMARKS ─────────────────────────────────────────────────────────────
  final bool bookmarkVibrate;

  // ── CINEMATIC ─────────────────────────────────────────────────────────────
  final bool   cinematicModeOnLock;
  final bool   gesturesInCinematic;
  final String cinematicTapBehavior;

  // ── TRANSPARENT (extra) ───────────────────────────────────────────────────
  final bool transparentModeFrosted;

  // ── APPEARANCE CUSTOMISATION ──────────────────────────────────────────────
  /// ARGB int for the player accent colour. Default: RaddFlix red.
  final int    accentColorValue;
  /// SeekBarStyle enum name (see seek_bar_painter.dart). Default: 'classic'.
  final String seekBarStyle;
  /// PlayerTheme id (see player_theme.dart). Default: 'raddflix_red'.
  final String playerTheme;

  // ── Phase A3: Button & Icon Style ──────────────────────────────────────
  /// Button shape: 'circle' | 'squircle' | 'rounded' | 'sharp' | 'pill'
  final String buttonShape;
  /// Icon pack: 'mx' | 'ios' | 'fluent' | 'material3' | 'cute' | 'minimal'
  final String iconPack;

  // ── Phase A4: Controls Background ────────────────────────────────────────
  /// Controls bg style: 'none' | 'glass' | 'gradient' | 'solid' | 'mesh'
  final String controlsBgStyle;

  // ── Phase C: Gesture Action Map ──────────────────────────────────────────
  /// JSON-encoded Map<String,String> of gesture zone → action key.
  final String gestureActionMapJson;

  // ── Phase D1: Picture Profile ─────────────────────────────────────────────
  /// Active picture profile id: 'natural'|'cinema'|'vivid'|'night'|'anime'|'amoled'
  final String pictureProfile;

  // ── Phase E: Audio Lab ────────────────────────────────────────────────────
  final bool   vocalRemoverEnabled;
  final double vocalRemoverIntensity;
  final bool   surroundEnabled;
  final String surroundMode;
  final bool   bassBoostEnabled;
  final double bassBoostLevel;

  // ── Phase F1: Dual Subtitle ───────────────────────────────────────────────
  final bool   dualSubtitleEnabled;
  final bool   smartVolumeLevelingEnabled;
  final double smartVolumeTarget;  // 0.0–1.0 (maps to 0–100 MPV vol)
  final String smartVolumeMode;    // gentle | balanced | aggressive
  final bool   skipSilenceEnabled;
  final double skipSilenceThresholdSecs; // 0.5–5.0 seconds
  final bool   skipBlackFramesEnabled;
  final String customSpeedPresetsJson;   // JSON-encoded List<double>
  final String endOfVideoAction;         // play_next|loop|return_home|nothing
  final String colorBlindMode;           // none|deuteranopia|protanopia|tritanopia
  final bool   oneHandedModeEnabled;
  final String oneHandedModeSide;        // right|left

  /// Convenience getter — converts [accentColorValue] to a [Color].
  Color get accentColor => Color(accentColorValue);

  /// Convenience getter — audio delay as seconds (double).
  double get audioDelay => audioTimingOffsetMs / 1000.0;

  const PlayerPrefs({
    this.gestureEnabled = true,
    this.swipeBrightnessEnabled = true,
    this.swipeVolumeEnabled = true,
    this.swipeSeekEnabled = true,
    this.doubleTapSeekEnabled = true,
    this.doubleTapSeekSeconds = 10,
    this.longPressSpeedEnabled = true,
    this.longPressSpeed = 2.0,
    this.pinchZoomEnabled = true,
    this.swipeSensitivity = 1.0,
    this.seekSensitivity = 1.0,
    this.rageSkipEnabled = true,
    this.rageSkipSeconds = 120,
    this.buttonSize = 1.0,
    this.controlBarOpacity = 0.85,
    this.autoHideSeconds = 3,
    this.tapTimeToToggleRemaining = true,
    this.showBufferBar = true,
    this.subtitleEnabled = true,
    this.subtitleFontSize = 18.0,
    this.subtitleTimingOffsetMs = 0,
    this.subtitleEncoding = 'auto',
    this.subtitleBold = false,
    this.subtitleItalic = false,
    this.subtitleFontFamily = 'Sans-Serif',
    this.subtitleOutlineThickness = 2.0,
    this.subtitleTextColorValue = 0xFFFFFFFF,
    this.subtitleOutlineColorValue = 0xFF000000,
    this.subtitleBackgroundColorValue = 0xFF000000,
    this.subtitleBackgroundOpacity = 0.0,
    this.subtitlePosition = 'bottom',
    this.subtitleVerticalOffset = 0.1,
    this.subtitleAutoDetect = false,
    this.audioTimingOffsetMs = 0,
    this.volumeBoostMultiplier = 1.0,
    this.equalizerEnabled = false,
    this.equalizerPreset = 'flat',
    this.equalizerBands = const [0,0,0,0,0,0,0,0,0,0],
    this.dialogueBoostEnabled = false,
    this.audioNormalization = false,
    this.deinterlaceEnabled = false,
    this.rememberAudioTrack = true,
    this.rememberSubtitleTrack = true,
    this.autoSelectAudioByLocale = true,
    this.showActiveTrackBadge = true,
    this.showTrackCountBadge = true,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.hue = 0.0,
    this.nightMode = false,
    this.nightModeIntensity = 0.5,
    this.sharpnessEnabled = false,
    this.sharpness = 0.3,
    this.rotationMode = 'sensor_landscape',
    this.playbackSpeed = 1.0,
    this.rememberSpeed = false,
    this.rememberPosition = true,
    this.autoPlayNext = true,
    this.nextEpisodeCountdown = 10,
    this.hwDecoderEnabled = true,
    this.backgroundPlayEnabled = true,
    this.seekBackOnResumeSeconds = 5,
    this.longPressPlayRestart = false,
    this.autoSkipIntroEnabled = false,
    this.showSkipIntroButton = true,
    this.transparentModeEnabled = false,
    this.transparentModeOpacity = 0.5,
    this.ambilightEnabled = false,
    this.ambilightIntensity = 0.7,
    this.ambilightSampleIntervalMs = 400,
    this.ambilightBlurRadius = 24.0,
    this.bingeGuardEnabled = false,
    this.bingeGuardThresholdMinutes = 120,
    this.sleepFadeEnabled = true,
    this.sleepFadeDurationSeconds = 30,
    this.showNetworkSpeed = false,
    this.showDecoderInfo = false,
    this.showPlaybackInfo = false,
    this.showEpisodeInfo = true,
    this.vibrateOnGesture = true,
    this.uiFontSize = 1.0,
    this.bookmarkVibrate = true,
    this.cinematicModeOnLock = false,
    this.gesturesInCinematic = true,
    this.cinematicTapBehavior = 'pause_resume',
    this.transparentModeFrosted = false,
    this.accentColorValue = 0xFFE8002D,
    this.seekBarStyle = 'classic',
    this.playerTheme = 'raddflix_red',
    this.buttonShape = 'circle',
    this.iconPack = 'mx',
    this.controlsBgStyle = 'none',
    this.gestureActionMapJson = '',
    this.pictureProfile = 'natural',
    this.vocalRemoverEnabled = false,
    this.vocalRemoverIntensity = 0.75,
    this.surroundEnabled = false,
    this.surroundMode = 'theater',
    this.bassBoostEnabled = false,
    this.bassBoostLevel = 0.5,
    this.dualSubtitleEnabled       = false,
    this.smartVolumeLevelingEnabled = false,
    this.smartVolumeTarget          = 0.80,
    this.smartVolumeMode            = 'balanced',
    this.skipSilenceEnabled         = false,
    this.skipSilenceThresholdSecs   = 1.5,
    this.skipBlackFramesEnabled     = false,
    this.customSpeedPresetsJson     = '',
    this.endOfVideoAction           = 'play_next',
    this.colorBlindMode             = 'none',
    this.oneHandedModeEnabled       = false,
    this.oneHandedModeSide          = 'right',
  });

  PlayerPrefs copyWith({
    bool? gestureEnabled, bool? swipeBrightnessEnabled, bool? swipeVolumeEnabled,
    bool? swipeSeekEnabled, bool? doubleTapSeekEnabled, int? doubleTapSeekSeconds,
    bool? longPressSpeedEnabled, double? longPressSpeed, bool? pinchZoomEnabled,
    double? swipeSensitivity, double? seekSensitivity,
    bool? rageSkipEnabled, int? rageSkipSeconds,
    double? buttonSize, double? controlBarOpacity, int? autoHideSeconds,
    bool? tapTimeToToggleRemaining, bool? showBufferBar,
    bool? subtitleEnabled, double? subtitleFontSize, int? subtitleTimingOffsetMs,
    String? subtitleEncoding, bool? subtitleBold, bool? subtitleItalic,
    String? subtitleFontFamily, double? subtitleOutlineThickness,
    int? subtitleTextColorValue, int? subtitleOutlineColorValue, int? subtitleBackgroundColorValue,
    double? subtitleBackgroundOpacity, String? subtitlePosition,
    double? subtitleVerticalOffset, bool? subtitleAutoDetect,
    int? audioTimingOffsetMs, double? volumeBoostMultiplier,
    bool? equalizerEnabled, String? equalizerPreset, List<double>? equalizerBands,
    bool? dialogueBoostEnabled, bool? audioNormalization, bool? deinterlaceEnabled,
    bool? rememberAudioTrack, bool? rememberSubtitleTrack,
    bool? autoSelectAudioByLocale, bool? showActiveTrackBadge, bool? showTrackCountBadge,
    double? brightness, double? contrast, double? saturation, double? hue,
    bool? nightMode, double? nightModeIntensity,
    bool? sharpnessEnabled, double? sharpness,
    String? rotationMode,
    double? playbackSpeed, bool? rememberSpeed, bool? rememberPosition,
    bool? autoPlayNext, int? nextEpisodeCountdown,
    bool? hwDecoderEnabled, bool? backgroundPlayEnabled,
    int? seekBackOnResumeSeconds, bool? longPressPlayRestart,
    bool? autoSkipIntroEnabled, bool? showSkipIntroButton,
    bool? transparentModeEnabled, double? transparentModeOpacity,
    bool? ambilightEnabled, double? ambilightIntensity, int? ambilightSampleIntervalMs, double? ambilightBlurRadius,
    bool? bingeGuardEnabled, int? bingeGuardThresholdMinutes,
    bool? sleepFadeEnabled, int? sleepFadeDurationSeconds,
    bool? showNetworkSpeed, bool? showDecoderInfo, bool? showPlaybackInfo,
    bool? showEpisodeInfo, bool? vibrateOnGesture, double? uiFontSize,
    bool? bookmarkVibrate, bool? cinematicModeOnLock, bool? gesturesInCinematic,
    String? cinematicTapBehavior, bool? transparentModeFrosted,
    int? accentColorValue, String? seekBarStyle, String? playerTheme,
    String? buttonShape, String? iconPack, String? controlsBgStyle,
    String? gestureActionMapJson, String? pictureProfile,
    bool? vocalRemoverEnabled, double? vocalRemoverIntensity,
    bool? surroundEnabled, String? surroundMode,
    bool? bassBoostEnabled, double? bassBoostLevel,
    bool? dualSubtitleEnabled,
    bool?   smartVolumeLevelingEnabled,
    double? smartVolumeTarget,
    String? smartVolumeMode,
    bool?   skipSilenceEnabled,
    double? skipSilenceThresholdSecs,
    bool?   skipBlackFramesEnabled,
    String? customSpeedPresetsJson,
    String? endOfVideoAction,
    String? colorBlindMode,
    bool?   oneHandedModeEnabled,
    String? oneHandedModeSide,
  }) => PlayerPrefs(
    gestureEnabled: gestureEnabled ?? this.gestureEnabled,
    swipeBrightnessEnabled: swipeBrightnessEnabled ?? this.swipeBrightnessEnabled,
    swipeVolumeEnabled: swipeVolumeEnabled ?? this.swipeVolumeEnabled,
    swipeSeekEnabled: swipeSeekEnabled ?? this.swipeSeekEnabled,
    doubleTapSeekEnabled: doubleTapSeekEnabled ?? this.doubleTapSeekEnabled,
    doubleTapSeekSeconds: doubleTapSeekSeconds ?? this.doubleTapSeekSeconds,
    longPressSpeedEnabled: longPressSpeedEnabled ?? this.longPressSpeedEnabled,
    longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    pinchZoomEnabled: pinchZoomEnabled ?? this.pinchZoomEnabled,
    swipeSensitivity: swipeSensitivity ?? this.swipeSensitivity,
    seekSensitivity: seekSensitivity ?? this.seekSensitivity,
    rageSkipEnabled: rageSkipEnabled ?? this.rageSkipEnabled,
    rageSkipSeconds: rageSkipSeconds ?? this.rageSkipSeconds,
    buttonSize: buttonSize ?? this.buttonSize,
    controlBarOpacity: controlBarOpacity ?? this.controlBarOpacity,
    autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
    tapTimeToToggleRemaining: tapTimeToToggleRemaining ?? this.tapTimeToToggleRemaining,
    showBufferBar: showBufferBar ?? this.showBufferBar,
    subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
    subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
    subtitleTimingOffsetMs: subtitleTimingOffsetMs ?? this.subtitleTimingOffsetMs,
    subtitleEncoding: subtitleEncoding ?? this.subtitleEncoding,
    subtitleBold: subtitleBold ?? this.subtitleBold,
    subtitleItalic: subtitleItalic ?? this.subtitleItalic,
    subtitleFontFamily: subtitleFontFamily ?? this.subtitleFontFamily,
    subtitleOutlineThickness: subtitleOutlineThickness ?? this.subtitleOutlineThickness,
    subtitleTextColorValue: subtitleTextColorValue ?? this.subtitleTextColorValue,
    subtitleOutlineColorValue: subtitleOutlineColorValue ?? this.subtitleOutlineColorValue,
    subtitleBackgroundColorValue: subtitleBackgroundColorValue ?? this.subtitleBackgroundColorValue,
    subtitleBackgroundOpacity: subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
    subtitlePosition: subtitlePosition ?? this.subtitlePosition,
    subtitleVerticalOffset: subtitleVerticalOffset ?? this.subtitleVerticalOffset,
    subtitleAutoDetect: subtitleAutoDetect ?? this.subtitleAutoDetect,
    audioTimingOffsetMs: audioTimingOffsetMs ?? this.audioTimingOffsetMs,
    volumeBoostMultiplier: volumeBoostMultiplier ?? this.volumeBoostMultiplier,
    equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
    equalizerPreset: equalizerPreset ?? this.equalizerPreset,
    equalizerBands: equalizerBands ?? this.equalizerBands,
    dialogueBoostEnabled: dialogueBoostEnabled ?? this.dialogueBoostEnabled,
    audioNormalization: audioNormalization ?? this.audioNormalization,
    deinterlaceEnabled: deinterlaceEnabled ?? this.deinterlaceEnabled,
    rememberAudioTrack: rememberAudioTrack ?? this.rememberAudioTrack,
    rememberSubtitleTrack: rememberSubtitleTrack ?? this.rememberSubtitleTrack,
    autoSelectAudioByLocale: autoSelectAudioByLocale ?? this.autoSelectAudioByLocale,
    showActiveTrackBadge: showActiveTrackBadge ?? this.showActiveTrackBadge,
    showTrackCountBadge: showTrackCountBadge ?? this.showTrackCountBadge,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    hue: hue ?? this.hue,
    nightMode: nightMode ?? this.nightMode,
    nightModeIntensity: nightModeIntensity ?? this.nightModeIntensity,
    sharpnessEnabled: sharpnessEnabled ?? this.sharpnessEnabled,
    sharpness: sharpness ?? this.sharpness,
    rotationMode: rotationMode ?? this.rotationMode,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    rememberSpeed: rememberSpeed ?? this.rememberSpeed,
    rememberPosition: rememberPosition ?? this.rememberPosition,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    nextEpisodeCountdown: nextEpisodeCountdown ?? this.nextEpisodeCountdown,
    hwDecoderEnabled: hwDecoderEnabled ?? this.hwDecoderEnabled,
    backgroundPlayEnabled: backgroundPlayEnabled ?? this.backgroundPlayEnabled,
    seekBackOnResumeSeconds: seekBackOnResumeSeconds ?? this.seekBackOnResumeSeconds,
    longPressPlayRestart: longPressPlayRestart ?? this.longPressPlayRestart,
    autoSkipIntroEnabled: autoSkipIntroEnabled ?? this.autoSkipIntroEnabled,
    showSkipIntroButton: showSkipIntroButton ?? this.showSkipIntroButton,
    transparentModeEnabled: transparentModeEnabled ?? this.transparentModeEnabled,
    transparentModeOpacity: transparentModeOpacity ?? this.transparentModeOpacity,
    ambilightEnabled: ambilightEnabled ?? this.ambilightEnabled,
    ambilightIntensity: ambilightIntensity ?? this.ambilightIntensity,
    ambilightSampleIntervalMs: ambilightSampleIntervalMs ?? this.ambilightSampleIntervalMs,
    ambilightBlurRadius: ambilightBlurRadius ?? this.ambilightBlurRadius,
    bingeGuardEnabled: bingeGuardEnabled ?? this.bingeGuardEnabled,
    bingeGuardThresholdMinutes: bingeGuardThresholdMinutes ?? this.bingeGuardThresholdMinutes,
    sleepFadeEnabled: sleepFadeEnabled ?? this.sleepFadeEnabled,
    sleepFadeDurationSeconds: sleepFadeDurationSeconds ?? this.sleepFadeDurationSeconds,
    showNetworkSpeed: showNetworkSpeed ?? this.showNetworkSpeed,
    showDecoderInfo: showDecoderInfo ?? this.showDecoderInfo,
    showPlaybackInfo: showPlaybackInfo ?? this.showPlaybackInfo,
    showEpisodeInfo: showEpisodeInfo ?? this.showEpisodeInfo,
    vibrateOnGesture: vibrateOnGesture ?? this.vibrateOnGesture,
    uiFontSize: uiFontSize ?? this.uiFontSize,
    bookmarkVibrate: bookmarkVibrate ?? this.bookmarkVibrate,
    cinematicModeOnLock: cinematicModeOnLock ?? this.cinematicModeOnLock,
    gesturesInCinematic: gesturesInCinematic ?? this.gesturesInCinematic,
    cinematicTapBehavior: cinematicTapBehavior ?? this.cinematicTapBehavior,
    transparentModeFrosted: transparentModeFrosted ?? this.transparentModeFrosted,
    accentColorValue: accentColorValue ?? this.accentColorValue,
    seekBarStyle: seekBarStyle ?? this.seekBarStyle,
    playerTheme: playerTheme ?? this.playerTheme,
    buttonShape: buttonShape ?? this.buttonShape,
    iconPack: iconPack ?? this.iconPack,
    controlsBgStyle: controlsBgStyle ?? this.controlsBgStyle,
    gestureActionMapJson: gestureActionMapJson ?? this.gestureActionMapJson,
    pictureProfile: pictureProfile ?? this.pictureProfile,
    vocalRemoverEnabled: vocalRemoverEnabled ?? this.vocalRemoverEnabled,
    vocalRemoverIntensity: vocalRemoverIntensity ?? this.vocalRemoverIntensity,
    surroundEnabled: surroundEnabled ?? this.surroundEnabled,
    surroundMode: surroundMode ?? this.surroundMode,
    bassBoostEnabled: bassBoostEnabled ?? this.bassBoostEnabled,
    bassBoostLevel: bassBoostLevel ?? this.bassBoostLevel,
    dualSubtitleEnabled: dualSubtitleEnabled ?? this.dualSubtitleEnabled,
      smartVolumeLevelingEnabled: smartVolumeLevelingEnabled ?? this.smartVolumeLevelingEnabled,
      smartVolumeTarget:          smartVolumeTarget          ?? this.smartVolumeTarget,
      smartVolumeMode:            smartVolumeMode            ?? this.smartVolumeMode,
      skipSilenceEnabled:         skipSilenceEnabled         ?? this.skipSilenceEnabled,
      skipSilenceThresholdSecs:   skipSilenceThresholdSecs   ?? this.skipSilenceThresholdSecs,
      skipBlackFramesEnabled:     skipBlackFramesEnabled     ?? this.skipBlackFramesEnabled,
      customSpeedPresetsJson:     customSpeedPresetsJson     ?? this.customSpeedPresetsJson,
      endOfVideoAction:           endOfVideoAction           ?? this.endOfVideoAction,
      colorBlindMode:             colorBlindMode             ?? this.colorBlindMode,
      oneHandedModeEnabled:       oneHandedModeEnabled       ?? this.oneHandedModeEnabled,
      oneHandedModeSide:          oneHandedModeSide          ?? this.oneHandedModeSide,
  );

  // ── Load from SharedPreferences ─────────────────────────────────────────

  static Future<PlayerPrefs> load() async {
    final s = await SharedPreferences.getInstance();

    List<double> bands;
    try {
      final raw = s.getString('${_p}eq_bands');
      bands = raw == null
          ? List.filled(10, 0.0)
          : (jsonDecode(raw) as List).map((e) => (e as num).toDouble()).toList();
      if (bands.length != 10) bands = List.filled(10, 0.0);
    } catch (_) {
      bands = List.filled(10, 0.0);
    }

    return PlayerPrefs(
      gestureEnabled:         s.getBool('${_p}gesture_enabled')   ?? true,
      swipeBrightnessEnabled: s.getBool('${_p}swipe_brightness')  ?? true,
      swipeVolumeEnabled:     s.getBool('${_p}swipe_volume')      ?? true,
      swipeSeekEnabled:       s.getBool('${_p}swipe_seek')        ?? true,
      doubleTapSeekEnabled:   s.getBool('${_p}dt_seek_enabled')   ?? true,
      doubleTapSeekSeconds:   s.getInt('${_p}dt_seek_secs')       ?? 10,
      longPressSpeedEnabled:  s.getBool('${_p}lp_speed_enabled')  ?? true,
      longPressSpeed:         s.getDouble('${_p}lp_speed')        ?? 2.0,
      pinchZoomEnabled:       s.getBool('${_p}pinch_zoom')        ?? true,
      swipeSensitivity:       s.getDouble('${_p}swipe_sens')      ?? 1.0,
      seekSensitivity:        s.getDouble('${_p}seek_sens')       ?? 1.0,
      rageSkipEnabled:        s.getBool('${_p}rage_skip_enabled') ?? true,
      rageSkipSeconds:        s.getInt('${_p}rage_skip_secs')     ?? 120,
      buttonSize:             s.getDouble('${_p}btn_size')        ?? 1.0,
      controlBarOpacity:      s.getDouble('${_p}bar_opacity')     ?? 0.85,
      autoHideSeconds:        s.getInt('${_p}auto_hide_secs')     ?? 3,
      tapTimeToToggleRemaining: s.getBool('${_p}tap_time_toggle') ?? true,
      showBufferBar:          s.getBool('${_p}show_buffer_bar')   ?? true,
      subtitleEnabled:        s.getBool('${_p}sub_enabled')       ?? true,
      subtitleFontSize:       s.getDouble('${_p}sub_font_size')   ?? 18.0,
      subtitleTimingOffsetMs: s.getInt('${_p}sub_timing_ms')      ?? 0,
      subtitleEncoding:       s.getString('${_p}sub_encoding')    ?? 'auto',
      subtitleBold:           s.getBool('${_p}sub_bold')          ?? false,
      subtitleItalic:         s.getBool('${_p}sub_italic')        ?? false,
      subtitleFontFamily:     s.getString('${_p}sub_font_family') ?? 'Sans-Serif',
      subtitleOutlineThickness: s.getDouble('${_p}sub_outline')   ?? 2.0,
      subtitleTextColorValue: s.getInt('${_p}sub_text_color')     ?? 0xFFFFFFFF,
      subtitleOutlineColorValue: s.getInt('${_p}sub_outline_color') ?? 0xFF000000,
      subtitleBackgroundColorValue: s.getInt('${_p}sub_bg_color') ?? 0xFF000000,
      subtitleBackgroundOpacity: s.getDouble('${_p}sub_bg_opacity') ?? 0.0,
      subtitlePosition:       s.getString('${_p}sub_position')    ?? 'bottom',
      subtitleVerticalOffset: s.getDouble('${_p}sub_v_offset')    ?? 0.1,
      subtitleAutoDetect:     s.getBool('${_p}sub_auto_detect')   ?? false,
      audioTimingOffsetMs:    s.getInt('${_p}audio_timing_ms')    ?? 0,
      volumeBoostMultiplier:  s.getDouble('${_p}vol_boost')       ?? 1.0,
      equalizerEnabled:       s.getBool('${_p}eq_enabled')        ?? false,
      equalizerPreset:        s.getString('${_p}eq_preset')       ?? 'flat',
      equalizerBands:         bands,
      dialogueBoostEnabled:   s.getBool('${_p}dialogue_boost')    ?? false,
      audioNormalization:     s.getBool('${_p}audio_norm')        ?? false,
      deinterlaceEnabled:     s.getBool('${_p}deinterlace')       ?? false,
      rememberAudioTrack:     s.getBool('${_p}remember_audio')    ?? true,
      rememberSubtitleTrack:  s.getBool('${_p}remember_sub')      ?? true,
      autoSelectAudioByLocale: s.getBool('${_p}auto_locale')      ?? true,
      showActiveTrackBadge:   s.getBool('${_p}track_badge')       ?? true,
      showTrackCountBadge:    s.getBool('${_p}track_count_badge') ?? true,
      brightness:             s.getDouble('${_p}vid_brightness')  ?? 0.0,
      contrast:               s.getDouble('${_p}vid_contrast')    ?? 0.0,
      saturation:             s.getDouble('${_p}vid_saturation')  ?? 0.0,
      hue:                    s.getDouble('${_p}vid_hue')         ?? 0.0,
      nightMode:              s.getBool('${_p}night_mode')        ?? false,
      nightModeIntensity:     s.getDouble('${_p}night_intensity') ?? 0.5,
      sharpnessEnabled:       s.getBool('${_p}sharpness_enabled') ?? false,
      sharpness:              s.getDouble('${_p}sharpness')       ?? 0.3,
      rotationMode:           s.getString('${_p}rotation_mode')   ?? 'sensor_landscape',
      playbackSpeed:          s.getDouble('${_p}speed')           ?? 1.0,
      rememberSpeed:          s.getBool('${_p}remember_speed')    ?? false,
      rememberPosition:       s.getBool('${_p}remember_pos')      ?? true,
      autoPlayNext:           s.getBool('${_p}auto_play_next')    ?? true,
      nextEpisodeCountdown:   s.getInt('${_p}next_ep_countdown')  ?? 10,
      hwDecoderEnabled:       s.getBool('${_p}hw_decoder')        ?? true,
      backgroundPlayEnabled:  s.getBool('${_p}bg_play')           ?? true,
      seekBackOnResumeSeconds: s.getInt('${_p}seek_back_resume')  ?? 5,
      longPressPlayRestart:   s.getBool('${_p}lp_restart')        ?? false,
      autoSkipIntroEnabled:   s.getBool('${_p}auto_skip_intro')   ?? false,
      showSkipIntroButton:    s.getBool('${_p}show_skip_intro')   ?? true,
      transparentModeEnabled: s.getBool('${_p}transparent_mode')  ?? false,
      transparentModeOpacity: s.getDouble('${_p}transparent_opacity') ?? 0.5,
      ambilightEnabled:       s.getBool('${_p}ambilight')         ?? false,
      ambilightIntensity:     s.getDouble('${_p}ambilight_intensity') ?? 0.7,
      ambilightSampleIntervalMs: s.getInt('${_p}ambilight_interval') ?? 400,
      ambilightBlurRadius:    s.getDouble('${_p}ambilight_blur_radius') ?? 24.0,
      bingeGuardEnabled:      s.getBool('${_p}binge_guard')       ?? false,
      bingeGuardThresholdMinutes: s.getInt('${_p}binge_threshold') ?? 120,
      sleepFadeEnabled:       s.getBool('${_p}sleep_fade')        ?? true,
      sleepFadeDurationSeconds: s.getInt('${_p}sleep_fade_secs')  ?? 30,
      showNetworkSpeed:       s.getBool('${_p}show_net_speed')    ?? false,
      showDecoderInfo:        s.getBool('${_p}show_decoder')      ?? false,
      showPlaybackInfo:       s.getBool('${_p}show_playback_info') ?? false,
      showEpisodeInfo:        s.getBool('${_p}show_episode_info') ?? true,
      vibrateOnGesture:       s.getBool('${_p}vibrate_gesture')   ?? true,
      uiFontSize:             s.getDouble('${_p}ui_font_size')    ?? 1.0,
      bookmarkVibrate:        s.getBool('${_p}bookmark_vibrate')  ?? true,
      cinematicModeOnLock:    s.getBool('${_p}cinematic_on_lock') ?? false,
      gesturesInCinematic:    s.getBool('${_p}gestures_cinematic') ?? true,
      cinematicTapBehavior:   s.getString('${_p}cinematic_tap')   ?? 'pause_resume',
      transparentModeFrosted: s.getBool('${_p}transparent_frosted') ?? false,
      accentColorValue:       s.getInt('${_p}accent_color')       ?? 0xFFE8002D,
      seekBarStyle:           s.getString('${_p}seek_bar_style')  ?? 'classic',
      playerTheme:            s.getString('${_p}player_theme')    ?? 'raddflix_red',
      buttonShape:            s.getString('${_p}button_shape')     ?? 'circle',
      iconPack:               s.getString('${_p}icon_pack')        ?? 'mx',
      controlsBgStyle:        s.getString('${_p}controls_bg')      ?? 'none',
      gestureActionMapJson:   s.getString('${_p}gesture_map_json')  ?? '',
      pictureProfile:         s.getString('${_p}picture_profile')   ?? 'natural',
      vocalRemoverEnabled:    s.getBool('${_p}vocal_remover')       ?? false,
      vocalRemoverIntensity:  s.getDouble('${_p}vocal_intensity')   ?? 0.75,
      surroundEnabled:        s.getBool('${_p}surround')            ?? false,
      surroundMode:           s.getString('${_p}surround_mode')     ?? 'theater',
      bassBoostEnabled:       s.getBool('${_p}bass_boost')          ?? false,
      bassBoostLevel:         s.getDouble('${_p}bass_level')        ?? 0.5,
      dualSubtitleEnabled:         s.getBool('${_p}dual_subtitle')              ?? false,
      smartVolumeLevelingEnabled: s.getBool('${_p}smart_vol_enabled')    ?? false,
      smartVolumeTarget:          s.getDouble('${_p}smart_vol_target')   ?? 0.80,
      smartVolumeMode:            s.getString('${_p}smart_vol_mode')     ?? 'balanced',
      skipSilenceEnabled:         s.getBool('${_p}skip_silence')          ?? false,
      skipSilenceThresholdSecs:   s.getDouble('${_p}skip_silence_secs')   ?? 1.5,
      skipBlackFramesEnabled:     s.getBool('${_p}skip_black_frames')      ?? false,
      customSpeedPresetsJson:     s.getString('${_p}speed_presets_json')   ?? '',
      endOfVideoAction:           s.getString('${_p}end_action')           ?? 'play_next',
      colorBlindMode:             s.getString('${_p}colorblind_mode')      ?? 'none',
      oneHandedModeEnabled:       s.getBool('${_p}one_handed')             ?? false,
      oneHandedModeSide:          s.getString('${_p}one_handed_side')      ?? 'right',
    );
  }

  // ── Reset all player preferences to defaults ────────────────────────────
  static Future<void> reset() async {
    final s = await SharedPreferences.getInstance();
    final keysToRemove = s.getKeys().where((k) => k.startsWith(_p)).toList();
    await Future.wait(keysToRemove.map((k) => s.remove(k)));
  }

  // ── Save to SharedPreferences ────────────────────────────────────────────

  Future<void> save() async {
    final s = await SharedPreferences.getInstance();
    await Future.wait([
      s.setBool('${_p}gesture_enabled',    gestureEnabled),
      s.setBool('${_p}swipe_brightness',   swipeBrightnessEnabled),
      s.setBool('${_p}swipe_volume',       swipeVolumeEnabled),
      s.setBool('${_p}swipe_seek',         swipeSeekEnabled),
      s.setBool('${_p}dt_seek_enabled',    doubleTapSeekEnabled),
      s.setInt('${_p}dt_seek_secs',        doubleTapSeekSeconds),
      s.setBool('${_p}lp_speed_enabled',   longPressSpeedEnabled),
      s.setDouble('${_p}lp_speed',         longPressSpeed),
      s.setBool('${_p}pinch_zoom',         pinchZoomEnabled),
      s.setDouble('${_p}swipe_sens',       swipeSensitivity),
      s.setDouble('${_p}seek_sens',        seekSensitivity),
      s.setBool('${_p}rage_skip_enabled',  rageSkipEnabled),
      s.setInt('${_p}rage_skip_secs',      rageSkipSeconds),
      s.setDouble('${_p}btn_size',         buttonSize),
      s.setDouble('${_p}bar_opacity',      controlBarOpacity),
      s.setInt('${_p}auto_hide_secs',      autoHideSeconds),
      s.setBool('${_p}tap_time_toggle',    tapTimeToToggleRemaining),
      s.setBool('${_p}show_buffer_bar',    showBufferBar),
      s.setBool('${_p}sub_enabled',        subtitleEnabled),
      s.setDouble('${_p}sub_font_size',    subtitleFontSize),
      s.setInt('${_p}sub_timing_ms',       subtitleTimingOffsetMs),
      s.setString('${_p}sub_encoding',     subtitleEncoding),
      s.setBool('${_p}sub_bold',           subtitleBold),
      s.setBool('${_p}sub_italic',         subtitleItalic),
      s.setString('${_p}sub_font_family',  subtitleFontFamily),
      s.setDouble('${_p}sub_outline',      subtitleOutlineThickness),
      s.setInt('${_p}sub_text_color',      subtitleTextColorValue),
      s.setInt('${_p}sub_outline_color',   subtitleOutlineColorValue),
      s.setInt('${_p}sub_bg_color',        subtitleBackgroundColorValue),
      s.setDouble('${_p}sub_bg_opacity',   subtitleBackgroundOpacity),
      s.setString('${_p}sub_position',     subtitlePosition),
      s.setDouble('${_p}sub_v_offset',     subtitleVerticalOffset),
      s.setBool('${_p}sub_auto_detect',    subtitleAutoDetect),
      s.setInt('${_p}audio_timing_ms',     audioTimingOffsetMs),
      s.setDouble('${_p}vol_boost',        volumeBoostMultiplier),
      s.setBool('${_p}eq_enabled',         equalizerEnabled),
      s.setString('${_p}eq_preset',        equalizerPreset),
      s.setString('${_p}eq_bands',         jsonEncode(equalizerBands)),
      s.setBool('${_p}dialogue_boost',     dialogueBoostEnabled),
      s.setBool('${_p}audio_norm',         audioNormalization),
      s.setBool('${_p}deinterlace',        deinterlaceEnabled),
      s.setBool('${_p}remember_audio',     rememberAudioTrack),
      s.setBool('${_p}remember_sub',       rememberSubtitleTrack),
      s.setBool('${_p}auto_locale',        autoSelectAudioByLocale),
      s.setBool('${_p}track_badge',        showActiveTrackBadge),
      s.setBool('${_p}track_count_badge',  showTrackCountBadge),
      s.setDouble('${_p}vid_brightness',   brightness),
      s.setDouble('${_p}vid_contrast',     contrast),
      s.setDouble('${_p}vid_saturation',   saturation),
      s.setDouble('${_p}vid_hue',          hue),
      s.setBool('${_p}night_mode',         nightMode),
      s.setDouble('${_p}night_intensity',  nightModeIntensity),
      s.setBool('${_p}sharpness_enabled',  sharpnessEnabled),
      s.setDouble('${_p}sharpness',        sharpness),
      s.setString('${_p}rotation_mode',    rotationMode),
      s.setDouble('${_p}speed',            playbackSpeed),
      s.setBool('${_p}remember_speed',     rememberSpeed),
      s.setBool('${_p}remember_pos',       rememberPosition),
      s.setBool('${_p}auto_play_next',     autoPlayNext),
      s.setInt('${_p}next_ep_countdown',   nextEpisodeCountdown),
      s.setBool('${_p}hw_decoder',         hwDecoderEnabled),
      s.setBool('${_p}bg_play',            backgroundPlayEnabled),
      s.setInt('${_p}seek_back_resume',    seekBackOnResumeSeconds),
      s.setBool('${_p}lp_restart',         longPressPlayRestart),
      s.setBool('${_p}auto_skip_intro',    autoSkipIntroEnabled),
      s.setBool('${_p}show_skip_intro',    showSkipIntroButton),
      s.setBool('${_p}transparent_mode',   transparentModeEnabled),
      s.setDouble('${_p}transparent_opacity', transparentModeOpacity),
      s.setBool('${_p}ambilight',          ambilightEnabled),
      s.setDouble('${_p}ambilight_intensity', ambilightIntensity),
      s.setInt('${_p}ambilight_interval',  ambilightSampleIntervalMs),
      s.setDouble('${_p}ambilight_blur_radius', ambilightBlurRadius),
      s.setBool('${_p}binge_guard',        bingeGuardEnabled),
      s.setInt('${_p}binge_threshold',     bingeGuardThresholdMinutes),
      s.setBool('${_p}sleep_fade',         sleepFadeEnabled),
      s.setInt('${_p}sleep_fade_secs',     sleepFadeDurationSeconds),
      s.setBool('${_p}show_net_speed',     showNetworkSpeed),
      s.setBool('${_p}show_decoder',       showDecoderInfo),
      s.setBool('${_p}show_playback_info', showPlaybackInfo),
      s.setBool('${_p}show_episode_info',  showEpisodeInfo),
      s.setBool('${_p}vibrate_gesture',    vibrateOnGesture),
      s.setDouble('${_p}ui_font_size',     uiFontSize),
      s.setBool('${_p}bookmark_vibrate',   bookmarkVibrate),
      s.setBool('${_p}cinematic_on_lock',  cinematicModeOnLock),
      s.setBool('${_p}gestures_cinematic', gesturesInCinematic),
      s.setString('${_p}cinematic_tap',    cinematicTapBehavior),
      s.setBool('${_p}transparent_frosted',transparentModeFrosted),
      s.setInt('${_p}accent_color',        accentColorValue),
      s.setString('${_p}seek_bar_style',   seekBarStyle),
      s.setString('${_p}player_theme',     playerTheme),
      s.setString('${_p}button_shape',     buttonShape),
      s.setString('${_p}icon_pack',        iconPack),
      s.setString('${_p}controls_bg',      controlsBgStyle),
      s.setString('${_p}gesture_map_json', gestureActionMapJson),
      s.setString('${_p}picture_profile',  pictureProfile),
      s.setBool('${_p}vocal_remover',      vocalRemoverEnabled),
      s.setDouble('${_p}vocal_intensity',  vocalRemoverIntensity),
      s.setBool('${_p}surround',           surroundEnabled),
      s.setString('${_p}surround_mode',    surroundMode),
      s.setBool('${_p}bass_boost',         bassBoostEnabled),
      s.setDouble('${_p}bass_level',       bassBoostLevel),
      s.setBool('${_p}dual_subtitle',      dualSubtitleEnabled),
      s.setBool('${_p}smart_vol_enabled', smartVolumeLevelingEnabled),
      s.setDouble('${_p}smart_vol_target', smartVolumeTarget),
      s.setString('${_p}smart_vol_mode',   smartVolumeMode),
      s.setBool('${_p}skip_silence',         skipSilenceEnabled),
      s.setDouble('${_p}skip_silence_secs',  skipSilenceThresholdSecs),
      s.setBool('${_p}skip_black_frames',    skipBlackFramesEnabled),
      s.setString('${_p}speed_presets_json', customSpeedPresetsJson),
      s.setString('${_p}end_action',         endOfVideoAction),
      s.setString('${_p}colorblind_mode',    colorBlindMode),
      s.setBool('${_p}one_handed',           oneHandedModeEnabled),
      s.setString('${_p}one_handed_side',    oneHandedModeSide),
    ]);
  }
}
