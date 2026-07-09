import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Applies one of 5 background styles behind the player controls overlay.
/// Wraps any child in the chosen visual treatment.
class ControlsBackground extends StatelessWidget {
  final String style;      // 'none' | 'glass' | 'gradient' | 'solid' | 'mesh'
  final Color accentColor;
  final Widget child;

  const ControlsBackground({
    super.key,
    required this.style,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 'glass':
        return _GlassBg(accentColor: accentColor, child: child);
      case 'gradient':
        return _GradientBg(accentColor: accentColor, child: child);
      case 'solid':
        return _SolidBg(child: child);
      case 'mesh':
        return _MeshBg(accentColor: accentColor, child: child);
      case 'none':
      default:
        return child;
    }
  }
}

// ── Glass (frosted blur) ─────────────────────────────────────────────────────
class _GlassBg extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  const _GlassBg({required this.accentColor, required this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          border: Border.all(color: accentColor.withOpacity(0.12), width: 0.5),
        ),
        child: child,
      ),
    ),
  );
}

// ── Gradient (dark scrim that fades to transparent center) ───────────────────
class _GradientBg extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  const _GradientBg({required this.accentColor, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          accentColor.withOpacity(0.06),
          Colors.black.withOpacity(0.45),
        ],
        stops: const [0.0, 0.6, 1.0],
      ),
    ),
    child: child,
  );
}

// ── Solid (opaque dark surface) ───────────────────────────────────────────────
class _SolidBg extends StatelessWidget {
  final Widget child;
  const _SolidBg({required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withOpacity(0.72),
    child: child,
  );
}

// ── Mesh (custom painted colour mesh) ────────────────────────────────────────
class _MeshBg extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  const _MeshBg({required this.accentColor, required this.child});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MeshPainter(accent: accentColor),
    child: child,
  );
}

class _MeshPainter extends CustomPainter {
  final Color accent;
  const _MeshPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw a subtle gradient mesh overlay
    final paint = Paint()..style = PaintingStyle.fill;

    // Top-left blob
    paint.shader = RadialGradient(
      colors: [accent.withOpacity(0.18), Colors.transparent],
    ).createShader(Rect.fromCircle(
      center: Offset(0, 0), radius: size.width * 0.55));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Bottom-right blob
    paint.shader = RadialGradient(
      colors: [Colors.black.withOpacity(0.6), Colors.transparent],
    ).createShader(Rect.fromCircle(
      center: Offset(size.width, size.height), radius: size.width * 0.6));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_MeshPainter o) => o.accent != accent;
}

/// Preview card for a background style — used in Quick Settings.
class ControlsBgPreview extends StatelessWidget {
  final String styleId;
  final String label;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  const ControlsBgPreview({
    super.key,
    required this.styleId,
    required this.label,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 80, height: 52,
        decoration: BoxDecoration(
          color: selected ? accentColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accentColor : Colors.white12,
            width: selected ? 1.5 : 1.0),
        ),
        child: Stack(alignment: Alignment.center, children: [
          // Mini preview
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.expand(
              child: ControlsBackground(
                style: styleId,
                accentColor: accentColor,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Label
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_iconFor(styleId),
                color: selected ? accentColor : Colors.white54, size: 16),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 9, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ]),
      ),
    );
  }

  IconData _iconFor(String s) {
    switch (s) {
      case 'glass':    return Icons.blur_on_rounded;
      case 'gradient': return Icons.gradient_rounded;
      case 'solid':    return Icons.rectangle_rounded;
      case 'mesh':     return Icons.auto_awesome_rounded;
      default:         return Icons.layers_clear_rounded;
    }
  }
}
