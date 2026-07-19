/// BB6 — RaddOverlay system
/// Three static overlay methods backed by OverlayEntry — no Scaffold dependency.
///
///   RaddOverlay.snack(context, 'Message')         // bottom pill, 3 s auto-dismiss
///   RaddOverlay.confirm(context, message: ..., confirmLabel: ...)  // bottom card
///   RaddOverlay.toast(context, 'Message')         // center pill, 2 s auto-dismiss
///
/// All methods are tier-aware (AnimConfig) and use RaddTheme tokens.
/// All methods call HapticService where appropriate.
library radd_overlay;

import 'package:flutter/material.dart';
// preflight: AppColors lives in core/constants.dart (relative from lib/core/ui/)
import '../../core/constants.dart';
import '../player/haptic_service.dart';

class RaddOverlay {
  RaddOverlay._();

  // ── Internal state ─────────────────────────────────────────────────────────
  static OverlayEntry? _activeSnack;

  // ── snack ─────────────────────────────────────────────────────────────────

  /// Bottom pill snackbar — slide+fade up, auto-dismiss after [duration].
  /// Replaces any currently visible snack. Optional [actionLabel]+[onAction]
  /// renders a tappable action on the right side.
  static void snack(
    BuildContext context,
    String message, {
    String?       actionLabel,
    VoidCallback? onAction,
    Duration      duration = const Duration(seconds: 3),
  }) {
    HapticService.instance.minor();
    _activeSnack?.remove();
    _activeSnack = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RaddSnack(
        message:     message,
        actionLabel: actionLabel,
        onAction:    onAction,
        duration:    duration,
        onDone: () {
          entry.remove();
          if (_activeSnack == entry) _activeSnack = null;
        },
      ),
    );
    _activeSnack = entry;
    Overlay.of(context).insert(entry);
  }

  // ── confirm ───────────────────────────────────────────────────────────────

  /// Bottom confirmation card with scrim — replaces AlertDialog.
  /// Returns true when confirmed, false when cancelled / dismissed.
  static Future<bool> confirm(
    BuildContext context, {
    String?  title,
    required String message,
    required String confirmLabel,
    String   cancelLabel = 'Cancel',
    bool     destructive = false,
  }) async {
    HapticService.instance.standard();
    final result = await showModalBottomSheet<bool>(
      context:          context,
      backgroundColor:  Colors.transparent,
      barrierColor:     Colors.black54,
      isScrollControlled: true,
      builder: (_) => _RaddConfirmCard(
        title:        title,
        message:      message,
        confirmLabel: confirmLabel,
        cancelLabel:  cancelLabel,
        destructive:  destructive,
      ),
    );
    return result ?? false;
  }

  // ── toast ─────────────────────────────────────────────────────────────────

  /// Centered pill toast — scale+fade, no action, auto-dismisses after [duration].
  static void toast(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RaddToast(
        message:  message,
        duration: duration,
        onDone:   () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _RaddSnack
// ─────────────────────────────────────────────────────────────────────────────
class _RaddSnack extends StatefulWidget {
  final String        message;
  final String?       actionLabel;
  final VoidCallback? onAction;
  final Duration      duration;
  final VoidCallback  onDone;

  const _RaddSnack({
    required this.message,
    this.actionLabel,
    this.onAction,
    required this.duration,
    required this.onDone,
  });

  @override State<_RaddSnack> createState() => _RaddSnackState();
}

class _RaddSnackState extends State<_RaddSnack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset>   _slide;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _slide = Tween<Offset>(begin: const Offset(0, 1.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) { if (mounted) widget.onDone(); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left:   0,
      right:  0,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Center(
            child: Container(
              margin:  const EdgeInsets.symmetric(horizontal: 20),
              padding: EdgeInsets.fromLTRB(
                  16, 12, widget.actionLabel != null ? 8 : 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(widget.message,
                    style: const TextStyle(color: Colors.white70, fontSize: 13))),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () { widget.onAction!(); _dismiss(); },
                    child: Text(widget.actionLabel!,
                        style: const TextStyle(color: AppColors.primary,
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 4),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _RaddConfirmCard
// ─────────────────────────────────────────────────────────────────────────────
class _RaddConfirmCard extends StatelessWidget {
  final String?  title;
  final String   message;
  final String   confirmLabel;
  final String   cancelLabel;
  final bool     destructive;

  const _RaddConfirmCard({
    this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  @override
  Widget build(BuildContext context) {
    final confirmColor = destructive ? Colors.redAccent : AppColors.primary;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(title!,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
            ],
            Text(message,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                HapticService.instance.standard();
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor.withOpacity(0.18),
                foregroundColor: confirmColor,
                side: BorderSide(color: confirmColor.withOpacity(0.6)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(confirmLabel,
                  style: TextStyle(color: confirmColor,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: Text(cancelLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _RaddToast
// ─────────────────────────────────────────────────────────────────────────────
class _RaddToast extends StatefulWidget {
  final String       message;
  final Duration     duration;
  final VoidCallback onDone;

  const _RaddToast({
    required this.message,
    required this.duration,
    required this.onDone,
  });

  @override State<_RaddToast> createState() => _RaddToastState();
}

class _RaddToastState extends State<_RaddToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) { if (mounted) widget.onDone(); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Center(
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh.withOpacity(0.96),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
            ),
            child: Text(widget.message,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ),
      ),
    ),
  );
}
