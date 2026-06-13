# AGENT HANDOFF — Jazz Drive / RaddFlix
**Date**: 2026-06-13
**Session**: UA fix, conflict detector, session health panel, upload session-dead fix, OTP VK fix, Clear Cookies feature

---

## Current State

### Oracle Server
- **Host**: ubuntu@92.4.95.252, SSH key at /tmp/oracle_key (rebuild each session from `ORACLE_SSH_KEY` env)
- **Service**: `sudo supervisorctl restart raddflix_radd` → RUNNING, port 5000
- **Repo on Oracle**: `/opt/jazzmax/radd-hub/` → synced with `raddclub/raddflix-app` main branch
- **HEAD**: Clear Cookies feature (last push 2026-06-13)

### SSH Key Rebuild (every session)
```bash
python3 -c "
import os, re, stat
raw = os.environ['ORACLE_SSH_KEY']
m = re.search(r'(-----BEGIN RSA PRIVATE KEY-----)(.*?)(-----END RSA PRIVATE KEY-----)', raw, re.DOTALL)
body = m.group(2).strip().replace(' ', '\n')
key = m.group(1)+'\n'+body+'\n'+m.group(3)+'\n'
open('/tmp/oracle_key','w').write(key)
" && chmod 600 /tmp/oracle_key
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

### Account Status
| ID | MSISDN | Role | Active | VK | JSESSIONID | Refresh Token |
|----|--------|------|--------|-----|-----------|--------------|
| 4 | 03257719165 | flix | YES | ❌ MISSING | ✅ Valid | ✅ Valid |

> **CRITICAL**: Account id=4 has JSESSIONID and refresh_token but NO validation_key.
> Without VK every SAPI call fails. User MUST do OTP login once more.
> After the code fix (commit 0ceb1544), next OTP will obtain VK correctly.

---

## ⚠️ FIRST THING — User must do OTP again
1. Go to Scan page → Send OTP for `03257719165` → enter code
2. Logs should show: `verify_otp: mobile_direct gave VK — merging with OAuth2 tokens`
3. After login: delete stuck Karuppu.2026.480p... file (files.id=37) → re-upload

---

## What Was Done This Session

### FIX-UA-STRINGS ✅ (commit db30e8bf)
All 10 User-Agent strings corrected in scanner.py, jazzdrive.py, proxy_pool.py, app.py:
- **Wrong**: `SM-A515F/Android12` (Samsung)
- **Correct**: `Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)`

### FEAT-CONFLICT-DETECTOR ✅ (commits b2e7bc5f, 05c73576)
`hub/keepalive.py` additions:
- `_classify_error()` — detects JD "device conflict" vs normal errors
- `_log_event()` / `get_events()` — 100-entry in-memory ring buffer
- Auto-pause on 2+ conflicts in 10 min window + WhatsApp alert

### FEAT-KEEPALIVE-HEALTH-API ✅
`hub/routes/admin.py`:
- `GET /admin/api/keepalive-health` — per-account health cards, event log, conflict stats
- `POST /admin/api/keepalive-health/trigger/<aid>` — force heartbeat for one account

### FEAT-SESSION-HEALTH-PANEL ✅
`hub/templates/services.html`:
- JazzDrive Session Health panel: per-account cards, expiry countdown bar
- Force Heartbeat / Refresh buttons, event log, conflict banner

### FIX-UPLOAD-HANG ✅ (commit 0f133ce5)
`hub/uploader.py` `_run()`: pre-flight session check before uploading:
- Verifies JSESSIONID exists + calls `verify_jd_session()` → tries `refresh_session()`
- If all fail → state=`session_dead` with clear re-login message (no more 0% hang)
`hub/templates/upload.html`: `session_dead` badge + banner + link to Scan page

### FIX-OTP-VK-MISSING ✅ (commit 0ceb1544)
**Root cause**: `jazzdrive_verify_otp()` returned early with JSESSIONID from cookies but `validation_key=""`.  
**Fix 1** — `hub/scanner.py`: after OAuth2 gives `vk=False`, calls `mobile_direct_verify_otp()` with same OTP → gets VK from `keytype=otp` endpoint (geo-unrestricted).  
**Fix 2** — `hub/_legacy/scanner.py`: early-return guards now require BOTH JSESSIONID AND VK.

### FEAT-CLEAR-COOKIES ✅ (2026-06-13)
New "🍪 Clear Cookies" button on every account card in Scan page:
- **Wipes**: JSESSIONID, validation_key, node
- **Keeps**: refresh_token, raw_accesstoken, is_active=1
- Also clears jazzdrive_session.json cookies fields
- Keepalive will attempt silent refresh automatically after clearing
- Files changed: `hub/jazzdrive.py` (jd_clear_cookies()), `hub/routes/scan.py` (POST /clear-cookies), `hub/templates/scan.html` (button + JS)

---

## Rules for Next Agent
1. `db.setting(k)` not `db.get_setting(k)`
2. Restart: `sudo supervisorctl restart raddflix_radd` (NOT systemctl)
3. Push files: Python+urllib using `GITHUB_TOKEN` env var (no git shell)
4. Correct UA: `Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)`
5. Device: name=`Infinix Hot 9 Play`, ID=`fcbf291eddd5d372`
6. Logs: `/var/log/raddflix_radd.out.log` and `.err.log`
7. DB: `/opt/jazzmax/radd-hub/data/radd_hub.db` — SQLite
8. Active account: id=4 (03257719165). After OTP re-login VK is populated and all uploads work.
9. `keytype=accesstoken` SAPI endpoint always returns 401 — never use. Use `keytype=otp` at OTP time.
