# RaddFlix — Full System Audit Prompt
> **For a new Replit agent account starting fresh.**
> Date written: 2026-06-08. Copy this entire file as your task prompt.
> Work through every section in order. Fix everything you find.

---

## Your Mission

Perform a complete audit of the RaddFlix codebase — Flutter app, Flask backend, and all
agent-hub documentation. Find every:
- Gap between what the docs say and what the code actually does
- Feature that is half-built or not yet wired
- Logic error or inconsistency
- Missing error handling
- Stale/wrong comment or doc claim

Fix everything you find. Leave nothing open. Update the docs to match reality when done.

---

## Step 0 — Environment Setup (do this first, every time)

### Set up SSH key
```bash
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('ORACLE_SSH_KEY missing'); process.exit(1); }
require('fs').writeFileSync('/tmp/oracle_key',
  m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
  { mode: 0o600 });
console.log('SSH key ready');
"
```

### Verify Oracle is alive
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"
```
Expected: `{"ok":true,"version":"3.0.0"}`

### Read current state
```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/HANDOFF_NEXT.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -100
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md" | tail -60
```

### GitHub push method — ONLY this, never git shell
```python
import json, os, urllib.request

TOKEN = os.environ['GITHUB_TOKEN']
BASE  = 'https://api.github.com/repos/raddclub/raddflix-app'

def gh(method, path, body=None):
    req = urllib.request.Request(BASE + path,
        data=json.dumps(body).encode() if body else None,
        headers={'Authorization': f'token {TOKEN}',
                 'Accept': 'application/vnd.github.v3+json',
                 'Content-Type': 'application/json',
                 'User-Agent': 'raddflix-agent'},
        method=method)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

# Multi-file atomic commit (Trees API):
ref       = gh('GET', '/git/refs/heads/main')
head_sha  = ref['object']['sha']
base_tree = gh('GET', f'/git/commits/{head_sha}')['tree']['sha']
tree      = [{'path': 'path/to/file', 'mode': '100644', 'type': 'blob',
              'content': open('/tmp/file').read()}]
new_tree  = gh('POST', '/git/trees', {'base_tree': base_tree, 'tree': tree})
new_commit= gh('POST', '/git/commits', {'message': 'msg', 'tree': new_tree['sha'], 'parents': [head_sha]})
gh('PATCH', '/git/refs/heads/main', {'sha': new_commit['sha'], 'force': False})
```

---

## Step 1 — Read ALL Agent-Hub Docs First

Before touching any code, read every doc. Build a mental model of what the system is
supposed to do, then verify the code matches.

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/CONTEXT.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/RULES.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/STREAMING_ARCHITECTURE.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/ZERO_RATING_DELTA.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SECURITY_ARCHITECTURE.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/PRODUCT_CONTEXT.md"
```

---

## Step 2 — Known Discrepancies (Verify and Fix These First)

These gaps were found during audit on 2026-06-08. **Verify each one against actual code,
then fix the code or docs as appropriate.**

---

### DISCREPANCY-01 — RequestEncoder.enabled: docs say false, code says true

**What docs say** (`SECURITY_ARCHITECTURE.md`, Layer 5 status table):
> XOR API encoding — Flutter side: `enabled=false`

**What code actually has** (`lib/core/security/request_encoder.dart`):
```dart
static bool enabled = true;
```

**What you must do:**
1. Check whether the Oracle server actually decodes XOR in production:
   ```bash
   ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
     "grep -n 'xor\|XOR\|RequestEncoder\|request_encoding' /opt/jazzmax/radd-hub/hub/app.py /opt/jazzmax/radd-hub/hub/routes/*.py 2>/dev/null | head -40"
   ```
   Also check if `request_encoding.py` is imported and applied:
   ```bash
   ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
     "cat /opt/jazzmax/radd-hub/hub/request_encoding.py 2>/dev/null || echo 'FILE NOT FOUND'"
   ```

2. **If server decodes XOR (both sides active):** Update `SECURITY_ARCHITECTURE.md`
   status table to `enabled=true` and mark as ✅ Active. This is the correct state.

3. **If server does NOT decode XOR:** Then `enabled=true` in Flutter will break all
   API calls because server sees garbled base64. Set `enabled=false` in `request_encoder.dart`
   immediately and fix `SECURITY_ARCHITECTURE.md` to say disabled pending server deploy.

