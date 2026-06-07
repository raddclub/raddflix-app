# RaddFlix Player — New Feature Ideas
**Written by:** Replit Agent (handoff session)
**Date:** 2026-06-07
**Status:** Ideas only — none implemented. Each idea is fully specced for the next agent to pick up.

> These are completely new features. None of them exist in VLC, MX Player, Infuse, Plex, or any mainstream mobile player as of this writing. Each idea is rated by implementation difficulty and user impact.

---

## IDEA-01 — Universal Subtitle Hunter 🔍
**(Requested by user — highest priority)**

### What it does
Right now the player finds subtitles only if they are in the **same folder as the video** with a matching filename. IDEA-01 makes the player able to find subtitles **anywhere on the device**, including:

- Any folder in internal storage or SD card
- Inside `.zip`, `.rar`, `.7z` archive files (extract-and-scan)
- Inside sub-folders (recursive)
- Downloaded from a URL pasted by the user
- Scanned via QR code that points to a subtitle URL

### How it works — step by step

#### Step 1 — Fuzzy Filename Index
When a video starts playing, the player launches a background isolate that:
1. Walks the entire device file tree (using `path_provider` + `permission_handler` for storage access)
2. Collects every `.srt`, `.ass`, `.ssa`, `.vtt`, `.sub`, `.sbv` file it finds
3. Scores each subtitle file against the current video filename using **Levenshtein distance** + **token overlap** (e.g. `Movie.Name.2024.720p.BluRay` → tokens `['movie','name','2024','720p','bluray']`)
4. Returns the top 5 matches ranked by score

#### Step 2 — Archive Extraction
For every `.zip`, `.rar`, `.7z` file on the device:
1. Peek the archive's file list without fully extracting (fast)
2. If any entry matches the subtitle extension list, score it
3. If score is above threshold, extract ONLY that entry to a temp dir `/data/user/0/…/cache/subtitles/`
4. Load from temp path

#### Step 3 — User Confirmation Sheet
Show a bottom sheet: "Found 3 possible subtitle files — which one?" with:
- Ranked list with confidence % and file location
- Preview: first 5 subtitle lines
- One-tap load button

#### Step 4 — URL / QR Subtitle Loader
In the subtitle sheet, add:
- Paste URL field → download subtitle to cache → load
- QR code scanner button → scan → load from URL
- Works with OpenSubtitles direct download links, GitHub raw URLs, etc.

### Flutter implementation notes
- Use `archive` package (already common in Flutter) for ZIP extraction
- Use `flutter_file_utils` or manual `Directory.list(recursive: true)` for file walking
- Run file walk in a `compute()` isolate to avoid jank
- Cache the index for 60 seconds so replaying same video is instant
- Storage permission: `READ_EXTERNAL_STORAGE` (Android) — already likely granted

### Files to create/modify
- `lib/core/subtitles/subtitle_hunter.dart` — new file, the entire hunter logic
- `lib/core/subtitles/subtitle_hunter_sheet.dart` — UI bottom sheet
- `lib/screens/player_screen.dart` — call `SubtitleHunter.findForVideo(videoPath)` at init
- `pubspec.yaml` — add `archive: ^3.x` if not present

### Difficulty: 🟠 Medium (3–4 days)
### User impact: 🔥 Extremely high — biggest subtitle pain point for Pakistani users who have mixed folder structures

---

## IDEA-02 — Gesture Macro Recorder 🎮
**(Completely original — no other player has this)**

### What it does
Users can **record a sequence of player actions** (change speed, enable night mode, jump forward 30s, set brightness to 80%) and save it as a single named shortcut. Then trigger the whole macro with one tap or one custom gesture.

Example macros:
- **"Study Mode"** → Speed 0.75x + Subtitles ON + Night Mode ON + No autoplay
- **"Cinema Mode"** → Speed 1.0x + Subtitles OFF + Cinematic Mode ON + DND ON + Max brightness
- **"Binge Mode"** → Speed 1.5x + Skip Intro ON + Autoplay ON + Sleep timer 90 min

### How it works

