# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — FIX-PLAYER-REAUDIT session_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last APK build | ✅ run#27729363694, commit c099057 — **SUCCESS** |
| Latest commit | c099057 — re-audit: 4 more bugs fixed (orphan import, clock timer, dead guard, getter shadow) |
| Build triggered? | Yes — build completed **success** |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## What was done this session

Full line-by-line re-audit of player_screen.dart (7,099 lines) completed. 4 additional bugs found and fixed in commit c099057. APK build triggered and completed ✅ SUCCESS.

**Fixes in c099057:**
1. Removed orphaned `reaction_stamps_overlay.dart` import (widget was removed in 09760ca but import stayed → Dart unused-import warning every build)
2. Clock timer: 30s → 10s interval (HH:MM display was up to 30s stale; 10s gives ≤10s drift)
3. Removed dead `_audioSessionInitialized` guard in BG-play toggle callback (`_initAudioSession()` is always called in initState; the guard condition was always false, making the block unreachable)
4. Renamed local `final _np` variable in `onToggleSidebarMode` callback to `newPrefs` — it shadowed the class-level `NativePlayer get _np` getter (maintenance hazard)

## Remaining player_screen.dart items (not yet fixed)

| Category | Items |
|----------|-------|
| Duplicate UX systems | D1: Two next-ep overlays, D2: Two EQ UIs, D3: Three speed pickers, D4: Two audio panels, D5: Two bookmark panels, D6: Three jump-to implementations |
| UX illogic | X4: Sleep panel Expanded in fixed-width container, X5: VideoDisplay Sheet inconsistent toggle API, X6: VDSTile always blue regardless of feature, X8: rage-skip silent 4th-tap swallow, X9: dual next-ep overlays at video end |
| Architecture | A1: 7094-line file (5 controllers to extract), A2: _ControlsOverlay 50+ params, A4: applyAudioPrefs/applyVideoFilters called from 6+ places |
| Ghost features | _showCountdown never set true, _watchPartyRoom never assigned, _secondSubtitleText never populated (all safely no-op — conditions always false) |

## Critical Rules — never violate

| Rule | Detail |
|------|--------|
| vf= mid-play guard | NEVER call _np.setProperty('vf', ...) while playing from startup code paths. Must check _firstVfApplied gate and _lastAppliedVf dedup. On MediaTek/Infinix HW decoder, even empty vf= destroys GL surface. |
| sqflite_sqlcipher | NEVER upgrade past 3.1.0+1 — breaks encrypted DB on older Android. |
| androidAttachSurface | NEVER add androidAttachSurfaceAfterVideoParameters:true — HW decoder crash. |
| XOR padding fix | request_encoder.dart XOR padding must stay. Do not revert. |
| Icons | Never use Icons.replay_15_rounded / forward_15_rounded — don't exist in Flutter 3.22.3. Use replay_10 / forward_10. |
| GitHub push | GitHub API only — never git push from shell. Push files SEQUENTIALLY (never parallel) — parallel creates branch tree SHA conflicts. |
| DebugDiagnosticsScreen | Do NOT re-add kDebugMode gate — intentionally release-accessible. |
| _np getter shadow | Never name a local variable `_np` inside player_screen.dart — it shadows the `NativePlayer get _np` class getter. |

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
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" \
  | grep -E '"id"|"status"|"conclusion"|"message"' | head -20
```
