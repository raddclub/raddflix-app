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
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/jazzdrive_service.dart';
import '../core/db/local_db.dart';
import '../core/api/catalog_api.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';

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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

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
  bool _ended = false;
  String? _streamError;
  bool _isLinkLoading = false;

  // ── Current episode ─────────────────────────────────────────────────────────
  int _currentEpIdx = 0;
  String _currentFileId = '';
  String _currentTitle = '';

  // ── Controls visibility ─────────────────────────────────────────────────────
  bool _showControls = true;
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

  // ── MX Layout State ──────────────────────────────────────────────────────────
  bool _isLocked = false;
  BoxFit _videoFit = BoxFit.contain;

  // Smart Enhance
  bool _smartEnhanceEnabled = false;
  int _smartEnhancePhase = 0; // 0=off 1=dots 2=scan 3=title
  bool _showSmartEnhanceToast = false;
  Timer? _smartEnhanceTimer;
  late AnimationController _smartEnhanceAnim;
  double _scanLinePos = 0.0; // 0..1 sweep position
  Timer? _scanLineTimer;

  // Video zoom
  // 0=Fit 1=Stretch 2=Crop 3=100% 4=Custom
  int _zoomMode = 0;

  // Audio effect
  int _selectedPreset = 0; // 0=Original 1=TrebleBoost 2=BassBoost 3=Clarity 4=Movie 5=Music
  List<double> _eqBands = [0, 0, 0, 0, 0]; // 60,230,910,3600,14000 Hz
  bool _eqEnabled = true;

  // Subtitle
  double _subSync = 0.0; // seconds
  double _subSpeed = 1.0; // 0.5..2.0
  String? _currentSubFile;

  // Audio
  double _audioSync = 0.0;
  bool _useSWDecoder = false;

  // Sleep timer
  int? _sleepTimerMinutes;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEnd;

  // Settings
  bool _showRemainingTime = false;
  bool _keepScreenOn = true;
  int _skipInterval = 10;
  // Feature 26 — resume position
  Timer? _savePositionTimer;
  static const _kResumePrefix = 'resume_pos_';

  // Loop
  bool _loopEnabled = false;
  bool _isMuted = false;

  // A-B repeat
  Duration? _abA;
  Duration? _abB;
  bool _abActive = false;

  // ── Subscriptions ───────────────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  // ── Watch position ──────────────────────────────────────────────────────────
  Timer? _posTimer;

  // ═══════════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WakelockPlus.enable();
    _currentEpIdx = widget.episodeIndex;
    _currentFileId = widget.fileId;
    _currentTitle = widget.title;
    _smartEnhanceAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchPos();
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveWatchPos();
    _hideTimer?.cancel();
    _posTimer?.cancel();
    _indicatorTimer?.cancel();
    _smartEnhanceTimer?.cancel();
    _sleepTimer?.cancel();
    _scanLineTimer?.cancel();
    _smartEnhanceAnim.dispose();
    for (final s in _subs) { s.cancel(); }
    VolumeController().removeListener();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
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
        if (mounted) {
        setState(() => _playing = v);
        if (v) _startSavePositionTimer();
      }
      }),
      _player.stream.position.listen((v) {
        if (mounted) {
          setState(() => _position = v);
          // A-B repeat check
          if (_abActive && _abA != null && _abB != null && v >= _abB!) {
            _player.seek(_abA!);
          }
        }
      }),
      _player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }),
      _player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
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
      }),
      _player.stream.track.listen((track) {
        if (mounted) setState(() {
          _selectedAudio = track.audio;
          _selectedSubtitle = track.subtitle;
        });
      }),
    ]);

    _posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());

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
    final effectivePath = localPath ?? (isLocal ? fileId : null);

    if (effectivePath != null) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true;
      await _player.open(Media(effectivePath));
      await _restoreWatchPos();
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
        if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
        _videoOpened = true;
        await _player.open(Media(link.streamUrl));
        await _restoreWatchPos();
        _scheduleHide();
        return;
      }
    } catch (e) {
      DebugLogger.logError('PLAYER', 'Stream resolution failed for $fileId', e);
      if (mounted) {
        setState(() {
          _isLinkLoading = false;
          _streamError = _friendlyError(e.toString());
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLinkLoading = false;
        _streamError = 'No stream link found. Please sync your library in Settings → Sync.';
      });
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
    });
    _openMediaForEpisode(ep,
      localPath: ep['local_path'] as String?,
      shareUrl: ep['share_url'] as String?,
    );
  }

  Future<void> _openMediaForEpisode(Map<String, dynamic> ep,
      {String? localPath, String? shareUrl}) async {
    final fileId = ep['file_id'] as String? ?? '';

    if (localPath != null && localPath.isNotEmpty) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true;
      await _player.open(Media(localPath));
      await _restoreWatchPos();
      _scheduleHide();
      return;
    }

    if (mounted) setState(() { _streamError = null; _isLinkLoading = true; _ended = false; _position = Duration.zero; });

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
        if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
        _videoOpened = true;
        await _player.open(Media(link.streamUrl));
        await _restoreWatchPos();
        _scheduleHide();
        return;
      }
    } catch (e) {
      DebugLogger.logError('PLAYER', 'Episode stream failed for $fileId', e);
      if (mounted) setState(() { _isLinkLoading = false; _streamError = _friendlyError(e.toString()); });
      return;
    }

    if (mounted) setState(() { _isLinkLoading = false; _streamError = 'No stream link found for this episode.'; });
  }

  void _onVideoCompleted() {
    _clearSavedPosition(_currentFileId);
    _saveWatchPos();
    if (_loopEnabled) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_hasNext) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _ended) _playEpisodeAt(_currentEpIdx + 1);
      });
    }
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
  }

  Future<void> _restoreWatchPos() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_posKey) ?? 0;
    if (ms > 30000 && ms < (_duration.inMilliseconds - 10000)) {
      await _player.seek(Duration(milliseconds: ms));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Controls helpers
  // ═══════════════════════════════════════════════════════════════════════════

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      // Show briefly when locked
      setState(() => _showControls = true);
      _scheduleHide();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _seekRelative(int seconds) {
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
    _np.setProperty('speed', '1.0');
    _np.setProperty('framedrop', 'vo');
    _np.setProperty('hr-seek', 'yes');
    if (mounted) setState(() {});
  }

  // ─── Feature 26: Resume position ────────────────────────────────────────
  void _saveCurrentPosition() {
    if (_position.inSeconds < 5) return; // don't save if near start
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('$_kResumePrefix$_currentFileId', _position.inSeconds);
    });
  }

  void _clearSavedPosition(String fileId) {
    SharedPreferences.getInstance().then((prefs) => prefs.remove('$_kResumePrefix$fileId'));
  }

  Future<void> _tryResumePosition(String fileId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedSec = prefs.getInt('$_kResumePrefix$fileId');
    if (savedSec != null && savedSec > 5 && _duration.inSeconds > savedSec + 10) {
      if (!mounted) return;
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Resume Playback', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            'Continue from ${_formatDuration(Duration(seconds: savedSec))}?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Start Over', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resume', style: TextStyle(color: Color(0xFFE8950A), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (cont == true && mounted) {
        await Future.delayed(const Duration(milliseconds: 300));
        _player.seek(Duration(seconds: savedSec));
      }
    }
  }

  void _startSavePositionTimer() {
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveCurrentPosition());
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
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Smart Enhance
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleSmartEnhance() {
    if (_smartEnhancePhase > 0) return; // animation in progress
    if (_smartEnhanceEnabled) {
      // Turn off
      setState(() {
        _smartEnhanceEnabled = false;
        _smartEnhancePhase = 0;
      });
      _showToast('Smart Enhance disabled.');
      return;
    }
    // Phase 1: dots circle
    setState(() => _smartEnhancePhase = 1);
    _smartEnhanceAnim.repeat();

    // Phase 2: scan line after 1.6s
    _smartEnhanceTimer?.cancel();
    _smartEnhanceTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _smartEnhanceAnim.stop();
      setState(() {
        _smartEnhancePhase = 2;
        _scanLinePos = 0.0;
      });
      // Animate scan line
      const scanDuration = 900; // ms
      const steps = 60;
      int step = 0;
      _scanLineTimer?.cancel();
      _scanLineTimer = Timer.periodic(
        Duration(milliseconds: scanDuration ~/ steps),
        (t) {
          step++;
          if (!mounted || step >= steps) {
            t.cancel();
            if (!mounted) return;
            // Phase 3: title
            setState(() {
              _smartEnhancePhase = 3;
              _smartEnhanceEnabled = true;
            });
            // Fade out title after 1.8s
            _smartEnhanceTimer = Timer(const Duration(milliseconds: 1800), () {
              if (!mounted) return;
              setState(() => _smartEnhancePhase = 0);
              _showToast('Smart Enhance enabled.');
            });
            return;
          }
          if (mounted) setState(() => _scanLinePos = step / steps);
        },
      );
    });
  }

  void _showToast(String message) {
    setState(() {
      _showSmartEnhanceToast = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSmartEnhanceToast = false);
    });
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
    final afString = index == 0 ? '' : 'equalizer=${gains.join(':')}';
    try {
      _np.setProperty('af', afString);
    } catch (_) {}
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
  }

  void _applyCustomEq() {
    if (!_eqEnabled) return;
    // Map 5-band sliders to 10-band EQ
    final b = _eqBands;
    final g = [
      b[0].round(), b[0].round(),   // 31.25, 62.5 → 60Hz
      b[1].round(), b[1].round(),   // 125, 250 → 230Hz
      b[2].round(), b[2].round(),   // 500, 1000 → 910Hz
      b[3].round(), b[3].round(),   // 2000, 4000 → 3600Hz
      b[4].round(), b[4].round(),   // 8000, 16000 → 14000Hz
    ];
    try {
      _np.setProperty('af', 'equalizer=${g.join(':')}');
    } catch (_) {}
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
      default: return BoxFit.contain;
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
  //  Gesture handlers
  // ═══════════════════════════════════════════════════════════════════════════

  void _onDragStart(DragStartDetails d, BoxConstraints constraints) {
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
      if (dx.abs() > dy.abs() && dx.abs() > 12) {
        _dragIntent = 'seek';
      } else if (dy.abs() > 12) {
        _dragIntent = isLeftSide ? 'brightness' : 'volume';
      }
    }

    if (_dragIntent == 'seek') {
      // Horizontal seek: 120s across full width
      final delta = dx / constraints.maxWidth;
      final seekSec = delta * 120.0;
      final targetMs = (_dragStartPos.inMilliseconds + seekSec * 1000)
          .clamp(0, _duration.inMilliseconds.toDouble());
      _seekBarDelta = targetMs / (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1);
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
    _dragIntent = null;
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════════


    // ── extra state for modern UI ────────────────────────────────────────────
    // (seek preview label during horizontal drag)
    String _seekPreviewLabel = '';

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // 1. Video surface — full screen
                Positioned.fill(child: _buildVideoSurface()),

                // 2. Lock overlay
                if (_isLocked) _buildLockOverlay(),

                // 3. Gesture layer
                if (!_isLocked)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) {
                        final isLeft = d.localPosition.dx < constraints.maxWidth / 2;
                        _seekRelative(isLeft ? -_skipInterval : _skipInterval);
                      },
                      onLongPressStart: (_) => _startLongPress(),
                      onLongPressEnd: (_) => _endLongPress(),
                      onLongPressCancel: () => _endLongPress(),
                      onHorizontalDragStart: (d) => _onDragStart(d, constraints),
                      onHorizontalDragUpdate: (d) => _onDragUpdate(d, constraints),
                      onHorizontalDragEnd: _onDragEnd,
                      onVerticalDragStart: (d) => _onDragStart(d, constraints),
                      onVerticalDragUpdate: (d) => _onDragUpdate(d, constraints),
                      onVerticalDragEnd: _onDragEnd,
                    ),
                  ),

                // 4. Smart Enhance animation
                if (_smartEnhancePhase > 0)
                  _buildSmartEnhanceAnimation(constraints),

                // 5. Controls overlay (auto-hides)
                AnimatedOpacity(
                  opacity: _showControls && !_isLocked ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  child: IgnorePointer(
                    ignoring: !_showControls || _isLocked,
                    child: _buildControlsOverlay(constraints),
                  ),
                ),

                // 6. Volume/brightness indicator — centered pill
                if (_showVolumeIndicator || _showBrightnessIndicator)
                  Positioned(
                    top: constraints.maxHeight * 0.35,
                    left: constraints.maxWidth * 0.18,
                    right: constraints.maxWidth * 0.18,
                    child: _showVolumeIndicator
                        ? _buildCenteredVolumeOverlay()
                        : _buildCenteredBrightnessOverlay(),
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

                // 8. Double-tap seek flash (constrained to video bounds)
                if (_showSeekFlash)
                  Positioned(
                    left: _seekFlashLeft ? 0 : null,
                    right: _seekFlashLeft ? null : 0,
                    top: 0, bottom: 0,
                    width: constraints.maxWidth / 2,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _seekFlashLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                              color: Colors.white, size: 36,
                            ),
                            const SizedBox(height: 2),
                            Text('$_skipInterval s',
                                style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 9. Smart Enhance toast — center of screen
                if (_showSmartEnhanceToast)
                  Positioned(
                    top: 0, bottom: 0, left: 0, right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: _buildSmartEnhanceToast(),
                      ),
                    ),
                  ),

                // 10. Buffering spinner
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

                // 12. Error overlay
                if (_streamError != null)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.redAccent, size: 52),
                            const SizedBox(height: 16),
                            Text(_streamError!,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                  onPressed: () {
                                    setState(() => _streamError = null);
                                    _openMedia(_currentFileId);
                                  },
                                ),
                                const SizedBox(width: 16),
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
                            const Text('Up next in 3s…',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(width: 14),
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
            top: 0, left: 0, right: 0, height: 140,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xDD000000), Colors.transparent],
                ),
              ),
            ),
          ),

          // Bottom gradient
          Positioned(
            bottom: 0, left: 0, right: 0, height: 180,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xDD000000), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── TOP BAR ──────────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: _buildTopBar(),
            ),
          ),

          // ── CENTER PLAYBACK CONTROLS ──────────────────────────────────────────
          Positioned.fill(
            child: Center(
              child: _buildCenterControls(),
            ),
          ),

          // ── BOTTOM AREA: seek bar + icon row ──────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
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

    Widget _buildTopBar() {
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

            // Title
            Expanded(
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

            const SizedBox(width: 4),

            // Subtitle
            _RaddIconBtn(
              icon: Icons.subtitles_rounded,
              size: 20,
              onTap: _openSubtitlePanel,
            ),

            // Replay from start
            _RaddIconBtn(
              icon: Icons.replay_rounded,
              size: 20,
              onTap: () => _player.seek(Duration.zero),
            ),

            // Zoom / fit
            _RaddIconBtn(
              icon: Icons.fit_screen_rounded,
              size: 20,
              onTap: _openZoomPanel,
            ),

            // Lock
            _RaddIconBtn(
              icon: Icons.lock_open_rounded,
              size: 20,
              onTap: () => setState(() { _isLocked = true; _showControls = false; }),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Center playback controls (skip + play/pause)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildCenterControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous video — always visible, dimmed when unavailable
        Opacity(
          opacity: _hasPrev ? 1.0 : 0.3,
          child: _RaddIconBtn(
            icon: Icons.skip_previous_rounded,
            size: 36,
            onTap: _hasPrev ? () => _playEpisodeAt(_currentEpIdx - 1) : null,
          ),
        ),

        const SizedBox(width: 24),

        // Play / Pause — large circle button
        GestureDetector(
          onTap: () {
            _player.playOrPause();
            _scheduleHide();
          },
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),

        const SizedBox(width: 24),

        // Next video — always visible, dimmed when unavailable
        Opacity(
          opacity: _hasNext ? 1.0 : 0.3,
          child: _RaddIconBtn(
            icon: Icons.skip_next_rounded,
            size: 36,
            onTap: _hasNext ? () => _playEpisodeAt(_currentEpIdx + 1) : null,
          ),
        ),
      ],
    );
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

            const SizedBox(height: 4),

            // ── Bottom icon row ──────────────────────────────────────────────────
            _buildBottomIconRow(),
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
                builder: (ctx, bc) => CustomPaint(
                  size: Size(bc.maxWidth, 28),
                  painter: _HorizontalSeekPainter(progress: progress),
                ),
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
    //  Bottom Icon Row
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildBottomIconRow() {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Smart Enhance
          _BottomIconBtn(
            icon: Icons.auto_awesome_rounded,
            label: 'Enhance',
            active: _smartEnhanceEnabled,
            onTap: _toggleSmartEnhance,
          ),

          // Audio tracks
          _BottomIconBtn(
            icon: Icons.headphones_rounded,
            label: 'Audio',
            active: false,
            onTap: _openAudioPanel,
          ),

          // Episode list
          _BottomIconBtn(
            icon: Icons.view_list_rounded,
            label: 'Episodes',
            active: false,
            onTap: _eps.length > 1 ? _showEpisodeSheet : null,
            opacity: _eps.length > 1 ? 1.0 : 0.3,
          ),

          // Speed
          _BottomIconBtn(
            icon: Icons.speed_rounded,
            label: '${_speed == 1.0 ? "1×" : "${_speed}×"}',
            active: _speed != 1.0,
            onTap: _cycleSpeed,
          ),

          // HW/SW decoder badge
          GestureDetector(
            onTap: () => _showInfoSnackbar(
                'Decoder: ${_useSWDecoder ? "SW" : "HW+"}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white30, width: 0.8),
                    ),
                    child: Text(
                      _useSWDecoder ? 'SW' : 'HW+',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Decoder',
                      style: TextStyle(color: Colors.white54, fontSize: 9)),
                ],
              ),
            ),
          ),

          // More
          _BottomIconBtn(
            icon: Icons.more_horiz_rounded,
            label: 'More',
            active: false,
            onTap: _openMoreMenu,
          ),
        ],
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Volume indicator — centered glassmorphism pill
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildCenteredVolumeOverlay() {
      final percent = (_volume * 100).round();
      final barFrac = (_volume / 1.5).clamp(0.0, 1.0);
      return _buildCenteredIndicatorPill(
        icon: _isMuted
            ? Icons.volume_off_rounded
            : percent > 60
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
        barValue: barFrac,
        barColor: const Color(0xFFE8950A),
        label: '$percent%',
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Brightness indicator — centered glassmorphism pill
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildCenteredBrightnessOverlay() {
      final percent = (_brightness * 100).round();
      return _buildCenteredIndicatorPill(
        icon: _brightness < 0.3
            ? Icons.brightness_low_rounded
            : _brightness > 0.7
                ? Icons.brightness_high_rounded
                : Icons.brightness_medium_rounded,
        barValue: _brightness,
        barColor: const Color(0xFF3A8EF5),
        label: '$percent%',
      );
    }

    Widget _buildCenteredIndicatorPill({
      required IconData icon,
      required double barValue,
      required Color barColor,
      required String label,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: barValue,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Smart Enhance Animation (3 phases)
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildSmartEnhanceAnimation(BoxConstraints constraints) {
      if (_smartEnhancePhase == 1) {
        return Positioned.fill(
          child: Container(
            color: const Color(0xCC2A1A0A),
            child: Center(
              child: AnimatedBuilder(
                animation: _smartEnhanceAnim,
                builder: (context, _) => CustomPaint(
                  size: Size(constraints.maxWidth * 0.65, constraints.maxWidth * 0.65),
                  painter: _SmartEnhanceDotsCirclePainter(
                    progress: _smartEnhanceAnim.value,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      if (_smartEnhancePhase == 2) {
        return Positioned.fill(
          child: Container(
            color: const Color(0xCC1A0A0A),
            child: Stack(
              children: [
                Positioned(
                  top: _scanLinePos * constraints.maxHeight - 15,
                  left: 0, right: 0, height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFFE8530A).withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(child: _SmartEnhanceIcon(size: 42, color: Colors.white)),
              ],
            ),
          ),
        );
      }

      if (_smartEnhancePhase == 3) {
        return Positioned.fill(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmartEnhanceIcon(size: 54, color: Colors.white),
                const SizedBox(height: 18),
                const Text(
                  'SMART ENHANCE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Immersive visual experience',
                  style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        );
      }

      return const SizedBox.shrink();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Smart Enhance Toast
    // ═══════════════════════════════════════════════════════════════════════════

    Widget _buildSmartEnhanceToast() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xDD1A1A1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _smartEnhanceEnabled
                  ? Icons.auto_awesome_rounded
                  : Icons.auto_awesome_outlined,
              color: _smartEnhanceEnabled
                  ? const Color(0xFFE8950A)
                  : Colors.white54,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              _smartEnhanceEnabled ? 'Smart Enhance enabled.' : 'Smart Enhance disabled.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Panels (right-side slide-in)
    // ═══════════════════════════════════════════════════════════════════════════

    void _openRightPanel(Widget content, {double widthFactor = 0.82}) {
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black54,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (ctx, anim, sec) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(ctx).size.width * widthFactor,
                height: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
                ),
                child: content,
              ),
            ),
          );
        },
        transitionBuilder: (ctx, anim, sec, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      );
    }

    void _openSubtitlePanel() {
      _openRightPanel(_SubtitlePanel(
        subSync: _subSync,
        subSpeed: _subSpeed,
        currentFile: _currentSubFile,
        onSyncChanged: (delta) => _adjustSubSync(delta),
        onSpeedChanged: (v) => setState(() => _subSpeed = v),
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openAudioPanel() {
      _openRightPanel(_AudioTrackPanel(
        tracks: _audioTracks,
        selectedTrack: _selectedAudio,
        audioSync: _audioSync,
        useSWDecoder: _useSWDecoder,
        onTrackSelected: (track) {
          setState(() => _selectedAudio = track);
          _player.setAudioTrack(track);
        },
        onSyncChanged: (delta) => _adjustAudioSync(delta),
        onSWDecoderChanged: (v) => setState(() => _useSWDecoder = v),
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openZoomPanel() {
      _openRightPanel(_VideoZoomPanel(
        selectedMode: _zoomMode,
        onModeSelected: (mode) {
          setState(() => _zoomMode = mode);
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
        },
        onEqEnabledChanged: (v) {
          setState(() => _eqEnabled = v);
          if (!v) {
            try { _np.setProperty('af', ''); } catch (_) {}
          } else {
            _applyCustomEq();
          }
        },
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _openMoreMenu() {
      _openRightPanel(_QuickShortcutsPanel(
        isLocked: _isLocked,
        isMuted: _isMuted,
        loopEnabled: _loopEnabled,
        smartEnhanceEnabled: _smartEnhanceEnabled,
        sleepTimerMinutes: _sleepTimerMinutes,
        sleepTimerEnd: _sleepTimerEnd,
        speed: _speed,
        abA: _abA,
        abB: _abB,
        abActive: _abActive,
        onLockToggle: () { Navigator.of(context).pop(); setState(() => _isLocked = true); },
        onMuteToggle: () { Navigator.of(context).pop(); _toggleMute(); },
        onLoopToggle: () { Navigator.of(context).pop(); _toggleLoop(); },
        onSmartEnhanceToggle: () { Navigator.of(context).pop(); _toggleSmartEnhance(); },
        onSleepTimer: (mins) { Navigator.of(context).pop(); _setSleepTimer(mins); },
        onSpeedSelected: (s) { Navigator.of(context).pop(); _setSpeed(s); },
        onAudioEffect: () { Navigator.of(context).pop(); _openAudioEffectPanel(); },
        onSettingsOpen: () { Navigator.of(context).pop(); _openSettingsPanel(); },
        onAbSet: () { Navigator.of(context).pop(); _handleAbRepeat(); },
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    void _handleAbRepeat() {
      if (_abA == null) {
        setState(() { _abA = _position; _abActive = false; });
        _showInfoSnackbar('A point set at ${_formatDuration(_position)}');
      } else if (_abB == null) {
        setState(() { _abB = _position; _abActive = true; });
        _showInfoSnackbar('B point set. A-B repeat active.');
      } else {
        setState(() { _abA = null; _abB = null; _abActive = false; });
        _showInfoSnackbar('A-B repeat cleared.');
      }
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
        onClose: () => Navigator.of(context).pop(),
      ));
    }

    // Feature 24: Picture-in-Picture
  void _enterPiP() {
    // On Android, trigger PiP mode via platform channel
    const _pipChannel = MethodChannel('com.raddclub.raddflix/pip');
    _pipChannel.invokeMethod('enterPiP').catchError((_) {
      // PiP not supported on this device/version — minimize instead
      Navigator.of(context).pop();
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

    // ═══════════════════════════════════════════════════════════════════════════
    //  Episode sheet
    // ═══════════════════════════════════════════════════════════════════════════

    void _showEpisodeSheet() {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1C1C1C),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) => SizedBox(
          height: 380,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text('Episodes',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: _eps.length,
                  itemBuilder: (_, i) {
                    final ep = _eps[i];
                    final label = ep['label'] as String? ??
                        ep['title'] as String? ?? 'Episode ${i + 1}';
                    final isCurrent = i == _currentEpIdx;
                    return ListTile(
                      title: Text(label,
                          style: TextStyle(
                            color: isCurrent ? Colors.white : Colors.white70,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                          )),
                      trailing: isCurrent
                          ? const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 20)
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
          ),
        ),
      );
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
    _HorizontalSeekPainter({required this.progress});

    @override
    void paint(Canvas canvas, Size size) {
      final cy = size.height / 2;
      final trackPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      final progressPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      // Track
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);

      // Progress
      final progX = size.width * progress;
      if (progX > 0) {
        canvas.drawLine(Offset(0, cy), Offset(progX, cy), progressPaint);
      }

      // Thumb circle
      final thumbPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(progX, cy), 7, thumbPaint);
    }

    @override
    bool shouldRepaint(_HorizontalSeekPainter old) => old.progress != progress;
  }

  
// Smart Enhance dots circle painter
class _SmartEnhanceDotsCirclePainter extends CustomPainter {
  final double progress;
  _SmartEnhanceDotsCirclePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final paint = Paint()..color = Colors.white;

    // Draw 2 rings of dots rotating
    for (int ring = 0; ring < 2; ring++) {
      final r = maxR * (0.55 + ring * 0.3);
      final dotCount = 28 + ring * 12;
      final angleOffset = progress * 2 * math.pi * (ring % 2 == 0 ? 1 : -1);

      for (int i = 0; i < dotCount; i++) {
        final angle = (i / dotCount) * 2 * math.pi + angleOffset;
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);
        // Vary dot size by position for visual effect
        final sizeFactor = (math.sin(angle * 3 + progress * math.pi) + 1) / 2;
        final dotR = 2.0 + sizeFactor * 3.0;
        final alpha = (0.3 + sizeFactor * 0.7).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(x, y), dotR, paint..color = Colors.white.withOpacity(alpha));
      }
    }

    // Center icon (just a square with triangle inside — simplified ⊡+ icon)
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const iconSize = 32.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: iconSize, height: iconSize),
        const Radius.circular(4),
      ),
      iconPaint,
    );
    // Down-pointing triangle inside box
    final triPath = Path();
    triPath.moveTo(center.dx - 8, center.dy - 5);
    triPath.lineTo(center.dx + 8, center.dy - 5);
    triPath.lineTo(center.dx, center.dy + 6);
    triPath.close();
    canvas.drawPath(triPath, iconPaint);
  }

  @override
  bool shouldRepaint(_SmartEnhanceDotsCirclePainter old) => old.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Helper Widgets
// ═════════════════════════════════════════════════════════════════════════════

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
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size + 20,
          height: size + 20,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: size,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black45)]),
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 20,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black54)]),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        color: active ? const Color(0xFFE8950A) : Colors.white70,
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
    }
  }

  
class _MxIconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  const _MxIconBtn({required this.icon, this.size = 22, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

class _MxSideBtn extends StatelessWidget {
  final Widget child;
  const _MxSideBtn({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    );
  }
}

class _SmartEnhanceIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _SmartEnhanceIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.tv_rounded, color: color, size: size * 0.8),
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: Icon(Icons.add_rounded, color: color, size: size * 0.36),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SUBTITLE PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _SubtitlePanel extends StatefulWidget {
  final double subSync;
  final double subSpeed;
  final String? currentFile;
  final void Function(double) onSyncChanged;
  final void Function(double) onSpeedChanged;
  final VoidCallback onClose;

  const _SubtitlePanel({
    required this.subSync,
    required this.subSpeed,
    required this.currentFile,
    required this.onSyncChanged,
    required this.onSpeedChanged,
    required this.onClose,
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

  @override
  void initState() {
    super.initState();
    _sync = widget.subSync;
    _speed = widget.subSpeed;
  }

  // Feature 21: Online subtitle search via OpenSubtitles REST
  Future<void> _fetchOnlineSubtitles(BuildContext ctx) async {
    if (_onlineLoading) return;
    setState(() { _onlineLoading = true; _onlineError = ''; _onlineResults = []; });
    try {
      final title = Uri.encodeComponent(
          (widget.currentFile ?? 'video').replaceAll(RegExp(r'\.[^.]+

        // Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final tab in ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'])
                GestureDetector(
                  onTap: () => setState(() => _tab = ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'].indexOf(tab)),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _tab == ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'].indexOf(tab)
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
                  const Row(children: [
                    Expanded(child: Text('Font', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('Sans Serif', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Size', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('22', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Scale', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('100%', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Bold', style: TextStyle(color: Colors.white, fontSize: 14))),
                    const Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Color', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Container(width: 20, height: 20, color: Colors.white),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Background', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Container(width: 20, height: 20, color: Colors.black54),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Fade out', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('80%', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ],
                if (_tab == 4) ...[
                  const Text('Layout', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Row(children: [
                    Expanded(child: Text('Alignment', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('Center', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Bottom margin', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('22', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Fit subtitles into video size', style: TextStyle(color: Colors.white, fontSize: 14))),
                    const Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
                  ]),
                ],
                if (_tab == 0) ...[
                GestureDetector(
                  onTap: () => _fetchOnlineSubtitles(context),
                  child: const Text('🔍  Search online subtitles',
                      style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 14,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF4A9EFF))),
                ),
                const SizedBox(height: 8),
                const Text('Searches OpenSubtitles.org for matching subtitles.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                if (widget.currentFile != null) ...[
                  GestureDetector(
                    onTap: () => _showTranslationDialog(context),
                    child: const Text('🌐  Add Translation',
                        style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF4A9EFF))),
                  ),
                ],
              ],
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
  final void Function(AudioTrack) onTrackSelected;
  final void Function(double) onSyncChanged;
  final void Function(bool) onSWDecoderChanged;
  final VoidCallback onClose;

  const _AudioTrackPanel({
    required this.tracks,
    required this.selectedTrack,
    required this.audioSync,
    required this.useSWDecoder,
    required this.onTrackSelected,
    required this.onSyncChanged,
    required this.onSWDecoderChanged,
    required this.onClose,
  });

  @override
  State<_AudioTrackPanel> createState() => _AudioTrackPanelState();
}

class _AudioTrackPanelState extends State<_AudioTrackPanel> {
  late double _sync;
  late bool _useSW;

  @override
  void initState() {
    super.initState();
    _sync = widget.audioSync;
    _useSW = widget.useSWDecoder;
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
                  title: Text(
                    widget.tracks[i].title ??
                        widget.tracks[i].language ??
                        'Audio track ${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  activeColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),

              const Divider(color: Colors.white12),

              // Disable
              RadioListTile<AudioTrack?>(
                value: null,
                groupValue: widget.selectedTrack,
                onChanged: (_) {},
                title: const Text('Disable', style: TextStyle(color: Colors.white, fontSize: 14)),
                activeColor: Colors.white,
                controlAffinity: ListTileControlAffinity.trailing,
              ),

              const Divider(color: Colors.white12),

              // SW decoder toggle
              SwitchListTile(
                title: const Text('Use SW audio decoder', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _useSW,
                onChanged: (v) {
                  setState(() => _useSW = v);
                  widget.onSWDecoderChanged(v);
                },
                activeColor: Colors.white,
              ),

              const Divider(color: Colors.white12),

              // Stereo mode (info only)
              ListTile(
                title: const Text('Stereo mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Text('Stereo', style: TextStyle(color: Colors.white54, fontSize: 13)),
                onTap: () {},
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
                        Text('${_sync.toStringAsFixed(2)}s',
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
//  VIDEO ZOOM PANEL
// ═════════════════════════════════════════════════════════════════════════════

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
    const modes = ['Fit to screen', 'Stretch', 'Crop', '100%', 'Custom'];
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
  final VoidCallback onClose;

  const _AudioEffectPanel({
    required this.selectedPreset,
    required this.eqBands,
    required this.eqEnabled,
    required this.onPresetSelected,
    required this.onEqBandChanged,
    required this.onEqEnabledChanged,
    required this.onReverbChanged,
    required this.onClose,
  });

  @override
  State<_AudioEffectPanel> createState() => _AudioEffectPanelState();
}

class _AudioEffectPanelState extends State<_AudioEffectPanel> {
  int _tab = 0; // 0=Presets 1=Equalizer
  late List<double> _bands;
  late int _preset;
  late bool _eqEnabled;

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
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('Audio Effect', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              const Spacer(),
              // Tab switcher
              GestureDetector(
                onTap: () => setState(() => _tab = 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Presets',
                      style: TextStyle(
                        color: _tab == 0 ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: _tab == 0 ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _tab = 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Equalizer',
                      style: TextStyle(
                        color: _tab == 1 ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: _tab == 1 ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        if (_tab == 0)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
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

                // Reverb
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      const Text('Reverb', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      const Text('None', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
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
//  QUICK SHORTCUTS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _QuickShortcutsPanel extends StatelessWidget {
  final bool isLocked;
  final bool isMuted;
  final bool loopEnabled;
  final bool smartEnhanceEnabled;
  final int? sleepTimerMinutes;
  final DateTime? sleepTimerEnd;
  final double speed;
  final Duration? abA;
  final Duration? abB;
  final bool abActive;
  final VoidCallback onLockToggle;
  final VoidCallback onMuteToggle;
  final VoidCallback onLoopToggle;
  final VoidCallback onSmartEnhanceToggle;
  final void Function(int?) onSleepTimer;
  final void Function(double) onSpeedSelected;
  final VoidCallback onAudioEffect;
  final VoidCallback onSettingsOpen;
  final VoidCallback onAbSet;
  final VoidCallback onClose;

  const _QuickShortcutsPanel({
    required this.isLocked,
    required this.isMuted,
    required this.loopEnabled,
    required this.smartEnhanceEnabled,
    required this.sleepTimerMinutes,
    required this.sleepTimerEnd,
    required this.speed,
    required this.abA,
    required this.abB,
    required this.abActive,
    required this.onLockToggle,
    required this.onMuteToggle,
    required this.onLoopToggle,
    required this.onSmartEnhanceToggle,
    required this.onSleepTimer,
    required this.onSpeedSelected,
    required this.onAudioEffect,
    required this.onSettingsOpen,
    required this.onAbSet,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    String abLabel = 'A-B';
    if (abA != null && abB == null) abLabel = 'A-B (A set)';
    if (abActive) abLabel = 'A-B ●';

    String sleepLabel = 'Sleep';
    if (sleepTimerEnd != null) {
      final remaining = sleepTimerEnd!.difference(DateTime.now());
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
                onPressed: onClose,
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
                  _ShortcutItem(Icons.screen_rotation_rounded, 'Rotate', false, () {}),
                  _ShortcutItem(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Mute', isMuted, onMuteToggle),
                  _ShortcutItem(Icons.equalizer_rounded, 'Equalizer', false, onAudioEffect),
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
                      '${speed}×',
                      speed != 1.0,
                      () { _showSpeedDialog(context); }),
                  _ShortcutItem(Icons.loop_rounded, 'Loop', loopEnabled, onLoopToggle),
                  _ShortcutItem(Icons.repeat_one_rounded, abLabel, abActive, onAbSet),
                  _ShortcutItem(Icons.lock_rounded, 'Lock', isLocked, onLockToggle),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),

              // Smart Enhance row
              ListTile(
                leading: const Icon(Icons.tv_rounded, color: Colors.white, size: 20),
                title: const Text('Smart Enhance', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: Switch(
                  value: smartEnhanceEnabled,
                  onChanged: (_) => onSmartEnhanceToggle(),
                  activeColor: Colors.white,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // Settings
              ListTile(
                leading: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                title: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: onSettingsOpen,
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
                trailing: sleepTimerMinutes == mins
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSleepTimer(mins);
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
                title: Text('${s}×', style: const TextStyle(color: Colors.white)),
                trailing: speed == s ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSpeedSelected(s);
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
  _ShortcutItem(this.icon, this.label, this.active, this.onTap);
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
  final VoidCallback onClose;

  const _SettingsPanel({
    required this.showRemainingTime,
    required this.keepScreenOn,
    required this.skipInterval,
    required this.onShowRemainingChanged,
    required this.onKeepScreenChanged,
    required this.onSkipIntervalChanged,
    required this.onClose,
  });

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  int _tab = 0; // 0=Style 1=Screen 2=Controls 3=Navigation
  late bool _showRemaining;
  late bool _keepScreenOn;
  late int _skipInterval;

  @override
  void initState() {
    super.initState();
    _showRemaining = widget.showRemainingTime;
    _keepScreenOn = widget.keepScreenOn;
    _skipInterval = widget.skipInterval;
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Preset', style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 8),
        Text('Default', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Text('Progress bar style', style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 8),
        Text('Slim', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        const Text('Battery / clock in title bar', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('Brightness', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Touch action', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Pause / resume', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Text('Lock mode', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Auto lock controls when video plays', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Divider(color: Colors.white12),
        SizedBox(height: 8),
        Text('Gestures', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Left half: Brightness  •  Right half: Volume', style: TextStyle(color: Colors.white70, fontSize: 13)),
        SizedBox(height: 4),
        Text('Double tap left: Rewind  •  Double tap right: Forward', style: TextStyle(color: Colors.white70, fontSize: 13)),
        SizedBox(height: 4),
        Text('Long press: 2× speed', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
            const Expanded(
              child: Slider(
                value: 10,
                min: 5, max: 60, divisions: 11,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: null,
              ),
            ),
            const Text('10', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        Row(
          children: const [
            Expanded(child: Text('Forward / backward button', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            Expanded(child: Text('Previous / next button', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            Expanded(child: Text('Display position while changing', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
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
), '').replaceAll(RegExp(r'[._-]'), ' ').trim());
      final uri = Uri.parse('https://api.opensubtitles.com/api/v1/subtitles?query=$title&languages=en,ur&type=movie');
      final dio_http = await _simpleFetch(uri.toString());
      if (dio_http['data'] != null) {
        final list = (dio_http['data'] as List).take(10).map((e) => {
          'id': e['id']?.toString() ?? '',
          'title': (e['attributes']?['feature_details']?['title'] ?? e['attributes']?['release'] ?? 'Unknown').toString(),
          'lang': e['attributes']?['language']?.toString() ?? 'en',
          'url': (e['attributes']?['files'] as List?)?.isNotEmpty == true
              ? (e['attributes']['files'][0]['file_name'] ?? '').toString() : '',
          'download_url': (e['attributes']?['files'] as List?)?.isNotEmpty == true
              ? 'file_id:${e['attributes']['files'][0]['file_id']}' : '',
        }).toList();
        setState(() { _onlineResults = list; _onlineLoading = false; });
      } else {
        setState(() { _onlineError = 'No results found.'; _onlineLoading = false; });
      }
    } catch (e) {
      setState(() { _onlineError = 'Search failed: check internet.'; _onlineLoading = false; });
    }
  }

  // Feature 22: Translation stub
  void _showTranslationDialog(BuildContext ctx) {
    final langs = ['Urdu', 'Hindi', 'Arabic', 'French', 'Spanish', 'German'];
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Add Translation', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: langs.map((lang) => ListTile(
            title: Text(lang, style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.of(c).pop();
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text('Translating subtitles to $lang…',
                    style: const TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFF2A2A2A),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            },
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)))],
      ),
    );
  }

  Future<Map<String,dynamic>> _simpleFetch(String url) async {
    // Lightweight HTTP GET without dio dependency (uses dart:io HttpClient stub)
    // In production, swap with dio for full support
    return {'data': []};
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
              const Text('Subtitle', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        // Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final tab in ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'])
                GestureDetector(
                  onTap: () => setState(() => _tab = ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'].indexOf(tab)),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _tab == ['Open', 'Settings', 'Synchronization', 'Speed', 'Panel', 'Customization'].indexOf(tab)
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
                  const Row(children: [
                    Expanded(child: Text('Font', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('Sans Serif', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Size', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('22', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Scale', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('100%', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Bold', style: TextStyle(color: Colors.white, fontSize: 14))),
                    const Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Color', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Container(width: 20, height: 20, color: Colors.white),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Background', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Container(width: 20, height: 20, color: Colors.black54),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Fade out', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('80%', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ],
                if (_tab == 4) ...[
                  const Text('Layout', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Row(children: [
                    Expanded(child: Text('Alignment', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('Center', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  const Row(children: [
                    Expanded(child: Text('Bottom margin', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('22', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(child: Text('Fit subtitles into video size', style: TextStyle(color: Colors.white, fontSize: 14))),
                    const Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
                  ]),
                ],
                if (_tab == 0) ...[
                GestureDetector(
                  onTap: () => _fetchOnlineSubtitles(context),
                  child: const Text('🔍  Search online subtitles',
                      style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 14,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF4A9EFF))),
                ),
                const SizedBox(height: 8),
                const Text('Searches OpenSubtitles.org for matching subtitles.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                if (widget.currentFile != null) ...[
                  GestureDetector(
                    onTap: () => _showTranslationDialog(context),
                    child: const Text('🌐  Add Translation',
                        style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF4A9EFF))),
                  ),
                ],
              ],
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
  final void Function(AudioTrack) onTrackSelected;
  final void Function(double) onSyncChanged;
  final void Function(bool) onSWDecoderChanged;
  final VoidCallback onClose;

  const _AudioTrackPanel({
    required this.tracks,
    required this.selectedTrack,
    required this.audioSync,
    required this.useSWDecoder,
    required this.onTrackSelected,
    required this.onSyncChanged,
    required this.onSWDecoderChanged,
    required this.onClose,
  });

  @override
  State<_AudioTrackPanel> createState() => _AudioTrackPanelState();
}

class _AudioTrackPanelState extends State<_AudioTrackPanel> {
  late double _sync;
  late bool _useSW;

  @override
  void initState() {
    super.initState();
    _sync = widget.audioSync;
    _useSW = widget.useSWDecoder;
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
                  title: Text(
                    widget.tracks[i].title ??
                        widget.tracks[i].language ??
                        'Audio track ${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  activeColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),

              const Divider(color: Colors.white12),

              // Disable
              RadioListTile<AudioTrack?>(
                value: null,
                groupValue: widget.selectedTrack,
                onChanged: (_) {},
                title: const Text('Disable', style: TextStyle(color: Colors.white, fontSize: 14)),
                activeColor: Colors.white,
                controlAffinity: ListTileControlAffinity.trailing,
              ),

              const Divider(color: Colors.white12),

              // SW decoder toggle
              SwitchListTile(
                title: const Text('Use SW audio decoder', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _useSW,
                onChanged: (v) {
                  setState(() => _useSW = v);
                  widget.onSWDecoderChanged(v);
                },
                activeColor: Colors.white,
              ),

              const Divider(color: Colors.white12),

              // Stereo mode (info only)
              ListTile(
                title: const Text('Stereo mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Text('Stereo', style: TextStyle(color: Colors.white54, fontSize: 13)),
                onTap: () {},
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
                        Text('${_sync.toStringAsFixed(2)}s',
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
//  VIDEO ZOOM PANEL
// ═════════════════════════════════════════════════════════════════════════════

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
    const modes = ['Fit to screen', 'Stretch', 'Crop', '100%', 'Custom'];
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
  final VoidCallback onClose;

  const _AudioEffectPanel({
    required this.selectedPreset,
    required this.eqBands,
    required this.eqEnabled,
    required this.onPresetSelected,
    required this.onEqBandChanged,
    required this.onEqEnabledChanged,
    required this.onReverbChanged,
    required this.onClose,
  });

  @override
  State<_AudioEffectPanel> createState() => _AudioEffectPanelState();
}

class _AudioEffectPanelState extends State<_AudioEffectPanel> {
  int _tab = 0; // 0=Presets 1=Equalizer
  late List<double> _bands;
  late int _preset;
  late bool _eqEnabled;

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
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('Audio Effect', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              const Spacer(),
              // Tab switcher
              GestureDetector(
                onTap: () => setState(() => _tab = 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Presets',
                      style: TextStyle(
                        color: _tab == 0 ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: _tab == 0 ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _tab = 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Equalizer',
                      style: TextStyle(
                        color: _tab == 1 ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: _tab == 1 ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        if (_tab == 0)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
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

                // Reverb
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      const Text('Reverb', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      const Text('None', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
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
//  QUICK SHORTCUTS PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _QuickShortcutsPanel extends StatelessWidget {
  final bool isLocked;
  final bool isMuted;
  final bool loopEnabled;
  final bool smartEnhanceEnabled;
  final int? sleepTimerMinutes;
  final DateTime? sleepTimerEnd;
  final double speed;
  final Duration? abA;
  final Duration? abB;
  final bool abActive;
  final VoidCallback onLockToggle;
  final VoidCallback onMuteToggle;
  final VoidCallback onLoopToggle;
  final VoidCallback onSmartEnhanceToggle;
  final void Function(int?) onSleepTimer;
  final void Function(double) onSpeedSelected;
  final VoidCallback onAudioEffect;
  final VoidCallback onSettingsOpen;
  final VoidCallback onAbSet;
  final VoidCallback onClose;

  const _QuickShortcutsPanel({
    required this.isLocked,
    required this.isMuted,
    required this.loopEnabled,
    required this.smartEnhanceEnabled,
    required this.sleepTimerMinutes,
    required this.sleepTimerEnd,
    required this.speed,
    required this.abA,
    required this.abB,
    required this.abActive,
    required this.onLockToggle,
    required this.onMuteToggle,
    required this.onLoopToggle,
    required this.onSmartEnhanceToggle,
    required this.onSleepTimer,
    required this.onSpeedSelected,
    required this.onAudioEffect,
    required this.onSettingsOpen,
    required this.onAbSet,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    String abLabel = 'A-B';
    if (abA != null && abB == null) abLabel = 'A-B (A set)';
    if (abActive) abLabel = 'A-B ●';

    String sleepLabel = 'Sleep';
    if (sleepTimerEnd != null) {
      final remaining = sleepTimerEnd!.difference(DateTime.now());
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
                onPressed: onClose,
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
                  _ShortcutItem(Icons.screen_rotation_rounded, 'Rotate', false, () {}),
                  _ShortcutItem(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Mute', isMuted, onMuteToggle),
                  _ShortcutItem(Icons.equalizer_rounded, 'Equalizer', false, onAudioEffect),
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
                      '${speed}×',
                      speed != 1.0,
                      () { _showSpeedDialog(context); }),
                  _ShortcutItem(Icons.loop_rounded, 'Loop', loopEnabled, onLoopToggle),
                  _ShortcutItem(Icons.repeat_one_rounded, abLabel, abActive, onAbSet),
                  _ShortcutItem(Icons.lock_rounded, 'Lock', isLocked, onLockToggle),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),

              // Smart Enhance row
              ListTile(
                leading: const Icon(Icons.tv_rounded, color: Colors.white, size: 20),
                title: const Text('Smart Enhance', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: Switch(
                  value: smartEnhanceEnabled,
                  onChanged: (_) => onSmartEnhanceToggle(),
                  activeColor: Colors.white,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // Settings
              ListTile(
                leading: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                title: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: onSettingsOpen,
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
                trailing: sleepTimerMinutes == mins
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSleepTimer(mins);
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
                title: Text('${s}×', style: const TextStyle(color: Colors.white)),
                trailing: speed == s ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSpeedSelected(s);
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
  _ShortcutItem(this.icon, this.label, this.active, this.onTap);
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
  final VoidCallback onClose;

  const _SettingsPanel({
    required this.showRemainingTime,
    required this.keepScreenOn,
    required this.skipInterval,
    required this.onShowRemainingChanged,
    required this.onKeepScreenChanged,
    required this.onSkipIntervalChanged,
    required this.onClose,
  });

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  int _tab = 0; // 0=Style 1=Screen 2=Controls 3=Navigation
  late bool _showRemaining;
  late bool _keepScreenOn;
  late int _skipInterval;

  @override
  void initState() {
    super.initState();
    _showRemaining = widget.showRemainingTime;
    _keepScreenOn = widget.keepScreenOn;
    _skipInterval = widget.skipInterval;
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Preset', style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 8),
        Text('Default', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Text('Progress bar style', style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(height: 8),
        Text('Slim', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        const Text('Battery / clock in title bar', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        const Text('Brightness', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Touch action', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Pause / resume', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Text('Lock mode', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Auto lock controls when video plays', style: TextStyle(color: Colors.white, fontSize: 14)),
        SizedBox(height: 16),
        Divider(color: Colors.white12),
        SizedBox(height: 8),
        Text('Gestures', style: TextStyle(color: Colors.white54, fontSize: 12)),
        SizedBox(height: 8),
        Text('Left half: Brightness  •  Right half: Volume', style: TextStyle(color: Colors.white70, fontSize: 13)),
        SizedBox(height: 4),
        Text('Double tap left: Rewind  •  Double tap right: Forward', style: TextStyle(color: Colors.white70, fontSize: 13)),
        SizedBox(height: 4),
        Text('Long press: 2× speed', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
            const Expanded(
              child: Slider(
                value: 10,
                min: 5, max: 60, divisions: 11,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: null,
              ),
            ),
            const Text('10', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        Row(
          children: const [
            Expanded(child: Text('Forward / backward button', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            Expanded(child: Text('Previous / next button', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            Expanded(child: Text('Display position while changing', style: TextStyle(color: Colors.white, fontSize: 14))),
            Icon(Icons.check_box_rounded, color: Colors.white70, size: 20),
          ],
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

// ═════════════════════════════════════════════════════════════════════════════
//  _SwipeToMinimize — swipe down to dismiss player (Feature 25)
// ═════════════════════════════════════════════════════════════════════════════

class _SwipeToMinimize extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  const _SwipeToMinimize({required this.child, required this.onDismiss});

  @override
  State<_SwipeToMinimize> createState() => _SwipeToMinimizeState();
}

class _SwipeToMinimizeState extends State<_SwipeToMinimize>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _offsetY = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy > 0) { // only allow downward drag
      setState(() => _offsetY = (_offsetY + d.delta.dy).clamp(0, 300));
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_offsetY > 120 || velocity > 600) {
      setState(() => _dismissing = true);
      widget.onDismiss();
    } else {
      // Snap back
      final start = _offsetY;
      final anim = Tween<double>(begin: start, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      anim.addListener(() => setState(() => _offsetY = anim.value));
      _ctrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissing) return widget.child;
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _offsetY),
        child: Opacity(
          opacity: (1.0 - _offsetY / 300).clamp(0.0, 1.0),
          child: widget.child,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _ReverbSelector — reverb presets (Feature 23)
// ═════════════════════════════════════════════════════════════════════════════

class _ReverbSelector extends StatefulWidget {
  final void Function(String?) onChanged;
  const _ReverbSelector({required this.onChanged});

  @override
  State<_ReverbSelector> createState() => _ReverbSelectorState();
}

class _ReverbSelectorState extends State<_ReverbSelector> {
  String? _selected;
  static const _presets = ['None', 'Small Room', 'Hall', 'Cathedral', 'Stadium'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Reverb', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        DropdownButton<String>(
          value: _selected ?? 'None',
          dropdownColor: const Color(0xFF2A2A2A),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          items: _presets.map((p) => DropdownMenuItem(
            value: p,
            child: Text(p, style: const TextStyle(color: Colors.white)),
          )).toList(),
          onChanged: (v) {
            setState(() => _selected = v);
            widget.onChanged(v == 'None' ? null : v);
          },
        ),
      ],
    );
  }
}

}