4. **CRITICAL — Test after your decision:** Make a test API call through SSH tunnel to
   verify the app would still get real catalog data. Do not leave this state ambiguous.

---

### DISCREPANCY-02 — MainActivity.kt: docs say security channel not wired, but it IS

**What docs say** (`SECURITY_ARCHITECTURE.md`, Native Channel TODO section):
> "The following MethodChannel handlers need to be added to `MainActivity.kt`"

**What code actually has** (`android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt`):
All three handlers ARE fully implemented:
- `getSignatureFingerprint` — reads APK signing cert, computes SHA-256
- `checkFrida` — scans `/proc/self/maps` for frida/gadget strings
- `checkRoot` — checks su binary paths

**What you must do:**
1. Confirm by reading the actual file — do not trust these notes alone.
2. Update `SECURITY_ARCHITECTURE.md`:
   - Remove the "Native Channel TODO" section (it's done)
   - Update the security layers status table:
     - APK signature check → `⚠️ Pending fingerprint config` (channel wired, just needs real cert)
     - Frida detection → `✅ Active` (both port check AND native /proc/maps check wired)
   - Update the summary at the bottom

---

### DISCREPANCY-03 — AppGuard fingerprint placeholder: enforcement is still OFF

**Current state** (`lib/core/security/app_guard.dart`):
```dart
static const String _officialFingerprint = 'RADDFLIX_CERT_SHA256_PLACEHOLDER';
```

The signature check correctly skips itself when this placeholder is detected.
**This means: cracked APKs are NOT blocked today.**

**What you must do:**
1. This requires a real signed APK to get the actual fingerprint. You cannot fix this
   in code without the user building a signed APK.
2. Add a clear **⚠️ PENDING USER ACTION** note to `HANDOFF_NEXT.md` and `SECURITY_ARCHITECTURE.md`:
   - Explain exactly what the user must do:
     1. Build a signed release APK (GitHub Actions `build-apk.yml`)
     2. Download the APK from CI artifacts
     3. Run: `keytool -printcert -jarfile app-release.apk`
     4. Find the `SHA-256:` line
     5. Replace `RADDFLIX_CERT_SHA256_PLACEHOLDER` with that value in `app_guard.dart`
     6. Push → rebuild → enforcement is live

---

### DISCREPANCY-04 — PRODUCT_CONTEXT.md: "Delta JSON — NO share URLs, NO file IDs"

**What docs say** (`PRODUCT_CONTEXT.md`, Security Architecture table):
> Delta JSON on JazzDrive: Metadata only — NO share folder URLs, NO file IDs

**What is actually true:** delta.json DOES include `share_url`, `file_id`, `folder_share_url`,
and full episode lists. This is the ENTIRE POINT of the delta system — Jazz SIM users
need share_urls to play content without Oracle.

**What you must do:**
Update `PRODUCT_CONTEXT.md` Security Architecture section. The correct description:
> Delta JSON on JazzDrive: Full playback data — includes share_urls and file_ids.
> Security enforced by APK integrity (AppGuard), not by withholding URLs.

---

### DISCREPANCY-05 — PRODUCT_CONTEXT.md: "Every day after" flow is outdated

**What docs say** (`PRODUCT_CONTEXT.md`, "Every day after (zero-rated mode possible)"):
> App opens → reads local SQLite → shows full catalog instantly
> ↓ Tries to fetch delta JSON from JazzDrive (zero-rated)

**What actually happens:**
1. `RemoteConfig.loadCached()` → instant SharedPreferences load, sets `jd_delta_url`
2. Oracle sync attempted FIRST (`SyncService._syncFromOracle()`)
3. If Oracle times out in 5s (no bundle) → JazzDrive delta fallback
4. `RemoteConfig.fetchBackground()` → fire-and-forget Oracle config refresh

The flow shown in `PRODUCT_CONTEXT.md` skips the Oracle-first step entirely.

**What you must do:**
Update the "Every day after" flow in `PRODUCT_CONTEXT.md` to match the actual sequence
documented in `STREAMING_ARCHITECTURE.md`.

---

### DISCREPANCY-06 — share_url scrambling: exists in code, NOT wired in local_db.dart

**What docs say** (`SECURITY_ARCHITECTURE.md`, Layer 4 status):
> ⚠️ NOT YET WIRED — `RequestEncoder.scrambleUrl()` and `.unscrambleUrl()` exist
> but `local_db.dart` does not yet call them on share_url read/write.

**Verified correct** — `scrambleUrl()` and `unscrambleUrl()` exist in `request_encoder.dart`
but `local_db.dart` does not call them.

**What you must do:**
This is a REAL SECURITY GAP. If someone roots a device and breaks SQLCipher,
share_urls are exposed as plain text.

Wire the scrambling in `local_db.dart`:
```dart
// Import DeviceId at top:
import '../security/device_id.dart';
import '../security/request_encoder.dart';

// In mergeDeltaTitle() — before INSERT/UPDATE:
final deviceId = await DeviceId.get();
final safeShareUrl = shareUrl.isNotEmpty
    ? RequestEncoder.scrambleUrl(shareUrl, deviceId) : '';
final safeFolderUrl = folderShareUrl.isNotEmpty
    ? RequestEncoder.scrambleUrl(folderShareUrl, deviceId) : '';

// In getShareUrl() / wherever share_url is READ back:
final raw = row['share_url'] as String? ?? '';
return RequestEncoder.unscrambleUrl(raw, deviceId);

// Same pattern for upsertEpisode() episode share_urls
// Same pattern for _persistItems() (Oracle sync path)
```

**Important:** Before wiring, read `local_db.dart` fully to understand all the places
where `share_url` is written and read. There will be several. Wire ALL of them.
Also: existing rows in SQLite have plain URLs. `unscrambleUrl()` handles this:
it passes through any URL that doesn't start with `RF1:` (backward compatible).

---

## Step 3 — Systematic Code Audit (File by File)

For each file below: download it, read it completely, then verify every claim.

### 3A — Flutter Core: `lib/core/api/api_client.dart`

Download and verify:
```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/api/api_client.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following:**
- [ ] `connectTimeout` is 6 seconds (NOT 15s — was fixed in TASK-042)
- [ ] `receiveTimeout` is 30 seconds (large catalog downloads need this)
- [ ] XOR `_AuthInterceptor` sends `Authorization: Bearer <token>` header correctly
- [ ] XOR decode is called on responses — the padding fix `(4 - b64.length % 4) % 4` is present
- [ ] `AppGuard.isTampered` check: when tampered, returns empty/fake response
- [ ] `X-Device-Id` header is sent on every request
- [ ] Base URL is `AppConstants.apiBaseUrl` (mutable — updated by RemoteConfig)
- [ ] Type guard exists: `data is String ? jsonDecode(data) : data` (BUG-D01 fix)

---

### 3B — Flutter Core: `lib/core/db/sync_service.dart`

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/db/sync_service.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following:**
- [ ] `sync()` tries Oracle FIRST, falls to delta on ANY exception
- [ ] `CatalogApi.getVersion()` has `.timeout(const Duration(seconds: 5))` (TASK-042)
- [ ] `syncFull()` and `syncDelta()` do NOT have short timeouts (they need 30s)
- [ ] `_syncFromJazzDriveDelta()` uses `AppConstants.jazzDriveDeltaUrl` (set by RemoteConfig)
- [ ] If `jazzDriveDeltaUrl` is empty, delta is skipped gracefully (no crash)
- [ ] `_resolveJazzDriveDocumentUrl()` hits `cloud.jazzdrive.com.pk` directly (NEVER Oracle)
- [ ] `LocalDb.mergeDeltaTitle()` is called (not raw INSERT — that would overwrite user data)
- [ ] Debug logs are gated behind `kDebugMode` or `DebugLogger` wrapper

---

### 3C — Flutter Core: `lib/core/remote_config.dart`

**Check ALL of the following:**
- [ ] `loadCached()` reads ONLY from `SharedPreferences` — zero network calls
- [ ] `loadCached()` calls `_applyData()` which sets `AppConstants.jazzDriveDeltaUrl`
- [ ] `fetchBackground()` has 4-second timeout (`receiveTimeout` + `sendTimeout`)
- [ ] `fetchBackground()` wraps everything in try/catch and silently swallows errors
- [ ] `fetchBackground()` writes to SharedPreferences cache after success
- [ ] `fetch()` shim exists and calls `fetchBackground().ignore()` (backwards compat)
- [ ] `AppConstants.apiBaseUrl` is updated if the config returns a new `api_base_url`
- [ ] Brand config keys (primary_color, tagline, etc.) are applied by `_applyData()`

---

### 3D — Flutter: `lib/main.dart`

**Check ALL of the following:**
- [ ] `await RemoteConfig.loadCached()` is called BEFORE `runApp()`
- [ ] `unawaited(RemoteConfig.fetchBackground())` is called AFTER `runApp()`
- [ ] `await AppGuard.initialize()` is called BEFORE any network or DB operations
- [ ] `MediaKit.ensureInitialized()` is called before runApp
- [ ] `ConnectivitySyncService.start()` is called AFTER `runApp()` (not before)
- [ ] `unawaited(JazzDriveService.warmTopFreeItems(8))` is fire-and-forget
- [ ] `HistoryApi.flushUnsynced()` is fire-and-forget (`.ignore()`)
- [ ] `UsageService.flushPending()` is fire-and-forget
- [ ] No unnecessary `await` chains before `runApp()` that would slow startup

---

### 3E — Flutter Security: `lib/core/security/app_guard.dart`

**Check ALL of the following:**
- [ ] `_officialFingerprint = 'RADDFLIX_CERT_SHA256_PLACEHOLDER'` — enforcement OFF (expected)
- [ ] When placeholder detected, `_checkSignature()` returns early WITHOUT setting `isTampered`
- [ ] Frida port check: `127.0.0.1:27042` with 400ms timeout — connection refused = good
- [ ] `isTampered = true` is set if Frida port connects (not refused)
- [ ] `_checkRoot()` does NOT set `isTampered` — only sets `isRooted` (intentional: root ≠ crack)
- [ ] `SecurityTelemetry.reportTamperAttempt()` is called — verify `security_telemetry.dart` exists
  and what it actually does (ping Oracle? Log locally? Nothing yet?)
- [ ] `shouldShowRealContent` getter returns `!isTampered` — correct

**Find `security_telemetry.dart`:**
```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/security/security_telemetry.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```
Verify it doesn't accidentally do something harmful (like crashing or sending PII).

---

### 3F — Flutter Security: `lib/core/security/request_encoder.dart`

**Check ALL of the following:**
- [ ] `enabled = true` — verify this is correct once DISCREPANCY-01 is resolved
- [ ] Padding fix present in `decode()`: `(4 - encodedBody.length % 4) % 4` (BUG-C01 root cause)
- [ ] `scrambleUrl()` prefixes with `'RF1:'` before storing
- [ ] `unscrambleUrl()` returns plain URL unchanged if it does NOT start with `'RF1:'` (backward compat)
- [ ] `scrambleUrl()` does NOT double-scramble (guard: `if (url.startsWith('RF1:')) return url`)
- [ ] Session key uses device ID + UTC day + UTC hour (hourly rotation)
- [ ] `encode()` and `decode()` return original string unchanged when `enabled = false`

---

### 3G — Flutter DB: `lib/core/db/local_db.dart`

This is the most important file to audit carefully.

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/db/local_db.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following:**
- [ ] Schema version is 17 (if different, read migration code carefully)
- [ ] `sqflite_sqlcipher` is used, NOT `sqflite`
- [ ] DB key comes from `Keystore.getDbKey()` (Android Keystore — hardware bound)
- [ ] `mergeDeltaTitle()` uses SELECT then UPDATE/INSERT (NOT `ON CONFLICT DO UPDATE` — crashes Android 8)
- [ ] On UPDATE in `mergeDeltaTitle()`: `share_url` only overwritten if delta value is non-empty
  (preserves any share_url from prior Oracle sync)
- [ ] `upsertEpisode()` uses `ConflictAlgorithm.replace` (freshest episode data always wins)
- [ ] **share_url scrambling** — is `RequestEncoder.scrambleUrl()` called here?
  If NOT, this is DISCREPANCY-06 — wire it now
- [ ] `cleanExpiredStreamCache()` deletes rows from `stream_cache` where expiry < now
- [ ] `consumeForceResyncFlag()` exists and works (used in main.dart for schema v17 migration)
- [ ] `savePosterPath()` exists and is called correctly (fixes blank poster bug)
- [ ] `getLastSyncTimestamp()` / `setLastSyncTimestamp()` exist

---

### 3H — Flask Backend: `radd-hub/hub/jazzdrive.py`

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cat /opt/jazzmax/radd-hub/hub/jazzdrive.py" > /tmp/jazzdrive.py
```

**Check ALL of the following:**
- [ ] `list_all_files_in_folder(folder_id)` exists (added TASK-041)
- [ ] It uses `SAPI /media/video?action=get` (returns ALL MIME types — not just video)
- [ ] `upload_json_to_jazzdrive(file_path)` bypasses `uploader.py` (which blocks `.json`)
- [ ] `is_proxy_bypass()` guard is present in ALL chain builders:
  - `_ar_chain` (OAuth2 refresh)
  - `_s2_chain` (SAPI login)
  - `_sub_chain` (OTP verify)
- [ ] When `PROXY_BYPASS=1`: all chains return `[None]` (direct via wg0)
- [ ] `keepalive()` uploads heartbeat file directly (no proxy when bypass=1)
- [ ] No hardcoded proxy list that overrides the bypass setting

---

### 3I — Flask Backend: `radd-hub/hub/routes/zero_rating.py`

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cat /opt/jazzmax/radd-hub/hub/routes/zero_rating.py" > /tmp/zero_rating.py
```

**Check ALL of the following:**
- [ ] `upload_delta()` calls `list_all_files_in_folder()` BEFORE upload (snapshot)
- [ ] After successful upload: trashes all files from the snapshot (NOT re-listing after upload)
- [ ] New share URL saved to `settings.jd_delta_url` via `db.set_setting()`
- [ ] `POST /zero-rating/purge-delta-folder` route exists (manual purge)
- [ ] Purge route returns file count that was trashed
- [ ] `generate_delta_payload()` includes `share_url`, `file_id`, `folder_share_url` per title
- [ ] TV shows include full `episodes` array with per-episode `share_url`
- [ ] `db.setting()` used for reads (NOT `db.get_setting()` — does not exist)
- [ ] Settings table columns are `k` and `v` (NOT `key` and `value`)

---

### 3J — Flask Backend: `radd-hub/hub/db.py`

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cat /opt/jazzmax/radd-hub/hub/db.py" > /tmp/db.py
```

**Check ALL of the following:**
- [ ] Only `setting(k, default='')` and `set_setting(k, v)` are exported
- [ ] NO `get_setting` function exists (it must not — callers using it get AttributeError + HTTP 500)
- [ ] `conn()` returns the shared SQLite connection
- [ ] For background thread writes: callers should use `sqlite3.connect()` + `BEGIN IMMEDIATE`
  (verify this warning is in the code or docs for any bulk write function)

---

### 3K — Flask Backend: `radd-hub/hub/routes/mobile_api.py` (or `api.py`)

```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cat /opt/jazzmax/radd-hub/hub/routes/mobile_api.py 2>/dev/null || cat /opt/jazzmax/radd-hub/hub/routes/api.py"
```

**Check ALL of the following:**
- [ ] `/api/config` route returns `jd_delta_url` (delta URL for Flutter RemoteConfig)
- [ ] `/api/config` route returns brand config keys (for RemoteConfig brand theme)
- [ ] `/api/catalog/version` is PUBLIC (no JWT required) — Flutter getVersion() uses it as probe
- [ ] `/api/catalog/poster/<id>` is PUBLIC (no JWT required)
- [ ] `/api/catalog/sync` REQUIRES JWT auth (returns 401 without token)
- [ ] `/api/catalog/delta` REQUIRES JWT auth
- [ ] JWT auth is verified server-side (not just trusted from client)
- [ ] XOR encoding: if `request_encoding.py` is imported, check it's applied correctly
  (only on encoded endpoints, not on public ones like `/healthz`, `/api/auth/login`)

---

### 3L — Android: `MainActivity.kt`

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following:**
- [ ] Security channel `com.raddflix.app/security` is registered
- [ ] `getSignatureFingerprint` handler: reads signing cert, computes SHA-256, returns `"AA:BB:..."` format
- [ ] `checkFrida` handler: reads `/proc/self/maps`, checks for `frida`, `gadget`, `gum-js-loop`, `linjector`
- [ ] `checkRoot` handler: checks su binary paths, returns boolean
- [ ] `deleteMediaFiles` handler exists (vault import — removes originals from gallery)
  - Android 11+ (API 30+): uses `MediaStore.createDeleteRequest` (system dialog)
  - Android 10-: uses `ContentResolver.delete()` directly
- [ ] `onActivityResult` handles `DELETE_MEDIA_REQUEST_CODE` and resolves `pendingDeleteResult`
- [ ] Intent channel handles `getPendingVideoUri`, `getPendingVideoTitle`, `getPendingSubtitleUri`
- [ ] `onNewIntent` handles warm-start "Open with" intents
- [ ] Cast channel (`com.raddflix.app/cast`) handles `discoverDevices`, `castVideo`, etc.
- [ ] PiP channel (`com.raddflix.app/pip`) handles `enterPiP`

---

### 3M — Flutter: `lib/core/services/jazzdrive_service.dart`

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/services/jazzdrive_service.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following:**
- [ ] `getStreamLink()` makes calls DIRECTLY to `cloud.jazzdrive.com.pk` (NEVER via Oracle)
- [ ] Step 1: `POST /sapi/link/login?action=login` with `{"data": {"accesstoken": "XXXXX"}}`
- [ ] Step 2: `GET /sapi/media/video?action=get&shared=true&key=...&validationkey=...`
- [ ] CDN URL is cached in memory (Map) AND SQLite `stream_cache` table (3h TTL)
- [ ] `_jazzAutoRetry` is available from player to transparently refresh expired links
- [ ] **BUG-J01 is fixed**: Pass 3 (episode matching by SxxExx code) uses string
  concatenation, NOT `'s${...}e${...}'` template (the `\$` escape bug)
- [ ] `loadCacheFromDb()` restores in-memory cache from SQLite on app start
- [ ] `warmTopFreeItems(n)` pre-warms CDN links for top N free titles

---

### 3N — Flutter: `lib/core/security/vault_service.dart`

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddflix/raddflix-app/contents/raddflix_flutter/lib/core/security/vault_service.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Check ALL of the following — all vault bugs were fixed in TASK-034:**
- [ ] `biometricOnly: false` in `authenticateBiometric()` options
  (CRITICAL — must be FALSE. `biometricOnly: true` breaks Infinix/MediaTek phones)
  Wait — this was reverted in TASK-037 to `false`. Confirm it's `false` in the code.
- [ ] `authenticateBiometric()` uses dual-check: `canCheckBiometrics || isDeviceSupported()`
  (VAULT-02 fix — MediaTek phones return false for canCheckBiometrics even with fingerprints)
- [ ] `isBiometricEnabled()` defaults to `false` (VAULT-04 — opt-in, not opt-out)
- [ ] `getVaultFolder()` creates `.nomedia` in subdirectories (VAULT-06)
- [ ] `importFiles()` collects `file.identifier` (content URI) and calls `deleteMediaFiles(uris)`
  to remove originals from gallery (VAULT-01)

---

## Step 4 — Player Screen Quick Checks

The player screen has had 40+ bugs fixed. You do not need to re-audit the whole file,
but verify these specific items that are easy to get wrong:

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/screens/player_screen.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/ps.dart','wb').write(base64.b64decode(d['content'].replace(b'\n',b'')))"
wc -l /tmp/ps.dart
```

**Spot-checks (grep rather than read the whole file):**
```bash
# 1. No androidAttachSurfaceAfterVideoParameters (BUG-P01)
grep "androidAttachSurfaceAfterVideoParameters" /tmp/ps.dart && echo "BUG PRESENT" || echo "OK"

# 2. biometricOnly not in player (should only be in vault_service)
grep "biometricOnly" /tmp/ps.dart

# 3. onToggleCinematic and onToggleNightMode are separate callbacks (BUG-P-NEW-07)
grep -n "onToggleCinematic\|onToggleNightMode\|onNightMode" /tmp/ps.dart | head -20

# 4. _abLoop.setA / _abLoop.setB called in onTrimChanged (BUG-P-NEW-05)
grep -n "_abLoop.setA\|_abLoop.setB" /tmp/ps.dart

# 5. Cinematic toggle bidirectional check (BUG-P-NEW-06)
grep -n "cinematicMode.*!=.*_cinematicMode\|_cinematicMode.*!=.*cinematicMode" /tmp/ps.dart

# 6. _applyVolumeBoost doesn't call VolumeController().setVolume(1.0) unconditionally (BUG-C-01)
grep -n "setVolume" /tmp/ps.dart | head -10

# 7. _audioSessionInitialized guard (BUG-P-NEW-01)
grep -n "_audioSessionInitialized" /tmp/ps.dart | head -10

# 8. Night mode colorchannelmixer has :ra=0 :ga=0 :ba=1 (BUG-M-05)
grep -n "colorchannelmixer\|:ra=\|:ba=" /tmp/ps.dart | head -5

# 9. Hue value NOT divided by 180 (BUG-M-06)
grep -n "hue.*180\|/180" /tmp/ps.dart | head -5

# 10. _openSettings replaced with _openPlayerSettings (BUG-BUILD-01)
grep -n "_openSettings\b" /tmp/ps.dart
```

---

## Step 5 — pubspec.yaml Dependency Audit

```bash
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/pubspec.yaml" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content'].replace('\n','')).decode())"
```

**Verify:**
- [ ] `sqflite_sqlcipher: 3.1.0+1` — NEVER change this (API changed in higher versions)
- [ ] `media_kit` and `media_kit_video` are present (video player)
- [ ] `archive` package is present (for SubtitleHunter ZIP/RAR support — TASK-029)
- [ ] No `sqflite` package (conflicts with `sqflite_sqlcipher`)
- [ ] No duplicate packages (common source of build failures)

---

## Step 6 — Oracle Server Live State Check

```bash
# Flask running?
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl status raddflix_radd"

# Session active? (JazzDrive OAuth token valid)
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "curl -s http://localhost:5000/healthz"

# DB is the real one (not a temp copy)
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "ls -lh /opt/jazzmax/radd-hub/data/radd_hub.db"

# Recent logs — any errors?
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "tail -50 /opt/jazzmax/radd-hub/data/logs/raddhub.log"

# PROXY_BYPASS setting
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "python3 -c \"
import sqlite3
conn = sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
rows = conn.execute(\\\"SELECT k, v FROM settings WHERE k IN ('proxy_bypass','jd_delta_url','last_delta_generated_at')\\\").fetchall()
for r in rows: print(r)
\""

# How many titles in DB?
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "python3 -c \"
import sqlite3
conn = sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
print('titles:', conn.execute('SELECT COUNT(*) FROM titles').fetchone()[0])
print('episodes:', conn.execute('SELECT COUNT(*) FROM files WHERE season IS NOT NULL').fetchone()[0])
print('users:', conn.execute('SELECT COUNT(*) FROM users').fetchone()[0])
\""
```

**Check:**
- [ ] Flask running with status RUNNING
- [ ] DB file is at `/opt/jazzmax/radd-hub/data/radd_hub.db` (the real DB, not a temp)
- [ ] `proxy_bypass` setting = `1` (PROXY_BYPASS=1 is the correct production state)
- [ ] `jd_delta_url` is set (not empty — delta URL is configured)
- [ ] No recent ERROR log entries (especially 401/session errors from JazzDrive)

---

## Step 7 — Fix Everything Found

For each issue found in Steps 2–6:

1. **Open a task in `agent-hub/TASKS.md`** with `TASK-NNN | description | ⏳ IN PROGRESS`
2. **Fix the code or docs**
3. **Mark ✅ DONE** after pushing
4. **Append to `TASK_LOG_APPEND.md`**

### Priority order for fixes:
1. **CRITICAL (app-breaking):** Any issue that makes the app non-functional for users
2. **DISCREPANCY-01 (XOR encoding state):** Must be resolved — wrong enabled state = broken API
3. **DISCREPANCY-06 (share_url scrambling):** Security gap — wire it if safe to do so
4. **DISCREPANCY-04/05 (PRODUCT_CONTEXT.md wrong claims):** Docs fixes — low risk
5. **DISCREPANCY-02/03 (security docs):** Update docs to match code reality

---

## Step 8 — Update All Docs After Fixes

After all code fixes are pushed:

1. **`agent-hub/SECURITY_ARCHITECTURE.md`**:
   - Remove "Native Channel TODO" section (MainActivity.kt is already wired)
   - Update security layers status table to reflect actual state
   - Add "PENDING USER ACTION" block for AppGuard fingerprint setup

2. **`agent-hub/PRODUCT_CONTEXT.md`**:
   - Fix Security Architecture table (delta.json DOES include share_urls)
   - Fix "Every day after" flow to show Oracle-first → delta fallback

3. **`agent-hub/HANDOFF_NEXT.md`**:
   - Update to reflect what this audit session did + what remains

4. **`agent-hub/history/TASK_LOG_APPEND.md`**:
   - Append full session summary

5. **`agent-hub/TASKS.md`**:
   - All tasks completed this session marked ✅ DONE

---

## Step 9 — Final Verification Checklist

Before ending session, confirm every item:

```
FLUTTER APP:
[ ] connectTimeout = 6s in api_client.dart
[ ] 5s probe on getVersion() in sync_service.dart
[ ] loadCached() has zero network calls in remote_config.dart
[ ] fetchBackground() is unawaited in main.dart
[ ] AppGuard.initialize() is called before runApp in main.dart
[ ] RequestEncoder.enabled state matches server-side XOR deployment state
[ ] biometricOnly = false in vault_service.dart
[ ] sqflite_sqlcipher pinned at 3.1.0+1 in pubspec.yaml
[ ] XOR padding fix present in request_encoder.dart
[ ] No androidAttachSurfaceAfterVideoParameters in player_screen.dart
[ ] Security MethodChannel (getSignatureFingerprint/checkFrida/checkRoot) wired in MainActivity.kt

FLASK BACKEND:
[ ] PROXY_BYPASS=1 is set in Oracle DB settings
[ ] All chain builders have is_proxy_bypass() guard
[ ] db.setting() used (not db.get_setting())
[ ] upload_delta() snapshots files BEFORE upload
[ ] list_all_files_in_folder() uses /media/video?action=get
[ ] /api/catalog/version is public (no JWT)
[ ] /api/catalog/sync requires JWT

DOCS:
[ ] SECURITY_ARCHITECTURE.md: MainActivity.kt section reflects actual wired state
[ ] PRODUCT_CONTEXT.md: delta.json correctly described as containing share_urls
[ ] PRODUCT_CONTEXT.md: sync flow shows Oracle-first → delta fallback
[ ] TASKS.md: all tasks this session marked DONE
[ ] TASK_LOG_APPEND.md: session summary appended
[ ] HANDOFF_NEXT.md: updated with current state
```

---

## Critical Rules You Must Never Break

```
1.  NO git shell commands — GitHub API (Trees/Contents) only
2.  NEVER upgrade sqflite_sqlcipher past 3.1.0+1
3.  NEVER add androidAttachSurfaceAfterVideoParameters: true to VideoController
4.  biometricOnly MUST be false — breaks vault on Infinix/MediaTek
5.  Oracle port 5000 is NOT public — test via SSH tunnel only
6.  XOR padding fix stays in request_encoder.dart — NEVER remove it
7.  AppConstants.jazzDriveDeltaUrl must stay a mutable static String (not getter)
8.  connectTimeout must stay ≤ 6s — no-bundle Jazz SIM users depend on it
9.  5s timeout on getVersion() must stay — it's the no-bundle fallback trigger
10. share_url scrambling: unscrambleUrl() must pass through non-RF1: URLs (backward compat)
11. db.setting() — NEVER db.get_setting() — it does not exist
12. settings table columns: k and v (NOT key and value)
13. list_all_files_in_folder() uses /media/video?action=get — ALL MIME types
14. Debug code MUST be gated behind kDebugMode or DebugLogger
15. THE ONLY REAL DB: /opt/jazzmax/radd-hub/data/radd_hub.db
```

---

## End of Audit Prompt

When all sections are complete and all docs are updated, your session is done.
The next agent should see a clean TASKS.md (no open items) and an updated
HANDOFF_NEXT.md describing the current state of the system.
