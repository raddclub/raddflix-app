import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/radd_text_field.dart';
import '../core/utils/auth_utils.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _phone    = TextEditingController();
  final _pass     = TextEditingController();
  final _confirm  = TextEditingController();
  bool _obscure   = true;
  bool _loading   = false;
  String? _error;

  @override
  void dispose() { _phone.dispose(); _pass.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(phone: _phone.text.trim(), password: _pass.text);
      // Auto-login immediately so the user goes straight to the home screen.
      await ref.read(authProvider.notifier).login(
          phone: _phone.text.trim(), password: _pass.text);
      if (!mounted) return;
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
                  gradient: RadialGradient(colors: [AppColors.primary.withOpacity(0.12), Colors.transparent])))),
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
                        hint: '03001234567', keyboardType: TextInputType.phone,
                        prefixIcon: AppIcons.phone,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                          final digits = v.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
                          if (digits.length != 11) return 'Enter 11-digit number (e.g. 03001234567)';
                          if (!RegExp(r'^03\d{9}$').hasMatch(digits)) return 'Must be a Pakistani mobile number (03XX-XXXXXXX)';
                          return null;
                        })
                        .animate(delay: 120.ms).fadeIn(duration: 350.ms)
                        .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                    SizedBox(height: 14),
                    RaddTextField(controller: _pass, label: 'Password',
                        obscureText: _obscure, prefixIcon: AppIcons.lock,
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
                      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.error.withOpacity(0.3))),
                      child: Row(children: [
                        Icon(AppIcons.errorIcon, color: AppColors.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                      ]),
                    ).animate().fadeIn(duration: 250.ms).shakeX(hz: 3, amount: 4),
                  ],
                  const SizedBox(height: 28),
                  Container(height: 52,
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: AppShadows.primary),
                    child: Material(color: Colors.transparent,
                      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: _loading ? null : _register,
                        child: Center(child: Text('Create Account',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))))))
                      .animate(delay: 300.ms).fadeIn(duration: 350.ms)
                      .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
                  SizedBox(height: 12),
                  OutlinedButton(onPressed: _loading ? null : _guest,
                      child: Text('Continue as Guest'))
                      .animate(delay: 350.ms).fadeIn(duration: 300.ms),
                  SizedBox(height: 20),
                  Center(child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text.rich(TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: t.textMuted, fontSize: 14),
                        children: [TextSpan(text: 'Sign In',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))])),
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