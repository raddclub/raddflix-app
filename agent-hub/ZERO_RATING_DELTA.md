# RaddFlix — Zero-Rating Delta Sync

> Permanent spec. Every future AI agent must read this before touching
> anything related to `delta.json`, `zero_rating.py`, `sync_service.dart`,
> `remote_config.dart`, or `constants.dart`.

---

## What This System Is

RaddFlix users install the app and register with a normal internet connection.
After that, Jazz SIM users can get **new catalog updates without any data bundle**
because `cloud.jazzdrive.com.pk` is zero-rated on the Jazz network (whitelisted
at the network level — no bundle required, not "free with a bundle").

The delta system is a **snapshot of all published titles** uploaded to JazzDrive
periodically. It is the bridge between Oracle (the real database) and Jazz SIM
users who have no active internet package.

**Oracle vs JazzDrive delta — critical distinction:**
- **Oracle** (`92.4.95.252`) = complete full database, all titles since day one.
  Oracle catalog endpoints **require JWT auth** (added 2026-06-02). Full bundle/WiFi needed.
- **JazzDrive delta** (`cloud.jazzdrive.com.pk`) = snapshot of all published titles.
  Zero-rated — works on Jazz SIM without any data bundle. No auth required.

---

## CRITICAL ARCHITECTURE DECISION — Share URL Permanence

**JazzDrive share_urls NEVER expire.** (Confirmed by user 2026-05-31)

This is intentional and permanent. Any "24h expiry" claim anywhere in this codebase
or docs is WRONG and should be removed.

Consequences:
- delta.json can contain share_urls that will work indefinitely
- Security must focus on APK integrity (cracked APK = attacker gets permanent URLs)
- The APK signature check in AppGuard is critical — see SECURITY_ARCHITECTURE.md
- Server regenerates delta.json periodically but NOT because links expire

---

## What delta.json Is

- **Snapshot of all published titles** — full catalog at time of generation
- **Full playback data** — includes everything Flutter needs to play a video:
  `file_id`, `share_url`, `folder_share_url`, complete episode list per show
- **JazzDrive hosted** — downloadable via zero-rated CDN
- **Format**: `delta_v2`

### Security Model
The share_urls in delta.json are **permanent links**. Security is enforced by:
1. **APK signature check** (AppGuard) — cracked APK gets fake empty data, never real URLs
2. **Frida detection** (AppGuard) — runtime hooking attempt → fake data
3. **Build obfuscation** — compiled APK class names randomised, hard to find security checks
4. **SQLCipher AES-256** — local DB is device-bound encrypted (Phase 4)
5. **share_url scrambling** (RequestEncoder) — XOR-scrambled at rest in SQLite

The **main Oracle database is never exposed** — that contains admin credentials,
user accounts, subscription data. The delta.json contains only catalog/playback data.

See `agent-hub/SECURITY_ARCHITECTURE.md` for the full threat model and implementation.

---

## Outer Envelope Format

```json
{
  "format": "delta_v2",
  "generated_at": 1748700000,
  "count": 24,
  "titles": [ /* array of title objects — see below */ ]
}
```

`generated_at` = Unix timestamp when delta was generated.
Flutter stores this for display purposes. There is no `expires_at` —
links never expire, so no expiry enforcement is needed or correct.

---

## What delta.json Contains Per Title

```json
{
  "id": 5,
  "title": "Pathaan",
  "year": 2023,
  "media_type": "movie",
  "description": "A rogue agent...",
  "rating": 5.8,
  "genres": ["Action", "Thriller"],
  "language": "Hindi",
  "is_free": 0,
  "poster_url": "https://image.tmdb.org/...",
  "poster_share_url": "https://cloud.jazzdrive.com.pk/share/f/...",
  "folder_share_url": "https://cloud.jazzdrive.com.pk/share/f/...",
  "status": "released",
  "is_ongoing": 0,
  "runtime": 146,
  "season_count": null,
  "episode_count": null,
  "db_version": 1717000000,
  "file_id": "5",
  "share_url": "https://cloud.jazzdrive.com.pk/share/f/...",
  "episodes": []
}
```

