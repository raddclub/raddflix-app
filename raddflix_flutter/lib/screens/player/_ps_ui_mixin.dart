part of '../player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Phase J5 — _PlayerUIMixin
//  Extracted from _PlayerScreenState (Phase J God-Class decomposition).
//  Owns: gesture handling (tap/pinch/drag/long-press), controls visibility
//  and immersive mode, zoom/crop, night mode, on-screen clock, sleep timer,
//  A-B repeat UI, layout presets/sidebar customization, watch-party dialogs,
//  voice commands, and every _buildXxx widget helper / _openXxxPanel /
//  _showXxxSheet presentation method for the player screen.
//
//  Cross-cluster members below are declared abstract because they are
//  implemented elsewhere in _PlayerScreenState (or one of its other part
//  files) — this mixin only has access to members declared in itself or in
//  ConsumerState<PlayerScreen>. Do NOT give these bodies here.
// ═══════════════════════════════════════════════════════════════════════════
mixin _PlayerUIMixin on ConsumerState<PlayerScreen> {
  // ── Cross-cluster members (defined in _PlayerScreenState or another mixin) ──
  List<Map<String, dynamic>> get _eps;
  bool get _hasNext;
  bool get _hasPrev;
  NativePlayer get _np;
  Duration get _duration;
  SubtitleTrack? get _selectedSubtitle; set _selectedSubtitle(SubtitleTrack? v);
  double get _silenceSkipThreshold; set _silenceSkipThreshold(double v);
  double get _subSync; set _subSync(double v);
  void _applySubtitleMargin({required bool controlsVisible});
  void _scheduleSavePrefs();
  void _showInfoSnackbar(String msg);
  void _minimizePlayer();

  // ── Cross-cluster methods (defined in other mixins) ──────────────────────
  void _adjustAudioSync(double delta);
  void _applyAllAf();
  void _applyBalance(double balance);
  void _applyCustomEq();
  void _applyPreset(int index);
  void _applySilenceSkip();
  Widget _buildDubProgressOverlay();
  void _cancelAutoRetry();
  void _disableDubMode();
  Future<void> _openMedia(String fileId, {String? localPath});
  void _openSubtitlePanel();
  void _playEpisodeAt(int idx);
  void _scheduleHide();
  void _setSleepTimer(int? minutes);
  Future<void> _setSpeed(double speed);
  void _syncNativeAbLoop();
  void _toggleLoop();
  void _toggleShuffle();
  void _toggleMute();

  // ── Cross-cluster fields (defined in other mixins) ────────────────────────
  Duration? get _abA; set _abA(Duration? v);
  bool get _abActive; set _abActive(bool v);
  Duration? get _abB; set _abB(Duration? v);
  double get _audioBalance;
  double get _bufferedFraction;
  bool get _buffering;
  int get _channelModeIdx; set _channelModeIdx(int v);
  String get _currentChannelModeAf; set _currentChannelModeAf(String v);
  int get _currentEpIdx;
  String get _currentFileId;
  String get _currentLabAf; set _currentLabAf(String v);
  String get _currentReverbAf; set _currentReverbAf(String v);
  String get _currentTitle;
  // SUB-OVERLAY-FIX: declared in _PlayerSubtitleMixin; read here for SubtitleOverlay
  String? get _currentSubLine;
  String get _dubActiveLang;
  bool get _dubGenerating;
  String get _endAction; set _endAction(String v);
  List<double> get _eqBands;
  bool get _eqEnabled; set _eqEnabled(bool v);
  bool get _isDubMode;
  bool get _isLinkLoading;
  bool get _isMuted;
  bool get _labBass; set _labBass(bool v);
  double get _labBassLevel; set _labBassLevel(double v);
  bool get _labCompress; set _labCompress(bool v);
  bool get _labDialogue; set _labDialogue(bool v);
  bool get _labDialogueOnly; set _labDialogueOnly(bool v);
  bool get _labNoise; set _labNoise(bool v);
  bool get _labNorm; set _labNorm(bool v);
  bool get _labStereoWide; set _labStereoWide(bool v);
  bool get _labVocal; set _labVocal(bool v);
  bool get _longPressFast; set _longPressFast(bool v);
  bool get _loopEnabled;
  bool get _shuffleEnabled;
  int get _orientMode; set _orientMode(int v);
  bool get _isAudioOnly;
  bool get _playing;
  Duration get _position;
  List<SubtitleTrack> get _realSubtitleTracks;
  String get _reverbPreset; set _reverbPreset(String v);
  int get _selectedPreset; set _selectedPreset(int v);
  bool get _silenceSkipEnabled; set _silenceSkipEnabled(bool v);
  double get _speed;
  String? get _streamError; set _streamError(String? v);
  VideoController get _videoCtrl;
  Player get _player;

  bool _showControls = true;

  bool _panelOpen = false;

  // ── Live TV helpers ──────────────────────────────────────────────────────────
  bool get _isLive => widget.contentType == 'live';

  Timer? _hideTimer;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

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

  bool _showSeekFlash = false;

  bool _seekFlashLeft = false;

  List<AudioTrack> _audioTracks = [];

  AudioTrack? _selectedAudio;

  String? _prefAudioLang;

  bool _isLocked = false;

  bool _isImmersive = false;        // Immersive / cinema mode
  bool _immersiveExitVisible = false; // tiny exit button visible after tap
  Timer? _immersiveExitTimer;       // auto-hides exit button after 3s
  BoxFit _videoFit = BoxFit.contain;

  bool _smartEnhanceEnabled = false;

  Timer? _smartEnhanceTimer;

  int _zoomMode = 0;

  double _pinchScale = 1.0;

  double _pinchBaseScale = 1.0;

  bool _showZoomIndicator = false;

  bool _nightModeEnabled = false;

  double _nightWarmth = 0.4;

  bool _showClockInTitle = true;
  // ── Status HUD (clock format + battery) ──────────────────────────────────
  // 0 = Auto (follow device 12h/24h setting), 1 = force 12-hour, 2 = force 24-hour
  int _clockFormat = 0;
  bool _showBatteryInTitle = true;
  bool _batteryChargeAnim = true;
  int? _batteryLevel;
  BatteryState _batteryState = BatteryState.unknown;
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySub;
  Timer? _batteryPollTimer;

  String _clockStr = '';

  Timer? _clockDisplayTimer;

  int _videoRotation = 0;

  double _audioSync = 0.0;

  bool _useSWDecoder = false;

  String _currentAudioCodec = '';

  List<AudioTrack> get _realAudioTracks =>
      _audioTracks.where((t) => t.id != null && int.tryParse(t.id!) != null).toList();

  int? _sleepTimerMinutes;

  Timer? _sleepTimer;

  int _autoAdvanceCountdown = 0;

  Timer? _autoAdvanceTimer;

  DateTime? _sleepTimerEnd;

  bool _showRemainingTime = false;

  bool _keepScreenOn = true;

  bool _showSkipBtns = true;

  bool _showPrevNextBtns = true;

  bool _showSeekPositionLabel = true;

  int _skipInterval = 10;

  double _seekSwipeSec = 120.0;

  Timer? _savePositionTimer;

  Timer? _bgNotifTimer;

  bool _isInBackground = false;

  String _layoutPreset = 'default'; // default | cinema | compact

  // ── Live quality selector state (LIVE-P7-A) ──────────────────────────────
  // _liveRenditions is populated by _fetchLiveRenditions() after each live
  // channel opens. Empty = no renditions available (single-stream or blocked).
  // _selectedRenditionIdx: -1 = Auto ABR (default), 0+ = specific rendition.
  List<_LiveRendition> _liveRenditions = [];
  int _selectedRenditionIdx = -1;
  bool _liveRenditionsFetching = false;

  // Voice commands
  bool _voiceCommandsEnabled = false;

  bool _doubleTapSeekEnabled = true;

  bool _longPressSpeedEnabled = true;

  bool _swipeSeekEnabled = true;

  bool _swipeBVEnabled = true;

  bool _skipEditorEnabled = false;

  Duration? _introStart;

  Duration? _introEnd;

  Duration? _outroStart;

  WatchPartyRoom? _watchPartyRoom;

  StreamSubscription<WatchPartyRoom?>? _watchPartySub;

  StreamSubscription<VoiceCommand>? _voiceSub;

  String _lastVoiceCmd = '';

  Timer? _voiceCmdTimer;

  bool _oneHandedLeft = false;

  bool _sidebarExpanded = true;

  List<String> _sidebarOrder = [
    'bgaudio','cc','audio','eq','vivid','episodes','speed','loop','pip',
  ];

  static const _allSidebarIds = [
    'bgaudio','cc','audio','eq','speed','loop','rotate','lock','pip',
    'screenshot','sleep','ab','episodes','settings','vivid',
    'mute','frame','onehanded','zoom','silence','more',
  ];

  String? _lastSkipRegion;

  int _cropAspectIdx = 0;

  bool _oneHandedMode = false;

  bool _backgroundAudio = false;

  int _accentColorIdx = 0;

  static const _accentColors = [
    Color(0xFFE8950A),
    Color(0xFF3A8EF5),
    Color(0xFF34C759),
    Color(0xFFFF2D55),
  ];

  Color get _accentColor => _accentColors[_accentColorIdx];

  int _progressBarStyle = 0;

  String _seekPreviewLabel = '';

  String _fmtClock() {
    final n = DateTime.now();
    // 0 = Auto → follow the device's own 12h/24h system setting
    // (MediaQuery.alwaysUse24HourFormat mirrors that OS preference exactly,
    // same signal Android's own status bar clock uses).
    final use24 = _clockFormat == 2 ||
        (_clockFormat == 0 && MediaQuery.of(context).alwaysUse24HourFormat);
    if (use24) {
      return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    }
    final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final ampm = n.hour < 12 ? 'AM' : 'PM';
    return '$h12:${n.minute.toString().padLeft(2, '0')} $ampm';
  }

  // ── Battery HUD ───────────────────────────────────────────────────────────
  // battery_plus only pushes *state* changes (charging/discharging/full) —
  // level has to be polled. 60s is plenty for a status readout, not a
  // precision gauge, and keeps this off the hot path entirely.
  void _initBatteryMonitor() {
    _battery.batteryLevel.then((lvl) {
      if (mounted) setState(() => _batteryLevel = lvl);
    }).catchError((_) {});
    _battery.batteryState.then((s) {
      if (mounted) setState(() => _batteryState = s);
    }).catchError((_) {});
    _batterySub = _battery.onBatteryStateChanged.listen((s) {
      if (mounted) setState(() => _batteryState = s);
      // A state change (e.g. plugged in) is exactly when the level is also
      // likely to have just changed — refresh it immediately instead of
      // waiting for the next poll tick.
      _battery.batteryLevel.then((lvl) {
        if (mounted) setState(() => _batteryLevel = lvl);
      }).catchError((_) {});
    }, onError: (_) {});
    _batteryPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _battery.batteryLevel.then((lvl) {
        if (mounted) setState(() => _batteryLevel = lvl);
      }).catchError((_) {});
    });
  }

  void _disposeBatteryMonitor() {
    _batterySub?.cancel();
    _batteryPollTimer?.cancel();
  }

  IconData _batteryIconFor(int lvl, bool charging) {
    if (charging) return Icons.battery_charging_full_rounded;
    if (lvl >= 95) return Icons.battery_full_rounded;
    if (lvl >= 80) return Icons.battery_6_bar_rounded;
    if (lvl >= 60) return Icons.battery_5_bar_rounded;
    if (lvl >= 45) return Icons.battery_4_bar_rounded;
    if (lvl >= 30) return Icons.battery_3_bar_rounded;
    if (lvl >= 15) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }

  /// Compact battery readout for the player's top bar — mirrors what
  /// Android's own status bar shows (icon + %), plus a pulsing bolt while
  /// charging so it's obvious at a glance mid-movie without looking away
  /// from the video. Fully optional — off entirely when the user disables
  /// "Show battery" in Settings → Style.
  Widget _buildBatteryBadge() {
    if (!_showBatteryInTitle || _batteryLevel == null) return const SizedBox.shrink();
    final lvl = _batteryLevel!;
    final isCharging = _batteryState == BatteryState.charging ||
        _batteryState == BatteryState.full;
    final low = lvl <= 15 && !isCharging;
    final color = low ? const Color(0xFFFF4D4D) : Colors.white70;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCharging && _batteryChargeAnim)
            Icon(_batteryIconFor(lvl, true), size: 15, color: const Color(0xFF34C759))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 700.ms, curve: Curves.easeInOut)
                .then()
                .fadeOut(duration: 700.ms, curve: Curves.easeInOut, begin: 1.0)
          else
            Icon(_batteryIconFor(lvl, isCharging), size: 15,
                color: isCharging ? const Color(0xFF34C759) : color),
          const SizedBox(width: 2),
          Text('$lvl%',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _fmtSleepRemaining() {
    if (_sleepTimerEnd == null) return '';
    final mins = _sleepTimerEnd!.difference(DateTime.now()).inMinutes;
    return mins > 0 ? '${mins}m' : '<1m';
  }

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

  void _toggleSmartEnhance() {
    setState(() => _smartEnhanceEnabled = !_smartEnhanceEnabled);
    _scheduleSavePrefs();
    _showInfoSnackbar(_smartEnhanceEnabled ? 'Vivid Mode on' : 'Vivid Mode off');
  }

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
    // LIVE-P3: horizontal swipe on a live stream switches channels instead of
    // seeking (live streams have no meaningful seek target).
    if (_isLive && _dragIntent == 'seek') {
      final vx = d.velocity.pixelsPerSecond.dx;
      if (vx.abs() > 500) {
        // Swipe right (positive dx) → previous channel; left → next channel.
        _switchToAdjacentLiveChannel(vx > 0 ? -1 : 1);
      }
      _seekBarDelta = null;
      _dragIntent = null;
      if (mounted) setState(() {});
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

    Widget _buildVideoSurface() {
      Widget video = SizedBox.expand(
        child: Video(
          controller: _videoCtrl,
          controls: NoVideoControls,
          fit: _getBoxFit(),
          // SUB-OVERLAY-FIX: disable MPV's native subtitle renderer so the
          // Flutter SubtitleOverlay widget owns all rendering.  Without this
          // line MPV kept rendering subs inside the SurfaceView texture — a
          // layer that has no knowledge of Flutter controls — while
          // SubtitleOverlay was never wired up, so every style/position
          // change pushed via NativePlayer.setProperty() fought against
          // embedded ASS style blocks and never stuck reliably.
          subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
        ),
      );

      if (_smartEnhanceEnabled) {
        // Vivid Mode — Rec.709 luminance-weighted saturation (s=1.35) + contrast (c=1.12).
        // Uses proper cross-channel mixing so colours become more vibrant with ZERO colour cast
        // (no yellow tint). Formula: combined matrix = contrast(c) × saturation(s) where
        //   lumR=0.2126, lumG=0.7152, lumB=0.0722 (standard Rec.709 weights)
        //   sat row R : [(1-s)*lumR+s, (1-s)*lumG,      (1-s)*lumB     ]
        //   contrast  : multiply each row by c, offset = -(c-1)*128
        // Net result: colours punch up ~35%, contrast tightens ~12%, whites/greys stay neutral.
        video = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
             1.43, -0.28, -0.03, 0.0, -16.0,
            -0.08,  1.23, -0.03, 0.0, -16.0,
            -0.08, -0.28,  1.48, 0.0, -16.0,
             0.0,   0.0,   0.0,  1.0,   0.0,
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
                child: Stack(
                  children: [
                    // ── Background audio quick-toggle (top-left) ─────────────
                    // Accessible even while the screen is locked so users can
                    // flip BG audio on/off before minimising without unlocking.
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _backgroundAudio = !_backgroundAudio);
                            _scheduleSavePrefs();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _backgroundAudio
                                  ? Colors.orange.withOpacity(0.25)
                                  : Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _backgroundAudio
                                    ? Colors.orange.withOpacity(0.6)
                                    : Colors.white24,
                              ),
                            ),
                            child: Icon(
                              _backgroundAudio
                                  ? Icons.headphones_rounded
                                  : Icons.headphones_outlined,
                              color: _backgroundAudio ? Colors.orange : Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── Unlock button (top-right) ────────────────────────────
                    Align(
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
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
            // ── Background audio quick-toggle ─────────────────────────────
            // Persistent 1-tap access without opening any panel or sidebar.
            // Orange tint makes "active" state unambiguous at a glance.
            _RaddIconBtn(
              icon: _backgroundAudio
                  ? Icons.headphones_rounded
                  : Icons.headphones_outlined,
              size: 20,
              color: _backgroundAudio ? Colors.orange : Colors.white,
              onTap: () {
                setState(() => _backgroundAudio = !_backgroundAudio);
                _scheduleSavePrefs();
              },
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
            // Back button — always fully ends this playback session.
            _RaddIconBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 20,
              onTap: () => Navigator.of(context).pop(),
            ),

            // UX3-10: Minimize — keeps playback running behind a live mini
            // bar on Home/Search/etc. instead of ending the session.
            // Dimmed relative to Back so the two adjacent, differently-
            // consequential actions aren't visually interchangeable.
            _RaddIconBtn(
              icon: Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: Colors.white70,
              onTap: _minimizePlayer,
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

            // Battery HUD (icon + % + charging pulse) — mirrors the device
            // status bar so viewers can track charge without leaving the video.
            _buildBatteryBadge(),

            // Clock overlay — respects the user's 12h/24h preference (Settings → Style).
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

            // Background audio toggle button — always visible so the user can
            // turn BG audio on without opening the sidebar or switching to
            // one-handed mode.  Orange headphones = active; dimmed outline =
            // inactive.  Tapping while active also turns it off — one tap
            // in either direction from the top bar.
            GestureDetector(
              onTap: () {
                setState(() => _backgroundAudio = !_backgroundAudio);
                _scheduleSavePrefs();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 2),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _backgroundAudio
                      ? Colors.orange.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: _backgroundAudio
                      ? Border.all(color: Colors.orange.withOpacity(0.45), width: 0.8)
                      : null,
                ),
                child: Icon(
                  _backgroundAudio
                      ? Icons.headphones_rounded
                      : Icons.headphones_outlined,
                  color: _backgroundAudio ? Colors.orange : Colors.white38,
                  size: 18,
                ),
              ),
            ),

          ],
        ),
      );
    }

    Widget _buildCenterControls() {
      // Cinematic mode — no buttons in the center of the video.
      // All playback controls live under the seek bar only.
      return const SizedBox.shrink();
    }

    Widget _buildBottomArea(BoxConstraints constraints, Duration currentPos) {
      // Live TV: replace seek bar + full transport with live status row + simplified controls.
      if (_isLive) return _buildLiveBottomArea();

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

    // ══════════════════════════════════════════════════════════════════════════
    //  Live TV UI helpers
    //  Shown when widget.contentType == 'live'.
    //  • Seek bar is replaced with a red ● LIVE status indicator.
    //  • Replay/skip/prev/next transport buttons are hidden.
    //  • A channel-switcher button opens a bottom sheet listing all live channels.
    // ══════════════════════════════════════════════════════════════════════════

    /// Landscape bottom area for live content.
    Widget _buildLiveBottomArea() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLiveStatusRow(),
            const SizedBox(height: 6),
            _buildLiveTransportRow(),
          ],
        ),
      );
    }

    /// Portrait panel for live content (landscape controls bottom area only —
    /// not used in portrait since P2 replaced portrait with its own scaffold).
    Widget _buildLivePortraitPanel() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLiveStatusRow(),
            const SizedBox(height: 6),
            _buildLiveTransportRow(),
          ],
        ),
      );
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  LIVE-P2: YouTube-style portrait scaffold for live TV
    //  Layout: header bar → 16:9 video box → identity bar → channel list.
    //  Replaces the full-bleed TikTok portrait layout for live content only.
    // ══════════════════════════════════════════════════════════════════════════

    Widget _buildLivePortraitScaffold(BoxConstraints constraints) {
      final channels = ref.watch(liveChannelProvider).channels;
      return Container(
        color: Colors.black,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Header bar (back + channel name + settings) ─────────────
            SafeArea(
              bottom: false,
              child: _buildLivePortraitHeader(),
            ),

            // ── 2. 16:9 video box with tap overlay and status overlays ─────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildLiveVideoBox(),
            ),

            // ── 3. Channel identity bar (logo + name + LIVE badge) ─────────
            _buildLiveIdentityBar(),

            const Divider(height: 0.5, color: Color(0x1AFFFFFF), thickness: 0.5),

            // ── 4. Inline channel list (scrollable, fills remaining space) ──
            Expanded(
              child: _buildLiveInlineChannelList(channels),
            ),
          ],
        ),
      );
    }

    /// Top header bar for the live portrait scaffold.
    Widget _buildLivePortraitHeader() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            _RaddIconBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 18,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _RaddIconBtn(
              icon: Icons.settings_rounded,
              size: 18,
              onTap: _openLiveSettingsPanel,
            ),
          ],
        ),
      );
    }

    /// 16:9 video box with status overlays for the live portrait scaffold.
    Widget _buildLiveVideoBox() {
      return Stack(
        children: [
          // Video surface — fills the AspectRatio box
          Positioned.fill(child: RepaintBoundary(child: _buildVideoSurface())),

          // Gesture layer: tap to toggle controls overlay
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
            ),
          ),

          // Buffering spinner
          if (_buffering && !_isLinkLoading && _streamError == null)
            const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),

          // Reconnecting label shown below spinner during live stream stall
          if (_buffering && !_isLinkLoading && _streamError == null)
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.70),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Reconnecting…',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),

          // Link loading
          if (_isLinkLoading)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 8),
                  Text('Connecting…',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),

          // Error overlay (compact live version)
          if (_streamError != null) _buildLiveErrorOverlay(),

          // Controls overlay (auto-hides)
          AnimatedOpacity(
            opacity: _showControls && !_isLocked ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: !_showControls || _isLocked,
              child: _buildLiveVideoControlsOverlay(),
            ),
          ),

          // Always-visible LIVE badge when controls are hidden
          if (!_showControls || _isLocked)
            Positioned(
              top: 7, left: 9,
              child: _buildLiveBadgePill(),
            ),
        ],
      );
    }

    /// Compact controls overlay that sits on the 16:9 video box in portrait.
    Widget _buildLiveVideoControlsOverlay() {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x99000000), Colors.transparent, Color(0x99000000)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // LIVE badge — top-left
            Positioned(
              top: 7, left: 9,
              child: _buildLiveBadgePill(),
            ),
            // Fullscreen button — top-right
            Positioned(
              top: 2, right: 2,
              child: _RaddIconBtn(
                icon: Icons.fullscreen_rounded,
                size: 22,
                onTap: () {
                  _setNativeOrientation('sensor_landscape');
                  setState(() => _orientMode = 1);
                },
              ),
            ),
            // Play/pause — center
            Center(
              child: GestureDetector(
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
            ),
            // Bottom row: channel list + settings + lock
            Positioned(
              bottom: 6, left: 6, right: 6,
              child: Row(
                children: [
                  _RaddIconBtn(
                    icon: Icons.list_rounded,
                    size: 18,
                    onTap: _openChannelSwitcher,
                  ),
                  const Spacer(),
                  _RaddIconBtn(
                    icon: Icons.settings_rounded,
                    size: 18,
                    onTap: _openLiveSettingsPanel,
                  ),
                  _RaddIconBtn(
                    icon: Icons.lock_outline_rounded,
                    size: 18,
                    onTap: () => setState(() {
                      _isLocked = true;
                      _showControls = false;
                      _applySubtitleMargin(controlsVisible: false);
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    /// Compact LIVE badge pill — shown on video box corner.
    Widget _buildLiveBadgePill() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    /// Identity bar: channel logo + name + LIVE status + channel switcher icon.
    Widget _buildLiveIdentityBar() {
      final logoUrl = widget.posterUrl ?? '';
      return Container(
        color: const Color(0xFF111111),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Channel logo
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: logoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.live_tv_rounded, size: 22, color: Colors.white38),
                      ),
                    )
                  : const Icon(Icons.live_tv_rounded, size: 26, color: Colors.white38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Pulsing red dot
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: Color(0x88FF0000), blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Channel list button
            _RaddIconBtn(
              icon: Icons.swap_vert_rounded,
              size: 20,
              onTap: _openChannelSwitcher,
            ),
          ],
        ),
      );
    }

    /// Inline scrollable channel list shown below the identity bar in portrait.
    Widget _buildLiveInlineChannelList(List<LiveChannel> channels) {
      final String currentId = widget.fileId.startsWith('live_')
          ? widget.fileId.substring(5)
          : '';
      if (channels.isEmpty) {
        return const Center(
          child: Text('Loading channels…',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 20),
        itemCount: channels.length,
        itemBuilder: (_, i) {
          final ch = channels[i];
          final isCurrent = ch.id == currentId;
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            tileColor: isCurrent ? Colors.white.withOpacity(0.06) : null,
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: ch.hexColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: ch.logoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        ch.logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.live_tv_rounded,
                            size: 18,
                            color: Colors.white38),
                      ),
                    )
                  : const Icon(Icons.live_tv_rounded,
                      size: 18, color: Colors.white38),
            ),
            title: Text(
              ch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight:
                    isCurrent ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              ch.genre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            trailing: isCurrent
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  )
                : null,
            onTap: isCurrent
                ? null
                : () {
                    Navigator.pushReplacementNamed(
                        context, AppRoutes.player,
                        arguments: {
                          'file_id':      'live_${ch.id}',
                          'title':        ch.name,
                          'stream_url':   ch.streamUrl,
                          'content_type': 'live',
                          'is_free':      ch.isFree,
                          'poster_url':   ch.logoUrl,
                        });
                  },
          );
        },
      );
    }

    /// Red ● LIVE indicator row with channel name.
    Widget _buildLiveStatusRow() {
      return Row(
        children: [
          // Static red dot — clear enough without animation inside the player.
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Color(0x88FF0000), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    /// Simplified transport row for live: play/pause centred, channel-switcher
    /// on the left, lock/immersive/settings on the right.
    Widget _buildLiveTransportRow() {
      return SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel switcher
                _RaddIconBtn(
                  icon: Icons.list_rounded,
                  size: 22,
                  onTap: _openChannelSwitcher,
                ),
                const Spacer(),
                // Utility buttons
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
            // Play/pause — always pixel-centred via Stack
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

    // ══════════════════════════════════════════════════════════════════════════
    //  LIVE-P4: Error/reconnecting UX for live streams
    // ══════════════════════════════════════════════════════════════════════════

    /// Compact error overlay used inside the 16:9 live video box.
    Widget _buildLiveErrorOverlay() {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                    Icons.signal_wifi_connected_no_internet_4_rounded,
                    color: Colors.white38,
                    size: 38),
                const SizedBox(height: 10),
                Text(
                  _streamError ?? 'Stream unavailable',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Retry'),
                      onPressed: () {
                        _cancelAutoRetry();
                        setState(() => _streamError = null);
                        _openMedia(_currentFileId);
                      },
                    ),
                    TextButton(
                      onPressed: _openChannelSwitcher,
                      child: const Text(
                        'Switch Channel',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  LIVE-P3: Landscape watermark + swipe-to-switch
    // ══════════════════════════════════════════════════════════════════════════

    /// Semi-transparent channel logo watermark — bottom-right corner.
    /// Used in landscape fullscreen live mode. Always visible (not control-gated).
    Widget _buildLiveLandscapeWatermark() {
      final logoUrl = widget.posterUrl ?? '';
      if (logoUrl.isEmpty) return const SizedBox.shrink();
      return Positioned(
        bottom: 18,
        right: 76, // clear of the shortcut sidebar
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.20,
            child: Image.network(
              logoUrl,
              width: 56,
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    /// Swipe-to-switch: called from _onScaleEnd when a horizontal swipe is
    /// detected on a live stream. [delta] = -1 for previous, +1 for next.
    void _switchToAdjacentLiveChannel(int delta) {
      final channels = ref.read(liveChannelProvider).channels;
      if (channels.isEmpty) return;
      final currentId = widget.fileId.startsWith('live_')
          ? widget.fileId.substring(5)
          : '';
      final idx = channels.indexWhere((c) => c.id == currentId);
      if (idx < 0) return;
      final nextIdx = (idx + delta).clamp(0, channels.length - 1);
      if (nextIdx == idx) return;
      final next = channels[nextIdx];
      HapticFeedback.lightImpact();
      Navigator.pushReplacementNamed(context, AppRoutes.player,
          arguments: {
            'file_id':      'live_${next.id}',
            'title':        next.name,
            'stream_url':   next.streamUrl,
            'content_type': 'live',
            'is_free':      next.isFree,
            'poster_url':   next.logoUrl,
          });
    }

    /// Bottom sheet listing all live channels — tap one to switch via
    /// pushReplacementNamed so the route stack stays clean.
    void _openChannelSwitcher() {
      final channels = ref.read(liveChannelProvider).channels;
      if (channels.isEmpty) return;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LiveChannelSwitcherSheet(
          channels: channels,
          currentTitle: widget.title,
          onSelect: (ch) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, AppRoutes.player,
                arguments: {
                  'file_id':      'live_${ch.id}',
                  'title':        ch.name,
                  'stream_url':   ch.streamUrl,
                  'content_type': 'live',
                  'is_free':      ch.isFree,
                  'poster_url':   ch.logoUrl,
                });
          },
        ),
      );
    }

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
        'bgaudio': (
          icon: _backgroundAudio ? Icons.music_note_rounded : Icons.music_off_rounded,
          label: 'BG Audio',
          active: _backgroundAudio,
          available: true,
          onTap: () {
            setState(() => _backgroundAudio = !_backgroundAudio);
            _scheduleSavePrefs();
          },
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

    Widget _buildPortraitLayout(BoxConstraints constraints) {
      // LIVE-P2: Live TV gets a YouTube-style portrait layout —
      // 16:9 video box at the top, identity bar, then inline channel list below.
      // This replaces the full-bleed TikTok layout for live content only.
      if (_isLive) return _buildLivePortraitScaffold(constraints);

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

                // Flutter subtitle overlay — SUB-OVERLAY-FIX (portrait)
                // Mirrors the landscape layer in player_screen.dart.
                if (!_isAudioOnly)
                  Positioned.fill(
                    child: Consumer(
                      builder: (ctx, ref, _) {
                        final prefs = ref.watch(playerPrefsProvider);
                        return IgnorePointer(
                          ignoring: !prefs.dictEnabled,
                          child: SubtitleOverlay(
                            currentLine: _currentSubLine,
                            prefs: prefs,
                            onPausedForLookup: () {
                              try { _player.pause(); } catch (_) {}
                            },
                            onResumedAfterLookup: () {
                              try { _player.play(); } catch (_) {}
                            },
                          ),
                        );
                      },
                    ),
                  ),

                // Audio-mode backdrop — sits above the (blank) video SurfaceView
                // whenever MPV opens a file with no video track. Gives audio-only
                // playback a blurred art backdrop, rotating vinyl disc, and a
                // frosted-glass controls card instead of a dead black screen.
                if (_isAudioOnly)
                  Positioned.fill(
                    child: AudioModeBackdrop(
                      isPlaying: _playing,
                      position: _position,
                      duration: _duration,
                      title: _currentTitle,
                      localPath: widget.localPath,
                      hasPrev: _hasPrev,
                      hasNext: _hasNext,
                      loopEnabled: _loopEnabled,
                      shuffleEnabled: _shuffleEnabled,
                      onPlayPause: () {
                        if (_playing) {
                          _player.pause();
                        } else {
                          _player.play();
                        }
                      },
                      onSeek: (pos) => _player.seek(pos),
                      onPrev: _hasPrev
                          ? () => _playEpisodeAt(_currentEpIdx - 1)
                          : null,
                      onNext: _hasNext
                          ? () => _playEpisodeAt(_currentEpIdx + 1)
                          : null,
                      onLoopToggle: _toggleLoop,
                      onShuffleToggle: _toggleShuffle,
                    ),
                  ),

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
                          onTap: () {
                            // BB4: if pipOnMinimize is on and video is playing,
                            // enter PiP instead of popping. Shows a one-time tip.
                            final p = ref.read(playerPrefsProvider);
                            if (p.pipOnMinimize && _player.state.playing) {
                              _enterPiP();
                              SharedPreferences.getInstance().then((sp) {
                                if (!(sp.getBool('seen_pip_tip') ?? false)) {
                                  sp.setBool('seen_pip_tip', true);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Video continues in a floating window'),
                                        duration: Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              });
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),

                // ── Fade-in title bar: title + episode + rotate + PiP ──────────
                // BB7: slide+fade on basic+ tiers; potato gets opacity only
                // (AnimDurations.controlsShow returns Duration.zero on potato,
                // making AnimatedSlide an instant snap — effectively no slide).
                if (!_isImmersive)
                  Positioned(
                    top: 0, left: 44, right: 0,
                    child: AnimatedSlide(
                      offset: _showControls && !_isLocked
                          ? Offset.zero
                          : const Offset(0, -1),
                      duration: _showControls
                          ? AnimDurations.controlsShow(ref.read(animConfigProvider))
                          : AnimDurations.controlsHide(ref.read(animConfigProvider)),
                      curve: _showControls ? Curves.easeOutCubic : Curves.easeIn,
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
                // BB7: slide+fade on basic+ tiers (same tier-gate as top bar).
                if (!_isImmersive)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: AnimatedSlide(
                      offset: _showControls && !_isLocked
                          ? Offset.zero
                          : const Offset(0, 1),
                      duration: _showControls
                          ? AnimDurations.controlsShow(ref.read(animConfigProvider))
                          : AnimDurations.controlsHide(ref.read(animConfigProvider)),
                      curve: _showControls ? Curves.easeOutCubic : Curves.easeIn,
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
      // Live TV: show live status row + simplified transport only.
      if (_isLive) return _buildLivePortraitPanel();

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
          _scheduleSavePrefs(); // pref_sw_dec — was missing, choice lost on exit if nothing else saved
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
        clockFormat: _clockFormat,
        onClockFormatChanged: (v) {
          setState(() { _clockFormat = v; _clockStr = _fmtClock(); });
          _scheduleSavePrefs();
        },
        showBatteryInTitle: _showBatteryInTitle,
        onBatteryToggle: (v) { setState(() => _showBatteryInTitle = v); _scheduleSavePrefs(); },
        batteryChargeAnim: _batteryChargeAnim,
        onBatteryAnimToggle: (v) { setState(() => _batteryChargeAnim = v); _scheduleSavePrefs(); },
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

    // ── LIVE-P7-A: Live quality selector helpers ────────────────────────────

    // Fetches the master playlist for the current live channel and populates
    // _liveRenditions. Called fire-and-forget after every live open.
    // Resets _selectedRenditionIdx to -1 (Auto) on each new channel load.
    Future<void> _fetchLiveRenditions() async {
      final masterUrl = widget.streamUrl;
      if (masterUrl == null || !_isLive) return;
      if (_liveRenditionsFetching) return;
      if (mounted) setState(() { _liveRenditionsFetching = true; });
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        final req = await client.getUrl(Uri.parse(masterUrl));
        req.headers.set('User-Agent', 'RaddFlix/3.0');
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        client.close();
        if (res.statusCode != 200) {
          if (mounted) setState(() { _liveRenditions = []; _liveRenditionsFetching = false; });
          return;
        }
        final renditions = _parseLiveRenditions(masterUrl, body);
        if (mounted) setState(() {
          _liveRenditions = renditions;
          _selectedRenditionIdx = -1; // reset to Auto on new channel
          _liveRenditionsFetching = false;
        });
      } catch (_) {
        if (mounted) setState(() { _liveRenditions = []; _liveRenditionsFetching = false; });
      }
    }

    // Parses #EXT-X-STREAM-INF blocks from [body], resolves relative URLs
    // against [masterUrl], and returns renditions sorted highest-bandwidth first.
    List<_LiveRendition> _parseLiveRenditions(String masterUrl, String body) {
      final baseUri = Uri.parse(masterUrl);
      final basePath = baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
      final base = baseUri.replace(path: basePath, query: null, fragment: null);

      final lines = body.split('\n');
      final result = <_LiveRendition>[];
      for (int i = 0; i < lines.length - 1; i++) {
        final inf = lines[i].trim();
        if (!inf.startsWith('#EXT-X-STREAM-INF:')) continue;
        final urlLine = lines[i + 1].trim();
        if (urlLine.isEmpty || urlLine.startsWith('#')) continue;

        int bw = 0;
        final bwM = RegExp(r'BANDWIDTH=(\d+)').firstMatch(inf);
        if (bwM != null) bw = int.tryParse(bwM.group(1)!) ?? 0;

        String res = _fmtBandwidth(bw);
        final resM = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(inf);
        if (resM != null) {
          final h = int.tryParse(resM.group(1)!) ?? 0;
          res = h >= 1080 ? '1080p' : h >= 720 ? '720p' : h >= 480 ? '480p' : h >= 360 ? '360p' : '${h}p';
        }

        final resolved = urlLine.startsWith('http')
            ? urlLine
            : base.resolve(urlLine).toString();

        result.add(_LiveRendition(bandwidth: bw, resolution: res, url: resolved));
      }
      result.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      return result;
    }

    // Re-fetches the master for a fresh nimblesessionid, then opens the
    // rendition at [index] (-1 = Auto ABR = re-open the master itself).
    Future<void> _switchLiveRendition(int index) async {
      final masterUrl = widget.streamUrl;
      if (masterUrl == null) return;

      if (index == -1) {
        // Auto — open master directly; media_kit/mpv handles ABR
        if (mounted) setState(() => _selectedRenditionIdx = -1);
        await _player.open(Media(masterUrl));
        return;
      }

      // Re-fetch master to get a fresh nimblesessionid for the chosen rendition
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        final req = await client.getUrl(Uri.parse(masterUrl));
        req.headers.set('User-Agent', 'RaddFlix/3.0');
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        client.close();
        if (res.statusCode != 200) {
          _showInfoSnackbar('Could not fetch stream — try again.');
          return;
        }
        final fresh = _parseLiveRenditions(masterUrl, body);
        if (index >= fresh.length) {
          _showInfoSnackbar('Quality not available for this channel.');
          return;
        }
        if (mounted) setState(() {
          _liveRenditions = fresh;
          _selectedRenditionIdx = index;
        });
        await _player.open(Media(fresh[index].url));
      } catch (_) {
        _showInfoSnackbar('Could not switch quality — check your connection.');
      }
    }

    // Opens the quality picker sheet (shown when _liveRenditions.length > 1).
    void _openLiveQualitySheet() {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36, height: 3,
                    decoration: BoxDecoration(
                        color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text(
                      'Select Quality',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    height: 0.5,
                    color: const Color(0x1AFFFFFF),
                    margin: const EdgeInsets.only(bottom: 4),
                  ),
                  // Auto option
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white54, size: 20),
                    title: const Text('Auto (ABR)',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Adjusts to your connection',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: _selectedRenditionIdx == -1
                        ? Icon(Icons.check_rounded, color: _accentColor, size: 18)
                        : null,
                    dense: true,
                    onTap: () { Navigator.of(context).pop(); _switchLiveRendition(-1); },
                  ),
                  // Rendition rows
                  for (int i = 0; i < _liveRenditions.length; i++) ...[
                    Container(height: 0.5, color: const Color(0x1AFFFFFF),
                        margin: const EdgeInsets.only(left: 56)),
                    ListTile(
                      leading: const Icon(Icons.hd_rounded,
                          color: Colors.white54, size: 20),
                      title: Text(_liveRenditions[i].resolution,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(_fmtBandwidth(_liveRenditions[i].bandwidth),
                          style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: _selectedRenditionIdx == i
                          ? Icon(Icons.check_rounded, color: _accentColor, size: 18)
                          : null,
                      dense: true,
                      onTap: () { Navigator.of(context).pop(); _switchLiveRendition(i); },
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      );
    }

    String _fmtBandwidth(int bps) {
      if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
      if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} Kbps';
      return '$bps bps';
    }

    // ── LIVE-P7-B: Slim settings panel for live TV ─────────────────────────
    // Shows only live-relevant options: Quality (informational), Audio track
    // (if multi-track), and Sleep Timer. Replaces the full VOD _openSettingsPanel
    // for any settings icon tapped during live playback.
    void _openLiveSettingsPanel() {
      final hasMultiAudio = _realAudioTracks.length > 1;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36, height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Sheet title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_rounded, color: Colors.white54, size: 17),
                        const SizedBox(width: 8),
                        Text(
                          'Channel Settings',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 0.5,
                    color: const Color(0x1AFFFFFF),
                    margin: const EdgeInsets.only(bottom: 4),
                  ),

                  // ── Quality ── real picker when renditions available, else informational
                  if (_liveRenditions.length > 1)
                    ListTile(
                      leading: const Icon(Icons.high_quality_rounded,
                          color: Colors.white54, size: 22),
                      title: const Text('Quality',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        _selectedRenditionIdx >= 0 && _selectedRenditionIdx < _liveRenditions.length
                            ? _liveRenditions[_selectedRenditionIdx].resolution
                            : 'Auto (ABR)',
                        style: TextStyle(
                          color: _selectedRenditionIdx >= 0 ? _accentColor : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: Colors.white38, size: 18),
                      dense: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        _openLiveQualitySheet();
                      },
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.high_quality_rounded,
                          color: Colors.white54, size: 22),
                      title: const Text('Quality',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Auto (ABR)',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: const Icon(Icons.info_outline_rounded,
                          color: Colors.white24, size: 16),
                      dense: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        _showInfoSnackbar(
                            'Quality adjusts automatically based on your connection.');
                      },
                    ),

                  // ── Audio track ── only if stream has multiple tracks
                  if (hasMultiAudio)
                    ListTile(
                      leading: const Icon(Icons.headphones_rounded,
                          color: Colors.white54, size: 22),
                      title: const Text('Audio Track',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        _selectedAudio?.title?.isNotEmpty == true
                            ? _selectedAudio!.title!
                            : _selectedAudio?.language?.isNotEmpty == true
                                ? _selectedAudio!.language!
                                : 'Default',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: Colors.white38, size: 18),
                      dense: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        _openAudioPanel();
                      },
                    ),

                  // ── Sleep timer ──
                  StatefulBuilder(
                    builder: (ctx, localSet) => ListTile(
                      leading: const Icon(Icons.bedtime_rounded,
                          color: Colors.white54, size: 22),
                      title: const Text('Sleep Timer',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        _sleepTimerEnd != null
                            ? '⏱ ${_fmtSleepRemaining()} remaining'
                            : 'Off',
                        style: TextStyle(
                          color: _sleepTimerEnd != null
                              ? _accentColor
                              : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: _sleepTimerEnd != null
                          ? GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                _setSleepTimer(null);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3),
                                      width: 0.8),
                                ),
                                child: const Text('Cancel',
                                    style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 11)),
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded,
                              color: Colors.white38, size: 18),
                      dense: true,
                      onTap: _sleepTimerEnd != null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              _showLiveSleepTimerSheet();
                            },
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      );
    }

    void _showLiveSleepTimerSheet() {
      const options = [15, 30, 60, 90];
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36, height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    'Sleep Timer',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  height: 0.5,
                  color: const Color(0x1AFFFFFF),
                  margin: const EdgeInsets.only(bottom: 4),
                ),
                for (final mins in options)
                  ListTile(
                    leading: const Icon(Icons.bedtime_outlined,
                        color: Colors.white54, size: 20),
                    title: Text('$mins minutes',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    dense: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      _setSleepTimer(mins);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    }

  void _enterPiP() {
    // On Android, trigger PiP mode via platform channel
    const MethodChannel('com.raddflix.app/pip')
        .invokeMethod('enterPiP')
        .catchError((_) {
      _showInfoSnackbar('Picture-in-Picture not supported on this device.');
    });
  }

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

    String _formatDuration(Duration d) {
      if (d.isNegative) d = Duration.zero;
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Live channel switcher bottom sheet
//  Shown when the user taps the ≡ button during live playback.
//  Tapping a channel invokes pushReplacementNamed so the player route is
//  recycled cleanly (no stacked live sessions in the navigation history).
// ═════════════════════════════════════════════════════════════════════════════

class _LiveChannelSwitcherSheet extends StatefulWidget {
  final List<LiveChannel> channels;
  final String            currentTitle;
  final void Function(LiveChannel) onSelect;

  const _LiveChannelSwitcherSheet({
    required this.channels,
    required this.currentTitle,
    required this.onSelect,
  });

  @override
  State<_LiveChannelSwitcherSheet> createState() => _LiveChannelSwitcherSheetState();
}

class _LiveChannelSwitcherSheetState extends State<_LiveChannelSwitcherSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<LiveChannel> get _filtered {
    if (_query.isEmpty) return widget.channels;
    final q = _query.toLowerCase();
    return widget.channels
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.genre.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.live_tv_rounded, size: 18, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text('Switch Channel', style: TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded, size: 20, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.search_rounded, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                        decoration: const InputDecoration(
                          hintText: 'Search channels…',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white10, height: 1),
            // Channel list
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No channels found',
                          style: TextStyle(color: Colors.white38, fontSize: 14)),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final ch         = filtered[i];
                        final isCurrent  = ch.name == widget.currentTitle;
                        final bgColor    = _parseHexColor(ch.backdropColor);
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 2),
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: bgColor.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: bgColor.withOpacity(0.45)),
                            ),
                            child: ch.logoUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.network(
                                      ch.logoUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Icon(
                                          Icons.live_tv_rounded,
                                          size: 20,
                                          color: Colors.white38),
                                    ),
                                  )
                                : const Icon(Icons.live_tv_rounded,
                                    size: 20, color: Colors.white38),
                          ),
                          title: Text(
                            ch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? Colors.red : Colors.white,
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            ch.genre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                          trailing: isCurrent
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.circle, size: 8, color: Colors.red),
                                    SizedBox(width: 4),
                                    Text('LIVE', style: TextStyle(
                                      color: Colors.red, fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    )),
                                  ],
                                )
                              : null,
                          onTap: isCurrent ? null : () => widget.onSelect(ch),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseHexColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    return const Color(0xFF1A1A2E);
  }
}

// ── LIVE-P7-A: Live rendition model ──────────────────────────────────────────
// Represents one #EXT-X-STREAM-INF entry from a master HLS playlist.
// [url] is already fully resolved (absolute). [bandwidth] is in bps.
// [resolution] is a human label like "1080p", "720p", etc.
class _LiveRendition {
  final int bandwidth;
  final String resolution;
  final String url; // absolute, with fresh nimblesessionid
  const _LiveRendition({
    required this.bandwidth,
    required this.resolution,
    required this.url,
  });
}
