// lib/design_system/components/radd_text_field.dart
//
// RaddTextField — Volume IV. Height 52dp, md radius, surface fill, 1px
// border, focus -> 1.5px signal.primary. Error state -> accent.error border
// + helper text.

import 'package:flutter/material.dart';
import '../../core/theme/radd_colors.dart';
import '../radius/radd_radius.dart';
import '../spacing/radd_space.dart';
import '../typography/radd_type.dart';

class RaddTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  // D1: added so login/register/subscription screens (previously stuck on
  // the inferior lib/widgets/radd_text_field.dart) can migrate to this one
  // without losing functionality.
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool enabled;
  // D2: exposes the FocusNode so multi-field forms can do Tab-order /
  // programmatic focus (e.g. focusNode.requestFocus() from a "next" button).
  // Only disposed here when this widget created it itself.
  final FocusNode? focusNode;

  const RaddTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.suffixIcon,
    this.prefixIcon,
    this.validator,
    this.maxLines = 1,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<RaddTextField> createState() => _RaddTextFieldState();
}

class _RaddTextFieldState extends State<RaddTextField> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final bool _ownsFocusNode = widget.focusNode == null;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    // D1: wrapping in a FormField (rather than a bare TextField) is what
    // lets `validator` participate in an ambient Form's `.validate()` call
    // (login/register screens gate submission on this) while keeping this
    // component's own boxed decoration instead of Flutter's default
    // underline+helper-text look.
    return FormField<String>(
      initialValue: widget.controller?.text,
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.disabled,
      builder: (field) {
        final effectiveError = widget.errorText ?? field.errorText;
        final hasError = effectiveError != null && effectiveError.isNotEmpty;
        final Color borderColor = hasError
            ? context.accentError
            : (_focused ? context.signalPrimary : t.border);
        final double borderWidth = hasError ? 1 : (_focused ? 1.5 : 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label != null) ...[
              Text(widget.label!, style: context.raddCaption.copyWith(color: t.textSecondary)),
              const SizedBox(height: RaddSpace.xs),
            ],
            Container(
              height: widget.maxLines > 1 ? null : 52,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: RaddRadius.mdRadius,
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md, vertical: RaddSpace.sm),
              alignment: Alignment.center,
              child: Row(
                children: [
                  if (widget.prefixIcon != null) ...[
                    Icon(widget.prefixIcon, color: t.textMuted, size: 20),
                    const SizedBox(width: RaddSpace.sm),
                  ],
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      obscureText: widget.obscureText,
                      keyboardType: widget.keyboardType,
                      maxLines: widget.maxLines,
                      enabled: widget.enabled,
                      style: context.raddBody.copyWith(color: t.textPrimary),
                      onChanged: (v) {
                        field.didChange(v);
                        widget.onChanged?.call(v);
                      },
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: context.raddBody.copyWith(color: t.textMuted),
                        suffixIcon: widget.suffixIcon,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: RaddSpace.xs),
              Text(effectiveError, style: context.raddCaption.copyWith(color: context.accentError)),
            ],
          ],
        );
      },
    );
  }
}