For TV shows `episodes` is a full list:
```json
"episodes": [
  {
    "id": 8,
    "file_id": "8",
    "season": 1,
    "episode": 1,
    "label": "S01E01",
    "quality": "720p",
    "share_url": "https://cloud.jazzdrive.com.pk/share/f/...",
    "folder_share_url": "https://cloud.jazzdrive.com.pk/share/f/..."
  }
]
```

### What Is NEVER in delta.json
- Raw validation_key / jsessionid / OAuth tokens
- Oracle internal credentials
- User account data, subscription data, payment data
- Any field beyond what Flutter needs to play and display

---

## Poster Fallback for Offline Users

- `poster_url` = TMDB/IMDB URL (loads when user has any internet)
- `poster_share_url` = JazzDrive-hosted poster image inside the movie's folder
  (zero-rated — loads without a bundle)
- `poster_path` = locally cached poster path in app storage (persisted after
  first successful poster download, works completely offline forever after)

Flutter poster load priority:
1. `poster_path` (local file — no network at all)
2. `poster_share_url` (JazzDrive CDN — zero-rated)
3. `poster_url` (TMDB/IMDB — needs internet)

---

## Who Gets Zero-Rating? (All Jazz SIM Users)

Zero-rating via JazzDrive works for **ALL** Jazz SIM users — paid, free, or no bundle.
The network whitelists `cloud.jazzdrive.com.pk` at the packet level.

| User Type | Oracle Sync | Delta Sync |
|-----------|-------------|------------|
| Has internet bundle | ✅ Full Oracle sync | ✅ Also available |
| No bundle (Jazz SIM) | ❌ Times out in ~5s | ✅ Works (zero-rated) |
| Registered (one-time) | Required once for account creation | N/A |
| Guest | ❌ | ✅ Can browse catalog |

**First registration requires internet once** — account is created, device bound,
subscription checked. After that: Oracle sync when online, delta when not.

The Oracle timeout before delta fallback is **≤ 5 seconds** (TASK-042, 2026-06-08):
- `connectTimeout: 6s` in `api_client.dart`
- `.timeout(Duration(seconds: 5))` on `CatalogApi.getVersion()` probe in `sync_service.dart`

---

## Free vs Paid Content

| Type | `is_free` | Who Can Play |
|------|-----------|-------------|
| Free movies (max ~50) | 1 | Everyone (guests too) |
| Paid movies/dramas | 0 | Subscribed users only |

---

## Why NOT a `.db` File

SQLite `.db` file merging is dangerous:
- Server schema version ≠ phone schema version → crash
- Overwriting the full DB destroys watch history, positions, downloads
- `.json` gives full control: merge only what you want, skip duplicates cleanly

---

## Server Side (Oracle / radd-hub)

### File: `radd-hub/hub/routes/zero_rating.py`
- `generate_delta_payload()` — queries all published titles,
  joins files for `file_id`/`share_url`, queries episodes for shows
- `upload_delta()` route — **UPDATED (TASK-041, 2026-06-08)**:
  1. Calls `jazzdrive.list_all_files_in_folder(delta_folder_id)` to snapshot ALL existing files
  2. Calls `jazzdrive.upload_json_to_jazzdrive()` to upload new delta.json
  3. Trashes ALL files from the pre-upload snapshot (keeps folder clean — only current JSON)
  4. Saves new share URL to `settings.jd_delta_url`
- `POST /zero-rating/purge-delta-folder` — manual purge route, trashes all files in delta
  folder, returns count. Admin UI button shows file count before purge.
- Scheduler (`hub/scheduler.py`) calls upload_delta periodically

### File: `radd-hub/hub/jazzdrive.py`
- `upload_json_to_jazzdrive(file_path)` — uploads `.json` directly via SAPI
  multipart, bypassing the media-only extension check in `uploader.py`
  Returns `{"ok": True, "share_url": "https://cloud.jazzdrive.com.pk/share/f/..."}`
