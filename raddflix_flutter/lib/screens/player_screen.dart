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
import 'package:audio_session/audio_session.dart';
import 'package:battery_plus/battery_plus.dart';
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
import '../services/playback_service.dart';
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
import '../widgets/player/audio_mode_backdrop.dart';
import '../core/player/word_dict.dart';
import '../widgets/player/word_definition_sheet.dart';
import '../widgets/player/subtitle_overlay.dart'; // SUB-OVERLAY-FIX
import '../core/player/subtitle_style.dart';
import '../core/utils/anim_config.dart';
import '../core/utils/anim_durations.dart';
import '../providers/live_channel_provider.dart';
import '../data/live_channels.dart';

// ── Phase J: panel classes extracted to part files ─────────────────────────
part 'player/_ps_panels_subtitle.dart';
part 'player/_ps_panels_audio.dart';
part 'player/_ps_panels_sidebar.dart';
part 'player/_ps_playback_mixin.dart';
part 'player/_ps_audiolab_mixin.dart';
part 'player/_ps_subtitle_mixin.dart';
part 'player/_ps_ui_mixin.dart';

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
  // UX3-10: when true, _initPlayer() reattaches to the live session held by
  // PlaybackService (see services/playback_service.dart) instead of
  // creating a new Player — this is how tapping the mini bar reopens
  // fullscreen playback without a reload. Set by MiniPlayerBar via
  // PlaybackService.buildResumeArgs().
  final bool attachExisting;

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
    this.attachExisting = false,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
