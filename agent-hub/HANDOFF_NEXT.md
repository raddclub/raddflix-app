# agent-hub/HANDOFF_NEXT.md — Next Agent Handoff
> Generated: 2026-06-07 | Author: Replit Agent (session ending)
> **Read this AFTER AGENT_HANDOFF.md and BEFORE touching any code.**

---

## What happened this session

Two major workstreams completed:

### 1. Player Pass 1 Bug Fixes (TASK-022, commit `d2dd57e`)
Fixed 11 critical bugs in `player_screen.dart`:
- BUG-01: Volume boost NaN crash
- BUG-02: Audio session not released on dispose
- BUG-03: Double retry race condition on stream error
- BUG-04: Cast stale URL after seek
- BUG-05: Sleep timer paused but volume not restored
- BUG-06: Audio/subtitle track memory not cleared on new video
- BUG-07: Background play flag not synced to MediaSession
- BUG-14: Resume position ignored when `rememberPosition = false`
- LAYOUT-01: Skip Intro button breaking out of Positioned bounds
- LAYOUT-02: More Panel overflowing on short screens
- UX-01: Night Mode toggle in More Sheet not wiring to `_cinematicMode`

### 2. Player UI Customization — Pass 1 (TASK-023, commit `f0eb788`)
Three new features added to the player:

**A) Center Button Position** (`centerBtnPosition` pref):
- `'center'` — classic MX Player layout (centered, vertically adjustable)
- `'bottom'` — modern style: compact `[Prev] [⏪] [⏯] [⏩] [Next]` row at `Positioned(bottom: 84)`, screen centre completely clear
- `'hidden'` — center controls entirely hidden (cinema/immersive feel without locking)

**B) Quick Shortcut Bar** (`showQuickBar` + `quickBarItems` prefs):
- Thin icon row (46×40px tiles) above the seek slider
- 8 configurable slots: `pip`, `bgplay`, `fit`, `screenshot`, `speed`, `subtitle`, `lock`, `nightmode`
- Active state: accent-coloured border + tinted background
- `HapticFeedback.selectionClick()` on tap
- Per-slot toggles in Settings → Quick Shortcut Bar section

**C) Settings Screen** fully rewritten (`player_settings_screen.dart`):
- New "Controls Position" chip picker (Center / Bottom / Hidden)
- New "Quick Shortcut Bar" section with master toggle + 8 per-slot checkboxes

---

## Files changed this session

| File (GitHub path) | What changed | Commit |
|----|----|----|
| `raddflix_flutter/lib/screens/player_screen.dart` | Pass 1 bugs + center position + quick bar | d2dd57e, f0eb788 |
| `raddflix_flutter/lib/core/player/player_prefs.dart` | +3 new prefs (centerBtnPosition, showQuickBar, quickBarItems) | f0eb788 |
| `raddflix_flutter/lib/screens/player_settings_screen.dart` | Full rewrite with new sections | f0eb788 |
| `agent-hub/TASKS.md` | TASK-023 added, Pass 2 tasks added as TASK-024 through TASK-034 | this push |
| `agent-hub/HANDOFF_NEXT.md` | This file | this push |

---

## Files in /tmp (working copies — already pushed, do NOT re-use without re-downloading)

The `/tmp/` files from this session may be stale. Always re-download from GitHub:

```bash
# Download current player_screen.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/screens/player_screen.dart" \
  | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); const j=JSON.parse(d); require('fs').writeFileSync('/tmp/player_screen.dart', Buffer.from(j.content,'base64').toString('utf8'))"

# Download player_prefs.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/player/player_prefs.dart" \
  | node -e "const d=require('fs').readFileSync('/dev/stdin','utf8'); const j=JSON.parse(d); require('fs').writeFileSync('/tmp/player_prefs.dart', Buffer.from(j.content,'base64').toString('utf8'))"
```

---

## Next Agent: Immediate Tasks (Pass 2)

Pick up from TASKS.md "Current Sprint". Recommended order:

### Priority 1 — Quick wins (1-3 lines each)

**TASK-027: BUG-11 — Rage-skip fires during A-B loop**
```dart
// In _handleRageSkip() — add guard at top:
if (_abLoop.isActive) return;
```

**TASK-030: BUG-15 — Speed presets decimal inconsistency**
```dart
// In _SpeedItem label or wherever presets are formatted:
'${speed.toStringAsFixed(1)}×'  // always 1 decimal
```

**TASK-032: LAYOUT-03 — Quick bar overflow on small screens**
```dart
// In _QuickShortcutBar.build(), wrap Row in:
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: spaced),
)
```

### Priority 2 — Medium effort

**TASK-026: BUG-10 — Sleep timer resume**
In `_PlayerScreenState.didChangeAppLifecycleState`:
- When `resumed`: restore `_sleepTimer` from saved remaining seconds instead of resetting
- Store `_sleepRemainingSeconds` before pause, restore on resume

**TASK-033: UX-02 — Night Mode quick bar should set opacity**
In `_QuickShortcutBar`, the `onNightMode` callback calls `onToggleCinematic` (a `VoidCallback`).
Need to pass `accentColor` and opacity via a separate callback so toggling Night Mode via quick bar also applies `_prefs.cinematicOpacity` to `_cinematicOpacity`.

