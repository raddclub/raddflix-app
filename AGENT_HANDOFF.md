# AGENT_HANDOFF.md
> **Read this file first — every session, every agent, no exceptions.**
> Last updated: 2026-06-09

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
# Expected: {"ok":true,"version":"3.0.0"}

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
      mobile_api.py          — POST /api/auth/*, GET /api/usage/*, history, /api/app/config
      admin.py               — Admin panel API (db/reset, db/full-delete, users, etc.)
      subscriptions.py       — GET /api/subscription/plans|status
      library.py             — Admin panel, trending, WhatsApp blast
  run.py                     — Entry point, binds to localhost:5000
  data/
    radd_hub.db              — THE real database (DATA_DIR/radd_hub.db)
    media/                   — Staging area for files waiting to upload to JazzDrive
    backups/                 — Rolling SQLite backups (every 5 min via self_heal)
    logs/raddhub.log         — Main application log

Supervisor: /etc/supervisor/conf.d/raddflix.conf
Process name: raddflix_radd
Restart: sudo supervisorctl restart raddflix_radd
```

**⚠️ DB path warning:** There are many `.db` files scattered around `/opt/jazzmax/`.
The REAL database is always at `config.DB_PATH` = `/opt/jazzmax/radd-hub/data/radd_hub.db`.
Do NOT touch `/opt/jazzmax/radd_hub.db` or any hub-level `.db` files — those are stale copies.

**Server management commands (run via SSH):**
```bash
# Check status
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "sudo supervisorctl status"

# View logs
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "tail -100 /opt/jazzmax/radd-hub/data/logs/raddhub.log"

# Restart Flask
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "sudo supervisorctl restart raddflix_radd"
```

---

## db.py API — Important Function Names

```python
db.setting(k, default=None)    # READ a setting — NOT db.get_setting() (does not exist)
db.set_setting(k, v)           # WRITE a setting
db.conn()                      # Context manager — use for normal queries
                               # WARNING: do NOT use db.conn() for bulk DELETEs in WAL mode
                               # (background threads can silently block the write)
                               # Use direct sqlite3.connect() + BEGIN IMMEDIATE instead
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
    ...(sha ? { sha } : {}),
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

**Important:** Always fetch fresh SHA before each push. A stale SHA causes a 422 error.

**Do NOT use heredoc (`cat > file << 'END'`) to write scripts** — use the Replit `write` tool
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
11. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist in db.py

---

## SAPI Proxy Pool Architecture

> Critical for uploads to cloud.jazzdrive.com.pk

### Two proxy paths (never mix them)
| Path | Function | Purpose |
|------|---------|---------|
| `resolve_proxies(purpose='sapi')` | Uses `proxy_pool.py` pool | All JazzDrive SAPI/upload calls |
| `resolve_proxies(purpose='otp')` | Uses old single `JAZZDRIVE_PROXIES` setting | OTP/auth/refresh only |

### Current proxy state (as of 2026-06-06)
- `JAZZDRIVE_PROXY_BYPASS=1` — **all JazzDrive traffic goes DIRECT** (no proxy pool used)
- `JAZZDRIVE_PROXY_ENABLED=0` — manual proxy disabled
- WARP (`wg0`) is UP with split tunnel routing only 3 Jazz SAPI IPs (NOT JazzDrive upload host)
- Uploads go direct from Oracle IP `92.4.95.252`

### Pool management API (Settings page)
| Endpoint | Method | Purpose |
|---------|--------|---------|
| `/settings/api/pool/list` | GET | Full proxy list with scores |
| `/settings/api/pool/stats` | GET | Stats dashboard |
| `/settings/api/pool/bulk-import` | POST | Add 100+ proxies at once |
| `/settings/api/pool/test/<id>` | POST | Per-proxy live SAPI test |
| `/settings/api/pool/reset-dead` | POST | Re-enable all disabled proxies |
| `/settings/api/pool/export` | GET | Download proxy list as .txt |

---

## Upload / Auto-Delete System

- Upload watcher thread runs every 30s, scans `config.MEDIA_DIR` (`data/media/`)
- Files placed in `data/media/` are auto-queued for JazzDrive upload
- `upload_auto_delete=true` — local file deleted ONLY after successful upload with `share_url OR remote_id`
- If account session is expired → uploads fail → no share_url → files NEVER auto-deleted
- **Current state:** 2 test files stuck in `data/media/` (Pitt_Siyapa_2026.mp4, Vncenz0 S01E02) — waiting on OTP re-login for account 03286829827

---

## Current State (2026-06-08)

All code bugs fixed. Uploads fully working. 17 titles / 28 files — all Live.
Latest APK: **RaddFlix-1.0.0+1-build1034.apk** (run 27156269376, expires 2026-07-08).
> **Next build needed: 1035** — includes `pruneStaleIds()` permanent stale-entry cleanup (Flutter commits on GitHub, not yet built).

### Completed 2026-06-09 (TASK-058) — Fix: Flutter stale catalog after DB rebuild (BUG-STALE-IDS)

**Root cause:** Oracle DB was rebuilt with new title IDs (1–20). Flutter's cached `localVersion`
(1780929441) exactly matched the server version → Flutter said "Already up to date" → never
re-synced → kept stale entries (e.g. Spider-Noir `id=28`, `file_id=31` which no longer exists
→ 404 "Jazz SIM Required"). Even when sync ran, `/sync` is additive only, so old IDs remained.

**Server fixes (live immediately, affect build1034 now):**
- `POST /api/catalog/force-version-bump` → version bumped to `1781003205`
  (forced_ts > localVersion → every device triggers full re-sync on next app open)
- `/api/catalog/sync` now returns `valid_title_ids` list in response body
  (`hub/routes/catalog_api.py`)

**Flutter fixes (GitHub commits — next build 1035):**
| Commit | File | Change |
|--------|------|--------|
| e9107cb6 | `lib/core/api/catalog_api.dart` | `syncFull()` returns `SyncFullResult{items, validTitleIds}` |
| cb32f9ba | `lib/core/db/local_db.dart` | `pruneStaleIds(List<int> validIds)` — deletes titles+orphaned episodes not in valid set |
| b523de28 | `lib/core/db/sync_service.dart` | Full sync calls `pruneStaleIds()` after persisting items |
| 338ad31b | `lib/core/db/local_db.dart` | Fix `$placeholders` in pruneStaleIds SQL (bash heredoc ate the Dart variable) |

**Encryption/Decryption audit (2026-06-09) — all PASS:**
- Flutter `RequestEncoder` + `_XorInterceptor`: ✅ no issues
- Server `request_encoding.py`: ✅ no issues (±1h candidate keys, padding, fallback)
- `CatalogItem.fromJson()`: ✅ all fields safe-cast
- `scrambleUrl`/`unscrambleUrl`: ✅ RF1: prefix guard, passthrough for legacy plain URLs

### Completed 2026-06-08 (TASK-057) — A-Z Full Audit
- **FIX-ISONGOING**: zero_rating.py — `is_ongoing` string "0" truthy in Python → int() cast
- **FIX-XOR-NEXTHR**: request_encoding.py — `_candidate_keys` missing +1 hour window
- **BUG-TAB-01**: show_detail_screen.dart — TabController memory leak on pull-to-refresh
- **BUG-DL-THROTTLE**: download_service.dart — SQLite progress DB flooded (100s writes/sec)
- **FIX-URI-01**: splash_screen.dart — URI deep-link parse drops query params
- **FIX-LIKE-01**: local_db.dart — LIKE query didn't escape % / _ meta-chars
- **FIX-SEARCH-INIT**: search_screen.dart — initialFilter didn't trigger _doSearch()
- **FIX-ID-CAST**: catalog_item.dart — json['id'] as int throws TypeError on null

### Completed 2026-06-08 (TASK-048 → TASK-056)
- TASK-048/050/051: JazzDrive duplicate upload guards (all paths)
- TASK-049: Delta folder cleanup (26 orphaned files removed)
- TASK-052: Delta pre-purge before upload
- TASK-053/055/056: Data flow verification (all checks A–J passed)
- TASK-054: TV show episodes missing from delta (zero_rating.py + jazzdrive_service.dart)

### Previously completed (2026-06-07)
- Full proxy audit, BUG-A03a–e fixed, agent-hub docs created, GitHub synced

### Previously completed (2026-06-06)
- BUG-A01/A02 fixed, IMDbAPI URL fix, Admin reimport endpoint, WARP tunnel, proxy pool

### Open (data gap — not code bugs)
- **DATA-01**: All Of Us Are Dead missing E03/E04/E05/E09 — need JazzDrive upload + sync
- **DATA-02**: 9 movies with deleted JD files — need admin re-upload to JazzDrive

### JazzDrive — critical notes

**3-pass filename match** (in `jazzdrive_service.dart`):
- Pass 1: direct substring match (e.g. "E01" in record name)
- Pass 2: normalised spaces match
- Pass 3: episode code match — builds `s01e04` style code and searches
  WARNING: NEVER use backslash-dollar in Dart strings generated by scripts.
  Use concatenation. Pass3 was dead for this reason (fixed commit 778b33e).

**Test suite**: `raddflix_flutter/test_suite/jazzdrive_logic_test.js` — 27 tests
  - Run anywhere: `node jazzdrive_logic_test.js`
  - Full network test on Jazz SIM: `node jazzdrive_logic_test.js --live <shareUrl> [target]`

See `.agents/tasks/BUG_TRACKER.md` for full bug table.


## Session 2026-06-09 (2nd) — JD File ID Audit: VERIFIED CORRECT

### Question Investigated
How does JazzDrive identify files (for delete, rename, play)? Is there a permanent ID?
Are we using the correct ID throughout the Flutter → Oracle → JazzDrive chain?

### Answer: YES — system uses `remote_id` correctly everywhere

**JD permanent file ID = `remote_id`** (called `id` in JD SAPI responses, e.g. `242518443`)
- Assigned at upload, **never changes** — survives renames and folder moves
- Oracle uses it in `rename_video()` and `delete_files_permanent()` ✅

**Full verified chain (all PASS):**

| Layer | Component | Status |
|-------|-----------|--------|
| Oracle DB | `files.remote_id` stores JD permanent file ID | ✅ |
| Oracle API | `/api/catalog/sync` returns `remote_id` per episode | ✅ |
| Flutter sync | `_persistItems()` writes `remote_id` to SQLite episodes table | ✅ |
| Flutter DB | `episodes.remote_id INTEGER` column exists (via ALTER TABLE) | ✅ |
| Flutter DB | `getShareInfo()` reads and returns `remote_id` | ✅ |
| Flutter player | `remoteId = shareInfo['remote_id']` → passed to `getStreamLink` | ✅ |
| Flutter JD service | Pass 0 in `_getMedia()`: `m['id'] == remoteId` → exact file match | ✅ |

**Folder share pattern (Spider-Noir, Vincenzo):**
Both episodes of a show share the same folder share URL. JD returns both files in the
SAPI media response. Pass 0 uses `remote_id` to pick the correct one:
- Spider-Noir S01E01: remote_id=242518443 → `m['id']==242518443` → S01E01 ✅
- Spider-Noir S01E02: remote_id=242518530 → `m['id']==242518530` → S01E02 ✅
- Cache keys are separate ("37" vs "36") → each episode gets its own CDN URL ✅

### No code changes needed. System was already correct.
