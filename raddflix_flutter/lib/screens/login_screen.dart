import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api/auth_api.dart';
import '../core/security/keystore.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/radd_text_field.dart';
import '../core/utils/auth_utils.dart';
import '../widgets/particle_overlay.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() { _phoneCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        phone: _phoneCtrl.text.trim(), password: _passCtrl.text);
      // auth_provider catches all DioExceptions internally — it never throws.
      // Must explicitly check state after the call to detect failure.
      final s = ref.read(authProvider);
      if (s.isDeviceConflict) {
        setState(() { _loading = false; });
        return;
      }
      // BUG-LOGIN-01: login() sets state.error on wrong password instead of
      // throwing, so the original code always reached pushReplacementNamed and
      // navigated to home regardless of failure → appeared as guest login.
      if (s.error != null) {
        setState(() { _error = s.error; _loading = false; });
        return;
      }
      if (mounted) await navigateAfterAuth(context, ref);
    } catch (e) {
      final s = ref.read(authProvider);
      if (s.isDeviceConflict) {
        setState(() { _loading = false; });
        return;
      }
      if (mounted) setState(() { _error = AuthErrors.login(e.toString()); _loading = false; });
    }
  }

  Future<void> _guest() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).continueAsGuest();
      if (mounted) await navigateAfterAuth(context, ref);
    } catch (e) {
      if (mounted) setState(() { _error = 'Cannot connect. Check your internet.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final authState = ref.watch(authProvider);
    return LoadingOverlay(
      loading: _loading,
      child: Scaffold(
        backgroundColor: null,
        body: Stack(
          children: [
            // Background glows
            Positioned(
              top: -100, left: -80,
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.primary.withOpacity(0.16), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60, right: -60,
              child: Container(
                width: 240, height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.primary.withOpacity(0.08), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Phase 49 ANIM-49-03: ambient spark particles on Tier 3 (API 33+)
            Positioned.fill(child: ParticleOverlay()),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 48),
                    // Logo
                    Center(child: _Logo())
                        .animate().fadeIn(duration: 500.ms)
                        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
                            duration: 500.ms, curve: AppCurves.enter),
                    SizedBox(height: 48),
                    Text('Welcome back',
                        style: TextStyle(
                          color: t.textMuted, fontSize: 14, letterSpacing: 0.4,
                          fontWeight: FontWeight.w500))
                        .animate(delay: 100.ms).fadeIn(duration: 400.ms),
                    SizedBox(height: 4),
                    Text('Sign In',
                        style: TextStyle(
                          color: t.textPrimary, fontSize: 30,
                          fontWeight: FontWeight.w800, letterSpacing: -0.8))
                        .animate(delay: 150.ms).fadeIn(duration: 400.ms)
                        .slideX(begin: -0.2, end: 0, duration: 400.ms, curve: AppCurves.standard),
                    const SizedBox(height: 28),
                    Form(
                      key: _formKey,
                      child: Column(children: [
                        RaddTextField(
                          controller: _phoneCtrl,
                          label: 'Phone Number',
                          hint: '03001234567',
                          keyboardType: TextInputType.phone,
                          prefixIcon: AppIcons.phone,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                            return null;
                          },
                        ).animate(delay: 200.ms).fadeIn(duration: 350.ms)
                            .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                        SizedBox(height: 14),
                        RaddTextField(
                          controller: _passCtrl,
                          label: 'Password',
                          obscureText: _obscure,
                          prefixIcon: AppIcons.lock,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? AppIcons.eyeOff : AppIcons.eye,
                              color: t.textMuted, size: 20),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter your password';
                            return null;
                          },
                        ).animate(delay: 260.ms).fadeIn(duration: 350.ms)
                            .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                      ]),
                    ),
                    // Device conflict panel — shown when another device is bound
                    if (authState.isDeviceConflict) ...[
                      const SizedBox(height: 14),
                      _DeviceConflictPanel(deviceName: authState.deviceConflictName ?? 'another device')
                          .animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, duration: 300.ms),
                    ] else if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBanner(message: _error!)
                          .animate().fadeIn(duration: 250.ms).shakeX(hz: 3, amount: 4),
                    ],
                    SizedBox(height: 28),
                    // Sign In Button
                    _GradientButton(label: 'Sign In', onTap: _loading ? null : _login)
                        .animate(delay: 320.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                    SizedBox(height: 12),
                    // Guest
                    OutlinedButton(
                      onPressed: _loading ? null : _guest,
                      child: Text('Continue as Guest'),
                    )
                        .animate(delay: 370.ms).fadeIn(duration: 350.ms),
                    SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.register),
                        child: Text.rich(
                          TextSpan(
                            text: "Don't have an account? ",
                            style: TextStyle(color: t.textMuted, fontSize: 14),
                            children: [
                              TextSpan(text: 'Register',
                                  style: const TextStyle(
                                      color: AppColors.primary, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ).animate(delay: 400.ms).fadeIn(duration: 300.ms),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Device Conflict Panel ──────────────────────────────────────────────────────
//
// Current mode: WhatsApp-only (AppConstants.otpDeviceSwitchEnabled = false).
//
// To enable OTP self-serve device switching in future:
//   1. Set AppConstants.otpDeviceSwitchEnabled = true
//   2. Implement AuthApi.requestDeviceSwitchOtp() + verifyDeviceSwitchOtp()
//   3. Add server endpoints (see ApiPaths.deviceSwitchOtpRequest/Verify)
//   The OTP UI section below will become visible automatically.
//
class _DeviceConflictPanel extends StatefulWidget {
  final String deviceName;
  const _DeviceConflictPanel({required this.deviceName});
  @override
  State<_DeviceConflictPanel> createState() => _DeviceConflictPanelState();
}

class _DeviceConflictPanelState extends State<_DeviceConflictPanel> {
  // ── OTP HOOK — state vars (used only when otpDeviceSwitchEnabled = true) ──
  bool _otpSent      = false;
  bool _otpLoading   = false;
  String? _otpError;
  final _otpCtrl     = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _otpCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(
      'Hi RaddFlix Support, I need to switch my account to a new device. '
      'My account was active on: ${widget.deviceName}');
    final url = Uri.parse(
        'https://wa.me/${AppConstants.supportWhatsApp}?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open WhatsApp. Install it first.')));
      }
    }
  }

  // ── OTP HOOK — request OTP (wire when otpDeviceSwitchEnabled = true) ──────
  Future<void> _requestOtp() async {
    final rawPhone = _phoneCtrl.text.trim();
    final digits   = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!RegExp(r'^03\d{9}$').hasMatch(digits)) {
      setState(() => _otpError = 'Enter a valid Pakistani mobile number (03XX-XXXXXXX)');
      return;
    }
    setState(() { _otpLoading = true; _otpError = null; });
    try {
      await AuthApi.requestDeviceSwitchOtp(phone: _phoneCtrl.text.trim());
      setState(() { _otpSent = true; _otpLoading = false; });
    } catch (e) {
      if (mounted) setState(() {
        _otpError = e.toString().contains('Unimplemented')
            ? 'OTP not yet configured' : 'Failed to send OTP. Try again.';
        _otpLoading = false;
      });
    }
  }

  // ── OTP HOOK — verify OTP (wire when otpDeviceSwitchEnabled = true) ───────
  Future<void> _verifyOtp() async {
    setState(() { _otpLoading = true; _otpError = null; });
    try {
      final result = await AuthApi.verifyDeviceSwitchOtp(
        phone: _phoneCtrl.text.trim(),
        otpCode: _otpCtrl.text.trim(),
      );
      await Keystore.saveTokens(
        accessToken:  result.accessToken,
        refreshToken: result.refreshToken,
        userId:       result.userId.toString(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) setState(() {
        _otpError = e.toString().contains('Unimplemented')
            ? 'OTP not yet configured' : 'Invalid or expired OTP.';
        _otpLoading = false;
      });
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningDark.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warningDark.withOpacity(0.4), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(AppIcons.devices, color: Color(0xFFF59E0B), size: 18),
          SizedBox(width: 8),
          Text('Device Conflict',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
        SizedBox(height: 8),
        Text(
          'This account is already signed in on "${widget.deviceName}". '
          'RaddFlix allows only one device per account.',
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),

        // ── Primary action: WhatsApp support (always visible) ──────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF25D366), width: 1),
              foregroundColor: const Color(0xFF25D366),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: Icon(AppIcons.chat, size: 16),
            label: Text('Contact Support on WhatsApp',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            onPressed: _openWhatsApp,
          ),
        ),

        // ── OTP HOOK — shown only when otpDeviceSwitchEnabled = true ───────
        // To activate: set AppConstants.otpDeviceSwitchEnabled = true
        // and implement the two AuthApi OTP methods.
        if (AppConstants.otpDeviceSwitchEnabled) ...[
          SizedBox(height: 14),
          Row(children: [
            Expanded(child: Divider(color: Color(0x33FFFFFF))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('or switch yourself',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
            ),
            const Expanded(child: Divider(color: Color(0x33FFFFFF))),
          ]),
          const SizedBox(height: 12),
          if (!_otpSent) ...[
            // Step 1: enter phone + request OTP
            RaddTextField(
              controller: _phoneCtrl,
              label: 'Your Phone Number',
              hint: '03001234567',
              keyboardType: TextInputType.phone,
              prefixIcon: AppIcons.phone,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _otpLoading ? null : _requestOtp,
                child: _otpLoading
                    ? const SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send OTP to My Number',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else ...[
            // Step 2: enter OTP + verify
            RaddTextField(
              controller: _otpCtrl,
              label: 'Enter OTP',
              hint: '6-digit code',
              keyboardType: TextInputType.number,
              prefixIcon: AppIcons.pinCode,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _otpLoading ? null : _verifyOtp,
                child: _otpLoading
                    ? SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Verify & Switch Device',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            TextButton(
              onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); }),
              child: Text('Resend OTP',
                  style: TextStyle(color: t.textMuted, fontSize: 12)),
            ),
          ],
          if (_otpError != null) ...[
            const SizedBox(height: 8),
            Text(_otpError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ],
        // ── END OTP HOOK ────────────────────────────────────────────────────
      ]),
    );
  }
}

// ── Logo ───────────────────────────────────────────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFE8002D), Color(0xFF8B0000)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            boxShadow: AppShadows.glow,
          ),
          child: Center(
            child: Text('R', style: TextStyle(
              color: Colors.white, fontSize: 32,
              fontWeight: FontWeight.w900, letterSpacing: -1)),
          ),
        ),
        SizedBox(height: 14),
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.5, height: 1),
            children: [
              TextSpan(text: 'Radd', style: TextStyle(color: t.textPrimary)),
              TextSpan(text: 'Flix', style: TextStyle(color: AppColors.primary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Error Banner ───────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.errorIcon, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: const TextStyle(color: AppColors.error, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Gradient Button ────────────────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _GradientButton({required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: onTap != null ? AppColors.primaryGradient : null,
        color: onTap == null ? AppColors.primary.withOpacity(0.4) : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: onTap != null ? AppShadows.primary : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Center(
            child: Text(label,
              style: const TextStyle(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ),
      ),
    );
  }
}
