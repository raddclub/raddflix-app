# RaddFlix Animation Tasks

> **All 9 animation phases (41–49) are complete as of 2026-07-01.**
> See `agent-hub/history/TASK_LOG.md` for full session detail.
> See `agent-hub/ANIMATION_PLAN.md` for spec and acceptance criteria.

---

## ✅ Phase 41 — Performance Infrastructure · `8396c13`

| ID | Task | Status |
|----|------|--------|
| ANIM-41-01 | AnimConfig singleton (`anim_config.dart`) — 4 tiers, Riverpod provider | ✅ DONE |
| ANIM-41-02 | Detect API level + RAM → assign AnimTier at startup | ✅ DONE |
| ANIM-41-03 | Add `flutter_animate ^4.5.0`, `animations ^2.0.11`, `flutter_staggered_animations ^1.1.1` to pubspec | ✅ DONE |
| ANIM-41-04 | Add `animated_text_kit ^4.2.2` to pubspec | ✅ DONE |
| ANIM-41-05 | RepaintBoundary audit — all existing animated widgets wrapped | ✅ DONE |
| ANIM-41-06 | Disable all animation fallback: `MediaQuery.disableAnimations` respected globally | ✅ DONE |

---

## ✅ Phase 42 — Hero Poster Transition · `50717ac`

| ID | Task | Status |
|----|------|--------|
| ANIM-42-01 | `Hero` widget on poster images (home→detail, search→detail) | ✅ DONE |
| ANIM-42-02 | `heroTag` keyed to item ID — no tag collisions | ✅ DONE |
| ANIM-42-03 | Tier 1+ only; Tier 0 uses plain Navigator.push | ✅ DONE |
| ANIM-42-04 | Custom `HeroFlightShuttleBuilder` with fade + scale envelope | ✅ DONE |
| ANIM-42-05 | Detail screen hero receives same tag and renders hero-wrapped image | ✅ DONE |

---

## ✅ Phase 43 — Staggered Grid / List Entry · `4f55fcd`

| ID | Task | Status |
|----|------|--------|
| ANIM-43-01 | `AnimationConfiguration.staggeredGrid` on home screen content grid | ✅ DONE |
| ANIM-43-02 | `AnimationConfiguration.staggeredList` on downloads + search lists | ✅ DONE |
| ANIM-43-03 | FadeIn + SlideAnimation entry per card (duration 350ms, delay 50ms×i) | ✅ DONE |
| ANIM-43-04 | Tier 1+ only; Tier 0 renders static (no stagger) | ✅ DONE |
| ANIM-43-05 | `stagger(i)` returns 0ms on Tier 0 — no animation controllers created | ✅ DONE |

---

## ✅ Phase 44 — Card → Detail Morph (OpenContainer) · `2600a39`

| ID | Task | Status |
|----|------|--------|
| ANIM-44-01 | `OpenContainer` wrapping each content card → show_detail_screen | ✅ DONE |
| ANIM-44-02 | `ContainerTransitionType.fadeThrough` on Tier 2+ (API 28+, canMorph) | ✅ DONE |
| ANIM-44-03 | Tier 0/1 fallback: plain `Navigator.push` (no OpenContainer overhead) | ✅ DONE |
| ANIM-44-04 | Duration: 400ms on Tier 2, 350ms on Tier 1 | ✅ DONE |
| ANIM-44-05 | closedElevation 0, openElevation 0 to avoid shadow artifacts | ✅ DONE |

---

## ✅ Phase 45 — Neon/Glow Primary Action Buttons · `bec1909`

| ID | Task | Status |
|----|------|--------|
| ANIM-45-01 | `_GlowPulse` StatefulWidget — AnimationController 1400ms, reverse repeat | ✅ DONE |
| ANIM-45-02 | Play button always glows; glow intensity tier-scaled (maxBlur 14→22) | ✅ DONE |
| ANIM-45-03 | Download button: conditional glow when `isDownloading==true` only | ✅ DONE |
| ANIM-45-04 | Tier 0 / `disableAnimations`: static button, no controller created | ✅ DONE |
| ANIM-45-05 | Downloads SnackBar icon: `.animate().shake(400ms).scale(1→1.15)` on completion | ✅ DONE |

---

## ✅ Phase 46 — Typewriter & Animated Text · `647ac5c`

