# NEXT AGENT BRIEF — RaddFlix Data Flow Verification
> Created: 2026-06-08 | Read AGENT_PROMPT.md first, then this file.

---

## Your Task This Session

Verify the **complete end-to-end data flow** of the Flutter app — how it gets catalog data,
how the Play and Download buttons work, how data is persisted, and whether the Library page
shows all correct content. Fix any bugs you find.

---

## 1. Understanding the Two ID Systems (CRITICAL — do not confuse these)

### JazzDrive File IDs (large numbers like 242552967)
These are assigned by JazzDrive CDN when a file is uploaded. You will see them in:
- Oracle DB: `files.remote_id` column
- JazzDrive folder listings (`list_all_files_in_folder()` returns these)
- The delta folder: `delta.txt` has id=242552967

**Flutter NEVER sees or uses these IDs directly.**
They are used ONLY by Oracle for:
- Knowing which JD file to delete (dedup guard, pre-purge cleanup)
- Knowing which file was uploaded last (`jd_delta_remote_id` setting)

### Oracle File IDs (small numbers like 2, 5, 22, 42)
These are Oracle's own SQLite auto-increment row IDs (`files.id`).
**This is what Flutter calls `file_id` everywhere.**
When Flutter wants to play episode Vincenzo S01E01, it sends `file_id=42` to Oracle.

### Episode/Poster/Video identification
Everything is by **Oracle `files.id`**. The `files.remote_id` is invisible to Flutter.

### The heartbeat files you see in JD listings
```
id=242553093  name=radd_hub_heartbeat (31).txt  folder=1763859  (Radd-Heartbeat folder)
id=242553092  name=delta_4015zcxg.txt           folder=1763725  (Radd-Delta folder — STALE, now deleted)
id=242552967  name=delta.txt                    folder=1763725  (current live delta)
```
Heartbeat files live in a **different** JazzDrive folder (Radd-Heartbeat, folder_id=1763859).
They are uploaded by `keepalive.py` every 360 minutes to keep the JD session alive.
They contain the session expiry timestamp. They are NOT catalog data — ignore them.

---

## 2. How Flutter Gets Catalog Data — Three Scenarios

### Priority Order
```
1. Oracle API (http://92.4.95.252) — when user has internet bundle
   └─ GET /api/catalog/version → compare to local SQLite version
      ├─ Same version → instant return, no download (zero cost)
      ├─ Admin force-bump → full sync all titles
      └─ New version → delta sync (only changed titles)

2. Local SQLite DB (offline) — when no internet at all
   └─ Shows whatever was last synced, works fully offline

3. JazzDrive delta.json (zero-rated) — when Jazz SIM but no bundle
   └─ delta.json is a 24h rolling snapshot of all published titles
   └─ Fetched via zero-rated JazzDrive share URL (stored in AppConstants.jazzDriveDeltaUrl)
   └─ AppConstants.jazzDriveDeltaUrl comes from RemoteConfig → /api/config → DB setting jd_delta_url
```

### Sync triggers (when does Flutter sync?)
1. **Cold/warm start** — always attempts version check
2. **App comes to foreground** — WidgetsBindingObserver.didChangeAppLifecycleState
3. **Internet restored** — Connectivity.onConnectivityChanged
4. All syncs are version-gated: no work done if Oracle version == local version

### Key files
```
lib/core/db/sync_service.dart        — SyncService.sync(), _syncFromOracle(), _syncFromJazzDriveDelta()
lib/providers/catalog_provider.dart  — CatalogNotifier, initialize(), _loadFromDb()
lib/core/remote_config.dart          — loadCached() (instant on start) + fetchBackground() (fire-and-forget)
lib/core/constants.dart              — AppConstants.jazzDriveDeltaUrl, .apiBaseUrl
```

### RemoteConfig flow (startup)
```
main() → RemoteConfig.loadCached()    — reads SharedPrefs cache, sets AppConstants.jazzDriveDeltaUrl
         → runApp()
         → RemoteConfig.fetchBackground()  — fires Oracle /api/config request (4s timeout, fire+forget)
            → updates AppConstants + SharedPrefs cache for NEXT launch
```

---

## 3. How Play Button Works

### Stream URL resolution (3 layers)
```dart
// In player_screen.dart → _initStream()
// Layer 1: in-memory cache (JazzDriveService._inMemory[fileId])  — instant
// Layer 2: SQLite stream_cache table                             — fast, no network
// Layer 3: Live JazzDrive API call (zero-rated)                  — 2 API calls to JD
```

