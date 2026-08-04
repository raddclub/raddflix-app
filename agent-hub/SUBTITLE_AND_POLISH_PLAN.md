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

---

## Phase I — Player Gesture & Control Bugs (P1–P2)

> Found in deep audit of `_ps_ui_mixin.dart` (gestures/controls) and `_ps_playback_mixin.dart`.

### PLAY-I1 — Brightness/volume swipe: no throttle, out-of-order OS writes
**File:** `_ps_ui_mixin.dart` ~L611–L689
**Bug:** `ScreenBrightness().setScreenBrightness` and `VolumeController().setVolume` are called on
every pointer move event with no throttle, no await, and no error handling. Rapid writes can
complete out of order, leaving the OS value different from what the HUD shows. Failures are
completely silent.
**Fix:** Debounce/throttle with a 16 ms minimum interval (one frame). Wrap each call in
try/catch and log silently on failure. Read back the OS value after setting to confirm sync.

### PLAY-I2 — Volume model inconsistency: OS clamped to 0–1, MPV forced to 100, HUD shows 0–2.5
**File:** `_ps_ui_mixin.dart` ~L750–L756
**Bug:** `_volume` tracks 0..2.5, but OS volume is clamped to 0..1. For values ≤1, MPV is forced
to `volume=100` (native OS controls it). For values >1, MPV boost takes over. When the user
changes OS volume externally (e.g. hardware buttons), `_volume` is never updated and the HUD
shows stale data. On navigation/reload, MPV volume/boost state is not restored.
**Fix:** Subscribe to `VolumeController().volumeStream` to keep `_volume` in sync with OS
hardware changes. On navigation restart, restore the last MPV boost value from `PlayerPrefs`.
Add a clear visual distinction in the HUD between OS volume (0–100%) and MPV boost (>100%).

### PLAY-I3 — Lock screen: locked controls show full UI instead of unlock-only affordance
**File:** `_ps_ui_mixin.dart` `_toggleControls` ~L445–L455
**Bug:** When the player is locked, `_toggleControls` still shows and schedules hide for the full
controls overlay. A locked user can see and potentially tap all controls except with no
functional consequence. The expected behavior (MX Player / VLC) is: tap while locked → show
unlock icon only for 2 seconds, then re-hide.
**Fix:** In `_toggleControls`, when `_isLocked == true`, show only the lock/unlock affordance widget
(not the full overlay) and schedule its auto-hide after 2 seconds. All other control tap/gesture
targets must remain inert while locked.

### PLAY-I4 — `_seekRelative` uses stale cached position on rapid taps
**File:** `_ps_ui_mixin.dart` `_seekRelative` ~L458–L469
**Bug:** Each skip-forward/backward tap reads `_position` (a cached stream value). If the user
taps 3× quickly before the position stream updates, all three taps seek from the same old position
instead of accumulating. The skip flash timers are also not cancellable — overlapping flashes can
hide a newer flash prematurely.
**Fix:** Maintain a local `_pendingSeekTargetMs` that accumulates tap offsets client-side.
Commit to the player in a debounced call. Show flash based on total accumulated delta, not
per-tap. Cancel pending flash timers on new taps.

### PLAY-I5 — `_buildCenterControls()` is an explicitly empty widget
**File:** `_ps_ui_mixin.dart` ~L1328–L1332
**Bug:** The center controls builder returns an empty widget, while `_buildControlsOverlay`
still allocates a placeholder for it. Any intended center play/pause or skip controls are invisible.
Only the bottom transport row has a play button.
**Fix:** If center controls are not intended (bottom-only design), remove the dead allocation in
`_buildControlsOverlay`. If a center play/pause button is intended, implement it here.

### PLAY-I6 — Seek gesture emits full `setState` on every pointer move event
**File:** `_ps_ui_mixin.dart` gesture handler
**Bug:** Unlike position stream throttling, the seek drag gesture calls `setState` on every
pointer update. This triggers a full rebuild of the player overlay on every frame of a drag.
**Fix:** Use a `ValueNotifier<double>` for the in-progress seek delta and wrap only the
seekbar/preview widget in `ValueListenableBuilder` so the drag only rebuilds what it needs.

### PLAY-I7 — Player error visible only when `!_playing` — playing errors are silently lost
**File:** `_ps_playback_mixin.dart` ~L462–L466
**Bug:** The error stream listener only sets `_streamError` when `!_playing`. Errors that occur
while MPV still reports playing (e.g. stream buffer exhaustion, decode errors) are completely
invisible to the user. Transient errors while paused are treated as terminal.
**Fix:** Always update `_streamError` on error. For "playing" state errors, show a non-dismissive
error chip/snackbar overlay that auto-dismisses if playback recovers. For paused errors, show the
existing full error state.

