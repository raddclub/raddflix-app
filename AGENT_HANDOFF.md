# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — HUNTER-AUDIT session_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last APK build | ✅ run#27730921492, commit 4882ba1 — **SUCCESS** |
| Latest commit | 4882ba1 — hunter audit: 10 bugs fixed across player files |
| Build triggered? | Yes — build completed **success** |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## What was done this session

Full "hunter mode" audit of all 100 player-related Flutter files. 5 parallel subagents audited every file. 10 bugs confirmed and fixed across 10 files in commit 4882ba1. APK build triggered.

**Fixes in 4882ba1:**
1. `n_series_network.dart` — removed `_lastBytes` (declared, never read)
2. `p_series_parental.dart` — removed `_todayKey` field + assignment in `configure()` (computed, never read)
3. `enhanced_screenshot_service.dart` — removed unused `title` param from `_saveToGallery()`
4. `sync_panel.dart` — double spaces `'delayed by  +'` → `'delayed by +'`
5. `scene_bookmarks_panel.dart` — null-safe `bm.id`: `Dismissible` key now `bm.id?.toString() ?? bm.positionMs.toString()`; `onDismissed`/`onLongPress` guard `bm.id != null`
6. `smart_enhance_sheet.dart` — Before/After hold button caches `_prevEnabled` on press, restores it on release (was blindly setting `true`); extracted duplicate portrait/landscape lambda into `_handleBeforeHold()`
7. `subtitle_overlay.dart` — RegExp `r"[\w']+"` and `r"^[\w']+$"` moved from local vars (O(n) recompilation per subtitle line/token) to `static final` class fields
8. `video_enhance_suite.dart` — triplicate `_pctDelta` lambda extracted into `static String _pctDelta(double v)` method
9. `speed_presets_sheet.dart` — `_toggle()` now shows `SnackBar('Keep at least 2 speeds')` instead of silent no-op when minimum reached
10. `player_screen.dart` `_VDSTile` — replaced hardcoded `_blue` (0xFF1565C0) with `_accent` (0xFFE8002D) for active tile state

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

## Known open data issue

- **DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from Oracle DB. Not in scope for player audit sessions.

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