#### Recording
1. User opens Quick Settings → taps "Record Macro"
2. Player enters **macro recording state** (red dot indicator in corner)
3. Every action the user takes (speed change, toggle, seek, etc.) is appended to a `List<MacroAction>` log with the delta value
4. User taps "Stop Recording" → names the macro
5. Macro saved as JSON in SharedPreferences

#### Playback
- Macros appear in the Quick Bar as custom items
- Long-press macro → edit or delete
- One tap → all actions execute in sequence with 150ms delay between each (smooth animation)

#### Trigger options
- Quick Bar tap (default)
- Double-tap volume button
- Shake device
- Custom swipe gesture (from edge)

### Data model
```dart
class MacroAction {
  final String type;    // 'speed', 'toggle', 'seek', 'brightness', etc.
  final dynamic value;  // 1.5, true, 30, 0.8, etc.
  final String label;   // human-readable description
}

class PlayerMacro {
  final String id;
  final String name;
  final String icon;
  final List<MacroAction> actions;
}
```

### Files to create/modify
- `lib/core/player/player_macro.dart` — data model + JSON serialization
- `lib/core/player/macro_recorder.dart` — recording state machine
- `lib/screens/player_screen.dart` — intercept actions during recording
- `lib/widgets/macro_editor_sheet.dart` — UI to name/edit macros
- `player_prefs.dart` — add `String macrosJson` field

### Difficulty: 🟠 Medium (4–5 days)
### User impact: 🔥 High — power users will love this; makes RaddFlix feel like a PRO tool

---

## IDEA-03 — AI Scene Mood Sync 🎨
**(Completely original)**

### What it does
The player **analyzes the video in real-time** (every 2 seconds) to detect the emotional tone of the current scene, then automatically:
- Adjusts **ambilight color temperature** (cool blue for action, warm amber for romance, deep red for horror)
- Adjusts **haptic pattern** (strong pulse on jump scares, gentle throb for tension, nothing for quiet dialogue)
- Adjusts **UI accent color** to match the dominant scene color

### How it detects mood
Uses only on-device signals — no AI API needed:
1. **Audio RMS energy** — high energy → action/excitement
2. **Audio frequency band** — dominant bass → action/horror; dominant mid → dialogue; dominant treble → suspense
3. **Average frame brightness** — very dark (< 30 avg) → horror/noir; bright (> 180 avg) → comedy/romance
4. **Frame color temperature** — warm dominant hue → romance; cool → thriller
5. Combine all 4 signals into a `SceneMood` enum: `action`, `romance`, `horror`, `dialogue`, `suspense`, `neutral`

### Mood → Output mapping
| Mood | Ambilight | Haptic | Accent |
|------|-----------|--------|--------|
| action | Cool blue + fast sample | Medium pulse every 500ms | Blue |
| romance | Warm amber | None | Amber |
| horror | Deep red, slow fade | Random short pulse | Red |
| dialogue | Neutral warm | None | Unchanged |
| suspense | Dim purple | Slow increasing pulse | Purple |
| neutral | Auto (current behavior) | None | Unchanged |

### User control
- Toggle in Quick Settings: "Mood Sync ON/OFF"
- Sensitivity slider: how aggressively it overrides user settings
- User can pin specific overrides: "Always keep ambilight color fixed"

### Files to create/modify
- `lib/core/player/scene_mood_analyzer.dart` — the analysis logic (runs in isolate, uses FFT for audio)
- `lib/core/player/ambilight_controller.dart` — already exists; extend with mood input
- `player_prefs.dart` — add `moodSyncEnabled`, `moodSyncSensitivity`
- `lib/screens/player_screen.dart` — start/stop analyzer with player state

### Difficulty: 🔴 Hard (1–2 weeks for full quality)
### User impact: 🔥🔥 Extremely high — this is genuinely the most impressive feature possible. No player in the world does this.

---

## IDEA-04 — Offline Watch Party 📡
**(Completely original — no other player has LAN-only sync)**

### What it does
Two or more phones on the **same WiFi network** (or hotspot — no internet needed) can watch the exact same video file in perfect sync. One phone is the **Host**, others are **Guests**.

