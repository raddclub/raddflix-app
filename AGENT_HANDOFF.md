# RaddFlix Agent Handoff

_Last updated: 2026-06-18 — FIX-PLAYER-BUGS session_

## Current State

| Item | Status |
|------|--------|
| Oracle Flask | Running v3.0.0 at 92.4.95.252:5000 |
| Last APK build | ✅ run#1099/1100, commit 91e52dc (56.9MB) |
| Latest commit | 09760ca — FIX-PLAYER-BUGS (11 bugs fixed in player_screen.dart) |
| Build triggered? | No — player-only fix, safe to queue |
| Open tasks | DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 |

## What was done this session

Full audit of player_screen.dart (7,131 lines) and 11 confirmed bugs fixed in one commit (09760ca). See TASK_LOG for full details.

**Key fixes:**
- SmartVolumeController no longer overrides mute (clamp 20→0)
- Stream error retry now uses current episode (_currentFileId), not ep1
- Next-episode "Cancel" no longer exits the entire player
- Floating ball icon reflects actual play/pause state
- Duplicate 20-line skip-intro timer code extracted into _scheduleSkipIntroCheck()
- 6 dead state variables removed
- Frame-step controls now clear when playback resumes

## Remaining player_screen.dart audit items (not yet fixed)

| Category | Items |
|----------|-------|
| Duplicate UX systems | D1: Two next-ep overlays, D2: Two EQ UIs, D3: Three speed pickers, D4: Two audio panels, D5: Two bookmark panels, D6: Three jump-to implementations |
| UX illogic | X4: Sleep panel Expanded in fixed-width container, X5: VideoDisplay Sheet inconsistent toggle API, X6: VDSTile always blue regardless of feature, X8: rage-skip silent 4th-tap swallow, X9: dual next-ep overlays at video end |
| Architecture | A1: 7099-line file (5 controllers to extract), A2: _ControlsOverlay 50+ params, A4: applyAudioPrefs/applyVideoFilters called from 6+ places |
| Ghost features | _showCountdown never set true, _watchPartyRoom never assigned, _secondSubtitleText never populated |

## Critical Rules — never violate

| Rule | Detail |
|------|--------|
| vf= mid-play guard | NEVER call _np.setProperty('vf', ...) while playing from startup code paths. Must check _firstVfApplied gate and _lastAppliedVf dedup. On MediaTek/Infinix HW decoder, even empty vf= destroys GL surface. |
| sqflite_sqlcipher | NEVER upgrade past 3.1.0+1 — breaks encrypted DB on older Android. |
| androidAttachSurface | NEVER add androidAttachSurfaceAfterVideoParameters:true — HW decoder crash. |
| XOR padding fix | request_encoder.dart XOR padding must stay. Do not revert. |
| Icons | Never use Icons.replay_15_rounded / forward_15_rounded — don't exist in Flutter 3.22.3. Use replay_10 / forward_10. |
| GitHub push | GitHub API only — never git push from shell. |
| DebugDiagnosticsScreen | Do NOT re-add kDebugMode gate — intentionally release-accessible. |

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
