import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../core/api/api_client.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/radd_text_field.dart';
import 'tid_status_screen.dart';

// ── Payment method model (fetched from billing API) ──────────────────────────
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
  String? _tidSuccess;
  String? _selectedPlanId;
  String? _selectedMethod;
  List<_PayMethod> _methods   = [];
  bool _methodsLoading        = true;

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
      // Payment methods API unavailable. Do NOT show placeholder account numbers —
      // users could send real money to a wrong/fake number. Show empty list instead.
      setState(() { _methods = []; _methodsLoading = false; });
    }
  }

  @override
  void dispose() { _tidCtrl.dispose(); super.dispose(); }

  Future<void> _submitTid() async {
    final tid = _tidCtrl.text.trim();
    if (tid.length < 6) { setState(() => _tidError = 'Enter a valid Transaction ID'); return; }
    if (_selectedPlanId == null) { setState(() => _tidError = 'Select a plan first'); return; }
    setState(() { _submitting = true; _tidError = null; _tidSuccess = null; });
    try {
      final user = ref.read(authProvider).user;
      final success = await ref.read(subscriptionProvider.notifier).submitTid(
        phone: user?.phone ?? '',
        tid: tid,
        plan: _selectedPlanId!,
        paymentMethod: _selectedMethod ?? 'jazzcash',
      );
      if (success) {
        setState(() { _submitting = false; });
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TidStatusScreen(
              phone: user?.phone ?? '',
              tid: tid,
              plan: _selectedPlanId!,
              paymentMethod: _selectedMethod ?? 'jazzcash',
            ),
          ));
        }
      } else {
        final err = ref.read(subscriptionProvider).error ?? 'Submission failed.';
        setState(() { _tidError = err.replaceFirst('Exception: ', ''); _submitting = false; });
      }
    } catch (e) {
      setState(() { _tidError = e.toString().replaceFirst('Exception: ', ''); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final state = ref.watch(subscriptionProvider);
    return LoadingOverlay(
      loading: _submitting,
      child: Scaffold(
        backgroundColor: null,
        appBar: AppBar(
          title: const Text('Subscription', style: TextStyle(fontWeight: FontWeight.w800)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop()),
        ),
        body: state.loading
            ? Center(child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary), strokeCap: StrokeCap.round))
            : _buildBody(state),
      ),
    );
  }

  Widget _buildBody(SubscriptionState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Active status
        if (state.status != null && state.status!.isActive)
          _buildActiveCard(state.status!)
              .animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0, duration: 400.ms),

        // Plans header
        Text('Choose a Plan', style: TextStyle(color: t.textPrimary,
            fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3))
            .animate().fadeIn(duration: 400.ms),
        SizedBox(height: 6),
        Text('Zero-rated on Jazz · HD quality · All content',
            style: TextStyle(color: t.textMuted, fontSize: 13))
            .animate(delay: 80.ms).fadeIn(duration: 300.ms),
        SizedBox(height: 10),
        const _JazzPartnerBadge()
            .animate(delay: 120.ms).fadeIn(duration: 400.ms),
        SizedBox(height: 16),

        // Plan cards
        if (state.plans.isEmpty && state.error != null)
          ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.error.withOpacity(0.25))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Could not load plans',
                      style: TextStyle(color: AppColors.error, fontSize: 13,
                          fontWeight: FontWeight.w600))),
                ]),
                SizedBox(height: 10),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => ref.read(subscriptionProvider.notifier).loadPlans(),
                    icon: Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Try Again', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withOpacity(0.5))),
                  )),
              ]),
            ),
            const SizedBox(height: 8),
          ]
        else if (state.plans.isEmpty)
          ..._shimmerPlans()
        else
          ...state.plans.asMap().entries.map((e) => _PlanCard(
            plan: e.value,
            isPopular: e.key == 1,
            isSelected: _selectedPlanId == e.value.id,
            onSelect: () => setState(() => _selectedPlanId = e.value.id),
          ).animate(delay: (e.key * 80).ms).fadeIn(duration: 350.ms)
              .slideY(begin: 0.15, end: 0, duration: 350.ms, curve: AppCurves.standard)),

        if (_selectedPlanId != null) ...[
          SizedBox(height: 24),
          if (ref.read(authProvider).user?.isGuest == true)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
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
                Text('Create a free account to subscribe. Guest users cannot make payments.',
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
            ),
          if (ref.read(authProvider).user?.isGuest != true)
            Text('Pay With', style: TextStyle(color: t.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3))
              .animate().fadeIn(duration: 300.ms),
          SizedBox(height: 12),
          if (_methodsLoading)
            ...List.generate(2, (_) => Container(
              height: 80, margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md))))
          else
            ..._methods.map((m) => _PayMethodCard(
              method: m,
              isSelected: _selectedMethod == m.key,
              onSelect: () => setState(() => _selectedMethod = m.key),
            ).animate().fadeIn(duration: 300.ms)),

          SizedBox(height: 20),
          Text('Transaction ID', style: TextStyle(color: t.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('After sending payment, enter the Transaction ID here for verification.',
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
              Text(_tidError!, style: const TextStyle(color: AppColors.error, fontSize: 12))
                  .animate().fadeIn(duration: 200.ms).shakeX(hz: 3, amount: 4),
            ],
            if (_tidSuccess != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.success.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_tidSuccess!,
                      style: const TextStyle(color: AppColors.success, fontSize: 12))),
                ]),
              ).animate().fadeIn(duration: 300.ms),
            ],
            const SizedBox(height: 16),
            Container(height: 52,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.primary),
            child: Material(color: Colors.transparent,
              child: InkWell(borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: _submitting ? null : _submitTid,
                child: const Center(child: Text('Submit Transaction',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700)))))),
          ], // end guest payment block
          const SizedBox(height: 32),

        // Feature table
        const _FeatureTable(),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildActiveCard(SubscriptionStatus sub) {
    String? expStr;
    if (sub.expiresAt != null) {
      try {
        final dt = DateTime.parse(sub.expiresAt!);
        final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        expStr = '${dt.day} ${months[dt.month-1]} ${dt.year}';
      } catch (_) { expStr = sub.expiresAt; }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.success.withOpacity(0.15), AppColors.success.withOpacity(0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.success.withOpacity(0.3))),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: AppColors.success.withOpacity(0.15)),
          child: Center(child: Icon(Icons.verified_rounded,
              color: AppColors.success, size: 24))),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Active: ${sub.plan.toUpperCase()}', style: TextStyle(
              color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          if (expStr != null)
            Text('Expires $expStr', style: TextStyle(
                color: t.textMuted, fontSize: 12)),
        ])),
      ]),
    );
  }

  List<Widget> _shimmerPlans() => List.generate(3, (_) => Container(
    height: 100, margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md))));
}