- Host play/pause → all guests play/pause simultaneously
- Host seeks to 45:30 → all guests jump to 45:30
- Host changes speed → all guests change speed
- Latency compensation: each device reports its ping to the host; host sends timestamps accounting for delay

### No chat, no accounts, no internet — just sync.

### How it works
#### Host side
1. Broadcasts a UDP discovery beacon on port 5555 every 2 seconds: `{"type":"raddflix_party","host":"iPhone of Ali","code":"TIGER"}`
2. Accepts TCP connections from guests
3. Every playback event → broadcasts JSON event to all connected sockets
4. Periodically sends `{"type":"heartbeat","pos_ms":45300,"playing":true}` so late-joining guests can catch up

#### Guest side
1. Scans local network for UDP beacons (no manual IP entry)
2. Shows list: "RaddFlix Watch Party found: Ali's phone (code: TIGER)"
3. Taps join → TCP connection established
4. Local player is now in "slave mode" — ignores local seek/play unless guest explicitly overrides
5. Guest can optionally "break free" (watch independently) and re-sync

#### Zero-internet proof
- Works entirely over local UDP/TCP
- No server, no relay, no Firebase
- Works on airline WiFi, mobile hotspot, home router

### Files to create/modify
- `lib/core/watch_party/party_host.dart` — UDP beacon + TCP server
- `lib/core/watch_party/party_guest.dart` — UDP scanner + TCP client
- `lib/core/watch_party/party_event.dart` — event data model
- `lib/screens/player_screen.dart` — integrate event dispatch + receive
- `lib/widgets/watch_party_sheet.dart` — join/host UI

### Difficulty: 🟠 Medium (5–7 days)
### User impact: 🔥🔥 Very high — families watching together is a HUGE use case in Pakistan

---

## IDEA-05 — Cinematic Frame Capture + Story Export 📸
**(New — no player has this)**

### What it does
Triple-tap anywhere on the paused video → the current frame is captured as a **cinematic still**:

1. Auto-crops to 2.39:1 (ultra-wide cinematic ratio) with smooth black bars
2. Applies a subtle film grain overlay matching the current `filmGrainLevel` setting
3. Adds a very subtle vignette
4. Overlays the video title and timestamp (like a movie still) in a stylish lower-left caption
5. One-tap share: formatted perfectly for Instagram Story (9:16) with the cinematic still centered on a blurred background of itself
6. Or save to gallery as a high-quality PNG

### Makes every video look like a movie promotional still.

### Technical approach
- Use `VideoThumbnail` package to extract current frame as `Uint8List`
- Manipulate with `dart:ui` Canvas: crop, grain, vignette, text overlay
- Encode to PNG with `image` package
- Share via `share_plus`

### Difficulty: 🟢 Easy (2–3 days)
### User impact: 🔥 High — very sharable, makes RaddFlix look premium

---

## IDEA-06 — Subtitle Personality Engine 💬
**(Completely original)**

### What it does
Subtitles are boring — same font, same size, every line. This feature makes subtitles **adapt their visual style** based on what the line says:

| Subtitle content | Visual style |
|-----------------|--------------|
| ALL CAPS line (shouting) | Bold, 20% larger, slight red tint on outline |
| `...` ending (trailing off) | Italic, slightly faded opacity |
| `[whispering]` or `(quietly)` | Tiny font (70%), italicized, no outline |
| `?!` ending (shock) | Bold + brief scale-up bounce animation on appear |
| Long line (> 80 chars) | Compact 2-line layout, smaller font |
| Short 1-2 word line | Large bold center — emphasis |
| `[MUSIC NOTE]` or `♪` | Italic + soft gradient background |

### How it works
- Parse each incoming subtitle line through a `SubtitlePersonalityParser`
- Returns a `SubtitleStyle` override (font size multiplier, bold, italic, color, animation type)
- Applied in the subtitle rendering widget

### User control
- Toggle: "Subtitle Personality ON/OFF"
- Intensity slider: 0% = no change, 100% = full effect

