# Subtitle, Audio, Player & Live TV Polish Plan
**Created:** 2026-08-04 | **Status:** OPEN — awaiting implementation

> Research basis: full code audit (2026-08-04) across `subtitle_overlay.dart`,
> `player_prefs.dart`, `_ps_panels_subtitle.dart`, `_ps_panels_audio.dart`,
> `audio_mode_backdrop.dart`, `_ps_audiolab_mixin.dart`, `_ps_ui_mixin.dart`,
> `quick_settings_panel.dart`, `settings_screen.dart`, `live_tv_screen.dart`,
> `LIVE_TV_FIXES.md`, and `FEATURES_ROADMAP.md`. Line-number citations are from
> the audit and may drift slightly — always re-grep before editing.
>
> Online research (August 2026): popular subtitle styles and UX patterns from
> YouTube, Netflix, VLC, MX Player, PotPlayer, mpv, Disney+, Prime Video.

---

## Phase A — Subtitle Positioning & Margin (P0 Critical)

These bugs make the subtitle margin/position settings completely non-functional. The root
cause is a structural disconnect: the subtitle panel writes to MPV properties and to a
different set of SharedPreferences keys than the ones `SubtitleOverlay` actually reads.

### SUB-A1 — Fix sign-stripped `abs()` in vertical offset calculation
**File:** `lib/widgets/player/subtitle_overlay.dart` L99–L106
**Bug:** Both top and bottom branches call `offset.abs()`, discarding the sign. Positive
and negative slider values produce identical positioning — the slider appears to work in
one direction only, and at zero offset the behaviour is the same as at any negative value.
**Fix:** Remove `abs()`. Use signed offset directly:
- Bottom: `bottom: 80.0 + offset` — positive moves up, negative moves down
- Top: `top: 20.0 - offset`
- Center: apply `top: offset` padding so center position responds too
Guard: clamp so bottom never goes negative (`bottom: max(4.0, 80.0 + offset)`).

### SUB-A2 — Wire bottom-margin slider to SubtitleOverlay (critical disconnect fix)
**Root cause:** The Position tab's "Bottom Margin" slider writes `pref_sub_margin` (via
`_saveSubPrefs` L2016) as a pixel value (0–200). `SubtitleOverlay` reads
`prefs.subtitleVerticalOffset` (a –1.0→+1.0 float stored under a different key). They are
unrelated fields. Changing the margin slider has zero visible effect on subtitles.
**Fix (two options — pick A or B):**
- **Option A (simpler):** In `_ps_panels_subtitle.dart`'s margin slider `onChanged`,
  also write `PlayerPrefs.subtitleVerticalOffset = value / 200.0 * 1.5` and persist via
  `playerPrefsProvider`. Remove the old MPV `sub-margin-y` setProperty call (MPV renders
  nothing — Rule 51).
- **Option B (clean):** Add a `subtitleBottomMarginPx` int field to PlayerPrefs (0–200,
  default 80). Wire the slider to write this field. Update `SubtitleOverlay._padding` to
  read it directly: `bottom: prefs.subtitleBottomMarginPx.toDouble()`.

### SUB-A3 — Auto-raise subtitles when seekbar/controls are visible (MX Player / YouTube behaviour)
**File:** `_ps_ui_mixin.dart` (control visibility transitions) + `subtitle_overlay.dart`
**Bug:** The existing `_applySubtitleMargin()` MPV call tries to push subtitles up when
controls show (`140px above bottom controls`), but MPV's subtitle renderer is disabled
(Rule 51). The Flutter `SubtitleOverlay` is `Positioned.fill` with a fixed bottom
padding — it never moves when controls appear. Subtitles sit over the seekbar.
**Fix:**
1. Add a `ValueNotifier<double> subtitleRaiseNotifier` to the player state (or use an
   existing `_showControls` bool to compute it).
2. When `_showControls == true`, raise value = seekbar height (48) + transport row (52) +
   bottom padding (10) + 8 safety gap = **~120 dp total raise**.
3. When `_showControls == false`, raise value = 0.
4. Animate the transition: `AnimationController(200ms, easeOut)` to smoothly slide the
   subtitle block up/down as controls fade in/out — identical to MX Player behaviour.
5. Pass raise value into `SubtitleOverlay` (new `controlsRaiseDp` param) and add it to
   the bottom padding: `bottom: basePadding + controlsRaiseDp`.
