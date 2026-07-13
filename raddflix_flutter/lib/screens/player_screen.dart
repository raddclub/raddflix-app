// player_screen.dart — MX Player Style v3 (2026-06-19)
// Portrait orientation. MX Player layout exact copy.
//
// MediaTek HW decoder safety rules (NEVER break these):
//   • NEVER vf= or any video filter property
//   • NEVER change hwdec mid-play
//   • _videoOpened = true BEFORE every _player.open()
//   • androidAttachSurfaceAfterVideoParameters: false (CRITICAL)
//   • Speed via NativePlayer.setProperty('speed', ...) with framedrop guard
//
// Smart Enhance = Flutter ColorFiltered widget (NOT MPV vf=) — 100% safe
// EQ = MPV af=equalizer (audio only) — 100% safe
// Sub sync = MPV sub-delay — 100% safe
// Audio sync = MPV audio-delay — 100% safe

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/jazzdrive_service.dart';
import '../core/db/local_db.dart';
import '../core/api/catalog_api.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import '../widgets/player/seek_bar_painter.dart';
import '../core/player/watch_party_service.dart';
import '../core/player/voice_commands_service.dart';
import '../core/services/usage_service.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../core/player/subtitle_dubber.dart';
import '../core/player/player_prefs_provider.dart';
import '../design_system/components/radd_sheet.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';

// ── Phase J: panel classes extracted to part files ─────────────────────────
part 'player/_ps_panels_subtitle.dart';
part 'player/_ps_panels_audio.dart';
part 'player/_ps_panels_sidebar.dart';
part 'player/_ps_playback_mixin.dart';
part 'player/_ps_audiolab_mixin.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Widget
// ─────────────────────────────────────────────────────────────────────────────

class PlayerScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String? localPath;
  final String? subtitlePath;
  final List<Map<String, dynamic>>? episodes;
  final int episodeIndex;
  final String contentType;
  // G1: these three used to be read at runtime via
  // `ModalRoute.of(context)?.settings.arguments` instead of being passed as
  // constructor params. That indirection is exactly what caused
  // BUG-FREE-PLAY-01 (a PageRouteBuilder that didn't forward `settings:`
  // silently dropped `is_free`, charging free content). Making them typed,
  // required-at-the-call-site fields removes that failure mode entirely —
  // there's no longer a second, independent path that can diverge from what
  // the caller intended.
  final bool isFree;
  final String? streamUrl;
  final String? posterUrl;

  const PlayerScreen({
    super.key,
    required this.fileId,
    required this.title,
    this.localPath,
    this.subtitlePath,
    this.episodes,
    this.episodeIndex = 0,
    this.contentType = 'series',
    this.isFree = false,
    this.streamUrl,
    this.posterUrl,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
//  State
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, _PlayerPlaybackMixin, _PlayerAudioLabMixin {

  // ── MPV player ──────────────────────────────────────────────────────────────


  // ── Black-screen guards (MediaTek/Infinix) ──────────────────────────────────



  // ── Controls visibility ─────────────────────────────────────────────────────
  bool _showControls = true;
  bool _panelOpen = false;
  Timer? _hideTimer;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Gesture ─────────────────────────────────────────────────────────────────
  String? _dragIntent; // 'brightness' | 'volume' | 'seekbar'
  Offset _dragStart = Offset.zero;
  double _startBrightness = 0.5;
  double _startVolume = 0.7;
  Duration _dragStartPos = Duration.zero;
  double? _seekBarDelta; // fractional 0..1 during seekbar drag

  // ── Volume / Brightness ──────────────────────────────────────────────────────
  double _brightness = 0.5;
  double _volume = 0.7;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  Timer? _indicatorTimer;

  // ── Seek flash ───────────────────────────────────────────────────────────────
  bool _showSeekFlash = false;
  bool _seekFlashLeft = false;

  // ── Audio / Subtitle tracks ──────────────────────────────────────────────────
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _selectedAudio;
  List<SubtitleTrack> _subtitleTracks = [];
  SubtitleTrack? _selectedSubtitle;
  SubtitleTrack? _selectedSecondSub; // secondary-sid — OST / signs track
  // Language preference — persisted; null = let MPV auto-select
  String? _prefSubLang;
  String? _prefAudioLang;

  // ── MX Layout State ──────────────────────────────────────────────────────────
  bool _isLocked = false;
  bool _isImmersive = false;        // Immersive / cinema mode
  bool _immersiveExitVisible = false; // tiny exit button visible after tap
  Timer? _immersiveExitTimer;       // auto-hides exit button after 3s
  BoxFit _videoFit = BoxFit.contain;

  // Smart Enhance
  bool _smartEnhanceEnabled = false;
  Timer? _smartEnhanceTimer;

  // Video zoom
  // 0=Fit 1=Stretch 2=Crop 3=100% 4=Custom
  int _zoomMode = 0;
  // Pinch-to-zoom
  double _pinchScale = 1.0;
  double _pinchBaseScale = 1.0;
  bool _showZoomIndicator = false;

  // Night mode eye-comfort filter
  bool _nightModeEnabled = false;
  double _nightWarmth = 0.4;

  // Clock overlay in title bar
  bool _showClockInTitle = true;
  String _clockStr = '';
  Timer? _clockDisplayTimer;

  // Audio L/R balance

  // Video rotation (0/90/180/270)
  int _videoRotation = 0;

  // Subtitle bottom margin — promoted to main state so controls-hide can shift it
  double _subBottomMarginMain = 100.0;


  // Subtitle
  double _subSync = 0.0; // seconds
  double _subSpeed = 1.0; // 0.5..2.0
  String? _currentSubFile;

  // Audio
  double _audioSync = 0.0;
  bool _useSWDecoder = false;
  String _currentAudioCodec = '';


  // ── Real track getters — filter media_kit sentinel values ───────────────────
  // SubtitleTrack.no() has id='no'; AudioTrack.auto() has id='auto'.
  // Only tracks with numeric MPV IDs are real embedded tracks.
  List<SubtitleTrack> get _realSubtitleTracks =>
      _subtitleTracks.where((t) => t.id != null && int.tryParse(t.id!) != null).toList();
  List<AudioTrack> get _realAudioTracks =>
      _audioTracks.where((t) => t.id != null && int.tryParse(t.id!) != null).toList();

  // Sleep timer
  int? _sleepTimerMinutes;
  Timer? _sleepTimer;
  int _autoAdvanceCountdown = 0;
  Timer? _autoAdvanceTimer;
  DateTime? _sleepTimerEnd;

  // Settings
  bool _showRemainingTime = false;
  bool _keepScreenOn = true;
  bool _showSkipBtns = true;
  bool _showPrevNextBtns = true;
  bool _showSeekPositionLabel = true;
  int _skipInterval = 10;
  double _seekSwipeSec = 120.0;
  // Feature 26 — resume position
  Timer? _savePositionTimer;
  // Background-playback notification refresh timer (fires every 5 s)
  Timer? _bgNotifTimer;
  bool _isInBackground = false;






  // Layout preset
  String _layoutPreset = 'default'; // default | cinema | compact

  // Voice commands
  bool _voiceCommandsEnabled = false;

  // Gesture toggles
  bool _doubleTapSeekEnabled = true;
  bool _longPressSpeedEnabled = true;
  bool _swipeSeekEnabled = true;
  bool _swipeBVEnabled = true;

  // Skip editor
  bool _skipEditorEnabled = false;
  Duration? _introStart;
  Duration? _introEnd;
  Duration? _outroStart;

  // Watch Party state
  WatchPartyRoom? _watchPartyRoom;
  StreamSubscription<WatchPartyRoom?>? _watchPartySub;

  // Voice Commands state
  StreamSubscription<VoiceCommand>? _voiceSub;
  String _lastVoiceCmd = '';
  Timer? _voiceCmdTimer;

  // One-handed mode — hand preference
  bool _oneHandedLeft = false;


  // ── Customizable sidebar ──────────────────────────────────────────────────
  bool _sidebarExpanded = true;
  // Ordered list of shortcut IDs shown in the sidebar (persisted)
  List<String> _sidebarOrder = [
    'cc','audio','eq','vivid','episodes','speed','loop','pip',
  ];
  static const _allSidebarIds = [
    'cc','audio','eq','speed','loop','rotate','lock','pip',
    'screenshot','sleep','ab','episodes','settings','vivid',
    'mute','frame','onehanded','zoom','silence','more',
  ];

  // Skip editor debounce
  String? _lastSkipRegion;

  // Zoom/crop — separate aspect ratio index from BoxFit mode
  int _cropAspectIdx = 0;




  // ── P7: One-handed mode ──────────────────────────────────────────────────────
  bool _oneHandedMode = false;

  // ── P12: Background audio ────────────────────────────────────────────────────
  bool _backgroundAudio = false;

  // ── P14: Accent color (0=orange,1=blue,2=green,3=pink) ──────────────────────
  int _accentColorIdx = 0;
  static const _accentColors = [
    Color(0xFFE8950A),
    Color(0xFF3A8EF5),
    Color(0xFF34C759),
    Color(0xFFFF2D55),
  ];
  Color get _accentColor => _accentColors[_accentColorIdx];

  // ── P14: Progress bar style (0=slim,1=thick,2=gradient) ─────────────────────
  int _progressBarStyle = 0;


  // ── P9: Seek preview label (shown above seek bar during drag) ────────────────
  String _seekPreviewLabel = '';


  // ═══════════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Allow all orientations — video dimension auto-detects the right one
    // Allow all 4 orientations so Flutter layout responds to any rotation.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // Force sensor-based rotation via the native Android API — works even
    // when the user's system auto-rotate toggle is disabled.
    _setNativeOrientation('sensor');
    WakelockPlus.enable();
    _currentEpIdx = widget.episodeIndex;
    _currentFileId = widget.fileId;
    _currentTitle = widget.title;
    // Seed _currentSubFile so _applyCompanionSub() can load it once media opens.
    // Prefer the explicit subtitlePath prop from the route args; fall back to the
    // opening episode's subtitle_path field (set by Oracle/LocalDb for companion SRTs).
    _currentSubFile = widget.subtitlePath ??
        (_eps.isNotEmpty && _currentEpIdx < _eps.length
            ? _eps[_currentEpIdx]['subtitle_path']?.toString()
            : null);
    _initPlayer();
    // Init volume/brightness readings
    VolumeController().listener((v) {
      if (mounted) setState(() => _volume = v);
    });
    VolumeController().getVolume().then((v) {
      if (mounted) setState(() => _volume = v);
    });
    ScreenBrightness().current.then((v) {
      if (mounted) setState(() => _brightness = v);
    });
    _loadPrefs();
    _clockStr = _fmtClock();
    _clockDisplayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _clockStr = _fmtClock());
    });

    // Media notification shade controls — receive button taps from Android
    const MethodChannel('com.raddflix.app/pip').setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onPipExited':
          if (mounted) setState(() {});
          break;
        case 'onNotificationAction':
          final action = call.arguments as String? ?? '';
          if (action == 'play_pause') {
            if (_player.state.playing) { _player.pause(); } else { _player.play(); }
            // Push updated state back to the notification after a short delay
            Future.delayed(const Duration(milliseconds: 150), _notifyBgState);
          } else if (action == 'seek_back') {
            final t = _position - const Duration(seconds: 10);
            _player.seek(t.isNegative ? Duration.zero : t);
          } else if (action == 'seek_forward') {
            _player.seek(_position + const Duration(seconds: 30));
          } else if (action.startsWith('seek_to:')) {
            final ms = int.tryParse(action.split(':').last) ?? -1;
            if (ms >= 0) _player.seek(Duration(milliseconds: ms));
          }
          break;
      }
    });
  }

  String _fmtClock() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  String _fmtSleepRemaining() {
    if (_sleepTimerEnd == null) return '';
    final mins = _sleepTimerEnd!.difference(DateTime.now()).inMinutes;
    return mins > 0 ? '${mins}m' : '<1m';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchPos();
      if (!_backgroundAudio) {
        _player.pause();
      } else {
        _isInBackground = true;
        // Start the foreground service so Android keeps the process alive.
        _notifyBgState();
        // Refresh the notification every 5 s so the progress bar stays in sync.
        _bgNotifTimer?.cancel();
        _bgNotifTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_isInBackground) _notifyBgState();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _bgNotifTimer?.cancel();
      _bgNotifTimer = null;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Dismiss the media notification now that the app is back in the foreground.
      const MethodChannel('com.raddflix.app/pip')
          .invokeMethod('stopBgPlayback').catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveWatchPos();
    _savePrefsDebounce?.cancel(); // C4: flush synchronously on dispose, do not debounce the final save
    _savePrefs();
    _hideTimer?.cancel();
    _posTimer?.cancel();
    _savePositionTimer?.cancel();
    _bgNotifTimer?.cancel();
    _bgNotifTimer = null;
    _isInBackground = false;
    _indicatorTimer?.cancel();
    _smartEnhanceTimer?.cancel();
    _sleepTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _clockDisplayTimer?.cancel();
    _autoRetryTimer?.cancel();
    for (final s in _subs) { s.cancel(); }
    VolumeController().removeListener();
    WakelockPlus.disable();
    // Reset orientation to unspecified so the app reverts to its default
    // after the player closes (home screen = portrait only, etc.).
    _setNativeOrientation('unspecified');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Dismiss media notification when player screen closes
    const MethodChannel('com.raddflix.app/pip')
        .invokeMethod('stopBgPlayback').catchError((_) {});
    const MethodChannel('com.raddflix.app/pip').setMethodCallHandler(null);
    _immersiveExitTimer?.cancel();
    _watchPartySub?.cancel();
    _voiceSub?.cancel();
    _voiceCmdTimer?.cancel();
    WatchPartyService.instance.leaveRoom();
    VoiceCommandsService.instance.stop();
    _stopUsageTimer();
    // Fix #1: unregister the log-message observer added in _initPlayer().
    // Without this, the C-level MPV callback fires into disposed Dart state.
    try { _np.unobserveProperty('log-message'); } catch (_) {}
    _player.dispose();
    super.dispose();
  }

  // ── Usage tracking helpers ───────────────────────────────────────────────────
  /// Starts a 30-second periodic timer that reports streamed bytes to UsageService.
  /// Only active when _trackUsage = true (non-local, non-free streaming).


  // ═══════════════════════════════════════════════════════════════════════════
  //  Player init
  // ═══════════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════════
  //  Stream resolution + open
  // ═══════════════════════════════════════════════════════════════════════════





  // ── Native A-B loop sync ──────────────────────────────────────────────
  // Pushes the current `_abA`/`_abB` Dart state into MPV's own ab-loop-a /
  // ab-loop-b / ab-loop-count properties. Once both points are set, MPV
  // enforces the loop natively inside the playback engine (sample-accurate,
  // zero Dart overhead) instead of Flutter polling `position` every tick and
  // calling `_player.seek()` — lighter, smoother, and immune to any Dart-side
  // jank near the loop boundary.

  // ── Prefetch next episode's stream link ahead of time ───────────────────
  // Mirrors the remote-link resolution steps in `_openMediaForEpisode` but
  // only resolves the URL — it never touches the player. Safe to call
  // repeatedly; guarded by `_prefetchInFlight` and a match check on the
  // target file id so it never resolves the same episode twice or races
  // itself. Local/offline episodes need no prefetch (opening them is
  // already instant), so this is a no-op for those.







  // ═══════════════════════════════════════════════════════════════════════════
  //  Controls helpers
  // ═══════════════════════════════════════════════════════════════════════════


  // Dynamically shift subtitles above the controls area so they are never
  // covered. Called whenever controls show or hide.
  // Controls bottom area is ~90px (seek bar ~32px + transport row ~48px + padding).
  /// Loads [subPath] into MPV immediately after _player.open().
  /// Callers MUST capture _currentSubFile into a local before the await open()
  /// call and pass it here — this prevents a race where rapid episode taps
  /// cause a later setState to overwrite _currentSubFile before an earlier
  /// open() completes, which would load the wrong SRT.

  void _applySubtitleMargin({required bool controlsVisible}) {
    // When controls are visible, push subs 140px above bottom controls so they
    // clear the seek bar AND transport row.
    // sub-ass-override 'yes' makes sub-margin-y apply to ASS-format subs too
    // (which is the default embedded format). Using 'yes' not 'force' so that
    // ASS colour/bold/italic styles are still respected.
    final base = _subBottomMarginMain;
    final marginY = controlsVisible ? (base + 140).round() : base.round();
    try {
      _np.setProperty('sub-ass-override', 'yes');
      _np.setProperty('sub-margin-y', marginY.toString());
    } catch (_) {}
  }

  // ── Immersive mode ────────────────────────────────────────────────────────
  void _enterImmersive() {
    setState(() {
      _isImmersive = true;
      _showControls = false;
      _immersiveExitVisible = false;
    });
    _applySubtitleMargin(controlsVisible: false);
  }

  void _exitImmersive() {
    _immersiveExitTimer?.cancel();
    setState(() {
      _isImmersive = false;
      _immersiveExitVisible = false;
      _showControls = true;
    });
    _applySubtitleMargin(controlsVisible: true);
    _scheduleHide();
  }

  /// Called when user taps video surface while in immersive mode.
  /// Single tap = pause/resume. Also briefly shows the exit button.
  void _onImmersiveTap() {
    // Toggle playback
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    // Show the exit corner button briefly
    _immersiveExitTimer?.cancel();
    setState(() => _immersiveExitVisible = true);
    _immersiveExitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _immersiveExitVisible = false);
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      // Show briefly when locked
      setState(() => _showControls = true);
      _applySubtitleMargin(controlsVisible: true);
      _scheduleHide();
      return;
    }
    setState(() => _showControls = !_showControls);
    _applySubtitleMargin(controlsVisible: _showControls);
    if (_showControls) _scheduleHide();
  }

  void _seekRelative(int seconds) {
    HapticFeedback.lightImpact();
    final target = _position + Duration(seconds: seconds);
    _player.seek(target.isNegative ? Duration.zero : target);
    setState(() {
      _showSeekFlash = true;
      _seekFlashLeft = seconds < 0;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showSeekFlash = false);
    });
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    _setSpeed(next);
  }


  void _startLongPress() {
    if (_longPressFast) return;
    _longPressFast = true;
    // Smooth 2× — no seek, let MPV run at speed natively
    _np.setProperty('framedrop', 'decoder+vo');
    _np.setProperty('hr-seek', 'no');
    _np.setProperty('speed', '2.0');
    if (mounted) setState(() {});
  }

  void _endLongPress() {
    if (!_longPressFast) return;
    _longPressFast = false;
    _np.setProperty('speed', _speed.toStringAsFixed(4));
    _np.setProperty('framedrop', _speed > 1.0 ? 'decoder+vo' : 'vo');
    _np.setProperty('hr-seek', 'yes');
    if (mounted) setState(() {});
  }

  // ─── Feature 26: Resume position ────────────────────────────────────────




  // ═══════════════════════════════════════════════════════════════════════════
  //  P13: Load / Save prefs
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _speed       = prefs.getDouble('pref_speed') ?? 1.0;
      _zoomMode    = prefs.getInt('pref_zoom') ?? 0;
      _skipInterval = prefs.getInt('pref_skip') ?? 10;
      _nightModeEnabled = prefs.getBool('pref_night') ?? false;
      _nightWarmth = prefs.getDouble('pref_warmth') ?? 0.4;
      _smartEnhanceEnabled = prefs.getBool('pref_vivid') ?? false; // J1: was never persisted
      _showClockInTitle = prefs.getBool('pref_clock') ?? true;
      _videoRotation = prefs.getInt('pref_vrotate') ?? 0;
      _audioBalance = prefs.getDouble('pref_balance') ?? 0.0;
      _seekSwipeSec = prefs.getDouble('pref_swipe') ?? 120.0;
      _accentColorIdx = prefs.getInt('pref_accent') ?? 0;
      _progressBarStyle = prefs.getInt('pref_pbstyle') ?? 0;
      _oneHandedMode    = prefs.getBool('pref_onehanded') ?? false;
      _showSkipBtns     = prefs.getBool('pref_skip_btns') ?? true;     // J1: was never persisted
      _showPrevNextBtns = prefs.getBool('pref_prev_next_btns') ?? true; // J1: was never persisted
      _backgroundAudio  = prefs.getBool('pref_bgaudio') ?? false;
      _keepScreenOn = prefs.getBool('pref_screenon') ?? true;
      _showRemainingTime = prefs.getBool('pref_remaining') ?? false;
      _showSeekPositionLabel = prefs.getBool('pref_seek_pos_label') ?? true; // J2: was never persisted
      // EQ + Lab + Reverb + Channel
      for (int i = 0; i < _eqBands.length; i++) {
        _eqBands[i] = prefs.getDouble('pref_eq_${i}') ?? 0.0;
      }
      _eqEnabled = prefs.getBool('pref_eq_on') ?? true;
      _reverbPreset = prefs.getString('pref_reverb') ?? 'None';
      _subBottomMarginMain = prefs.getDouble('pref_sub_margin') ?? 100.0;
      _labVocal = prefs.getBool('pref_lab_vocal') ?? false;
      _labDialogue = prefs.getBool('pref_lab_dialogue') ?? false;
      _labNorm = prefs.getBool('pref_lab_norm') ?? false;
      _labBass = prefs.getBool('pref_lab_bass') ?? false;
      _labBassLevel = prefs.getDouble('pref_lab_bass_level') ?? 0.5;
      _labDialogueOnly = prefs.getBool('pref_lab_dialogue_only') ?? false;
      _labCompress = prefs.getBool('pref_lab_compress') ?? false;
      _labStereoWide = prefs.getBool('pref_lab_stereo_wide') ?? false;
      _labNoise = prefs.getBool('pref_lab_noise') ?? false;
      _channelModeIdx = prefs.getInt('pref_ch_mode') ?? 0;
      _useSWDecoder   = prefs.getBool('pref_sw_dec') ?? false;
      _subSpeed       = prefs.getDouble('pref_sub_speed') ?? 1.0;
      _subSync        = prefs.getDouble('pref_sub_sync') ?? 0.0;
      _prefSubLang    = prefs.getString('pref_sub_lang');
      _prefAudioLang  = prefs.getString('pref_audio_lang');
      // Sprint 2 keys
      _endAction           = prefs.getString('pref_end_action') ?? 'play_next';
      _silenceSkipEnabled  = prefs.getBool('pref_silence_skip') ?? false;
      _silenceSkipThreshold= prefs.getDouble('pref_silence_thr') ?? 1.5;
      _silenceInPipeline   = _silenceSkipEnabled; // J1: restore pipeline flag — was left false after restart
      _layoutPreset        = prefs.getString('pref_layout') ?? 'default';
      _voiceCommandsEnabled= prefs.getBool('pref_voice_cmd') ?? false;
      _doubleTapSeekEnabled= prefs.getBool('pref_gest_dtap') ?? true;
      _longPressSpeedEnabled=prefs.getBool('pref_gest_lp') ?? true;
      _swipeSeekEnabled    = prefs.getBool('pref_gest_seek') ?? true;
      _swipeBVEnabled      = prefs.getBool('pref_gest_bv') ?? true;
      _skipEditorEnabled   = prefs.getBool('pref_skip_ed_on') ?? false;
      _cropAspectIdx       = prefs.getInt('pref_crop_aspect') ?? 0;
      _oneHandedLeft       = prefs.getBool('pref_onehanded_left') ?? false;
      // Sidebar
      _sidebarExpanded = prefs.getBool('pref_sidebar_exp') ?? true;
      final sbJson = prefs.getString('pref_sidebar_order');
      if (sbJson != null) {
        try {
          _sidebarOrder = (jsonDecode(sbJson) as List).cast<String>();
          // Ensure at least one valid item exists
          if (_sidebarOrder.isEmpty) _sidebarOrder = ['cc','audio','eq','vivid','episodes','speed','loop','pip'];
        } catch (_) {}
      }
      // Rebuild reverb AF string from loaded preset
      switch (_reverbPreset) {
        case 'Small Room': _currentReverbAf = 'aecho=0.8:0.9:30:0.4'; break;
        case 'Hall':       _currentReverbAf = 'aecho=0.8:0.88:60:0.4'; break;
        case 'Cathedral':  _currentReverbAf = 'aecho=0.8:0.88:120:0.5'; break;
        case 'Stadium':    _currentReverbAf = 'aecho=0.8:0.9:180:0.6'; break;
        default:           _currentReverbAf = '';
      }
      // Rebuild lab AF string from loaded lab state
      final labParts = <String>[];
      // A4 fix: use 0.5 scale to prevent 2× amplitude clipping (matches _applyLabAf)
      if (_labVocal)        labParts.add('pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0');
      if (_labDialogue)     labParts.add('equalizer=0:0:0:0:0:0:3:4:2:0');
      if (_labNorm)         labParts.add('dynaudnorm');
      if (_labBass) {
        final db = (_labBassLevel * 12).round().clamp(1, 12);
        labParts.add('equalizer=$db:$db:0:0:0:0:0:0:0:0');
      }
      if (_labDialogueOnly) labParts.add('pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1');
      if (_labCompress)     labParts.add('acompressor=threshold=0.089:ratio=9:attack=200:release=1000');
      if (_labStereoWide)   labParts.add('extrastereo=m=2.5');
      if (_labNoise)        labParts.add('afftdn=nf=-25');
      _currentLabAf = labParts.isEmpty ? '' : labParts.join(',');
      // Rebuild channel mode AF from loaded index
      const chFilters = ['', 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1', 'pan=stereo|c0=c0|c1=c0', 'pan=stereo|c0=c1|c1=c1'];
      _currentChannelModeAf = chFilters[_channelModeIdx.clamp(0, 3)];
    });
    // Restore speed via MPV
    // Deferred AF restore — applied once player is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _applyAllAf();
    });
    if (_speed != 1.0) {
      try {
        _np.setProperty('framedrop', _speed > 1.0 ? 'decoder+vo' : 'vo');
        _np.setProperty('speed', _speed.toStringAsFixed(4));
      } catch (_) {}
    }
    // L6: re-apply subSpeed + videoRotation to MPV — Dart state was restored
    // from prefs but MPV was never told, so video started at wrong rotation/speed
    // until user manually toggled the control again.
    if (_subSpeed != 1.0) {
      try { _np.setProperty('sub-speed', _subSpeed.toStringAsFixed(4)); } catch (_) {}
    }
    if (_subSync != 0.0) {
      try { _np.setProperty('sub-delay', _subSync.toStringAsFixed(1)); } catch (_) {}
    }
    if (_videoRotation != 0) {
      try { _np.setProperty('video-rotate', _videoRotation.toString()); } catch (_) {}
    }
  }

  // C2: _savePrefs() used to be called synchronously from ~60 call sites,
  // including inside setState() closures — SharedPreferences I/O on the main
  // thread is a known cause of dropped frames. Call sites now debounce
  // through this wrapper instead of writing on every keystroke/toggle.
  void _scheduleSavePrefs() {
    _savePrefsDebounce?.cancel();
    _savePrefsDebounce = Timer(const Duration(milliseconds: 300), _savePrefs);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pref_speed', _speed);
    await prefs.setInt('pref_zoom', _zoomMode);
    await prefs.setInt('pref_skip', _skipInterval);
    await prefs.setDouble('pref_swipe', _seekSwipeSec);
    await prefs.setInt('pref_accent', _accentColorIdx);
    await prefs.setInt('pref_pbstyle', _progressBarStyle);
    await prefs.setBool('pref_onehanded', _oneHandedMode);
    await prefs.setBool('pref_bgaudio', _backgroundAudio);
    await prefs.setBool('pref_screenon', _keepScreenOn);
    await prefs.setBool('pref_remaining', _showRemainingTime);
    await prefs.setBool('pref_night', _nightModeEnabled);
    await prefs.setDouble('pref_warmth', _nightWarmth);
    await prefs.setBool('pref_vivid', _smartEnhanceEnabled);              // J1
    await prefs.setBool('pref_skip_btns', _showSkipBtns);                 // J1
    await prefs.setBool('pref_prev_next_btns', _showPrevNextBtns);        // J1
    await prefs.setBool('pref_seek_pos_label', _showSeekPositionLabel);   // J2
    await prefs.setBool('pref_clock', _showClockInTitle);
    await prefs.setInt('pref_vrotate', _videoRotation);
    await prefs.setDouble('pref_balance', _audioBalance);
    await prefs.setDouble('pref_sub_margin', _subBottomMarginMain);
    // EQ + Lab + Reverb + Channel
    for (int i = 0; i < _eqBands.length; i++) {
      await prefs.setDouble('pref_eq_${i}', _eqBands[i]);
    }
    await prefs.setBool('pref_eq_on', _eqEnabled);
    await prefs.setString('pref_reverb', _reverbPreset);
    await prefs.setBool('pref_lab_vocal', _labVocal);
    await prefs.setBool('pref_lab_dialogue', _labDialogue);
    await prefs.setBool('pref_lab_norm', _labNorm);
    await prefs.setBool('pref_lab_bass', _labBass);
    await prefs.setDouble('pref_lab_bass_level', _labBassLevel);
    await prefs.setBool('pref_lab_dialogue_only', _labDialogueOnly);
    await prefs.setBool('pref_lab_compress', _labCompress);
    await prefs.setBool('pref_lab_stereo_wide', _labStereoWide);
    await prefs.setBool('pref_lab_noise', _labNoise);
    await prefs.setInt('pref_ch_mode', _channelModeIdx);
    await prefs.setBool('pref_sw_dec', _useSWDecoder);
    await prefs.setDouble('pref_sub_speed', _subSpeed);
    await prefs.setDouble('pref_sub_sync', _subSync);
    if (_prefSubLang != null)   await prefs.setString('pref_sub_lang',   _prefSubLang!);
    if (_prefAudioLang != null) await prefs.setString('pref_audio_lang', _prefAudioLang!);
    // Sprint 2 keys
    await prefs.setString('pref_end_action', _endAction);
    await prefs.setBool('pref_silence_skip', _silenceSkipEnabled);
    await prefs.setDouble('pref_silence_thr', _silenceSkipThreshold);
    await prefs.setString('pref_layout', _layoutPreset);
    await prefs.setBool('pref_voice_cmd', _voiceCommandsEnabled);
    await prefs.setBool('pref_gest_dtap', _doubleTapSeekEnabled);
    await prefs.setBool('pref_gest_lp', _longPressSpeedEnabled);
    await prefs.setBool('pref_gest_seek', _swipeSeekEnabled);
    await prefs.setBool('pref_gest_bv', _swipeBVEnabled);
    await prefs.setBool('pref_skip_ed_on', _skipEditorEnabled);
    await prefs.setInt('pref_crop_aspect', _cropAspectIdx);
    await prefs.setBool('pref_onehanded_left', _oneHandedLeft);
    await prefs.setBool('pref_sidebar_exp', _sidebarExpanded);
    await prefs.setString('pref_sidebar_order', jsonEncode(_sidebarOrder));
    // Skip editor timestamps (per content ID)
    final id = _currentFileId.length > 80 ? _currentFileId.hashCode.toString() : _currentFileId;
    if (_introStart != null) await prefs.setInt('pref_intro_s_$id', _introStart!.inSeconds);
    if (_introEnd != null)   await prefs.setInt('pref_intro_e_$id', _introEnd!.inSeconds);
    if (_outroStart != null) await prefs.setInt('pref_outro_s_$id', _outroStart!.inSeconds);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  P3: Auto-retry
  // ═══════════════════════════════════════════════════════════════════════════





  // ── Orientation control ─────────────────────────────────────────────────────

  // Calls the native Android channel to set requestedOrientation.
  // This works even when the user has system auto-rotate OFF —
  // unlike SystemChrome.setPreferredOrientations which respects that setting.
  void _setNativeOrientation(String mode) {
    const MethodChannel('com.raddflix.app/orient')
        .invokeMethod('setOrientation', {'mode': mode})
        .catchError((_) {});
  }


  void _cycleOrientation() {
    final next = (_orientMode + 1) % 4;
    setState(() => _orientMode = next);
    switch (next) {
      case 0: // Auto — physical sensor controls rotation (ignores system toggle)
        _setNativeOrientation('sensor');
        break;
      case 1: // Lock landscape (both sides, sensor-based)
        _setNativeOrientation('sensor_landscape');
        break;
      case 2: // Lock portrait (both sides, sensor-based)
        _setNativeOrientation('sensor_portrait');
        break;
      case 3: // Lock landscape right only
        _setNativeOrientation('landscape_right');
        break;
    }
  }

  IconData get _orientIcon {
    switch (_orientMode) {
      case 1: return Icons.stay_current_landscape_rounded;
      case 2: return Icons.stay_current_portrait_rounded;
      case 3: return Icons.screen_lock_rotation_rounded;
      default: return Icons.screen_rotation_rounded;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Smart Enhance
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleSmartEnhance() {
    setState(() => _smartEnhanceEnabled = !_smartEnhanceEnabled);
    _showInfoSnackbar(_smartEnhanceEnabled ? 'Vivid Mode on' : 'Vivid Mode off');
    _scheduleSavePrefs(); // J2: was missing — change was only saved on dispose()
  }




  // ── Merged audio-filter pipeline ─────────────────────────────────────────────
  // NEVER call _np.setProperty('af',...) directly — always go through _applyAllAf()
  // so EQ + Reverb + Lab stack correctly instead of overwriting each other.


  void _rotateVideo() {
    setState(() => _videoRotation = (_videoRotation + 90) % 360);
    try { _np.setProperty('video-rotate', _videoRotation.toString()); } catch (_) {}
    _scheduleSavePrefs();
  }

  void _showVideoInfoDialog() {
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    final res = w > 0 ? '${w}x${h}' : 'Unknown';
    final quality = h >= 2160 ? '4K' : h >= 1080 ? 'Full HD' : h >= 720 ? 'HD' : h > 0 ? 'SD' : '-';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Video Info', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: DefaultTextStyle(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Resolution', '$res ($quality)'),
              _infoRow('Duration', _formatDuration(_duration)),
              _infoRow('Position', _formatDuration(_position)),
              _infoRow('Speed', '${_speed}x'),
              if (_videoRotation != 0) _infoRow('Rotation', '${_videoRotation}deg'),
              if (_pinchScale != 1.0) _infoRow('Pinch Scale', '${_pinchScale.toStringAsFixed(1)}x'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.white54))),
      Flexible(child: Text(value, style: const TextStyle(color: Colors.white))),
    ]),
  );

  // A1: Log the filter string so a developer running `flutter logs` can confirm
  // what is actually reaching MPV — the previous bare catch hid all errors.

  // Push current playback state to the Android media notification service.
  // Called when going to background, when play/pause changes via notification,
  // and periodically from the bg-play timer.

  // ═══════════════════════════════════════════════════════════════════════════
  //  Sleep timer
  // ═══════════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════════
  //  Video Zoom
  // ═══════════════════════════════════════════════════════════════════════════

  BoxFit _getBoxFit() {
    switch (_zoomMode) {
      case 0: return BoxFit.contain;   // Fit to screen
      case 1: return BoxFit.fill;      // Stretch
      case 2: return BoxFit.cover;     // Crop
      case 3: return BoxFit.none;      // 100%
      case 4: return BoxFit.contain;   // Pinch & Zoom (pinch gesture sets scale)
      default: return BoxFit.contain;
    }
  }

  // Seek bar style mapper: 0-2 → _HorizontalSeekPainter, 3+ → SeekBarPainter
  SeekBarStyle _seekBarStyleFromIdx(int idx) {
    switch (idx - 3) {
      case 0: return SeekBarStyle.gradientGlow;
      case 1: return SeekBarStyle.materialBold;
      case 2: return SeekBarStyle.waveform;
      case 3: return SeekBarStyle.neonRgb;
      case 4: return SeekBarStyle.filmstrip;
      case 5: return SeekBarStyle.chapters;
      case 6: return SeekBarStyle.dots;
      case 7: return SeekBarStyle.minimal;
      default: return SeekBarStyle.classic;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Subtitle helpers
  // ═══════════════════════════════════════════════════════════════════════════

  void _adjustSubSync(double delta) {
    _subSync = (_subSync + delta);
    try { _np.setProperty('sub-delay', _subSync.toStringAsFixed(1)); } catch (_) {}
    setState(() {});
    _scheduleSavePrefs(); // was previously never persisted — reset to 0 on next open
  }


  // ═══════════════════════════════════════════════════════════════════════════
  //  Phase 59 — AI Dub (Method 1: Android TTS + MPV karaoke filter)
  // ═══════════════════════════════════════════════════════════════════════════





  // ═══════════════════════════════════════════════════════════════════════════
  //  Gesture handlers
  // ═══════════════════════════════════════════════════════════════════════════

  void _onDragStart(DragStartDetails d, BoxConstraints constraints) {
    HapticFeedback.lightImpact();
    _dragStart = d.localPosition;
    _dragStartPos = _position;
    _startBrightness = _brightness;
    _startVolume = _volume;
    _seekBarDelta = null;
    _dragIntent = null;
  }

  void _onDragUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    final dx = d.localPosition.dx - _dragStart.dx;
    final dy = d.localPosition.dy - _dragStart.dy;
    final isLeftSide = _dragStart.dx < constraints.maxWidth / 2;

    if (_dragIntent == null) {
      if (dx.abs() > dy.abs() && dx.abs() > 12 && _swipeSeekEnabled) {
        _dragIntent = 'seek';
      } else if (dy.abs() > 12 && _swipeBVEnabled) {
        _dragIntent = isLeftSide ? 'brightness' : 'volume';
      }
    }

    if (_dragIntent == 'seek') {
      // Horizontal seek: 120s across full width
      final delta = dx / constraints.maxWidth;
      final seekSec = delta * _seekSwipeSec;
      final targetMs = (_dragStartPos.inMilliseconds + seekSec * 1000)
          .clamp(0, _duration.inMilliseconds.toDouble());
      _seekBarDelta = targetMs / (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1);
      // P9: Update seek preview label
      final previewPos = Duration(milliseconds: targetMs.round());
      final diff = previewPos - _dragStartPos;
      final sign = diff.isNegative ? '-' : '+';
      _seekPreviewLabel = '${_formatDuration(previewPos)}  ($sign${_formatDuration(diff.abs())})';
      if (mounted) setState(() {});
    } else if (_dragIntent == 'brightness') {
      final newVal = (_startBrightness - dy / constraints.maxHeight * 1.5).clamp(0.0, 1.0);
      _brightness = newVal;
      ScreenBrightness().setScreenBrightness(newVal);
      _showBrightnessIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    } else if (_dragIntent == 'volume') {
      // Volume 0–100% = OS volume, 100–250% = MPV audio boost
      final newVal = (_startVolume - dy / constraints.maxHeight * 3.0).clamp(0.0, 2.5);
      _volume = newVal;
      // OS volume only goes 0-1.0 (100%)
      VolumeController().setVolume(newVal.clamp(0.0, 1.0));
      // MPV audio amp for boost above 100%
      if (newVal > 1.0) {
        _np.setProperty('volume', (newVal * 100).clamp(100, 250).round().toString());
      } else {
        _np.setProperty('volume', '100');
      }
      _showVolumeIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragIntent == 'seek' && _seekBarDelta != null) {
      final targetMs = (_seekBarDelta! * _duration.inMilliseconds).round();
      _player.seek(Duration(milliseconds: targetMs));
      _seekBarDelta = null;
    }
    if (_dragIntent == 'brightness' || _dragIntent == 'volume') {
      _indicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {
          _showBrightnessIndicator = false;
          _showVolumeIndicator = false;
        });
      });
    }
    _seekPreviewLabel = '';
    _dragIntent = null;
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Scale gesture (single-finger drag + pinch-to-zoom)
  // ═══════════════════════════════════════════════════════════════════════════

  void _onScaleStart(ScaleStartDetails d, BoxConstraints constraints) {
    if (d.pointerCount >= 2) {
      _pinchBaseScale = _pinchScale;
      _dragIntent = 'pinch';
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.lightImpact();
    _dragStart = d.localFocalPoint;
    _dragStartPos = _position;
    _startBrightness = _brightness;
    _startVolume = _volume;
    _seekBarDelta = null;
    _dragIntent = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, BoxConstraints constraints) {
    if (d.pointerCount >= 2 || _dragIntent == 'pinch') {
      _dragIntent = 'pinch';
      final newScale = (_pinchBaseScale * d.scale).clamp(0.5, 4.0);
      _indicatorTimer?.cancel();
      if (mounted) setState(() { _pinchScale = newScale; _showZoomIndicator = true; });
      // Apply zoom via MPV's native video-zoom (log2 scale: 0=1x, 1=2x, -1=0.5x).
      // This works correctly with SurfaceView; Flutter Transform.scale does not.
      try { _np.setProperty('video-zoom',
          (math.log(newScale) / math.log(2)).toStringAsFixed(4)); } catch (_) {}
      return;
    }
    // Single-finger drag — replicate _onDragUpdate
    final dx = d.localFocalPoint.dx - _dragStart.dx;
    final dy = d.localFocalPoint.dy - _dragStart.dy;
    final isLeftSide = _dragStart.dx < constraints.maxWidth / 2;
    if (_dragIntent == null) {
      if (dx.abs() > dy.abs() && dx.abs() > 12 && _swipeSeekEnabled) {
        _dragIntent = 'seek';
      } else if (dy.abs() > 12 && _swipeBVEnabled) {
        _dragIntent = isLeftSide ? 'brightness' : 'volume';
      }
    }
    if (_dragIntent == 'seek') {
      final delta = dx / constraints.maxWidth;
      final seekSec = delta * _seekSwipeSec;
      final targetMs = (_dragStartPos.inMilliseconds + seekSec * 1000)
          .clamp(0, _duration.inMilliseconds.toDouble());
      _seekBarDelta = targetMs / (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1);
      final previewPos = Duration(milliseconds: targetMs.round());
      final diff = previewPos - _dragStartPos;
      final sign = diff.isNegative ? '-' : '+';
      _seekPreviewLabel = '${_formatDuration(previewPos)}  ($sign${_formatDuration(diff.abs())})';
      if (mounted) setState(() {});
    } else if (_dragIntent == 'brightness') {
      final newVal = (_startBrightness - dy / constraints.maxHeight * 1.5).clamp(0.0, 1.0);
      _brightness = newVal;
      ScreenBrightness().setScreenBrightness(newVal);
      _showBrightnessIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    } else if (_dragIntent == 'volume') {
      final newVal = (_startVolume - dy / constraints.maxHeight * 3.0).clamp(0.0, 2.5);
      _volume = newVal;
      VolumeController().setVolume(newVal.clamp(0.0, 1.0));
      if (newVal > 1.0) {
        _np.setProperty('volume', (newVal * 100).clamp(100, 250).round().toString());
      } else {
        _np.setProperty('volume', '100');
      }
      _showVolumeIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragIntent == 'pinch') {
      // Snap back to 1.0 if within ±8% of natural size
      if (_pinchScale > 0.92 && _pinchScale < 1.08) {
        setState(() { _pinchScale = 1.0; _showZoomIndicator = false; });
        try { _np.setProperty('video-zoom', '0'); } catch (_) {}
      } else {
        _indicatorTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showZoomIndicator = false);
        });
      }
      _dragIntent = null;
      return;
    }
    if (_dragIntent == 'seek' && _seekBarDelta != null) {
      final targetMs = (_seekBarDelta! * _duration.inMilliseconds).round();
      _player.seek(Duration(milliseconds: targetMs));
      _seekBarDelta = null;
    }
    if (_dragIntent == 'brightness' || _dragIntent == 'volume') {
      _indicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {
          _showBrightnessIndicator = false;
          _showVolumeIndicator = false;
        });
      });
    }
    _seekPreviewLabel = '';
    _dragIntent = null;
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════════


    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final bool isPortrait = constraints.maxWidth < constraints.maxHeight;
            if (isPortrait) {
              return _buildPortraitLayout(constraints);
            }
            return Stack(
              children: [
                // 1. Video surface — full screen
                Positioned.fill(
                  child: RepaintBoundary(child: _buildVideoSurface()),
                ),

                // 2. Lock overlay
                if (_isLocked) _buildLockOverlay(),

                // P59: AI Dub generation progress overlay
                if (_dubGenerating) _buildDubProgressOverlay(),

                // Voice command feedback badge
                if (_voiceCommandsEnabled && _lastVoiceCmd.isNotEmpty)
                  Positioned(
                    top: 80, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.78),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mic_rounded, color: Colors.white70, size: 14),
                          const SizedBox(width: 6),
                          Text(_lastVoiceCmd.replaceAll('🎤 ', ''),
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),

                // Watch Party overlay (participant list + sync badge)
                if (_watchPartyRoom != null)
                  WatchPartyOverlay(
                    room: _watchPartyRoom!,
                    accentColor: _accentColor,
                    onLeave: () {
                      WatchPartyService.instance.leaveRoom();
                      setState(() => _watchPartyRoom = null);
                    },
                  ),

                // 3. Gesture layer
                // Immersive mode: tap = pause/resume, all swipe gestures still work,
                // but no controls, no indicators, no title — pure cinema experience.
                if (_isImmersive)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _onImmersiveTap,
                      onScaleStart: (d) => _onScaleStart(d, constraints),
                      onScaleUpdate: (d) => _onScaleUpdate(d, constraints),
                      onScaleEnd: _onScaleEnd,
                    ),
                  ),

                if (!_isLocked && !_isImmersive)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) {
                        if (!_doubleTapSeekEnabled) return;
                        final isLeft = d.localPosition.dx < constraints.maxWidth / 2;
                        _seekRelative(isLeft ? -_skipInterval : _skipInterval);
                      },
                      onLongPressStart: (_) { if (_longPressSpeedEnabled) _startLongPress(); },
                      onLongPressEnd: (_) { if (_longPressSpeedEnabled) _endLongPress(); },
                      onLongPressCancel: () { if (_longPressSpeedEnabled) _endLongPress(); },
                      onScaleStart: (d) => _onScaleStart(d, constraints),
                      onScaleUpdate: (d) => _onScaleUpdate(d, constraints),
                      onScaleEnd: _onScaleEnd,
                    ),
                  ),

                // 4. Controls overlay (auto-hides) — hidden in immersive mode
                if (!_isImmersive)
                  AnimatedOpacity(
                    opacity: _showControls && !_isLocked ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: IgnorePointer(
                      ignoring: !_showControls || _isLocked,
                      child: _buildControlsOverlay(constraints),
                    ),
                  ),

                // 5. Customizable shortcut sidebar — hidden in immersive and lock mode
                if (!_isLocked && !_isImmersive)
                  Positioned(
                    right: 0, top: 0, bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _panelOpen ? 0.0 : (_showControls ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 280),
                      child: IgnorePointer(
                        ignoring: _panelOpen || !_showControls,
                        child: _buildSidebar(constraints),
                      ),
                    ),
                  ),

                // 5b. Immersive exit button — tiny semi-transparent, top-right corner.
                // Appears for 3s after a tap, then auto-hides.
                if (_isImmersive)
                  Positioned(
                    top: 18, right: 18,
                    child: AnimatedOpacity(
                      opacity: _immersiveExitVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: !_immersiveExitVisible,
                        child: GestureDetector(
                          onTap: _exitImmersive,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.52),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.fullscreen_exit_rounded,
                                    color: Colors.white70, size: 16),
                                SizedBox(width: 5),
                                Text('Exit',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 6a. Brightness indicator — LEFT side (MX Player style vertical pill)
                // Hidden in immersive mode for a completely clean experience.
                if (_showBrightnessIndicator && !_isImmersive)
                  Positioned(
                    left: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _buildSideIndicator(
                        icon: _brightness < 0.3
                            ? Icons.brightness_low_rounded
                            : _brightness > 0.7
                                ? Icons.brightness_high_rounded
                                : Icons.brightness_medium_rounded,
                        barValue: _brightness,
                        barColor: const Color(0xFFFFD60A),
                        label: '${(_brightness * 100).round()}%',
                      ),
                    ),
                  ),

                // 6b. Volume indicator — LEFT side (sidebar on right; both indicators on left)
                if (_showVolumeIndicator && !_isImmersive)
                  Positioned(
                    left: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _buildSideIndicator(
                        icon: _isMuted
                            ? Icons.volume_off_rounded
                            : _volume > 1.0
                                ? Icons.volume_up_rounded
                                : _volume > 0.4
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_mute_rounded,
                        barValue: _volume.clamp(0.0, 1.0),
                        barColor: _volume > 2.0
                            ? const Color(0xFFFF3B30)
                            : _volume > 1.0
                                ? const Color(0xFFFF6B35)
                                : Colors.white,
                        label: '${(_volume * 100).round()}%',
                      ),
                    ),
                  ),

                // 7. Long-press 2× badge
                if (_longPressFast)
                  Positioned(
                    top: 52, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('2× Speed',
                                style: TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 8a. Pinch-to-zoom indicator pill
                if (_showZoomIndicator && _pinchScale != 1.0)
                  IgnorePointer(
                    child: Positioned(
                      top: 0, bottom: 0, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.72),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: RaddSpace.sm),
                              Text(
                                '${_pinchScale.toStringAsFixed(1)}×',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 8b. Reset zoom button (shown when pinch scale != 1.0)
                if (_pinchScale != 1.0)
                  Positioned(
                    top: 14,
                    right: 60,
                    child: GestureDetector(
                      onTap: () {
                        setState(() { _pinchScale = 1.0; _showZoomIndicator = false; });
                        try { _np.setProperty('video-zoom', '0'); } catch (_) {}
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.72),
                          borderRadius: RaddRadius.mdRadius,
                          border: Border.all(color: AppColors.orange.withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_out_rounded, color: AppColors.orange, size: 14),
                            SizedBox(width: RaddSpace.xs),
                            Text('Reset zoom', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 8. Double-tap seek flash — Phase 51: MX-style triple-chevron
                // ripple burst + "+Ns"/"-Ns" text, fades out over 600ms total.
                if (_showSeekFlash)
                  Positioned(
                    left: _seekFlashLeft ? 0 : null,
                    right: _seekFlashLeft ? null : 0,
                    top: 0, bottom: 0,
                    width: constraints.maxWidth / 2,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(3, (i) {
                                  final sizes = [22.0, 28.0, 28.0];
                                  final colors = [Colors.white54, Colors.white, Colors.white];
                                  return Icon(
                                    _seekFlashLeft ? Icons.chevron_left : Icons.chevron_right,
                                    color: colors[i], size: sizes[i],
                                  )
                                      .animate(delay: (i * 90).ms)
                                      .fadeIn(duration: 150.ms, curve: Curves.easeOut)
                                      .scaleXY(begin: 0.4, end: 1.0, duration: 220.ms, curve: Curves.easeOutBack)
                                      .then(delay: (150 - i * 40).ms)
                                      .fadeOut(duration: 180.ms);
                                }),
                              ),
                              const SizedBox(height: RaddSpace.xs),
                              Text(
                                _seekFlashLeft ? '−$_skipInterval s' : '+$_skipInterval s',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                              )
                                  .animate()
                                  .fadeIn(duration: 150.ms, delay: 60.ms)
                                  .slideY(begin: 0.3, end: 0, duration: 200.ms, curve: Curves.easeOut)
                                  .then(delay: 180.ms)
                                  .fadeOut(duration: 200.ms),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 100.ms)
                      .scaleXY(begin: 0.85, end: 1.0, duration: 180.ms, curve: Curves.easeOutBack)
                      .then(delay: 260.ms)
                      .fadeOut(duration: 160.ms),

                // 9. Buffering spinner
                if (_buffering && !_isLinkLoading && _streamError == null)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)),

                // 11. Link loading
                if (_isLinkLoading)
                  Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: RaddSpace.md),
                          Text('Loading stream…',
                              style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),

                // 12. Error overlay — P3 upgrade (smart categories + auto-retry)
                if (_streamError != null)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Smart icon by error type
                            Icon(
                              _streamError!.contains('Jazz') || _streamError!.contains('SIM')
                                  ? Icons.sim_card_alert_rounded
                                  : _streamError!.contains('timed out') || _streamError!.contains('timeout')
                                      ? Icons.timer_off_rounded
                                      : Icons.error_outline_rounded,
                              color: _streamError!.contains('Jazz') || _streamError!.contains('SIM')
                                  ? Colors.orangeAccent
                                  : Colors.redAccent,
                              size: 56,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _streamError!.contains('Jazz') || _streamError!.contains('SIM')
                                  ? 'Jazz SIM Required'
                                  : _streamError!.contains('timed out') || _streamError!.contains('timeout')
                                      ? 'Connection Timed Out'
                                      : 'Stream Error',
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: RaddSpace.sm),
                            Text(_streamError!,
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                                textAlign: TextAlign.center),
                            // Jazz SIM specific help steps
                            if (_streamError!.contains('Jazz') || _streamError!.contains('SIM')) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.orange.withOpacity(0.3)),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('• Disconnect WiFi, use Jazz mobile data',
                                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    SizedBox(height: RaddSpace.xs),
                                    Text('• Ensure Jazz SIM is active in slot 1',
                                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    SizedBox(height: RaddSpace.xs),
                                    Text('• Toggle airplane mode off/on, then retry',
                                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            // Auto-retry countdown
                            if (_autoRetryCountdown > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Auto-retry in ${_autoRetryCountdown}s…',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5), fontSize: 12),
                                ),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry Now'),
                                  onPressed: () {
                                    _cancelAutoRetry();
                                    setState(() => _streamError = null);
                                    _openMedia(_currentFileId);
                                  },
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Go Back',
                                      style: TextStyle(color: Colors.white70)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 13. Auto-advance banner
                if (_ended && _hasNext)
                  Positioned(
                    bottom: 90, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.88),
                          borderRadius: RaddRadius.mdRadius,
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Up next in ${_autoAdvanceCountdown}s…',
                                style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(width: 14),
                            GestureDetector(
                              onTap: () {
                                _autoAdvanceTimer?.cancel();
                                setState(() => _ended = false);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: RaddRadius.smRadius,
                                ),
                                child: const Text('Cancel',
                                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: RaddSpace.sm),
                            GestureDetector(
                              onTap: () => _playEpisodeAt(_currentEpIdx + 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: RaddRadius.smRadius,
                                ),
                                child: const Text('Play Now',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Video Surface — fills Positioned.fill exactly
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildVideoSurface() {
      Widget video = SizedBox.expand(
        child: Video(
          controller: _videoCtrl,
          controls: NoVideoControls,
          fit: _getBoxFit(),
        ),
      );

      if (_smartEnhanceEnabled) {
        video = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.15,  0.0,   0.0,   0.0,  8.0,
            0.0,   1.08,  0.0,   0.0,  4.0,
            0.0,   0.0,   0.92,  0.0, -3.0,
            0.0,   0.0,   0.0,   1.0,  0.0,
          ]),
          child: video,
        );
      }
      // Night mode eye-comfort warm filter
      if (_nightModeEnabled) {
        final w = _nightWarmth.clamp(0.0, 1.0);
        video = ColorFiltered(
          colorFilter: ColorFilter.matrix([
            1.0 + w * 0.25, 0.0, 0.0, 0.0,  w * 12.0,
            0.0, 1.0 - w * 0.05, 0.0, 0.0,  0.0,
            0.0, 0.0, 1.0 - w * 0.55, 0.0, -w * 25.0,
            0.0, 0.0, 0.0, 1.0, 0.0,
          ]),
          child: video,
        );
      }
      // Pinch-to-zoom: zoom is applied via MPV's native video-zoom property
      // (set in _onScaleUpdate / _onScaleEnd). Do NOT use Transform.scale here —
      // media_kit renders to an Android SurfaceView which Flutter's Transform
      // cannot scale; it would produce a gray/blank area instead of a zoomed image.
      return video;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Lock overlay
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildLockOverlay() {
      return Positioned.fill(
        child: GestureDetector(
          onTap: () {
            setState(() => _showControls = true);
            _applySubtitleMargin(controlsVisible: true);
            _scheduleHide();
          },
          child: Container(
            color: Colors.transparent,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isLocked = false;
                        _showControls = true;
                        _applySubtitleMargin(controlsVisible: true);
                        _scheduleHide();
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.lock_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Controls overlay — modern clean layout
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildControlsOverlay(BoxConstraints constraints) {
      final currentPos = _seekBarDelta != null
          ? Duration(milliseconds: (_seekBarDelta! * _duration.inMilliseconds).round())
          : _position;

      return Stack(
        children: [
          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0, height: 80,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xBB000000), Colors.transparent],
                ),
              ),
            ),
          ),

          // Bottom gradient
          Positioned(
            bottom: 0, left: 0, right: 0, height: 100,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xBB000000), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── TOP BAR ── hidden in one-handed mode (side strip used instead) ──
          if (!_oneHandedMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: _buildTopBar(),
              ),
            ),

          // ── CENTER PLAYBACK CONTROLS ── P7: shift down in one-handed mode ───────
          if (_oneHandedMode)
            Positioned(
              bottom: 75,
              left: _oneHandedLeft ? 0 : null,
              right: _oneHandedLeft ? null : 0,
              width: MediaQuery.of(context).size.width * 0.88,
              child: _buildCenterControls(),
            )
          else
            Positioned.fill(
              child: Center(
                child: _buildCenterControls(),
              ),
            ),

          // ── ONE-HANDED SIDE STRIP (top bar replacement) ──────────────────────
          if (_oneHandedMode && _showControls)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.22,
              right: _oneHandedLeft ? null : 12,
              left: _oneHandedLeft ? 12 : null,
              child: _buildOneHandedSideStrip(),
            ),

          // P9: Seek preview label during drag
          if (_dragIntent == 'seek' && _seekPreviewLabel.isNotEmpty && _showSeekPositionLabel)
            Positioned(
              bottom: 88, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    _seekPreviewLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),

          // ── BOTTOM AREA: seek bar + icon row ──────────────────────────────────
          Positioned(
            bottom: 0,
            left: _oneHandedMode && !_oneHandedLeft ? null : 0,
            right: _oneHandedMode && _oneHandedLeft ? null : 0,
            width: _oneHandedMode
                ? MediaQuery.of(context).size.width * 0.90
                : null,
            child: SafeArea(
              top: false,
              child: _buildBottomArea(constraints, currentPos),
            ),
          ),
        ],
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Top Bar
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildOneHandedSideStrip() {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.68),
          borderRadius: RaddRadius.lgRadius,
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RaddIconBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 20,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 6),
            _RaddIconBtn(
              icon: _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 20,
              onTap: () => setState(() {
                _isLocked = !_isLocked;
                _showControls = true;
                _applySubtitleMargin(controlsVisible: true);
              }),
            ),
            const SizedBox(height: 6),
            _RaddIconBtn(
              icon: Icons.screen_rotation_rounded,
              size: 20,
              onTap: _cycleOrientation,
            ),
            const SizedBox(height: 6),
            _RaddIconBtn(
              icon: Icons.picture_in_picture_rounded,
              size: 20,
              onTap: _enterPiP,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () { setState(() => _oneHandedLeft = !_oneHandedLeft); _scheduleSavePrefs(); },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: RaddRadius.smRadius,
                ),
                child: Text(
                  _oneHandedLeft ? '✋' : '🤚',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _buildTopBar() {
      // P1: badge helpers
      final hasAudio = _realAudioTracks.length > 1;
      final hasSubs  = _realSubtitleTracks.isNotEmpty;
      final isEpSeries = _eps.length > 1;
      final zoomLabels = ['Fit', 'Fill', 'Crop', '1:1', 'Cust'];

      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            // Back/minimize button
            _RaddIconBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 20,
              onTap: () => Navigator.of(context).pop(),
            ),

            const SizedBox(width: RaddSpace.xs),

            // Title + episode counter badge
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _currentTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // P1: Episode counter badge
                  if (isEpSeries) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'E${_currentEpIdx + 1}/${_eps.length}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: RaddSpace.xs),

            // P2: Zoom badge
            if (_zoomMode != 0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _accentColor.withOpacity(0.5), width: 0.8),
                  ),
                  child: Text(
                    zoomLabels[_zoomMode],
                    style: TextStyle(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // P2: Sub sync badge
            if (_subSync.abs() > 0.05)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'S${_subSync >= 0 ? '+' : ''}${_subSync.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ),

            // P2: Audio sync badge
            if (_audioSync.abs() > 0.05)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'A${_audioSync >= 0 ? '+' : ''}${_audioSync.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ),

            // Replay from start
            _RaddIconBtn(
              icon: Icons.replay_rounded,
              size: 20,
              onTap: () => _player.seek(Duration.zero),
            ),

            // Clock overlay
            if (_showClockInTitle) ...[
              Text(
                _clockStr,
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
            ],

            // Sleep timer badge
            if (_sleepTimerEnd != null)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A8EF5).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF3A8EF5).withOpacity(0.45), width: 0.8),
                ),
                child: Text(
                  '💤 ${_fmtSleepRemaining()}',
                  style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),

            // Video rotation badge
            if (_videoRotation != 0)
              GestureDetector(
                onTap: _rotateVideo,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.orange.withOpacity(0.6), width: 0.8),
                  ),
                  child: Text('${_videoRotation}deg',
                      style: const TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),


          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Center playback controls (skip + play/pause)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildCenterControls() {
      // Cinematic mode — no buttons in the center of the video.
      // All playback controls live under the seek bar only.
      return const SizedBox.shrink();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Bottom area: seek bar + icon row
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildBottomArea(BoxConstraints constraints, Duration currentPos) {
      // J1: compact layout actually reduces chrome density
      final isCompact = _layoutPreset == 'compact';
      return Padding(
        padding: EdgeInsets.fromLTRB(isCompact ? 8 : 16, 0, isCompact ? 8 : 16, isCompact ? 6 : 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Seek bar row ────────────────────────────────────────────────────
            _buildHorizontalSeekBar(constraints, currentPos),

            SizedBox(height: isCompact ? 0 : 2),

            // ── Transport controls: prev · skip· play/pause · skip · next ────────
            _buildTransportRow(),

          ],
        ),
      );
    }

    Widget _buildTransportRow() {
      // ── Stack layout: play/pause always pixel-centered. Nav buttons (prev/next/
      // skip) and utility buttons (lock/immersive/settings) share a single Row that
      // overlays the Stack. No fixed-width SizedBox = no RenderFlex overflow when
      // all optional buttons are active simultaneously.
      return SizedBox(
        height: _layoutPreset == 'compact' ? 48 : 52, // J1: compact uses 48 (Material min) vs default 52
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Nav + utility row (spans full width) ───────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left nav: replay + prev episode
                if (_showSkipBtns)
                  _RaddIconBtn(
                    icon: Icons.replay_rounded,
                    size: 22,
                    onTap: () => _seekRelative(-_skipInterval),
                  ),
                if (_showSkipBtns && _showPrevNextBtns)
                  const SizedBox(width: 2),
                if (_showPrevNextBtns)
                  Opacity(
                    opacity: _hasPrev ? 1.0 : 0.25,
                    child: _RaddIconBtn(
                      icon: Icons.skip_previous_rounded,
                      size: 26,
                      onTap: _hasPrev ? () => _playEpisodeAt(_currentEpIdx - 1) : null,
                    ),
                  ),
                const Spacer(),
                // Right nav: next episode + skip forward
                if (_showPrevNextBtns)
                  Opacity(
                    opacity: _hasNext ? 1.0 : 0.25,
                    child: _RaddIconBtn(
                      icon: Icons.skip_next_rounded,
                      size: 26,
                      onTap: _hasNext ? () => _playEpisodeAt(_currentEpIdx + 1) : null,
                    ),
                  ),
                if (_showPrevNextBtns && _showSkipBtns)
                  const SizedBox(width: 2),
                if (_showSkipBtns)
                  _RaddIconBtn(
                    icon: Icons.forward_rounded,
                    size: 22,
                    onTap: () => _seekRelative(_skipInterval),
                  ),
                // Utility buttons — always shown, right of nav
                const SizedBox(width: RaddSpace.xs),
                _RaddIconBtn(
                  icon: Icons.lock_outline_rounded,
                  size: 19,
                  onTap: () => setState(() {
                    _isLocked = true;
                    _showControls = false;
                    _applySubtitleMargin(controlsVisible: false);
                  }),
                ),
                _RaddIconBtn(
                  icon: _isImmersive
                      ? Icons.theaters_rounded
                      : Icons.theaters_outlined,
                  size: 19,
                  onTap: _isImmersive ? _exitImmersive : _enterImmersive,
                ),
                _RaddIconBtn(
                  icon: Icons.settings_rounded,
                  size: 19,
                  onTap: _openSettingsPanel,
                ),
              ],
            ),

            // ── Play/pause — always centered via Stack.center ──────────────────
            GestureDetector(
              onTap: () { _player.playOrPause(); _scheduleHide(); },
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.35), width: 1.2),
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Horizontal Seek Bar
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildHorizontalSeekBar(BoxConstraints parentConstraints, Duration currentPos) {
      final progress = _duration.inMilliseconds > 0
          ? (currentPos.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

      return Row(
        children: [
          // Current time
          SizedBox(
            width: 44,
            child: Text(
              _formatDuration(currentPos),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Seek slider
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: (d) {
                _dragIntent = 'seekbar';
                _dragStart = d.localPosition;
                _dragStartPos = _position;
              },
              onHorizontalDragUpdate: (d) {
                if (_dragIntent != 'seekbar') return;
                final barWidth = parentConstraints.maxWidth - 44 - 44 - 32;
                final relX = d.localPosition.dx.clamp(0.0, barWidth);
                final frac = relX / barWidth;
                if (mounted) setState(() => _seekBarDelta = frac.clamp(0.0, 1.0));
              },
              onHorizontalDragEnd: (_) {
                if (_seekBarDelta != null && _duration.inMilliseconds > 0) {
                  _player.seek(Duration(
                      milliseconds: (_seekBarDelta! * _duration.inMilliseconds).round()));
                  _seekBarDelta = null;
                }
                _dragIntent = null;
                if (mounted) setState(() {});
              },
              onTapDown: (d) {
                final barWidth = parentConstraints.maxWidth - 44 - 44 - 32;
                final frac = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
                if (_duration.inMilliseconds > 0) {
                  _player.seek(Duration(
                      milliseconds: (frac * _duration.inMilliseconds).round()));
                }
              },
              child: LayoutBuilder(
                builder: (ctx, bc) {
                  // Style 0-2 → built-in painter (preserves A-B markers)
                  // Style 3+  → SeekBarPainter (10 rich visual styles)
                  final CustomPainter seekPainter = _progressBarStyle <= 2
                      ? _HorizontalSeekPainter(
                          progress: progress,
                          buffered: _bufferedFraction,
                          abA: _abA,
                          abB: _abB,
                          duration: _duration,
                          style: _progressBarStyle,
                          accentColor: _accentColor,
                        )
                      : SeekBarPainter(
                          style: _seekBarStyleFromIdx(_progressBarStyle),
                          progress: progress,
                          buffered: _bufferedFraction,
                          accentColor: _accentColor,
                        );
                  return SizedBox(
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(bc.maxWidth, 28),
                              painter: seekPainter,
                            ),
                          ),
                        ),
                        // ── A-B repeat pins overlay ──────────────────────
                        if (_duration.inMilliseconds > 0 &&
                            (_abA != null || _abB != null))
                          _AbPinsOverlay(
                            barWidth: bc.maxWidth,
                            duration: _duration,
                            abA: _abA,
                            abB: _abB,
                            accentColor: _accentColor,
                            onAChanged: (d) {
                              if (_abB == null || d < _abB!) {
                                setState(() => _abA = d);
                                _syncNativeAbLoop();
                              }
                            },
                            onBChanged: (d) {
                              if (_abA == null || d > _abA!) {
                                setState(() {
                                  _abB = d;
                                  _abActive = _abA != null;
                                });
                                _syncNativeAbLoop();
                              }
                            },
                            onAClear: () => setState(() {
                              _abA = null;
                              if (_abB == null) _abActive = false;
                              _syncNativeAbLoop();
                            }),
                            onBClear: () => setState(() {
                              _abB = null;
                              _abActive = false;
                              _syncNativeAbLoop();
                            }),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Duration / remaining
          GestureDetector(
            onTap: () { setState(() => _showRemainingTime = !_showRemainingTime); _scheduleSavePrefs(); },
            child: SizedBox(
              width: 44,
              child: Text(
                _showRemainingTime
                    ? '-${_formatDuration(_duration - currentPos)}'
                    : _formatDuration(_duration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      );
    }


    // ═══════════════════════════════════════════════════════════════════════════
    //  Customizable Shortcut Sidebar
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildSidebar(BoxConstraints constraints) {
      // Build shortcut definitions from current live state
      final defs = <String, ({IconData icon, String label, bool active, bool available, VoidCallback? onTap})>{
        'cc': (
          // Reflect whether subtitles are actually turned on, not merely
          // whether tracks exist — a user who explicitly disabled subs
          // (sid=no) should not see the icon highlighted as active.
          icon: _selectedSubtitle != null ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
          label: 'CC',
          active: _selectedSubtitle != null,
          available: true,
          onTap: _openSubtitlePanel,
        ),
        'audio': (
          icon: Icons.headphones_rounded,
          label: 'Audio',
          active: _realAudioTracks.length > 1,
          available: _realAudioTracks.length > 1,
          onTap: _openAudioPanel,
        ),
        'eq': (
          icon: Icons.equalizer_rounded,
          label: 'EQ',
          active: _eqEnabled,
          available: true,
          onTap: _openAudioEffectPanel,
        ),
        'speed': (
          icon: Icons.speed_rounded,
          label: _speed == 1.0 ? '1×' : '${_speed.toStringAsFixed(2)}×',
          active: _speed != 1.0,
          available: true,
          onTap: _cycleSpeed,
        ),
        'loop': (
          icon: Icons.loop_rounded,
          label: 'Loop',
          active: _loopEnabled,
          available: true,
          onTap: _toggleLoop,
        ),
        'rotate': (
          icon: _orientIcon,
          label: 'Rotate',
          active: _orientMode != 0,
          available: true,
          onTap: _cycleOrientation,
        ),
        'lock': (
          icon: Icons.lock_outline_rounded,
          label: 'Lock',
          active: false,
          available: true,
          onTap: () => setState(() {
            _isLocked = true;
            _showControls = false;
            _applySubtitleMargin(controlsVisible: false);
          }),
        ),
        'immersive': (
          icon: Icons.theaters_rounded,
          label: 'Immersive',
          active: _isImmersive,
          available: true,
          onTap: _isImmersive ? _exitImmersive : _enterImmersive,
        ),
        'pip': (
          icon: Icons.picture_in_picture_alt_rounded,
          label: 'PiP',
          active: false,
          available: true,
          onTap: _enterPiP,
        ),
        'screenshot': (
          icon: Icons.camera_alt_rounded,
          label: 'Shot',
          active: false,
          available: true,
          onTap: _takeScreenshot,
        ),
        'sleep': (
          icon: Icons.bedtime_rounded,
          label: _sleepTimerEnd != null ? '💤 ${_fmtSleepRemaining()}' : 'Sleep',
          active: _sleepTimerEnd != null,
          available: true,
          onTap: _sleepTimerEnd != null
              ? () { _setSleepTimer(null); }
              : () { _openMoreMenu(); },
        ),
        'ab': (
          icon: Icons.repeat_one_rounded,
          label: _abActive ? 'A-B●' : 'A-B',
          active: _abActive,
          available: true,
          onTap: _handleAbRepeat,
        ),
        'episodes': (
          icon: Icons.view_list_rounded,
          label: 'Eps',
          active: false,
          available: _eps.length > 1,
          onTap: _showEpisodeSheet,
        ),
        'settings': (
          icon: Icons.settings_rounded,
          label: 'Config',
          active: false,
          available: true,
          onTap: _openSettingsPanel,
        ),
        'vivid': (
          icon: Icons.auto_awesome_rounded,
          label: 'Vivid',
          active: _smartEnhanceEnabled,
          available: true,
          onTap: _toggleSmartEnhance,
        ),
        'mute': (
          icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: _isMuted ? 'Unmute' : 'Mute',
          active: _isMuted,
          available: true,
          onTap: _toggleMute,
        ),
        'frame': (
          icon: Icons.skip_next_rounded,
          label: 'Frame',
          active: false,
          available: true,
          onTap: () { try { _np.command(['frame-step']); } catch (_) {} },
        ),
        'onehanded': (
          icon: Icons.pan_tool_alt_rounded,
          label: '1-Hand',
          active: _oneHandedMode,
          available: true,
          onTap: () { setState(() => _oneHandedMode = !_oneHandedMode); _scheduleSavePrefs(); },
        ),
        'zoom': (
          icon: Icons.zoom_in_rounded,
          label: 'Zoom',
          active: _zoomMode != 0,
          available: true,
          onTap: _openZoomPanel,
        ),
        'silence': (
          icon: Icons.volume_off_outlined,
          label: 'Silence',
          active: _silenceSkipEnabled,
          available: true,
          onTap: () => _showSilenceSkipSheet(context),
        ),
        'more': (
          icon: Icons.more_horiz_rounded,
          label: 'More',
          active: false,
          available: true,
          onTap: _openMoreMenu,
        ),
      };

      final visibleItems = _sidebarOrder
          .where((id) => defs.containsKey(id))
          .toList();

      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Toggle chevron tab ──────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              setState(() => _sidebarExpanded = !_sidebarExpanded);
              _scheduleSavePrefs();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.72),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                border: Border(
                  left: BorderSide(
                    color: _sidebarExpanded
                        ? _accentColor.withOpacity(0.60)
                        : Colors.white.withOpacity(0.14),
                    width: 1.5,
                  ),
                  top: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5),
                  bottom: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5),
                ),
              ),
              child: Icon(
                _sidebarExpanded ? Icons.chevron_right : Icons.chevron_left,
                color: _sidebarExpanded
                    ? _accentColor.withOpacity(0.90)
                    : Colors.white.withOpacity(0.40),
                size: 13,
              ),
            ),
          ),

          // ── Sidebar body ────────────────────────────────────────────────
          if (_sidebarExpanded) ...[
            const SizedBox(height: RaddSpace.xs),
            Flexible(
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.74),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                  border: Border(
                    left: BorderSide(color: Colors.white.withOpacity(0.09), width: 0.8),
                    top: BorderSide(color: Colors.white.withOpacity(0.05), width: 0.5),
                    bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Shortcut buttons ────────────────────────────────
                      for (int _si = 0; _si < visibleItems.length; _si++) ...[
                        if (defs[visibleItems[_si]] != null) ...[
                          if (_si > 0)
                            Container(
                              height: 0.4,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              color: Colors.white.withOpacity(0.07),
                            ),
                          _buildSidebarBtn(defs[visibleItems[_si]]!),
                        ],
                      ],
                      // ── Edit / Customize ─────────────────────────────────
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        color: Colors.white.withOpacity(0.13),
                      ),
                      GestureDetector(
                        onTap: _openSidebarCustomizer,
                        child: Container(
                          width: 64,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded,
                                  color: Colors.white.withOpacity(0.30), size: 17),
                              const SizedBox(height: 3),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.24),
                                  fontSize: 9,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // ── Sidebar shortcut button (icon + label, active = accent left border) ──
    Widget _buildSidebarBtn(({IconData icon, String label, bool active, bool available, VoidCallback? onTap}) def) {
      return GestureDetector(
        onTap: def.available ? def.onTap : null,
        child: Opacity(
          opacity: def.available ? 1.0 : 0.28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: def.active ? _accentColor.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: def.active
                  ? Border(left: BorderSide(color: _accentColor, width: 2.5))
                  : const Border(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  def.icon,
                  color: def.active ? _accentColor : Colors.white.withOpacity(0.70),
                  size: 22,
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    def.label,
                    style: TextStyle(
                      color: def.active ? _accentColor : Colors.white.withOpacity(0.46),
                      fontSize: 10,
                      fontWeight: def.active ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  MX Player-style side indicator (vertical pill)
    //  Brightness → LEFT side (amber bar)
    //  Volume     → RIGHT side (white/orange bar)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildSideIndicator({
      required IconData icon,
      required double barValue,
      required Color barColor,
      required String label,
    }) {
      return Container(
        width: 44,
        height: 176,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.58),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: RaddSpace.sm),
            // Vertical bar — fills bottom-to-top like MX Player
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: RotatedBox(
                    quarterTurns: 3, // rotate so bar fills bottom→top
                    child: LinearProgressIndicator(
                      value: barValue.clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withOpacity(0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      minHeight: 6,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: RaddSpace.sm),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Portrait layout — YouTube/Netflix split (video top 38% + controls below)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildPortraitLayout(BoxConstraints constraints) {
      // Full-bleed video — video surface fills the entire screen (TikTok/YouTube
      // Shorts style) instead of being confined to a fixed top zone. Controls are
      // a floating, auto-hiding overlay on top, not a permanent panel that eats
      // half the screen.
      final Duration currentPos = _seekBarDelta != null
          ? Duration(milliseconds: (_seekBarDelta! * _duration.inMilliseconds).round())
          : _position;
      final BoxConstraints videoConstraints = BoxConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      );

      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Stack(
              children: [
                // Video surface
                Positioned.fill(child: RepaintBoundary(child: _buildVideoSurface())),

                // AI Dub progress overlay
                if (_dubGenerating) _buildDubProgressOverlay(),

                // Lock overlay
                if (_isLocked) _buildLockOverlay(),

                // Gesture layer — scoped to video zone only
                if (!_isLocked && !_isImmersive)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) {
                        if (!_doubleTapSeekEnabled) return;
                        final isLeft = d.localPosition.dx < constraints.maxWidth / 2;
                        _seekRelative(isLeft ? -_skipInterval : _skipInterval);
                      },
                      onLongPressStart: (_) { if (_longPressSpeedEnabled) _startLongPress(); },
                      onLongPressEnd: (_) { if (_longPressSpeedEnabled) _endLongPress(); },
                      onLongPressCancel: () { if (_longPressSpeedEnabled) _endLongPress(); },
                      onScaleStart: (d) => _onScaleStart(d, videoConstraints),
                      onScaleUpdate: (d) => _onScaleUpdate(d, videoConstraints),
                      onScaleEnd: _onScaleEnd,
                    ),
                  ),

                // Top gradient
                Positioned(
                  top: 0, left: 0, right: 0, height: 60,
                  child: IgnorePointer(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xBB000000), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Persistent back button — always visible, never auto-hides ──
                if (!_isLocked)
                  Positioned(
                    top: 0, left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: _RaddIconBtn(
                          icon: Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),

                // ── Fade-in title bar: title + episode + rotate + PiP ──────────
                if (!_isImmersive)
                  Positioned(
                    top: 0, left: 44, right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls && !_isLocked ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 280),
                      child: IgnorePointer(
                        ignoring: !_showControls || _isLocked,
                        child: SafeArea(
                          bottom: false,
                          child: _buildPortraitTopBar(),
                        ),
                      ),
                    ),
                  ),

                // Sidebar suppressed in portrait — it covers video content and
                // duplicates the quick actions row below. Landscape only.

                // Brightness indicator
                if (_showBrightnessIndicator && !_isImmersive)
                  Positioned(
                    left: 20, top: 0, bottom: 0,
                    child: Center(
                      child: _buildSideIndicator(
                        icon: _brightness < 0.3
                            ? Icons.brightness_low_rounded
                            : _brightness > 0.7
                                ? Icons.brightness_high_rounded
                                : Icons.brightness_medium_rounded,
                        barValue: _brightness,
                        barColor: const Color(0xFFFFD60A),
                        label: '${(_brightness * 100).round()}%',
                      ),
                    ),
                  ),

                // Volume indicator — RIGHT side (volume swipe is right-half of screen)
                if (_showVolumeIndicator && !_isImmersive)
                  Positioned(
                    right: 20, top: 0, bottom: 0,
                    child: Center(
                      child: _buildSideIndicator(
                        icon: _isMuted
                            ? Icons.volume_off_rounded
                            : _volume > 1.0
                                ? Icons.volume_up_rounded
                                : _volume > 0.4
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_mute_rounded,
                        barValue: _volume.clamp(0.0, 1.0),
                        barColor: _volume > 2.0
                            ? const Color(0xFFFF3B30)
                            : _volume > 1.0
                                ? const Color(0xFFFF6B35)
                                : Colors.white,
                        label: '${(_volume * 100).round()}%',
                      ),
                    ),
                  ),

                // Long-press 2× speed badge
                if (_longPressFast)
                  Positioned(
                    top: 10, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('2× Speed', style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),

                // Buffering spinner
                if (_buffering && !_isLinkLoading && _streamError == null)
                  const Center(child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)),

                // Link loading
                if (_isLinkLoading)
                  Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: RaddSpace.md),
                        Text('Loading stream…',
                            style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ]),
                    ),
                  ),

                // Error overlay (compact for portrait video zone)
                if (_streamError != null)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(RaddSpace.md),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 36),
                          const SizedBox(height: RaddSpace.sm),
                          Text(_streamError!,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 10),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6)),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry',
                                  style: TextStyle(fontSize: 13)),
                              onPressed: () {
                                _cancelAutoRetry();
                                setState(() => _streamError = null);
                                _openMedia(_currentFileId);
                              },
                            ),
                            const SizedBox(width: RaddSpace.sm),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Back',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ),

                // ── Floating bottom controls overlay (TikTok/Shorts style) ──────
                // Not a fixed panel — sits on top of the full-bleed video, fades
                // with the rest of the controls, and lets the video show through
                // above the gradient instead of permanently occupying screen space.
                if (!_isImmersive)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls && !_isLocked ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 280),
                      child: IgnorePointer(
                        ignoring: !_showControls || _isLocked,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xE6000000)],
                              stops: [0.0, 0.35],
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: _buildPortraitControlsPanel(constraints, currentPos),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      );
    }

    Widget _buildPortraitTopBar() {
      // Back button is always-visible separately (Positioned above this widget).
      // This bar only handles title + episode badge + rotate + PiP (fade-in only).
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _currentTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_eps.length > 1)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'E${_currentEpIdx + 1}/${_eps.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            _RaddIconBtn(
              icon: _orientIcon,
              size: 18,
              onTap: _cycleOrientation,
            ),
            _RaddIconBtn(
              icon: Icons.picture_in_picture_rounded,
              size: 18,
              onTap: _enterPiP,
            ),
          ],
        ),
      );
    }

    Widget _buildPortraitControlsPanel(BoxConstraints constraints, Duration currentPos) {
      // Floating overlay over full-bleed video — sizes to its content instead of
      // stretching to fill a fixed panel height (TikTok/Shorts style controls).
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHorizontalSeekBar(constraints, currentPos),
            const SizedBox(height: 4),
            _buildPortraitTransportRow(),
            const SizedBox(height: 4),
            _buildPortraitQuickActions(),
          ],
        ),
      );
    }

    Widget _buildPortraitQuickActions() {
      // Each button is Expanded+Center so they share width equally and never overflow
      return Row(
        children: [
          Expanded(child: Center(child: _buildPortraitActionBtn(
            _selectedSubtitle != null
                ? Icons.subtitles_rounded
                : Icons.subtitles_off_rounded,
            'CC',
            _openSubtitlePanel,
            active: _selectedSubtitle != null,
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.headphones_rounded,
            'Audio',
            _openAudioPanel,
            active: _realAudioTracks.length > 1,
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.equalizer_rounded,
            'EQ',
            _openAudioEffectPanel,
            active: _eqEnabled,
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.speed_rounded,
            _speed == 1.0 ? '1×' : '${_speed.toStringAsFixed(1)}×',
            _cycleSpeed,
            active: _speed != 1.0,
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.lock_outline_rounded,
            'Lock',
            () => setState(() {
              _isLocked = true;
              _showControls = false;
              _applySubtitleMargin(controlsVisible: false);
            }),
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.more_horiz_rounded,
            'More',
            _openSettingsPanel,
          ))),
        ],
      );
    }

    Widget _buildPortraitActionBtn(
        IconData icon, String label, VoidCallback? onTap, {bool active = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: active
                    ? _accentColor.withOpacity(0.18)
                    : Colors.white.withOpacity(0.06),
                borderRadius: RaddRadius.mdRadius,
                border: Border.all(
                  color: active
                      ? _accentColor.withOpacity(0.55)
                      : Colors.white12,
                  width: 0.8,
                ),
              ),
              child: Icon(icon,
                  color: active ? _accentColor : Colors.white70, size: 20),
            ),
            const SizedBox(height: RaddSpace.xs),
            Text(
              label,
              style: TextStyle(
                color: active ? _accentColor : Colors.white54,
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Portrait-only transport row (no Lock / Immersive / Settings clutter)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildPortraitTransportRow() {
      // Landscape transport row appends Lock/Immersive/Settings on the right.
      // In portrait those live in the quick actions row — keep this row clean.
      return SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_showSkipBtns)
                  _RaddIconBtn(
                    icon: Icons.replay_rounded,
                    size: 24,
                    onTap: () => _seekRelative(-_skipInterval),
                  ),
                if (_showPrevNextBtns)
                  Opacity(
                    opacity: _hasPrev ? 1.0 : 0.25,
                    child: _RaddIconBtn(
                      icon: Icons.skip_previous_rounded,
                      size: 28,
                      onTap: _hasPrev ? () => _playEpisodeAt(_currentEpIdx - 1) : null,
                    ),
                  ),
                const Spacer(),
                if (_showPrevNextBtns)
                  Opacity(
                    opacity: _hasNext ? 1.0 : 0.25,
                    child: _RaddIconBtn(
                      icon: Icons.skip_next_rounded,
                      size: 28,
                      onTap: _hasNext ? () => _playEpisodeAt(_currentEpIdx + 1) : null,
                    ),
                  ),
                if (_showSkipBtns)
                  _RaddIconBtn(
                    icon: Icons.forward_rounded,
                    size: 24,
                    onTap: () => _seekRelative(_skipInterval),
                  ),
              ],
            ),
            // Play/pause — always pixel-centered via Stack
            GestureDetector(
              onTap: () { _player.playOrPause(); _scheduleHide(); },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.14),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.40), width: 1.2),
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Panels (right-side slide-in / bottom-sheet in portrait)
    // ═══════════════════════════════════════════════════════════════════════════

