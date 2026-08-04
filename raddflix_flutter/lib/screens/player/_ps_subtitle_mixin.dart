part of '../player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Phase J4 — _PlayerSubtitleMixin
//  Extracted from _PlayerScreenState (Phase J God-Class decomposition).
//  Owns: subtitle track selection (primary + secondary/OST), subtitle
//  language preference, subtitle bottom margin, subtitle sync offset/speed,
//  the current external subtitle file path, and the subtitle picker panel.
//
//  Cross-cluster members below are declared abstract because they are
//  implemented elsewhere in _PlayerScreenState (or one of its other part
//  files) — this mixin only has access to members declared in itself or in
//  ConsumerState<PlayerScreen>. Do NOT give these bodies here.
// ═══════════════════════════════════════════════════════════════════════════
mixin _PlayerSubtitleMixin on ConsumerState<PlayerScreen> {
  // ── Cross-cluster members (defined in _PlayerScreenState or another mixin) ──
  NativePlayer get _np;
  Player get _player;
  String get _currentTitle;
  bool get _isLocal;
  void _scheduleSavePrefs();
  Future<void> _startDubGeneration(String lang);
  void _openPanel({
    required Widget panel,
    required String title,
    double widthFactor = 0.40,
    double maxHeightFraction = 0.85,
  });

  List<SubtitleTrack> _subtitleTracks = [];

  SubtitleTrack? _selectedSubtitle;

  SubtitleTrack? _selectedSecondSub; // secondary-sid — OST / signs track
  // Language preference — persisted; null = let MPV auto-select
  String? _prefSubLang;

  double _subBottomMarginMain = 100.0;

  // 0B PLAYER-PERF: subtitle line is now a ValueNotifier<String?> so that
  // SubtitleOverlay can be rebuilt via ValueListenableBuilder without calling
  // setState() on every subtitle tick (1–10 calls/s depending on frame rate).
  // The getter/setter pair keeps all cross-cluster references transparent —
  // callers still write `_currentSubLine = line` and read `_currentSubLine`.
  // SUB-A3: raised dp when controls are showing — drives controlsRaiseDp on
  // SubtitleOverlay without forcing a Consumer/ValueListenableBuilder rebuild.
  final ValueNotifier<double> _subtitleRaiseNotifier = ValueNotifier(0.0);

  final ValueNotifier<String?> _currentSubLineNotifier = ValueNotifier(null);
  String? get _currentSubLine => _currentSubLineNotifier.value;
  set _currentSubLine(String? v) => _currentSubLineNotifier.value = v;

  // DUAL-SUB: secondary subtitle line — from secondary-sid track (stream lines[1]).
  // Kept alongside _currentSubLineNotifier so both notifiers live in the same mixin.
  final ValueNotifier<String?> _currentSecondSubLineNotifier = ValueNotifier(null);
  String? get _currentSecondSubLine => _currentSecondSubLineNotifier.value;
  set _currentSecondSubLine(String? v) => _currentSecondSubLineNotifier.value = v;

  double _subSync = 0.0; // seconds
  double _subSpeed = 1.0; // 0.5..2.0
  String? _currentSubFile;
  int _subtitleStyleReapplyGeneration = 0;

  List<SubtitleTrack> get _realSubtitleTracks =>
      _subtitleTracks.where((t) => t.id != null && int.tryParse(t.id!) != null).toList();

  // 0B PLAYER-PERF: debounce state — collapses rapid back-to-back calls
  // (show/hide transitions fire this multiple times per gesture) into a
  // single MPV property write after 16 ms. The latest controlsVisible value
  // is captured in _subMarginLastVisible so the timer always applies the
  // most recent intent even if several ticks arrive before it fires.
  bool? _subMarginLastVisible;
  Timer?  _subMarginDebounce;

  void _applySubtitleMargin({required bool controlsVisible}) {
    // When controls are visible, push subs 140px above bottom controls so they
    // clear the seek bar AND transport row.
    //
    // BUG-SUB-STYLE-01 (root cause of "customization changes preview but not
    // the real player"): this function runs on nearly every controls
    // show/hide transition — far more often than any style edit — so it is
    // the de-facto last writer of `sub-ass-override` on every real playback
    // session. It used to set 'yes', which lets an embedded ASS/SSA
    // subtitle's own baked-in style block win over our custom sub-color/
    // sub-font-size/sub-margin-y properties. The panel's style callbacks set
    // 'force' right before pushing a style change, but the very next
    // controls toggle (a few seconds later, or immediately via a tap)
    // silently downgraded it back to 'yes', undoing the override — so
    // embedded subtitles always snapped back to their built-in look/position
    // moments after a customization, which is exactly the reported symptom.
    //
    // Fix: 'sub-ass-override' must always be 'force' everywhere it's touched
    // (here, in `_loadSubPrefs`, on track selection, and on episode reset) —
    // never 'yes'. Do not reintroduce 'yes' in any of those call sites.
    _subMarginLastVisible = controlsVisible;
    _subMarginDebounce?.cancel();
    _subMarginDebounce = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      final base = _subBottomMarginMain;
      final cv = _subMarginLastVisible ?? controlsVisible;
      final marginY = cv ? (base + 140).round() : base.round();
      try {
        _np.setProperty('sub-ass-override', 'force');
        _np.setProperty('sub-margin-y', marginY.toString());
      } catch (_) {}
    });
  }

  void _adjustSubSync(double delta) {
    _subSync = (_subSync + delta);
    try { _np.setProperty('sub-delay', _subSync.toStringAsFixed(1)); } catch (_) {}
    setState(() {});
    _scheduleSavePrefs(); // was previously never persisted — reset to 0 on next open
  }

  // VIBE-1D: Set MPV's sub-speed so subtitle timestamps stay in sync with
  // a slowed or sped-up audio stream. Without this, subtitles indexed to
  // real-time positions drift ahead of/behind the vibe-shifted audio.
  // sub-speed is a multiplier on the subtitle's timestamp clock — setting it
  // to the same ratio as the vibe speed makes the two streams re-align.
  void _adjustSubSyncForVibe(PlaybackVibeMode mode) {
    final double speedRatio;
    switch (mode) {
      case PlaybackVibeMode.slowed:
      case PlaybackVibeMode.slowedReverb:
        speedRatio = 0.82;
      case PlaybackVibeMode.nightcore:
        speedRatio = 1.25;
      case PlaybackVibeMode.lofi:
        speedRatio = 0.93;
      case PlaybackVibeMode.phonk:
        speedRatio = 0.90;
      default: // none, eightD, club — no speed change
        speedRatio = 1.0;
    }
    try {
      _np.setProperty('sub-speed', speedRatio.toStringAsFixed(2));
    } catch (_) {}
  }

  // Called from _loadPrefs() at player startup so saved subtitle style/position
  // is applied to MPV immediately — without requiring the user to open the
  // subtitle panel first (which was the only place _loadSubPrefs() ran before).
  Future<void> _applySubtitleStylePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    const mpvFonts = ['sans-serif', 'serif', 'monospace', 'sans-serif'];
    final fontIdx    = prefs.getInt('pref_sub_font_idx')    ?? 0;
    final size       = prefs.getDouble('pref_sub_size')     ?? 22.0;
    final bold       = prefs.getBool('pref_sub_bold')       ?? false;
    final colorVal   = prefs.getInt('pref_sub_color')       ?? Colors.white.value;
    final bgColorVal = prefs.getInt('pref_sub_bg_color')    ?? Colors.transparent.value;
    final opacity    = prefs.getDouble('pref_sub_opacity')  ?? 1.0;
    final shadowIdx  = prefs.getInt('pref_sub_shadow')      ?? 2;
    final alignX     = prefs.getInt('pref_sub_align_x')     ?? 1;
    final alignY     = prefs.getInt('pref_sub_align_y')     ?? 2;
    final edgePad    = prefs.getDouble('pref_sub_edge_pad') ?? 16.0;
    final fitToVideo = prefs.getBool('pref_sub_fit')        ?? true;
    try {
      // Force ASS override FIRST (BUG-SUB-STYLE-01) — the same rule that
      // applies in _loadSubPrefs, _applySubtitleMargin, and track selection.
      _np.setProperty('sub-ass-override',          'force');
      _np.setProperty('sub-font',                  mpvFonts[fontIdx.clamp(0, 3)]);
      _np.setProperty('sub-font-size',             size.round().toString());
      _np.setProperty('sub-bold',                  bold ? 'yes' : 'no');
      _np.setProperty('sub-color',                 _mpvSubColor(Color(colorVal)));
      _np.setProperty('sub-back-color',            _mpvSubBackColor(Color(bgColorVal)));
      _np.setProperty('sub-opacity',               opacity.toStringAsFixed(2));
      _np.setProperty('sub-align-x',               ['left','center','right'][alignX.clamp(0, 2)]);
      _np.setProperty('sub-align-y',               ['top','center','bottom'][alignY.clamp(0, 2)]);
      _np.setProperty('sub-margin-x',              edgePad.round().toString());
      _np.setProperty('sub-ass-scale-with-window', fitToVideo ? 'yes' : 'no');
      // Shadow: 0=None  1=Outline  2=Drop Shadow  3=Box
      if (shadowIdx == 0) {
        _np.setProperty('sub-shadow-offset', '0');
        _np.setProperty('sub-outline-size',  '0');
      } else if (shadowIdx == 1) {
        _np.setProperty('sub-outline-size',  '2');
        _np.setProperty('sub-shadow-offset', '0');
      } else if (shadowIdx == 2) {
        _np.setProperty('sub-shadow-offset', '3');
        _np.setProperty('sub-outline-size',  '0.5');
      } else if (shadowIdx == 3) {
        _np.setProperty('sub-shadow-offset', '0');
        _np.setProperty('sub-outline-size',  '0');
      }
    } catch (_) {}
  }

  /// MPV may recreate its subtitle renderer after a track or `sub-file`
  /// change. Reapply after that lifecycle event, rather than racing the
  /// renderer while it is still loading the new subtitle stream.
  void _reapplySubtitleStyleAfterLifecycle() {
    final generation = ++_subtitleStyleReapplyGeneration;
    Future.delayed(const Duration(milliseconds: 150), () async {
      if (!mounted || generation != _subtitleStyleReapplyGeneration) return;
      await _applySubtitleStylePrefs();
    });
  }

  void _openSubtitlePanel() {
      final panel = _SubtitlePanel(
        isLocal: _isLocal,
        subSync: _subSync,
        subSpeed: _subSpeed,
        currentFile: _currentSubFile,
        onSyncChanged: (delta) => _adjustSubSync(delta),
        onSpeedChanged: (v) {
          setState(() => _subSpeed = v);
          try { _np.setProperty('sub-speed', v.toString()); } catch (_) {}
          _scheduleSavePrefs();
        },
        onSubPropertyChanged: (prop, val) {
          if (prop == '_sub_margin_main') {
            // Internal signal — update main state so _applySubtitleMargin
            // uses the user's latest base value.
            setState(() => _subBottomMarginMain = double.tryParse(val) ?? _subBottomMarginMain);
            _scheduleSavePrefs();
          } else {
            try {
              // Force ASS style override FIRST so that the property change below
              // immediately takes effect on ASS-format subs (embedded or SRT→ASS).
              // BUG-SUB-01 fix: apply 'force' unconditionally for ALL real MPV
              // sub-* properties. The previous per-prop whitelist was missing
              // sub-align-x, sub-align-y, sub-margin-x, and sub-ass-scale-with-window,
              // which meant position/alignment changes from the Position tab were
              // silently overridden by the embedded subtitle's own ASS style block.
              _np.setProperty('sub-ass-override', 'force');
              _np.setProperty(prop, val);
            } catch (_) {}
          }
        },
        title: _currentTitle,
        onSubtitleFilePicked: (path) {
          setState(() => _currentSubFile = path);
          try { _np.setProperty('sub-file', path); } catch (_) {}
        },
        // P57-02: embedded track selector
        embeddedTracks: _realSubtitleTracks,
        selectedSubtitle: _selectedSubtitle,
        onSubtitleTrackSelected: (track) {
          setState(() {
            _selectedSubtitle = track;
            // Remember the language so future episodes auto-select the same
            // language. Only update when track has a real language code.
            if (track != null && (track.language?.isNotEmpty ?? false)) {
              _prefSubLang = track.language;
            }
          });
          _scheduleSavePrefs();
          if (track != null) {
            _player.setSubtitleTrack(track);
            // Reapply the complete saved style after the track switch. MPV
            // can recreate its subtitle renderer and restore the track's
            // baked-in ASS defaults after the selection call returns.
            _reapplySubtitleStyleAfterLifecycle();
          } else {
            try { _np.setProperty('sid', 'no'); } catch (_) {}
          }
        },
        // P57-07: secondary subtitle (OST/signs at top)
        selectedSecondSub: _selectedSecondSub,
        onSecondSubSelected: (track) {
          setState(() => _selectedSecondSub = track);
          try {
            // Guard against tracks with a null/non-numeric id (e.g. synthetic
            // or virtual entries) — track.id! used to crash the player here.
            final id = track?.id;
            if (track != null && id != null && int.tryParse(id) != null) {
              _np.setProperty('secondary-sid', id);
              _np.setProperty('secondary-sub-visibility', 'yes');
            } else {
              _np.setProperty('secondary-sid', 'no');
            }
          } catch (_) {}
        },
        onDubRequested: _startDubGeneration,  // P59
        onStyleSynced: ({required fontIdx, required size, required bold,
            required color, required bgColor, required opacity,
            required shadowIdx}) {
          const fontNames = ['Sans Serif', 'Serif', 'Monospace', 'Casual'];
          // Map shadow style index to the outline thickness used by the Flutter
          // subtitle overlay (SubtitleOverlay / DualSubtitleOverlay).
          // Mirrors the sub-outline-size values sent to MPV in _applyShadow():
          //   0=None → 0.0   1=Outline → 2.0   2=Drop Shadow → 0.5   3=Box → 0.0
          const outlineThicknesses = [0.0, 2.0, 0.5, 0.0];
          ref.read(playerPrefsProvider.notifier).update((p) => p.copyWith(
                subtitleFontFamily: fontNames[fontIdx.clamp(0, fontNames.length - 1)],
                subtitleFontSize: size,
                subtitleBold: bold,
                // Bake the panel's separate text-opacity slider into the
                // color's alpha channel, since PlayerPrefs has no distinct
                // text-opacity field.
                subtitleTextColorValue: color.withOpacity(opacity).value,
                subtitleBackgroundColorValue: bgColor.value,
                subtitleBackgroundOpacity: bgColor.opacity,
                subtitleOutlineThickness: outlineThicknesses[shadowIdx.clamp(0, 3)],
              ));
        },
      );
      _openPanel(panel: panel, title: 'Subtitles', widthFactor: 0.42, maxHeightFraction: 0.90);
    }
}

// ── Shared MPV colour helpers ─────────────────────────────────────────────────
//
// mpv colour format: #RRGGBBAA  (AA=00 → fully opaque, AA=FF → transparent)
//
// Both _PlayerSubtitleMixin and _SubtitlePanelState are part-files of the same
// library (player_screen.dart), so these top-level private functions are
// visible to both without any class prefix — no need to duplicate them.

/// Text colour — always fully opaque in mpv format.
String _mpvSubColor(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}'
    '${c.green.toRadixString(16).padLeft(2, '0')}'
    '${c.blue.toRadixString(16).padLeft(2, '0')}';

/// Background colour — supports partial/full transparency in mpv format.
String _mpvSubBackColor(Color c) {
  if (c.opacity == 0) return '#000000ff'; // fully transparent
  final r  = c.red  .toRadixString(16).padLeft(2, '0');
  final g  = c.green.toRadixString(16).padLeft(2, '0');
  final b  = c.blue .toRadixString(16).padLeft(2, '0');
  // mpv AA=00 → opaque. Flutter opacity 1.0 → AA=00, opacity 0.0 → AA=FF
  final aa = ((1.0 - c.opacity) * 255).round()
                 .toRadixString(16).padLeft(2, '0');
  return '#$r$g$b$aa';
}
