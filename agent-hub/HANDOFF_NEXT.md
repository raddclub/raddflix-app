# Handoff — Next Agent
_Updated: 2026-06-21 | Build #1218 ✅ SUCCESS_

---

## Current State

The video player (`raddflix_flutter/lib/screens/player_screen.dart`) is in a stable,
clean state. Build #1218 succeeded. The file is **7071 lines, 21 widget classes**.

### Recently Completed (this session)
1. **Right-side panels** — all 10 showModalBottomSheet → showGeneralDialog, 45% width, 60% dark bg
2. **MX-style indicators** — brightness LEFT (amber), volume RIGHT (white/orange), vertical pills
3. **Auto-rotation** — native Android SCREEN_ORIENTATION_SENSOR via com.raddflix.app/orient channel
4. **Customizable sidebar** — persistent right-edge strip, toggle, scroll, 19 shortcuts, drag reorder, add/remove, persisted prefs

### Files Modified
| File | State |
|------|-------|
| raddflix_flutter/lib/screens/player_screen.dart | 7071 lines — stable ✅ |
| raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt | orient channel added ✅ |

---

## Critical Rules — NEVER BREAK

1. **NO `vf=` property** — destroys GL surface on MediaTek → 15-day black screen bug
2. **NO `hwdec` mid-play** — only in initial player config before open()
3. **NO `androidAttachSurfaceAfterVideoParameters: true`** — same black screen bug
4. **NO local var named `_np`** — reserved for the mpv player instance (using `_np` is fine, creating a local with that name shadows it and breaks everything)
5. **db.setting(k)** NOT db.get_setting(k)
6. **GitHub push via Contents API** (`/tmp/push.js`) — Replit sandbox blocks git shell commits
7. **Always fetch fresh SHA** before PUT (the push script does this automatically)

### Existing Platform Channel Names (DO NOT REUSE)
- `com.raddflix.app/pip` — PiP + notification controls
- `com.raddflix.app/media` — media session
- `com.raddflix.app/cast` — cast
- `com.raddflix.app/intent` — deep links
- `com.raddflix.app/security` — screen security
- `com.raddflix.app/orient` — rotation control (NEW)

---

## Environment / Tools

```
GITHUB_TOKEN: in Replit env vars
Working copy: /tmp/raddflix/player_screen.dart
Push script:  node /tmp/push.js   (fetches SHA, pushes player_screen.dart)
Push orient:  node /tmp/push_orient.js (multi-file push)
Trigger build: POST /repos/raddclub/raddflix-app/actions/workflows/282572869/dispatches
Monitor: node /tmp/poll_run.js
```

---

## Priority Next Tasks

### HIGH
- **BUG-01 Subtitle alignment** — sub-margin-y not applied correctly in MPV
- **BUG-02 Subtitle background style** — no-op, needs MPV sub-back-color property
- **Top bar overflow** — 12+ icons on small screens, needs overflow menu or reorganization

### MEDIUM
- **Watch Party** — built but no visible UI entry point on main player screen
- **Voice Commands** — mic button missing from main UI, only accessible in settings
- **Sleep timer countdown** — badge in top bar exists but no full-screen countdown widget

### LOW
- Long-press sidebar shortcut → inline quick-swap picker
- A-B repeat indicator on seek bar timeline
- Download manager
