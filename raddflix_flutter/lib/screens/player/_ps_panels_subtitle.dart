// J4-part: Subtitle panel classes extracted from player_screen.dart (Phase J)
// ignore_for_file: unused_import
part of '../player_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  SUBTITLE PANEL
// ═════════════════════════════════════════════════════════════════════════════

class _SubtitlePanel extends StatefulWidget {
  final bool isLocal;
  final double subSync;
  final double subSpeed;
  final String? currentFile;
  final void Function(double) onSyncChanged;
  final void Function(double) onSpeedChanged;
  final void Function(String prop, String val) onSubPropertyChanged;
  final String? title;
  final void Function(String)? onSubtitleFilePicked;
  final void Function(String lang)? onDubRequested; // P59
  // P57-02: embedded MKV subtitle tracks + P57-07: secondary (OST/signs) sub
  final List<SubtitleTrack> embeddedTracks;
  final SubtitleTrack? selectedSubtitle;
  final SubtitleTrack? selectedSecondSub;
  final void Function(SubtitleTrack?) onSubtitleTrackSelected;
  final void Function(SubtitleTrack?) onSecondSubSelected;
  // Mirrors this panel's pref_sub_* style state into PlayerPrefs whenever it
  // changes, so the (separately maintained) PlayerPrefs-based settings screen
  // and any future Flutter-rendered overlay stay in sync with what's actually
  // being sent to MPV, instead of silently drifting apart.
  final void Function({
    required int fontIdx,
    required double size,
    required bool bold,
    required Color color,
    required Color bgColor,
    required double opacity,
  })? onStyleSynced;

