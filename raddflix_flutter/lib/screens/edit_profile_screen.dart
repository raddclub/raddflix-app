import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/motion/radd_motion.dart';
import '../design_system/components/radd_text_field.dart';
import '../core/constants.dart';
import '../core/api/auth_api.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

// ── Avatar palette ────────────────────────────────────────────────────────────
const _kColors = [
  '#8B002D', // primary red
  '#7C5CFF', // purple
  '#3B82F6', // blue
  '#14B8A6', // teal
  '#22C55E', // green
  '#F59E0B', // amber
  '#F97316', // orange
  '#EC4899', // pink
];

Color _hex(String h) {
  final s = h.replaceAll('#', '');
  return Color(int.parse('FF$s', radix: 16));
}

// ── Screen ────────────────────────────────────────────────────────────────────
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late String _avatarColor;
  late String _avatarEmoji;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameCtrl    = TextEditingController(text: user?.displayName ?? '');
    _emailCtrl   = TextEditingController(text: user?.email ?? '');
    _avatarColor = user?.avatarColor ?? '#8B002D';
    _avatarEmoji = user?.avatarEmoji ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await AuthApi.updateProfile(
        displayName: name,
        email: email,
        avatarColor: _avatarColor,
        avatarEmoji: _avatarEmoji,
      );
      // Refresh user in provider
      await ref.read(authProvider.notifier).silentRefresh();
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      // A1: guard against setState after dispose if user navigates away mid-request
      if (kDebugMode) debugPrint('[EditProfile] save error: $e');
      if (mounted) setState(() { _error = 'Could not save changes. Please try again.'; _saving = false; });
    }
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ColorPickerSheet(
        selected: _avatarColor,
        onSelect: (c) {
          setState(() => _avatarColor = c);
          HapticFeedback.selectionClick();
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _showChangePassword() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ChangePasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final user = ref.watch(authProvider).user;
    final initial = user?.avatarInitial ?? 'U';
    final color = _hex(_avatarColor);

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: t.bg,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: Icon(AppIcons.close, color: t.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text('Edit Profile',
                style: TextStyle(color: t.textPrimary, fontSize: 17,
                    fontWeight: FontWeight.w700)),
            centerTitle: true,
            // Save lives solely in the bottom "Save Changes" button below —
            // having it duplicated here too made it unclear which one to use.
          ),

          SliverToBoxAdapter(
            child: Column(children: [
              const SizedBox(height: 28),

              // ── Avatar ─────────────────────────────────────────────────
              GestureDetector(
                onTap: _showColorPicker,
                child: Stack(alignment: Alignment.center, children: [
                  // Outer glow halo
                  Container(
                    width: 122, height: 122,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.08),
                    ),
                  ),
                  Container(
                    width: 112, height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withOpacity(0.35), width: 2),
                    ),
                  ),
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: color.withOpacity(0.55),
                            blurRadius: 30, spreadRadius: 4),
                      ],
                    ),
                    child: Center(
                      child: _avatarEmoji.isNotEmpty
                          ? Text(_avatarEmoji,
                              style: const TextStyle(fontSize: 42))
                          : Text(initial,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 44, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  // Palette badge bottom-right
                  Positioned(
                    bottom: 6, right: 6,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: t.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                        boxShadow: [BoxShadow(
                            color: color.withOpacity(0.2), blurRadius: 6)],
                      ),
                      child: Icon(AppIcons.colorPalette,
                          size: 16, color: color),
                    ),
                  ),
                ]).animate().scale(
                    begin: const Offset(0.85, 0.85),
                    duration: 350.ms, curve: Curves.easeOutBack),
              ),

              const SizedBox(height: 10),
              Text(
                (user?.displayName ?? '').isNotEmpty
                    ? user!.displayName!
                    : (user?.phone ?? ''),
                style: TextStyle(
                    color: t.textPrimary, fontSize: 17,
                    fontWeight: FontWeight.w700),
              ).animate(delay: 80.ms).fadeIn(),
              const SizedBox(height: 2),
              Text('Tap to change color · pick emoji below',
                  style: TextStyle(color: t.textMuted, fontSize: 12))
                  .animate(delay: 100.ms).fadeIn(),
              const SizedBox(height: 14),
              // ── Emoji row ───────────────────────────────────────────────
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    Tooltip(
                      message: 'No emoji — show initials instead',
                      child: _EmojiChip(
                        emoji: '',
                        isSelected: _avatarEmoji.isEmpty,
                        onTap: () => setState(() => _avatarEmoji = ''),
                        isNone: true,
                      ),
                    ),
                    // Visual separator so "clear" reads as a distinct action,
                    // not just another item in the emoji row.
                    Container(
                      width: 1, height: 24,
                      margin: const EdgeInsets.only(right: 8),
                      color: RaddTheme.of(context).border,
                    ),
                    ...['🎬','🎭','🎮','🎵','🦁','🔥','⚡','🌟','👑','🎯',
                        '🦊','🐺','🎸','💎','🚀','🌙','😎','🦅','🐉','🌺',
                    ].map((e) => _EmojiChip(
                        emoji: e,
                        isSelected: _avatarEmoji == e,
                        onTap: () {
                          setState(() => _avatarEmoji = e);
                          HapticFeedback.selectionClick();
                        })),
                  ],
                ),
              ).animate(delay: 130.ms).fadeIn(),

              const SizedBox(height: RaddSpace.lg),

              // ── Fields ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Icon(AppIcons.errorIcon,
                            color: AppColors.error, size: 16),
                        const SizedBox(width: RaddSpace.sm),
                        Expanded(child: Text(_error!,
                            style: TextStyle(color: AppColors.error,
                                fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: RaddSpace.md),
                  ],

                  RaddTextField(
                    controller: _nameCtrl,
                    label: 'Display Name',
                    hint: 'Your name (optional)',
                    prefixIcon: AppIcons.profile,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                  ),

                  const SizedBox(height: 12),

                  RaddTextField(
                    controller: _emailCtrl,
                    label: 'Email',
                    hint: 'For account recovery (optional)',
                    prefixIcon: AppIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: RaddSpace.lg),

                  // ── Change Password ──────────────────────────────────
                  _FieldCard(children: [
                    InkWell(
                      onTap: _showChangePassword,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(AppIcons.lock,
                                size: 18, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Change Password',
                                style: TextStyle(color: t.textPrimary,
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text('Update your login password',
                                style: TextStyle(color: t.textMuted,
                                    fontSize: 12)),
                          ])),
                          Icon(AppIcons.caretRight,
                              color: t.textMuted, size: 20),
                        ]),
                      ),
                    ),
                  ]),

                  const SizedBox(height: RaddSpace.lg),

                  // ── Save button ──────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: _saving
                              ? LinearGradient(colors: [
                                  AppColors.primary.withOpacity(0.4),
                                  AppColors.primary.withOpacity(0.3),
                                ])
                              : AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _saving
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('Save Changes',
                                  style: TextStyle(color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),
                ]).animate(delay: 150.ms).fadeIn(duration: 300.ms)
                    .slideY(begin: 0.1, end: 0, duration: 300.ms),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Emoji chip ───────────────────────────────────────────────────────────────
