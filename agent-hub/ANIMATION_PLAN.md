# RaddFlix Animation Roadmap
> Created: 2026-06-30 | Owner: Agent | Target: All Android API 21+ (Android 5+)

---

## 🎯 Mission Statement

Deliver a streaming-app-quality animation system that feels **premium on flagship phones**
and **fast and snappy on low-end Android 5 devices** (1 GB RAM, weak GPU).
Every animation decision is gated by a device tier — no animation ever runs unconditionally.

---

## ⚠️ Hard Performance Rules (must never be broken)

| Rule | Rationale |
|------|-----------|
| **RULE-1** Respect `MediaQuery.of(ctx).disableAnimations` | Android "Remove Animations" accessibility setting — always check first |
| **RULE-2** No `BackdropFilter` (blur) on API < 28 | Skia blur is painfully slow on Mali-400/Adreno 3xx GPUs (common in Pakistan low-end market) |
| **RULE-3** No Fragment Shaders on API < 26 | OpenGL ES < 3.1 cannot run custom GLSL reliably |
| **RULE-4** No more than 3 simultaneous running animations per screen | Compositing cost stacks — flatten using `RepaintBoundary` |
| **RULE-5** All animation durations ≤ 350ms on Tier 0/1 | Longer = user perceives lag, not beauty |
| **RULE-6** Never block user input waiting for an animation | Interactions must be responsive immediately |
| **RULE-7** No `rive` or `lottie` without explicit tier-3 gate | Both have heavy runtimes unsuitable for 1 GB devices |
| **RULE-8** Every animated widget gets `RepaintBoundary` if it doesn't affect siblings | Prevents full-tree repaints on each frame |
| **RULE-9** `const` constructors on all static widgets in the same tree | Zero-cost during animation frames |
| **RULE-10** Test every phase on API-21 emulator (512 MB RAM) before committing | Pakistani market has millions of entry-level phones |

---

## 📱 Device Tier System

Implemented in `lib/core/utils/anim_config.dart` (created in Phase 41).
Detection uses **Android SDK version** (available via `device_info_plus`, no extra permissions).

```
Tier 0 — Potato (API 21-22)  → fade/opacity ONLY, 200ms max, no shimmer, no stagger
Tier 1 — Basic   (API 23-27)  → flutter_animate effects, 300ms max, shimmer OK
Tier 2 — Standard (API 28-32) → card morphing, stagger, simple shadow glow, 400ms max
Tier 3 — Premium (API 33+)   → blur, shader glow, 3D tilt, particles, 600ms max
```

The `AnimConfig` class is a singleton initialized once at app start
and stored in a Riverpod `Provider<AnimConfig>` so every widget can read it cheaply.

---

## 📦 Package Budget

| Package | Already Installed | Tier Required | Notes |
|---------|:-----------------:|:-------------:|-------|
| `flutter_animate ^4.5.0` | ✅ | All tiers | Foundation for everything |
| `shimmer ^3.0.0` | ✅ | Tier 1+ | Already used in loading screens |
| `device_info_plus ^9.1.2` | ✅ | — | Used by AnimConfig |
| `animations ^2.x` (Google) | ❌ add | Tier 2+ | OpenContainer morph transition |
| `flutter_staggered_animations ^1.x` | ❌ add | Tier 1+ | List/grid stagger |
| `animated_text_kit ^4.x` | ❌ add | Tier 1+ | Typewriter, wavy text |
| `glow_effects ^1.x` | ❌ add (optional) | Tier 3 | GPU shader neon — only if stable |
| `liquid_glass_widgets` | ❌ skip | — | Too heavy; use manual BackdropFilter instead |
| `rive` | ❌ skip | — | Runtime too heavy for our audience |
| `lottie` | ❌ skip (Phase 48 only) | Tier 2+ | Only for specific loading JSON, lightweight files |

**3 new packages total** (animations, flutter_staggered_animations, animated_text_kit).
All are tiny, pure-Dart, maintained by Google or Flutter Favorites.

---

## 🗂️ Phase Breakdown

