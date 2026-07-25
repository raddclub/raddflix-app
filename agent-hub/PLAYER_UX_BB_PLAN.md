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
**Completed:** ✅ DONE 2026-07-25 — `_restoreWatchPos` auto-seeks; `_ResumeStrip` widget (slide+fade, 4s auto-dismiss, Restart button) in `_ps_playback_mixin.dart:1408`  

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
**Completed:** ✅ DONE 2026-07-25 — `subtitle_dubber.dart` has all 4 backend fixes (setEngine, getVoices check, locale variants loop, ApplicationDocuments preflight path); `_ps_audiolab_mixin.dart` `_showTtsInstallPrompt` upgraded to warm modal bottom sheet with "Open TTS Settings" + "Maybe Later"; `_launchTtsSettings()` tries `INSTALL_TTS_DATA` → `TTS_SETTINGS` → `SETTINGS` intent chain  

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
**Completed:** ✅ DONE 2026-07-25 — keys aligned (`resume_poster_url` via `ResumeFab.kPosterUrl` const used in both write and read); `CachedNetworkImage` with `errorWidget` in both static and live bars; `_posterFallback()` shows `AppColors.card` + `AppIcons.movieFill` so blank looks intentional  

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

### BB10 — WORD LOOKUP UPGRADE: Subtitle Word Dictionary

**Priority:** 🟡 Medium — feature already exists but is broken for most words; this makes it genuinely useful  

---

**What's already built (DO NOT rebuild from scratch):**

| Component | File | State |
|---|---|---|
| Offline dict (241 words) | `lib/core/player/word_dict.dart` | ✅ Works |
| `SavedWord` model (word, urdu, roman, pos, savedAt) | `word_dict.dart` | ✅ Complete |
| Definition popup (bottom sheet) | `lib/widgets/player/word_definition_sheet.dart` | ✅ Works but needs upgrades |
| Single-tap word trigger | `lib/widgets/player/subtitle_overlay.dart:154` | ✅ Keep as-is |
| Dotted underline on known words | `subtitle_overlay.dart:164` | ✅ Keep |
| Save/unsave word to SharedPrefs | `word_dict.dart` | ✅ Works |
| dictEnabled toggle | `quick_settings_panel.dart:1337` | ✅ Keep |
| `dictEnabled` pref | `player_prefs.dart:194` | ✅ Keep |

**GESTURE DECISION: Keep single-tap** — it's already wired, works perfectly, and is faster than double-tap. Do NOT change the trigger.

---

**What to build on top of this:**

#### 1. Online Dictionary Fallback (biggest improvement)
When `WordDict.instance.lookup(word)` returns null (word not in 241-word offline dict):
- Call **`dictionaryapi.dev`** API: `GET https://api.dictionaryapi.dev/api/v2/entries/en/{word}`
- This API is free, requires no API key, and returns: definitions, phonetics, part of speech, example sentences, and an audio pronunciation URL (`.mp3`)
- Use `dio` (already in pubspec at `^5.4.0`) for the request
- Cache results in a session-scoped `Map<String, WordEntry?>` in `WordDict` — so the same word is instant the second time it's tapped in the same session
- If API call fails (offline / timeout after 3s) → fall back gracefully, show "No definition found" state (same as current)
- For the Urdu meaning of online-looked-up words: call **MyMemory API** `GET https://api.mymemory.translated.net/get?q={word}&langpair=en|{targetLangCode}` — free, no API key, returns translated text
- Store the `dictTargetLanguage` code (default `'ur'`) in `PlayerPrefs` — so the translation is always into whatever the user has set

#### 2. User-Selectable Target Language
Add `dictTargetLanguage` pref to `PlayerPrefs` (type `String`, default `'ur'` for Urdu). The value is the ISO 639-1 language code passed to the MyMemory API `langpair`.

In the subtitle panel Style tab (or a new settings row in the existing dict toggle area in `quick_settings_panel.dart`), add a language picker **only visible when `dictEnabled` is true**:
- Label: "Translate meanings to:"
- A dropdown / chip selector: `Urdu (ur)` · `Arabic (ar)` · `Hindi (hi)` · `Turkish (tr)` · `Spanish (es)` · `French (fr)` · `Persian (fa)` · `Bengali (bn)`
- When changed, update `dictTargetLanguage` pref — affects all future lookups immediately
- Update the quick settings subtitle text from "Tap subtitle words for Urdu translation" → "Tap subtitle words for word meanings" (language-agnostic label)

