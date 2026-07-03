# Next Agent Brief — RaddFlix (2026-06-18)
**Priority**: LOW — all known bugs fixed + comprehensive logging in place.

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

## ✅ App Status — All Known Bugs Fixed

| Bug | Fix | Commit |
|-----|-----|--------|
| Black screen (local videos) | vf= startup gate + hwdec guard | multiple |
| Long-press blank frame | framedrop channel + seek after | multiple |
| Mute override by SmartVolume | clamp min 20→0 | 09760ca |
| Cancel exiting player | removed Navigator.pop | 09760ca |
| Retry wrong episode | use _currentFileId | 09760ca |
| All debug logging | DebugLogger v2 + nav observer + crash handler | 96f8cc1 |

---

## Comprehensive Debug Logging — DONE ✅

The app now captures EVERYTHING. See AGENT_HANDOFF.md for full details.

To read logs on device: **Profile → Account → Debug Logs**
Filter chips: CRASH → ERR → VIDEO/AUDIO → NAV → TAP

---

## Project Summary

RaddFlix — Pakistani Flutter streaming app. Jazz SIM zero-rated access to JazzDrive CDN content.
Oracle server (`92.4.95.252`) runs Flask hub proxying all JazzDrive SAPI calls.

**Stack**: Flutter app → HTTPS → nginx (port 80) → Flask (port 5000) → JazzDrive SAPI

---

## Critical Rules (never break these)

| Rule | Why |
|------|-----|
| `db.setting(k)` not `db.get_setting(k)` | Function doesn't exist → AttributeError |
| `sudo supervisorctl restart raddflix_radd` | NOT systemctl |
| Push via GitHub Contents/Trees API | No git shell on Replit main |
| Never parallel-push to GitHub | Creates SHA tree conflicts |
| `import 'dart:ui' show PlatformDispatcher;` | NOT exported by flutter/material.dart |
| sqflite_sqlcipher ≤ 3.1.0+1 | Breaks encrypted DB on older Android |
| Never `androidAttachSurfaceAfterVideoParameters:true` | Black screen |
| Check DebugLogger method exists before calling it | Past builds failed from missing methods |
| DebugDiagnosticsScreen NOT gated by kDebugMode | Intentional — release-accessible |

## Open Data Gap

- **DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from JazzDrive. Needs admin re-upload.