6. Apply the same raise logic in the portrait stack.

### SUB-A4 — Wire horizontal alignment (Left / Center / Right) to SubtitleOverlay
**File:** `subtitle_overlay.dart` + `_ps_panels_subtitle.dart`
**Bug:** The panel's "Horizontal Alignment" segmented control writes MPV `sub-align-x`
only. `SubtitleOverlay` always uses `Alignment.bottomCenter` / hardcoded centered
horizontal `margin: symmetric(horizontal: 24)`.
**Fix:**
1. Add `subtitleHorizontalAlignment` String field to PlayerPrefs (`'left'|'center'|'right'`,
   default `'center'`). Persist under `pref_sub_align_x`.
2. In panel `onChanged`, also call `ref.read(playerPrefsProvider.notifier)
   .update(p => p.copyWith(subtitleHorizontalAlignment: val))`.
3. In `SubtitleOverlay`, map the field: left → `Alignment.bottomLeft` + `left: 16` padding;
   center → existing; right → `Alignment.bottomRight` + `right: 16` padding.
4. Remove the MPV `sub-align-x` setProperty call (no-op with MPV disabled).

### SUB-A5 — Wire edge padding (horizontal margin) to SubtitleOverlay
**File:** `subtitle_overlay.dart` + `_ps_panels_subtitle.dart`
**Bug:** Edge Padding slider writes MPV `sub-margin-x`. `SubtitleOverlay` uses a
hardcoded `horizontal: 24` margin regardless of slider.
**Fix:**
1. Add `subtitleEdgePaddingPx` int field to PlayerPrefs (0–60, default 24). Persist under
   `pref_sub_edge_pad`.
2. Update `SubtitleOverlay` to read it: `horizontal: prefs.subtitleEdgePaddingPx.toDouble()`.
3. Remove the MPV `sub-margin-x` setProperty call.

---

## Phase B — Subtitle Style Presets & New Styles (P1)

### SUB-B1 — Fix `_applyPreset` — incomplete preset application
**File:** `_ps_panels_subtitle.dart` — `_applyPreset()` method
**Bug:** `_applyPreset` only applies font size, weight, text color, background
opacity/color, and a boolean shadow/outline presence. It does NOT apply: `position`,
`verticalOffset`, `italic`, `shadowBlur`, `shadowColor`, `shadowOffset`, line spacing,
or letter spacing. Preset styles that include these properties silently half-apply.
**Fix:** Extend `_applyPreset` to call `copyWith` on all fields defined in the preset's
`SubtitleStyle` object. After applying, call `_saveSubPrefs()` and the playerPrefs update.

### SUB-B2 — Wire `subtitleFont` and `subtitleStyleData` to SubtitleOverlay
**File:** `subtitle_overlay.dart`
**Bug:** PlayerPrefs has `subtitleFont` (5 font options) and `subtitleStyleData` (encoded
SubtitleStyle). Neither field is consumed by `SubtitleOverlay`; the font picker and style
data in the panel have zero visible effect.
**Fix:**
1. In `SubtitleOverlay._buildTextStyle()`, check `prefs.subtitleFont`:
   - `'open_dyslexic'` → `GoogleFonts.openDyslexic()`
   - `'lexie_readable'` → `GoogleFonts.lexieReadable()` (fallback to system if unavailable)
   - `'roboto'` → `GoogleFonts.roboto()`
   - `'atkinson'` → `GoogleFonts.atkinsonHyperlegible()`
   - `'system'` / default → current `TextStyle` family chain
2. Parse `subtitleStyleData` via `SubtitleStyle.decode()` and apply its fields (shadow blur,
   shadow color, letter spacing, line height) to the resulting `TextStyle`.

### SUB-B3 — Add popular preset subtitle styles
**Research basis:** YouTube (Aug 2026 default), Netflix, VLC, MX Player, Disney+, BBC,
PotPlayer, mpv defaults. Add to the preset list in `_ps_panels_subtitle.dart` and as named
`SubtitleStyle` enum/constants. All styles are pure Flutter — no MPV properties.

