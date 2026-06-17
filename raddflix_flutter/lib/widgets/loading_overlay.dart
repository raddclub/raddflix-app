import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
            color: Colors.black.withOpacity(0.58),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.elevated,
                  border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Pulse ring + spinner stack
                  SizedBox(
                    width: 60, height: 60,
                    child: Stack(alignment: Alignment.center, children: [
                      // Outer pulse ring — animates outward and fades
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                      ).animate(onPlay: (c) => c.repeat())
                       .scale(
                         begin: const Offset(1.0, 1.0),
                         end: const Offset(1.45, 1.45),
                         duration: 950.ms,
                         curve: Curves.easeOut,
                       )
                       .fadeOut(duration: 950.ms),
                      // Spinner
                      SizedBox(
                        width: 36, height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    ]),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      message!,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ]),
              )
              // Card entrance: scale up from 0.88 + fade in
              .animate()
              .scale(
                begin: const Offset(0.88, 0.88),
                end: const Offset(1.0, 1.0),
                duration: 220.ms,
                curve: Curves.easeOut,
              )
              .fadeIn(duration: 200.ms),
            ),
          ),
        ),
    ]);
  }
}
