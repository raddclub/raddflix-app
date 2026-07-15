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

    playing = player.state.playing;
    position = player.state.position;
    duration = player.state.duration;
    buffering = player.state.buffering;

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
