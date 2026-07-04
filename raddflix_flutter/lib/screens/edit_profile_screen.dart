import 'dart:async';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
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
      setState(() { _error = e.toString().replaceAll('Exception:', '').trim(); _saving = false; });
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
              icon: Icon(AppAppIcons.close, color: t.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text('Edit Profile',
                style: TextStyle(color: t.textPrimary, fontSize: 17,
                    fontWeight: FontWeight.w700)),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: AppColors.primary))
                    : const Text('Save',
                        style: TextStyle(color: AppColors.primary,
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
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
                    _EmojiChip(
                      emoji: '',
                      isSelected: _avatarEmoji.isEmpty,
                      onTap: () => setState(() => _avatarEmoji = ''),
                      isNone: true,
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

              const SizedBox(height: 32),

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
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!,
                            style: TextStyle(color: AppColors.error,
                                fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _FieldCard(children: [
                    _Field(
                      ctrl: _nameCtrl,
                      label: 'Display Name',
                      hint: 'Your name (optional)',
                      icon: AppIcons.profile,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ]),

                  const SizedBox(height: 12),

                  _FieldCard(children: [
                    _Field(
                      ctrl: _emailCtrl,
                      label: 'Email',
                      hint: 'For account recovery (optional)',
                      icon: AppIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ]),

                  const SizedBox(height: 24),

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
                            child: const Icon(AppIcons.lock,
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

                  const SizedBox(height: 32),

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
              ? Icon(AppAppIcons.close, size: 16,
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
                duration: const Duration(milliseconds: 200),
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
                    ? const Icon(AppIcons.check,
                          color: Colors.white, size: 24)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ]),
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
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } on Exception catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
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
            child: const Icon(AppIcons.lock,
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

        _PwField(ctrl: _currentCtrl, label: 'Current Password',
            show: _showCurrent,
            onToggle: () => setState(() => _showCurrent = !_showCurrent)),
        const SizedBox(height: 12),
        _PwField(ctrl: _newCtrl, label: 'New Password',
            show: _showNew,
            onToggle: () => setState(() => _showNew = !_showNew)),
        const SizedBox(height: 12),
        _PwField(ctrl: _confirmCtrl, label: 'Confirm New Password',
            show: _showConfirm,
            onToggle: () => setState(() => _showConfirm = !_showConfirm)),
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

// ── Shared field widgets ───────────────────────────────────────────────────────
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

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: t.textMuted, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            style: TextStyle(color: t.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: t.textMuted, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              counterText: '',
            ),
          ),
        ])),
      ]),
    );
  }
}

class _PwField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool show;
  final VoidCallback onToggle;
  const _PwField({required this.ctrl, required this.label,
      required this.show, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: !show,
        style: TextStyle(color: t.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: t.textMuted, fontSize: 13),
          suffixIcon: IconButton(
            icon: Icon(show
                ? AppIcons.eyeOff
                : AppIcons.eye,
                size: 18, color: t.textMuted),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
