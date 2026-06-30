import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device animation tier — detected once at app start via Android SDK version.
///
/// Tier 0 — Potato  (API 21-22): fade/opacity only, 200ms max
/// Tier 1 — Basic   (API 23-27): flutter_animate, shimmer, stagger, 300ms max
/// Tier 2 — Standard(API 28-32): card morphing, shadow glow, 400ms max
/// Tier 3 — Premium (API 33+)  : blur, shader, 3D tilt, particles, 600ms max
enum AnimTier { potato, basic, standard, premium }

class AnimConfig {
  final AnimTier tier;
  final int sdkInt;

  const AnimConfig({required this.tier, required this.sdkInt});

  /// Quick tier int (0-3) for comparisons.
  int get tierLevel => tier.index;

  /// Returns false if Android "Remove Animations" accessibility setting is on,
  /// or if tier is potato (API 21-22) and the animation is not just a simple fade.
  /// Always call this before adding any animation to a widget.
  bool shouldAnimate(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return false;
    return true;
  }

  // ── Capability flags ────────────────────────────────────────────────────────
  /// BackdropFilter blur — Skia is too slow on Mali-400/Adreno 3xx (API < 28)
  bool get canBlur     => tierLevel >= AnimTier.standard.index;
  /// Fragment shaders — OpenGL ES < 3.1 on API < 26
  bool get canShader   => tierLevel >= AnimTier.premium.index;
  /// Stagger / flutter_staggered_animations — safe from API 23+
  bool get canStagger  => tierLevel >= AnimTier.basic.index;
  /// OpenContainer morph — animations package, API 28+
  bool get canMorph    => tierLevel >= AnimTier.standard.index;
  /// Particle system — API 33+ only
  bool get canParticle => tierLevel >= AnimTier.premium.index;
  /// Gyroscope tilt — API 33+ only
  bool get canGyro     => tierLevel >= AnimTier.premium.index;

  // ── Tier-aware durations ────────────────────────────────────────────────────
  Duration get fast   => tierLevel == 0 ? const Duration(milliseconds: 150)
                       : tierLevel == 1 ? const Duration(milliseconds: 200)
                                        : const Duration(milliseconds: 250);
  Duration get normal => tierLevel == 0 ? const Duration(milliseconds: 200)
                       : tierLevel == 1 ? const Duration(milliseconds: 300)
                                        : const Duration(milliseconds: 400);
  Duration get slow   => tierLevel == 0 ? const Duration(milliseconds: 250)
                       : tierLevel == 1 ? const Duration(milliseconds: 350)
                                        : const Duration(milliseconds: 550);

  /// Stagger delay between list/grid items (0ms on potato to avoid jank).
  Duration stagger(int index) {
    final base = tierLevel == 0 ? 0 : tierLevel == 1 ? 25 : 35;
    return Duration(milliseconds: base * index);
  }

  // ── Detection ───────────────────────────────────────────────────────────────
  /// Detect the current device tier. Call once at app startup in main().
  static Future<AnimConfig> detect() async {
    final info = DeviceInfoPlugin();
    int sdk = 33; // safe default — assume premium if detection fails
    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        sdk = android.version.sdkInt;
      }
    } catch (_) {}
    return AnimConfig(
      sdkInt: sdk,
      tier: sdk < 23 ? AnimTier.potato
          : sdk < 28 ? AnimTier.basic
          : sdk < 33 ? AnimTier.standard
                     : AnimTier.premium,
    );
  }
}

/// Global Riverpod provider — initialized in main() via overrideWithValue().
/// Read anywhere: final anim = ref.watch(animConfigProvider);
final animConfigProvider = Provider<AnimConfig>(
  (_) => throw UnimplementedError(
    'animConfigProvider not initialized — call AnimConfig.detect() in main() '
    'and pass result to ProviderScope(overrides: [animConfigProvider.overrideWithValue(cfg)])',
  ),
);
