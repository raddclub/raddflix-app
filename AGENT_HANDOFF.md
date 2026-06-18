# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — BUG-DEBUGLOGGER-MISSING fix_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last APK build | ⏳ triggered after commit 426d78c — awaiting result |
| Latest commit | 426d78c — fix(debug_logger): add 6 missing methods (logWarn, logApi, getLastLines, shareLogs, clearBuffer, getLogPath) |
| Previous passing build | ✅ run#27752025995, commit 1a4294c |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## What was done this session

Investigated 2 consecutive APK build failures (run#27753380200 commit 5ce16d8, run#27753231660 commit 9439a69). Both failed at "Build release APK" step with `Member not found` Dart compile errors for 6 `DebugLogger` methods that were called across 5 files but never existed in the class:

- `logWarn(tag, msg)` — called in `remote_config.dart`, `jazzdrive_service.dart`, `usage_service.dart`, `api_client.dart`, `download_service.dart`
- `logApi({method, url, ...})` — called in `api_client.dart` with named params
- `getLastLines(n)` → `String` — called in `debug_diagnostics_screen.dart`
- `shareLogs()` — used as `onPressed` callback in `debug_diagnostics_screen.dart`
- `clearBuffer()` — called in `debug_diagnostics_screen.dart`
- `getLogPath()` → `String` — called in `debug_diagnostics_screen.dart`

All 6 methods added to `lib/core/debug/debug_logger.dart` in commit `426d78c`. New APK build triggered.

## Critical Rules — never violate

| Rule | Detail |
|------|--------|
| vf= mid-play guard | NEVER call `_np.setProperty('vf', ...)` while playing from startup code paths. Must check `_firstVfApplied` gate and `_lastAppliedVf` dedup. On MediaTek/Infinix HW decoder, even empty `vf=` destroys GL surface. |
| sqflite_sqlcipher | NEVER upgrade past 3.1.0+1 — breaks encrypted DB on older Android. |
| androidAttachSurface | NEVER add `androidAttachSurfaceAfterVideoParameters:true` — HW decoder crash. |
| XOR padding fix | `request_encoder.dart` XOR padding must stay. Do not revert. |
| Icons | Never use `Icons.replay_15_rounded` / `forward_15_rounded` — don't exist in Flutter 3.22.3. Use `replay_10` / `forward_10`. |
| GitHub push | GitHub API only — never `git push` from shell. Push files SEQUENTIALLY (never parallel) — parallel creates branch tree SHA conflicts. Use Trees API for multi-file atomic commits. |
| DebugDiagnosticsScreen | Do NOT re-add `kDebugMode` gate — intentionally release-accessible. |
| _np getter shadow | Never name a local variable `_np` inside `player_screen.dart` — it shadows the `NativePlayer get _np` class getter. |
| DebugLogger methods | When adding calls to `DebugLogger.*` in any file, ensure the method exists in `lib/core/debug/debug_logger.dart` first. Class has: `log`, `logError`, `logWarn`, `logApi`, `logState`, `getLastLines`, `getRecent`, `clearBuffer`, `getLogPath`, `copyToClipboard`, `flush`, `share`, `shareLogs`. |

## Known open data issue

- **DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from Oracle DB. Not in scope for current sessions.

## Common Commands

### Verify Oracle is alive
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```

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