**TASK-034: CLEAN-01 — Remove duplicate `_bgPlayEnabled`**
In `_PlayerScreenState`:
- `_bgPlayEnabled` field is set by `onBgPlayToggle` callback from quick bar
- Verify this is the SAME field used by background playback logic
- If so, remove any duplicate or redundant sync code

### Priority 3 — Harder bugs

**TASK-024: BUG-08 — Subtitle sync per-track persistence**
When user changes subtitle track (`onSubtitleTracks`), the `subDelayMs` slider in `_MxSubPanel` resets to 0. Should:
1. Save `subDelayMs` keyed by track index (JSON map in PlayerPrefs)
2. Restore on track change

**TASK-025: BUG-09 — Audio delay unit display**
In `_MxAudioPanel`, the delay slider step is 1 unit but label shows "ms". Confirm what unit `audioDelayMs` is actually in; if frames, convert for display (`frames ÷ fps × 1000 = ms`).

**TASK-028: BUG-12 — Volume boost warning**
At `volumeBoostMultiplier > 1.5`:
- Show a brief `SnackBar` warning "High boost may distort audio"
- Hard cap at 3.0× (already in slider range? — verify)

**TASK-029: BUG-13 — PiP subtitle loss**
PiP surface in `player_screen.dart` uses `_controller.value` only. Subtitles rendered in Flutter overlay layer are NOT included in PiP surface. Mitigation:
- Set `MediaSession.setMetadata` with subtitle text as description (Android only, fallback)
- Or: use `Picture_in_Picture_params` API to include text overlay

**TASK-031: BUG-16 — Seek bar thumb on wave/film styles**
In `widgets/player/seek_bar_painter.dart`, `wave` and `film` CustomPainter subclasses don't call `super.drawThumb()`. Add explicit thumb circle draw at `thumbX` position.

---

## Key Code Locations (player_screen.dart — post f0eb788, ~6230 lines)

| Section | Approx Line | Description |
|---------|-------------|-------------|
| `_PlayerScreenState` class | ~180 | Master state + all fields |
| `_bgPlayEnabled` field | ~320 | Background play toggle state |
| `_sleepTimer` / sleep logic | ~850 | Sleep timer management |
| `_handleRageSkip()` | ~1100 | Rage skip — add A-B loop guard here |
| `_ControlsOverlay` call site | ~3060 | All pref params passed here |
| `_ControlsOverlay` class | ~3654 | Widget definition + all params |
| Center controls ternary | ~3974 | `centerBtnPosition` switch: bottom/center/hidden |
| Quick bar render | ~4247 | `if (showQuickBar && !locked) _QuickShortcutBar(...)` |
| Seek row (position/slider/duration) | ~4263 | Below quick bar |
| `_QuickShortcutBar` class | ~4597 | New widget — 8-slot shortcut bar |
| `_CenterAuxBtn` class | ~4580 | Prev/Skip/Next aux buttons |
| `_MxSeekBtn` class | ~4490 | Seek ±15s button |
| `_MxSideBtn` class | ~4530 | Right-strip vertical buttons |

---

## PlayerPrefs fields relevant to next tasks

```dart
// All these already exist in player_prefs.dart:
final double playbackSpeed;          // current speed
final String speedPresets;           // comma-sep: '0.25,0.5,...,3.0'
final double volumeBoostMultiplier;  // 1.0–3.0 (soft cap at 1.5 with warning)
final int    subtitleSyncOffsetMs;   // global sub delay (per-track not yet impl)
final int    audioTimingOffsetMs;    // audio delay in ms
final bool   rageSkipEnabled;        // rage-skip feature toggle
final int    rageSkipSeconds;        // seconds to skip on rage (default 120)
final bool   abLoopEnabled;          // whether A-B loop is turned on
final bool   backgroundPlayEnabled;  // BG play on/off
// Added this session:
final String centerBtnPosition;      // 'center' | 'bottom' | 'hidden'
final bool   showQuickBar;           // quick bar visibility
final String quickBarItems;          // 'pip,bgplay,fit,screenshot,speed,...'
```

---

## GitHub Push Recipe

Always use the Trees API for multi-file atomic commits:

```bash
# Write push script, edit OWNER/REPO/files list, then:
node /tmp/push_mychanges.js
```

Script template at `.agents/memory/push-pattern.md`.
Owner: `raddclub`, Repo: `raddflix-app`, Branch: `main`.

---

## Oracle SSH (for backend work only — not needed for player fixes)

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n', {mode:0o600});
console.log('key written');
"
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "echo ok"
```

---

## Definition of Done (for each Pass 2 bug)

1. Edit `/tmp/player_screen.dart` (re-download from GitHub first)
2. Verify the fix with a read of surrounding context
3. Update `agent-hub/TASKS.md` — mark task ✅ DONE
4. Push via Trees API — all changed files + updated TASKS.md in one commit
5. Update `agent-hub/HANDOFF_NEXT.md` with what was done