// ── Plan Card ─────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isPopular, isSelected;
  final VoidCallback onSelect;
  const _PlanCard({required this.plan, required this.isPopular,
      required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: isSelected ? AppColors.primary : t.border,
              width: isSelected ? 1.5 : 0.5),
          boxShadow: isSelected ? AppShadows.primary : null),
        child: Row(children: [
          AnimatedContainer(duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(color: isSelected ? AppColors.primary : t.textMuted, width: 2)),
            child: isSelected ? Center(
                child: Icon(Icons.check_rounded, size: 12, color: Colors.white)) : null),
          SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(plan.name, style: TextStyle(
                  color: isSelected ? AppColors.primary : t.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
              if (isPopular) ...[
                SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('POPULAR', style: TextStyle(
                      color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
              ],
            ]),
            if (plan.features.isNotEmpty) ...[
              SizedBox(height: 4),
              Text(plan.features.take(3).join(' · '),
                  style: TextStyle(color: t.textMuted, fontSize: 11), maxLines: 2),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(plan.priceMonthly == 0 ? 'Free' : 'Rs. ${plan.priceMonthly}',
                style: TextStyle(
                    color: isSelected ? AppColors.primary : t.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w800)),
            if (plan.priceMonthly > 0)
              Text('/month', style: TextStyle(color: t.textMuted, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

// ── Payment Method Card ────────────────────────────────────────────────────────
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
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(color: isSelected ? AppColors.primary : t.textMuted, width: 2)),
              child: isSelected ? Center(
                  child: Icon(Icons.check_rounded, size: 10, color: Colors.white)) : null),
            SizedBox(width: 10),
            Text(method.name, style: TextStyle(
                color: isSelected ? AppColors.primary : t.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          if (isSelected && method.accountNumber != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                child: Row(children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(child: Text(method.accountNumber!, style: TextStyle(
                      color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w700,
                      letterSpacing: 0.5))),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: method.accountNumber!));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied!'), duration: Duration(seconds: 2)));
                    },
                    child: Icon(Icons.copy_rounded, size: 16, color: AppColors.primary)),
                ]),
              )),
            ]),
            if (method.instructions != null) ...[
              SizedBox(height: 8),
              Text(method.instructions!, style: TextStyle(
                  color: t.textMuted, fontSize: 12, height: 1.5)),
            ],
          ],
        ]),
      ),
    );
  }
}

