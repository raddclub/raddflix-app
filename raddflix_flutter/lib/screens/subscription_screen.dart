import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/api/api_client.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/radd_text_field.dart';
import 'tid_status_screen.dart';

// ── Payment method model ──────────────────────────────────────────────────────
class _PayMethod {
  final String key, name;
  final String? accountNumber, instructions;
  final bool enabled;
  const _PayMethod({required this.key, required this.name,
      this.accountNumber, this.instructions, this.enabled = true});

  factory _PayMethod.fromJson(Map<String, dynamic> j) => _PayMethod(
    key:           j['code']           as String? ?? j['key'] as String? ?? j['id'] as String? ?? '',
    name:          j['name']           as String? ?? '',
    accountNumber: j['account_number'] as String?,
    instructions:  j['instructions']   as String?,
    enabled:       j['enabled'] is bool ? j['enabled'] as bool : (j['enabled'] as int? ?? 1) == 1,
  );
}

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  RaddTheme get t => RaddTheme.of(context);

  final _tidCtrl      = TextEditingController();
  bool _submitting    = false;
  String? _tidError;
  String? _selectedPlanId;
  String? _selectedMethod;
  List<_PayMethod> _methods  = [];
  bool _methodsLoading       = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(subscriptionProvider.notifier).loadPlans();
      ref.read(subscriptionProvider.notifier).loadStatus();
      _fetchMethods();
    });
  }

  Future<void> _fetchMethods() async {
    try {
      final res = await ApiClient.instance.get(ApiPaths.publicMethods);
      final data = res.data;
      List<dynamic> raw = [];
      if (data is Map && data['methods'] != null) raw = data['methods'] as List;
      else if (data is List) raw = data;
      setState(() {
        _methods = raw
            .cast<Map<String, dynamic>>()
            .map((j) => _PayMethod.fromJson(j))
            .where((m) => m.enabled && m.name.isNotEmpty)
            .toList();
        _methodsLoading = false;
      });
    } catch (_) {
      setState(() { _methods = []; _methodsLoading = false; });
    }
  }

  @override
  void dispose() { _tidCtrl.dispose(); super.dispose(); }

  Future<void> _submitTid() async {
    final tid = _tidCtrl.text.trim();
    if (tid.length < 6) { setState(() => _tidError = 'Enter a valid Transaction ID'); return; }
    if (_selectedPlanId == null) { setState(() => _tidError = 'Select a plan first'); return; }
    setState(() { _submitting = true; _tidError = null; });
    try {
      final user = ref.read(authProvider).user;
      final success = await ref.read(subscriptionProvider.notifier).submitTid(
        phone: user?.phone ?? '',
        tid: tid,
        plan: _selectedPlanId!,
        paymentMethod: _selectedMethod ?? 'jazzcash',
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (success) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TidStatusScreen(
            phone: user?.phone ?? '',
            tid: tid,
            plan: _selectedPlanId!,
            paymentMethod: _selectedMethod ?? 'jazzcash',
          ),
        ));
      } else {
        final err = ref.read(subscriptionProvider).error ?? 'Submission failed.';
        setState(() => _tidError = err.replaceFirst('Exception: ', ''));
      }
    } catch (e) {
      setState(() { _tidError = e.toString().replaceFirst('Exception: ', ''); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscriptionProvider);
    return LoadingOverlay(
      loading: _submitting,
      child: Scaffold(
        backgroundColor: null,
        appBar: AppBar(
          title: const Text('Get RaddFlix', style: TextStyle(fontWeight: FontWeight.w800)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop()),
        ),
        body: state.loading && state.plans.isEmpty
            ? Center(child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary), strokeCap: StrokeCap.round))
            : _buildBody(state),
      ),
    );
  }

  Widget _buildBody(SubscriptionState state) {
    final status  = state.status;
    final isGuest = ref.read(authProvider).user?.isGuest == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Active plan card with GB progress ─────────────────────────────────
        if (status != null && status.isActive)
          _ActivePlanCard(status: status)
              .animate().fadeIn(duration: 400.ms).slideY(begin: -0.15, end: 0, duration: 400.ms),

        if (status != null && status.isActive) const SizedBox(height: 20),

        // ── Header ────────────────────────────────────────────────────────────
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                letterSpacing: -0.4, color: t.textPrimary),
            children: [
              TextSpan(
                text: status != null && status.isActive
                    ? 'Renew or Upgrade '
                    : 'Pick Your ',
              ),
              TextSpan(text: 'Plan',
                  style: const TextStyle(color: AppColors.primary)),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms),
        const SizedBox(height: 5),
        Text(
          status != null && status.isActive
              ? 'Resubscribe to the same plan or switch to a bigger one — your choice.'
              : 'Zero-rated on Jazz · No data cost · Stream all day.',
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ).animate(delay: 60.ms).fadeIn(duration: 300.ms),
        const SizedBox(height: 10),
        const _JazzPartnerBadge().animate(delay: 100.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: 18),

        // ── Plan cards ────────────────────────────────────────────────────────
        if (state.plans.isEmpty && state.error != null) ...[
          _ErrorCard(
            message: 'Could not load plans',
            onRetry: () => ref.read(subscriptionProvider.notifier).loadPlans(),
          ),
          const SizedBox(height: 8),
        ] else if (state.plans.isEmpty)
          ..._shimmerPlans()
        else
          ...state.plans.asMap().entries.map((e) {
            final isCurrentPlan = status?.isActive == true &&
                (status!.plan.toLowerCase() == e.value.id.toLowerCase() ||
                 status.planName.toLowerCase() == e.value.name.toLowerCase());
            return _PlanCard(
              plan:          e.value,
              isPopular:     e.key == 1,
              isSelected:    _selectedPlanId == e.value.id,
              isCurrentPlan: isCurrentPlan,
              isRenewal:     isCurrentPlan && status?.isActive == true,
              onSelect:      () => setState(() => _selectedPlanId = e.value.id),
            ).animate(delay: (e.key * 80).ms)
                .fadeIn(duration: 350.ms)
                .slideY(begin: 0.15, end: 0, duration: 350.ms, curve: AppCurves.standard);
          }),

        // ── Payment section (shown after plan selected) ────────────────────────
        if (_selectedPlanId != null) ...[
          const SizedBox(height: 28),

          // Guest warning
          if (isGuest)
            _GuestWarning()
          else ...[

            // Selected plan summary
            Builder(builder: (_) {
              final plan = state.plans.firstWhere(
                (p) => p.id == _selectedPlanId,
                orElse: () => const SubscriptionPlan(
                  id: '', name: '', priceMonthly: 0, dataGb: 0,
                  maxDevices: 1, durationDays: 30, description: '',
                  features: [], color: '#E8002D', jazzSavingsMsg: ''),
              );
              final isRenew = status?.isActive == true &&
                  status!.plan.toLowerCase() == _selectedPlanId!.toLowerCase();
              return _SelectedPlanSummary(plan: plan, isRenewal: isRenew)
                  .animate().fadeIn(duration: 250.ms);
            }),
            const SizedBox(height: 20),

            // Pay With
            Text('Pay With', style: TextStyle(color: t.textPrimary,
                fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3))
                .animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 12),
            if (_methodsLoading)
              ...List.generate(2, (_) => Container(
                height: 70, margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md))))
            else if (_methods.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: t.border)),
                child: Text('Payment methods loading... proceed with your TID below.',
                    style: TextStyle(color: t.textMuted, fontSize: 13)),
              )
            else
              ..._methods.map((m) => _PayMethodCard(
                method: m,
                isSelected: _selectedMethod == m.key,
                onSelect: () => setState(() => _selectedMethod = m.key),
              ).animate().fadeIn(duration: 300.ms)),

            const SizedBox(height: 22),

            // TID entry
            Text('Enter Transaction ID',
                style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('After you pay on JazzCash or Easypaisa, paste your TID here. '
                'We verify within 24 hours and activate your plan. 🚀',
                style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 14),
            RaddTextField(
              controller: _tidCtrl,
              label: 'Transaction ID',
              hint: 'e.g. T123456789',
              prefixIcon: Icons.receipt_long_outlined,
            ).animate().fadeIn(duration: 300.ms),
            if (_tidError != null) ...[
              const SizedBox(height: 8),
              Text(_tidError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12))
                  .animate().fadeIn(duration: 200.ms).shakeX(hz: 3, amount: 4),
            ],
            const SizedBox(height: 18),
            _SubmitButton(onTap: _submitting ? null : _submitTid)
                .animate().fadeIn(duration: 300.ms),
          ],
        ],

        const SizedBox(height: 32),
        const _WhyRaddFlix(),
        const SizedBox(height: 40),
      ]),
    );
  }

  List<Widget> _shimmerPlans() => List.generate(3, (i) => Container(
    height: 110, margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md)))
    .animate(delay: (i * 80).ms).fadeIn(duration: 300.ms));
}

