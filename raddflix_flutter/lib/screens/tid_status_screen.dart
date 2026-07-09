import 'dart:async';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../core/api/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/subscription_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// TID Payment Status Polling Screen.
/// Shown immediately after a user submits a TID — polls every 20s for approval.
class TidStatusScreen extends StatefulWidget {
  final String phone;
  final String tid;
  final String plan;
  final String paymentMethod;

  const TidStatusScreen({
    super.key,
    required this.phone,
    required this.tid,
    required this.plan,
    required this.paymentMethod,
  });

  @override
  State<TidStatusScreen> createState() => _TidStatusScreenState();
}

class _TidStatusScreenState extends State<TidStatusScreen>
    with TickerProviderStateMixin {
  static const _pollInterval = Duration(seconds: 20);

  _TidStatus _status = _TidStatus.pending;
  String? _approvedPlan;
  String? _errorMsg;
  int _pollCount = 0;
  Timer? _timer;
  int _countdown = 20;
  Timer? _countdownTimer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _startPolling();
    _poll(); // immediate first poll
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _startCountdown();
  }

  void _startCountdown() {
    _countdown = 20;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _countdown = (_countdown - 1).clamp(0, 20));
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _poll() async {
    if (!mounted) return;
    setState(() => _pollCount++);
    try {
      final res = await ApiClient.instance.get(
        '/api/subscription/tid/check_by_phone',
        params: {'phone': widget.phone},
      );
      final data = res.data as Map<String, dynamic>;
      final payments = (data['payments'] as List<dynamic>?) ?? [];

      // Find this specific TID
      final match = payments.firstWhere(
        (p) => (p as Map<String, dynamic>)['tid'] == widget.tid,
        orElse: () => null,
      );

      if (match != null) {
        final s = (match as Map<String, dynamic>)['status'] as String? ?? '';
        if (s == 'approved') {
          setState(() {
            _status = _TidStatus.approved;
            _approvedPlan = match['plan'] as String?;
          });
          _timer?.cancel();
          _countdownTimer?.cancel();
          return;
        } else if (s == 'rejected') {
          setState(() => _status = _TidStatus.rejected);
          _timer?.cancel();
          _countdownTimer?.cancel();
          return;
        }
      }

      // Still pending
      if (mounted) {
        setState(() => _status = _TidStatus.pending);
        _startCountdown();
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _errorMsg = 'Connection error — will retry');
      _startCountdown();
    } catch (_) {
      _startCountdown();
    }
  }

  String get _planLabel {
    switch (widget.plan) {
      case 'basic':
        return 'Basic Plan';
      case 'standard':
        return 'Standard Plan';
      case 'premium':
        return 'Premium Plan';
      default:
        return widget.plan.toUpperCase();
    }
  }

  String get _methodLabel =>
      widget.paymentMethod == 'easypaisa' ? 'EasyPaisa' : 'JazzCash';

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        elevation: 0,
        leading: _status != _TidStatus.approved
            ? IconButton(
                icon: Icon(AppIcons.back, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          _status == _TidStatus.approved ? 'Payment Approved!' : 'Payment Status',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: RaddSpace.md),
              _buildStatusIcon(),
              const SizedBox(height: RaddSpace.lg),
              _buildStatusTitle(),
              const SizedBox(height: RaddSpace.sm),
              _buildStatusSubtitle(),
              const SizedBox(height: RaddSpace.lg),
              _buildPaymentSummaryCard(),
              const SizedBox(height: 20),
              _buildTimeline(),
              const SizedBox(height: RaddSpace.lg),
              if (_status == _TidStatus.pending) ...[
                _buildPollIndicator(),
                const SizedBox(height: 20),
                _buildManualRefresh(),
                const SizedBox(height: RaddSpace.md),
                _buildWhatsAppButton(),
              ],
              if (_status == _TidStatus.approved) ...[
                const SizedBox(height: RaddSpace.sm),
                _buildStartWatchingButton(),
              ],
              if (_status == _TidStatus.rejected) ...[
                const SizedBox(height: RaddSpace.sm),
                _buildContactSupportButton(),
                const SizedBox(height: 12),
                _buildTryAgainButton(),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final t = RaddTheme.of(context);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Transform.scale(
        scale: _status == _TidStatus.pending ? _pulseAnim.value : 1.0,
        child: child,
      ),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _statusColor().withOpacity(0.15),
          border: Border.all(color: _statusColor(), width: 2.5),
        ),
        child: Icon(_statusIcon(), size: 48, color: _statusColor()),
      ),
    );
  }

  Widget _buildStatusTitle() {
    final t = RaddTheme.of(context);
    return Text(
      _statusTitleText(),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: _statusColor(),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildStatusSubtitle() {
    final t = RaddTheme.of(context);
    return Text(
      _statusSubtitleText(),
      style: TextStyle(color: t.textSecondary, fontSize: 14),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPaymentSummaryCard() {
    final t = RaddTheme.of(context);
    return Container(
      padding: EdgeInsets.all(RaddSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RaddRadius.mdRadius,
        border: Border.all(color: t.divider),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Plan', value: _planLabel),
          Divider(color: t.divider, height: 20),
          _SummaryRow(label: 'Payment Via', value: _methodLabel),
          Divider(color: t.divider, height: 20),
          Row(
            children: [
              Text('TID', style: TextStyle(color: t.textSecondary, fontSize: 13)),
              const Spacer(),
              Text(
                widget.tid,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: RaddSpace.sm),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.tid));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('TID copied'),
                    duration: Duration(seconds: 2),
                    backgroundColor: AppColors.primary,
                  ));
                },
                child: Icon(AppIcons.copy, size: 16, color: t.textSecondary),
              ),
            ],
          ),
          Divider(color: t.divider, height: 20),
          _SummaryRow(label: 'Phone', value: widget.phone),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final t = RaddTheme.of(context);
    return Container(
      padding: EdgeInsets.all(RaddSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RaddRadius.mdRadius,
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Progress',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: RaddSpace.md),
          _TimelineStep(
            icon: AppIcons.sendMessage,
            label: 'TID Submitted',
            sublabel: 'Your transaction ID was received',
            isActive: true,
            isDone: true,
          ),
          _TimelineStep(
            icon: AppIcons.search,
            label: 'Under Review',
            sublabel: _status == _TidStatus.pending
                ? 'Admin is verifying your payment'
                : _status == _TidStatus.approved
                    ? 'Payment verified'
                    : 'Could not verify payment',
            isActive: _status == _TidStatus.pending,
            isDone: _status == _TidStatus.approved,
            isFailed: _status == _TidStatus.rejected,
          ),
          _TimelineStep(
            icon: AppIcons.successIcon,
            label: 'Subscription Activated',
            sublabel: _status == _TidStatus.approved
                ? 'Your ${_approvedPlan?.toUpperCase() ?? widget.plan.toUpperCase()} plan is now active!'
                : 'Will activate after approval',
            isActive: _status == _TidStatus.approved,
            isDone: _status == _TidStatus.approved,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPollIndicator() {
    final t = RaddTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Checking in ${_countdown}s   (check $_pollCount)',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        if (_errorMsg != null) ...[
          const SizedBox(width: RaddSpace.sm),
          Icon(AppIcons.wifiOff, size: 14, color: AppColors.error),
        ],
      ],
    );
  }

  Widget _buildManualRefresh() {
    final t = RaddTheme.of(context);
    return OutlinedButton.icon(
      onPressed: () {
        _countdownTimer?.cancel();
        _poll();
      },
      icon: Icon(AppIcons.refresh, size: 18),
      label: const Text('Check Now'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildWhatsAppButton() {
    final t = RaddTheme.of(context);
    return TextButton.icon(
      onPressed: () async {
        final uri = Uri.parse(
          'https://wa.me/${AppConstants.supportWhatsApp}?text=RaddFlix+Support+%E2%80%94+TID:+${widget.tid}',
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('WhatsApp not installed. Please contact RaddFlix support.'),
            duration: Duration(seconds: 3),
          ));
        }
      },
      icon: Icon(AppIcons.chat, size: 18, color: Color(0xFF25D366)),
      label: const Text('Contact Support on WhatsApp'),
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF25D366)),
    );
  }

  Widget _buildStartWatchingButton() {
    final t = RaddTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          // P28-03: Refresh subscription state so home screen immediately
          // reflects the newly approved plan without a cold restart.
          final container = ProviderScope.containerOf(context);
          await container.read(subscriptionProvider.notifier).loadStatus();
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        icon: Icon(AppIcons.playCircleFill),
        label: const Text('Start Watching', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: RaddRadius.mdRadius),
        ),
      ),
    );
  }

  Widget _buildContactSupportButton() {
    final t = RaddTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final uri = Uri.parse(
            'https://wa.me/${AppConstants.supportWhatsApp}?text=RaddFlix+Payment+Rejected+%E2%80%94+TID:+${widget.tid}',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('WhatsApp not installed. Please contact RaddFlix support.'),
              duration: Duration(seconds: 3),
            ));
          }
        },
        icon: Icon(AppIcons.support),
        label: const Text('Contact Support via WhatsApp'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: RaddRadius.mdRadius),
        ),
      ),
    );
  }

  Widget _buildTryAgainButton() {
    final t = RaddTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textSecondary,
          side: BorderSide(color: t.divider),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: RaddRadius.mdRadius),
        ),
        child: const Text('Try Again'),
      ),
    );
  }

  Color _statusColor() {
    switch (_status) {
      case _TidStatus.pending:
        return AppColors.primary;
      case _TidStatus.approved:
        return AppColors.success;
      case _TidStatus.rejected:
        return AppColors.error;
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case _TidStatus.pending:
        return AppIcons.hourglass;
      case _TidStatus.approved:
        return AppIcons.verified;
      case _TidStatus.rejected:
        return AppIcons.cancel;
    }
  }

  String _statusTitleText() {
    switch (_status) {
      case _TidStatus.pending:
        return 'Payment Under Review';
      case _TidStatus.approved:
        return 'Payment Approved!';
      case _TidStatus.rejected:
        return 'Payment Rejected';
    }
  }

  String _statusSubtitleText() {
    switch (_status) {
      case _TidStatus.pending:
        return 'Our team reviews payments within a few hours.\nWe will activate your subscription automatically.';
      case _TidStatus.approved:
        return 'Your ${_approvedPlan?.toUpperCase() ?? widget.plan.toUpperCase()} subscription is now active.\nEnjoy watching!';
      case _TidStatus.rejected:
        return 'We could not verify your payment.\nPlease contact support with your TID.';
    }
  }
}

enum _TidStatus { pending, approved, rejected }

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Row(
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
  }
}

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isActive;
  final bool isDone;
  final bool isFailed;
  final bool isLast;

  const _TimelineStep({
    required this.icon,
    required this.label,
    required this.sublabel,
    this.isActive = false,
    this.isDone = false,
    this.isFailed = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    final Color color = isDone
        ? AppColors.success
        : isFailed
            ? AppColors.error
            : isActive
                ? AppColors.primary
                : t.divider;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(isActive || isDone || isFailed ? 0.15 : 0.05),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Icon(
                isDone ? AppIcons.check : isFailed ? AppIcons.close : icon,
                size: 16,
                color: color,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: color.withOpacity(0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isActive || isDone ? t.textPrimary : t.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                ),
                if (!isLast) const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}