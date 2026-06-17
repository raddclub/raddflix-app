# RaddFlix Agent Handoff
Updated: 2026-06-17 | Flask running port 5000 at /opt/jazzmax/radd-hub

## Current System State
- **Oracle Flask:** RUNNING — `{"ok":true,"version":"3.0.0"}`
- **Account id=11** (03257719165): VK ✅ JID ✅ raw_accesstoken ✅ (40 hex chars) refresh_token ✅
- **JazzDrive chain:** PROVEN — full login→media→CDN chain tested with real video bytes (HTTP 206, ftyp isom confirmed 2026-06-16)
- **Proxy pool:** 150+ active proxies, all healthy (fail_count=0)
- **Flutter app:** All known bugs fixed. Player UX improved (8 features, commits 01fc775f + bd75f9d6). APK build needed for new features.
- **Debug screen:** Live in release builds — tap version text 5× in Profile to open

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
lib/core/db/local_db.dart                SQLCipher DB, schema v17+
lib/core/services/jazzdrive_service.dart JazzDrive stream + download + diagnosticTest()
lib/screens/player_screen.dart           Video player
lib/screens/show_detail_screen.dart      Show/movie detail + season tabs + episode tiles
lib/screens/debug_diagnostics_screen.dart Diagnostics (release-accessible, 5-tap entry)
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

## Debug Diagnostics Screen

**Entry:** Profile screen → tap version text 5 times → `DebugDiagnosticsScreen` opens

**Checks tab** (auto-runs on open):
1. Oracle Server — hits `/healthz`
2. **JazzDrive API** — live end-to-end test: picks first episode or movie from local SQLite, decodes share_url, calls `JazzDriveService.diagnosticTest()`, shows Login/Media/URL per step
3. XOR Decode — hits `/api/catalog/version`
4. DB Row Counts — counts titles, episodes, movies, shows
5. Auth Tokens — checks Keystore + user plan
6. Sync Meta — reads `sync_meta` table
7. Device ID — shows masked ID + session key

**Live Logs tab** — streams `DebugLogger._memBuffer` every 2s
- Filters: ALL / ERROR / WARN / JAZZDRIVE / API / SYNC / DB
- JAZZDRIVE filter isolates JazzDrive log lines (green color)
- Share button exports full log file

**`JazzDriveService.diagnosticTest()`:**
```dart
// Returns: { share_key, login, media, stream_url } on success
//       or { error } on failure at any step
static Future<Map<String, dynamic>> diagnosticTest({
  required String shareUrl,
  String? targetFilename,
  int remoteId = 0,
})
```

| Player UX — floating ball | White 40px circle visible when controls hidden. Tap=show controls, drag=reposition. State: `_ballOffset`, `_sidebarMode`, `_clockStr`, `_clockTimer`. |
| Player sidebar 3-state | Chevron at top of right rail: full(58px)→icons-only(40px)→hidden. Persisted in `PlayerPrefs.sidebarMode`. All 11 `_MxSideBtn` calls use `iconsOnly: sidebarMode==1`. |
| Speed picker → horizontal track | `_SpeedPanel` (right-side list) replaced by `_SpeedTrackPanel` (top bar). Active=13px #4DB6FF dot; inactive=7px white38. |
| Background play foreground service | When `_bgPlayEnabled=true` and app goes to background, `startBgPlayback` is invoked via pip channel → starts `PlaybackService` (foreground, mediaPlayback type). On resume or dispose, `stopBgPlayback` stops the service. Never start the service when bgplay is OFF. |
| PiP exit detection | `MainActivity.onPictureInPictureModeChanged(false)` sends `onPipExited` via PIP channel. Flutter `_initPipChannel()` handler sets `_inPiP=false`. This is the ONLY place `_inPiP` is reset. |
| audio_session vs audio_service | Only `audio_session` is in pubspec (handles audio focus). The `audio_service` package (foreground service) is NOT and was never added. Background process survival uses our own `PlaybackService.kt`, not any Flutter package. |
| **Do NOT re-add `kDebugMode` gate** to `DebugDiagnosticsScreen` — it is intentionally release-accessible. See `BUG_TRACKER.md` Critical Rules.

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
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" \
  | grep -E '"id"|"status"|"conclusion"|"message"' | head -20
```

### Run JazzDrive chain live from Oracle (verify CDN URLs are real)
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 'python3 -c "
import requests, urllib.parse, sqlite3
# Get a share_url from DB
db = sqlite3.connect(\"/opt/jazzmax/radd-hub/data/radd_hub.db\")
row = db.execute(\"SELECT share_url, remote_id FROM files WHERE share_url != \"\"\" LIMIT 1\").fetchone()
print(row)
"'
```
