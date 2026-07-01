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

---

## ✅ Audit Fixes — Guest/Free/Premium logic · `336dbb5`

| ID | Fix | Status |
|----|-----|--------|
| AUD-01 | _EpisodeTile: add isLocked field + PREMIUM lock badge for paid episodes | ✅ DONE |
| AUD-02 | _requireSub: show different SnackBar message for guests vs free users | ✅ DONE |
| AUD-03 | Episode builder: pass isLocked = !isFree && !_isSubscribed to each tile | ✅ DONE |

---

## ✅ 5 Feature Batch · settings=1859ec1 search=a6d938b player=2562512 home=d2f8146

| ID | Feature | File |
|----|---------|------|
| F01 | Settings screen (WiFi-only, auto-play, sync, WhatsApp support) | settings_screen.dart |
| F02 | Search history UI (recent chips + clear all) | search_screen.dart |
| F03 | Subtitle local file picker (SRT/VTT/ASS/SSA) | player_screen.dart |
| F04 | In-app update check (/api/config min_version_code) | home_screen.dart |
| F05 | Continue Watching hero shortcut (resume item first + Resume button) | home_screen.dart |


---

## ⏳ Phase 57 — Player Audit: Dual Subtitles, Track Bugs, EAC3, MKV · Planned 2026-07-01

> **Research + audit session findings. Fix in next session.**
> Source: User request — kisskh.la dual-subtitle analysis + full player track/codec audit.

### 🎯 What is the kisskh.la dual-subtitle system?

kisskh.la shows **two subtitle tracks simultaneously**:
- **Bottom** — regular dialogue subtitles (primary)
- **Top** — OST lyrics, song titles, character names, location cards, on-screen sign translations (secondary)

Their web player loads two separate subtitle files and overlays them using WebVTT position cues (or
CSS positioning). When you download the video and play locally in MX Player, the OST/signs track
is a **separate file** that was never downloaded — only the dialogue .srt was saved. That's why it
disappears in MX Player.

**MPV natively supports this via `secondary-sid` property.** Our player can show the exact same
effect: primary dialogue at bottom, secondary OST/signs track at top, simultaneously.

---

### Findings — Bugs & Missing Features

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| P57-01 | 🔴 HIGH | **Fake subtitle track bug** — `_subtitleTracks.isNotEmpty` is always `true` because media_kit always includes `SubtitleTrack.no()` in the list. Subtitle button shows active even for videos with zero embedded subs. | ⏳ OPEN |
| P57-02 | 🔴 HIGH | **No embedded MKV subtitle track selector** — `_SubtitlePanel` has NO way to switch between multiple embedded subtitle tracks (e.g. English, Arabic, Urdu tracks in an MKV). `_AudioTrackPanel` has this; `_SubtitlePanel` is missing the equivalent. | ⏳ OPEN |
| P57-03 | 🟠 MED | **Fake audio track bug** — `_audioTracks.length > 1` check: for single-audio-track MKV, media_kit includes `AudioTrack.auto()` + 1 real track = length 2. Audio button shows when there's nothing to switch to. Fix: count only real tracks, filter out the auto() sentinel. | ⏳ OPEN |
| P57-04 | 🟠 MED | **SW decoder toggle broken during playback** — The "Use SW audio decoder" switch in AudioPanel has a guard that only applies when `_player.state.duration == Duration.zero` (video not started yet). During playback it silently does nothing. UI should be grayed out + show "Restart video to apply" tooltip. | ⏳ OPEN |
| P57-05 | 🟠 MED | **EAC3/DTS no auto-fallback** — EAC3 IS supported by media_kit_libs_android_video (full ffmpeg). But Android MediaCodec (hwdec=auto-safe) fails silently on EAC3/DTS on many MediaTek devices. User must manually toggle SW decoder without knowing when. Fix: after playback starts, read `audio-codec` via `_np.getProperty('audio-codec')` → if EAC3/DTS/AC3, auto-switch to SW decoder + show SnackBar: "EAC3 audio detected — switched to software decoder". | ⏳ OPEN |
| P57-06 | 🟡 LOW | **No codec label in AudioPanel** — Track list shows language/title but not codec (EAC3, AAC, AC3, Opus…). Users don't know what they're selecting. Add small grey codec badge from `audio-codec` property. | ⏳ OPEN |
| P57-07 | ✨ FEAT | **Dual subtitle / Secondary-SID system (kisskh.la feature)** — Add `secondary-sid` support so user can pick a second subtitle track displayed at the TOP of video (OST/signs) while primary dialogue shows at bottom. MPV supports this natively. Add "Secondary Subtitle" row in SubtitlePanel after the primary track list. | ⏳ OPEN |

---

### Implementation Plan — Phase 57

#### TASK-57-01 — Fix subtitle track visibility (P57-01)

**File:** `player_screen.dart`

**Problem:** `SubtitleTrack.no()` is always in `_subtitleTracks`, so the subtitle button is always active.

**Fix:** Replace the raw list with a filtered getter:
```dart
// Add getter near top of _PlayerScreenState:
List<SubtitleTrack> get _realSubtitleTracks =>
    _subtitleTracks.where((t) => t.id != null).toList();
```
Then replace all 4 usages of `_subtitleTracks.isNotEmpty` with `_realSubtitleTracks.isNotEmpty`.