### PLAY-I8 — `_player.open()` calls not wrapped in try/catch
**File:** `_ps_playback_mixin.dart` ~L641, L661, L739, L785
**Bug:** Direct `_player.open()` calls in the live, network, and local media paths are outside
any try/catch. An open failure (missing file, invalid URL, codec error on open) bypasses the
friendly error state and auto-retry logic entirely — the player silently stalls.
**Fix:** Wrap each `_player.open()` call in try/catch. On catch, set `_streamError` and
trigger the existing retry / friendly error display path.

### PLAY-I9 — `completed` event: no duplicate emission guard
**File:** `_ps_playback_mixin.dart` ~L460–L480 (`completed` stream listener)
**Bug:** media_kit can emit `completed=true` multiple times. There is no guard, so the completion
handler (end action sheet, episode navigation) can fire twice — opening two bottom sheets or
navigating twice.
**Fix:** Add a `bool _completionHandled = false` guard. Set it true on first completion; reset
it on `_openMedia`. Check it at the top of the completion handler.

---

## Phase J — PiP Overlay & Cast Panel Bugs (P2)

### PIP-J1 — PiP resize compounding: scale multiplied per frame → exponential jump
**File:** `lib/widgets/player/pip_overlay.dart` ~L64–L69
**Bug:** `onScaleUpdate` multiplies the *current* width by `details.scale` on each event.
Flutter's `ScaleUpdateDetails.scale` is cumulative relative to the gesture start, not
the previous event. The result: size grows or shrinks exponentially during a single pinch, making
any resize unusably jumpy.
**Fix:** Store `_baseSize` at `onScaleStart`. In `onScaleUpdate`, compute:
`_size = (_baseSize * details.scale).clamp(minSize, maxSize)` — this is the standard Flutter
pinch-to-resize pattern.

### PIP-J2 — PiP window draggable under status bar and navigation bar
**File:** `pip_overlay.dart` ~L57–L61
**Bug:** Pan bounds clamp to `screen.height - _size.height` with no safe-area offset, while the
snap logic (L37–L48) does account for safe area. The PiP window can be dragged behind the status
bar or Android navigation bar.
**Fix:** Fetch `MediaQuery.of(context).padding` in both pan and snap code paths and apply
consistently: `maxY = screen.height - _size.height - padding.bottom`.

### PIP-J3 — PiP controls never auto-hide (`_showControls` starts true, no timer)
**File:** `pip_overlay.dart` ~L31, L70
**Bug:** `_showControls` initialises to `true` and is only toggled on tap. There is no
auto-hide timer. Controls (close, expand, play/pause) are permanently visible over the video.
**Fix:** Add a 3-second auto-hide timer (same pattern as the main player). Reset on every tap.

### PIP-J4 — PiP inner buttons trigger outer `onTap` (controls toggle) unintentionally
**File:** `pip_overlay.dart` ~L70, child buttons
**Bug:** Close, expand, and play/pause buttons are nested under the outer `GestureDetector`.
Tapping any of them also fires the outer `onTap` → `_showControls` toggle. Tapping Close can
both close the PiP and show controls briefly, causing a visible flash.
**Fix:** Wrap each inner action button in `GestureDetector(behavior: HitTestBehavior.opaque,
onTap: ...)` with a top-level `AbsorbPointer` or use `Listener(onPointerDown: (e) =>
e.stopPropagation())` to prevent bubbling.

### CAST-J5 — Cast panel shows "No devices found" simultaneously with the scanning spinner
**File:** `lib/widgets/player/cast_panel.dart` ~L42–L65
**Bug:** When `onScanRequested` is in progress and `devices` is empty, the empty-state widget
("No devices found") and the scanning spinner are both visible simultaneously, sending
contradictory signals.
**Fix:** Add a `_scanning` boolean. Show "Searching…" placeholder (not the empty state) when
`_scanning && devices.isEmpty`. Show the empty state only after scanning completes.

### CAST-J6 — Connected device duplicated in available devices list
**File:** `cast_panel.dart` ~L54–L74
**Bug:** The connected device is shown in the dedicated `_ConnectedCard` AND also rendered
(disabled) in the available-devices list below. This is confusing and looks like a bug.
**Fix:** Filter `widget.devices` to exclude the currently connected device ID before rendering
the available-devices list.

