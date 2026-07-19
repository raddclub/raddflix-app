# PLAYER UX — COMFORT & EMOTION PLAN (Phase BB)
**Created:** 2026-07-19  
**Status:** AWAITING CODING APPROVAL  
**Task IDs:** BB1–BB8  
**Principle:** Cinema first. User feels the content, not the controls. Fastest player, warmest experience.

---

## BEFORE YOU START — WHAT ALREADY EXISTS (do not re-build)

The following are **already implemented**. Never re-plan or duplicate these:

| Feature | Location | Status |
|---|---|---|
| Long-press 2× speed | `_ps_ui_mixin.dart:2031-2033` | ✅ DONE |
| Double-tap ±10s seek | `_ps_ui_mixin.dart:~2026` | ✅ DONE |
| A-B loop (native) | `PlaybackService.kt` + AGENT_HANDOFF.md | ✅ DONE |
| PiP (Android OS native) | `_ps_ui_mixin.dart:3480` (`_enterPiP`), `pip_overlay.dart` | ✅ DONE (multiple entry points) |
| HapticService | `lib/core/player/haptic_service.dart` | ✅ DONE |
| RaddBanner (top status strip) | `lib/design_system/components/radd_banner.dart` | ✅ DONE (9 variants, AnimatedSlide 220ms) |
| Animation tier system | `lib/core/utils/anim_config.dart` + `anim_durations.dart` | ✅ DONE (potato/basic/standard/premium) |
| All animation phases 41–49 | `agent-hub/ANIMATION_PLAN.md` | ✅ DONE |
| Theme system (6 color themes) | `lib/core/theme/radd_theme.dart` | ✅ DONE |
| Language track preference persistence | `_ps_playback_mixin.dart` (`_prefSubLang`/`_prefAudioLang`) | ✅ DONE (Task L3) |
| SubtitlePresetPicker widget | `lib/core/player/subtitle_style.dart` | ✅ BUILT — not wired (BB3 fixes this) |

---

## CONSTRAINTS — NEVER VIOLATE THESE

1. **`BackdropFilter` banned on API < 28** (standard tier+ only). Always gate on `AnimConfig.tier >= AnimTier.standard`.
2. **MediaTek HW Safety Rules**: no `video-filter` changes mid-play, specific surface attachment sequence in `player_screen.dart` comments.
3. **`db.setting(k)`** — not `db.get_setting(k)`. The second form does not exist.
4. **`sqflite_sqlcipher` version locked at `3.1.0+1`**. Never upgrade it.
5. **All new animations MUST go through `AnimConfig`** — check tier, scale duration from `anim_durations.dart`, fall back to opacity-only on `potato` tier.
6. **No frame extraction** — causes jank, battery drain, memory spikes. Zero tolerance.
7. **No ML/AI inference at runtime** — no silence detection, no skip detection, nothing heavy.
8. **`part of` files in player**: `_ps_*.dart` files are `part of '../player_screen.dart'`. Use `SKIP_PREFLIGHT=1` if preflight false-positives on them.
9. **Commit workflow**: `log_pending.sh` → edit → `auto_commit.sh`. Never raw git. CI must go green before marking done.

---

## WHAT WE ARE NOT DOING (and WHY — for future agents)

| Skipped Feature | Reason |
|---|---|
| Seek scrubbing preview thumbnails | Frame extraction at intervals = high CPU/memory/battery. Kills the "fastest player" goal. |
| In-app floating video card (old YouTube style) | Video surface lifecycle across navigation = fragile. PiP (already built) solves this better. |
| Chapter markers on seek bar | Needs MP4 chapter metadata parsing at every load = startup latency. |
| Subtitle tap-to-seek | Interaction zone conflicts with seek bar, complex hit-test logic. Niche. Future consideration. |
| Smart skip / silence detection | On-device ML inference. Out of scope entirely. |
| A-B loop visual indicator | Already built — AGENT_HANDOFF.md documents native implementation. Nothing to add. |
| Per-episode subtitle sync memory | Not high-impact enough now. Future. |
| Screenshot-to-share | Not core player feature. Future. |
| Seek preview thumbnails of any kind | See "No frame extraction" rule above. |

