# RaddFlix — New Agent Handoff Prompt
> Copy this ENTIRE prompt and give it to the new Replit account agent to start from.
> Last Updated: 2026-06-01

---

## THE PROMPT (copy everything below this line)

---

You are continuing work on **RaddFlix** — a Pakistani streaming platform with a custom Flutter video player. The goal is to make the most advanced, customizable video player in the world — beating MX Player, VLC, and all others.

## STEP 1 — Read these 4 files from GitHub FIRST (no code before this):

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/FEATURES_ROADMAP.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/PLAYER_SPEC.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md"
```

## STEP 2 — GitHub API access

All file pushes go via GitHub API (no git CLI). The GitHub token is stored in your Replit Secrets as `GITHUB_TOKEN`. Never use shell git commands.

```python
import urllib.request, base64, json, os

TOKEN = os.environ.get("GITHUB_TOKEN", "")   # ← from Replit Secrets
REPO  = "raddclub/raddflix-app"
BASE  = "https://api.github.com"
HEADERS = {
    "Authorization": f"token {TOKEN}",
    "Content-Type": "application/json",
    "Accept": "application/vnd.github.v3+json"
}

def get(path):
    req = urllib.request.Request(f"{BASE}/repos/{REPO}/contents/{path}", headers=HEADERS)
    with urllib.request.urlopen(req) as r:
        d = json.loads(r.read())
        return d["sha"], base64.b64decode(d["content"]).decode()

def push(path, content_str, sha, msg):
    payload = json.dumps({
        "message": msg,
        "content": base64.b64encode(content_str.encode()).decode(),
        "sha": sha, "branch": "main"
    }).encode()
    req = urllib.request.Request(
        f"{BASE}/repos/{REPO}/contents/{path}",
        data=payload, headers=HEADERS, method="PUT"
    )
    with urllib.request.urlopen(req) as r:
        d = json.loads(r.read())
        print(f"OK → {d['content']['sha'][:12]}  {path}")
```

To read any file (no token needed for public repo):
```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/<path>"
```

## STEP 3 — Current State (as of 2026-06-01)

The player is fully functional with:
- MX Player UI (4521-line `player_screen.dart`)
- 3 modes: Normal / Cinematic (opacity-based) / Immersive (one-tap pause)
- **Cinematic opacity slider** (15%–100%, live preview in settings sheet) — just completed
- Full Quick Settings (5 tabs), EQ panel, More Sheet (16 items), Audio/Subtitle panels

## STEP 4 — What the user wants next

**Primary goal**: Make this the world's most customizable video player.

The user's exact request:
> "make it as customizable as possible like each user can design their own video player — world number 1 controllable — like girls can make it pink/yellow — more stylish seek lines different kinds — most advanced player that beats MX Player, VLC, and all others"

### Priority tasks (from FEATURES_ROADMAP.md Sprint 1):

**Task 1 — Accent Color System** (highest impact):
- Add `accentColor` to `PlayerPrefs` (`core/player/player_prefs.dart`)
- Create `widgets/player/color_picker_sheet.dart` — 24-color swatch grid + custom hex input
- Add "Player Color" row to Quick Settings → Style tab
- Wire `accentColor` to: seek bar fill, play button ring, active chips, mode indicators, all blue/red accents

**Task 2 — Seek Bar Styles** (most visually impressive, never seen in MX/VLC):
- Add `seekBarStyle` enum to `PlayerPrefs`
- Create `widgets/player/seek_bar_painter.dart` — CustomPainter with 10 styles:
  classic, materialBold, gradientGlow, waveform, neonRgb, filmstrip, chapters, dots, circular, minimal
- Add seek bar style picker to Quick Settings → Style tab (horizontal preview strip)

**Task 3 — Bundled Themes** (instant wow — "Sakura" makes entire player pink):
- Create `core/player/player_theme.dart` — theme data class
- 8 built-in themes: RaddFlix Red, Midnight Purple, **Sakura Pink**, Gold Class, Matrix Green, Ocean Cyan, Sunset Orange, Snow White
- Create `widgets/player/theme_picker_sheet.dart` — grid of theme cards with live preview
- Selecting "Sakura" → pink accent + waveform seek bar + pill buttons

## STEP 5 — Key rules

1. **NEVER delete `radd-hub/hub/_legacy/`**
2. **ALWAYS append to `agent-hub/history/TASK_LOG.md`** at end of every session
3. **Read every file before editing** — `player_screen.dart` is 4521 lines
4. All file pushes via GitHub API only (no git CLI)
5. After major work: update `REINCARNATION.md` → IMMEDIATE STATUS section

## STEP 6 — Key file paths

| File | Lines | Purpose |
|------|-------|---------|
| `raddflix_flutter/lib/screens/player_screen.dart` | 4521 | Main player state machine |
| `raddflix_flutter/lib/core/player/player_prefs.dart` | ~200 | Add accentColor, seekBarStyle here |
| `raddflix_flutter/lib/widgets/player/quick_settings_panel.dart` | ~600 | Style tab needs color + seekbar rows |
| `raddflix_flutter/lib/widgets/player/cinematic_settings_sheet.dart` | 397 | Cinematic/Immersive settings + opacity slider |
| `raddflix_flutter/lib/widgets/player/immersive_overlay.dart` | ~180 | Immersive mode widget |
| `agent-hub/FEATURES_ROADMAP.md` | 542 | Full 12-phase feature plan — read this! |
| `agent-hub/PLAYER_SPEC.md` | 181 | Player architecture, mode system, gesture map |
| `agent-hub/history/TASK_LOG.md` | — | Session history — append after every session |

## STEP 7 — What "done" looks like

A user should be able to:
1. Open player → Quick Settings → Style → choose "Sakura" theme → entire player turns pink instantly
2. Tap "Seek Bar Style" → pick "Gradient Glow" → seek bar becomes a pink-to-purple glowing gradient
3. Pick "Pill" button shape → all buttons become pill-shaped
4. Long-press Night Mode in More Sheet → opacity slider 15%–100% live preview
5. Every colored element (seek bar, play button, chip borders, mode icons) follows the accent color

## STEP 8 — Complete feature vision

Read `agent-hub/FEATURES_ROADMAP.md` for the full 12-phase vision:
- Phase A: UI Theme Engine (color, seek bar styles, icons, button shapes, skins)
- Phase B: Drag & Drop Control Layout Designer
- Phase C: Full Gesture Remapping
- Phase D: Video Science (Picture Profiles, LUTs, Film Grain)
- Phase E: Audio Lab (Surround, Karaoke/Vocal Remover, Dialogue Boost)
- Phase F: Subtitle World (Dual-track, Word Dictionary, Karaoke mode, Export)
- Phase G: Smart/AI Features (Scene Detection, Skip Silence, Smart Subtitle Positioning)
- Phase H: Mobile-First Features (One-Handed Mode, Floating Mini Player)
- Phase I: Social (Watch Party Rooms, Reaction Stamps)
- Phase J: Accessibility (Voice Commands, Color Blind Modes, Dyslexia Font)
- Phase K: Privacy (Private Screen Mode, Screenshot Lock)
- Phase L: Video Frame Features (Zoom Region, Frame Export)
