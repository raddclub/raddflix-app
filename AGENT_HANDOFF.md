# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — Comprehensive debug logging added to all screens, build ✅_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last APK build | ✅ SUCCESS — commit `96f8cc1` (dart:ui fix, build passed) |
| Latest commit | `96f8cc1` — fix(build): add dart:ui import for PlatformDispatcher in main.dart |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## What was done this session (2026-06-18)

Implemented **maximum comprehensive debug logging** — every crash, black screen, user tap, navigation event, and player error is now captured and visible in the debug log screen.

### DebugLogger v2 (commit `613f686`) — `lib/core/debug/debug_logger.dart`
| Addition | Detail |
|----------|--------|
| Buffer size | 1000 → 5000 entries |
| Log rotation | 8 MB max (was 5 MB) |
| New: `logTap(screen, action, [detail])` | Logs every user tap with screen + action |
| New: `logNav(action, route, [detail])` | Logs every navigation event |
| New: `logLifecycle(screen, event)` | Logs initState/dispose for every screen |
| New: `logFeature(feature, [params])` | Logs feature usage |
| New: `logCrash(tag, error, stack)` | Logs crashes with full stack |
| New: `getFiltered(tagFragment)` | Returns entries where tag contains fragment |
| Auto-flush | Every 30 seconds (was manual only) |
| Session ID | `_sessionId` — UUID embedded in every log file |

### Global crash handler — `lib/main.dart` (commits `bb59f50` + `96f8cc1`)
- `PlatformDispatcher.instance.onError` catches **all** uncaught Dart errors (requires `import 'dart:ui' show PlatformDispatcher;`)
- `DebugLogger.init()` called at very first line of `main()` before anything else
- Any crash before `runApp()` is now captured

### Global navigation logging — `lib/app.dart` (commit `d5a449c`)
- `_RaddNavObserver` implements `NavigatorObserver`
- Every push/pop/replace/remove logs: `[NAV] PUSH /route | from=/prev`
- Registered globally in `MaterialApp.navigatorObservers`

### Screens patched with full logging

| Screen | Commit | What's logged |
|--------|--------|---------------|
| `player_screen.dart` | `2413c3f` | 13 crash paths: initPlayer, hwdec guard, vf= gate, setSpeed, open() URLs, buffering stream, completed event, error stream, jazzAutoRetry, onSwDecoderChanged |
| `home_screen.dart` | `9c55499` | lifecycle + bottom nav tabs + filter chips + hero card taps |
| `show_detail_screen.dart` | `69a7d63` | lifecycle + play/download episode taps with title+id |
| `search_screen.dart` | `f739564` | lifecycle + query changes + filter changes + clearAll + suggestion taps + result taps |
| `profile_screen.dart` | `198033b` | lifecycle + subscription/watchlist/history/downloads tabs |
| `downloads_screen.dart` | `1e7128f` | lifecycle + play-download tap |

### Build fix (commit `96f8cc1`)
- `PlatformDispatcher` not in `package:flutter/material.dart` — requires explicit `import 'dart:ui' show PlatformDispatcher;`
- All 4 prior failures (commits `d5a449c`, `9c55499`, `69a7d63`, `bb59f50`) cascaded from this missing import
- Fix pushed as `96f8cc1` — build ✅ SUCCESS

---

## Previous session (2026-06-18, earlier)

Made debug diagnostics screen directly accessible:
1. `profile_screen.dart` — added visible "Debug Logs" tile in Account section (one tap, always visible)
2. `debug_diagnostics_screen.dart` — opens on Logs tab by default; log timer auto-starts

---

## How to read debug logs (on device)
1. Open app → Profile → Account → **Debug Logs**
2. Filter chips: tap **CRASH** first, then **ERR**, then **VIDEO** or **AUDIO**
3. Tap **Share** (top right) to export `.log` file

---

## Critical Rules — never violate

| Rule | Detail |
|------|--------|
| vf= mid-play guard | NEVER call `_np.setProperty('vf', ...)` while playing from startup code paths. Must check `_firstVfApplied` gate and `_lastAppliedVf` dedup. |
| sqflite_sqlcipher | NEVER upgrade past 3.1.0+1 — breaks encrypted DB on older Android. |
| androidAttachSurface | NEVER add `androidAttachSurfaceAfterVideoParameters:true` — HW decoder crash. |
| XOR padding fix | `request_encoder.dart` XOR padding must stay. Do not revert. |
| Icons | Never use `Icons.replay_15_rounded` / `forward_15_rounded` — don't exist in Flutter 3.22.3. Use `replay_10` / `forward_10`. |
| GitHub push | GitHub API only — never `git push` from shell. Push files SEQUENTIALLY (never parallel). |
| DebugDiagnosticsScreen | Do NOT re-add `kDebugMode` gate — intentionally release-accessible. |
| _np getter shadow | Never name a local variable `_np` inside `player_screen.dart` — shadows the `NativePlayer get _np` getter. |
| PlatformDispatcher import | Requires `import 'dart:ui' show PlatformDispatcher;` — NOT exported by flutter/material.dart. |
| DebugLogger methods | When calling `DebugLogger.*`, ensure the method exists in the class first. Current v2 methods: `log`, `logError`, `logWarn`, `logApi`, `logState`, `logTap`, `logNav`, `logLifecycle`, `logFeature`, `logCrash`, `getLastLines`, `getRecent`, `getFiltered`, `clearBuffer`, `getLogPath`, `copyToClipboard`, `flush`, `share`, `shareLogs`. |

## Known open data issue

- **DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from Oracle DB. Not in scope.

## Common Commands

### Trigger APK build
```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'
```

### Check build status
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.id,'|',r.status,'|',(r.conclusion||'-'),'| commit:',r.head_sha.slice(0,7)));
  });"
```

### Verify Oracle is alive
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```