| Preset name | Font | Size | Color | Background | Outline | Shadow | Notes |
|---|---|---|---|---|---|---|---|
| **YouTube Default** | Roboto | 18 | White | Semi-black pill (opacity 0.75) | None | None | Exactly YouTube's current default |
| **Netflix** | Netflix Sans / Roboto | 20 | White | None | 1.5px black outline + soft drop shadow | Yes | Netflix's current style |
| **BBC iPlayer** | Reith / system | 20 | Yellow | Solid black box | None | None | High contrast, widely used by visually impaired |
| **Cinema Dark** | System | 22 | #F5F5DC (warm white) | None | 2px deep black outline | Subtle | Film festival / cinematic feel |
| **High Contrast** | Atkinson Hyperlegible | 24 | White | Solid black (opacity 0.9) | None | None | Accessibility-first; WCAG AAA |
| **Minimal** | System | 16 | White | None | None | 1px drop shadow | Unobtrusive, clean |
| **Night Mode** | System | 18 | #FFD700 (gold) | None | 1.5px dark outline | None | Easy on eyes in dark rooms |
| **Karaoke Ready** | Roboto Bold | 20 | White → Red highlight | Pill | None | None | Used with karaoke word highlight feature |
| **Urdu/Hindi Optimized** | Noto Nastaliq Urdu | 22 | White | Semi-black pill | None | Yes | Right-to-left text, larger base size |
| **Large Print** | System Bold | 28 | White | Black box | None | None | Low vision / TV viewing distance |

Implementation notes:
- Each preset is a `SubtitleStylePreset` const with a display name and a `SubtitleStyle`
  object (all fields fully populated — SUB-B1 must be done first).
- The existing preset grid in the panel (`_buildStyleTab`) should show these as named cards
  with a live preview of the text rendering on a mock dark background.
- Add a small "preview" mini-renderer (a scaled-down `SubtitleOverlay` with a fixed sample
  line) inside each preset card so the user can see exactly what the style looks like before
  selecting it.

### SUB-B4 — Add letter spacing and line spacing controls
**File:** `_ps_panels_subtitle.dart` — position/style tab
**Missing:** No line spacing or letter spacing slider exists.
**Fix:** Add two sliders to the Style tab:
- Line spacing: 1.0–2.0 (default 1.2), writes `subtitleLineSpacing` double in PlayerPrefs.
- Letter spacing: -1.0–4.0 px (default 0), writes `subtitleLetterSpacing` double.
Apply both in `SubtitleOverlay._buildTextStyle()` via `TextStyle.height` and `letterSpacing`.

### SUB-B5 — Add subtitle text shadow controls (blur + offset)
**File:** `_ps_panels_subtitle.dart` — style tab
**Missing:** Outline thickness exists but no shadow blur radius or shadow offset sliders.
Many popular styles (Netflix, Cinema) rely on soft shadows, not hard outlines.
**Fix:** Add:
- Shadow blur radius slider: 0–12 px (default 2), writes `subtitleShadowBlur` double.
- Shadow direction selector: None / Down-right / Down / All-sides (default Down-right).
Apply via `Shadow(blurRadius: r, offset: Offset(dx, dy))` in the `TextStyle.shadows` list.

---

## Phase C — Audio Player & Panel Fixes (P1)

### AUDIO-C1 — Vinyl disc audio player: add vibe entry point when mode is None
**File:** `lib/widgets/player/audio_mode_backdrop.dart` L398–L420
**Bug:** The vibe chip widget is only rendered when the current vibe mode is not `none`.
There is no button, chip, or affordance to enter a vibe mode when currently in Normal mode.
User can only activate vibes from the Audio Effect panel (not visible in the audio disc UI).
**Fix:** Always render a vibe row/chip. When mode is `none`, show a dim ghost chip labelled
"+ Vibe" with the vibe icon. Tapping it opens the Audio Effect panel directly at the Vibe
tab. When a mode is active, show the existing active chip (current behaviour).

### AUDIO-C2 — `_AudioTrackPanelState` missing `didUpdateWidget`
**File:** `_ps_panels_audio.dart` L1553–L1562 and surrounding `_AudioTrackPanelState`
**Bug:** `_selectedTrack`, `_sync`, `_useSW`, `_chIdx` are initialized in `initState` from
`widget` fields. If the parent rebuilds with new values while the sheet is mounted, all four
remain stale. Audio track switches made via other UI paths while the panel is open are not
reflected.
**Fix:** Add `didUpdateWidget` to sync all four fields when `widget` changes.

