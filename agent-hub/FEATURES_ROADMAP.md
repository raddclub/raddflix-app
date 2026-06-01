# RaddFlix Player — World's Most Advanced Video Player Roadmap
> Vision: Beat MX Player, VLC, Kodi, and every other player on earth.
> Full customizability — every button, color, position, seek bar style, theme.
> Features never seen in any player. Research-backed. Implementation-ready.
> Last Updated: 2026-06-01

---

## 🎯 North Star

> "Any user — teenage girl who wants a pink fluffy player, a cinephile who wants a film-grain LUT overlay, a developer who wants full gesture remapping — should be able to make this player completely their own without installing anything extra."

---

## ✅ ALREADY BUILT (Current State)

| Feature | Status | Notes |
|---------|--------|-------|
| MX Player UI layout | ✅ | Vertical seek btn, column center controls, right strip |
| Quick Settings (5 tabs) | ✅ | Style/Screen/Controls/Navigation/Text |
| EQ Panel (8-band) | ✅ | Audio Effect + Equalizer tabs |
| More Sheet (16 items) | ✅ | Full 4×4 grid |
| Cinematic Mode | ✅ | Controls wrapped in Opacity(_cinematicOpacity) |
| Immersive Mode | ✅ | Pure one-tap pause, gesture values silent |
| Cinematic Opacity Slider | ✅ | 15%–100%, live preview bar in settings sheet |
| Audio/Subtitle panels | ✅ | Track chips + sync sliders |
| A-B Loop | ✅ | |
| Scene Bookmarks | ✅ | Emoji markers on timeline |
| Sleep Timer | ✅ | |
| PiP Mode | ✅ | |
| Ambilight Effect | ✅ | |
| Subtitle customization | ✅ | Font, size, color, shadow, border |
| Video Enhancement | ✅ | Brightness, contrast, saturation |
| Frame Step | ✅ | |
| Volume Boost | ✅ | |
| Speed Picker | ✅ | |
| Thumbnail preview seek | ✅ | |
| Chapter markers | ✅ | |
| Long-press 2× speed | ✅ | Works in all 3 modes |

---

## 🎨 PHASE A — Full UI Theme Engine (THE BIG ONE)

> This is what no other player has: a complete skin designer inside the app.

### A1 — Accent Color System
**Never seen in MX Player or VLC.**

Every colored element in the player (seek bar fill, play button, active icons, chip borders, mode indicators) reads from a single `accentColor` in `PlayerPrefs`. 

```dart
// PlayerPrefs additions:
Color accentColor = const Color(0xFFE8002D);  // default RaddFlix red
// User picks: hex input OR palette of 24 presets:
// Red, Pink, Hot Pink, Purple, Lavender, Blue, Sky, Cyan,
// Teal, Green, Lime, Yellow, Amber, Orange, White, Silver,
// Rose Gold, Coral, Mint, Indigo, Peach, Lilac, Gold, Neon Green
```

UI: In Quick Settings → Style tab → **"Player Color"** row → opens `_ColorPickerSheet`:
- 24 preset swatches in 4×6 grid (labeled)
- "Custom" button → hex text field + RGB sliders
- Live preview: seek bar + play button + chip instantly update

**Files to create:**
- `widgets/player/color_picker_sheet.dart`
- Modify `PlayerPrefs` — add `accentColor`
- Modify `quick_settings_panel.dart` — add color row to Style tab
- Modify ALL colored widgets to read `PlayerPrefs.accentColor`

---

### A2 — Seek Bar Styles (10 styles — biggest innovation)
**VLC has 1. MX Player has 1. We have 10.**

Add `seekBarStyle` enum to `PlayerPrefs`:

```dart
enum SeekBarStyle {
  classic,       // ─────●───────────── (current thin line)
  materialBold,  // ═════●═══════════  (fat line, Material3)
  gradientGlow,  // gradient + bloom shadow (2 user colors)
  waveform,      // audio amplitude painted as bumpy bar
  filmstrip,     // tiny frame thumbnails row (when available)
  neonRgb,       // animated rainbow cycling
  chapters,      // bar auto-splits at chapter points, each segment color
  dots,          // ● ● ● ● ● ● (dots instead of line)
  circular,      // arc seek bar wraps around play button (portrait mode)
  minimal,       // hairline 1px + bare circle thumb
}
```

