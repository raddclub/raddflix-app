import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // TextInputFormatter for UX4-10
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:dio/dio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/loading_overlay.dart';
import '../design_system/components/radd_button.dart';
import '../design_system/components/radd_text_field.dart';
import '../core/utils/auth_utils.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

// UX4-10: Pakistani phone formatter (same instance used in LoginScreen)
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

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _phone      = TextEditingController();
  final _pass       = TextEditingController();
  final _confirm    = TextEditingController();
  final _phoneFocus   = FocusNode(); // UX4-08
  final _passFocus    = FocusNode(); // UX4-08
  final _confirmFocus = FocusNode(); // UX4-08
  bool _obscure   = true;
  bool _loading   = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose(); _pass.dispose(); _confirm.dispose();
    _phoneFocus.dispose(); _passFocus.dispose(); _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      // UX4-10: strip formatter hyphen before sending to API
      final rawPhone = _phone.text.replaceAll('-', '').trim();
      await ref.read(authProvider.notifier).register(phone: rawPhone, password: _pass.text);
      // Auto-login immediately so the user goes straight to the home screen.
      await ref.read(authProvider.notifier).login(
          phone: rawPhone, password: _pass.text);
      if (!mounted) return;
      // BUG-REGISTER-01: auth_provider.login() handles errors internally and
      // never throws — must explicitly check state after the call (same fix
      // already applied to login_screen.dart for the same root cause).
      final s = ref.read(authProvider);
      if (s.isDeviceConflict) {
        setState(() { _error = 'Account already active on another device. Contact support.'; _loading = false; });
        return;
      }
      if (s.error != null) {
        setState(() { _error = s.error; _loading = false; });
        return;
      }
      await navigateAfterAuth(context, ref);
    } on DioException catch (e) {
      final _errData = e.response?.data;
      final serverMsg = (_errData is Map
          ? ((_errData['error'] ?? _errData['message']) as String?)
          : (_errData is String && _errData.isNotEmpty ? _errData : null));
      final _isNetErr = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      setState(() {
        _error = _isNetErr
            ? 'Cannot connect. Check your internet connection.'
            : (serverMsg ?? AuthErrors.register(e.toString()));
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = AuthErrors.register(e.toString()); _loading = false; });
    }
  }

  Future<void> _guest() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).continueAsGuest();
      if (mounted) await navigateAfterAuth(context, ref);
    } catch (e) {
      setState(() { _error = 'Cannot connect. Check your internet.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return LoadingOverlay(
      loading: _loading,
      child: Scaffold(
        backgroundColor: null,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(AppIcons.back, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Stack(
          children: [
            Positioned(top: -120, right: -80,
              child: Container(width: 280, height: 280,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [context.signalPrimary.withOpacity(0.12), Colors.transparent])))),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 8),
                  Text('Create Account',
                      style: TextStyle(color: t.textPrimary, fontSize: 28,
                          fontWeight: FontWeight.w800, letterSpacing: -0.5))
                      .animate().fadeIn(duration: 400.ms)
                      .slideX(begin: -0.2, end: 0, duration: 400.ms, curve: AppCurves.standard),
                  SizedBox(height: 6),
                  Text('Join RaddFlix — free for Jazz SIM users',
                      style: TextStyle(color: t.textMuted, fontSize: 14))
                      .animate(delay: 80.ms).fadeIn(duration: 400.ms),
                  SizedBox(height: 32),
                  Form(key: _formKey, child: Column(children: [
                    RaddTextField(controller: _phone, label: 'Phone Number',
                        hint: '03XX-XXXXXXX', keyboardType: TextInputType.phone,
                        prefixIcon: AppIcons.phone,
                        focusNode: _phoneFocus,
                        textInputAction: TextInputAction.next, // UX4-08
                        inputFormatters: [_PhoneFormatter()],  // UX4-10
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(_passFocus),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                          final digits = v.replaceAll('-', '');
                          if (digits.length != 11 || !digits.startsWith('03')) {
                            return 'Enter a valid Pakistani number (03XX-XXXXXXX)';
                          }
                          return null;
                        })
                        .animate(delay: 120.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                    SizedBox(height: 14),
                    RaddTextField(controller: _pass, label: 'Password',
                        obscureText: _obscure, prefixIcon: AppIcons.lock,
                        focusNode: _passFocus,
                        textInputAction: TextInputAction.next, // UX4-08
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(_confirmFocus),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
                              color: t.textMuted, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure)),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter a password';
                          if (v.length < 8) return 'Min 8 characters';
                          return null;
                        })
                        .animate(delay: 180.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                    const SizedBox(height: 14),
                    RaddTextField(controller: _confirm, label: 'Confirm Password',
                        obscureText: _obscure, prefixIcon: AppIcons.lock,
                        focusNode: _confirmFocus,
                        textInputAction: TextInputAction.done, // UX4-08
                        onFieldSubmitted: (_) => _register(),
                        validator: (v) {
                          if (v != _pass.text) return 'Passwords do not match';
                          return null;
                        })
                        .animate(delay: 240.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                  ])),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: context.accentError.withOpacity(0.1),
                          borderRadius: RaddRadius.smRadius,
                          border: Border.all(color: context.accentError.withOpacity(0.3))),
                      child: Row(children: [
                        Icon(AppIcons.errorIcon, color: context.accentError, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: TextStyle(color: context.accentError, fontSize: 13))),
                      ]),
                    ).animate().fadeIn(duration: 250.ms).shakeX(hz: 3, amount: 4),
                  ],
                  const SizedBox(height: 28),
                  RaddButton(
                    label: 'Create Account',
                    onPressed: _loading ? null : _register,
                    loading: _loading,
                    fullWidth: true,
                  )
                      .animate(delay: 300.ms).fadeIn(duration: 350.ms)
                      .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                  SizedBox(height: 12),
                  RaddButton(
                    variant: RaddButtonVariant.ghost,
                    label: 'Continue as Guest',
                    onPressed: _loading ? null : _guest,
                    fullWidth: true,
                  )
                      .animate(delay: 350.ms).fadeIn(duration: 300.ms),
                  SizedBox(height: 20),
                  Center(child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text.rich(TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: t.textMuted, fontSize: 14),
                        children: [TextSpan(text: 'Sign In',
                            style: TextStyle(color: context.signalPrimary, fontWeight: FontWeight.w700))])),
                  )).animate(delay: 400.ms).fadeIn(duration: 300.ms),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