//  State
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, _PlayerPlaybackMixin, _PlayerAudioLabMixin,
        _PlayerSubtitleMixin, _PlayerUIMixin {

  // ── MPV player ──────────────────────────────────────────────────────────────

  // ── Black-screen guards (MediaTek/Infinix) ──────────────────────────────────

  // ── Controls visibility ─────────────────────────────────────────────────────

  // ── Gesture ─────────────────────────────────────────────────────────────────

  // ── Seek flash ───────────────────────────────────────────────────────────────

  // ── Audio / Subtitle tracks ──────────────────────────────────────────────────

  // ── MX Layout State ──────────────────────────────────────────────────────────

  // Smart Enhance

  // Video zoom
  // 0=Fit 1=Stretch 2=Crop 3=100% 4=Custom
  // Pinch-to-zoom

  // Night mode eye-comfort filter

  // Clock overlay in title bar

  // Audio L/R balance

  // Video rotation (0/90/180/270)

  // Subtitle bottom margin — promoted to main state so controls-hide can shift it

  // Subtitle

  // Audio

  // ── Real track getters — filter media_kit sentinel values ───────────────────
  // SubtitleTrack.no() has id='no'; AudioTrack.auto() has id='auto'.
  // Only tracks with numeric MPV IDs are real embedded tracks.

  // Sleep timer

  // Settings
  // Feature 26 — resume position
  // Background-playback notification refresh timer (fires every 5 s)

  // Layout preset

  // Gesture toggles

  // Skip editor

  // Watch Party state

  // Voice Commands state

  // One-handed mode — hand preference

  // ── Customizable sidebar ──────────────────────────────────────────────────
  // Ordered list of shortcut IDs shown in the sidebar (persisted)

  // Skip editor debounce

  // Zoom/crop — separate aspect ratio index from BoxFit mode

  // ── P7: One-handed mode ──────────────────────────────────────────────────────

  // ── P12: Background audio ────────────────────────────────────────────────────

  // ── P14: Accent color (0=orange,1=blue,2=green,3=pink) ──────────────────────

  // ── P14: Progress bar style (0=slim,1=thick,2=gradient) ─────────────────────

  // ── P9: Seek preview label (shown above seek bar during drag) ────────────────

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
    _initBatteryMonitor();

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
          } else if (action == 'resume') {
            // Audio focus regained (call ended, other app stopped) — resume only
            // if we were actually playing before the interruption. Using a
            // dedicated 'resume' action (rather than 'play_pause') prevents a
            // double-toggle that would pause if the user had manually paused
            // during the interruption.
            if (!_player.state.playing) _player.play();
            Future.delayed(const Duration(milliseconds: 150), _notifyBgState);
          }
          break;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchPos();
      if (!_backgroundAudio) {
        // DA-2-FIX-2: trigger SMC when the app backgrounds without background audio.
        // The session is effectively suspended — if the OS kills the process, dispose()
        // will never fire, so this is the last safe point to capture the charge.
        // _resetSmcTracking() ensures the resumed session is treated as fresh;
        // the per-day cooldown in smc_log prevents any double-charge.
        _applySmcOnSessionEnd().ignore();
        _resetSmcTracking();
        _player.pause();
      } else {
        _isInBackground = true;
        // BGAUDIO-VID: drop the video decode path so Android does not stall
        // the audio pipeline waiting for a surface that gets destroyed in the
        // background.  Restored to vid=auto in the resumed branch above.
        try { _np.setProperty('vid', 'no'); } catch (_) {}
        // Start the foreground service so Android keeps the process alive.
        _notifyBgState();
        // Refresh the notification every 5 s so the progress bar stays in sync.
        _bgNotifTimer?.cancel();
        _bgNotifTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_isInBackground) _notifyBgState();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // BGAUDIO-VID: restore video track now that the surface is back.
      if (_isInBackground) {
        try { _np.setProperty('vid', 'auto'); } catch (_) {}
      }
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
    // Dismiss media notification when player screen closes — but not when
    // we're only closing because playback was handed off to PlaybackService
    // (minimize). That service owns the notification/method-handler for the
    // minimized session now; killing it here would silently break "MX
    // Player"-style background audio the moment the user minimizes.
    if (!_handedOffToService) {
      const MethodChannel('com.raddflix.app/pip')
          .invokeMethod('stopBgPlayback').catchError((_) {});
      const MethodChannel('com.raddflix.app/pip').setMethodCallHandler(null);
    }
    _immersiveExitTimer?.cancel();
    _watchPartySub?.cancel();
    _voiceSub?.cancel();
    _voiceCmdTimer?.cancel();
    // Bug fixes (post-UX3-10 review): none of these should fire on the
    // minimize path — the session is still live, just handed off to
    // PlaybackService, not actually ending.
    //  - leaveRoom()/stop() used to run unconditionally, so minimizing during
    //    a watch party silently kicked the user out of the room and killed
    //    voice commands even though the video kept playing.
    //  - _stopUsageTimer() used to run unconditionally too, so a minimized
    //    paid stream stopped being tracked/billed the instant you minimized
    //    it. PlaybackService now runs its own equivalent heartbeat while a
    //    session lives there (see playback_service.dart), so this only needs
    //    to stop when the session is actually ending.
    if (!_handedOffToService) {
      WatchPartyService.instance.leaveRoom();
      VoiceCommandsService.instance.stop();
      _applySmcOnSessionEnd().ignore(); // DA-2: charge SMC on real session end
      _stopUsageTimer();
    }
    _disposeBatteryMonitor();
    // Fix #1: unregister the log-message observer added in _initPlayer().
    // Without this, the C-level MPV callback fires into disposed Dart state.
    try { _np.unobserveProperty('log-message'); } catch (_) {}
    // UX3-10: if the user minimized playback, PlaybackService now owns this
    // Player — leave it running instead of disposing it out from under the
    // mini bar. _handedOffToService is only ever true right before a pop
    // triggered by _minimizePlayer().
    if (!_handedOffToService) {
      _player.dispose();
    }
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

  // ── Immersive mode ────────────────────────────────────────────────────────

  /// Called when user taps video surface while in immersive mode.
  /// Single tap = pause/resume. Also briefly shows the exit button.

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
      _clockFormat = prefs.getInt('pref_clock_fmt') ?? 0; // 0=auto 1=12h 2=24h
      _showBatteryInTitle = prefs.getBool('pref_battery') ?? true;
      _batteryChargeAnim = prefs.getBool('pref_battery_anim') ?? true;
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
      // Loop / shuffle — Z1: was never persisted; lost on restart
      _loopEnabled    = prefs.getBool('pref_loop')    ?? false;
      _shuffleEnabled = prefs.getBool('pref_shuffle') ?? false;
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
      // BUG-BALANCE-STARTUP: _audioBalance was loaded above but _currentBalanceAf
      // was never rebuilt — _applyAllAf() (500ms delay below) used '' for balance
      // so a saved non-zero balance had zero effect until the user moved the slider.
      // Rebuild using the same logic as _applyBalance() in _ps_audiolab_mixin.dart.
      if (_audioBalance.abs() < 0.02) {
        _currentBalanceAf = '';
      } else {
        final l = _audioBalance <= 0 ? 1.0 : (1.0 - _audioBalance);
        final r = _audioBalance >= 0 ? 1.0 : (1.0 + _audioBalance);
        _currentBalanceAf =
            'pan=stereo|c0=${l.toStringAsFixed(3)}*c0|c1=${r.toStringAsFixed(3)}*c1';
      }
    });
    // Restore speed via MPV
    // AUDIO-FIX-2: AF chain is now applied inside stream.tracks.listen
    // (after audio track discovery) so it fires when the audio pipeline is
    // actually ready. The old 500ms blind timer fired before MPV had opened
    // its audio decoder on slow devices / poor connections, causing setProperty
    // to be silently discarded. No delayed call needed here.
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
    // BUG-SW-DEC-STARTUP: pref_sw_dec was loaded into Dart state but hwdec was
    // never sent to MPV — hardware decoding ran regardless of the saved preference
    // until a codec failure auto-detected it. Apply immediately when enabled.
    if (_useSWDecoder) {
      try { _np.setProperty('hwdec', 'no'); } catch (_) {}
    }
    // Z1: restore loop state to MPV — pref_loop was loaded into Dart state
    // but MPV's loop-file was never set, so repeat didn't actually work after restart.
    if (_loopEnabled) {
      try { _np.setProperty('loop-file', 'inf'); } catch (_) {}
    }
    // BUG-SUB-STYLE-STARTUP: saved subtitle style (font, size, bold, color,
    // opacity, shadow, alignment, edge padding, fit) was only applied when the
    // subtitle panel opened — not at player startup. Apply all saved style props
    // to MPV now so the first subtitle frame already uses the user's preferences.
    // Delay slightly beyond _applyAllAf so MPV is fully ready to accept sub-* props.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _applySubtitleStylePrefs();
    });
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
    await prefs.setInt('pref_clock_fmt', _clockFormat);
    await prefs.setBool('pref_battery', _showBatteryInTitle);
    await prefs.setBool('pref_battery_anim', _batteryChargeAnim);
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
    // Loop / shuffle — Z1: was never persisted
    await prefs.setBool('pref_loop',    _loopEnabled);
    await prefs.setBool('pref_shuffle', _shuffleEnabled);
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  Smart Enhance
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Merged audio-filter pipeline ─────────────────────────────────────────────
  // NEVER call _np.setProperty('af',...) directly — always go through _applyAllAf()
  // so EQ + Reverb + Lab stack correctly instead of overwriting each other.

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

  // Seek bar style mapper: 0-2 → _HorizontalSeekPainter, 3+ → SeekBarPainter

  // ═══════════════════════════════════════════════════════════════════════════
  //  Subtitle helpers
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  //  Phase 59 — AI Dub (Method 1: Android TTS + MPV karaoke filter)
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  //  Gesture handlers
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  //  Scale gesture (single-finger drag + pinch-to-zoom)
  // ═══════════════════════════════════════════════════════════════════════════

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

                // 1b. Flutter subtitle overlay — SUB-OVERLAY-FIX
                // Sits above the video texture, below gesture/controls layers.
                // MPV's native renderer is disabled via SubtitleViewConfiguration
                // (visible: false) in _buildVideoSurface(), so this widget is the
                // sole subtitle renderer.  It reads PlayerPrefs directly so every
                // style change (font, colour, size, position, outline) takes effect
                // instantly without any NativePlayer.setProperty() race condition.
                // IgnorePointer lets taps fall through to the gesture layer when
                // dict lookup is off, so play/pause taps still work normally.
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

                // LIVE-P3: Channel logo watermark — bottom-right, always visible
                // in landscape live mode regardless of control visibility.
                if (_isLive) _buildLiveLandscapeWatermark(),

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

    // ═══════════════════════════════════════════════════════════════════════════
    //  Lock overlay
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Controls overlay — modern clean layout
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Top Bar
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Center playback controls (skip + play/pause)
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Bottom area: seek bar + icon row
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Horizontal Seek Bar
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Customizable Shortcut Sidebar
    // ═══════════════════════════════════════════════════════════════════════════

    // ── Sidebar shortcut button (icon + label, active = accent left border) ──

    // ═══════════════════════════════════════════════════════════════════════════
    //  MX Player-style side indicator (vertical pill)
    //  Brightness → LEFT side (amber bar)
    //  Volume     → RIGHT side (white/orange bar)
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Portrait layout — YouTube/Netflix split (video top 38% + controls below)
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Portrait-only transport row (no Lock / Immersive / Settings clutter)
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Panels (right-side slide-in / bottom-sheet in portrait)
    // ═══════════════════════════════════════════════════════════════════════════

