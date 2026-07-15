import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/radd_theme.dart';
import '../core/theme/radd_colors.dart';
import '../design_system/elevation/radd_elevation.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import '../core/constants.dart';
import '../core/utils/anim_config.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import 'add_edit_profile_screen.dart';
import 'home_screen.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Color hexToColor(String h) {
  final s = h.replaceAll('#', '');
  return Color(int.parse('FF$s', radix: 16));
}

/// Derives a stable accent color for a profile from its id and name via a
/// deterministic hash into a curated palette. No new persisted field needed.
Color _accentForProfile(Profile p) {
  // Use the stored avatarColor if it is set to something other than the generic
  // default — if the user explicitly chose a color, respect it.
  final stored = hexToColor(p.avatarColor);

  // We still want a slightly-richer palette option for profiles whose stored
  // color is the out-of-the-box default '#8B002D'. In that case we hash the
  // id into the curated set. This keeps things deterministic without a DB field.
  const defaultHex = '#8B002D';
  if (p.avatarColor.toUpperCase() != defaultHex.toUpperCase()) {
    return stored;
  }

  // Curated palette — varied hues that look great on dark surfaces.
  const palette = [
    Color(0xFFE8002D), // signal red
    Color(0xFF7C5CFF), // simosa purple
    Color(0xFF3B82F6), // info blue
    Color(0xFF10B981), // teal
    Color(0xFFF59E0B), // amber
    Color(0xFFEC4899), // rose
    Color(0xFF06B6D4), // cyan
    Color(0xFF8B5CF6), // violet
  ];

  final hash = (p.id * 2654435761) ^ p.name.codeUnits.fold(0, (a, b) => a ^ b);
  return palette[(hash.abs() % palette.length)];
}

// ── Fade page route (Tier 0/1 fallback) ──────────────────────────────────────

/// Lightweight fade-only transition for Tier 0/1 devices where canMorph is
/// false. Still feels deliberate compared to the default system push slide,
/// without the GPU-heavy scale compositing required by _ZoomMorphRoute.
class _FadeRoute<T> extends PageRouteBuilder<T> {
  _FadeRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                  parent: animation, curve: Curves.easeOut),
              child: child,
            );
          },
        );
}

// ── Zoom-morph page route ────────────────────────────────────────────────────

/// A custom route that zooms-and-fades from the tapped avatar's screen
/// position into the destination screen — spec: 320–400ms, cubic(0.2,0,0,1).
class _ZoomMorphRoute<T> extends PageRouteBuilder<T> {
  _ZoomMorphRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const curve = Cubic(0.2, 0, 0, 1);
            final curved =
                CurvedAnimation(parent: animation, curve: curve);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// "Who's Watching?" — shown after login (when the account has more than one
/// profile) and reachable any time from Settings → Switch Profile.
class ProfileSwitcherScreen extends ConsumerStatefulWidget {
  const ProfileSwitcherScreen({super.key});

  @override
  ConsumerState<ProfileSwitcherScreen> createState() =>
      _ProfileSwitcherScreenState();
}

class _ProfileSwitcherScreenState
    extends ConsumerState<ProfileSwitcherScreen> {
  bool _managing = false;
  bool _switching = false;

  /// Which profile is currently hovered/focused — drives the ambient bleed.
  int? _focusedProfileId;

  Future<void> _selectProfile(Profile p) async {
    if (_switching) return;
    if (_managing) {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AddEditProfileScreen(existing: p)),
      );
      if (result == true) await ref.read(profileProvider.notifier).load();
      return;
    }

    setState(() => _switching = true);
    bool ok = true;
    if (p.isLocked) {
      final pin = await _askPin(p);
      if (pin == null) {
        setState(() => _switching = false);
        return;
      }
      ok = await ref
          .read(profileProvider.notifier)
          .selectProfile(p.id, pin: pin);
    } else {
      ok = await ref.read(profileProvider.notifier).selectProfile(p.id);
    }