- `list_all_files_in_folder(folder_id)` — **NEW (TASK-041, 2026-06-08)**:
  Uses `SAPI /media/video?action=get` which returns ALL file types regardless of MIME.
  Do NOT use any other listing endpoint — they filter by MIME and miss `.json` files.

### File: `radd-hub/hub/routes/api.py` (mobile_api.py)
- `/api/config` route includes `jd_delta_url` from `settings` table
- Flutter reads this via `RemoteConfig.fetchBackground()` and caches to SharedPreferences

---

## Flutter Side

### File: `lib/core/constants.dart`
- `AppConstants.jazzDriveDeltaUrl` — mutable `static String` (NOT a getter)
- Default: `''` (empty = JazzDrive delta disabled, Oracle-only sync)
- Updated by both `RemoteConfig.loadCached()` (from cache) and `fetchBackground()` (from Oracle)

### File: `lib/core/remote_config.dart` — **UPDATED (TASK-040, 2026-06-08)**

Two methods, called at different times in `main.dart`:

```dart
// Called BEFORE runApp() — awaited — instant — NO network
static Future<void> loadCached() async {
  // Reads SharedPreferences only
  // Sets AppConstants.jazzDriveDeltaUrl from cached value
  // Completes in < 10ms even with no internet
}

// Called AFTER runApp() — NOT awaited — fire-and-forget
static Future<void> fetchBackground() async {
  // Hits Oracle /api/config with 4-second timeout
  // Updates AppConstants.jazzDriveDeltaUrl in memory
  // Refreshes SharedPreferences cache for next cold start
  // Silently ignored on timeout/error
}

// Legacy shim — kept for backwards compat — calls fetchBackground()
static Future<void> fetch() => fetchBackground();
```

**Why the split matters:**
- `loadCached()` ensures `jazzDriveDeltaUrl` is set from the start, even offline
- `fetchBackground()` keeps the URL fresh without blocking startup
- Before this split, startup hung for up to 4s on slow Oracle connections before showing the app

### File: `lib/core/db/sync_service.dart`
- `SyncService.sync()` — tries Oracle first, falls back to JazzDrive delta on ANY exception
- Oracle probe: `CatalogApi.getVersion().timeout(Duration(seconds: 5))` — lightweight,
  throws TimeoutException if Oracle unreachable → caught by outer catch → delta runs
- `syncFull()` / `syncDelta()` keep 30s receiveTimeout for large catalog downloads
- `_syncFromJazzDriveDelta()` — if URL is a JazzDrive share URL, calls
  `_resolveJazzDriveDocumentUrl()` first (2-step zero-rated SAPI flow)
- `_resolveJazzDriveDocumentUrl()`:
  1. POST `cloud.jazzdrive.com.pk/sapi/link/login?action=login` → validationKey
  2. GET `cloud.jazzdrive.com.pk/sapi/media/video?shared=true&key=KEY&validationkey=VK`
     → picks `downloadUrl` from first record → downloads JSON
- Merges each title via `LocalDb.mergeDeltaTitle()` (preserves existing share_url)
- Merges episodes via `LocalDb.upsertEpisode()` (replace-on-conflict)

### File: `lib/core/db/local_db.dart`
- `mergeDeltaTitle()` — SELECT then UPDATE or INSERT (avoids SQLite 3.24+ UPSERT,
  safe on Android 8+). On UPDATE: only overwrites `share_url` if delta has a
  non-empty value (preserves any share_url from a prior Oracle sync)
- `upsertEpisode()` — ConflictAlgorithm.replace (always take freshest episode data)

---

## End-to-End Flow (updated 2026-06-08)