**Implementation plan:**
- Create `widgets/player/seek_bar_painter.dart` — `CustomPainter` with a `switch` on `SeekBarStyle`
- Quick Settings → Style tab → **"Seek Bar Style"** row → horizontal scroll preview strip
- `gradientGlow` style: two `gradientColor1/2` extra prefs, glow via `BoxShadow`
- `waveform`: pre-generates amplitude array on first play (from video duration, random seed for now; real audio analysis if we add `fftea` package later)
- `neonRgb`: uses `AnimationController` at 3s period cycling HSV hue
- `chapters`: reads `_chapters` list from state, draws colored segments
- `filmstrip`: uses existing thumbnail cache

---

### A3 — Button & Icon Style System

```dart
enum ButtonShape { circle, squircle, rounded, sharp, pill }
enum IconPack    { mx, ios, fluent, material3, cute, minimal }
```

**ButtonShape** affects: play/pause button, seek buttons, side buttons, bottom sheet buttons.
- `circle` — current default (stadium around icon)
- `squircle` — Apple-style super-ellipse (use `smooth_corner` or custom path)
- `rounded` — 8px rounded rectangle
- `sharp` — no rounding
- `pill` — very elongated rounded rectangle (makes all buttons feel friendly)

**IconPack** — swappable icon sets:
- `mx` — current MX-style (Material icons)
- `ios` — SF Symbols-matching (CupertinoIcons)
- `cute` — rounded, chonky, friendly (great for the teenage girl use case)
- `fluent` — Microsoft Fluent icons (modern professional)
- `minimal` — hairline outline icons, very thin weight

Map: `IconPack` → `Map<String, IconData>` (play, pause, forward, back, lock, etc.)

**Files:**
- `core/player/icon_packs.dart` — defines all mappings
- `core/player/button_shape_painter.dart` — custom clip path for squircle
- Add to PlayerPrefs: `buttonShape`, `iconPack`
- Add to Quick Settings → Style tab

---

### A4 — Controls Background Style

```dart
enum ControlsBgStyle { none, glass, gradient, solid, mesh }
```

- `none` — controls float with no background (current)
- `glass` — `BackdropFilter(ImageFilter.blur(sigmaX:16))` + white5% fill (iOS-style)
- `gradient` — black gradient behind top bar + bottom controls
- `solid` — solid dark bar (like YouTube)
- `mesh` — animated mesh gradient (rare, looks premium)

Add to Quick Settings → Style tab.

---

### A5 — Saved Themes ("Player Skins")

Pre-built themes bundled in app:

| Theme | Accent | SeekBar | Buttons | Icons | Background |
|-------|--------|---------|---------|-------|-----------|
| **RaddFlix** (default) | Red #E8002D | Classic | Circle | MX | None |
| **Midnight** | Purple #8B5CF6 | GradientGlow | Squircle | Fluent | Glass |
| **Sakura** 🌸 | Hot Pink #FF4081 | Waveform | Pill | Cute | Gradient |
| **Gold Class** | Gold #FFB300 | Chapters | Squircle | Fluent | Solid |
| **Matrix** | Green #00FF41 | Neon RGB | Sharp | Minimal | None |
| **Ocean** | Cyan #00BCD4 | GradientGlow | Rounded | iOS | Glass |
| **Sunset** | Orange #FF6D00 | Dots | Pill | Cute | Gradient |
| **Snow** | White #FFFFFF | Minimal | Sharp | Minimal | Solid |

User can also save their own custom theme. Max 6 saved custom themes.

**"Sakura" theme** solves the "girls want pink player" request perfectly. One tap.

---

## 🕹️ PHASE B — Control Layout Designer
**NO other player has this. Ever.**

### B1 — Drag & Drop Layout Editor

A dedicated full-screen editor (separate route: `/player/layout-designer`) where:
- The video plays behind (or shows a blurred screenshot)
- All player controls appear as draggable "tiles"
- User drags any tile to any position on screen
- Long-press tile → resize (S/M/L) or remove
- "Save Layout" → stores JSON to SharedPreferences
- Multiple saved layouts ("Movie", "Music", "One-Hand", etc.)

Layout JSON format:
```json
{
  "name": "Sakura Layout",
  "controls": [
    {"id": "play_pause", "x": 0.5, "y": 0.5, "size": "L", "visible": true},
    {"id": "seek_back",  "x": 0.3, "y": 0.5, "size": "M", "visible": true},
    {"id": "seek_fwd",   "x": 0.7, "y": 0.5, "size": "M", "visible": true},
    {"id": "lock",       "x": 0.05, "y": 0.1, "size": "S", "visible": true},
    ...
  ]
}
```