    if (!mounted) return;
    if (!ok) {
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Incorrect PIN'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    // Force a fresh Home so per-profile watchlist / continue-watching / resume
    // widgets reload for the newly active profile.
    ref.read(watchlistProvider.notifier).load();

    // Zoom-morph transition into home — gated by canMorph (Standard tier+).
    // On lower tiers fall back to a flat named-route push which has no custom
    // transition, avoiding any frame-budget risk on slower GPUs.
    final animCfg = ref.read(animConfigProvider);
    if (animCfg.canMorph) {
      Navigator.of(context).pushAndRemoveUntil(
        _ZoomMorphRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      // Tier 0/1: lightweight fade transition — feels intentional without
      // the GPU-heavy scale compositing that canMorph gates.
      Navigator.of(context).pushAndRemoveUntil(
        _FadeRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  Future<String?> _askPin(Profile p) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinEntrySheet(profile: p),
    );
  }

  Future<void> _addProfile() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddEditProfileScreen()),
    );
    if (result == true) await ref.read(profileProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final animCfg = ref.watch(animConfigProvider);
    final state = ref.watch(profileProvider);
    final canPop = Navigator.of(context).canPop();

    // Determine which profile is ambient-focused: the active one or the one
    // the user last hovered. Falls back to the active profile.
    Profile? ambientProfile;
    if (_focusedProfileId != null) {
      try {
        ambientProfile = state.profiles
            .firstWhere((p) => p.id == _focusedProfileId);
      } catch (_) {}
    }
    ambientProfile ??= state.active;

    final ambientColor =
        ambientProfile != null ? _accentForProfile(ambientProfile) : null;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: canPop
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(AppIcons.close, color: t.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Ambient color bleed layer ─────────────────────────────
            if (ambientColor != null)
              _AmbientBleed(
                color: ambientColor,
                animate: animCfg.canStagger,
              ),

            // ── 2. Content ───────────────────────────────────────────────
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RaddSpace.lg, vertical: RaddSpace.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Who's Watching?",
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w800),
                      )
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: 0.15, end: 0),
                      const SizedBox(height: RaddSpace.sm),
                      Text(
                        _managing
                            ? 'Tap a profile to edit it'
                            : 'Select a profile to continue',
                        style:
                            TextStyle(color: t.textMuted, fontSize: 14),
                      ).animate(delay: 60.ms).fadeIn(),
                      const SizedBox(height: 36),
                      Wrap(
                        spacing: 20,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          for (int i = 0; i < state.profiles.length; i++)
                            _ProfileTile(
                              profile: state.profiles[i],
                              isActive:
                                  state.active?.id == state.profiles[i].id,
                              managing: _managing,
                              onTap: () =>
                                  _selectProfile(state.profiles[i]),
                              onFocus: () => setState(() =>
                                  _focusedProfileId = state.profiles[i].id),
                              onBlur: () => setState(
                                  () => _focusedProfileId = null),
                              animCfg: animCfg,
                            ).animate(delay: (100 + i * 60).ms)
                                .fadeIn()
                                .slideY(begin: 0.2, end: 0),
                          if (state.profiles.length < kMaxProfiles)
                            _AddProfileTile(onTap: _addProfile)
                                .animate(
                                    delay: (100 +
                                            state.profiles.length * 60)
                                        .ms)
                                .fadeIn(),
                        ],
                      ),
                      const SizedBox(height: 40),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _managing = !_managing),
                        icon: Icon(
                            _managing ? AppIcons.check : AppIcons.edit,
                            size: 18,
                            color: t.textMuted),
                        label: Text(
                          _managing ? 'Done' : 'Manage Profiles',
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ambient bleed ─────────────────────────────────────────────────────────────

/// Renders a soft centered radial gradient that bleeds the focused profile's
/// accent color into the background — Apple Liquid Glass "ambient color" style.
class _AmbientBleed extends StatefulWidget {
  final Color color;
  final bool animate;

  const _AmbientBleed({required this.color, required this.animate});

  @override
  State<_AmbientBleed> createState() => _AmbientBleedState();
}

class _AmbientBleedState extends State<_AmbientBleed>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AmbientBleed old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return _buildGradient(1.0);
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => _buildGradient(_opacity.value),
    );
  }

  Widget _buildGradient(double opacity) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [
              widget.color.withOpacity(0.18 * opacity),
              widget.color.withOpacity(0.06 * opacity),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

// ── Profile tile ──────────────────────────────────────────────────────────────

class _ProfileTile extends StatefulWidget {
  final Profile profile;
  final bool isActive;
  final bool managing;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onBlur;
  final AnimConfig animCfg;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.managing,
    required this.onTap,
    required this.onFocus,
    required this.onBlur,
    required this.animCfg,
  });

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseOpacity;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    if (widget.animCfg.canStagger) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ProfileTile old) {
    super.didUpdateWidget(old);
    if (widget.animCfg.canStagger && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.animCfg.canStagger && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final color = _accentForProfile(widget.profile);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => widget.onFocus(),
      onTapUp: (_) => widget.onBlur(),
      onTapCancel: widget.onBlur,
      child: MouseRegion(
        onEnter: (_) => widget.onFocus(),
        onExit: (_) => widget.onBlur(),
        child: SizedBox(
          width: 96,
          child: Column(children: [
            Stack(alignment: Alignment.center, children: [
              // Breathing ring (Pulse primitive)
              _PulseRing(
                color: color,
                isActive: widget.isActive,
                pulseCtrl: _pulseCtrl,
                pulseOpacity: _pulseOpacity,
                pulseScale: _pulseScale,
                canStagger: widget.animCfg.canStagger,
              ),

              // Avatar circle
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: widget.isActive
                      ? Border.all(color: Colors.white, width: 3)
                      : Border.all(
                          color: color.withOpacity(0.25), width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(
                            widget.isActive ? 0.55 : 0.3),
                        blurRadius: widget.isActive ? 24 : 14,
                        spreadRadius: widget.isActive ? 2 : 0),
                  ],
                ),
                child: Center(
                  child: widget.profile.avatarEmoji.isNotEmpty
                      ? Text(widget.profile.avatarEmoji,
                          style: const TextStyle(fontSize: 36))
                      : Text(
                          widget.profile.avatarInitial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900),
                        ),
                ),
              ),

              if (widget.profile.isKids)
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: RaddRadius.smRadius,
                      border: Border.all(color: t.bg, width: 2),
                    ),
                    child: const Text('KIDS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              if (widget.profile.isLocked && !widget.managing)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: EdgeInsets.all(RaddSpace.xs),
                    decoration: BoxDecoration(
                      color: t.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.bg, width: 2),
                    ),
                    child:
                        Icon(AppIcons.lock, size: 11, color: t.textMuted),
                  ),
                ),
              if (widget.managing)
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.4),
                  ),
                  child: Center(
                    child:
                        Icon(AppIcons.edit, color: Colors.white, size: 26),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Text(
              widget.profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: widget.isActive ? t.textPrimary : t.textMuted,
                  fontSize: 13,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w500),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Pulse ring ────────────────────────────────────────────────────────────────

/// The animated ring behind each avatar implementing the Pulse motion primitive
/// (1800ms, opacity 1 ↔ 0.6, scale 1 ↔ 1.03). Gated by canStagger — falls
/// back to a static ring when false.
class _PulseRing extends StatelessWidget {
  final Color color;
  final bool isActive;
  final AnimationController pulseCtrl;
  final Animation<double> pulseOpacity;
  final Animation<double> pulseScale;
  final bool canStagger;

  const _PulseRing({
    required this.color,
    required this.isActive,
    required this.pulseCtrl,
    required this.pulseOpacity,
    required this.pulseScale,
    required this.canStagger,
  });

  @override
  Widget build(BuildContext context) {
    final ringColor = color.withOpacity(isActive ? 0.55 : 0.30);
    const ringSize = 100.0;

    if (!canStagger) {
      // Static fallback
      return Container(
        width: ringSize,
        height: ringSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: 1.5),
        ),
      );
    }

    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) {
        return Opacity(
          opacity: pulseOpacity.value,
          child: Transform.scale(
            scale: pulseScale.value,
            child: Container(
              width: ringSize,
              height: ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Add profile tile ──────────────────────────────────────────────────────────

class _AddProfileTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProfileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Column(children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.surface,
              border: Border.all(
                  color: t.border, style: BorderStyle.solid, width: 1.5),
            ),
            child: Icon(AppIcons.add, color: t.textMuted, size: 34),
          ),
          const SizedBox(height: 10),
          Text('Add Profile',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ── PIN entry bottom sheet ────────────────────────────────────────────────────

class _PinEntrySheet extends StatefulWidget {
  final Profile profile;
  const _PinEntrySheet({required this.profile});

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  String _pin = '';
  bool _shake = false;

  void _tap(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      if (_pin == widget.profile.pin) {
        Navigator.of(context).pop(_pin);
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _shake = true);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() {
            _pin = '';
            _shake = false;
          });
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    // Use ProviderScope.containerOf to read animConfigProvider without a ref.
    // _PinEntrySheetState is not a ConsumerState, so we use the container.
    final animCfg = ProviderScope.containerOf(context, listen: false).read(animConfigProvider);

    // ── Shell geometry (RaddSheet spec) ─────────────────────────────────────
    // blur sigma 20, surfaceHigh @ 92%, 1px top border, lg top-corner radius
    final sheetContent = Container(
      decoration: BoxDecoration(
        color: t.surfaceHigh.withOpacity(0.92),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(RaddRadius.lg)),
        border: Border(top: BorderSide(color: t.border, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        RaddSpace.lg,
        RaddSpace.sm,
        RaddSpace.lg,
        RaddSpace.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
              color: t.textMuted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: RaddSpace.md),
        Icon(AppIcons.lock, color: context.signalPrimary, size: 28),
        const SizedBox(height: RaddSpace.sm),
        Text(
          'Enter PIN for ${widget.profile.name}',
          style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: RaddSpace.lg),
        // PIN dots with shake-on-wrong
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform:
              Matrix4.translationValues(_shake ? 8 : 0, 0, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < _pin.length;
              return Container(
                width: 16,
                height: 16,
                margin:
                    const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (_shake
                          ? AppColors.error
                          : AppColors.primary)
                      : Colors.transparent,
                  border: Border.all(
                      color: filled
                          ? (_shake
                              ? AppColors.error
                              : AppColors.primary)
                          : t.border,
                      width: 1.5),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: RaddSpace.lg + RaddSpace.sm),
        _GlassNumPad(onTap: _tap, onBackspace: _backspace, animCfg: animCfg),
      ]),
    );

    // Wrap in BackdropFilter when device supports blur (canBlur gate)
    if (animCfg.canBlur) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(RaddRadius.lg)),
        child: RaddElevation.blurWrap(
          sigma: RaddElevation.sheetBlurSigma,
          child: sheetContent,
        ),
      );
    }
    return sheetContent;
  }
}

