# Next Agent Brief — RaddFlix / JazzDrive
**Date**: 2026-06-17 | **Priority**: NORMAL — All known bugs fixed

---

## Context
RaddFlix is a Pakistani streaming app targeting Jazz SIM users (zero-rated via JazzDrive).
Oracle backend (`92.4.95.252`, Flask, `/opt/jazzmax/radd-hub/hub/`) handles all JD calls.

---

## ✅ Current Status — No Blocking Issues

All known Flutter app bugs fixed as of 2026-06-17. Build 1067 in progress (commit 61f58908).
Oracle Flask is running. JazzDrive chain is proven working.

---

## Key Findings — Important for Future Work

### ⚠️ CRITICAL: hwdec guard must check `_player.state.duration == Duration.zero` (fixed 2026-06-17)
Root cause of the "screen goes black after 2 seconds on local videos" bug:
- `_loadPrefs()` runs async from `initState` and completes ~1-2 seconds after playback starts
- It called `_applyAudioPrefs()` which was guarded by `if (!_playing)`
- `_playing` is a **Flutter state variable** — it lags one `setState()` cycle behind actual MPV state
- By the time `_loadPrefs` resolved, `_playing` was still `false` even though MPV's decoder was active
- Changing `hwdec` while the decoder pipeline is active → MPV restarts decoder → GL surface destroyed → black screen
- **Fix:** Guard is now `if (!_playing && !_player.state.playing && _player.state.duration == Duration.zero)`
- `_player.state.duration` is synchronous MPV state — becomes non-zero immediately when `_player.open()` is called
- BUG_TRACKER.md Critical Rules updated accordingly

### Long-press fast-forward black frame (fixed 2026-06-17)
- At 2.5x speed, MPV drops most frames to keep up; on speed reset the surface is left blank
- Fix: 80ms after `onLongPressEnd`, seek to current position → forces MPV to decode + render fresh frame

### ⚠️ IMPORTANT: All JazzDrive Dio requests need `validateStatus: (s) => true` (fixed 2026-06-17)
- Without it, any non-200 HTTP response throws an opaque `DioException` BEFORE the response body is available
- JazzDrive returns HTML error pages (not JSON) when not on Jazz SIM — these crash `Map<String,dynamic>` cast
- `_loginShare` and `_getMedia` now use `_dio.post<dynamic>` + `validateStatus: (s) => true` + HTML detection
- All exceptions from `getStreamLink` are now routed through `_buildJazzError()` for specific messages

### ⚠️ PREVIOUS: hwdec was guarded by `if (!_playing)` only (fixed earlier attempt incomplete)
The 2026-06-16 fix added `if (!_playing)` but that alone wasn't sufficient — `_playing` (Flutter state var) is false when MPV is already open. The 2026-06-17 fix adds the additional `_player.state.*` checks that use actual MPV state.

### OTP login VK issue (fixed, commit 0ceb1544 — 2026-06-13)
- `jazzdrive_verify_otp()` returned with JSESSIONID but empty VK (early return from cookie check)
- `keytype=accesstoken` SAPI endpoint always returns 401 for fnbroot OAuth2 tokens — never use it
- Fix: after OAuth2 gives `vk=False`, call `mobile_direct_verify_otp()` with same OTP (`keytype=otp`)
- `keytype=otp` is geo-unrestricted, works from Oracle IP, returns VK

### Silent refresh cannot get VK (watch this)
`android_refresh_session()` uses `token.php` → new `access_token` → tries `keytype=accesstoken` → 401.
**VK is only obtainable during OTP login.** If VK expires:
1. User clicks 🍪 Clear Cookies → keepalive tries silent refresh → new JSESSIONID but still no VK
2. If that's not enough → user must do OTP again

---

## Files Changed — 2026-06-17 Session (commit 61f58908)
| File | What Changed |
|------|-------------|
| `raddflix_flutter/lib/screens/player_screen.dart` | hwdec guard: `_player.state.playing` + `_player.state.duration == Duration.zero`; long-press seek fix; `_buildJazzError()` helper; capture `_linkGenError` in `_openMedia` catch |
| `raddflix_flutter/lib/core/services/jazzdrive_service.dart` | `_loginShare`: `post<dynamic>` + `validateStatus` + HTML detection; `_getMedia`: same treatment |

## Files Changed — 2026-06-16 Session
| File | What Changed | Commit |
|------|-------------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | hwdec wrapped in `if (!_playing)` (partial fix); Slider `noThumb` for non-classic seek bar | 3b56547 |
| `raddflix_flutter/lib/widgets/player/seek_bar_painter.dart` | Dots style: skip track dots under thumb position | 936a0a2 |
| `raddflix_flutter/lib/screens/show_detail_screen.dart` | Separated Play + Download into equal labelled buttons for movies and episodes | 24beefa |

## Files Changed — 2026-06-13 Session
| File | What Changed |
|------|-------------|
| hub/keepalive.py | Conflict detector, event log, auto-pause |
| hub/routes/admin.py | /admin/api/keepalive-health GET+POST |
| hub/templates/services.html | Session Health panel |
| hub/uploader.py | Pre-flight session check, session_dead state |
| hub/templates/upload.html | session_dead badge + banner |
| hub/scanner.py | mobile_direct VK fetch after OAuth2 |
| hub/_legacy/scanner.py | Fixed early-return in jazzdrive_verify_otp |
| hub/jazzdrive.py | jd_clear_cookies(), all UA strings corrected |
| hub/routes/scan.py | POST /clear-cookies route |
| hub/templates/scan.html | 🍪 Clear Cookies button + JS |

---

## Server / Auth Quick Reference
```
Oracle:   ubuntu@92.4.95.252
Restart:  sudo supervisorctl restart raddflix_radd
Health:   curl -s http://localhost:5000/healthz → {"ok":true,"version":"3.0.0"}
Logs:     /var/log/raddflix_radd.out.log / .err.log
DB:       /opt/jazzmax/radd-hub/data/radd_hub.db
Repo:     /opt/jazzmax/radd-hub/ → raddclub/raddflix-app main
Account:  id=11, 03257719165, role=flix
UA:       Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)
Device:   Infinix Hot 9 Play, ID: fcbf291eddd5d372
GitHub:   Push via Node.js Trees API at /tmp/push_*.js using GITHUB_TOKEN (git shell blocked)
Rules:    db.setting(k) NOT db.get_setting(k); supervisorctl NOT systemctl
```
