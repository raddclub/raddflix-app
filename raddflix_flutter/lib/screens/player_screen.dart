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

  const PlayerScreen({
    super.key,
    required this.fileId,
    required this.title,
    this.localPath,
    this.subtitlePath,
    this.episodes,
    this.episodeIndex = 0,
    this.contentType = 'series',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
//  State
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {

  // ── MPV player ──────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _videoCtrl;

  // NativePlayer getter — NEVER create a local variable named _np
  NativePlayer get _np => _player.platform as NativePlayer;

  // ── Black-screen guards (MediaTek/Infinix) ──────────────────────────────────
  bool _videoOpened = false;

  // ── Playback state ──────────────────────────────────────────────────────────
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = false;
  Duration _buffered = Duration.zero;
  double _bufferedFraction = 0.0;
  bool _ended = false;
  String? _streamError;
  bool _isLinkLoading = false;

  // ── Current episode ─────────────────────────────────────────────────────────
  int _currentEpIdx = 0;
  String _currentFileId = '';
  String _currentTitle = '';

  // ── Controls visibility ─────────────────────────────────────────────────────
  bool _showControls = true;
  bool _panelOpen = false;
  Timer? _hideTimer;

  // ── Speed ───────────────────────────────────────────────────────────────────
  double _speed = 1.0;
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  bool _longPressFast = false;
  String _currentFramedrop = 'vo';

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
  double _audioBalance = 0.0;
  String _currentBalanceAf = '';
  String _currentChannelModeAf = '';
  int _channelModeIdx = 0; // 0=Stereo 1=Mono 2=Left only 3=Right only

  // Video rotation (0/90/180/270)
  int _videoRotation = 0;

  // Subtitle bottom margin — promoted to main state so controls-hide can shift it
  double _subBottomMarginMain = 100.0;

  // Audio effect
  int _selectedPreset = 0; // 0=Original 1=TrebleBoost 2=BassBoost 3=Clarity 4=Movie 5=Music
  List<double> _eqBands = [0, 0, 0, 0, 0]; // 60,230,910,3600,14000 Hz
  bool _eqEnabled = true;
  String _currentReverbAf = ''; // active reverb aecho string
  String _currentLabAf = '';    // active lab af chain from _AudioEffectPanel
  bool _isLocal    = false;  // true when current media is a local file (not a stream)
  bool _isFree     = false;  // true when playing free (is_free=1) content — no quota deduction
  bool _trackUsage = false;  // true only for non-local, non-free streaming
  Timer? _usageTimer;        // 30-second heartbeat to log streamed bytes
  // Lab state (persisted so panel reopens restore state)
  bool _labVocal = false;
  bool _labDialogue = false;
  bool _labNorm = false;
  bool _labBass = false;
  double _labBassLevel = 0.5;
  String _reverbPreset = 'None';

  // Subtitle
  double _subSync = 0.0; // seconds
  double _subSpeed = 1.0; // 0.5..2.0
  String? _currentSubFile;

  // Audio
  double _audioSync = 0.0;
  bool _useSWDecoder = false;
  String _currentAudioCodec = '';

  // ── AI Dub state (Phase 59) ──────────────────────────────────────────────
  String? _dubbedWavPathUr;     // cached path for Urdu dub WAV
  String? _dubbedWavPathHi;     // cached path for Hindi dub WAV
  bool   _isDubMode    = false;
  bool   _dubGenerating = false;
  double _dubProgress  = 0.0;   // 0.0..1.0
  int    _dubCurrentLine = 0;
  int    _dubTotalLines  = 0;
  String _dubActiveLang  = 'ur-PK';
  String _dubStatusText  = '';

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
  static const _kResumePrefix = 'resume_pos_';

  // Loop
  bool _loopEnabled = false;
  bool _isMuted = false;

  // A-B repeat (enforced natively by MPV via ab-loop-a/ab-loop-b — Dart only
  // mirrors state for the UI pins/labels, it never seeks manually anymore)
  Duration? _abA;
  Duration? _abB;
  bool _abActive = false;

  // ── Near-gapless episode transitions ─────────────────────────────────────
  // Next episode's stream link is resolved ahead of time (while the current
  // episode is still playing) so `_playEpisodeAt` can call `_player.open()`
  // immediately instead of waiting on a network round-trip for the link.
  String? _prefetchedFileId;
  String? _prefetchedStreamUrl;
  bool _prefetchInFlight = false;
  bool _prefetchTriggeredForEp = false;

  // ── Sprint 2 — new state vars ────────────────────────────────────────────────
  // End action (what happens when video finishes)
  String _endAction = 'play_next'; // play_next | loop | stop | ask

  // Silence skip
  bool _silenceSkipEnabled = false;
  double _silenceSkipThreshold = 1.5; // seconds

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

  // Silence skip — in merged AF pipeline flag
  bool _silenceInPipeline = false;

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

  // ── Subscriptions ───────────────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  // ── Orientation ─────────────────────────────────────────────────────────────
  // 0=Auto 1=ForceLandscape 2=ForcePortrait 3=ForceLandscapeReverse
  int _orientMode = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;

  // ── Watch position ──────────────────────────────────────────────────────────
  Timer? _posTimer;

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

  // ── P3: Auto-retry countdown ─────────────────────────────────────────────────
  Timer? _autoRetryTimer;
  int _autoRetryCountdown = 0;

  // ── P9: Seek preview label (shown above seek bar during drag) ────────────────
  String _seekPreviewLabel = '';

  // ── Perf: throttle position setState to max 2×/sec ──────────────────
  int _lastPositionMs = -1;

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
  void _startUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_trackUsage && _playing && mounted) {
        // Estimate quality from video width (1920→1080p, 1280→720p, 854→480p, else→360p)
        final w = _player.state.width ?? 0;
        final quality = w >= 1920 ? '1080p' : w >= 1280 ? '720p' : w >= 854 ? '480p' : '360p';
        UsageService.addWatchSession(seconds: 30, quality: quality).ignore();
      }
    });
  }

  void _stopUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Player init
  // ═══════════════════════════════════════════════════════════════════════════

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'RaddFlix',
        logLevel: MPVLogLevel.error,
      ),
    );

    // CRITICAL: androidAttachSurfaceAfterVideoParameters: false
    _videoCtrl = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    _subs.addAll([
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
        // Usage tracking: start/stop 30-second heartbeat when play state changes
        if (_trackUsage) {
          if (v) _startUsageTimer();
          else   _stopUsageTimer();
        }
        // Watch Party: broadcast play/pause state to guests (host only)
        if (_watchPartyRoom != null) {
          final isHost = _watchPartyRoom!.hostId == WatchPartyService.instance.myId;
          if (isHost) WatchPartyService.instance.sendSync(isPlaying: v, position: _position);
        }
      }),
      _player.stream.position.listen((v) {
        if (!mounted) return;
        _position = v;
        _checkSkipEditor();
        // A-B loop is now enforced natively by MPV (ab-loop-a/ab-loop-b) —
        // no manual seek here anymore, which removes a per-tick Duration
        // comparison + seek call from the hottest listener in the player.
        // Fire the next-episode prefetch once, ~20s before this episode ends,
        // so the transition can skip the network round-trip entirely.
        if (!_prefetchTriggeredForEp &&
            _hasNext &&
            _duration.inMilliseconds > 0 &&
            (_duration - v).inSeconds <= 20 &&
            (_duration - v).inSeconds >= 0) {
          _prefetchTriggeredForEp = true;
          _prefetchNextEpisode();
        }
        // Throttle UI rebuild to 2×/sec — seek bar stays smooth
        final ms = v.inMilliseconds;
        if ((ms - _lastPositionMs).abs() >= 500) {
          _lastPositionMs = ms;
          setState(() {});
        }
      }),
      _player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }),
      _player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }),
      _player.stream.buffer.listen((v) {
        if (mounted) setState(() {
          _buffered = v;
          _bufferedFraction = _duration.inMilliseconds > 0
              ? (_buffered.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
        });
      }),
      _player.stream.completed.listen((v) {
        if (v && mounted) {
          setState(() => _ended = true);
          _onVideoCompleted();
        }
      }),
      _player.stream.error.listen((e) {
        DebugLogger.logError('PLAYER', 'MPV error', e);
        if (mounted && !_playing) {
          setState(() => _streamError = 'Playback error. Please retry.');
        }
      }),
      _player.stream.tracks.listen((tracks) {
        if (mounted) setState(() {
          _audioTracks = tracks.audio;
          _subtitleTracks = tracks.subtitle;
        });
        // P57-05: EAC3/DTS auto SW decoder fallback
        // media_kit_libs_android_video bundles full ffmpeg so EAC3 decodes fine,
        // but Android MediaCodec (hwdec=auto-safe) can silently fail on EAC3/DTS
        // on MediaTek devices. Auto-detect and switch to SW to be safe.
        if (mounted && tracks.audio.any((t) => t.id != null && int.tryParse(t.id!) != null)) {
          Future.delayed(const Duration(seconds: 1), () async {
            if (!mounted) return;
            try {
              final codec = (await _np.getProperty('audio-codec-name') ?? '').toLowerCase();
              const advCodecs = ['eac3', 'ac3', 'dts', 'dca', 'truehd', 'mlp'];
              final detected = advCodecs.firstWhere((c) => codec.contains(c), orElse: () => '');
              if (mounted) setState(() => _currentAudioCodec = detected.isNotEmpty ? detected : codec);
              if (detected.isNotEmpty && !_useSWDecoder) {
                try { _np.setProperty('hwdec', 'no'); } catch (_) {}
                if (mounted) setState(() => _useSWDecoder = true);
                final name = {
                  'eac3': 'E-AC-3 (Dolby Digital+)', 'ac3': 'AC-3 (Dolby Digital)',
                  'dts': 'DTS', 'dca': 'DTS-HD', 'truehd': 'Dolby TrueHD', 'mlp': 'MLP/TrueHD',
                }[detected] ?? detected.toUpperCase();
                _showInfoSnackbar('$name — using software decoder for full fidelity');
              }
            } catch (_) {}
          });
        }
      }),
      _player.stream.track.listen((track) {
        if (mounted) setState(() {
          _selectedAudio = track.audio;
          _selectedSubtitle = track.subtitle;
        });
      }),
      // Video dimension listeners — drive auto-orientation
      _player.stream.width.listen((w) {
        if (w != null && w > 0 && mounted) {
          setState(() => _videoWidth = w);
          _applyAutoOrientation();
        }
      }),
      _player.stream.height.listen((h) {
        if (h != null && h > 0 && mounted) {
          setState(() => _videoHeight = h);
          _applyAutoOrientation();
        }
      }),
    ]);

    _posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());

    // Silence skip: subscribe to MPV log for silencedetect events
    try {
      _np.observeProperty('log-message', (String msg) async {
        if (!_silenceInPipeline || !mounted) return;
        if (msg.contains('[silencedetect') && msg.contains('silence_end:')) {
          final endMatch = RegExp(r'silence_end:\s*([\d.]+)').firstMatch(msg);
          final durMatch = RegExp(r'silence_duration:\s*([\d.]+)').firstMatch(msg);
          if (endMatch != null && durMatch != null) {
            final endSec = double.tryParse(endMatch.group(1)!) ?? 0.0;
            final durSec = double.tryParse(durMatch.group(1)!) ?? 0.0;
            if (durSec >= _silenceSkipThreshold && endSec > 0) {
              final now = _position.inMilliseconds / 1000.0;
              if ((now - endSec).abs() < 3.0) {
                _player.seek(Duration(milliseconds: (endSec * 1000).round()));
                if (mounted) _showInfoSnackbar('Skipped ${durSec.toStringAsFixed(1)}s silence');
              }
            }
          }
        }
      });
    } catch (_) {
      // observeProperty may not be available on all media_kit versions — fail silently
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openMedia(_currentFileId, localPath: widget.localPath);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Stream resolution + open
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _openMedia(String fileId, {String? localPath}) async {
    _currentFileId = fileId.isNotEmpty ? fileId : _currentFileId;

    final isLocal = (localPath != null && localPath.isNotEmpty) ||
        (fileId.startsWith('/') || fileId.startsWith('content://'));
    _isLocal = isLocal;

    // ── Usage tracking setup ─────────────────────────────────────────────────
    // Read is_free flag passed by show_detail_screen in route args.
    // Local files (downloaded or user's own) never count toward quota.
    // BUG-M05 fix: only re-read is_free from route args on the very first open.
    // On retries (_videoOpened == true), _isFree is already correctly set:
    //   • initial episode: set from route args on first open (below)
    //   • navigated episode: set by _openMediaForEpisode (C02 fix)
    // Re-reading route args on retry would revert to the INITIAL episode's is_free,
    // wrongly treating a navigated paid episode as free (or vice-versa).
    if (!isLocal) {
      if (!_videoOpened) {
        // First open — trust route args which show_detail sets correctly
        final routeArgsFree = ModalRoute.of(context)?.settings.arguments as Map?;
        final isFreeArg     = routeArgsFree?['is_free'];
        _isFree     = isFreeArg == true || isFreeArg == 1;
        _trackUsage = !_isFree;
      }
      // else: retry or re-open — keep _isFree/_trackUsage as already set
    } else {
      _isFree     = false;
      _trackUsage = false;
    }
    _stopUsageTimer(); // cancel any leftover timer from previous file

    // ── Subscription gate (Layer 2 — defense in depth) ──────────────────────
    // Blocks non-free streams for users who have no active subscription.
    // Layer 1 is show_detail_screen; this catches any deep-link or code bypass.
    // BUG-2 fix: prefer subscriptionProvider.status (fresh) over stale authProvider
    // cache; fall back to cache only when subscriptionProvider hasn't loaded yet.
    if (_trackUsage && mounted) {
      final authState = ref.read(authProvider);
      final subStatus = ref.read(subscriptionProvider).status;
      final isSubscribed = authState.user != null &&
          !(authState.user!.isGuest) &&
          (subStatus != null ? subStatus.isActive : authState.user!.subscription?.isActive == true);
      if (!isSubscribed) {
        if (mounted) {
          setState(() { _isLinkLoading = false; });
          Navigator.of(context).pushReplacementNamed(AppRoutes.subscription);
        }
        return;
      }
    }
    // ────────────────────────────────────────────────────────────────────────

    // Quota gate — block play if monthly limit reached (streaming non-free only)
    if (_trackUsage && mounted) {
      final quota = await UsageService.getCachedQuota();
      if (quota['allowed'] == false || quota['is_exceeded'] == true) {
        // BUG-H01 fix: pass real quota numbers so the screen can show a filled progress bar
        // BUG-3 fix: server quota dict uses monthly_used_gb / monthly_limit_gb keys,
        // not used_gb / limit_gb — previously QuotaFullScreen always showed 0%.
        if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.quotaFull, arguments: {
          'used_gb':   quota['monthly_used_gb'],
          'limit_gb':  quota['monthly_limit_gb'],
          'plan_name': quota['plan_name'],
          'resets_at': quota['resets_at'],
        });
        return;
      }
    }
    // ────────────────────────────────────────────────────────────────────────

    final effectivePath = localPath ?? (isLocal ? fileId : null);

    if (effectivePath != null) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true;
      final _subForThisOpen = _currentSubFile; // capture before async open
      await _player.open(Media(effectivePath));
      _applyCompanionSub(_subForThisOpen); // load companion SRT after media opens
      await _restoreWatchPos();
      _startSavePositionTimer();
    _loadSkipEditorPrefs();
      if (mounted) setState(() { _isLinkLoading = false; });
      _scheduleHide();
      return;
    }

    if (mounted) setState(() { _streamError = null; _isLinkLoading = true; _ended = false; _position = Duration.zero; });

    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map?;
    final inlineShareUrl = routeArgs?['stream_url'] as String?;

    String? shareUrl;
    String? targetFilename;
    int remoteId = 0;

    try {
      if (fileId.isNotEmpty) {
        final info = await LocalDb.getShareInfo(fileId);
        shareUrl = info['share_url'] as String?;
        targetFilename = info['filename'] as String?;
        remoteId = info['remote_id'] as int? ?? 0;
      }

      if ((shareUrl == null || shareUrl.isEmpty) &&
          inlineShareUrl != null && inlineShareUrl.isNotEmpty) {
        shareUrl = await LocalDb.decodeShareUrl(inlineShareUrl);
      }

      if ((shareUrl == null || shareUrl.isEmpty) && fileId.isNotEmpty) {
        shareUrl = await CatalogApi.getShareUrl(fileId);
      }

      if (shareUrl != null && shareUrl.isNotEmpty) {
        final cacheKey = fileId.isNotEmpty ? fileId : 'share_${shareUrl.hashCode}';
        final link = await JazzDriveService.getStreamLink(
          cacheKey, shareUrl,
          targetFilename: targetFilename,
          remoteId: remoteId,
        );
        _cancelAutoRetry();
        if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
        _videoOpened = true;
        final _subForThisOpen = _currentSubFile; // capture before async open
        await _player.open(Media(link.streamUrl));
        _applyCompanionSub(_subForThisOpen); // load companion SRT after media opens
        await _restoreWatchPos();
      _startSavePositionTimer();
        _scheduleHide();
        return;
      }
    } catch (e) {
      DebugLogger.logError('PLAYER', 'Stream resolution failed', e);
      if (mounted) {
        setState(() {
          _isLinkLoading = false;
          _streamError = _friendlyError(e.toString());
        });
        _startAutoRetry();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLinkLoading = false;
        _streamError = 'No stream link found. Please sync your library in Settings → Sync.';
      });
      _startAutoRetry();
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Jazz') || raw.contains('SIM') || raw.contains('401')) {
      return 'Jazz SIM required to stream. Connect to Jazz mobile data.';
    }
    if (raw.contains('timeout') || raw.contains('SocketException')) {
      return 'Connection timed out. Check your internet connection.';
    }
    return 'Could not load stream. Please retry.';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Episode navigation
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get _eps => widget.episodes ?? [];
  bool get _hasPrev => _currentEpIdx > 0;
  bool get _hasNext => _currentEpIdx < _eps.length - 1;

  void _playEpisodeAt(int idx) {
    if (idx < 0 || idx >= _eps.length) return;
    final ep = _eps[idx];
    _saveWatchPos();
    setState(() {
      _currentEpIdx = idx;
      _currentFileId = ep['file_id'] as String? ?? '';
      _currentTitle = ep['label'] as String? ?? ep['title'] as String? ?? widget.title;
      _ended = false;
      _position = Duration.zero;
      // Track the companion SRT for the incoming episode (null clears previous one).
      _currentSubFile = ep['subtitle_path']?.toString();
      // Reset pinch zoom — carry-over zoom from the previous episode is
      // disorienting and the MPV video-zoom property is also cleared below.
      _pinchScale = 1.0;
      _pinchBaseScale = 1.0;
      _showZoomIndicator = false;
      // A-B loop never carries over to a new episode.
      _abA = null;
      _abB = null;
      _abActive = false;
      // BUG-SUB-CARRY-01: a manually-picked subtitle/secondary-subtitle track ID
      // (e.g. sid=3) is an MPV *property*, not per-file state — it survives a
      // loadfile/open of the next episode and gets blindly re-applied to that
      // file's track list, which can pick the wrong (or a nonexistent) track.
      // Reset the Dart-side selection here; the native `sid`/`secondary-sid`
      // properties are reset to 'auto' just below so MPV re-picks the new
      // episode's default/forced track once it loads.
      _selectedSubtitle = null;
      _selectedSecondSub = null;
      // Reset the prefetch-trigger latch for the new episode; a stale
      // `_prefetchedFileId` from the previous one is fine — it's simply
      // ignored below if it doesn't match the episode we're opening.
      _prefetchTriggeredForEp = false;
    });
    // Reset MPV native zoom + A-B loop alongside Flutter state so they stay in sync.
    try { _np.setProperty('video-zoom', '0'); } catch (_) {}
    try {
      _np.setProperty('ab-loop-a', 'no');
      _np.setProperty('ab-loop-b', 'no');
    } catch (_) {}
    // BUG-SUB-CARRY-01: reset subtitle track selection to auto so MPV re-picks
    // the new episode's own default track instead of reapplying a stale index.
    try {
      _np.setProperty('sid', 'auto');
      _np.setProperty('secondary-sid', 'no');
    } catch (_) {}
    _openMediaForEpisode(ep,
      localPath: (ep['local_path'] ?? ep['localPath'] ?? ep['download_path']) as String?,
      shareUrl: (ep['share_url'] ?? ep['shareUrl']) as String?,
    );
  }

  // ── Native A-B loop sync ──────────────────────────────────────────────
  // Pushes the current `_abA`/`_abB` Dart state into MPV's own ab-loop-a /
  // ab-loop-b / ab-loop-count properties. Once both points are set, MPV
  // enforces the loop natively inside the playback engine (sample-accurate,
  // zero Dart overhead) instead of Flutter polling `position` every tick and
  // calling `_player.seek()` — lighter, smoother, and immune to any Dart-side
  // jank near the loop boundary.
  void _syncNativeAbLoop() {
    try {
      _np.setProperty('ab-loop-a', _abA != null
          ? (_abA!.inMilliseconds / 1000).toStringAsFixed(3) : 'no');
      _np.setProperty('ab-loop-b', _abB != null
          ? (_abB!.inMilliseconds / 1000).toStringAsFixed(3) : 'no');
      _np.setProperty('ab-loop-count', (_abA != null && _abB != null) ? 'inf' : '1');
    } catch (_) {}
  }

  // ── Prefetch next episode's stream link ahead of time ───────────────────
  // Mirrors the remote-link resolution steps in `_openMediaForEpisode` but
  // only resolves the URL — it never touches the player. Safe to call
  // repeatedly; guarded by `_prefetchInFlight` and a match check on the
  // target file id so it never resolves the same episode twice or races
  // itself. Local/offline episodes need no prefetch (opening them is
  // already instant), so this is a no-op for those.
  Future<void> _prefetchNextEpisode() async {
    if (_prefetchInFlight || !_hasNext) return;
    final next = _eps[_currentEpIdx + 1];
    final fileId = next['file_id'] as String? ?? '';
    final localPath = (next['local_path'] ?? next['localPath'] ?? next['download_path']) as String?;
    if (fileId.isEmpty) return;
    if ((localPath != null && localPath.isNotEmpty) ||
        fileId.startsWith('/') || fileId.startsWith('content://')) {
      return; // local files open instantly — nothing to prefetch
    }
    if (_prefetchedFileId == fileId && _prefetchedStreamUrl != null) return;
    _prefetchInFlight = true;
    try {
      String? resolvedShare = (next['share_url'] ?? next['shareUrl']) as String?;
      String? targetFilename;
      int remoteId = 0;
      final info = await LocalDb.getShareInfo(fileId);
      final dbShare = info['share_url'] as String?;
      if (dbShare != null && dbShare.isNotEmpty) resolvedShare = dbShare;
      targetFilename = info['filename'] as String?;
      remoteId = info['remote_id'] as int? ?? 0;

      if (resolvedShare != null &&
          (resolvedShare.startsWith('RF1:') || resolvedShare.startsWith('RF2:'))) {
        resolvedShare = await LocalDb.decodeShareUrl(resolvedShare);
      }
      if ((resolvedShare == null || resolvedShare.isEmpty) && fileId.isNotEmpty) {
        resolvedShare = await CatalogApi.getShareUrl(fileId);
      }
      if (resolvedShare != null && resolvedShare.isNotEmpty) {
        final cacheKey = fileId.isNotEmpty ? fileId : 'share_${resolvedShare.hashCode}';
        final link = await JazzDriveService.getStreamLink(
          cacheKey, resolvedShare,
          targetFilename: targetFilename,
          remoteId: remoteId,
        );
        // Only keep the result if we're still on the episode that scheduled
        // this prefetch (user may have navigated elsewhere while awaiting).
        if (mounted && _hasNext && _eps[_currentEpIdx + 1]['file_id'] == fileId) {
          _prefetchedFileId = fileId;
          _prefetchedStreamUrl = link.streamUrl;
        }
      }
    } catch (e) {
      // Silent by design — prefetch is a pure optimization. A failure here
      // just means the normal (slower) resolution path runs when the user
      // actually advances to this episode.
      DebugLogger.logError('PLAYER', 'Prefetch failed', e);
    } finally {
      _prefetchInFlight = false;
    }
  }

  Future<void> _openMediaForEpisode(Map<String, dynamic> ep,
      {String? localPath, String? shareUrl}) async {
    final fileId = ep['file_id'] as String? ?? '';

    // ── BUG-C02 fix: update _isFree/_trackUsage per episode ─────────────────
    // Previously these were only set in _openMedia() on first load and never
    // updated during in-player episode navigation, causing wrong quota tracking:
    //   ep1=free  → ep2=paid : _isFree stuck true  → ep2 never counted (revenue leak)
    //   ep1=paid  → ep2=free : _isFree stuck false → ep2 wrongly counted (user penalised)
    final _isLocalEp = (localPath != null && localPath.isNotEmpty) ||
        fileId.startsWith('/') || fileId.startsWith('content://');
    if (!_isLocalEp) {
      final isFreeArg = ep['is_free'];
      _isFree     = isFreeArg == true || isFreeArg == 1;
      _trackUsage = !_isFree;
    } else {
      _isFree     = false;
      _trackUsage = false;
    }
    _stopUsageTimer(); // cancel previous episode's heartbeat before any gate check

    // ── BUG-C01 fix: subscription + quota gates for in-player episode nav ────
    // _openMedia() has these gates for the initial load. _openMediaForEpisode()
    // had none — pressing Next Episode bypassed ALL access control entirely.
    // BUG-2 fix: prefer subscriptionProvider.status (fresh) over stale authProvider
    // cache; fall back to cache only when subscriptionProvider hasn't loaded yet.
    if (_trackUsage && mounted) {
      final authState = ref.read(authProvider);
      final subStatus = ref.read(subscriptionProvider).status;
      final isSubscribed = authState.user != null &&
          !(authState.user!.isGuest) &&
          (subStatus != null ? subStatus.isActive : authState.user!.subscription?.isActive == true);
      if (!isSubscribed) {
        if (mounted) {
          setState(() { _isLinkLoading = false; });
          Navigator.of(context).pushReplacementNamed(AppRoutes.subscription);
        }
        return;
      }
    }
    if (_trackUsage && mounted) {
      final quota = await UsageService.getCachedQuota();
      if (quota['allowed'] == false || quota['is_exceeded'] == true) {
        // BUG-H01 fix: pass real quota numbers to QuotaFullScreen
        // BUG-3 fix: server quota dict uses monthly_used_gb / monthly_limit_gb keys.
        if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.quotaFull, arguments: {
          'used_gb':   quota['monthly_used_gb'],
          'limit_gb':  quota['monthly_limit_gb'],
          'plan_name': quota['plan_name'],
          'resets_at': quota['resets_at'],
        });
        return;
      }
    }
    // ────────────────────────────────────────────────────────────────────────

    if (localPath != null && localPath.isNotEmpty) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true;
      final _subForThisOpen = _currentSubFile; // capture before async open
      await _player.open(Media(localPath));
      _applyCompanionSub(_subForThisOpen); // load companion SRT after media opens
      await _restoreWatchPos();
      _startSavePositionTimer();
      _scheduleHide();
      return;
    }

    // Handle content:// or absolute path fileIds as local
    if (fileId.startsWith('/') || fileId.startsWith('content://')) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true;
      final _subForThisOpen = _currentSubFile; // capture before async open
      await _player.open(Media(fileId));
      _applyCompanionSub(_subForThisOpen); // load companion SRT after media opens
      await _restoreWatchPos();
      _startSavePositionTimer();
      _scheduleHide();
      return;
    }

    if (mounted) setState(() { _streamError = null; _isLinkLoading = true; _ended = false; _position = Duration.zero; });

    // ── Near-gapless fast path ────────────────────────────────────────────
    // If this exact episode's link was already resolved by the background
    // prefetch (see `_prefetchNextEpisode`), skip straight to `_player.open`
    // — no DB lookup, no share-URL decode, no network round-trip.
    if (fileId.isNotEmpty && _prefetchedFileId == fileId && _prefetchedStreamUrl != null) {
      final fastUrl = _prefetchedStreamUrl!;
      _prefetchedFileId = null;
      _prefetchedStreamUrl = null;
      _cancelAutoRetry();
      if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
      _videoOpened = true;
      final _subForThisOpen = _currentSubFile;
      await _player.open(Media(fastUrl));
      _applyCompanionSub(_subForThisOpen);
      await _restoreWatchPos();
      _startSavePositionTimer();
      _scheduleHide();
      return;
    }

    String? resolvedShare = shareUrl;
    String? targetFilename;
    int remoteId = 0;

    try {
      if (fileId.isNotEmpty) {
        final info = await LocalDb.getShareInfo(fileId);
        final dbShare = info['share_url'] as String?;
        if (dbShare != null && dbShare.isNotEmpty) resolvedShare = dbShare;
        targetFilename = info['filename'] as String?;
        remoteId = info['remote_id'] as int? ?? 0;
      }

      if (resolvedShare != null && resolvedShare.isNotEmpty) {
        if (resolvedShare.startsWith('RF1:') || resolvedShare.startsWith('RF2:')) {
          resolvedShare = await LocalDb.decodeShareUrl(resolvedShare);
        }
      }

      if ((resolvedShare == null || resolvedShare.isEmpty) && fileId.isNotEmpty) {
        resolvedShare = await CatalogApi.getShareUrl(fileId);
      }

      if (resolvedShare != null && resolvedShare.isNotEmpty) {
        final cacheKey = fileId.isNotEmpty ? fileId : 'share_${resolvedShare.hashCode}';
        final link = await JazzDriveService.getStreamLink(
          cacheKey, resolvedShare,
          targetFilename: targetFilename,
          remoteId: remoteId,
        );
        _cancelAutoRetry();
        if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
        _videoOpened = true;
        final _subForThisOpen = _currentSubFile; // capture before async open
        await _player.open(Media(link.streamUrl));
        _applyCompanionSub(_subForThisOpen); // load companion SRT after media opens
        await _restoreWatchPos();
      _startSavePositionTimer();
        _scheduleHide();
        return;
      }
    } catch (e) {
      DebugLogger.logError('PLAYER', 'Episode stream failed', e);
      if (mounted) {
        setState(() { _isLinkLoading = false; _streamError = _friendlyError(e.toString()); });
        _startAutoRetry();
      }
      return;
    }

    if (mounted) {
      setState(() { _isLinkLoading = false; _streamError = 'No stream link found for this episode.'; });
      _startAutoRetry();
    }
  }

  void _onVideoCompleted() {
    _clearSavedPosition(_currentFileId);
    _saveWatchPos();
    if (_loopEnabled) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    // End action (only applies when loop is off)
    if (_endAction == 'loop') {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_endAction == 'stop') return; // stay on last frame
    if (_endAction == 'ask') {
      _showEndActionDialog();
      return;
    }
    // 'play_next' — auto-advance countdown
    if (_hasNext) {
      _autoAdvanceCountdown = 3;
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_ended) {
          t.cancel();
          return;
        }
        setState(() {
          if (_autoAdvanceCountdown > 1) {
            _autoAdvanceCountdown--;
          } else {
            t.cancel();
            _playEpisodeAt(_currentEpIdx + 1);
          }
        });
      });
    }
  }

  void _showEndActionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Episode Finished', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('What would you like to do?',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () { Navigator.of(ctx).pop(); _player.seek(Duration.zero); _player.play(); },
            child: const Text('Replay', style: TextStyle(color: Colors.white54)),
          ),
          if (_hasNext)
            TextButton(
              onPressed: () { Navigator.of(ctx).pop(); _playEpisodeAt(_currentEpIdx + 1); },
              child: const Text('Next Episode', style: TextStyle(color: Color(0xFF4A9EFF))),
            ),
          TextButton(
            onPressed: () { Navigator.of(ctx).pop(); Navigator.of(context).pop(); },
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Watch position
  // ═══════════════════════════════════════════════════════════════════════════

  String get _posKey {
    if (_currentFileId.isNotEmpty) return 'wp_$_currentFileId';
    final ep = _eps.isNotEmpty ? _eps[_currentEpIdx] : null;
    final lp = ep?['local_path'] as String? ?? widget.localPath ?? '';
    return 'wp_local_${lp.hashCode}';
  }

  Future<void> _saveWatchPos() async {
    final ms = _position.inMilliseconds;
    if (ms < 5000) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_posKey, ms);
    // ── Resume FAB data ───────────────────────────────────────────────────
    // Save enough context for ResumeFab on the home screen to reconstruct
    // the player route and show a meaningful card (title + progress).
    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map?;
    await prefs.setString('resume_title',        _currentTitle);
    await prefs.setString('resume_file_id',      _currentFileId);
    await prefs.setInt   ('resume_pos_ms',       ms);
    await prefs.setInt   ('resume_dur_ms',       _duration.inMilliseconds);
    await prefs.setString('resume_content_type', widget.contentType);
    // BUG-11 fix: persist is_free so ResumeFab can skip sub gate for free content.
    await prefs.setBool  ('resume_is_free',      _isFree);
    final streamUrl  = routeArgs?['stream_url'] as String?;
    final localPath  = routeArgs?['local_path']  as String?;
    final posterUrl  = routeArgs?['poster_url']  as String?
                    ?? routeArgs?['poster']      as String?;
    if (streamUrl  != null) await prefs.setString('resume_stream_url', streamUrl);
    if (localPath  != null) await prefs.setString('resume_local_path', localPath);
    if (posterUrl  != null) await prefs.setString('resume_poster_url', posterUrl);
  }

  Future<void> _restoreWatchPos() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_posKey) ?? 0;
    if (ms <= 30000 || ms >= (_duration.inMilliseconds - 10000)) return;
    // For content watched > 30s in: ask user instead of silently seeking
    if (!mounted) return;
    final cont = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Resume Playback', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Continue from ${_formatDuration(Duration(milliseconds: ms))}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Start Over', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Resume', style: TextStyle(
                color: Color(0xFFE8950A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (cont == true && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      _player.seek(Duration(milliseconds: ms));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Controls helpers
  // ═══════════════════════════════════════════════════════════════════════════

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) {
        setState(() => _showControls = false);
        _applySubtitleMargin(controlsVisible: false);
      }
    });
  }

  // Dynamically shift subtitles above the controls area so they are never
  // covered. Called whenever controls show or hide.
  // Controls bottom area is ~90px (seek bar ~32px + transport row ~48px + padding).
  /// Loads [subPath] into MPV immediately after _player.open().
  /// Callers MUST capture _currentSubFile into a local before the await open()
  /// call and pass it here — this prevents a race where rapid episode taps
  /// cause a later setState to overwrite _currentSubFile before an earlier
  /// open() completes, which would load the wrong SRT.
  void _applyCompanionSub(String? subPath) {
    if (subPath == null || subPath.isEmpty) return;
    try { _np.setProperty('sub-file', subPath); } catch (_) {}
  }

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

  Future<void> _setSpeed(double speed) async {
    final newFramedrop = speed > 1.0 ? 'decoder+vo' : 'vo';
    if (newFramedrop != _currentFramedrop) {
      _np.setProperty('framedrop', newFramedrop);
    }
    _np.setProperty('speed', speed.toStringAsFixed(4));
    if (newFramedrop != _currentFramedrop && _playing) {
      final pos = _player.state.position;
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) _player.seek(pos);
    }
    _currentFramedrop = newFramedrop;
    if (mounted) setState(() => _speed = speed);
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
  void _saveCurrentPosition() {
    _saveWatchPos(); // delegated to unified watch-pos system
  }

  void _clearSavedPosition(String fileId) {
    final _safeId = fileId.length > 80 ? fileId.hashCode.toString() : fileId;
    SharedPreferences.getInstance().then((prefs) => prefs.remove('$_kResumePrefix$_safeId'));
  }


  void _startSavePositionTimer() {
    _immersiveExitTimer?.cancel();
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());
  }

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
      _showClockInTitle = prefs.getBool('pref_clock') ?? true;
      _videoRotation = prefs.getInt('pref_vrotate') ?? 0;
      _audioBalance = prefs.getDouble('pref_balance') ?? 0.0;
      _seekSwipeSec = prefs.getDouble('pref_swipe') ?? 120.0;
      _accentColorIdx = prefs.getInt('pref_accent') ?? 0;
      _progressBarStyle = prefs.getInt('pref_pbstyle') ?? 0;
      _oneHandedMode = prefs.getBool('pref_onehanded') ?? false;
      _backgroundAudio = prefs.getBool('pref_bgaudio') ?? false;
      _keepScreenOn = prefs.getBool('pref_screenon') ?? true;
      _showRemainingTime = prefs.getBool('pref_remaining') ?? false;
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
      _channelModeIdx = prefs.getInt('pref_ch_mode') ?? 0;
      // Sprint 2 keys
      _endAction           = prefs.getString('pref_end_action') ?? 'play_next';
      _silenceSkipEnabled  = prefs.getBool('pref_silence_skip') ?? false;
      _silenceSkipThreshold= prefs.getDouble('pref_silence_thr') ?? 1.5;
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
      if (_labVocal)    labParts.add('pan=stereo|c0=c0-c1|c1=c1-c0');
      if (_labDialogue) labParts.add('equalizer=0:0:0:0:0:0:3:4:2:0');
      if (_labNorm)     labParts.add('dynaudnorm');
      if (_labBass) {
        final db = (_labBassLevel * 12).round().clamp(1, 12);
        labParts.add('equalizer=$db:$db:0:0:0:0:0:0:0:0');
      }
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
    await prefs.setInt('pref_ch_mode', _channelModeIdx);
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

  void _startAutoRetry() {
    _autoRetryTimer?.cancel();
    setState(() => _autoRetryCountdown = 30);
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _autoRetryCountdown--);
      if (_autoRetryCountdown <= 0) {
        t.cancel();
        setState(() => _streamError = null);
        _openMedia(_currentFileId);
      }
    });
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    if (mounted) setState(() => _autoRetryCountdown = 0);
  }

  void _toggleMute() {
    _isMuted = !_isMuted;
    _np.setProperty('mute', _isMuted ? 'yes' : 'no');
    if (!_isMuted && _volume > 1.0) {
      _np.setProperty('volume', (_volume * 100).clamp(100, 250).round().toString());
    }
    setState(() {});
  }

  void _toggleLoop() {
    _loopEnabled = !_loopEnabled;
    try { _np.setProperty('loop-file', _loopEnabled ? 'inf' : 'no'); } catch (_) {}
    setState(() {});
  }

  // ── Orientation control ─────────────────────────────────────────────────────

  // Calls the native Android channel to set requestedOrientation.
  // This works even when the user has system auto-rotate OFF —
  // unlike SystemChrome.setPreferredOrientations which respects that setting.
  void _setNativeOrientation(String mode) {
    const MethodChannel('com.raddflix.app/orient')
        .invokeMethod('setOrientation', {'mode': mode})
        .catchError((_) {});
  }

  void _applyAutoOrientation() {
    if (_orientMode != 0) return;
    // Smart orientation: read actual video pixel dimensions and silently force
    // the right orientation — no user action needed, works like MX Player.
    // Falls back to sensor if dimensions not yet known.
    if (_videoWidth > 0 && _videoHeight > 0) {
      if (_videoWidth >= _videoHeight) {
        // Landscape video (movies, episodes) → force landscape
        _setNativeOrientation('sensor_landscape');
      } else {
        // Portrait video (shorts, reels, vertical clips) → force portrait
        _setNativeOrientation('sensor_portrait');
      }
    } else {
      // Dimensions not yet available → allow sensor freely
      _setNativeOrientation('sensor');
    }
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
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Audio Effect / EQ
  // ═══════════════════════════════════════════════════════════════════════════

  // EQ preset gains: 10-band MPV equalizer
  // Bands: 31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz
  static const List<String> _presetNames = [
    'Original', 'Treble Boost', 'Bass Boost', 'Clarity', 'Movie', 'Music',
  ];
  static const List<List<int>> _presetGains = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],        // Original
    [0, 0, 0, 0, 0, 0, 3, 5, 7, 8],        // Treble Boost
    [8, 6, 4, 2, 0, 0, 0, 0, 0, 0],        // Bass Boost
    [0, 0, 3, 5, 7, 5, 3, 0, 0, 0],        // Clarity
    [5, 3, 0, 0, 2, 4, 6, 6, 4, 2],        // Movie
    [3, 5, 5, 2, 0, 0, 2, 4, 5, 3],        // Music
  ];

  void _applyPreset(int index) {
    final gains = _presetGains[index];
    setState(() {
      _selectedPreset = index;
      // Map 10-band preset to 5-band UI sliders (60, 230, 910, 3600, 14000 Hz)
      _eqBands = [
        gains[1].toDouble(),  // ~60Hz  → band 2 (62.5Hz)
        gains[2].toDouble(),  // ~230Hz → band 3 (125Hz)
        gains[4].toDouble(),  // ~910Hz → band 5 (500Hz)
        gains[7].toDouble(),  // ~3600Hz→ band 8 (4000Hz)
        gains[9].toDouble(),  // ~14kHz → band 10 (16000Hz)
      ];
    });
    _applyAllAf();
  }

  void _applyCustomEq() {
    if (!_eqEnabled) return;
    _applyAllAf();
  }

  // ── Merged audio-filter pipeline ─────────────────────────────────────────────
  // NEVER call _np.setProperty('af',...) directly — always go through _applyAllAf()
  // so EQ + Reverb + Lab stack correctly instead of overwriting each other.
  String _buildMergedAfString() {
    final parts = <String>[];
    // EQ chain — only if enabled and at least one band non-zero
    if (_eqEnabled) {
      final b = _eqBands;
      final g = [
        b[0].round(), b[0].round(),   // 31.25, 62.5 → 60Hz
        b[1].round(), b[1].round(),   // 125, 250 → 230Hz
        b[2].round(), b[2].round(),   // 500, 1000 → 910Hz
        b[3].round(), b[3].round(),   // 2000, 4000 → 3600Hz
        b[4].round(), b[4].round(),   // 8000, 16000 → 14000Hz
      ];
      if (g.any((v) => v != 0)) parts.add('equalizer=${g.join(':')}');
    }
    // Reverb chain (aecho)
    if (_currentReverbAf.isNotEmpty) parts.add(_currentReverbAf);
    // Lab chain (pan, dynaudnorm, etc.)
    if (_currentLabAf.isNotEmpty) parts.add(_currentLabAf);
    if (_currentChannelModeAf.isNotEmpty) parts.add(_currentChannelModeAf);
    if (_currentBalanceAf.isNotEmpty) parts.add(_currentBalanceAf);
    // Silence detection — must be last (detection filter, not audio transform)
    if (_silenceInPipeline) {
      parts.add('lavfi=[silencedetect=noise=-50dB:d=${_silenceSkipThreshold.toStringAsFixed(1)}]');
    }
    return parts.join(',');
  }

  void _applyBalance(double balance) {
    setState(() {
      _audioBalance = balance.clamp(-1.0, 1.0);
      if (_audioBalance.abs() < 0.02) {
        _currentBalanceAf = '';
      } else {
        final l = _audioBalance <= 0 ? 1.0 : (1.0 - _audioBalance);
        final r = _audioBalance >= 0 ? 1.0 : (1.0 + _audioBalance);
        _currentBalanceAf =
            'pan=stereo|c0=${l.toStringAsFixed(3)}*c0|c1=${r.toStringAsFixed(3)}*c1';
      }
      _applyAllAf();
    });
    _savePrefs();
  }

  void _rotateVideo() {
    setState(() => _videoRotation = (_videoRotation + 90) % 360);
    try { _np.setProperty('video-rotate', _videoRotation.toString()); } catch (_) {}
    _savePrefs();
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

  void _applyAllAf() {
    try { _np.setProperty('af', _buildMergedAfString()); } catch (_) {}
  }

  // Push current playback state to the Android media notification service.
  // Called when going to background, when play/pause changes via notification,
  // and periodically from the bg-play timer.
  void _notifyBgState() {
    if (!_backgroundAudio) return;
    const MethodChannel('com.raddflix.app/pip').invokeMethod('startBgPlayback', {
      'title':      widget.title,
      'isPlaying':  _player.state.playing,
      'positionMs': _position.inMilliseconds,
      'durationMs': _duration.inMilliseconds,
    }).catchError((_) {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Sleep timer
  // ═══════════════════════════════════════════════════════════════════════════

  void _setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimerEnd = null;
    if (minutes != null && minutes > 0) {
      _sleepTimerEnd = DateTime.now().add(Duration(minutes: minutes));
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        if (mounted) _player.pause();
      });
    }
    setState(() => _sleepTimerMinutes = minutes);
  }

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
  }

  void _adjustAudioSync(double delta) {
    _audioSync = (_audioSync + delta);
    try { _np.setProperty('audio-delay', _audioSync.toStringAsFixed(1)); } catch (_) {}
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Phase 59 — AI Dub (Method 1: Android TTS + MPV karaoke filter)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startDubGeneration(String lang) async {
    if (_currentSubFile == null) {
      _showInfoSnackbar('Load an SRT subtitle file first');
      return;
    }
    setState(() {
      _dubGenerating  = true;
      _isDubMode      = false;
      _dubActiveLang  = lang;
      _dubProgress    = 0.0;
      _dubCurrentLine = 0;
      _dubTotalLines  = 0;
      _dubStatusText  = 'Reading subtitle file…';
    });
    try {
      final srtContent = await File(_currentSubFile!).readAsString();
      final entries    = SubtitleDubber.parseSrt(srtContent);
      if (entries.isEmpty) {
        if (mounted) setState(() { _dubGenerating = false; });
        _showInfoSnackbar('No subtitle entries found in the file');
        return;
      }
      setState(() { _dubTotalLines = entries.length; });
      final cacheKey = '${_currentSubFile!.hashCode}_${lang.replaceAll('-', '')}';
      final wavPath  = await SubtitleDubber.generateDub(
        entries:       entries,
        language:      lang,
        totalDuration: _duration,
        cacheKey:      cacheKey,
        onProgress: (cur, total, status) {
          if (mounted) setState(() {
            _dubCurrentLine = cur;
            _dubTotalLines  = total;
            _dubProgress    = total > 0 ? cur / total : 0.0;
            _dubStatusText  = status;
          });
        },
      );
      if (!mounted) return;
      if (wavPath == null) {
        setState(() { _dubGenerating = false; });
        final langName = lang == 'ur-PK' ? 'Urdu' : 'Hindi';
        if (_dubStatusText == 'LANG_NOT_INSTALLED') {
          // Language pack missing — show actionable prompt to open TTS settings
          _showTtsInstallPrompt(langName);
        } else {
          _showInfoSnackbar('Dub generation failed — check that $langName TTS is installed');
        }
        return;
      }
      setState(() {
        if (lang == 'ur-PK') _dubbedWavPathUr = wavPath;
        else                  _dubbedWavPathHi = wavPath;
        _dubGenerating = false;
      });
      _applyDubMode(lang);
    } catch (e) {
      if (mounted) setState(() { _dubGenerating = false; });
      _showInfoSnackbar('Dub error: $e');
    }
  }

  void _applyDubMode(String lang) {
    final path = lang == 'ur-PK' ? _dubbedWavPathUr : _dubbedWavPathHi;
    if (path == null) return;
    setState(() { _isDubMode = true; _dubActiveLang = lang; });
    // Load external dubbed WAV as aid=2
    try { _np.setProperty('audio-file', path); } catch (_) {}
    // After MPV registers the new track, apply lavfi-complex:
    //   aid1 = original audio → karaoke filter (removes centre-panned dialogue ~65%)
    //          then at 65% volume so music/SFX stay audible but voices are faint
    //   aid2 = dubbed WAV → full volume
    //   amix: both tracks mixed to output
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || !_isDubMode) return;
      try {
        _np.setProperty('lavfi-complex',
          '[aid1]pan=stereo|c0=0.5*c0-0.5*c1|c1=-0.5*c0+0.5*c1,'
          'volume=0.65[bg];'
          '[aid2]volume=1.5[fg];'
          '[bg][fg]amix=inputs=2:normalize=0[ao]');
      } catch (_) {}
    });
  }

  void _disableDubMode() {
    setState(() { _isDubMode = false; });
    try { _np.setProperty('lavfi-complex', ''); } catch (_) {}
    try { _np.setProperty('audio-file', '');    } catch (_) {}
  }

  Widget _buildDubProgressOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.88),
        child: Center(
          child: _DubProgressCard(
            lang:        _dubActiveLang,
            progress:    _dubProgress,
            currentLine: _dubCurrentLine,
            totalLines:  _dubTotalLines,
            statusText:  _dubStatusText,
          ),
        ),
      ),
    );
  }

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
                              const SizedBox(width: 8),
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
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_out_rounded, color: Colors.orange, size: 14),
                            SizedBox(width: 4),
                            Text('Reset zoom', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500)),
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
                              const SizedBox(height: 4),
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
                          SizedBox(height: 16),
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
                            const SizedBox(height: 8),
                            Text(_streamError!,
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                                textAlign: TextAlign.center),
                            // Jazz SIM specific help steps
                            if (_streamError!.contains('Jazz') || _streamError!.contains('SIM')) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('• Disconnect WiFi, use Jazz mobile data',
                                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    SizedBox(height: 4),
                                    Text('• Ensure Jazz SIM is active in slot 1',
                                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    SizedBox(height: 4),
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
                          borderRadius: BorderRadius.circular(12),
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
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Cancel',
                                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _playEpisodeAt(_currentEpIdx + 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(16),
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
              onTap: () => setState(() { _isLocked = !_isLocked; _showControls = true; }),
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
              onTap: () { setState(() => _oneHandedLeft = !_oneHandedLeft); _savePrefs(); },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
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

            const SizedBox(width: 4),

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

            const SizedBox(width: 4),

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
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.orange.withOpacity(0.6), width: 0.8),
                  ),
                  child: Text('${_videoRotation}deg',
                      style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Seek bar row ────────────────────────────────────────────────────
            _buildHorizontalSeekBar(constraints, currentPos),

            const SizedBox(height: 2),

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
        height: 52,
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
                const SizedBox(width: 4),
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
            onTap: () => setState(() => _showRemainingTime = !_showRemainingTime),
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
          icon: _realSubtitleTracks.isNotEmpty ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
          label: 'CC',
          active: _realSubtitleTracks.isNotEmpty,
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
          onTap: () => setState(() { _isLocked = true; _showControls = false; }),
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
          onTap: () { setState(() => _oneHandedMode = !_oneHandedMode); _savePrefs(); },
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
              _savePrefs();
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
            const SizedBox(height: 4),
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
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
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
      final double videoH = constraints.maxHeight * 0.38;
      final Duration currentPos = _seekBarDelta != null
          ? Duration(milliseconds: (_seekBarDelta! * _duration.inMilliseconds).round())
          : _position;
      final BoxConstraints videoConstraints = BoxConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: videoH,
      );

      return Column(
        children: [
          // ── Video zone (top 38%) ────────────────────────────────────────────
          SizedBox(
            width: constraints.maxWidth,
            height: videoH,
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

                // Compact top bar (shown when controls visible)
                if (!_isImmersive)
                  Positioned(
                    top: 0, left: 0, right: 0,
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

                // Shortcut sidebar (right edge of video zone)
                if (!_isLocked && !_isImmersive)
                  Positioned(
                    right: 0, top: 0, bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _panelOpen ? 0.0 : (_showControls ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 280),
                      child: IgnorePointer(
                        ignoring: _panelOpen || !_showControls,
                        child: _buildSidebar(videoConstraints),
                      ),
                    ),
                  ),

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

                // Volume indicator
                if (_showVolumeIndicator && !_isImmersive)
                  Positioned(
                    left: 20, top: 0, bottom: 0,
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
                        SizedBox(height: 16),
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
                        padding: const EdgeInsets.all(16),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 36),
                          const SizedBox(height: 8),
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
                            const SizedBox(width: 8),
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
              ],
            ),
          ),

          // ── Controls panel (bottom 62%) ────────────────────────────────────
          Expanded(
            child: Container(
              color: const Color(0xFF0D0D0D),
              child: SingleChildScrollView(
                child: _buildPortraitControlsPanel(constraints, currentPos),
              ),
            ),
          ),
        ],
      );
    }

    Widget _buildPortraitTopBar() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            _RaddIconBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 18,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 6),
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHorizontalSeekBar(constraints, currentPos),
            const SizedBox(height: 4),
            _buildTransportRow(),
            const SizedBox(height: 12),
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
            _realSubtitleTracks.isNotEmpty
                ? Icons.subtitles_rounded
                : Icons.subtitles_off_rounded,
            'CC',
            _openSubtitlePanel,
            active: _realSubtitleTracks.isNotEmpty,
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
            Icons.loop_rounded,
            'Loop',
            _toggleLoop,
            active: _loopEnabled,
          ))),
          Expanded(child: Center(child: _buildPortraitActionBtn(
            Icons.settings_rounded,
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
                borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 4),
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
    //  Panels (right-side slide-in / bottom-sheet in portrait)
    // ═══════════════════════════════════════════════════════════════════════════

void _openRightPanel(Widget content, {double widthFactor = 0.55}) {
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
            child: Container(color: Colors.black.withOpacity(0.38 * anim.value)),
          ),
          Positioned(
            right: 0, top: 0, bottom: 0,
            width: w * widthFactor,
            child: SlideTransition(
              position: slide,
              child: Material(
                color: Colors.black.withOpacity(0.60),
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

    void _openSubtitlePanel() {
      _openRightPanel(_SubtitlePanel(
        isLocal: _isLocal,
        subSync: _subSync,
        subSpeed: _subSpeed,
        currentFile: _currentSubFile,
        onSyncChanged: (delta) => _adjustSubSync(delta),
        onSpeedChanged: (v) {
          setState(() => _subSpeed = v);
          try { _np.setProperty('sub-speed', v.toString()); } catch (_) {}
        },
        onSubPropertyChanged: (prop, val) {
          if (prop == '_sub_margin_main') {
            // Internal signal — update main state so _applySubtitleMargin
            // uses the user's latest base value.
            setState(() => _subBottomMarginMain = double.tryParse(val) ?? _subBottomMarginMain);
            _savePrefs();
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
        onClose: () => Navigator.of(context).pop(),
        title: _currentTitle,
        onSubtitleFilePicked: (path) {
          setState(() => _currentSubFile = path);
          try { _np.setProperty('sub-file', path); } catch (_) {}
        },
        // P57-02: embedded track selector
        embeddedTracks: _realSubtitleTracks,
        selectedSubtitle: _selectedSubtitle,
        onSubtitleTrackSelected: (track) {
          setState(() => _selectedSubtitle = track);
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
            if (track != null) {
              _np.setProperty('secondary-sid', track.id!);
              _np.setProperty('secondary-sub-visibility', 'yes');
            } else {
              _np.setProperty('secondary-sid', 'no');
            }
          } catch (_) {}
        },
        onDubRequested: _startDubGeneration,  // P59
      ));
    }

    void _openAudioPanel() {
      _openRightPanel(_AudioTrackPanel(
        tracks: _realAudioTracks,
        selectedTrack: _selectedAudio,
        audioSync: _audioSync,
        useSWDecoder: _useSWDecoder,
        onTrackSelected: (track) {
          setState(() => _selectedAudio = track);
          if (track != null) {
            _player.setAudioTrack(track);
          } else {
            try { _np.setProperty('aid', 'no'); } catch (_) {}
          }
        },
        onSyncChanged: (delta) => _adjustAudioSync(delta),
        onSWDecoderChanged: (v) {
          try { _np.setProperty('hwdec', v ? 'no' : 'auto-safe'); } catch (_) {}
          setState(() => _useSWDecoder = v);
          if (_playing) _showInfoSnackbar('Seek forward to fully apply the decoder change');
        },
        onChannelModeChanged: (filterStr) {
          setState(() {
            _currentChannelModeAf = filterStr;
            _channelModeIdx = (_channelModeIdx + 1) % 4;
          });
          _applyAllAf();
          _savePrefs();
        },
        initialChannelModeIdx: _channelModeIdx,
        isPlaying: _playing,
        currentCodec: _currentAudioCodec.isNotEmpty ? _currentAudioCodec : null,
        onClose: () => Navigator.of(context).pop(),
        isDubMode: _isDubMode,           // P60
        dubActiveLang: _dubActiveLang,   // P60
        onRemoveDub: () {                // P60
          _disableDubMode();
          Navigator.of(context).pop();
        },
      ));
    }

    void _openZoomPanel() {
      _openRightPanel(_VideoZoomPanel(
        selectedMode: _zoomMode,
        onModeSelected: (mode) {
          setState(() => _zoomMode = mode);
          if (mode == 4) {
            _showInfoSnackbar('Pinch the video to set a custom zoom level');
          }
          Navigator.of(context).pop();
        },
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openAudioEffectPanel() {
      _openRightPanel(_AudioEffectPanel(
        selectedPreset: _selectedPreset,
        eqBands: _eqBands,
        eqEnabled: _eqEnabled,
        onPresetSelected: _applyPreset,
        onEqBandChanged: (i, v) {
          setState(() { _eqBands[i] = v; _selectedPreset = -1; });
          _applyCustomEq();
          _savePrefs();
        },
        onEqEnabledChanged: (v) {
          setState(() => _eqEnabled = v);
          _applyAllAf(); // merged pipeline — reverb/lab still active if enabled
          _savePrefs();
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
          _savePrefs();
        },
        onLabAfChanged: (afStr) {
          _currentLabAf = afStr;
          _applyAllAf(); // EQ + reverb + lab all stack
        },
        onLabStateChanged: (vocal, dialogue, norm, bass, bassLevel) {
          setState(() {
            _labVocal = vocal;
            _labDialogue = dialogue;
            _labNorm = norm;
            _labBass = bass;
            _labBassLevel = bassLevel;
          });
          _savePrefs();
        },
        labVocal: _labVocal,
        labDialogue: _labDialogue,
        labNorm: _labNorm,
        labBass: _labBass,
        labBassLevel: _labBassLevel,
        initialReverbPreset: _reverbPreset,
        audioBalance: _audioBalance,
        onBalanceChanged: _applyBalance,
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openMoreMenu() {
      _openRightPanel(_QuickShortcutsPanel(
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
          _savePrefs();
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
        onClose: () => Navigator.of(context).pop(),
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
      ));
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
                        borderRadius: BorderRadius.circular(8),
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
              const SizedBox(height: 4),
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
                    _savePrefs();
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
                        _savePrefs();
                      },
                      activeColor: Colors.white,
                    ),
                  ],
                ),
                if (_silenceSkipEnabled) ...[
                  const SizedBox(height: 16),
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
                      _savePrefs();
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

    void _applySilenceSkip() {
      setState(() => _silenceInPipeline = _silenceSkipEnabled);
      _applyAllAf();
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
                const SizedBox(height: 4),
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
                        _savePrefs();
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
                const SizedBox(height: 4),
                const Text('Toggle each gesture on or off', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Double-tap seek', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Double-tap left/right to ±${_skipInterval}s', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _doubleTapSeekEnabled,
                  onChanged: (v) { setState(() => _doubleTapSeekEnabled = v); setSt(() {}); _savePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Long press speed boost', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Hold to play at 2× speed', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _longPressSpeedEnabled,
                  onChanged: (v) { setState(() => _longPressSpeedEnabled = v); setSt(() {}); _savePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe to seek', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Horizontal swipe jumps through video', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _swipeSeekEnabled,
                  onChanged: (v) { setState(() => _swipeSeekEnabled = v); setSt(() {}); _savePrefs(); },
                  activeColor: Colors.white,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe brightness / volume', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Left edge: brightness  •  Right edge: volume', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _swipeBVEnabled,
                  onChanged: (v) { setState(() => _swipeBVEnabled = v); setSt(() {}); _savePrefs(); },
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
                    onChanged: (v) { setState(() => _skipEditorEnabled = v); setSt(() {}); _savePrefs(); },
                    activeColor: Colors.white,
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('INTRO', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _introStart = _position); setSt(() {}); _savePrefs(); _showInfoSnackbar('Intro start: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('Start', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_introStart != null ? _formatDuration(_introStart!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _introEnd = _position); setSt(() {}); _savePrefs(); _showInfoSnackbar('Intro end: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('End', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_introEnd != null ? _formatDuration(_introEnd!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () { setState(() { _introStart = null; _introEnd = null; }); setSt(() {}); _savePrefs(); },
                    child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text('OUTRO', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () { setState(() => _outroStart = _position); setSt(() {}); _savePrefs(); _showInfoSnackbar('Outro skip from: ${_formatDuration(_position)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Column(children: [
                          const Text('Skip from', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          Text(_outroStart != null ? _formatDuration(_outroStart!) : '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () { setState(() => _outroStart = null); setSt(() {}); _savePrefs(); },
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

    void _checkSkipEditor() {
      if (!_skipEditorEnabled) return;
      if (_introStart != null && _introEnd != null) {
        if (_position >= _introStart! && _position < _introEnd!) {
          _player.seek(_introEnd!);
          _showInfoSnackbar('Skipped intro');
          return;
        }
      }
      if (_outroStart != null && _duration > Duration.zero) {
        if (_position >= _outroStart! && _position < _duration - const Duration(seconds: 2)) {
          _player.seek(_duration - const Duration(seconds: 1));
          _showInfoSnackbar('Skipped outro');
        }
      }
    }

    Future<void> _loadSkipEditorPrefs() async {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final is_ = prefs.getInt('pref_intro_s_$_currentFileId');
      final ie  = prefs.getInt('pref_intro_e_$_currentFileId');
      final os_ = prefs.getInt('pref_outro_s_$_currentFileId');
      setState(() {
        _introStart = is_ != null ? Duration(seconds: is_) : null;
        _introEnd   = ie  != null ? Duration(seconds: ie)  : null;
        _outroStart = os_ != null ? Duration(seconds: os_) : null;
      });
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
                ('compact', Icons.fit_screen_rounded,   'Compact',  'Smaller UI, condensed seek bar padding'),
              ])
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _layoutPreset = item.$1;
                      if (item.$1 == 'cinema') _showSkipBtns = false;
                      if (item.$1 == 'default' || item.$1 == 'compact') _showSkipBtns = true;
                    });
                    _savePrefs();
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
      _openRightPanel(_SidebarCustomizerPanel(
        currentOrder: List<String>.from(_sidebarOrder),
        allIds: List<String>.from(_allSidebarIds),
        onOrderChanged: (newOrder) {
          setState(() => _sidebarOrder = newOrder);
          _savePrefs();
        },
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openSettingsPanel() {
      _openRightPanel(_SettingsPanel(
        showRemainingTime: _showRemainingTime,
        keepScreenOn: _keepScreenOn,
        skipInterval: _skipInterval,
        onShowRemainingChanged: (v) => setState(() => _showRemainingTime = v),
        onKeepScreenChanged: (v) {
          setState(() => _keepScreenOn = v);
          if (v) WakelockPlus.enable(); else WakelockPlus.disable();
        },
        onSkipIntervalChanged: (v) => setState(() => _skipInterval = v),
        seekSwipeSec: _seekSwipeSec,
        onSeekSwipeSpeedChanged: (v) => setState(() => _seekSwipeSec = v),
        accentColorIdx: _accentColorIdx,
        progressBarStyle: _progressBarStyle,
        onAccentColorChanged: (i) { setState(() => _accentColorIdx = i); _savePrefs(); },
        onProgressBarStyleChanged: (s) { setState(() => _progressBarStyle = s); _savePrefs(); },
        backgroundAudio: _backgroundAudio,
        onBackgroundAudioChanged: (v) { setState(() => _backgroundAudio = v); _savePrefs(); },
        nightModeEnabled: _nightModeEnabled,
        nightWarmth: _nightWarmth,
        onNightModeToggle: (v) { setState(() => _nightModeEnabled = v); _savePrefs(); },
        onNightWarmthChanged: (v) { setState(() => _nightWarmth = v); _savePrefs(); },
        showClockInTitle: _showClockInTitle,
        onClockToggle: (v) {
          setState(() { _showClockInTitle = v; _clockStr = _fmtClock(); });
          _savePrefs();
        },
        initialBrightness: _brightness,
        onShowSkipBtnsChanged: (v) => setState(() => _showSkipBtns = v),
        onShowPrevNextBtnsChanged: (v) => setState(() => _showPrevNextBtns = v),
        onShowSeekPositionChanged: (v) => setState(() => _showSeekPositionLabel = v),
        showSkipBtns: _showSkipBtns,
        showPrevNextBtns: _showPrevNextBtns,
        showSeekPosition: _showSeekPositionLabel,
        onRotateVideo: () { Navigator.of(context).pop(); _rotateVideo(); },
        onClose: () => Navigator.of(context).pop(),
        doubleTapSeekEnabled: _doubleTapSeekEnabled,
        longPressSpeedEnabled: _longPressSpeedEnabled,
        swipeSeekEnabled: _swipeSeekEnabled,
        swipeBVEnabled: _swipeBVEnabled,
        onDoubleTapSeekChanged: (v) { setState(() => _doubleTapSeekEnabled = v); _savePrefs(); },
        onLongPressSpeedChanged: (v) { setState(() => _longPressSpeedEnabled = v); _savePrefs(); },
        onSwipeSeekChanged: (v) { setState(() => _swipeSeekEnabled = v); _savePrefs(); },
        onSwipeBVChanged: (v) { setState(() => _swipeBVEnabled = v); _savePrefs(); },
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
          _savePrefs();
        },
      ));
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

  void _showInfoSnackbar(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF2A2A2A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    // Fix #DUB-01: shown when setLanguage() returns LANG_MISSING_DATA (-1) or
    // LANG_NOT_SUPPORTED (-2). Provides an "Install" action that deep-links to
    // the Android TTS settings page so the user can download the voice pack.
    void _showTtsInstallPrompt(String langName) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$langName TTS voice not installed. Tap Install to add it.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF2A2A2A),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'Install',
            textColor: Colors.amber,
            onPressed: () {
              try {
                const AndroidIntent(
                  action: 'com.android.settings.TTS_SETTINGS',
                ).launch();
              } catch (_) {
                try {
                  const AndroidIntent(
                    action: 'android.settings.SETTINGS',
                  ).launch();
                } catch (_) {}
              }
            },
          ),
        ),
      );
    }

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

// ═════════════════════════════════════════════════════════════════════════════
//  SUBTITLE PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _SubtitlePanel extends StatefulWidget {
  final bool isLocal;
  final double subSync;
  final double subSpeed;
  final String? currentFile;
  final void Function(double) onSyncChanged;
  final void Function(double) onSpeedChanged;
  final void Function(String prop, String val) onSubPropertyChanged;
  final VoidCallback onClose;
  final String? title;
  final void Function(String)? onSubtitleFilePicked;
  final void Function(String lang)? onDubRequested; // P59
  // P57-02: embedded MKV subtitle tracks + P57-07: secondary (OST/signs) sub
  final List<SubtitleTrack> embeddedTracks;
  final SubtitleTrack? selectedSubtitle;
  final SubtitleTrack? selectedSecondSub;
  final void Function(SubtitleTrack?) onSubtitleTrackSelected;
  final void Function(SubtitleTrack?) onSecondSubSelected;

  const _SubtitlePanel({
    required this.isLocal,
    required this.subSync,
    required this.subSpeed,
    required this.currentFile,
    required this.onSyncChanged,
    required this.onSpeedChanged,
    required this.onSubPropertyChanged,
    required this.onClose,
    this.title,
    this.onSubtitleFilePicked,
    this.onDubRequested,
    this.embeddedTracks = const [],
    this.selectedSubtitle,
    this.selectedSecondSub,
    required this.onSubtitleTrackSelected,
    required this.onSecondSubSelected,
  });

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<_SubtitlePanel> {
  int _tab = 0; // 0=Open 1=Settings 2=Sync 3=Speed 4=Panel 5=Custom
  late double _sync;
  late double _speed;
  List<Map<String,dynamic>> _onlineResults = [];
  bool _onlineLoading = false;
  String _onlineError = '';
  // Subtitle search improvements
  late TextEditingController _searchController;
  String _selectedLangCode = 'urd,hin'; // default: Urdu + Hindi for Pakistani content
  bool _hasSearched = false;
  String? _osToken; // cached XML-RPC session token
  // Real subtitle style state
  int _subFontIdx = 0;  // 0=Sans Serif 1=Serif 2=Monospace 3=Casual
  double _subSize = 22.0;
  double _subScale = 1.0;
  bool _subBold = false;
  Color _subColor = Colors.white;
  Color _subBg = Colors.transparent;
  double _subFade = 0.8;
  // Panel tab
  int _subAlignIdx = 1; // 0=Left 1=Center 2=Right
  double _subBottomMargin = 100.0;
  bool _subFitToVideo = true;
  // Customization tab state
  int _subPositionIdx = 2;    // 0=Top 1=Center 2=Bottom  → sub-align-y
  int _subShadowIdx = 1;      // 0=None 1=Outline 2=Shadow 3=Box
  double _subOpacity = 1.0;   // 0.0–1.0 → sub-ass-style alpha
  double _subEdgePadding = 16.0; // sub-margin-x
  double _subLineSpacing = 1.2;  // sub-spacing

  static const _subFonts = ['Sans Serif', 'Serif', 'Monospace', 'Casual'];
  static const _subAligns = ['Left', 'Center', 'Right'];
  static const _subColorPresets = [
    Colors.white, Colors.yellow, Color(0xFFFFD700),
    Color(0xFF00FF00), Color(0xFF00FFFF), Colors.black,
  ];
  static const _subBgPresets = [
    Colors.transparent, Colors.black87, Color(0x99000000),
    Color(0x99FFFF00), Colors.black,
  ];

  void _showInfoSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void initState() {
    super.initState();
    _sync = widget.subSync;
    _speed = widget.subSpeed;
    _searchController = TextEditingController(text: widget.title ?? '');
    // Auto-search on open if we have a title and aren't viewing local files
    if ((widget.title ?? '').isNotEmpty && !widget.isLocal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchOnlineSubtitles(context);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showColorPicker(BuildContext ctx, List<Color> presets, Color current, ValueChanged<Color> onPick) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Pick Color', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Wrap(
          spacing: 12, runSpacing: 12,
          children: presets.map((col) => GestureDetector(
            onTap: () { onPick(col); Navigator.of(c).pop(); },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                border: Border.all(
                  color: col == current ? Colors.white : Colors.white24,
                  width: col == current ? 2.5 : 1,
                ),
              ),
            ),
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)))],
      ),
    );
  }


  // ── Online subtitle search via OpenSubtitles XML-RPC (anonymous, no key needed) ──
  // The old REST API (rest.opensubtitles.org) is dead as of 2023.
  // The XML-RPC API (api.opensubtitles.org/xml-rpc) still accepts anonymous login.

  /// Step 1: anonymous login → returns session token (cached in _osToken)
  Future<String?> _osLogin() async {
    if (_osToken != null) return _osToken;
    const loginXml =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<methodCall><methodName>LogIn</methodName><params>'
        '<param><value><string></string></value></param>'
        '<param><value><string></string></value></param>'
        '<param><value><string>en</string></value></param>'
        '<param><value><string>RaddFlix v1</string></value></param>'
        '</params></methodCall>';
    try {
      final client = HttpClient();
      final req = await client.postUrl(
          Uri.parse('https://api.opensubtitles.org/xml-rpc'));
      req.headers.set('Content-Type', 'text/xml; charset=utf-8');
      req.headers.set('User-Agent', 'RaddFlix v1');
      req.write(loginXml);
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final body = await resp.transform(const Utf8Decoder()).join();
      client.close();
      final m = RegExp(r'<name>token</name>\s*<value><string>([^<]+)</string>')
          .firstMatch(body);
      _osToken = m?.group(1);
      return _osToken;
    } catch (_) { return null; }
  }

  /// Extract all string-value members from an XML-RPC struct block
  Map<String, String> _parseXmlRpcStruct(String block) {
    final result = <String, String>{};
    final members = RegExp(
        r'<name>([^<]+)</name>\s*<value><string>([^<]*)</string>',
        dotAll: true).allMatches(block);
    for (final m in members) {
      result[m.group(1)!] = m.group(2)!;
    }
    return result;
  }

  /// Step 2: search by query + language code
  Future<void> _fetchOnlineSubtitles(BuildContext ctx) async {
    if (_onlineLoading) return;
    final query = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : (widget.title ?? '');
    if (query.isEmpty) return;
    if (mounted) setState(() {
      _onlineLoading = true; _onlineError = ''; _onlineResults = []; _hasSearched = true;
    });
    try {
      final token = await _osLogin();
      if (token == null) {
        if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Could not connect to subtitle server. Try again.'; });
        return;
      }
      final safeQuery = query.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
      final searchXml =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<methodCall><methodName>SearchSubtitles</methodName><params>'
          '<param><value><string>$token</string></value></param>'
          '<param><value><array><data><value><struct>'
          '<member><name>sublanguageid</name><value><string>$_selectedLangCode</string></value></member>'
          '<member><name>query</name><value><string>$safeQuery</string></value></member>'
          '</struct></value></data></array></value></param>'
          '</params></methodCall>';
      final client = HttpClient();
      final req = await client.postUrl(
          Uri.parse('https://api.opensubtitles.org/xml-rpc'));
      req.headers.set('Content-Type', 'text/xml; charset=utf-8');
      req.headers.set('User-Agent', 'RaddFlix v1');
      req.write(searchXml);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final body = await resp.transform(const Utf8Decoder()).join();
      client.close();
      // Check for fault
      if (body.contains('<name>faultString</name>')) {
        _osToken = null; // token may be expired, reset
        if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Search failed. Tap retry.'; });
        return;
      }
      // Split on struct boundaries and parse each subtitle entry
      final structs = RegExp(r'<value><struct>(.*?)</struct></value>', dotAll: true)
          .allMatches(body)
          .map((m) => _parseXmlRpcStruct(m.group(1)!))
          .where((s) => s.containsKey('SubFileName'))
          .toList();
      if (mounted) setState(() {
        _onlineResults = structs.take(20).toList();
        _onlineLoading = false;
        if (structs.isEmpty) _onlineError = 'No subtitles found. Try a different title or language.';
      });
    } catch (e) {
      if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Search failed: try again.'; });
    }
  }

  Future<void> _downloadOnlineSubtitle(BuildContext ctx, Map<String, dynamic> entry) async {
    final link = (entry['SubDownloadLink'] ?? '') as String;
    final fname = (entry['SubFileName'] ?? 'subtitle.srt') as String;
    if (link.isEmpty) return;
    if (mounted) setState(() => _onlineLoading = true);
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(link));
      req.headers.set('User-Agent', 'RaddFlix v1');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final bytesList = <List<int>>[];
      await for (final chunk in resp) { bytesList.add(chunk); }
      final bytes = bytesList.expand((e) => e).toList();
      client.close();
      List<int> srtBytes;
      try { srtBytes = ZLibDecoder().convert(bytes); }
      catch (_) { srtBytes = bytes; }
      final dir = await getTemporaryDirectory();
      final cleanName = fname.replaceAll('.gz', '');
      final outPath = '${dir.path}/$cleanName';
      File(outPath).writeAsBytesSync(srtBytes);
      widget.onSubtitleFilePicked?.call(outPath);
      if (mounted) setState(() => _onlineLoading = false);
      if (mounted) _showInfoSnackbar('✓ Subtitle loaded: $cleanName');
    } catch (e) {
      if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Download failed: try again.'; });
    }
  }

  // ── P59: AI Dub button section ─────────────────────────────────────────
  List<Widget> _buildDubSection(BuildContext context) {
    final hasDub = widget.onDubRequested != null;
    return [
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.35), width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI', style: TextStyle(color: Color(0xFF4A9EFF),
                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
              const SizedBox(width: 8),
              const Text('Auto Dubbing', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            const Text('Generates on-device voice dub from this subtitle',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _DubLangBtn(
                flag: '🇵🇰', label: 'Urdu', sublabel: 'ur-PK',
                color: const Color(0xFF00A651),
                onTap: hasDub ? () => widget.onDubRequested!('ur-PK') : null,
              )),
              const SizedBox(width: 10),
              Expanded(child: _DubLangBtn(
                flag: '🇮🇳', label: 'Hindi', sublabel: 'hi-IN',
                color: const Color(0xFFFF9933),
                onTap: hasDub ? () => widget.onDubRequested!('hi-IN') : null,
              )),
            ]),
            const SizedBox(height: 10),
            const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.white24, size: 12),
              SizedBox(width: 5),
              Expanded(child: Text(
                'Music + effects preserved via karaoke filter. 2-5 min first time.',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              )),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('Subtitle',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        // Tabs — B1/B2 fix: 'AI Dub' is now a dedicated tab (index 6) rather than
        // a pinned block above the tabs. The pinned block consumed ~213 dp of fixed
        // height, leaving almost no room for settings in landscape mode. Moving it
        // into a tab makes the full settings list reachable in all orientations.
        // B2: the tab is only added when onDubRequested is non-null.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final tab in [
                'Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization',
                if (widget.onDubRequested != null) 'AI Dub',
              ])
                GestureDetector(
                  onTap: () => setState(() => _tab = [
                    'Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization',
                    if (widget.onDubRequested != null) 'AI Dub',
                  ].indexOf(tab)),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _tab == [
                        'Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization',
                        if (widget.onDubRequested != null) 'AI Dub',
                      ].indexOf(tab)
                          ? Colors.white24
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(tab, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Subtitle file info
              if (widget.currentFile != null) ...[
                Text(widget.currentFile!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('Add Translation',
                    style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 13)),
                const SizedBox(height: 16),
              ],

              // ── Open tab: local file picker ──────────────────────────────────────
              if (_tab == 0) ...[
                // P57-02: Embedded subtitle track selector
                if (widget.embeddedTracks.isNotEmpty) ...[
                  const Text('Embedded Tracks',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (int i = 0; i < widget.embeddedTracks.length; i++)
                    RadioListTile<SubtitleTrack?>(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      value: widget.embeddedTracks[i],
                      groupValue: widget.selectedSubtitle,
                      onChanged: (t) => widget.onSubtitleTrackSelected(t),
                      activeColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.embeddedTracks[i].language != null && widget.embeddedTracks[i].title != null
                            ? '${widget.embeddedTracks[i].language} — ${widget.embeddedTracks[i].title}'
                            : widget.embeddedTracks[i].language
                                ?? widget.embeddedTracks[i].title
                                ?? 'Track ${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  RadioListTile<SubtitleTrack?>(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                    value: null,
                    groupValue: widget.selectedSubtitle,
                    onChanged: (_) => widget.onSubtitleTrackSelected(null),
                    activeColor: Colors.white,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Off', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  // P57-07: Secondary subtitle (OST / signs) — displayed at TOP via MPV secondary-sid
                  const Text('Secondary Subtitle — OST / Signs (shown at top)',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Select a track to show at the top of the video (song lyrics, signs, on-screen text)',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 6),
                  for (int i = 0; i < widget.embeddedTracks.length; i++)
                    RadioListTile<SubtitleTrack?>(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      value: widget.embeddedTracks[i],
                      groupValue: widget.selectedSecondSub,
                      onChanged: (t) => widget.onSecondSubSelected(t),
                      activeColor: const Color(0xFF4A9EFF),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.embeddedTracks[i].language != null && widget.embeddedTracks[i].title != null
                            ? '${widget.embeddedTracks[i].language} — ${widget.embeddedTracks[i].title}'
                            : widget.embeddedTracks[i].language
                                ?? widget.embeddedTracks[i].title
                                ?? 'Track ${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  RadioListTile<SubtitleTrack?>(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                    value: null,
                    groupValue: widget.selectedSecondSub,
                    onChanged: (_) => widget.onSecondSubSelected(null),
                    activeColor: const Color(0xFF4A9EFF),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Off', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  const Text('External File',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
                    );
                    if (result != null && result.files.single.path != null) {
                      widget.onSubtitleFilePicked?.call(result.files.single.path!);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder_open_rounded, color: Colors.white70, size: 30),
                      SizedBox(height: 8),
                      Text('Open from device',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('SRT · VTT · ASS · SSA',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ]),
                  ),
                ),
              ],

              if (_tab == 2) ...[
                // Synchronization
                const Text('Synchronization', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SyncBtn(label: '−', onTap: () {
                      setState(() => _sync -= 0.1);
                      widget.onSyncChanged(-0.1);
                    }),
                    const SizedBox(width: 16),
                    Text('${_sync.toStringAsFixed(1)}s',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    _SyncBtn(label: '+', onTap: () {
                      setState(() => _sync += 0.1);
                      widget.onSyncChanged(0.1);
                    }),
                  ],
                ),
              ],

              if (_tab == 3) ...[
                // Speed
                const Text('Speed', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SyncBtn(label: '−', onTap: () => setState(() { _speed = (_speed - 0.1).clamp(0.5, 2.0); widget.onSpeedChanged(_speed); })),
                    const SizedBox(width: 16),
                    Text('${(_speed * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    _SyncBtn(label: '+', onTap: () => setState(() { _speed = (_speed + 0.1).clamp(0.5, 2.0); widget.onSpeedChanged(_speed); })),
                  ],
                ),
              ],

              if (_tab == 1) ...[
                  const Text('Text', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  // Font picker
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: const Color(0xFF1C1C1C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          title: const Text('Subtitle Font', style: TextStyle(color: Colors.white)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(_subFonts.length, (i) => ListTile(
                              dense: true,
                              title: Text(_subFonts[i], style: TextStyle(
                                color: Colors.white,
                                fontWeight: i == _subFontIdx ? FontWeight.bold : FontWeight.normal,
                              )),
                              trailing: i == _subFontIdx ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                              onTap: () {
                                setState(() => _subFontIdx = i);
                                const mpvFonts = ['sans-serif', 'serif', 'monospace', 'sans-serif'];
                                widget.onSubPropertyChanged('sub-font', mpvFonts[i]);
                                Navigator.of(c).pop();
                              },
                            )),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.of(c).pop(),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54)))],
                        ),
                      );
                    },
                    child: Row(children: [
                      const Expanded(child: Text('Font', style: TextStyle(color: Colors.white, fontSize: 14))),
                      Text(_subFonts[_subFontIdx], style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  // Size slider
                  const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(children: [
                    Expanded(child: Slider(
                      value: _subSize, min: 12, max: 40, divisions: 14,
                      activeColor: Colors.white, inactiveColor: Colors.white24,
                      onChanged: (v) { setState(() => _subSize = v); widget.onSubPropertyChanged('sub-font-size', v.round().toString()); },
                    )),
                    SizedBox(width: 32, child: Text('${_subSize.round()}', style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.right)),
                  ]),
                  const SizedBox(height: 4),
                  // Scale slider
                  const Text('Scale', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(children: [
                    Expanded(child: Slider(
                      value: _subScale, min: 0.5, max: 2.0, divisions: 15,
                      activeColor: Colors.white, inactiveColor: Colors.white24,
                      onChanged: (v) { setState(() => _subScale = v); widget.onSubPropertyChanged('sub-scale', v.toStringAsFixed(2)); },
                    )),
                    SizedBox(width: 40, child: Text('${(_subScale * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.right)),
                  ]),
                  const SizedBox(height: 4),
                  // Bold toggle
                  SwitchListTile(
                    title: const Text('Bold', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: _subBold,
                    onChanged: (v) {
                      setState(() => _subBold = v);
                      widget.onSubPropertyChanged('sub-bold', v ? 'yes' : 'no');
                    },
                    activeColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 4),
                  // Color picker
                  GestureDetector(
                    onTap: () => _showColorPicker(context, _subColorPresets, _subColor, (col) {
                      setState(() => _subColor = col);
                      final hex = '#'
                          + col.red.toRadixString(16).padLeft(2, '0')
                          + col.green.toRadixString(16).padLeft(2, '0')
                          + col.blue.toRadixString(16).padLeft(2, '0');
                      widget.onSubPropertyChanged('sub-color', hex);
                    }),
                    child: Row(children: [
                      const Expanded(child: Text('Text color', style: TextStyle(color: Colors.white, fontSize: 14))),
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: _subColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  // Background picker
                  GestureDetector(
                    onTap: () => _showColorPicker(context, _subBgPresets, _subBg, (col) {
                      setState(() => _subBg = col);
                      if (col == Colors.transparent) {
                        widget.onSubPropertyChanged('sub-back-color', '#00000000');
                      } else {
                        final hex = col.red.toRadixString(16).padLeft(2, '0')
                            + col.green.toRadixString(16).padLeft(2, '0')
                            + col.blue.toRadixString(16).padLeft(2, '0');
                        widget.onSubPropertyChanged('sub-back-color', '#ff$hex');
                      }
                    }),
                    child: Row(children: [
                      const Expanded(child: Text('Background', style: TextStyle(color: Colors.white, fontSize: 14))),
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: _subBg == Colors.transparent ? Colors.transparent : _subBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38),
                        ),
                        child: _subBg == Colors.transparent
                            ? const Icon(Icons.block, color: Colors.white38, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  // Fade out slider
                  const Text('Fade out', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(children: [
                    Expanded(child: Slider(
                      value: _subFade, min: 0.0, max: 1.0, divisions: 10,
                      activeColor: Colors.white, inactiveColor: Colors.white24,
                      onChanged: (v) { setState(() => _subFade = v); widget.onSubPropertyChanged('sub-opacity', v.toStringAsFixed(2)); },
                    )),
                    SizedBox(width: 40, child: Text('${(_subFade * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.right)),
                  ]),
                ],
                if (_tab == 4) ...[
                  const Text('Layout', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  // Alignment
                  const Text('Alignment', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(_subAligns.length, (i) => Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _subAlignIdx = i);
                          const _mpvAligns = ['left', 'center', 'right'];
                          widget.onSubPropertyChanged('sub-align-x', _mpvAligns[i]);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _subAlignIdx == i ? Colors.white24 : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_subAligns[i],
                            style: TextStyle(
                              color: _subAlignIdx == i ? Colors.white : Colors.white54,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )),
                  ),
                  const SizedBox(height: 12),
                  // Bottom margin
                  const Text('Bottom margin', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Row(children: [
                    Expanded(child: Slider(
                      value: _subBottomMargin, min: 0, max: 200, divisions: 40,
                      activeColor: Colors.white, inactiveColor: Colors.white24,
                      onChanged: (v) => setState(() => _subBottomMargin = v),
                      onChangeEnd: (v) {
                        // Notify main state so _applySubtitleMargin has current base
                        widget.onSubPropertyChanged('sub-margin-y', v.round().toString());
                        widget.onSubPropertyChanged('_sub_margin_main', v.toStringAsFixed(1));
                      },
                    )),
                    SizedBox(width: 36, child: Text('${_subBottomMargin.round()}px', style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.right)),
                  ]),
                  const SizedBox(height: 4),
                  // Fit to video toggle
                  SwitchListTile(
                    title: const Text('Fit subtitles into video size', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: _subFitToVideo,
                    onChanged: (v) {
                      setState(() => _subFitToVideo = v);
                      widget.onSubPropertyChanged('sub-ass-scale-with-window', v ? 'yes' : 'no');
                    },
                    activeColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                if (_tab == 0 && !widget.isLocal) ...[
                // ── Online Subtitle Search ─────────────────────────────────
                const Text('Search Online', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                // Search field
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Enter title to search...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: Colors.white10,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                                onPressed: () => setState(() => _searchController.clear()),
                                padding: EdgeInsets.zero,
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _fetchOnlineSubtitles(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _onlineLoading ? null : () => _fetchOnlineSubtitles(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _onlineLoading ? Colors.white12 : Colors.white24,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _onlineLoading
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Search', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // Language chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final lang in [
                      ('🇵🇰 Urdu', 'urd'),
                      ('🇮🇳 Hindi', 'hin'),
                      ('🇵🇰+🇮🇳', 'urd,hin'),
                      ('🇬🇧 English', 'eng'),
                      ('🇸🇦 Arabic', 'ara'),
                      ('🌍 All', ''),
                    ])
                      GestureDetector(
                        onTap: () {
                          setState(() => _selectedLangCode = lang.$2);
                          _fetchOnlineSubtitles(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _selectedLangCode == lang.$2
                                ? const Color(0xFF4A9EFF)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(lang.$1,
                              style: TextStyle(
                                color: _selectedLangCode == lang.$2 ? Colors.white : Colors.white60,
                                fontSize: 12,
                                fontWeight: _selectedLangCode == lang.$2
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                // Error state with retry
                if (!_onlineLoading && _onlineError.isNotEmpty) ...[
                  Row(children: [
                    Expanded(child: Text(_onlineError,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                    TextButton(
                      onPressed: () => _fetchOnlineSubtitles(context),
                      child: const Text('Retry', style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
                // Idle state — not yet searched
                if (!_hasSearched && !_onlineLoading && _onlineError.isEmpty)
                  const Text('Auto-searching... or tap Search.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                // Results
                if (!_onlineLoading && _onlineResults.isNotEmpty) ...[
                  Text('${_onlineResults.length} subtitles found:',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 8),
                  for (final r in _onlineResults)
                    GestureDetector(
                      onTap: () => _downloadOnlineSubtitle(context, r),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (r['SubFileName'] ?? '').replaceAll('.gz', ''),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                // Language badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4A9EFF).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    (r['LanguageName'] ?? r['SubLanguageID'] ?? '').toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 9, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '↓ ${r['SubDownloadsCnt'] ?? '0'}  •  ⭐ ${double.tryParse(r['SubRating'] ?? '0')?.toStringAsFixed(1) ?? '-'}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              ]),
                            ],
                          )),
                          const SizedBox(width: 8),
                          const Icon(Icons.download_rounded, color: Colors.white54, size: 20),
                        ]),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
              ],
              // Customization tab (tab 5)
              if (_tab == 5) ...[
                const Text('Subtitle Style', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                // Position (top / center / bottom)
                const Text('Position', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (int i = 0; i < 3; i++) Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _subPositionIdx = i);
                          const mpvY = ['top', 'center', 'bottom'];
                          widget.onSubPropertyChanged('sub-align-y', mpvY[i]);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _subPositionIdx == i ? Colors.white24 : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(const ['Top','Center','Bottom'][i],
                            style: TextStyle(color: _subPositionIdx == i ? Colors.white : Colors.white54, fontSize: 13),
                            textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Shadow style
                const Text('Shadow', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (int i = 0; i < 4; i++) Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _subShadowIdx = i);
                          const depths = ['0', '0', '3', '0'];
                          const outlines = ['0', '1.5', '0', '0'];
                          widget.onSubPropertyChanged('sub-shadow-offset', depths[i]);
                          widget.onSubPropertyChanged('sub-outline-size', outlines[i]);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: _subShadowIdx == i ? Colors.white24 : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(const ['None','Outline','Shadow','Box'][i],
                            style: TextStyle(color: _subShadowIdx == i ? Colors.white : Colors.white54, fontSize: 11),
                            textAlign: TextAlign.center, maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Opacity
                const Text('Opacity', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  Expanded(child: Slider(
                    value: _subOpacity, min: 0.1, max: 1.0, divisions: 9,
                    activeColor: Colors.white, inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() { _subOpacity = v; _subFade = v; }),
                    onChangeEnd: (v) {
                      // sub-opacity is the correct property; sub-color must not be touched here
                      widget.onSubPropertyChanged('sub-opacity', v.toStringAsFixed(2));
                    },
                  )),
                  SizedBox(width: 40, child: Text('${(_subOpacity * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.right)),
                ]),
                const SizedBox(height: 6),
                // Edge padding
                const Text('Edge padding', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  Expanded(child: Slider(
                    value: _subEdgePadding, min: 0, max: 60, divisions: 12,
                    activeColor: Colors.white, inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => _subEdgePadding = v),
                    onChangeEnd: (v) => widget.onSubPropertyChanged('sub-margin-x', v.round().toString()),
                  )),
                  SizedBox(width: 40, child: Text('${_subEdgePadding.round()} px',
                      style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.right)),
                ]),
                const SizedBox(height: 6),
                // Line spacing
                const Text('Line spacing', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  Expanded(child: Slider(
                    value: _subLineSpacing, min: 0.8, max: 2.5, divisions: 17,
                    activeColor: Colors.white, inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => _subLineSpacing = v),
                    onChangeEnd: (v) => widget.onSubPropertyChanged('sub-spacing', v.toStringAsFixed(1)),
                  )),
                  SizedBox(width: 40, child: Text('${_subLineSpacing.toStringAsFixed(1)}×',
                      style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.right)),
                ]),
              ],
              // AI Dub tab (tab 6) — B1 fix: dub controls moved here from the
              // pinned block above the tab row, which blocked all settings in
              // landscape mode (~213 dp of fixed height with no scrolling).
              if (_tab == 6 && widget.onDubRequested != null) ..._buildDubSection(context),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  AUDIO TRACK PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _AudioTrackPanel extends StatefulWidget {
  final List<AudioTrack> tracks;
  final AudioTrack? selectedTrack;
  final double audioSync;
  final bool useSWDecoder;
  final void Function(AudioTrack?) onTrackSelected;
  final void Function(double) onSyncChanged;
  final void Function(bool) onSWDecoderChanged;
  final void Function(String) onChannelModeChanged;
  final int initialChannelModeIdx;
  final bool isPlaying; // P57-04: disable SW decoder toggle during playback
  final String? currentCodec; // P57-06: show codec badge on active track
  final VoidCallback onClose;
  final bool isDubMode;        // P60: dub active indicator
  final String dubActiveLang;  // P60: 'ur-PK' or 'hi-IN'
  final VoidCallback? onRemoveDub; // P60: tap to disable dub

  const _AudioTrackPanel({
    required this.tracks,
    required this.selectedTrack,
    required this.audioSync,
    required this.useSWDecoder,
    required this.onTrackSelected,
    required this.onSyncChanged,
    required this.onSWDecoderChanged,
    required this.onChannelModeChanged,
    this.initialChannelModeIdx = 0,
    this.isPlaying = false,
    this.currentCodec,
    required this.onClose,
    this.isDubMode = false,
    this.dubActiveLang = 'ur-PK',
    this.onRemoveDub,
  });

  @override
  State<_AudioTrackPanel> createState() => _AudioTrackPanelState();
}

class _VideoZoomPanel extends StatelessWidget {
  final int selectedMode;
  final void Function(int) onModeSelected;
  final VoidCallback onClose;

  const _VideoZoomPanel({
    required this.selectedMode,
    required this.onModeSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    const modes = ['Fit to screen', 'Stretch', 'Crop', '100%', 'Pinch & Zoom'];
    return Column(
      children: [
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('Video zoom', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (int i = 0; i < modes.length; i++)
                RadioListTile<int>(
                  value: i,
                  groupValue: selectedMode,
                  onChanged: (v) => v != null ? onModeSelected(v) : null,
                  title: Text(modes[i], style: const TextStyle(color: Colors.white, fontSize: 14)),
                  activeColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  AUDIO EFFECT PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _AudioEffectPanel extends StatefulWidget {
  final int selectedPreset;
  final List<double> eqBands;
  final bool eqEnabled;
  final void Function(int) onPresetSelected;
  final void Function(int, double) onEqBandChanged;
  final void Function(bool) onEqEnabledChanged;
  final void Function(String?) onReverbChanged;
  final void Function(String) onLabAfChanged;
  final void Function(bool vocal, bool dialogue, bool norm, bool bass, double bassLevel) onLabStateChanged;
  final double audioBalance;
  final void Function(double) onBalanceChanged;
  // Lab initial state (persisted across panel reopens)
  final bool labVocal;
  final bool labDialogue;
  final bool labNorm;
  final bool labBass;
  final double labBassLevel;
  final String initialReverbPreset;
  final VoidCallback onClose;

  const _AudioEffectPanel({
    required this.selectedPreset,
    required this.eqBands,
    required this.eqEnabled,
    required this.onPresetSelected,
    required this.onEqBandChanged,
    required this.onEqEnabledChanged,
    required this.onReverbChanged,
    required this.onLabAfChanged,
    required this.onLabStateChanged,
    required this.audioBalance,
    required this.onBalanceChanged,
    this.labVocal = false,
    this.labDialogue = false,
    this.labNorm = false,
    this.labBass = false,
    this.labBassLevel = 0.5,
    this.initialReverbPreset = 'None',
    required this.onClose,
  });

  @override
  State<_AudioEffectPanel> createState() => _AudioEffectPanelState();
}

class _AudioEffectPanelState extends State<_AudioEffectPanel> {
  int _tab = 0; // 0=Presets 1=Equalizer 2=Lab
  late List<double> _bands;
  late int _preset;
  late bool _eqEnabled;
  // P8: Lab state (initialized from widget props in initState)
  late bool _labVocal;
  late bool _labDialogue;
  late bool _labNorm;
  late bool _labBass;
  late double _labBassLevel;

  void _applyLabAf() {
    final parts = <String>[];
    // Vocal remover: phase-cancel center channel (works on stereo content)
    if (_labVocal) parts.add('pan=stereo|c0=c0-c1|c1=c1-c0');
    // Dialogue boost: 10-band equalizer boosting speech-clarity range 2-5kHz
    // MPV equalizer filter syntax: gain values for each of 10 bands
    if (_labDialogue) parts.add('equalizer=0:0:0:0:0:0:3:4:2:0');
    // Audio normalization: dynamic audio normalizer
    if (_labNorm) parts.add('dynaudnorm=f=150:g=15');
    // Bass boost: lavfi low-shelf filter (correct MPV af syntax)
    if (_labBass) {
      final db = (_labBassLevel * 12).round().clamp(1, 12);
      // lavfi aecho for bass: use low-shelf equalizer — 10-band equalizer
      // boosting the low bands (31Hz, 62Hz) by db amount
      parts.add('equalizer=$db:$db:0:0:0:0:0:0:0:0');
    }
    widget.onLabAfChanged(parts.isEmpty ? '' : parts.join(','));
    widget.onLabStateChanged(_labVocal, _labDialogue, _labNorm, _labBass, _labBassLevel);
  }

  static const _presetNames = ['Original', 'Treble Boost', 'Bass Boost', 'Clarity', 'Movie', 'Music'];
  static const _presetIcons = [
    Icons.music_note_rounded,
    Icons.arrow_upward_rounded,
    Icons.arrow_downward_rounded,
    Icons.wb_sunny_rounded,
    Icons.local_movies_rounded,
    Icons.library_music_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _bands = List.from(widget.eqBands);
    _preset = widget.selectedPreset;
    _eqEnabled = widget.eqEnabled;
    _labVocal = widget.labVocal;
    _labDialogue = widget.labDialogue;
    _labNorm = widget.labNorm;
    _labBass = widget.labBass;
    _labBassLevel = widget.labBassLevel;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(4, 10, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Text('Audio Effect',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              // Tab row — separate line so it never overflows on narrow portrait sheets
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Row(
                  children: [
                    for (final entry in [
                      (label: 'Presets', idx: 0),
                      (label: 'Equalizer', idx: 1),
                      (label: 'Lab', idx: 2),
                    ])
                      GestureDetector(
                        onTap: () => setState(() => _tab = entry.idx),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20, top: 4, bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.label,
                                  style: TextStyle(
                                    color: _tab == entry.idx ? Colors.white : Colors.white54,
                                    fontSize: 13,
                                    fontWeight: _tab == entry.idx ? FontWeight.bold : FontWeight.normal,
                                  )),
                              const SizedBox(height: 4),
                              if (_tab == entry.idx)
                                Container(height: 2, width: 32, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        if (_tab == 0)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  for (int i = 0; i < _presetNames.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _preset = i);
                        widget.onPresetSelected(i);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _preset == i
                              ? const Color(0xFF3A6ECC).withOpacity(0.6)
                              : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _preset == i ? const Color(0xFF4A7EDD) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_presetIcons[i], color: Colors.white70, size: 18),
                            const SizedBox(width: 6),
                            Text(_presetNames[i],
                                style: TextStyle(
                                  color: _preset == i ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: _preset == i ? FontWeight.bold : FontWeight.normal,
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // P8: Lab tab content
        if (_tab == 2)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const Text('Audio Lab', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                _LabToggleRow(
                  icon: Icons.mic_off_rounded,
                  title: 'Vocal Remover',
                  subtitle: 'Phase-cancel centre-channel vocals',
                  enabled: _labVocal,
                  onChanged: (v) { setState(() => _labVocal = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Dialogue Boost',
                  subtitle: 'Boosts 2–5 kHz speech clarity',
                  enabled: _labDialogue,
                  onChanged: (v) { setState(() => _labDialogue = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Audio Normalization',
                  subtitle: 'Dynamic normalize — evens loud/quiet scenes',
                  enabled: _labNorm,
                  onChanged: (v) { setState(() => _labNorm = v); _applyLabAf(); },
                ),
                _LabToggleRow(
                  icon: Icons.speaker_rounded,
                  title: 'Bass Boost',
                  subtitle: 'Enhances low-frequency response',
                  enabled: _labBass,
                  onChanged: (v) { setState(() => _labBass = v); _applyLabAf(); },
                ),
                if (_labBass) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Row(children: [
                      const Icon(Icons.volume_down_rounded, color: Colors.white38, size: 16),
                      Expanded(child: Slider(
                        value: _labBassLevel,
                        min: 0, max: 1, divisions: 10,
                        activeColor: const Color(0xFFE8950A),
                        inactiveColor: Colors.white12,
                        onChanged: (v) { setState(() => _labBassLevel = v); _applyLabAf(); },
                      )),
                      const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 36, child: Text(
                        '${(_labBassLevel * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        textAlign: TextAlign.right,
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.orange, size: 14),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lab, EQ and Reverb now stack — all active together.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
                  child: Text('L / R Balance',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Row(children: [
                  const Text('L', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(child: Slider(
                    value: widget.audioBalance,
                    min: -1.0, max: 1.0, divisions: 20,
                    activeColor: Colors.white, inactiveColor: Colors.white24,
                    onChanged: widget.onBalanceChanged,
                  )),
                  const Text('R', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      widget.audioBalance.abs() < 0.02
                          ? 'Center'
                          : widget.audioBalance < 0
                              ? 'Left ${(-widget.audioBalance * 100).round()}%'
                              : 'Right ${(widget.audioBalance * 100).round()}%',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => widget.onBalanceChanged(0.0),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white38,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Reset', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (_tab == 1)
          Expanded(
            child: Column(
              children: [
                // EQ on/off toggle
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Text('Equalizer', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: _eqEnabled,
                        onChanged: (v) {
                          setState(() => _eqEnabled = v);
                          widget.onEqEnabledChanged(v);
                        },
                        activeColor: Colors.white,
                      ),
                    ],
                  ),
                ),
                // EQ band sliders
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < 5; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: -1,
                                    child: Slider(
                                      value: _bands[i],
                                      min: -10, max: 10,
                                      divisions: 20,
                                      activeColor: Colors.white,
                                      inactiveColor: Colors.white24,
                                      onChanged: (v) {
                                        setState(() => _bands[i] = v);
                                        widget.onEqBandChanged(i, v);
                                      },
                                    ),
                                  ),
                                ),
                                Text(
                                  ['60Hz', '230Hz', '910Hz', '3.6k', '14k'][i],
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_bands[i] >= 0 ? '+' : ''}${_bands[i].round()}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Reverb — real selector
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _ReverbSelector(onChanged: widget.onReverbChanged, initialPreset: widget.initialReverbPreset),
              ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  QUICK SHORTCUTS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _QuickShortcutsPanel extends StatefulWidget {
  final bool isLocked;
  final bool isMuted;
  final bool loopEnabled;
  final bool smartEnhanceEnabled;
  final bool isOneHanded;
  final int? sleepTimerMinutes;
  final DateTime? sleepTimerEnd;
  final double speed;
  final Duration? abA;
  final Duration? abB;
  final bool abActive;
  final bool isRotateLocked;
  final VoidCallback onRotate;
  final VoidCallback onLockToggle;
  final VoidCallback onMuteToggle;
  final VoidCallback onLoopToggle;
  final VoidCallback onSmartEnhanceToggle;
  final VoidCallback onOneHandedToggle;
  final void Function(int?) onSleepTimer;
  final void Function(double) onSpeedSelected;
  final VoidCallback onAudioEffect;
  final VoidCallback onSettingsOpen;
  final VoidCallback onAbSet;
  final VoidCallback onFrameStep;
  final VoidCallback onClose;
  // Extended shortcuts
  final VoidCallback onJumpTo;
  final VoidCallback onSpeedPresets;
  final VoidCallback onEndAction;
  final VoidCallback onScreenshot;
  final VoidCallback? onScreenshotWithSubtitles;
  final VoidCallback onWatchParty;
  final VoidCallback onSilenceSkip;
  final VoidCallback onZoomCrop;
  final VoidCallback onGestureMap;
  final VoidCallback onSkipEditor;
  final VoidCallback onLayoutDesigner;
  final bool silenceSkipEnabled;
  final String endAction;
  final VoidCallback onPiP;
  final VoidCallback onSidebarEdit;

  const _QuickShortcutsPanel({
    required this.isLocked,
    required this.isMuted,
    required this.loopEnabled,
    required this.smartEnhanceEnabled,
    required this.isOneHanded,
    required this.sleepTimerMinutes,
    required this.sleepTimerEnd,
    required this.speed,
    required this.abA,
    required this.abB,
    required this.abActive,
    required this.isRotateLocked,
    required this.onRotate,
    required this.onLockToggle,
    required this.onMuteToggle,
    required this.onLoopToggle,
    required this.onSmartEnhanceToggle,
    required this.onOneHandedToggle,
    required this.onSleepTimer,
    required this.onSpeedSelected,
    required this.onAudioEffect,
    required this.onSettingsOpen,
    required this.onAbSet,
    required this.onFrameStep,
    required this.onClose,
    required this.onJumpTo,
    required this.onSpeedPresets,
    required this.onEndAction,
    required this.onScreenshot,
    this.onScreenshotWithSubtitles,
    required this.onWatchParty,
    required this.onSilenceSkip,
    required this.onZoomCrop,
    required this.onGestureMap,
    required this.onSkipEditor,
    required this.onLayoutDesigner,
    required this.silenceSkipEnabled,
    required this.endAction,
    required this.onPiP,
    required this.onSidebarEdit,
  });

  @override
  State<_QuickShortcutsPanel> createState() => _QuickShortcutsPanelState();
}

class _QuickShortcutsPanelState extends State<_QuickShortcutsPanel> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh every 10s so sleep-timer countdown ticks live (Rule 19: ≤10s)
    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final abA = widget.abA; final abB = widget.abB;
    final abActive = widget.abActive;
    final sleepTimerEnd = widget.sleepTimerEnd;
    final speed = widget.speed;
    final isLocked = widget.isLocked;
    final isMuted = widget.isMuted;
    final loopEnabled = widget.loopEnabled;
    final isRotateLocked = widget.isRotateLocked;
    final sleepTimerMinutes = widget.sleepTimerMinutes;
    final smartEnhanceEnabled = widget.smartEnhanceEnabled;
    final isOneHanded = widget.isOneHanded;

    String abLabel = 'A-B';
    if (abA != null && abB == null) abLabel = 'A-B (A set)';
    if (abActive) abLabel = 'A-B ●';

    String sleepLabel = 'Sleep';
    if (sleepTimerEnd != null) {
      final remaining = sleepTimerEnd.difference(DateTime.now());
      if (remaining.isNegative) {
        sleepLabel = 'Sleep';
      } else {
        sleepLabel = 'Sleep ${remaining.inMinutes}m';
      }
    }

    return Column(
      children: [
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('More', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, top: 4),
                child: Text('Quick Shortcuts', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),

              // Row 1 of shortcuts
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.screen_rotation_rounded, 'Rotate', isRotateLocked, widget.onRotate),
                  _ShortcutItem(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Mute', isMuted, widget.onMuteToggle),
                  _ShortcutItem(Icons.equalizer_rounded, 'Equalizer', false, widget.onAudioEffect),
                  _ShortcutItem(Icons.timer_rounded, sleepLabel, sleepTimerMinutes != null, () {
                    _showSleepTimerDialog(context);
                  }),
                ],
              ),

              const SizedBox(height: 8),

              // Row 2 of shortcuts
              _ShortcutGrid(
                items: [
                  _ShortcutItem(
                      Icons.speed_rounded,
                      '${speed == speed.roundToDouble() ? speed.toInt() : speed.toStringAsFixed(2)}×',
                      speed != 1.0,
                      () { _showSpeedDialog(context); }),
                  _ShortcutItem(Icons.loop_rounded, 'Loop', loopEnabled, widget.onLoopToggle),
                  _ShortcutItem(Icons.repeat_one_rounded, abLabel, abActive, widget.onAbSet),
                  _ShortcutItem(Icons.lock_rounded, 'Lock', isLocked, widget.onLockToggle),
                ],
              ),

              const SizedBox(height: 8),

              // Row 3 — advanced
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.skip_next_rounded, 'Frame Step', false, widget.onFrameStep),
                  _ShortcutItem(Icons.smart_display_rounded, 'Smart View', smartEnhanceEnabled, widget.onSmartEnhanceToggle),
                  _ShortcutItem(Icons.settings_rounded, 'Settings', false, widget.onSettingsOpen),
                  _ShortcutItem(Icons.pan_tool_alt_rounded, '1-Hand', isOneHanded, widget.onOneHandedToggle),
                ],
              ),

              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 6),
                child: Text('Features', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),

              // Row 4 — navigation features
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.access_time_rounded, 'Jump To', false, widget.onJumpTo),
                  _ShortcutItem(Icons.speed_outlined, 'Speed List', false, widget.onSpeedPresets),
                  _ShortcutItem(Icons.last_page_rounded, 'End Action', widget.endAction != 'play_next', widget.onEndAction),
                  _ShortcutItem(Icons.camera_alt_rounded, 'Screenshot', false, widget.onScreenshot,
                      widget.onScreenshotWithSubtitles),
                ],
              ),

              const SizedBox(height: 8),

              // Row 5 — audio & silence
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.people_rounded, 'Watch Party', false, widget.onWatchParty),
                  _ShortcutItem(Icons.volume_off_outlined, 'Silence Skip', widget.silenceSkipEnabled, widget.onSilenceSkip),
                  _ShortcutItem(Icons.touch_app_rounded, 'Gestures', false, widget.onGestureMap),
                  _ShortcutItem(Icons.content_cut_rounded, 'Skip Editor', false, widget.onSkipEditor),
                ],
              ),

              const SizedBox(height: 8),

              // Row 6 — video & layout
              _ShortcutGrid(
                items: [
                  _ShortcutItem(Icons.crop_rounded, 'Zoom & Crop', false, widget.onZoomCrop),
                  _ShortcutItem(Icons.dashboard_customize_rounded, 'Layout', false, widget.onLayoutDesigner),
                  _ShortcutItem(Icons.picture_in_picture_alt_rounded, 'PiP', false, widget.onPiP),
                  _ShortcutItem(Icons.tune_rounded, 'Sidebar', false, widget.onSidebarEdit),
                ],
              ),

            ],
          ),
        ),
      ],
    );
  }

  void _showSleepTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Sleep Timer', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mins in [15, 30, 45, 60, 90, null])
              ListTile(
                title: Text(
                  mins == null ? 'Disable' : '$mins minutes',
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: widget.sleepTimerMinutes == mins
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onSleepTimer(mins);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in speeds)
              ListTile(
                title: Text('${s == s.roundToDouble() ? s.toInt() : s}×', style: const TextStyle(color: Colors.white)),
                trailing: widget.speed == s ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onSpeedSelected(s);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  _ShortcutItem(this.icon, this.label, this.active, this.onTap, [this.onLongPress]);
}

class _ShortcutGrid extends StatelessWidget {
  final List<_ShortcutItem> items;
  const _ShortcutGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.map((item) => Expanded(
        child: GestureDetector(
          onTap: item.onTap,
          onLongPress: item.onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: item.active ? Colors.white.withOpacity(0.15) : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(item.icon, color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(item.label, style: const TextStyle(color: Colors.white70, fontSize: 10),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      )).toList(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SETTINGS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsPanel extends StatefulWidget {
  final bool showRemainingTime;
  final bool keepScreenOn;
  final int skipInterval;
  final void Function(bool) onShowRemainingChanged;
  final void Function(bool) onKeepScreenChanged;
  final void Function(int) onSkipIntervalChanged;
  final double seekSwipeSec;
  final void Function(double) onSeekSwipeSpeedChanged;
  // P14: accent color + progress bar style
  final int accentColorIdx;
  final int progressBarStyle;
  final void Function(int) onAccentColorChanged;
  final void Function(int) onProgressBarStyleChanged;
  // P12: background audio
  final bool backgroundAudio;
  final void Function(bool) onBackgroundAudioChanged;
  // Night mode + clock
  final bool nightModeEnabled;
  final double nightWarmth;
  final void Function(bool) onNightModeToggle;
  final void Function(double) onNightWarmthChanged;
  final bool showClockInTitle;
  final void Function(bool) onClockToggle;
  final double initialBrightness;
  final void Function(bool) onShowSkipBtnsChanged;
  final void Function(bool) onShowPrevNextBtnsChanged;
  final void Function(bool) onShowSeekPositionChanged;
  // Initial values for navigation toggles
  final bool showSkipBtns;
  final bool showPrevNextBtns;
  final bool showSeekPosition;
  // Video rotate shortcut
  final VoidCallback onRotateVideo;
  final VoidCallback onClose;
  // Gesture toggles
  final bool doubleTapSeekEnabled;
  final bool longPressSpeedEnabled;
  final bool swipeSeekEnabled;
  final bool swipeBVEnabled;
  final void Function(bool) onDoubleTapSeekChanged;
  final void Function(bool) onLongPressSpeedChanged;
  final void Function(bool) onSwipeSeekChanged;
  final void Function(bool) onSwipeBVChanged;
  // Voice commands
  final bool voiceCommandsEnabled;
  final void Function(bool) onVoiceCommandsChanged;
  // Video info (optional — shows in Style tab)
  final VoidCallback? onVideoInfo;

  const _SettingsPanel({
    required this.showRemainingTime,
    required this.keepScreenOn,
    required this.skipInterval,
    required this.onShowRemainingChanged,
    required this.onKeepScreenChanged,
    required this.onSkipIntervalChanged,
    required this.seekSwipeSec,
    required this.onSeekSwipeSpeedChanged,
    required this.accentColorIdx,
    required this.progressBarStyle,
    required this.onAccentColorChanged,
    required this.onProgressBarStyleChanged,
    required this.backgroundAudio,
    required this.onBackgroundAudioChanged,
    required this.nightModeEnabled,
    required this.nightWarmth,
    required this.onNightModeToggle,
    required this.onNightWarmthChanged,
    required this.showClockInTitle,
    required this.onClockToggle,
    required this.initialBrightness,
    required this.onShowSkipBtnsChanged,
    required this.onShowPrevNextBtnsChanged,
    required this.onShowSeekPositionChanged,
    required this.showSkipBtns,
    required this.showPrevNextBtns,
    required this.showSeekPosition,
    required this.onRotateVideo,
    required this.onClose,
    required this.doubleTapSeekEnabled,
    required this.longPressSpeedEnabled,
    required this.swipeSeekEnabled,
    required this.swipeBVEnabled,
    required this.onDoubleTapSeekChanged,
    required this.onLongPressSpeedChanged,
    required this.onSwipeSeekChanged,
    required this.onSwipeBVChanged,
    required this.voiceCommandsEnabled,
    required this.onVoiceCommandsChanged,
    this.onVideoInfo,
  });

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  int _tab = 0; // 0=Style 1=Screen 2=Controls 3=Navigation
  late bool _showRemaining;
  late bool _keepScreenOn;
  late int _skipInterval;
  late double _seekSwipeSec;
  late int _accentIdx;
  late int _pbStyle;
  late bool _backgroundAudio;
  // Navigation tab real toggles (initialized from widget props in initState)
  late bool _showSkipBtns;
  late bool _showPrevNextBtns;
  late bool _showSeekPosition;
  // Screen tab brightness
  double _screenBrightness = 0.5;

  @override
  void initState() {
    super.initState();
    _showRemaining = widget.showRemainingTime;
    _keepScreenOn = widget.keepScreenOn;
    _skipInterval = widget.skipInterval;
    _seekSwipeSec = widget.seekSwipeSec;
    _accentIdx = widget.accentColorIdx;
    _pbStyle = widget.progressBarStyle;
    _backgroundAudio = widget.backgroundAudio;
    _screenBrightness = widget.initialBrightness;
    _showSkipBtns = widget.showSkipBtns;
    _showPrevNextBtns = widget.showPrevNextBtns;
    _showSeekPosition = widget.showSeekPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),

              // Tab bar
              Row(
                children: [
                  for (final tab in ['Style', 'Screen', 'Controls', 'Navigation'])
                    GestureDetector(
                      onTap: () => setState(() => _tab = ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16, top: 8, bottom: 0),
                        child: Column(
                          children: [
                            Text(tab,
                                style: TextStyle(
                                  color: _tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: _tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                )),
                            const SizedBox(height: 6),
                            if (_tab == ['Style', 'Screen', 'Controls', 'Navigation'].indexOf(tab))
                              Container(height: 2, width: 40, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        Expanded(
          child: _tab == 0 ? _buildStyleTab() :
                 _tab == 1 ? _buildScreenTab() :
                 _tab == 2 ? _buildControlsTab() :
                 _buildNavigationTab(),
        ),
      ],
    );
  }

  Widget _buildStyleTab() {
    const accentColors = [Color(0xFFE8950A), Color(0xFF3A8EF5), Color(0xFF34C759), Color(0xFFFF2D55)];
    const accentNames = ['Orange', 'Blue', 'Green', 'Pink'];
    const pbStyles = [
      'Slim', 'Thick', 'Accent',          // 0-2  classic built-in
      'Gradient', 'Bold', 'Waveform',      // 3-5  SeekBarPainter
      'Neon', 'Filmstrip', 'Chapters',     // 6-8
      'Dots', 'Minimal',                   // 9-10
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Video info shortcut (replaces the old top-bar info button)
        if (widget.onVideoInfo != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
            ),
            title: const Text('Video information',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Resolution, codec, stream details',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
            onTap: widget.onVideoInfo,
          ),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
        ],
        // P14: Accent colour picker
        const Text('Accent colour', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (int i = 0; i < accentColors.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _accentIdx = i);
                    widget.onAccentColorChanged(i);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: accentColors[i],
                          shape: BoxShape.circle,
                          border: _accentIdx == i
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(accentNames[i],
                          style: TextStyle(
                              color: _accentIdx == i ? Colors.white : Colors.white38,
                              fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        // P14: Progress bar style
        const Text('Progress bar style', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        for (int i = 0; i < pbStyles.length; i++)
          GestureDetector(
            onTap: () {
              setState(() => _pbStyle = i);
              widget.onProgressBarStyleChanged(i);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(
                  _pbStyle == i ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: _pbStyle == i ? Colors.white : Colors.white38, size: 18),
                const SizedBox(width: 8),
                Text(pbStyles[i], style: TextStyle(
                    color: _pbStyle == i ? Colors.white : Colors.white60, fontSize: 14)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildScreenTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Display', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),

        SwitchListTile(
          title: const Text('Show Remaining Time', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: _showRemaining,
          onChanged: (v) {
            setState(() => _showRemaining = v);
            widget.onShowRemainingChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),

        SwitchListTile(
          title: const Text('Keep Screen On', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: _keepScreenOn,
          onChanged: (v) {
            setState(() => _keepScreenOn = v);
            widget.onKeepScreenChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),

        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text('Status bar in player', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),

        SwitchListTile(
          title: const Text('Show clock / time', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: widget.showClockInTitle,
          onChanged: widget.onClockToggle,
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text('Screen brightness', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.brightness_low_rounded, color: Colors.white38, size: 18),
            Expanded(
              child: Slider(
                value: _screenBrightness,
                min: 0.05, max: 1.0,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) async {
                  setState(() => _screenBrightness = v);
                  await ScreenBrightness().setScreenBrightness(v);
                },
              ),
            ),
            const Icon(Icons.brightness_high_rounded, color: Colors.white, size: 18),
            SizedBox(
              width: 36,
              child: Text(
                '${(_screenBrightness * 100).round()}%',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),

        const Divider(color: Colors.white12),

        SwitchListTile(
          title: const Text('Night mode (eye comfort)', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Warm filter — reduces blue light', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.nightModeEnabled,
          onChanged: widget.onNightModeToggle,
          activeColor: Colors.orange,
        ),
        if (widget.nightModeEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Warmth', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  const Icon(Icons.wb_sunny_outlined, color: Colors.white38, size: 16),
                  Expanded(child: Slider(
                    value: widget.nightWarmth, min: 0.1, max: 1.0, divisions: 9,
                    activeColor: Colors.orange, inactiveColor: Colors.white24,
                    onChanged: widget.onNightWarmthChanged,
                  )),
                  const Icon(Icons.wb_sunny_rounded, color: Colors.orange, size: 16),
                ]),
              ],
            ),
          ),
        ],

        const Divider(color: Colors.white12),

        ListTile(
          title: const Text('Rotate video', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Cycles 0° → 90° → 180° → 270°', style: TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: widget.onRotateVideo,
            child: const Text('Rotate'),
          ),
        ),

      ],
    );
  }

  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        // P12: Background audio
        const Text('Background audio', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continue audio in background',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  Text('Audio plays when app is backgrounded',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _backgroundAudio,
              onChanged: (v) {
                setState(() => _backgroundAudio = v);
                widget.onBackgroundAudioChanged(v);
              },
              activeColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text('Gestures', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Double-tap seek', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Double-tap left/right to rewind/forward', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.doubleTapSeekEnabled,
          onChanged: widget.onDoubleTapSeekChanged,
          activeColor: Colors.white,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Long press speed boost', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Hold to play at 2× speed', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.longPressSpeedEnabled,
          onChanged: widget.onLongPressSpeedChanged,
          activeColor: Colors.white,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Swipe to seek', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Horizontal swipe jumps through video', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.swipeSeekEnabled,
          onChanged: widget.onSwipeSeekChanged,
          activeColor: Colors.white,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Swipe brightness / volume', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Left edge: brightness  •  Right edge: volume', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.swipeBVEnabled,
          onChanged: widget.onSwipeBVChanged,
          activeColor: Colors.white,
        ),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text('Voice Commands', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable voice commands', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Say "Pause", "Play", "Forward 30" hands-free', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: widget.voiceCommandsEnabled,
          onChanged: widget.onVoiceCommandsChanged,
          activeColor: Colors.white,
        ),
      ],
    );
  }

  Widget _buildNavigationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Seek Speed (sec / swipe)', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _seekSwipeSec.clamp(30.0, 300.0),
                min: 30, max: 300, divisions: 9,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) {
                  setState(() => _seekSwipeSec = v);
                  widget.onSeekSwipeSpeedChanged(v);
                },
              ),
            ),
            Text('${_seekSwipeSec.round()}s', style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Move interval (seconds)', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _skipInterval.toDouble(),
                min: 5, max: 60, divisions: 11,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) {
                  setState(() => _skipInterval = v.round());
                  widget.onSkipIntervalChanged(v.round());
                },
              ),
            ),
            Text('${_skipInterval}s', style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Forward / backward buttons', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Show ±skip buttons in center controls', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: _showSkipBtns,
          onChanged: (v) {
            setState(() => _showSkipBtns = v);
            widget.onShowSkipBtnsChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Previous / next episode buttons', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Show episode navigation arrows', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: _showPrevNextBtns,
          onChanged: (v) {
            setState(() => _showPrevNextBtns = v);
            widget.onShowPrevNextBtnsChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Show position label while seeking', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Displays timestamp above seek bar during drag', style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: _showSeekPosition,
          onChanged: (v) {
            setState(() => _showSeekPosition = v);
            widget.onShowSeekPositionChanged(v);
          },
          activeColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared small widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SyncBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SyncBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _AudioTrackPanelState extends State<_AudioTrackPanel> {
  late double _sync;
  late bool _useSW;
  late int _chIdx;

  @override
  void initState() {
    super.initState();
    _sync = widget.audioSync;
    _useSW = widget.useSWDecoder;
    _chIdx = widget.initialChannelModeIdx;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('Audio Track', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // P60: Dub active indicator + one-tap remove
              if (widget.isDubMode)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2B0D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00C853).withOpacity(0.55)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          color: Color(0xFF00C853), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Dub Active',
                                style: TextStyle(
                                    color: Color(0xFF00C853),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              widget.dubActiveLang == 'ur-PK'
                                  ? '🇵🇰 Urdu dub is playing'
                                  : '🇮🇳 Hindi dub is playing',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onRemoveDub,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Remove',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              // Track list
              if (widget.tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No audio tracks found.', style: TextStyle(color: Colors.white54)),
                ),

              for (int i = 0; i < widget.tracks.length; i++)
                RadioListTile<AudioTrack>(
                  value: widget.tracks[i],
                  groupValue: widget.selectedTrack,
                  onChanged: (v) => v != null ? widget.onTrackSelected(v) : null,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (widget.tracks[i].language != null && widget.tracks[i].title != null)
                              ? "\${widget.tracks[i].language} (\${widget.tracks[i].title})"
                              : widget.tracks[i].language ?? widget.tracks[i].title ?? "Audio track \${i + 1}",
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      // P57-06: codec badge on active track
                      if (widget.tracks[i] == widget.selectedTrack && widget.currentCodec != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.currentCodec!.toUpperCase(),
                            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  activeColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

              const Divider(color: Colors.white12),

              // Disable
              RadioListTile<AudioTrack?>(
                value: null,
                groupValue: widget.selectedTrack,
                onChanged: (_) => widget.onTrackSelected(null),
                title: const Text('Disable', style: TextStyle(color: Colors.white, fontSize: 14)),
                activeColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
              ),

              const Divider(color: Colors.white12),

              // SW decoder toggle — always enabled; handles DTS/EAC-3/TrueHD/MLP
              SwitchListTile(
                title: const Text('Use SW audio decoder', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                  widget.isPlaying
                      ? 'Seek forward to fully apply'
                      : 'Required for DTS, EAC-3, TrueHD, MLP',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _useSW,
                onChanged: (v) {
                  setState(() => _useSW = v);
                  widget.onSWDecoderChanged(v);
                },
                activeColor: Colors.white,
              ),

              const Divider(color: Colors.white12),

              // Audio channel mode
              ListTile(
                title: const Text('Channel mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: Text(
                  const ['Stereo', 'Mono', 'Left only', 'Right only'][_chIdx],
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                onTap: () {
                  const filters = ['', 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1', 'pan=stereo|c0=c0|c1=c0', 'pan=stereo|c0=c1|c1=c1'];
                  setState(() => _chIdx = (_chIdx + 1) % 4);
                  widget.onChannelModeChanged(filters[_chIdx]);
                },
              ),

              const Divider(color: Colors.white12),

              // AV Sync
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Synchronization', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SyncBtn(label: '−', onTap: () {
                          setState(() => _sync -= 0.1);
                          widget.onSyncChanged(-0.1);
                        }),
                        const SizedBox(width: 16),
                        Text('${_sync.toStringAsFixed(1)}s',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                        _SyncBtn(label: '+', onTap: () {
                          setState(() => _sync += 0.1);
                          widget.onSyncChanged(0.1);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
// ═════════════════════════════════════════════════════════════════════════════
//  _ReverbSelector — reverb room presets (Feature 23)
// ═════════════════════════════════════════════════════════════════════════════

class _ReverbSelector extends StatefulWidget {
  final void Function(String?) onChanged;
  final String initialPreset;
  const _ReverbSelector({required this.onChanged, this.initialPreset = 'None'});

  @override
  State<_ReverbSelector> createState() => _ReverbSelectorState();
}

// ═════════════════════════════════════════════════════════════════════════════
//  P8: _LabToggleRow — simple toggle row for Audio Lab tab
// ═════════════════════════════════════════════════════════════════════════════

class _LabToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _LabToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: enabled ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    color: enabled ? Colors.white : Colors.white70,
                    fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged, activeColor: Colors.white),
        ],
      ),
    );
  }
}

class _ReverbSelectorState extends State<_ReverbSelector> {
  late String _selected;
  static const _presets = ['None', 'Small Room', 'Hall', 'Cathedral', 'Stadium'];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPreset;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Reverb', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        DropdownButton<String>(
          value: _selected,
          dropdownColor: const Color(0xFF2A2A2A),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          items: _presets.map((p) => DropdownMenuItem(
            value: p,
            child: Text(p, style: const TextStyle(color: Colors.white)),
          )).toList(),
          onChanged: (v) {
            setState(() => _selected = v ?? _selected);
            widget.onChanged(v == 'None' ? null : v);
          },
        ),
      ],
    );
  }

}

// ═════════════════════════════════════════════════════════════════════════════
//  SIDEBAR CUSTOMIZER PANEL
//  Lets the user reorder shortcuts and toggle which ones appear in the sidebar.
// ═════════════════════════════════════════════════════════════════════════════

class _SidebarCustomizerPanel extends StatefulWidget {
  final List<String> currentOrder;
  final List<String> allIds;
  final void Function(List<String>) onOrderChanged;
  final VoidCallback onClose;

  const _SidebarCustomizerPanel({
    required this.currentOrder,
    required this.allIds,
    required this.onOrderChanged,
    required this.onClose,
  });

  @override
  State<_SidebarCustomizerPanel> createState() => _SidebarCustomizerPanelState();
}

class _SidebarCustomizerPanelState extends State<_SidebarCustomizerPanel> {
  late List<String> _order;

  // Human-readable labels and icons for each shortcut ID
  static const _labels = <String, String>{
    'cc': 'Subtitles (CC)',  'audio': 'Audio Track',    'eq': 'Equalizer / EQ',
    'speed': 'Speed',        'loop': 'Loop',            'rotate': 'Rotate',
    'lock': 'Lock Screen',   'pip': 'Picture-in-Picture','screenshot': 'Screenshot',
    'immersive': 'Immersive Mode',
    'sleep': 'Sleep Timer',  'ab': 'A-B Repeat',        'episodes': 'Episodes',
    'settings': 'Settings',  'vivid': 'Vivid / Smart',  'mute': 'Mute',
    'frame': 'Frame Step',   'onehanded': 'One-Handed', 'zoom': 'Zoom & Crop',
    'silence': 'Silence Skip',
    'more': 'More (Quick Shortcuts)',
  };

  static const _icons = <String, IconData>{
    'cc': Icons.subtitles_rounded,            'audio': Icons.headphones_rounded,
    'eq': Icons.equalizer_rounded,            'speed': Icons.speed_rounded,
    'loop': Icons.loop_rounded,               'rotate': Icons.screen_rotation_rounded,
    'lock': Icons.lock_outline_rounded,       'pip': Icons.picture_in_picture_alt_rounded,
    'immersive': Icons.theaters_rounded,
    'screenshot': Icons.camera_alt_rounded,   'sleep': Icons.bedtime_rounded,
    'ab': Icons.repeat_one_rounded,           'episodes': Icons.view_list_rounded,
    'settings': Icons.settings_rounded,       'vivid': Icons.auto_awesome_rounded,
    'mute': Icons.volume_off_rounded,         'frame': Icons.skip_next_rounded,
    'onehanded': Icons.pan_tool_alt_rounded,  'zoom': Icons.zoom_in_rounded,
    'silence': Icons.volume_off_outlined,
    'more': Icons.more_horiz_rounded,
  };

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.currentOrder);
  }

  List<String> get _hidden =>
      widget.allIds.where((id) => !_order.contains(id)).toList();

  void _remove(String id) {
    setState(() => _order.remove(id));
    widget.onOrderChanged(List.from(_order));
  }

  void _add(String id) {
    setState(() => _order.add(id));
    widget.onOrderChanged(List.from(_order));
  }

  void _reorder(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    final item = _order.removeAt(oldIdx);
    _order.insert(newIdx, item);
    widget.onOrderChanged(List.from(_order));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          color: const Color(0xFF252525),
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 10),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sidebar Shortcuts',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Drag to reorder • tap × to hide',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ),
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_order.length} shown',
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        // Reorderable visible list
        Expanded(
          child: Column(children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _order.length,
                onReorder: _reorder,
                itemBuilder: (ctx, i) {
                  final id = _order[i];
                  return ListTile(
                    key: ValueKey(id),
                    dense: true,
                    leading: Icon(_icons[id] ?? Icons.star_rounded,
                        color: Colors.white70, size: 20),
                    title: Text(_labels[id] ?? id,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Remove button
                      GestureDetector(
                        onTap: () => _remove(id),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white38, size: 16),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Drag handle
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded,
                            color: Colors.white38, size: 20),
                      ),
                    ]),
                  );
                },
              ),
            ),

            // ── Hidden shortcuts — tap to add back ───────────────────────
            if (_hidden.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(children: [
                  const Text('Hidden shortcuts',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  Text('tap + to show',
                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ]),
              ),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _hidden.length,
                  itemBuilder: (ctx, i) {
                    final id = _hidden[i];
                    return ListTile(
                      dense: true,
                      leading: Opacity(
                        opacity: 0.45,
                        child: Icon(_icons[id] ?? Icons.star_rounded,
                            color: Colors.white, size: 18),
                      ),
                      title: Opacity(
                        opacity: 0.45,
                        child: Text(_labels[id] ?? id,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      trailing: GestureDetector(
                        onTap: () => _add(id),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.add_circle_outline_rounded,
                              color: Colors.white60, size: 20),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Dub language button
// ─────────────────────────────────────────────────────────────────────────────
class _DubLangBtn extends StatelessWidget {
  final String flag;
  final String label;
  final String sublabel;
  final Color  color;
  final VoidCallback? onTap;
  const _DubLangBtn({required this.flag, required this.label,
      required this.sublabel, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.40), width: 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w700)),
          Text(sublabel, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Dub progress card (shown as full-screen overlay during generation)
// ─────────────────────────────────────────────────────────────────────────────
class _DubProgressCard extends StatelessWidget {
  final String lang;
  final double progress;
  final int    currentLine;
  final int    totalLines;
  final String statusText;

  const _DubProgressCard({
    required this.lang,
    required this.progress,
    required this.currentLine,
    required this.totalLines,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final isUrdu   = lang == 'ur-PK';
    final flag     = isUrdu ? '🇵🇰' : '🇮🇳';
    final langName = isUrdu ? 'Urdu' : 'Hindi';
    final barColor = isUrdu ? const Color(0xFF00A651) : const Color(0xFFFF9933);
    final pct      = (progress * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Flag + title
        Text(flag, style: const TextStyle(fontSize: 48))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(1,1), end: const Offset(1.08,1.08),
                   duration: 900.ms, curve: Curves.easeInOut),
        const SizedBox(height: 14),
        Text('Generating $langName Dub',
            style: const TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Using on-device TTS · Music will be preserved',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 28),

        // Animated waveform bars
        const _WaveformBars(),
        const SizedBox(height: 28),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 12),

        // Percentage + line counter
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$pct%',
              style: TextStyle(color: barColor,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          Text(totalLines > 0 ? 'Line $currentLine of $totalLines' : statusText,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Text(statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  P59 — Animated waveform bars
// ─────────────────────────────────────────────────────────────────────────────
class _WaveformBars extends StatelessWidget {
  const _WaveformBars();

  @override
  Widget build(BuildContext context) {
    const bars = 7;
    const barW = 5.0;
    const maxH = 36.0;
    const minH = 8.0;
    const barColor = Color(0xFF4A9EFF);
    return SizedBox(
      height: maxH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bars, (i) {
          final delay = Duration(milliseconds: i * 100);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(width: barW, height: minH,
                    decoration: BoxDecoration(
                      color: barColor.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ))
                .animate(onPlay: (c) => c.repeat(reverse: true), delay: delay)
                .scaleY(begin: 1, end: maxH / minH,
                        duration: 500.ms, curve: Curves.easeInOut,
                        alignment: Alignment.bottomCenter)
                .then()
                .custom(
                  duration: 0.ms,
                  builder: (ctx, val, child) => ColorFiltered(
                    colorFilter: ColorFilter.mode(
                        barColor.withOpacity(0.4 + val * 0.5),
                        BlendMode.srcATop),
                    child: child,
                  ),
                ),
          );
        }),
      ),
    );
  }
}