All control IDs: `play_pause`, `seek_back`, `seek_fwd`, `lock`, `pip`, `rotate`,
`subtitle_toggle`, `audio_track`, `settings`, `speed`, `more`, `volume_bar`,
`brightness_bar`, `next_episode`, `skip_intro`, `bookmark`

### B2 — Quick Layout Presets
- "Centered" (all controls centered — default)
- "Left Handed" (major controls on left side)  
- "Right Handed" (major controls on right side)
- "Minimal" (only play/pause + seek bar)
- "Full" (everything visible)

---

## 👆 PHASE C — Gesture Engine (Full Remapping)
**MX Player has fixed gestures. We let users remap everything.**

### C1 — Gesture Action Map

Every gesture → any action from this list:
```
Actions: Play/Pause | Seek ±5s | Seek ±10s | Seek ±30s | Volume ±
         Brightness ± | Speed ± | Lock | Mode Cycle | Next Episode
         Screenshot | Rotate | Jump to % (0/25/50/75/100%) | Bookmark | PiP
         Toggle Subtitle | Toggle Audio | Nothing
```

Zones:
- Left swipe vertical → (default: brightness)
- Right swipe vertical → (default: volume)
- Center swipe horizontal → (default: seek)
- Left half double-tap → (default: seek back)
- Right half double-tap → (default: seek forward)
- Center double-tap → (default: play/pause)
- Long press → (default: 2× speed)
- Triple tap → (default: rage skip)
- Two-finger swipe up → (default: nothing → could set: fullscreen toggle)
- Two-finger tap → (default: nothing → could set: screenshot)

UI: Quick Settings → Controls tab → **"Customize Gestures"** button → `_GestureMapSheet`
Each gesture row has a dropdown/selector for the action.

### C2 — Gesture Sensitivity
Per-gesture sensitivity slider (multiplier 0.5×–3.0×):
- Volume swipe sensitivity
- Brightness swipe sensitivity  
- Seek swipe sensitivity (px per second of video)

---

## 🔬 PHASE D — Video Science Features

### D1 — Picture Profiles (Like Camera Profiles)
**Never seen in any streaming app.**

Save complete video enhancement settings (brightness/contrast/saturation/sharpness/warmth/tint/grain reduction) as a named profile.

Bundled profiles:
- **Natural** (0,0,0,0 all neutral)
- **Cinema** (+5 contrast, -10 saturation, +8 warmth, slight vignette)
- **Vivid** (+15 saturation, +8 contrast, +5 sharpness)
- **Night** (+20 brightness, -5 contrast, +5 warmth) — great for dark rooms
- **Anime** (+12 saturation, +8 sharpness, +5 contrast)
- **AMOLED Saver** (-20 brightness, pure blacks enhanced)

User can save custom profiles. Max 8.
Auto-apply by content type detection (from title metadata: Movie/Anime/Music/Sports).

### D2 — Color LUT Support
**VLC has LUT support. MX Player doesn't. We add it better.**

Load a `.cube` LUT file from device storage and apply it to video via shader.
Bundled LUTs: Teal-Orange (Hollywood blockbuster), Moody Blue, Golden Hour, B&W Classic, Faded Film.

Implementation: Flutter custom shader (GLSL) via `FragmentShader`. 

### D3 — Video Grain / Film Look
Toggleable animated film grain overlay (a subtle, randomized static layer).
3 intensity levels: Subtle / Medium / Heavy.
Makes old content feel cinematic. Never seen in mobile players.

---

## 🎵 PHASE E — Audio Lab (Beyond EQ)

### E1 — Virtual Surround Sound
Binaural audio processing — makes stereo content feel like 5.1 surround through headphones.
Toggle + 3 room modes: Stadium / Theater / Small Room.

### E2 — Karaoke Mode (Vocal Remover)
Phase-cancellation algorithm to reduce center-channel vocals.
3 levels: Reduce / Strong Reduce / Remove.
Perfect for dance covers, language learning, karaoke sessions.

### E3 — Dialogue Boost
Intelligently boosts the 2kHz–5kHz frequency range where speech sits.
Makes dialogue crisp without boosting background music/noise.
Great for content with heavy background score.

### E4 — Bluetooth Audio Delay Fix
Automatic Bluetooth latency detection + manual fine-tune (0–500ms).
Different from subtitle sync — this offsets video forward to match audio playback latency.

### E5 — Bass Boost + Virtualizer
Android AudioEffect wrappers for BassBoost and Virtualizer, exposed as simple sliders.

---

## 💬 PHASE F — Subtitle World

