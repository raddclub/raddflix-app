// player_screen.dart — Clean Player v2 (2026-06-19)
//
// Intentional design constraints (MediaTek/Infinix HW decoder safety):
//   • NEVER call setProperty('vf', ...) — destroys GL surface on HW decoder
//   • NEVER change hwdec mid-play
//   • _videoOpened = true set BEFORE every _player.open() call (no race window)
//   • Speed changes via NativePlayer.setProperty('speed', ...) with framedrop guard
//   • VideoController with androidAttachSurfaceAfterVideoParameters: false (critical)
//
// Features: play/pause · seek bar · ±10s skip · speed cycle · volume/brightness
//           swipe · double-tap seek · long-press 2× · episode list · prev/next
//           episode · watch-position save/restore · error retry · wakelock.

import 'dart:async';
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
    with WidgetsBindingObserver {

  // ── MPV player ──────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _videoCtrl;

  // NativePlayer getter — NEVER create a local variable named _np (would shadow this)
  NativePlayer get _np => _player.platform as NativePlayer;

  // ── Black-screen guards (MediaTek/Infinix) ──────────────────────────────────
  // Set true synchronously BEFORE every _player.open() call.
  // Prevents _applyVideoFilters-style startup races.
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
  String _currentFramedrop = 'vo'; // track framedrop direction for recovery

  // ── Gesture ─────────────────────────────────────────────────────────────────
  String? _dragIntent; // 'brightness' | 'volume' | 'seek'
  Offset _dragStart = Offset.zero;
  double _startBrightness = 0.5;
  double _startVolume = 0.7;
  Duration _dragStartPos = Duration.zero;
  double? _dragSeekDelta; // seconds offset while scrubbing

  // ── Indicators ──────────────────────────────────────────────────────────────
  double _brightness = 0.5;
  double _volume = 0.7;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  bool _showSeekFlash = false;
  bool _seekFlashLeft = false;
  Timer? _indicatorTimer;

  // ── Subscriptions ───────────────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  // ── Watch position ──────────────────────────────────────────────────────────
  Timer? _posTimer;

  // ─────────────────────────────────────────────────────────────────────────────
  //  Lifecycle
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();
    _currentEpIdx = widget.episodeIndex;
    _currentFileId = widget.fileId;
    _currentTitle = widget.title;
    _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchPos();
    } else if (state == AppLifecycleState.resumed) {
      // Re-enable immersive mode after notification shade etc.
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
    for (final s in _subs) { s.cancel(); }
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Player init
  // ─────────────────────────────────────────────────────────────────────────────

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'RaddFlix',
        logLevel: MPVLogLevel.error,
      ),
    );

    // CRITICAL: androidAttachSurfaceAfterVideoParameters: false
    // Setting it to true causes GL surface detach/reattach → black screen on MediaTek.
    _videoCtrl = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // Subscribe to streams
    _subs.addAll([
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }),
      _player.stream.position.listen((v) {
        if (mounted) setState(() => _position = v);
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
    ]);

    // Save position every 10 seconds
    _posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());

    // Open first media after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openMedia(_currentFileId, localPath: widget.localPath);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Stream resolution + open
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _openMedia(String fileId, {String? localPath}) async {
    _currentFileId = fileId.isNotEmpty ? fileId : _currentFileId;

    // Local file path — play directly, no JazzDrive needed
    final isLocal = (localPath != null && localPath.isNotEmpty) ||
        (fileId.startsWith('/') || fileId.startsWith('content://'));
    final effectivePath = localPath ?? (isLocal ? fileId : null);

    if (effectivePath != null) {
      if (mounted) setState(() { _streamError = null; _ended = false; _position = Duration.zero; });
      _videoOpened = true; // MUST be set BEFORE _player.open()
      await _player.open(Media(effectivePath));
      await _restoreWatchPos();
      if (mounted) setState(() { _isLinkLoading = false; });
      _scheduleHide();
      return;
    }

    // Catalog content — resolve stream URL via JazzDrive
    if (mounted) setState(() { _streamError = null; _isLinkLoading = true; _ended = false; _position = Duration.zero; });

    // Read inline share_url from route args (safe before any await)
    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map?;
    final inlineShareUrl = routeArgs?['stream_url'] as String?;

    String? shareUrl;
    String? targetFilename;
    int remoteId = 0;

    try {
      // Step 1: local DB
      if (fileId.isNotEmpty) {
        final info = await LocalDb.getShareInfo(fileId);
        shareUrl = info['share_url'] as String?;
        targetFilename = info['filename'] as String?;
        remoteId = info['remote_id'] as int? ?? 0;
      }

      // Step 2: inline route arg (RF1:xxx encoded — decode first)
      if ((shareUrl == null || shareUrl.isEmpty) &&
          inlineShareUrl != null && inlineShareUrl.isNotEmpty) {
        shareUrl = await LocalDb.decodeShareUrl(inlineShareUrl);
      }

      // Step 3: Oracle fallback for fresh installs
      if ((shareUrl == null || shareUrl.isEmpty) && fileId.isNotEmpty) {
        shareUrl = await CatalogApi.getShareUrl(fileId);
      }

      // Step 4: generate CDN stream URL via JazzDrive (zero-rated on Jazz SIM)
      if (shareUrl != null && shareUrl.isNotEmpty) {
        final cacheKey = fileId.isNotEmpty ? fileId : 'share_${shareUrl.hashCode}';
        final link = await JazzDriveService.getStreamLink(
          cacheKey, shareUrl,
          targetFilename: targetFilename,
          remoteId: remoteId,
        );
        if (mounted) setState(() { _isLinkLoading = false; _streamError = null; });
        _videoOpened = true; // MUST be set BEFORE _player.open()
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

  // ─────────────────────────────────────────────────────────────────────────────
  //  Episode navigation
  // ─────────────────────────────────────────────────────────────────────────────

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
    final localPath = ep['local_path'] as String?;
    final shareUrl = ep['share_url'] as String?;
    // Store share_url in route args equivalent — pass via openMedia directly
    _openMediaForEpisode(ep, localPath: localPath, shareUrl: shareUrl);
  }

  Future<void> _openMediaForEpisode(
    Map<String, dynamic> ep, {
    String? localPath,
    String? shareUrl,
  }) async {
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

      // Decode if still RF1-encoded
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
    _saveWatchPos();
    if (_hasNext) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _ended) _playEpisodeAt(_currentEpIdx + 1);
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Watch position
  // ─────────────────────────────────────────────────────────────────────────────

  String get _posKey {
    if (_currentFileId.isNotEmpty) return 'wp_$_currentFileId';
    final ep = _eps.isNotEmpty ? _eps[_currentEpIdx] : null;
    final lp = ep?['local_path'] as String? ?? widget.localPath ?? '';
    return 'wp_local_${lp.hashCode}';
  }

  Future<void> _saveWatchPos() async {
    final ms = _position.inMilliseconds;
    if (ms < 5000) return; // don't save if less than 5s in
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

  // ─────────────────────────────────────────────────────────────────────────────
  //  Controls
  // ─────────────────────────────────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
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

  // Speed cycling (tap on speed badge)
  void _cycleSpeed() {
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    _setSpeed(next);
  }

  // Speed change — uses NativePlayer channel with framedrop guard (MediaTek safety)
  Future<void> _setSpeed(double speed) async {
    final newFramedrop = speed > 1.0 ? 'decoder+vo' : 'vo';
    if (newFramedrop != _currentFramedrop) {
      _np.setProperty('framedrop', newFramedrop);
    }
    _np.setProperty('speed', speed.toStringAsFixed(4));
    if (newFramedrop != _currentFramedrop && _playing) {
      // Recovery seek after framedrop direction change (MediaTek GL surface safety)
      final pos = _player.state.position;
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) _player.seek(pos);
    }
    _currentFramedrop = newFramedrop;
    if (mounted) setState(() => _speed = speed);
  }

  // Long-press 2× fast-forward
  Future<void> _startLongPress() async {
    if (_longPressFast) return;
    _longPressFast = true;
    _np.setProperty('framedrop', 'decoder+vo');
    _np.setProperty('speed', '2.0000');
    final pos = _player.state.position;
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted && _longPressFast) _player.seek(pos);
    _currentFramedrop = 'decoder+vo';
    if (mounted) setState(() {});
  }

  Future<void> _endLongPress() async {
    if (!_longPressFast) return;
    _longPressFast = false;
    _np.setProperty('framedrop', 'vo');
    _np.setProperty('speed', '1.0000');
    final pos = _player.state.position;
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) _player.seek(pos);
    _currentFramedrop = 'vo';
    if (mounted) setState(() => _speed = 1.0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Gesture handlers
  // ─────────────────────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d, BoxConstraints constraints) {
    _dragStart = d.localPosition;
    _dragStartPos = _position;
    _startBrightness = _brightness;
    _startVolume = _volume;
    _dragSeekDelta = null;
    _dragIntent = null;
  }

  void _onDragUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    final dx = d.localPosition.dx - _dragStart.dx;
    final dy = d.localPosition.dy - _dragStart.dy;

    if (_dragIntent == null) {
      if (dx.abs() > dy.abs() && dx.abs() > 12) {
        _dragIntent = 'seek';
      } else if (dy.abs() > 12) {
        _dragIntent = _dragStart.dx < constraints.maxWidth / 2 ? 'brightness' : 'volume';
      }
    }

    if (_dragIntent == 'seek') {
      final seconds = dx / constraints.maxWidth * 120; // 120s across full width
      _dragSeekDelta = seconds;
      if (mounted) setState(() {});
    } else if (_dragIntent == 'brightness') {
      final newVal = (_startBrightness - dy / constraints.maxHeight * 1.5).clamp(0.0, 1.0);
      _brightness = newVal;
      ScreenBrightness().setScreenBrightness(newVal);
      _showBrightnessIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    } else if (_dragIntent == 'volume') {
      final newVal = (_startVolume - dy / constraints.maxHeight * 1.5).clamp(0.0, 1.0);
      _volume = newVal;
      VolumeController().setVolume(newVal);
      _showVolumeIndicator = true;
      _indicatorTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragIntent == 'seek' && _dragSeekDelta != null) {
      final target = _dragStartPos + Duration(milliseconds: (_dragSeekDelta! * 1000).round());
      _player.seek(target.isNegative ? Duration.zero : target);
      _dragSeekDelta = null;
    }
    if (_dragIntent == 'brightness' || _dragIntent == 'volume') {
      _indicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() { _showBrightnessIndicator = false; _showVolumeIndicator = false; });
      });
    }
    _dragIntent = null;
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ── Video surface ──────────────────────────────────────────────
              Positioned.fill(
                child: Video(
                  controller: _videoCtrl,
                  controls: NoVideoControls,
                ),
              ),

              // ── Gesture layer ──────────────────────────────────────────────
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTapDown: (d) {
                    final isLeft = d.localPosition.dx < constraints.maxWidth / 2;
                    _seekRelative(isLeft ? -10 : 10);
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

              // ── Seek flash indicators ──────────────────────────────────────
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
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_seekFlashLeft ? Icons.replay_10 : Icons.forward_10,
                              color: Colors.white, size: 36),
                          Text('10s', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Seek scrub preview ──────────────────────────────────────────
              if (_dragSeekDelta != null)
                Positioned(
                  top: constraints.maxHeight / 2 - 24,
                  left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatDuration(_dragStartPos + Duration(milliseconds: (_dragSeekDelta! * 1000).round())),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

              // ── Brightness indicator ───────────────────────────────────────
              if (_showBrightnessIndicator)
                Positioned(
                  left: 24, top: 0, bottom: 0,
                  child: Center(
                    child: _SideIndicator(
                      icon: Icons.brightness_6_rounded,
                      value: _brightness,
                    ),
                  ),
                ),

              // ── Volume indicator ──────────────────────────────────────────
              if (_showVolumeIndicator)
                Positioned(
                  right: 24, top: 0, bottom: 0,
                  child: Center(
                    child: _SideIndicator(
                      icon: Icons.volume_up_rounded,
                      value: _volume,
                    ),
                  ),
                ),

              // ── Long-press 2× badge ───────────────────────────────────────
              if (_longPressFast)
                Positioned(
                  top: 24, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('2× Speed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Controls overlay ──────────────────────────────────────────
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [
                      // Gradient top
                      Positioned(
                        top: 0, left: 0, right: 0, height: 100,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      // Gradient bottom
                      Positioned(
                        bottom: 0, left: 0, right: 0, height: 120,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter, end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      // ── Top bar ──────────────────────────────────────────
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                Expanded(
                                  child: Text(
                                    _currentTitle,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Episode list button (series only)
                                if (_eps.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.list_rounded, color: Colors.white),
                                    onPressed: _showEpisodeSheet,
                                  ),
                                // Speed badge
                                GestureDetector(
                                  onTap: _cycleSpeed,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _speed != 1.0 ? Colors.amber.withOpacity(0.85) : Colors.white24,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_speed}×',
                                      style: TextStyle(
                                        color: _speed != 1.0 ? Colors.black : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // ── Center play/pause ──────────────────────────────────
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasPrev)
                              _CenterBtn(
                                icon: Icons.skip_previous_rounded,
                                onTap: () => _playEpisodeAt(_currentEpIdx - 1),
                              ),
                            const SizedBox(width: 24),
                            _CenterBtn(
                              icon: Icons.replay_10_rounded,
                              onTap: () => _seekRelative(-10),
                              size: 36,
                            ),
                            const SizedBox(width: 16),
                            _CenterBtn(
                              icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              onTap: () {
                                _player.playOrPause();
                                _scheduleHide();
                              },
                              size: 52,
                              bg: true,
                            ),
                            const SizedBox(width: 16),
                            _CenterBtn(
                              icon: Icons.forward_10_rounded,
                              onTap: () => _seekRelative(10),
                              size: 36,
                            ),
                            const SizedBox(width: 24),
                            if (_hasNext)
                              _CenterBtn(
                                icon: Icons.skip_next_rounded,
                                onTap: () => _playEpisodeAt(_currentEpIdx + 1),
                              ),
                          ],
                        ),
                      ),
                      // ── Bottom seek bar ────────────────────────────────────
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Time labels
                                Row(
                                  children: [
                                    Text(
                                      _formatDuration(_dragSeekDelta != null
                                          ? _dragStartPos + Duration(milliseconds: (_dragSeekDelta! * 1000).round())
                                          : _position),
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _formatDuration(_duration),
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Seek slider
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                    trackHeight: 3,
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                    activeTrackColor: Colors.red,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    overlayColor: Colors.white24,
                                  ),
                                  child: Slider(
                                    value: _duration.inMilliseconds > 0
                                        ? (_dragSeekDelta != null
                                            ? ((_dragStartPos.inMilliseconds + _dragSeekDelta! * 1000)
                                                .clamp(0, _duration.inMilliseconds.toDouble()) /
                                                _duration.inMilliseconds)
                                            : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0))
                                        : 0.0,
                                    onChanged: (v) {
                                      final target = Duration(milliseconds: (v * _duration.inMilliseconds).round());
                                      _player.seek(target);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Buffering spinner ─────────────────────────────────────────
              if (_buffering && !_isLinkLoading && _streamError == null)
                const Center(child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2.5)),

              // ── Link loading overlay ──────────────────────────────────────
              if (_isLinkLoading)
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.red),
                        SizedBox(height: 16),
                        Text('Loading stream…', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),

              // ── Error overlay ─────────────────────────────────────────────
              if (_streamError != null)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _streamError!,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
                                child: const Text('Go Back', style: TextStyle(color: Colors.white70)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Auto-advance next episode banner ──────────────────────────
              if (_ended && _hasNext)
                Positioned(
                  bottom: 80, right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red, width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Next Episode in 3s', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _ended = false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 16)),
                              onPressed: () => _playEpisodeAt(_currentEpIdx + 1),
                              child: const Text('Play Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Episode sheet
  // ─────────────────────────────────────────────────────────────────────────────

  void _showEpisodeSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _eps.length,
        itemBuilder: (_, idx) {
          final ep = _eps[idx];
          final label = ep['label'] as String? ?? ep['title'] as String? ?? 'Episode ${idx + 1}';
          final isCurrent = idx == _currentEpIdx;
          return ListTile(
            leading: isCurrent
                ? const Icon(Icons.play_arrow_rounded, color: Colors.red)
                : Text('${idx + 1}', style: const TextStyle(color: Colors.white54)),
            title: Text(label, style: TextStyle(color: isCurrent ? Colors.red : Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
            onTap: () {
              Navigator.pop(context);
              if (idx != _currentEpIdx) _playEpisodeAt(idx);
              _scheduleHide();
            },
          );
        },
      ),
    ).then((_) => _scheduleHide());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CenterBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool bg;

  const _CenterBtn({required this.icon, required this.onTap, this.size = 28, this.bg = false});

  @override
  Widget build(BuildContext context) {
    final btn = Icon(icon, color: Colors.white, size: size);
    if (!bg) return GestureDetector(onTap: onTap, child: btn);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
        child: btn,
      ),
    );
  }
}

class _SideIndicator extends StatelessWidget {
  final IconData icon;
  final double value;

  const _SideIndicator({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            width: 4,
            child: RotatedBox(
              quarterTurns: -1,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
