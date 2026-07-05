import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import 'profile_switcher_screen.dart' show hexToColor;

const _kColors = [
  '#8B002D', '#7C5CFF', '#3B82F6', '#14B8A6',
  '#22C55E', '#F59E0B', '#F97316', '#EC4899',
];

const _kEmojis = [
  '', '🎬', '🎭', '🎮', '🎵', '🦁', '🔥', '⚡', '🌟', '👑',
  '🎯', '🦊', '🐺', '🎸', '💎', '🚀', '🌙', '😎', '🦅', '🧸',
];

/// Create or edit a "Who's Watching" profile. Pass [existing] to edit.
class AddEditProfileScreen extends ConsumerStatefulWidget {
  final Profile? existing;
  const AddEditProfileScreen({super.key, this.existing});

  @override
  ConsumerState<AddEditProfileScreen> createState() => _AddEditProfileScreenState();
}

class _AddEditProfileScreenState extends ConsumerState<AddEditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late String _avatarColor;
  late String _avatarEmoji;
  late bool _isKids;
  String? _pin; // 4-digit, null = no lock
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl    = TextEditingController(text: p?.name ?? '');
    _avatarColor = p?.avatarColor ?? _kColors[(DateTime.now().millisecond) % _kColors.length];
    _avatarEmoji = p?.avatarEmoji ?? '';
    _isKids      = p?.isKids ?? false;
    _pin         = p?.pin;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give this profile a name');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (_isEditing) {
        await ref.read(profileProvider.notifier).editProfile(
          widget.existing!.id,
          name: name,
          avatarColor: _avatarColor,
          avatarEmoji: _avatarEmoji,
          isKids: _isKids,
          pin: _pin,
          clearPin: _pin == null,
        );
      } else {
        await ref.read(profileProvider.notifier).addProfile(
          name: name,
          avatarColor: _avatarColor,
          avatarEmoji: _avatarEmoji,
          isKids: _isKids,
          pin: _pin,
        );
      }
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() { _error = 'Could not save profile'; _saving = false; });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('This removes "${widget.existing!.name}"\'s watchlist and '
            'watch history from this device. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(profileProvider.notifier).removeProfile(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _setPin() async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SetPinSheet(),
    );
    if (pin != null) setState(() => _pin = pin);
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final color = hexToColor(_avatarColor);
    final canDelete = _isEditing && ref.watch(profileProvider).profiles.length > 1;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.close, color: t.textMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEditing ? 'Edit Profile' : 'Add Profile',
            style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Text('Save', style: TextStyle(color: AppColors.primary,
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(children: [
          // ── Avatar preview ─────────────────────────────────────────────
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 26, spreadRadius: 2)],
            ),
            child: Center(
              child: _avatarEmoji.isNotEmpty
                  ? Text(_avatarEmoji, style: const TextStyle(fontSize: 42))
                  : Text(
                      _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim()[0].toUpperCase() : 'P',
                      style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                    ),
            ),
          ).animate().scale(begin: const Offset(0.85, 0.85), duration: 300.ms),

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
              child: Row(children: [
                Icon(AppIcons.errorIcon, color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Name field ────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border)),
            child: TextField(
              controller: _nameCtrl,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: t.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Profile name',
                hintStyle: TextStyle(color: t.textMuted),
                prefixIcon: Icon(AppIcons.profile, color: t.textMuted, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Color picker ──────────────────────────────────────────────
          Align(alignment: Alignment.centerLeft,
              child: Text('Avatar Color', style: TextStyle(color: t.textMuted, fontSize: 13,
                  fontWeight: FontWeight.w600))),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: _kColors.map((hex) {
            final selected = hex == _avatarColor;
            final c = hexToColor(hex);
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _avatarColor = hex); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [c, c.withOpacity(0.7)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                  boxShadow: selected
                      ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 10, spreadRadius: 1)]
                      : [],
                ),
                child: selected ? Icon(AppIcons.check, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList()),

          const SizedBox(height: 20),

          // ── Emoji picker ──────────────────────────────────────────────
          Align(alignment: Alignment.centerLeft,
              child: Text('Avatar Icon', style: TextStyle(color: t.textMuted, fontSize: 13,
                  fontWeight: FontWeight.w600))),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: _kEmojis.map((e) {
              final selected = e == _avatarEmoji;
              return GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => _avatarEmoji = e); },
                child: Container(
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary.withOpacity(0.18) : t.surface,
                    border: Border.all(color: selected ? AppColors.primary.withOpacity(0.6) : t.border,
                        width: selected ? 1.5 : 1),
                  ),
                  child: Center(
                    child: e.isEmpty
                        ? Icon(AppIcons.close, size: 16,
                            color: selected ? AppColors.primary : t.textMuted)
                        : Text(e, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              );
            }).toList()),
          ),

          const SizedBox(height: 24),

          // ── Kids profile toggle ───────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border)),
            child: SwitchListTile(
              value: _isKids,
              onChanged: (v) => setState(() => _isKids = v),
              activeColor: const Color(0xFF22C55E),
              title: Text('Kids Profile', style: TextStyle(color: t.textPrimary, fontSize: 14,
                  fontWeight: FontWeight.w600)),
              subtitle: Text('Hides the Private Vault and adult content sections',
                  style: TextStyle(color: t.textMuted, fontSize: 12)),
              secondary: const Text('🧸', style: TextStyle(fontSize: 22)),
            ),
          ),

          const SizedBox(height: 12),

          // ── PIN lock ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border)),
            child: ListTile(
              leading: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(_pin != null ? AppIcons.lock : AppIcons.unlock,
                    size: 18, color: AppColors.primary),
              ),
              title: Text(_pin != null ? 'PIN Lock — On' : 'PIN Lock — Off',
                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(_pin != null ? 'Tap to change' : 'Require a 4-digit PIN to switch to this profile',
                  style: TextStyle(color: t.textMuted, fontSize: 12)),
              trailing: _pin != null
                  ? IconButton(
                      icon: Icon(AppIcons.close, size: 18),
                      color: t.textMuted,
                      onPressed: () => setState(() => _pin = null),
                    )
                  : Icon(AppIcons.caretRight, color: t.textMuted, size: 20),
              onTap: _setPin,
            ),
          ),

          if (canDelete) ...[
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _delete,
                icon: Icon(AppIcons.trash, color: Color(0xFFEF4444), size: 18),
                label: const Text('Delete Profile',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

// ── Set PIN bottom sheet ─────────────────────────────────────────────────────
class _SetPinSheet extends StatefulWidget {
  const _SetPinSheet();
  @override
  State<_SetPinSheet> createState() => _SetPinSheetState();
}

class _SetPinSheetState extends State<_SetPinSheet> {
  String _first = '';
  String _current = '';
  bool _confirming = false;
  String? _error;

  void _tap(String d) {
    if (_current.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _current += d);
    if (_current.length == 4) {
      if (!_confirming) {
        setState(() { _first = _current; _current = ''; _confirming = true; });
      } else {
        if (_current == _first) {
          Navigator.of(context).pop(_current);
        } else {
          setState(() { _error = "PINs don't match — try again"; _current = ''; _confirming = false; _first = ''; });
        }
      }
    }
  }

  void _backspace() {
    if (_current.isEmpty) return;
    setState(() => _current = _current.substring(0, _current.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      decoration: BoxDecoration(color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text(_confirming ? 'Confirm PIN' : 'Set a 4-digit PIN',
            style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
        ],
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
          final filled = i < _current.length;
          return Container(
            width: 16, height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? AppColors.primary : Colors.transparent,
              border: Border.all(color: filled ? AppColors.primary : t.border, width: 1.5),
            ),
          );
        })),
        const SizedBox(height: 24),
        _AddProfilePinPad(onTap: _tap, onBackspace: _backspace),
      ]),
    );
  }
}

class _AddProfilePinPad extends StatelessWidget {
  final ValueChanged<String> onTap;
  final VoidCallback onBackspace;
  const _AddProfilePinPad({required this.onTap, required this.onBackspace});

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

    final rows = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']];
    return Column(children: [
      for (final row in rows)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map((d) => key(d)).toList()),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        key('', child: const SizedBox.shrink()),
        key('0'),
        key('', child: Icon(AppIcons.backspace, size: 20, color: t.textMuted), onPressed: onBackspace),
      ]),
    ]);
  }
}
