import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme/radd_theme.dart';

class RaddTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxLines;

  const RaddTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        color: t.textPrimary,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: t.textMuted, size: 20)
            : null,
        suffixIcon: suffixIcon,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