// ── Feature Comparison Table ──────────────────────────────────────────────────
class _FeatureTable extends StatelessWidget {
  const _FeatureTable();
  static const _rows = [
    ('Zero-data streaming', true,  true,  true),
    ('Offline catalog',     true,  true,  true),
    ('Free content',        true,  true,  true),
    ('HD 720p quality',     false, true,  true),
    ('Full HD 1080p',       false, false, true),
    ('All premium content', false, true,  true),
    ('Multiple devices',    false, false, true),
  ];
  static const _heads = ['Basic', 'Standard', 'Premium'];
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Plan Comparison', style: TextStyle(color: t.textPrimary,
          fontSize: 16, fontWeight: FontWeight.w700)),
      SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: t.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(flex: 3, child: Padding(padding: EdgeInsets.only(left: 16),
                child: Text('Feature', style: TextStyle(color: t.textMuted,
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)))),
              ...List.generate(3, (i) => Expanded(child: Center(
                  child: Text(_heads[i], style: TextStyle(
                      color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w700))))),
            ])),
          const Divider(height: 1),
          ..._rows.asMap().entries.map((e) => Column(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
              Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(left: 16),
                child: Text(e.value.$1, style: TextStyle(
                    color: t.textPrimary, fontSize: 12)))),
              _cell(e.value.$2), _cell(e.value.$3), _cell(e.value.$4),
            ])),
            if (e.key < _rows.length - 1) const Divider(height: 1, indent: 16),
          ])),
        ]),
      ),
    ]);
  }
  Widget _cell(bool yes) => Expanded(child: Center(child: Icon(
      yes ? Icons.check_circle_rounded : Icons.remove_rounded,
      size: 16, color: yes ? AppColors.success : AppColors.textDisabled)));
}


// ── Jazz Partnership Badge (Phase 9.5) ────────────────────────────────────────
class _JazzPartnerBadge extends StatelessWidget {
  const _JazzPartnerBadge();
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.jazzGreenDark, AppColors.jazzGreen],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(color: AppColors.jazzGreen.withOpacity(0.25),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 20, height: 20,
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Colors.white),
          child: const Center(
            child: Text('J', style: TextStyle(
              color: AppColors.jazzGreenDark, fontSize: 11,
              fontWeight: FontWeight.w900))),
        ),
        const SizedBox(width: 8),
        const Text('Official Jazz Partner',
            style: TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4)),
          child: const Text('Zero-Rated', style: TextStyle(
              color: Colors.white, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
      ]),
    );
  }
}
