import 'dart:io';
  import 'package:flutter/services.dart';

  /// RaddFlix Playback Timeline — records precise startup event timestamps.
  /// Diagnoses black screen (GL surface destruction) on MediaTek/Infinix devices.
  /// Each PlayerScreen session gets a row of timestamped events; last 20 persisted.
  ///
  /// Probe points (inserted into player_screen.dart):
  ///   startSession()      → _initPlayer() entry
  ///   record()            → surface_ready, video_opened, player_open_called, prefs_loaded,
  ///                          vf_debounce_fired
  ///   recordGate()        → _applyVideoFilters startup gate result + all flag values
  ///   recordHwdecGate()   → _applyAudioPrefs hwdec gate result
  ///   recordMpvPlaying()  → _player.stream.playing callback
  ///   recordFirstFrame()  → fetchPlaybackInfo codec/res/decoder snapshot
  class PlaybackTimeline {
    static const int _maxSessions = 20;

    // ── Current session ──────────────────────────────────────────────────────
    static String _sessionId   = '';
    static String _fileId      = '';
    static int    _startMs     = 0;
    static bool   _isLocal     = false;
    static final List<PtEvent> _events = [];

    // ── Completed sessions ring-buffer ───────────────────────────────────────
    static final List<PtSession> _sessions = [];
    static String? _filePath;

    // ── Quick-access flags (checked by black screen detector) ────────────────
    static bool hadVfGatePassed  = false;
    static bool hadHwdecGatePassed = false;

    // ══════════════════════════════════════════════════════════════════════════
    // Public API
    // ══════════════════════════════════════════════════════════════════════════

    /// Call at the very start of _initPlayer(), before Player() is constructed.
    static void startSession(String fileId, {bool isLocal = false}) {
      if (_events.isNotEmpty) _commit();          // save previous session
      _sessionId        = _shortId();
      _fileId           = fileId.length > 50
          ? '…${fileId.substring(fileId.length - 50)}'
          : fileId;
      _startMs          = _now();
      _isLocal          = isLocal;
      _events.clear();
      hadVfGatePassed   = false;
      hadHwdecGatePassed = false;
      _filePath         ??= '${Directory.systemTemp.path}/raddflix_timeline.log';
      _append('[=== SESSION $_sessionId ${_wallMs(_startMs)} local=$isLocal fid=$_fileId ===]');
      _record('session_start');
    }

    /// Generic named event (surface_ready, prefs_loaded, vf_debounce_fired, etc.)
    static void record(String event, {String? extra}) => _record(event, extra: extra);

    /// Called from _applyVideoFilters startup gate — records every flag value.
    static void recordGate({
      required bool   blocked,
      required bool   videoOpened,
      required bool   mpvPlaying,
      required bool   flutterPlaying,
      required String lastVf,
      required String builtVf,
    }) {
      if (!blocked) hadVfGatePassed = true;
      final reason = blocked
          ? (videoOpened    ? 'videoOpened'
            : mpvPlaying    ? 'mpvPlaying'
            : 'flutterPlaying')
          : 'ALL_FLAGS_FALSE_⚠️';
      final lvSnip = lastVf.isEmpty ? '(empty)'
          : lastVf.length > 24 ? '${lastVf.substring(0, 24)}…' : lastVf;
      final bvSnip = builtVf.isEmpty ? '(empty)'
          : builtVf.length > 24 ? '${builtVf.substring(0, 24)}…' : builtVf;
      _record(
        blocked ? 'vf_gate_BLOCKED' : '⚠️vf_gate_PASSED',
        extra: 'reason=$reason vOpened=$videoOpened mpv=$mpvPlaying fl=$flutterPlaying '
               'lastVf="$lvSnip" builtVf="$bvSnip"',
      );
    }

    /// Called from _applyAudioPrefs hwdec guard.
    static void recordHwdecGate({
      required bool     blocked,
      required bool     videoSurfaceReady,
      required bool     mpvPlaying,
      required bool     flutterPlaying,
      required Duration duration,
      required bool     hwEnabled,
    }) {
      if (!blocked) hadHwdecGatePassed = true;
      _record(
        blocked ? 'hwdec_gate_BLOCKED' : '⚠️hwdec_gate_PASSED',
        extra: 'sfc=$videoSurfaceReady mpv=$mpvPlaying fl=$flutterPlaying '
               'dur=${duration.inMilliseconds}ms hwEn=$hwEnabled',
      );
    }

    /// Called from _player.stream.playing.listen.
    static void recordMpvPlaying(bool playing) =>
        _record('mpv_playing_${playing ? "TRUE" : "false"}');

    /// Called from fetchPlaybackInfo after codec/res/decoder are known.
    static void recordFirstFrame({
      required String codec,
      required String resolution,
      required String fps,
      required String decoder,
    }) =>
        _record('first_frame', extra: 'codec=$codec res=$resolution fps=$fps dec=$decoder');

    /// Called at T+3s if vf gate PASSED — strong signal of black screen.
    static void recordSuspectedBlackScreen({
      required bool     audioPlaying,
      required Duration position,
    }) {
      _record('⚠️BLACK_SCREEN_SUSPECTED',
          extra: 'audio=$audioPlaying pos=${position.inMilliseconds}ms '
                 'vfGatePassed=$hadVfGatePassed hwdecGatePassed=$hadHwdecGatePassed');
      _flushAppend('  *** BLACK SCREEN SUSPECTED at T+${_now() - _startMs}ms ***');
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Accessors
    // ══════════════════════════════════════════════════════════════════════════

    static List<PtSession> get sessions => List.unmodifiable(_sessions);

    static PtSession? get currentSession => _events.isEmpty ? null : PtSession(
      id: _sessionId, fileId: _fileId, startMs: _startMs,
      isLocal: _isLocal, events: List.of(_events),
    );

    /// Full formatted text of current + all past sessions — for clipboard/share.
    static String formatAll() {
      final sb = StringBuffer();
      final current = currentSession;
      if (current != null) {
        sb.writeln('── CURRENT ──────────────────────────────');
        sb.writeln(_fmt(current));
      }
      if (_sessions.isNotEmpty) {
        sb.writeln('── HISTORY (${_sessions.length} sessions) ──────────');
        for (final s in _sessions.reversed) {
          sb.writeln(_fmt(s));
          sb.writeln();
        }
      }
      return sb.toString();
    }

    static Future<void> copyToClipboard() async =>
        Clipboard.setData(ClipboardData(text: formatAll()));

    // ══════════════════════════════════════════════════════════════════════════
    // Internal
    // ══════════════════════════════════════════════════════════════════════════

    static void _record(String event, {String? extra}) {
      final rel  = _now() - _startMs;
      final prev = _events.isEmpty ? 0 : _events.last.relMs;
      final e    = PtEvent(event: event, relMs: rel, deltaMs: rel - prev, extra: extra);
      _events.add(e);
      _append('  T+${rel}ms (+${rel-prev}ms) $event${extra != null ? " | $extra" : ""}');
    }

    static void _commit() {
      final s = PtSession(
        id: _sessionId, fileId: _fileId, startMs: _startMs,
        isLocal: _isLocal, events: List.of(_events),
      );
      _sessions.add(s);
      if (_sessions.length > _maxSessions) _sessions.removeAt(0);
      _append('[--- session $_sessionId committed (${_events.length} events) ---]');
    }

    static String _fmt(PtSession s) {
      final sb = StringBuffer();
      final t  = _wallMs(s.startMs);
      sb.writeln('Session ${s.id} | $t | ${s.isLocal ? "LOCAL" : "JAZZ"} | ${s.fileId}');
      sb.writeln('  # Event                       T+ms   Δms');
      sb.writeln('  ───────────────────────────────────────────────────');
      for (int i = 0; i < s.events.length; i++) {
        final e    = s.events[i];
        final warn = e.event.contains('⚠️') || e.event.contains('PASS') ? '⚠' : ' ';
        final ok   = e.event.contains('BLOCK') ? '✓' : ' ';
        final flag = '$warn$ok';
        final nm   = e.event.length > 28 ? '${e.event.substring(0, 28)}' : e.event.padRight(28);
        sb.write('  $flag $nm  ${e.relMs.toString().padLeft(5)}  +${e.deltaMs}ms');
        if (e.extra != null) sb.write('  | ${e.extra}');
        sb.writeln();
      }
      final hasBS  = s.events.any((e) => e.event.contains('BLACK_SCREEN'));
      final hasBad = s.events.any((e) => e.event.contains('PASS'));
      if (hasBS)  sb.writeln('  *** BLACK SCREEN DETECTED in this session ***');
      if (hasBad) sb.writeln('  *** GATE PASSED — surface destruction likely ***');
      return sb.toString();
    }

    static void _append(String line) {
      if (_filePath == null) return;
      // BUG-TIMELINE-SYNC fix: async fire-and-forget — writeAsStringSync on the
      // main thread caused measurable UI jank on budget MediaTek devices during
      // player startup. Diagnostic log loss on crash is acceptable.
      File(_filePath!).writeAsString('$line\n', mode: FileMode.append).ignore();
    }

    static void _flushAppend(String line) => _append(line);

    static int  _now()       => DateTime.now().millisecondsSinceEpoch;
    static String _shortId() => (_now() % 1000000).toString().padLeft(6, '0');
    static String _wallMs(int ms) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.hour.toString().padLeft(2,"0")}:'
             '${dt.minute.toString().padLeft(2,"0")}:'
             '${dt.second.toString().padLeft(2,"0")}.'
             '${dt.millisecond.toString().padLeft(3,"0")}';
    }
  }

  /// A single timestamped event within a playback session.
  class PtEvent {
    final String  event;
    final int     relMs;    // ms since session start
    final int     deltaMs;  // ms since previous event
    final String? extra;
    const PtEvent({
      required this.event,
      required this.relMs,
      required this.deltaMs,
      this.extra,
    });
  }

  /// A complete playback session snapshot.
  class PtSession {
    final String       id;
    final String       fileId;
    final int          startMs;
    final bool         isLocal;
    final List<PtEvent> events;
    const PtSession({
      required this.id,
      required this.fileId,
      required this.startMs,
      required this.isLocal,
      required this.events,
    });
    bool get hadVfGatePassed   => events.any((e) => e.event.contains('vf_gate_PASSED'));
    bool get hadBlackScreen    => events.any((e) => e.event.contains('BLACK_SCREEN'));
    bool get isHealthy         => !hadVfGatePassed && !hadBlackScreen;
  }
  