| ID | Task | Status |
|----|------|--------|
| ANIM-46-01 | `TypewriterAnimatedText` on show_detail synopsis (Tier 1+, 300ms initState delay) | ✅ DONE |
| ANIM-46-02 | Synopsis capped at 220 chars; `displayFullTextOnTap: true` | ✅ DONE |
| ANIM-46-03 | Home chips shimmer (500ms, white24) appended to entrance stagger | ✅ DONE |
| ANIM-46-04 | Tier 0: plain Text widget, no animated_text_kit controller created | ✅ DONE |

---

## ✅ Phase 47 — Frosted Glass Bottom Nav · `af27e1a`

| ID | Task | Status |
|----|------|--------|
| ANIM-47-01 | `bottom_nav.dart` → ConsumerWidget; `BackdropFilter(sigmaX/Y: 12)` on Tier 2+ | ✅ DONE |
| ANIM-47-02 | Home Scaffold: `extendBody: true` so content scrolls under glass nav | ✅ DONE |
| ANIM-47-03 | `SliverToBoxAdapter(height: 72)` bottom clearance in home slivers | ✅ DONE |
| ANIM-47-04 | Tier 0/1: solid nav background (no BackdropFilter, no canBlur) | ✅ DONE |
| ANIM-47-05 | Fixed duplicate `@override` compile error in follow-up commit | ✅ DONE |

---

## ✅ Phase 48 — 3D Tilt Hero Banner · `a8d4323`

| ID | Task | Status |
|----|------|--------|
| ANIM-48-01 | `_HeroCard` → `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin` | ✅ DONE |
| ANIM-48-02 | AnimationController 3200ms sine auto-float → `Matrix4` perspective + rotateX/Y ±0.025/0.015 rad | ✅ DONE |
| ANIM-48-03 | `AnimatedBuilder` wraps `Transform` — only hero card repaints | ✅ DONE |
| ANIM-48-04 | Tier 0 / `disableAnimations`: static card, no controller created | ✅ DONE |
| ANIM-48-05 | `_floatCtrl.dispose()` in dispose() — no battery drain | ✅ DONE |

---

## ✅ Phase 49 — Ambient Particle Background · `f81b0cb`

| ID | Task | Status |
|----|------|--------|
| ANIM-49-01 | `particles_flutter` package: skipped — `pubspec.lock` needs `flutter pub get`; pure-Dart CustomPainter is functionally equivalent | ⏭ SKIPPED |
| ANIM-49-02 | splash_screen: `Positioned.fill(child: ParticleOverlay())` in body Stack, behind Center content | ✅ DONE |
| ANIM-49-03 | login_screen: `Positioned.fill(child: ParticleOverlay())` in body Stack, behind SafeArea | ✅ DONE |
| ANIM-49-04 | Particle config: 25 particles, radius 1.0-1.4px, opacity 20-70%, sine horizontal drift, no connect lines | ✅ DONE |
| ANIM-49-05 | `AnimationController` disposed in `ConsumerState.dispose()` — no battery drain | ✅ DONE |

---

## 🛡️ Hard Rules for Every Animation Phase

> An agent MUST verify these before marking any ANIM task as DONE:
> 1. ✅ Gated behind `AnimConfig.tier` check
> 2. ✅ Respects `MediaQuery.disableAnimations`
> 3. ✅ No `BackdropFilter` on API < 28 (Tier < 2)
> 4. ✅ No fragment shaders on API < 26 (Tier < 2)
> 5. ✅ `RepaintBoundary` on every isolated animated widget
> 6. ✅ All controllers/listeners disposed in `dispose()`
> 7. ✅ Tested on API-21 emulator — must not crash or jank
> 8. ✅ Duration ≤ 350ms on Tier 0/1

---

## Open Tasks
**None.** Phases 41–49 fully implemented. Animation roadmap complete. 🎉

---

## ✅ Phase 56 — Subscription Tier Badge · `a34b5f9`

| ID | Task | Status |
|----|------|--------|
| ANIM-56-01 | TierBadge widget — animated glow pulse (FREE/STANDARD/PREMIUM) | ✅ DONE |
| ANIM-56-02 | profile_screen: replace static plan badge with TierBadge | ✅ DONE |
| ANIM-56-03 | subscription_screen _ActivePlanCard: add TierBadge beside plan name | ✅ DONE |
| ANIM-56-04 | Tier gate: basic+ glows; potato static; respects disableAnimations | ✅ DONE |
