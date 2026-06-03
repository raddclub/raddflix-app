import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import '../core/constants.dart';

class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool loading;
  final String? message;
  const LoadingOverlay({super.key, required this.child, required this.loading, this.message});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Stack(children: [
      child,
      if (loading)
        Positioned.fill(
          child: Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.elevated,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeCap: StrokeCap.round,
                  ),
                  if (message != null) ...[
                    SizedBox(height: 14),
                    Text(message!, style: const TextStyle(
                        color: t.textSecondary, fontSize: 13)),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
