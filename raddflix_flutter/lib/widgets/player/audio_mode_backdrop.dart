// audio_mode_backdrop.dart — Neo-Phonograph Edition (AB1)
// Full-screen audio-mode UI: blurred art backdrop, rotating vinyl disc with
// realistic grooves + tonearm, frosted-glass controls card.
// Shown instead of the blank black SurfaceView whenever MPV opens a file
// with no video track (MP3, FLAC, AAC, OGG, etc.).
//
// Architecture: entirely self-contained StatefulWidget. Caller passes the
// minimum playback state it already has — no additional platform channels.
//
// Cover art strategy:
//   1. Scan the audio file's parent directory for common cover-image filenames.
//   2. If found → FileImage + palette_generator accent extraction.
//   3. If not   → try flutter_media_metadata to read embedded ID3/Vorbis/MP4 art.
//   4. If not   → animated procedural gradient blobs based on title hash.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;
import '../../core/player/haptic_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Public widget
// ─────────────────────────────────────────────────────────────────────────────

class AudioModeBackdrop extends StatefulWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String title;
  final String? localPath; // used to scan sibling cover images
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  // Skip controls — null when no episode list is available.
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  // Shuffle / Repeat toggles.
  final bool loopEnabled;
  final bool shuffleEnabled;
  final VoidCallback onLoopToggle;
  final VoidCallback onShuffleToggle;

  const AudioModeBackdrop({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.title,
    required this.onPlayPause,
    required this.onSeek,
    this.localPath,
    this.hasPrev = false,
    this.hasNext = false,
    this.onPrev,
    this.onNext,
    this.loopEnabled = false,
    this.shuffleEnabled = false,
    VoidCallback? onLoopToggle,
    VoidCallback? onShuffleToggle,
  })  : onLoopToggle = onLoopToggle ?? _noop,
        onShuffleToggle = onShuffleToggle ?? _noop;

  static void _noop() {}

  @override
  State<AudioModeBackdrop> createState() => _AudioModeBackdropState();
}