### CAST-J7 — Cast signal bars unclamped — out-of-range `signalStrength` renders wrong
**File:** `cast_panel.dart` ~L157–L161
**Bug:** Signal bars loop `i < device.signalStrength` with no clamp. A value of 7 draws 7
bars in a 4-bar widget; a value of 0 or negative draws nothing or crashes.
**Fix:** Clamp to valid range: `device.signalStrength.clamp(0, 4)`.

---

## Phase K — Downloads & Local Media Reliability (P1–P2)

### DL-K1 — Download accepts HTTP 4xx/3xx as successful (validateStatus bug) 🔴 P1
**File:** `lib/services/download_service.dart` ~L160–L164
**Bug:** `validateStatus: (s) => s < 500` treats HTTP 401, 403, and 404 as successful
responses. An HTML error page larger than 512 KB is saved to disk and marked `completed`.
The user sees a "downloaded" file that is actually an error page.
**Fix:** Change to `validateStatus: (s) => s >= 200 && s < 300`. Add content-type
validation: if the response `Content-Type` is `text/html`, abort and mark as failed.

### DL-K2 — Concurrent downloads for same `fileId` overwrite each other
**File:** `download_service.dart` ~L123–L126
**Bug:** Destination filename is `$fileId.$ext`. Two simultaneous downloads for the same
file (e.g. user queues the same episode twice) write to the same path; whichever finishes
first is overwritten by the second.
**Fix:** Check for an existing in-progress download for the `fileId` before enqueuing.
If found, silently skip or show "already downloading" toast.

### DL-K3 — Partial files not cleaned up on generic Dio errors
**File:** `download_service.dart` ~L188–L202
**Bug:** The 512 KB validation path deletes the partial file on failure. Generic Dio errors
(timeout, connection reset, SSL) mark the DB row as failed but leave the partial `.mp4`/`.mkv`
file on disk indefinitely.
**Fix:** Add `File(destPath).deleteSync()` in the generic failure catch block (with a
`File.existsSync()` guard).

### DL-K4 — Resume CTA leads to nonexistent file (stale path not validated)
**File:** `lib/screens/local_media_screen.dart` ~L112–L121
**Bug:** The "Resume" CTA uses a persisted file path without checking `File(path).existsSync()`.
If the file was deleted, moved to vault, or is on external storage that unmounted, the resume
opens a nonexistent path — the player errors immediately. Stale resume prefs are never cleared.
**Fix:** On `_load()`, validate each persisted resume path. If the file no longer exists, clear
that resume record from SharedPreferences. Show the resume CTA only for validated paths.

### DL-K5 — `setState` without `mounted` guard in `_load()` and `_loadMusic()`
**File:** `local_media_screen.dart` ~L124–L205
**Bug:** Multiple `setState` calls after `await` operations (permission checks, media queries)
do not check `mounted`. If the user navigates away during the async load, these throw
`setState called on disposed widget` errors.
**Fix:** Add `if (!mounted) return;` before every `setState` call in both `_load()` and
`_loadMusic()`.

### DL-K6 — No pause/resume in downloads UI — only cancel or wait
**File:** `lib/screens/downloads_screen.dart`
**Bug:** The downloads screen offers Cancel and Delete for in-progress downloads but no
Pause/Resume. On slow connections, users have no option to temporarily pause a download
without cancelling it entirely.
**Fix:** Add `pauseDownload(fileId)` and `resumeDownload(fileId)` to `DownloadService`
(cancel the Dio token on pause, re-enqueue on resume). Show Pause/Resume toggle button in
the download progress row.

### DL-K7 — Bulk delete leaks files on disk
**File:** `downloads_screen.dart` bulk delete callbacks ~L687–L699
**Bug:** Bulk delete removes DB rows via the provider but does not call `File.deleteSync()`
on the actual downloaded files. Files accumulate on device storage invisibly.
**Fix:** `DownloadService.deleteDownload(fileId)` must delete the physical file before (or
immediately after) removing the DB row. Verify this is the case — if not, add the file
deletion step there.

---

## Phase L — Show Detail & History Screen Bugs (P1–P2)

### DET-L1 — Episode gap calculation broken in descending sort
**File:** `lib/screens/show_detail_screen.dart` ~L191–L196, L209–L229
**Bug:** `_currentEpisodesWithGaps` always computes missing-episode gaps as if episodes are
ascending (`prevNum + 1 .. thisNum`). In descending sort mode, this produces no gaps or
incorrect gaps, and placeholder ordering is wrong. Gap placeholders appear in the wrong
positions in the episode list.
**Fix:** Perform gap calculation on an ascending copy of the episode list, then reverse the
final padded list for descending display.

