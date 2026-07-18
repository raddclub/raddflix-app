// playback_service.dart — UX3-10: true background miniplayer
//
// Global, screen-independent home for an in-progress playback session.
//
// Historically every `Player`/`VideoController` pair was created AND owned
// by `_PlayerScreenState` — the instant that screen popped, `dispose()`
// tore the player down. That's why the old `MiniPlayerBar` could only ever
// show a static "resume from here" card read out of SharedPreferences: there
// was no live player left to talk to once the user navigated away.
//
// This service is the fix: when the user taps "minimize" in the fullscreen
// player, PlayerScreen hands its live `Player`/`VideoController` off here
// instead of disposing them, then pops itself. Playback keeps running.
// `MiniPlayerBar` renders real play/pause + live progress against this
// service, and tapping it re-opens `PlayerScreen` with `attachExisting: true`
// so the screen reattaches to the same session instead of starting a new one.
//
// Only one minimized session exists at a time — starting a new title while
// one is minimized disposes the old session first, mirroring the
// single-`Player`-instance assumption the rest of the player already makes.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/usage_service.dart';

// Same native bridge PlayerScreen already talks to for its "MX Player-style"
// background audio (Kotlin PlaybackService + MediaSession, see
// android/.../PlaybackService.kt + MainActivity.kt). PlayerScreen only owns
// this channel while it's mounted — once a session is minimized, PlayerScreen
// is gone, so *this* service has to keep the notification alive if the user
// then backgrounds the whole app (locks the phone, switches apps, etc.).
const MethodChannel _pipChannel = MethodChannel('com.raddflix.app/pip');

class PlaybackService extends ChangeNotifier with WidgetsBindingObserver {
  PlaybackService() {
    WidgetsBinding.instance.addObserver(this);
  }

  // Whether the user has "Continue audio in background" enabled (Settings →
  // Controls). Captured at minimize time from PlayerScreen's own _backgroundAudio
  // pref — this service has no UI of its own to toggle it from.
  bool backgroundAudioEnabled = false;
  bool _bgServiceRunning = false;
  Timer? _bgNotifTimer;
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription> _subs = [];

  // ── Session metadata — mirrors the route-arg shape PlayerScreen already
  // expects (see AppRoutes.player in app.dart), so reopening from the mini
  // bar is just "the same push, plus attach_existing: true".
  String? fileId;
  String? title;
  String? posterUrl;
  String? localPath;
  String? streamUrl;
  String? subtitlePath;
  String contentType = 'movie';
  bool isFree = false;
  int episodeIndex = 0;
  List<Map<String, dynamic>>? episodes;

  // ── Usage-tracking / resume-position bug fixes (post-UX3-10 review) ─────
  // PlayerScreen used to own a 30s usage heartbeat + 10s position-save timer,
  // and both got cancelled unconditionally in dispose() — including on the
  // "minimize" path, even though the player kept running here. That meant a
  // minimized paid stream stopped being billed/tracked, and its resume
  // position froze at whatever it was when the user minimized. This service
  // now runs the equivalent timers itself for as long as a session lives here.
  bool trackUsage = false; // captured from PlayerScreen's _trackUsage at adopt time
  String? posKey; // same key PlayerScreen's own _saveWatchPos() uses (wp_<fileId>)
  Timer? _usageTimer;
  Timer? _posSaveTimer;

  // ── Live state, mirrored from the player's own streams ──────────────────
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool buffering = false;

  Player? get player => _player;
  VideoController? get videoController => _videoController;
  bool get hasSession => _player != null;
  bool sessionMatches(String id) => hasSession && fileId == id && id.isNotEmpty;