### Phase 41 — Performance Infrastructure *(do this FIRST)*
**Goal**: Build the tier detection + animation utility layer.
No animations added yet — only the engine that makes every future animation safe.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-41-01 | Create `AnimConfig` singleton + Riverpod provider | `lib/core/utils/anim_config.dart` | Reads AndroidSdkInt via device_info_plus, caches tier 0-3 |
| ANIM-41-02 | `AnimConfig.shouldAnimate(BuildContext ctx)` — checks `MediaQuery.disableAnimations` first | same file | Overrides tier if accessibility says reduce motion |
| ANIM-41-03 | Audit home_screen + downloads_screen: wrap isolated animated widgets with `RepaintBoundary` | both screens | Every shimmer card, every animated list item |
| ANIM-41-04 | Add `animations`, `flutter_staggered_animations`, `animated_text_kit` to pubspec.yaml | `pubspec.yaml` | All small packages |
| ANIM-41-05 | Set `Animate.restartOnHotReload = kDebugMode` in main.dart | `main.dart` | Avoid wasted cycles in release builds |
| ANIM-41-06 | Create `lib/core/utils/anim_durations.dart` — tier-aware duration constants | new file | FAST/NORMAL/SLOW per tier |

**Acceptance criteria**: AnimConfig.tier returns correct value on API-21 emulator (0), API-28 (2), API-34 (3). All future phases MUST use AnimConfig.

---

### Phase 42 — Hero Poster Transition *(zero cost, built-in Flutter)*
**Goal**: Poster image morphs from grid thumbnail → detail screen banner.
No new package. Works API 21+. Zero performance cost.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-42-01 | Wrap poster `Image`/`CachedNetworkImage` in home grid with `Hero(tag: 'poster_${item.id}')` | `home_screen.dart` | Tag must match exactly |
| ANIM-42-02 | Wrap banner image on show_detail_screen with matching `Hero(tag: 'poster_${item.id}')` | `show_detail_screen.dart` | SliverAppBar background image |
| ANIM-42-03 | Wrap poster in search_screen results with Hero | `search_screen.dart` | Same tag pattern |
| ANIM-42-04 | Wrap poster in downloads_screen grid cards with Hero | `downloads_screen.dart` | Tag: 'dl_poster_${fileId}' |
| ANIM-42-05 | Set `PageRouteBuilder` default transition to `FadeTransition` (replace MaterialPageRoute push slide) | `app.dart` or router | Cleaner than slide-from-right on streaming apps |

**Acceptance criteria**: Tap a content card → poster smoothly morphs into banner. No jank on API-21 emulator. Back navigation reverses the Hero.

---

### Phase 43 — Staggered Grid / List Entry *(flutter_staggered_animations)*
**Goal**: Home screen content cards and downloads grid cascade in with a stagger effect instead of all appearing at once. Tier 1+ only.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-43-01 | Wrap home screen `GridView.builder` itemBuilder with `AnimationConfiguration.staggeredGrid` + `FadeInAnimation` + `SlideAnimation` | `home_screen.dart` | Tier 1+ gate; stagger offset 25ms, slideY begin 0.06 |
| ANIM-43-02 | Apply same stagger to downloads grid (`_gridView`) | `downloads_screen.dart` | Already has `.animate(delay: (i*30).ms)` — replace with proper AnimationLimiter |
| ANIM-43-03 | Apply stagger to search results grid/list | `search_screen.dart` | |
| ANIM-43-04 | Apply stagger to "More Like This" horizontal scroll on detail screen | `show_detail_screen.dart` | |
| ANIM-43-05 | Gate all stagger with `if (animConfig.tier >= 1 && animConfig.shouldAnimate(context))` | all above files | Tier 0: no animation wrapper, raw widget |

**Acceptance criteria**: On Tier 0 (API-21): plain grid, no animation, instant render. On Tier 1+: cards cascade in smoothly at ≤60fps.

---