### AUDIO-C3 — `_AudioEffectPanelState` missing `didUpdateWidget`
**File:** `_ps_panels_audio.dart` — `_AudioEffectPanelState` (near L181–L203)
**Bug:** Same pattern. `_bands`, `_preset`, `_vibeMode`, `_eqEnabled`, and all lab toggles
are init-once. External state changes while panel is open are not reflected.
**Fix:** Add `didUpdateWidget` to re-sync all fields.

### AUDIO-C4 — SW decoder toggle should disable during active playback
**File:** `_ps_panels_audio.dart` L1693–L1707
**Bug:** The "Use Software Decoder" `SwitchListTile.onChanged` is always active. The panel
comment at L19 says to disable during playback (seeking is required to apply it).
**Fix:** Set `onChanged: _isPlaying ? null : (val) { ... }` and add a subtitle note:
`"Seek or restart to apply"` only visible when disabled.

### AUDIO-C5 — Audio backdrop title parser truncates names with dots
**File:** `audio_mode_backdrop.dart` L985–L995
**Bug:** Title is extracted by stripping from the last dot, treating any dot as an extension
separator. `"Dr. Who S01E01.mkv"` becomes `"Dr"`. Only exact `' - '` is recognised as an
artist separator.
**Fix:** Only strip the extension if the substring after the last dot is a known short
extension (`mp3`, `flac`, `wav`, `aac`, `m4a`, `ogg`, `opus`, `mp4`, `mkv` — max 4 chars).
For the artist split, also recognise `' – '` (em-dash) and `' — '` (en-dash).

### AUDIO-C6 — Wire dead audio-sync / sub-sync callbacks at player call site
**File:** `_ps_ui_mixin.dart` — the `_AudioTrackPanel(... onAudioDelay: (_) {}, onOpenSubSync: () {}, onOpenAudioSync: () {} ...)` call site (near L4484–L4492)
**Bug:** All three callbacks are no-ops `{}`. Users cannot adjust audio/sub sync delay from
the Audio Track panel even though the UI rows are rendered.
**Fix:** Wire `onAudioDelay` to the existing `_audioDelay` state setter + MPV
`audio-delay` property call. Wire `onOpenSubSync`/`onOpenAudioSync` to open the respective
sync panels.

---

## Phase D — Player Settings Panels & Quick Settings (P1–P2)

### PLAYER-D1 — Wire `onOpenPictureProfiles` and `onOpenWakeDnd` (dead no-ops)
**File:** `_ps_ui_mixin.dart` L4470–L4483
**Bug:** Both callbacks passed as `() {}`. Tapping the Picture Profiles row or Wake/DnD row
in the player settings panel does nothing.
**Fix:**
- `onOpenPictureProfiles`: show the `PictureProfilesSheet` bottom sheet (file exists at
  `widgets/player/picture_profiles_sheet.dart`). Guard against `_p.pictureProfile.isEmpty`
  (see PLAYER-D6) before opening.
- `onOpenWakeDnd`: open the inline wake/DnD section (or scroll to it if already visible in
  the same panel). Check if the QuickSettings panel already handles this inline and if so,
  remove the row from `_SettingsPanel` to avoid duplication.

### PLAYER-D2 — Style/Frame/Controls density/Progress settings not persisted
**File:** `quick_settings_panel.dart` — Style tab local state variables
**Bug:** Style preset selection, Frame style, Controls density, and Progress position are
stored in local widget state only. They reset every time the panel is closed. They also do
not affect any actual rendering because they never write to `PlayerPrefs`.
**Fix:** Map each control to a `PlayerPrefs` field (add fields if missing), wire the panel
to call `ref.read(playerPrefsProvider.notifier).update(...)` on change, and apply the
selected value in the relevant player rendering code.

### PLAYER-D3 — Add `immersive` to `_allSidebarIds`
**File:** `_ps_ui_mixin.dart` — `_allSidebarIds` list (near L281–L285)
**Bug:** `immersive` is defined as a sidebar action (L2343ff) but is absent from
`_allSidebarIds`. The sidebar customiser only shows IDs from this list, so users can never
add the Immersive mode shortcut to their sidebar.
**Fix:** Add `'immersive'` to `_allSidebarIds`. Verify no duplicate is introduced.