// ── Active plan card with GB progress bar ─────────────────────────────────────
class _ActivePlanCard extends StatelessWidget {
  final SubscriptionStatus status;
  const _ActivePlanCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final pct = status.usagePercent;
    final barColor = pct >= 0.9
        ? AppColors.error
        : pct >= 0.7
            ? AppColors.warning
            : AppColors.success;
    final daysLeft = status.daysUntilExpiry;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withOpacity(0.12), AppColors.success.withOpacity(0.03)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(0.15)),
            child: const Center(child: Icon(Icons.verified_rounded,
                color: AppColors.success, size: 20))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Active: ${status.planName}',
                style: TextStyle(color: t.textPrimary,
                    fontSize: 15, fontWeight: FontWeight.w700)),
            if (status.expiryLabel != null)
              Text('Renews ${status.expiryLabel}',
                  style: TextStyle(color: t.textMuted, fontSize: 12)),
          ])),
          if (daysLeft != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: daysLeft <= 5
                    ? AppColors.warning.withOpacity(0.15)
                    : AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.round)),
              child: Text('${daysLeft}d left',
                  style: TextStyle(
                      color: daysLeft <= 5 ? AppColors.warning : AppColors.success,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ]),
        if (status.monthlyLimitGb > 0) ...[
          const SizedBox(height: 16),
          // GB usage bar
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${status.monthlyUsedGb.toStringAsFixed(1)} GB used',
                style: TextStyle(color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(status.remainingLabel,
                style: TextStyle(color: barColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: t.border,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Text('${status.monthlyUsedGb.toStringAsFixed(1)} of ${status.monthlyLimitGb.toInt()} GB',
              style: TextStyle(color: t.textMuted, fontSize: 11)),
          if (pct >= 0.8) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: barColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: barColor.withOpacity(0.25))),
              child: Row(children: [
                Icon(pct >= 1.0
                    ? Icons.block_rounded
                    : Icons.warning_amber_rounded,
                    color: barColor, size: 14),
                const SizedBox(width: 7),
                Expanded(child: Text(
                    pct >= 1.0
                        ? "You've hit your limit — streaming is paused. Renew below!"
                        : 'Running low! Upgrade for more or renew early.',
                    style: TextStyle(color: barColor,
                        fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

// ── Jazz partner badge ─────────────────────────────────────────────────────────
class _JazzPartnerBadge extends StatelessWidget {
  const _JazzPartnerBadge();
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.round),
        border: Border.all(color: t.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.signal_cellular_4_bar_rounded, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Text('Zero-rated on Jazz SIM · No data deducted from your Jazz balance',
            style: TextStyle(color: t.textMuted, fontSize: 11)),
      ]),
    );
  }
}

// ── Plan card ──────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isPopular, isSelected, isCurrentPlan, isRenewal;
  final VoidCallback onSelect;
  const _PlanCard({
    required this.plan, required this.isPopular, required this.isSelected,
    required this.isCurrentPlan, required this.isRenewal, required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    Color accentColor;
    try {
      final hex = plan.color.replaceAll('#', '');
      accentColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      accentColor = AppColors.primary;
    }

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.07) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: isSelected ? accentColor : t.border,
              width: isSelected ? 1.5 : 0.5),
          boxShadow: isSelected
              ? [BoxShadow(color: accentColor.withOpacity(0.18),
                  blurRadius: 12, offset: const Offset(0, 4))]
              : null),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Radio dot
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : Colors.transparent,
                border: Border.all(color: isSelected ? accentColor : t.textMuted, width: 2)),
              child: isSelected ? Center(
                  child: Icon(Icons.check_rounded, size: 12, color: Colors.white)) : null),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(plan.name, style: TextStyle(
                  color: isSelected ? accentColor : t.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 7),
              if (isCurrentPlan)
                _Chip(label: 'YOUR PLAN', color: AppColors.success),
              if (!isCurrentPlan && isPopular)
                _Chip(label: 'POPULAR', color: AppColors.warning),
            ]),
            const SizedBox(height: 5),
            // Big GB label
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Text('${plan.dataGb.toInt()}',
                  style: TextStyle(
                      color: isSelected ? accentColor : t.textPrimary,
                      fontSize: 32, fontWeight: FontWeight.w900,
                      letterSpacing: -1.0, height: 1)),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('GB / month', style: TextStyle(
                    color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            if (plan.approxLabel.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(plan.approxLabel,
                  style: TextStyle(color: t.textSecondary, fontSize: 12)),
            ],
            if (plan.jazzSavingsMsg.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4)),
                child: Text('💰 ${plan.jazzSavingsMsg}',
                    style: const TextStyle(color: AppColors.success,
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
            if (isRenewal) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.autorenew_rounded, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('Tap to renew this plan',
                    style: TextStyle(color: AppColors.primary,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Rs. ${plan.priceMonthly}',
                style: TextStyle(
                    color: isSelected ? accentColor : t.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w800)),
            Text('/month', style: TextStyle(color: t.textMuted, fontSize: 10)),
            if (plan.pricePerGb.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(plan.pricePerGb,
                  style: TextStyle(color: t.textMuted, fontSize: 9)),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ── Small chip badge ──────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.7)),
  );
}

// ── Selected plan summary (before TID form) ───────────────────────────────────
class _SelectedPlanSummary extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isRenewal;
  const _SelectedPlanSummary({required this.plan, required this.isRenewal});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withOpacity(0.25))),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text('${plan.dataGb.toInt()}',
              style: const TextStyle(color: AppColors.primary,
                  fontSize: 14, fontWeight: FontWeight.w900)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isRenewal ? '${plan.name} — Renewal' : plan.name,
            style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${plan.dataGb.toInt()} GB · ${plan.durationDays} days · Rs. ${plan.priceMonthly}',
              style: TextStyle(color: t.textMuted, fontSize: 12)),
        ])),
        Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 20),
      ]),
    );
  }
}