### Phase 44 — Card → Detail Screen Morph *(animations package, Tier 2+)*
**Goal**: Tapping a content card expands into the detail screen using OpenContainer — the card physically grows into the page.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-44-01 | Wrap content grid card with `OpenContainer` (closedBuilder = card widget, openBuilder = ShowDetailScreen) | `home_screen.dart` | Tier 2+ only; Tier 0/1 keep regular Navigator.push |
| ANIM-44-02 | Set `closedElevation: 0`, `openElevation: 0`, `transitionDuration: AnimDurations.morph` | same | |
| ANIM-44-03 | Set `closedColor: Colors.transparent` so the card background is preserved | same | Avoids white flash |
| ANIM-44-04 | Ensure Hero tags are REMOVED from cards that use OpenContainer (they conflict) | `home_screen.dart` | Hero + OpenContainer cannot coexist on same widget |
| ANIM-44-05 | Apply same OpenContainer to search result cards (Tier 2+) | `search_screen.dart` | |

**Acceptance criteria**: On Tier 2+ Android 28 emulator: card morphs to detail page. On Tier 0/1: regular Navigator.push works identically. No ANR or jank. Back gesture dismisses correctly.

---

### Phase 45 — Neon/Glow on Primary Action Buttons *(flutter_animate + BoxShadow, all tiers with degradation)*
**Goal**: Play button and Download button have a subtle pulsing glow. No GPU shader on low-end — uses BoxShadow pulsing (CPU, cheap). GPU shader only on Tier 3.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-45-01 | Tier 0/1: add `.animate(onPlay: (c) => c.repeat(reverse:true)).boxShadow(end: BoxShadow(color: primary.withOpacity(0.5), blurRadius: 14))` to Play button | `show_detail_screen.dart` | Pure CSS-style pulse, zero GPU cost |
| ANIM-45-02 | Tier 2: same but with stronger shadow + scale(end:1.03) breathing effect | same | |
| ANIM-45-03 | Tier 3: optionally wrap with `glow_effects` NeonGlowEffect if package stable | same | Guard behind try/catch, fallback to Tier 2 |
| ANIM-45-04 | Apply pulsing glow to Download button when a download is actively running | `show_detail_screen.dart`, `episode_tile.dart` | Use `isDownloading` state to start/stop animation |
| ANIM-45-05 | Download complete: `.animate().shake(duration:400.ms).scale(begin:1.0, end:1.15)` burst on done SnackBar icon | `downloads_screen.dart` | Already-installed flutter_animate, all tiers |

**Acceptance criteria**: Play button glows softly on all tiers. No stutter on Tier 0 (API-21). On Tier 3: neon effect visible without frame drops.

---

### Phase 46 — Typewriter & Animated Text *(animated_text_kit, Tier 1+)*
**Goal**: Episode description/synopsis types itself in on the detail screen. Tagline on hero banner has a fade-loop. Adds personality to content browsing.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-46-01 | Synopsis text on show_detail_screen: `TypewriterAnimatedText` (speed: 18ms/char, cursor: '', pause: 3s) | `show_detail_screen.dart` | Tier 1+; Tier 0 = plain Text widget |
| ANIM-46-02 | Only trigger typewriter AFTER page transition finishes (use `WidgetsBinding.addPostFrameCallback + 300ms delay`) | same | Avoids competing with Hero/OpenContainer animation |
| ANIM-46-03 | Movie/show tagline on hero banner: `FadeAnimatedText` looping between tagline + year + rating | same | Tier 1+; only if tagline data available |
| ANIM-46-04 | "Now Downloading" label in downloads storage bar: `WavyAnimatedText` when active > 0 | `downloads_screen.dart` | Subtle, very short |
| ANIM-46-05 | Genre chips on home screen filter row: `.animate().shimmer()` on initial load | `home_screen.dart` | flutter_animate already installed |

**Acceptance criteria**: Typewriter starts after page transition, never during. Text readable at all speeds. On Tier 0: no typewriter, plain text.

---

