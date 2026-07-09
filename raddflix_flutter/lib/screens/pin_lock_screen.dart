/// Phase K3 — Watch History PIN Lock
/// Shown before history/vault screens on shared devices.
/// PIN stored via flutter_secure_storage (already in pubspec).
///
/// UI migrated 2026-07-09 (UI-UX-MIGRATION Phase 2) onto the shared
/// `RaddLockPad` component (Volume IV) — do not reintroduce a bespoke
/// numpad here; extend `RaddLockPad` instead if new behavior is needed.
library pin_lock;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/components/radd_lock_pad.dart';
import '../design_system/spacing/radd_space.dart';

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

  const PinLockScreen({super.key, this.title = 'Enter PIN'});

  static Route<bool> route({String title = 'Enter PIN'}) =>
      MaterialPageRoute(builder: (_) => PinLockScreen(title: title));

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  bool _wrong = false;
  bool _loading = false;

  Future<void> _onSubmit(String code) async {
    setState(() => _loading = true);
    final ok = await PinLockService.instance.verify(code);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.mediumImpact();
      setState(() {
        _wrong = true;
        _loading = false;
      });
    }
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
                icon: Icon(AppIcons.close, color: t.textSecondary),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ]),
            const Spacer(),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.signalPrimary.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: context.signalPrimary.withOpacity(0.4), width: 1.5),
              ),
              child: Icon(AppIcons.lock, color: context.signalPrimary, size: 32),
            ),
            const SizedBox(height: RaddSpace.md),
            Text(widget.title, style: context.raddHeadline.copyWith(color: t.textPrimary)),
            const SizedBox(height: RaddSpace.xl),
            RaddLockPad(
              pinLength: 4,
              accent: RaddLockPadAccent.standard,
              onSubmit: _loading ? (_) {} : _onSubmit,
              errorText: _wrong ? 'Incorrect PIN' : null,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ── PIN Setup screen ──────────────────────────────────────────────────────────
/// Two-step PIN setup (enter + confirm). Returns true when PIN is saved.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  static Route<bool> route() => MaterialPageRoute(builder: (_) => const PinSetupScreen());

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  bool _confirming = false;
  bool _mismatch = false;

  Future<void> _onSubmit(String code) async {
    if (!_confirming) {
      setState(() {
        _first = code;
        _confirming = true;
        _mismatch = false;
      });
      return;
    }
    if (code != _first) {
      HapticFeedback.mediumImpact();
      setState(() {
        _confirming = false;
        _first = '';
        _mismatch = true;
      });
      return;
    }
    await PinLockService.instance.setPin(_first);
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
                    setState(() {
                      _confirming = false;
                      _first = '';
                    });
                  } else {
                    Navigator.of(context).pop(false);
                  }
                },
              ),
            ]),
            const Spacer(),
            Icon(AppIcons.shield, color: context.signalPrimary, size: 48),
            const SizedBox(height: RaddSpace.sm),
            Text(
              _confirming ? 'Confirm PIN' : 'Set a 4-digit PIN',
              style: context.raddHeadline.copyWith(color: t.textPrimary),
            ),
            const SizedBox(height: RaddSpace.xs),
            Text(
              _confirming ? 'Enter the same PIN again' : 'For Watch History access on shared devices',
              style: context.raddCaption.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: RaddSpace.lg),
            RaddLockPad(
              key: ValueKey(_confirming),
              pinLength: 4,
              accent: RaddLockPadAccent.standard,
              onSubmit: _onSubmit,
              errorText: _mismatch ? "PINs didn't match — try again" : null,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
