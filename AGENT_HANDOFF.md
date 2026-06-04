# AGENT_HANDOFF.md
> **Read this file first — every session, every agent, no exceptions.**
> Last updated: 2026-06-04

---

## What is RaddFlix?

Pakistani Flutter streaming app, zero-rated on Jazz SIM.
Users pay PKR 149–399/month. Content served from JazzDrive CDN.
Backend: Flask server on Oracle Ubuntu VPS at `92.4.95.252`.

---

## Secrets — already in Replit Secrets tab

| Key | Purpose |
|-----|---------|
| `GITHUB_TOKEN` | GitHub PAT — repo read/write |
| `ORACLE_SSH_KEY` | Full PEM private key for SSH to Oracle |
| `SESSION_SECRET` | Express session secret (not used by agents) |

---

## Step 0 — Always do this first (copy-paste into Replit shell)

```bash
# Restore SSH key from Replit secret
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing or malformed'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  {mode: 0o600});
console.log('SSH key written to /tmp/oracle_key');
"

# Verify Oracle is alive (use localhost via SSH — port 5000 NOT publicly exposed)
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
# Expected: {"status":"ok","version":"3.0.0",...}

# Read current state
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/AGENT_HANDOFF.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -150
```

---

## Architecture

### XOR Request Encoding — THE most important thing to understand

Every `/api/*` response from Oracle is XOR-encoded. **Excluded paths** (plain JSON):
- `/api/auth/login`, `/api/auth/register`, `/api/auth/refresh`, `/api/auth/guest`, `/healthz`

**How it works:**
1. Client sends `X-Device-Id: <sha256-of-device-id>` header on every request
2. Server XOR-encodes the response body, encodes as base64-urlsafe, **strips `=` padding**
3. Client receives `X-Encoded: 1` header → decodes: re-add padding, base64-decode, XOR with same key
4. Key formula (must match exactly on both sides):
   `key = SHA-256("raddflix_xor_v1:{deviceId}:{utc_day}:{utc_hour}")[:32]`

**The critical padding fix** (root cause of all 5 initial bugs):
```dart
// In request_encoder.dart — MUST exist or base64Url.decode throws FormatException
final pad = (4 - b64.length % 4) % 4;
b64 += '=' * pad;
```
The server uses Python `rstrip(b"=")` which removes 1–2 padding chars. Without re-adding them, every XOR decode throws and the whole catalog/auth/plans system breaks silently.

### Local Database

- **Package: `sqflite_sqlcipher: 3.1.0+1` — PINNED, NEVER upgrade**
  (SQLCipher Dart API changed after this version, breaks DB key derivation)
- DB encryption key: generated once on install, stored in Android Keystore, never leaves device
- Schema version: 17
- Tables: `titles`, `episodes`, `sync_meta`, `watch_positions`, `downloads`,
  `stream_cache`, `usage_log`, `quota_cache`, `show_ep_seen`

### Authentication Flow

1. `POST /api/auth/login` — plain JSON (XOR excluded), returns access + refresh tokens
2. Tokens stored in Android Keystore via `flutter_secure_storage`
3. `GET /api/auth/me` — XOR-encoded, returns user plan/phone → cached in `SharedPreferences`
4. App restart: `checkAuth()` reads SharedPrefs cache → instant session restore (works offline)
5. Access token: 7-day JWT · Refresh token: 90-day JWT (auto-refreshed transparently)

### Catalog Sync

1. `GET /api/catalog/version` → compare with local `sync_meta` table
2. If version differs: fetch `/api/catalog/titles` + `/api/catalog/episodes`
3. Upsert into SQLite → update `sync_meta` record
4. On any sync failure → fall back to local DB (offline mode)

### Video Playback

- Packages: `media_kit ^1.1.10` + `media_kit_video ^1.2.4`
- **NEVER use `androidAttachSurfaceAfterVideoParameters: true`** in `VideoController`
  (causes 3–5 second black screen before video plays on Android)
- Stream links: `POST /api/stream/link`, cached 180 min in `stream_cache` table

---

## Oracle Server Layout

```
ubuntu@92.4.95.252
/opt/jazzmax/radd-hub/
  hub/
    app.py                   — Flask factory + WSGI XOR middleware
    request_encoding.py      — XOR after_request hook (strips padding here)
    db.py                    — SQLite schema + migrations
    routes/
      catalog_api.py         — GET /api/catalog/version|titles|episodes
      mobile_api.py          — POST /api/auth/*, GET /api/usage/*, history
      subscriptions.py       — GET /api/subscription/plans|status
      library.py             — Admin panel, trending, WhatsApp blast
  run.py                     — Entry point, binds to localhost:5000

Supervisor: /etc/supervisor/conf.d/raddflix.conf
Process name: raddflix_radd
Log: /var/log/supervisor/raddflix_radd.log
```

**Server management commands (run via SSH):**
```bash
# Check status
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "supervisorctl status"

# View last 100 log lines
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "tail -100 /var/log/supervisor/raddflix_radd.log"

# Deploy server changes (safe — stash, pull, pop, restart)
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 \
  "cd /opt/jazzmax && git stash && git pull origin main && git stash pop && supervisorctl restart raddflix_radd"
```

