import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/cast_service.dart';
import '../core/constants.dart';
import '../core/security/keystore.dart';
import '../core/db/local_db.dart';
import '../core/api/catalog_api.dart';
import '../core/api/history_api.dart';
import '../core/services/jazzdrive_service.dart';
import '../core/debug/debug_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/player/player_prefs.dart';
import '../core/player/player_prefs_provider.dart';
import '../core/player/smart_intro_store.dart';
import '../core/player/ambilight_controller.dart';
import '../core/player/binge_guard_controller.dart';
import '../core/player/scene_bookmark_store.dart';
import '../core/player/ab_loop_controller.dart';
import '../widgets/player/seek_bar_painter.dart';
import '../core/player/video_look_filter.dart'; // Phase D2
import '../core/player/haptic_service.dart'; // Phase J5
import '../widgets/player/reaction_stamps_overlay.dart'; // Phase I2
import '../widgets/player/zoom_focus_overlay.dart'; // Phase L3
import '../core/player/enhanced_screenshot_service.dart'; // Phase L1
import '../widgets/player/speed_presets_sheet.dart'; // Phase M1
import '../widgets/player/jump_to_panel.dart'; // Phase M2
import '../core/player/end_of_video_actions.dart'; // Phase M3
import '../core/player/smart_skip_service.dart'; // Phase M4
import '../core/player/audio_lab_service.dart'; // Phase E1-E4
import '../core/services/voice_commands_service.dart'; // Phase J1
import '../core/services/wake_lock_service.dart'; // Phase H4
import '../core/services/dnd_service.dart'; // Phase H5
import '../core/player/color_blind_filter.dart'; // Phase J2
import '../core/player/dyslexia_subtitle_style.dart'; // Phase J3
import '../core/player/watch_party_service.dart'; // Phase I1
import '../core/player/frame_navigation_service.dart'; // Phase L2
import '../core/player/shared_bookmarks_service.dart'; // Phase I3
import '../widgets/player/karaoke_overlay.dart'; // Phase E2
import '../widgets/player/film_grain_overlay.dart'; // Phase D3
import '../widgets/player/controls_background.dart';
import '../widgets/player/sleep_timer_sheet.dart';
import '../widgets/player/speed_picker_sheet.dart';
import '../widgets/player/bookmark_panel.dart';
import '../widgets/player/eq_visualizer.dart';
import '../screens/player_settings_screen.dart';
import '../widgets/player/cast_panel.dart';
import '../widgets/player/audio_mixer_sheet.dart';
import '../widgets/player/clip_trimmer.dart';
import '../widgets/player/binge_guard.dart';
import '../widgets/player/pip_overlay.dart';
import '../widgets/player/ab_loop_panel.dart';
import '../widgets/player/rage_skip_panel.dart';
import '../widgets/player/network_speed_overlay.dart';
import '../widgets/player/screenshot_share_sheet.dart';
import '../widgets/player/video_enhance_suite.dart';
import '../widgets/player/sync_panel.dart';
import '../widgets/player/eq_panel.dart';
import '../widgets/player/quick_settings_panel.dart';
import '../widgets/player/ambilight_glow_border.dart';
import '../widgets/player/playback_info_overlay.dart';
import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:saver_gallery/saver_gallery.dart';
import '../widgets/player/immersive_overlay.dart';
import '../widgets/player/cinematic_settings_sheet.dart';
import '../widgets/player/scene_bookmarks_panel.dart';
import '../widgets/player/track_badges.dart';
import '../widgets/player/video_enhance_panel.dart';
import '../widgets/player/transparent_player_layer.dart';
import '../core/services/usage_service.dart';
import '../widgets/player/subtitle_overlay.dart';
import '../core/player/intro_skip_store.dart';
import '../widgets/player/gesture_map_sheet.dart';
import '../widgets/player/picture_profiles_sheet.dart';
import '../widgets/player/audio_lab_sheet.dart';
import '../widgets/player/intro_skip_editor.dart';
import '../widgets/player/dual_subtitle_overlay.dart';
import '../widgets/player/jump_to_sheet.dart';
import '../widgets/player/end_action_sheet.dart';
import '../widgets/player/speed_presets_sheet.dart';
import '../widgets/player/silence_skip_sheet.dart';
import '../widgets/player/zoom_crop_overlay.dart';

// ── PiP Method Channel ────────────────────────────────────────────────────────
const _pipChannel = MethodChannel('com.raddflix.app/pip');

class PlayerScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String? localPath;
  final List<Map<String, dynamic>>? episodes;
  final int episodeIndex;
  final String contentType; // 'series'|'drama'|'anime'|'movie'|'song'|etc.

  const PlayerScreen({
    super.key,
    required this.fileId,
    required this.title,
    this.localPath,
    this.episodes,
    this.episodeIndex = 0,
    this.contentType = 'series',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoCtrl;

  // Controls
  bool _showControls = true;
  bool _isLinkLoading = false;
  Timer? _hideTimer;
  bool _locked = false;

  // Seek flash
  bool _showSeekLeft = false;
  bool _showSeekRight = false;
  String _seekLabel = '';

  // Speed
  double _speed = 1.0;
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // Gesture state (unified scale handler)
  String? _dragIntent; // 'brightness' | 'volume' | 'seek' | 'pinch'
  Offset _dragStartLocal = Offset.zero;
  double _startScale = 1.0;
  double _startBrightness = 0.5;
  double _startVolume = 0.7;
  double _startVolumeBoost = 1.0; // boost at gesture start (for swipe-into-boost)
  bool _inBoostGesture = false;  // true once system vol hit 100% and swiping up
  Duration _dragStartPosition = Duration.zero;
  bool _draggingBrightness = false;
  bool _draggingVolume = false;
  bool _draggingSeek = false;
  double? _dragSeekDelta; // seconds offset while scrubbing

  // Long press 2×
    bool _longPressFast = false;

    // §3.16F: Headphone button double/triple press
    int _mediaButtonPressCount = 0;
    Timer? _mediaButtonTimer;

  // Panels
  bool _showSpeedPicker = false;
  bool _showSubtitleMenu = false;
  bool _showAudioMenu = false;
  bool _showSleepMenu = false;

  // Zoom & pan
  double _scale = 1.0;
  bool _castConnected = false;

  // Skip intro
  bool _skipIntroVisible = false;
  Timer? _skipIntroTimer;

  // Next Episode
  bool _showNextEpisode = false;
  int _nextCountdown = 7;
  Timer? _nextEpTimer;
  Timer? _quotaTimer; // BUG-A29: periodic quota check every 5 min
  late int _currentEpIdx;
  bool get _hasNextEp =>
      widget.episodes != null && _currentEpIdx < widget.episodes!.length - 1;

  // Aspect ratio
  final _ratios = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  int _ratioIdx = 0;

  // Playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = true;
  bool _slowConnectionShown = false;
  Timer? _slowConnTimer;
  bool _playing = false;
  bool _ended = false;
  DateTime? _sessionStartTime; // track watch-time for usage reporting
  Duration _bufferedPosition = Duration.zero;

  // Position notifier — updates slider/time WITHOUT rebuilding full tree
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final _durationNotifier = ValueNotifier<Duration>(Duration.zero);

  // Sleep timer
  int? _sleepRemainingSeconds;
  Timer? _sleepTimer;
  bool _sleepAtEpisodeEnd = false; // FIX-SLEEP: -1 = pause at end of episode
  // Sleep fade
  bool _sleepFadeActive = false;
  double _preFadeVolume = 0.7;
  Timer? _sleepFadeTimer;

  // PiP
  bool _inPiP = false;

  // Phase P: Custom skip segments (loaded per video)
  List<SkipSegment> _skipSegments = [];
  SkipSegment? _activeSkipSegment;

  // Phase F1: Second subtitle track
  String _secondSubtitleText = '';

  // Background audio — track if user explicitly paused
  bool _userPaused = false;

  // Seek thumbnail (local/downloaded only)
  Uint8List? _seekThumb;
  Timer? _seekThumbDebounce;
  _SmartVolumeController? _svc; // Phase SVL

  // Phase L3: Zoom & Crop
  double     _zoomLevel  = 1.0;
  AspectMode _aspectMode = AspectMode.original;
  bool       _showZoomOverlay = false;

  // Phase H4: Wake Lock timeout
  Timer?     _wakeTimer;

  bool _sliderDragging = false;
  double _sliderDragValue = 0.0;

  bool get _isLocalFile =>
      (widget.localPath != null && widget.localPath!.isNotEmpty) ||
      _isLocalPath(widget.fileId);

  // JazzDrive XML auto-retry
  int _jazzRetryCount = 0;
  Timer? _jazzRetryTimer;
  String? _streamError;
  String? _currentPlaybackUrl; // track current URL for "Open with" feature

  // Time display toggle (tap = elapsed/remaining)
  bool _showRemaining = false;

  // PlayerPrefs (loaded async — defaults used until ready)
  PlayerPrefs _prefs = const PlayerPrefs();

  // ── Phase 3B: Quick Settings / EQ panels ─────────────────────────────────
  bool _showQuickSettings    = false;
  bool _showMorePanel        = false;
  bool _showEqPanel          = false;
  bool _showAudioSyncPanel   = false;
  bool _showSubSyncPanel     = false;
  bool _showVideoDisplay     = false;

  // ── Video Display Shortcuts toggles ──────────────────────────────────────
  bool _bgPlayEnabled  = false;  // background play
  bool _isMuted        = false;  // mute toggle

  // ── Phase 3C: Smart Skip Intro ────────────────────────────────────────────
  int? _savedIntroEnd; // seconds — loaded from SmartIntroStore

  // ── Phase 3D: Sync ────────────────────────────────────────────────────────
  int _audioDelayMs = 0;
  int _subDelayMs   = 0;

  // ── Phase 3G: Enhancement ────────────────────────────────────────────────
  double _volumeBoost = 1.0; // 1.0–3.0 = 100%–300%

  // ── Phase 3I: Ambilight ───────────────────────────────────────────────────
  AmbilightController? _ambilightCtrl;
  AmbilightColors _ambilightColors = const AmbilightColors();

  // ── Phase 3I: Binge Guard ─────────────────────────────────────────────────
  BingeGuardController? _bingeGuardCtrl;
  bool _showBingeGuard = false;
  int  _bingeWatchedMins = 0;

  // ── Phase 3I: Rage Skip ───────────────────────────────────────────────────
  bool  _rageSkipActive = false;
  int   _tapCount = 0;
  Timer? _tapTimer;

  // ── Phase 3I: Scene Bookmarks ─────────────────────────────────────────────
  List<SceneBookmark> _bookmarks = [];
  bool _showBookmarksPanel = false;

  // ── Phase 3K: A-B Loop ────────────────────────────────────────────────────
  final AbLoopController _abLoop = AbLoopController();
  bool _showAbPanel = false;

  // ── Phase 3K: Playback Info ───────────────────────────────────────────────
  bool _showPlaybackInfo = false;
  String _piCodec = '—', _piRes = '—', _piFps = '—',
         _piBitrate = '—', _piBuffer = '—', _piDecoder = 'HW';

  // ── Phase 3K: Frame Step ─────────────────────────────────────────────────
  bool _showFrameStep = false;

  // ── Phase 3K: Chapter Markers ────────────────────────────────────────────
  List<Duration> _chapters = [];

  // ── Phase 3F: Cinematic Mode ─────────────────────────────────────────────
  bool _cinematicMode = false;
  bool _immersiveMode = false;
  // User-adjustable cinematic controls opacity (0.25–1.0, default 0.5)
  double _cinematicOpacity = 0.5;

  // ── Video Enhance / Transparent Slider ───────────────────────────────────
  bool _showVideoEnhance = false;
  bool _showTransparentSlider = false;

  // ── Track Intelligence ────────────────────────────────────────────────────
  int _activeAudioIdx = 0;
  int _activeSubIdx   = 0;

    // ── Subtitle text for custom overlay ─────────────────────────────────────
    String? _currentSubtitleText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentEpIdx = widget.episodeIndex;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    WakelockPlus.enable();
    _initPlayer();
    _startWakeTimer(); // Phase H4: optional wake timeout
    _scheduleHide();
    _onUserActivity(); // reset wake timer on tap
    _initBrightnessVolume();
    _loadPrefs();
    _initAudioSession();
    _loadSmartIntro();
    _loadBookmarks();
    _checkQuota();
    _quotaTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkQuota());
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
    }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Background audio: don't pause if user didn't pause
      if (!_userPaused) {
        // Keep playing for background audio — just disable wakelock
        WakelockPlus.disable();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_userPaused) {
        WakelockPlus.enable();
        // Seek back N seconds so user doesn't miss anything after switching apps
        final seekBack = _prefs.seekBackOnResumeSeconds;
        if (seekBack > 0 && _position.inSeconds > seekBack) {
          _player.seek(_position - Duration(seconds: seekBack));
        }
      }
    }
  }

  Future<void> _initBrightnessVolume() async {
    try {
      _brightness = await ScreenBrightness().current;
      _volume = await VolumeController().getVolume();
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    final loaded = await PlayerPrefs.load();
    if (!mounted) return;
    setState(() => _prefs = loaded);
    // Apply rotation mode from prefs
    _applyRotation(loaded.rotationMode);
    // Apply volume boost from prefs
    if (loaded.volumeBoostMultiplier > 1.0) _applyVolumeBoost(loaded.volumeBoostMultiplier);
    _volumeBoost = loaded.volumeBoostMultiplier;
    // Apply audio + video prefs
    _applyAudioPrefs(loaded);
    _applyVideoFilters(loaded);
    // Init binge guard + ambilight from prefs
    _initBingeGuard();
    _initAmbilight();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((event) {
        if (!mounted) return;
        if (event.begin) {
          _player.pause();
        } else if (event.type == AudioInterruptionType.pause && !_userPaused) {
          _player.play();
        }
      });
      // Pause on headphone unplug + user toast
      session.becomingNoisyEventStream.listen((_) {
        if (!mounted) return;
        if (!_userPaused) {
          _player.pause();
          _userPaused = true;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎧 Headphones disconnected — paused'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ));
        }
      });
    } catch (_) {}
  }

  Future<void> _loadSmartIntro() async {
    if (!SmartIntroStore.shouldShow(
        contentType: widget.contentType,
        totalDuration: _duration)) return;
    final seriesId = widget.fileId.split('/').first;
    final end = await SmartIntroStore.getIntroEnd(
        seriesId: seriesId, epIndex: _currentEpIdx);
    if (mounted) setState(() => _savedIntroEnd = end);
  }

  Future<void> _loadBookmarks() async {
    final bm = await SceneBookmarkStore.getAll(
        contentId: widget.fileId,
        episodeId: widget.episodes != null ? _currentEpIdx.toString() : null);
    if (mounted) setState(() => _bookmarks = bm);
  }

  // Build MPV vf= filter string from prefs
  String _buildVfString(PlayerPrefs p) {
    final parts = <String>[];
    if (p.brightness != 0 || p.contrast != 0 || p.saturation != 0 || p.hue != 0) {
      parts.add('eq=brightness=${p.brightness}:contrast=${1 + p.contrast}'
          ':saturation=${1 + p.saturation}:hue=${p.hue / 180.0}');
    }
    if (p.nightMode) {
      final i = p.nightModeIntensity;
      parts.add('colorchannelmixer='
          'rr=${(0.9 + i * 0.05).toStringAsFixed(3)}'
          ':rg=${(0.1 * i).toStringAsFixed(3)}'
          ':rb=${(0.05 * i).toStringAsFixed(3)}'
          ':gr=${(0.01 * i).toStringAsFixed(3)}'
          ':gg=${(0.8 + i * 0.05).toStringAsFixed(3)}'
          ':gb=${(0.05 * i).toStringAsFixed(3)}'
          ':br=0:bg=0:bb=${(0.7 + i * 0.1).toStringAsFixed(3)}');
    }
    if (p.sharpnessEnabled) {
      parts.add('unsharp=la=${(p.sharpness * 2).toStringAsFixed(2)}'
          ':ca=${p.sharpness.toStringAsFixed(2)}');
    }
    return parts.join(',');
  }

  Future<void> _applyAudioPrefs(PlayerPrefs p) async {
    // Hardware decoder
    await _np.setProperty('hwdec', p.hwDecoderEnabled ? 'auto' : 'no');
    // Deinterlace
    await _np.setProperty('deinterlace', p.deinterlaceEnabled ? 'yes' : 'no');

    // ── Build a single combined MPV audio filter chain (af=) ─────────────────
    // All active filters are joined with commas into ONE setProperty call.
    // Previously, multiple setProperty calls each overwrote the last — fixed.
    final afParts = <String>[];

    // 1. Dynamic audio normalization
    if (p.audioNormalization) {
      afParts.add('dynaudnorm=p=0.9:m=30');
    }

    // 2. 10-band parametric equalizer
    if (p.equalizerEnabled) {
      const freqs = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000];
      final b = p.equalizerBands;
      for (int i = 0; i < freqs.length; i++) {
        final gain = i < b.length ? b[i] : 0.0;
        if (gain.abs() > 0.05) {
          afParts.add('equalizer=f=${freqs[i]}:width_type=o:width=2:g=${gain.toStringAsFixed(1)}');
        }
      }
    }

    // 3. Dialogue boost — fixed speech-clarity EQ (2–6 kHz presence lift)
    if (p.dialogueBoostEnabled) {
      afParts.add('equalizer=f=310:width_type=o:width=2:g=2');
      afParts.add('equalizer=f=1000:width_type=o:width=2:g=5');
      afParts.add('equalizer=f=3000:width_type=o:width=2:g=4');
      afParts.add('equalizer=f=6000:width_type=o:width=2:g=2');
    }

    // 4. Bass Boost — low-shelf via two EQ bands (80 Hz + 120 Hz)
    //    bassBoostLevel 0–1 maps to 0–15 dB at 80 Hz, 0–8 dB at 120 Hz
    if (p.bassBoostEnabled && p.bassBoostLevel > 0.02) {
      final g1 = (p.bassBoostLevel * 15).toStringAsFixed(1);
      final g2 = (p.bassBoostLevel * 8).toStringAsFixed(1);
      afParts.add('equalizer=f=60:width_type=o:width=2:g=$g1');
      afParts.add('equalizer=f=120:width_type=o:width=2:g=$g2');
    }

    // 5. Vocal Remover — stereo phase-cancellation (karaoke effect)
    //    Subtracts the centre channel (where vocals are mixed in stereo).
    //    intensity 0.5 → subtle reduction; 0.75 → strong; 1.0 → full removal
    if (p.vocalRemoverEnabled) {
      final intensity = p.vocalRemoverIntensity.clamp(0.0, 1.0);
      final keep = (1.0 - intensity * 0.5).toStringAsFixed(3); // 0.750→0.625→0.500
      final sub  = (intensity * 0.5).toStringAsFixed(3);       // 0.250→0.375→0.500
      afParts.add('pan=stereo|c0=$keep*c0-$sub*c1|c1=$keep*c1-$sub*c0');
    }

    // 6. Virtual Surround — stereo widening via extrastereo
    //    m=1.5 (room) | 2.5 (theater) | 3.5 (stadium)
    if (p.surroundEnabled) {
      final m = p.surroundMode == 'theater'
          ? '2.5'
          : p.surroundMode == 'stadium'
              ? '3.5'
              : '1.5';
      afParts.add('extrastereo=m=$m');
    }

    // 7. Skip Silence detection (MPV silencedetect filter)
    if (p.skipSilenceEnabled) {
      final dur = p.skipSilenceThresholdSecs.toStringAsFixed(1);
      afParts.add('silencedetect=noise=-40dB:duration=$dur');
    }

    // 8. Smart Volume Leveling — MPV-side dynamic range compression
    if (p.smartVolumeLevelingEnabled) {
      final acomp = p.smartVolumeMode == 'aggressive'
          ? 'acompressor=threshold=0.5:ratio=8:attack=20:release=200:makeup=2'
          : p.smartVolumeMode == 'balanced'
              ? 'acompressor=threshold=0.7:ratio=4:attack=80:release=800:makeup=1.5'
              : 'acompressor=threshold=0.89:ratio=2:attack=300:release=2000:makeup=1';
      afParts.add(acomp);
    }
    // Dart-side volume ramp controller — update target/mode, start/stop
    _svc?.update(targetLevel: p.smartVolumeTarget, mode: p.smartVolumeMode);
    if (p.smartVolumeLevelingEnabled) { _svc?.start(); } else { _svc?.stop(); }

    // Commit the complete filter chain — empty string clears all filters
    await _np.setProperty('af', afParts.join(','));

    // Audio timing offset (sync delay in seconds)
    await _np.setProperty(
        'audio-delay',
        (p.audioTimingOffsetMs / 1000.0).toStringAsFixed(3));
  }

  Future<void> _applyVideoFilters(PlayerPrefs p) async {
    final vf = _buildVfString(p);
    await _np.setProperty('vf', vf);
  }

  void _applyVolumeBoost(double multiplier) {
    _volumeBoost = multiplier;
    // Step 1: system volume to max
    VolumeController().setVolume(1.0);
    // Step 2: MPV internal amplification (100 = normal, 300 = 3×)
    _np.setProperty('volume', '${(multiplier * 100).toInt()}');
  }

  Future<void> _applyAudioSync(int ms) async {
    _audioDelayMs = ms;
    await _np.setProperty('audio-delay', '${ms / 1000.0}');
  }

  Future<void> _applySubSync(int ms) async {
    _subDelayMs = ms;
    await _np.setProperty('sub-delay', '${ms / 1000.0}');
  }

  Future<void> _fetchPlaybackInfo() async {
    try {
      final codec  = await _np.getProperty('video-codec');
      final width  = await _np.getProperty('width');
      final height = await _np.getProperty('height');
      final fps    = await _np.getProperty('fps');
      final bits   = await _np.getProperty('video-bitrate');
      final buf    = await _np.getProperty('demuxer-cache-duration');
      final hwdec  = await _np.getProperty('hwdec-current');
      if (!mounted) return;
      setState(() {
        _piCodec   = codec ?? '—';
        _piRes     = (width != null && height != null) ? '${width}×${height}' : '—';
        _piFps     = fps != null ? '${double.tryParse(fps)?.toStringAsFixed(1) ?? fps} fps' : '—';
        _piBitrate = bits != null ? '${(int.tryParse(bits) ?? 0) ~/ 1000} kbps' : '—';
        _piBuffer  = buf != null ? '${double.tryParse(buf)?.toStringAsFixed(1) ?? buf}s' : '—';
        _piDecoder = (hwdec != null && hwdec.isNotEmpty && hwdec != 'no') ? 'HW' : 'SW';
      });
    } catch (_) {}
  }

  /// Triple-tap center = Rage Skip
  void _handleCenterTap() {
    // Immersive mode: tap = play/pause only, never show controls.
    if (_immersiveMode) {
      _player.playOrPause();
      _userPaused = !_playing;
      return;
    }
    if (!_prefs.rageSkipEnabled) { _toggleControls(); return; }
    _tapCount++;
    _tapTimer?.cancel();
    if (_tapCount >= 3) {
      _tapCount = 0;
      final skipSecs = _prefs.rageSkipSeconds;
      _seekRelative(skipSecs);
      HapticFeedback.heavyImpact();
      setState(() => _rageSkipActive = true);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _rageSkipActive = false);
      });
    } else {
      _tapTimer = Timer(const Duration(milliseconds: 600), () {
        _tapCount = 0;
        _toggleControls();
      });
    }
  }

  void _shareTimestamp() {
    final pos = _fmtDur(_position);
    Share.share('Watching ${widget.title} at $pos on RaddFlix');
  }

  // ── §3.3 item 5: Seek bar long-press → "Set intro end here" ──────────────
  void _onSeekBarLongPress() {
    if (_duration == Duration.zero) return;
    if (!SmartIntroStore.shouldShow(
        contentType: widget.contentType, totalDuration: _duration)) return;
    final pos = _fmtDur(_position);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Set Intro End',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'Set intro skip point to $pos?\n\nNext time this series plays, "Skip Intro" will jump to this position.',
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final seriesId = widget.fileId.split('/').first;
              await SmartIntroStore.saveIntroEnd(
                seriesId: seriesId,
                epIndex: _currentEpIdx,
                positionSeconds: _position.inSeconds);
              if (!mounted) return;
              setState(() {
                _savedIntroEnd = _position.inSeconds;
                _skipIntroVisible = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Intro end set to $pos'),
                    duration: const Duration(seconds: 2)));
            },
            child: const Text('Set Here',
                style: TextStyle(color: Color(0xFFE8002D), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── §3K: Frame-by-frame step ──────────────────────────────────────────────
  void _frameStep() {
    if (_playing) { _player.pause(); _userPaused = true; }
    _np.command(['frame-step']);
    setState(() => _showFrameStep = true);
  }

  void _frameBackStep() {
    if (_playing) { _player.pause(); _userPaused = true; }
    _np.command(['frame-back-step']);
    setState(() => _showFrameStep = true);
  }

  // ── §3K: Load chapter markers from MPV ───────────────────────────────────
  Future<void> _loadChapters() async {
    try {
      final raw = await _np.getProperty('chapter-list');
      if (raw == null || raw.isEmpty || _duration == Duration.zero) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final chapters = list.map((ch) {
        final timeSec = (ch['time'] as num? ?? 0).toDouble();
        return Duration(milliseconds: (timeSec * 1000).toInt());
      }).where((d) => d > Duration.zero).toList();
      if (mounted && chapters.isNotEmpty) setState(() => _chapters = chapters);
    } catch (_) {}
  }

  // ── Cinematic Mode ────────────────────────────────────────────────────────
  void _toggleCinematic() {
    setState(() => _cinematicMode = !_cinematicMode);
      // Phase H5: DND mode indicator on cinematic
      if (_cinematicMode && _prefs.dndOnCinematic) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('DND active — go to phone Settings to enable Do Not Disturb'),
          duration: Duration(seconds: 3)));
      }
    // Cinematic: controls still show/hide normally, just dimmed by _cinematicOpacity.
    if (_cinematicMode) _scheduleHide();
  }

  // ── Immersive Mode ────────────────────────────────────────────────────────
  void _toggleImmersive() {
    setState(() {
      _immersiveMode = !_immersiveMode;
      if (_immersiveMode) _showControls = false;
    });
  }

  void _showCinematicSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CinematicSettingsSheet(
        initialOpacity: _cinematicOpacity,
        // Live callback: slider in sheet immediately dims controls
        onOpacityChanged: (v) => setState(() => _cinematicOpacity = v),
      ),
    );
  }

  void _showImmersiveSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ImmersiveModeSettingsSheet(),
    );
  }

  // ── Scene Bookmark ────────────────────────────────────────────────────────
  Future<void> _addBookmarkAtPosition() async {
    if (_duration == Duration.zero) return;
    final emoji = await showBookmarkEmojiPicker(context);
    if (emoji == null) return;
    await SceneBookmarkStore.add(SceneBookmark(
      contentId: widget.fileId,
      episodeId: widget.episodes != null ? _currentEpIdx.toString() : null,
      positionMs: _position.inMilliseconds,
      emoji: emoji,
      createdAt: DateTime.now(),
    ));
    await _loadBookmarks();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bookmark $emoji added'), duration: const Duration(seconds: 2)));
  }

  Future<void> _deleteBookmark(int id) async {
    await SceneBookmarkStore.delete(id);
    await _loadBookmarks();
  }

  // ── Screenshot → Gallery ──────────────────────────────────────────────────
  void _openCastPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CastPanel(
        devices: _castDevices,
        connected: _connectedCastDevice,
        scanning: _castScanning,
        accentColor: _prefs.accentColor,
        onConnect: (d) => setState(() => _connectedCastDevice = d),
        onDisconnect: () => setState(() => _connectedCastDevice = null),
        onScanRequested: () {
          setState(() => _castScanning = true);
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _castScanning = false);
          });
        },
      ),
    );
  }

  // ── Phase C: Gesture Map ─────────────────────────────────────────────────
  void _openGestureMap() {
    Map<String, String> map = Map.from(kDefaultGestureMap);
    if (_prefs.gestureActionMapJson.isNotEmpty) {
      try { map = Map<String, String>.from(jsonDecode(_prefs.gestureActionMapJson)); } catch (_) {}
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureMapSheet(
        current: map,
        accentColor: _prefs.accentColor,
        onChanged: (newMap) {
          final encoded = jsonEncode(newMap);
          setState(() => _prefs = _prefs.copyWith(gestureActionMapJson: encoded));
          _prefs.save();
        },
      ),
    );
  }

  // ── Phase D1: Picture Profiles ────────────────────────────────────────────
  void _openPictureProfiles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PictureProfilesSheet(
        prefs: _prefs,
        accentColor: _prefs.accentColor,
        onApply: (newPrefs) {
          setState(() => _prefs = newPrefs);
          newPrefs.save();
          _applyVideoFilters(newPrefs);
        },
      ),
    );
  }

  // ── Phase E: Audio Lab ────────────────────────────────────────────────────
  void _openAudioLab() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioLabSheet(
        prefs: _prefs,
        accentColor: _prefs.accentColor,
        onChanged: (newPrefs) {
          setState(() => _prefs = newPrefs);
          newPrefs.save();
          _applyAudioPrefs(newPrefs);
        },
      ),
    );
  }

  // ── Phase P: Intro Skip Editor ────────────────────────────────────────────
  void _openIntroSkipEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IntroSkipEditor(
        videoId: widget.fileId,
        currentPosition: _previewPosition,
        totalDuration: _duration,
        accentColor: _prefs.accentColor,
        onSaved: () async {
          final segs = await IntroSkipStore.load(widget.fileId);
          if (mounted) setState(() => _skipSegments = segs);
        },
      ),
    );
  }

  // ── Load custom skip segments for this video ───────────────────────────────
  Future<void> _loadSkipSegments() async {
    final segs = await IntroSkipStore.load(widget.fileId);
    if (mounted) setState(() => _skipSegments = segs);
  }

  void _openAudioMixer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioMixerSheet(
        tracks: _audioTracks,
        selectedTrackId: _selectedAudioTrack,
        audioDelay: _prefs.audioDelay,
        accentColor: _prefs.accentColor,
        onTrackSelected: (id) {
          setState(() => _selectedAudioTrack = id);
          _applyAudioPrefs(_prefs);
        },
        onDelayChanged: (v) {
          setState(() => _prefs = _prefs.copyWith(audioDelay: v));
          _applyAudioPrefs(_prefs);
          _prefs.save();
        },
        onBalanceChanged: (v) {
          setState(() => _prefs = _prefs.copyWith(channelBalance: v));
          _applyAudioPrefs(_prefs);
          _prefs.save();
        },
        onBoostDialogueToggled: (v) {
          setState(() => _prefs = _prefs.copyWith(dialogueBoostEnabled: v));
          _applyAudioPrefs(_prefs);
          _prefs.save();
        },
      ),
    );
  }

  void _openClipTrimmer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipTrimmer(
        totalDuration: _duration,
        initialStart: _abLoopStart ?? _position,
        initialEnd:   _abLoopEnd   ?? (_position + const Duration(seconds: 30)),
        accentColor: _prefs.accentColor,
        onTrimChanged: (trim) {
          setState(() { _abLoopStart = trim.start; _abLoopEnd = trim.end; });
        },
        onExportClip: () => Navigator.pop(context),
        onExportGif:  () => Navigator.pop(context),
      ),
    );
  }

  void _openABLoop() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ABLoopPanel(
        pointA: _abLoopStart,
        pointB: _abLoopEnd,
        totalDuration: _duration,
        loopActive: _abLoopActive,
        accentColor: _prefs.accentColor,
        onSetA: () { Navigator.pop(context); setState(() => _abLoopStart = _position); },
        onSetB: () { Navigator.pop(context); setState(() => _abLoopEnd = _position); },
        onClearA: () => setState(() => _abLoopStart = null),
        onClearB: () => setState(() => _abLoopEnd = null),
        onLoopToggled: (v) => setState(() => _abLoopActive = v),
      ),
    );
  }

  void _openSpeedPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeedPickerSheet(
        currentSpeed: _speed,
        rememberSpeed: _prefs.rememberSpeed,
        accentColor: _prefs.accentColor,
        onSpeedChanged: (v) { setState(() => _speed = v); _player.setRate(v); },
        onRememberToggled: (v) {
          setState(() => _prefs = _prefs.copyWith(rememberSpeed: v));
          _prefs.save();
        },
        onPitchToggled: (_) {},
      ),
    );
  }

  void _openEqVisualizer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EqVisualizer(
        currentPreset: _prefs.equalizerPreset,
        bands: _prefs.equalizerBands,
        enabled: _prefs.equalizerEnabled,
        accentColor: _prefs.accentColor,
        onPresetChanged: (p) {
          setState(() => _prefs = _prefs.copyWith(equalizerPreset: p));
          _prefs.save();
        },
        onBandsChanged: (b) {
          setState(() => _prefs = _prefs.copyWith(equalizerBands: b));
          _applyAudioPrefs(_prefs);
          _prefs.save();
        },
        onToggle: (v) {
          setState(() => _prefs = _prefs.copyWith(equalizerEnabled: v));
          _applyAudioPrefs(_prefs);
          _prefs.save();
        },
      ),
    );
  }

  void _openBookmarkPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookmarkPanel(
        bookmarks: _bookmarks,
        currentPosition: _position,
        totalDuration: _duration,
        accentColor: _prefs.accentColor,
        onSeekTo: (pos) => _player.seek(pos),
        onAddBookmark: _addBookmarkAtPosition,
        onDeleteBookmark: (bm) => setState(() => _bookmarks.remove(bm)),
        onUpdateBookmark: (bm) {},
      ),
    );
  }

  void _openPlayerSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerSettingsScreen(
        prefs: _prefs,
        onSave: (p) {
          setState(() => _prefs = p);
          _applyVideoFilters(p);
          _applyAudioPrefs(p);
        },
      ),
    ));
  }

  void _openSleepTimer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SleepTimerSheet(
        currentTimer: _sleepDuration,
        fadeEnabled: _prefs.sleepFadeEnabled,
        fadeDurationSeconds: _prefs.sleepFadeDurationSeconds,
        accentColor: _prefs.accentColor,
        onTimerSet: (d) => setState(() => _sleepDuration = d),
        onCancel: () => setState(() => _sleepDuration = null),
        onFadeToggled: (v) {
          setState(() => _prefs = _prefs.copyWith(sleepFadeEnabled: v));
          _prefs.save();
        },
        onStopAtEpisodeEnd: (_) {},
      ),
    );
  }

  void _openVideoEnhanceSuite() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoEnhanceSuite(
        brightness:          _prefs.brightness,
        contrast:            _prefs.contrast,
        saturation:          _prefs.saturation,
        hue:                 _prefs.hue,
        sharpness:           _prefs.sharpness,
        sharpnessEnabled:    _prefs.sharpnessEnabled,
        nightMode:           _prefs.nightMode,
        nightModeIntensity:  _prefs.nightModeIntensity,
        cinematicMode:       _cinematicMode,
        cinematicOpacity:    _prefs.transparentModeOpacity,
        ambilightEnabled:    _prefs.ambilightEnabled,
        accentColor:         _prefs.accentColor,
        onChanged:           (map) {
          final next = _prefs.copyWith(
            brightness:       map['brightness']       as double?,
            contrast:         map['contrast']         as double?,
            saturation:       map['saturation']       as double?,
            hue:              map['hue']              as double?,
            sharpness:        map['sharpness']        as double?,
            sharpnessEnabled: map['sharpnessEnabled'] as bool?,
            nightMode:        map['nightMode']        as bool?,
            nightModeIntensity: map['nightModeIntensity'] as double?,
            ambilightEnabled: map['ambilightEnabled'] as bool?,
          );
          setState(() => _prefs = next);
          _applyVideoFilters(next);
          if (map['cinematicMode'] as bool? ?? false) {
            _toggleCinematic();
          }
          next.save();
        },
      ),
    );
  }

  void _openJumpTo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => JumpToSheet(
        currentPosition: _position,
        totalDuration:   _player.state.duration,
        accentColor:     _prefs.accentColor,
        onJumpTo:        (d) => _player.seek(d),
      ),
    );
  }

  void _openSpeedPresets() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeedPresetsSheet(
        presetsJson:      _prefs.customSpeedPresetsJson,
        currentSpeed:     _speed,
        accentColor:      _prefs.accentColor,
        onSpeedSelected:  (s) {
          setState(() => _speed = s);
          _player.setRate(s);
        },
        onPresetsChanged: (json) {
          final next = _prefs.copyWith(customSpeedPresetsJson: json);
          setState(() => _prefs = next);
          next.save();
        },
      ),
    );
  }

  void _openEndAction() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EndActionSheet(
        prefs:       _prefs,
        accentColor: _prefs.accentColor,
        onChanged:   (next) {
          setState(() => _prefs = next);
          next.save();
        },
      ),
    );
  }

  void _openZoomCrop() {
    setState(() => _showZoomOverlay = !_showZoomOverlay);
    // Restore saved zoom level on first open
    if (_showZoomOverlay && _zoomLevel == 1.0 && _prefs.savedZoomLevel > 1.0) {
      setState(() => _zoomLevel = _prefs.savedZoomLevel);
    }
  }

  void _startWakeTimer() {
    _wakeTimer?.cancel();
    if (_prefs.wakeTimeoutMins <= 0) return; // 0 = always on
    _wakeTimer = Timer(Duration(minutes: _prefs.wakeTimeoutMins), () {
      WakelockPlus.disable();
    });
  }

  void _onUserActivity() {
    // Re-enable wakelock + restart timeout on any user interaction
    WakelockPlus.enable();
    _startWakeTimer();
  }

  void _openSilenceSkip() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SilenceSkipSheet(
        prefs:       _prefs,
        accentColor: _prefs.accentColor,
        onChanged:   (next) {
          setState(() => _prefs = next);
          _applyAudioPrefs(next);
          _applyVideoFilters(next); // color blind mode re-trigger
          next.save();
        },
      ),
    );
  }


  Future<void> _takeScreenshot() async {
    try {
      final frame = await _player.screenshot();
      if (frame == null) return;
      final result = await SaverGallery.saveImage(
        frame,
        fileName: 'raddflix_${DateTime.now().millisecondsSinceEpoch}',
        androidRelativePath: 'Pictures',
        skipIfExists: false,
      );
      if (result.isSuccess != true) throw Exception('Save failed');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot saved to gallery'),
            duration: Duration(seconds: 2)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save screenshot'),
            duration: Duration(seconds: 2)));
    }
  }

  Future<void> _showJumpToTime() async {
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Jump to Timestamp',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Enter time as SS, MMSS, or HHMMSS',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 20),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '4520 → 45:20',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE8002D))),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8002D)),
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  child: const Text('Go', style: TextStyle(color: Colors.white)))),
            ]),
          ]),
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    final n = int.tryParse(result);
    if (n == null) return;
    Duration target;
    if (result.length <= 2) {
      target = Duration(seconds: n);
    } else if (result.length <= 4) {
      final m = n ~/ 100; final s = n % 100;
      target = Duration(minutes: m, seconds: s);
    } else {
      final h = n ~/ 10000; final m = (n % 10000) ~/ 100; final s = n % 100;
      target = Duration(hours: h, minutes: m, seconds: s);
    }
    _player.seek(target);
  }

  Future<void> _restoreTrackMemory() async {
      try {
        final sp = await SharedPreferences.getInstance();
        final savedAudioLang = sp.getString('player_last_audio_lang');
        final savedSubLang   = sp.getString('player_last_sub_lang');
        if (savedAudioLang != null && _prefs.rememberAudioTrack) {
          final tracks = _player.state.tracks.audio;
          for (int i = 0; i < tracks.length; i++) {
            if (tracks[i].language == savedAudioLang) {
              setState(() => _activeAudioIdx = i);
              _player.setAudioTrack(tracks[i]);
              break;
            }
          }
        }
        if (savedSubLang != null && _prefs.rememberSubtitleTrack) {
          final tracks = _player.state.tracks.subtitle;
          for (int i = 0; i < tracks.length; i++) {
            if (tracks[i].language == savedSubLang) {
              setState(() => _activeSubIdx = i);
              _player.setSubtitleTrack(tracks[i]);
              break;
            }
          }
        }
        // §3.15 Item 5: if no saved audio pref, auto-select by device locale
        if (savedAudioLang == null || !_prefs.rememberAudioTrack) {
          _autoSelectTrackByLocale();
        }
      } catch (_) {}
    }
  
    // §3.16F: Headphone button double/triple press ────────────────────────────
    bool _onHardwareKey(KeyEvent event) {
      if (event is! KeyDownEvent) return false;
      if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        _handleMediaButtonPress();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
        if (_hasNextEp) _playNextEpisode();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
        _player.seek(_position - const Duration(seconds: 10));
        return true;
      }
      return false;
    }

    void _handleMediaButtonPress() {
      _mediaButtonPressCount++;
      _mediaButtonTimer?.cancel();
      _mediaButtonTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        final count = _mediaButtonPressCount;
        _mediaButtonPressCount = 0;
        if (count == 1) {
          setState(() => _userPaused = _playing);
          _player.playOrPause();
        } else if (count == 2) {
          // Double-press → next episode
          if (_hasNextEp) _playNextEpisode();
        } else {
          // Triple-press → seek back 10 s
          _player.seek(_position - const Duration(seconds: 10));
        }
      });
    }

    // §3.16D: Long-press play button = restart from beginning ─────────────────
    void _onLongPressPlay() {
      if (!_prefs.longPressPlayRestart) return;
      _player.seek(Duration.zero);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⏮ Restarting from beginning'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }

    // §3.15 Item 5: Auto-select audio track by device locale ──────────────────
    void _autoSelectTrackByLocale() {
      try {
        final deviceLang =
            WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
        final tracks = _player.state.tracks.audio;
        if (tracks.isEmpty) return;
        // For Hindi/Urdu device locales: prefer hin-tagged track first (most
        // South-Asian content uses hin even for Urdu dubs), then urd.
        // Never force-select Urdu as a default.
        final List<String> preferred;
        if (deviceLang == 'hi' || deviceLang == 'ur') {
          preferred = ['hin', 'hi', 'urd', 'ur'];
        } else {
          preferred = [deviceLang];
        }
        for (final lang in preferred) {
          for (int i = 0; i < tracks.length; i++) {
            final tLang = (tracks[i].language ?? '').toLowerCase();
            if (tLang == lang) {
              if (_activeAudioIdx != i) {
                setState(() => _activeAudioIdx = i);
                _player.setAudioTrack(tracks[i]);
              }
              return;
            }
          }
        }
      } catch (_) {}
    }
  
    void _initBingeGuard() {
    _bingeGuardCtrl?.dispose();
    if (!_prefs.bingeGuardEnabled) return;
    _bingeGuardCtrl = BingeGuardController(
      thresholdMinutes: _prefs.bingeGuardThresholdMinutes,
      onThreshold: () {
        if (mounted) {
          _player.pause();
          setState(() {
            _showBingeGuard = true;
            _bingeWatchedMins = _bingeGuardCtrl?.watchedMinutes ?? 0;
          });
        }
      },
    );
  }

  void _initAmbilight() {
    _ambilightCtrl?.dispose();
    if (!_prefs.ambilightEnabled) return;
    _ambilightCtrl = AmbilightController(
      player: _player,
      intervalMs: _prefs.ambilightSampleIntervalMs,
      onUpdate: (colors) {
        if (mounted) setState(() => _ambilightColors = colors);
      },
    );
    _ambilightCtrl!.start();
  }

  void _applyRotation(String mode) {
    switch (mode) {
      case 'auto':
        // Empty list = OS controls all orientations (MX Player-style auto-rotate)
        SystemChrome.setPreferredOrientations([]);
        break;
      case 'lock_left':
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
        break;
      case 'lock_right':
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight]);
        break;
      case 'lock_portrait':
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        break;
      case 'lock_current':
        final mq = WidgetsBinding.instance.renderViews.first.flutterView.physicalSize;
        final isLandscape = mq.width > mq.height;
        SystemChrome.setPreferredOrientations(isLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
        break;
      default: // 'sensor_landscape'
        SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    setState(() => _prefs = _prefs.copyWith(rotationMode: mode));
    _prefs.copyWith(rotationMode: mode).save();
  }

  void _cycleRotation() {
    const order = ['sensor_landscape', 'auto', 'lock_left', 'lock_right', 'lock_portrait'];
    final idx = order.indexOf(_prefs.rotationMode);
    final next = order[(idx + 1) % order.length];
    _applyRotation(next);
    HapticFeedback.selectionClick();
  }

  /// Called when JazzDrive stream errors (XML page / expired token).
  /// Equivalent of "delete cookies + reload" in a browser.
  void _jazzAutoRetry(String reason) {
    if (_jazzRetryCount >= 1) {
      // Already retried once — show error overlay
      if (mounted) setState(() => _streamError = reason);
      return;
    }
    _jazzRetryCount++;
    if (mounted) {
      setState(() {
        _streamError = null;
        _isLinkLoading = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Refreshing video link…'),
        duration: Duration(seconds: 2),
      ));
    }
    // Wipe stale cached URL — forces fresh JazzDrive login + new CDN token
    JazzDriveService.invalidate(widget.fileId);
    _openMedia(widget.fileId);
  }
  double _brightness = 0.5;
  double _volume = 0.7;

  // Helper: access MPV-level setProperty / getProperty / command
  NativePlayer get _np => _player.platform as NativePlayer;

  Future<void> _initPlayer() async {
    _player = Player();
    _videoCtrl = VideoController(_player);
    await _openMedia(widget.fileId, localPath: widget.localPath);
    _loadSkipSegments(); // Phase P: load custom skip segments
    // Phase SVL: Smart Volume Leveling controller
    _svc = _SmartVolumeController(
      player: _player, np: _np,
      targetLevel: _prefs.smartVolumeTarget,
      mode:        _prefs.smartVolumeMode,
    );
    if (_prefs.smartVolumeLevelingEnabled) _svc!.start();

    _player.stream.position.listen((p) {
      if (!mounted) return;
      _position = p;
      _positionNotifier.value = p;
      // Phase P: active skip segment check
      final _activeSeg = IntroSkipStore.activeAt(_skipSegments, p);
      if (_activeSeg != _activeSkipSegment) {
        setState(() => _activeSkipSegment = _activeSeg);
      }
      // A-B Loop
      final seekBack = _abLoop.maybeSeekBack(p);
      if (seekBack != null) _player.seek(seekBack);
      if (p.inSeconds % 10 == 0 && _duration.inMilliseconds > 0) {
        LocalDb.saveWatchPosition(
            fileId: widget.fileId,
            positionMs: p.inMilliseconds,
            durationMs: _duration.inMilliseconds);
      }
      // Sleep countdown handled by _sleepTimer
    });
    _player.stream.duration.listen((d) {
      if (!mounted) return;
      _duration = d;
      _durationNotifier.value = d;
      // Load chapter markers once duration is known
      if (d.inSeconds > 0) _loadChapters();
    });
    _player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
      if (b) {
        if (!_isLocalFile) {
          _slowConnTimer?.cancel();
          _slowConnTimer = Timer(const Duration(seconds: 8), () {
            if (!mounted || !_buffering) return;
            if (!_slowConnectionShown) {
              _slowConnectionShown = true;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Slow connection — video may stutter'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      } else {
        _slowConnTimer?.cancel();
        _slowConnectionShown = false;
      }
    });
    _player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
      if (p) {
        _bingeGuardCtrl?.onPlay();
        _sessionStartTime ??= DateTime.now();
      } else {
        _bingeGuardCtrl?.onPause();
      }
    });
    _player.stream.buffer.listen((b) {
      if (!mounted) return;
      setState(() => _bufferedPosition = b);
    });
    _player.stream.completed.listen((done) {
      if (!mounted || !done) return;
      setState(() => _ended = true);
      _onPlaybackEnded();
    });

    // Track list -> restore saved language preferences
    _player.stream.tracks.listen((_) {
      if (mounted && _activeAudioIdx == 0) _restoreTrackMemory();
    });

    // Subtitle text -> custom SubtitleOverlay
    _player.stream.subtitle.listen((lines) {
      if (!mounted) return;
      final text = lines.where((l) => l.trim().isNotEmpty).join('\n');
      setState(() => _currentSubtitleText = text.isEmpty ? null : text);
    });

    // ── JazzDrive XML error detection ──────────────────────────────────────
    // Layer 1: MPV fires a hard error (expired token, DNS fail, etc.)
    _player.stream.error.listen((err) {
      if (!mounted || _isLocalFile) return;
      // Skip error popup if video is already playing fine
      if (_playing && _position.inSeconds > 3) return;
      DebugLogger.logError('PLAYER', 'Stream error: $err');
      _jazzAutoRetry(err);
    });

    // Layer 2: Wait 8s — only trigger if duration still zero AND video not started
    _jazzRetryTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _isLocalFile || _jazzRetryCount > 0) return;
      // Key fix: !_playing ensures we don't show error popup during actual playback
      if (_duration == Duration.zero && !_isLinkLoading && !_playing && !_buffering) {
        DebugLogger.logError('PLAYER', 'Duration still zero after 8s and not playing');
        _jazzAutoRetry('Stream returned non-video content (possible XML error page)');
      }
    });

    // Smart skip intro: load saved position or show at 85s default
    _skipIntroTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      if (!SmartIntroStore.shouldShow(
          contentType: widget.contentType,
          totalDuration: _duration)) return;
      if (!_prefs.showSkipIntroButton) return;
      final seriesId = widget.fileId.split('/').first;
      final saved = await SmartIntroStore.getIntroEnd(
          seriesId: seriesId, epIndex: _currentEpIdx);
      setState(() { _savedIntroEnd = saved; });
      if (_duration.inSeconds > 60) {
        setState(() => _skipIntroVisible = true);
        if (_prefs.autoSkipIntroEnabled && saved != null) {
          _player.seek(Duration(seconds: saved));
          setState(() => _skipIntroVisible = false);
          return;
        }
        Timer(const Duration(seconds: 8), () {
          if (mounted) setState(() => _skipIntroVisible = false);
        });
      }
    });
  }

  /// Returns true when [path] is a device-local file path or URI.
  static bool _isLocalPath(String path) =>
      path.startsWith('/') ||
      path.startsWith('file://') ||
      path.startsWith('content://');

  Future<void> _openMedia(String fileId, {String? localPath}) async {
    // FIX-LOCAL: detect local paths passed as fileId (e.g. gallery videos).
    final effectiveLocalPath = (localPath != null && localPath.isNotEmpty)
        ? localPath
        : (_isLocalPath(fileId) ? fileId : null);
    if (effectiveLocalPath != null) {
      _currentPlaybackUrl = effectiveLocalPath;
      await _player.open(Media(effectiveLocalPath));
      setState(() { _ended = false; _position = Duration.zero; });
      return;
    }

    if (mounted) setState(() => _isLinkLoading = true);

    // Step 0.5: Read inline share_url from route args BEFORE any await
    // (BuildContext is only safe to use synchronously before first await)
    final _routeArgs = ModalRoute.of(context)?.settings.arguments as Map?;
    final _inlineShareUrl = _routeArgs?['stream_url'] as String?;

    // Step 1: Get share_url from local DB (fast, works offline on Jazz SIM)
    String? shareUrl = fileId.isNotEmpty ? await LocalDb.getShareUrl(fileId) : null;

    // Step 2: If not in local DB, try inline shareUrl or ask Oracle
    if (shareUrl == null || shareUrl.isEmpty) {
      if (_inlineShareUrl != null && _inlineShareUrl.isNotEmpty) {
        // Caller passed shareUrl directly (handles movies without file_id in catalog)
        shareUrl = _inlineShareUrl;
        DebugLogger.log('PLAYER', 'Using inline share_url for ${fileId.isEmpty ? "direct-share" : fileId}');
      } else if (fileId.isNotEmpty) {
        // Oracle stores catalog metadata (incl. share_urls) — NOT the video files.
        try {
          shareUrl = await CatalogApi.getShareUrl(fileId);
          DebugLogger.log('PLAYER', 'Got share_url from Oracle for ${fileId}');
        } catch (e) {
          DebugLogger.logError('PLAYER', 'Oracle share_url lookup failed for ${fileId}', e);
        }
      }
    }

    // Step 3: Generate direct CDN stream URL via JazzDrive (zero-rated on Jazz SIM)
    if (shareUrl != null && shareUrl.isNotEmpty) {
      final cacheKey = fileId.isNotEmpty ? fileId : 'share_\${shareUrl.hashCode}';
      try {
        final link = await JazzDriveService.getStreamLink(cacheKey, shareUrl);
        _currentPlaybackUrl = link.streamUrl;
        await _player.open(Media(link.streamUrl));
        if (mounted) setState(() { _ended = false; _position = Duration.zero; _isLinkLoading = false; });
        return;
      } catch (e) {
        DebugLogger.logError('PLAYER', 'JazzDrive stream link failed for \$cacheKey', e);
        // Step 3b: shareUrl may be stale/expired — force-refresh from Oracle and retry once
        if (fileId.isNotEmpty) {
          try {
            final freshUrl = await CatalogApi.getShareUrl(fileId);
            if (freshUrl != null && freshUrl.isNotEmpty) {
              await JazzDriveService.invalidate(fileId);
              final link2 = await JazzDriveService.getStreamLink(fileId, freshUrl);
              _currentPlaybackUrl = link2.streamUrl;
              await _player.open(Media(link2.streamUrl));
              if (mounted) setState(() { _ended = false; _position = Duration.zero; _isLinkLoading = false; });
              return;
            }
          } catch (e2) {
            DebugLogger.logError('PLAYER', 'Oracle+JazzDrive retry failed for \$fileId', e2);
          }
        }
      }
    }

    // All methods failed — show sync guidance
    if (mounted) {
      setState(() {
        _isLinkLoading = false;
        _streamError = (shareUrl == null || shareUrl.isEmpty)
            ? 'No stream link found. Please sync your library in Settings → Sync.'
            : 'Stream link expired. Tap Retry to refresh.';
      });
    }
  }


  /// Launch the current video in an external player (MX Player, VLC, etc.)
  Future<void> _openWithExternalPlayer() async {
    final url = _currentPlaybackUrl;
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No video loaded yet'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }
    try {
      const ch = MethodChannel('com.raddflix.app/intent');
      await ch.invokeMethod('openVideoWith', {'uri': url});
    } catch (e) {
      // Fallback: use share_plus to share the URL/file with other apps
      try {
        await Share.shareUri(Uri.parse(url.startsWith('/') ? 'file://$url' : url));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open external player'), duration: Duration(seconds: 2)),
          );
        }
      }
    }
  }

  void _onPlaybackEnded() {
    _logWatchSession();
    // FIX-SLEEP: if "End of episode" sleep timer is set, pause here
    if (_sleepAtEpisodeEnd) {
      _sleepAtEpisodeEnd = false;
      _player.pause();
      _userPaused = true;
      setState(() => _showControls = true);
      return;
    }
    if (_hasNextEp && (_prefs.endOfVideoAction == 'play_next' || _prefs.endOfVideoAction == '')) {
      _startNextEpCountdown();
    } else {
      switch (_prefs.endOfVideoAction) {
        case 'loop':
          _player.seek(Duration.zero);
          _player.play();
          break;
        case 'return_home':
          if (mounted) Navigator.pop(context);
          break;
        case 'nothing':
          setState(() { _showControls = true; _ended = true; });
          break;
        default: // play_next or when no next ep
          setState(() => _showControls = true);
      }
    }
  }


  // ── Usage tracking helpers ────────────────────────────────────────────────
  /// Maps player resolution string (e.g. "1920x1080") to a quality label.
  String get _qualityFromRes {
    if (_piRes.contains('1080')) return '1080p';
    if (_piRes.contains('720'))  return '720p';
    if (_piRes.contains('480'))  return '480p';
    return '360p';
  }

  /// Call at session end or dispose to record watch time to usage log.
  void _logWatchSession() {
    final start = _sessionStartTime;
    if (start == null) return;
    _sessionStartTime = null;
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds < 5) return; // ignore very short views
    UsageService.addWatchSession(seconds: seconds, quality: _qualityFromRes);
  }

  /// Check data quota before playback; also enforces plan expiry for offline
  /// files (task 6.9). Reads the quota cache — no network call needed.
  Future<void> _checkQuota() async {
    try {
      final quota = await UsageService.getCachedQuota();

      // 6.9 — offline plan expiry: block if subscription has expired
      if (widget.localPath != null) {
        final subExpiresAt = quota['sub_expires_at'];
        if (subExpiresAt != null && subExpiresAt is int && subExpiresAt > 0) {
          final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (subExpiresAt < nowUnix) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacementNamed(AppRoutes.planExpired);
            });
            return;
          }
        }
      }

      if (quota['allowed'] == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(AppRoutes.quotaFull);
        });
      }
    } catch (_) {}
  }

  void _startNextEpCountdown() {
    setState(() {
      _showNextEpisode = true;
      _nextCountdown = 7;
      _showControls = false;
    });
    _nextEpTimer?.cancel();
    _nextEpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _nextCountdown--);
      if (_nextCountdown <= 0) {
        t.cancel();
        _playNextEpisode();
      }
    });
  }

  void _playNextEpisode() {
    if (!_hasNextEp) return;
    _nextEpTimer?.cancel();
    final next = widget.episodes![_currentEpIdx + 1];
    final nextFileId = next['file_id']?.toString() ?? '';
    setState(() {
      _currentEpIdx++;
      _showNextEpisode = false;
      _ended = false;
      _position = Duration.zero;
      _skipIntroVisible = false;
    });
    _openMedia(nextFileId);
    _skipIntroTimer?.cancel();
    _skipIntroTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      if (!SmartIntroStore.shouldShow(
          contentType: widget.contentType,
          totalDuration: _duration)) return;
      if (!_prefs.showSkipIntroButton) return;
      final seriesId = widget.fileId.split('/').first;
      final saved = await SmartIntroStore.getIntroEnd(
          seriesId: seriesId, epIndex: _currentEpIdx);
      if (!mounted) return;
      setState(() { _savedIntroEnd = saved; _skipIntroVisible = _duration.inSeconds > 60; });
      if (_prefs.autoSkipIntroEnabled && saved != null && _duration.inSeconds > 60) {
        _player.seek(Duration(seconds: saved));
        setState(() => _skipIntroVisible = false);
        return;
      }
      Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _skipIntroVisible = false);
      });
    });
  }

  String get _currentTitle {
    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      final ep = widget.episodes![_currentEpIdx];
      return ep['label'] as String? ?? widget.title;
    }
    return widget.title;
  }

  String get _nextEpLabel {
    if (!_hasNextEp) return '';
    final ep = widget.episodes![_currentEpIdx + 1];
    return ep['label'] as String? ?? 'Episode ${_currentEpIdx + 2}';
  }

  // ── Sleep Timer ───────────────────────────────────────────────────────────
  void _startSleepFade() {
    if (_sleepFadeActive) return;
    _sleepFadeActive = true;
    _preFadeVolume = _volume;
    final steps = _prefs.sleepFadeDurationSeconds.clamp(5, 120);
    var step = 0;
    _sleepFadeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !_sleepFadeActive) { t.cancel(); return; }
      step++;
      final fraction = step / steps;
      final newVol = ((1.0 - fraction) * _preFadeVolume).clamp(0.0, 1.0);
      VolumeController().setVolume(newVol);
      _np.setProperty('volume', '${(newVol * _volumeBoost * 100).toInt()}');
      if (step >= steps) t.cancel();
    });
  }

  void _restoreVolumeAfterSleep() {
    _sleepFadeTimer?.cancel();
    _sleepFadeActive = false;
    VolumeController().setVolume(_preFadeVolume);
    _np.setProperty('volume', '${(_volumeBoost * 100).toInt()}');
  }

  void _setSleepTimer(int minutes) {
    _cancelSleepTimer();
    // FIX-SLEEP: -1 = "End of episode" — pause when playback ends naturally
    if (minutes == -1) {
      setState(() => _sleepAtEpisodeEnd = true);
      return;
    }
    if (minutes <= 0) return;
    setState(() => _sleepRemainingSeconds = minutes * 60);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _sleepRemainingSeconds = (_sleepRemainingSeconds ?? 0) - 1;

        // Start volume fade when N seconds remain
        if (_prefs.sleepFadeEnabled &&
            !_sleepFadeActive &&
            _sleepRemainingSeconds! > 0 &&
            _sleepRemainingSeconds! <= _prefs.sleepFadeDurationSeconds) {
          _startSleepFade();
        }

        if (_sleepRemainingSeconds! <= 0) {
          t.cancel();
          _sleepRemainingSeconds = null;
          _restoreVolumeAfterSleep();
          _player.pause();
          _userPaused = true;
          setState(() => _showControls = true);
        }
      });
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepFadeTimer?.cancel();
    if (_sleepFadeActive) _restoreVolumeAfterSleep();
    _sleepFadeActive = false;
    // FIX-SLEEP: also clear end-of-episode flag
    setState(() { _sleepRemainingSeconds = null; _sleepAtEpisodeEnd = false; });
  }

  // ── PiP ──────────────────────────────────────────────────────────────────
  Future<void> _enterPiP() async {
    try {
      await _pipChannel.invokeMethod('enterPiP');
      setState(() => _inPiP = true);
    } catch (_) {}
  }

  Future<void> _enterCast() async {
    await CastService.discoverDevices();
    final connected = await CastService.isConnected();
    if (!mounted) return;
    if (connected) {
      // Already casting — show disconnect option
      final stop = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Casting Active', style: TextStyle(color: Colors.white)),
          content: const Text('Stop casting to this device?',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep Casting')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Stop', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
      if (stop == true) {
        await CastService.stop();
        await CastService.disconnect();
        if (mounted) setState(() => _castConnected = false);
      }
      return;
    }
    // No device found via discovery — open system Cast dialog
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final url  = args?['stream_url'] as String? ?? args?['local_path'] as String? ?? '';
    final title = args?['title'] as String? ?? widget.title;
    final ok = await CastService.castVideo(
      url: url,
      title: title,
      positionMs: _position.inMilliseconds,
    );
    if (mounted) setState(() => _castConnected = ok);
  }

  // ── Seek Thumbnail ────────────────────────────────────────────────────────
  void _updateSeekThumb(double fraction) {
    if (!_isLocalFile) return;
    // FIX-LOCAL-2: use effective path — widget.localPath OR fileId for gallery videos
    final videoPath = (widget.localPath != null && widget.localPath!.isNotEmpty)
        ? widget.localPath!
        : widget.fileId;
    _seekThumbDebounce?.cancel();
    _svc?.dispose();
    _wakeTimer?.cancel();
    _jazzRetryTimer?.cancel();
    _seekThumbDebounce = Timer(const Duration(milliseconds: 120), () async {
      final ms = (fraction * _duration.inMilliseconds).toInt();
      try {
        final thumb = await VideoThumbnail.thumbnailData(
          video: videoPath,
          timeMs: ms,
          quality: 60,
          maxWidth: 160,
        );
        if (mounted) setState(() => _seekThumb = thumb);
      } catch (_) {}
    });
  }

  // ── Gesture Handlers (unified onScale) ────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _dragStartLocal = d.localFocalPoint;
    _startBrightness = _brightness;
    _startVolume = _volume;
    _startVolumeBoost = _volumeBoost;
    _inBoostGesture = false;
    _dragStartPosition = _position;
    if (d.pointerCount >= 2) {
      _dragIntent = 'pinch';
      _startScale = _scale;
    } else {
      _dragIntent = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_locked) return;

    // Pinch-to-zoom
    if (d.pointerCount >= 2 || _dragIntent == 'pinch') {
      _dragIntent = 'pinch';
      setState(() => _scale = (_startScale * d.scale).clamp(1.0, 5.0));
      return;
    }

    final delta = d.localFocalPoint - _dragStartLocal;
    final size = MediaQuery.of(context).size;

    // Determine drag intent once.
    // FIX-GESTURE: horizontal must dominate 2:1 AND exceed 24px to be 'seek'.
    // Vertical only needs 1.5:1 dominance and 8px so brightness/volume swipes
    // are reliably detected even when the finger has slight horizontal drift.
    if (_dragIntent == null) {
      final isDefinitelyHorizontal =
          delta.dx.abs() > delta.dy.abs() * 2.0 && delta.dx.abs() > 24;
      final isDefinitelyVertical =
          delta.dy.abs() > delta.dx.abs() * 1.5 && delta.dy.abs() > 8;
      if (isDefinitelyHorizontal) {
        _dragIntent = 'seek';
      } else if (isDefinitelyVertical) {
        // MX Player: vertical swipe = brightness (left) or volume (right) on both up and down
        _dragIntent =
            d.localFocalPoint.dx < size.width / 2 ? 'brightness' : 'volume';
      }
    }

    switch (_dragIntent) {
      case 'brightness':
        final newB =
            (_startBrightness - delta.dy / size.height * 1.5).clamp(0.0, 1.0);
        ScreenBrightness().setScreenBrightness(newB);
        setState(() {
          _brightness = newB;
          _draggingBrightness = true;
          _draggingVolume = false;
        });
      case 'volume':
        // Raw value — may exceed 1.0 if starting at max and still swiping up
        final rawV = _startVolume - delta.dy / size.height * 1.5;
        if (rawV <= 1.0) {
          // Normal system volume range 0–100%
          final newV = rawV.clamp(0.0, 1.0);
          VolumeController().setVolume(newV);
          _np.setProperty('volume', '${(newV * _volumeBoost * 100).toInt()}');
          setState(() {
            _volume = newV;
            _inBoostGesture = false;
            _draggingVolume = true;
            _draggingBrightness = false;
          });
        } else {
          // Swipe-into-boost: system at max, MPV internal amplification 100%→300%
          final boostDelta = (rawV - 1.0) * 2.5; // 2.5× gain per screen-height above max
          final newBoost = (_startVolumeBoost + boostDelta).clamp(1.0, 3.0);
          VolumeController().setVolume(1.0); // system stays at max
          _np.setProperty('volume', '${(newBoost * 100).toInt()}');
          if (newBoost > 2.0) HapticFeedback.mediumImpact(); // haptic at 200%+
          setState(() {
            _volume = 1.0;
            _volumeBoost = newBoost;
            _inBoostGesture = true;
            _draggingVolume = true;
            _draggingBrightness = false;
          });
        }
      case 'seek':
        // Max 2 min per full-width swipe
        final seconds =
            (delta.dx / size.width * 120).clamp(-120.0, 120.0);
        setState(() {
          _dragSeekDelta = seconds;
          _draggingSeek = true;
        });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Persist volume boost if changed via swipe-into-boost
    if (_inBoostGesture && _volumeBoost != _startVolumeBoost) {
      final np = _prefs.copyWith(volumeBoostMultiplier: _volumeBoost);
      setState(() => _prefs = np);
      np.save();
    }
    _inBoostGesture = false;
    if (_dragIntent == 'seek' && _dragSeekDelta != null) {
      final newPos =
          _dragStartPosition + Duration(seconds: _dragSeekDelta!.toInt());
      _player.seek((newPos < Duration.zero ? Duration.zero : newPos > _duration ? _duration : newPos));
    }
    setState(() {
      _draggingBrightness = false;
      _draggingVolume = false;
      _draggingSeek = false;
      _dragSeekDelta = null;
      _dragIntent = null;
    });
  }

  // ── Subtitle File Picker ──────────────────────────────────────────────────
  Future<void> _pickSubtitle() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['srt', 'ass', 'vtt']);
    if (r == null || r.files.single.path == null) return;
    await _player.setSubtitleTrack(SubtitleTrack.uri(r.files.single.path!));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _quotaTimer?.cancel();
    _skipIntroTimer?.cancel();
    _nextEpTimer?.cancel();
    _sleepTimer?.cancel();
    _sleepFadeTimer?.cancel();
    _slowConnTimer?.cancel();
    _seekThumbDebounce?.cancel();
    _svc?.dispose();
    _wakeTimer?.cancel();
    _jazzRetryTimer?.cancel();
    _tapTimer?.cancel();
    _ambilightCtrl?.dispose();
    _bingeGuardCtrl?.dispose();
    _logWatchSession(); // log partial session on exit
    if (_position.inMilliseconds > 0 && _duration.inMilliseconds > 0) {
      LocalDb.saveWatchPosition(
          fileId: widget.fileId,
          positionMs: _position.inMilliseconds,
          durationMs: _duration.inMilliseconds);
      // BUG-A08/A19: sync position to server on player exit.
      // BUG-A11: server expects position_ms/duration_ms in milliseconds.
      // watched_at in GET /api/history is epoch SECONDS — use
      // DateTime.fromMillisecondsSinceEpoch(watchedAt * 1000) to parse.
      HistoryApi.syncPosition(
          fileId: widget.fileId,
          positionMs: _position.inMilliseconds,
          durationMs: _duration.inMilliseconds);
    }
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Restore full auto-rotate so system works normally after player exit
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
      _mediaButtonTimer?.cancel();
      super.dispose();
  }

  void _scheduleHide() {
    // Never schedule hide/show for standard controls in Immersive mode.
    if (_immersiveMode) return;
    _hideTimer?.cancel();
    final secs = _prefs.autoHideSeconds;
    if (secs <= 0) return; // never auto-hide
    _hideTimer = Timer(Duration(seconds: secs), () {
      if (mounted &&
          !_showSpeedPicker &&
          !_showSubtitleMenu &&
          !_showAudioMenu &&
          !_showSleepMenu &&
          !_showQuickSettings &&
          !_showEqPanel &&
          !_showAudioSyncPanel &&
          !_showSubSyncPanel &&
          !_showAbPanel &&
          !_showBookmarksPanel &&
          !_showVideoEnhance &&
          !_showMorePanel) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showNextEpisode) return;
    if (_immersiveMode) return; // controls never show in immersive
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _seekRelative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    _player.seek((target < Duration.zero ? Duration.zero : target > _duration ? _duration : target));
    final label = seconds > 0 ? '+${seconds}s' : '${seconds}s';
    setState(() {
      if (seconds > 0) {
        _showSeekRight = true;
        _seekLabel = label;
      } else {
        _showSeekLeft = true;
        _seekLabel = label;
      }
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() {
        _showSeekLeft = false;
        _showSeekRight = false;
      });
    });
  }

  void _cycleFit() => setState(() => _ratioIdx = (_ratioIdx + 1) % _ratios.length);

  String get _fitLabel {
    switch (_ratios[_ratioIdx]) {
      case BoxFit.contain: return 'Fit';
      case BoxFit.cover:   return 'Zoom';
      default:             return 'Fill';
    }
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progressFraction => _duration.inMilliseconds > 0
      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  String get _sleepLabel {
    if (_sleepRemainingSeconds == null) return '';
    final m = _sleepRemainingSeconds! ~/ 60;
    final s = _sleepRemainingSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // Seek preview position while scrubbing
  Duration get _previewPosition {
    if (_sliderDragging) {
      return Duration(
          milliseconds: (_sliderDragValue * _duration.inMilliseconds).toInt());
    }
    if (_draggingSeek && _dragSeekDelta != null) {
      final p =
          _dragStartPosition + Duration(seconds: _dragSeekDelta!.toInt());
      return (p < Duration.zero ? Duration.zero : p > _duration ? _duration : p);
    }
    return _position;
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildPlayerBody();
    final Widget amblit = _prefs.ambilightEnabled
        ? AmbilightGlowBorder(
            colors: _ambilightColors,
            intensity: _prefs.ambilightIntensity,
            blurRadius: _prefs.ambilightBlurRadius,
            child: body,
          )
        : body;
    // Phase D2: Color Look Preset (applies cinematic color grade to entire screen)
    final _colorLookFilter = videoLookFilter(_prefs.colorLook);
    final Widget looked = _colorLookFilter != null
        ? ColorFiltered(colorFilter: _colorLookFilter, child: amblit)
        : amblit;

    // Phase J2: color blind correction filter
    final Widget screened = _prefs.colorBlindMode != 'none'
        ? ColorFiltered(
            colorFilter: ColorFilter.matrix(
                _colorBlindMatrix(_prefs.colorBlindMode)),
            child: looked,
          )
        : looked;
    return Scaffold(
      backgroundColor: Colors.black,
      body: screened,
    );
  }

  Widget _buildPlayerBody() {
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleCenterTap,
        onDoubleTapDown: (d) {
          final w = MediaQuery.of(context).size.width;
          if (_scale > 1.01) {
            // Double-tap to reset zoom
            setState(() { _scale = 1.0; });
            return;
          }
          HapticFeedback.selectionClick();
          _seekRelative(d.localPosition.dx < w / 2 ? -15 : 15);
        },
        onLongPressStart: (_) {
          setState(() => _longPressFast = true);
          _player.setRate(_prefs.longPressSpeed);
        },
        onLongPressEnd: (_) {
          setState(() => _longPressFast = false);
          _player.setRate(_speed);
        },
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(children: [
          // ── VIDEO with zoom ──
          Positioned.fill(
            child: Transform.scale(
              scale: _scale,
              child: Opacity(
                opacity: _prefs.transparentModeEnabled
                    ? _prefs.transparentModeOpacity.clamp(0.2, 1.0)
                    : 1.0,
                child: GestureDetector(
                  onScaleStart: (_) {},
                  onScaleUpdate: (d) {
                    final newZoom = (_zoomLevel * d.scale).clamp(1.0, 5.0);
                    if ((newZoom - _zoomLevel).abs() > 0.01) {
                      setState(() => _zoomLevel = newZoom);
                    }
                  },
                  child: Transform.scale(
                    scale: _zoomLevel,
                    child: Video(
                      controller: _videoCtrl,
                      fit: _aspectMode == AspectMode.fill    ? BoxFit.cover
                          : _aspectMode == AspectMode.stretch ? BoxFit.fill
                          : _ratios[_ratioIdx],
                      filterQuality: FilterQuality.medium,
                      controls: NoVideoControls,
                      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Zoom & Crop Overlay (Phase L3) ──
          if (_showZoomOverlay)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: ZoomCropOverlay(
                currentZoom: _zoomLevel,
                currentMode: _aspectMode,
                accentColor: _prefs.accentColor,
                onZoomChanged: (z) {
                  setState(() => _zoomLevel = z);
                  // Persist last zoom level
                  final next = _prefs.copyWith(savedZoomLevel: z);
                  setState(() => _prefs = next);
                  next.save();
                },
                onModeChanged: (m) {
                  setState(() {
                    _aspectMode = m;
                    if (m == AspectMode.fit)      _ratioIdx = 0;
                    else if (m == AspectMode.fill) _ratioIdx = 1;
                    else if (m == AspectMode.crop169) _ratioIdx = 0;
                  });
                },
                onReset: () {
                  setState(() {
                    _zoomLevel = 1.0;
                    _aspectMode = AspectMode.original;
                    _ratioIdx = 0;
                  });
                },
              ),
            ),

          // ── Seek flash ──
          if (_showSeekLeft) _SeekFlash(isRight: false, label: _seekLabel),
          if (_showSeekRight) _SeekFlash(isRight: true, label: _seekLabel),

          // ── Buffering (accent color + pulse ring) ──
          if (_buffering && !_ended && _streamError == null)
            Center(
              child: SizedBox(
                width: 60, height: 60,
                child: Stack(alignment: Alignment.center, children: [
                  // Outer pulse ring
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _prefs.accentColor.withOpacity(0.35),
                        width: 1.5)),
                  ).animate(onPlay: (c) => c.repeat())
                    .scale(begin: const Offset(1, 1), end: const Offset(1.45, 1.45),
                           duration: 900.ms, curve: Curves.easeOut)
                    .fadeOut(duration: 900.ms),
                  // Inner spinner
                  const SizedBox(
                    width: 36, height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(_prefs.accentColor)),
                  ),
                ]),
              ),
            ),

          // ── Stream error overlay ──
          if (_streamError != null)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline_rounded,
                        color: _prefs.accentColor, size: 48),
                    const SizedBox(height: 16),
                    const Text('Could not load video',
                        style: TextStyle(color: Colors.white,
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('The video link may have expired.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.65),
                            fontSize: 13)),
                    const SizedBox(height: 28),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      // Retry button
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: _prefs.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: () {
                          setState(() { _streamError = null; _jazzRetryCount = 0; });
                          JazzDriveService.invalidate(widget.fileId);
                          _openMedia(widget.fileId);
                        },
                      ),
                      const SizedBox(width: 12),
                      // Back button
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.white24))),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go Back'),
                      ),
                    ]),
                  ]),
                ),
              ),
            ).animate().fadeIn(duration: 300.ms),

          // ── Link loading (JazzDrive/Oracle URL resolution) ──
          // ── Link loading (JazzDrive URL resolution) — shimmer + spinner ──
          if (_isLinkLoading)
            Stack(children: [
              Shimmer.fromColors(
                baseColor: Colors.grey[900]!,
                highlightColor: Colors.grey[800]!,
                child: Container(color: Colors.white),
              ),
              // MX Player-style circular dots loading animation
              const Center(child: _CircularDotsLoader()),
            ]),

          // ── Drag Indicator: full in normal/cinematic, number-only in immersive ──
          if (_draggingBrightness || _draggingVolume)
            _immersiveMode
                ? _ImmersiveDragNumber(
                    value: _draggingBrightness ? _brightness : _volume,
                    isBrightness: _draggingBrightness,
                    isBoost: _inBoostGesture,
                    boostValue: _inBoostGesture ? _volumeBoost : null,
                  )
                : _DragIndicator(
                    icon: _draggingBrightness
                        ? Icons.brightness_medium_rounded
                        : (_inBoostGesture ? Icons.speaker_rounded : Icons.volume_up_rounded),
                    value: _draggingBrightness ? _brightness : _volume,
                    boostValue: (!_draggingBrightness && _inBoostGesture) ? _volumeBoost : null,
                  ),

          // ── Seek scrub label ──
          if (_draggingSeek && _dragSeekDelta != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${_fmtDur(_previewPosition)}  (${_dragSeekDelta! >= 0 ? '+' : ''}${_dragSeekDelta!.toInt()}s)',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),

          // ── Zoom indicator ──
          if (_scale > 1.02 && _dragIntent == 'pinch')
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${_scale.toStringAsFixed(1)}×',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),

          // ── Long press 2× ──
          if (_longPressFast)
            Positioned(
              top: 16, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('2× Speed',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ).animate().fadeIn(duration: 150.ms, curve: Curves.easeOut),
            ),

          // ── Sleep fade badge ──
          if (_sleepFadeActive && _sleepRemainingSeconds != null)
            Positioned(
              top: 12, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.orange.withOpacity(0.6), width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bedtime_rounded, color: Colors.orange, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Sleeping in ${_sleepRemainingSeconds}s…',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .fadeIn(duration: 800.ms).then().fadeOut(duration: 800.ms),
              ),
            ),
          // ── Sleep timer badge ──
          if (_sleepRemainingSeconds != null && !_showControls)
            Positioned(
              top: 16, right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bedtime_rounded, color: Colors.orange, size: 13),
                  const SizedBox(width: 5),
                  Text(_sleepLabel,
                      style: const TextStyle(color: Colors.orange, fontSize: 12)),
                ]),
              ),
            ),

          // ── Phase P: Custom skip segment button ──
          if (_activeSkipSegment != null && !_locked && !_showNextEpisode)
            SkipSegmentButton(
              segment: _activeSkipSegment!,
              accentColor: _prefs.accentColor,
              onSkip: () {
                _player.seek(_activeSkipSegment!.end);
                setState(() => _activeSkipSegment = null);
              },
            ),

          // ── Skip intro ──
          if (_skipIntroVisible && !_locked && !_showNextEpisode)
            Positioned(
              bottom: 90, right: 20,
              child: GestureDetector(
                onTap: () async {
                  final seekTo = _savedIntroEnd ?? 85;
                  _player.seek(Duration(seconds: seekTo));
                  setState(() => _skipIntroVisible = false);
                  // Save for next time
                  final seriesId = widget.fileId.split('/').first;
                  await SmartIntroStore.saveIntroEnd(
                    seriesId: seriesId,
                    epIndex: _currentEpIdx,
                    positionSeconds: seekTo);
                },
              onLongPress: () async {
                  // Long-press: clear saved intro time
                  final seriesId = widget.fileId.split('/').first;
                  await SmartIntroStore.clearIntroEnd(
                    seriesId: seriesId, epIndex: _currentEpIdx);
                  setState(() { _savedIntroEnd = null; });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cleared saved skip time'),
                        duration: Duration(seconds: 2)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: Colors.white38)),
                  child: const Text('Skip Intro →',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .slideY(
                      begin: 0.3,
                      end: 0,
                      duration: 300.ms,
                      curve: AppCurves.standard),
            ),

          // ── Next Episode ──
          if (_showNextEpisode)
            _NextEpisodeOverlay(
              currentTitle: _currentTitle,
              nextTitle: _nextEpLabel,
              countdown: _nextCountdown,
              onPlay: _playNextEpisode,
              onCancel: () {
                _nextEpTimer?.cancel();
                setState(() => _showNextEpisode = false);
                Navigator.of(context).pop();
              },
              onSkipCountdown: _playNextEpisode,
            ),

          // ── Custom Subtitle Overlay ──
          if (_prefs.subtitleEnabled)
            SubtitleOverlay(
              currentLine: _currentSubtitleText,
              prefs: _prefs,
            ),

          // ── Phase F1: Dual Subtitle Overlay ──
          if (_prefs.subtitleEnabled && _prefs.dualSubtitleEnabled && _secondSubtitleText.isNotEmpty)
            DualSubtitleOverlay(
              primaryLine: _currentSubtitleText,
              secondaryLine: _secondSubtitleText,
              prefs: _prefs,
            ),

          // ── Phase D3: Film Grain overlay ──────────────────────────────────
          if (_prefs.filmGrainLevel != 'none')
            FilmGrainOverlay(level: _prefs.filmGrainLevel),

          // ── Phase I2: Reaction Stamps ─────────────────────────────────────
          if (_prefs.reactionsEnabled)
            ReactionStampsOverlay(
              position: _position,
              contentId: widget.fileId,
              accentColor: _prefs.accentColor,
              visible: _showControls && !_locked,
            ),

          // ── Phase L3: Video Zoom / Focus Mode ───────────────────────────────
          ZoomFocusOverlay(
            enabled: _prefs.focusModeEnabled,
            accentColor: _prefs.accentColor,
          ),

          // ── Phase M2: Jump To Panel ──────────────────────────────────────
          if (_showJumpPanel)
            JumpToPanel(
              current: _position,
              total: _duration,
              accentColor: _prefs.accentColor,
              onJump: (pos) {
                _controller?.seekTo(pos);
                setState(() => _showJumpPanel = false);
              },
              onDismiss: () => setState(() => _showJumpPanel = false),
            ),

          // ── Phase M3: End-of-Video countdown overlay ──────────────────────
          if (_showCountdown)
            CountdownNextOverlay(
              accentColor: _prefs.accentColor,
              nextTitle: widget.title,
              onDone: () {
                setState(() => _showCountdown = false);
                _handleVideoEnd();
              },
              onCancel: () => setState(() => _showCountdown = false),
            ),

          // ── Phase I1: Watch Party Overlay ─────────────────────────────────
          if (_watchPartyRoom != null)
            WatchPartyOverlay(
              room: _watchPartyRoom!,
              accentColor: _prefs.accentColor,
              onLeave: () {
                WatchPartyService.instance.leaveRoom();
                setState(() => _watchPartyRoom = null);
              },
            ),

          // ── Phase L2: Frame Counter HUD ───────────────────────────────────
          if (_prefs.frameCounterEnabled && _showControls)
            Positioned(
              top: 16, left: 0, right: 0,
              child: Center(
                child: FrameCounterHud(
                  position: _position,
                  total: _duration,
                  accentColor: _prefs.accentColor,
                  fps: _prefs.videoFps,
                ),
              ),
            ),

          // ── Phase E2: Karaoke Active Indicator ────────────────────────────
          Positioned(
            top: 16, right: 80,
            child: KaraokeActiveIndicator(
              accentColor: _prefs.accentColor,
              levelLabel: _prefs.audioLabConfig.split('|').length > 1
                  ? _prefs.audioLabConfig.split('|')[1]
                  : 'off',
              visible: _prefs.audioLabConfig.contains('|') &&
                  _prefs.audioLabConfig.split('|')[1] != 'off',
            ),
          ),

          // ── Phase J1: Voice Command button (shown over controls) ──────────
          if (_prefs.voiceCommandsEnabled && _showControls && !_locked)
            Positioned(
              left: 16, bottom: 80,
              child: VoiceCommandButton(
                accentColor: _prefs.accentColor,
                onCommand: _handleVoiceCommand,
              ),
            ),

          // ── Controls (Opacity wrapper dims them in Cinematic mode) ──
          if (_showControls && !_longPressFast && !_showNextEpisode && !_inPiP && !_immersiveMode)
            // Phase H1: One-Handed Mode — translate controls toward the active hand
            Transform.translate(
              offset: _prefs.oneHandedModeEnabled
                  ? Offset(_prefs.oneHandedModeSide == 'left' ? -56.0 : 56.0, 40.0)
                  : Offset.zero,
              child: ControlsBackground(
              style: _prefs.controlsBgStyle,
              accentColor: _prefs.accentColor,
              child: Opacity(
              opacity: _cinematicMode ? _cinematicOpacity.clamp(0.15, 1.0) : 1.0,
              child: _ControlsOverlay(
              title: _currentTitle,
              playing: _playing,
              buffering: _buffering,
              locked: _locked,
              position: _previewPosition,
              duration: _duration,
              progress: _sliderDragging
                  ? _sliderDragValue
                  : _progressFraction,
              speed: _speed,
              fitLabel: _fitLabel,
              hasNext: _hasNextEp,
              currentEp: widget.episodes != null ? _currentEpIdx : null,
              totalEps: widget.episodes?.length,
              sleepLabel: _sleepLabel,
              scale: _scale,
              bufferedFraction: _duration.inMilliseconds > 0
                  ? (_bufferedPosition.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0,
              isLocal: _isLocalFile,
              seekThumb: _seekThumb,
              sliderDragging: _sliderDragging,
              onBack: () => Navigator.of(context).pop(),
              onPlayPause: () {
                _player.playOrPause();
                _userPaused = !_playing;
              },
              onLongPressPlay: _prefs.longPressPlayRestart ? _onLongPressPlay : null,
              onSeekTo: (frac) {
                final ms = (frac * _duration.inMilliseconds).toInt();
                _player.seek(Duration(milliseconds: ms));
                setState(() => _seekThumb = null);
              },
              onSliderStart: (v) {
                setState(() {
                  _sliderDragging = true;
                  _sliderDragValue = v;
                });
                _updateSeekThumb(v);
              },
              onSliderChange: (v) {
                setState(() => _sliderDragValue = v);
                _updateSeekThumb(v);
              },
              onSliderEnd: (v) {
                final ms = (v * _duration.inMilliseconds).toInt();
                _player.seek(Duration(milliseconds: ms));
                setState(() {
                  _sliderDragging = false;
                  _seekThumb = null;
                });
              },
              onSeekBack: () => _seekRelative(-15),
              onSeekForward: () => _seekRelative(15),
              onLock: () => setState(() {
                _locked = !_locked;
                _showControls = false;
              }),
              onCycleFit: _cycleFit,
              onSpeed: () => setState(() {
                _showSpeedPicker = !_showSpeedPicker;
                _scheduleHide();
              }),
              onSubtitleFile: _pickSubtitle,
              onSubtitleTracks: () =>
                  setState(() => _showSubtitleMenu = !_showSubtitleMenu),
              onAudioTracks: () =>
                  setState(() => _showAudioMenu = !_showAudioMenu),
              rotationMode: _prefs.rotationMode,
              onCycleRotation: _cycleRotation,
              audioDelayMs: _audioDelayMs,
              subDelayMs: _subDelayMs,
              volumeBoost: _volumeBoost,
              showPlaybackInfo: _showPlaybackInfo,
              onSettings: () => setState(() => _showQuickSettings = true),
              onMorePanel: () => setState(() => _showMorePanel = true),
              onEq: () => setState(() => _showEqPanel = true),
              onAudioSync: () => setState(() => _showAudioSyncPanel = true),
              onSubSync: () => setState(() => _showSubSyncPanel = true),
              onShareTimestamp: _shareTimestamp,
              onJumpToTime: _showJumpToTime,
              onTogglePlaybackInfo: () {
                setState(() => _showPlaybackInfo = !_showPlaybackInfo);
                if (_showPlaybackInfo) _fetchPlaybackInfo();
              },
              showRemaining: _showRemaining,
              onToggleRemaining: () => setState(() => _showRemaining = !_showRemaining),
              onNextEpisode: _hasNextEp ? _playNextEpisode : null,
              onPiP: _enterPiP,
              onCast: _enterCast,
              castConnected: _castConnected,
              onSleep: () => setState(() => _showSleepMenu = !_showSleepMenu),
              onResetZoom: _scale > 1.02
                  ? () => setState(() => _scale = 1.0)
                  : null,
              fmtDur: _fmtDur,
              cinematicMode: _cinematicMode,
              onToggleCinematic: _toggleCinematic,
              activeAudioIdx: _activeAudioIdx,
              activeSubIdx: _activeSubIdx,
              audioLabels: _buildAudioLabels(_player.state.tracks.audio),
              subLabels: _buildSubLabels(_player.state.tracks.subtitle),
              showActiveTrackBadge: _prefs.showActiveTrackBadge,
              showTrackCountBadge: _prefs.showTrackCountBadge,
              bookmarks: _bookmarks,
              abLoop: _abLoop,
              onToggleAbPanel: () => setState(() => _showAbPanel = !_showAbPanel),
              onToggleBookmarks: _openBookmarkPanel,
              onToggleVideoEnhance: _openVideoEnhanceSuite,
              onTakeScreenshot: _takeScreenshot,
              onAddBookmark: _addBookmarkAtPosition,
              onSeekBarLongPress: _onSeekBarLongPress,
              chapters: _chapters,
              showFrameStep: _showFrameStep,
              onFrameStep: _frameStep,
              onFrameBackStep: _frameBackStep,
              isTransparentMode: _prefs.transparentModeEnabled,
              onToggleTransparentSlider: _prefs.transparentModeEnabled
                  ? () => setState(() => _showTransparentSlider = !_showTransparentSlider)
                  : null,
              accentColor: _prefs.accentColor,
              buttonShape: _prefs.buttonShape,
              seekBarStyle: _prefs.seekBarStyle,
              iconPack: _prefs.iconPack,
              moodEnabled: _prefs.contentMoodEnabled,
            ),
            )), // end Opacity + ControlsBackground
          ), // end ControlsBackground
            ), // end Transform.translate (Phase H1: oneHandedMode)

          // ── Lock Button ──
          if (_locked && _showControls)
            Positioned(
              right: 20, top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _locked = false;
                    _showControls = true;
                    _scheduleHide();
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                        border: Border.all(color: Colors.white30)),
                    child: const Icon(Icons.lock_open_rounded,
                        color: Colors.white, size: 22)),
                ),
              ).animate().fadeIn(duration: 150.ms, curve: Curves.easeOut),
            ),

          // ── Speed Panel ──
          if (_showSpeedPicker && !_locked)
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: _SpeedPanel(
                currentSpeed: _speed,
                speeds: _speeds,
                onSelect: (s) {
                  setState(() {
                    _speed = s;
                    _showSpeedPicker = false;
                  });
                  _player.setRate(s);
                  _scheduleHide();
                },
              ),
            ),

          // ── Subtitle Tracks (MX Player bottom sheet style) ──
          if (_showSubtitleMenu && !_locked)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showSubtitleMenu = false),
              child: Container(color: Colors.black54))),
          if (_showSubtitleMenu && !_locked)
            Positioned(bottom: 0, left: 0, right: 0,
              child: _MxSubPanel(
                tracks: _buildSubLabels(_player.state.tracks.subtitle),
                activeIndex: _activeSubIdx,
                syncMs: _subDelayMs,
                onSelect: (i) {
                  if (i >= 0 && i < _player.state.tracks.subtitle.length) {
                    _player.setSubtitleTrack(_player.state.tracks.subtitle[i]);
                  }
                  setState(() { _activeSubIdx = i; _showSubtitleMenu = false; });
                },
                onSyncChanged: _applySubSync,
                onOpen: () { setState(() => _showSubtitleMenu = false); _pickSubtitle(); },
                onSettings: () { setState(() { _showSubtitleMenu = false; _showQuickSettings = true; }); },
                onClose: () => setState(() => _showSubtitleMenu = false),
              )),

          // ── Audio Tracks (MX Player bottom sheet style) ──
          if (_showAudioMenu && !_locked)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showAudioMenu = false),
              child: Container(color: Colors.black54))),
          if (_showAudioMenu && !_locked)
            Positioned(bottom: 0, left: 0, right: 0,
              child: _MxAudioPanel(
                tracks: _buildAudioLabels(_player.state.tracks.audio),
                activeIndex: _activeAudioIdx,
                syncMs: _audioDelayMs,
                onSelect: (i) {
                  if (i >= 0 && i < _player.state.tracks.audio.length) {
                    _player.setAudioTrack(_player.state.tracks.audio[i]);
                    setState(() { _activeAudioIdx = i; });
                  }
                  setState(() => _showAudioMenu = false);
                },
                onSyncChanged: _applyAudioSync,
                onOpen: () => setState(() => _showAudioMenu = false),
                onClose: () => setState(() => _showAudioMenu = false),
              )),

          // ── Rage Skip Badge ──
          if (_rageSkipActive)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(color: Colors.red.withOpacity(0.22)).animate()
                  .fadeIn(duration: 50.ms).then(delay: 150.ms).fadeOut(duration: 200.ms),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'RAGE SKIP ⚡ +${(_prefs.rageSkipSeconds ~/ 60)}:00',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                ).animate()
                  .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.1, 1.1), duration: 250.ms, curve: Curves.elasticOut)
                  .then().scale(end: const Offset(1.0, 1.0), duration: 100.ms)
                  .then(delay: 600.ms).fadeOut(duration: 300.ms),
              ]),
            ),

          // ── Binge Guard overlay ──
          if (_showBingeGuard)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.88),
                child: Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.health_and_safety_outlined, color: Color(0xFFE8002D), size: 52),
                    const SizedBox(height: 16),
                    const Text('Time for a Break!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text("You've watched $_bingeWatchedMins minutes in this session.",
                        style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton(
                        onPressed: () { setState(() => _showBingeGuard = false); _player.play(); _bingeGuardCtrl?.reset(); },
                        style: TextButton.styleFrom(foregroundColor: Colors.white54),
                        child: const Text('Keep Watching')),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8002D),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                        child: const Text('Take a Break', style: TextStyle(color: Colors.white))),
                    ]),
                  ]),
                )),
              ).animate().fadeIn(duration: 300.ms),
            ),

          // ── Volume Boost badge ──
          if (_volumeBoost > 1.01 && !_showControls)
            Positioned(
              top: 16, left: 12,
              child: GestureDetector(
                onTap: () => setState(() => _showQuickSettings = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _volumeBoost > 2.5 ? Colors.red.withOpacity(0.5) : _volumeBoost > 1.5 ? Colors.orange.withOpacity(0.5) : Colors.white24)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.volume_up_rounded, size: 12,
                      color: _volumeBoost > 2.5 ? Colors.red : _volumeBoost > 1.5 ? Colors.orange : Colors.white),
                    const SizedBox(width: 4),
                    Text('${(_volumeBoost * 100).toInt()}%',
                      style: TextStyle(
                        color: _volumeBoost > 2.5 ? Colors.red : _volumeBoost > 1.5 ? Colors.orange : Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),

          // ── Playback Info overlay ──
          if (_showPlaybackInfo && !_showControls)
            PlaybackInfoOverlay(
              codec: _piCodec, resolution: _piRes, fps: _piFps,
              bitrate: _piBitrate, buffer: _piBuffer, decoder: _piDecoder),

          // ── Quick Settings bottom sheet trigger (overlay) ──
          if (_showQuickSettings)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showQuickSettings = false),
                child: Container(color: Colors.black45),
              ),
            ),
          if (_showQuickSettings)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: QuickSettingsPanel(
                prefs: _prefs,
                onChanged: (newPrefs) {
                  setState(() => _prefs = newPrefs);
                  newPrefs.save();
                  // Apply live changes
                  if (newPrefs.volumeBoostMultiplier != _prefs.volumeBoostMultiplier) {
                    _applyVolumeBoost(newPrefs.volumeBoostMultiplier);
                  }
                  _applyVideoFilters(newPrefs);
                  _applyAudioPrefs(newPrefs);
                  _initAmbilight();
                  _initBingeGuard();
                },
                onDone: () => setState(() => _showQuickSettings = false),
                onOpenFullSettings: () {
                  setState(() => _showQuickSettings = false);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PlayerSettingsScreen()));
                },
                onOpenGestureMap: () {
                  setState(() => _showQuickSettings = false);
                  _openGestureMap();
                },
                onOpenPictureProfiles: () {
                  setState(() => _showQuickSettings = false);
                  _openPictureProfiles();
                },
                onOpenAudioLab: () {
                  setState(() => _showQuickSettings = false);
                  _openAudioLab();
                },
                onOpenSkipEditor: () {
                  setState(() => _showQuickSettings = false);
                  _openIntroSkipEditor();
                },
                onOpenJumpTo: () {
                  setState(() => _showQuickSettings = false);
                  _openJumpTo();
                },
                onOpenSpeedPresets: () {
                  setState(() => _showQuickSettings = false);
                  _openSpeedPresets();
                },
                onOpenEndAction: () {
                  setState(() => _showQuickSettings = false);
                  _openEndAction();
                },
                onOpenSilenceSkip: () {
                  setState(() => _showQuickSettings = false);
                  _openSilenceSkip();
                },
                onOpenZoomCrop: () {
                  setState(() => _showQuickSettings = false);
                  _openZoomCrop();
                },
                onOpenWakeDnd: () {
                  setState(() => _showQuickSettings = false);
                },
                subDelayMs: _subDelayMs,
                audioDelayMs: _audioDelayMs,
                onSubDelay: (ms) => _applySubSync(ms),
                onAudioDelay: (ms) => _applyAudioSync(ms),
                onOpenSubSync: () {
                  setState(() { _showQuickSettings = false; _showSubSyncPanel = true; });
                },
                onOpenAudioSync: () {
                  setState(() { _showQuickSettings = false; _showAudioSyncPanel = true; });
                },
                speed: _speed,
                onSpeedChanged: (s) {
                  setState(() => _speed = s);
                  _player.setRate(s);
                },
                fitMode: _fitLabel,
                onFitChanged: (mode) {
                  setState(() {
                    if (mode == 'Zoom') _ratioIdx = 1;
                    else if (mode == 'Fill') _ratioIdx = 2;
                    else _ratioIdx = 0;
                  });
                },
                selectedQuality: _qualityFromRes,
                onQualityChanged: (_) {},
              ),
            ),

            // ── More Panel (MX Player–style bottom sheet) ─────────────────────────
            if (_showMorePanel)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _showMorePanel = false),
                  child: Container(color: Colors.black45),
                ),
              ),
            if (_showMorePanel)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _MxMoreSheet(
                    cinematicMode: _cinematicMode,
                    abLoopActive: _abLoop.isActive,
                    sleepActive: _sleepRemainingSeconds != null || _sleepAtEpisodeEnd,
                    bookmarkCount: _bookmarks.length,
                    speed: _speed,
                    fitLabel: _ratios[_ratioIdx] == BoxFit.contain ? 'Fit'
                        : _ratios[_ratioIdx] == BoxFit.cover ? 'Crop' : 'Fill',
                    castConnected: _castConnected,
                    onFit: () { setState(() => _showMorePanel = false); _cycleFit(); },
                    onSpeed: () { setState(() { _showMorePanel = false; _showSpeedPicker = !_showSpeedPicker; }); },
                    onNight: () { setState(() { _showMorePanel = false; }); _toggleCinematic(); },
                    onLoop: () { setState(() { _showMorePanel = false; _showAbPanel = !_showAbPanel; }); },
                    onSleep: () { setState(() { _showMorePanel = false; _showSleepMenu = !_showSleepMenu; }); },
                    onBookmarks: () { setState(() { _showMorePanel = false; _showBookmarksPanel = !_showBookmarksPanel; }); },
                    onEq: () { setState(() { _showMorePanel = false; _showEqPanel = true; }); },
                    onScreenshot: () { setState(() => _showMorePanel = false); _takeScreenshot(); },
                    onCast: () { setState(() => _showMorePanel = false); _enterCast(); },
                    onPiP: () { setState(() => _showMorePanel = false); _enterPiP(); },
                    onRotation: () { setState(() => _showMorePanel = false); _cycleRotation(); },
                    onSettings: () { setState(() { _showMorePanel = false; _showQuickSettings = true; }); },
                    onOpenWith: () { setState(() => _showMorePanel = false); _openWithExternalPlayer(); },
                    onVideoDisplay: () { setState(() { _showMorePanel = false; _showVideoDisplay = true; }); },
                    immersiveMode: _immersiveMode,
                    onImmersive: () { setState(() => _showMorePanel = false); _toggleImmersive(); },
                    onImmersiveSettings: () { setState(() => _showMorePanel = false); _showImmersiveSettings(); },
                    onCinematicSettings: () { setState(() => _showMorePanel = false); _showCinematicSettings(); },
                  ),
              ),
  
          // ── Audio Sync Panel ──
          if (_showAudioSyncPanel)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showAudioSyncPanel = false),
              child: Container(color: Colors.black45))),
          if (_showAudioSyncPanel)
            Positioned(bottom: 0, left: 0, right: 0,
              child: SyncPanel(
                label: 'Audio',
                delayMs: _audioDelayMs,
                onChanged: _applyAudioSync,
                onDone: () => setState(() => _showAudioSyncPanel = false),
              )),

          // ── Subtitle Sync Panel ──
          if (_showSubSyncPanel)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showSubSyncPanel = false),
              child: Container(color: Colors.black45))),
          if (_showSubSyncPanel)
            Positioned(bottom: 0, left: 0, right: 0,
              child: SyncPanel(
                label: 'Subtitle',
                delayMs: _subDelayMs,
                onChanged: _applySubSync,
                onDone: () => setState(() => _showSubSyncPanel = false),
              )),

          // ── EQ Panel ──
          if (_showEqPanel)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showEqPanel = false),
              child: Container(color: Colors.black45))),
          if (_showEqPanel)
            Positioned(bottom: 0, left: 0, right: 0,
              child: EqPanel(
                prefs: _prefs,
                onChanged: (newPrefs) {
                  setState(() => _prefs = newPrefs);
                  newPrefs.save();
                  _applyAudioPrefs(newPrefs);
                },
                onDone: () => setState(() => _showEqPanel = false),
              )),

          // ── Video Display Shortcuts Panel ──
          if (_showVideoDisplay)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showVideoDisplay = false),
              child: Container(color: Colors.black45))),
          if (_showVideoDisplay)
            Positioned(bottom: 0, left: 0, right: 0,
              child: _VideoDisplaySheet(
                screenRotation: _rotationMode != 'auto',
                bgPlay: _bgPlayEnabled,
                isMuted: _isMuted,
                eqEnabled: _prefs.equalizerEnabled,
                sleepActive: _sleepRemainingSeconds != null || _sleepAtEpisodeEnd,
                nightMode: _cinematicMode,
                speed: _speed,
                loopActive: _abLoop.isActive,
                abRepeatActive: _abLoop.isActive,
                onScreenRotation: () {
                  _cycleRotation();
                  setState(() {});
                },
                onBgPlay: (v) {
                  setState(() => _bgPlayEnabled = v);
                  // Keep audio session active when backgrounded
                  _initAudioSession();
                },
                onMute: (v) {
                  setState(() => _isMuted = v);
                  VolumeController().setVolume(v ? 0.0 : _volume, showSystemUI: false);
                },
                onEq: () {
                  setState(() { _showVideoDisplay = false; _showEqPanel = true; });
                },
                onSleep: () {
                  setState(() { _showVideoDisplay = false; _showSleepMenu = true; });
                },
                onNightMode: () {
                  _toggleCinematic();
                  setState(() {});
                },
                onSpeed: () {
                  setState(() { _showVideoDisplay = false; _showSpeedPicker = true; });
                },
                onAudioEffect: () {
                  setState(() { _showVideoDisplay = false; _showEqPanel = true; });
                },
                onAbRepeat: () {
                  setState(() { _showVideoDisplay = false; _showAbPanel = !_showAbPanel; });
                },
                onDone: () => setState(() => _showVideoDisplay = false),
              )),

          // ── Sleep Timer Menu ──
          if (_showSleepMenu && !_locked)
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: _SleepPanel(
                remaining: _sleepRemainingSeconds,
                onSelect: (mins) {
                  _setSleepTimer(mins);
                  setState(() => _showSleepMenu = false);
                  _scheduleHide();
                },
                onCancel: () {
                  _cancelSleepTimer();
                  setState(() => _showSleepMenu = false);
                  _scheduleHide();
                },
              ),
            ),

          // ── Cinematic mode: no separate overlay — controls are wrapped in
          //    Opacity(_cinematicOpacity) above. Nothing extra needed here.

          // ── Immersive Mode: corner exit icon + time HUD ──
          if (_immersiveMode)
            ImmersiveOverlay(
              isPlaying: _playing,
              position: _position,
              duration: _duration,
              fmtDur: _fmtDur,
              onPlayPause: () {
                _player.playOrPause();
                _userPaused = !_playing;
              },
              onExit: _toggleImmersive,
            ),

          // ── Scene Bookmarks Panel ──
          if (_showBookmarksPanel)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showBookmarksPanel = false),
              child: Container(color: Colors.black45))),
          if (_showBookmarksPanel)
            Positioned(bottom: 0, left: 0, right: 0,
              child: SceneBookmarksPanel(
              bookmarks: _bookmarks,
                fmtDur: _fmtDur,
                onSeekTo: (pos) => _player.seek(pos),
                onDelete: _deleteBookmark,
                onClose: () => setState(() => _showBookmarksPanel = false),
              )),

          // ── A-B Loop Panel ──
          if (_showAbPanel)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showAbPanel = false),
              child: Container(color: Colors.black45))),
          if (_showAbPanel)
            Positioned(bottom: 0, left: 0, right: 0,
              child: AbLoopPanel(
                controller: _abLoop,
                currentPosition: _position,
                fmtDur: _fmtDur,
                onChanged: () => setState(() {}),
                onClose: () => setState(() => _showAbPanel = false),
              )),

          // ── Video Enhancement Panel ──
          if (_showVideoEnhance)
            Positioned.fill(child: GestureDetector(
              onTap: () => setState(() => _showVideoEnhance = false),
              child: Container(color: Colors.black45))),
          if (_showVideoEnhance)
            Positioned(bottom: 0, left: 0, right: 0,
              child: VideoEnhancePanel(
                prefs: _prefs,
                onChanged: (newPrefs) {
                  setState(() => _prefs = newPrefs);
                  newPrefs.save();
                  _applyVideoFilters(newPrefs);
                },
                onClose: () => setState(() => _showVideoEnhance = false),
              )),

          // ── Transparent Mode Opacity Slider ──
          if (_prefs.transparentModeEnabled && _showTransparentSlider)
            TransparentPlayerSlider(
              opacity: _prefs.transparentModeOpacity,
              onChanged: (v) {
                final np = _prefs.copyWith(transparentModeOpacity: v);
                setState(() => _prefs = np);
                np.save();
              },
              onClose: () => setState(() => _showTransparentSlider = false),
            ),
        ]),
      );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTROLS OVERLAY
