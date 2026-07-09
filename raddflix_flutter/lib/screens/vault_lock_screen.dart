import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../design_system/components/radd_lock_pad.dart';
import '../services/vault_service.dart';

class VaultLockScreen extends StatefulWidget {
  final bool isSetup;
  const VaultLockScreen({super.key, this.isSetup = false});
  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  String _pin = '';
  String _confirmPin = '';
  bool _confirming = false;
  bool _error = false;
  String _errorMsg = '';
  bool _loading = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  int _expectedPinLength = 6;
  int _pinLengthChoice = 6;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final biAvail = await VaultService.isBiometricAvailable();
    final biEnabled = await VaultService.isBiometricEnabled();
    final info = await VaultService.getLockoutInfo();
    if (mounted) {
      setState(() {
        _biometricAvailable = biAvail;
        _biometricEnabled = biEnabled;
        _failedAttempts = info.attempts;
        _lockedUntil = info.lockedUntil;
      });
    }
    if (!widget.isSetup) {
      final pinLen = await VaultService.getPinLength();
      if (mounted) setState(() => _expectedPinLength = pinLen);
    }
    // FIX-VAULT-05: only auto-trigger biometric if BOTH available AND enabled
    if (!widget.isSetup && biAvail && biEnabled) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    setState(() => _loading = true);
    final ok = await VaultService.authenticateBiometric(context);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) Navigator.of(context).pushReplacementNamed(AppRoutes.vault);
  }

  /// Called by `RaddLockPad` once the active field (PIN, or confirm-PIN
  /// during setup) reaches `_expectedPinLength` digits.
  Future<void> _onLockPadSubmit(String code) async {
    if (_loading) return;
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    setState(() {
      _error = false;
      if (_confirming) {
        _confirmPin = code;
      } else {
        _pin = code;
      }
    });
    await _submit();
  }

  Future<void> _submit() async {
    final current = _confirming ? _confirmPin : _pin;
    if (current.length < VaultService.minPinLength) return;

    if (widget.isSetup) {
      if (!_confirming) {
        setState(() { _confirming = true; _confirmPin = ''; });
        return;
      }
      if (_pin != _confirmPin) {
        _shake('PINs do not match. Try again.');
        setState(() { _confirming = false; _pin = ''; _confirmPin = ''; });
        return;
      }
      setState(() => _loading = true);
      await VaultService.setPin(_pin);
      if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.vault);
      return;
    }

    setState(() => _loading = true);
    try {
      final ok = await VaultService.checkPin(_pin);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.vault);
      } else {
        final info = await VaultService.getLockoutInfo();
        _shake(info.lockedUntil != null
            ? 'Too many attempts. ${VaultLockedException(info.lockedUntil!).message}'
            : 'Wrong PIN. ${info.attempts >= 3 ? "${5 - info.attempts} attempt${5 - info.attempts == 1 ? '' : 's'} left" : ""}');
        setState(() {
          _pin = '';
          _loading = false;
          _failedAttempts = info.attempts;
          _lockedUntil = info.lockedUntil;
        });
      }
    } on VaultLockedException catch (e) {
      _shake(e.message);
      setState(() { _pin = ''; _loading = false; });
    }
  }

  void _shake(String msg) {
    HapticFeedback.heavyImpact();
    setState(() { _error = true; _errorMsg = msg; });
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      icon: Icon(AppIcons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  Column(
                    children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C5CFF), AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(
                            color: const Color(0xFF7C5CFF).withOpacity(0.4),
                            blurRadius: 20, spreadRadius: 2,
                          )],
                        ),
                        child: Icon(AppIcons.lock, color: Colors.white, size: 26),
                      ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 10),
                      Text(
                        widget.isSetup
                            ? (_confirming ? 'Confirm PIN' : 'Set a PIN')
                            : 'Private Vault',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isSetup
                            ? (_confirming ? 'Re-enter your PIN to confirm' : 'Choose a ${_pinLengthChoice}-digit PIN')
                            : isLocked
                                ? VaultLockedException(_lockedUntil!).message
                                : 'Enter your PIN to continue',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Spacer(),

            if (widget.isSetup && !_confirming)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('PIN length:', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(width: 16),
                    for (final len in [4, 6])
                      GestureDetector(
                        onTap: () => setState(() {
                          _pinLengthChoice = len;
                          _expectedPinLength = len;
                          _pin = ''; _confirmPin = '';
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: _pinLengthChoice == len
                                ? const Color(0xFF7C5CFF)
                                : const Color(0xFF12151E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _pinLengthChoice == len
                                  ? const Color(0xFF7C5CFF)
                                  : const Color(0xFF1E2530),
                            ),
                          ),
                          child: Text(
                            '$len digits',
                            style: TextStyle(
                              color: _pinLengthChoice == len ? Colors.white : Colors.white54,
                              fontSize: 14,
                              fontWeight: _pinLengthChoice == len
                                  ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            if (!isLocked)
              // RaddLockPad manages the dot row + numpad + its own entered-digits
              // state; `key` is bumped whenever the active field or expected
              // length changes so the pad's internal buffer resets cleanly.
              RaddLockPad(
                key: ValueKey('$_confirming-$_expectedPinLength'),
                pinLength: _expectedPinLength,
                accent: RaddLockPadAccent.vault,
                onSubmit: _onLockPadSubmit,
                errorText: _error ? _errorMsg : null,
                showBiometric:
                    _biometricAvailable && _biometricEnabled && !widget.isSetup,
                onBiometricTap: _tryBiometric,
              )
            else
              _LockedOutTimer(until: _lockedUntil!, onExpired: () {
                setState(() => _lockedUntil = null);
              }),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _LockedOutTimer extends StatefulWidget {
  final DateTime until;
  final VoidCallback onExpired;
  const _LockedOutTimer({required this.until, required this.onExpired});
  @override
  State<_LockedOutTimer> createState() => _LockedOutTimerState();
}

class _LockedOutTimerState extends State<_LockedOutTimer> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    if (!mounted) return;
    final rem = widget.until.difference(DateTime.now());
    if (rem.isNegative) { widget.onExpired(); return; }
    setState(() => _remaining = rem);
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds % 60;
    return Column(children: [
      Icon(AppIcons.timerIcon, color: Colors.white38, size: 48),
      const SizedBox(height: 12),
      Text(
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
        style: const TextStyle(color: Colors.white70, fontSize: 40,
            fontWeight: FontWeight.w200, letterSpacing: 4),
      ),
      const SizedBox(height: 8),
      const Text('Too many attempts\nTry again when timer expires',
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center),
    ]);
  }
}
