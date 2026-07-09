// lib/design_system/components/radd_lock_pad.dart
//
// RaddLockPad — Volume IV. One component, two skins driven by `accent`:
// signal.primary for standard app lock, purple->crimson gradient for Vault.
// Same geometry/motion/layout throughout — do not fork a second PIN pad.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/radd_colors.dart';
import '../spacing/radd_space.dart';
import '../typography/radd_type.dart';

enum RaddLockPadAccent { standard, vault }

class RaddLockPad extends StatefulWidget {
  final int pinLength;
  final RaddLockPadAccent accent;
  final ValueChanged<String> onSubmit;
  final String? errorText;
  final bool showBiometric;
  final VoidCallback? onBiometricTap;

  /// Fires on every digit press/backspace, before [pinLength] is reached.
  /// Use this to clear caller-owned error/mismatch state as soon as the user
  /// starts a new attempt, instead of waiting for the next [onSubmit].
  final ValueChanged<String>? onChanged;

  const RaddLockPad({
    super.key,
    this.pinLength = 4,
    this.accent = RaddLockPadAccent.standard,
    required this.onSubmit,
    this.errorText,
    this.showBiometric = false,
    this.onBiometricTap,
    this.onChanged,
  });

  @override
  State<RaddLockPad> createState() => _RaddLockPadState();
}

class _RaddLockPadState extends State<RaddLockPad> {
  String _entered = '';

  Gradient _gradientFor(BuildContext context) {
    if (widget.accent == RaddLockPadAccent.vault) {
      return const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFE8002D)]);
    }
    return LinearGradient(colors: [context.signalPrimary, context.signalPrimary]);
  }

  void _tap(String digit) {
    if (_entered.length >= widget.pinLength) return;
    setState(() => _entered += digit);
    widget.onChanged?.call(_entered);
    if (_entered.length == widget.pinLength) {
      final code = _entered;
      widget.onSubmit(code);
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _entered = '');
      });
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
    widget.onChanged?.call(_entered);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final gradient = _gradientFor(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.pinLength, (i) {
            final filled = i < _entered.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: filled ? gradient : null,
                color: filled ? null : t.glass,
                border: Border.all(color: t.border),
              ),
            );
          }),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: RaddSpace.sm),
          Text(widget.errorText!, style: context.raddCaption.copyWith(color: context.accentError)),
        ],
        const SizedBox(height: RaddSpace.xl),
        _buildGrid(context),
      ],
    );
  }

  Widget _buildGrid(BuildContext context) {
    final t = context.t;
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', 'back'];
    return Wrap(
      spacing: RaddSpace.md,
      runSpacing: RaddSpace.md,
      alignment: WrapAlignment.center,
      children: keys.map((key) {
        if (key == 'bio') {
          return _RaddLockPadKey(
            child: widget.showBiometric
                ? Icon(PhosphorIcons.fingerprint(), color: t.textSecondary)
                : const SizedBox.shrink(),
            onTap: widget.showBiometric ? widget.onBiometricTap : null,
          );
        }
        if (key == 'back') {
          return _RaddLockPadKey(
            child: Icon(PhosphorIcons.backspace(), color: t.textSecondary),
            onTap: _backspace,
          );
        }
        return _RaddLockPadKey(
          child: Text(key, style: context.raddTitle.copyWith(color: t.textPrimary)),
          onTap: () => _tap(key),
        );
      }).toList(),
    );
  }
}

class _RaddLockPadKey extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _RaddLockPadKey({required this.child, this.onTap});

  @override
  State<_RaddLockPadKey> createState() => _RaddLockPadKeyState();
}

class _RaddLockPadKeyState extends State<_RaddLockPadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.elasticOut,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.glass.withOpacity(0.07),
            border: Border.all(color: t.border, width: 1),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
