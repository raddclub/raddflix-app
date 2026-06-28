import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/theme/radd_theme.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _defaultQuality = 'auto';
  bool _subtitleDefault = false;
  String _version = '';
  String _buildNumber = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _defaultQuality = prefs.getString(StorageKeys.defaultQuality) ?? 'auto';
        _subtitleDefault = prefs.getBool(StorageKeys.subtitleDefault) ?? false;
        _version = info.version;
        _buildNumber = info.buildNumber;
        _isLoading = false;
      });
    }
  }

  Future<void> _setQuality(String q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.defaultQuality, q);
    setState(() => _defaultQuality = q);
    DebugLogger.logTap('Settings', 'quality: $q');
  }

  Future<void> _setSubtitleDefault(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.subtitleDefault, v);
    setState(() => _subtitleDefault = v);
  }

  Future<void> _clearCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLive();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image cache cleared successfully')),
      );
    }
  }

  String _qualityLabel(String q) {
    switch (q) {
      case 'high':   return 'High (1080p)';
      case 'medium': return 'Medium (720p)';
      case 'low':    return 'Low (480p)';
      default:       return 'Auto (recommended)';
    }
  }

  void _showQualitySheet() {
    final t = RaddTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: t.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
                color: t.textMuted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Text('Default Video Quality',
                  style: TextStyle(color: t.textPrimary,
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 4),
          ...['auto', 'high', 'medium', 'low'].map((q) {
            final selected = _defaultQuality == q;
            return ListTile(
              leading: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : t.textMuted, size: 22,
              ),
              title: Text(_qualityLabel(q),
                  style: TextStyle(
                      color: t.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400)),
              onTap: () {
                Navigator.pop(context);
                _setQuality(q);
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: t.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings',
            style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border.withOpacity(0.5)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
              children: [
                // ── Playback ────────────────────────────────────────────
                _SettingsSection(t: t, title: 'Playback', children: [
                  _SettingsTile(
                    t: t,
                    icon: Icons.hd_rounded,
                    label: 'Default Quality',
                    subtitle: _qualityLabel(_defaultQuality),
                    onTap: _showQualitySheet,
                  ),
                  _divider(t),
                  _SettingsSwitch(
                    t: t,
                    icon: Icons.subtitles_outlined,
                    label: 'Subtitles On By Default',
                    subtitle: 'Auto-enable subs when opening a video',
                    value: _subtitleDefault,
                    onChanged: _setSubtitleDefault,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Storage ─────────────────────────────────────────────
                _SettingsSection(t: t, title: 'Storage & Cache', children: [
                  _SettingsTile(
                    t: t,
                    icon: Icons.cleaning_services_rounded,
                    label: 'Clear Image Cache',
                    subtitle: 'Frees up cached poster & thumbnail images',
                    onTap: _clearCache,
                    iconColor: AppColors.primary,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── About ───────────────────────────────────────────────
                _SettingsSection(t: t, title: 'About', children: [
                  _SettingsTile(
                    t: t,
                    icon: Icons.info_outline_rounded,
                    label: 'App Version',
                    subtitle: '$_version (build $_buildNumber)',
                    onTap: null,
                  ),
                  _divider(t),
                  _SettingsTile(
                    t: t,
                    icon: Icons.bolt_rounded,
                    label: 'Zero-Rated on Jazz',
                    subtitle:
                        'Stream & download with no data charges on Jazz SIM',
                    onTap: null,
                    iconColor: const Color(0xFFFFB800),
                  ),
                  _divider(t),
                  _SettingsTile(
                    t: t,
                    icon: Icons.favorite_outline_rounded,
                    label: 'Made in Pakistan',
                    subtitle: 'RaddFlix — Streaming ki apni zubaan',
                    onTap: null,
                    iconColor: const Color(0xFF00A550),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _divider(RaddTheme t) => Divider(
      height: 1,
      color: t.border.withOpacity(0.5),
      indent: 52,
      endIndent: 0);
}

// ── Shared section widgets ─────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final RaddTheme t;
  const _SettingsSection(
      {required this.title, required this.children, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      ),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: t.border.withOpacity(0.7)),
        ),
        child: Column(children: children),
      ),
    ]).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

class _SettingsTile extends StatelessWidget {
  final RaddTheme t;
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  const _SettingsTile({
    required this.t,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? t.textSecondary).withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? t.textSecondary),
      ),
      title: Text(label,
          style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(color: t.textMuted, fontSize: 12))
          : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20)
          : null,
      onTap: onTap,
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final RaddTheme t;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsSwitch({
    required this.t,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: t.textSecondary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: t.textSecondary),
      ),
      title: Text(label,
          style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(color: t.textMuted, fontSize: 12))
          : null,
      trailing:
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    );
  }
}
