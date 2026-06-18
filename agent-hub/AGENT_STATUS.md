# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-18 (Comprehensive debug logging session)

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | raddflix_radd via supervisorctl, port 5000, v3.0.0 |
| JazzDrive Session | ✅ LIVE | Account id=11 (03257719165): VK ✅ JID ✅ tokens ✅ |
| JazzDrive Chain | ✅ PROVEN | Full login→media→CDN tested 2026-06-16, real MP4 bytes confirmed |
| Flutter app | ✅ STABLE | Build ✅ commit 96f8cc1 |
| Debug Logging | ✅ COMPLETE | All screens + global crash handler + nav observer active |
| Debug screen | ✅ LIVE | Profile → Account → Debug Logs (one tap, always visible) |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |
| Admin Panel | ✅ AUDITED | All 27 route files clean |

---

## Latest APK

| Build | Commit | Status | Key Fix |
|-------|--------|--------|---------|
| debug-logging-fix | 96f8cc1 | ✅ Success | dart:ui import fix — all logging commits now live |
| downloads-log | 1e7128f | ❌ Cascaded (main.dart) | downloads_screen logging |
| profile-log | 198033b | ❌ Cascaded (main.dart) | profile_screen logging |
| search-log | f739564 | ❌ Cascaded (main.dart) | search_screen logging |
| show-detail-log | 69a7d63 | ❌ Cascaded (main.dart) | show_detail logging |
| home-log | 9c55499 | ❌ Cascaded (main.dart) | home_screen logging |
| nav-observer | d5a449c | ❌ Cascaded (main.dart) | NavigatorObserver in app.dart |
| debuglogger-v2 | 613f686 | ✅ Success | DebugLogger v2 upgrade |

> All "cascaded" failures were caused by a single missing `import 'dart:ui' show PlatformDispatcher;`
> in main.dart. The fix (96f8cc1) passes and includes ALL prior logging commits.

---

## Debug Logging System (added 2026-06-18)

### DebugLogger v2 — `lib/core/debug/debug_logger.dart`
| Method | Tag | Usage |
|--------|-----|-------|
| `logTap(screen, action, [detail])` | `TAP/Screen` | Every user tap |
| `logNav(action, route, [detail])` | `NAV` | Every route push/pop/replace |
| `logLifecycle(screen, event)` | `LC/Screen` | initState / dispose |
| `logFeature(feature, [params])` | `FEAT` | Feature usage |
| `logCrash(tag, error, stack)` | `CRASH` | Crash with full stack |
| `getFiltered(tagFragment)` | — | Filter log entries by tag |
| buffer | 5000 entries | — |
| rotation | 8 MB max | — |
| auto-flush | every 30s | — |
| session ID | UUID | Embedded in every log file |

### Coverage
| Layer | File | Events |
|-------|------|--------|
| Dart crash net | main.dart | ALL uncaught Dart errors via PlatformDispatcher.onError |
| Navigation | app.dart | Every push/pop/replace/remove |
| Home | home_screen.dart | Lifecycle, nav tabs, filters, hero taps |
| Show detail | show_detail_screen.dart | Lifecycle, play/download ep taps |
| Search | search_screen.dart | Lifecycle, query, filter, results, taps |
| Profile | profile_screen.dart | Lifecycle, nav tab taps |
| Downloads | downloads_screen.dart | Lifecycle, play taps |
| Player | player_screen.dart | 13 crash-path checkpoints |

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

| ID | MSISDN | Role | Active | VK | JSESSIONID | Notes |
|----|--------|------|--------|----|-----------|-------|
| 11 | 03257719165 | flix | YES | ✅ valid | ✅ .2i182 node | All tokens healthy |

---

## Known Limitations

- `keytype=accesstoken` SAPI endpoint always returns 401 — use `keytype=otp` at OTP login time only.
- JSESSIONID `.NODE` suffix MUST NOT be stripped — sticky routing mandatory.