### Phase 47 — Frosted Glass Bottom Nav *(manual BackdropFilter, Tier 2+)*
**Goal**: Bottom navigation bar becomes translucent frosted glass. Content scrolls behind it. Tier 2+ only (BackdropFilter needs API 28+).

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-47-01 | Wrap BottomNav widget with `BackdropFilter(filter: ImageFilter.blur(sigmaX:12, sigmaY:12))` + semi-transparent container | `bottom_nav.dart` | Tier 2+ ONLY — check tier before adding filter |
| ANIM-47-02 | Tier 0/1 fallback: solid background color with no blur (current behavior unchanged) | same | |
| ANIM-47-03 | Add `extendBody: true` to Scaffold so content renders behind nav bar | `app.dart` or each screen | Required for blur to show through |
| ANIM-47-04 | Add bottom safe-area padding to screen body so last item isn't hidden behind nav | all main screens | `MediaQuery.of(ctx).padding.bottom + navBarHeight` |
| ANIM-47-05 | Performance: use `clampingScrollPhysics` override only when blur is active (prevents over-scroll repaints) | bottom_nav.dart | |

**Acceptance criteria**: On Tier 2+ (API 28): nav bar is frosted glass, content scrolls behind. On Tier 0/1: standard solid nav bar, identical layout. No layout shift. No content clipping.

---

### Phase 48 — 3D Tilt Hero Banner *(flutter_animate + Transform, Tier 3)*
**Goal**: The featured content hero banner on the home screen responds to the phone's orientation (gyroscope) with a subtle 3D parallax tilt — poster layer moves more than text layer.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-48-01 | Add accelerometer/gyroscope listener using `sensors_plus` package (add to pubspec, Tier 3 only) | `home_screen.dart` | Very small package; cancel listener in dispose() |
| ANIM-48-02 | Map gyroscope x/y to Transform.rotateX/Y (max ±8°, lerp with 0.08 factor for smoothing) | same | Use `Matrix4.identity()..rotateX()..rotateY()` |
| ANIM-48-03 | Parallax: poster image transforms ×1.0, title text transforms ×0.4 (different depth layers) | same | |
| ANIM-48-04 | On API < 33 or no gyroscope: run a gentle auto-float animation instead (sine wave tilt via flutter_animate) | same | Fallback for Tier 2 that still has some motion |
| ANIM-48-05 | Dispose sensor listener in widget dispose() — never leak | same | Critical: sensor listeners are one of the top causes of battery drain and ANRs |

**Acceptance criteria**: On flagship (API 33+, gyroscope): banner tilts with phone movement. On mid-range: auto-float animation. On Tier 0: static banner. Sensor disposed correctly — no battery drain.

---

### Phase 49 — Ambient Particle Background *(particles_flutter, Tier 3 splash/login only)*
**Goal**: Floating spark/dust particles on splash screen and login screen. Cinematic feel.

| Task ID | Task | File(s) | Notes |
|---------|------|---------|-------|
| ANIM-49-01 | Add `particles_flutter` to pubspec | `pubspec.yaml` | Tier 3 only; very low particle count (max 25) |
| ANIM-49-02 | Wrap splash screen background with `ParticleField` (25 particles max, slow speed, opacity 0.3) | `splash_screen.dart` | Gate behind Tier 3 check |
| ANIM-49-03 | Same on login/auth screen background | `login_screen.dart` or equiv | |
| ANIM-49-04 | Particle config: radius 1.2, speed 0.3, opacity 20-70%, connect lines OFF (too expensive) | same | No line connections — they are O(n²) |
| ANIM-49-05 | Dispose particle controller in dispose() | same | Same as sensor — dispose everything |

**Acceptance criteria**: On Tier 3: visible floating particles, smooth. On Tier 0/1/2: static background, no particles. Particle count verified ≤ 25.

---

## 🧪 Testing Checklist (run before each phase commit)

Each phase must pass ALL of the following before a commit is made:

```
[ ] API 21 emulator (512 MB RAM): no jank, no crash, fallback path renders correctly
[ ] API 28 emulator (2 GB RAM): standard animations run smoothly
[ ] API 34 emulator (4 GB RAM): premium animations run at 60fps+
[ ] Accessibility: enable "Remove animations" in Android settings → zero animations play
[ ] Memory: no memory leak after 10× navigate-in/navigate-out
[ ] Dispose: all animation controllers, sensor listeners, and timers are disposed in dispose()
[ ] Const: all non-animated sibling widgets are const
[ ] RepaintBoundary: every animated widget that doesn't affect siblings has a RepaintBoundary wrapper
```