  const _SubtitlePanel({
    required this.isLocal,
    required this.subSync,
    required this.subSpeed,
    required this.currentFile,
    required this.onSyncChanged,
    required this.onSpeedChanged,
    required this.onSubPropertyChanged,
    this.title,
    this.onSubtitleFilePicked,
    this.onDubRequested,
    this.embeddedTracks = const [],
    this.selectedSubtitle,
    this.selectedSecondSub,
    required this.onSubtitleTrackSelected,
    required this.onSecondSubSelected,
    this.onStyleSynced,
  });

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<_SubtitlePanel> {
  // ── Tabs: 0=Tracks  1=Style  2=Position  3=Sync  4=Online  5=AI Dub ──────
  int _tab = 0;
  late double _sync;
  late double _speed;

  // ── Style ─────────────────────────────────────────────────────────────────
  int    _subFontIdx   = 0;       // 0=Sans  1=Serif  2=Mono  3=Casual
  double _subSize      = 22.0;
  bool   _subBold      = false;
  Color  _subColor     = Colors.white;
  Color  _subBgColor   = Colors.transparent;
  double _subOpacity   = 1.0;
  int    _subShadowIdx = 2;       // 0=None  1=Outline  2=Drop Shadow  3=Box

  // ── Position ──────────────────────────────────────────────────────────────
  int    _subAlignX       = 1;    // 0=Left   1=Center   2=Right
  int    _subAlignY       = 2;    // 0=Top    1=Center   2=Bottom
  double _subBottomMargin = 100.0;
  double _subEdgePadding  = 16.0;
  bool   _subFitToVideo   = true;

  // ── Online search ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _onlineResults = [];
  bool    _onlineLoading   = false;
  String  _onlineError     = '';
  late    TextEditingController _searchController;
  String  _selectedLangCode = 'urd,hin';
  bool    _hasSearched = false;
  // static: _SubtitlePanelState is recreated every time the panel opens (it's
  // built fresh inside a bottom sheet), so an instance field lost the token on
  // every open and re-logged in to OpenSubtitles each time. A static field
  // survives across panel opens for the life of the app process.
  static String? _osToken;

  static const _subFonts     = ['Sans Serif', 'Serif', 'Monospace', 'Casual'];
  static const _mpvFonts     = ['sans-serif', 'serif', 'monospace', 'sans-serif'];
  static const _shadowLabels = ['None', 'Outline', 'Shadow', 'Box'];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _sync  = widget.subSync;
    _speed = widget.subSpeed;
    _searchController = TextEditingController(text: widget.title ?? '');
    if ((widget.title ?? '').isNotEmpty && !widget.isLocal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchOnlineSubtitles(context);
      });
    }
    // Load saved subtitle style/position settings and re-apply to MPV
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSubPrefs();
    });
  }

  Future<void> _loadSubPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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
    // Load saved bottom margin so the slider reflects the actual active value
    // instead of always resetting to 100 when the panel reopens.
    final margin     = prefs.getDouble('pref_sub_margin')   ?? 100.0;
    setState(() {
      _subFontIdx      = fontIdx;
      _subSize         = size;
      _subBold         = bold;
      _subColor        = Color(colorVal);
      _subBgColor      = Color(bgColorVal);
      _subOpacity      = opacity;
      _subShadowIdx    = shadowIdx;
      _subAlignX       = alignX;
      _subAlignY       = alignY;
      _subEdgePadding  = edgePad;
      _subFitToVideo   = fitToVideo;
      _subBottomMargin = margin;
    });
    if (!mounted) return;
    // Re-apply all saved settings to MPV so the live video matches prefs.
    // BUG-SUB-STYLE-01: force ASS style override FIRST — otherwise an
    // embedded subtitle's own baked-in style block can win over every
    // property pushed below, which is why customization used to appear to
    // do nothing on the real player despite updating the preview box.
    _setProp('sub-ass-override',          'force');
    _setProp('sub-font',                  _mpvFonts[fontIdx]);
    _setProp('sub-font-size',             size.round().toString());
    _setProp('sub-bold',                  bold ? 'yes' : 'no');
    _setProp('sub-color',                 _mpvSubColor(Color(colorVal)));
    _setProp('sub-back-color',            _mpvSubBackColor(Color(bgColorVal)));
    _setProp('sub-opacity',               opacity.toStringAsFixed(2));
    _setProp('sub-align-x',              ['left','center','right'][alignX]);
    _setProp('sub-align-y',              ['top','center','bottom'][alignY]);
    _setProp('sub-margin-x',              edgePad.round().toString());
    _setProp('sub-ass-scale-with-window', fitToVideo ? 'yes' : 'no');
    _applyShadow(shadowIdx);
  }

  Future<void> _saveSubPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pref_sub_font_idx',    _subFontIdx);
    await prefs.setDouble('pref_sub_size',      _subSize);
    await prefs.setBool('pref_sub_bold',        _subBold);
    await prefs.setInt('pref_sub_color',        _subColor.value);
    await prefs.setInt('pref_sub_bg_color',     _subBgColor.value);
    await prefs.setDouble('pref_sub_opacity',   _subOpacity);
    await prefs.setInt('pref_sub_shadow',       _subShadowIdx);
    await prefs.setInt('pref_sub_align_x',      _subAlignX);
    await prefs.setInt('pref_sub_align_y',      _subAlignY);
    await prefs.setDouble('pref_sub_edge_pad',  _subEdgePadding);
    await prefs.setBool('pref_sub_fit',         _subFitToVideo);
    widget.onStyleSynced?.call(
      fontIdx: _subFontIdx,
      size:    _subSize,
      bold:    _subBold,
      color:   _subColor,
      bgColor: _subBgColor,
      opacity: _subOpacity,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _setProp(String prop, String val) =>
      widget.onSubPropertyChanged(prop, val);

  void _showInfoSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 2),
    ));
  }

  /// Apply shadow style + fix the "Box" mode using sub-back-color correctly.
  void _applyShadow(int idx) {
    setState(() => _subShadowIdx = idx);
    HapticFeedback.selectionClick();
    if (idx == 0) {        // None
      _setProp('sub-shadow-offset', '0');
      _setProp('sub-outline-size', '0');
    } else if (idx == 1) { // Outline
      _setProp('sub-outline-size', '2');
      _setProp('sub-shadow-offset', '0');
    } else if (idx == 2) { // Drop Shadow
      _setProp('sub-shadow-offset', '3');
      _setProp('sub-outline-size', '0.5');
    } else if (idx == 3) { // Box — opaque background, no shadow/outline
      _setProp('sub-shadow-offset', '0');
      _setProp('sub-outline-size', '0');
      if (_subBgColor.opacity == 0) {
        setState(() => _subBgColor = Colors.black87);
        _setProp('sub-back-color', _toMpvBackColor(Colors.black87));
      }
    }
    _saveSubPrefs();
  }


  // ── Online subtitle search via OpenSubtitles XML-RPC (anonymous, no key needed) ──
  // The old REST API (rest.opensubtitles.org) is dead as of 2023.
  // The XML-RPC API (api.opensubtitles.org/xml-rpc) still accepts anonymous login.

  /// Step 1: anonymous login → returns session token (cached in _osToken)
  Future<String?> _osLogin() async {
    if (_osToken != null) return _osToken;
    const loginXml =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<methodCall><methodName>LogIn</methodName><params>'
        '<param><value><string></string></value></param>'
        '<param><value><string></string></value></param>'
        '<param><value><string>en</string></value></param>'
        '<param><value><string>RaddFlix v1</string></value></param>'
        '</params></methodCall>';
    HttpClient? client;
    try {
      client = HttpClient();
      final req = await client.postUrl(
          Uri.parse('https://api.opensubtitles.org/xml-rpc'));
      req.headers.set('Content-Type', 'text/xml; charset=utf-8');
      req.headers.set('User-Agent', 'RaddFlix v1');
      req.write(loginXml);
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final body = await resp.transform(const Utf8Decoder()).join();
      final m = RegExp(r'<name>token</name>\s*<value><string>([^<]+)</string>')
          .firstMatch(body);
      _osToken = m?.group(1);
      return _osToken;
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
  }

  /// Extract all string-value members from an XML-RPC struct block
  Map<String, String> _parseXmlRpcStruct(String block) {
    final result = <String, String>{};
    final members = RegExp(
        r'<name>([^<]+)</name>\s*<value><string>([^<]*)</string>',
        dotAll: true).allMatches(block);
    for (final m in members) {
      result[m.group(1)!] = m.group(2)!;
    }
    return result;
  }

  /// Step 2: search by query + language code
  Future<void> _fetchOnlineSubtitles(BuildContext ctx) async {
    if (_onlineLoading) return;
    final query = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : (widget.title ?? '');
    if (query.isEmpty) return;
    if (mounted) setState(() {
      _onlineLoading = true; _onlineError = ''; _onlineResults = []; _hasSearched = true;
    });
    HttpClient? client;
    try {
      final token = await _osLogin();
      if (token == null) {
        if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Could not connect to subtitle server. Try again.'; });
        return;
      }
      final safeQuery = query.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
      final searchXml =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<methodCall><methodName>SearchSubtitles</methodName><params>'
          '<param><value><string>$token</string></value></param>'
          '<param><value><array><data><value><struct>'
          '<member><name>sublanguageid</name><value><string>$_selectedLangCode</string></value></member>'
          '<member><name>query</name><value><string>$safeQuery</string></value></member>'
          '</struct></value></data></array></value></param>'
          '</params></methodCall>';
      client = HttpClient();
      final req = await client.postUrl(
          Uri.parse('https://api.opensubtitles.org/xml-rpc'));
      req.headers.set('Content-Type', 'text/xml; charset=utf-8');
      req.headers.set('User-Agent', 'RaddFlix v1');
      req.write(searchXml);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final body = await resp.transform(const Utf8Decoder()).join();
      // Check for fault
      if (body.contains('<name>faultString</name>')) {
        _osToken = null; // token may be expired, reset
        if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Search failed. Tap retry.'; });
        return;
      }
      // Split on struct boundaries and parse each subtitle entry
      final structs = RegExp(r'<value><struct>(.*?)</struct></value>', dotAll: true)
          .allMatches(body)
          .map((m) => _parseXmlRpcStruct(m.group(1)!))
          .where((s) => s.containsKey('SubFileName'))
          .toList();
      if (mounted) setState(() {
        _onlineResults = structs.take(20).toList();
        _onlineLoading = false;
        if (structs.isEmpty) _onlineError = 'No subtitles found. Try a different title or language.';
      });
    } catch (e) {
      if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Search failed: try again.'; });
    } finally {
      client?.close();
    }
  }

  Future<void> _downloadOnlineSubtitle(BuildContext ctx, Map<String, dynamic> entry) async {
    final link = (entry['SubDownloadLink'] ?? '') as String;
    final fname = (entry['SubFileName'] ?? 'subtitle.srt') as String;
    if (link.isEmpty) return;
    if (mounted) setState(() => _onlineLoading = true);
    HttpClient? client;
    try {
      client = HttpClient();
      final req = await client.getUrl(Uri.parse(link));
      req.headers.set('User-Agent', 'RaddFlix v1');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final bytesList = <List<int>>[];
      await for (final chunk in resp) { bytesList.add(chunk); }
      final bytes = bytesList.expand((e) => e).toList();
      List<int> srtBytes;
      // OpenSubtitles serves gzip (RFC 1952, magic bytes 1f 8b). ZLibDecoder
      // only understands raw zlib (RFC 1950) and throws on gzip input, which
      // silently fell through to writing the raw compressed bytes as an SRT
      // file. dart:io's `gzip` codec (already available via dart:io) is the
      // correct decoder here — no extra dependency needed.
      try { srtBytes = gzip.decode(bytes); }
      catch (_) { srtBytes = bytes; }
      final dir = await getTemporaryDirectory();
      final cleanName = fname.replaceAll('.gz', '');
      final outPath = '${dir.path}/$cleanName';
      File(outPath).writeAsBytesSync(srtBytes);
      widget.onSubtitleFilePicked?.call(outPath);
      if (mounted) setState(() => _onlineLoading = false);
      if (mounted) _showInfoSnackbar('✓ Subtitle loaded: $cleanName');
    } catch (e) {
      if (mounted) setState(() { _onlineLoading = false; _onlineError = 'Download failed: try again.'; });
    } finally {
      client?.close();
    }
  }

  // ── P59: AI Dub button section ─────────────────────────────────────────
  List<Widget> _buildDubSection(BuildContext context) {
    final hasDub = widget.onDubRequested != null;
    return [
      const SizedBox(height: RaddSpace.xs),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF352A1F), Color(0xFF2C2219)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.35), width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI', style: TextStyle(color: Color(0xFF4A9EFF),
                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
              const SizedBox(width: RaddSpace.sm),
              const Text('Auto Dubbing', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: RaddSpace.xs),
            const Text('Generates on-device voice dub from this subtitle',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 10),
            // C5: explicit up-front hint — first-time use of a language often
            // needs its Android TTS voice pack installed first. Surfacing this
            // before the user taps (rather than only after a failure) avoids a
            // confusing silent-feeling wait followed by an error snackbar.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: RaddRadius.smRadius,
                border: Border.all(color: Colors.amber.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.download_for_offline_outlined, color: Colors.amber, size: 15),
                  const SizedBox(width: RaddSpace.sm),
                  const Expanded(
                    child: Text(
                      'First time in a language? Install its voice pack first.',
                      style: TextStyle(color: Colors.amber, fontSize: 10.5, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Install',
                          style: TextStyle(color: Colors.amber, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _DubLangBtn(
                flag: '🇵🇰', label: 'Urdu', sublabel: 'ur-PK',
                color: AppColors.jazzGreen,
                onTap: hasDub ? () => widget.onDubRequested!('ur-PK') : null,
              )),
              const SizedBox(width: 10),
              Expanded(child: _DubLangBtn(
                flag: '🇮🇳', label: 'Hindi', sublabel: 'hi-IN',
                color: const Color(0xFFFF9933),
                onTap: hasDub ? () => widget.onDubRequested!('hi-IN') : null,
              )),
            ]),
            const SizedBox(height: 10),
            const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.white24, size: 12),
              SizedBox(width: 5),
              Expanded(child: Text(
                'Music + effects preserved via karaoke filter. 2-5 min first time.',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              )),
            ]),
          ],
        ),
      ),
      const SizedBox(height: RaddSpace.md),
    ];
  }

  // ── Live subtitle preview ─────────────────────────────────────────────────
  Widget _buildPreview() {
    final shadows = <Shadow>[
      if (_subShadowIdx == 1) ...[
        const Shadow(color: Colors.black, blurRadius: 4, offset: Offset.zero),
        const Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1.5, 1.5)),
        const Shadow(color: Colors.black, blurRadius: 2, offset: Offset(-1.5, -1.5)),
      ],
      if (_subShadowIdx == 2)
        const Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(2, 3)),
    ];
    final textStyle = TextStyle(
      fontSize: (_subSize * 0.68).clamp(10.0, 28.0),
      fontWeight: _subBold ? FontWeight.bold : FontWeight.normal,
      color: _subColor.withOpacity(_subOpacity),
      // Preview previously always rendered the default sans-serif font
      // regardless of the font family selected above it.
      fontFamily: _mpvFonts[_subFontIdx],
      shadows: shadows,
      height: 1.3,
    );
    final vAlign = _subAlignY == 0 ? Alignment.topCenter
                 : _subAlignY == 1 ? Alignment.center
                                   : Alignment.bottomCenter;
    final hAlign = _subAlignX == 0 ? TextAlign.left
                 : _subAlignX == 2 ? TextAlign.right : TextAlign.center;
    final hasBg = _subBgColor.opacity > 0;
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.card, AppColors.surface],
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(children: [
        Align(
          alignment: vAlign,
          child: Padding(
            padding: const EdgeInsets.all(RaddSpace.sm),
            child: Container(
              padding: _subShadowIdx == 3
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: _subShadowIdx == 3
                    ? (hasBg ? _subBgColor : Colors.black.withOpacity(0.78))
                    : (hasBg ? _subBgColor : null),
                borderRadius: _subShadowIdx == 3 ? BorderRadius.circular(3) : null,
              ),
              child: Text('نمونہ  Sample subtitle', style: textStyle,
                  textAlign: hAlign, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        const Positioned(top: 5, left: 8,
          child: Text('PREVIEW', style: TextStyle(
              color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.4))),
      ]),
    );
  }

  // ── Tab helpers ────────────────────────────────────────────────────────────
  static Widget _secLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Text(label, style: const TextStyle(
        color: Colors.white54, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.4)),
  );

  Widget _buildSliderRow({
    required String label, required String valueLabel,
    required double value, required double min, required double max,
    required int divisions, required ValueChanged<double> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const Spacer(),
        Text(valueLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2.5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions,
            activeColor: Colors.white, inactiveColor: Colors.white24,
            onChanged: onChanged),
      ),
    ]),
  );

  Widget _buildSwitchRow({required IconData icon, required String label,
      required bool value, required ValueChanged<bool> onChanged}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: Colors.white54, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
        Switch(value: value, onChanged: onChanged,
            activeColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ]),
    );

  Widget _buildColorRow({required List<Color> presets, required Color current,
      required ValueChanged<Color> onPick}) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: presets.map((c) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); onPick(c); },
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c,
              border: Border.all(
                color: c == current ? Colors.white : Colors.white38,
                width: c == current ? 2.5 : 1.2,
              ),
            ),
            child: c == Colors.transparent
                ? const Icon(Icons.block, color: Colors.white38, size: 16)
                : c == current
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
          ),
        ),
      )).toList()),
    );

  Widget _buildSegment({required List<String> labels, required int selected,
      required ValueChanged<int> onChanged}) =>
    Row(children: List.generate(labels.length, (i) => Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: i < labels.length - 1 ? 6 : 0),
        child: GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); onChanged(i); },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected == i ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.06),
              borderRadius: RaddRadius.smRadius,
              border: Border.all(
                color: selected == i ? Colors.white60 : Colors.white12,
                width: selected == i ? 1.5 : 1,
              ),
            ),
            child: Text(labels[i],
                style: TextStyle(color: selected == i ? Colors.white : Colors.white54,
                    fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
          ),
        ),
      ),
    )));

  // ── Tab bodies ─────────────────────────────────────────────────────────────

  Widget _buildTracksTab() => ListView(padding: const EdgeInsets.all(14), children: [
    if (widget.embeddedTracks.isNotEmpty) ...[
      _secLabel('Primary Track'),
      ...widget.embeddedTracks.asMap().entries.map((e) => _SubTrackTile(
        track: e.value, index: e.key,
        selected: widget.selectedSubtitle == e.value,
        accentColor: Colors.white,
        onTap: () => widget.onSubtitleTrackSelected(e.value),
      )),
      _SubTrackTile(track: null, index: -1, label: 'Off',
        selected: widget.selectedSubtitle == null,
        accentColor: Colors.white,
        onTap: () => widget.onSubtitleTrackSelected(null)),
      const SizedBox(height: 10),
      const Divider(color: Colors.white12, height: 1),
      const SizedBox(height: 10),
      _secLabel('Secondary — OST / Signs (top of screen)'),
      const Padding(padding: EdgeInsets.only(bottom: 8),
        child: Text('Song lyrics, signs, on-screen text shown above primary',
            style: TextStyle(color: Colors.white38, fontSize: 11))),
      ...widget.embeddedTracks.asMap().entries.map((e) => _SubTrackTile(
        track: e.value, index: e.key,
        selected: widget.selectedSecondSub == e.value,
        accentColor: const Color(0xFF4A9EFF),
        onTap: () => widget.onSecondSubSelected(e.value),
      )),
      _SubTrackTile(track: null, index: -1, label: 'Off',
        selected: widget.selectedSecondSub == null,
        accentColor: const Color(0xFF4A9EFF),
        onTap: () => widget.onSecondSubSelected(null)),
      const SizedBox(height: 10),
      const Divider(color: Colors.white12, height: 1),
      const SizedBox(height: 10),
    ],
    _secLabel('External File'),
    const SizedBox(height: 2),
    if (widget.currentFile != null)
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: RaddRadius.smRadius,
          border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.subtitles_rounded, color: Color(0xFF4A9EFF), size: 18),
          const SizedBox(width: RaddSpace.sm),
          Expanded(child: Text(widget.currentFile!.split('/').last,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
    GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        final r = await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: ['srt', 'vtt', 'ass', 'ssa']);
        if (r != null && r.files.single.path != null)
          widget.onSubtitleFilePicked?.call(r.files.single.path!);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.white10,
            borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open_rounded, color: Colors.white70, size: 28),
          SizedBox(height: 6),
          Text('Open from device',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          SizedBox(height: 2),
          Text('SRT · VTT · ASS · SSA',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ),
    ),
  ]);

  Widget _buildStyleTab() {
    const textColors = [
      Colors.white, Colors.yellow, Color(0xFFFFD700),
      Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFFFF8C00), Colors.black,
    ];
    const bgColors = [
      Colors.transparent, Colors.black87, Color(0x99000000),
      Color(0xCC000000), Color(0x99FFFF00), Colors.black,
    ];
    return ListView(padding: const EdgeInsets.all(14), children: [
      _buildPreview(),
      _secLabel('Font'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: List.generate(_subFonts.length, (i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () { setState(() => _subFontIdx = i); HapticFeedback.selectionClick(); _setProp('sub-font', _mpvFonts[i]); _saveSubPrefs(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _subFontIdx == i ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _subFontIdx == i ? Colors.white60 : Colors.white24,
                  width: _subFontIdx == i ? 1.5 : 1,
                ),
              ),
              child: Text(_subFonts[i], style: TextStyle(
                color: _subFontIdx == i ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: _subFontIdx == i ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          ),
        ))),
      ),
      const SizedBox(height: 14),
      _buildSliderRow(
        label: 'Size', valueLabel: '${_subSize.round()} pt',
        value: _subSize, min: 12, max: 40, divisions: 28,
        onChanged: (v) { setState(() => _subSize = v); _setProp('sub-font-size', v.round().toString()); _saveSubPrefs(); },
      ),
      _buildSwitchRow(
        icon: Icons.format_bold_rounded, label: 'Bold',
        value: _subBold,
        onChanged: (v) { setState(() => _subBold = v); HapticFeedback.selectionClick(); _setProp('sub-bold', v ? 'yes' : 'no'); _saveSubPrefs(); },
      ),
      _buildSliderRow(
        label: 'Opacity', valueLabel: '${(_subOpacity * 100).round()}%',
        value: _subOpacity, min: 0.1, max: 1.0, divisions: 9,
        onChanged: (v) { setState(() => _subOpacity = v); _setProp('sub-opacity', v.toStringAsFixed(2)); _saveSubPrefs(); },
      ),
      const SizedBox(height: RaddSpace.sm),
      _secLabel('Text Colour'),
      _buildColorRow(presets: textColors, current: _subColor, onPick: (c) {
        setState(() => _subColor = c);
        _setProp('sub-color', _mpvSubColor(c));
        _saveSubPrefs();
      }),
      const SizedBox(height: 14),
      _secLabel('Background'),
      _buildColorRow(presets: bgColors, current: _subBgColor, onPick: (c) {
        setState(() => _subBgColor = c);
        _setProp('sub-back-color', _mpvSubBackColor(c));
        _saveSubPrefs();
      }),
      const SizedBox(height: 14),
      _secLabel('Shadow Style'),
      _buildSegment(
        labels: _shadowLabels,
        selected: _subShadowIdx,
        onChanged: _applyShadow,
      ),
      const SizedBox(height: RaddSpace.sm),
    ]);
  }

  Widget _buildPositionTab() => ListView(padding: const EdgeInsets.all(14), children: [
    _buildPreview(),
    _secLabel('Horizontal Alignment'),
    _buildSegment(
      labels: const ['Left', 'Center', 'Right'], selected: _subAlignX,
      onChanged: (i) { setState(() => _subAlignX = i); _setProp('sub-align-x', ['left','center','right'][i]); _saveSubPrefs(); },
    ),
    const SizedBox(height: 14),
    _secLabel('Vertical Position'),
    _buildSegment(
      labels: const ['Top', 'Center', 'Bottom'], selected: _subAlignY,
      onChanged: (i) { setState(() => _subAlignY = i); _setProp('sub-align-y', ['top','center','bottom'][i]); _saveSubPrefs(); },
    ),
    const SizedBox(height: 14),
    _buildSliderRow(
      label: 'Bottom Margin', valueLabel: '${_subBottomMargin.round()} px',
      value: _subBottomMargin, min: 0, max: 200, divisions: 40,
      onChanged: (v) {
        setState(() => _subBottomMargin = v);
        _setProp('sub-margin-y', v.round().toString());
        _setProp('_sub_margin_main', v.toStringAsFixed(1));
        _saveSubPrefs();
      },
    ),
    _buildSliderRow(
      label: 'Edge Padding', valueLabel: '${_subEdgePadding.round()} px',
      value: _subEdgePadding, min: 0, max: 60, divisions: 12,
      onChanged: (v) { setState(() => _subEdgePadding = v); _setProp('sub-margin-x', v.round().toString()); _saveSubPrefs(); },
    ),
    _buildSwitchRow(
      icon: Icons.fit_screen_rounded, label: 'Fit subtitles into video frame',
      value: _subFitToVideo,
      onChanged: (v) { setState(() => _subFitToVideo = v); HapticFeedback.selectionClick(); _setProp('sub-ass-scale-with-window', v ? 'yes' : 'no'); _saveSubPrefs(); },
    ),
    const SizedBox(height: RaddSpace.sm),
  ]);

  Widget _buildSyncTab() => ListView(padding: const EdgeInsets.all(20), children: [
    _secLabel('Synchronisation'),
    const Text('Shift subtitles earlier (−) or later (+) relative to audio',
        style: TextStyle(color: Colors.white38, fontSize: 11)),
    const SizedBox(height: 20),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _BigStepBtn(label: '−0.5s', onTap: () { setState(() => _sync -= 0.5); widget.onSyncChanged(-0.5); HapticFeedback.selectionClick(); }),
      const SizedBox(width: 6),
      _BigStepBtn(label: '−0.1s', onTap: () { setState(() => _sync -= 0.1); widget.onSyncChanged(-0.1); HapticFeedback.selectionClick(); }),
      const SizedBox(width: RaddSpace.md),
      Container(
        width: 76, height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Center(child: Text(
          '${_sync >= 0 ? '+' : ''}${_sync.toStringAsFixed(1)}s',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        )),
      ),
      const SizedBox(width: RaddSpace.md),
      _BigStepBtn(label: '+0.1s', onTap: () { setState(() => _sync += 0.1); widget.onSyncChanged(0.1); HapticFeedback.selectionClick(); }),
      const SizedBox(width: 6),
      _BigStepBtn(label: '+0.5s', onTap: () { setState(() => _sync += 0.5); widget.onSyncChanged(0.5); HapticFeedback.selectionClick(); }),
    ]),
    Center(child: TextButton(
      onPressed: () { final was = _sync; setState(() => _sync = 0); widget.onSyncChanged(-was); },
      child: const Text('Reset', style: TextStyle(color: Colors.white54, fontSize: 12)),
    )),
    const SizedBox(height: 20),
    const Divider(color: Colors.white12),
    const SizedBox(height: RaddSpace.md),
    _secLabel('Display Speed'),
    const Text('Adjust subtitle timing rate relative to video speed',
        style: TextStyle(color: Colors.white38, fontSize: 11)),
    const SizedBox(height: 20),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _BigStepBtn(label: '−10%', onTap: () { setState(() => _speed = (_speed - 0.1).clamp(0.5, 2.0)); widget.onSpeedChanged(_speed); HapticFeedback.selectionClick(); }),
      const SizedBox(width: RaddSpace.lg),
      Container(
        width: 76, height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Center(child: Text(
          '${(_speed * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        )),
      ),
      const SizedBox(width: RaddSpace.lg),
      _BigStepBtn(label: '+10%', onTap: () { setState(() => _speed = (_speed + 0.1).clamp(0.5, 2.0)); widget.onSpeedChanged(_speed); HapticFeedback.selectionClick(); }),
    ]),
    Center(child: TextButton(
      onPressed: () { setState(() => _speed = 1.0); widget.onSpeedChanged(1.0); },
      child: const Text('Reset to 100%', style: TextStyle(color: Colors.white54, fontSize: 12)),
    )),
  ]);

  Widget _buildOnlineTab() {
    if (widget.isLocal) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(RaddSpace.xl),
        child: Text('Online search is not available for local files.',
            style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
      ));
    }
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        Expanded(child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search by title…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            filled: true, fillColor: Colors.white10, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: RaddRadius.smRadius, borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                    onPressed: () => setState(() => _searchController.clear()),
                    padding: EdgeInsets.zero)
                : null,
          ),
          onSubmitted: (_) => _fetchOnlineSubtitles(context),
        )),
        const SizedBox(width: RaddSpace.sm),
        GestureDetector(
          onTap: _onlineLoading ? null : () => _fetchOnlineSubtitles(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _onlineLoading ? Colors.white12 : Colors.white24,
              borderRadius: RaddRadius.smRadius,
            ),
            child: _onlineLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Search', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final lang in [
            ('🇵🇰 Urdu', 'urd'), ('🇮🇳 Hindi', 'hin'), ('🇵🇰+🇮🇳', 'urd,hin'),
            ('🇬🇧 English', 'eng'), ('🇸🇦 Arabic', 'ara'), ('🌍 All', ''),
          ])
            GestureDetector(
              onTap: () { setState(() => _selectedLangCode = lang.$2); _fetchOnlineSubtitles(context); },
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _selectedLangCode == lang.$2 ? const Color(0xFF4A9EFF) : Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(lang.$1, style: TextStyle(
                  color: _selectedLangCode == lang.$2 ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: _selectedLangCode == lang.$2 ? FontWeight.w600 : FontWeight.normal,
                )),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (!_onlineLoading && _onlineError.isNotEmpty)
        Row(children: [
          Expanded(child: Text(_onlineError, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          TextButton(onPressed: () => _fetchOnlineSubtitles(context),
              child: const Text('Retry', style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 12))),
        ]),
      if (!_hasSearched && !_onlineLoading && _onlineError.isEmpty)
        const Text('Auto-searching… or tap Search.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      if (!_onlineLoading && _onlineResults.isNotEmpty) ...[
        Text('${_onlineResults.length} subtitles found:',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: RaddSpace.sm),
        for (final r in _onlineResults)
          GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); _downloadOnlineSubtitle(context, r); },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((r['SubFileName'] ?? '').replaceAll('.gz', ''),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: RaddSpace.xs),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A9EFF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text((r['LanguageName'] ?? r['SubLanguageID'] ?? '').toUpperCase(),
                          style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Text('↓ ${r['SubDownloadsCnt'] ?? '0'}  •  ⭐ ${double.tryParse(r['SubRating'] ?? '0')?.toStringAsFixed(1) ?? '-'}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ]),
                ])),
                const SizedBox(width: RaddSpace.sm),
                const Icon(Icons.download_rounded, color: Colors.white54, size: 20),
              ]),
            ),
          ),
      ],
      const SizedBox(height: RaddSpace.sm),
    ]);
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tabs = [
      'Tracks', 'Style', 'Position', 'Sync',
      if (!widget.isLocal) 'Online',
      if (widget.onDubRequested != null) 'AI Dub',
    ];
    final tabName = _tab < tabs.length ? tabs[_tab] : '';

    return Column(
      children: [
        // ── Tab bar (title provided by RaddSheet) ─────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              for (int i = 0; i < tabs.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, top: 8, bottom: 0),
                    child: Column(children: [
                      Text(tabs[i], style: TextStyle(
                        color: _tab == i ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: _tab == i ? FontWeight.w700 : FontWeight.normal,
                      )),
                      const SizedBox(height: 6),
                      if (_tab == i)
                        Container(height: 2, width: 28,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Divider(color: Colors.white12, height: 1),
        // ── Body ──────────────────────────────────────────────────────────────
        Expanded(child: switch (tabName) {
          'Tracks'   => _buildTracksTab(),
          'Style'    => _buildStyleTab(),
          'Position' => _buildPositionTab(),
          'Sync'     => _buildSyncTab(),
          'Online'   => _buildOnlineTab(),
          'AI Dub'   => ListView(padding: const EdgeInsets.all(14),
                            children: _buildDubSection(context)),
          _          => const SizedBox.shrink(),
        }),
      ],
    );
  }
}

// Subtitle track tile helper
class _SubTrackTile extends StatelessWidget {
  final SubtitleTrack? track;
  final int index;
  final String? label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  const _SubTrackTile({required this.track, required this.index,
      this.label, required this.selected, required this.accentColor,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final name = label
        ?? (track?.language != null && track?.title != null
            ? '${track!.language} — ${track!.title}'
            : track?.language ?? track?.title ?? 'Track ${index + 1}');
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: RaddRadius.smRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? accentColor : Colors.transparent,
              border: Border.all(
                color: selected ? accentColor : Colors.white38,
                width: selected ? 0 : 1.5,
              ),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.black, size: 13) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ))),
        ]),
      ),
    );
  }
}

// Sync / speed step button helper
class _BigStepBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BigStepBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: RaddRadius.smRadius,
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}


