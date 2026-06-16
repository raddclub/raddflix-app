# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-16

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | raddflix_radd via supervisorctl, port 5000, v3.0.0 |
| JazzDrive Session | ✅ LIVE | Account id=11 (03257719165): VK ✅ JID ✅ raw_accesstoken ✅ refresh_token ✅ |
| JazzDrive Chain | ✅ PROVEN | Full login→media→CDN tested 2026-06-16, real MP4 bytes confirmed |
| Flutter app | ✅ STABLE | All known bugs fixed — latest APK build 1053 |
| Login screen | ✅ FIXED | Wrong password no longer navigates to home — shows error banner |
| Catalog sync | ✅ FORCED | catalog_forced_version=1781620750 — all devices will full re-sync |
| Debug screen | ✅ LIVE | Accessible in release — tap version text 5× in Profile |
| JazzDrive diag | ✅ LIVE | Checks tab runs live JazzDrive chain test on-device |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |
| Admin Panel | ✅ AUDITED | All 27 route files clean |

---

## Latest APK

| Build | APK | Status |
|-------|-----|--------|
| build-1053 (run 27626589677) | RaddFlix-1.0.0+1-build1053.apk (56.8 MB) | ✅ Success |

---

## Oracle Server Quick Reference

```
IP:        92.4.95.252
SSH:       ubuntu@92.4.95.252  (key from ORACLE_SSH_KEY secret → /tmp/oracle_key)
App path:  /opt/jazzmax/radd-hub/hub/
Service:   sudo supervisorctl restart raddflix_radd
Logs:      sudo tail -f /opt/jazzmax/radd-hub/data/logs/raddhub.log
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

## Account State (2026-06-16)

| ID | MSISDN | Role | Active | VK | JSESSIONID | Refresh Token | Notes |
|----|--------|------|--------|----|-----------|--------------|-------|
| 11 | 03257719165 | flix | YES | ✅ valid | ✅ .2i182 node | ✅ valid | All tokens healthy |

---

## Pending User Actions

None. Install build 1053 and test.

---

## Known Limitations

- `keytype=accesstoken` SAPI endpoint always returns 401 for fnbroot OAuth2 tokens — use `keytype=otp` at OTP login time only.
- `android_refresh_session()` rotates refresh_token but cannot get fresh VK without OTP — keepalive covers this via heartbeat.
- JSESSIONID `.NODE` suffix MUST NOT be stripped — sticky routing to same LB node is mandatory.
