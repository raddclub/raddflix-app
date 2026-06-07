# agent-hub/HANDOFF_NEXT.md — Next Agent Handoff
> Generated: 2026-06-07 | Author: Replit Agent (Pass 5 session — Player Feature Sprint)
> **Read this AFTER AGENT_HANDOFF.md and BEFORE touching any code.**

---

## What happened this session (Pass 5 — Player Feature Sprint)

Four new player features implemented across TASK-029 → TASK-032.
All committed via GitHub Trees API. Latest commit: `034938fb`
Player screen: `player_screen.dart` (275 KB, ~6,440+ lines)

### Features shipped this session

| Task | Feature | Commit |
|------|---------|--------|
| TASK-029 | Universal Subtitle Hunter | prior session |
| TASK-030 | Layout & HUD Settings Sheet v1 | `cd8bcd83` |
| TASK-031 | Layout & HUD Settings Sheet v2 (full rewrite) | `0a4c3c58` |
| TASK-032 | Smart Enhance — MX-style AI video enhancement | `034938fb` |

---

## TASK-029 — Universal Subtitle Hunter
**Status:** ✅ Complete

New files:
- `lib/core/subtitles/subtitle_hunter.dart` — recursive file walk, fuzzy match, archive extract
- `lib/core/subtitles/subtitle_hunter_sheet.dart` — bottom sheet UI with ranked results
- `archive` package added to pubspec.yaml for ZIP/RAR scanning

Wired into player_screen.dart: subtitle icon opens hunter when no embedded subs found.

---

## TASK-030 — Layout & HUD Settings Sheet v1
**Status:** ✅ Complete (superseded by v2, still in history)

New file: `lib/widgets/player/player_hud_settings_sheet.dart` (758 lines, v1)
Wired via "Layout & HUD" button in _MxMoreSheet.

---

## TASK-031 — Layout & HUD Settings Sheet v2
**Status:** ✅ Complete | Commit: `0a4c3c58`

Full rewrite (1145 lines) of `lib/widgets/player/player_hud_settings_sheet.dart`:
- **Layout preset strip**: Netflix / MX Classic / Minimal / Binge / Custom chips
- **Per-orientation tabs**: Portrait / Landscape — independent prefs per orientation
- **Drag-to-reorder Quick Bar**: `ReorderableListView` with drag handles
- **Dedup guard**: amber warning when subtitle added to Quick Bar (already in top bar)
- **Button shape switcher**: Circle / Squircle / Rounded / Pill / Sharp — each previews its shape
- **MX-style auto-rotation**: `didChangeMetrics()` override tracks which physical side user
  flipped to via safe-area padding heuristic; `sensor_landscape` snaps to that exact side.
  `_lastLandscapeSide` state variable persists between flips.

PlayerPrefs fields added (TASK-031):
- `centerBtnScale`, `centerBtnVerticalOffset`, `centerBtnIconOnly`, `centerBtnBgOpacity`
- `showCenterPrev`, `showCenterSkip`, `showCenterNext`, `centerBtnPosition`
- `showQuickBar`, `quickBarItems`, `buttonShape`, `layoutPreset`, `layoutJson`

---

## TASK-032 — Smart Enhance (MX-style AI Video Enhancement)
**Status:** ✅ Complete | Commit: `034938fb`

New files:
- `lib/core/player/smart_enhance.dart` — `SmartEnhancePreset` class + `kSmartEnhancePresets` (8 modes)
- `lib/widgets/player/smart_enhance_sheet.dart` — full MX-style panel (655 lines)

8 content modes: Standard / Movie / Sports / Anime / Low Light / AMOLED / Drama / Documentary
Each preset defines: brightness/contrast/saturation/hue deltas + sharpness + noiseReduce flag

Panel features:
- Master ON/OFF toggle with green glow ring
- 8-card mode grid (3 cols) — selecting any mode auto-enables Smart Enhance
- "What's Applied" badge chips showing actual values per mode
- Intensity slider: Subtle → Max (0.5×–1.5× multiplier on preset deltas)
- Before/After hold button — hold to bypass enhance and see original video live

`_buildVfString` in player_screen.dart extended to merge Smart Enhance deltas with user eq:
- brightness/contrast/saturation/hue stacked + clamped to MPV limits
- sharpness = (user + se delta) clamped 0–1.5
- `hqdn3d` noise filter appended when Low Light mode active

PlayerPrefs fields added (TASK-032):
- `smartEnhanceEnabled` (bool, default: false)
- `smartEnhanceMode` (String, default: 'standard')

---

## Key Code Locations (player_screen.dart — post `034938fb`, ~6,440 lines)

