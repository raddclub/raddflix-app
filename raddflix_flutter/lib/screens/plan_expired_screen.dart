import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import '../core/constants.dart';

/// Task 6.9 — shown when an offline file is opened but the subscription
/// has expired (checked against the cached quota).
class PlanExpiredScreen extends StatelessWidget {
  const PlanExpiredScreen({super.key});

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
                  child: Icon(AppIcons.lock,
                      color: AppColors.primary, size: 46),
                ),
                SizedBox(height: RaddSpace.lg),
                Text(
                  'Plan Expired',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 14),
                Text(
                  'Your subscription has expired. Renew your plan to continue watching downloaded content offline.',
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
                      borderRadius: RaddRadius.mdRadius,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.crown,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text('Renew Plan',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
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