// ── Guest warning ─────────────────────────────────────────────────────────────
class _GuestWarning extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_circle_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Sign in to Subscribe',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        Text('Create a free RaddFlix account to subscribe. Guest users cannot make payments.',
            style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.register, (r) => false),
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Create Account', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.5))),
          )),
      ]),
    );
  }
}

// ── Payment method card ───────────────────────────────────────────────────────
class _PayMethodCard extends StatelessWidget {
  final _PayMethod method;
  final bool isSelected;
  final VoidCallback onSelect;
  const _PayMethodCard({required this.method, required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.06) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: isSelected ? AppColors.primary : t.border,
              width: isSelected ? 1.5 : 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(duration: const Duration(milliseconds: 200),
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                    color: isSelected ? AppColors.primary : t.textMuted, width: 2)),
              child: isSelected ? Center(
                  child: Icon(Icons.check_rounded, size: 10, color: Colors.white)) : null),
            const SizedBox(width: 10),
            Text(method.name, style: TextStyle(
                color: isSelected ? AppColors.primary : t.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          if (isSelected && method.accountNumber != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppColors.primary.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(method.accountNumber!,
                    style: const TextStyle(color: AppColors.primary,
                        fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: method.accountNumber!));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Account number copied! ✅'),
                        duration: Duration(seconds: 2)));
                  },
                  child: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary)),
              ]),
            ),
            if (method.instructions != null) ...[
              const SizedBox(height: 8),
              Text(method.instructions!, style: TextStyle(
                  color: t.textMuted, fontSize: 12, height: 1.5)),
            ],
          ],
        ]),
      ),
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────
class _SubmitButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _SubmitButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    decoration: BoxDecoration(
      gradient: AppColors.primaryGradient,
      borderRadius: BorderRadius.circular(AppRadius.md),
      boxShadow: AppShadows.primary),
    child: Material(color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.send_rounded, color: Colors.white, size: 18),
          SizedBox(width: 10),
          Text('Submit TID & Activate Plan',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ]))),
  );
}

