# RaddFlix Agent Handoff
Updated: 2026-06-16 | Flask running port 5000 at /opt/jazzmax/radd-hub

## Current System State
- **Oracle Flask:** RUNNING — `{"ok":true,"version":"3.0.0"}`
- **Account id=11** (03257719165): VK ✅ JID ✅ raw_accesstoken ✅ (40 hex chars) refresh_token ✅
- **Proxy pool:** 150+ active proxies, all healthy (fail_count=0)
- **JazzDrive upload:** WORKING — session auto-recovers on Flask restart via `sapi_direct_login()` fallback
- **Flutter app:** All known bugs fixed as of 2026-06-16 (see BUG_TRACKER.md for rules)

---

## Architecture Overview

### Oracle Server (92.4.95.252)
- Flask app at `/opt/jazzmax/radd-hub/hub/` — port 5000 (not public, SSH tunnel only)
- SQLite DB: `/opt/jazzmax/radd-hub/data/radd_hub.db`
- Logs: `/opt/jazzmax/radd-hub/data/logs/raddhub.log`
- Supervisor: `sudo supervisorctl restart raddflix_radd`

### JazzDrive Session Flow
1. **startup_refresh:** Android OAuth2 via wg0 → rotates RT chain → gets AT+RT
2. **Fallback:** `sapi_direct_login()` uses DB `raw_accesstoken` to get fresh VK+JID from SAPI directly (no OAuth2 needed)
3. **SAPI calls:** All use `raw_accesstoken` (OTP-issued) as `key=` param — OAuth2-rotated tokens DO NOT work with SAPI
4. **Keepalive:** SAPI ping every 20 min + heartbeat upload every 6 h

### Flutter App
- Dart code lives only in GitHub (`raddclub/raddflix-app`) — NOT checked out on Oracle
- Push Flutter fixes via GitHub API only (blobs → tree → commit → PATCH ref)
- XOR encode/decode: server key = UTC hour; Flutter re-adds base64 `=` padding before decode
- JazzDrive stream: `jazzdrive_service.dart` → `_loginShare()` → `_buildStreamUrl()` (CDN URL, no validationkey)
- Catalog sync: `catalog_provider.dart` has `_initialized` guard + no-op skip when `itemsSynced==0`

---

## Key File Paths

### Oracle
```
hub/jazzdrive.py          JazzDrive session, OTP, upload, keepalive, sapi_direct_login()
hub/proxy_pool.py         Proxy pool management
hub/keepalive.py          Heartbeat + SAPI ping scheduler
hub/routes/catalog_api.py /api/catalog/*
hub/routes/mobile_api.py  /api/auth/*, usage, history, /api/app/config
hub/routes/admin.py       Admin panel API
```

### Flutter
```
lib/core/security/request_encoder.dart   XOR decode + padding fix (critical)
lib/core/api/api_client.dart             Dio + XOR + auth interceptors
lib/core/db/local_db.dart                SQLCipher DB, schema v17
lib/core/services/jazzdrive_service.dart JazzDrive stream + download (_loginShare, _buildStreamUrl)
lib/screens/player_screen.dart           Video player
lib/screens/show_detail_screen.dart      Show/movie detail + season tabs + episode tiles
lib/providers/auth_provider.dart         Auth state + session restore
lib/providers/catalog_provider.dart      Catalog sync (_initialized guard + no-op skip)
```

### Coordination (GitHub main)
```
agent-hub/TASKS.md          Open tasks — READ FIRST every session
agent-hub/RULES.md          Full rules list
agent-hub/CONTEXT.md        System context
AGENT_HANDOFF.md            This file
.agents/tasks/BUG_TRACKER.md  Known bugs + critical rules
agent-hub/history/TASK_LOG.md Session history
```

---

## Common Commands

### Verify Oracle is alive
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```

### Restart Flask
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sleep 3 && curl -s http://localhost:5000/healthz"
```

### Oracle git pull
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cd /opt/jazzmax/radd-hub && git stash && git pull && git stash pop"
```

### Trigger APK build
```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'
```

### Check build status
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
    JSON.parse(d).workflow_runs.forEach(r=>
      console.log('run#'+r.run_number,'|',r.status,'|',(r.conclusion||'-'),'| commit:',r.head_sha.slice(0,7)));
  });"
```
