import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/theme/radd_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../services/vault_service.dart';
import '../core/security/device_id.dart';
import '../core/theme/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../providers/watchlist_provider.dart';
import '../providers/subscription_provider.dart';
import '../core/api/subscription_api.dart';
import '../widgets/loading_overlay.dart';
import '../core/player/scene_bookmark_store.dart';  // BUG-A23
import '../core/player/player_prefs.dart';          // BUG-A21
import '../core/db/local_db.dart';                  // BUG-A22
import '../widgets/bottom_nav.dart';
import 'debug_diagnostics_screen.dart';
import 'edit_profile_screen.dart';
import '../core/debug/debug_logger.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOut = false;
  String? _deviceName;
  bool _hasInternet = true;
  String _appVersion = 'v1.0.0';
  int? _daysLeft;
  bool _subExpiring = false;
  int _versionTapCount = 0;
  String? _remotePlan;
  double _remoteUsedGb  = 0.0;
  double _remoteLimitGb = 0.0;
  late final _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChange);

  @override
  void initState() {
    super.initState();
    DebugLogger.logLifecycle('ProfileScreen', 'initState');
    DeviceIdentifier.getDeviceName().then((n) {
      if (mounted) setState(() => _deviceName = n);
    });
    _checkConnectivity();
    _connectivitySub; // activate listener
    _loadExtras();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) setState(() => _hasInternet = result != ConnectivityResult.none);
  }

  void _onConnectivityChange(List<ConnectivityResult> results) {
    if (mounted) setState(() => _hasInternet = results.isNotEmpty && results.first != ConnectivityResult.none);
  }

  Future<void> _loadExtras() async {
    // BUG-A14: catch blocks now log errors so developers can diagnose
    // PackageInfo / SubscriptionApi failures in the debug console.
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v\${info.version}');
    } catch (e) {
      debugPrint('[ProfileScreen] PackageInfo error: \$e');
    }
    try {
      final status = await SubscriptionApi.getStatus();
      if (!mounted) return;
      // status.monthlyUsedGb is populated from the quota embedded in the
      // /status response (BUG-A fix: backend now includes quota in status).
      // We additionally fetch fresh quota to guarantee up-to-date usage.
      double usedGb  = status.monthlyUsedGb;
      double limitGb = status.monthlyLimitGb;
      try {
        final quota = await SubscriptionApi.getQuota();
        if (quota != null) {
          usedGb  = (quota['monthly_used_gb']  as num?)?.toDouble() ?? usedGb;
          limitGb = (quota['monthly_limit_gb'] as num?)?.toDouble() ?? limitGb;
        }
      } catch (_) { /* offline — use values from status */ }
      setState(() {
        _remotePlan    = status.plan;
        _remoteUsedGb  = usedGb;
        _remoteLimitGb = limitGb;
      });
      final expiresAt = status.expiresAt;
      if (expiresAt != null && status.isActive) {
        final dt = DateTime.tryParse(expiresAt);
        if (dt != null) {
          final diff = dt.difference(DateTime.now()).inDays;
          if (mounted) setState(() {
            _daysLeft = diff > 0 ? diff : 0;
            _subExpiring = diff <= 7;
          });
        }
      }
    } catch (e) {
      debugPrint('[ProfileScreen] SubscriptionApi error: \$e');
    }
  }

  @override
  void dispose() {
    DebugLogger.logLifecycle('ProfileScreen', 'dispose');
    _connectivitySub.cancel();
    super.dispose();
  }

  Color _avatarColor(AppUser? user) {
    final hex = (user?.avatarColor ?? '#8B002D').replaceAll('#', '');
    try { return Color(int.parse('FF$hex', radix: 16)); }
    catch (_) { return AppColors.primary; }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Sign Out'),
      content: const Text('Are you sure you want to sign out?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (ok != true) return;
    setState(() => _loggingOut = true);
    // BUG-A23: clean up per-user scene bookmarks on logout
    await SceneBookmarkStore.deleteAllContent();
    await ref.read(authProvider.notifier).logout();
    if (mounted) Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final user  = ref.watch(authProvider).user;
    final theme = ref.watch(themeProvider);
    final initial = user?.avatarInitial ?? 'U';

    return LoadingOverlay(
      loading: _loggingOut,
      child: Scaffold(
        backgroundColor: null,
        bottomNavigationBar: RaddFlixBottomNav(
          currentIndex: 3,
          onTap: (i) {
            if (i == 3) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
            if (i == 1) Navigator.of(context).pushNamed(AppRoutes.localMedia);
            else if (i == 2) Navigator.of(context).pushNamed(AppRoutes.downloads);
          },
        ),
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    RichText(text: TextSpan(
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      children: [
                        TextSpan(text: 'My ', style: TextStyle(color: t.textPrimary)),
                        TextSpan(text: 'Profile', style: TextStyle(color: AppColors.primary)),
                      ],
                    )),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: t.textMuted)),
                  ]),
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),

            // Avatar & plan
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Column(children: [
                  // Avatar with glow ring
                  GestureDetector(
                    onTap: user?.isGuest == true ? null : () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                      if (changed == true && mounted) setState(() {});
                    },
                    child: Stack(alignment: Alignment.bottomRight, children: [
                      // Glow ring
                      Container(
                        width: 108, height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _avatarColor(user).withOpacity(0.3), width: 2),
                        ),
                      ),
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_avatarColor(user), _avatarColor(user).withOpacity(0.7)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: _avatarColor(user).withOpacity(0.45),
                                blurRadius: 28, spreadRadius: 2),
                          ],
                        ),
                        child: Center(child: Text(initial, style: const TextStyle(
                            color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900))),
                      ),
                      if (user?.isGuest != true)
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: t.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.border, width: 1.5),
                          ),
                          child: Icon(Icons.edit_rounded, size: 14, color: t.textMuted),
                        ),
                    ]),
                  ).animate().scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1),
                      duration: 400.ms, curve: AppCurves.enter),
                  const SizedBox(height: 14),
                  Text(user?.displayLabel ?? 'Guest', style: TextStyle(
                      color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w700,
                      letterSpacing: -0.3))
                      .animate(delay: 100.ms).fadeIn(duration: 300.ms),
                  if (user?.isGuest != true && user?.displayName != null && user!.displayName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(user.phone, style: TextStyle(color: t.textMuted, fontSize: 13))
                        .animate(delay: 120.ms).fadeIn(),
                  ],
                  const SizedBox(height: 8),
                  Builder(builder: (ctx) {
                    final plan = (_remotePlan ?? user?.planName ?? 'FREE').toUpperCase();
                    final isPremium = plan.contains('PREMIUM') || plan.contains('GOLD');
                    final isStandard = plan.contains('STANDARD') || plan.contains('SILVER');
                    final emoji = isPremium ? '👑' : isStandard ? '⭐' : '🎬';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadius.round),
                        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 12)],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(plan, style: const TextStyle(color: AppColors.primary, fontSize: 11,
                            fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      ]),
                    );
                  }).animate(delay: 150.ms).fadeIn(duration: 300.ms),
                ]),
              ),
            ),

            // Subscription card
            if (user?.subscription != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary.withOpacity(0.18), const Color(0x0A8B002D), AppColors.primary.withOpacity(0.08)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        stops: const [0.0, 0.5, 1.0]),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.07), blurRadius: 20)],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.star_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Active Subscription', style: TextStyle(
                              color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                          if (user!.subscription!.expiresAt != null)
                            Text('Expires ${_fmt(user.subscription!.expiresAt!)}',
                                style: TextStyle(color: t.textMuted, fontSize: 12)),
                          if (_daysLeft != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _subExpiring
                                  ? '⚠ ${_daysLeft}d remaining — renew soon'
                                  : '${_daysLeft}d remaining',
                              style: TextStyle(
                                color: _subExpiring
                                    ? const Color(0xFFFFB300)
                                    : const Color(0xFF00C853),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ])),
                        TextButton(
                          onPressed: () { DebugLogger.logTap('Profile', 'subscription'); Navigator.of(context).pushNamed(AppRoutes.subscription); },
                          child: Text('Manage', style: TextStyle(fontSize: 12))),
                      ]),
                      // GB usage progress bar
                      if (_remoteLimitGb > 0) ...[
                        const SizedBox(height: 14),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('${_remoteUsedGb.toStringAsFixed(1)} GB used',
                              style: TextStyle(color: t.textMuted, fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          Text('of ${_remoteLimitGb.toInt()} GB',
                              style: TextStyle(color: t.textMuted, fontSize: 11)),
                        ]),
                        const SizedBox(height: 6),
                        Builder(builder: (_) {
                          final pct = _remoteLimitGb > 0
                              ? (_remoteUsedGb / _remoteLimitGb).clamp(0.0, 1.0)
                              : 0.0;
                          final barColor = pct >= 0.9
                              ? AppColors.error
                              : pct >= 0.7
                                  ? AppColors.warning
                                  : AppColors.primary;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct, minHeight: 7,
                              backgroundColor: AppColors.primary.withOpacity(0.12),
                              valueColor: AlwaysStoppedAnimation(barColor),
                            ),
                          );
                        }),
                      ],
                    ]),
                  ),
                ).animate(delay: 200.ms).fadeIn(duration: 350.ms)
                    .slideY(begin: 0.2, end: 0, duration: 350.ms, curve: AppCurves.standard),
              ),

            // Sections
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  // General
                  _Section(title: 'General', children: [
                    _SectionTile(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () {
                        DebugLogger.logTap('Profile', 'settings');
                        Navigator.of(context).pushNamed(AppRoutes.settings);
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Appearance
                  _Section(title: 'Appearance', children: [
                    _SectionTile(
                      icon: Icons.palette_outlined,
                      label: 'Theme',
                      trailing: _ThemeTrailing(),
                      onTap: () => _showThemePicker(context),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Player — BUG-A21 + BUG-A22: expose reset actions
                  _Section(title: 'Player', children: [
                    _SectionTile(
                      icon: Icons.tune_rounded,
                      label: 'Reset Player Settings',
                      onTap: () async {
                        final ok = await showDialog<bool>(context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Reset Player Settings'),
                              content: const Text(
                                  'This will reset all playback preferences '
                                  '(gestures, subtitles, equalizer, etc.) '
                                  'to their defaults.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Reset',
                                        style: TextStyle(color: AppColors.error))),
                              ],
                            ));
                        if (ok != true || !context.mounted) return;
                        await PlayerPrefs.reset();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Player settings reset to defaults')));
                        }
                      },
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.history_toggle_off_rounded,
                      label: 'Reset Watch Progress',
                      onTap: () async {
                        final ok = await showDialog<bool>(context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Reset Watch Progress'),
                              content: const Text(
                                  'This will clear your resume positions '
                                  'for all content. You cannot undo this.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Clear',
                                        style: TextStyle(color: AppColors.error))),
                              ],
                            ));
                        if (ok != true || !context.mounted) return;
                        await LocalDb.clearAllPositions();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Watch progress cleared')));
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Watchlist & History
                  // ── Watch Stats card ───────────────────────────────────────────
                  _StatsCard(),
                  const SizedBox(height: 12),

                  _Section(title: 'My Content', children: [
                    _SectionTile(
                      icon: Icons.bookmark_rounded,
                      iconColor: AppColors.primary,
                      label: 'My Watchlist',
                      onTap: () { DebugLogger.logTap('Profile', 'watchlist'); Navigator.of(context).pushNamed(AppRoutes.watchlist); },
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF22C55E),
                      label: 'Watch History',
                      onTap: () { DebugLogger.logTap('Profile', 'history'); Navigator.of(context).pushNamed(AppRoutes.history); },
                    ),
                  ]),
                  SizedBox(height: 12),
                  // Device
                  _Section(title: 'Device', children: [
                    _SectionTile(
                      icon: Icons.smartphone_rounded,
                      label: 'Device',
                      trailing: Text(_deviceName ?? '…',
                          style: TextStyle(color: t.textMuted, fontSize: 12)),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: _hasInternet ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      iconColor: _hasInternet ? const Color(0xFF22C55E) : AppColors.error,
                      label: 'Network',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (_hasInternet ? const Color(0xFF22C55E) : AppColors.error).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_hasInternet ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: _hasInternet ? const Color(0xFF22C55E) : AppColors.error,
                              fontSize: 11, fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Account
                  _Section(title: 'Account', children: [
                    _SectionTile(
                      icon: Icons.workspace_premium_outlined,
                      iconColor: AppColors.primary,
                      label: 'Upgrade Plan',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.subscription),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.lock_rounded,
                      iconColor: const Color(0xFF7C5CFF),
                      label: 'Private Vault',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x207C5CFF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('PRIVATE', style: TextStyle(
                            color: Color(0xFF7C5CFF), fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      onTap: () async {
                        final hasPin = await VaultService.hasPin();
                        if (!context.mounted) return;
                        if (hasPin) {
                          if (VaultService.isUnlocked) {
                            Navigator.of(context).pushNamed(AppRoutes.vault);
                          } else {
                            Navigator.of(context).pushNamed(AppRoutes.vaultLock);
                          }
                        } else {
                          Navigator.of(context).pushNamed(AppRoutes.vaultLock,
                              arguments: {'setup': true});
                        }
                      },
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.download_outlined,
                      label: 'Downloads',
                      onTap: () { DebugLogger.logTap('Profile', 'downloads'); Navigator.of(context).pushNamed(AppRoutes.downloads); },
                    ),
                    if (user?.isGuest != true && _hasInternet) ...[
                      _divider(),
                      _SectionTile(
                        icon: Icons.cloud_download_outlined,
                        iconColor: const Color(0xFF3B82F6),
                        label: 'Server Downloads',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x223B82F6),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('ADMIN', style: TextStyle(
                              color: Color(0xFF3B82F6), fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.adminQueue),
                      ),
                    ],
                    _divider(),
                    _SectionTile(
                      icon: Icons.bug_report_outlined,
                      iconColor: Colors.orange,
                      label: 'Debug Logs',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const DebugDiagnosticsScreen())),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.error,
                      label: 'Sign Out',
                      labelColor: AppColors.error,
                      onTap: _loggingOut ? null : _logout,
                    ),
                  ]),
                  SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                      border: Border.all(color: t.border),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _versionTapCount++);
                        if (_versionTapCount >= 5) {
                          setState(() => _versionTapCount = 0);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const DebugDiagnosticsScreen()));
                        }
                      },
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(color: t.textMuted, fontSize: 11),
                          children: [
                            TextSpan(text: 'Radd', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                            const TextSpan(text: 'Flix', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                            TextSpan(text: ' $_appVersion · Pakistan ka entertainment, data-free'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ]),
              ).animate(delay: 250.ms).fadeIn(duration: 400.ms),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 52);

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(context: context, builder: (_) => _ThemePicker());
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return iso; }
  }
}

