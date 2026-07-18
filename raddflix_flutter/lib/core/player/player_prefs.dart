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
  // BACKLOG-01: cinematicOpacity was a local state variable that reset every session
  final double cinematicOpacity;

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
  final int    wakeTimeoutMins;    // 0=always-on, 10/20/30 mins
  final bool   dndOnCinematic;     // Phase H5: DND when cinematic
  final double savedZoomLevel;     // Phase L3: last used zoom level
  final bool   contentMoodEnabled; // Phase G4: narrative-arc seek bar zones
  final bool   screenshotLockEnabled; // Phase K2: prevent screenshots

  // ── Phase B: Layout Designer ──────────────────────────────────────────────
  /// JSON-encoded PlayerLayout. Empty = use layoutPreset.
  final String layoutJson;
  /// Active preset: 'centered'|'left_handed'|'right_handed'|'minimal'|'custom'
  final String layoutPreset;

  // ── Phase F2: Word Dictionary ──────────────────────────────────────────────
  /// Enable tap-a-word dictionary lookup in subtitle overlay.
  final bool dictEnabled;

  // ── Phase D2: Color Look Presets ───────────────────────────────────────────
  /// Active color look preset name. 'none' = no filter.
  final String colorLook;

  // ── Phase D3: Film Grain / Film Look ───────────────────────────────────────
  /// Film grain intensity: 'none'|'subtle'|'medium'|'heavy'
  final String filmGrainLevel;

  // ── Phase J5: Haptic Feedback Patterns ────────────────────────────────────
  /// 'none'|'light'|'medium'|'heavy'
  final String hapticLevel;

  // ── Phase I2: Reaction Stamps ─────────────────────────────────────────────
  /// Whether to show emoji reaction stamp panel in player.
  final bool reactionsEnabled;

  // ── Phase K3: Watch History PIN Lock ─────────────────────────────────────
  /// Whether a PIN is required to view watch history.
  final bool historyPinEnabled;

  // ── Phase J4: Motor Impairment Mode ─────────────────────────────────────
  /// Increases touch targets, slows double-tap recognition, enables hold-to-seek.
  final bool motorImpairmentMode;

  // ── Phase L1: Enhanced Screenshot ────────────────────────────────────────
  /// Whether to overlay movie title + timestamp watermark on screenshots.
  final bool screenshotWatermark;

  // ── Phase L3: Video Zoom / Focus Mode ────────────────────────────────────
  /// Whether the Focus Mode zoom lens is active.
  final bool focusModeEnabled;

  // ── Phase M1: Custom Speed Presets ───────────────────────────────────────
  /// Comma-separated speed values e.g. '0.5,1.0,1.5,2.0'
  final String speedPresets;

  // ── Phase M3: End-of-Video Action ─────────────────────────────────────────
  /// One of: play_next | loop | return_home | show_credits | countdown_next | do_nothing
  final String endAction;

  // ── Phase M4: Smart Skip ──────────────────────────────────────────────────
  /// Encoded SmartSkipConfig string
  final String smartSkipConfig;

  // ── Phase E1–E4: Audio Lab ───────────────────────────────────────────────
  /// Encoded AudioLabConfig: 'surround|karaoke|dialogueBoost|btDelayMs'
  final String audioLabConfig;

  // ── Phase J1: Voice Commands ─────────────────────────────────────────────
  final bool voiceCommandsEnabled;

  // ── Phase H4: Wake Lock ───────────────────────────────────────────────────
  /// Minutes of inactivity before sleep. 0 = always on.
  final int wakeLockTimeoutMinutes;

  // ── Phase H5: Do Not Disturb ─────────────────────────────────────────────
  /// Enable Android DND when entering Cinematic/Immersive mode.
  // [dndOnCinematic defined earlier in SUBTITLES/Phase F1/H5 section]

  // ── Phase J2: Color Blind Mode ────────────────────────────────────────────
  // [colorBlindMode defined earlier in SUBTITLES/Phase F1/H5 section]

  // ── Phase J3: Dyslexia Subtitle Font ─────────────────────────────────────
  final String subtitleFont; // 'system'|'open_dyslexic'|'lexie_readable'|'roboto'|'atkinson'

  // ── Phase I1: Watch Party ─────────────────────────────────────────────────
  final bool watchPartyEnabled;

  // ── Phase L2: Frame Navigation ────────────────────────────────────────────
  final bool frameCounterEnabled;
  final double videoFps; // default 24.0

  // ── Phase D1: Picture Profiles ────────────────────────────────────────────
  final String pictureProfileId;

  // ── Phase F1: Dual Subtitles ──────────────────────────────────────────────
  final bool dualSubtitlesEnabled;
  final String secondarySubtitleLanguage;

  // ── Phase F3: Subtitle Style ──────────────────────────────────────────────
  final String subtitleStyleData; // SubtitleStyle.encode()

  // ── Phase F4: Subtitle Timing Debug ───────────────────────────────────────
  final bool subtitleTimingDebug;

  // ── Phase G1: Advanced Subtitle Sync ─────────────────────────────────────
  final int subtitleSyncOffsetMs;

  // ── Phase G3: Smart Subtitle Position ────────────────────────────────────
  // [subtitlePosition defined earlier in SUBTITLES/Phase F1/H5 section]

  // ── Phase C1: Custom Gesture Map ──────────────────────────────────────────
  final String gestureMapData; // GestureMap.encode()

  // ── Phase N1: Buffer Strategy ─────────────────────────────────────────────
  final String bufferStrategy; // BufferStrategy.name

  // ── Phase N2: Download Quality ────────────────────────────────────────────
  final String downloadQuality; // DownloadQuality name

  // ── Phase N3: Network Speed HUD ───────────────────────────────────────────
  final bool networkSpeedHud;

  // ── Phase O4: Mood Tags ───────────────────────────────────────────────────
  final String moodTagsData; // JSON list of MoodTag.name

  // ── Phase S: Audio Mixer ─────────────────────────────────────────────────────
  final double channelBalance; // -1.0 (left) … +1.0 (right)

  // ── Phase A-B Loop setting ───────────────────────────────────────────────────
  final bool abLoopEnabled;

  // ── Center Button Customization ──────────────────────────────────────────
  /// Scale multiplier for all center buttons (play, seek, prev, next, skip). 0.6–2.0.
  final double centerBtnScale;
  /// Vertical offset in logical pixels. Negative = up, positive = down. -150 to 150.
  final double centerBtnVerticalOffset;
  /// When true, seek/next/prev buttons show icon only with no background container.
  final bool   centerBtnIconOnly;
  /// Background opacity for seek, next, prev, and skip buttons. 0.0 (transparent) – 1.0.
  final double centerBtnBgOpacity;
  /// Show a Prev Episode button in the center row.
  final bool   showCenterPrev;
  /// Show Skip Intro button inline in the center row.
  final bool   showCenterSkip;
  /// Show Next Episode button in the center row (requires hasNext to be true).
  final bool   showCenterNext;

  // ── Quick Shortcut Bar & Center Button Position ───────────────────────────
  /// Controls widget anchor: 'center' | 'bottom' | 'hidden'.
  /// bottom = modern style (Netflix/YouTube), near the seek bar.
  final String centerBtnPosition;
  /// Show a one-tap icon shortcut bar above the seek bar.
  final bool   showQuickBar;
  /// Comma-separated quick-bar slot IDs.
  /// Supported: pip, bgplay, fit, screenshot, speed, subtitle, lock, nightmode
  final String quickBarItems;

  // ── Smart Enhance ────────────────────────────────────────────────────────
  /// Whether MX-style AI video enhancement is active.
  final bool   smartEnhanceEnabled;
  /// Content mode preset ID — 'standard'|'movie'|'sports'|'anime'|
  /// 'low_light'|'amoled'|'drama'|'documentary'
  final String smartEnhanceMode;
  final int    sidebarMode;          // 0=full 1=icons-only 2=hidden

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
    this.rotationMode = 'auto',
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
    this.cinematicOpacity = 0.5,
    this.transparentModeFrosted = false,
    this.accentColorValue = 0xFFD4784A,
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
    this.wakeTimeoutMins         = 0,
    this.dndOnCinematic           = false,
    this.savedZoomLevel           = 1.0,
    this.contentMoodEnabled       = false,
    this.screenshotLockEnabled    = false,
    this.layoutJson               = '',
    this.layoutPreset             = 'centered',
    this.dictEnabled               = true,
    this.colorLook                 = 'none',
    this.filmGrainLevel            = 'none',
    this.hapticLevel               = 'heavy',
    this.reactionsEnabled          = false,
    this.historyPinEnabled         = false,
    this.motorImpairmentMode       = false,
    this.screenshotWatermark       = true,
    this.focusModeEnabled          = false,
    this.speedPresets              = '0.25,0.5,0.75,1.0,1.25,1.5,1.75,2.0,2.5,3.0',
    this.endAction                 = 'play_next',
    this.smartSkipConfig           = '0,0,90,0,120',
    this.audioLabConfig            = 'off|off|0|0',
    this.voiceCommandsEnabled      = false,
    this.wakeLockTimeoutMinutes    = 0,
    this.subtitleFont              = 'system',
    this.watchPartyEnabled         = true,
    this.frameCounterEnabled       = false,
    this.videoFps                  = 24.0,
    this.pictureProfileId          = 'standard',
    this.dualSubtitlesEnabled      = false,
    this.secondarySubtitleLanguage = 'en',
    this.subtitleStyleData         = '',
    this.subtitleTimingDebug       = false,
    this.subtitleSyncOffsetMs      = 0,
    this.gestureMapData            = '',
    this.bufferStrategy            = 'auto',
    this.downloadQuality           = 'auto',
    this.networkSpeedHud           = false,
    this.moodTagsData              = '[]',
    this.channelBalance            = 0.0,
    this.abLoopEnabled             = false,
    this.centerBtnScale              = 1.0,
    this.centerBtnVerticalOffset     = 0.0,
    this.centerBtnIconOnly           = false,
    this.centerBtnBgOpacity          = 0.3,
    this.showCenterPrev              = false,
    this.showCenterSkip              = false,
    this.showCenterNext              = true,
    this.centerBtnPosition           = 'center',
    this.showQuickBar                = true,
    this.quickBarItems               = 'pip,bgplay,fit,screenshot,speed',
    this.smartEnhanceEnabled         = false,
    this.smartEnhanceMode            = 'standard',
    this.sidebarMode                 = 0,
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
    String? cinematicTapBehavior, double? cinematicOpacity, bool? transparentModeFrosted,
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
    int?    wakeTimeoutMins,
    bool?   dndOnCinematic,
    String? subtitleFont,
    bool?   watchPartyEnabled,
    bool?   frameCounterEnabled,
    double? videoFps,
    String? pictureProfileId,
    bool?   dualSubtitlesEnabled,
    String? secondarySubtitleLanguage,
    String? subtitleStyleData,
    bool?   subtitleTimingDebug,
    int?    subtitleSyncOffsetMs,
    String? gestureMapData,
    String? bufferStrategy,
    String? downloadQuality,
    bool?   networkSpeedHud,
    String? moodTagsData,
    double? savedZoomLevel,
    bool?   contentMoodEnabled,
    bool?   screenshotLockEnabled,
    String? layoutJson,
    String? layoutPreset,
    bool?   dictEnabled,
    String? colorLook,
    String? filmGrainLevel,
    String? hapticLevel,
    bool?   reactionsEnabled,
    bool?   historyPinEnabled,
    bool?   motorImpairmentMode,
    bool?   screenshotWatermark,
    bool?   focusModeEnabled,
    String? speedPresets,
    String? endAction,
    String? smartSkipConfig,
    String? audioLabConfig,
    bool?   voiceCommandsEnabled,
    int?    wakeLockTimeoutMinutes,
    double? channelBalance,
    bool?   abLoopEnabled,
    double? centerBtnScale,
    double? centerBtnVerticalOffset,
    bool?   centerBtnIconOnly,
    double? centerBtnBgOpacity,
    bool?   showCenterPrev,
    bool?   showCenterSkip,
    bool?   showCenterNext,
    String? centerBtnPosition,
    bool?   showQuickBar,
    String? quickBarItems,
    bool?   smartEnhanceEnabled,
    String? smartEnhanceMode,
    int?    sidebarMode,
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
    cinematicOpacity: cinematicOpacity ?? this.cinematicOpacity,
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
      wakeTimeoutMins:             wakeTimeoutMins             ?? this.wakeTimeoutMins,
      dndOnCinematic:              dndOnCinematic              ?? this.dndOnCinematic,
      savedZoomLevel:              savedZoomLevel              ?? this.savedZoomLevel,
      contentMoodEnabled:          contentMoodEnabled          ?? this.contentMoodEnabled,
      screenshotLockEnabled:       screenshotLockEnabled       ?? this.screenshotLockEnabled,
      layoutJson:                  layoutJson                  ?? this.layoutJson,
      layoutPreset:                layoutPreset                ?? this.layoutPreset,
      dictEnabled:                 dictEnabled                  ?? this.dictEnabled,
      colorLook:                   colorLook                    ?? this.colorLook,
      filmGrainLevel:              filmGrainLevel               ?? this.filmGrainLevel,
      hapticLevel:                 hapticLevel                  ?? this.hapticLevel,
      reactionsEnabled:            reactionsEnabled             ?? this.reactionsEnabled,
      historyPinEnabled:           historyPinEnabled            ?? this.historyPinEnabled,
      motorImpairmentMode:         motorImpairmentMode          ?? this.motorImpairmentMode,
      screenshotWatermark:         screenshotWatermark          ?? this.screenshotWatermark,
      focusModeEnabled:            focusModeEnabled             ?? this.focusModeEnabled,
      speedPresets:                speedPresets                 ?? this.speedPresets,
      endAction:                   endAction                    ?? this.endAction,
      smartSkipConfig:             smartSkipConfig              ?? this.smartSkipConfig,
      audioLabConfig:              audioLabConfig               ?? this.audioLabConfig,
      voiceCommandsEnabled:        voiceCommandsEnabled         ?? this.voiceCommandsEnabled,
      wakeLockTimeoutMinutes:      wakeLockTimeoutMinutes       ?? this.wakeLockTimeoutMinutes,
      subtitleFont:                subtitleFont                 ?? this.subtitleFont,
      watchPartyEnabled:           watchPartyEnabled            ?? this.watchPartyEnabled,
      frameCounterEnabled:         frameCounterEnabled          ?? this.frameCounterEnabled,
      videoFps:                    videoFps                     ?? this.videoFps,
      pictureProfileId:            pictureProfileId             ?? this.pictureProfileId,
      dualSubtitlesEnabled:        dualSubtitlesEnabled         ?? this.dualSubtitlesEnabled,
      secondarySubtitleLanguage:   secondarySubtitleLanguage    ?? this.secondarySubtitleLanguage,
      subtitleStyleData:           subtitleStyleData            ?? this.subtitleStyleData,
      subtitleTimingDebug:         subtitleTimingDebug          ?? this.subtitleTimingDebug,
      subtitleSyncOffsetMs:        subtitleSyncOffsetMs         ?? this.subtitleSyncOffsetMs,
      gestureMapData:              gestureMapData               ?? this.gestureMapData,
      bufferStrategy:              bufferStrategy               ?? this.bufferStrategy,
      downloadQuality:             downloadQuality              ?? this.downloadQuality,
      networkSpeedHud:             networkSpeedHud              ?? this.networkSpeedHud,
      moodTagsData:                moodTagsData                 ?? this.moodTagsData,
      channelBalance:              channelBalance               ?? this.channelBalance,
      abLoopEnabled:               abLoopEnabled                ?? this.abLoopEnabled,
      centerBtnScale:              centerBtnScale              ?? this.centerBtnScale,
      centerBtnVerticalOffset:     centerBtnVerticalOffset     ?? this.centerBtnVerticalOffset,
      centerBtnIconOnly:           centerBtnIconOnly           ?? this.centerBtnIconOnly,
      centerBtnBgOpacity:          centerBtnBgOpacity          ?? this.centerBtnBgOpacity,
      showCenterPrev:              showCenterPrev              ?? this.showCenterPrev,
      showCenterSkip:              showCenterSkip              ?? this.showCenterSkip,
      showCenterNext:              showCenterNext              ?? this.showCenterNext,
      centerBtnPosition:           centerBtnPosition           ?? this.centerBtnPosition,
      showQuickBar:                showQuickBar                ?? this.showQuickBar,
      quickBarItems:               quickBarItems               ?? this.quickBarItems,
      smartEnhanceEnabled:         smartEnhanceEnabled         ?? this.smartEnhanceEnabled,
      smartEnhanceMode:            smartEnhanceMode            ?? this.smartEnhanceMode,
      sidebarMode:                 sidebarMode                 ?? this.sidebarMode,
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
      cinematicOpacity:       s.getDouble('${_p}cinematic_opacity') ?? 0.5, // BACKLOG-01
      transparentModeFrosted: s.getBool('${_p}transparent_frosted') ?? false,
      accentColorValue:       s.getInt('${_p}accent_color')       ?? 0xFFD4784A,
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
      wakeTimeoutMins:             s.getInt('${_p}wake_timeout_mins')    ?? 0,
      dndOnCinematic:              s.getBool('${_p}dnd_cinematic')        ?? false,
      savedZoomLevel:              s.getDouble('${_p}saved_zoom_level')   ?? 1.0,
      contentMoodEnabled:          s.getBool('${_p}content_mood')          ?? false,
      screenshotLockEnabled:       s.getBool('${_p}screenshot_lock')       ?? false,
      layoutJson:                  s.getString('${_p}layout_json')           ?? '',
      layoutPreset:                s.getString('${_p}layout_preset')         ?? 'centered',
      dictEnabled:                 s.getBool('${_p}dict_enabled')            ?? true,
      colorLook:                   s.getString('${_p}color_look')             ?? 'none',
      filmGrainLevel:              s.getString('${_p}film_grain')              ?? 'none',
      hapticLevel:                 s.getString('${_p}haptic_level')           ?? 'heavy',
      reactionsEnabled:            s.getBool('${_p}reactions_enabled')        ?? false, // P03: was true, mismatched constructor default
      historyPinEnabled:           s.getBool('${_p}history_pin_enabled')      ?? false,
      motorImpairmentMode:         s.getBool('${_p}motor_impairment')         ?? false,
      screenshotWatermark:         s.getBool('${_p}screenshot_watermark')     ?? true,
      focusModeEnabled:            s.getBool('${_p}focus_mode_enabled')       ?? false,
      speedPresets:                s.getString('${_p}speed_presets')           ?? '0.25,0.5,0.75,1.0,1.25,1.5,1.75,2.0,2.5,3.0',
      endAction:                   s.getString('${_p}end_action_v2')           ?? 'play_next', // P01: was sharing key with endOfVideoAction
      smartSkipConfig:             s.getString('${_p}smart_skip_config')       ?? '0,0,90,0,120',
      audioLabConfig:              s.getString('${_p}audio_lab_config')         ?? 'off|off|0|0',
      voiceCommandsEnabled:        s.getBool('${_p}voice_commands_enabled')    ?? false,
      wakeLockTimeoutMinutes:      s.getInt('${_p}wake_lock_timeout')           ?? 0,
      subtitleFont:                s.getString('${_p}subtitle_font')             ?? 'system',
      watchPartyEnabled:           s.getBool('${_p}watch_party_enabled')        ?? true,
      frameCounterEnabled:         s.getBool('${_p}frame_counter_enabled')      ?? false,
      videoFps:                    s.getDouble('${_p}video_fps')                 ?? 24.0,
      pictureProfileId:            s.getString('${_p}picture_profile_id')        ?? 'standard',
      dualSubtitlesEnabled:        s.getBool('${_p}dual_subtitles_enabled')      ?? false,
      secondarySubtitleLanguage:   s.getString('${_p}secondary_sub_lang')        ?? 'en',
      subtitleStyleData:           s.getString('${_p}subtitle_style_data')       ?? '',
      subtitleTimingDebug:         s.getBool('${_p}subtitle_timing_debug')       ?? false,
      subtitleSyncOffsetMs:        s.getInt('${_p}subtitle_sync_offset_ms')      ?? 0,
      gestureMapData:              s.getString('${_p}gesture_map_data')          ?? '',
      bufferStrategy:              s.getString('${_p}buffer_strategy')           ?? 'auto',
      downloadQuality:             s.getString('${_p}download_quality')          ?? 'auto',
      networkSpeedHud:             s.getBool('${_p}network_speed_hud')           ?? false,
      moodTagsData:                s.getString('${_p}mood_tags_data')            ?? '[]',
      channelBalance:              s.getDouble('${_p}channel_balance')           ?? 0.0,
      abLoopEnabled:               s.getBool('${_p}ab_loop_enabled')             ?? false,
      centerBtnScale:              s.getDouble('${_p}center_btn_scale')          ?? 1.0,
      centerBtnVerticalOffset:     s.getDouble('${_p}center_btn_v_offset')       ?? 0.0,
      centerBtnIconOnly:           s.getBool('${_p}center_btn_icon_only')        ?? false,
      centerBtnBgOpacity:          s.getDouble('${_p}center_btn_bg_opacity')     ?? 0.3,
      showCenterPrev:              s.getBool('${_p}center_show_prev')            ?? false,
      showCenterSkip:              s.getBool('${_p}center_show_skip')            ?? false,
      showCenterNext:              s.getBool('${_p}center_show_next')            ?? true,
      centerBtnPosition:           s.getString('${_p}center_btn_position')       ?? 'center',
      showQuickBar:                s.getBool('${_p}show_quick_bar')              ?? true,
      quickBarItems:               s.getString('${_p}quick_bar_items')           ?? 'pip,bgplay,fit,screenshot,speed',
      smartEnhanceEnabled:         s.getBool('${_p}smart_enhance_enabled')        ?? false,
      smartEnhanceMode:            s.getString('${_p}smart_enhance_mode')         ?? 'standard',
      sidebarMode:                 s.getInt('${_p}sidebar_mode')                ?? 0,
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
      s.setDouble('${_p}cinematic_opacity', cinematicOpacity), // BACKLOG-01
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
      s.setInt('${_p}wake_timeout_mins',  wakeTimeoutMins),
      s.setBool('${_p}dnd_cinematic',      dndOnCinematic),
      s.setDouble('${_p}saved_zoom_level', savedZoomLevel),
      s.setBool('${_p}content_mood',        contentMoodEnabled),
      s.setBool('${_p}screenshot_lock',     screenshotLockEnabled),
      s.setString('${_p}layout_json',        layoutJson),
      s.setString('${_p}layout_preset',      layoutPreset),
      s.setBool('${_p}dict_enabled',          dictEnabled),
      s.setString('${_p}color_look',           colorLook),
      s.setString('${_p}film_grain',            filmGrainLevel),
      s.setString('${_p}haptic_level',          hapticLevel),
      s.setBool('${_p}reactions_enabled',        reactionsEnabled),
      s.setBool('${_p}history_pin_enabled',       historyPinEnabled),
      s.setBool('${_p}motor_impairment',           motorImpairmentMode),
      s.setBool('${_p}screenshot_watermark',       screenshotWatermark),
      s.setBool('${_p}focus_mode_enabled',         focusModeEnabled),
      s.setString('${_p}speed_presets',            speedPresets),
      s.setString('${_p}end_action_v2',             endAction), // P01: was sharing key with endOfVideoAction
      s.setString('${_p}smart_skip_config',        smartSkipConfig),
      s.setString('${_p}audio_lab_config',           audioLabConfig),
      s.setBool('${_p}voice_commands_enabled',        voiceCommandsEnabled),
      s.setInt('${_p}wake_lock_timeout',              wakeLockTimeoutMinutes),
      s.setString('${_p}subtitle_font',               subtitleFont),
      s.setBool('${_p}watch_party_enabled',            watchPartyEnabled),
      s.setBool('${_p}frame_counter_enabled',          frameCounterEnabled),
      s.setDouble('${_p}video_fps',                    videoFps),
      s.setString('${_p}picture_profile_id',           pictureProfileId),
      s.setBool('${_p}dual_subtitles_enabled',         dualSubtitlesEnabled),
      s.setString('${_p}secondary_sub_lang',           secondarySubtitleLanguage),
      s.setString('${_p}subtitle_style_data',          subtitleStyleData),
      s.setBool('${_p}subtitle_timing_debug',          subtitleTimingDebug),
      s.setInt('${_p}subtitle_sync_offset_ms',         subtitleSyncOffsetMs),
      s.setString('${_p}gesture_map_data',             gestureMapData),
      s.setString('${_p}buffer_strategy',              bufferStrategy),
      s.setString('${_p}download_quality',             downloadQuality),
      s.setBool('${_p}network_speed_hud',              networkSpeedHud),
      s.setString('${_p}mood_tags_data',               moodTagsData),
      s.setDouble('${_p}channel_balance',            channelBalance),
      s.setBool('${_p}ab_loop_enabled',              abLoopEnabled),
      s.setDouble('${_p}center_btn_scale',           centerBtnScale),
      s.setDouble('${_p}center_btn_v_offset',        centerBtnVerticalOffset),
      s.setBool('${_p}center_btn_icon_only',         centerBtnIconOnly),
      s.setDouble('${_p}center_btn_bg_opacity',      centerBtnBgOpacity),
      s.setBool('${_p}center_show_prev',             showCenterPrev),
      s.setBool('${_p}center_show_skip',             showCenterSkip),
      s.setBool('${_p}center_show_next',             showCenterNext),
      s.setString('${_p}center_btn_position',        centerBtnPosition),
      s.setBool('${_p}show_quick_bar',               showQuickBar),
      s.setString('${_p}quick_bar_items',            quickBarItems),
      s.setBool('${_p}smart_enhance_enabled',         smartEnhanceEnabled),
      s.setString('${_p}smart_enhance_mode',          smartEnhanceMode),
      s.setInt('${_p}sidebar_mode',               sidebarMode),
    ]);
  }
}