# Next Agent Brief — RaddFlix / JazzDrive (2026-06-13)
**Priority**: HIGH — user needs one OTP re-login before uploads work

---

## Start Here — SSH key + health check (always first)
```bash
python3 -c "
import os, re
raw = os.environ['ORACLE_SSH_KEY']
m = re.search(r'(-----BEGIN RSA PRIVATE KEY-----)(.*?)(-----END RSA PRIVATE KEY-----)', raw, re.DOTALL)
body = m.group(2).strip().replace(' ', '\n')
key = m.group(1)+'\n'+body+'\n'+m.group(3)+'\n'
open('/tmp/oracle_key','w').write(key)
" && chmod 600 /tmp/oracle_key
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

---

## ⚠️ FIRST USER ACTION — OTP Re-Login Required

Account id=4 (`03257719165`) has JSESSIONID + refresh_token but **no validation_key (VK)**.
Without VK every SAPI call fails with AUTH-001. The fix is already deployed (commit 0ceb1544).

**Tell user**: "Please go to Scan page → Send OTP → enter the SMS code"

**Verify in logs** (`sudo tail -50 /var/log/raddflix_radd.out.log`):
```
verify_otp: mobile_direct gave VK — merging with OAuth2 tokens
```

**After successful OTP**:
1. Delete stuck file: Upload page → find `Karuppu.2026.480p...` → delete (files.id=37)
2. Re-upload the file — should upload immediately

---

## Project Summary

RaddFlix — Pakistani Flutter streaming app. Jazz SIM users get zero-rated access to content hosted on JazzDrive CDN. Oracle server (`92.4.95.252`) runs a Flask hub that proxies all JazzDrive SAPI calls.

**Stack**: Flutter app → HTTPS → nginx (port 80) → Flask (port 5000) → JazzDrive SAPI

---

## Critical Rules (never break these)

| Rule | Why |
|------|-----|
| `db.setting(k)` not `db.get_setting(k)` | Function doesn't exist |
| `sudo supervisorctl restart raddflix_radd` | NOT systemctl |
| Push via Python+urllib + GITHUB_TOKEN | No git shell on Oracle |
| UA: `Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)` | Must match real device |
| Device: `Infinix Hot 9 Play`, ID: `fcbf291eddd5d372` | Must match real device |
| `keytype=accesstoken` SAPI endpoint → always 401 | Wrong token format — never use |
| VK only obtainable during OTP login | keytype=otp endpoint, geo-unrestricted |

---

## Key Architecture

### Files on Oracle
```
/opt/jazzmax/radd-hub/
├── hub/
│   ├── jazzdrive.py          — JD SAPI client; jd_clear_cookies(), jd_logout_account()
│   ├── scanner.py            — OTP flow; verify_otp() calls mobile_direct_verify_otp for VK
│   ├── uploader.py           — Upload worker; pre-flight session check; session_dead state
│   ├── keepalive.py          — Heartbeat; conflict detector; event log
│   ├── db.py                 — SQLite helpers; db.setting(k)
│   ├── routes/
│   │   ├── scan.py           — /scan/* routes incl. POST /clear-cookies
│   │   ├── admin.py          — /admin/* routes incl. /keepalive-health
│   │   └── upload.py         — /upload/* routes
│   └── templates/
│       ├── scan.html         — Account cards with 🍪 Clear Cookies + Logout JD buttons
│       ├── upload.html       — Upload UI with session_dead badge
│       └── services.html     — Session Health panel
├── data/
│   ├── radd_hub.db           — SQLite DB
│   └── jazzdrive_session.json — JD session file (cookies field is pickle b64)
```

### Account Buttons (scan page)
| Button | What it wipes | What it keeps | Account status |
|--------|--------------|---------------|----------------|
| 🍪 Clear Cookies | JSESSIONID, VK, node | refresh_token, raw_accesstoken | stays active |
| Logout JD | ALL tokens | nothing | marked inactive |

---

## Session Work Done (2026-06-13)

1. **FIX-UA-STRINGS** — All 10 UA strings → Infinix X680F/Android10 (commit db30e8bf)
2. **FEAT-CONFLICT-DETECTOR** — keepalive.py: conflict classifier, event log, auto-pause (commits b2e7bc5f, 05c73576)
3. **FEAT-KEEPALIVE-HEALTH-API** — GET/POST /admin/api/keepalive-health in admin.py
4. **FEAT-SESSION-HEALTH-PANEL** — JD Session Health panel in services.html
5. **FIX-UPLOAD-HANG** — pre-flight check in uploader.py; session_dead state (commit 0f133ce5)
6. **FIX-OTP-VK-MISSING** — mobile_direct_verify_otp after OAuth2; _legacy guard fix (commit 0ceb1544)
7. **FEAT-CLEAR-COOKIES** — 🍪 button + jd_clear_cookies() + /clear-cookies route

---

## DB Quick Reference
```bash
# Check account tokens
ssh oracle "python3 -c \"
import sqlite3, json
db = sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
db.row_factory = sqlite3.Row
for r in db.execute('SELECT id,msisdn,role,is_active,validation_key,jsessionid,refresh_token FROM accounts'):
    print(dict(r))
\""
```