// ═══════════════════════════════════════════════════════════════════════════════

class _ControlsOverlay extends StatelessWidget {
  final String title;
  final bool playing, buffering, locked;
  final double bufferedFraction;
  final Duration position, duration;
  final double progress, speed, scale;
  final String fitLabel, sleepLabel;
  final bool hasNext, isLocal, sliderDragging;
  final int? currentEp, totalEps;
  final Uint8List? seekThumb;
  final VoidCallback onBack, onPlayPause, onSeekBack, onSeekForward;
    final VoidCallback? onLongPressPlay; // §3.16D
  final VoidCallback onLock, onCycleFit, onSpeed;
  final VoidCallback onSubtitleFile, onSubtitleTracks, onAudioTracks;
  final VoidCallback onPiP, onSleep, onCast;
  final bool castConnected;
  final String rotationMode;
  final VoidCallback onCycleRotation;
  final int audioDelayMs;
  final int subDelayMs;
  final double volumeBoost;
  final bool showPlaybackInfo;
  final bool showRemaining;
  final VoidCallback onSettings;
  final VoidCallback onMorePanel;
  final VoidCallback onEq;
  final VoidCallback onAudioSync;
  final VoidCallback onSubSync;
  final VoidCallback onShareTimestamp;
  final VoidCallback onJumpToTime;
  final VoidCallback onToggleRemaining;
  final VoidCallback onTogglePlaybackInfo;
  final VoidCallback? onNextEpisode, onResetZoom;
  final ValueChanged<double> onSeekTo, onSliderStart, onSliderChange, onSliderEnd;
  final String Function(Duration) fmtDur;
  // Extended params
  final bool cinematicMode;
  final VoidCallback onToggleCinematic;
  final int activeAudioIdx;
  final int activeSubIdx;
  final List<String> audioLabels;
  final List<String> subLabels;
  final bool showActiveTrackBadge;
  final bool showTrackCountBadge;
  final List<SceneBookmark> bookmarks;
  final AbLoopController abLoop;
  final VoidCallback onToggleAbPanel;
  final VoidCallback onToggleBookmarks;
  final VoidCallback onToggleVideoEnhance;
  final VoidCallback onTakeScreenshot;
  final VoidCallback onAddBookmark;
  // §3.3 item 5: seek bar long-press
  final VoidCallback? onSeekBarLongPress;
  // §3K: chapter markers + frame-step
  final List<Duration> chapters;
  final bool showFrameStep;
  final VoidCallback onFrameStep;
  final VoidCallback onFrameBackStep;
  // PL-001: transparent slider trigger
  final bool isTransparentMode;
  final VoidCallback? onToggleTransparentSlider;
  final Color accentColor;
  final String buttonShape;
  final bool moodEnabled; // Phase G4: narrative arc mood zone colors
  // Phase A2: 10-style seek bar
  final String seekBarStyle;
  // Phase A3: icon pack (mx|ios|fluent|material3|cute|minimal)
  final String iconPack;

