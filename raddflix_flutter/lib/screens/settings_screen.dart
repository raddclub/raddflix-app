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
import '../design_system/components/settings_row.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/spacing/radd_space.dart';
import '../core/constants.dart';
import '../core/app_container.dart';
import '../providers/remote_values_provider.dart';
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
    final phone = appContainer.read(remoteValuesProvider).supportWhatsApp;
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.subtitle,
                      label: 'Subtitles On By Default',
                      subtitle: 'Auto-enable subtitles when opening a video',
                      trailing: SettingsRowTrailing.switchControl,
                      switchValue: _subtitleDefault,
                      onSwitchChanged: (v) => _set(StorageKeys.subtitleDefault, v,
                          (x) => _subtitleDefault = x),
                    ),
                  ),
                  _divider(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.skipForward,
                      label: 'Auto-play Next Episode',
                      subtitle: 'Automatically play the next episode when one ends',
                      trailing: SettingsRowTrailing.switchControl,
                      switchValue: _autoPlayNext,
                      onSwitchChanged: (v) => _set('jm_autoplay_next', v,
                          (x) => _autoPlayNext = x),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Network & Data ────────────────────────────────────────
                _SettingsSection(t: t, title: 'Network & Data', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.wifi,
                      label: 'Download on WiFi Only',
                      subtitle: 'Prevent downloads over mobile data',
                      trailing: SettingsRowTrailing.switchControl,
                      switchValue: _wifiOnly,
                      iconColor: AppColors.info,
                      onSwitchChanged: (v) => _set('jm_wifi_only', v,
                          (x) => _wifiOnly = x),
                    ),
                  ),
                  _divider(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.dataSaver,
                      label: 'Data Saver',
                      subtitle: 'Reduces streaming buffer size to save mobile data',
                      trailing: SettingsRowTrailing.switchControl,
                      switchValue: _dataSaver,
                      iconColor: AppColors.success,
                      onSwitchChanged: (v) => _set('jm_data_saver', v,
                          (x) => _dataSaver = x),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Storage & Cache ───────────────────────────────────────
                _SettingsSection(t: t, title: 'Storage & Cache', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.clearCache,
                      label: 'Clear Image Cache',
                      subtitle: 'Frees cached poster and thumbnail images',
                      onTap: _clearImageCache,
                      iconColor: context.accentWarning,
                    ),
                  ),
                  _divider(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.folder2,
                      label: 'Manage Downloads',
                      subtitle: 'View, delete and manage downloaded content',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.downloads),
                      iconColor: context.signalPrimary,
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Catalog Sync ──────────────────────────────────────────
                _SettingsSection(t: t, title: 'Catalog', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: _syncing
                        ? _SyncingRow(signalColor: context.signalPrimary)
                        : SettingsRow(
                            icon: AppIcons.refresh,
                            label: 'Refresh Catalog',
                            subtitle: 'Force download the latest movies and shows',
                            onTap: _syncNow,
                            iconColor: context.signalPrimary,
                          ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Support ───────────────────────────────────────────────
                _SettingsSection(t: t, title: 'Support', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.support,
                      label: 'Contact Support',
                      subtitle: 'Chat with us on WhatsApp',
                      onTap: _contactSupport,
                      iconColor: const Color(0xFF25D366), // intentional: WhatsApp brand green
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── About ─────────────────────────────────────────────────
                _SettingsSection(t: t, title: 'About', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.info,
                      label: 'App Version',
                      subtitle: '$_version (build $_buildNumber)',
                      trailing: SettingsRowTrailing.none,
                    ),
                  ),
                  _divider(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.lightning,
                      label: 'Streaming Features',
                      subtitle: 'HD quality video and offline downloads included',
                      trailing: SettingsRowTrailing.none,
                      iconColor: const Color(0xFFFFB800), // intentional: gold accent
                    ),
                  ),
                  _divider(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RaddSpace.md),
                    child: SettingsRow(
                      icon: AppIcons.heart,
                      label: 'Made in Pakistan',
                      subtitle: 'RaddFlix — Streaming ki apni zubaan',
                      trailing: SettingsRowTrailing.none,
                      iconColor: const Color(0xFF00A550), // intentional: Pakistan flag green
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _divider(RaddTheme t) => Divider(
      height: 1, color: t.border.withOpacity(0.5), indent: 56, endIndent: 0);
}

// ── Shared section widgets ─────────────────────────────────────────────────

class _SyncingRow extends StatelessWidget {
  final Color signalColor;
  const _SyncingRow({required this.signalColor});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return SizedBox(
      height: 64,
      child: Row(children: [
        Icon(AppIcons.arrowsSync, size: 24, color: signalColor),
        const SizedBox(width: RaddSpace.md),
        Expanded(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Syncing…',
                style: TextStyle(color: t.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('Force download the latest movies and shows',
                style: TextStyle(color: t.textMuted, fontSize: 12)),
          ],
        )),
        SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(signalColor))),
      ]),
    );
  }
}

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

// _SettingsTile and _SettingsSwitch removed — Phase F: all rows now use SettingsRow.
