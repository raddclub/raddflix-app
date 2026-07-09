import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import 'add_edit_profile_screen.dart';

Color hexToColor(String h) {
  final s = h.replaceAll('#', '');
  return Color(int.parse('FF$s', radix: 16));
}

/// "Who's Watching?" — shown after login (when the account has more than one
/// profile) and reachable any time from Settings → Switch Profile.
class ProfileSwitcherScreen extends ConsumerStatefulWidget {
  const ProfileSwitcherScreen({super.key});

  @override
  ConsumerState<ProfileSwitcherScreen> createState() => _ProfileSwitcherScreenState();
}

class _ProfileSwitcherScreenState extends ConsumerState<ProfileSwitcherScreen> {
  bool _managing = false;
  bool _switching = false;

  Future<void> _selectProfile(Profile p) async {
    if (_switching) return;
    if (_managing) {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AddEditProfileScreen(existing: p)),
      );
      if (result == true) await ref.read(profileProvider.notifier).load();
      return;
    }

    setState(() => _switching = true);
    bool ok = true;
    if (p.isLocked) {
      final pin = await _askPin(p);
      if (pin == null) { setState(() => _switching = false); return; }
      ok = await ref.read(profileProvider.notifier).selectProfile(p.id, pin: pin);
    } else {
      ok = await ref.read(profileProvider.notifier).selectProfile(p.id);
    }

    if (!mounted) return;
    if (!ok) {
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN'), backgroundColor: AppColors.error),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    // Force a fresh Home so per-profile watchlist / continue-watching / resume
    // widgets reload for the newly active profile.
    ref.read(watchlistProvider.notifier).load();
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<String?> _askPin(Profile p) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinEntrySheet(profile: p),
    );
  }

  Future<void> _addProfile() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddEditProfileScreen()),
    );
    if (result == true) await ref.read(profileProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final state = ref.watch(profileProvider);
    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: canPop
            ? AppBar(
                backgroundColor: t.bg,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(AppIcons.close, color: t.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Who's Watching?",
                      style: TextStyle(color: t.textPrimary, fontSize: 28,
                          fontWeight: FontWeight.w800))
                      .animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
                  const SizedBox(height: RaddSpace.sm),
                  Text(_managing ? 'Tap a profile to edit it' : 'Select a profile to continue',
                      style: TextStyle(color: t.textMuted, fontSize: 14))
                      .animate(delay: 60.ms).fadeIn(),
                  const SizedBox(height: 36),
                  Wrap(
                    spacing: 20, runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      for (int i = 0; i < state.profiles.length; i++)
                        _ProfileTile(
                          profile: state.profiles[i],
                          isActive: state.active?.id == state.profiles[i].id,
                          managing: _managing,
                          onTap: () => _selectProfile(state.profiles[i]),
                        ).animate(delay: (100 + i * 60).ms).fadeIn().slideY(begin: 0.2, end: 0),
                      if (state.profiles.length < kMaxProfiles)
                        _AddProfileTile(onTap: _addProfile)
                            .animate(delay: (100 + state.profiles.length * 60).ms).fadeIn(),
                    ],
                  ),
                  const SizedBox(height: 40),
                  TextButton.icon(
                    onPressed: () => setState(() => _managing = !_managing),
                    icon: Icon(_managing ? AppIcons.check : AppIcons.edit,
                        size: 18, color: t.textMuted),
                    label: Text(_managing ? 'Done' : 'Manage Profiles',
                        style: TextStyle(color: t.textMuted, fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final bool managing;
  final VoidCallback onTap;
  const _ProfileTile({
    required this.profile, required this.isActive,
    required this.managing, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final color = hexToColor(profile.avatarColor);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Column(children: [
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: isActive
                    ? Border.all(color: Colors.white, width: 3)
                    : Border.all(color: color.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(isActive ? 0.55 : 0.3),
                      blurRadius: isActive ? 24 : 14, spreadRadius: isActive ? 2 : 0),
                ],
              ),
              child: Center(
                child: profile.avatarEmoji.isNotEmpty
                    ? Text(profile.avatarEmoji, style: const TextStyle(fontSize: 36))
                    : Text(profile.avatarInitial,
                        style: const TextStyle(color: Colors.white, fontSize: 34,
                            fontWeight: FontWeight.w900)),
              ),
            ),
            if (profile.isKids)
              Positioned(
                bottom: -2, left: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.bg, width: 2),
                  ),
                  child: const Text('KIDS', style: TextStyle(color: Colors.white,
                      fontSize: 8, fontWeight: FontWeight.w800)),
                ),
              ),
            if (profile.isLocked && !managing)
              Positioned(
                top: -2, right: -2,
                child: Container(
                  padding: EdgeInsets.all(RaddSpace.xs),
                  decoration: BoxDecoration(
                    color: t.surface, shape: BoxShape.circle,
                    border: Border.all(color: t.bg, width: 2),
                  ),
                  child: Icon(AppIcons.lock, size: 11, color: t.textMuted),
                ),
              ),
            if (managing)
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.4),
                ),
                child: Center(
                  child: Icon(AppIcons.edit, color: Colors.white, size: 26),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(profile.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isActive ? t.textPrimary : t.textMuted,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _AddProfileTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProfileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Column(children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.surface,
              border: Border.all(color: t.border, style: BorderStyle.solid, width: 1.5),
            ),
            child: Icon(AppIcons.add, color: t.textMuted, size: 34),
          ),
          const SizedBox(height: 10),
          Text('Add Profile', style: TextStyle(color: t.textMuted, fontSize: 13,
              fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ── PIN entry bottom sheet ───────────────────────────────────────────────────
class _PinEntrySheet extends StatefulWidget {
  final Profile profile;
  const _PinEntrySheet({required this.profile});

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  String _pin = '';
  bool _shake = false;

  void _tap(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      if (_pin == widget.profile.pin) {
        Navigator.of(context).pop(_pin);
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _shake = true);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() { _pin = ''; _shake = false; });
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Icon(AppIcons.lock, color: AppColors.primary, size: 28),
        const SizedBox(height: 10),
        Text('Enter PIN for ${widget.profile.name}',
            style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: RaddSpace.lg),
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(_shake ? 8 : 0, 0, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
            final filled = i < _pin.length;
            return Container(
              width: 16, height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? (_shake ? AppColors.error : AppColors.primary)
                    : Colors.transparent,
                border: Border.all(
                    color: filled
                        ? (_shake ? AppColors.error : AppColors.primary)
                        : t.border, width: 1.5),
              ),
            );
          })),
        ),
        const SizedBox(height: 28),
        _NumPad(onTap: _tap, onBackspace: _backspace),
      ]),
    );
  }
}

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onTap;
  final VoidCallback onBackspace;
  const _NumPad({required this.onTap, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    Widget key(String label, {Widget? child, VoidCallback? onPressed}) {
      return SizedBox(
        width: 72, height: 56,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed ?? (label.isEmpty ? null : () => onTap(label)),
          child: Center(
            child: child ?? Text(label,
                style: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(children: [
      for (final row in rows)
        Row(mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) => key(d)).toList()),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        key('', child: const SizedBox.shrink()),
        key('0'),
        key('', child: Icon(AppIcons.backspace, size: 20, color: t.textMuted),
            onPressed: onBackspace),
      ]),
    ]);
  }
}