  const _ControlsOverlay({
    required this.title, required this.playing, required this.buffering,
    required this.bufferedFraction,
    required this.locked, required this.position, required this.duration,
    required this.progress, required this.speed, required this.fitLabel,
    required this.hasNext, required this.isLocal, required this.sliderDragging,
    required this.scale, required this.sleepLabel,
    this.seekThumb, this.currentEp, this.totalEps,
    required this.onBack, required this.onPlayPause, required this.onSeekBack,
    required this.onSeekForward, this.onLongPressPlay, required this.onLock, required this.onCycleFit,
    required this.onSpeed, required this.onSubtitleFile, required this.onSubtitleTracks,
    required this.onAudioTracks, required this.onPiP, required this.onSleep,
    required this.onCast, required this.castConnected,
    required this.rotationMode, required this.onCycleRotation,
    this.audioDelayMs = 0, this.subDelayMs = 0,
    this.volumeBoost = 1.0, this.showPlaybackInfo = false,
    this.showRemaining = false,
    required this.onSettings, required this.onMorePanel, required this.onEq,
    required this.onAudioSync, required this.onSubSync,
    required this.onShareTimestamp, required this.onJumpToTime,
    required this.onToggleRemaining, required this.onTogglePlaybackInfo,
    this.onNextEpisode, this.onResetZoom,
    required this.onSeekTo, required this.onSliderStart,
    required this.onSliderChange, required this.onSliderEnd,
    required this.fmtDur,
    this.cinematicMode = false,
    required this.onToggleCinematic,
    this.activeAudioIdx = 0,
    this.activeSubIdx = 0,
    this.audioLabels = const [],
    this.subLabels = const [],
    this.showActiveTrackBadge = true,
    this.showTrackCountBadge = true,
    this.bookmarks = const [],
    required this.abLoop,
    required this.onToggleAbPanel,
    required this.onToggleBookmarks,
    required this.onToggleVideoEnhance,
    required this.onTakeScreenshot,
    required this.onAddBookmark,
    this.onSeekBarLongPress,
    this.chapters = const [],
    this.showFrameStep = false,
    required this.onFrameStep,
    required this.onFrameBackStep,
    this.isTransparentMode = false,
    this.onToggleTransparentSlider,
    this.accentColor = const Color(0xFFE8002D),
    this.buttonShape = 'circle',
    this.moodEnabled = false,
    this.seekBarStyle = 'classic',
    this.iconPack = 'mx',
  });