### F1 — Dual Subtitle Display
Show two subtitle tracks simultaneously (stacked).
Perfect for language learning (native + learning language).
Settings: gap between lines, per-track size, per-track color.

### F2 — Subtitle Search
Tap magnifier on subtitle panel → type a word or phrase →
jumps to that dialogue moment. Perfect: "find the scene where they said X".

### F3 — Word Tap Dictionary
Long-press any word in the currently displayed subtitle → dictionary popup.
Use `wiktionary` free API (no key needed). Show: definition, pronunciation, examples.
Language-aware: Urdu subtitles → Urdu dictionary; English → English.

### F4 — Subtitle Karaoke Mode
Highlight the currently spoken word in the subtitle (when `.srt` has timing granularity, or via phoneme sync algorithm). Like YouTube auto-captions highlight.

### F5 — Subtitle Export
After adjusting subtitle timing, export corrected `.srt` file to device.
Huge feature for subtitle editors/translators.

---

## 🤖 PHASE G — Smart Features (AI-Powered)

### G1 — Smart Chapter Detection
Analyze scene change frequency from video stream → auto-create chapters.
Mark on seek bar as vertical tick marks.
Show chapter names (Part 1, Part 2… or use TMDB chapters if available).

### G2 — Skip Silence
Detect silent/music-only segments (no dialogue) and auto-skip them.
Works amazingly for lectures, interviews, podcasts.
Similar to Netflix's silence detection but for local/any content.

### G3 — Smart Subtitle Positioning
Detect faces in current frame using ML Kit → if a face is near the bottom where subtitles appear, move subtitles to top.
**First ever in a mobile video player.**

### G4 — Content Mood Timeline
Analyze subtitle text sentiment → color-code the seek bar:
Blue tints = calm/dialogue, Red = action/tension, Yellow = comedy, Purple = dramatic.
Subtle visual layer that adds richness to the seek bar.

---

## 📱 PHASE H — Mobile-First Features

### H1 — One-Handed Mode
All controls shift to one side (left or right).
Seek bar moves to side. Play/pause moves to corner.
Configurable which side.

### H2 — Lock Screen Player
When screen locks, show minimal player controls on lock screen.
(Already partially possible via Android media session — full integration.)

