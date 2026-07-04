/// Phase K3 — Watch History PIN Lock
/// Shown before history/vault screens on shared devices.
/// PIN stored via flutter_secure_storage (already in pubspec).
library pin_lock;

import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kPinKey = 'radd_history_pin';

// ── PIN management helpers ────────────────────────────────────────────────────
class PinLockService {
  PinLockService._();
  static final instance = PinLockService._();
  static const _storage = FlutterSecureStorage();

  Future<bool> isPinSet() async {
    final p = await _storage.read(key: _kPinKey);
    return p != null && p.isNotEmpty;
  }

  Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _kPinKey);
    return stored == pin;
  }

  Future<void> setPin(String pin) => _storage.write(key: _kPinKey, value: pin);

  Future<void> clearPin() => _storage.delete(key: _kPinKey);
}

// ─────────────────────────────────────────────────────────────────────────────
/// Full-screen PIN entry. Returns `true` when the PIN is verified (or not set).
/// Usage: `await Navigator.of(ctx).push(PinLockScreen.route())`
class PinLockScreen extends StatefulWidget {
  final String title;
  final Color accentColor;

  const PinLockScreen({
    super.key,
    this.title = 'Enter PIN',
    this.accentColor = const Color(0xFFE8002D),
  });

  static Route<bool> route({String title = 'Enter PIN', Color? accentColor}) =>
      MaterialPageRoute(builder: (_) => PinLockScreen(
        title: title,
        accentColor: accentColor ?? const Color(0xFFE8002D),
      ));

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _input = '';
  bool _wrong = false;
  bool _loading = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        duration: const Duration(milliseconds: 400), vsync: this);
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -8.0, end:  8.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin:  8.0, end:  0.0), weight: 40),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (_input.length >= 6 || _loading) return;
    HapticFeedback.selectionClick();
    setState(() { _input += digit; _wrong = false; });
    if (_input.length == 4) _verify();
  }

  void _backspace() {
    if (_input.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final ok = await PinLockService.instance.verify(_input);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.mediumImpact();
      await _shakeCtrl.forward();
      _shakeCtrl.reset();
      setState(() { _input = ''; _wrong = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 32),
          // Back button
          Row(children: [
            IconButton(
              icon: const Icon(AppIcons.close, color: Colors.white54),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ]),
          const Spacer(),
          // Lock icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: widget.accentColor.withOpacity(0.4), width: 1.5)),
            child: Icon(AppIcons.lock,
                color: widget.accentColor, size: 32),
          ),
          const SizedBox(height: 16),
          Text(widget.title,
              style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child),
            child: Column(children: [
              if (_wrong)
                const Text('Incorrect PIN',
                    style: TextStyle(color: Color(0xFFE8002D), fontSize: 12)),
              const SizedBox(height: 16),
              // PIN dots
              Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                final filled = i < _input.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? widget.accentColor : Colors.white12,
                    border: Border.all(
                        color: filled ? widget.accentColor : Colors.white38,
                        width: 1.5)),
                );
              })),
            ]),
          ),
          const Spacer(),
          // Numpad
          _buildNumpad(),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildNumpad() {
    final keys = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
      ['','0','⌫'],
    ];
    return Column(
      children: keys.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) => _key(k)).toList(),
      )).toList(),
    );
  }

  Widget _key(String label) {
    if (label.isEmpty) return const SizedBox(width: 80, height: 72);
    return GestureDetector(
      onTap: label == '⌫' ? _backspace : () => _press(label),
      child: Container(
        width: 80, height: 72,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: label == '⌫'
              ? const Icon(AppIcons.backspace, color: Colors.white54, size: 22)
              : Text(label,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 26, fontWeight: FontWeight.w400)),
        ),
      ),
    );
  }
}

// ── PIN Setup screen ──────────────────────────────────────────────────────────
/// Two-step PIN setup (enter + confirm). Returns true when PIN is saved.
class PinSetupScreen extends StatefulWidget {
  final Color accentColor;
  const PinSetupScreen({super.key, this.accentColor = const Color(0xFFE8002D)});

  static Route<bool> route({Color? accentColor}) => MaterialPageRoute(
      builder: (_) => PinSetupScreen(
          accentColor: accentColor ?? const Color(0xFFE8002D)));

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _second = '';
  bool _confirming = false;
  bool _mismatch = false;

  void _press(String digit) {
    final current = _confirming ? _second : _first;
    if (current.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_confirming) _second += digit;
      else _first += digit;
      _mismatch = false;
    });
    if ((_confirming ? _second : _first).length == 4) {
      if (_confirming) _save();
      else setState(() => _confirming = true);
    }
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_confirming) {
        if (_second.isNotEmpty) _second = _second.substring(0, _second.length - 1);
        else { _confirming = false; }
      } else {
        if (_first.isNotEmpty) _first = _first.substring(0, _first.length - 1);
      }
    });
  }

  Future<void> _save() async {
    if (_first != _second) {
      HapticFeedback.mediumImpact();
      setState(() { _second = ''; _mismatch = true; });
      return;
    }
    await PinLockService.instance.setPin(_first);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final input = _confirming ? _second : _first;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 32),
          Row(children: [
            IconButton(
              icon: const Icon(AppIcons.back, color: Colors.white54),
              onPressed: () {
                if (_confirming) setState(() { _confirming = false; _second = ''; });
                else Navigator.of(context).pop(false);
              },
            ),
          ]),
          const Spacer(),
          Icon(AppIcons.shield, color: widget.accentColor, size: 48),
          const SizedBox(height: 12),
          Text(
            _confirming ? 'Confirm PIN' : 'Set a 4-digit PIN',
            style: const TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _confirming ? 'Enter the same PIN again' : 'For Watch History access on shared devices',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (_mismatch) ...[
            const SizedBox(height: 6),
            const Text("PINs didn't match — try again",
                style: TextStyle(color: Color(0xFFE8002D), fontSize: 12)),
          ],
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
            final filled = i < input.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? widget.accentColor : Colors.white12,
                border: Border.all(
                    color: filled ? widget.accentColor : Colors.white38,
                    width: 1.5)),
            );
          })),
          const Spacer(),
          _buildNumpad(),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildNumpad() {
    final keys = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']];
    return Column(children: keys.map((row) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: row.map((k) {
        if (k.isEmpty) return const SizedBox(width: 80, height: 72);
        return GestureDetector(
          onTap: k == '⌫' ? _backspace : () => _press(k),
          child: Container(
            width: 80, height: 72,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              shape: BoxShape.circle),
            child: Center(child: k == '⌫'
              ? const Icon(AppIcons.backspace, color: Colors.white54, size: 22)
              : Text(k, style: const TextStyle(color: Colors.white,
                    fontSize: 26, fontWeight: FontWeight.w400))),
          ),
        );
      }).toList(),
    )).toList());
  }
}