  /// Returns the BoxDecoration for the play button based on [shape].
  static BoxDecoration _playBtnDecoration(String shape, Color accent) {
    final shadow = BoxShadow(color: accent.withOpacity(0.33), blurRadius: 24, spreadRadius: 4);
    switch (shape) {
      case 'squircle':
        return BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20), boxShadow: [shadow]);
      case 'rounded':
        return BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12), boxShadow: [shadow]);
      case 'sharp':
        return BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3), boxShadow: [shadow]);
      case 'pill':
        return BoxDecoration(color: accent, borderRadius: BorderRadius.circular(34), boxShadow: [shadow]);
      case 'circle':
      default:
        return BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [shadow]);
    }
  }

  /// Returns the icon for [iconName] based on the active [pack].
  /// Falls back to Material icons for unknown packs or icons.
  static IconData _iconForPack(String pack, String iconName) {
    switch (pack) {
      case 'ios':
        switch (iconName) {
          case 'play':     return CupertinoIcons.play_fill;
          case 'pause':    return CupertinoIcons.pause_fill;
          case 'subtitle': return CupertinoIcons.captions_bubble_fill;
          case 'audio':    return CupertinoIcons.music_note;
          case 'more':     return CupertinoIcons.ellipsis;
          case 'settings': return CupertinoIcons.gear;
        }
        break;
      case 'fluent':
        switch (iconName) {
          case 'play':     return Icons.play_circle_filled_rounded;
          case 'pause':    return Icons.pause_circle_filled_rounded;
          case 'subtitle': return Icons.closed_caption_rounded;
          case 'audio':    return Icons.graphic_eq_rounded;
          case 'more':     return Icons.more_horiz_rounded;
          case 'settings': return Icons.tune_rounded;
        }
        break;
      case 'cute':
        switch (iconName) {
          case 'play':     return Icons.play_circle_rounded;
          case 'pause':    return Icons.pause_circle_rounded;
          case 'subtitle': return Icons.subtitles_outlined;
          case 'audio':    return Icons.headphones_rounded;
          case 'more':     return Icons.widgets_rounded;
          case 'settings': return Icons.manage_accounts_rounded;
        }
        break;
      case 'minimal':
        switch (iconName) {
          case 'play':     return Icons.play_arrow_outlined;
          case 'pause':    return Icons.pause_outlined;
          case 'subtitle': return Icons.subtitles_outlined;
          case 'audio':    return Icons.audiotrack_outlined;
          case 'more':     return Icons.more_horiz;
          case 'settings': return Icons.settings_outlined;
        }
        break;
    }
    // mx / material3 / default
    switch (iconName) {
      case 'play':     return Icons.play_arrow_rounded;
      case 'pause':    return Icons.pause_rounded;
      case 'subtitle': return Icons.subtitles_rounded;
      case 'audio':    return Icons.audiotrack_rounded;
      case 'more':     return Icons.more_horiz_rounded;
      case 'settings': return Icons.settings_rounded;
      default:         return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // ── Gradient scrim (MX Player: stronger dark at top+bottom) ────────────
      Positioned.fill(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xDD000000), Colors.transparent, Colors.transparent, Color(0xDD000000)],
              stops: [0.0, 0.22, 0.72, 1.0],
            ),
          ),
        ),
      ),

      // ── TOP BAR (exact MX Player: back | title | audio? | sub? | ⋮) ────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
                  onPressed: onBack,
                  padding: const EdgeInsets.all(8),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (currentEp != null && totalEps != null)
                        Text('EP ${currentEp! + 1} / $totalEps',
                            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500)),
                      Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (audioDelayMs != 0)
                  _MxBadge(label: 'A${audioDelayMs > 0 ? '+' : ''}${audioDelayMs}ms', color: accentColor, onTap: onAudioSync),
                if (subDelayMs != 0)
                  _MxBadge(label: 'S${subDelayMs > 0 ? '+' : ''}${subDelayMs}ms', color: accentColor, onTap: onSubSync),
                if (onResetZoom != null)
                  _MxBadge(label: '${scale.toStringAsFixed(1)}×', color: Colors.white70, onTap: onResetZoom!),
                if (audioLabels.length > 1)
                  IconButton(
                    icon: const Icon(Icons.audiotrack_rounded, color: Colors.white70, size: 20),
                    onPressed: onAudioTracks,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.subtitles_rounded,
                    color: (subLabels.isNotEmpty && activeSubIdx < subLabels.length)
                        ? Colors.white : Colors.white38,
                    size: 20,
                  ),
                  onPressed: onSubtitleTracks,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 24),
                  onPressed: onMorePanel,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
          ),
        ),
  

      // ── CENTER CONTROLS (MX Player landscape: vertical — up=seek-back, down=seek-fwd) ──
        if (!locked)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _MxSeekBtn(isForward: false, seconds: 15, onTap: onSeekBack),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: onPlayPause,
                  onLongPress: onLongPressPlay,
                  child: Container(
                    width: 68, height: 68,
                    decoration: _playBtnDecoration(buttonShape, accentColor),
                    clipBehavior: Clip.hardEdge,
                    child: Icon(
                      playing
                          ? _iconForPack(iconPack, 'pause')
                          : _iconForPack(iconPack, 'play'),
                      color: Colors.white, size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _MxSeekBtn(isForward: true, seconds: 15, onTap: onSeekForward),
                if (hasNext) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onNextEpisode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Next', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        SizedBox(width: 4),
                        Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
                      ]),
                    ),
                  ),
                ],
              ],
            ).animate().fadeIn(duration: 150.ms, curve: Curves.easeOut),
          ),

      // ── RIGHT-SIDE STRIP (MX Player: vertical icon strip on right edge) ──────
      if (!locked)
        Positioned(
          right: 8, top: 0, bottom: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MxSideBtn(
                  icon: _iconForPack(iconPack, 'subtitle'),
                  label: subLabels.isNotEmpty ? 'Sub' : 'Sub',
                  active: subLabels.isNotEmpty && activeSubIdx < subLabels.length,
                  activeColor: const Color(0xFF4DB6FF),
                  onTap: onSubtitleTracks,
                ),
                const SizedBox(height: 8),
                _MxSideBtn(
                  icon: _iconForPack(iconPack, 'audio'),
                  label: audioLabels.length > 1 ? 'Audio' : 'Audio',
                  active: audioLabels.length > 1,
                  activeColor: const Color(0xFF4DB6FF),
                  onTap: onAudioTracks,
                ),
                const SizedBox(height: 8),
                _MxSideBtn(
                  icon: _rotationIcon(rotationMode),
                  label: _rotationLabel(rotationMode),
                  onTap: onCycleRotation,
                ),
                const SizedBox(height: 8),
                _MxSideBtn(
                  icon: _iconForPack(iconPack, 'more'),
                  label: 'More',
                  onTap: onMorePanel,
                ),
              ],
            ).animate().fadeIn(duration: 150.ms, curve: Curves.easeOut),
          ),
        ),

  
      // ── LEFT SIDE SEEK BAR (MX Player landscape: vertical seek on left edge) ──────
      if (!locked)
        Positioned(
          left: 0, top: 0, bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Seek thumbnail (shows beside bar when dragging local file) ──
                  if (seekThumb != null && sliderDragging && isLocal)
                    Container(
                      width: 120, height: 70,
                      margin: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white38),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(children: [
                        Image.memory(seekThumb!, fit: BoxFit.cover, width: 120, height: 70),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              fmtDur(Duration(milliseconds:
                                  (progress * duration.inMilliseconds).toInt())),
                              style: const TextStyle(color: Colors.white, fontSize: 9,
                                  fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  // ── Current position time (top of bar) ──
                  GestureDetector(
                    onTap: onToggleRemaining,
                    onLongPress: onJumpToTime,
                    child: Text(
                      showRemaining
                          ? '-${fmtDur(duration - position)}'
                          : fmtDur(position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                  // ── Vertical seek slider ──────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          final sliderLen = constraints.maxHeight;
                          return SizedBox(
                            width: 44,
                            child: Stack(alignment: Alignment.center, children: [
                              // Buffered progress (vertical background track)
                              Positioned(
                                top: 0, bottom: 0,
                                child: RotatedBox(
                                  quarterTurns: 1,
                                  child: SizedBox(
                                    width: sliderLen, height: 3,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: bufferedFraction.clamp(0.0, 1.0),
                                        backgroundColor: Colors.white12,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white30),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // A-B loop point A marker
                              if (abLoop.pointA != null && duration.inMilliseconds > 0)
                                Positioned(
                                  bottom: ((abLoop.pointA!.inMilliseconds /
                                      duration.inMilliseconds).clamp(0.0,1.0) * sliderLen),
                                  child: Container(
                                    width: 10, height: 10,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle, color: Colors.orange),
                                  ),
                                ),
                              // A-B loop point B marker
                              if (abLoop.pointB != null && duration.inMilliseconds > 0)
                                Positioned(
                                  bottom: ((abLoop.pointB!.inMilliseconds /
                                      duration.inMilliseconds).clamp(0.0,1.0) * sliderLen),
                                  child: Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle, color: accentColor),
                                  ),
                                ),
                              // Bookmark emoji markers on the bar
                              ...bookmarks.map((bm) {
                                if (duration.inMilliseconds <= 0) return const SizedBox.shrink();
                                final frac = (bm.positionMs / duration.inMilliseconds).clamp(0.0,1.0);
                                return Positioned(
                                  bottom: frac * sliderLen - 8,
                                  child: GestureDetector(
                                    onTap: () => onSeekTo(frac),
                                    child: Text(bm.emoji,
                                        style: const TextStyle(fontSize: 10)),
                                  ),
                                );
                              }),
                              // Chapter markers as thin horizontal lines
                              ...chapters.map((ch) {
                                if (duration.inMilliseconds <= 0) return const SizedBox.shrink();
                                final frac = (ch.inMilliseconds / duration.inMilliseconds).clamp(0.0,1.0);
                                return Positioned(
                                  bottom: frac * sliderLen - 1,
                                  left: 6, right: 6,
                                  child: Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: Colors.white54,
                                      borderRadius: BorderRadius.circular(1)),
                                  ),
                                );
                              }),
                              // Phase G4: Narrative arc mood zone tints ─────
                              if (moodEnabled)
                                ...List.generate(4, (z) {
                                  const zColors = [
                                    Color(0x281E90FF), // 0-25%  intro/calm
                                    Color(0x2832CD32), // 25-50% rising action
                                    Color(0x28FF8C00), // 50-75% tension
                                    Color(0x28DC143C), // 75-100% climax
                                  ];
                                  final zLen = sliderLen / 4;
                                  return Positioned(
                                    bottom: z * zLen,
                                    left: 2, right: 2,
                                    height: zLen,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: zColors[z],
                                        borderRadius: BorderRadius.circular(1)),
                                    ),
                                  );
                                }),
                              // Seek-bar long-press gesture overlay
                              if (onSeekBarLongPress != null)
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onLongPress: onSeekBarLongPress,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              // The vertical slider — SeekBarPainter for non-classic styles ──
                              RotatedBox(
                                quarterTurns: 1,
                                child: SizedBox(
                                  width: sliderLen,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Custom painter for all non-classic seek bar styles
                                      if (seekBarStyle != 'classic')
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: SeekBarPainter(
                                              style: seekBarStyleFromString(seekBarStyle),
                                              progress: progress.clamp(0.0, 1.0),
                                              buffered: bufferedFraction,
                                              accentColor: accentColor,
                                              chapterFractions: chapters
                                                  .where((_) => duration.inMilliseconds > 0)
                                                  .map((c) => (c.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0))
                                                  .toList(),
                                              moodEnabled: moodEnabled,
                                            ),
                                          ),
                                        ),
                                      SliderTheme(
                                        data: SliderTheme.of(ctx).copyWith(
                                          trackHeight: seekBarStyle != 'classic'
                                              ? 0 : (sliderDragging ? 5 : 3),
                                          thumbShape: RoundSliderThumbShape(
                                              enabledThumbRadius: sliderDragging ? 10 : 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                                          activeTrackColor: seekBarStyle != 'classic'
                                              ? Colors.transparent : accentColor,
                                          inactiveTrackColor: seekBarStyle != 'classic'
                                              ? Colors.transparent : Colors.white12,
                                          thumbColor: Colors.white,
                                          overlayColor: accentColor.withOpacity(0.13),
                                        ),
                                        child: Slider(
                                          value: progress.clamp(0.0, 1.0),
                                          onChangeStart: onSliderStart,
                                          onChanged: onSliderChange,
                                          onChangeEnd: onSliderEnd,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ),
                  // ── Duration at bottom of bar ─────────────────────────────────
                  GestureDetector(
                    onLongPress: onShareTimestamp,
                    child: Text(
                      fmtDur(duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                  // ── Frame-step controls when paused ──────────────────────────
                  if (!playing && showFrameStep)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded,
                            color: Colors.white70, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onFrameBackStep),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Frame',
                            style: TextStyle(color: Colors.white38, fontSize: 9)),
                        Text(
                          '#\${(position.inMilliseconds * 24.0 / 1000).round()}',
                          style: const TextStyle(color: Colors.white70, fontSize: 9,
                              fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                      ]),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded,
                            color: Colors.white70, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onFrameStep),
                    ]),
                ],
              ).animate().fadeIn(duration: 150.ms, curve: Curves.easeOut),
            ),
          ),
        ),
    ]);
  }
}