The `active:` / `available:` in sidebar and icon toggle both use this check.

---

#### TASK-57-02 — Add embedded subtitle track selector to SubtitlePanel (P57-02)

**File:** `player_screen.dart`

**Problem:** SubtitlePanel has no track switcher for embedded MKV subs.

**Fix:**
1. Add `tracks`, `selectedSubtitle`, `onSubtitleTrackSelected` params to `_SubtitlePanel` (mirror AudioPanel)
2. In `_SubtitlePanelState` build(), add a new header section at top of "Open" tab (tab index 0):
   - "Embedded Tracks" heading (only shown when `widget.tracks.isNotEmpty`)
   - RadioListTile for each real SubtitleTrack (language ?? title ?? "Track N")
   - "None" option at end
3. In `_openSubtitlePanel()`, pass `tracks: _realSubtitleTracks`, `selectedSubtitle: _selectedSubtitle`, `onSubtitleTrackSelected: (t) { setState(() => _selectedSubtitle = t); if (t != null) _player.setSubtitleTrack(t); else _np.setProperty('sid', 'no'); }`

---

#### TASK-57-03 — Fix fake audio track (P57-03)

**File:** `player_screen.dart`

**Fix:** Add getter:
```dart
List<AudioTrack> get _realAudioTracks =>
    _audioTracks.where((t) => t.id != null).toList();
```
Replace `_audioTracks.length > 1` (3 usages) with `_realAudioTracks.length > 1`.
Pass `tracks: _realAudioTracks` to AudioPanel instead of `_audioTracks`.

---

#### TASK-57-04 — Disable SW decoder toggle during playback (P57-04)

**File:** `player_screen.dart` → `_AudioTrackPanelState`

**Fix:** Pass a `bool isPlaying` param to `_AudioTrackPanel`. In the SW decoder `SwitchListTile`:
```dart
SwitchListTile(
  title: const Text('Use SW audio decoder', ...),
  subtitle: widget.isPlaying
      ? const Text('Stop video to apply', style: TextStyle(color: Colors.orange, fontSize: 11))
      : null,
  value: _useSW,
  onChanged: widget.isPlaying ? null : (v) { ... }, // null = disabled
  ...
)
```

---

#### TASK-57-05 — EAC3/DTS auto SW fallback (P57-05)

**File:** `player_screen.dart`

**Fix:** In `_player.stream.tracks.listen` callback (after tracks populate), schedule a 1-second delayed check:
```dart
Future.delayed(const Duration(seconds: 1), () async {
  if (!mounted) return;
  try {
    final codec = await _np.getProperty('audio-codec-name');
    if (['eac3','ac3','dts','dts-hd','truehd','mlp'].contains(codec?.toLowerCase())) {
      if (!_useSWDecoder) {
        _np.setProperty('hwdec', 'no'); // force SW
        setState(() => _useSWDecoder = true);
        _showInfoSnackbar('EAC3/DTS detected — using SW audio decoder');
      }
    }
  } catch (_) {}
});
```
Note: Use `audio-codec-name` (short name) not `audio-codec` (full name with profile).

---

#### TASK-57-06 — Codec badge in AudioPanel track list (P57-06)

**File:** `player_screen.dart` → `_AudioTrackPanelState`

**Fix:** The track label already shows language + title. Append codec as a small grey tag:
Pass `List<String?> codecs` (length = tracks.length) into AudioPanel. In player, populate after track load via repeated `getProperty('audio-codec-name')` calls per track id.
OR simpler: just read the CURRENT codec once and show it as a badge only on the selected/active track. Less complex, still useful.

---

#### TASK-57-07 — Dual subtitle / Secondary-SID (kisskh.la feature) (P57-07)

**File:** `player_screen.dart`

**New state vars:**
```dart
SubtitleTrack? _selectedSecondSub;
bool _secondSubEnabled = false;
```

**SubtitlePanel changes:** After the primary subtitle track list, add:
- Divider + "Secondary Subtitle (OST / Signs)" heading
- "OFF" option + real subtitle track list (same `_realSubtitleTracks` list)
- When user picks one: `_np.setProperty('secondary-sid', track.id.toString())`
- When user picks OFF: `_np.setProperty('secondary-sid', 'no')`

**MPV behaviour:** Secondary track auto-renders at top of video. No extra Flutter widget needed —
MPV renders it natively above the primary subtitle.

**Note:** Secondary subtitle respects `sub-margin-y` for the primary track but secondary sub has its
own margin via `secondary-sub-pos` (MPV property). Default is top-of-screen, which is correct.

---

### 🧪 Testing Checklist (for implementing agent)

- [ ] Video with NO subtitles → subtitle button grayed out (P57-01)
- [ ] Video with NO multi-audio → audio button grayed out (P57-03)
- [ ] MKV with 3 subtitle tracks → all 3 appear in SubtitlePanel, switching works (P57-02)
- [ ] MKV with EAC3 audio → SW decoder auto-enables + snackbar shows (P57-05)
- [ ] AAC audio → SW decoder does NOT auto-enable (P57-05)
- [ ] SW decoder toggle grayed out during playback (P57-04)
- [ ] Secondary subtitle (OST) shows at top while primary shows at bottom (P57-07)
- [ ] Setting secondary-sid to 'no' removes top subtitle (P57-07)
- [ ] APK builds clean, no compile errors