// ── Glass numpad (RaddLockPad spec) ───────────────────────────────────────────

/// Per the RaddLockPad component spec:
///   64×64dp circle, glass @ 7% fill, 1px border, elastic scale-in on tap
///   (220ms spring, 12% overshoot — motion doc "Lock numpad key" row).
class _GlassNumPad extends StatelessWidget {
  final ValueChanged<String> onTap;
  final VoidCallback onBackspace;
  final AnimConfig animCfg;

  const _GlassNumPad({
    required this.onTap,
    required this.onBackspace,
    required this.animCfg,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);

    Widget key(String label, {Widget? child, VoidCallback? onPressed}) {
      return _GlassKey(
        label: label,
        child: child,
        onPressed: onPressed ?? (label.isEmpty ? null : () => onTap(label)),
        animCfg: animCfg,
        textColor: t.textPrimary,
        glassColor: t.glass,
        borderColor: t.border,
      );
    }

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: RaddSpace.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) => key(d)).toList(),
          ),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        key('', child: const SizedBox.shrink()),
        key('0'),
        key(
          '',
          child: Icon(AppIcons.backspace, size: 20, color: t.textMuted),
          onPressed: onBackspace,
        ),
      ]),
    ]);
  }
}

/// A single RaddLockPad key: 64×64dp circle, glass 7% fill, 1px border.
/// Elastic scale-in on tap: 220ms, spring 12% overshoot — gated by canStagger.
class _GlassKey extends StatefulWidget {
  final String label;
  final Widget? child;
  final VoidCallback? onPressed;
  final AnimConfig animCfg;
  final Color textColor;
  final Color glassColor;
  final Color borderColor;

