import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/vault_service.dart';

class VaultLockScreen extends StatefulWidget {
  final bool isSetup;
  const VaultLockScreen({super.key, this.isSetup = false});
  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen>
    with SingleTickerProviderStateMixin {
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

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
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

  void _onKey(String digit) {
    if (_loading) return;
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    final current = _confirming ? _confirmPin : _pin;
    if (current.length >= _expectedPinLength) return;
    setState(() {
      _error = false;
      if (_confirming) {
        _confirmPin = _confirmPin + digit;
      } else {
        _pin = _pin + digit;
      }
    });
    if (!_confirming && _pin.length == _expectedPinLength) _submit();
    if (_confirming && _confirmPin.length == _expectedPinLength) _submit();
  }

  void _onBackspace() {
    setState(() {
      _error = false;
      if (_confirming && _confirmPin.isNotEmpty) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else if (!_confirming && _pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
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
    _shakeCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _confirmPin : _pin;
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
                      icon: const Icon(Icons.close, color: Colors.white54),
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
                        child: const Icon(Icons.lock_rounded, color: Colors.white, size: 26),
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

            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_expectedPinLength, (i) {
                  final filled = i < current.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 16 : 14,
                    height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _error
                          ? Colors.red
                          : filled
                              ? const Color(0xFF7C5CFF)
                              : Colors.white24,
                      boxShadow: filled && !_error
                          ? [const BoxShadow(
                              color: Color(0x807C5CFF),
                              blurRadius: 8, spreadRadius: 1,
                            )]
                          : null,
                    ),
                  );
                }),
              ),
            ),

            if (_error) ...[
              const SizedBox(height: 12),
              Text(
                _errorMsg,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ).animate().shakeX(),
            ],

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    for (final row in [
                      ['1','2','3'],
                      ['4','5','6'],
                      ['7','8','9'],
                      ['bio','0','⌫'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: row.map((k) {
                            if (k == 'bio') {
                              // FIX-VAULT-05: show fingerprint button ONLY when
                              // BOTH available (hardware exists + enrolled) AND
                              // user explicitly enabled it in Vault Settings.
                              return _biometricAvailable && _biometricEnabled && !widget.isSetup
                                  ? _NumKey(
                                      child: const Icon(Icons.fingerprint_rounded,
                                          color: Colors.white, size: 28),
                                      onTap: _tryBiometric,
                                    )
                                  : const SizedBox(width: 80, height: 64);
                            }
                            if (k == '⌫') {
                              return _NumKey(
                                child: const Icon(Icons.backspace_outlined,
                                    color: Colors.white, size: 22),
                                onTap: _onBackspace,
                                onLongPress: () => setState(() {
                                  _pin = ''; _confirmPin = '';
                                }),
                              );
                            }
                            return _NumKey(
                              child: Text(k, style: const TextStyle(
                                color: Colors.white, fontSize: 26,
                                fontWeight: FontWeight.w300,
                              )),
                              onTap: () => _onKey(k),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
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

class _NumKey extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _NumKey({required this.child, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      onLongPress: onLongPress,
      child: Container(
        width: 80, height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF12151E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E2530)),
        ),
        child: Center(child: child),
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
      const Icon(Icons.timer_outlined, color: Colors.white38, size: 48),
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
