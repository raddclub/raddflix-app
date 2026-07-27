import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // TextInputFormatter for UX4-10
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api/auth_api.dart';
import '../core/security/keystore.dart';
import '../core/constants.dart';
import '../core/app_container.dart';
import '../providers/remote_values_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/loading_overlay.dart';
import '../design_system/components/radd_button.dart';
import '../design_system/components/radd_text_field.dart';
import '../core/utils/auth_utils.dart';
import '../widgets/particle_overlay.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

// UX4-10: Pakistani phone formatter — inserts hyphen after digit 4 (03XX-XXXXXXX),
// strips non-digits, caps at 12 chars (11 digits + 1 hyphen).
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue val) {
    final digits = val.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) return old;
    final formatted =
        digits.length <= 4 ? digits : '${digits.substring(0, 4)}-${digits.substring(4)}';
    return val.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneFocus = FocusNode(); // UX4-08
  final _passFocus  = FocusNode(); // UX4-08
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;

  bool get _phoneIsValid {
    final digits = _phoneCtrl.text.replaceAll('-', '').trim();
    return digits.length == 11 && digits.startsWith('03');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose(); _passCtrl.dispose();
    _phoneFocus.dispose(); _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    TextInput.finishAutofillContext(shouldSave: false);
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        phone: _phoneCtrl.text.replaceAll('-', '').trim(), // UX4-10: strip formatter hyphen
        password: _passCtrl.text);
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
    HapticFeedback.lightImpact();
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
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
                    colors: [context.signalPrimary.withOpacity(0.16), Colors.transparent],
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
                    colors: [context.signalPrimary.withOpacity(0.08), Colors.transparent],
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
                    Text('Sign in to continue watching',
                        style: TextStyle(
                          color: t.textPrimary, fontSize: 29,
                          fontWeight: FontWeight.w800, letterSpacing: -0.8))
                        .animate(delay: 150.ms).fadeIn(duration: 400.ms)
                        .slideX(begin: -0.2, end: 0, duration: 400.ms, curve: AppCurves.standard),
                    const SizedBox(height: 28),
                    AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(children: [
                        RaddTextField(
                          controller: _phoneCtrl,
                          label: 'Phone Number',
                          hint: '03XX-XXXXXXX',
                          keyboardType: TextInputType.phone,
                          prefixIcon: AppIcons.phone,
                          focusNode: _phoneFocus,
                          textInputAction: TextInputAction.next, // UX4-08
                          inputFormatters: [_PhoneFormatter()],  // UX4-10
                          autofillHints: const [AutofillHints.telephoneNumber],
                          semanticsLabel: 'Phone number',
                          semanticsHint: 'Enter your Pakistani phone number',
                          onChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_passFocus),
                          suffixIcon: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            // Autofill/state feedback should respect the
                            // user's reduced-motion preference.
                            reverseDuration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: _phoneIsValid
                                ? Icon(
                                    AppIcons.successIcon,
                                    key: const ValueKey('valid-phone'),
                                    color: context.signalPrimary,
                                    size: 20,
                                  )
                                : const SizedBox(
                                    key: ValueKey('empty-phone'),
                                    width: 20,
                                    height: 20,
                                  ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                            final digits = v.replaceAll('-', '');
                            if (digits.length != 11 || !digits.startsWith('03')) {
                              return 'Enter a valid Pakistani number (03XX-XXXXXXX)';
                            }
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
                          focusNode: _passFocus,
                          textInputAction: TextInputAction.done, // UX4-08
                          autofillHints: const [AutofillHints.password],
                          semanticsLabel: 'Password',
                          semanticsHint: 'Enter your account password',
                          onFieldSubmitted: (_) => _login(),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
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
                    ),
                    // Device conflict panel — shown when another device is bound
                    if (authState.isDeviceConflict) ...[
                      const SizedBox(height: 14),
                      _DeviceConflictPanel(deviceName: authState.deviceConflictName ?? 'another device')
                          .animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, duration: 300.ms),
                    ] else if (_error != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        label: 'Sign-in error: $_error',
                        child: _ErrorBanner(message: _error!),
                      ).animate().fadeIn(
                            duration: reduceMotion ? Duration.zero : 250.ms,
                          ).shakeX(
                            hz: reduceMotion ? 0 : 3,
                            amount: reduceMotion ? 0 : 4,
                          ),
                    ],
                    SizedBox(height: 28),
                    Row(
                      children: [
                        Icon(AppIcons.shield, color: context.signalPrimary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your account stays private and synced to one device.',
                            style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ],
                    ).animate(delay: 290.ms).fadeIn(duration: 300.ms),
                    const SizedBox(height: 16),
                    // Sign In Button
                    RaddButton(
                      label: 'Sign In',
                      onPressed: _loading ? null : _login,
                      loading: _loading,
                      fullWidth: true,
                    )
                        .animate(delay: 320.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                    SizedBox(height: 12),
                    // Guest
                    RaddButton(
                      variant: RaddButtonVariant.ghost,
                      label: 'Continue as Guest',
                      onPressed: _loading ? null : _guest,
                      fullWidth: true,
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
                                  style: TextStyle(
                                      color: context.signalPrimary, fontWeight: FontWeight.w700)),
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
        'https://wa.me/${appContainer.read(remoteValuesProvider).supportWhatsApp}?text=$msg');
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
        borderRadius: RaddRadius.mdRadius,
        border: Border.all(color: AppColors.warningDark.withOpacity(0.4), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(AppIcons.devices, color: AppColors.warning, size: 18),
          SizedBox(width: 8),
          Text('Device Conflict',
              style: TextStyle(color: AppColors.warning, fontSize: 14,
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
            Expanded(child: Divider(color: t.border)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('or switch yourself',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
            ),
            Expanded(child: Divider(color: t.border)),
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
              child: RaddButton(
                variant: RaddButtonVariant.tonal,
                label: 'Send OTP to My Number',
                loading: _otpLoading,
                onPressed: _otpLoading ? null : _requestOtp,
                fullWidth: true,
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
              child: RaddButton(
                variant: RaddButtonVariant.tonal,
                label: 'Verify & Switch Device',
                loading: _otpLoading,
                onPressed: _otpLoading ? null : _verifyOtp,
                fullWidth: true,
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
                style: TextStyle(color: context.accentError, fontSize: 12)),
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
              colors: [AppColors.primary, AppColors.primaryDark],
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
              TextSpan(text: 'Flix', style: TextStyle(color: context.signalPrimary)),
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
        color: context.accentError.withOpacity(0.1),
        borderRadius: RaddRadius.smRadius,
        border: Border.all(color: context.accentError.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(AppIcons.errorIcon, color: context.accentError, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: TextStyle(color: context.accentError, fontSize: 13))),
        ],
      ),
    );
  }
}

// _GradientButton removed — Phase F: replaced with RaddButton.signal.
