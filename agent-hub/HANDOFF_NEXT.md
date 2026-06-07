# agent-hub/HANDOFF_NEXT.md — Next Agent Handoff
> Generated: 2026-06-07 | Author: Replit Agent (Pass 4 session)
> **Read this AFTER AGENT_HANDOFF.md and BEFORE touching any code.**

---

## What happened this session (Pass 4)

**Player screen full re-audit complete.** All 7 bugs across 4 passes are fixed.
Latest commit: `2ac9e8dc`

### Pass 4 fixes (this session)

**BUG-P-NEW-06** (Medium) — `_openVideoEnhanceSuite` cinematic toggle one-way
- Root cause: `if (map['cinematicMode'] as bool? ?? false) _toggleCinematic()` — only fired when value was `true`. If user turned cinematic OFF in the sheet, nothing happened.
- Fix: compare against `_cinematicMode`; call `_toggleCinematic()` only when value differs.

**BUG-P-NEW-07** (High) — Quick Bar "Night Mode" wired to wrong callback
- Root cause: `onNightMode: onToggleCinematic` in `_ControlsOverlay._QuickShortcutBar` call. Tapping "Night" silently toggled cinematic mode instead of the blue-light filter.
- Fix: added `onToggleNightMode` callback to `_ControlsOverlay`; wired from `_buildPlayerBody` with `_prefs.copyWith(nightMode: !_prefs.nightMode)` + save + `_applyVideoFilters()`.

### All player bugs — complete history

| ID | Severity | Status | Commit |
|----|---------|--------|--------|
| BUG-P-NEW-01 | HIGH | ✅ Fixed | `7802d53` |
| BUG-P-NEW-02 | MEDIUM | ✅ Fixed | `7802d53` |
| BUG-P-NEW-03 | HIGH | ✅ Fixed | `7802d53` |
| BUG-P-NEW-04 | CRITICAL | ✅ Fixed | `7802d53` |
| BUG-P-NEW-05 | HIGH | ✅ Fixed | `e9abc17` |
| BUG-P-NEW-06 | MEDIUM | ✅ Fixed | `2ac9e8dc` |
| BUG-P-NEW-07 | HIGH | ✅ Fixed | `2ac9e8dc` |

**`player_screen.dart` is clean. No remaining known bugs.**

---

## Files changed this session

| File | Change | Commit |
|------|--------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | BUG-P-NEW-06 + BUG-P-NEW-07 fixes | `2ac9e8dc` |
| `agent-hub/TASKS.md` | TASK-025 added to completed archive | `2ac9e8dc` |
| `.agents/tasks/BUG_TRACKER.md` | Pass 4 bugs appended | `2ac9e8dc` |
| `agent-hub/history/TASK_LOG.md` | Pass 4 session entry added | `2ac9e8dc` |
| All other agent-hub .md files | Updated to reflect audit completion | this push |

---

## Next Agent: Open Tasks

The player audit is complete. The open items below are **UI polish** (not bugs) and
**infrastructure tasks** (not player-related).

### Player polish (low urgency — not bugs)

**TASK-P01: Quick bar overflow on small screens**
```dart
// In _QuickShortcutBar.build(), wrap the Row in:
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: spaced),
)
```

**TASK-P02: Sleep timer resume position**
When app goes background and auto-pauses (bgPlay=false), `_sleepTimer` keeps counting.
On resume, remaining sleep time should be restored, not reset.
Store `_sleepRemainingSeconds` before `didChangeAppLifecycleState(paused)`, restore on `resumed`.

**TASK-P03: Volume boost warning**
At `volumeBoostMultiplier > 1.5`: show brief SnackBar "High boost may distort audio".
Hard cap at 3.0× (already enforced in slider range — just add the warning toast).

**TASK-P04: Seek bar thumb on wave/film styles**
`wave` and `film` CustomPainter subclasses in `seek_bar_painter.dart` don't draw the
thumb circle. Add explicit thumb draw at the current position.

### Infrastructure (backend/ops)

**OPEN-OPS-01: JazzDrive session expired**
Account 03286829827 needs OTP re-login via the Upload page on the admin panel.
Until fixed: uploads fail, keepalive fails, delta_push 401 errors every few minutes.

**OPEN-DATA-01: Missing episodes**
All Of Us Are Dead — E03/E04/E05/E09 not on JazzDrive. Need upload + catalog sync.

---

## Key Code Locations (player_screen.dart — post `2ac9e8dc`, 6265 lines)

| Section | Approx Line | Description |
|---------|-------------|-------------|
| `_PlayerScreenState` class | ~180 | Master state + all fields |
| `_openClipTrimmer()` | ~940 | ClipTrimmer A-B: onTrimChanged must call _abLoop.setA()/setB() |
| `_openVideoEnhanceSuite()` | ~1150 | VideoEnhanceSuite: cinematic compare-and-toggle pattern |
| `_ControlsOverlay` call site | ~3076 | All pref params + both night-mode callbacks passed here |
| `onToggleCinematic` wiring | ~3080 | → `_toggleCinematic` |
| `onToggleNightMode` wiring | ~3084 | → `_prefs.copyWith(nightMode:)` + save + `_applyVideoFilters()` |
| `_ControlsOverlay` class | ~3680 | Widget definition + all params |
| `onNightMode` in QuickShortcutBar | ~4294 | **Must be `onToggleNightMode`, NOT `onToggleCinematic`** |
| `_QuickShortcutBar` class | ~4617 | 8-slot shortcut bar |
| `_SleepPanel` class | ~4770 | Sleep timer options |
| `_MxBadge` class | ~4742 | Compact top-bar badge widget |

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

Use Trees API for multi-file atomic commits. Always:
1. Download the file fresh from GitHub before editing (never reuse stale /tmp copies)
2. Apply patches in Python (`str.replace()` with asserts)
3. Update tracker files (TASKS.md, BUG_TRACKER.md, TASK_LOG.md) in the same commit
4. Push all files at once via `pushTree` in a Node.js script

Owner: `raddclub`, Repo: `raddflix-app`, Branch: `main`.

---

## Oracle SSH (backend work only)

```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n', {mode:0o600});
console.log('key written');
"
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```