### PLAYER-D4 — Hide CC sidebar item when no subtitle tracks are available
**File:** `_ps_ui_mixin.dart` — sidebar rendering near L2350–L2355
**Bug:** The CC (subtitle) sidebar button is always shown even when the current media has
zero subtitle tracks. Tapping it opens an empty panel, confusing users.
**Fix:** Gate the CC sidebar button render on `_subtitleTracks.isNotEmpty || _subtitleEnabled`.
Show a disabled/dimmed state when `_subtitleTracks.isEmpty` so users know it's intentionally
absent for this file.

### PLAYER-D5 — Guard `pictureProfile[0]` against empty list
**File:** `quick_settings_panel.dart` L693–L694 (or wherever `_p.pictureProfile[0]` appears)
**Bug:** Can throw `RangeError` if `pictureProfile` list is empty (e.g. first launch before
any profile is created).
**Fix:** Replace with `_p.pictureProfile.isNotEmpty ? _p.pictureProfile[0] : null` and
handle the null case with a fallback "Default" label.

### PLAYER-D6 — Remove unused imports from `_ps_panels_audio.dart`
**File:** `_ps_panels_audio.dart`
**Bug:** `wake_lock_service.dart` and `voice_commands_service.dart` appear to be imported
but not directly referenced. Dart analyzer likely flags these as unused imports.
**Fix:** Remove the unused imports after verifying no symbol from those files is used.

### PLAYER-D7 — `_showFwdBtn` / `_showPrevNext` declared but never used
**File:** `_ps_ui_mixin.dart` — state declarations (grep for `_showFwdBtn`)
**Bug:** Both bool fields are declared and persist to prefs but nothing reads them to
conditionally show/hide the forward button or prev/next buttons.
**Fix:** Either (a) wire them to the transport row button rendering so they actually control
visibility, or (b) remove them entirely and remove the settings rows that configure them —
whichever matches the intended design.

---

## Phase E — Live TV Screen Fixes (P1–P2)

> Several of these are already documented in `LIVE_TV_FIXES.md`. Some may be partially
> done (check file state before implementing). Verify each against current code before coding.

### LTV-E1 — O-01: Live TV should retain current device orientation
**File:** `lib/screens/player_screen.dart` — `initState` orientation setup
**Bug:** `initState` unconditionally calls `_setNativeOrientation('sensor')` for ALL
content. When user taps a live channel in portrait, the player rotates to landscape.
**Fix:** Gate the orientation call on content type: live channels skip it and retain the
device's current orientation. VOD/movie/series keeps the existing sensor-autorotate.

### LTV-E2 — O-02: Dimension listener auto-rotates even for live streams
**File:** `_ps_playback_mixin.dart` — the `player.stream.videoParams` listener that calls
`_autoSelectOrientation()`
**Bug:** Auto-orientation runs for all content types. Live streams with landscape dimensions
force landscape on channels the user is watching in portrait.
**Fix:** Add `if (_isLive) return;` guard at the start of the auto-select callback.

### LTV-E3 — V-01: Live streams call unnecessary `_generateLink()` proxy/auth chain
**File:** `_ps_playback_mixin.dart` — `_openMedia()` for live content
**Bug:** `_openMedia()` calls `_generateLink()` which performs proxy selection, JazzDrive
login, and media URL generation. For live channels, a direct HLS URL is already provided.
**Fix:** Add an early branch: if `widget.streamUrl != null && _isLive`, call
`_player.open(Media(widget.streamUrl!))` directly and skip the rest of `_generateLink()`.

### LTV-E4 — Search keyboard not dismissed on scroll
**File:** `lib/screens/live_tv_screen.dart` L256–L270 (search TextField area)
**Bug:** No `textInputAction: TextInputAction.search` on the search field, no
`onSubmitted` dismissal, and no `ScrollController` listener to dismiss focus.
**Fix:** Add `textInputAction: TextInputAction.search`, `onSubmitted: (_) =>
FocusScope.of(context).unfocus()`, and a scroll listener: `_scrollCtrl.addListener(() {
  if (_scrollCtrl.position.userScrollDirection != ScrollDirection.idle)
    FocusScope.of(context).unfocus(); })`.

