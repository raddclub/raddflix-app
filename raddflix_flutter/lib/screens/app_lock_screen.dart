/// App-level PIN / biometric lock screen and setup screens.
///
/// [AppLockScreen]         — overlay widget (not a route) rendered by _AppLockGuard
///                           in app.dart while the app is locked.
/// [AppLockSetupScreen]    — route: first-time PIN setup. Returns true on success.
/// [AppLockChangePinScreen]— route: change PIN (verify old → enter new → confirm new).
///                           Returns true on success.
library app_lock_screen;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/components/radd_lock_pad.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/typography/radd_type.dart';
import '../services/app_lock_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AppLockScreen — renders as the full app overlay while locked
// ══════════════════════════════════════════════════════════════════════════════

class AppLockScreen extends StatefulWidget {
  /// Called after the PIN is verified or biometric passes successfully.
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _loading           = false;
  bool _error             = false;
  String _errorMsg        = '';
  bool _biometricAvailable = false;
  bool _biometricEnabled   = false;
  int  _pinLength          = 4;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bioAvail   = await AppLockService.isBiometricAvailable();
    final bioEnabled = await AppLockService.isBiometricEnabled();
    final pinLen     = await AppLockService.getPinLength();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = bioAvail;
      _biometricEnabled   = bioEnabled;
      _pinLength          = pinLen;
    });
    // Auto-trigger biometric prompt on open if both available and enabled.
    if (bioAvail && bioEnabled) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    setState(() => _loading = true);
    try {
      final ok = await AppLockService.authenticateBiometric();
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) widget.onUnlocked();
    } on BiometricHardwareException catch (e) {
      if (!mounted) return;
      // Hardware can't do biometric on this device — show the error and hide
      // the fingerprint button so the user knows they must use their PIN.
      setState(() {
        _loading            = false;
        _biometricAvailable = false;
        _error              = true;
        _errorMsg           = e.message;
      });
    }
  }

  Future<void> _onPinSubmit(String code) async {
    if (_loading) return;
    setState(() => _loading = true);
    final ok = await AppLockService.checkPin(code);
    if (!mounted) return;
    if (ok) {
      AppLockService.unlock();
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _loading  = false;
        _error    = true;
        _errorMsg = 'Wrong PIN. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope prevents the back gesture from dismissing the lock screen.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top spacer + logo + title ─────────────────────────────────
              const Spacer(),
              _AppLockHeader(loading: _loading),
              const SizedBox(height: RaddSpace.xl),

              // ── PIN pad ───────────────────────────────────────────────────
              RaddLockPad(
                key: const ValueKey('app-lock-pad'),
                pinLength: _pinLength,
                accent: RaddLockPadAccent.standard,
                onSubmit: _loading ? (_) {} : _onPinSubmit,
                errorText: _error ? _errorMsg : null,
                showBiometric: _biometricAvailable && _biometricEnabled,
                onBiometricTap: _tryBiometric,
                onChanged: (_) {
                  if (_error) setState(() => _error = false);
                },
              ),

              const Spacer(),
              const SizedBox(height: RaddSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated lock-icon + title / subtitle ─────────────────────────────────────
class _AppLockHeader extends StatelessWidget {
  final bool loading;
  const _AppLockHeader({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glowing shield icon — mirrors vault lock screen style
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.signalPrimary.withOpacity(0.10),
            border: Border.all(
                color: context.signalPrimary.withOpacity(0.35), width: 1.5),
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(context.signalPrimary),
                  ),
                )
              : Icon(AppIcons.lock,
                  color: context.signalPrimary, size: 30),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: RaddSpace.md),
        Text(
          'RaddFlix',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter your PIN to continue',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AppLockSetupScreen — first-time PIN setup; push as a route, returns bool
// ══════════════════════════════════════════════════════════════════════════════

class AppLockSetupScreen extends StatefulWidget {
  const AppLockSetupScreen({super.key});

  static Route<bool> route() =>
      MaterialPageRoute(builder: (_) => const AppLockSetupScreen());

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  String _first      = '';
  bool   _confirming = false;
  bool   _mismatch   = false;
  bool   _saving     = false;

  Future<void> _onSubmit(String code) async {
    if (!_confirming) {
      setState(() {
        _first      = code;
        _confirming = true;
        _mismatch   = false;
      });
      return;
    }
    if (code != _first) {
      HapticFeedback.mediumImpact();
      setState(() { _mismatch = true; _confirming = false; _first = ''; });
      return;
    }
    setState(() => _saving = true);
    await AppLockService.setPin(_first);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: RaddSpace.xl),
            Row(children: [
              IconButton(
                icon: Icon(AppIcons.back, color: t.textSecondary),
                onPressed: () {
                  if (_confirming) {
                    setState(() { _confirming = false; _first = ''; _mismatch = false; });
                  } else {
                    Navigator.of(context).pop(false);
                  }
                },
              ),
            ]),
            const Spacer(),
            Icon(AppIcons.shield,
                color: context.signalPrimary, size: 48),
            const SizedBox(height: RaddSpace.sm),
            Text(
              _confirming ? 'Confirm PIN' : 'Set App Lock PIN',
              style: context.raddHeadline.copyWith(color: t.textPrimary),
            ),
            const SizedBox(height: RaddSpace.xs),
            Text(
              _confirming
                  ? 'Re-enter your PIN to confirm'
                  : 'Choose a 4-digit PIN to lock the app',
              style: context.raddCaption.copyWith(color: t.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RaddSpace.lg),
            RaddLockPad(
              key: ValueKey('setup-${_confirming ? 'confirm' : 'enter'}'),
              pinLength: 4,
              accent: RaddLockPadAccent.standard,
              onSubmit: _saving ? (_) {} : _onSubmit,
              errorText: _mismatch ? "PINs didn't match — try again" : null,
              onChanged: (_) {
                if (_mismatch) setState(() => _mismatch = false);
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AppLockChangePinScreen — verify old PIN, then set a new one; returns bool
// ══════════════════════════════════════════════════════════════════════════════

enum _ChangePinStep { verifyOld, enterNew, confirmNew }

class AppLockChangePinScreen extends StatefulWidget {
  const AppLockChangePinScreen({super.key});

  static Route<bool> route() =>
      MaterialPageRoute(builder: (_) => const AppLockChangePinScreen());

  @override
  State<AppLockChangePinScreen> createState() => _AppLockChangePinScreenState();
}

class _AppLockChangePinScreenState extends State<AppLockChangePinScreen> {
  _ChangePinStep _step    = _ChangePinStep.verifyOld;
  String         _newPin  = '';
  bool           _error   = false;
  String         _errorMsg = '';
  bool           _saving  = false;

  Future<void> _onSubmit(String code) async {
    switch (_step) {
      case _ChangePinStep.verifyOld:
        final ok = await AppLockService.checkPin(code);
        if (!mounted) return;
        if (ok) {
          setState(() { _step = _ChangePinStep.enterNew; _error = false; });
        } else {
          HapticFeedback.heavyImpact();
          setState(() { _error = true; _errorMsg = 'Wrong PIN. Try again.'; });
        }
      case _ChangePinStep.enterNew:
        setState(() { _newPin = code; _step = _ChangePinStep.confirmNew; _error = false; });
      case _ChangePinStep.confirmNew:
        if (code != _newPin) {
          HapticFeedback.mediumImpact();
          setState(() { _error = true; _errorMsg = "PINs didn't match — try again"; _step = _ChangePinStep.enterNew; _newPin = ''; });
        } else {
          setState(() => _saving = true);
          await AppLockService.setPin(_newPin);
          if (mounted) Navigator.of(context).pop(true);
        }
    }
  }

  String get _title => switch (_step) {
    _ChangePinStep.verifyOld  => 'Enter Current PIN',
    _ChangePinStep.enterNew   => 'Enter New PIN',
    _ChangePinStep.confirmNew => 'Confirm New PIN',
  };

  String get _subtitle => switch (_step) {
    _ChangePinStep.verifyOld  => 'Verify your current app lock PIN',
    _ChangePinStep.enterNew   => 'Choose a 4-digit PIN',
    _ChangePinStep.confirmNew => 'Re-enter the new PIN to confirm',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: RaddSpace.xl),
            Row(children: [
              IconButton(
                icon: Icon(AppIcons.back, color: t.textSecondary),
                onPressed: () {
                  if (_step == _ChangePinStep.confirmNew) {
                    setState(() { _step = _ChangePinStep.enterNew; _newPin = ''; _error = false; });
                  } else if (_step == _ChangePinStep.enterNew) {
                    setState(() { _step = _ChangePinStep.verifyOld; _error = false; });
                  } else {
                    Navigator.of(context).pop(false);
                  }
                },
              ),
            ]),
            const Spacer(),
            Icon(AppIcons.lock, color: context.signalPrimary, size: 44),
            const SizedBox(height: RaddSpace.sm),
            Text(_title,
                style: context.raddHeadline.copyWith(color: t.textPrimary)),
            const SizedBox(height: RaddSpace.xs),
            Text(_subtitle,
                style: context.raddCaption.copyWith(color: t.textSecondary)),
            const SizedBox(height: RaddSpace.lg),
            RaddLockPad(
              key: ValueKey('change-${_step.name}'),
              pinLength: 4,
              accent: RaddLockPadAccent.standard,
              onSubmit: _saving ? (_) {} : _onSubmit,
              errorText: _error ? _errorMsg : null,
              onChanged: (_) {
                if (_error) setState(() => _error = false);
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