#### 3. Video Pause on Word Tap
In `subtitle_overlay.dart`, `_onWordTap` currently does NOT pause the video. Add a `VoidCallback? onPausedForLookup` parameter to the `SubtitleOverlay` widget. When a word is tapped and the sheet opens, call `onPausedForLookup?.call()`. When the sheet is dismissed (returned from `await showWordDefinition(...)`), call a matching `VoidCallback? onResumedAfterLookup` after an 800ms delay — so the user can re-read the subtitle before it changes.

Thread these callbacks from `_ps_ui_mixin.dart` where `SubtitleOverlay` is constructed: `onPausedForLookup: () => _np.pause()` and `onResumedAfterLookup: () => _np.play()`.

#### 4. Context Sentence from Current Subtitle
The current popup shows an example sentence from the dictionary entry. Add the **actual subtitle line** the user was reading as a "context" field.

In `_onWordTap`, pass `widget.currentLine` (the currently displayed subtitle text) as a new `contextSentence` parameter to `showWordDefinition`. In `word_definition_sheet.dart`, show it at the top of the popup **above** the definition:
```
📖  "She looked beautiful in the moonlight."
         ─────────────
```
The tapped word is visually highlighted (accent color underline or bold) within the context sentence. This is more useful than a generic dictionary example because it's the actual usage the user encountered.

#### 5. Pronunciation Audio Playback
`dictionaryapi.dev` returns an audio URL (typically a `.mp3` file) in the `phonetics` array. In `word_definition_sheet.dart`:
- Add a `🔊 Hear it` button below the phonetic line
- On tap: use `url_launcher`'s `launchUrl` with `LaunchMode.externalNonBrowserApplication` to play the audio — OR (better) use `flutter_tts` (already in pubspec) to speak the word via `tts.speak(word)` as a fallback when no audio URL is available
- If the API returned an audio URL, prefer it (real human voice). If not, fall back to TTS.
- Show a brief loading indicator (circular, 20px) while the audio loads on first tap; subsequent taps are instant

#### 6. Popup Animation — Scale from Word Position
Currently the sheet slides up from the bottom (standard `showModalBottomSheet`). Upgrade to a **scale-up animation from the tapped word's position**:
- Use `showGeneralDialog` with a custom `pageBuilder` instead of `showModalBottomSheet`
- Compute the tapped word's position on screen (pass `RenderBox` offset from the word's `GestureDetector`'s `BuildContext`)
- Animate: scale from 0.6 → 1.0 with `easeOutBack` curve, 220ms; origin point = word's screen position
- The card itself is floating (not a full-height bottom sheet) — max height 55% of screen, centered horizontally, positioned vertically so it doesn't cover the word (above it if word is in the lower half, below if upper half)
- Tier gate: standard+ gets scale-from-origin; basic tier gets standard slide-up; potato tier gets instant appear

#### 7. Popup UI — Upgrade to RaddTheme Tokens
The current `word_definition_sheet.dart` uses `AppColors.surface` and hardcoded `#D4784A`. Replace with:
- Background: `RaddTheme.of(context).surface` (theme-change safe)
- Accent: `PlayerPrefs.accentColor` (already available in the sheet via the prefs parameter)
- Border radius: `RaddRadius.xlRadius` for the card
- Typography: keep existing Lexend font for the word, Naskh/Noto for Urdu, use `RaddSpace` for spacing
- Dividers: `RaddTheme.of(context).divider` color
- POS chip: `RaddRadius.smRadius`, accent color fill at 15% opacity + accent border

#### 8. Saved vs Known Word Underline Distinction
Currently, ALL words in the offline dict (241 words) get a dotted underline. There's no visual distinction between "I've saved this word" and "this word is in the dictionary."

New behavior in `_buildTappableText`:
- Word is in offline dict OR returned from online cache AND **saved by user**: thick solid underline in accent color (saved = important)
- Word is in offline dict OR returned from online cache AND **not saved**: thin dotted underline (just known/available)  
- Word not in any dict yet: no underline (default, clean subtitle appearance)

This makes the saved underline feel like an achievement — you can see your vocabulary growing.