```
Admin → "Generate + Upload to JazzDrive"
  → delta.json generated (ALL published titles, full playback data)
  → list_all_files_in_folder() → snapshot existing files in delta folder
  → upload new delta.json via upload_json_to_jazzdrive()
  → trash all files from snapshot (folder now contains only new delta.json)
  → new share URL saved to settings.jd_delta_url
  → /api/config now returns new jd_delta_url

User opens app — startup sequence:
  → main() BEFORE runApp:
      await RemoteConfig.loadCached()
        → reads jd_delta_url from SharedPreferences (instant, no network)
        → AppConstants.jazzDriveDeltaUrl set immediately

  → runApp() → app visible immediately

  → main() AFTER runApp (fire-and-forget):
      RemoteConfig.fetchBackground()   // NOT awaited
        → hits Oracle /api/config (4s timeout)
        → updates jd_delta_url in memory + refreshes cache

User opens app WITH internet bundle:
  → SyncService.sync():
      _syncFromOracle()
        → getVersion().timeout(5s) → Oracle responds < 1s ✅
        → syncDelta() or syncFull() as needed (30s timeout)
      → full Oracle sync complete, delta never used

User opens app WITHOUT bundle (Jazz SIM):
  → SyncService.sync():
      _syncFromOracle()
        → getVersion().timeout(5s) → times out after 5s (no bundle) ❌
        → TimeoutException thrown
      → caught by outer catch → _syncFromJazzDriveDelta() runs:
          POST /sapi/link/login   (zero-rated ✅)
          GET  /sapi/media/video  (zero-rated ✅)
          GET  <CDN URL>          (zero-rated ✅)
      → delta.json downloaded, merged into local SQLite
      → User sees full catalog, can play content (total wait: ≤ 5s)

User eventually gets a bundle:
  → Oracle sync fills in everything automatically
  → delta.json data stays as base; Oracle overwrites where data is fresher
```

---

## Size Estimates

| Catalog size | delta.json approx size |
|---|---|
| 10 titles | ~8–12 KB |
| 50 titles | ~40–60 KB |
| 100 titles | ~80–120 KB |
| 200 titles | ~160–240 KB |

Size drivers: description length, episode count for shows. Always under 1 MB
for any realistic catalog size — trivial to download over zero-rated CDN.

---

## Admin Panel

Zero-Rating Manager at `/zero-rating/`:
1. **Generate Delta Now** — creates delta.json from all published titles
2. **Generate + Upload to JazzDrive** — creates + uploads + purges old files + saves share URL
3. **Purge Delta Folder** — manual button showing file count, trashes all files in delta folder
4. **JD Delta URL field** — shows current URL, can be manually set
5. **Free/Paid toggle** — per-title is_free flag

Scheduler auto-runs periodically (tracked in `settings.last_delta_generated_at`).

---

## Critical Rules for Future Agents

1. **Never put raw credentials** (validation_key, jsessionid) in delta.json
2. **Never use `upload_file_to_jazzdrive()`** for delta.json — it goes through
   `uploader.py` which blocks `.json`. Always use `upload_json_to_jazzdrive()`
3. **`jazzDriveDeltaUrl` must stay a mutable `static String`**, not a `get` getter —
   RemoteConfig needs to write to it
4. **`mergeDeltaTitle` must use SELECT+UPDATE/INSERT** — never `ON CONFLICT DO UPDATE`
   (requires SQLite 3.24+, crashes Android 8, BUG-A04)
5. **Both SAPI calls are zero-rated** — they hit `cloud.jazzdrive.com.pk` which is
   Jazz network-whitelisted. Never proxy these through Oracle
6. **Share_urls NEVER expire** — this is confirmed architecture. Any code/doc claiming
   "links expire 24h" is WRONG. Do not reintroduce that claim.
7. **Security relies on APK integrity, not link expiry** — see SECURITY_ARCHITECTURE.md
8. **`list_all_files_in_folder()` must use `/media/video?action=get`** — this is the only
   SAPI endpoint that returns ALL file types. Switching to another listing endpoint will
   miss `.json` files and leave stale deltas in the folder (TASK-041, 2026-06-08)
9. **`RemoteConfig.loadCached()` must never make network calls** — it is the instant
   startup path. Network calls belong in `fetchBackground()` only. (TASK-040, 2026-06-08)
10. **`connectTimeout` in api_client.dart must stay ≤ 6s** and **5s timeout on
    `getVersion()` must stay** — no-bundle users cannot wait 15s for a cold start.
    (TASK-042, 2026-06-08)