### DET-L2 — Episode tap uses display-list index, not stable file ID — plays wrong episode in descending sort
**File:** `show_detail_screen.dart` ~L1147–L1167
**Bug:** `_realIndex` is the visual index in the (potentially reversed) current-season list.
This is passed to `_playEpisode()` and also used for `nowPlayingIdx` highlighting. With
descending sort, tapping the first visible tile plays the last episode in ascending order.
**Fix:** Key episode navigation on stable `fileId` (or map display index back to an ascending
index). Never use `ListView` display position as an episode identity.

### DET-L3 — Season tab reload resets `_selectedSeason` to first — loses user's season selection
**File:** `show_detail_screen.dart` ~L167–L180
**Bug:** The `_reload()` method always sets `_selectedSeason = _seasons.first` and creates a
new `TabController`. Any refresh (sync, progress update, pull-to-refresh) jumps the user back
to Season 1. The tab listener captures a nullable `_seasonTab` that can be disposed before the
async callback fires, creating a disposed-controller race.
**Fix:** In `_reload()`, save `_selectedSeason?.id` before reloading and restore it afterward
(fall back to first if the season no longer exists). Guard the tab listener with a stale-flag
or cancel/re-register it.

### DET-L4 — Episode progress crashes on out-of-range values / empty file ID collision
**File:** `show_detail_screen.dart` ~L1149, L2203–L2217
**Bug:** (a) Progress is keyed by `file_id`. All episodes with a missing/empty `file_id`
share the key `''` and display the same progress value — or overwrite each other in the map.
(b) The progress value from the DB is passed directly to `CircularProgressIndicator.value`
without clamping to `0.0..1.0`. A malformed stored value (e.g. `1.2`, `-0.1`) triggers an
assertion crash.
**Fix:** (a) Skip keying by empty string; treat missing `file_id` as "no progress". (b) Clamp:
`progress.clamp(0.0, 1.0)` before passing to the indicator.

### HIST-L5 — "Clear All" history only clears local; server entries return on next sync
**File:** `lib/screens/history_screen.dart` ~L76–L103
**Bug:** `clearAllContinueWatching()` only clears the local DB. On next app launch (or when
another device triggers a history sync), the cleared entries reappear from the server.
**Fix:** Call a server-side history clear API endpoint as well. If no such endpoint exists,
mark items as `server_deleted` locally and filter them out of future sync merges.

### HIST-L6 — History screen: no per-item delete, clear is fire-and-forget with no error UI
**File:** `history_screen.dart`
**Bug:** (a) There is no per-item swipe-to-delete or long-press delete on individual history
entries — only the nuclear "Clear All" option.
(b) The clear operation is fire-and-forget; a failure leaves the UI unchanged with no error
banner or retry affordance.
**Fix:** (a) Add swipe-to-dismiss (same pattern as Watchlist) on each history tile.
(b) Await the clear operation; show a brief error snackbar on failure with a Retry CTA.

### HIST-L7 — History list has no date/day grouping
**File:** `history_screen.dart` ~L212–L247
**Bug:** History is a flat 3-column grid with no date or time grouping. Items watched
"today", "this week", and "months ago" are mixed together with no visual hierarchy.
**Fix:** Group history items by relative date bucket (Today / Yesterday / This week / Earlier).
Use a `SliverStickyHeader` or section header pattern (already used in other screens) to
separate groups.

---

## Phase M — Auth & Network Reliability (P2–P3)

### AUTH-M1 — 401 retry loop: no max retry count
**File:** `lib/core/api/api_client.dart` ~L251–L285
**Bug:** After a token refresh, the interceptor retries the original request via `_dio.fetch`.
If the refreshed token is also rejected (bad endpoint, misconfigured backend), this loop can
repeat indefinitely, hanging the app.
**Fix:** Add an `extra['_retryCount']` counter to request options. Abort and surface an error
if `_retryCount >= 2`. The refresh request itself is already path-excluded.

### AUTH-M2 — Refresh failure leaves UI "authenticated" (Keystore cleared, Riverpod not updated)
**File:** `api_client.dart` ~L287–L297
**Bug:** On refresh failure, tokens are cleared from the Keystore but the Riverpod `AuthProvider`
state is never updated. The UI shows the user as still logged in until the next screen/API check
coincidentally triggers a provider refresh.
**Fix:** On refresh failure, call an auth-invalidation method on the provider
(e.g. `authProvider.forceLogout()`) so the UI immediately reflects the unauthenticated state
and redirects to login.