#### 9. "My Words" Tab — Vocab List in Subtitle Panel
Add a **7th tab** to `_SubtitlePanel` in `_ps_panels_subtitle.dart` (after the existing 6 tabs: Tracks / Style / Position / Sync / Online / AI Dub):
- Tab icon: `PhosphorIcons.bookOpen` 
- Tab label: "My Words"
- Content: A scrollable list of `SavedWord` entries from `WordDict.instance.savedWords` sorted by `savedAt` descending (most recent first)
- Each row: word (left, bold) + POS chip + Urdu text (right, RTL) + `savedAt` date (small, muted)
- Tap row → re-opens `word_definition_sheet` for that word
- Long-press row → shows `RaddOverlay.confirm()` "Remove from saved words?" → on confirm, calls `WordDict.instance.unsaveWord(word)` + refreshes list
- Empty state: `PhosphorIcons.bookOpenText` + "Tap any subtitle word while watching to build your vocabulary"
- **Search bar** at top of the tab (filtered in real-time as user types, matches word or Urdu text)
- **Word count pill** next to the tab label: "My Words ・ 34" (pulls from `savedWords.length`)

#### 10. Extend Dict Support to Dual Subtitle Overlay
`dual_subtitle_overlay.dart` currently has NO word-level interactivity. Add the same `_buildTappableText` logic from `subtitle_overlay.dart` to `dual_subtitle_overlay.dart`'s `_SubLine` widget. Both primary and secondary subtitle lines should support word lookup when `dictEnabled` is true.

---

**API references:**
- Dictionary: `https://api.dictionaryapi.dev/api/v2/entries/en/{word}` — GET, no auth, returns JSON
- Translation: `https://api.mymemory.translated.net/get?q={word}&langpair=en|{targetLang}` — GET, no auth, 5000 chars/day free
- Both use `dio` (already in pubspec `^5.4.0`). No new packages needed.

**Files to change:**
- `lib/core/player/word_dict.dart` — add online lookup method, session cache, `dictTargetLanguage` param
- `lib/widgets/player/word_definition_sheet.dart` — add context sentence, audio, RaddTheme tokens, scale animation, online entry display
- `lib/widgets/player/subtitle_overlay.dart` — add pause/resume callbacks, upgrade saved vs known underline
- `lib/widgets/player/dual_subtitle_overlay.dart` — add dict support to `_SubLine`
- `lib/screens/player/_ps_panels_subtitle.dart` — add "My Words" 7th tab
- `lib/core/player/player_prefs.dart` — add `dictTargetLanguage` pref (String, default `'ur'`)
- `lib/widgets/player/quick_settings_panel.dart` — add language picker row; update subtitle text to be language-agnostic

**DO NOT change:** the offline 241-word dictionary data (keep as instant fallback), the `SavedWord` model structure (already correct), the `dictEnabled` pref key, or any subtitle rendering logic outside word-level interaction.

---

### BB9 — PORTRAIT PLAYER (Placeholder — Separate Execution)

**Priority:** 🟢 Planned — already has full spec  

The portrait player layout (YouTube/Netflix style — video in top 38%, controls in lower 62%) already has a complete plan at `agent-hub/PORTRAIT_PLAYER_PLAN.md`. This is a larger task and should be executed as a **separate task approval** after BB1–BB8 are complete. Not part of this batch.

---

---

### BB-AUDIT — AMBIENT QUALITY CHECK (Runs with every BB task)

**Not a separate task — a standing rule baked into every BB commit.**

While implementing any BB task, the agent MUST audit the 3–5 surrounding feature areas most affected by that change. Specifically:

1. **Token compliance** — do the widgets you touched use `RaddTheme.of(context)` / `RaddRadius.*` / `RaddSpace.*` tokens, or are they still on legacy `AppColors.*` / `AppRadius.*`? Migrate any legacy usage in the touched files (small, no-risk change).
2. **Does it actually work?** — do not assume surrounding features are correct. Briefly test the user-facing flow mentally: is there a dead end? A null check missing? A state that never resets? Fix small issues inline.
3. **Animation tier compliance** — any animation in touched code should check `AnimConfig.tier` before running effects beyond opacity. Add the check if missing.
4. **Haptic hygiene** — any tap that should have haptic feedback (confirmation, destructive action, selection) should route through `HapticService.instance`. Add where absent in touched files.
5. **Larger issues found** → add a new `BB-AUDIT-[N]` entry to `TASKS.md` for tracking. Do not silently ignore.

