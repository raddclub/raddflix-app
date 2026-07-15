import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
import '../design_system/elevation/radd_elevation.dart';
import '../design_system/typography/radd_type.dart';
import '../core/constants.dart';
import '../core/app_container.dart';
import '../providers/remote_values_provider.dart';
import '../core/debug/debug_logger.dart';
import '../providers/catalog_provider.dart';
import '../core/utils/anim_config.dart';

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
    final animConfig = ref.watch(animConfigProvider);

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
              padding: const EdgeInsets.fromLTRB(
                  RaddSpace.md, RaddSpace.lg, RaddSpace.md, RaddSpace.xxl),
              children: [

                // ── Playback ────────────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'Playback',
                  sectionIcon: AppIcons.play,
                  sectionIconColor: context.signalPrimary,
                  staggerIndex: 0,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.subtitle,
                        label: 'Subtitles On By Default',
                        subtitle: 'Auto-enable subtitles when opening a video',
                        trailing: SettingsRowTrailing.switchControl,
                        switchValue: _subtitleDefault,
                        onSwitchChanged: (v) => _set(StorageKeys.subtitleDefault,
                            v, (x) => _subtitleDefault = x),
                      ),
                    ),
                    _divider(t),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.skipForward,
                        label: 'Auto-play Next Episode',
                        subtitle:
                            'Automatically play the next episode when one ends',
                        trailing: SettingsRowTrailing.switchControl,
                        switchValue: _autoPlayNext,
                        onSwitchChanged: (v) => _set(
                            'jm_autoplay_next', v, (x) => _autoPlayNext = x),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RaddSpace.lg),

                // ── Network & Data ──────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'Network & Data',
                  sectionIcon: AppIcons.wifi,
                  sectionIconColor: AppColors.info,
                  staggerIndex: 1,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.wifi,
                        label: 'Download on WiFi Only',
                        subtitle: 'Prevent downloads over mobile data',
                        trailing: SettingsRowTrailing.switchControl,
                        switchValue: _wifiOnly,
                        iconColor: AppColors.info,
                        onSwitchChanged: (v) =>
                            _set('jm_wifi_only', v, (x) => _wifiOnly = x),
                      ),
                    ),
                    _divider(t),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.dataSaver,
                        label: 'Data Saver',
                        subtitle:
                            'Reduces streaming buffer size to save mobile data',
                        trailing: SettingsRowTrailing.switchControl,
                        switchValue: _dataSaver,
                        iconColor: AppColors.success,
                        onSwitchChanged: (v) =>
                            _set('jm_data_saver', v, (x) => _dataSaver = x),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RaddSpace.lg),

                // ── Storage & Cache ─────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'Storage & Cache',
                  sectionIcon: AppIcons.folder2,
                  sectionIconColor: context.accentWarning,
                  staggerIndex: 2,
                  children: [
                    // Destructive action row — warning accent treatment
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: _DestructiveRow(
                        t: t,
                        child: SettingsRow(
                          icon: AppIcons.clearCache,
                          label: 'Clear Image Cache',
                          subtitle: 'Frees cached poster and thumbnail images',
                          onTap: _clearImageCache,
                          iconColor: context.accentWarning,
                        ),
                      ),
                    ),
                    _divider(t),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.folder2,
                        label: 'Manage Downloads',
                        subtitle:
                            'View, delete and manage downloaded content',
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.downloads),
                        iconColor: context.signalPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RaddSpace.lg),

                // ── Catalog Sync ────────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'Catalog',
                  sectionIcon: AppIcons.refresh,
                  sectionIconColor: context.signalPrimary,
                  staggerIndex: 3,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: _syncing
                          ? _SyncingRow(signalColor: context.signalPrimary)
                          : SettingsRow(
                              icon: AppIcons.refresh,
                              label: 'Refresh Catalog',
                              subtitle:
                                  'Force download the latest movies and shows',
                              onTap: _syncNow,
                              iconColor: context.signalPrimary,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: RaddSpace.lg),

                // ── Support ─────────────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'Support',
                  sectionIcon: AppIcons.support,
                  sectionIconColor: const Color(0xFF25D366), // intentional: WhatsApp brand green
                  staggerIndex: 4,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.support,
                        label: 'Contact Support',
                        subtitle: 'Chat with us on WhatsApp',
                        onTap: _contactSupport,
                        iconColor: const Color(0xFF25D366), // intentional: WhatsApp brand green
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RaddSpace.lg),

                // ── About ───────────────────────────────────────────────────
                _SettingsSection(
                  t: t,
                  animConfig: animConfig,
                  title: 'About',
                  sectionIcon: AppIcons.info,
                  sectionIconColor: t.textMuted,
                  staggerIndex: 5,
                  children: [
                    // Version pill row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.info,
                        label: 'App Version',
                        trailing: SettingsRowTrailing.none,
                        trailingWidget:
                            _VersionPill(version: _version, buildNumber: _buildNumber, t: t),
                      ),
                    ),
                    _divider(t),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.lightning,
                        label: 'Streaming Features',
                        subtitle:
                            'HD quality video and offline downloads included',
                        trailing: SettingsRowTrailing.none,
                        iconColor: const Color(0xFFFFB800), // intentional: gold accent
                      ),
                    ),
                    _divider(t),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RaddSpace.md),
                      child: SettingsRow(
                        icon: AppIcons.heart,
                        label: 'Made in Pakistan',
                        subtitle: 'RaddFlix — Streaming ki apni zubaan',
                        trailing: SettingsRowTrailing.none,
                        iconColor: const Color(0xFF00A550), // intentional: Pakistan flag green
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _divider(RaddTheme t) => Divider(
      height: 1, color: t.border.withOpacity(0.5), indent: 56, endIndent: 0);
}