### Files to create/modify
- `lib/core/subtitles/subtitle_personality.dart` — new parser
- `lib/widgets/subtitle_overlay.dart` — apply dynamic styles
- `player_prefs.dart` — add `subtitlePersonalityEnabled`, `subtitlePersonalityIntensity`

### Difficulty: 🟢 Easy (2–3 days)
### User impact: 🔥 High — feels magical, completely unique

---

## IDEA-07 — Player Skin Palette Generator 🎨
**(Completely original)**

### What it does
User takes a **photo or screenshot of anything** — a movie poster, a painting, a website, a WhatsApp chat wallpaper — and the app **automatically generates a complete player skin** from the color palette:

- Extracts 5 dominant colors
- Maps them to: accent color, seek bar color, controls background tint, icon color, text color
- Generates a live preview of what the player would look like
- One-tap apply

### Technical approach
- Use `palette_generator` Flutter package (Google-made, very reliable)
- Map dominant colors → player theme JSON
- Live preview using existing `playerTheme` system (which already exists in `player_prefs.dart`)

### Difficulty: 🟢 Easy (2 days) — `palette_generator` does all the hard work
### User impact: 🔥 High — extremely Instagram-worthy, zero other player offers this

---

## IDEA-08 — Phonetic Subtitle Overlay 🔤
**(Unique to Pakistani/South Asian market)**

### What it does
For Urdu, Arabic, or Hindi subtitle text, show a **Roman Urdu transliteration** (phonetic reading guide) as a second smaller line below the main subtitle:

```
آپ کیسے ہیں؟
Aap kaise hain?
```

This helps:
- Urdu learners who understand spoken Urdu but can't read Nastaliq script
- Diaspora Pakistanis who speak Urdu but read Roman Urdu
- Non-Urdu speakers learning the language

### How it works
- Detect subtitle language from `.srt` metadata or character set heuristic (Arabic Unicode range)
- Apply a transliteration map (Urdu → Roman) — this is a well-known algorithm, not AI
- Render as a second subtitle row in smaller italic font
- Toggle: "Phonetic Guide ON/OFF"

### Difficulty: 🟠 Medium (3–4 days for the transliteration table)
### User impact: 🔥🔥 Extremely high for Pakistani market — **no other player in the world has this**

---

## Implementation Priority Order (recommended)

| Priority | Feature | Reason |
|----------|---------|--------|
| 1 | IDEA-01 Universal Subtitle Hunter | User specifically requested; highest pain point |
| 2 | IDEA-06 Subtitle Personality | Easiest, highest wow factor, 2-3 days |
| 3 | IDEA-07 Player Skin Palette Generator | Easiest, very sharable, 2 days |
| 4 | IDEA-05 Cinematic Frame Capture | Easy + very sharable, 2-3 days |
| 5 | IDEA-08 Phonetic Subtitle Overlay | Unique market differentiator |
| 6 | IDEA-02 Gesture Macro Recorder | Power user feature |
| 7 | IDEA-04 Offline Watch Party | High impact but needs testing |
| 8 | IDEA-03 AI Scene Mood Sync | Most impressive but hardest |

---

## Handoff Notes for Next Agent

- All existing player prefs infrastructure is in `raddflix_flutter/lib/core/player/player_prefs.dart`
- The player screen is `raddflix_flutter/lib/screens/player_screen.dart` (6,353 lines after Pass 6 fixes)
- Ambilight controller already exists — IDEA-03 extends it
- Quick Bar system already exists in player_screen.dart (`showQuickBar`, `quickBarItems` in PlayerPrefs)
- Subtitle overlay widget already exists — IDEA-06 extends it
- `playerTheme` field already exists in PlayerPrefs (String) — IDEA-07 generates values for it
- Film grain already exists as `filmGrainLevel` — IDEA-05 uses it for frame capture style
- All new `PlayerPrefs` fields must be added to all 5 locations: field, constructor, copyWith, load(), save()
- Always commit via GitHub Trees API (no git shell access)
- Repo: `raddclub/raddflix-app`, branch: `main`
- Task tracking: `agent-hub/TASKS.md` + `agent-hub/history/TASK_LOG.md`
- Read `agent-hub/RULES.md` before starting any task