This audit does NOT mean rewriting untouched code. It means "I was here, I checked, I left it better."

---

## EXECUTION ORDER

```
BB5 → BB2 → BB1 → BB6 → BB3 → BB4 → BB10 → BB7 → BB8
```

| Step | Task | Why here |
|---|---|---|
| 1 | BB5 — FAB Thumbnail Fix | Pure SharedPrefs key bug, zero risk, sets clean foundation |
| 2 | BB2 — TTS Fix | Feature completely broken, users see errors every time they try AI Dub |
| 3 | BB1 — Resume Strip | Most frequently triggered annoyance; blocking dialog removed |
| 4 | BB6 — RaddOverlay System | Build the overlay system FIRST — BB3, BB4, BB10 all use it for confirmations and toasts |
| 5 | BB3 — Subtitle Preset Picker | Wire already-built widget; clean, small |
| 6 | BB4 — PiP Minimize | Small wiring change; uses BB6 for the first-use toast |
| 7 | BB10 — Word Lookup Upgrade | Depends on BB6 (for RaddOverlay.confirm in vocab delete); medium task, standalone |
| 8 | BB7 — Controls Slide+Fade | Pure animation polish; last so it doesn't complicate debugging above |
| 9 | BB8 — Subtitle Crossfade | Smallest polish task; absolutely last |

**BB-AUDIT runs with every task** — no separate step needed.  
**BB9 (Portrait Player)** — separate approval + separate task, not part of this batch.

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
| AB1 | Neo-Phonograph Audio Player | 🔲 Pending approval | — |

---

## AB1 — Neo-Phonograph Audio Player Overhaul

**File:** `raddflix_flutter/lib/widgets/player/audio_mode_backdrop.dart` (993 lines, self-contained)
**Priority:** 🟡 Polish / Identity
**Phase:** AB (Audio Backdrop)
**Aesthetic concept:** *Neo-Phonograph* — the warmth, romance, and physicality of a 1950s record player fused with modern glassmorphism, physics animation, and dark-cinema precision. Every element should feel like it was machined from warm brass and polished glass, not drawn in a design tool.

---

### Creative Direction: What "Modern + Classic" Means Here

**Classic signals to keep:**
- Warm amber/gold accent tones when no cover art (replaces the current hue-hash blue/purple defaults)
- Tonearm — the single most iconic phonograph element, currently absent
- Vinyl label zone (paper label in center of the disc, distinct from the groove area)
- Realistic groove physics (variable pitch, not uniform rings)
- Spindle cap with a machined-metal look
- Warm sepia vignette on the backdrop (not cold black)

**Modern signals to keep:**
- Glassmorphism on the controls card (already exists, enhance it)
- Smooth physics-based animation (spin-down deceleration)
- Palette-extracted accent color from cover art
- Clean sans-serif typography, precise layout
- Micro-interaction feedback (seek bar pulse, tonearm haptic on swing)

**The synthesis:** A darkened listening room with warm overhead light, a real disc spinning on a turntable below a polished brass arm — but the controls panel is frosted glass with a precision seek bar. The disc looks like a physical object sitting in space, not a flat icon.

---

### Changes Spec

#### 1. Physics Spin-Down & Spin-Up (replaces hard-stop)

**Current:** `_discCtrl.repeat()` / `_discCtrl.stop()` — the disc teleports to a stop the frame you hit pause.

**New:**
- Add `_discAngle` (double, persisted across controller cycles) tracking the current rotation angle in radians.
- On **pause**: stop repeating, then run a one-shot `AnimationController` (`_spinDownCtrl`) using `CurvedAnimation(curve: Curves.decelerate)` over **900ms**. It tweens from `_discCtrl.value` → the natural "coasted" end position (no snapping to zero). On completion, record `_discAngle = result`.
- On **play**: start from `_discAngle`, run a one-shot `_spinUpCtrl` using `Curves.easeIn` over **600ms** to reach full speed, then hand off to `_discCtrl.repeat(from: normalized)`.
- Both controllers need `vsync: this` — add `_spinDownCtrl` and `_spinUpCtrl` as `late final` fields in `_AudioModeBackdropState`.
- **Tier gate:**
  - potato → instant stop/start (existing behavior, no new controllers allocated)
  - basic+ → ease-out decelerate (Curves.decelerate, no physics sim)
  - standard+ → same (decelerate is sufficient; physics sim would be overkill and CPU-heavy)

