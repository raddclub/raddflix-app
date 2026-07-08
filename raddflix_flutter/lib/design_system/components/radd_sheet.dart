// lib/design_system/components/radd_sheet.dart
//
// RaddSheet — Volume IV / VIII contract. Single shared component for every
// modal/bottom sheet in the app. Interaction rule (Volume X): never stack —
// call `RaddSheet.show` again while one is open and it dismisses the first
// automatically via a static route-aware guard.

import 'package:flutter/material.dart';
import '../../core/theme/radd_colors.dart';
import '../elevation/radd_elevation.dart';
import '../radius/radd_radius.dart';
import '../spacing/radd_space.dart';
import '../motion/radd_motion.dart';
import '../typography/radd_type.dart';

enum RaddSheetStyle { list, tabbed }

class RaddSheetTab {
  final String label;
  final WidgetBuilder builder;
  const RaddSheetTab({required this.label, required this.builder});
}

class RaddSheet extends StatefulWidget {
  final RaddSheetStyle style;
  final String title;
  final List<RaddSheetTab>? tabs;
  final int initialTab;
  final double maxHeightFraction;
  final bool dismissible;
  final VoidCallback? onDismiss;
  final WidgetBuilder? listBuilder;

  const RaddSheet({
    super.key,
    this.style = RaddSheetStyle.list,
    required this.title,
    this.tabs,
    this.initialTab = 0,
    this.maxHeightFraction = 0.85,
    this.dismissible = true,
    this.onDismiss,
    this.listBuilder,
  }) : assert(style != RaddSheetStyle.tabbed || tabs != null,
            'RaddSheet.tabbed requires a non-null tabs list');

  /// Guard so only one RaddSheet is ever open at a time — opening a second
  /// dismisses the first before presenting (Volume X, no stacked sheets).
  static bool _isOpen = false;

  static Future<T?> show<T>(
    BuildContext context, {
    required RaddSheetStyle style,
    required String title,
    List<RaddSheetTab>? tabs,
    int initialTab = 0,
    double maxHeightFraction = 0.85,
    bool dismissible = true,
    WidgetBuilder? listBuilder,
  }) async {
    if (_isOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _isOpen = true;
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isDismissible: dismissible,
      enableDrag: dismissible,
      builder: (context) => RaddSheet(
        style: style,
        title: title,
        tabs: tabs,
        initialTab: initialTab,
        maxHeightFraction: maxHeightFraction,
        dismissible: dismissible,
        listBuilder: listBuilder,
      ),
    );
    _isOpen = false;
    return result;
  }

  @override
  State<RaddSheet> createState() => _RaddSheetState();
}

class _RaddSheetState extends State<RaddSheet> with SingleTickerProviderStateMixin {
  late int _tabIndex = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * widget.maxHeightFraction),
      child: RaddElevation.blurWrap(
        sigma: RaddElevation.sheetBlurSigma,
        child: Container(
          decoration: RaddElevation.sheet(context),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle — excluded from semantics, purely visual affordance.
                ExcludeSemantics(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.textMuted,
                      borderRadius: RaddRadius.pillRadius,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md, vertical: RaddSpace.sm),
                  child: Row(
                    children: [
                      Expanded(child: Text(widget.title, style: context.raddTitle.copyWith(color: t.textPrimary))),
                      if (widget.dismissible)
                        GestureDetector(
                          onTap: () {
                            widget.onDismiss?.call();
                            Navigator.of(context).maybePop();
                          },
                          child: Icon(Icons.close, size: 20, color: t.textMuted),
                        ),
                    ],
                  ),
                ),
                if (widget.style == RaddSheetStyle.tabbed && widget.tabs != null)
                  _buildTabBar(context),
                Flexible(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final t = context.t;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
        itemCount: widget.tabs!.length,
        itemBuilder: (context, i) {
          final selected = i == _tabIndex;
          return GestureDetector(
            onTap: () => setState(() => _tabIndex = i),
            child: Container(
              margin: const EdgeInsets.only(right: RaddSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? context.signalPrimary.withOpacity(0.12) : Colors.transparent,
                borderRadius: RaddRadius.pillRadius,
              ),
              child: Text(
                widget.tabs![i].label,
                style: context.raddLabel.copyWith(
                  color: selected ? context.signalPrimary : t.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.style == RaddSheetStyle.tabbed && widget.tabs != null) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: RaddMotion.tune,
        child: Padding(
          key: ValueKey(_tabIndex),
          padding: const EdgeInsets.all(RaddSpace.md),
          child: widget.tabs![_tabIndex].builder(context),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(RaddSpace.md),
      child: widget.listBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
