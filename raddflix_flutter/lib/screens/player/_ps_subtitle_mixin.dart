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

  double _subSync = 0.0; // seconds
  double _subSpeed = 1.0; // 0.5..2.0
  String? _currentSubFile;

  List<SubtitleTrack> get _realSubtitleTracks =>
      _subtitleTracks.where((t) => t.id != null && int.tryParse(t.id!) != null).toList();

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
    final base = _subBottomMarginMain;
    final marginY = controlsVisible ? (base + 140).round() : base.round();
    try {
      _np.setProperty('sub-ass-override', 'force');
      _np.setProperty('sub-margin-y', marginY.toString());
    } catch (_) {}
  }

  void _adjustSubSync(double delta) {
    _subSync = (_subSync + delta);
    try { _np.setProperty('sub-delay', _subSync.toStringAsFixed(1)); } catch (_) {}
    setState(() {});
    _scheduleSavePrefs(); // was previously never persisted — reset to 0 on next open
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
              if (prop == 'sub-font-size'    || prop == 'sub-font'          ||
                  prop == 'sub-bold'        || prop == 'sub-color'        ||
                  prop == 'sub-back-color'  || prop == 'sub-scale'        ||
                  prop == 'sub-opacity'     || prop == 'sub-outline-size' ||
                  prop == 'sub-shadow-offset') {
                _np.setProperty('sub-ass-override', 'force');
              }
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
            // BUG-SUB-STYLE-01: force the override mode immediately on every
            // track switch so a newly-selected track's baked-in ASS style
            // never wins over the user's custom style/position, even before
            // the next controls show/hide fires `_applySubtitleMargin`.
            try { _np.setProperty('sub-ass-override', 'force'); } catch (_) {}
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
            required color, required bgColor, required opacity}) {
          const fontNames = ['Sans Serif', 'Serif', 'Monospace', 'Casual'];
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
              ));
        },
      );
      _openPanel(panel: panel, title: 'Subtitles', widthFactor: 0.42, maxHeightFraction: 0.90);
    }
}