class _EmojiChip extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isNone;
  const _EmojiChip({required this.emoji, required this.isSelected,
      required this.onTap, this.isNone = false});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40, height: 40,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? AppColors.primary.withOpacity(0.18)
              : t.surface,
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.6)
                : t.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 8)]
              : null,
        ),
        child: Center(
          child: isNone
              ? Icon(AppIcons.close, size: 16,
                    color: isSelected ? AppColors.primary : t.textMuted)
              : Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

// ── Color picker bottom sheet ─────────────────────────────────────────────────
class _ColorPickerSheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _ColorPickerSheet({required this.selected, required this.onSelect});

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
            decoration: BoxDecoration(color: t.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text('Choose Avatar Color',
            style: TextStyle(color: t.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14, runSpacing: 14,
          children: _kColors.map((hex) {
            final isSelected = hex == selected;
            final color = _hex(hex);
            return GestureDetector(
              onTap: () => onSelect(hex),
              child: AnimatedContainer(
                duration: RaddMotion.tuneDuration,
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withOpacity(0.6),
                            blurRadius: 12, spreadRadius: 2)]
                      : [],
                ),
                child: isSelected
                    ? Icon(AppIcons.check,
                          color: Colors.white, size: 24)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: RaddSpace.sm),
      ]),
    );
  }
}

// ── Settings-row card wrapper (used for the "Change Password" entry point) ────
class _FieldCard extends StatelessWidget {
  final List<Widget> children;
  const _FieldCard({required this.children});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(children: children),
    );
  }
}

// ── Change password bottom sheet ──────────────────────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _showCurrent = false, _showNew = false, _showConfirm = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text.trim();
    final next    = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }
    if (next.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await AuthApi.changePassword(
          currentPassword: current, newPassword: next);
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[EditProfile] password change error: $e');
      setState(() {
        _error = 'Could not change password. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(AppIcons.lock,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text('Change Password',
              style: TextStyle(color: t.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),

        if (_error != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Text(_error!,
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ),
          const SizedBox(height: 14),
        ],

        RaddTextField(
          controller: _currentCtrl,
          label: 'Current Password',
          obscureText: !_showCurrent,
          prefixIcon: AppIcons.lock,
          suffixIcon: IconButton(
            icon: Icon(_showCurrent ? AppIcons.eyeOff : AppIcons.eye, size: 18, color: t.textMuted),
            onPressed: () => setState(() => _showCurrent = !_showCurrent),
          ),
        ),
        const SizedBox(height: 12),
        RaddTextField(
          controller: _newCtrl,
          label: 'New Password',
          obscureText: !_showNew,
          prefixIcon: AppIcons.lock,
          suffixIcon: IconButton(
            icon: Icon(_showNew ? AppIcons.eyeOff : AppIcons.eye, size: 18, color: t.textMuted),
            onPressed: () => setState(() => _showNew = !_showNew),
          ),
        ),
        const SizedBox(height: 12),
        RaddTextField(
          controller: _confirmCtrl,
          label: 'Confirm New Password',
          obscureText: !_showConfirm,
          prefixIcon: AppIcons.lock,
          suffixIcon: IconButton(
            icon: Icon(_showConfirm ? AppIcons.eyeOff : AppIcons.eye, size: 18, color: t.textMuted),
            onPressed: () => setState(() => _showConfirm = !_showConfirm),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
                : const Text('Update Password',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