  int _lastNotifyMs = 0;
  void _throttledNotify() {
    // Position ticks arrive multiple times/sec — cap mini-bar rebuilds to
    // ~2.5×/sec, same throttle PlayerScreen itself applies to its seek bar.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyMs >= 400) {
      _lastNotifyMs = now;
      notifyListeners();
    }
  }

  /// Called by PlayerScreen's minimize control. Takes ownership of the live
  /// player instead of letting PlayerScreen.dispose() tear it down.
  void adopt({
    required Player player,
    required VideoController videoController,
    required String fileId,
    required String title,
    String? posterUrl,
    String? localPath,
    String? streamUrl,
    String? subtitlePath,
    String contentType = 'movie',
    bool isFree = false,
    int episodeIndex = 0,
    List<Map<String, dynamic>>? episodes,
    bool backgroundAudioEnabled = false,
    bool trackUsage = false,
    String? posKey,
  }) {
    this.backgroundAudioEnabled = backgroundAudioEnabled;
    if (_player != null && !identical(_player, player)) {
      _disposeCurrent();
    }
    _player = player;
    _videoController = videoController;
    this.fileId = fileId;
    this.title = title;
    this.posterUrl = posterUrl;
    this.localPath = localPath;
    this.streamUrl = streamUrl;
    this.subtitlePath = subtitlePath;
    this.contentType = contentType;
    this.isFree = isFree;
    this.episodeIndex = episodeIndex;
    this.episodes = episodes;
    this.trackUsage = trackUsage;
    this.posKey = posKey;

    playing = player.state.playing;
    position = player.state.position;
    duration = player.state.duration;
    buffering = player.state.buffering;

    _startUsageTimer();
    _startPosSaveTimer();

    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _subs.addAll([
      player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      player.stream.position.listen((v) {
        position = v;
        _throttledNotify();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      // Content finished while minimized — end the session, don't leave a
      // dead player behind the mini bar.
      player.stream.completed.listen((v) {
        if (v) stop();
      }),
    ]);
    notifyListeners();
  }

  /// Called by PlayerScreen when it reattaches to an already-minimized
  /// session (attachExisting == true) — the screen resumes full ownership
  /// of the player, so this service goes back to "no active session" until
  /// minimized again.
  void detachForReattach() {
    _stopNativeBgIfRunning();
    _stopUsageTimer();
    _stopPosSaveTimer();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player = null;
    _videoController = null;
    notifyListeners();
  }

  // ── Native background audio bridge (only while minimized) ───────────────
  // PlayerScreen already does this exact dance while it's mounted (fullscreen
  // playback backgrounded = normal MX-Player-style background audio). This
  // mirrors it for the *minimized* case: hasSession is only true here while
  // the mini bar owns the player, so this never fights with PlayerScreen's
  // own didChangeAppLifecycleState handler.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!hasSession) return;
    if (state == AppLifecycleState.paused) {
      if (!backgroundAudioEnabled) return;
      _pipChannel.setMethodCallHandler(_handleNativeCall);
      _startOrUpdateNativeBg(starting: true);
      _bgNotifTimer?.cancel();
      _bgNotifTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (hasSession) _startOrUpdateNativeBg(starting: false);
      });
    } else if (state == AppLifecycleState.resumed) {
      _bgNotifTimer?.cancel();
      _bgNotifTimer = null;
      if (_bgServiceRunning) {
        _pipChannel.invokeMethod('stopBgPlayback').catchError((_) {});
        _bgServiceRunning = false;
      }
    }
  }

  void _startOrUpdateNativeBg({required bool starting}) {
    final p = _player;
    if (p == null) return;
    _bgServiceRunning = true;
    _pipChannel.invokeMethod(starting ? 'startBgPlayback' : 'updateBgNotification', {
      'title': title ?? 'Playing…',
      'isPlaying': p.state.playing,
      'positionMs': p.state.position.inMilliseconds,
      'durationMs': p.state.duration.inMilliseconds,
      // Pass poster URL so the Kotlin service can fetch and display real
      // content artwork in the lock-screen / notification shade.
      'artworkUrl': posterUrl ?? '',
    }).catchError((_) {});
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onNotificationAction') return null;
    final p = _player;
    if (p == null) return null;
    final action = call.arguments as String? ?? '';
    if (action == 'play_pause') {
      togglePlayPause();
      Future.delayed(const Duration(milliseconds: 150), () => _startOrUpdateNativeBg(starting: false));
    } else if (action == 'seek_back') {
      final t = p.state.position - const Duration(seconds: 10);
      p.seek(t.isNegative ? Duration.zero : t);
    } else if (action == 'seek_forward') {
      p.seek(p.state.position + const Duration(seconds: 30));
    } else if (action.startsWith('seek_to:')) {
      final ms = int.tryParse(action.split(':').last) ?? -1;
      if (ms >= 0) p.seek(Duration(milliseconds: ms));
    }
    return null;
  }

  /// Stops the native foreground-service notification this service may have
  /// started while minimized. Called whenever a session stops being "just
  /// the mini bar" — reattaching to fullscreen, ending, or swapping content —
  /// so a stale notification never survives past the state it describes.
  void _stopNativeBgIfRunning() {
    _bgNotifTimer?.cancel();
    _bgNotifTimer = null;
    if (_bgServiceRunning) {
      _pipChannel.invokeMethod('stopBgPlayback').catchError((_) {});
      _bgServiceRunning = false;
    }
  }

  // ── Usage heartbeat (mirrors PlayerScreen's own 30s timer) ───────────────
  void _startUsageTimer() {
    _usageTimer?.cancel();
    if (!trackUsage) return;
    _usageTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final p = _player;
      if (p == null || !trackUsage || !playing) return;
      final w = p.state.width ?? 0;
      final quality = w >= 1920 ? '1080p' : w >= 1280 ? '720p' : w >= 854 ? '480p' : '360p';
      UsageService.addWatchSession(seconds: 30, quality: quality, fileId: fileId).ignore();
    });
  }

  void _stopUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  // ── Resume-position persistence while minimized ──────────────────────────
  // PlayerScreen's own periodic save timer dies with the screen the instant
  // it's disposed, even on the minimize path — without this, a session left
  // minimized for a while (then killed before being reopened) would resume
  // from wherever it was at the moment of minimizing, not where it actually
  // got to.
  void _startPosSaveTimer() {
    _posSaveTimer?.cancel();
    _posSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
  }

  void _stopPosSaveTimer() {
    _posSaveTimer?.cancel();
    _posSaveTimer = null;
  }

  Future<void> _savePosition() async {
    final key = posKey;
    final ms = position.inMilliseconds;
    if (key == null || key.isEmpty || ms < 5000) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, ms);
    await prefs.setString('resume_title', title ?? '');
    await prefs.setString('resume_file_id', fileId ?? '');
    await prefs.setInt('resume_pos_ms', ms);
    await prefs.setInt('resume_dur_ms', duration.inMilliseconds);
    await prefs.setString('resume_content_type', contentType);
    await prefs.setBool('resume_is_free', isFree);
    if (streamUrl != null) await prefs.setString('resume_stream_url', streamUrl!);
    if (localPath != null) await prefs.setString('resume_local_path', localPath!);
    if (posterUrl != null) await prefs.setString('resume_poster_url', posterUrl!);
  }

  void togglePlayPause() {
    final p = _player;
    if (p == null) return;
    if (p.state.playing) {
      p.pause();
    } else {
      p.play();
    }
  }

  void _disposeCurrent() {
    _stopNativeBgIfRunning();
    _stopUsageTimer();
    _stopPosSaveTimer();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _videoController = null;
  }

  /// Ends the minimized session entirely — user dismissed the mini bar, the
  /// content finished, or a different title is about to start playing.
  void stop() {
    if (_player == null) return;
    _disposeCurrent();
    fileId = null;
    title = null;
    notifyListeners();
  }

  /// Route arguments to reopen the fullscreen player against this exact
  /// session — see the `AppRoutes.player` branch of `onGenerateRoute`.
  Map<String, dynamic> buildResumeArgs() => {
        'file_id': fileId ?? '',
        'title': title ?? '',
        'local_path': localPath,
        'subtitle_path': subtitlePath,
        'episodes': episodes ?? const <Map<String, dynamic>>[],
        'episode_index': episodeIndex,
        'content_type': contentType,
        'is_free': isFree,
        'stream_url': streamUrl,
        'poster_url': posterUrl,
        'attach_existing': true,
      };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCurrent();
    super.dispose();
  }
}

final playbackServiceProvider = ChangeNotifierProvider<PlaybackService>((ref) {
  return PlaybackService();
});
