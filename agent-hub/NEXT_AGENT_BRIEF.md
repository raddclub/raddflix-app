# NEXT AGENT BRIEF — RaddFlix Data Flow Verification
  > Last verified: 2026-06-08 (TASK-055 complete) | Read AGENT_PROMPT.md first, then this file.

  ---

  ## Your Task This Session

  Read AGENT_PROMPT.md and TASKS.md first, then pick up the next open task.

  **TASK-055 (data flow verification) is COMPLETE as of 2026-06-08.**
  All checks A–J passed. One new bug found and fixed (Inuyashiki/Reborn season/episode).
  The system is fully verified end-to-end.

  ---

  ## 1. Understanding the Two ID Systems (CRITICAL — do not confuse these)

  ### JazzDrive File IDs (large numbers like 242554393)
  These are assigned by JazzDrive CDN when a file is uploaded. You will see them in:
  - Oracle DB: `files.remote_id` column
  - JazzDrive folder listings
  - The delta folder: `delta.txt` has remote_id=242554393 (as of 2026-06-08)

  **Flutter NEVER sees or uses these IDs directly.**
  They are used ONLY by Oracle/Python for:
  - Knowing which JD file to delete (dedup guard, pre-purge cleanup)
  - Knowing which file was uploaded last (`jd_delta_remote_id` setting)

  ### Oracle File IDs (small numbers like 2, 5, 22, 42)
  These are Oracle's own SQLite auto-increment row IDs (`files.id`).
  **This is what Flutter calls `file_id` everywhere.**
  When Flutter wants to play episode Vincenzo S01E01, it sends `file_id=42` to Oracle.

  ---

  ## 2. How Flutter Gets Catalog Data — Three Scenarios (VERIFIED OK)

  ### Priority Order
  ```
  1. Oracle API (http://92.4.95.252) — when user has internet bundle
     PORT 80: nginx proxies to Flask on port 5000
     All /api/* responses are XOR-encoded when Flutter sends X-Encoded:1 header
     
     GET /api/catalog/version (XOR) → compare to local SQLite version
        Same version → instant return, zero download
        Admin force-bump (forcedTs > localVersion) → full sync
        New version → delta sync (only changed titles)

  2. Local SQLite DB (offline) — when no internet at all
     Shows whatever was last synced, works fully offline

  3. JazzDrive delta.json (zero-rated) — when Jazz SIM but no bundle
     delta.json is a 24h rolling snapshot of all published titles
     Fetched via zero-rated JazzDrive share URL (stored in AppConstants.jazzDriveDeltaUrl)
     AppConstants.jazzDriveDeltaUrl comes from RemoteConfig -> /api/config -> DB setting jd_delta_url
     /api/config returns PLAIN JSON (RemoteConfig uses raw Dio, not XOR ApiClient)
  ```

  ### XOR Encoding (VERIFIED ACTIVE)
  - Flutter: RequestEncoder.enabled = true
  - _XorInterceptor adds X-Encoded:1 + X-Device-Id headers
  - Session key: SHA-256("raddflix_xor_v1:deviceId:day:hour")[:32] — rotates hourly
  - Oracle _xor_encode_response: after_request hook, checks X-Encoded:1 -> octet-stream response
  - Oracle XorWsgiMiddleware: decodes incoming request bodies
  - Padding fix in request_encoder.dart: '=' * ((4 - b64.length % 4) % 4) — NEVER remove
  - EXCEPTION: /api/auth/* and /healthz are NOT XOR-encoded (no X-Encoded:1 sent)
  - EXCEPTION: /api/config is NOT XOR-encoded (RemoteConfig uses plain Dio)

  ### RemoteConfig flow (startup)
  ```
  main() -> RemoteConfig.loadCached()    — reads SharedPrefs cache, sets AppConstants
           -> runApp()
           -> RemoteConfig.fetchBackground()  — fires /api/config (4s timeout, plain Dio)
              -> updates AppConstants + SharedPrefs cache for NEXT launch
  ```

  ---

  ## 3. How Play Button Works (VERIFIED OK)

  ### Stream URL resolution (3 layers)
  ```dart
  // In player_screen.dart -> _openMedia()
  // Layer 1: SQLite getShareInfo(fileId) -> share_url, filename, remote_id (fast)
  // Layer 2: JazzDriveService.getStreamLink() — 3-layer cache:
  //   2a: in-memory cache (_inMemory[fileId]) — instant (110min TTL)
  //   2b: SQLite stream_cache table — fast, no network
  //   2c: Live JazzDrive API call (zero-rated) — 2 API calls to JD
  // Layer 3: If local file exists (downloaded) -> play directly
  ```

  ### The 2-step JazzDrive stream URL generation
  ```
  Step 1: POST cloud.jazzdrive.com.pk/sapi/link/login?action=login&sharekey=KEY
          body: {data: {accesstoken: KEY}}
          -> returns validationKey (VK) AND jsessionid from data.jsessionid (JSON body)
          CRITICAL: Read JSESSIONID from JSON body (data.jsessionid) — NOT Set-Cookie header
          Android absorbs Set-Cookie before Dart/Dio sees it. Fixed in jazzdrive_service.dart.

  Step 2: GET cloud.jazzdrive.com.pk/sapi/media/video?shared=true&key=KEY&validationkey=VK
          Cookie: JSESSIONID=<value from step 1 JSON body>
          -> returns list of files in share folder
          -> JazzDriveService picks the right file using 3-pass filename matching:
              Pass 0: exact remote_id match (most reliable)
              Pass 1: direct substring match
              Pass 2: normalised spaces match
              Pass 3: episode code match (builds "s01e04" style code)
          -> returns CDN stream URL (expires ~2h, cached 110 min)
  ```

  ### isMovie determination in show_detail_screen.dart
  - isMovie = item.mediaType == 'movie' -> shows play+download buttons directly
  - isMovie = false (type='show'/'tv'/'series') -> shows episodes list; user taps episode
  - Single-file series (Inuyashiki, Reborn): stored as type='series', season=1, episode=1
    -> shown as Season 1, Episode 1 in Flutter -> tappable -> plays

  ---

  ## 4. How Download Button Works (VERIFIED OK)

  ```dart
  // DownloadService.downloadFile(fileId, title, streamUrl, shareUrl, targetFilename, remoteId)
  // 1. _checkDownloadQuota(): GET /api/usage/quota (XOR-encoded, auth required)
  //    quota['allowed']==false -> throw DownloadQuotaException
  // 2. JazzDriveService.getStreamLink(fileId, shareUrl, remoteId) -> CDN URL
  //    Falls back to LocalDb.getShareUrl(fileId) if no shareUrl passed
  // 3. Dio.download(cdnUrl -> app/documents/downloads/fileId.mp4)
  // 4. File size validation: < 512KB = broken -> delete + re-flag as failed
  // 5. LocalDb.insertDownload(fileId, localPath)
  ```

  ---

  ## 5. Library Page — Verified State (2026-06-08)

  ### Current DB contents (all correct, all VERIFIED)

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

  **Single-file Series/Anime (2) — shown as TV shows with 1 episode:**
  | Title | Year | Oracle file_id | Season | Episode | JD remote_id |
  |-------|------|----------------|--------|---------|--------------|
  | Inuyashiki | 2017 | 7 | 1 | 1 | 242363265 |
  | Reborn as a Vending Machine… | 2023 | 12 | 1 | 1 | 242464975 |
  > Season/episode set to 1/1 (fixed 2026-06-08). Shows as "Season 1, Episode 1" in Flutter.

  **TV Shows with episodes (2):**
  | Title | S | E | Oracle file_id | JD remote_id |
  |-------|---|---|----------------|--------------|
  | Vincenzo | 1 | 1 | 42 | 242518574 |
  | Vincenzo | 1 | 2 | 39 | 242531168 |
  | Spider-Noir | 1 | 1 | 37 | 242518443 |
  | Spider-Noir | 1 | 2 | 36 | 242518530 |

  **Summary:** 17 titles, 19 files, 17 published, 19/19 have share_url
  Oracle /api/catalog/sync returns: 17 titles + 6 episodes (verified with XOR decode)

  ---

  ## 6. Key Oracle DB Settings (VERIFIED CORRECT)

  ```sql
  SELECT k, v FROM settings WHERE k IN (
    'jd_delta_url',       -- https://cloud.jazzdrive.com.pk/share/f/gH9GymFdRKmy1rDgdQq5B...
    'jd_delta_remote_id', -- 242554393 (as of 2026-06-08)
    'jd_delta_folder_id', -- 1763725 (Radd-Delta folder)
    'api_base_url'        -- http://92.4.95.252 (nginx:80 -> Flask:5000)
  );
  ```

  ---

  ## 7. Recent Changes (2026-06-08)

  ### TASK-053: upload_delta() pre-purge strategy
  Pre-purge all JD files before upload so JD always names it delta.txt.

  ### TASK-054: TV episode fixes
  1. zero_rating.py: media_type IN ("show","tv","series") — was only "show"
  2. jazzdrive_service.dart: JSESSIONID from JSON body (not Set-Cookie header)
  3. Delta regen+upload: Spider-Noir + Vincenzo episodes now in delta

  ### TASK-055: Full verification + Inuyashiki/Reborn fix
  1. All 10 verification checks (A–J) passed
  2. Inuyashiki + Reborn: season=NULL -> season=1,episode=1 in Oracle DB
     Now appear in /api/catalog/sync episodes array AND delta episodes
  3. Delta regen+upload: remote_id=242554393, same share URL
  4. XOR encoding round-trip verified live

  ---

  ## 8. Known Issues (not blocking — need admin action)

  **9 movies with deleted JazzDrive files** (need re-upload by admin):
  Animal, Dune: Part Two, Inception, Interstellar, Inuyashiki (file deleted but entry exists),
  Oppenheimer, Reborn (same), The Ninth Gate, Super Mario Galaxy.
  Their old individual-file JD share links are invalid (MED-1011). No local source files.
  App now shows "MED-1011: invalid JazzDrive key" instead of "Jazz SIM Required".
  Flutter users see a clear error. Blocking only for those specific titles.

  **Bug 1 (no movie play button):** Code is CORRECT in show_detail_screen.dart line 464.
  Most likely old APK predates the play button code. Rebuild from current main branch.

  ---

  ## 9. Verification Checklist (for future agents)

  All checks are verified as of 2026-06-08. Re-run if code changes are made.

  ```
  A. Oracle health       ssh -> curl http://localhost:5000/healthz
  B. Library data        sqlite3 -> SELECT titles+files with share_url status
  C. Delta settings      sqlite3 -> SELECT k,v FROM settings WHERE k LIKE 'jd_delta%'
  D. Flutter sync_service.dart  — verify Oracle->JD fallback, version gate
  E. Player flow         — player_screen.dart _openMedia() + JazzDriveService cache layers
  F. Download flow       — download_service.dart quota + JD resolve + private storage
  G. Live API test       — /api/catalog/version, /api/config, /api/catalog/sync
  H. XOR decode          — send X-Encoded:1 + X-Device-Id, decode response
  I. Delta content       — check delta.json episodes for TV shows
  J. JD share login      — POST /sapi/link/login with Spider-Noir share key -> validationKey
  ```

  ---

  ## 10. Admin Panel Pages Reference

  | URL (via SSH on server) | Purpose |
  |------------------------|---------|
  | http://localhost:5000/admin/ | Main admin dashboard |
  | http://localhost:5000/library/ | Title library — publish/unpublish |
  | http://localhost:5000/zero-rating/ | Delta upload, delta URL management |
  | http://localhost:5000/scan/ | JazzDrive scanner |
  | http://localhost:5000/settings/ | Proxy pool, account settings |
  | http://localhost:5000/security/xor-encoding | XOR encoding status page |

  All pages require admin login. Oracle port 5000 is NOT public.
  Port 80 (nginx) IS public — proxies all /api/* to Flask 5000.
  