### The 2-step JazzDrive stream URL generation (Layer 3)
```
Step 1: POST cloud.jazzdrive.com.pk/sapi/link/login?action=login&sharekey=KEY
        → returns validationKey (VK)

Step 2: GET cloud.jazzdrive.com.pk/sapi/media/video?shared=true&key=KEY&validationkey=VK
        → returns list of files in the share folder
        → JazzDriveService picks the right file using 3-pass filename matching:
            Pass 0: exact remote_id match (JazzDrive numeric ID — most reliable)
            Pass 1: direct substring match (e.g. "E01" in filename)
            Pass 2: normalised spaces match
            Pass 3: episode code match (builds "s01e04" style code)
        → returns CDN stream URL (expires in ~2h, cached 110 min)
```

### What `fileId` is used for
The `fileId` parameter in PlayerScreen is the Oracle DB `files.id` (e.g. "42" for Vincenzo S01E01).
It's sent to:
- `/api/stream/link` (POST) — Oracle generates XOR-encoded stream link response
- `JazzDriveService.getStreamLink(fileId, shareUrl)` — Flutter generates stream URL directly (zero-rated, bypasses Oracle)
- `stream_cache` table — cache key is `fileId`

### Which path is used (Oracle vs JazzDrive direct)?
- **Oracle path**: `POST /api/stream/link` with `file_id` → Oracle returns the CDN URL
- **JazzDrive direct path**: Flutter's `JazzDriveService.getStreamLink()` → Flutter resolves URL itself (zero-rated, no Oracle needed)
- **Offline path**: `localPath` is set → PlayerScreen opens local file directly

The app prefers JazzDrive direct (zero-rated) when `shareUrl` is available in the local DB.
Oracle `/api/stream/link` is used as fallback or for premium content checks.

### XOR encoding reminder
All Oracle API responses (except `/api/auth/*`, `/healthz`) are XOR-encoded.
`request_encoder.dart` has the critical padding fix: `b64 += '=' * ((4 - b64.length % 4) % 4)`.
Never remove this. Without it, all catalog/auth/stream calls break silently.

---

## 4. How Download Button Works

### Flow
```dart
// DownloadService.downloadFile(fileId, title, streamUrl, shareUrl, targetFilename, remoteId)
// 1. Check download quota: GET /api/usage/quota (Oracle, XOR-encoded)
// 2. Resolve stream URL:
//    - If shareUrl set → JazzDriveService.getStreamLink(fileId, shareUrl, remoteId=...) → CDN URL
//    - If no shareUrl → use provided streamUrl directly
// 3. Download with Dio → save to app's private storage
// 4. Record in LocalDb.downloads table
```

### `remoteId` in downloads
The `remoteId` parameter to `downloadFile()` is the JazzDrive numeric file ID (`files.remote_id` from Oracle).
It enables **Pass 0** exact matching in JazzDriveService — bypasses all filename matching.
Passed when Oracle DB has it; 0 = not available (falls through to Passes 1-3).

### Where downloads are stored
- Private app storage: `(await getApplicationDocumentsDirectory()).path/downloads/`
- Recorded in SQLite `downloads` table with `file_id`, `local_path`, `title`
- Encrypted by device storage (SQLCipher for DB, private app dir for files)

---

## 5. Library Page — Verified State (2026-06-08)

### Current DB contents (all correct ✅)

**Movies (13) — all published, all have share_url:**
| Title | Year | Oracle file_id | JD remote_id |
|-------|------|----------------|--------------|
| Animal | 2023 | 5 | 242361088 |
| Bhooth Bangla | 2026 | 27 | 242517108 |
| Dune: Part Two | 2024 | 3 | 242361509 |
| Inception | 2010 | 10 | 242381252 |
| Interstellar | 2014 | 2 | 242373442 |
| Luka Chuppi | 2019 | 15 | 242527434 |
| Oppenheimer | 2023 | 11 | 242381254 |
| Pitt Siyapa | 2026 | 22 | 242531171 |
| Swapped | 2026 | 28 | 242518532 |
| The Ninth Gate | 1999 | 6 | 242363529 |
| The Raja Saab | 2026 | 21 | 242518553 |
| The Super Mario Galaxy Movie | 2026 | 9 | 242363286 |
| Wildcat | 2025 | 26 | 242518572 |

**Series/Anime (2) — single-file (full series as one file):**
| Title | Year | Oracle file_id | JD remote_id |
|-------|------|----------------|--------------|
| Inuyashiki | 2017 | 7 | 242363265 |
| Reborn as a Vending Machine… | 2023 | 12 | 242464975 |

**TV Shows with episodes (2):**
| Title | S | E | Oracle file_id | JD remote_id |
|-------|---|---|----------------|--------------|
| Vincenzo | 1 | 1 | 42 | 242518574 |
| Vincenzo | 1 | 2 | 39 | 242531168 |
| Spider-Noir | 1 | 1 | 37 | 242518443 |
| Spider-Noir | 1 | 2 | 36 | 242518530 |

