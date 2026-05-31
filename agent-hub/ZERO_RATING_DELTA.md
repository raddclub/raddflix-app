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

The delta system is a **24-hour rolling database snapshot** uploaded to JazzDrive
every 24 hours. It is the bridge between Oracle (the real database) and users
who have no active internet package.

---

## What delta.json Is

- **24-hour rolling window** of all titles published/updated in the last 24 hours
- **Full playback data** — includes everything Flutter needs to play a video:
  `file_id`, `share_url`, `folder_share_url`, complete episode list per show
- **Auto-expires in 24 hours** — regenerated and re-uploaded by the scheduler
- **Publicly downloadable** from JazzDrive (that's how zero-rating works)
- **Format**: `delta_v2`

### Security Model
JazzDrive links in delta.json expire within 24 hours. Even if a hacker downloads
the file, the links go stale fast. The **main Oracle database is never exposed** —
that is the real asset being protected. Local SQLite on user devices is
**AES-256 encrypted via SQLCipher** (device-bound key from Android Keystore) —
even a rooted phone cannot read the DB.

---

## Outer Envelope Format

```json
{
  "format": "delta_v2",
  "generated_at": 1748700000,
  "expires_at": 1748786400,
  "count": 5,
  "titles": [ /* array of title objects — see below */ ]
}
```

`expires_at` = `generated_at + 86400`. Flutter currently stores it but does not enforce it
(future: auto-refresh before expiry). The 24h expiry is enforced server-side by the scheduler
overwriting the JazzDrive file every 24 hours.

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

## Why NOT a `.db` File

SQLite `.db` file merging is dangerous:
- Server schema version ≠ phone schema version → crash
- Overwriting the full DB destroys watch history, positions, downloads
- `.json` gives full control: merge only what you want, skip duplicates cleanly

---

## Server Side (Oracle / radd-hub)

### File: `radd-hub/hub/routes/zero_rating.py`
- `generate_delta_payload()` — queries titles WHERE `updated_at >= now-86400`,
  joins files for `file_id`/`share_url`, queries episodes for shows
- `upload_delta()` route — calls `jazzdrive.upload_json_to_jazzdrive()` (bypasses
  media extension block), saves share URL to `settings.jd_delta_url`
- Scheduler (`hub/scheduler.py`) calls this every 24h automatically

### File: `radd-hub/hub/jazzdrive.py`
- `upload_json_to_jazzdrive(file_path)` — uploads `.json` directly via SAPI
  multipart, bypassing the media-only extension check in `uploader.py`
- Returns `{"ok": True, "share_url": "https://cloud.jazzdrive.com.pk/share/f/..."}`

### File: `radd-hub/hub/routes/api.py`
- `/api/config` route includes `jd_delta_url` from `settings` table
- Flutter reads this on every startup and caches it in SharedPreferences

---

## Flutter Side

### File: `lib/core/constants.dart`
- `AppConstants.jazzDriveDeltaUrl` — mutable `static String` (NOT a getter)
- Default: `''` (empty = JazzDrive delta disabled, Oracle-only sync)
- Updated by `RemoteConfig.fetch()` on every successful Oracle connection

### File: `lib/core/remote_config.dart`
- Reads `jd_delta_url` from `/api/config` response
- Writes it to `AppConstants.jazzDriveDeltaUrl`
- Caches full config JSON in SharedPreferences under key `jm_remote_config`
- On offline start: loads from SharedPreferences cache (so delta URL survives reboot without internet)

### File: `lib/core/db/sync_service.dart`
- `SyncService.sync()` — tries Oracle first, falls back to JazzDrive delta
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

## End-to-End Flow

```
Admin → "Generate + Upload to JazzDrive"
  → delta.json generated (last 24h titles, full playback data)
  → uploaded to JazzDrive via SAPI (upload_json_to_jazzdrive)
  → share URL saved to settings.jd_delta_url
  → /api/config now returns jd_delta_url

User opens app WITH internet:
  → RemoteConfig.fetch() → gets jd_delta_url → caches in SharedPreferences
  → Oracle sync runs → full catalog update

User opens app WITHOUT bundle (Jazz SIM):
  → RemoteConfig.fetch() fails → loads jd_delta_url from SharedPreferences cache
  → Oracle sync fails
  → _syncFromJazzDriveDelta() runs:
      POST /sapi/link/login   (zero-rated ✅)
      GET  /sapi/media/video  (zero-rated ✅)
      GET  <CDN URL>          (zero-rated ✅)
  → delta.json downloaded, merged into local SQLite
  → User sees new titles, can play them

User eventually gets a bundle:
  → Oracle sync fills in all missed days automatically
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
1. **Generate Delta Now** — creates delta.json from last 24h data
2. **Generate + Upload to JazzDrive** — creates + uploads, saves share URL
3. **JD Delta URL field** — shows current URL, can be manually set
4. **Free/Paid toggle** — per-title is_free flag

Scheduler auto-runs steps 1+2 every 24 hours (tracked in `settings.last_delta_generated_at`).

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
6. **delta.json expires in 24h by design** — this is the security model, not a bug