---

## THE TASKS

---

### BB1 — RESUME UX: Replace Blocking Dialog with Auto-Resume Strip

**Priority:** 🔴 High — triggered every time a user re-opens a video  

**Why the AlertDialog was there (original reason):**  
`_restoreWatchPos` used `showDialog<bool>` to force an explicit user choice before playback starts. Reasoning: the decision must be made before seeking. This was safe but unfriendly.

**Why we're changing it:**  
A modal dialog on video open creates friction and anxiety. The user is excited to watch; we stop them and ask a question. MX Player / Netflix / Disney+ all auto-resume silently and offer a one-tap "restart" escape. This respects the user's time and trust.

**What to build — `_ResumeStrip` widget:**
- Video starts playing immediately at saved position (no dialog)
- A `_ResumeStrip` widget renders inside the player's Stack, anchored above the seek bar (not above the seek bar controls row — just above it)
- Appearance: translucent dark pill/row, height 36px, content = `"▶ Resumed from 12:34"` (PhosphorIcons.play on left) + `"Restart ↺"` ghost text button on right
- Entry: slides up from below (180ms easeOutCubic) — tier-aware (potato = fade only)
- Auto-dismiss: starts a 4-second timer; when timer fires, fades out (200ms)
- Tap "Restart ↺": seeks to 0, dismiss strip immediately with haptic `selectionClick`
- Tap anywhere else on the strip: dismiss it (user acknowledged, keep resumed position)
- Swipe down on strip: same as tap anywhere (dismiss)
- Does NOT block video playback at any point

**Files to change:**
- `lib/screens/player/_ps_playback_mixin.dart` — remove `showDialog` from `_restoreWatchPos`; call `_showResumeStrip(positionMs)` instead
- `lib/screens/player/player_screen.dart` (or a new `_ps_resume_strip.dart` part file) — add `_ResumeStrip` StatefulWidget with timer + animation
- The strip widget is lightweight: `AnimatedOpacity` + `SlideTransition` + `Timer.cancel` on dispose

**DO NOT change:** the SharedPreferences save logic, the 30s/10s-from-end trigger window, or the `ResumeFab` on the home screen.

---

### BB2 — TTS FIX: LANG_NOT_INSTALLED Root Cause + Better Error UI

**Priority:** 🔴 Critical — feature is completely broken for non-English content  

