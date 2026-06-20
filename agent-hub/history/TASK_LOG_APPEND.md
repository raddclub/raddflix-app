# TASK_LOG_APPEND — 2026-06-17
> Staging area. Merged into TASK_LOG.md at session end.

## Session 2026-06-17 — Player UX: 8 MX Player Layout Improvements

### Commits
- `01fc775f` — feat(player): add sidebarMode pref + default rotation → auto
- `bd75f9d6` — feat(player): floating ball, sidebar 3-state, speed track, side panels, clock, auto-rotate

### 8 Improvements Delivered
1. Floating draggable ball — white circle, tap=controls, drag=reposition
2. Sidebar 3-state — full→icons-only→hidden (chevron toggle at top of rail)
3. Sidebar state memory — sidebarMode int persisted in SharedPreferences
4. Clock overlay — top-right white70, always visible when controls hidden, 30s timer
5. Subtitle+Audio panels → right-side overlays (320px, black26 scrim)
6. Speed picker → horizontal dot-rail (#4DB6FF active, white38 inactive)
7. Default rotation → auto (was sensor_landscape)
8. _MxSideBtn icons-only mode (36×36, icon 19px, no label)

### Verification
- 25/25 checks passed before push
- player_prefs.dart: 1152→1158 lines
- player_screen.dart: 6963→7087 lines

---
## Session: player-ux-fixes-2 — 2026-06-20
**Commit**: `2d9b2c8eebdb646d82f89496fc3ed0dfee188656`
**File**: `raddflix_flutter/lib/screens/player_screen.dart` (5126 to 5151 lines)
**Method**: 4 parallel subagents, sequential patch application, single push

### 22 Fixes Applied

**Visual Panel Fixes (Agent A)**
- V2: Audio track radio buttons changed to leading alignment (no longer detached at bottom)
- V3: Preset grid 2-col to 3-col, aspectRatio 2.2 to 1.8 (no more double-height Original card)
- V9: Track labels now show language and title with proper fallbacks
- G4: Removed fake Show battery level toggle from Settings

**Overlay & Button UX (Agent B)**
- V6: Volume/brightness pill narrowed (margins 0.18 to 0.28, smaller padding)
- V16: Volume icon now has 4 states: mute / low / normal / boost above 100%
- U10: Speed label 2.0x now shows as 2x (whole numbers truncated)
- U1/U2: _RaddIconBtn wrapped in Material+InkWell for tap ripple feedback
- B3: PiP failure now shows informative toast instead of Navigator.pop()

**Bug Fixes — Audio Lab + Subtitle (Agent C)**
- B5: Vocal Remover pan filter fixed (FL/FR notation replaced with correct c0/c1)
- B6: Dialogue Boost equalizer fixed (proper 10-band 2-5kHz boost string)
- G9: Subtitle online loading spinner now resets to false after snackbar
- G5: Subtitle Scale slider wired to MPV sub-scale property
- G6: Subtitle Fade slider wired to MPV sub-ass-fade-in-time
- B2: Auto-advance banner now shows live 3-2-1 countdown with Cancel button

**More Panel & Ghost Settings (Agent D)**
- D2-D4: Removed 3 duplicate ListTiles (Smart Enhance, One-Handed, Settings) from More panel
- G1-G3: Skip buttons and prev/next visibility toggles wired to real player state via callbacks
- G11: Settings panel brightness slider now initialises from current player brightness value

### Remaining Known Issues
- V1: Coffee icon third-party floating button (Android overlay, needs native investigation)
- V4: Smart Enhance icon looks fragmented (icon asset redesign needed)
- V5: Vertical seek bar in portrait mode (deeper layout refactor required)
- V8: Subtitle and audio panels have large empty space (content redesign needed)
- V10-V15: Portrait-mode layout polish items
