import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import '../design_system/elevation/radd_elevation.dart';
import '../widgets/theme_picker_sheet.dart'; // UX4-05
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/anim_config.dart';
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
import '../core/player/scene_bookmark_store.dart';
import '../core/player/player_prefs.dart';
import '../core/db/local_db.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/mini_player_bar.dart';
import 'debug_diagnostics_screen.dart';
import '../widgets/tier_badge.dart';
import 'edit_profile_screen.dart';
import '../core/debug/debug_logger.dart';
import '../providers/profile_provider.dart';
import 'profile_switcher_screen.dart';
import '../widgets/data_usage_ring.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  // UX4-01: showBottomNav=false when embedded inside the HomeScreen IndexedStack shell
  final bool showBottomNav;
  const ProfileScreen({super.key, this.showBottomNav = true});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late String _greetingTod; // A8: cached greeting

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
    final _h = DateTime.now().hour;
    _greetingTod = _h < 12 ? 'Good morning' : _h < 17 ? 'Good afternoon' : 'Good evening';
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
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfileScreen] PackageInfo error: $e');
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
      // PROFILE-AUDIT-1: guard before setState — getQuota() above is async,
      // widget may have been disposed while it was in flight.
      if (!mounted) return;
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
      if (kDebugMode) debugPrint('[ProfileScreen] SubscriptionApi error: $e');
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
    final t = RaddTheme.of(context);
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      // UX4-13: themed dialog — uses surface token + md radius
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: RaddRadius.mdRadius),
      title: Text('Sign Out', style: TextStyle(color: t.textPrimary)),
      content: Text('Are you sure you want to sign out?',
          style: TextStyle(color: t.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: t.textMuted))),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (ok != true) return;
    setState(() => _loggingOut = true);
    // Clean up per-user scene bookmarks on logout so User B never sees User A's history.
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
    final activeProfile = ref.watch(profileProvider).active;
    final isKidsProfile = activeProfile?.isKids ?? false;

    return LoadingOverlay(
      loading: _loggingOut,
      child: Scaffold(
        backgroundColor: null,
        // UX4-01: nav bar hidden when embedded in HomeScreen's IndexedStack shell
        bottomNavigationBar: widget.showBottomNav ? MiniPlayerDock(
          // NAV-RESTRUCTURE: Profile is now tab 2 (was tab 4).
          child: RaddFlixBottomNav(
          currentIndex: 2,
          onTap: (i) {
            if (i == 2) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
            if (i == 1) Navigator.of(context).pushNamed(AppRoutes.localMedia);
          },
          ),
        ) : null,
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
                    // PROFILE-AUDIT-4: close only valid when pushed as modal,
                    // not when embedded in the HomeScreen tab IndexedStack.
                    if (widget.showBottomNav)
                      IconButton(onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(AppIcons.close, color: t.textMuted)),
                  ]),
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),

            // Avatar & plan
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Column(children: [
                  // A8: greeting cached in initState — no DateTime.now() in build()
                  Text(_greetingTod, style: TextStyle(
                      color: t.textMuted, fontSize: 15, fontWeight: FontWeight.w500,
                      letterSpacing: 0.2)).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 18),
                  // Avatar with double glow ring
                  GestureDetector(
                    onTap: user?.isGuest == true ? null : () async {
                      // PROFILE-AUDIT-7: user comes from ref.watch(authProvider)
                      // — Riverpod rebuilds automatically; bare setState is redundant.
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                    },
                    child: Stack(alignment: Alignment.bottomRight, children: [
                      // Outer soft glow halo
                      Container(
                        width: 132, height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _avatarColor(user).withOpacity(0.07),
                        ),
                      ),
                      // Inner border ring
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _avatarColor(user).withOpacity(0.35), width: 2),
                        ),
                      ),
                      // Avatar circle
                      Container(
                        width: 108, height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_avatarColor(user), _avatarColor(user).withOpacity(0.72)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: _avatarColor(user).withOpacity(0.5),
                                blurRadius: 36, spreadRadius: 4),
                          ],
                        ),
                        child: Center(
                          child: (user?.avatarEmoji ?? '').isNotEmpty
                              ? Text(user!.avatarEmoji,
                                  style: const TextStyle(fontSize: 42))
                              : Text(initial, style: const TextStyle(
                                  color: Colors.white, fontSize: 48,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ),
                      // Edit pencil badge
                      if (user?.isGuest != true)
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: t.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _avatarColor(user).withOpacity(0.45), width: 1.5),
                            boxShadow: [BoxShadow(
                                color: _avatarColor(user).withOpacity(0.25),
                                blurRadius: 8)],
                          ),
                          child: Icon(AppIcons.edit, size: 15,
                              color: _avatarColor(user)),
                        ),
                    ]),
                  ).animate().scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1),
                      duration: 400.ms, curve: AppCurves.enter),
                  const SizedBox(height: 18),
                  Text(user?.displayLabel ?? 'Guest', style: TextStyle(
                      color: t.textPrimary, fontSize: 23, fontWeight: FontWeight.w800,
                      letterSpacing: -0.6))
                      .animate(delay: 100.ms).fadeIn(duration: 300.ms),
                  if (user?.isGuest != true) ...[
                    // Only show the phone row when the name above is a real
                    // display name — otherwise displayLabel already IS the
                    // phone number and this would repeat the same value twice.
                    if ((user!.displayName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppIcons.phone, size: 13, color: t.textMuted),
                        const SizedBox(width: 5),
                        Text(user.phone,
                            style: TextStyle(color: t.textMuted, fontSize: 12)),
                      ]).animate(delay: 120.ms).fadeIn(),
                    ],
                    if ((user.email ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppIcons.mail, size: 13, color: t.textMuted),
                        const SizedBox(width: 5),
                        Text(user.email!,
                            style: TextStyle(color: t.textMuted, fontSize: 12)),
                      ]).animate(delay: 140.ms).fadeIn(),
                    ],
                    if ((user.displayName ?? '').isEmpty) ...[
                      const SizedBox(height: 7),
                      GestureDetector(
                        onTap: () async {
                          // PROFILE-AUDIT-7: Riverpod rebuilds on auth change automatically.
                          await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                                builder: (_) => const EditProfileScreen()));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: t.surfaceHigh,
                            borderRadius: BorderRadius.circular(AppRadius.round),
                            border: Border.all(color: t.border),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(AppIcons.edit, size: 11, color: t.textMuted),
                            const SizedBox(width: RaddSpace.xs),
                            Text('Add your name',
                                style: TextStyle(color: t.textMuted, fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ).animate(delay: 160.ms).fadeIn(),
                    ],
                  ],
                  const SizedBox(height: RaddSpace.sm),
                  TierBadge(
                    plan: _remotePlan ?? user?.planName ?? 'FREE',
                  ).animate(delay: 150.ms).fadeIn(duration: 300.ms),
                ]),
              ),
            ),

            // Subscription card — only for users with a genuinely active
            // subscription. A subscription object always exists (even for
            // free users, with isActive: false), so checking for non-null
            // alone showed "Active Subscription" to free users right next
            // to their "FREE" tier badge.
            if (user?.hasActiveSubscription == true)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: EdgeInsets.all(RaddSpace.md),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary.withOpacity(0.18), AppColors.primary.withOpacity(0.04), AppColors.primary.withOpacity(0.08)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        stops: const [0.0, 0.5, 1.0]),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.07), blurRadius: 20)],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(AppIcons.starFill, color: AppColors.primary, size: 24),
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
                                    ? AppColors.warning
                                    : AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ])),
                        TextButton(
                          onPressed: () { DebugLogger.logTap('Profile', 'subscription'); Navigator.of(context).pushNamed(AppRoutes.subscription); },
                          child: Text('Manage', style: TextStyle(color: AppColors.primary, fontSize: 12))),
                      ]),
                      // DA-1: animated arc ring (replaces flat LinearProgressIndicator)
                      if (_remoteLimitGb > 0) ...[
                        const SizedBox(height: 14),
                        DataUsageRing(
                          usedGb:  _remoteUsedGb,
                          limitGb: _remoteLimitGb,
                          onTap: () {
                            DebugLogger.logTap('Profile', 'dataUsage');
                            Navigator.of(context).pushNamed(
                              AppRoutes.dataUsage,
                              arguments: {
                                'used_gb':  _remoteUsedGb,
                                'limit_gb': _remoteLimitGb,
                              },
                            );
                          },
                        ),
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
                  // PROFILE-AUDIT-6: merged single-tile "General" + "Appearance"
                  // into one card — one-item section was visually heavy.
                  _Section(title: 'General', dotColor: AppColors.primary, children: [
                    _SectionTile(
                      icon: AppIcons.settings,
                      label: 'Settings',
                      subtitle: 'App settings and preferences',
                      onTap: () {
                        DebugLogger.logTap('Profile', 'settings');
                        Navigator.of(context).pushNamed(AppRoutes.settings);
                      },
                    ),
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.colorPalette,
                      label: 'Theme',
                      subtitle: 'Customise app colour theme',
                      trailing: ThemePickerTrailing(), // UX4-05
                      onTap: () => showThemePickerSheet(context), // UX4-05
                    ),
                  ]),
                  const SizedBox(height: RaddSpace.md),
                  // Player — expose reset actions for troubleshooting prefs/DB issues
                  _Section(title: 'Player', dotColor: AppColors.warning, children: [
                    _SectionTile(
                      icon: AppIcons.equalizer,
                      label: 'Reset Player Settings',
                      subtitle: 'Restore default playback preferences',
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
                      icon: AppIcons.history,
                      label: 'Reset Watch Progress',
                      subtitle: 'Clear all resume positions',
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
                  const SizedBox(height: RaddSpace.md),
                  // PROFILE-AUDIT-5: My Content before My Stats — stats summarise
                  // activity so they belong after the content lists, not before.
                  _Section(title: 'My Content', dotColor: AppColors.primary, children: [
                    _SectionTile(
                      icon: AppIcons.bookmarkFill,
                      iconColor: AppColors.primary,
                      label: 'My Watchlist',
                      subtitle: 'Saved content to watch later',
                      onTap: () { DebugLogger.logTap('Profile', 'watchlist'); Navigator.of(context).pushNamed(AppRoutes.watchlist); },
                    ),
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.history,
                      iconColor: AppColors.success,
                      label: 'Watch History',
                      subtitle: 'Recently watched content',
                      onTap: () { DebugLogger.logTap('Profile', 'history'); Navigator.of(context).pushNamed(AppRoutes.history); },
                    ),
                  ]),
                  const SizedBox(height: RaddSpace.md),
                  _Section(
                    title: 'My Stats',
                    dotColor: AppColors.primary,
                    children: [const _StatsCard()],
                  ),
                  const SizedBox(height: RaddSpace.md),
                  // Device
                  _Section(title: 'Device', dotColor: AppColors.info, children: [
                    _SectionTile(
                      icon: AppIcons.device,
                      label: 'Device',
                      trailing: Text(_deviceName ?? '…',
                          style: TextStyle(color: t.textMuted, fontSize: 12)),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: _hasInternet ? AppIcons.wifi : AppIcons.wifiOff,
                      iconColor: _hasInternet ? AppColors.success : AppColors.error,
                      label: 'Network',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (_hasInternet ? AppColors.success : AppColors.error).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_hasInternet ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: _hasInternet ? AppColors.success : AppColors.error,
                              fontSize: 11, fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                  ]),
                  const SizedBox(height: RaddSpace.md),
                  // Account
                  _Section(title: 'Account', dotColor: AppColors.primary, children: [
                    _SectionTile(
                      icon: AppIcons.crown,
                      iconColor: AppColors.primary,
                      // PROFILE-AUDIT-3: active subscribers see "Manage Plan".
                      label: user?.hasActiveSubscription == true ? 'Manage Plan' : 'Upgrade Plan',
                      subtitle: user?.hasActiveSubscription == true
                          ? 'Adjust or renew your plan'
                          : 'Get more content and storage',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.subscription),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.users,
                      iconColor: AppColors.info,
                      label: 'Switch Profile',
                      subtitle: 'Change active viewer profile',
                      trailing: activeProfile != null
                          ? Text(activeProfile.name, style: TextStyle(
                              color: t.textMuted, fontSize: 13, fontWeight: FontWeight.w500))
                          : null,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.profileSwitcher),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.manageAccount,
                      iconColor: const Color(0xFF14B8A6),
                      label: 'Manage Profiles',
                      subtitle: 'Add, edit or remove profiles',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.addProfile),
                    ),
                    if (!isKidsProfile) ...[
                      _divider(),
                      _SectionTile(
                        icon: AppIcons.lock,
                        iconColor: AppColors.simosaAccent,
                        label: 'Private Vault',
                        subtitle: 'PIN-protected private folder',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x207C5CFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('PRIVATE', style: TextStyle(
                              color: AppColors.simosaAccent, fontSize: 10, fontWeight: FontWeight.w700)),
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
                    ],
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.downloads,
                      label: 'Downloads',
                      subtitle: 'Manage offline content',
                      onTap: () { DebugLogger.logTap('Profile', 'downloads'); Navigator.of(context).pushNamed(AppRoutes.downloads); },
                    ),
                    // L1: Debug Logs hidden in production for non-admin users
                    if (kDebugMode || (user?.isAdmin == true)) ...[
                      _divider(),
                      _SectionTile(
                        icon: AppIcons.bugReport,
                        iconColor: AppColors.orange,
                        label: 'Debug Logs',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const DebugDiagnosticsScreen())),
                      ),
                    ],
                    _divider(),
                    _SectionTile(
                      icon: AppIcons.logout,
                      iconColor: AppColors.error,
                      label: 'Sign Out',
                      subtitle: 'Sign out of your account',
                      labelColor: AppColors.error,
                      onTap: _loggingOut ? null : _logout,
                    ),
                  ]),
                  const SizedBox(height: RaddSpace.lg), // PROFILE-AUDIT-8
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
                          // L2: Easter egg only opens diagnostics for admins/debug builds
                          if (kDebugMode || (user?.isAdmin == true)) {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const DebugDiagnosticsScreen()));
                          }
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

  Widget _divider() => const Divider(height: 1, indent: 54);


  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return iso; }
  }
}