### AUTH-M3 — First offline startup unnecessarily logs out user (no cached identity)
**File:** `lib/providers/auth_provider.dart` ~L80–L108
**Bug:** On startup, if network is unreachable and no `cachedUser` exists in the local DB,
any non-401 network/unknown error sets state to unauthenticated — even though valid tokens may
still be present in the Keystore. The user is forced through the login screen on first offline
launch.
**Fix:** On startup network failure, distinguish "unknown network error with valid token" from
"confirmed 401/unauthorized". Keep state as authenticated with a stale-indicator if tokens exist.
Only set unauthenticated on a confirmed 401 response.

### AUTH-M4 — Guest-to-auth sign-in inherits guest local data/state
**File:** `auth_provider.dart` ~L122–L125
**Bug:** `login()` switches from guest config to account config but does not perform the same
data cleanup that `logout()` does (clearing watchlist, player state, profile, guest sync
identity). Signing in from guest mode can show the guest's continue-watching entries and stale
watchlist items under the new authenticated account.
**Fix:** Before applying the account session in `login()`, call the same cleanup steps as
`logout()` (or extract them into a shared `_clearLocalSession()` helper and call it in both
paths).

---

## Phase N — Actor Screen, Search, and Misc Screens (P2–P3)

### ACTOR-N1 — Filmography `Future.wait` rebuilt inside `build` — duplicate requests on every rebuild
**File:** `lib/screens/actor_screen.dart` ~L31–L35
**Bug:** `Future.wait([_fetchFilmography(), _fetchBio()])` is constructed directly inside
`build()`. Every Riverpod/theme/parent rebuild creates two new HTTP requests and resets the
loading state visually.
**Fix:** Cache the future in `initState` (assign to a `late final _actorFuture`) and use
`FutureBuilder(future: _actorFuture, ...)`.

### ACTOR-N2 — `File.existsSync()` synchronous I/O inside `build`
**File:** `actor_screen.dart` ~L210–L212
**Bug:** `File(backdropPath).existsSync()` is called synchronously during `build()` for both
the backdrop and avatar images. On slower devices or large file systems, this blocks the UI
thread and causes jank on scroll/rebuild.
**Fix:** Pre-check existence in `initState` or `didUpdateWidget` and cache the result as a
bool field. The `build` method should only read the cached bool.

### ACTOR-N3 — Empty/whitespace actor profile URLs passed to `CachedNetworkImage`
**File:** `actor_screen.dart` ~L210–L243
**Bug:** `member.profileUrl != null` is the only guard. Empty string `""` and whitespace
URLs pass through to `CachedNetworkImage`, which fires HTTP requests to malformed URIs and
produces unnecessary error log churn.
**Fix:** Add `.isNotEmpty` and `.trim().isNotEmpty` guards alongside the null check.

### SEARCH-N4 — Search TextField missing `textInputAction: TextInputAction.search`
**File:** `lib/screens/search_screen.dart` ~L256–L270
**Bug:** No `textInputAction: search` and no `onSubmitted` — the software keyboard shows
a generic "return" key, not a search key. Submitting from the keyboard does not trigger a
search or dismiss the keyboard.
**Fix:** Add `textInputAction: TextInputAction.search` and
`onSubmitted: (_) { FocusScope.of(context).unfocus(); _runSearch(); }`.

### DOWNLOADS-N5 — Download progress stuck display on stalled transfers
**File:** `downloads_screen.dart` ~L416–L475
**Bug:** Progress bar renders `activeProgress[id] ?? persistedProgress`. A stalled download
(connection dropped, no data flowing) keeps showing the last active progress value
indefinitely — the user has no indication the download has stalled vs. is still progressing.
**Fix:** Add a stall-detection timeout in `DownloadService`: if no new bytes are received
within 30 seconds, mark the download as stalled and surface a "Stalled — tap to retry" state.

### NAV-N6 — Deep link to unknown/removed content crashes with unhandled route
**File:** `lib/app.dart` router ~L142–L153
**Bug:** The router's `onUnknownRoute` is not wired or falls back to a raw error route
instead of a safe home fallback. A deep link to a deleted episode or expired share link
crashes the navigation stack.
**Fix:** Add `onUnknownRoute: (settings) => MaterialPageRoute(builder: (_) => const HomeScreen())`
(or equivalent in the go_router setup). Show a brief "Content not found" snackbar.

### NAV-N7 — Mini-player reattach doesn't copy `_currentFileId`/episode metadata
**File:** `_ps_playback_mixin.dart` reattach path ~L300–L320
**Bug:** When the user returns from the mini-player to the full player (reattach), the
`_currentFileId`, title, and episode metadata are not copied from `PlaybackService`. Episode
navigation (Next/Prev) and resume key tracking can reference the wrong episode after reattach.
**Fix:** In the reattach path, copy all metadata from `PlaybackService` into local player state
alongside the existing stream/track state copy.