// ── Shared section widgets ────────────────────────────────────────────────────

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

/// Thin warning-accent tint layered behind a destructive action row.
/// Does not alter the row's interactivity or layout — purely decorative.
class _DestructiveRow extends StatelessWidget {
  final RaddTheme t;
  final Widget child;
  const _DestructiveRow({required this.t, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Subtle left accent bar in warning color
        Positioned(
          left: 0,
          top: 8,
          bottom: 8,
          child: Container(
            width: 2.5,
            decoration: BoxDecoration(
              color: context.accentWarning.withOpacity(0.7),
              borderRadius: RaddRadius.pillRadius,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Glass pill showing version + build — used in the About section's App Version row.
class _VersionPill extends StatelessWidget {
  final String version;
  final String buildNumber;
  final RaddTheme t;
  const _VersionPill({required this.version, required this.buildNumber, required this.t});

  @override
  Widget build(BuildContext context) {
    if (version.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: RaddSpace.sm + 2, vertical: RaddSpace.xs),
      decoration: BoxDecoration(
        color: t.glass,
        borderRadius: RaddRadius.pillRadius,
        border: Border.all(color: t.border.withOpacity(0.6), width: 0.75),
      ),
      child: Text(
        'v$version ($buildNumber)',
        style: context.raddCaption.copyWith(
          color: t.textSecondary,
          // Slightly tighter tracking gives it a "build stamp" feel
          letterSpacing: 0.4,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Premium glass grouped section card.
///
/// Visual anatomy:
///   • Outer glass card: `t.card` fill, `t.cardBorder` 0.5px outline, `md` radius.
///   • Specular highlight: 1px top inner edge in `t.glassHigh` — feels lit.
///   • BackdropFilter blur (sigma 12) when `animConfig.canBlur`; solid-surface
///     fallback (`t.surfaceHigh`) otherwise.
///   • Section label: label-scale uppercase, left-indented to align with row
///     icon containers, with a colour-coded dot accent.
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final RaddTheme t;
  final AnimConfig animConfig;
  final PhosphorIconData? sectionIcon; // optional left accent icon
  final Color? sectionIconColor;
  final int staggerIndex;

  const _SettingsSection({
    required this.title,
    required this.children,
    required this.t,
    required this.animConfig,
    this.sectionIcon,
    this.sectionIconColor,
    this.staggerIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final staggerDelay = animConfig.canStagger
        ? Duration(milliseconds: 40 * staggerIndex)
        : Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header label ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(RaddSpace.xs, 0, 0, RaddSpace.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Colour-coded accent dot — ties the section to its icon hue
              if (sectionIconColor != null) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: sectionIconColor!.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: RaddSpace.sm),
              ],
              Text(
                title.toUpperCase(),
                style: context.raddLabel.copyWith(
                  color: t.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),

        // ── Glass card body ─────────────────────────────────────────────────
        _buildCard(context),
      ],
    ).animate(delay: staggerDelay)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOut);
  }

  Widget _buildCard(BuildContext context) {
    final decoration = BoxDecoration(
      color: animConfig.canBlur
          ? t.card.withOpacity(0.80)
          : t.card,
      borderRadius: RaddRadius.mdRadius,
      border: Border.all(color: t.cardBorder.withOpacity(0.85), width: 0.5),
    );

    // Inner specular highlight — 1px top border lighter than card surface
    final specularDecoration = BoxDecoration(
      borderRadius: RaddRadius.mdRadius,
      border: Border(
        top: BorderSide(color: t.glassHigh, width: 1.0),
      ),
    );

    Widget cardContent = DecoratedBox(
      decoration: decoration,
      child: Stack(
        children: [
          // Specular top-edge highlight
          Positioned.fill(
            child: DecoratedBox(decoration: specularDecoration),
          ),
          // Actual row content
          Column(children: children),
        ],
      ),
    );

    if (animConfig.canBlur) {
      return ClipRRect(
        borderRadius: RaddRadius.mdRadius,
        child: RaddElevation.blurWrap(
          sigma: 12,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