// ── Theme section trailing: color swatch dot + name ──────────────────────────
class _ThemeTrailing extends ConsumerWidget {
  static Color _dotColor(JazzTheme mode) {
    switch (mode) {
      case JazzTheme.midnight: return const Color(0xFF181838);
      case JazzTheme.navy:     return const Color(0xFF162A4A);
      case JazzTheme.forest:   return const Color(0xFF152B1A);
      case JazzTheme.cobalt:   return const Color(0xFF18255A);
      case JazzTheme.rose:     return const Color(0xFF2E1822);
      case JazzTheme.charcoal: return const Color(0xFF272729);
      case JazzTheme.amoled:   return const Color(0xFF000000);
      case JazzTheme.light:    return const Color(0xFFF0F0F7);
      default:                 return const Color(0xFF1A1A2E);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t    = RaddTheme.of(context);
    final mode = ref.watch(themeProvider).mode;
    final name = ref.watch(themeProvider.notifier).displayName;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: _dotColor(mode),
          shape: BoxShape.circle,
          border: Border.all(color: t.textMuted.withOpacity(0.4), width: 1),
        ),
      ),
      const SizedBox(width: 6),
      Text(name, style: TextStyle(color: t.textMuted, fontSize: 13)),
    ]);
  }
}

class _ThemePicker extends ConsumerWidget {
  // Standard themes shown as list rows
  static const _standard = [
    (JazzTheme.dark,   Icons.nights_stay_rounded,   'Dark',   'Deep dark — easy on the eyes'),
    (JazzTheme.amoled, Icons.phone_android_rounded,  'AMOLED', 'Pure black — zero drain on OLED'),
    (JazzTheme.light,  Icons.wb_sunny_rounded,       'Light',  'Bright background for daylight'),
    (JazzTheme.auto,   Icons.brightness_auto_rounded,'Auto',   'Switches dark/light by time of day'),
  ];