#### 2. Tonearm / Needle (new widget `_Tonearm`)

A phonograph arm is the single most recognizable classic element. Currently 100% absent.

**Structure:**
- New `StatelessWidget _Tonearm` positioned in the `Stack` above the `_Disc`.
- Position: top-right quadrant, pivoting from a fixed point at `Offset(discCenter.dx + discRadius * 0.82, discCenter.dy - discRadius * 0.78)` — slightly above and right of the disc.
- Arm length: `discRadius * 1.05` (just long enough to reach the groove area).
- Arm width: 11px at base, tapers to 5px at needle tip.

**Rendering (`CustomPainter _TonearmPainter`):**
- Body: `LinearGradient` along the arm axis — warm brass tones: `[Color(0xFF8B6914), Color(0xFFD4A843), Color(0xFF8B6914)]` (dark → gold highlight → dark, giving a brushed-brass cylinder illusion).
- Pivot cap: filled circle (18px diameter) at pivot point, `RadialGradient` from `Color(0xFFE8C060)` center to `Color(0xFF5A3E0A)` edge — looks like a polished brass bearing cap.
- Needle stub: last 14px of arm, same brass gradient, ends with a `Color(0xFFB8860B)` dot (4px, accent-tinted when cover art provides palette color).
- Headshell (cartridge): a small rectangle (16×8px) perpendicular to the arm near the tip — painted as a dark-gunmetal `Color(0xFF2A2A35)` with a thin bright edge line.

**Animation:**
- `_tonearmCtrl`: `AnimationController` duration 500ms.
- **Playing** (value → 1.0): arm swings in to the "playing" angle — rotated ~22° from resting position, needle tip resting over the outer groove ring of the disc.
- **Paused / stopped** (value → 0.0): arm lifts back to resting position, angled ~58° away from disc.
- Curve: `Curves.easeInOut`.
- Tier gate: potato → tonearm widget not rendered at all. basic+ → rendered and animated.
- **Haptic**: `HapticService.instance.light()` when tonearm reaches the "playing" position (arm-settles-on-record moment).

#### 3. Realistic Groove Rendering (full `_GroovePainter` rewrite)

**Current:** 18 identical rings, fixed 4.8px spacing, all at opacity 0.22. Flat and unconvincing.

**New `_GroovePainter`:**

**a) Label zone:**
- Inner 36% of disc radius = label area. No grooves drawn here.
- Instead: draw a very subtle warm circle fill `Color(0x14D4A843)` (amber, 8% opacity) to suggest paper label warmth — no border, no text, just a barely-perceptible warm zone center.

**b) Transition ring:**
- At 36% radius: a single slightly-brighter ring `strokeWidth: 1.0`, `opacity: 0.35` — the "label edge" ring real vinyl has.

**c) Variable-pitch grooves (36%–97% radius):**
- Start spacing at label edge: `2.8px`.
- End spacing at outer edge: `5.6px`.
- Linear interpolation: `spacing(r) = 2.8 + (r - labelR) / (maxR - labelR) * 2.8`.
- Groove color: alternates between `opacity: 0.16` and `opacity: 0.28` for depth illusion.
- `strokeWidth: 0.45` (finer than current 0.5).

**d) Rotating sheen arc (standard+ tier only):**
- In the `_Disc` `AnimatedBuilder`, pass `discCtrl.value` to `_GroovePainter`.
- Paint a `RadialGradient`-filled arc wedge (~38° wide) that rotates with the disc, starting at the label edge and ending at the outer groove ring.
- Colors: `[Colors.white.withOpacity(0.0), Colors.white.withOpacity(0.13), Colors.white.withOpacity(0.0)]` — a soft light sweep suggesting the disc catching ambient light.
- This uses `canvas.drawArc` clipped to the annular groove region.

**e) Outer edge ring:**
- At 97% radius: `strokeWidth: 1.5`, `opacity: 0.45` — the pressed vinyl outer bevel ring.

