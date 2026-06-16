import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';

class QuotaFullScreen extends StatelessWidget {
  const QuotaFullScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5),
                    children: [
                      TextSpan(
                          text: 'Radd',
                          style: TextStyle(color: t.textPrimary)),
                      TextSpan(
                          text: 'Flix',
                          style: TextStyle(color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.08),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.25), width: 2),
                  ),
                  child: Icon(Icons.data_usage_rounded,
                      color: AppColors.primary, size: 46),
                ),
                SizedBox(height: 32),
                Text(
                  'Daily Limit Reached',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 14),
                Text(
                  "You've used your daily data quota. Upgrade your plan for more streaming, or get 100 MB free today via SIMOSA.",
                  style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 14,
                      height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.subscription),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text('Upgrade Plan',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final uri =
                        Uri.tryParse(AppConstants.simosaPlayStoreUrl);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.cardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🔥', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 8),
                        Text('Get 100 MB Free via SIMOSA',
                            style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Go Back',
                      style: TextStyle(
                          color: t.textMuted, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