  // Color themes shown as visual swatches (bg, card, label)
  static const _colorThemes = [
    (JazzTheme.midnight, Color(0xFF070712), Color(0xFF181838), 'Midnight'),
    (JazzTheme.navy,     Color(0xFF060D1A), Color(0xFF162A4A), 'Navy'),
    (JazzTheme.forest,   Color(0xFF060E09), Color(0xFF152B1A), 'Forest'),
    (JazzTheme.cobalt,   Color(0xFF060A1A), Color(0xFF18255A), 'Cobalt'),
    (JazzTheme.rose,     Color(0xFF100608), Color(0xFF2E1822), 'Rose'),
    (JazzTheme.charcoal, Color(0xFF0E0E0F), Color(0xFF272729), 'Charcoal'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t       = RaddTheme.of(context);
    final current = ref.watch(themeProvider).mode;

    void pick(JazzTheme m) {
      ref.read(themeProvider.notifier).setTheme(m);
      Navigator.pop(context);
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: t.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)))),

        // Title
        Text('Choose Theme',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 18),

        // ── Standard themes ──────────────────────────────────────────────
        _pickerLabel('Standard', t),
        const SizedBox(height: 10),
        ..._standard.map((opt) {
          final sel = current == opt.$1;
          return GestureDetector(
            onTap: () => pick(opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary.withOpacity(0.10) : t.card,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: sel ? AppColors.primary.withOpacity(0.6) : t.cardBorder,
                    width: sel ? 1.5 : 0.5),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary.withOpacity(0.15) : t.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(opt.$2,
                      color: sel ? AppColors.primary : t.textMuted, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opt.$3, style: TextStyle(
                      color: sel ? AppColors.primary : t.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(opt.$4, style: TextStyle(color: t.textMuted, fontSize: 12)),
                ])),
                if (sel)
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
              ]),
            ),
          );
        }),

        const SizedBox(height: 20),

        // ── Color themes grid ────────────────────────────────────────────
        _pickerLabel('Color Themes', t),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: _colorThemes.map((opt) {
            final sel = current == opt.$1;
            return GestureDetector(
              onTap: () => pick(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  gradient: LinearGradient(
                    colors: [opt.$2, opt.$3],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: sel ? AppColors.primary : Colors.white10,
                    width: sel ? 2 : 0.5,
                  ),
                  boxShadow: sel
                      ? [BoxShadow(color: AppColors.primary.withOpacity(0.25),
                          blurRadius: 10, spreadRadius: 1)]
                      : null,
                ),
                child: Stack(children: [
                  // Theme name bottom
                  Positioned(bottom: 8, left: 0, right: 0,
                    child: Text(opt.$4, textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11,
                            fontWeight: FontWeight.w600, letterSpacing: 0.2))),
                  // Check indicator top-right
                  if (sel)
                    Positioned(top: 6, right: 6,
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 12),
                      )),
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),
      ]),
    );
  }

  static Widget _pickerLabel(String label, RaddTheme t) => Row(children: [
    Container(width: 12, height: 1.5,
        margin: const EdgeInsets.only(right: 6),
        color: AppColors.primary.withOpacity(0.5)),
    Text(label.toUpperCase(),
        style: TextStyle(color: t.textMuted, fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.2)),
  ]);
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(children: [
          Container(width: 12, height: 1.5,
              margin: const EdgeInsets.only(right: 6),
              color: AppColors.primary.withOpacity(0.6)),
          Text(title.toUpperCase(), style: TextStyle(
              color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ])),
      Container(
        decoration: BoxDecoration(color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: t.border)),
        child: Column(children: children),
      ),
    ]);
  }
}