---

## 📊 Progress Tracker

| Phase | Name | Status | Commit |
|-------|------|--------|--------|
| 41 | Performance Infrastructure (AnimConfig + pubspec) | ⏳ TODO | — |
| 42 | Hero Poster Transition (built-in) | ⏳ TODO | — |
| 43 | Staggered Grid / List Entry | ⏳ TODO | — |
| 44 | Card → Detail Morph (OpenContainer) | ⏳ TODO | — |
| 45 | Neon/Glow Primary Action Buttons | ⏳ TODO | — |
| 46 | Typewriter & Animated Text | ⏳ TODO | — |
| 47 | Frosted Glass Bottom Nav | ⏳ TODO | — |
| 48 | 3D Tilt Hero Banner | ⏳ TODO | — |
| 49 | Ambient Particle Background | ⏳ TODO | — |

---

## 🏗️ AnimConfig API Reference (for agent implementing Phase 41)

```dart
// lib/core/utils/anim_config.dart

enum AnimTier { potato, basic, standard, premium }

class AnimConfig {
  final AnimTier tier;
  final int sdkInt;

  const AnimConfig({required this.tier, required this.sdkInt});

  // Quick tier int (0-3) for comparisons
  int get tierLevel => tier.index;

  // Respects Android "Remove Animations" accessibility setting
  bool shouldAnimate(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return false;
    return tier != AnimTier.potato || false; // potato = fade only
  }

  bool get canBlur        => tierLevel >= AnimTier.standard.index;   // API 28+
  bool get canShader      => tierLevel >= AnimTier.premium.index;    // API 33+
  bool get canStagger     => tierLevel >= AnimTier.basic.index;      // API 23+
  bool get canMorph       => tierLevel >= AnimTier.standard.index;   // API 28+
  bool get canParticle    => tierLevel >= AnimTier.premium.index;    // API 33+
  bool get canGyro        => tierLevel >= AnimTier.premium.index;    // API 33+

  Duration get fast       => tierLevel == 0 ? 150.ms : tierLevel == 1 ? 200.ms : 250.ms;
  Duration get normal     => tierLevel == 0 ? 200.ms : tierLevel == 1 ? 300.ms : 400.ms;
  Duration get slow       => tierLevel == 0 ? 250.ms : tierLevel == 1 ? 350.ms : 550.ms;

  static Future<AnimConfig> detect() async {
    final info = DeviceInfoPlugin();
    int sdk = 33; // safe default
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

// Riverpod provider — initialized once at startup in main.dart
final animConfigProvider = Provider<AnimConfig>((ref) => throw UnimplementedError());

// Usage in any widget:
// final anim = ref.watch(animConfigProvider);
// if (anim.canStagger) { ... }
```

---

## 🔑 Key Files Reference

| File | Role |
|------|------|
| `lib/core/utils/anim_config.dart` | Tier detection singleton (create in Phase 41) |
| `lib/core/utils/anim_durations.dart` | Tier-aware duration constants (create in Phase 41) |
| `lib/main.dart` | Initialize AnimConfig at startup, override animConfigProvider |
| `lib/screens/home_screen.dart` | Grid stagger (43), Hero (42), OpenContainer (44), Glow (45), Tilt (48) |
| `lib/screens/show_detail_screen.dart` | Hero (42), Glow (45), Typewriter (46) |
| `lib/screens/downloads_screen.dart` | Grid stagger (43), Burst (45) |
| `lib/screens/search_screen.dart` | Grid stagger (43), Hero (42), OpenContainer (44) |
| `lib/screens/splash_screen.dart` | Particles (49) |
| `lib/widgets/bottom_nav.dart` | Frosted glass (47) |
| `pubspec.yaml` | Add 3 packages in Phase 41 |