**Root cause (verified by research):**  
`tts.setLanguage('hi-IN')` returns `LANG_MISSING_DATA (-1)` even when Google TTS is installed, because:
1. Installing Google TTS app ≠ installing the voice data pack. Each language (Hindi, Urdu, etc.) is a **separate download** inside Google TTS Settings → Install Voice Data.
2. `flutter_tts 4.x setLanguage()` checks `isLanguageAvailable()` on the **currently set engine only**. If Samsung TTS is the system default, Google TTS voices are invisible.
3. `getEngines()` returns empty on some Android 12+ devices (flutter_tts issue #568, confirmed open).
4. The preflight `synthesizeToFile` path may fail silently on Android 13+ if writing to an external path the app doesn't own.

**Fix 1 — Replace the availability check:**  
Instead of `tts.setLanguage(language)` for the check, use `tts.getVoices` → filter for entries where `locale` matches the target language and `isInstalled == true`. This is the correct API for checking installed voice data.

**Fix 2 — Set engine explicitly first:**  
Before any language check, call `await tts.setEngine('com.google.android.tts')`. If this returns false, fall back to `await tts.getDefaultEngine` → use whatever is returned. Only proceed with the availability check after an engine is confirmed.

**Fix 3 — Try locale variants:**  
Test in order: `'$lang-$country'` → `'${lang}_${country}'` → `'$lang'` until one returns a positive `isLanguageAvailable` result. Stop at first success.

**Fix 4 — Fix the preflight synthesis path:**  
Replace external storage path with `(await getApplicationDocumentsDirectory()).path + '/tts_preflight.wav'`. This is always writable without permissions.

**Fix 5 — Human-readable error + deep-link:**  
When voice data is missing, instead of raw `'LANG_NOT_INSTALLED'` string, show a warm bottom card:  
- Title: `"Voice pack not installed"`  
- Body: `"Hindi (hi-IN) voice for AI Dub needs to be downloaded. Takes ~30 MB."`  
- Button 1: `"Open TTS Settings"` → fires `ACTION_INSTALL_TTS_DATA` Android intent (already used elsewhere in the codebase per `_ps_panels_subtitle.dart` line findings)  
- Button 2: `"Maybe Later"` → dismisses

This replaces the existing "Install" button logic in `_ps_panels_subtitle.dart` (AI Dub tab).

**Files to change:**
- `lib/core/player/subtitle_dubber.dart` — `_checkLanguageSupport()` method: swap `setLanguage()` check for `getVoices()` check; add `setEngine()` call; add locale variant loop; fix preflight path
- `lib/screens/player/_ps_panels_subtitle.dart` — AI Dub tab error UI: replace raw error string display with a warm `RaddConfirm`-style bottom card (or use BB6's `RaddOverlay.confirm()` if BB6 lands first; otherwise a local `showModalBottomSheet`)

**DO NOT change:** the actual synthesis loop, PCM assembly, WAV header builder, or the 200MB OOM guard. These are correct.

---

### BB3 — SUBTITLE PANEL: Wire Orphaned SubtitlePresetPicker

**Priority:** 🟡 Medium — major usability improvement, zero performance cost  

**Why SubtitlePresetPicker wasn't wired (original reason):**  
No TODO comment found. It was likely built in one session and the panel wiring was deferred. The widget is complete and tested.

**What to build:**
1. In `_ps_panels_subtitle.dart` Style tab → add `SubtitlePresetPicker` at the **very top** of the style tab's scroll view
2. When user selects any preset **other than `custom`**: apply the preset's values to the panel's local state (`_loadPreset(preset)`) AND call `onStyleSynced` to push to MPV — then **collapse** all the manual sliders/pickers (hide them with `AnimatedSwitcher`)
3. When user selects `custom`: show all sliders/pickers (current behavior preserved, nothing removed)
4. The picker should highlight the currently active preset — if user manually tweaked sliders and drifted away from a preset, auto-select `custom`
5. **Add one new preset — `"Broadcast"`**: bold white text (weight 700), thick black outline (width 3.0), zero background opacity, 22sp — matches how traditional TV broadcast captions look. Add this to `kSubtitlePresets` in `subtitle_style.dart`.
6. Surface dyslexia fonts: add a small `"Accessibility fonts"` toggle row **below** the preset picker — a horizontal chip row with `System / OpenDyslexic / Atkinson`. Tapping one sets `SubtitleFont` and calls the existing font-apply path.

**Files to change:**
- `lib/core/player/subtitle_style.dart` — add `broadcast` to `SubtitlePreset` enum + `kSubtitlePresets` map
- `lib/screens/player/_ps_panels_subtitle.dart` — wire picker at top of Style tab, add collapse logic, add accessibility font chips

**DO NOT change:** the actual MPV property push logic (`sub-ass-override: force`), the existing preset data for the 8 presets, or the `dyslexia_subtitle_style.dart` font definitions.

---

### BB4 — PIP: Wire Minimize to Trigger OS PiP

**Priority:** 🟡 Medium — tiny change, big UX win  

**Why PiP wasn't the minimize action (original reason):**  
PiP was added as an explicit gesture from the player HUD (settings sheet, title bar shortcut) — a deliberate user choice. The minimize/back arrow was kept as "go back to app + show mini bar" for users who don't want PiP.

**What to build:**
- When the user presses the **back/minimize button** from the player (the `←` or `⌄` in the top bar) AND a playback session is active AND the user has not disabled PiP in settings:
  - Trigger `_enterPiP()` instead of popping the route
  - The video continues in the OS floating window
  - When the user taps the PiP window to expand: brings back to full player (already handled by `onPipExited` → route re-push)
- Add a setting toggle in Player Settings screen: `"Minimize enters PiP"` (default: ON). Read from `layout_prefs.dart`. If OFF, falls through to existing mini-bar behavior.
- Show a one-time onboarding toast on first PiP trigger: `"Video continues in a floating window"` (dismiss after 2s). Gate on a `seen_pip_tip` SharedPreferences bool.

**Files to change:**
- `lib/screens/player/_ps_ui_mixin.dart` — modify the minimize/back handler to check `_prefPipOnMinimize` and call `_enterPiP()` when appropriate
- `lib/core/player/layout_prefs.dart` — add `pipOnMinimize` bool pref (default true)
- `lib/screens/player/player_settings_screen.dart` — add the toggle row

**DO NOT change:** `_enterPiP()` itself, `pip_overlay.dart`, `onPipExited` handler, or any other PiP entry points. They all stay.

---

### BB5 — FAB THUMBNAIL FIX: Blank Poster in ResumeFab / MiniPlayerBar

**Priority:** 🔴 High — blank card looks broken, first thing users see  

**Why it's blank (suspected):**  
`ResumeFab` and `MiniPlayerBar` read poster URL from SharedPreferences key `resume_poster` (or similar). `PlayerScreen._saveResumeFab()` writes the poster URL. A key name mismatch or URL not being passed through the route arguments chain means the field saves as empty string.

**What to do:**
1. Audit: find every `SharedPreferences.setString` call that saves the resume poster URL in `PlayerScreen` / `_ps_playback_mixin.dart`
2. Find every `SharedPreferences.getString` call that reads it in `ResumeFab` and `MiniPlayerBar`
3. Verify the key names match exactly. If mismatched, align them.
4. Verify the poster URL is actually non-null at save time (add an assertion-style debug log)
5. In `ResumeFab` and `MiniPlayerBar`: add a `CachedNetworkImage` `errorWidget` fallback — a dark grey container with a `PhosphorIcons.filmSlate` centered icon (so even if URL is broken, the card looks intentional, not broken)
6. If the URL is a relative path (not absolute), ensure the base URL is prepended correctly

**Files to change:**
- `lib/screens/player/_ps_playback_mixin.dart` or `player_screen.dart` — confirm write side
- `lib/widgets/resume_fab.dart` — confirm read + add error widget
- `lib/widgets/mini_player_bar.dart` — confirm read + add error widget

---

### BB6 — RaddOverlay: Centralized Animated Popup System

**Priority:** 🟡 Medium — affects every popup, confirmation, toast in the entire app. Biggest "warmth" improvement.  

**Why raw Flutter dialogs are there now:**  
The design system has `RaddBanner` for top-of-screen status strips, but nothing for bottom confirmations or snackbars. All current dialogs use standard Flutter `AlertDialog` + `ScaffoldMessenger.showSnackBar` which look cold, clinical, and feel out of place with the warm Radd theme.

**What to build — `lib/core/ui/radd_overlay.dart`:**

A single file with three static methods backed by `OverlayEntry` (not ScaffoldMessenger — works everywhere including inside the player).

**`RaddOverlay.snack(context, message, {icon, action, actionLabel})`**
- A bottom-anchored pill: 48px tall, 16px horizontal padding, `RaddRadius.lg` corners
- Background: `RaddTheme.glass` color (semi-transparent dark with subtle border)
- Content: `PhosphorIcon` (optional) + message text + optional action button (ghost style)
- Animation: `SlideTransition` (0,1)→(0,0) over `animDurations.fast` (tier-aware), fade layered on top
- Auto-dismiss: 3 seconds; action button dismisses immediately
- Haptic: `HapticService.selectionClick` on appear
- Potato tier: skip slide, use `AnimatedOpacity` only (100ms)
- Stacks if called twice (second snack appears above first after first starts dismissing)
- Replaces: all `ScaffoldMessenger.of(context).showSnackBar(...)` calls app-wide

**`RaddOverlay.confirm(context, {title, body, confirmLabel, cancelLabel, onConfirm, onCancel, isDangerous})`**
- A bottom-anchored card: full width, `RaddRadius.xl` top corners, max-height 40% screen
- Slide up from bottom: `animDurations.normal` `easeOutCubic`
- Scrim: 40% opacity black overlay that fades in behind it
- Content: bold title, body text (optional), two large tappable buttons stacked vertically
  - Confirm button: filled (accent color). If `isDangerous: true` → red tint.
  - Cancel button: ghost/outline
  - Both are minimum 52px tall WCAG touch targets
- Haptic: `HapticFeedback.mediumImpact` on appear
- Tap scrim = dismiss (same as cancel)
- Potato tier: no slide, fade only (150ms)
- Replaces: all `showDialog(AlertDialog(...))` confirmation calls in the player and widgets

**`RaddOverlay.toast(context, message, {icon})`**
- A centered floating pill: auto-width, 40px tall, `RaddRadius.full` corners
- Scale-in from 0.7 + fade in over 150ms; 2s hold; scale-out + fade out 150ms
- Background: `RaddTheme.surface` at 90% opacity
- No action, no tap target — information only
- Haptic: none (too noisy for pure info)
- Potato tier: fade only, no scale
- Use for: "Copied to clipboard", "Saved", "Volume 80%", brief info

**Implementation notes:**
- All three use `OverlayEntry` inserted at the root overlay — no Scaffold dependency
- All three respect `AnimConfig.tier` for animation complexity
- All three read from `RaddTheme.of(context)` for colors — theme-change safe
- All three call `HapticService.instance.vibrate(...)` — respects user haptic preference

**Rollout:** Build the system first. Then migrate only these high-frequency call sites (not a full app sweep yet — that's a separate task):
1. Player's `_confirmStop` dialog (MiniPlayerBar) → `RaddOverlay.confirm`
2. Resume dialog (replaced by BB1 strip, but any remaining dialogs) → `RaddOverlay.confirm`  
3. All SnackBars in `_ps_playback_mixin.dart`, `mini_player_bar.dart`, `resume_fab.dart` → `RaddOverlay.snack`
4. TTS error display (BB2) → `RaddOverlay.confirm`

**Files to create/change:**
- **Create** `lib/core/ui/radd_overlay.dart` — the full overlay system
- `lib/widgets/mini_player_bar.dart` — swap `showDialog` → `RaddOverlay.confirm`
- `lib/screens/player/_ps_playback_mixin.dart` — swap SnackBars
- `lib/widgets/resume_fab.dart` — swap SnackBar

---

### BB7 — CONTROLS ANIMATION: Upgrade Opacity-Only to Slide+Fade

**Priority:** 🟢 Polish — makes the "cinema feeling" real  

**Why opacity-only now:**  
`AnimatedOpacity` was the safe baseline. Slide adds one extra animation controller per axis but is GPU-accelerated (transform layer, no layout).

**What to build:**
- Top bar (title, back button, overflow): `SlideTransition` on `Offset(0, -1.0)` → `Offset(0, 0)` when showing
- Bottom controls (seek bar, transport row, progress): `SlideTransition` on `Offset(0, 1.0)` → `Offset(0, 0)` when showing
- Both layers keep existing `AnimatedOpacity` — the slide+fade combination makes it feel physical
- Duration: `180ms easeOutCubic` for show; `140ms easeIn` for hide (asymmetric — quick to hide, smooth to show)
- Reuses existing `_controlsVisible` bool — no new state variables
- **Tier gate:** only `basic` tier and above get the slide. `potato` tier = existing opacity only.
- The sidebar panels do NOT get this treatment — they already have their own slide animations

**Files to change:**
- `lib/screens/player/_ps_ui_mixin.dart` — add two `AnimationController`s for top and bottom bar slide; wire to existing `_controlsVisible` state changes
- `lib/core/utils/anim_durations.dart` — add `controlsShow` (180ms) + `controlsHide` (140ms) if not already present

**DO NOT change:** sidebar animations, panel slide-in/out, or any gesture handlers.

---

### BB8 — SUBTITLE CROSSFADE: 150ms Fade Between Lines

**Priority:** 🟢 Polish — small change, very noticeable quality improvement  

**Why instant now:**  
Subtitle text replacement is a direct setState call. No animation layer.

**What to build:**
- Wrap the subtitle text widget in `AnimatedSwitcher` with `FadeTransition` and `duration: 150ms`
- Use `transitionBuilder` that only applies to the **outgoing** widget (old line fades out while new appears simultaneously)
- **Tier gate:** potato tier = no `AnimatedSwitcher`, instant swap (existing behavior)
- **Critical constraint:** this affects the **Flutter subtitle overlay only** (the `subtitle_overlay.dart` / `dual_subtitle_overlay.dart` widgets). MPV-rendered ASS/SSA subtitles are controlled by MPV directly — do NOT touch those code paths. The `sub-ass-override: force` property is unaffected.
- Verify: if ASS subtitle override is active, the Flutter overlay is hidden — the crossfade code path is never reached. Confirm this guard exists before adding animation.

**Files to change:**
- `lib/widgets/player/subtitle_overlay.dart` — wrap text in `AnimatedSwitcher`
- `lib/widgets/player/dual_subtitle_overlay.dart` — same treatment for both subtitle lines

---

### BB9 — PORTRAIT PLAYER (Placeholder — Separate Execution)

**Priority:** 🟢 Planned — already has full spec  

The portrait player layout (YouTube/Netflix style — video in top 38%, controls in lower 62%) already has a complete plan at `agent-hub/PORTRAIT_PLAYER_PLAN.md`. This is a larger task and should be executed as a **separate task approval** after BB1–BB8 are complete. Not part of this batch.

---

## EXECUTION ORDER

```
BB5 (FAB fix) → BB2 (TTS) → BB1 (Resume strip) → BB6 (RaddOverlay) → BB3 (Subtitle presets) → BB4 (PiP minimize) → BB7 (Controls animation) → BB8 (Subtitle crossfade)
```

**Rationale:**
- BB5 first: it's a pure bug, changes SharedPrefs keys only, zero risk
- BB2 next: feature is broken, users see errors
- BB1: annoying dialog, high-frequency trigger
- BB6: build the overlay system BEFORE further dialog migrations so BB3/BB4 can use it
- BB3/BB4: medium improvements using BB6 infrastructure
- BB7/BB8: pure polish, last so they don't complicate debugging earlier tasks

---

## SUCCESS CRITERIA

Each task is done when:
1. APK builds clean (CI green)
2. Manual test on a physical device confirms the change works
3. No new jank frames visible in `adb shell dumpsys gfxinfo` (player stays ≥ 58fps)
4. TASKS.md entry updated with commit SHA
5. This plan file updated: task row marked ✅ DONE with commit SHA

---

## TASK STATUS TRACKER

| Task | Title | Status | Commit |
|---|---|---|---|
| BB5 | FAB Thumbnail Fix | 🔲 Pending approval | — |
| BB2 | TTS Root Cause Fix | 🔲 Pending approval | — |
| BB1 | Resume Strip | 🔲 Pending approval | — |
| BB6 | RaddOverlay System | 🔲 Pending approval | — |
| BB3 | Subtitle Preset Picker | 🔲 Pending approval | — |
| BB4 | PiP Minimize Wiring | 🔲 Pending approval | — |
| BB7 | Controls Slide+Fade | 🔲 Pending approval | — |
| BB8 | Subtitle Crossfade | 🔲 Pending approval | — |
| BB9 | Portrait Player | 🔲 Separate task (own plan file) | — |