### LTV-E5 — No "Clear search" CTA in empty search results
**File:** `live_tv_screen.dart` empty state widget (near L371–L388)
**Bug:** Empty state only shows "No channels found" text. User must manually delete their
search query — no affordance to clear it.
**Fix:** Add a `TextButton("Clear search", onPressed: () { _searchController.clear();
setState(() => _searchQuery = ''); })` below the empty state text.

### LTV-E6 — Spinner-only loading state → channel skeleton cards
**File:** `live_tv_screen.dart` L312–L327
**Bug:** Loading state is a centered `CircularProgressIndicator` in a fixed 300dp box.
No layout preview, inconsistent with content grid.
**Fix:** Replace with a grid of shimmer skeleton cards matching the real channel card
dimensions (logo placeholder + title + category strips). Use the existing shimmer pattern
from other screens.

### LTV-E7 — Category filtering: case-sensitive exact match drops malformed entries
**File:** `live_tv_screen.dart` L104, L114
**Bug:** `c.cat == _selectedCat` is case-sensitive. Server sending `"Sports"` vs `"sports"`
causes channels to silently disappear under a category filter.
**Fix:** Normalise both sides to lowercase for comparison:
`c.cat.toLowerCase() == _selectedCat.toLowerCase()`.

### LTV-E8 — No error banner when refresh fails with stale data present
**File:** `live_tv_screen.dart` near L165–L167
**Bug:** Refresh errors are only shown when `hasError && all.isEmpty`. If a refresh fails
while stale channels are displayed, the user sees no indication that data may be outdated.
**Fix:** Add a persistent top banner (`"Couldn't refresh — showing cached channels"`) that
shows when `hasError && all.isNotEmpty`, with a manual retry button.

### LTV-E9 — Per-card `_pulseCtrl` animation causes full list rebuild each tick
**File:** `live_tv_screen.dart` — channel card widget (area noted in LIVE_TV_FIXES.md UI-06)
**Bug:** `_pulseCtrl` AnimationController is embedded inside each card widget. With 50+
cards, 50+ concurrent 60fps rebuild cycles fire simultaneously.
**Fix:** Move the single `AnimationController` to the outer list widget and pass the
animation value down to cards as a parameter, so only one `AnimatedBuilder` drives all
pulse animations.

### LTV-E10 — Live TV header uses hardcoded typography and bespoke badge
**File:** `live_tv_screen.dart` L205–L227
**Bug:** Header text sizes/weights are hardcoded instead of using `RaddType`/`AppTextStyle`
theme tokens. The channel-count badge is a raw `Container` instead of a design-system chip.
**Fix:** Replace with `Theme.of(context).textTheme` or `RaddType` equivalents. Replace
badge with the project's `RaddChip` or equivalent.

---

## Phase F — General App & Guest/Free/Admin Audit Fixes (P2–P3)

### APP-F1 — Guest user: settings screen shows paid/logged-in sections with no guard
**Perspective:** guest user
**Bug:** The settings screen does not conditionally hide subscription-dependent sections
(e.g. "Manage Subscription", account-linked features) from guest users. Guest users see
rows that silently do nothing or throw.
**Fix:** Add `if (isGuest) return const SizedBox.shrink();` guards around subscription
sections. Show a "Sign in to access" prompt where relevant.

### APP-F2 — Free user: no clear subscription-gate UI on premium content tap
**Perspective:** free user
**Bug:** Free users tapping premium content may see an opaque error or silent failure
rather than a clear "Subscribe to unlock" prompt with a direct CTA to the plans screen.
**Verify:** Check `player_screen.dart` `_isFree` logic and the existing subscription gate
sheet. Ensure the gate fires reliably on every premium content entry point (home, search,
detail, continue watching, mini player).

### APP-F3 — Admin: bulk operations in admin panel lack progress feedback
**Perspective:** admin
**Bug:** Long-running admin operations (library scan, bulk metadata refresh) give no
progress indicator beyond the initial toast. Admin assumes the operation stalled.
**Fix:** Add a periodic status poll or SSE endpoint that pushes progress updates to the
admin panel for scan/bulk-refresh operations.

### APP-F4 — Subscribed user: subscription expiry not shown anywhere in app
**Perspective:** subscribed user
**Bug:** A subscribed user has no way to check when their subscription expires in-app.
They discover it only when content stops playing.
**Fix:** Add an expiry date line to the Profile screen under the user's plan badge.
Read it from the existing user profile API response.

