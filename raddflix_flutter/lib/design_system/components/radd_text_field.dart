// lib/design_system/components/radd_text_field.dart
//
// RaddTextField — Volume IV. Height 52dp, md radius, surface fill, 1px
// border, focus -> 1.5px signal.primary. Error state -> accent.error border
// + helper text.

import 'package:flutter/material.dart';
import '../../core/theme/radd_colors.dart';
import '../radius/radd_radius.dart';
import '../spacing/radd_space.dart';

class RaddTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final bool enabled;

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
    this.enabled = true,
  });

  @override
  State<RaddTextField> createState() => _RaddTextFieldState();
}

class _RaddTextFieldState extends State<RaddTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

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
          height: 52,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: RaddRadius.mdRadius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
          alignment: Alignment.center,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            enabled: widget.enabled,
            style: context.raddBody.copyWith(color: t.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: context.raddBody.copyWith(color: t.textMuted),
              suffixIcon: widget.suffixIcon,
              isCollapsed: true,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: RaddSpace.xs),
          Text(widget.errorText!, style: context.raddCaption.copyWith(color: context.accentError)),
        ],
      ],
    );
  }
}
