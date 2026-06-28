import 'package:flutter/material.dart';
  import 'package:intl/intl.dart';
  import '../core/theme/radd_theme.dart';
  import 'package:url_launcher/url_launcher.dart';
  import '../core/constants.dart';

  /// Shown when the user's monthly GB quota is exhausted.
  /// Accepts optional [usedGb], [limitGb], [planName], [resetsAt] so the screen
  /// can show exactly how much was used and when data resets.
  class QuotaFullScreen extends StatelessWidget {
    final double? usedGb;
    final double? limitGb;
    final String? planName;
    final String? resetsAt; // ISO date string or null

    const QuotaFullScreen({
      super.key,
      this.usedGb,
      this.limitGb,
      this.planName,
      this.resetsAt,
    });

    // FIX-11: use intl DateFormat so locale-aware month names are used.
    String _resetsLabel() {
      if (resetsAt == null) return '';
      try {
        final dt = DateTime.parse(resetsAt!);
        return DateFormat.yMMMd().format(dt);
      } catch (_) { return ''; }
    }

    @override
    Widget build(BuildContext context) {
      final t = RaddTheme.of(context);
      final used  = usedGb ?? 0.0;
      final limit = limitGb ?? 0.0;
      final pct   = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 1.0;
      final resetLabel = _resetsLabel();

      // FIX-24: PopScope(canPop: true) removed — canPop:true is the default.
      return Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // RaddFlix wordmark
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    children: [
                      TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)),
                      const TextSpan(text: 'Flix',
                          style: TextStyle(color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Icon
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error.withOpacity(0.07),
                    border: Border.all(
                        color: AppColors.error.withOpacity(0.2), width: 2)),
                  child: const Icon(Icons.data_usage_rounded,
                      color: AppColors.error, size: 42),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  "You've Hit Your\nData Limit 🚫",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: t.textPrimary, fontSize: 26,
                      fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.5),
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  limit > 0
                      ? 'You streamed ${used.toStringAsFixed(1)} GB out of your ${limit.toInt()} GB ${planName ?? ""} plan. '
                        'No worries — renew or upgrade to keep watching!'
                      : 'Your monthly streaming limit is reached. '
                        'Upgrade to a bigger plan and keep the binge going!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: t.textSecondary, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 20),

                // FIX-21: Primary CTA moved ABOVE the GB bar — always visible above fold
                // on small phones (Infinix Hot, Techno, etc — common in Pakistan).
                GestureDetector(
                  onTap: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.subscription),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.centerLeft, end: Alignment.centerRight),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 20, offset: const Offset(0, 8)),
                      ]),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text('Renew or Upgrade Plan',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                // GB usage bar (shown below CTA so it doesn't push CTA off-screen)
                if (limit > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: t.cardBorder)),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${used.toStringAsFixed(1)} GB used',
                            style: TextStyle(color: t.textMuted,
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${limit.toInt()} GB plan',
                            style: TextStyle(color: t.textMuted,
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: pct, minHeight: 10,
                          backgroundColor: t.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.error),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (resetLabel.isNotEmpty)
                        Text('🔄 Resets on $resetLabel',
                            style: TextStyle(color: t.textMuted, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // SIMOSA promo (Jazz's earn-free-MB app — external only)
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.tryParse(AppConstants.simosaPlayStoreUrl);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: t.cardBorder)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('🔥', style: TextStyle(fontSize: 17)),
                      const SizedBox(width: 8),
                      Text('Earn Free MB on Jazz via SIMOSA',
                          style: TextStyle(color: t.textPrimary,
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ]),
                  ),
                ),

                const SizedBox(height: 6),
                Text('SIMOSA is Jazz\'s own app for earning bonus MBs. '
                    'It\'s separate from RaddFlix.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textMuted, fontSize: 10)),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Go Back',
                      style: TextStyle(color: t.textMuted, fontSize: 14)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    }
  }
  