// ── Error card ─────────────────────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message,
              style: const TextStyle(color: AppColors.error,
                  fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try Again', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.5))),
          )),
      ]),
    );
  }
}

// ── Why RaddFlix section (replaces feature table) ─────────────────────────────
class _WhyRaddFlix extends StatelessWidget {
  const _WhyRaddFlix();

  static const _items = [
    (Icons.signal_cellular_4_bar_rounded, 'Zero Jazz Data Cost',
        'Stream all day — JazzDrive CDN means ZERO data deducted from your Jazz balance.'),
    (Icons.download_done_rounded, 'Download for Offline',
        'Save shows when on WiFi, watch them anywhere — no internet needed.'),
    (Icons.hd_rounded, 'HD Quality',
        'Enjoy HD and Full HD streams without buffering. Crystal clear, always.'),
    (Icons.auto_awesome_rounded, 'All Content Included',
        'Every plan unlocks the full library. Pick by GB, not by content.'),
    (Icons.lock_reset_rounded, 'Monthly Reset',
        'Your GB quota resets every month. Stream fresh every billing cycle.'),
    (Icons.verified_rounded, 'Fast Activation',
        'Pay → submit TID → activated within 24 hours. No contract, no hassle.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Why RaddFlix?', style: TextStyle(
          color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      ...(_items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(item.$1, color: AppColors.primary, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.$2, style: TextStyle(
                color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(item.$3, style: TextStyle(
                color: t.textMuted, fontSize: 12, height: 1.4)),
          ])),
        ]),
      ))),
    ]);
  }
}