**Summary:** 17 titles, 19 files, 17 published, 19/19 have share_url ✅

### Things to verify on the Library page
- [ ] All 17 titles appear in the admin library page
- [ ] Movies show poster images (poster_share_url populated)
- [ ] TV shows show season/episode breakdown
- [ ] Inuyashiki + Reborn show correctly as single-file series (no episode list needed)
- [ ] Publish status shows as "Live" for all 17

---

## 6. Key Oracle DB Settings to Know

```sql
-- Check these are set correctly:
SELECT k, v FROM settings WHERE k IN (
  'jd_delta_url',        -- JazzDrive folder share URL for delta.txt
  'jd_delta_remote_id',  -- Should be 242552967 (delta.txt)
  'jd_delta_folder_id',  -- Should be 1763725 (Radd-Delta folder)
  'api_base_url'         -- Base URL pushed to Flutter app via /api/config
);
```

Expected:
- `jd_delta_remote_id` = 242552967 ✅ (fixed this session)
- `jd_delta_folder_id` = 1763725 ✅
- `jd_delta_url` = a cloud.jazzdrive.com.pk/share/f/... URL ✅

---

## 7. Recent Changes (This Session — 2026-06-08)

### TASK-052: upload_delta() pre-purge strategy (commit ce35372 + 4a301ee)
**Problem**: JazzDrive auto-renames uploads to `delta_RANDOM.txt` when `delta.txt` already
exists. Old code did post-upload delete which sometimes failed silently, causing stale temp
files to accumulate. DB ended up pointing to wrong (stale) file.

**Fix**: `upload_delta()` in `zero_rating.py` now **deletes all files BEFORE upload**.
Empty folder → JD always names it `delta.txt`. No more accumulation.

**Also added**: `POST /zero-rating/purge-delta-folder` route + admin HTML button (red, with confirm dialog)
for emergency manual cleanup.

---

## 8. Verification Checklist for Next Agent

Run these checks:

### A. Oracle health
```bash
# SSH key setup (always first):
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('key ready');"
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
# Expected: {"ok":true,"version":"3.0.0"}
```

### B. Library data
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db '
SELECT t.title, t.media_type, t.is_published,
       f.id as file_id, f.season, f.episode,
       CASE WHEN f.share_url IS NOT NULL THEN \"OK\" ELSE \"MISSING\" END as share_url
FROM titles t LEFT JOIN files f ON f.title_id=t.id
ORDER BY t.media_type, t.title, f.season, f.episode;'"
# Expected: all 19 rows with share_url=OK
```

### C. Delta folder clean
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db 'SELECT k,v FROM settings WHERE k LIKE \"jd_delta%\";'"
# Expected: jd_delta_remote_id=242552967, folder=1763725, url=jazz share url
```

### D. Flutter catalog sync flow (theoretical verification)
Check `lib/core/db/sync_service.dart`:
- `_syncFromOracle()` uses 5s probe timeout for `/api/catalog/version`
- `_syncFromJazzDriveDelta()` is called only if Oracle throws
- `AppConstants.jazzDriveDeltaUrl` is set from RemoteConfig (populated from `jd_delta_url` DB setting)

### E. Play button flow verification
Check `lib/screens/player_screen.dart` for `_initStream()`:
- Confirm it calls `JazzDriveService.getStreamLink(fileId, shareUrl)` first
- Confirm `VideoController` does NOT have `androidAttachSurfaceAfterVideoParameters: true`

### F. Download flow verification
Check `lib/core/download/download_service.dart`:
- Confirm quota check before download
- Confirm JazzDriveService.getStreamLink is used when shareUrl available
- Confirm saves to private app storage

---

## 9. Prompt to Give New Agent

Copy-paste the content of `AGENT_PROMPT.md` as the starting prompt (fetch it fresh each time).
Then add this context line at the top:

> **Session task: Verify the complete Flutter↔Oracle↔JazzDrive data flow. Read NEXT_AGENT_BRIEF.md
> in agent-hub/ for full context. Start with the verification checklist in Section 8.**

---

## 10. Admin Panel Pages Reference

| URL (via SSH tunnel) | Purpose |
|---------------------|---------|
| `http://localhost:5000/admin/` | Main admin dashboard |
| `http://localhost:5000/library/` | Title library — publish/unpublish, status filter |
| `http://localhost:5000/zero-rating/` | Delta upload, delta URL management |
| `http://localhost:5000/scan/` | JazzDrive scanner (scan + upload new content) |
| `http://localhost:5000/settings/` | Proxy pool, account settings |
| `http://localhost:5000/admin/api/db/stats` | DB statistics JSON |

All pages require admin login. Oracle port 5000 is NOT public — access via SSH tunnel only.
