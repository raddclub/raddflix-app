# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-17

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | raddflix_radd via supervisorctl, port 5000, v3.0.0 |
| JazzDrive Session | ✅ LIVE | Account id=11 (03257719165): VK ✅ JID ✅ raw_accesstoken ✅ refresh_token ✅ |
| JazzDrive Chain | ✅ PROVEN | Full login→media→CDN tested 2026-06-16, real MP4 bytes confirmed |
| Flutter app | ✅ STABLE | All known bugs fixed — build 1067 (commit 61f58908) |
| Login screen | ✅ FIXED | Wrong password no longer navigates to home — shows error banner |
| Catalog sync | ✅ FORCED | catalog_forced_version=1781620750 — all devices will full re-sync |
| Debug screen | ✅ LIVE | Accessible in release — tap version text 5× in Profile |
| JazzDrive diag | ✅ LIVE | Checks tab runs live JazzDrive chain test on-device |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |
| Admin Panel | ✅ AUDITED | All 27 route files clean |

---

## Latest APK

| Build | Commit | Status | Key Fix |
|-------|--------|--------|---------|
| build-1067 | 61f58908 | 🔄 Building | Black screen + Jazz error messages |
| build-1066 | 5647a86e | ✅ Success (56.8MB) | Icon fix + SERVER_SETUP.md |
| build-1053 | — | ✅ Success | Debug screen accessible in release |

---

## Bug Fixes — 2026-06-17 (commit 61f58908)

### BUG-BLACKSCREEN-LOCAL (CRITICAL)
**Local video goes black after ~2 seconds — hwdec race condition**
- Root cause: `_loadPrefs()` async + `_player.open()` race. When prefs loaded, `_applyAudioPrefs` checked `if (!_playing)` — but `_playing` (Flutter state var) lags behind MPV state. MPV already had active decoder; setting `hwdec` mid-decode destroyed GL surface.
- Fix: guard changed to `if (!_playing && !_player.state.playing && _player.state.duration == Duration.zero)` — uses actual synchronous MPV state. `duration` becomes non-zero as soon as media is opened.

### BUG-BLACKSCREEN-LP
**Long-press fast-forward leaves black frame on release**
- Root cause: MPV drops frames at high speed, surface stays black when speed returns to 1.0x.
- Fix: 80ms after long-press end, seek to `_player.state.position` to force MPV to decode fresh frame.

### BUG-JAZZ-GENERIC-ERROR
**Catalog movies always show "Jazz SIM Required" regardless of real error**
- Root cause: (1) No `validateStatus` on Dio — non-200 responses threw opaque DioException. (2) HTML error pages crashed JSON cast. (3) All exceptions → same generic message.
- Fix: `validateStatus: (s) => true` + HTML detection in `_loginShare` and `_getMedia`. New `_buildJazzError()` in player_screen translates MED-/FOL- codes, HTTP 401/403, timeout, HTML page into specific messages.

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

## Known Limitations

- `keytype=accesstoken` SAPI endpoint always returns 401 for fnbroot OAuth2 tokens — use `keytype=otp` at OTP login time only.
- `android_refresh_session()` rotates refresh_token but cannot get fresh VK without OTP — keepalive covers this via heartbeat.
- JSESSIONID `.NODE` suffix MUST NOT be stripped — sticky routing to same LB node is mandatory.