// ── Stats Card ───────────────────────────────────────────────────────────────
class _StatsCard extends StatelessWidget {
  const _StatsCard();

  String _fmtTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _fmtBytes(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576)    return '${(b / 1048576).toStringAsFixed(0)} MB';
    if (b >= 1024)       return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b} B';
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: LocalDb.getWatchStats(),
      builder: (context, snap) {
        final data     = snap.data;
        final totalMs  = (data?['total_ms']  as int?) ?? 0;
        final completed= (data?['completed'] as int?) ?? 0;
        final dlCount  = (data?['dl_count']  as int?) ?? 0;
        final dlBytes  = (data?['dl_bytes']  as int?) ?? 0;
        final topGenre = data?['top_genre']  as String?;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(children: [
              Container(width: 12, height: 1.5, margin: const EdgeInsets.only(right: 6),
                  color: AppColors.primary.withOpacity(0.6)),
              Text('MY STATS', style: TextStyle(color: t.textMuted, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: t.border),
            ),
            child: snap.connectionState == ConnectionState.waiting
                ? Center(child: SizedBox(height: 40, child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary))))
                : Column(children: [
                    Row(children: [
                      _StatTile(
                        icon: Icons.access_time_rounded,
                        iconColor: AppColors.primary,
                        label: 'Watch Time',
                        value: totalMs > 0 ? _fmtTime(totalMs) : '—',
                      ),
                      _StatDivider(),
                      _StatTile(
                        icon: Icons.check_circle_outline_rounded,
                        iconColor: const Color(0xFF22C55E),
                        label: 'Completed',
                        value: completed > 0 ? '$completed' : '—',
                      ),
                    ]),
                    Divider(height: 1, color: t.border),
                    Row(children: [
                      _StatTile(
                        icon: Icons.download_rounded,
                        iconColor: const Color(0xFF3B82F6),
                        label: 'Downloads',
                        value: dlCount > 0 ? '$dlCount (${_fmtBytes(dlBytes)})' : '—',
                      ),
                      _StatDivider(),
                      _StatTile(
                        icon: Icons.local_fire_department_rounded,
                        iconColor: AppColors.warning,
                        label: 'Top Genre',
                        value: topGenre ?? '—',
                      ),
                    ]),
                  ]),
          ),
        ]);
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _StatTile({required this.icon, required this.iconColor,
      required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withOpacity(0.12),
              border: Border.all(color: iconColor.withOpacity(0.2)),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(color: t.textPrimary, fontSize: 13,
                      fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label,
                  style: TextStyle(color: t.textMuted, fontSize: 10)),
            ],
          )),
        ]),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(width: 1, height: 60, color: t.border);
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SectionTile({required this.icon, this.iconColor, required this.label,
      this.labelColor, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (iconColor ?? t.textMuted).withOpacity(0.12),
          border: Border.all(color: (iconColor ?? t.textMuted).withOpacity(0.15)),
        ),
        child: Icon(icon, size: 18, color: iconColor ?? t.textMuted)),
      title: Text(label, style: TextStyle(
          color: labelColor ?? t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: trailing ?? (onTap != null
          ? Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20)
          : null),
      onTap: onTap,
    );
  }
}