// Volume X: any sheet/panel over the video surface must stay ≤40% of the
// viewport so it never dominates or blocks the frame.
void _openRightPanel(Widget content, {double widthFactor = 0.4}) {
  final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
  setState(() => _panelOpen = true);
  if (isPortrait) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.88,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: PrimaryScrollController(
                  controller: scrollController,
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) { if (mounted) setState(() => _panelOpen = false); });
    return;
  }
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final w = MediaQuery.of(ctx).size.width;
      final slide = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
      return Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: Container(color: Colors.black.withOpacity(0.12 * anim.value)),
          ),
          Positioned(
            right: 0, top: 0, bottom: 0,
            width: w * widthFactor,
            child: SlideTransition(
              position: slide,
              child: Material(
                color: const Color(0xEA1C1C1E),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Colors.white12, width: 0.8)),
                  ),
                  child: SafeArea(child: content),
                ),
              ),
            ),
          ),
        ],
      );
    },
  ).then((_) { if (mounted) setState(() => _panelOpen = false); });
}

// C1: shared orientation-aware panel opener. All 7 panel-opening methods
// below (_openSubtitlePanel, _openAudioPanel, _openZoomPanel,
// _openAudioEffectPanel, _openMoreMenu, _openSidebarCustomizer,
// _openSettingsPanel) used to repeat this exact landscape/portrait branch
// inline (commit 72f93a8d). Centralized here so the branching logic only
// exists once.
void _openPanel({
  required Widget panel,
  required String title,
  double widthFactor = 0.40,
  double maxHeightFraction = 0.85,
}) {
  if (MediaQuery.of(context).orientation == Orientation.landscape) {
    _openRightPanel(panel, widthFactor: widthFactor);
    return;
  }
  setState(() => _panelOpen = true);
  RaddSheet.show<void>(
    context,
    style: RaddSheetStyle.list,
    title: title,
    maxHeightFraction: maxHeightFraction,
    listBuilder: (_) => panel,
  ).then((_) { if (mounted) setState(() => _panelOpen = false); });
}

    void _openSubtitlePanel() {
      final panel = _SubtitlePanel(
        isLocal: _isLocal,
        subSync: _subSync,
        subSpeed: _subSpeed,
        currentFile: _currentSubFile,
        onSyncChanged: (delta) => _adjustSubSync(delta),
        onSpeedChanged: (v) {
          setState(() => _subSpeed = v);
          try { _np.setProperty('sub-speed', v.toString()); } catch (_) {}
          _scheduleSavePrefs();
        },
        onSubPropertyChanged: (prop, val) {
          if (prop == '_sub_margin_main') {
            // Internal signal — update main state so _applySubtitleMargin
            // uses the user's latest base value.
            setState(() => _subBottomMarginMain = double.tryParse(val) ?? _subBottomMarginMain);
            _scheduleSavePrefs();
          } else {
            try {
              // Force ASS style override FIRST so that the property change below
              // immediately takes effect on ASS-format subs (embedded or SRT→ASS).
              if (prop == 'sub-font-size'    || prop == 'sub-font'          ||
                  prop == 'sub-bold'        || prop == 'sub-color'        ||
                  prop == 'sub-back-color'  || prop == 'sub-scale'        ||
                  prop == 'sub-opacity'     || prop == 'sub-outline-size' ||
                  prop == 'sub-shadow-offset') {
                _np.setProperty('sub-ass-override', 'force');
              }
              _np.setProperty(prop, val);
            } catch (_) {}
          }
        },
        title: _currentTitle,
        onSubtitleFilePicked: (path) {
          setState(() => _currentSubFile = path);
          try { _np.setProperty('sub-file', path); } catch (_) {}
        },
        // P57-02: embedded track selector
        embeddedTracks: _realSubtitleTracks,
        selectedSubtitle: _selectedSubtitle,
        onSubtitleTrackSelected: (track) {
          setState(() {
            _selectedSubtitle = track;
            // Remember the language so future episodes auto-select the same
            // language. Only update when track has a real language code.
            if (track != null && (track.language?.isNotEmpty ?? false)) {
              _prefSubLang = track.language;
            }
          });
          _scheduleSavePrefs();
          if (track != null) {
            _player.setSubtitleTrack(track);
          } else {
            try { _np.setProperty('sid', 'no'); } catch (_) {}
          }
        },
        // P57-07: secondary subtitle (OST/signs at top)
        selectedSecondSub: _selectedSecondSub,
        onSecondSubSelected: (track) {
          setState(() => _selectedSecondSub = track);
          try {
            // Guard against tracks with a null/non-numeric id (e.g. synthetic
            // or virtual entries) — track.id! used to crash the player here.
            final id = track?.id;
            if (track != null && id != null && int.tryParse(id) != null) {
              _np.setProperty('secondary-sid', id);
              _np.setProperty('secondary-sub-visibility', 'yes');
            } else {
              _np.setProperty('secondary-sid', 'no');
            }
          } catch (_) {}
        },
        onDubRequested: _startDubGeneration,  // P59
        onStyleSynced: ({required fontIdx, required size, required bold,
            required color, required bgColor, required opacity}) {
          const fontNames = ['Sans Serif', 'Serif', 'Monospace', 'Casual'];
          ref.read(playerPrefsProvider.notifier).update((p) => p.copyWith(
                subtitleFontFamily: fontNames[fontIdx.clamp(0, fontNames.length - 1)],
                subtitleFontSize: size,
                subtitleBold: bold,
                // Bake the panel's separate text-opacity slider into the
                // color's alpha channel, since PlayerPrefs has no distinct
                // text-opacity field.
                subtitleTextColorValue: color.withOpacity(opacity).value,
                subtitleBackgroundColorValue: bgColor.value,
                subtitleBackgroundOpacity: bgColor.opacity,
              ));
        },
      );
      _openPanel(panel: panel, title: 'Subtitles', widthFactor: 0.42, maxHeightFraction: 0.90);
    }

    void _openAudioPanel() {
      final panel = _AudioTrackPanel(
        tracks: _realAudioTracks,
        selectedTrack: _selectedAudio,
        audioSync: _audioSync,
        useSWDecoder: _useSWDecoder,
        onTrackSelected: (track) {
          setState(() {
            _selectedAudio = track;
            // Remember the language so future episodes auto-select the same
            // audio language. Only update when track has a real language code.
            if (track != null && (track.language?.isNotEmpty ?? false)) {
              _prefAudioLang = track.language;
            }
          });
          _scheduleSavePrefs();
          if (track != null) {
            _player.setAudioTrack(track);
            // Fallback: on some stream types (DASH/HLS) media_kit's
            // setAudioTrack() has been observed to silently no-op. Also set
            // the native mpv property directly, mirroring the existing
            // disable-path fallback right below — belt-and-braces so track
            // switching actually takes effect.
            if (track.id != null) {
              try { _np.setProperty('aid', track.id!); } catch (_) {}
            }
          } else {
            try { _np.setProperty('aid', 'no'); } catch (_) {}
          }
        },
        onSyncChanged: (delta) => _adjustAudioSync(delta),
        onSWDecoderChanged: (v) {
          setState(() => _useSWDecoder = v);
          // Safety rule (MediaTek/Infinix black-screen): never change hwdec while playing.
          // Apply immediately when paused/stopped; otherwise save state and notify the user.
          if (!_playing) {
            try { _np.setProperty('hwdec', v ? 'no' : 'auto-safe'); } catch (_) {}
          } else {
            _showInfoSnackbar('Decoder preference saved — will apply on next file or after pause');
          }
        },
        onChannelModeChanged: (filterStr) {
          setState(() {
            _currentChannelModeAf = filterStr;
            _channelModeIdx = (_channelModeIdx + 1) % 4;
          });
          _applyAllAf();
          _scheduleSavePrefs();
        },
        initialChannelModeIdx: _channelModeIdx,
        isPlaying: _playing,
        currentCodec: _currentAudioCodec.isNotEmpty ? _currentAudioCodec : null,
        isDubMode: _isDubMode,           // P60
        dubActiveLang: _dubActiveLang,   // P60
        onRemoveDub: () {                // P60
          _disableDubMode();
          Navigator.of(context).pop();
        },
      );
      _openPanel(panel: panel, title: 'Audio Track', widthFactor: 0.38);
    }

    void _openZoomPanel() {
      const modes = ['Fit to screen', 'Stretch', 'Crop', '100%', 'Pinch & Zoom'];
      final panel = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < modes.length; i++)
            RadioListTile<int>(
              value: i,
              groupValue: _zoomMode,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _zoomMode = v);
                _scheduleSavePrefs();
                Navigator.of(context).pop();
                if (v == 4) {
                  _showInfoSnackbar('Pinch the video to set a custom zoom level');
                }
              },
              title: Text(modes[i], style: const TextStyle(color: Colors.white, fontSize: 14)),
              activeColor: Colors.white,
              controlAffinity: ListTileControlAffinity.trailing,
            ),
        ],
      );
      _openPanel(panel: panel, title: 'Video Zoom', widthFactor: 0.30);
    }

    void _openAudioEffectPanel() {
      final panel = _AudioEffectPanel(
        selectedPreset: _selectedPreset,
        eqBands: _eqBands,
        eqEnabled: _eqEnabled,
        onPresetSelected: _applyPreset,
        onEqBandChanged: (i, v) {
          setState(() { _eqBands[i] = v; _selectedPreset = -1; });
          _applyCustomEq();
          _scheduleSavePrefs();
        },
        onEqEnabledChanged: (v) {
          setState(() => _eqEnabled = v);
          _applyAllAf(); // merged pipeline — reverb/lab still active if enabled
          _scheduleSavePrefs();
        },
        onReverbChanged: (preset) {
          setState(() => _reverbPreset = preset ?? 'None');
          switch (preset) {
            case 'Small Room':  _currentReverbAf = 'aecho=0.8:0.9:30:0.4'; break;
            case 'Hall':        _currentReverbAf = 'aecho=0.8:0.88:60:0.4'; break;
            case 'Cathedral':   _currentReverbAf = 'aecho=0.8:0.88:120:0.5'; break;
            case 'Stadium':     _currentReverbAf = 'aecho=0.8:0.9:180:0.6'; break;
            default:            _currentReverbAf = '';
          }
          _applyAllAf(); // EQ + reverb + lab now all stack correctly
          _scheduleSavePrefs();
        },
        onLabAfChanged: (afStr) {
          _currentLabAf = afStr;
          _applyAllAf(); // EQ + reverb + lab all stack
        },
        onLabStateChanged: (vocal, dialogue, norm, bass, bassLevel, dialogueOnly, compress, stereoWide, noise) {
          setState(() {
            _labVocal = vocal;
            _labDialogue = dialogue;
            _labNorm = norm;
            _labBass = bass;
            _labBassLevel = bassLevel;
            _labDialogueOnly = dialogueOnly;
            _labCompress = compress;
            _labStereoWide = stereoWide;
            _labNoise = noise;
          });
          _scheduleSavePrefs();
        },
        labVocal: _labVocal,
        labDialogue: _labDialogue,
        labNorm: _labNorm,
        labBass: _labBass,
        labBassLevel: _labBassLevel,
        labDialogueOnly: _labDialogueOnly,
        labCompress: _labCompress,
        labStereoWide: _labStereoWide,
        labNoise: _labNoise,
        initialReverbPreset: _reverbPreset,
        audioBalance: _audioBalance,
        onBalanceChanged: _applyBalance,
      );
      _openPanel(panel: panel, title: 'Audio Effect', widthFactor: 0.44, maxHeightFraction: 0.90);
    }

    void _openMoreMenu() {
      final panel = _QuickShortcutsPanel(
        isLocked: _isLocked,
        isMuted: _isMuted,
        loopEnabled: _loopEnabled,
        smartEnhanceEnabled: _smartEnhanceEnabled,
        isOneHanded: _oneHandedMode,
        sleepTimerMinutes: _sleepTimerMinutes,
        sleepTimerEnd: _sleepTimerEnd,
        speed: _speed,
        abA: _abA,
        abB: _abB,
        abActive: _abActive,
        isRotateLocked: _orientMode != 0,
        onRotate: () { Navigator.of(context).pop(); _cycleOrientation(); },
        onLockToggle: () { Navigator.of(context).pop(); setState(() => _isLocked = true); },
        onMuteToggle: () { Navigator.of(context).pop(); _toggleMute(); },
        onLoopToggle: () { Navigator.of(context).pop(); _toggleLoop(); },
        onSmartEnhanceToggle: () { Navigator.of(context).pop(); _toggleSmartEnhance(); },
        onOneHandedToggle: () {
          Navigator.of(context).pop();
          setState(() => _oneHandedMode = !_oneHandedMode);
          _scheduleSavePrefs();
        },
        onSleepTimer: (mins) { Navigator.of(context).pop(); _setSleepTimer(mins); },
        onSpeedSelected: (s) { Navigator.of(context).pop(); _setSpeed(s); },
        onAudioEffect: () { Navigator.of(context).pop(); _openAudioEffectPanel(); },
        onSettingsOpen: () { Navigator.of(context).pop(); _openSettingsPanel(); },
        onAbSet: () { Navigator.of(context).pop(); _handleAbRepeat(); },
        onFrameStep: () {
          Navigator.of(context).pop();
          try { _np.command(['frame-step']); } catch (_) {}
        },
        // Extended shortcuts
        onJumpTo:         () { Navigator.of(context).pop(); _showJumpToDialog(context); },
        onSpeedPresets:   () { Navigator.of(context).pop(); _showSpeedPresetsSheet(context); },
        onEndAction:      () { Navigator.of(context).pop(); _showEndActionSheet(context); },
        onScreenshot:     () { Navigator.of(context).pop(); _takeScreenshot(); },
        onScreenshotWithSubtitles: () { Navigator.of(context).pop(); _takeScreenshot(withSubtitles: true); },
        onWatchParty:     () { Navigator.of(context).pop(); _showWatchPartyDialog(context); },
        onSilenceSkip:    () { Navigator.of(context).pop(); _showSilenceSkipSheet(context); },
        onZoomCrop:       () { Navigator.of(context).pop(); _showZoomCropSheet(context); },
        onGestureMap:     () { Navigator.of(context).pop(); _showGestureMapSheet(context); },
        onSkipEditor:     () { Navigator.of(context).pop(); _showSkipEditorSheet(context); },
        onLayoutDesigner: () { Navigator.of(context).pop(); _showLayoutDesignerSheet(context); },
        silenceSkipEnabled: _silenceSkipEnabled,
        endAction: _endAction,
        onPiP: () { Navigator.of(context).pop(); _enterPiP(); },
        onSidebarEdit: () { Navigator.of(context).pop(); _openSidebarCustomizer(); },
      );
      _openPanel(panel: panel, title: 'More', widthFactor: 0.40);
    }

    void _handleAbRepeat() {
      if (_abA == null) {
        setState(() { _abA = _position; _abActive = false; });
        _syncNativeAbLoop();
        _showInfoSnackbar('A point set at ${_formatDuration(_position)}');
      } else if (_abB == null) {
        setState(() { _abB = _position; _abActive = true; });
        _syncNativeAbLoop();
        _showInfoSnackbar('B point set. A-B repeat active (native MPV loop).');
      } else {
        setState(() { _abA = null; _abB = null; _abActive = false; });
        _syncNativeAbLoop();
        _showInfoSnackbar('A-B repeat cleared.');
      }
    }

    // ── Jump To ───────────────────────────────────────────────────────────────
    void _showJumpToDialog(BuildContext ctx) {
      final ctrl = TextEditingController();
      showDialog(
        context: ctx,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Jump To Position', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter time  (mm:ss or hh:mm:ss)', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: const InputDecoration(
                  hintText: '1:30:00',
                  hintStyle: TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 6,
                children: ['1m', '5m', '10m', '15m', '30m', '45m'].map((label) {
                  return GestureDetector(
                    onTap: () {
                      final m = int.parse(label.replaceAll('m', ''));
                      ctrl.text = '$m:00';
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: RaddRadius.smRadius,
                      ),
                      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final t = ctrl.text.trim();
                final parts = t.split(':').reversed.toList();
                int total = 0;
                final mults = [1, 60, 3600];
                for (int i = 0; i < parts.length && i < 3; i++) {
                  total += (int.tryParse(parts[i]) ?? 0) * mults[i];
                }
                _player.seek(Duration(seconds: total.clamp(0, _duration.inSeconds)));
                Navigator.of(c).pop();
              },
              child: const Text('Go', style: TextStyle(color: Color(0xFF4A9EFF), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    // ── Speed Presets ─────────────────────────────────────────────────────────
    void _showSpeedPresetsSheet(BuildContext ctx) {
      const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
      _openRightPanel(StatefulBuilder(
          builder: (shCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Speed Presets', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: speeds.map((s) {
                    final active = (s - _speed).abs() < 0.01;
                    return GestureDetector(
                      onTap: () {
                        _setSpeed(s);
                        setSt(() {});
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        width: 72,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? Colors.white24 : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: active ? Colors.white38 : Colors.transparent),
                        ),
                        child: Text(
                          '${s == s.roundToDouble() ? s.toInt() : s}×',
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),);;
    }

    // ── End Action ────────────────────────────────────────────────────────────
    void _showEndActionSheet(BuildContext ctx) {
      _openRightPanel(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('When video ends…', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: RaddSpace.xs),
              const Text('Applies to every video in this session', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 12),
              for (final pair in [
                ('play_next', Icons.skip_next_rounded,   'Play Next Episode'),
                ('loop',      Icons.repeat_rounded,       'Loop Current'),
                ('stop',      Icons.stop_circle_outlined, 'Stop & Stay'),
                ('ask',       Icons.help_outline_rounded, 'Ask Each Time'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(pair.$2, color: _endAction == pair.$1 ? Colors.white : Colors.white54),
                  title: Text(
                    pair.$3,
                    style: TextStyle(
                      color: _endAction == pair.$1 ? Colors.white : Colors.white70,
                      fontWeight: _endAction == pair.$1 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: _endAction == pair.$1
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : null,
                  onTap: () {
                    setState(() => _endAction = pair.$1);
                    _scheduleSavePrefs();
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),);;
    }

    // ── Silence Skip ──────────────────────────────────────────────────────────
    void _showSilenceSkipSheet(BuildContext ctx) {
      _openRightPanel(StatefulBuilder(
          builder: (shCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Silence Skip', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Auto-skip silent gaps in audio', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _silenceSkipEnabled,
                      onChanged: (v) {
                        setState(() => _silenceSkipEnabled = v);
                        setSt(() {});
                        _applySilenceSkip();
                        _scheduleSavePrefs();
                      },
                      activeColor: Colors.white,
                    ),
                  ],
                ),
                if (_silenceSkipEnabled) ...[
                  const SizedBox(height: RaddSpace.md),
                  Row(children: [
                    const Text('Silence threshold  ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_silenceSkipThreshold.toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ]),
                  Slider(
                    value: _silenceSkipThreshold,
                    min: 0.3, max: 5.0, divisions: 47,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (v) {
                      setState(() => _silenceSkipThreshold = v);
                      setSt(() {});
                      _applySilenceSkip();
                      _scheduleSavePrefs();
                    },
                  ),
                  const Text(
                    'Detects silent audio sections and jumps past them automatically.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),);;
    }


    // ── Zoom & Crop ───────────────────────────────────────────────────────────
    void _showZoomCropSheet(BuildContext ctx) {
      final ratios = [
        ('Auto',    ''),
        ('16:9',    '16:9'),
        ('4:3',     '4:3'),
        ('21:9',    '21:9'),
        ('18:9',    '18:9'),
        ('1:1',     '1:1'),
        ('Stretch', '-1'),
      ];
      _openRightPanel(StatefulBuilder(
          builder: (shCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Zoom & Crop', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: RaddSpace.xs),
                const Text('Aspect ratio override', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: List.generate(ratios.length, (i) {
                    final active = (_cropAspectIdx == i);
                    return GestureDetector(
                      onTap: () {
                        setState(() => _cropAspectIdx = i);
                        setSt(() {});
                        try {
                          _np.setProperty('video-aspect-override', ratios[i].$2.isEmpty ? '-1' : ratios[i].$2);
                        } catch (_) {}
                        _scheduleSavePrefs();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? Colors.white24 : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: active ? Colors.white38 : Colors.transparent),
                        ),
                        child: Text(
                          ratios[i].$1,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 10),
                const Text(
                  'Pinch on the video to zoom digitally. Double-tap to reset.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),);;
    }

    // ── Gesture Map ───────────────────────────────────────────────────────────
    void _showGestureMapSheet(BuildContext ctx) {
      _openRightPanel(StatefulBuilder(
          builder: (shCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Gesture Map', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: RaddSpace.xs),
                const Text('Toggle each gesture on or off', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Double-tap seek', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Double-tap left/right to ±${_skipInterval}s', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _doubleTapSeekEnabled,
                  onChanged: (v) { setState(() => _doubleTapSeekEnabled = v); setSt(() {}); _scheduleSavePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Long press speed boost', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Hold to play at 2× speed', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _longPressSpeedEnabled,
                  onChanged: (v) { setState(() => _longPressSpeedEnabled = v); setSt(() {}); _scheduleSavePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe to seek', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Horizontal swipe jumps through video', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _swipeSeekEnabled,
                  onChanged: (v) { setState(() => _swipeSeekEnabled = v); setSt(() {}); _scheduleSavePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe brightness / volume', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Left edge: brightness  •  Right edge: volume', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _swipeBVEnabled,
                  onChanged: (v) { setState(() => _swipeBVEnabled = v); setSt(() {}); _scheduleSavePrefs(); },
                  activeColor: Colors.white,
                ),
              ],
            ),
          ),
        ),);;
    }

    // ── Skip Editor ───────────────────────────────────────────────────────────
    void _showSkipEditorSheet(BuildContext ctx) {
      _openRightPanel(StatefulBuilder(
          builder: (shCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Skip Editor', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Auto-skip intro & outro', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  )),
                  Switch(
                    value: _skipEditorEnabled,
                    onChanged: (v) { setState(() => _skipEditorEnabled = v); setSt(() {}); _scheduleSavePrefs(); },
                    activeColor: Colors.white,
                  ),
                ]),
                const SizedBox(height: RaddSpace.md),
                const Text('INTRO', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _introStart = _position); setSt(() {}); _scheduleSavePrefs(); _showInfoSnackbar('Intro start: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: RaddRadius.smRadius),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('Start', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_introStart != null ? _formatDuration(_introStart!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: RaddSpace.sm),
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _introEnd = _position); setSt(() {}); _scheduleSavePrefs(); _showInfoSnackbar('Intro end: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: RaddRadius.smRadius),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('End', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_introEnd != null ? _formatDuration(_introEnd!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: RaddSpace.sm),
                  GestureDetector(
                    onTap: () { setState(() { _introStart = null; _introEnd = null; }); setSt(() {}); _scheduleSavePrefs(); },
                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text('OUTRO', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _outroStart = _position); setSt(() {}); _scheduleSavePrefs(); _showInfoSnackbar('Outro skip from: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: RaddRadius.smRadius),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('Skip from', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_outroStart != null ? _formatDuration(_outroStart!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: RaddSpace.sm),
                  GestureDetector(
                    onTap: () { setState(() => _outroStart = null); setSt(() {}); _scheduleSavePrefs(); },
                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'Tap a cell to stamp the current playback position. When enabled, playback auto-jumps past marked ranges.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),);;
    }



    // ── Layout Designer ───────────────────────────────────────────────────────
    void _showLayoutDesignerSheet(BuildContext ctx) {
      _openRightPanel(Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Player Layout', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final item in [
                ('default', Icons.dashboard_rounded,    'Default',  'Full controls, skip buttons, progress overlay'),
                ('cinema',  Icons.theaters_rounded,      'Cinema',   'Minimal chrome — skip buttons hidden until tap'),
                ('compact', Icons.fit_screen_rounded,   'Compact',  'Smaller UI — tighter padding, shorter transport row'),
              ])
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _layoutPreset = item.$1;
                      if (item.$1 == 'cinema') _showSkipBtns = false;
                      if (item.$1 == 'default' || item.$1 == 'compact') _showSkipBtns = true;
                    });
                    _scheduleSavePrefs();
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _layoutPreset == item.$1 ? Colors.white.withOpacity(0.12) : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _layoutPreset == item.$1 ? Colors.white38 : Colors.transparent),
                    ),
                    child: Row(children: [
                      Icon(item.$2, color: _layoutPreset == item.$1 ? Colors.white : Colors.white54, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.$3, style: TextStyle(color: _layoutPreset == item.$1 ? Colors.white : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                        Text(item.$4, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ])),
                      if (_layoutPreset == item.$1) const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                    ]),
                  ),
                ),
            ],
          ),
        ),);;
    }

    // ── Screenshot ────────────────────────────────────────────────────────────
    // `withSubtitles: true` uses MPV's native `screenshot subtitles` mode
    // (burns in whatever subs/overlays are currently rendered) instead of
    // the default `screenshot video` (clean frame only). Long-press the
    // screenshot shortcut to capture with subtitles.
    Future<void> _takeScreenshot({bool withSubtitles = false}) async {
      try {
        final dir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final baseName = 'RaddFlix_$ts';
        _np.setProperty('screenshot-template', '${dir.path}/$baseName');
        await _np.command(['screenshot', withSubtitles ? 'subtitles' : 'video']);
        await Future.delayed(const Duration(milliseconds: 700));
        final pngFile = File('${dir.path}/$baseName.png');
        if (pngFile.existsSync()) {
          final bytes = Uint8List.fromList(pngFile.readAsBytesSync());
          final result = await SaverGallery.saveImage(
            bytes,
            fileName: '$baseName.png',
            androidRelativePath: 'Pictures/RaddFlix',
            skipIfExists: false,
            quality: 95,
          );
          _showInfoSnackbar(result.isSuccess
              ? (withSubtitles ? '📷 Screenshot (with subtitles) saved' : '📷 Screenshot saved to gallery')
              : 'Screenshot save failed');
        } else {
          _showInfoSnackbar('Screenshot captured — check mpv output folder');
        }
      } catch (e) {
        _showInfoSnackbar('Screenshot failed: $e');
      }
    }

    // ── Watch Party ───────────────────────────────────────────────────────────
    void _showWatchPartyDialog(BuildContext ctx) {
      WatchPartySheet.show(
        ctx,
        contentId: _currentFileId,
        accentColor: _accentColor,
        onJoined: _onWatchPartyJoined,
      );
    }

    void _onWatchPartyJoined(WatchPartyRoom room) {
      setState(() => _watchPartyRoom = room);
      _watchPartySub?.cancel();
      _watchPartySub = WatchPartyService.instance.roomStream.listen(_onWatchPartyRoomUpdate);
    }

    void _onWatchPartyRoomUpdate(WatchPartyRoom? room) {
      if (!mounted) return;
      setState(() => _watchPartyRoom = room);
      if (room == null) return;
      // Guest: respond to host sync commands
      final isHost = room.hostId == WatchPartyService.instance.myId;
      if (!isHost) {
        final hostPosDiff = (_position.inMilliseconds - room.hostPosition.inMilliseconds).abs();
        if (hostPosDiff > 2000) _player.seek(room.hostPosition);
        if (room.isPlaying && !_playing) _player.play();
        if (!room.isPlaying && _playing) _player.pause();
      }
    }

    void _onVoiceCommand(VoiceCommand cmd) {
      if (!mounted) return;
      String label = '';
      switch (cmd) {
        case VoiceCommand.play:
        case VoiceCommand.togglePlay:
          _player.playOrPause();
          label = _playing ? '🎤 Pause' : '🎤 Play';
        case VoiceCommand.pause:
          _player.pause();
          label = '🎤 Pause';
        case VoiceCommand.mute:
          _toggleMute();
          label = '🎤 Mute';
        case VoiceCommand.screenshot:
          _takeScreenshot();
          label = '🎤 Screenshot';
        case VoiceCommand.nextEpisode:
          if (_hasNext) { _playEpisodeAt(_currentEpIdx + 1); label = '🎤 Next Episode'; }
        case VoiceCommand.speedUp:
          _cycleSpeed();
          label = '🎤 Speed Up';
        case VoiceCommand.speedDown:
          final idx = _speeds.indexOf(_speed);
          if (idx > 0) { _setSpeed(_speeds[idx - 1]); label = '🎤 Speed: ${_speeds[idx-1]}×'; }
        case VoiceCommand.forward:
          _seekRelative(30);
          label = '🎤 Forward 30s';
        case VoiceCommand.back:
          _seekRelative(-30);
          label = '🎤 Back 30s';
        default:
          break;
      }
      if (label.isNotEmpty) {
        _voiceCmdTimer?.cancel();
        setState(() => _lastVoiceCmd = label);
        _voiceCmdTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _lastVoiceCmd = '');
        });
      }
    }

    void _openSidebarCustomizer() {
      final panel = _SidebarCustomizerPanel(
        currentOrder: List<String>.from(_sidebarOrder),
        allIds: List<String>.from(_allSidebarIds),
        onOrderChanged: (newOrder) {
          setState(() => _sidebarOrder = newOrder);
          _scheduleSavePrefs();
        },
      );
      _openPanel(panel: panel, title: 'Sidebar Shortcuts', widthFactor: 0.40, maxHeightFraction: 0.90);
    }

    void _openSettingsPanel() {
      final panel = _SettingsPanel(
        showRemainingTime: _showRemainingTime,
        keepScreenOn: _keepScreenOn,
        skipInterval: _skipInterval,
        onShowRemainingChanged: (v) { setState(() => _showRemainingTime = v); _scheduleSavePrefs(); },
        onKeepScreenChanged: (v) {
          setState(() => _keepScreenOn = v);
          if (v) WakelockPlus.enable(); else WakelockPlus.disable();
          _scheduleSavePrefs();
        },
        onSkipIntervalChanged: (v) { setState(() => _skipInterval = v); _scheduleSavePrefs(); },
        seekSwipeSec: _seekSwipeSec,
        onSeekSwipeSpeedChanged: (v) { setState(() => _seekSwipeSec = v); _scheduleSavePrefs(); },
        accentColorIdx: _accentColorIdx,
        progressBarStyle: _progressBarStyle,
        onAccentColorChanged: (i) { setState(() => _accentColorIdx = i); _scheduleSavePrefs(); },
        onProgressBarStyleChanged: (s) { setState(() => _progressBarStyle = s); _scheduleSavePrefs(); },
        backgroundAudio: _backgroundAudio,
        onBackgroundAudioChanged: (v) { setState(() => _backgroundAudio = v); _scheduleSavePrefs(); },
        nightModeEnabled: _nightModeEnabled,
        nightWarmth: _nightWarmth,
        onNightModeToggle: (v) { setState(() => _nightModeEnabled = v); _scheduleSavePrefs(); },
        onNightWarmthChanged: (v) { setState(() => _nightWarmth = v); _scheduleSavePrefs(); },
        showClockInTitle: _showClockInTitle,
        onClockToggle: (v) {
          setState(() { _showClockInTitle = v; _clockStr = _fmtClock(); });
          _scheduleSavePrefs();
        },
        initialBrightness: _brightness,
        onShowSkipBtnsChanged: (v) { setState(() => _showSkipBtns = v); _scheduleSavePrefs(); }, // J2
        onShowPrevNextBtnsChanged: (v) { setState(() => _showPrevNextBtns = v); _scheduleSavePrefs(); }, // J2
        onShowSeekPositionChanged: (v) { setState(() => _showSeekPositionLabel = v); _scheduleSavePrefs(); }, // J2
        showSkipBtns: _showSkipBtns,
        showPrevNextBtns: _showPrevNextBtns,
        showSeekPosition: _showSeekPositionLabel,
        onRotateVideo: () { Navigator.of(context).pop(); _rotateVideo(); },
        doubleTapSeekEnabled: _doubleTapSeekEnabled,
        longPressSpeedEnabled: _longPressSpeedEnabled,
        swipeSeekEnabled: _swipeSeekEnabled,
        swipeBVEnabled: _swipeBVEnabled,
        onDoubleTapSeekChanged: (v) { setState(() => _doubleTapSeekEnabled = v); _scheduleSavePrefs(); },
        onLongPressSpeedChanged: (v) { setState(() => _longPressSpeedEnabled = v); _scheduleSavePrefs(); },
        onSwipeSeekChanged: (v) { setState(() => _swipeSeekEnabled = v); _scheduleSavePrefs(); },
        onSwipeBVChanged: (v) { setState(() => _swipeBVEnabled = v); _scheduleSavePrefs(); },
        onVideoInfo: _showVideoInfoDialog,
        voiceCommandsEnabled: _voiceCommandsEnabled,
        onVoiceCommandsChanged: (v) async {
          if (v) {
            final granted = await VoiceCommandsService.instance.requestPermission();
            if (!granted) {
              _showInfoSnackbar('Microphone permission required for voice commands');
              return;
            }
            VoiceCommandsService.instance.start();
            _voiceSub = VoiceCommandsService.instance.commandStream.listen(_onVoiceCommand);
            // Fix #6: STT engine is not yet wired — be transparent about it.
            _showInfoSnackbar('🎤 Voice commands are in development — stay tuned!');
          } else {
            _voiceSub?.cancel();
            VoiceCommandsService.instance.stop();
          }
          setState(() => _voiceCommandsEnabled = v);
          _scheduleSavePrefs();
        },
      );
      _openPanel(panel: panel, title: 'Settings', widthFactor: 0.42, maxHeightFraction: 0.90);
    }

    // Feature 24: Picture-in-Picture
  void _enterPiP() {
    // On Android, trigger PiP mode via platform channel
    const MethodChannel('com.raddflix.app/pip')
        .invokeMethod('enterPiP')
        .catchError((_) {
      _showInfoSnackbar('Picture-in-Picture not supported on this device.');
    });
  }


    // Fix #DUB-01: shown when setLanguage() returns LANG_MISSING_DATA (-1) or
    // LANG_NOT_SUPPORTED (-2). Provides an "Install" action that deep-links to
    // the Android TTS settings page so the user can download the voice pack.

    // ═══════════════════════════════════════════════════════════════════════════
    //  Episode sheet
    // ═══════════════════════════════════════════════════════════════════════════

    void _showEpisodeSheet() {
      _openRightPanel(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              const Expanded(child: Text('Episodes',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _eps.length,
              itemBuilder: (_, i) {
                final ep = _eps[i];
                final label = ep['label'] as String? ??
                    ep['title'] as String? ?? 'Episode ${i + 1}';
                final isCurrent = i == _currentEpIdx;
                return ListTile(
                  dense: true,
                  title: Text(label,
                      style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      )),
                  trailing: isCurrent
                      ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _playEpisodeAt(i);
                  },
                );
              },
            ),
          ),
        ],
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Utility
    // ═══════════════════════════════════════════════════════════════════════════

    String _formatDuration(Duration d) {
      if (d.isNegative) d = Duration.zero;
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }
  }
  

  // ═════════════════════════════════════════════════════════════════════════════
  //  Horizontal Seek Bar Painter
  // ═════════════════════════════════════════════════════════════════════════════

  class _HorizontalSeekPainter extends CustomPainter {
    final double progress;
    final double buffered;
    final Duration? abA;
    final Duration? abB;
    final Duration duration;
    final int style;
    final Color accentColor;

    _HorizontalSeekPainter({
      required this.progress,
      this.buffered = 0.0,
      this.abA,
      this.abB,
      this.duration = Duration.zero,
      this.style = 0,
      this.accentColor = const Color(0xFFE8950A),
    });

    @override
    void paint(Canvas canvas, Size size) {
      final cy = size.height / 2;
      // P14: progress bar style — 0=slim(3px), 1=thick(5px), 2=gradient(3px accent)
      final trackH = style == 1 ? 5.0 : 3.0;
      final progressColor = style == 2 ? accentColor : Colors.white;

      final trackPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = trackH
        ..strokeCap = StrokeCap.round;

      final progressPaint = Paint()
        ..color = progressColor
        ..strokeWidth = trackH
        ..strokeCap = StrokeCap.round;

      // Track (background)
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);

      // Buffered region — light gray between played and buffer end
      if (buffered > 0) {
        final bufX = size.width * buffered;
        final progX0 = size.width * progress;
        if (bufX > progX0) {
          final bufPaint = Paint()
            ..color = Colors.white38
            ..strokeWidth = trackH
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(progX0, cy), Offset(bufX, cy), bufPaint);
        }
      }

      // P11: A-B loop segment highlight (draw behind progress)
      if (abA != null && abB != null && duration.inMilliseconds > 0) {
        final ax = size.width * (abA!.inMilliseconds / duration.inMilliseconds);
        final bx = size.width * (abB!.inMilliseconds / duration.inMilliseconds);
        final segPaint = Paint()
          ..color = accentColor.withOpacity(0.30)
          ..strokeWidth = trackH + 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(ax, cy), Offset(bx, cy), segPaint);
      }

      // Progress
      final progX = size.width * progress;
      if (progX > 0) {
        canvas.drawLine(Offset(0, cy), Offset(progX, cy), progressPaint);
      }

      // Thumb circle
      final thumbR = style == 1 ? 9.0 : 7.0;
      final thumbPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(progX, cy), thumbR, thumbPaint);

      // P11: A marker (green dot)
      if (abA != null && duration.inMilliseconds > 0) {
        final ax = size.width * (abA!.inMilliseconds / duration.inMilliseconds);
        final aPaint = Paint()..color = const Color(0xFF34C759);
        canvas.drawCircle(Offset(ax, cy), 5, aPaint);
        // 'A' label
        final aPaintBorder = Paint()..color = Colors.black.withOpacity(0.5);
        canvas.drawCircle(Offset(ax, cy), 5, aPaintBorder..style = PaintingStyle.stroke..strokeWidth = 1);
      }

      // P11: B marker (red dot)
      if (abB != null && duration.inMilliseconds > 0) {
        final bx = size.width * (abB!.inMilliseconds / duration.inMilliseconds);
        final bPaint = Paint()..color = const Color(0xFFFF3B30);
        canvas.drawCircle(Offset(bx, cy), 5, bPaint);
      }
    }

    @override
    bool shouldRepaint(_HorizontalSeekPainter old) =>
        old.progress != progress || old.buffered != buffered ||
        old.abA != abA || old.abB != abB ||
        old.style != style || old.accentColor != accentColor;
  }

// ═════════════════════════════════════════════════════════════════════════════
//  Helper Widgets
// ═════════════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────────────
  //  _AbPinsOverlay — draggable A/B repeat pins on the seek bar
  //  Track center is at y=24 inside a 48px SizedBox (CustomPaint 28px centered).
  //  Pins hang ABOVE the track; Stack uses Clip.none so they overflow upward.
  // ─────────────────────────────────────────────────────────────────────────────

  class _AbPinsOverlay extends StatelessWidget {
    final double barWidth;
    final Duration duration;
    final Duration? abA;
    final Duration? abB;
    final Color accentColor;
    final ValueChanged<Duration> onAChanged;
    final ValueChanged<Duration> onBChanged;
    final VoidCallback onAClear;
    final VoidCallback onBClear;

    const _AbPinsOverlay({
      required this.barWidth,
      required this.duration,
      required this.abA,
      required this.abB,
      required this.accentColor,
      required this.onAChanged,
      required this.onBChanged,
      required this.onAClear,
      required this.onBClear,
    });

    @override
    Widget build(BuildContext context) {
      final durMs = duration.inMilliseconds.toDouble();
      final aFrac = abA != null ? (abA!.inMilliseconds / durMs).clamp(0.0, 1.0) : null;
      final bFrac = abB != null ? (abB!.inMilliseconds / durMs).clamp(0.0, 1.0) : null;
      final aX = aFrac != null ? aFrac * barWidth : null;
      final bX = bFrac != null ? bFrac * barWidth : null;

      return SizedBox(
        width: barWidth,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Loop region band between A and B ──────────────────────
            if (aX != null && bX != null)
              Positioned(
                left: aX,
                top: 18,
                width: (bX - aX).abs(),
                height: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            // ── A pin (green) ─────────────────────────────────────────
            if (aX != null)
              _pin(
                xPos: aX,
                label: 'A',
                color: const Color(0xFF34C759),
                fraction: aFrac!,
                onChanged: onAChanged,
                onClear: onAClear,
              ),
            // ── B pin (red-orange) ────────────────────────────────────
            if (bX != null)
              _pin(
                xPos: bX,
                label: 'B',
                color: const Color(0xFFFF453A),
                fraction: bFrac!,
                onChanged: onBChanged,
                onClear: onBClear,
              ),
          ],
        ),
      );
    }

    Widget _pin({
      required double xPos,
      required String label,
      required Color color,
      required double fraction,
      required ValueChanged<Duration> onChanged,
      required VoidCallback onClear,
    }) {
      const w = 30.0;   // touch width
      const bubbleH = 22.0;
      const stemH = 8.0;
      // Track center is at y=24. Pin (bubble+stem) hangs above it.
      // Total pin height = bubbleH + stemH = 30. So top = 24 - 30 = -6 (overflows).
      const top = 24.0 - bubbleH - stemH;

      return Positioned(
        left: xPos - w / 2,
        top: top,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            final newFrac = (fraction + d.delta.dx / barWidth).clamp(0.0, 1.0);
            onChanged(Duration(
                milliseconds: (newFrac * duration.inMilliseconds).round()));
          },
          onDoubleTap: onClear,
          child: SizedBox(
            width: w,
            height: bubbleH + stemH,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Label bubble
                Container(
                  width: bubbleH,
                  height: bubbleH,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.55),
                        blurRadius: 7,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                // Stem
                Container(
                  width: 2,
                  height: stemH,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(1),
                      bottomRight: Radius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  _RaddIconBtn — modern tap-target icon button with ink splash
  // ─────────────────────────────────────────────────────────────────────────────

  class _RaddIconBtn extends StatelessWidget {
    final IconData icon;
    final double size;
    final VoidCallback? onTap;

    const _RaddIconBtn({required this.icon, this.size = 22, this.onTap});

    @override
    Widget build(BuildContext context) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size + 20),
          child: Container(
            width: size + 20,
            height: size + 20,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: size,
                shadows: const [Shadow(blurRadius: 6, color: Colors.black45)]),
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  _BottomIconBtn — icon + label used in bottom icon row
  // ─────────────────────────────────────────────────────────────────────────────

  class _BottomIconBtn extends StatelessWidget {
    final IconData icon;
    final String label;
    final bool active;
    final VoidCallback? onTap;
    final double opacity;

    const _BottomIconBtn({
      required this.icon,
      required this.label,
      required this.active,
      this.onTap,
      this.opacity = 1.0,
    });

    @override
    Widget build(BuildContext context) {
      final color = active ? const Color(0xFFE8950A) : Colors.white;
      return Opacity(
        opacity: opacity,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 20,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black54)]),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