### APP-F5 — Normal user: deep-link to a series opens detail screen but loses scroll
position on back
**Perspective:** normal user
**Bug:** Navigating from a shelf → Show Detail → back causes the home shelf to scroll back
to top. (Related to UX4-01's IndexedStack fix — verify home state is truly preserved after
the navigation stack pops back through ShowDetail.)
**Fix:** Verify `AutomaticKeepAliveClientMixin` is correctly applied to the Home tab child
in the IndexedStack; if not, add it.

### APP-F6 — Voice commands: no visible indicator when voice mode is listening
**Bug:** `_VoiceCommandsService` activates on long-press hold but there is no visual/haptic
indicator that the system is actively listening vs idle.
**Fix:** Add a brief haptic + a small animated mic icon overlay during the listen window.

---

## Phase G — Subtitle System: Dual Subtitles & Secondary Track Fixes (P2)

### SUB-G1 — Dual subtitle panel: secondary track highlight freeze (partially fixed)
> Note: PANEL-ACTIVESTATE-FIX (`94e1ee0b`) added `_selectedSecondSub` local state.
> Verify the fix is complete and the secondary track selection actually persists on reopen.

### SUB-G2 — `DualSubtitleOverlay`: apply same auto-raise logic from Phase A SUB-A3
**File:** `lib/widgets/player/dual_subtitle_overlay.dart`
**Bug:** If dual subtitles are active, neither track auto-raises when the seekbar appears.
**Fix:** Pass the same `controlsRaiseDp` parameter to `DualSubtitleOverlay` and apply it
to the bottom padding of both subtitle rows, with the secondary row raised an additional
fixed amount above the primary.

### SUB-G3 — Dual subtitle font/style should inherit Phase B styles for primary track
Ensure the primary dual-sub track respects `subtitleFont` and `subtitleStyleData` fields
after SUB-B2 is implemented.

---

## Phase H — Production Hygiene Tweaks (P2–P3)

### PROD-H1 — Remove dead MPV subtitle-property calls now that SubtitleOverlay owns all rendering
**Files:** `_ps_subtitle_mixin.dart` — `_applySubtitleStylePrefs()`, `_applySubtitleMargin()`
**Status:** Rule 51 (2026-07-29) says these are "no-ops but harmless to leave." After
Phase A is done, they are confirmed dead. Remove them to reduce confusion and prevent a
future developer from assuming they work.
**Caveat:** Read surrounding call sites carefully — some may have non-styling side-effects
(e.g. error logging, prefs-save side effects). Only delete lines that are pure setProperty
calls with no other effects.

### PROD-H2 — Sidebar stale-ID validation improvement
**File:** `_ps_ui_mixin.dart` L2530–L2532
**Bug:** On startup, stale/unknown sidebar IDs from old prefs are silently filtered during
render but never cleaned from the persisted list. Over time the prefs file accumulates
junk IDs.
**Fix:** On `_loadPrefs`, after reading `_sidebarOrder`, call
`_sidebarOrder.removeWhere((id) => !_allSidebarIds.contains(id))` and immediately
`_scheduleSavePrefs()` if any were removed.

### PROD-H3 — DropdownButton wake timeout assertion on unknown prefs value
**File:** `quick_settings_panel.dart` L796–L810
**Bug:** If `playerPrefs.wakeTimeoutSeconds` contains a value not in the dropdown items
list (e.g. from an old app version), `DropdownButton` asserts and throws.
**Fix:** Add `.contains(val) ? val : defaultTimeout` guard before passing to
`DropdownButton.value`.

---

## Implementation order (suggested)

```
Phase A (all 5) → Phase B (SUB-B1 first, then B2, B3, B4, B5)
 → Phase C (all 6) → Phase D (D1–D7) → Phase E (all 10)
 → Phase F (F1–F6) → Phase G (G1–G3) → Phase H (H1–H3)
```

Phase A is a hard prerequisite for B (margin must work before presets can be validated).
Phase C and D can run in any order relative to each other.
Phase E (Live TV) is fully independent.

---

## CI requirements

After any commit touching `raddflix_flutter/**`, check `build-apk.yml` conclusion == `success`.
After any commit touching `test/` or `pubspec.yaml`, also check `ci-tests.yml`.
Follow Rule 42 (log → edit → push) for every single file change.