**`shouldRepaint`:** repaint when `innerD`, `animValue` (new param), or tier changes.

#### 4. Spindle Cap Detail (replace current dark circle)

**Current:** `SizedBox(22×22)` dark `Color(0xFF0B0D14)` with white12 border. Looks like a dot.

**New `_SpindleCap` widget (CustomPainter):**
- Size: 28×28px.
- Outer bevel ring (28px): `RadialGradient([Colors.white30, Colors.black54])` — simulates a machined bevel.
- Inner body (22px): `RadialGradient` from `Color(0xFF3A3A45)` center → `Color(0xFF18181F)` edge — dark metallic.
- Center dot (6px): accent color at 70% opacity — the spindle tip catch-light.
- No border — the gradient sells the form.

#### 5. Pause Overlay (replace opacity dim)

**Current:** `AnimatedOpacity(opacity: isPlaying ? 1.0 : 0.70)` wrapping the entire disc — disc fades out, looks like a rendering glitch.

**New:**
- Remove the `AnimatedOpacity` wrapper from `_Disc`.
- Add a `Stack` inside `_Disc`: disc widget at full opacity always, then on top:
  ```
  AnimatedOpacity(
    opacity: isPlaying ? 0.0 : 1.0,
    duration: Duration(milliseconds: 300),
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.30),
      ),
    ),
  )
  ```
- Plus a centered `AnimatedOpacity` pause icon (no `Icons.pause_rounded` — use a `CustomPaint` of two vertical rounded bars, warm white, 24×28px each, gap 10px) at `opacity: isPlaying ? 0.0 : 0.60`.
- Both fade in/out 300ms. Disc stays solid — now it looks like a "paused lamp" not a broken fade.

#### 6. Glow Pulse Sync to Playback State

**Current:** `_pulseCtrl` always runs at 2200ms. No relation to what's happening with the music.

**New:**
- In `didUpdateWidget`, when `isPlaying` changes:
  - Playing → `_pulseCtrl.duration = const Duration(milliseconds: 1600)` then `_pulseCtrl.repeat(reverse: true)` (restart from current value, not from 0).
  - Paused → `_pulseCtrl.duration = const Duration(milliseconds: 3400)` then same.
- Playing pulse is quicker and more alive; paused pulse breathes slowly like a sleeping lamp.
- Backdrop glow opacity range also changes: playing = `0.12 + v * 0.18`, paused = `0.06 + v * 0.09` (dimmer at rest).

#### 7. Track Change Entrance Animation

When `localPath` or `title` changes, the new disc should feel like a record being placed on the platter — not a hard swap.

- Add `_entryCtrl`: `AnimationController(duration: 400ms)`, curve: `Curves.easeOutBack`.
- On track change (`didUpdateWidget` path that calls `_scanCoverArt()`): `_entryCtrl.forward(from: 0)`.
- Disc widget wrapped in `ScaleTransition(scale: Tween(0.88, 1.0).animate(_entryCtrl))`.
- Cover art: wrapped in `FadeTransition(opacity: _entryCtrl)` — fades in as disc "settles".
- Tonearm: wait `_entryCtrl.duration * 0.55` (220ms) then swing in.
- Tier gate: basic+ only. Potato → instant swap.

#### 8. Warm Backdrop Vignette (aesthetic upgrade)

**Current:** vignette uses pure `Colors.black` — cold and flat.

**New:**
- Replace vignette gradient colors with `Color(0xFF0D0905)` (very dark warm brown, not pure black).
- Stops and opacities stay the same.
- Effect: the darkened areas of the backdrop now feel like a warm listening room rather than a cold void.
- No performance impact — it's just a color change in the `DecoratedBox` `LinearGradient`.

#### 9. Default Fallback Palette (no cover art = warm amber, not blue/purple)

**Current:** `_accent = const Color(0xFF7C5CFF)` default (purple). When no cover art, glow and controls are cold purple — fights the classic warm aesthetic.

**New:**
- `_accent = const Color(0xFFD4943A)` — warm amber gold. This is the "Neo-Phonograph" brand tone.
- Gradient fallback colors (`_gradientColors()`): keep the hash-based hue variation but shift the HSV saturation to 0.55→0.72 and brightness to 0.38→0.52, and clamp the hue into the warm quadrant (0°–80° = warm, 180°–300° = cool) — give it a bias toward amber/terracotta/mahogany.