// ── Rotation helpers ────────────────────────────────────────────────────────────
  IconData _rotationIcon(String mode) {
    switch (mode) {
      case 'auto':          return Icons.screen_rotation_outlined;
      case 'lock_left':     return Icons.stay_current_landscape_rounded;
      case 'lock_right':    return Icons.screen_rotation_rounded;
      case 'lock_portrait': return Icons.stay_current_portrait_rounded;
      case 'lock_current':  return Icons.screen_lock_rotation_rounded;
      default:              return Icons.screen_rotation_rounded;
    }
  }

  String _rotationLabel(String mode) {
    switch (mode) {
      case 'auto':          return 'Auto';
      case 'lock_left':     return 'Left';
      case 'lock_right':    return 'Right';
      case 'lock_portrait': return 'Portrait';
      case 'lock_current':  return 'Current';
      default:              return 'Land';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
// MX PLAYER STYLE HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact side-strip button (right edge, MX Player style)
class _MxSideBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;
  const _MxSideBtn({required this.icon, required this.label, required this.onTap,
      this.active = false, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final col = active ? (activeColor ?? const Color(0xFFE8002D)) : Colors.white70;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 44,
        decoration: BoxDecoration(
          color: active ? (activeColor ?? const Color(0xFFE8002D)).withOpacity(0.18) : Colors.black45,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? (activeColor ?? const Color(0xFFE8002D)).withOpacity(0.55) : Colors.white.withOpacity(0.18),
            width: 0.8,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: col, size: 17),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

/// Triangular seek button (MX Player landscape style: double-chevron arrow + seconds)
class _MxSeekBtn extends StatelessWidget {
  final bool isForward;
  final int seconds;
  final VoidCallback onTap;
  const _MxSeekBtn({required this.isForward, required this.seconds, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: SizedBox(
        width: 54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isForward)
              Icon(Icons.keyboard_double_arrow_up_rounded,
                  color: Colors.white, size: 36),
            Text(
              '${seconds}s',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isForward)
              Icon(Icons.keyboard_double_arrow_down_rounded,
                  color: Colors.white, size: 36),
          ],
        ),
      ),
    );
  }
}

/// Small labeled badge for top bar (MX Player style)
class _MxBadge extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MxBadge({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.5), width: 0.8),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// SLEEP PANEL
// ═══════════════════════════════════════════════════════════════════════════════
class _SleepPanel extends StatelessWidget {
  final int? remaining;
  final ValueChanged<int> onSelect;
  final VoidCallback onCancel;
  const _SleepPanel({this.remaining, required this.onSelect, required this.onCancel});

  static const _options = [
    (label: '5 minutes',  value: 5),
    (label: '10 minutes', value: 10),
    (label: '15 minutes', value: 15),
    (label: '30 minutes', value: 30),
    (label: '45 minutes', value: 45),
    (label: '1 hour',     value: 60),
    (label: '2 hours',    value: 120),
    (label: 'End of episode', value: -1),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180, color: Colors.black87,
      child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Icon(Icons.bedtime_rounded, color: Colors.orange, size: 18),
            SizedBox(width: 8),
            Text('Sleep Timer', style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ])),
        if (remaining != null) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Stopping in ${remaining! ~/ 60}:${(remaining! % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.orange, fontSize: 12))),
          ListTile(dense: true,
            leading: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
            title: const Text('Cancel Timer', style: TextStyle(color: Colors.red, fontSize: 13)),
            onTap: onCancel),
          const Divider(color: Colors.white12),
        ],
        Expanded(child: ListView(children: _options.map((o) => ListTile(
          dense: true,
          leading: const Icon(Icons.alarm, color: Colors.white54, size: 18),
          title: Text(o.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          onTap: () => onSelect(o.value),
        )).toList())),
      ]),
    ).animate().slideX(begin: 1, end: 0, duration: 200.ms, curve: AppCurves.standard);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPEED PANEL