class _Section extends ConsumerWidget {
  final String title;
  final List<Widget> children;
  final Color? dotColor;
  const _Section({required this.title, required this.children, this.dotColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RaddTheme.of(context);
    final animConfig = ref.watch(animConfigProvider);
    final dot = dotColor ?? AppColors.primary;

    final cardDecoration = BoxDecoration(
      color: animConfig.canBlur ? t.card.withOpacity(0.80) : t.card,
      borderRadius: RaddRadius.mdRadius,
      border: Border.all(color: t.cardBorder.withOpacity(0.85), width: 0.5),
    );

    final specularDecoration = BoxDecoration(
      borderRadius: RaddRadius.mdRadius,
      border: Border(top: BorderSide(color: t.glassHigh, width: 1.0)),
    );

    Widget cardContent = DecoratedBox(
      decoration: cardDecoration,
      child: Stack(children: [
        Positioned.fill(child: DecoratedBox(decoration: specularDecoration)),
        Column(children: children),
      ]),
    );

    if (animConfig.canBlur) {
      cardContent = ClipRRect(
        borderRadius: RaddRadius.mdRadius,
        child: RaddElevation.blurWrap(sigma: 12, child: cardContent),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: dot.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: RaddSpace.sm),
          Text(title.toUpperCase(), style: TextStyle(
              color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 1.2)),
        ]),
      ),
      cardContent,
    ]);
  }
}

