import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import '../core/constants.dart';
import '../services/vault_service.dart';

class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key});
  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _hasFakePin = false;
  int _autoLockSeconds = 0;
  bool _loading = false;

  static const _lockOptions = [
    (label: 'Never', value: 0),
    (label: '30 seconds', value: 30),
    (label: '1 minute', value: 60),
    (label: '5 minutes', value: 300),
    (label: '15 minutes', value: 900),
    (label: '1 hour', value: 3600),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final biAvail = await VaultService.isBiometricAvailable();
    final biEnabled = await VaultService.isBiometricEnabled();
    final hasFake = await VaultService.hasFakePin();
    final autoLock = await VaultService.getAutoLockSeconds();
    if (mounted) {
      setState(() {
        _biometricAvailable = biAvail;
        _biometricEnabled = biEnabled;
        _hasFakePin = hasFake;
        _autoLockSeconds = autoLock;
      });
    }
  }

  Future<void> _changePin() async {
    final result = await _showPinDialog('Change PIN', 'Enter current PIN, then new PIN');
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await VaultService.changePin(result.$1, result.$2);
      if (mounted) _toast('PIN changed successfully');
    } catch (e) {
      if (mounted) _toast('Incorrect current PIN', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setFakePin() async {
    final pin = await _showNewPinDialog(
        _hasFakePin ? 'Change Decoy PIN' : 'Set Decoy PIN',
        'A fake vault opens with this PIN — shows empty vault to protect real content');
    if (pin == null) return;
    await VaultService.setFakePin(pin);
    setState(() => _hasFakePin = pin.isNotEmpty);
    if (mounted) _toast(pin.isEmpty ? 'Decoy PIN removed' : 'Decoy PIN set');
  }

  Future<void> _clearVault() async {
    final t = RaddTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Clear Vault?', style: TextStyle(color: AppColors.error.withOpacity(0.85))),
        content: Text(
          'This permanently deletes ALL files in your vault. This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete Everything', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    await VaultService.clearVault();
    if (mounted) _toast('Vault cleared');
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : AppColors.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Simplified pin dialogs
  Future<(String, String)?> _showPinDialog(String title, String hint) async {
    final t = RaddTheme.of(context);
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final ctrl3 = TextEditingController(); // confirm new PIN
    String? _localError;
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(title, style: TextStyle(color: t.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(hint, style: TextStyle(color: t.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          _pinField(ctrl1, 'Current PIN'),
          const SizedBox(height: 10),
          _pinField(ctrl2, 'New PIN (${VaultService.minPinLength}–${VaultService.maxPinLength} digits)'),
          const SizedBox(height: 10),
          _pinField(ctrl3, 'Confirm New PIN'),
          if (_localError != null) ...[
            const SizedBox(height: 8),
            Text(_localError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(
            onPressed: () {
              final oldPin = ctrl1.text.trim();
              final newPin = ctrl2.text.trim();
              final confirm = ctrl3.text.trim();
              if (newPin.length < VaultService.minPinLength) {
                setS(() => _localError = 'New PIN must be at least ${VaultService.minPinLength} digits');
                return;
              }
              if (newPin.length > VaultService.maxPinLength) {
                setS(() => _localError = 'New PIN must be at most ${VaultService.maxPinLength} digits');
                return;
              }
              if (newPin != confirm) {
                setS(() => _localError = 'New PINs do not match');
                return;
              }
              Navigator.pop(ctx, (oldPin, newPin));
            },
            child: Text('Change', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      )),
    );
  }

  Future<String?> _showNewPinDialog(String title, String hint) async {
    final t = RaddTheme.of(context);
    final ctrl = TextEditingController();
    String? _localError;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(title, style: TextStyle(color: t.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(hint, style: TextStyle(color: t.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          _pinField(ctrl, 'PIN (leave empty to remove)'),
          if (_localError != null) ...[
            const SizedBox(height: 8),
            Text(_localError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(
            onPressed: () {
              final pin = ctrl.text.trim();
              if (pin.isNotEmpty && pin.length < VaultService.minPinLength) {
                setS(() => _localError = 'PIN must be at least ${VaultService.minPinLength} digits');
                return;
              }
              if (pin.length > VaultService.maxPinLength) {
                setS(() => _localError = 'PIN must be at most ${VaultService.maxPinLength} digits');
                return;
              }
              Navigator.pop(ctx, pin);
            },
            child: Text('Save', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      )),
    );
  }

  Widget _pinField(TextEditingController ctrl, String hint) {
    final t = RaddTheme.of(context);
    return TextField(
    controller: ctrl,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: VaultService.maxPinLength,
    style: TextStyle(color: t.textPrimary, fontSize: 20, letterSpacing: 8),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: t.textSecondary, fontSize: 13, letterSpacing: 0),
      counterText: '',
      filled: true,
      fillColor: t.bg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.border)),
    ),
  );
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        title: Text('Vault Settings', style: TextStyle(color: t.textPrimary)),
        leading: IconButton(
          icon: Icon(AppIcons.back, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Security section
          _SectionHeader(label: 'Security'),
          _SettingCard(children: [
            _SettingTile(
              icon: AppIcons.pinCode,
              title: 'Change PIN',
              subtitle: 'Update your vault unlock PIN',
              onTap: _changePin,
              trailing: Icon(AppIcons.caretRight, color: t.textSecondary.withOpacity(0.4)),
            ),
            if (_biometricAvailable) ...[
              const _Divider(),
              _SettingTile(
                icon: AppIcons.fingerprint,
                title: 'Biometric Unlock',
                subtitle: 'Use fingerprint to open vault',
                trailing: Switch(
                  value: _biometricEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (v) async {
                    await VaultService.setBiometricEnabled(v);
                    setState(() => _biometricEnabled = v);
                  },
                ),
              ),
            ],
            const _Divider(),
            _SettingTile(
              icon: AppIcons.timerIcon,
              title: 'Auto-Lock',
              subtitle: _lockOptions
                  .firstWhere((o) => o.value == _autoLockSeconds,
                      orElse: () => (label: 'Custom', value: _autoLockSeconds))
                  .label,
              trailing: Icon(AppIcons.caretRight, color: t.textSecondary.withOpacity(0.4)),
              onTap: () => _showAutoLockPicker(),
            ),
          ]).animate().fadeIn(delay: 50.ms),

          const SizedBox(height: 16),

          // Privacy section
          _SectionHeader(label: 'Privacy'),
          _SettingCard(children: [
            _SettingTile(
              icon: AppIcons.fingerprint,
              title: 'Decoy PIN',
              subtitle: _hasFakePin
                  ? 'Active — shows empty vault'
                  : 'Set a fake PIN that opens an empty vault',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_hasFakePin) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('ON', style: TextStyle(
                      color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Icon(AppIcons.caretRight, color: t.textSecondary.withOpacity(0.4)),
              ]),
              onTap: _setFakePin,
            ),
          ]).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 16),

          // Danger zone
          _SectionHeader(label: 'Danger Zone'),
          _SettingCard(children: [
            _SettingTile(
              icon: AppIcons.trash,
              title: 'Clear Vault',
              subtitle: 'Permanently delete all vault files',
              titleColor: AppColors.error.withOpacity(0.85),
              onTap: _clearVault,
              trailing: Icon(AppIcons.caretRight, color: t.textSecondary.withOpacity(0.4)),
            ),
          ]).animate().fadeIn(delay: 150.ms),

          const SizedBox(height: 32),

          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(AppIcons.shield, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Vault files are stored in your app\'s private directory — invisible to other apps, file managers, and the system gallery. Auto-lock secures the vault when your phone is idle.',
                style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.5),
              )),
            ]),
          ).animate().fadeIn(delay: 200.ms),
        ],
      ),
    );
  }

  void _showAutoLockPicker() {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Auto-Lock After', style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          ..._lockOptions.map((o) => ListTile(
            title: Text(o.label, style: TextStyle(color: t.textPrimary)),
            trailing: _autoLockSeconds == o.value
                ? Icon(AppIcons.check, color: AppColors.primary)
                : null,
            onTap: () async {
              await VaultService.setAutoLockSeconds(o.value);
              setState(() => _autoLockSeconds = o.value);
              if (mounted) Navigator.pop(context);
            },
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(label.toUpperCase(), style: TextStyle(
        color: t.textSecondary, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});
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

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  const _SettingTile({required this.icon, required this.title,
    required this.subtitle, this.trailing, this.onTap, this.titleColor});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: t.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: titleColor ?? t.textPrimary, size: 20),
      ),
      title: Text(title, style: TextStyle(
          color: titleColor ?? t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 12)),
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Divider(
    height: 1, indent: 64,
    color: t.border,
    );
  }
}