#### 10. Controls Card Polish

The `_GlassCard` layout stays. These are targeted upgrades only:

**a) Seek bar gradient fill:**
- `_SeekPainter` progress fill: change from solid `accentColor` to `LinearGradient` from `accentColor` → `accentColor.withOpacity(0.65)` (slightly fades toward the right — looks like light).
- Same `createShader(Rect)` pattern already used in `_BarsPainter`.

**b) Seek thumb pulse while dragging:**
- Add a `_seeking`-gated `AnimationController _thumbPulseCtrl` (600ms, repeat reverse).
- When `_seeking` becomes true: `_thumbPulseCtrl.repeat(reverse: true)`.
- When false: `_thumbPulseCtrl.stop()`, reset to 0.
- In `_SeekPainter`: pass `thumbScale` param. Outer thumb radius = `8 + thumbScale * 3`. Creates a gentle beat while the user is dragging.

**c) Timestamp micro-animation:**
- Wrap timestamp `Text` widgets in `AnimatedSlide` + `AnimatedOpacity`: slide up 4px (`Offset(0, -0.15)`) and full opacity while seeking; slide back and 80% opacity at rest. Duration 200ms.

**d) Play button press feedback:**
- Existing `AnimatedContainer` already animates the button circle. Add: `HapticService.instance.medium()` on every `onPlayPause` call (if not already called from the player screen level — check first).

---

### What's NOT Changing
- `_BlobPainter` procedural gradient blobs — already good, leave it.
- Ken Burns `_kenBurnsCtrl` scale tween — already well done.
- `_GlassCard` layout, button positions, shuffle/repeat icons — no layout change.
- `BackdropFilter` on GlassCard — already API 28+ gated via `AnimConfig`, leave it.
- Audio routing, EQ, Lab, all panels in `_ps_panels_audio.dart` — zero touch.
- Cover art scanning logic — correct, leave it.
- `_parseTitle` artist/track parser — correct, leave it.

---

### Tier Compliance Table

| Feature | potato (API 21-22) | basic (API 23-27) | standard (API 28-32) | premium (API 33+) |
|---|---|---|---|---|
| Physics spin-down | ❌ instant stop | ✅ ease-out 900ms | ✅ ease-out 900ms | ✅ ease-out 900ms |
| Tonearm | ❌ not rendered | ✅ pivot animation | ✅ + needle dot | ✅ + needle dot |
| Groove sheen arc | ❌ | ❌ | ✅ | ✅ |
| Variable groove pitch | ✅ | ✅ | ✅ | ✅ |
| Pause overlay | ✅ | ✅ | ✅ | ✅ |
| Glow pulse sync | ✅ | ✅ | ✅ | ✅ |
| Track entrance anim | ❌ | ✅ | ✅ | ✅ |
| Warm vignette | ✅ | ✅ | ✅ | ✅ |
| Seek thumb pulse | ✅ | ✅ | ✅ | ✅ |
| Timestamp slide | ✅ | ✅ | ✅ | ✅ |

---

### New Controllers in `_AudioModeBackdropState`

```dart
late final AnimationController _spinDownCtrl;   // one-shot, 900ms
late final AnimationController _spinUpCtrl;     // one-shot, 600ms
late final AnimationController _tonearmCtrl;    // 500ms, drives tonearm angle
late final AnimationController _entryCtrl;      // 400ms, track-change entrance
AnimationController? _thumbPulseCtrl;           // nullable — only if standard+
```

All disposed in `dispose()`. `_thumbPulseCtrl` allocated lazily on first seek (avoids wasting a ticker on potato devices).

---

### Success Criteria
1. APK builds clean.
2. On physical device: disc decelerates visibly when pausing (no hard-stop).
3. Tonearm swings in/out smoothly on basic+ device; absent on potato.
4. Groove rings look like real vinyl (variable spacing, label zone, outer bevel ring visible).
5. Backdrop warm tones visible (not pure cold black).
6. No jank — gfxinfo shows ≥ 58fps during disc rotation.
7. Groove sheen arc only visible on standard+ device.
8. TASKS.md + PLAYER_UX_BB_PLAN.md tracker rows updated with commit SHA.