// ── Stats Card ───────────────────────────────────────────────────────────────
// PROFILE-AUDIT-2: converted to StatefulWidget so _statsFuture is created
// once in initState() — previously called as a StatelessWidget which
// recreated the DB query on every parent rebuild, causing stats to flicker
// back to the loading spinner whenever connectivity or tap-count changed.
class _StatsCard extends StatefulWidget {
  const _StatsCard();
  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  late final Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = LocalDb.getWatchStats();
  }

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
    return FutureBuilder<Map<String, dynamic>>(
      future: _statsFuture,
      builder: (context, snap) {
        final t        = RaddTheme.of(context);
        final data     = snap.data;
        final totalMs  = (data?['total_ms']  as int?) ?? 0;
        final completed= (data?['completed'] as int?) ?? 0;
        final dlCount  = (data?['dl_count']  as int?) ?? 0;
        final dlBytes  = (data?['dl_bytes']  as int?) ?? 0;
        final topGenre = data?['top_genre']  as String?;
        return Padding(
          padding: EdgeInsets.all(RaddSpace.md),
          child: snap.connectionState == ConnectionState.waiting
              ? Center(child: SizedBox(height: 40, child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary))))
              : Column(children: [
                  Row(children: [
                    _StatTile(
                      icon: AppIcons.clock,
                      iconColor: AppColors.primary,
                      label: 'Watch Time',
                      value: totalMs > 0 ? _fmtTime(totalMs) : '—',
                      countTarget: totalMs > 0 ? totalMs : null,
                      countFormatter: _fmtTime,
                    ),
                    _StatDivider(),
                    _StatTile(
                      icon: AppIcons.successIcon,
                      iconColor: AppColors.success,
                      label: 'Completed',
                      value: completed > 0 ? '$completed' : '—',
                      countTarget: completed > 0 ? completed : null,
                      countFormatter: (v) => '$v',
                    ),
                  ]),
                  Divider(height: 1, color: t.border),
                  Row(children: [
                    _StatTile(
                      icon: AppIcons.downloadAction,
                      iconColor: AppColors.info,
                      label: 'Downloads',
                      value: dlCount > 0 ? '$dlCount (${_fmtBytes(dlBytes)})' : '—',
                      countTarget: dlCount > 0 ? dlCount : null,
                      countFormatter: (v) => '$v (${_fmtBytes(dlBytes)})',
                    ),
                    _StatDivider(),
                    _StatTile(
                      icon: AppIcons.trending,
                      iconColor: AppColors.warning,
                      label: 'Top Genre',
                      value: topGenre ?? '—',
                    ),
                  ]),
                ]),
        );
      },
    );
  }
}

