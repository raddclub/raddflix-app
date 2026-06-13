# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-13

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | raddflix_radd via supervisorctl, port 5000 |
| JazzDrive Session | ⚠️ NEEDS OTP | Account id=4 has JSESSIONID+RT but NO VK — one OTP re-login needed |
| JazzDrive Upload | ⚠️ BLOCKED | Unblocks after OTP. Delete Karuppu.2026.480p (files.id=37) → re-upload |
| Flutter app | ✅ STABLE | All critical bugs fixed |
| User-Agent strings | ✅ FIXED | All 10 strings → Infinix X680F/Android10/QP1A.190711.020 |
| Keepalive | ✅ ENHANCED | Conflict detector + event log + auto-pause + WhatsApp alerts |
| Session Health Panel | ✅ LIVE | Per-account health cards + expiry countdown in Services page |
| Upload UI | ✅ ENHANCED | session_dead badge + re-login banner in upload.html |
| OTP VK fix | ✅ DEPLOYED | mobile_direct_verify_otp called after OAuth2 to get VK (commit 0ceb1544) |
| Clear Cookies | ✅ LIVE | 🍪 button on every account card; wipes JID+VK, keeps RT |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |
| Admin Panel | ✅ AUDITED | All 27 route files clean |
| Schema Validator | ✅ LIVE | validate_schema() at startup, /admin/api/schema-health |

---

## Oracle Server Quick Reference

```
IP:        92.4.95.252
SSH:       ubuntu@92.4.95.252  (key from ORACLE_SSH_KEY secret → /tmp/oracle_key)
App path:  /opt/jazzmax/raad-hub/
Hub path:  /opt/jazzmax/radd-hub/hub/
Service:   sudo supervisorctl restart raddflix_radd
Logs:      sudo tail -f /var/log/raddflix_radd.out.log
Health:    curl -s http://localhost:5000/healthz
DB:        /opt/jazzmax/radd-hub/data/radd_hub.db
```

**SSH key reconstruction (run once per session):**
```bash
python3 -c "
import os, re
raw = os.environ['ORACLE_SSH_KEY']
m = re.search(r'(-----BEGIN RSA PRIVATE KEY-----)(.*?)(-----END RSA PRIVATE KEY-----)', raw, re.DOTALL)
body = m.group(2).strip().replace(' ', '\n')
key = m.group(1)+'\n'+body+'\n'+m.group(3)+'\n'
open('/tmp/oracle_key','w').write(key)
" && chmod 600 /tmp/oracle_key
```

---

## Account State (2026-06-13)

| ID | MSISDN | Role | Active | VK | JSESSIONID | Refresh Token | Notes |
|----|--------|------|--------|----|-----------|--------------|-------|
| 4 | 03257719165 | flix | YES | ❌ empty | ✅ valid | ✅ valid | Needs OTP re-login for VK |

> After next successful OTP (with fixed code, commit 0ceb1544), VK will be populated.

---

## Pending User Actions

1. **OTP re-login**: Scan page → Send OTP → enter code → check logs for `mobile_direct gave VK`
2. **Delete stuck file**: Upload page → delete Karuppu.2026.480p... (files.id=37)
3. **Re-upload**: Upload the file again — will succeed immediately after login

---

## Known Limitations

- `keytype=accesstoken` SAPI endpoint always returns 401 for fnbroot OAuth2 tokens — never works from Oracle. Use `keytype=otp` at OTP login time.
- `android_refresh_session()` successfully rotates refresh_token but cannot get fresh VK without OTP.
- If VK expires between OTPs → uploads fail with AUTH-001 → user clicks 🍪 Clear Cookies → keepalive tries silent refresh → if refresh_token alive, new session obtained without OTP.