| Section | Approx Line | Description |
|---------|-------------|-------------|
| `_PlayerScreenState` fields | ~180 | All state vars incl. `_showHudSettings`, `_showSmartEnhance`, `_lastLandscapeSide` |
| `_buildVfString()` | ~527 | Video filter chain builder — Smart Enhance merged here |
| `_applyVideoFilters()` | ~655 | Debounced async caller for `_buildVfString` |
| `_openHudSettings()` | ~1194 | Opens HUD settings sheet |
| `_openSmartEnhance()` | ~1201 | Opens Smart Enhance sheet |
| `didChangeMetrics()` | ~261 | MX-style rotation side detection |
| `_MxMoreSheet` class | ~5310 | More panel — has both "Layout & HUD" and "Smart Enhance" buttons |
| Smart Enhance overlay | ~3820 | `if (_showSmartEnhance) SmartEnhanceSheet(...)` in Stack |
| HUD Settings overlay | ~3832 | `if (_showHudSettings) PlayerHudSettingsSheet(...)` in Stack |

---

## PlayerPrefs — All new fields added this session

```dart
// Quick Bar / Layout (TASK-031)
final double  centerBtnScale;           // default: 1.0
final double  centerBtnVerticalOffset;  // default: 0.0
final bool    centerBtnIconOnly;        // default: false
final double  centerBtnBgOpacity;       // default: 0.3
final bool    showCenterPrev;           // default: false
final bool    showCenterSkip;           // default: false
final bool    showCenterNext;           // default: true
final String  centerBtnPosition;        // 'center' | 'bottom' | 'hidden'
final bool    showQuickBar;             // default: true
final String  quickBarItems;            // comma-sep slot IDs
final String  layoutPreset;             // 'netflix'|'mx'|'minimal'|'binge'|'custom'
final String  layoutJson;               // serialized per-orientation prefs

// Smart Enhance (TASK-032)
final bool    smartEnhanceEnabled;      // default: false
final String  smartEnhanceMode;         // 'standard'|'movie'|'sports'|'anime'|'low_light'|'amoled'|'drama'|'documentary'
```

All fields wired in: field decl → constructor default → copyWith param+body → load() → save()
SharedPrefs keys all prefixed with `${_p}` (player key prefix).

---

## Next Agent — Suggested Features (from PLAYER_FEATURE_IDEAS.md)

Easiest + highest impact remaining:

### IDEA-06 — Subtitle Personality Engine (2–3 days, Easy)
Subtitles visually adapt their style based on content:
- ALL CAPS → bold + larger + slight red tint
- `...` trailing off → italic + faded
- `[whispering]` → tiny + italic + no outline
- `?!` shock → brief scale-up bounce animation
- `♪` music → italic + soft gradient background
Files: `lib/core/subtitles/subtitle_personality.dart` + extend subtitle overlay widget

### IDEA-07 — Player Skin Palette Generator (2 days, Easy)
User photos a poster → app extracts palette → generates entire player color scheme.
Uses `palette_generator` Flutter package (Google-made).
`playerTheme` field already exists in PlayerPrefs.

### IDEA-05 — Cinematic Frame Capture + Story Export (2–3 days, Easy)
Triple-tap paused video → 2.39:1 crop + film grain + vignette + title/timestamp caption.
One-tap export as Instagram Story format (9:16).
Uses `VideoThumbnail` + `dart:ui` Canvas + `share_plus`.

### IDEA-08 — Phonetic Subtitle Overlay (3–4 days, Medium)
For Urdu/Hindi subtitles: show Roman Urdu transliteration as a second row below main subtitle.
Huge differentiator for Pakistani market. No other player has this.

### IDEA-02 — Gesture Macro Recorder (4–5 days, Medium)
Record a sequence of player actions → save as named macro → trigger with one tap.
Example: "Study Mode" → Speed 0.75x + Subs ON + Night Mode ON + No autoplay.

---

## Open Ops Issues (unchanged from previous handoff)

- **OPEN-OPS-01**: JazzDrive session expired — account 03286829827 needs OTP re-login
  Until fixed: uploads fail, keepalive fails, delta_push 401 errors
- **OPEN-DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from JazzDrive

---

## Download fresh player_screen.dart

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/screens/player_screen.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/ps.dart','wb').write(base64.b64decode(d['content']))"
echo "Lines: $(wc -l < /tmp/ps.dart)"
```

---

## GitHub Push Recipe

Use Trees API for multi-file atomic commits:
1. `GET /repos/{owner}/{repo}/git/refs/heads/main` → commitSha
2. `GET /repos/{owner}/{repo}/git/commits/{commitSha}` → treeSha
3. `POST /git/blobs` for each file → blobSha
4. `POST /git/trees` with base_tree + new items → newTreeSha
5. `POST /git/commits` → newCommitSha
6. `PATCH /git/refs/heads/main` → update HEAD

Owner: `raddclub`, Repo: `raddflix-app`, Branch: `main`.
**NEVER use git shell commands.**