class _StatTile extends ConsumerStatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  // Phase 53: when set, animates a count-up from 0 to [countTarget] using
  // [countFormatter] to render each intermediate frame. Tier 1+ (basic) only —
  // potato devices and reduced-motion settings render [value] statically.
  final int? countTarget;
  final String Function(int)? countFormatter;
  const _StatTile({required this.icon, required this.iconColor,
      required this.label, required this.value,
      this.countTarget, this.countFormatter});

  @override
  ConsumerState<_StatTile> createState() => _StatTileState();
}

class _StatTileState extends ConsumerState<_StatTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _tween;

  bool get _canCountUp =>
      widget.countTarget != null && widget.countFormatter != null;

  @override
  void initState() {
    super.initState();
    if (_canCountUp) {
      final animConfig = ref.read(animConfigProvider);
      final shouldAnimate = animConfig.tierLevel >= AnimTier.basic.index &&
          animConfig.shouldAnimate(context);
      if (shouldAnimate) {
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1100));
        _tween = Tween<double>(begin: 0, end: widget.countTarget!.toDouble())
            .animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeOutCubic));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl!.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

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
              color: widget.iconColor.withOpacity(0.12),
              border: Border.all(color: widget.iconColor.withOpacity(0.2)),
            ),
            child: Icon(widget.icon, size: 16, color: widget.iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tween != null
                  ? AnimatedBuilder(
                      animation: _tween!,
                      builder: (_, __) => Text(
                          widget.countFormatter!(_tween!.value.round()),
                          style: TextStyle(color: t.textPrimary, fontSize: 14,
                              fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )
                  : Text(widget.value,
                      style: TextStyle(color: t.textPrimary, fontSize: 14,
                          fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(widget.label,
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
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
  final String? subtitle;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SectionTile({required this.icon, this.iconColor, required this.label,
      this.subtitle, this.labelColor, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: subtitle != null ? 4 : 2),
      leading: Container(width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (iconColor ?? t.textMuted).withOpacity(0.12),
          border: Border.all(color: (iconColor ?? t.textMuted).withOpacity(0.15)),
        ),
        child: Icon(icon, size: 18, color: iconColor ?? t.textMuted)),
      title: Text(label, style: TextStyle(
          color: labelColor ?? t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: t.textMuted, fontSize: 11))
          : null,
      trailing: trailing ?? (onTap != null
          ? Icon(AppIcons.caretRight, color: t.textMuted, size: 20)
          : null),
      onTap: onTap,
    );
  }
}
