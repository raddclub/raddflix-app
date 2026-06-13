# Next Agent Brief — RaddFlix / JazzDrive
**Date**: 2026-06-13 | **Priority**: HIGH

---

## Context
RaddFlix is a Pakistani streaming app targeting Jazz SIM users (zero-rated via JazzDrive).
Oracle backend (`92.4.95.252`, Flask, `/opt/jazzmax/radd-hub/hub/`) handles all JD calls.

---

## ⚠️ FIRST ACTION — User needs one more OTP login

Account id=4 (`03257719165`) currently has JSESSIONID + refresh_token but **no validation_key (VK)**.
Without VK every SAPI call fails with AUTH-001. The code fix (commit 0ceb1544) is already deployed.

**Tell user**: "Go to Scan page → Send OTP → enter code"

Verify in logs:
```
verify_otp: mobile_direct gave VK — merging with OAuth2 tokens
```

After login:
- Delete stuck file `Karuppu.2026.480p...` (files id=37, is_ready=0)
- Re-upload → should succeed immediately

---

## Key Findings — Important for Future Work

### OTP login VK issue (fixed, commit 0ceb1544)
- `jazzdrive_verify_otp()` returned with JSESSIONID but empty VK (early return from cookie check)
- `keytype=accesstoken` SAPI endpoint always returns 401 for fnbroot OAuth2 tokens — never use it
- Fix: after OAuth2 gives `vk=False`, call `mobile_direct_verify_otp()` with same OTP (`keytype=otp`)
- `keytype=otp` is geo-unrestricted, works from Oracle IP, returns VK

### Silent refresh cannot get VK (watch this)
`android_refresh_session()` uses `token.php` → new `access_token` → tries `keytype=accesstoken` → 401.
**VK is only obtainable during OTP login.** If VK expires:
1. User clicks 🍪 Clear Cookies → keepalive tries silent refresh → new JSESSIONID but still no VK
2. If that's not enough → user must do OTP again

### Clear Cookies feature (added this session)
New button on every account card in Scan page:
- Wipes: JSESSIONID, validation_key, node
- Keeps: refresh_token, raw_accesstoken, is_active=1
- Also clears jazzdrive_session.json cookies fields
- API: `POST /scan/api/accounts/<id>/clear-cookies`
- Function: `jd_clear_cookies(account_id)` in hub/jazzdrive.py

---

## Files Changed This Session
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
Account:  id=4, 03257719165, role=flix
UA:       Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)
Device:   Infinix Hot 9 Play, ID: fcbf291eddd5d372
GitHub:   Push via Python+urllib using GITHUB_TOKEN (no git shell)
Rules:    db.setting(k) NOT db.get_setting(k); supervisorctl NOT systemctl
```
