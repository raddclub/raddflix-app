import 'dart:async';
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
import '../providers/watchlist_provider.dart';
import '../providers/subscription_provider.dart';
import '../core/api/subscription_api.dart';
import '../widgets/loading_overlay.dart';
import '../core/player/scene_bookmark_store.dart';  // BUG-A23
import '../core/player/player_prefs.dart';          // BUG-A21
import '../core/db/local_db.dart';                  // BUG-A22

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
  String? _remotePlan;
  late final _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChange);

  @override
  void initState() {
    super.initState();
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
      setState(() { _remotePlan = status.plan; });
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
    _connectivitySub.cancel();
    super.dispose();
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
    final initial = user?.phone.isNotEmpty == true ? user!.phone[0].toUpperCase() : 'U';

    return LoadingOverlay(
      loading: _loggingOut,
      child: Scaffold(
        backgroundColor: null,
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
                  Stack(alignment: Alignment.center, children: [
                    // Outer glow ring
                    Container(
                      width: 106, height: 106,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1.5),
                      ),
                    ),
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.45), blurRadius: 28, spreadRadius: 2),
                        ],
                      ),
                      child: Center(child: Text(initial, style: TextStyle(
                          color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900))),
                    ),
                  ]).animate().scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1),
                      duration: 400.ms, curve: AppCurves.enter),
                  SizedBox(height: 14),
                  Text(user?.phone ?? '—', style: TextStyle(
                      color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w700,
                      letterSpacing: -0.3))
                      .animate(delay: 100.ms).fadeIn(duration: 300.ms),
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
                    child: Row(children: [
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
                        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.subscription),
                        child: Text('Manage', style: TextStyle(fontSize: 12))),
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
                  // Appearance
                  _Section(title: 'Appearance', children: [
                    _SectionTile(
                      icon: Icons.palette_outlined,
                      label: 'Theme',
                      trailing: Text(ref.watch(themeProvider.notifier).displayName,
                          style: TextStyle(color: t.textMuted, fontSize: 13)),
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
                  _Section(title: 'My Content', children: [
                    _SectionTile(
                      icon: Icons.bookmark_rounded,
                      iconColor: AppColors.primary,
                      label: 'My Watchlist',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.watchlist),
                    ),
                    _divider(),
                    _SectionTile(
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF22C55E),
                      label: 'Watch History',
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.history),
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
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.downloads),
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

class _ThemePicker extends ConsumerWidget {
  static const _options = [
    (JazzTheme.dark,   '🌙', 'Dark',   'Deep dark background'),
    (JazzTheme.amoled, '⬛', 'AMOLED', 'Pure black for OLED screens'),
    (JazzTheme.light,  '☀️', 'Light',  'Light background'),
    (JazzTheme.auto,   '🔄', 'Auto',   'Follows time of day'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RaddTheme.of(context);
    final current = ref.watch(themeProvider).mode;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: t.textMuted.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
        Text('Choose Theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: t.textPrimary)),
        const SizedBox(height: 16),
        ..._options.map((opt) => _ThemeOption(
          icon: opt.$2, title: opt.$3, subtitle: opt.$4,
          isSelected: current == opt.$1,
          onTap: () {
            ref.read(themeProvider.notifier).setTheme(opt.$1);
            Navigator.pop(context);
          },
        )),
      ]),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String icon, title, subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  const _ThemeOption({required this.icon, required this.title, required this.subtitle,
      required this.isSelected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.12) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: isSelected ? AppColors.primary : t.border)),
        child: Row(children: [
          Text(icon, style: TextStyle(fontSize: 24)),
          SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: isSelected ? AppColors.primary : t.textPrimary,
                fontWeight: FontWeight.w600, fontSize: 15)),
            Text(subtitle, style: TextStyle(color: t.textMuted, fontSize: 12)),
          ])),
          if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
        ]),
      ),
    );
  }
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