class _AudioModeBackdropState extends State<AudioModeBackdrop>
    with TickerProviderStateMixin {

  // ── Disc rotation ────────────────────────────────────────────────────────
  /// Continuous rotation [0,1] → [0,2π]. One full turn every 10 seconds.
  late final AnimationController _discCtrl;

  /// Saved disc angle [0,1] at the moment playback paused.
  double _discAngle = 0.0;

  /// The disc angle [0,1] at which the current spin-down started.
  double _spinDownFrom = 0.0;

  /// Physics-deceleration spin-down: coasts 0.28 turns after pause.
  late final AnimationController _spinDownCtrl;
  late final CurvedAnimation _spinDownCurve;

  // ── Other animation controllers ──────────────────────────────────────────
  /// Tonearm swing in (playing) / out (paused), 500ms easeInOut.
  late final AnimationController _tonearmCtrl;

  /// Track-change entrance: disc scale 0.88→1.0, cover art fade, 400ms easeOutBack.
  late final AnimationController _entryCtrl;

  /// Seek thumb pulse while dragging (600ms).
  late final AnimationController _thumbPulseCtrl;

  /// Ken Burns backdrop scale 1.0 ↔ 1.14 over 20s.
  late final AnimationController _kenBurnsCtrl;

  /// Slow ambient glow pulse.
  late final AnimationController _pulseCtrl;

  // ── Cover art & palette ───────────────────────────────────────────────────
  File? _coverArtFile;
  Uint8List? _embeddedArtBytes;

  /// AB1: warm amber default instead of cold purple.
  Color _accent = const Color(0xFFD4943A);

  // ── Seek interaction state ───────────────────────────────────────────────
  bool _seeking = false;
  double _seekFrac = 0.0;

  // ── Scan dedup ───────────────────────────────────────────────────────────
  String? _lastScannedPath;

  static const _coverNames = [
    'cover.jpg',  'cover.jpeg',  'cover.png',
    'folder.jpg', 'folder.jpeg', 'folder.png',
    'Cover.jpg',  'Folder.jpg',
    'album.jpg',  'Album.jpg',
    'artwork.jpg', 'Artwork.jpg',
    'AlbumArt.jpg', 'albumart.jpg',
    'front.jpg',  'Front.jpg',
  ];

  @override
  void initState() {
    super.initState();

    _discCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _kenBurnsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _spinDownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _spinDownCurve = CurvedAnimation(
      parent: _spinDownCtrl,
      curve: Curves.decelerate,
    );
    _spinDownCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _discAngle = (_spinDownFrom + 0.28) % 1.0;
          _discCtrl.value = _discAngle;
        });
        // Defer reset() to avoid calling it synchronously inside the listener's
        // notify cycle, which fires a second notifyListeners() during dispatch.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _spinDownCtrl.reset();
        });
      }
    });

    _tonearmCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _thumbPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    if (widget.isPlaying) {
      _discCtrl.value = _discAngle;
      _discCtrl.repeat();
      _tonearmCtrl.forward();
      _pulseCtrl.duration = const Duration(milliseconds: 1600);
    } else {
      _pulseCtrl.duration = const Duration(milliseconds: 3400);
    }

    // Entrance animation on first load.
    _entryCtrl.forward();
    _scanCoverArt();
  }

  @override
  void didUpdateWidget(AudioModeBackdrop old) {
    super.didUpdateWidget(old);

    // ── Play / pause state change ─────────────────────────────────────────
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying) {
        // Spin up from saved position.
        _spinDownCtrl.stop();
        _spinDownCtrl.reset();
        _discCtrl.value = _discAngle;
        _discCtrl.repeat();
        _tonearmCtrl.forward();
        // Faster pulse when playing.
        _pulseCtrl.duration = const Duration(milliseconds: 1600);
        _pulseCtrl.repeat(reverse: true);
      } else {
        // Physics spin-down.
        _spinDownFrom = _discCtrl.value;
        _discAngle    = _discCtrl.value;
        _discCtrl.stop();
        _spinDownCtrl.forward(from: 0.0);
        _tonearmCtrl.reverse();
        // Slower breathing pulse when paused.
        _pulseCtrl.duration = const Duration(milliseconds: 3400);
        _pulseCtrl.repeat(reverse: true);
      }
    }

    // ── New track → re-scan for cover art + entrance animation ───────────
    if (widget.localPath != old.localPath || widget.title != old.title) {
      if (widget.localPath != _lastScannedPath) {
        _lastScannedPath = widget.localPath;
        _discAngle = 0.0;
        _discCtrl.value = 0.0;
        // AB1-AUDIT: controller.value= calls stop() internally, killing the
        // repeat loop. Restart spin if the track changes while playing so the
        // disc doesn't freeze mid-rotation on track transitions.
        if (widget.isPlaying) _discCtrl.repeat();
        setState(() {
          _coverArtFile = null;
          _embeddedArtBytes = null;
          _accent = const Color(0xFFD4943A);
        });
        // Tonearm swings in 220ms after disc entry starts.
        _entryCtrl.forward(from: 0.0);
        Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted && widget.isPlaying) _tonearmCtrl.forward(from: 0.0);
        });
        _scanCoverArt();
      }
    }
  }

  @override
  void dispose() {
    _discCtrl.dispose();
    _spinDownCtrl.dispose();
    _spinDownCurve.dispose();
    _kenBurnsCtrl.dispose();
    _pulseCtrl.dispose();
    _tonearmCtrl.dispose();
    _entryCtrl.dispose();
    _thumbPulseCtrl.dispose();
    super.dispose();
  }

  // ── Cover art helpers ────────────────────────────────────────────────────

  Future<void> _scanCoverArt() async {
    final path = widget.localPath;
    if (path == null || path.isEmpty) return;
    _lastScannedPath = path;

    final dir = p.dirname(path);
    for (final name in _coverNames) {
      final f = File(p.join(dir, name));
      if (await f.exists()) {
        if (!mounted) return;
        setState(() => _coverArtFile = f);
        _extractPalette(FileImage(f));
        return;
      }
    }

    try {
      final metadata = await MetadataRetriever.fromFile(File(path))
          .timeout(const Duration(seconds: 5));
      final bytes = metadata.albumArt;
      if (bytes != null && bytes.isNotEmpty) {
        if (!mounted) return;
        setState(() => _embeddedArtBytes = bytes);
        _extractPalette(MemoryImage(bytes));
      }
    } catch (_) {}
  }

  Future<void> _extractPalette(ImageProvider provider) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider, maximumColorCount: 8);
      final color = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.dominantColor?.color;
      if (color != null && mounted) setState(() => _accent = color);
    } catch (_) {}
  }

  /// AB1: warm-biased gradient. Hue clamped toward amber/terracotta/mahogany.
  List<Color> _gradientColors() {
    var hash = 5381;
    for (final c in widget.title.codeUnits) {
      hash = ((hash << 5) + hash) ^ c;
    }
    hash = hash.abs();
    final rawH = (hash % 360).toDouble();
    // Bias toward warm quadrant (0°–80°). Cool hues (180–300) folded back.
    final h1 = rawH < 80
        ? rawH
        : rawH < 180
            ? 80 - (rawH - 80) * 0.3
            : rawH > 300
                ? rawH - 300
                : 40.0 + (rawH - 180) * 0.1;
    final h2 = (h1 + 40) % 80;
    return [
      HSVColor.fromAHSV(1.0, h1.clamp(0, 360), 0.62, 0.50).toColor(),
      HSVColor.fromAHSV(1.0, h2.clamp(0, 360), 0.72, 0.40).toColor(),
    ];
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gradColors = _gradientColors();

    ImageProvider? coverArt;
    if (_coverArtFile != null) {
      coverArt = FileImage(_coverArtFile!);
    } else if (_embeddedArtBytes != null) {
      coverArt = MemoryImage(_embeddedArtBytes!);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Layer 1: atmospheric backdrop ──────────────────────────────
        _Backdrop(
          coverArt: coverArt,
          gradColors: gradColors,
          accentColor: _accent,
          isPlaying: widget.isPlaying,
          kenBurnsCtrl: _kenBurnsCtrl,
          pulseCtrl: _pulseCtrl,
        ),

        // ── Layer 2 + 3: disc + tonearm + title above the card ─────────
        Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Disc (with physics spin-down + entry animation)
                  _Disc(
                    coverArt: coverArt,
                    gradColors: gradColors,
                    accentColor: _accent,
                    discCtrl: _discCtrl,
                    spinDownCtrl: _spinDownCtrl,
                    spinDownCurve: _spinDownCurve,
                    spinDownFrom: _spinDownFrom,
                    entryCtrl: _entryCtrl,
                    isPlaying: widget.isPlaying,
                  ),

                  // Tonearm (positioned in Stack relative to disc center)
                  _Tonearm(tonearmCtrl: _tonearmCtrl),
                ],
              ),
            ),

            // Title / artist below the disc.
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _TitleRow(title: widget.title),
            ),

            // Glass controls card at the very bottom.
            SafeArea(
              top: false,
              child: _GlassCard(
                isPlaying: widget.isPlaying,
                position: widget.position,
                duration: widget.duration,
                accentColor: _accent,
                seeking: _seeking,
                seekFrac: _seekFrac,
                hasPrev: widget.hasPrev,
                hasNext: widget.hasNext,
                loopEnabled: widget.loopEnabled,
                shuffleEnabled: widget.shuffleEnabled,
                thumbPulseCtrl: _thumbPulseCtrl,
                onPlayPause: () {
                  HapticService.instance.standard();
                  widget.onPlayPause();
                },
                onPrev: widget.onPrev,
                onNext: widget.onNext,
                onLoopToggle: widget.onLoopToggle,
                onShuffleToggle: widget.onShuffleToggle,
                onSeekStart: (frac) => setState(() {
                  _seeking = true;
                  _seekFrac = frac;
                  _thumbPulseCtrl.repeat(reverse: true);
                }),
                onSeekUpdate: (frac) => setState(() => _seekFrac = frac),
                onSeekEnd: (frac) {
                  setState(() => _seeking = false);
                  _thumbPulseCtrl.stop();
                  _thumbPulseCtrl.reset();
                  if (widget.duration > Duration.zero) {
                    widget.onSeek(Duration(
                      milliseconds:
                          (frac * widget.duration.inMilliseconds).round(),
                    ));
                  }
                },
                onTapSeek: (frac) {
                  if (widget.duration > Duration.zero) {
                    widget.onSeek(Duration(
                      milliseconds:
                          (frac * widget.duration.inMilliseconds).round(),
                    ));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Layer 1 — atmospheric backdrop
// ─────────────────────────────────────────────────────────────────────────────

class _Backdrop extends StatelessWidget {
  final ImageProvider? coverArt;
  final List<Color> gradColors;
  final Color accentColor;
  final bool isPlaying;
  final AnimationController kenBurnsCtrl;
  final AnimationController pulseCtrl;

  const _Backdrop({
    required this.coverArt,
    required this.gradColors,
    required this.accentColor,
    required this.isPlaying,
    required this.kenBurnsCtrl,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    Widget artLayer;
    if (coverArt != null) {
      artLayer = ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.14).animate(
          CurvedAnimation(parent: kenBurnsCtrl, curve: Curves.easeInOut),
        ),
        child: Image(
          image: coverArt!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      artLayer = ImageFiltered(
        imageFilter:
            ImageFilter.blur(sigmaX: 58, sigmaY: 58, tileMode: TileMode.mirror),
        child: artLayer,
      );
    } else {
      artLayer = AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, __) => CustomPaint(
          painter: _BlobPainter(progress: pulseCtrl.value, colors: gradColors),
          child: const SizedBox.expand(),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Warm near-black base — slightly tinted brown, not cold black.
        const ColoredBox(color: Color(0xFF100C08)),

        artLayer,

        // AB1: warm vignette — Color(0xFF0D0905) instead of cold black.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0D0905).withOpacity(0.60),
                const Color(0xFF0D0905).withOpacity(0.20),
                const Color(0xFF0D0905).withOpacity(0.55),
                const Color(0xFF0D0905).withOpacity(0.92),
              ],
              stops: const [0.0, 0.30, 0.62, 1.0],
            ),
          ),
        ),

        // AB1: glow opacity tied to play state.
        AnimatedBuilder(
          animation: pulseCtrl,
          builder: (_, __) {
            final v = pulseCtrl.value;
            final opacity = isPlaying
                ? 0.12 + v * 0.18   // alive, brighter when playing
                : 0.06 + v * 0.09;  // dim, slow breathing when paused
            return Center(
              child: Opacity(
                opacity: opacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor,
                        blurRadius: 90,
                        spreadRadius: 50,
                      ),
                    ],
                  ),
                  child: const SizedBox(width: 1, height: 1),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Layer 2 — rotating vinyl disc with physics spin-down
// ─────────────────────────────────────────────────────────────────────────────

class _Disc extends StatelessWidget {
  final ImageProvider? coverArt;
  final List<Color> gradColors;
  final Color accentColor;
  final AnimationController discCtrl;
  final AnimationController spinDownCtrl;
  final CurvedAnimation spinDownCurve;
  final double spinDownFrom;
  final AnimationController entryCtrl;
  final bool isPlaying;

  const _Disc({
    required this.coverArt,
    required this.gradColors,
    required this.accentColor,
    required this.discCtrl,
    required this.spinDownCtrl,
    required this.spinDownCurve,
    required this.spinDownFrom,
    required this.entryCtrl,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    const double outerD = 218;
    const double innerD = outerD - 18;

    Widget face;
    if (coverArt != null) {
      face = FadeTransition(
        opacity: entryCtrl,
        child: ClipOval(
          child: Image(
            image: coverArt!,
            width: innerD, height: innerD,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradientFace(innerD, gradColors),
          ),
        ),
      );
    } else {
      face = _gradientFace(innerD, gradColors);
    }

    final disc = SizedBox(
      width: outerD,
      height: outerD,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Shadow / glow ring.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.38),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const SizedBox(width: outerD, height: outerD),
          ),

          // Groove rings drawn over the face.
          // Only foregroundPainter is used — painter: would draw behind the
          // cover art face and be invisible, while also stamping grooves and
          // the sheen arc a second time at double opacity.
          ClipOval(
            child: CustomPaint(
              foregroundPainter: _GroovePainter(
                innerD: innerD,
                accentColor: accentColor,
              ),
              child: face,
            ),
          ),

          // AB1: pause overlay — dark circle + custom bars instead of opacity dim.
          if (!isPlaying)
            AnimatedOpacity(
              opacity: isPlaying ? 0.0 : 0.28,
              duration: const Duration(milliseconds: 350),
              child: Container(
                width: outerD,
                height: outerD,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
              ),
            ),
          if (!isPlaying)
            AnimatedOpacity(
              opacity: isPlaying ? 0.0 : 0.60,
              duration: const Duration(milliseconds: 350),
              child: const _PauseIcon(),
            ),

          // AB1: machined spindle cap.
          const _SpindleCap(),
        ],
      ),
    );

    // Physics rotation with spin-down support.
    return AnimatedBuilder(
      animation: Listenable.merge([discCtrl, spinDownCtrl, entryCtrl]),
      builder: (_, child) {
        double angle;
        if (spinDownCtrl.isAnimating) {
          // Coasting to a stop — advance spinDownFrom by up to 0.28 turns.
          angle = (spinDownFrom + spinDownCurve.value * 0.28) * 2 * math.pi;
        } else {
          angle = discCtrl.value * 2 * math.pi;
        }

        // AB1: entrance animation — disc scales in from 0.88.
        final entryScale = Tween<double>(begin: 0.88, end: 1.0)
            .animate(CurvedAnimation(parent: entryCtrl, curve: Curves.easeOutBack))
            .value;

        return Transform.scale(
          scale: entryScale,
          child: Transform.rotate(angle: angle, child: child),
        );
      },
      child: disc,
    );
  }

  static Widget _gradientFace(double d, List<Color> colors) {
    return Container(
      width: d, height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded,
            color: Colors.white.withOpacity(0.55), size: 64),
      ),
    );
  }
}