  const _GlassKey({
    required this.label,
    required this.onPressed,
    required this.animCfg,
    required this.textColor,
    required this.glassColor,
    required this.borderColor,
    this.child,
  });

  @override
  State<_GlassKey> createState() => _GlassKeyState();
}

class _GlassKeyState extends State<_GlassKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    // Spring 12% overshoot — cubic approximation per motion doc.
    _pressScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.animCfg.canStagger) {
      _pressCtrl.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.animCfg.canStagger) {
      _pressCtrl.reverse();
    }
    widget.onPressed?.call();
  }

  void _handleTapCancel() {
    if (widget.animCfg.canStagger) {
      _pressCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // glass @ 7% fill = Color(0x12FFFFFF) ≈ the glass token (0x0D-0x12 range)
    // We build our own 7% fill so it matches the spec precisely.
    final glassFill = Colors.white.withOpacity(0.07);

    Widget keyWidget = GestureDetector(
      onTapDown: widget.onPressed != null ? _handleTapDown : null,
      onTapUp: widget.onPressed != null ? _handleTapUp : null,
      onTapCancel: widget.onPressed != null ? _handleTapCancel : null,
      child: Container(
        width: 64,
        height: 64,
        margin: const EdgeInsets.symmetric(
            horizontal: RaddSpace.sm, vertical: 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.onPressed != null ? glassFill : Colors.transparent,
          border: widget.onPressed != null
              ? Border.all(color: widget.borderColor, width: 1)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Specular sheen along the top of the key, consistent with the
            // glass surfaces used elsewhere on this screen (avatar rings,
            // PIN sheet), so the numpad reads as part of the same material.
            if (widget.onPressed != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipOval(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: FractionallySizedBox(
                        heightFactor: 0.42,
                        widthFactor: 1.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.14),
                                Colors.white.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: widget.child ??
                  Text(
                    widget.label,
                    style: TextStyle(
                        color: widget.textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w600),
                  ),
            ),
          ],
        ),
      ),
    );

    if (widget.animCfg.canStagger) {
      return AnimatedBuilder(
        animation: _pressCtrl,
        builder: (_, child) => Transform.scale(
          scale: _pressScale.value,
          child: child,
        ),
        child: keyWidget,
      );
    }
    return keyWidget;
  }
}