---

## Flutter App File Map

```
raddflix_flutter/lib/
  main.dart                       entry — DebugLogger.init(), FlutterError.onError handler
  app.dart                        MaterialApp, named routes, theme bootstrap
  core/
    api/
      api_client.dart             Dio client with XOR interceptor + auth interceptor
      catalog_api.dart            /api/catalog/* calls
      subscription_api.dart       /api/subscription/* calls
    constants.dart                AppRoutes, ApiPaths, AppConfig (Oracle base URL)
    db/
      local_db.dart               SQLCipher DB, schema v17, all CRUD operations
      sync_service.dart           Catalog sync against Oracle
    debug/
      debug_logger.dart           In-memory + file logger; getLastLines(), shareLogs()
    player/
      player_prefs.dart           Playback preferences (subtitles, gestures, equalizer)
      scene_bookmark_store.dart   Per-show resume positions
    security/
      device_id.dart              Stable SHA-256 device ID (survives reboots)
      keystore.dart               Android Keystore token storage
      request_encoder.dart        XOR encode/decode WITH padding fix
    theme/
      radd_theme.dart             Theme tokens (colors, radius, curves, spacing)
      theme_provider.dart         Riverpod theme state (dark/amoled/light/auto)
  providers/
    auth_provider.dart            Auth state, login, logout, checkAuth, session restore
    catalog_provider.dart         Catalog state, sync, loadFromDb fallback
    subscription_provider.dart    Sub status and plan state
    watchlist_provider.dart       Watchlist CRUD
  screens/
    debug_diagnostics_screen.dart DEBUG ONLY — kDebugMode-gated, stripped from release
    player_screen.dart            VideoController (no androidAttachSurface!)
    profile_screen.dart           7-tap version text → debug screen (kDebugMode only)
    ... all other screens
```

---

## GitHub API — How to Push Files (NEVER use git shell)

```javascript
const https = require('https');
const TOKEN = process.env.GITHUB_TOKEN;
const REPO  = 'raddclub/raddflix-app';

// 1. Get current SHA (required for updates, omit for new files)
async function getSha(path) {
  return new Promise(r => {
    const opts = {
      hostname: 'api.github.com', port: 443,
      path: `/repos/${REPO}/contents/${path}`, method: 'GET',
      headers: { 'Authorization': `token ${TOKEN}`, 'User-Agent': 'agent',
                 'Accept': 'application/vnd.github.v3+json' }
    };
    const req = https.request(opts, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => { try { r(JSON.parse(d).sha || null); } catch { r(null); } });
    });
    req.on('error', () => r(null)); req.end();
  });
}

// 2. Push a file
async function putFile(path, content, message, sha) {
  const body = JSON.stringify({
    message,
    content: Buffer.from(content, 'utf8').toString('base64'),
    ...(sha ? { sha } : {}),   // omit sha entirely for new files
  });
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'api.github.com', port: 443,
      path: `/repos/${REPO}/contents/${path}`, method: 'PUT',
      headers: { 'Authorization': `token ${TOKEN}`, 'User-Agent': 'agent',
                 'Accept': 'application/vnd.github.v3+json',
                 'Content-Type': 'application/json',
                 'Content-Length': Buffer.byteLength(body) }
    };
    const req = https.request(opts, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => {
        const r = JSON.parse(d);
        if (r.content) resolve(r);
        else reject(new Error(r.message || 'push failed'));
      });
    });
    req.on('error', reject); req.write(body); req.end();
  });
}
```

**Important:** Always fetch fresh SHA before each push. A stale SHA (from a previous
session or commit) causes a 422 "is at X but expected Y" error.

**Do NOT use heredoc (`cat > file << 'END'`) to write scripts** — the bash tool scans
heredoc content for git commands and may block it. Instead use the Replit `write` tool
to create script files, then run with `node /path/to/script.js`.

---

## Non-Negotiable Rules (full list in `.agents/PROJECT_RULES.md`)

1. Never use git shell commands — GitHub Contents API only
2. Never commit secrets — GITHUB_TOKEN and ORACLE_SSH_KEY in Replit Secrets only
3. Never touch Oracle destructively without explicit user approval
4. Never upgrade `sqflite_sqlcipher` past 3.1.0+1
5. Debug code must be gated behind `kDebugMode`
6. XOR padding fix must always be present in `request_encoder.dart`
7. Never use `androidAttachSurfaceAfterVideoParameters: true`
8. Always append to `agent-hub/history/TASK_LOG.md` after your session
9. Always fetch fresh SHA before pushing any file
10. Test Oracle via SSH tunnel, not direct IP

---

## Current State (2026-06-04)

All critical bugs fixed. No known open issues.

Fixed: XOR base64 padding, api_client type safety, VideoController black screen,
catalog sync fallback, debug diagnostics screen added with logcat viewer.

See `.agents/tasks/BUG_TRACKER.md` for full table.
