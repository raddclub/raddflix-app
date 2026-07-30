part of '../player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Phase J2 — _PlayerPlaybackMixin
//  Extracted from _PlayerScreenState (Phase J God-Class decomposition).
//  Owns: player lifecycle (init/open state), stream resolution, episode
//  navigation + near-gapless prefetch, watch-position persistence, speed,
//  mute/loop, orientation lock, sleep timer, usage tracking, auto-retry,
//  and the skip-editor runtime check.
//
//  Cross-cluster members below are declared abstract because they are
//  implemented elsewhere in _PlayerScreenState (or one of its other part
//  files) — this mixin only has access to members declared in itself or in
//  ConsumerState<PlayerScreen>. Do NOT give these bodies here.
// ═══════════════════════════════════════════════════════════════════════════
mixin _PlayerPlaybackMixin on ConsumerState<PlayerScreen> {
  // ── Cross-cluster methods (defined in _PlayerScreenState) ────────────────
  void _applySubtitleMargin({required bool controlsVisible});
  void _reapplySubtitleStyleAfterLifecycle();
  void _applyAllAf(); // defined in _PlayerAudioLabMixin; called here after tracks confirmed
  String _formatDuration(Duration d);
  void _setNativeOrientation(String mode);
  void _scheduleSavePrefs();
  void _fetchLiveRenditions(); // defined in _PlayerUIMixin (LIVE-P7-A)

  // ── Cross-cluster fields (defined in _PlayerScreenState) ─────────────────
  double get _audioSync; set _audioSync(double v);
  List<AudioTrack> get _audioTracks; set _audioTracks(List<AudioTrack> v);
  int get _autoAdvanceCountdown; set _autoAdvanceCountdown(int v);
  Timer? get _autoAdvanceTimer; set _autoAdvanceTimer(Timer? v);
  bool get _backgroundAudio;
  String get _currentAudioCodec; set _currentAudioCodec(String v);
  String? get _currentSubFile; set _currentSubFile(String? v);
  // SUB-OVERLAY-FIX: declared in _PlayerSubtitleMixin; written here in stream.subtitle.listen
  String? get _currentSubLine; set _currentSubLine(String? v);
  Timer? get _hideTimer; set _hideTimer(Timer? v);
  Timer? get _immersiveExitTimer;
  Duration? get _introEnd; set _introEnd(Duration? v);
  Duration? get _introStart; set _introStart(Duration? v);
  Duration? get _outroStart; set _outroStart(Duration? v);
  double get _pinchBaseScale; set _pinchBaseScale(double v);
  double get _pinchScale; set _pinchScale(double v);
  String? get _prefAudioLang;
  String? get _prefSubLang;
  Timer? get _savePositionTimer; set _savePositionTimer(Timer? v);
  AudioTrack? get _selectedAudio; set _selectedAudio(AudioTrack? v);
  SubtitleTrack? get _selectedSecondSub; set _selectedSecondSub(SubtitleTrack? v);
  SubtitleTrack? get _selectedSubtitle; set _selectedSubtitle(SubtitleTrack? v);
  bool get _showControls; set _showControls(bool v);
  bool get _showZoomIndicator; set _showZoomIndicator(bool v);
  bool get _silenceInPipeline;
  double get _silenceSkipThreshold;
  bool get _skipEditorEnabled;
  Timer? get _sleepTimer; set _sleepTimer(Timer? v);
  DateTime? get _sleepTimerEnd; set _sleepTimerEnd(DateTime? v);
  int? get _sleepTimerMinutes; set _sleepTimerMinutes(int? v);
  double get _subSpeed; set _subSpeed(double v);
  double get _subSync; set _subSync(double v);
  List<SubtitleTrack> get _subtitleTracks; set _subtitleTracks(List<SubtitleTrack> v);
  bool get _useSWDecoder; set _useSWDecoder(bool v);
  double get _volume;
  WatchPartyRoom? get _watchPartyRoom;

  // ── State owned by this mixin ─────────────────────────────────────────────
  late final Player _player;
  late final VideoController _videoCtrl;
  // NativePlayer getter — NEVER create a local variable named _np
  NativePlayer get _np => _player.platform as NativePlayer;
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
  // ── Speed ───────────────────────────────────────────────────────────────────
  double _speed = 1.0;
  bool _longPressFast = false;
  String _currentFramedrop = 'vo';
  bool _isLocal    = false;  // true when current media is a local file (not a stream)
  bool _isFree     = false;  // true when playing free (is_free=1) content — no quota deduction
  bool _trackUsage = false;  // true only for non-local, non-free streaming
  Timer? _usageTimer;        // 30-second heartbeat to log streamed bytes
  // ── DA-2: per-session watch integrity + SMC tracking ─────────────────────
  DateTime? _smcSessionStart;        // wall clock when first play tick occurred
  int _realPlaySecs = 0;             // accumulated real playtime this session
  int _smcEstimatedBytes = 0;        // estimated bytes accumulated this session
  double _maxSeekJumpFraction = 0.0; // largest single forward seek / duration
  bool _abuseHighSpeedUsed = false;  // true if speed ≥ 4× was used this session
  static const _kResumePrefix = 'resume_pos_';
  // ── UX3-10: true background miniplayer ───────────────────────────────────
  // Set by _minimizePlayer() right before popping the screen. Tells
  // dispose() to leave the live Player alone — PlaybackService now owns it.
  bool _handedOffToService = false;
  // Loop / shuffle
  bool _loopEnabled = false;
  bool _shuffleEnabled = false;
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
  // ── Subscriptions ───────────────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];
  // ── Orientation ─────────────────────────────────────────────────────────────
  // 0=Auto 1=ForceLandscape 2=ForcePortrait 3=ForceLandscapeReverse
  int _orientMode = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;

  /// True when the current media has no video track — audio-only mode.
  ///
  /// Two-pass detection:
  ///   1. File extension (fast, decided at open time — covers local files).
  ///   2. MPV dimension stream (catches streams and files without extensions):
  ///      width and height stay 0 after the file opens → no video track.
  bool get _isAudioOnly {
    final path = widget.localPath ?? '';
    if (path.isNotEmpty) {
      final ext = path.split('.').last.toLowerCase();
      if (const {
        'mp3', 'flac', 'aac', 'ogg', 'opus', 'm4a', 'wav',
        'wma', 'ape', 'alac', 'mka', 'aiff', 'aif', 'dsd', 'dsf',
      }.contains(ext)) return true;
    }
    // MPV fallback: file is open, playing has a duration, but no video dims.
    return _videoOpened &&
        _videoWidth == 0 &&
        _videoHeight == 0 &&
        _duration > Duration.zero;
  }
  // ── Watch position ──────────────────────────────────────────────────────────
  Timer? _posTimer;
  // BB1 — non-blocking resume strip (replaces blocking AlertDialog)
  OverlayEntry? _resumeStripEntry;
  Timer?        _resumeStripTimer;
  // ── P3: Auto-retry countdown ─────────────────────────────────────────────────
  Timer? _autoRetryTimer;
  Timer? _savePrefsDebounce; // C2: debounce SharedPreferences writes off the main thread hot path
  int _autoRetryCountdown = 0;
  // ── Perf: throttle position setState to max 2×/sec ──────────────────
  int _lastPositionMs = -1;

  // ── Computed getters ───────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  //  Episode navigation
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get _eps => widget.episodes ?? [];
  bool get _hasPrev => _currentEpIdx > 0;
  bool get _hasNext => _currentEpIdx < _eps.length - 1;
  // ═══════════════════════════════════════════════════════════════════════════
  //  Watch position
  // ═══════════════════════════════════════════════════════════════════════════

  String get _posKey {
    if (_currentFileId.isNotEmpty) return 'wp_$_currentFileId';
    final ep = _eps.isNotEmpty ? _eps[_currentEpIdx] : null;
    final lp = ep?['local_path'] as String? ?? widget.localPath ?? '';
    return 'wp_local_${lp.hashCode}';
  }

  // ── Methods ─────────────────────────────────────────────────────────────
  void _startUsageTimer() {
    _usageTimer?.cancel();
    _smcSessionStart ??= DateTime.now(); // DA-2: wall clock starts on first play tick per session
    _usageTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_trackUsage && _playing && mounted) {
        // Estimate quality from video width (1920→1080p, 1280→720p, 854→480p, else→360p)
        final w = _player.state.width ?? 0;
        final quality = w >= 1920 ? '1080p' : w >= 1280 ? '720p' : w >= 854 ? '480p' : '360p';
        UsageService.addWatchSession(seconds: 30, quality: quality).ignore();
        // DA-2: accumulate real playtime + byte estimate for SMC and completion guard
        _realPlaySecs += 30;
        const bps = {'1080p': 2200000, '720p': 1100000, '480p': 600000, '360p': 300000};
        _smcEstimatedBytes += (30 * (bps[quality] ?? bps['720p']!)) ~/ 8;
      }
    });
  }

  void _stopUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  // ── DA-2: Watch Integrity & SMC helpers ──────────────────────────────────

  /// Title ID used for SMC cooldown keying.
  /// Series: reads title_id from episode map. Movies: parses fileId as int or hashes it.
  int get _smcTitleId {
    if (_eps.isNotEmpty) {
      return _eps[_currentEpIdx]['title_id'] as int? ?? 0;
    }
    return int.tryParse(_currentFileId) ?? _currentFileId.hashCode.abs();
  }

  /// Resets per-session DA-2 tracking state. Call at the start of each new media open.
  void _resetSmcTracking() {
    _smcSessionStart = null;
    _realPlaySecs = 0;
    _smcEstimatedBytes = 0;
    _maxSeekJumpFraction = 0.0;
    _abuseHighSpeedUsed = false;
  }

  /// True when completion credit should be awarded.
  /// Fails if real playtime < 70 % of total, or if both abuse signals fire.
  bool _isCompletionEarned() {
    final totalSecs = _duration.inSeconds;
    if (totalSecs <= 0) return true; // unknown duration — give benefit of doubt
    if (_abuseHighSpeedUsed &&
        _maxSeekJumpFraction >= UsageService.abuseSeekThreshold) {
      return false; // seek + fast-forward abuse → deny
    }
    return _realPlaySecs >= (totalSecs * UsageService.completionThreshold).round();
  }

  /// Applies SMC charge if wall-clock session ≥ 20 s and content is paid.
  /// Always fire-and-forget: call with `.ignore()` from synchronous code.
  Future<void> _applySmcOnSessionEnd() async {
    if (!_trackUsage) return;
    final start = _smcSessionStart;
    if (start == null) return;
    final wallSecs = DateTime.now().difference(start).inSeconds;
    if (wallSecs < UsageService.smcMinSessionSecs) return;
    final w = _player.state.width;
    final quality = (w != null && w >= 1920)
        ? '1080p'
        : (w != null && w >= 1280)
            ? '720p'
            : (w != null && w >= 854)
                ? '480p'
                : '360p';
    await UsageService.applySmcIfNeeded(
      titleId: _smcTitleId,
      quality: quality,
      actualBytes: _smcEstimatedBytes,
    );
  }

  // BGAUDIO-SESSION: request Android audio focus so the system keeps our audio
  // pipeline alive when the app moves to the background.  `audio_session` is
  // already in pubspec (^0.1.21) but was never wired up.  Called fire-and-forget
  // from _initPlayer() on both the fresh-create and reattach paths.
  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.moviePlayback,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.longFormVideo,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.movie,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
  }

  void _initPlayer() {
    // Request audio focus on every init (both fresh-create and reattach).
    _configureAudioSession().ignore();
    // UX3-10: if a minimized session for this exact title is still alive in
    // PlaybackService, reattach to it instead of creating a brand-new
    // Player — that's what makes "tap the mini bar → back to fullscreen,
    // no reload" possible.
    final playbackService = ref.read(playbackServiceProvider);
    if (widget.attachExisting && playbackService.sessionMatches(widget.fileId)) {
      _player = playbackService.player!;
      _videoCtrl = playbackService.videoController!;
      _videoOpened = true;
      final st = _player.state;
      _playing = st.playing;
      _position = st.position;
      _duration = st.duration;
      _buffering = st.buffering;
      _audioTracks = st.tracks.audio;
      _subtitleTracks = st.tracks.subtitle;
      _selectedAudio = st.track.audio;
      _selectedSubtitle = st.track.subtitle;
      _isLocal = (widget.localPath != null && widget.localPath!.isNotEmpty);
      _isFree = widget.isFree;
      _trackUsage = !_isFree && !_isLocal;
      playbackService.detachForReattach();
      _wirePlayerStreams();
      _wireSilenceSkipObserver();
      if (_trackUsage) _startUsageTimer();
      // DA-2-FIX-3: seed real-play counter from the current position so the
      // completion guard doesn't wrongly deny credit for playtime that occurred
      // while the session was minimized in PlaybackService.
      _realPlaySecs = _position.inSeconds;
      _posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());
      return;
    }
    // Starting different content while a session is minimized — only one
    // video plays at a time, so the old one must end first.
    if (playbackService.hasSession) {
      playbackService.stop();
    }

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

    _wirePlayerStreams();

    _posTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveWatchPos());

    _wireSilenceSkipObserver();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openMedia(_currentFileId, localPath: widget.localPath);
    });
  }

  /// Hands the live player + current session metadata off to
  /// [PlaybackService] instead of letting the normal `dispose()` path tear
  /// it down, then pops the fullscreen UI. Playback keeps running —
  /// [MiniPlayerBar] takes over as the visible, live control surface.
  void _minimizePlayer() {
    final playbackService = ref.read(playbackServiceProvider);
    playbackService.adopt(
      player: _player,
      videoController: _videoCtrl,
      fileId: _currentFileId,
      title: _currentTitle,
      posterUrl: widget.posterUrl,
      localPath: widget.localPath,
      streamUrl: widget.streamUrl,
      subtitlePath: _currentSubFile,
      contentType: widget.contentType,
      isFree: _isFree,
      episodeIndex: _currentEpIdx,
      episodes: widget.episodes,
      backgroundAudioEnabled: _backgroundAudio,
      // Bug fix: usage billing + resume-position saving used to stop the
      // instant this screen disposed, even though playback kept running via
      // PlaybackService. The service now runs its own equivalent timers, so
      // hand off what it needs to keep them going for this session.
      trackUsage: _trackUsage,
      posKey: _posKey,
    );
    _handedOffToService = true;
    Navigator.of(context).pop();
  }

  /// Wires up every `_player.stream.*` listener the screen depends on
  /// (playback state, tracks, near-gapless prefetch, codec auto-fallback,
  /// auto-orientation, …). Extracted out of `_initPlayer()` so the
  /// reattach-to-an-existing-session path (see above) can reuse it against
  /// a Player it didn't create itself.
  void _wirePlayerStreams() {
    _subs.addAll([
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
        // K1: save position immediately on pause so a force-kill never loses more than the
        // current second. The 10-second timer covers the playing case; this covers the rest.
        if (!v) _saveWatchPos();
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
        // DA-2: detect large forward seek jumps for abuse detection.
        // At this point _position is still the previous value; v is the new one.
        if (_duration.inMilliseconds > 0) {
          final jumpMs = v.inMilliseconds - _position.inMilliseconds;
          if (jumpMs > 5000) { // > 5 s forward delta = likely a seek, not playback
            final frac = jumpMs / _duration.inMilliseconds;
            if (frac > _maxSeekJumpFraction) _maxSeekJumpFraction = frac;
          }
        }
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
        // Re-apply saved language preferences on every new file load.
        // Uses microtask so MPV's own auto-selection settles first, then we
        // override only when a matching language track is found.
        Future.microtask(() {
          if (!mounted) return;
          if (_prefSubLang != null) {
            final t = tracks.subtitle.where((s) =>
                s.language == _prefSubLang &&
                s.id != null && s.id != 'no').firstOrNull;
            if (t != null) {
              _player.setSubtitleTrack(t);
              if (mounted) setState(() => _selectedSubtitle = t);
            }
          }
          if (_prefAudioLang != null) {
            final t = tracks.audio.where((a) =>
                a.language == _prefAudioLang &&
                a.id != null && a.id != 'auto').firstOrNull;
            if (t != null) {
              _player.setAudioTrack(t);
              if (mounted) setState(() => _selectedAudio = t);
            }
          }
          // Track discovery/selection can recreate MPV's subtitle renderer,
          // which otherwise restores the embedded track's default styling.
          _reapplySubtitleStyleAfterLifecycle();
          // AUDIO-FIX-2: apply the AF chain (EQ + Lab + reverb + balance) now
          // that MPV has confirmed audio tracks exist. A short delay lets the
          // audio decoder fully initialise before we set the filter graph —
          // MPV accepts setProperty('af') at any time, but the filter-graph
          // init itself happens asynchronously; firing this too early (as a
          // 500ms blind timer from prefs-load time) caused silent discard on
          // slow devices where media hadn't opened yet.
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _applyAllAf();
          });
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
                // Safety rule (MediaTek/Infinix black-screen): hwdec must never
                // change while frames are actively being decoded/rendered. This
                // auto-fallback used to set the property unconditionally, which
                // is exactly the case that rule exists to prevent — on affected
                // chipsets it could silently break audio/video for files that
                // need this switch (EAC3/DTS/TrueHD), which is the intermittent
                // "some videos have no audio" symptom. Pause across the property
                // change, mirroring the manual toggle's guard.
                final wasPlaying = _playing;
                if (wasPlaying) { try { await _player.pause(); } catch (_) {} }
                try { _np.setProperty('hwdec', 'no'); } catch (_) {}
                if (mounted) setState(() => _useSWDecoder = true);
                if (wasPlaying) { try { await _player.play(); } catch (_) {} }
                final name = {
                  'eac3': 'E-AC-3 (Dolby Digital+)', 'ac3': 'AC-3 (Dolby Digital)',
                  'dts': 'DTS', 'dca': 'DTS-HD', 'truehd': 'Dolby TrueHD', 'mlp': 'MLP/TrueHD',
                }[detected] ?? detected.toUpperCase();
                _showInfoSnackbar('$name — using software decoder for full fidelity');
                // Re-apply AF chain after hwdec switch — changing hwdec while
                // playing can reset MPV's audio pipeline, discarding any
                // previously applied filter graph.
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) _applyAllAf();
                });
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
      // SUB-OVERLAY-FIX: feed current subtitle text into _currentSubLine so
      // SubtitleOverlay can render it as a Flutter widget.  media_kit emits
      // List<String> where index 0 is the primary track line; an empty list
      // or an empty string means no subtitle is active at this timestamp.
      _player.stream.subtitle.listen((lines) {
        if (!mounted) return;
        final raw = lines.isNotEmpty ? lines.first : null;
        final line = (raw != null && raw.isNotEmpty) ? raw : null;
        setState(() => _currentSubLine = line);
      }),
    ]);
  }

  /// Subscribes to MPV's log-message property for silencedetect events.
  /// Extracted out of `_initPlayer()` so both the fresh-create path and the
  /// reattach-to-an-existing-session path register their own copy — the
  /// old widget instance's copy was already unregistered in dispose().
  void _wireSilenceSkipObserver() {
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
  }

  Future<void> _openMedia(String fileId, {String? localPath}) async {
    _currentFileId = fileId.isNotEmpty ? fileId : _currentFileId;

    final isLocal = (localPath != null && localPath.isNotEmpty) ||
        (fileId.startsWith('/') || fileId.startsWith('content://'));
    _isLocal = isLocal;

    // ── Live TV early-exit — bypass JazzDrive entirely ────────────────────────
    // Live streams are direct HLS CDN URLs (tamashaweb), NOT JazzDrive share
    // links. Routing them through JazzDriveService causes _extractShareKey() to
    // throw (no /f/ pattern in CDN path), and _friendlyError() then matches
    // 'Jazz' in the exception string → false "Jazz SIM required" message while
    // the stream was never even attempted. LIVE-P0-A fix.
    if (widget.contentType == 'live') {
      final url = widget.streamUrl;
      if (url == null || url.isEmpty) {
        if (mounted) setState(() { _streamError = 'No stream URL for this channel.'; _isLinkLoading = false; });
        return;
      }
      if (mounted) setState(() { _streamError = null; _isLinkLoading = false; _ended = false; });
      _videoOpened = true;
      await _player.open(Media(url));
      _scheduleHide();
      _fetchLiveRenditions(); // LIVE-P7-A: populate quality picker (fire-and-forget)
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    // ── Network stream early-exit — direct URL, no JazzDrive (NET-STREAM-1) ──
    // Plays any direct http/https URL (m3u8, mp4, mkv, etc.) without going
    // through JazzDrive resolution, quota tracking, or subscription gates.
    // Called by: share-sheet intent (ACTION_SEND text/plain) and the
    // "Play from URL" row in LocalMediaScreen.
    if (widget.contentType == 'network') {
      final url = widget.streamUrl;
      if (url == null || url.isEmpty) {
        if (mounted) setState(() { _streamError = 'No stream URL provided.'; _isLinkLoading = false; });
        return;
      }
      if (mounted) setState(() { _streamError = null; _isLinkLoading = false; _ended = false; });
      _videoOpened = true;
      await _player.open(Media(url));
      _scheduleHide();
      _fetchLiveRenditions(); // picks up HLS renditions when URL is an m3u8 master
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

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
        // First open — trust the typed constructor arg the caller passed in
        // (G1: previously re-read from ModalRoute.of(context)?.settings.arguments,
        // see BUG-FREE-PLAY-01).
        _isFree     = widget.isFree;
        _trackUsage = !_isFree;
      }
      // else: retry or re-open — keep _isFree/_trackUsage as already set
    } else {
      _isFree     = false;
      _trackUsage = false;
    }
    _applySmcOnSessionEnd().ignore(); // DA-2: charge SMC for any prior session
    _stopUsageTimer(); // cancel any leftover timer from previous file
    _resetSmcTracking(); // DA-2: fresh session state for this media

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

    final inlineShareUrl = widget.streamUrl;

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
    // LIVE-P0-B: live-specific messages before generic VOD checks so the CDN's
    // real 403/401 is surfaced correctly instead of matching 'Jazz' in the
    // JazzDrive exception string (which was the false-positive path).
    if (widget.contentType == 'live') {
      if (raw.contains('403') || raw.contains('Forbidden') || raw.contains('401')) {
        return 'Jazz SIM required. Connect to Jazz mobile data to watch live TV.';
      }
      return 'Could not load channel. Check your connection and retry.';
    }
    // NET-STREAM-1: network URLs — no Jazz SIM context; give URL-specific hints.
    if (widget.contentType == 'network') {
      if (raw.contains('403') || raw.contains('Forbidden')) return 'Access denied. The stream URL may require authentication.';
      if (raw.contains('404') || raw.contains('Not Found')) return 'Stream not found. Check the URL and try again.';
      if (raw.contains('timeout') || raw.contains('SocketException')) return 'Connection timed out. Check your internet connection.';
      return 'Could not play this URL. Make sure it is a valid direct stream link.';
    }
    if (raw.contains('Jazz') || raw.contains('SIM') || raw.contains('401')) {
      return 'Jazz SIM required to stream. Connect to Jazz mobile data.';
    }
    if (raw.contains('timeout') || raw.contains('SocketException')) {
      return 'Connection timed out. Check your internet connection.';
    }
    return 'Could not load stream. Please retry.';
  }

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
      // BUG-SUB-CARRY-01 / BUG-AUDIO-CARRY-01: a manually-picked track ID
      // (e.g. sid=3, aid=2) is an MPV *property*, not per-file state — it
      // survives a loadfile/open of the next episode and gets blindly
      // re-applied to that file's track list, which can pick the wrong (or a
      // nonexistent) track. Reset all three Dart-side selections here; the
      // native sid/secondary-sid/aid properties are reset to auto/no just
      // below so MPV re-picks the new episode's own default tracks.
      // Language preference (_prefSubLang/_prefAudioLang) is re-applied in
      // stream.tracks.listen once the new episode's track list arrives.
      _selectedSubtitle = null;
      _selectedSecondSub = null;
      _selectedAudio = null;
      // Sync offsets are per-file — carrying over sub/audio delay from the
      // previous episode immediately desyncs the next one.
      _subSync = 0.0;
      _audioSync = 0.0;
      // Sub speed is also per-content; reset to natural rate between episodes.
      _subSpeed = 1.0;
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
    // BUG-SUB-CARRY-01 / BUG-AUDIO-CARRY-01: reset all track selections to
    // auto/no so MPV re-picks each new episode's own default tracks instead
    // of reapplying stale indices from the previous file.
    try {
      _np.setProperty('sid', 'auto');
      _np.setProperty('secondary-sid', 'no');
      _np.setProperty('aid', 'auto');
      // BUG-SUB-STYLE-01: force ASS style override on every episode reset so
      // the new episode's subtitles honor the user's saved style/position
      // from the very first frame, instead of only after the panel is
      // reopened or the controls are next toggled.
      _np.setProperty('sub-ass-override', 'force');
    } catch (_) {}
    // Reset sync offsets and sub speed in MPV — these are session-level
    // properties that survive loadfile and must be cleared explicitly.
    try {
      _np.setProperty('sub-delay', '0');
      _np.setProperty('audio-delay', '0');
      _np.setProperty('sub-speed', '1');
    } catch (_) {}
    // AUDIO-FIX-1: lavfi-complex and audio-file survive loadfile just like
    // sid/aid above. If the user activated AI Dub on any episode, these two
    // properties persist into every subsequent episode in the same session,
    // causing MPV to route audio through a dead filter graph → total silence.
    // _disableDubMode() already clears them when the user manually turns Dub
    // off, but _playEpisodeAt() skips that path on next/prev navigation.
    // Reset unconditionally here so each episode always starts clean.
    try {
      _np.setProperty('lavfi-complex', '');
      _np.setProperty('audio-file', '');
    } catch (_) {}
    _openMediaForEpisode(ep,
      localPath: (ep['local_path'] ?? ep['localPath'] ?? ep['download_path']) as String?,
      shareUrl: (ep['share_url'] ?? ep['shareUrl']) as String?,
    );
  }

  void _syncNativeAbLoop() {
    try {
      _np.setProperty('ab-loop-a', _abA != null
          ? (_abA!.inMilliseconds / 1000).toStringAsFixed(3) : 'no');
      _np.setProperty('ab-loop-b', _abB != null
          ? (_abB!.inMilliseconds / 1000).toStringAsFixed(3) : 'no');
      _np.setProperty('ab-loop-count', (_abA != null && _abB != null) ? 'inf' : '1');
    } catch (_) {}
  }

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
    _applySmcOnSessionEnd().ignore(); // DA-2: charge SMC for the episode just ended
    _stopUsageTimer(); // cancel previous episode's heartbeat before any gate check
    _resetSmcTracking(); // DA-2: fresh session state for the incoming episode

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
    // DA-2: completion guard — only clear the resume position (awarding credit)
    // if real playtime meets the threshold and no abuse signals fired.
    if (_isCompletionEarned()) {
      _clearSavedPosition(_currentFileId);
    }
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
            _playEpisodeAt(_shuffleEnabled ? _randomEpIdx() : _currentEpIdx + 1);
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
        backgroundColor: AppColors.card,
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

  Future<void> _saveWatchPos() async {
    final ms = _position.inMilliseconds;
    if (ms < 5000) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_posKey, ms);
    // ── Resume FAB data ───────────────────────────────────────────────────
    // Save enough context for ResumeFab on the home screen to reconstruct
    // the player route and show a meaningful card (title + progress).
    await prefs.setString('resume_title',        _currentTitle);
    await prefs.setString('resume_file_id',      _currentFileId);
    await prefs.setInt   ('resume_pos_ms',       ms);
    await prefs.setInt   ('resume_dur_ms',       _duration.inMilliseconds);
    await prefs.setString('resume_content_type', widget.contentType);
    // BUG-11 fix: persist is_free so ResumeFab can skip sub gate for free content.
    await prefs.setBool  ('resume_is_free',      _isFree);
    final streamUrl  = widget.streamUrl;
    final localPath  = widget.localPath;
    final posterUrl  = widget.posterUrl;
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
    if (!mounted) return;
    // BB1: auto-seek immediately — no blocking dialog.
    // A non-blocking _ResumeStrip appears above the seek bar for 4 s so the user
    // can tap Restart if they want to start over. Video is already playing.
    _player.seek(Duration(milliseconds: ms));
    if (mounted) _showResumeStrip(ms);
  }

  // BB1 — show the non-blocking resume strip via an OverlayEntry.
  void _showResumeStrip(int ms) {
    _resumeStripEntry?.remove();
    _resumeStripTimer?.cancel();
    final timeStr = _formatDuration(Duration(milliseconds: ms));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ResumeStrip(
        time: timeStr,
        onRestart: () {
          entry.remove();
          _resumeStripEntry = null;
          _resumeStripTimer?.cancel();
          _player.seek(Duration.zero);
        },
        onDismiss: () {
          entry.remove();
          _resumeStripEntry = null;
          _resumeStripTimer?.cancel();
        },
      ),
    );
    _resumeStripEntry = entry;
    Overlay.of(context).insert(entry);
    _resumeStripTimer = Timer(const Duration(seconds: 4), () {
      if (_resumeStripEntry != null) {
        _resumeStripEntry!.remove();
        _resumeStripEntry = null;
      }
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Volume X: HUD auto-hides after 3s of inactivity.
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) {
        setState(() => _showControls = false);
        _applySubtitleMargin(controlsVisible: false);
      }
    });
  }

  void _applyCompanionSub(String? subPath) {
    if (subPath != null && subPath.isNotEmpty) {
      try { _np.setProperty('sub-file', subPath); } catch (_) {}
    }
    // This is called after every VOD/media open. Reapply even when there is no
    // companion file because MPV may have just recreated its subtitle renderer
    // while opening the media itself.
    _reapplySubtitleStyleAfterLifecycle();
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
    // DA-2: flag high-speed use for abuse detection (velocity ratio ≥ 4×)
    if (speed >= UsageService.abuseVelocityRatio) _abuseHighSpeedUsed = true;
    if (mounted) setState(() => _speed = speed);
  }

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

  void _startAutoRetry() {
    _autoRetryTimer?.cancel();
    // LIVE-P0-D: live streams disconnect frequently — retry in 10s, not 30s.
    final retryDelay = (widget.contentType == 'live') ? 10 : 30;
    setState(() => _autoRetryCountdown = retryDelay);
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
    _scheduleSavePrefs();
  }

  void _toggleShuffle() {
    setState(() => _shuffleEnabled = !_shuffleEnabled);
    _scheduleSavePrefs();
  }

  /// Shared Random instance — avoids allocating a new object on every shuffle advance.
  final _rng = math.Random();

  /// Returns a random episode index different from the current one.
  int _randomEpIdx() {
    if (_eps.length <= 1) return 0;
    int next;
    do {
      next = _rng.nextInt(_eps.length);
    } while (next == _currentEpIdx);
    return next;
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

  void _notifyBgState() {
    if (!_backgroundAudio) return;
    const MethodChannel('com.raddflix.app/pip').invokeMethod('startBgPlayback', {
      'title':      widget.title,
      'isPlaying':  _player.state.playing,
      'positionMs': _position.inMilliseconds,
      'durationMs': _duration.inMilliseconds,
      // Pass poster URL so the Kotlin service can fetch and display
      // real content artwork in the lock-screen / notification shade.
      'artworkUrl': widget.posterUrl ?? '',
    }).catchError((_) {});
  }

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

  void _showInfoSnackbar(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.surfaceHigh,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BB1 — _ResumeStrip
//  Non-blocking overlay strip shown when a watch position is auto-restored.
//  Slide+fade in 180ms easeOutCubic, auto-dismissed after 4 s.
//  "Restart ↺" tap seeks back to t=0 and dismisses.
// ─────────────────────────────────────────────────────────────────────────────
class _ResumeStrip extends StatefulWidget {
  final String        time;
  final VoidCallback  onRestart;
  final VoidCallback  onDismiss;
  const _ResumeStrip({
    required this.time,
    required this.onRestart,
    required this.onDismiss,
  });
  @override State<_ResumeStrip> createState() => _ResumeStripState();
}

class _ResumeStripState extends State<_ResumeStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset>   _slide;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _slide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 90, left: 0, right: 0,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Center(
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1410),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Text('Resumed from ${widget.time}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: widget.onRestart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Restart',
                            style: TextStyle(color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        SizedBox(width: 4),
                        Icon(Icons.replay_rounded, color: Colors.white, size: 13),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