### H3 — Floating Mini Player (enhanced)
Current PiP is system PiP. Build our own custom floating window:
- Draggable anywhere on screen
- Resize by pinch
- Tap to return to full screen
- Works within app (doesn't use system PiP API)

### H4 — Screen Wake Lock Options
Currently: always on during playback.
Add: "Allow sleep after 10/20/30 min of inactivity" toggle.

### H5 — Do Not Disturb Mode
When entering Immersive or Cinematic mode → optionally enable Android DND.
Silent mode while watching. Notifications blocked.

---

## 👥 PHASE I — Social Features

### I1 — Watch Party (RaddFlix Rooms)
Create a room → share 6-digit code → friends join →
playback synced to room host. Host play/pause/seek → everyone follows.
Host indicator badge on screen. Guest count shown.

Implementation: WebSocket server endpoint `/ws/room/<code>`.
Max 6 people per room.

### I2 — Reaction Stamps
While watching (solo or in party), send emoji reactions that float up from bottom.
Same as Twitch/YouTube Shorts reactions. Store timestamps.
After watching: "Reactions at this moment" timeline on seek bar as dots.

### I3 — Shared Bookmarks
Make a scene bookmark public → visible to friends who watch same content.
"3 people bookmarked this scene 🔥" indicator.

---

## ♿ PHASE J — Accessibility Champions
**MX Player has almost none. VLC has some. We lead.**

### J1 — Voice Commands
"Hey RaddFlix, skip 2 minutes" / "louder" / "subtitles off" / "speed 1.5"
Android SpeechRecognizer API → parse commands → execute actions.
No internet needed (on-device recognition).

### J2 — Color Blind Modes
3 modes: Deuteranopia / Protanopia / Tritanopia
Applies color-correction shader to video output.

### J3 — Dyslexia Subtitle Font
Option to use OpenDyslexic or Lexie Readable font for subtitles.

### J4 — Motor Impairment Mode
- Slow tap recognition speed (longer timeout for double-tap)
- Extra-large touch targets
- Tap-hold to seek (hold = continuous fast seek in one direction)
- Single large "play / pause" button mode

### J5 — Haptic Feedback Patterns
Different vibration patterns for: seek forward, seek back, lock, volume max, volume zero, mode change.
Fully customizable intensity.

---

## 🔒 PHASE K — Privacy & Security

### K1 — Private Screen Mode
Face detection: if more than 1 face detected (someone looking over shoulder) → blur/dim video.
"Privacy Shield" toggle. Uses ML Kit face detector on front camera.

### K2 — Screenshot Lock
Toggle to block Android screenshots in player.
(Already common in banking apps — `FLAG_SECURE`)

### K3 — Watch History PIN Lock
Require PIN/fingerprint to view watch history or clear it.
Useful for shared devices.

---

## 🖼️ PHASE L — Video Frame Features

### L1 — Video Screenshot (Enhanced)
Current: basic screenshot. Enhance:
- Auto-removes controls/overlays from screenshot
- Optionally adds: movie name + timestamp watermark
- Share directly or save to gallery

### L2 — Frame-by-Frame Navigation (Enhanced)
Current: frame step. Enhance:
- Show frame counter (Frame: 1847 / 142,360)
- Export current frame as JPEG at full native resolution
- Jump to specific frame by number

### L3 — Video Zoom Regions (Focus Mode)
User draws a rectangle on screen → video zooms into that region.
Like a magnifying glass mode.
Perfect for: reading text in movies, sports detail, medical content.

---

## 🎮 PHASE M — Advanced Controls

### M1 — Custom Speed Presets
User defines their own speed list (e.g., 0.8, 1.0, 1.2, 1.5, 1.75, 2.0, 3.0).
Long-press speed button → speed dial with user's presets.

### M2 — Jump To (Skip by Time)
Quick jump panel: tap -5m / -1m / -30s / +30s / +1m / +5m buttons.
Like a numpad for time navigation.

### M3 — End-of-Video Actions
User-configurable: when video ends:
- Play next (default)
- Loop
- Return to home
- Show credits
- Auto-play countdown (5, 10, 20 sec — user sets)
- Do nothing

### M4 — Smart Skip (Beat MX Player's "Skip Silent")
- Skip silence (no audio)
- Skip black frames (pre-roll ads, studio logos)
- Skip opening credits (first N seconds: user sets)
- Skip ending credits (last N seconds: user sets)

---

## 📊 Implementation Priority Order

### Sprint 1 (highest user impact):
1. **A1** Accent Color System — enables ALL color customization
2. **A2** Seek Bar Styles — most visible, most impressive  
3. **A5** Saved Themes (Sakura 🌸 + 7 others) — instant wow

### Sprint 2 (power users):
4. **A3** Button/Icon Style System
5. **C1** Gesture Remapping
6. **D1** Picture Profiles

### Sprint 3 (never-seen features):
7. **B1** Drag & Drop Layout Designer
8. **F1** Dual Subtitle Display
9. **G3** Smart Subtitle Positioning

### Sprint 4 (social + accessibility):
10. **I1** Watch Party Rooms
11. **J1** Voice Commands
12. **E2** Karaoke Mode (Vocal Remover)

---

## 🗂️ New Files to Create (implementation map)

| File | Purpose |
|------|---------|
| `widgets/player/color_picker_sheet.dart` | Accent color selection UI |
| `widgets/player/seek_bar_painter.dart` | 10 seek bar styles (CustomPainter) |
| `widgets/player/theme_picker_sheet.dart` | Bundled + custom themes |
| `core/player/icon_packs.dart` | Icon pack mappings (MX/iOS/Cute/Fluent/Minimal) |
| `core/player/button_shape_painter.dart` | Squircle + custom button shapes |
| `core/player/player_theme.dart` | Theme data class (accent + style + icons + bg) |
| `widgets/player/layout_designer.dart` | Drag & drop control layout editor |
| `core/player/layout_prefs.dart` | JSON persist/load for saved layouts |
| `widgets/player/gesture_map_sheet.dart` | Gesture action remapping UI |
| `widgets/player/picture_profiles_sheet.dart` | Picture profile save/load/apply |
| `widgets/player/dual_subtitle_overlay.dart` | Two subtitle tracks stacked |
| `widgets/player/word_dictionary_popup.dart` | Wiktionary word lookup |
| `core/audio/surround_processor.dart` | Virtual surround audio |
| `widgets/player/watch_party_panel.dart` | Room create/join UI |

### Existing files to modify:
- `core/player/player_prefs.dart` — add: `accentColor`, `seekBarStyle`, `buttonShape`, `iconPack`, `controlsBgStyle`, `savedTheme`
- `widgets/player/quick_settings_panel.dart` — Style tab: color, seekbar, theme pickers
- `player_screen.dart` — wire all new prefs to UI elements

