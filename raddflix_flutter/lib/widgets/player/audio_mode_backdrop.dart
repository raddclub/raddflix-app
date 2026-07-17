// audio_mode_backdrop.dart
// Full-screen audio-mode UI: blurred art backdrop, rotating vinyl disc,
// glass controls card. Shown instead of the blank black SurfaceView whenever
// MPV opens a file with no video track (MP3, FLAC, AAC, OGG, etc.).
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
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;

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
    // skip / shuffle / repeat — safe defaults so existing callers compile:
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
  // ── Animation controllers ────────────────────────────────────────────────
  /// Disc rotation — one full turn every 10 seconds while playing.
  late final AnimationController _discCtrl;
  /// Ken Burns backdrop scale 1.0 ↔ 1.12 over 20 s.
  late final AnimationController _kenBurnsCtrl;
  /// Slow ambient glow pulse — backdrop breathing effect.
  late final AnimationController _pulseCtrl;

  // ── Cover art & palette ───────────────────────────────────────────────────
  File? _coverArtFile;           // sidecar image file
  Uint8List? _embeddedArtBytes;  // embedded ID3 / Vorbis / MP4 art
  Color _accent = const Color(0xFF7C5CFF); // default purple; overridden by palette

  // ── Seek interaction state ───────────────────────────────────────────────
  bool _seeking = false;
  double _seekFrac = 0.0; // [0.0, 1.0] while dragging

  // ── Scan dedup ───────────────────────────────────────────────────────────
  String? _lastScannedPath;

  // ── Static cover-image filenames to probe ────────────────────────────────
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
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    if (widget.isPlaying) _discCtrl.repeat();
    _scanCoverArt();
  }

  @override
  void didUpdateWidget(AudioModeBackdrop old) {
    super.didUpdateWidget(old);
    // Play / pause → spin or freeze the disc.
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying) {
        _discCtrl.repeat();
      } else {
        _discCtrl.stop();
      }
    }
    // New track → re-scan for cover art.
    if (widget.localPath != old.localPath || widget.title != old.title) {
      if (widget.localPath != _lastScannedPath) {
        // Stamp _lastScannedPath immediately (not inside _scanCoverArt) so
        // rapid didUpdateWidget calls during a rebuild storm don't fire
        // multiple concurrent scans for the same path.
        _lastScannedPath = widget.localPath;
        setState(() {
          _coverArtFile = null;
          _embeddedArtBytes = null;
        });
        _scanCoverArt();
      }
    }
  }

  @override
  void dispose() {
    _discCtrl.dispose();
    _kenBurnsCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Cover art helpers ────────────────────────────────────────────────────

  Future<void> _scanCoverArt() async {
    final path = widget.localPath;
    if (path == null || path.isEmpty) return;
    _lastScannedPath = path;

    // 1. Probe sibling cover image files.
    final dir = p.dirname(path);
    for (final name in _coverNames) {
      final f = File(p.join(dir, name));
      if (await f.exists()) {
        if (!mounted) return;
        setState(() => _coverArtFile = f);
        _extractPalette(FileImage(f));
        return; // sidecar found — no need for embedded extraction
      }
    }

    // 2. Fall back to embedded ID3 / Vorbis / MP4 tags.
    //    Timeout guards against MetadataRetriever hanging on corrupt/very large files.
    try {
      final metadata = await MetadataRetriever.fromFile(File(path))
          .timeout(const Duration(seconds: 5));
      final bytes = metadata.albumArt;
      if (bytes != null && bytes.isNotEmpty) {
        if (!mounted) return;
        setState(() => _embeddedArtBytes = bytes);
        _extractPalette(MemoryImage(bytes));
      }
    } catch (_) {
      // Covers: unsupported format, platform limitation, timeout on corrupt file.
      // Fall through to procedural gradient blobs — already the default.
    }
  }

  Future<void> _extractPalette(ImageProvider provider) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 8,
      );
      final color = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.dominantColor?.color;
      if (color != null && mounted) setState(() => _accent = color);
    } catch (_) {}
  }

  /// Two deterministic gradient colours derived from the title string.
  /// Makes each track feel visually distinct when there's no cover art.
  List<Color> _gradientColors() {
    var hash = 5381;
    for (final c in widget.title.codeUnits) {
      hash = ((hash << 5) + hash) ^ c;
    }
    hash = hash.abs();
    final h1 = (hash % 360).toDouble();
    final h2 = (h1 + 145) % 360;
    return [
      HSVColor.fromAHSV(1.0, h1, 0.65, 0.55).toColor(),
      HSVColor.fromAHSV(1.0, h2, 0.78, 0.42).toColor(),
    ];
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gradColors = _gradientColors();

    // Resolved cover art provider: sidecar > embedded > null (procedural blobs).
    // Use explicit if/else — nested ternary confuses Dart's type inference
    // when both branches return different ImageProvider subtypes.
    ImageProvider? coverArt;
    if (_coverArtFile != null) {
      coverArt = FileImage(_coverArtFile!);
    } else if (_embeddedArtBytes != null) {
      coverArt = MemoryImage(_embeddedArtBytes!);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Layer 1: atmospheric backdrop ────────────────────────────────
        _Backdrop(
          coverArt: coverArt,
          gradColors: gradColors,
          accentColor: _accent,
          kenBurnsCtrl: _kenBurnsCtrl,
          pulseCtrl: _pulseCtrl,
        ),

        // ── Layer 2 + 3: disc + title in the upper area ───────────────
        Column(
          children: [
            // Disc — expands to fill available vertical space above the card.
            Expanded(
              child: Center(
                child: _Disc(
                  coverArt: coverArt,
                  gradColors: gradColors,
                  accentColor: _accent,
                  discCtrl: _discCtrl,
                  isPlaying: widget.isPlaying,
                ),
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
                onPlayPause: widget.onPlayPause,
                onPrev: widget.onPrev,
                onNext: widget.onNext,
                onLoopToggle: widget.onLoopToggle,
                onShuffleToggle: widget.onShuffleToggle,
                onSeekStart: (frac) => setState(() {
                  _seeking = true;
                  _seekFrac = frac;
                }),
                onSeekUpdate: (frac) => setState(() => _seekFrac = frac),
                onSeekEnd: (frac) {
                  setState(() => _seeking = false);
                  if (widget.duration > Duration.zero) {
                    widget.onSeek(Duration(
                      milliseconds: (frac * widget.duration.inMilliseconds).round(),
                    ));
                  }
                },
                onTapSeek: (frac) {
                  if (widget.duration > Duration.zero) {
                    widget.onSeek(Duration(
                      milliseconds: (frac * widget.duration.inMilliseconds).round(),
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
  final AnimationController kenBurnsCtrl;
  final AnimationController pulseCtrl;

  const _Backdrop({
    required this.coverArt,
    required this.gradColors,
    required this.accentColor,
    required this.kenBurnsCtrl,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    Widget artLayer;
    if (coverArt != null) {
      // Cover art: Ken Burns scale + heavy Gaussian blur.
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
        imageFilter: ImageFilter.blur(sigmaX: 58, sigmaY: 58, tileMode: TileMode.mirror),
        child: artLayer,
      );
    } else {
      // No cover art: animated colour blobs — still beautiful.
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
        // Near-black base so any bleed areas are consistent.
        const ColoredBox(color: Color(0xFF07090F)),

        // Art or animated blobs.
        artLayer,

        // Vignette gradient — darkens top and bottom for readability.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.60),
                Colors.black.withOpacity(0.20),
                Colors.black.withOpacity(0.55),
                Colors.black.withOpacity(0.92),
              ],
              stops: const [0.0, 0.30, 0.62, 1.0],
            ),
          ),
        ),

        // Subtle glow orb behind the disc (accent colour breathing).
        AnimatedBuilder(
          animation: pulseCtrl,
          builder: (_, __) => Center(
            child: Opacity(
              opacity: 0.10 + pulseCtrl.value * 0.12,
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
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Layer 2 — rotating vinyl disc
// ─────────────────────────────────────────────────────────────────────────────

class _Disc extends StatelessWidget {
  final ImageProvider? coverArt;
  final List<Color> gradColors;
  final Color accentColor;
  final AnimationController discCtrl;
  final bool isPlaying;

  const _Disc({
    required this.coverArt,
    required this.gradColors,
    required this.accentColor,
    required this.discCtrl,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    const double outerD = 218;
    const double innerD = outerD - 18; // slight border ring

    // Disc face: cover art or gradient with music note.
    Widget face;
    if (coverArt != null) {
      face = ClipOval(
        child: Image(
          image: coverArt!,
          width: innerD, height: innerD,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _gradientFace(innerD, gradColors),
        ),
      );
    } else {
      face = _gradientFace(innerD, gradColors);
    }

    // Outer ring + groove lines + face + centre hole.
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
                  spreadRadius: 0,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const SizedBox(width: outerD, height: outerD),
          ),

          // Groove rings drawn over the face.
          ClipOval(
            child: CustomPaint(
              painter: _GroovePainter(innerD: innerD),
              foregroundPainter: _GroovePainter(innerD: innerD),
              child: face,
            ),
          ),

          // Centre spindle hole.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B0D14),
              border: Border.all(color: Colors.white12, width: 1.2),
            ),
            child: const SizedBox(width: 22, height: 22),
          ),
        ],
      ),
    );

    // Apply rotation + pause-dim together.
    return AnimatedBuilder(
      animation: discCtrl,
      builder: (_, child) => Transform.rotate(
        angle: discCtrl.value * 2 * math.pi,
        child: child,
      ),
      child: AnimatedOpacity(
        opacity: isPlaying ? 1.0 : 0.70,
        duration: const Duration(milliseconds: 350),
        child: disc,
      ),
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

  /// Parses "Artist - Track.mp3" → ({artist: 'Artist', track: 'Track'}).
  /// Falls back gracefully when there's no separator.
  static ({String artist, String track}) _parseTitle(String raw) {
    // Strip file extension.
    final noExt = raw.contains('.') ? raw.substring(0, raw.lastIndexOf('.')) : raw;
    // Strip leading track number: "01 - ", "01. ", "1 " etc.
    final cleaned = noExt.replaceFirst(RegExp(r'^\d{1,3}[\s.\-]+'), '');
    // Split on " - " separator.
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

  // Skip controls.
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  // Shuffle / repeat.
  final bool loopEnabled;
  final bool shuffleEnabled;
  final VoidCallback onLoopToggle;
  final VoidCallback onShuffleToggle;

  // Seek callbacks.
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onTapSeek;

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
                // ── Shuffle / Repeat toggle row ────────────────────────────
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

                // ── Seek bar ───────────────────────────────────────────────
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
                    child: CustomPaint(
                      painter: _SeekPainter(
                        progress: progress.toDouble(),
                        accentColor: accentColor,
                      ),
                      child: const SizedBox(height: 38, width: double.infinity),
                    ),
                  ),
                ),

                // ── Timestamps ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(displayPos),
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    Text(
                      _fmt(duration),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Prev / Play-Pause / Next ───────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Prev button.
                    _SkipButton(
                      icon: Icons.skip_previous_rounded,
                      enabled: hasPrev,
                      onTap: hasPrev ? onPrev : null,
                    ),

                    const SizedBox(width: 28),

                    // Play / Pause button (accent-coloured circle).
                    GestureDetector(
                      onTap: onPlayPause,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.48),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(isPlaying),
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 28),

                    // Next button.
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

// ── Skip button (prev / next) ─────────────────────────────────────────────────

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
        child: Icon(
          icon,
          size: 22,
          color: active ? accentColor : Colors.white38,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// Vinyl groove concentric rings drawn over the disc face.
class _GroovePainter extends CustomPainter {
  final double innerD;
  const _GroovePainter({required this.innerD});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = innerD / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withOpacity(0.22);
    for (double r = maxR * 0.35; r < maxR * 0.97; r += 4.8) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_GroovePainter old) => old.innerD != innerD;
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

/// Clean seek bar: track line + filled progress + thumb dot.
class _SeekPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  const _SeekPainter({required this.progress, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    // Track.
    canvas.drawLine(
      Offset(0, y), Offset(size.width, y),
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3,
    );
    // Filled portion.
    final px = (size.width * progress).clamp(0.0, size.width);
    if (px > 0) {
      canvas.drawLine(
        Offset(0, y), Offset(px, y),
        Paint()
          ..color = accentColor
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3,
      );
    }
    // Thumb.
    final tx = px.clamp(6.0, size.width - 6.0);
    canvas.drawCircle(Offset(tx, y), 8, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(tx, y), 5.5, Paint()..color = accentColor);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.progress != progress || old.accentColor != accentColor;
}