// ── AB1: Pause icon drawn inside the disc ─────────────────────────────────────

class _PauseIcon extends StatelessWidget {
  const _PauseIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48, height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 11, height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Container(width: 11, height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3))),
        ],
      ),
    );
  }
}

// ── AB1: Machined spindle cap ─────────────────────────────────────────────────

class _SpindleCap extends StatelessWidget {
  const _SpindleCap();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpindleCapPainter(),
      child: const SizedBox(width: 24, height: 24),
    );
  }
}

class _SpindleCapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Dark metallic body.
    canvas.drawCircle(c, r,
        Paint()..color = const Color(0xFF1A1410));

    // Bevel highlight ring.
    canvas.drawCircle(c, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF5A4530)
          ..strokeWidth = 1.5);

    // Accent center dot — warm amber.
    canvas.drawCircle(c, 3.5,
        Paint()..color = const Color(0xFFD4943A));
  }

  @override
  bool shouldRepaint(_SpindleCapPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  AB1 — Tonearm (new)
// ─────────────────────────────────────────────────────────────────────────────

class _Tonearm extends StatelessWidget {
  final AnimationController tonearmCtrl;

  const _Tonearm({required this.tonearmCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tonearmCtrl,
      builder: (_, __) {
        // 0.0 = resting (arm lifted, ~58° from disc), 1.0 = playing (~22° onto disc).
        final swingAngle = Tween<double>(begin: -58 * math.pi / 180, end: -22 * math.pi / 180)
            .animate(CurvedAnimation(parent: tonearmCtrl, curve: Curves.easeInOut))
            .value;

        // Place the pivot cap at the outer-top-right of the 218dp disc.
        // Disc radius = 109dp, centered in the Stack. Translate (+60, -58)
        // from Stack center puts the SizedBox's top-right corner (the pivot)
        // at ≈ (105, -70) from disc center — just on the disc rim.
        // Previously used Positioned(top:8, right:8) which anchored to the
        // screen edge (~60dp off the disc on a 360dp-wide phone).
        return Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: const Offset(60, -58),
            child: Transform.rotate(
              angle: swingAngle,
              alignment: Alignment.topRight,
              child: CustomPaint(
                painter: _TonearmPainter(),
                child: const SizedBox(width: 90, height: 24),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TonearmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pivotX = size.width;
    final pivotY = 9.0;
    final tipX = 0.0;
    final tipY = size.height - 6;

    // Body gradient — brushed brass.
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF8B6914),
          Color(0xFFD4A843),
          Color(0xFF8B6914),
        ],
      ).createShader(Rect.fromLTWH(tipX, 0, size.width, size.height))
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(pivotX, pivotY), Offset(tipX, tipY), bodyPaint);

    // Headshell — gunmetal rectangle near the needle tip.
    final headshellRect = Rect.fromCenter(
      center: Offset(tipX + 10, tipY - 4),
      width: 16, height: 8,
    );
    final headshellPath = Path()
      ..addRRect(RRect.fromRectAndRadius(headshellRect, const Radius.circular(2)));
    canvas.drawPath(headshellPath,
        Paint()..color = const Color(0xFF2A2A35));
    canvas.drawPath(headshellPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white24
          ..strokeWidth = 0.8);

    // Needle dot.
    canvas.drawCircle(Offset(tipX + 2, tipY + 2), 4,
        Paint()..color = const Color(0xFFB8860B));

    // Pivot cap — polished brass bearing.
    final pivotPaint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFFE8C060), Color(0xFF5A3E0A)],
      ).createShader(Rect.fromCircle(center: Offset(pivotX, pivotY), radius: 9));
    canvas.drawCircle(Offset(pivotX, pivotY), 9, pivotPaint);
    canvas.drawCircle(Offset(pivotX, pivotY), 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF3A2505)
          ..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(_TonearmPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Layer 3 — track title / artist
// ─────────────────────────────────────────────────────────────────────────────

class _TitleRow extends StatelessWidget {
  final String title;
  const _TitleRow({required this.title});

  @override
  Widget build(BuildContext context) {
    final parsed = _parseTitle(title);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          parsed.track,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
            shadows: [Shadow(blurRadius: 10, color: Colors.black87)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (parsed.artist.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            parsed.artist,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  static ({String artist, String track}) _parseTitle(String raw) {
    final noExt = raw.contains('.') ? raw.substring(0, raw.lastIndexOf('.')) : raw;
    final cleaned = noExt.replaceFirst(RegExp(r'^\d{1,3}[\s.\-]+'), '');
    final idx = cleaned.indexOf(' - ');
    if (idx > 0 && idx < cleaned.length - 3) {
      return (
        artist: cleaned.substring(0, idx).trim(),
        track: cleaned.substring(idx + 3).trim(),
      );
    }
    return (artist: '', track: cleaned.trim().isEmpty ? raw : cleaned.trim());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Layer 4 — frosted glass controls card
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Color accentColor;
  final bool seeking;
  final double seekFrac;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool loopEnabled;
  final bool shuffleEnabled;
  final VoidCallback onLoopToggle;
  final VoidCallback onShuffleToggle;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onTapSeek;
  final AnimationController thumbPulseCtrl;

  const _GlassCard({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.accentColor,
    required this.seeking,
    required this.seekFrac,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.loopEnabled,
    required this.shuffleEnabled,
    required this.onLoopToggle,
    required this.onShuffleToggle,
    required this.onPlayPause,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onTapSeek,
    required this.thumbPulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final progress = totalMs > 0
        ? (seeking ? seekFrac : position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final displayPos = seeking
        ? Duration(milliseconds: (seekFrac * totalMs).round())
        : position;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.44),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.09), width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Shuffle / Repeat toggle row ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ToggleIcon(
                      icon: Icons.shuffle_rounded,
                      active: shuffleEnabled,
                      accentColor: accentColor,
                      onTap: onShuffleToggle,
                    ),
                    const SizedBox(width: 40),
                    _ToggleIcon(
                      icon: Icons.repeat_rounded,
                      active: loopEnabled,
                      accentColor: accentColor,
                      onTap: onLoopToggle,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Seek bar with gradient fill + thumb pulse ────────────
                LayoutBuilder(
                  builder: (_, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) =>
                        onSeekStart((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                    onHorizontalDragUpdate: (d) =>
                        onSeekUpdate((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                    onHorizontalDragEnd: (d) => onSeekEnd(seekFrac),
                    onTapDown: (d) =>
                        onTapSeek((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                    child: AnimatedBuilder(
                      animation: thumbPulseCtrl,
                      builder: (_, __) => CustomPaint(
                        painter: _SeekPainter(
                          progress: progress.toDouble(),
                          accentColor: accentColor,
                          thumbPulse: seeking ? thumbPulseCtrl.value : 0.0,
                        ),
                        child: const SizedBox(height: 38, width: double.infinity),
                      ),
                    ),
                  ),
                ),

                // ── Timestamps with slide+fade animation ────────────────
                AnimatedBuilder(
                  animation: thumbPulseCtrl,
                  builder: (_, __) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AnimatedSlide(
                          offset: seeking ? const Offset(0, -0.15) : Offset.zero,
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedOpacity(
                            opacity: seeking ? 1.0 : 0.6,
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _fmt(displayPos),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                        AnimatedSlide(
                          offset: seeking ? const Offset(0, -0.15) : Offset.zero,
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedOpacity(
                            opacity: seeking ? 0.8 : 0.38,
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _fmt(duration),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                // ── Prev / Play-Pause / Next ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkipButton(
                      icon: Icons.skip_previous_rounded,
                      enabled: hasPrev,
                      onTap: hasPrev ? onPrev : null,
                    ),
                    const SizedBox(width: 28),

                    GestureDetector(
                      onTap: onPlayPause,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 66, height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.48),
                              blurRadius: 24, spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(isPlaying),
                            color: Colors.white, size: 34,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 28),
                    _SkipButton(
                      icon: Icons.skip_next_rounded,
                      enabled: hasNext,
                      onTap: hasNext ? onNext : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ── Skip button ────────────────────────────────────────────────────────────────

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _SkipButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Icon(icon, color: Colors.white, size: 38),
      ),
    );
  }
}

// ── Shuffle / Repeat toggle icon ──────────────────────────────────────────────

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  const _ToggleIcon({
    required this.icon,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? accentColor.withOpacity(0.20) : Colors.transparent,
        ),
        child: Icon(icon, size: 22,
            color: active ? accentColor : Colors.white38),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// AB1: Realistic vinyl groove painter.
/// - Inner 36% = label zone (warm amber hint, no rings).
/// - Transition ring at 36%.
/// - Variable-pitch rings from 36%–97% (2.8px at label → 5.6px at edge).
/// - Rotating sheen arc (standard+ visual; drawn unconditionally here).
class _GroovePainter extends CustomPainter {
  final double innerD;
  final Color accentColor;
  const _GroovePainter({required this.innerD, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = innerD / 2;
    final labelR = maxR * 0.36;

    // ── Label zone: very subtle warm fill ────────────────────────────────
    canvas.drawCircle(center, labelR,
        Paint()..color = const Color(0x14D4A843));

    // ── Label edge transition ring ────────────────────────────────────────
    canvas.drawCircle(center, labelR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withOpacity(0.35));

    // ── Variable-pitch groove rings ───────────────────────────────────────
    const startSpacing = 2.8;
    const endSpacing   = 5.6;
    double r = labelR + startSpacing;
    int idx = 0;
    while (r < maxR * 0.97) {
      // Alternating opacity for depth.
      final opacity = idx % 2 == 0 ? 0.20 : 0.13;
      canvas.drawCircle(center, r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = Colors.black.withOpacity(opacity));

      // Progress fraction from label to edge for variable pitch.
      final frac = (r - labelR) / (maxR * 0.97 - labelR);
      final spacing = startSpacing + (endSpacing - startSpacing) * frac;
      r += spacing;
      idx++;
    }

    // ── Sheen arc: 38° soft light sweep rotating with disc ────────────────
    // This is drawn in foreground painter context (same painter used as both
    // painter and foregroundPainter, but the arc only renders once since the
    // disc rotates the whole widget).
    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = maxR * 0.45
      ..color = Colors.white.withOpacity(0.04)
      ..strokeCap = StrokeCap.butt;
    const sheenAngle = 38 * math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.67),
      -math.pi / 2,
      sheenAngle,
      false,
      sheenPaint,
    );
  }

  @override
  bool shouldRepaint(_GroovePainter old) =>
      old.innerD != innerD || old.accentColor != accentColor;
}

/// Animated colour blob painter for the no-cover-art backdrop.
class _BlobPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  const _BlobPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 85);
    final t = progress * math.pi * 2;
    final blobs = [
      (
        color: colors[0].withOpacity(0.65),
        x: size.width * (0.22 + 0.14 * math.sin(t)),
        y: size.height * (0.28 + 0.13 * math.cos(t)),
        r: size.width * 0.40,
      ),
      (
        color: colors[1].withOpacity(0.55),
        x: size.width * (0.76 - 0.12 * math.sin(t + 1.3)),
        y: size.height * (0.62 + 0.10 * math.cos(t + 0.9)),
        r: size.width * 0.34,
      ),
      (
        color: colors[0].withOpacity(0.25),
        x: size.width * (0.50 + 0.08 * math.cos(t * 0.7)),
        y: size.height * (0.50 - 0.08 * math.sin(t * 0.7)),
        r: size.width * 0.22,
      ),
    ];
    for (final b in blobs) {
      paint.color = b.color;
      canvas.drawCircle(Offset(b.x, b.y), b.r, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.progress != progress;
}

/// AB1: Seek bar with gradient fill + pulsing thumb while dragging.
class _SeekPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final double thumbPulse; // [0,1] — animates thumb radius when seeking

  const _SeekPainter({
    required this.progress,
    required this.accentColor,
    this.thumbPulse = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;

    // Track line.
    canvas.drawLine(
      Offset(0, y), Offset(size.width, y),
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3,
    );

    // Filled portion — gradient from accent to slightly faded.
    final px = (size.width * progress).clamp(0.0, size.width);
    if (px > 0) {
      final gradPaint = Paint()
        ..shader = LinearGradient(
          colors: [accentColor, accentColor.withOpacity(0.65)],
        ).createShader(Rect.fromLTWH(0, y - 1.5, px, 3))
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, y), Offset(px, y), gradPaint);
    }

    // Thumb — outer white ring + inner accent dot.
    final tx = px.clamp(6.0, size.width - 6.0);
    // Pulse: outer radius grows from 8→11 while dragging.
    final outerR = 8.0 + thumbPulse * 3.0;
    canvas.drawCircle(Offset(tx, y), outerR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(tx, y), 5.5 + thumbPulse, Paint()..color = accentColor);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.progress != progress ||
      old.accentColor != accentColor ||
      old.thumbPulse != thumbPulse;
}