// ═══════════════════════════════════════════════════════════════════════════════
class _SpeedPanel extends StatelessWidget {
  final double currentSpeed;
  final List<double> speeds;
  final ValueChanged<double> onSelect;
  const _SpeedPanel({required this.currentSpeed, required this.speeds, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Container(width: 140, color: Colors.black87,
      child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Speed', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
        Expanded(child: ListView(children: speeds.map((s) => ListTile(
          title: Text('${s}×', style: TextStyle(
              color: s == currentSpeed ? AppColors.primary : Colors.white,
              fontWeight: s == currentSpeed ? FontWeight.w700 : FontWeight.normal)),
          leading: s == currentSpeed
              ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 18) : null,
          onTap: () => onSelect(s), dense: true)).toList())),
      ])).animate().slideX(begin: 1, end: 0, duration: 200.ms, curve: AppCurves.standard);
  }
}


// ─── ISO 639 language code → human name ────────────────────────────────────
String _langName(String? code) {
  if (code == null || code.isEmpty) return '';
  const m = {
    'eng': 'English',  'en': 'English',
    'hin': 'Hindi',    'hi': 'Hindi',
    'urd': 'Urdu',     'ur': 'Urdu',
    'pan': 'Punjabi',  'pun': 'Punjabi', 'pa': 'Punjabi',
    'pus': 'Pashto',   'ps': 'Pashto',
    'snd': 'Sindhi',   'sd': 'Sindhi',
    'ara': 'Arabic',   'ar': 'Arabic',
    'per': 'Persian',  'fas': 'Persian', 'fa': 'Persian',
    'zho': 'Chinese',  'chi': 'Chinese', 'zh': 'Chinese',
    'kor': 'Korean',   'ko': 'Korean',
    'jpn': 'Japanese', 'ja': 'Japanese',
    'tam': 'Tamil',    'ta': 'Tamil',
    'tel': 'Telugu',   'te': 'Telugu',
    'mal': 'Malayalam','ml': 'Malayalam',
    'kan': 'Kannada',  'kn': 'Kannada',
    'ben': 'Bengali',  'bn': 'Bengali',
    'fre': 'French',   'fra': 'French', 'fr': 'French',
    'ger': 'German',   'deu': 'German', 'de': 'German',
    'spa': 'Spanish',  'es': 'Spanish',
    'ita': 'Italian',  'it': 'Italian',
    'rus': 'Russian',  'ru': 'Russian',
    'por': 'Portuguese','pt': 'Portuguese',
    'tur': 'Turkish',  'tr': 'Turkish',
    'und': '',
  };
  final key = code.toLowerCase().trim();
  return m[key] ?? (key.length <= 3 ? key.toUpperCase() : code);
}

List<String> _buildAudioLabels(List<dynamic> tracks) {
  final names = <String>[];
  final usedLangs = <String, int>{};
  for (var t in tracks) {
    final lang = _langName(t.language as String?);
    if (lang.isEmpty) {
      names.add('Audio ${names.length + 1}');
    } else {
      usedLangs[lang] = (usedLangs[lang] ?? 0) + 1;
      final count = usedLangs[lang]!;
      names.add(count == 1 ? lang : '$lang ($count)');
    }
  }
  return names;
}

List<String> _buildSubLabels(List<dynamic> tracks) {
  final names = <String>[];
  final usedLangs = <String, int>{};
  for (var t in tracks) {
    final lang = _langName(t.language as String?);
    final title = (t.title ?? '') as String;
    String label;
    if (lang.isNotEmpty) {
      usedLangs[lang] = (usedLangs[lang] ?? 0) + 1;
      final count = usedLangs[lang]!;
      label = count == 1 ? lang : '$lang ($count)';
    } else if (title.isNotEmpty) {
      label = title;
    } else {
      label = 'Sub ${names.length + 1}';
    }
    names.add(label);
  }
  return names;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKS PANEL
// ═══════════════════════════════════════════════════════════════════════════════
class _TracksPanel extends StatelessWidget {
  final String title;
  final List<String> tracks;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  const _TracksPanel({required this.title, required this.tracks, required this.onSelect, this.activeIndex = 0});
  @override
  Widget build(BuildContext context) {
    return Container(width: 200, color: Colors.black87,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
        Expanded(child: tracks.isEmpty
            ? const Center(child: Text('No tracks', style: TextStyle(color: Colors.white54, fontSize: 13)))
            : ListView.builder(itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final isActive = i == activeIndex;
                  return ListTile(
                    title: Text(tracks[i], style: TextStyle(
                      color: isActive ? const Color(0xFFE8002D) : Colors.white,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.normal)),
                    trailing: isActive
                      ? const Icon(Icons.check_rounded, color: Color(0xFFE8002D), size: 16)
                      : null,
                    dense: true, onTap: () => onSelect(i));
                })),
      ])).animate().slideX(begin: 1, end: 0, duration: 200.ms, curve: AppCurves.standard);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEEK FLASH
// ═══════════════════════════════════════════════════════════════════════════════
class _SeekFlash extends StatelessWidget {
  final bool isRight;
  final String label;
  const _SeekFlash({required this.isRight, required this.label});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Positioned(
      left: isRight ? w / 2 : 0, right: isRight ? 0 : w / 2, top: 0, bottom: 0,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
          end:   isRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: [Colors.white.withOpacity(0.08), Colors.transparent])),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(isRight ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white, size: 36),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ])),
      ),
    ).animate().fadeIn(duration: 150.ms).then().fadeOut(duration: 400.ms, delay: 250.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
// IMMERSIVE DRAG NUMBER — minimal number-only HUD for Immersive mode
// ═══════════════════════════════════════════════════════════════════════════════
class _ImmersiveDragNumber extends StatelessWidget {
  final double value;
  final bool isBrightness;
  final bool isBoost;
  final double? boostValue;
  const _ImmersiveDragNumber({
    required this.value,
    required this.isBrightness,
    required this.isBoost,
    this.boostValue,
  });

  @override
  Widget build(BuildContext context) {
    final pct = isBoost && boostValue != null
        ? '${(boostValue! * 100).toInt()}%'
        : '${(value * 100).toInt()}%';
    final color = isBoost
        ? (boostValue != null && boostValue! > 2.5
            ? Colors.red
            : boostValue != null && boostValue! > 1.5
                ? Colors.orange
                : Colors.white70)
        : Colors.white70;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          pct,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 80.ms).then(delay: 600.ms).fadeOut(duration: 300.ms);
  }
}

// DRAG INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════
class _DragIndicator extends StatelessWidget {
  final IconData icon;
  final double value;
  final double? boostValue; // non-null = we are in boost territory
  const _DragIndicator({required this.icon, required this.value, this.boostValue});

