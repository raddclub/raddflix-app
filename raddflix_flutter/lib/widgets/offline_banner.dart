/// Phase 54 — Global offline banner.
/// Drop `const OfflineBanner()` at the top of any screen's Column/body —
/// it collapses to zero height when online and slides/fades in when the
/// device loses connectivity, backed by the shared isOnlineProvider.
library offline_banner;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../core/constants.dart';
import '../providers/connectivity_provider.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final t = RaddTheme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !isOnline
          ? Container(
              key: const ValueKey('offline'),
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are offline. Some content may be unavailable.',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500, color: t.textPrimary),
                  ),
                ),
              ]),
            ).animate(key: const ValueKey('offline-anim'))
              .fadeIn(duration: 200.ms)
              .slideY(begin: -0.3, end: 0, duration: 220.ms, curve: Curves.easeOut)
          : const SizedBox.shrink(key: ValueKey('online')),
    );
  }
}
