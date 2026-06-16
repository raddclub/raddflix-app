# Next Agent Brief — RaddFlix / JazzDrive
  **Date**: 2026-06-16 | **Priority**: NORMAL — All known bugs fixed

  ---

  ## Context
  RaddFlix is a Pakistani streaming app targeting Jazz SIM users (zero-rated via JazzDrive).
  Oracle backend (`92.4.95.252`, Flask, `/opt/jazzmax/radd-hub/hub/`) handles all JD calls.

  ---

  ## ✅ Current Status — No Blocking Issues

  All known Flutter app bugs have been fixed as of 2026-06-16. Build 1058 is in progress.
  Oracle Flask is running. JazzDrive chain is proven working.

  ---

  ## Key Findings — Important for Future Work

  ### ⚠️ CRITICAL: hwdec must NOT be changed while video is playing (fixed 2026-06-16)
  Root cause of the "blank screen after 2-3 seconds on local videos" bug:
  - `_loadPrefs()` runs async from `initState` and completes ~1-2 seconds after playback starts
  - It called `_applyAudioPrefs()` which unconditionally set `hwdec` via MPV
  - Changing `hwdec` mid-playback on Android destroys the GL surface texture → black screen
  - Fix: wrapped `hwdec` + `deinterlace` setProperty in `if (!_playing)` guard
  - Commit: 3b56547 — player_screen.dart

  ### Seek bar double-dot fixed (2026-06-16)
  - Non-classic seek bar styles rendered both SeekBarPainter's custom thumb AND Slider's own white thumb
  - Fix: `SliderComponentShape.noThumb` for non-classic styles in SliderTheme
  - Commit: 3b56547 — player_screen.dart

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

  ## Files Changed — 2026-06-16 Session
  | File | What Changed | Commit |
  |------|-------------|--------|
  | `raddflix_flutter/lib/screens/player_screen.dart` | hwdec+deinterlace wrapped in `if (!_playing)`; Slider `noThumb` for non-classic seek bar | 3b56547 |
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
  GitHub:   Push via Python+urllib using GITHUB_TOKEN (no git shell)
  Rules:    db.setting(k) NOT db.get_setting(k); supervisorctl NOT systemctl
  ```
  