// Volume X: any sheet/panel over the video surface must stay ≤40% of the
// viewport so it never dominates or blocks the frame.

// C1: shared orientation-aware panel opener. All 7 panel-opening methods
// below (_openSubtitlePanel, _openAudioPanel, _openZoomPanel,
// _openAudioEffectPanel, _openMoreMenu, _openSidebarCustomizer,
// _openSettingsPanel) used to repeat this exact landscape/portrait branch
// inline (commit 72f93a8d). Centralized here so the branching logic only
// exists once.

    // ── Jump To ───────────────────────────────────────────────────────────────

    // ── Speed Presets ─────────────────────────────────────────────────────────

    // ── End Action ────────────────────────────────────────────────────────────

    // ── Silence Skip ──────────────────────────────────────────────────────────

    // ── Zoom & Crop ───────────────────────────────────────────────────────────

    // ── Gesture Map ───────────────────────────────────────────────────────────

    // ── Skip Editor ───────────────────────────────────────────────────────────

    // ── Layout Designer ───────────────────────────────────────────────────────

    // ── Screenshot ────────────────────────────────────────────────────────────
    // `withSubtitles: true` uses MPV's native `screenshot subtitles` mode
    // (burns in whatever subs/overlays are currently rendered) instead of
    // the default `screenshot video` (clean frame only). Long-press the
    // screenshot shortcut to capture with subtitles.

    // ── Watch Party ───────────────────────────────────────────────────────────

    // Feature 24: Picture-in-Picture

    // Fix #DUB-01: shown when setLanguage() returns LANG_MISSING_DATA (-1) or
    // LANG_NOT_SUPPORTED (-2). Provides an "Install" action that deep-links to
    // the Android TTS settings page so the user can download the voice pack.

    // ═══════════════════════════════════════════════════════════════════════════
    //  Episode sheet
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //  Utility
    // ═══════════════════════════════════════════════════════════════════════════

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
    // UX3-10 fix: Back (ends session) and Minimize (keeps it running) sit
    // right next to each other and used to be visually identical, which made
    // them easy to fumble. Letting callers dim non-destructive actions like
    // minimize gives Back the stronger visual weight of the two.
    final Color color;

    const _RaddIconBtn({
      required this.icon,
      this.size = 22,
      this.onTap,
      this.color = Colors.white,
    });

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
            child: Icon(icon, color: color, size: size,
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