  @override
  Widget build(BuildContext context) {
    final isBoost = boostValue != null;
    // Color: orange at 150%+, red at 250%+
    final pillColor = isBoost
        ? (boostValue! > 2.5
            ? Colors.red
            : boostValue! > 1.5
                ? Colors.orange
                : Colors.white)
        : Colors.white;
    final barValue = isBoost
        ? ((boostValue! - 1.0) / 2.0).clamp(0.0, 1.0) // 100%-300% mapped to 0-1
        : value;
    final label = isBoost
        ? '${(boostValue! * 100).toInt()}%'
        : '${(value * 100).toInt()}%';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(12),
          border: isBoost
              ? Border.all(color: pillColor.withOpacity(0.5), width: 1.2)
              : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: pillColor, size: 28),
          const SizedBox(height: 8),
          SizedBox(
            width: 100,
            child: LinearProgressIndicator(
              value: barValue,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(pillColor),
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
          if (isBoost) ...[
            Text('⚡ Boost', style: TextStyle(color: pillColor.withOpacity(0.8), fontSize: 10)),
            const SizedBox(height: 2),
          ],
          Text(label, style: TextStyle(color: pillColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    ).animate().scale(
      begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
      duration: 180.ms, curve: Curves.elasticOut,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEXT EPISODE OVERLAY  (unchanged)
// ═══════════════════════════════════════════════════════════════════════════════
class _NextEpisodeOverlay extends StatelessWidget {
  final String currentTitle, nextTitle;
  final int countdown;
  final VoidCallback onPlay, onCancel, onSkipCountdown;
  const _NextEpisodeOverlay({
    required this.currentTitle, required this.nextTitle, required this.countdown,
    required this.onPlay, required this.onCancel, required this.onSkipCountdown,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.skip_next_rounded, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text('Up Next', style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 8),
          Text(nextTitle, style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text('Playing in $countdown...', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(onPressed: onCancel,
              child: const Text('Exit', style: TextStyle(color: Colors.white54, fontSize: 15))),
            const SizedBox(width: 24),
            ElevatedButton(
              onPressed: onSkipCountdown,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              child: const Text('Play Now', style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
        ]),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

  // ── More Panel (MX Player–style bottom sheet) ────────────────────────────────
  class _MxMoreSheet extends StatelessWidget {
      final bool cinematicMode;
      final bool immersiveMode;
      final bool abLoopActive;
      final bool sleepActive;
      final int bookmarkCount;
      final double speed;
      final String fitLabel;
      final bool castConnected;
      final VoidCallback onFit;
      final VoidCallback onSpeed;
      final VoidCallback onNight;
      final VoidCallback onLoop;
      final VoidCallback onSleep;
      final VoidCallback onBookmarks;
      final VoidCallback onEq;
      final VoidCallback onScreenshot;
      final VoidCallback onCast;
      final VoidCallback onPiP;
      final VoidCallback onRotation;
      final VoidCallback onSettings;
      final VoidCallback onOpenWith;
      final VoidCallback onVideoDisplay;
      final VoidCallback onImmersive;
      final VoidCallback onImmersiveSettings;
      final VoidCallback onCinematicSettings;

      const _MxMoreSheet({
        required this.cinematicMode,
        required this.immersiveMode,
        required this.abLoopActive,
        required this.sleepActive,
        required this.bookmarkCount,
        required this.speed,
        required this.fitLabel,
        required this.castConnected,
        required this.onFit,
        required this.onSpeed,
        required this.onNight,
        required this.onLoop,
        required this.onSleep,
        required this.onBookmarks,
        required this.onEq,
        required this.onScreenshot,
        required this.onCast,
        required this.onPiP,
        required this.onRotation,
        required this.onSettings,
        required this.onOpenWith,
        required this.onVideoDisplay,
        required this.onImmersive,
        required this.onImmersiveSettings,
        required this.onCinematicSettings,
      });

      @override
      Widget build(BuildContext context) {
        // 4-column grid matching MX Player screenshot
        final items = <Map<String, dynamic>>[
          {'icon': Icons.queue_play_next_rounded,    'label': 'Playing\nQueue',    'active': false,             'color': null,                      'tap': onSpeed},
          {'icon': Icons.content_cut_rounded,        'label': 'Cut',               'active': false,             'color': null,                      'tap': onScreenshot},
          {'icon': Icons.share_rounded,              'label': 'Share',             'active': false,             'color': null,                      'tap': onOpenWith},
          {'icon': Icons.display_settings_rounded,   'label': 'Video Display\nShortcuts', 'active': false,     'color': null,                      'tap': onVideoDisplay},
          {'icon': Icons.fit_screen_rounded,         'label': 'Aspect\nRatio',     'active': fitLabel != 'Fit', 'color': const Color(0xFFE8002D),   'tap': onFit},
          {'icon': Icons.favorite_border_rounded,    'label': 'Favourite',         'active': false,             'color': Colors.red,                'tap': onBookmarks},
          {'icon': Icons.cast_rounded,               'label': 'Network\nStream',   'active': castConnected,     'color': const Color(0xFF4FC3F7),   'tap': onCast},
          {'icon': Icons.picture_in_picture_alt_rounded, 'label': 'PiP',           'active': false,             'color': null,                      'tap': onPiP},
          {'icon': Icons.playlist_add_rounded,       'label': 'Add To\nPlaylist',  'active': false,             'color': null,                      'tap': onBookmarks},
          {'icon': Icons.visibility_off_rounded,     'label': 'Immersive\nMode',   'active': immersiveMode,     'color': const Color(0xFF8B5CF6),   'tap': onImmersive,  'longTap': onImmersiveSettings},
          {'icon': Icons.equalizer_rounded,          'label': 'Equalizer',         'active': false,             'color': null,                      'tap': onEq},
          {'icon': Icons.dark_mode_rounded,          'label': 'Night\nMode',       'active': cinematicMode,     'color': const Color(0xFF3B82F6),   'tap': onNight,      'longTap': onCinematicSettings},
          {'icon': Icons.info_outline_rounded,       'label': 'Information',       'active': false,             'color': null,                      'tap': onSettings},
          {'icon': Icons.bookmarks_rounded,          'label': 'Bookmark',          'active': bookmarkCount > 0, 'color': Colors.amber,              'tap': onBookmarks},
          {'icon': sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                                     'label': 'Sleep\nTimer',      'active': sleepActive,       'color': Colors.orange,             'tap': onSleep},
          {'icon': Icons.loop_rounded,               'label': 'A-B\nRepeat',       'active': abLoopActive,      'color': const Color(0xFFE8002D),   'tap': onLoop},
        ];
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xF0101018),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return _MoreBtn(
                  icon: item['icon'] as IconData,
                  label: item['label'] as String,
                  active: item['active'] as bool,
                  activeColor: item['color'] as Color?,
                  onTap: item['tap'] as VoidCallback,
                  onLongPress: item['longTap'] as VoidCallback?,
                );
              },
            ),
          ]),
        ).animate().slideY(begin: 1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
      }
    }

    class _MoreBtn extends StatelessWidget {
      final IconData icon;
      final String label;
      final bool active;
      final Color? activeColor;
      final VoidCallback onTap;
      final VoidCallback? onLongPress;

      const _MoreBtn({
        required this.icon, required this.label,
        required this.active, this.activeColor, required this.onTap,
        this.onLongPress,
      });

      @override
      Widget build(BuildContext context) {
        final col = active ? (activeColor ?? const Color(0xFFE8002D)) : Colors.white54;
        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 72,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? (activeColor ?? const Color(0xFFE8002D)).withOpacity(0.15)
                      : Colors.white.withOpacity(0.07),
                  border: Border.all(
                    color: active
                        ? (activeColor ?? const Color(0xFFE8002D)).withOpacity(0.4)
                        : Colors.white12,
                  ),
                ),
                child: Icon(icon, color: col, size: 24),
              ),
              const SizedBox(height: 5),
              Text(label,
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.w500)),
            ]),
          ),
        );
      }
    }

// ═══════════════════════════════════════════════════════════════════════════════
// MX PLAYER STYLE — VIDEO DISPLAY SHORTCUTS PANEL (screenshot 7)
// ═══════════════════════════════════════════════════════════════════════════════
class _VideoDisplaySheet extends StatelessWidget {
  final bool screenRotation;
  final bool bgPlay;
  final bool isMuted;
  final bool eqEnabled;
  final bool sleepActive;
  final bool nightMode;
  final double speed;
  final bool loopActive;
  final bool abRepeatActive;

  final VoidCallback onScreenRotation;
  final ValueChanged<bool> onBgPlay;
  final ValueChanged<bool> onMute;
  final VoidCallback onEq;
  final VoidCallback onSleep;
  final VoidCallback onNightMode;
  final VoidCallback onSpeed;
  final VoidCallback onAudioEffect;
  final VoidCallback onAbRepeat;
  final VoidCallback onDone;

  const _VideoDisplaySheet({
    required this.screenRotation,
    required this.bgPlay,
    required this.isMuted,
    required this.eqEnabled,
    required this.sleepActive,
    required this.nightMode,
    required this.speed,
    required this.loopActive,
    required this.abRepeatActive,
    required this.onScreenRotation,
    required this.onBgPlay,
    required this.onMute,
    required this.onEq,
    required this.onSleep,
    required this.onNightMode,
    required this.onSpeed,
    required this.onAudioEffect,
    required this.onAbRepeat,
    required this.onDone,
  });

  static const _accent  = Color(0xFFE8002D);
  static const _blue    = Color(0xFF1565C0);
  static const _surface = Color(0xFF12121E);

  @override
  Widget build(BuildContext context) {
    // Row 1 (screenshot 7, top row): Screen Rotation, Background Play, Mute, Equalizer, Sleep Timer, Night Mode
    // Row 2 (screenshot 7, bottom row): Playback Speed, Customise Items, A-B Repeat, Audio Effect, Loop, Shuffle
    final row1 = [
      _VDSBtn(icon: Icons.screen_rotation_rounded,      label: 'Screen
Rotation',    active: screenRotation,     onTap: (_) => onScreenRotation()),
      _VDSBtn(icon: Icons.play_circle_outline_rounded,  label: 'Background
Play',    active: bgPlay,             onTap: onBgPlay,  isToggle: true),
      _VDSBtn(icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                                         label: 'Mute',               active: isMuted,            onTap: onMute,    isToggle: true),
      _VDSBtn(icon: Icons.equalizer_rounded,             label: 'Equalizer',          active: eqEnabled,          onTap: (_) => onEq()),
      _VDSBtn(icon: sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                                         label: 'Sleep
Timer',       active: sleepActive,        onTap: (_) => onSleep()),
      _VDSBtn(icon: Icons.dark_mode_rounded,             label: 'Night
Mode',        active: nightMode,          onTap: (_) => onNightMode()),
    ];
    final row2 = [
      _VDSBtn(icon: Icons.speed_rounded,                 label: 'Playback
Speed',    active: speed != 1.0,       onTap: (_) => onSpeed()),
      _VDSBtn(icon: Icons.loop_rounded,                  label: 'Loop',               active: loopActive,         onTap: (_) {}, isToggle: true),
      _VDSBtn(icon: Icons.shuffle_rounded,               label: 'Shuffle',            active: false,              onTap: (_) {}),
      _VDSBtn(icon: Icons.graphic_eq_rounded,            label: 'Audio
Effect',      active: false,              onTap: (_) => onAudioEffect()),
      _VDSBtn(icon: Icons.repeat_one_rounded,            label: 'A-B
Repeat',        active: abRepeatActive,     onTap: (_) => onAbRepeat()),
      _VDSBtn(icon: Icons.tune_rounded,                  label: 'Customise
Items',   active: false,              onTap: (_) {}),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.fromLTRB(0, 10, 0, 14),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        // Header
        Row(children: [
          const Icon(Icons.display_settings_rounded, color: Colors.white54, size: 18),
          const SizedBox(width: 8),
          const Text('Video Display Shortcuts',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: onDone,
            child: const Text('Done', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        // Row 1
        Row(children: row1.map((btn) => Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: _VDSTile(btn: btn),
        ))).toList()),
        const SizedBox(height: 10),
        // Row 2
        Row(children: row2.map((btn) => Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: _VDSTile(btn: btn),
        ))).toList()),
        const SizedBox(height: 8),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
  }
}

class _VDSBtn {
  final IconData icon;
  final String label;
  final bool active;
  final bool isToggle;
  final ValueChanged<bool> onTap;
  const _VDSBtn({
    required this.icon, required this.label, required this.active,
    required this.onTap, this.isToggle = false,
  });
}

class _VDSTile extends StatelessWidget {
  final _VDSBtn btn;
  const _VDSTile({required this.btn});

  static const _blue   = Color(0xFF1565C0);
  static const _accent = Color(0xFFE8002D);

  @override
  Widget build(BuildContext context) {
    final on = btn.active;
    return GestureDetector(
      onTap: () => btn.onTap(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: on ? _blue : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on ? _blue.withOpacity(0.8) : Colors.white12,
            width: on ? 1.5 : 1.0,
          ),
          boxShadow: on ? [BoxShadow(color: _blue.withOpacity(0.25), blurRadius: 8)] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(btn.icon, color: on ? Colors.white : Colors.white54, size: 22),
            const SizedBox(height: 5),
            Text(
              btn.label,
              style: TextStyle(
                color: on ? Colors.white : Colors.white54,
                fontSize: 9,
                height: 1.25,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════════════
// MX PLAYER STYLE — CIRCULAR DOTS LOADING ANIMATION (screenshot 15)
// ═══════════════════════════════════════════════════════════════════════════════
class _CircularDotsLoader extends StatefulWidget {
  const _CircularDotsLoader();
  @override
  State<_CircularDotsLoader> createState() => _CircularDotsLoaderState();
}

class _CircularDotsLoaderState extends State<_CircularDotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MX Player screenshot 15: large ring of uniform white dots with center AI icon
    const dotCount = 40;
    const radius = 80.0;
    const dotRadius = 5.5;
    const totalSize = (radius + dotRadius) * 2 + 16;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final phase = _ctrl.value;
        return SizedBox(
          width: totalSize,
          height: totalSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ring of dots — MX Player style: bright leading dot, fading tail
              ...List.generate(dotCount, (i) {
                final angle = (i / dotCount) * 2 * math.pi - math.pi / 2;
                final cx = radius * math.cos(angle);
                final cy = radius * math.sin(angle);
                final dotPhase = i / dotCount;
                double diff = (phase - dotPhase) % 1.0;
                if (diff < 0) diff += 1.0;
                // Short bright tail: only dots within 0–25% behind the leading dot are visible
                final opacity = diff < 0.25
                    ? (1.0 - (diff / 0.25) * 0.75)
                    : 0.12;
                return Positioned(
                  left: radius + dotRadius + cx - dotRadius,
                  top:  radius + dotRadius + cy - dotRadius,
                  child: Container(
                    width: dotRadius * 2,
                    height: dotRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(opacity.clamp(0.12, 1.0)),
                    ),
                  ),
                );
              }),
              // Center icon — MX Player: sparkle/AI magic icon
              const Icon(Icons.auto_awesome_rounded, color: Colors.white70, size: 32),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MX PLAYER STYLE — AUDIO TRACK PANEL (screenshots 4, 14)
// ═══════════════════════════════════════════════════════════════════════════════
class _MxAudioPanel extends StatefulWidget {
  final List<String> tracks;
  final int activeIndex;
  final int syncMs;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onSyncChanged;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _MxAudioPanel({
    required this.tracks,
    required this.activeIndex,
    required this.syncMs,
    required this.onSelect,
    required this.onSyncChanged,
    required this.onOpen,
    required this.onClose,
  });

  @override
  State<_MxAudioPanel> createState() => _MxAudioPanelState();
}

class _MxAudioPanelState extends State<_MxAudioPanel> {
  late int _syncMs;
  bool _swDecoder = false;

  @override
  void initState() {
    super.initState();
    _syncMs = widget.syncMs;
  }

  void _adjustSync(int delta) {
    setState(() => _syncMs = (_syncMs + delta).clamp(-5000, 5000));
    widget.onSyncChanged(_syncMs);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(
        color: Color(0xF0101018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),

        // Header
        Row(children: [
          const Icon(Icons.audiotrack_rounded, color: Color(0xFF4DB6FF), size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Audio Track',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 20),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 12),

        // Horizontal chip track list (MX Player screenshots 4, 14 style)
        if (widget.tracks.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                // "Disable" option
                _AudioTrackChip(
                  label: 'Disable',
                  selected: widget.activeIndex < 0,
                  onTap: () => widget.onSelect(-1),
                ),
                const SizedBox(width: 8),
                ...widget.tracks.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _AudioTrackChip(
                    label: e.value.isNotEmpty ? e.value : 'Audio ${e.key + 1}',
                    selected: e.key == widget.activeIndex,
                    onTap: () => widget.onSelect(e.key),
                  ),
                )),
              ],
            ),
          ),

        const Divider(color: Colors.white12, height: 20),

        // Options row: Open | Stereo Mode | SW Decoder
        Row(children: [
          _MxPanelOption(icon: Icons.folder_open_rounded, label: 'Open', onTap: widget.onOpen),
          const SizedBox(width: 16),
          _MxPanelOption(icon: Icons.headphones_rounded, label: 'Stereo mode', onTap: () {}),
          const SizedBox(width: 16),
          const Spacer(),
          const Text('SW Decoder', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _swDecoder,
              activeColor: const Color(0xFF4DB6FF),
              onChanged: (v) => setState(() => _swDecoder = v),
            ),
          ),
        ]),

        const Divider(color: Colors.white12, height: 20),

        // Synchronization section
        Row(children: [
          const Icon(Icons.sync_rounded, color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          const Text('Synchronization', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          _SyncButton(icon: Icons.remove, onTap: () => _adjustSync(-100)),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              '${(_syncMs / 1000).toStringAsFixed(2)}s',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _syncMs != 0 ? const Color(0xFF4DB6FF) : Colors.white,
                fontSize: 14, fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SyncButton(icon: Icons.add, onTap: () => _adjustSync(100)),
        ]),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 260.ms, curve: Curves.easeOutCubic);
  }
}

class _AudioTrackChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AudioTrackChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.white10,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF4DB6FF) : Colors.white12,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? const Color(0xFF4DB6FF) : Colors.white38,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SyncButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white10,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}

class _MxPanelOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MxPanelOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white54, size: 17),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MX PLAYER STYLE — SUBTITLE PANEL (screenshots 5, 13)
// ═══════════════════════════════════════════════════════════════════════════════
class _MxSubPanel extends StatefulWidget {
  final List<String> tracks;
  final int activeIndex;
  final int syncMs;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onSyncChanged;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  const _MxSubPanel({
    required this.tracks,
    required this.activeIndex,
    required this.syncMs,
    required this.onSelect,
    required this.onSyncChanged,
    required this.onOpen,
    required this.onSettings,
    required this.onClose,
  });

  @override
  State<_MxSubPanel> createState() => _MxSubPanelState();
}

class _MxSubPanelState extends State<_MxSubPanel> {
  late int _syncMs;

  @override
  void initState() {
    super.initState();
    _syncMs = widget.syncMs;
  }

  void _adjustSync(int delta) {
    setState(() => _syncMs = (_syncMs + delta).clamp(-5000, 5000));
    widget.onSyncChanged(_syncMs);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60),
      decoration: const BoxDecoration(
        color: Color(0xF0101018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),

        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Icon(Icons.subtitles_rounded, color: Color(0xFF4DB6FF), size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Subtitle',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            // "Online subtitles" label (decorative, MX Player style)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Online subs', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white38, size: 20),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Horizontal scrollable subtitle track chips (MX Player style)
        if (widget.tracks.isNotEmpty)
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final isActive = i == widget.activeIndex;
                return GestureDetector(
                  onTap: () => widget.onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF1565C0) : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive ? const Color(0xFF4DB6FF) : Colors.white12,
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isActive) ...[
                        const Icon(Icons.chevron_left, color: Color(0xFF4DB6FF), size: 16),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        widget.tracks[i],
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No subtitle tracks', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),

        const SizedBox(height: 14),

        // Action buttons row: Open | Settings | Add Translation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _MxPanelOption(icon: Icons.folder_open_rounded, label: 'Open', onTap: widget.onOpen),
            const SizedBox(width: 20),
            _MxPanelOption(icon: Icons.settings_rounded, label: 'Settings', onTap: widget.onSettings),
            const Spacer(),
            GestureDetector(
              onTap: () {},
              child: const Text('+ Add Translation',
                  style: TextStyle(color: Color(0xFF4DB6FF), fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),

        const Divider(color: Colors.white12, height: 24),

        // Synchronization
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Icon(Icons.sync_rounded, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            const Text('Synchronization', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            _SyncButton(icon: Icons.remove, onTap: () => _adjustSync(-100)),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                '${(_syncMs / 1000).toStringAsFixed(2)}s',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _syncMs != 0 ? const Color(0xFF4DB6FF) : Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SyncButton(icon: Icons.add, onTap: () => _adjustSync(100)),
          ]),
        ),
      ]),
    ).animate().slideY(begin: 1, end: 0, duration: 260.ms, curve: Curves.easeOutCubic);
  }
}


  // Color Blind Mode — 5×4 ColorFilter.matrix for daltonization correction
  static List<double> _colorBlindMatrix(String mode) {
    switch (mode) {
      case 'deuteranopia':
        return [0.625,0.375,0.0,0,0, 0.7,0.3,0.0,0,0, 0.0,0.3,0.7,0,0, 0,0,0,1,0];
      case 'protanopia':
        return [0.567,0.433,0.0,0,0, 0.558,0.442,0.0,0,0, 0.0,0.242,0.758,0,0, 0,0,0,1,0];
      case 'tritanopia':
        return [0.95,0.05,0.0,0,0, 0.0,0.433,0.567,0,0, 0.0,0.475,0.525,0,0, 0,0,0,1,0];
      default:
        return [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
    }
  }

// ─────────────────────────────────────────────────────────────────────────────
// Smart Volume Leveling — Dart-side volume ramp controller (Phase SVL)
// Smoothly adjusts MPV 'volume' property toward a user-set target level.
// Works alongside the MPV-side acompressor filter for full DRC coverage.
// ─────────────────────────────────────────────────────────────────────────────
class _SmartVolumeController {
  final Player      player;
  final NativePlayer np;

  double _targetVol; // 0–100 (MPV volume scale)
  String _mode;      // 'gentle' | 'balanced' | 'aggressive'

  Timer? _timer;
  bool   _running = false;

  _SmartVolumeController({
    required this.player,
    required this.np,
    required double targetLevel, // 0.0–1.0 → maps to 0–100
    required String mode,
  })  : _targetVol = targetLevel * 100.0,
        _mode      = mode;

  void start() {
    if (_running) return;
    _running = true;
    _timer?.cancel();
    // Tick every 600 ms — smooth but not spammy
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) => _tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void update({required double targetLevel, required String mode}) {
    _targetVol = targetLevel * 100.0;
    _mode      = mode;
  }

  Future<void> _tick() async {
    try {
      final current = player.state.volume; // 0–100 from media_kit state
      final diff    = _targetVol - current;
      if (diff.abs() < 0.8) return; // within tolerance — skip

      // Step per tick: gentle=0.5  balanced=1.5  aggressive=4.0
      final step = _mode == 'aggressive' ? 4.0
                 : _mode == 'balanced'   ? 1.5
                 :                         0.5;
      final move   = diff.sign * step.clamp(0, diff.abs());
      final newVol = (current + move).clamp(20.0, 130.0);
      await np.setProperty('volume', newVol.toStringAsFixed(1));
    } catch (_) {} // ignore if player torn down mid-tick
  }

  void dispose() {
    _timer?.cancel();
    _running = false;
  }
}
