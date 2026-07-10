// lib/design_system/components/settings_row.dart
//
// SettingsRow — Volume IV. Single row primitive: leading icon (24dp) +
// label (body) + trailing (chevron / switch / value text), 56dp height.
// Every settings-style list in the app should render from this.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/radd_colors.dart';
import '../spacing/radd_space.dart';
import '../typography/radd_type.dart';

enum SettingsRowTrailing { none, chevron, switchControl, valueText }

class SettingsRow extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final SettingsRowTrailing trailing;
  final String? valueText;
  final bool switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final VoidCallback? onTap;
  final bool enabled;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing = SettingsRowTrailing.chevron,
    this.valueText,
    this.switchValue = false,
    this.onSwitchChanged,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    Widget? trailingWidget;
    switch (trailing) {
      case SettingsRowTrailing.chevron:
        trailingWidget = Icon(PhosphorIcons.caretRight(), size: 18, color: t.textMuted);
        break;
      case SettingsRowTrailing.switchControl:
        trailingWidget = Switch(
          value: switchValue,
          onChanged: enabled ? onSwitchChanged : null,
          activeColor: context.signalPrimary,
        );
        break;
      case SettingsRowTrailing.valueText:
        trailingWidget = Text(
          valueText ?? '',
          style: context.raddBody.copyWith(color: t.textSecondary),
        );
        break;
      case SettingsRowTrailing.none:
        trailingWidget = null;
        break;
    }

    return Semantics(
      button: onTap != null,
      enabled: enabled,
      label: valueText != null ? '$label, $valueText' : label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Icon(icon, size: 24, color: t.textSecondary),
                const SizedBox(width: RaddSpace.md),
                Expanded(
                  child: Text(label, style: context.raddBody.copyWith(color: t.textPrimary)),
                ),
                if (trailingWidget != null) trailingWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
