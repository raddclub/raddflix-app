import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/radius/radd_radius.dart';
import '../core/constants.dart';
import '../core/debug/debug_logger.dart';
import '../providers/catalog_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Playback
  bool _subtitleDefault  = false;
  bool _autoPlayNext     = true;
  // Network
  bool _wifiOnly         = false;
  bool _dataSaver        = false;
  // Meta
  String _version        = '';
  String _buildNumber    = '';
  bool   _isLoading      = true;
  bool   _syncing        = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final info  = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _subtitleDefault = prefs.getBool(StorageKeys.subtitleDefault) ?? false;
        _autoPlayNext    = prefs.getBool('jm_autoplay_next')           ?? true;
        _wifiOnly        = prefs.getBool('jm_wifi_only')               ?? false;
        _dataSaver       = prefs.getBool('jm_data_saver')              ?? false;
        _version         = info.version;
        _buildNumber     = info.buildNumber;
        _isLoading       = false;
      });
    }
  }

  Future<void> _set(String key, bool v, void Function(bool) update) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
    if (mounted) setState(() => update(v));
  }

  Future<void> _clearImageCache() async {
    PaintingBinding.instance.imageCache.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image cache cleared')),
      );
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ref.read(catalogProvider.notifier).syncFromServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalog refreshed successfully')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed — check your connection')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _contactSupport() async {
    DebugLogger.logTap('Settings', 'contactSupport');
    final phone = AppConstants.supportWhatsApp;
    final uri   = Uri.parse('https://wa.me/$phone?text=Hi%2C%20I%20need%20help%20with%20RaddFlix');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open WhatsApp and message +$phone')),
        );
      }
    }
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
          icon: Icon(AppIcons.back, color: t.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings', style: TextStyle(
            color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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

                // ── Playback ──────────────────────────────────────────────
                _SettingsSection(t: t, title: 'Playback', children: [
                  _SettingsSwitch(
                    t: t,
                    icon: AppIcons.subtitle,
                    label: 'Subtitles On By Default',
                    subtitle: 'Auto-enable subtitles when opening a video',
                    value: _subtitleDefault,
                    onChanged: (v) => _set(StorageKeys.subtitleDefault, v,
                        (x) => _subtitleDefault = x),
                  ),
                  _divider(t),
                  _SettingsSwitch(
                    t: t,
                    icon: AppIcons.skipForward,
                    label: 'Auto-play Next Episode',
                    subtitle: 'Automatically play the next episode when one ends',
                    value: _autoPlayNext,
                    onChanged: (v) => _set('jm_autoplay_next', v,
                        (x) => _autoPlayNext = x),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Network & Data ────────────────────────────────────────
                _SettingsSection(t: t, title: 'Network & Data', children: [
                  _SettingsSwitch(
                    t: t,
                    icon: AppIcons.wifi,
                    label: 'Download on WiFi Only',
                    subtitle: 'Prevent downloads over mobile data',
                    value: _wifiOnly,
                    iconColor: AppColors.info,
                    onChanged: (v) => _set('jm_wifi_only', v, (x) => _wifiOnly = x),
                  ),
                  _divider(t),
                  _SettingsSwitch(
                    t: t,
                    icon: AppIcons.dataSaver,
                    label: 'Data Saver',
                    subtitle: 'Reduces streaming buffer size to save mobile data',
                    value: _dataSaver,
                    iconColor: AppColors.success,
                    onChanged: (v) => _set('jm_data_saver', v, (x) => _dataSaver = x),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Storage & Cache ───────────────────────────────────────
                _SettingsSection(t: t, title: 'Storage & Cache', children: [
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.clearCache,
                    label: 'Clear Image Cache',
                    subtitle: 'Frees cached poster and thumbnail images',
                    onTap: _clearImageCache,
                    iconColor: context.accentWarning,
                  ),
                  _divider(t),
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.folder2,
                    label: 'Manage Downloads',
                    subtitle: 'View, delete and manage downloaded content',
                    onTap: () => Navigator.of(context).pushNamed(AppRoutes.downloads),
                    iconColor: context.signalPrimary,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Catalog Sync ──────────────────────────────────────────
                _SettingsSection(t: t, title: 'Catalog', children: [
                  _SettingsTile(
                    t: t,
                    icon: _syncing ? AppIcons.arrowsSync : AppIcons.refresh,
                    label: _syncing ? 'Syncing…' : 'Refresh Catalog',
                    subtitle: 'Force download the latest movies and shows',
                    onTap: _syncing ? null : _syncNow,
                    iconColor: context.signalPrimary,
                    trailing: _syncing
                        ? SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(context.signalPrimary)))
                        : null,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Support ───────────────────────────────────────────────
                _SettingsSection(t: t, title: 'Support', children: [
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.support,
                    label: 'Contact Support',
                    subtitle: 'Chat with us on WhatsApp',
                    onTap: _contactSupport,
                    iconColor: const Color(0xFF25D366),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── About ─────────────────────────────────────────────────
                _SettingsSection(t: t, title: 'About', children: [
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.info,
                    label: 'App Version',
                    subtitle: '$_version (build $_buildNumber)',
                    onTap: null,
                  ),
                  _divider(t),
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.lightning,
                    label: 'Streaming Features',
                    subtitle: 'HD quality video and offline downloads included',
                    onTap: null,
                    iconColor: const Color(0xFFFFB800),
                  ),
                  _divider(t),
                  _SettingsTile(
                    t: t,
                    icon: AppIcons.heart,
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
      height: 1, color: t.border.withOpacity(0.5), indent: 52, endIndent: 0);
}

// ── Shared section widgets ─────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final RaddTheme t;
  const _SettingsSection({required this.title, required this.children, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Text(title.toUpperCase(), style: TextStyle(
            color: t.textMuted, fontSize: 10.5,
            fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RaddRadius.mdRadius,
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
  final Widget? trailing;
  const _SettingsTile({
    required this.t, required this.icon, required this.label,
    this.subtitle, this.onTap, this.iconColor, this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? t.textSecondary).withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? t.textSecondary),
      ),
      title: Text(label, style: TextStyle(
          color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: t.textMuted, fontSize: 12))
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(AppIcons.caretRight, color: t.textMuted, size: 20)
              : null),
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
  final Color? iconColor;
  const _SettingsSwitch({
    required this.t, required this.icon, required this.label,
    this.subtitle, required this.value, required this.onChanged, this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? t.textSecondary).withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? t.textSecondary),
      ),
      title: Text(label, style: TextStyle(
          color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: t.textMuted, fontSize: 12))
          : null,
      trailing: Switch(value: value, onChanged: onChanged, activeColor: context.signalPrimary),
    );
  }
}
