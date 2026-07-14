part of '../player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Phase J3 — _PlayerAudioLabMixin
//  Extracted from _PlayerScreenState (Phase J God-Class decomposition).
//  Owns: EQ presets/custom EQ, merged audio-filter (af) pipeline construction,
//  L/R balance, reverb + Audio Lab (vocal/dialogue/bass/compressor/stereo
//  widen/denoise) chain, audio sync offset, silence-skip pipeline flag, and
//  AI Dub generation/playback (Phase 59).
//
//  Cross-cluster members below are declared abstract because they are
//  implemented elsewhere in _PlayerScreenState (or one of its other part
//  files) — this mixin only has access to members declared in itself or in
//  ConsumerState<PlayerScreen>. Do NOT give these bodies here.
// ═══════════════════════════════════════════════════════════════════════════
mixin _PlayerAudioLabMixin on ConsumerState<PlayerScreen> {
  // ── Cross-cluster members (defined in _PlayerScreenState or another mixin) ──
  NativePlayer get _np;
  void _scheduleSavePrefs();
  void _showInfoSnackbar(String msg);
  String? get _currentSubFile; set _currentSubFile(String? v);
  SubtitleTrack? get _selectedSubtitle;
  Duration get _duration;
  double get _audioSync; set _audioSync(double v);

  double _audioBalance = 0.0;
  String _currentBalanceAf = '';
  String _currentChannelModeAf = '';
  int _channelModeIdx = 0; // 0=Stereo 1=Mono 2=Left only 3=Right only

  // Audio effect
  int _selectedPreset = 0; // 0=Original 1=TrebleBoost 2=BassBoost 3=Clarity 4=Movie 5=Music
  List<double> _eqBands = [0, 0, 0, 0, 0]; // 60,230,910,3600,14000 Hz
  bool _eqEnabled = true;
  String _currentReverbAf = ''; // active reverb aecho string
  String _currentLabAf = '';    // active lab af chain from _AudioEffectPanel
  // Lab state (persisted so panel reopens restore state)
  bool _labVocal = false;
  bool _labDialogue = false;
  bool _labNorm = false;
  bool _labBass = false;
  double _labBassLevel = 0.5;
  bool _labDialogueOnly = false;  // I1: keep centre-channel sum → mutes music/SFX
  bool _labCompress = false;      // I1: soft compressor → tames explosions for late-night
  bool _labStereoWide = false;    // I1: extrastereo → wider soundstage for headphones
  bool _labNoise = false;         // I1: afftdn spectral denoising → cleans noisy streams
  String _reverbPreset = 'None';

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

  // Silence skip
  bool _silenceSkipEnabled = false;
  double _silenceSkipThreshold = 1.5; // seconds

  // Silence skip — in merged AF pipeline flag
  bool _silenceInPipeline = false;

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

  String _buildMergedAfString() {
    final parts = <String>[];

    // A3: Extract any equalizer contribution from Lab (Dialogue Boost / Bass Boost)
    // and merge into the main EQ chain to prevent a double-equalizer conflict.
    // Two equalizer filters in the same af chain cause the main EQ sliders to appear
    // to do nothing when Dialogue or Bass Boost is active.
    // A3 fix: use allMatches so gains from ALL Lab equalizer segments are summed.
    // If only firstMatch is used, Bass Boost gains are silently dropped when
    // Dialogue Boost is also on (they each emit a separate equalizer= segment).
    List<int> labEqGains = List.filled(10, 0);
    for (final m in RegExp(r'equalizer=([\d:.\-]+)').allMatches(_currentLabAf)) {
      final rawGains = m.group(1)!.split(':');
      final parsed = rawGains.map((s) => int.tryParse(s) ?? 0).toList();
      for (int i = 0; i < 10; i++) {
        labEqGains[i] += i < parsed.length ? parsed[i] : 0;
      }
    }

    // A2+A3: Always emit equalizer= when EQ is enabled (even all-zero) so MPV
    // explicitly clears any previous non-zero state instead of leaving stale gains.
    // Also emit when Lab has EQ gains (Dialogue/Bass Boost) so those effects work
    // even when the main EQ toggle is off.
    if (_eqEnabled || labEqGains.any((v) => v != 0)) {
      final b = _eqBands;
      final g = [
        b[0].round() + labEqGains[0],  b[0].round() + labEqGains[1],   // 31.25, 62.5 → 60Hz
        b[1].round() + labEqGains[2],  b[1].round() + labEqGains[3],   // 125, 250 → 230Hz
        b[2].round() + labEqGains[4],  b[2].round() + labEqGains[5],   // 500, 1000 → 910Hz
        b[3].round() + labEqGains[6],  b[3].round() + labEqGains[7],   // 2000, 4000 → 3600Hz
        b[4].round() + labEqGains[8],  b[4].round() + labEqGains[9],   // 8000, 16000 → 14000Hz
      ].map((v) => v.clamp(-12, 12)).toList();
      parts.add('equalizer=${g.join(':')}');
    }

    // Reverb chain (aecho)
    if (_currentReverbAf.isNotEmpty) parts.add(_currentReverbAf);

    // A3: Lab chain — strip the equalizer segment already merged above so it
    // does not produce a second equalizer filter in the chain.
    final labAfClean = _currentLabAf
        .replaceAll(RegExp(r'equalizer=[^,]+(,|$)'), '')
        .replaceAll(RegExp(r'^,|,' + r'$'), '')
        .trim();
    if (labAfClean.isNotEmpty) parts.add(labAfClean);

    if (_currentChannelModeAf.isNotEmpty) parts.add(_currentChannelModeAf);
    if (_currentBalanceAf.isNotEmpty) parts.add(_currentBalanceAf);
    // Silence detection — must be last (detection filter, not audio transform)
    if (_silenceInPipeline) {
      parts.add('lavfi=[silencedetect=noise=-50dB:d=${_silenceSkipThreshold.toStringAsFixed(1)}]');
    }

    // BUG-AUDIO-SILENT-01 (root cause of "audio missing on some videos but
    // not others"): every `pan=stereo|c0=...|c1=...` filter above (Balance,
    // Channel Mode, Lab vocal-isolation/dialogue-only) hardcodes 2-channel
    // (c0/c1) input. These settings persist across episodes (by design, so a
    // user's EQ/effects stay put) and the underlying mpv `af` property
    // itself also carries over a loadfile unless explicitly reset. The
    // catalog mixes stereo, mono, and 5.1/7.1 sources — when any pan= filter
    // above receives a non-stereo track, ffmpeg's filter-graph negotiation
    // for that pan filter fails, which breaks the *entire* af chain (one bad
    // filter takes down the whole graph) and produces total silence for
    // that specific video, while stereo videos with the exact same settings
    // play fine. This is an async native-side failure our Dart
    // try/catch around setProperty can never see (the property set call
    // itself succeeds; only the filter's internal init fails).
    //
    // Fix: whenever any pan= filter is present, force the input into a
    // known 2-channel layout first via `aformat=channel_layouts=stereo`, so
    // every pan filter downstream always gets the stereo input it expects
    // regardless of the source track's real channel count.
    if (parts.any((p) => p.startsWith('pan='))) {
      parts.insert(0, 'aformat=channel_layouts=stereo');
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
    _scheduleSavePrefs();
  }

  void _applyAllAf() {
    final filterStr = _buildMergedAfString();
    try {
      _np.setProperty('af', filterStr);
      if (kDebugMode) debugPrint('[AudioLab] af set: $filterStr');
    } catch (e) {
      if (kDebugMode) debugPrint('[AudioLab] _applyAllAf ERROR: $e | filter: $filterStr');
    }
  }

  void _adjustAudioSync(double delta) {
    _audioSync = (_audioSync + delta);
    try { _np.setProperty('audio-delay', _audioSync.toStringAsFixed(1)); } catch (_) {}
    setState(() {});
  }

  Future<void> _startDubGeneration(String lang) async {
    if (_currentSubFile == null) {
      // _selectedSubtitle can be non-null for embedded/streaming MKV tracks
      // that have no backing SRT file — dubbing needs actual text lines, so
      // give an accurate reason instead of implying no subtitles are active.
      _showInfoSnackbar(_selectedSubtitle != null
          ? 'AI Dub needs a downloadable subtitle file — embedded tracks aren\'t supported yet. Download an online SRT first.'
          : 'Load an SRT subtitle file first');
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

    void _applySilenceSkip() {
      setState(() => _silenceInPipeline = _silenceSkipEnabled);
      _applyAllAf();
    }

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
}
