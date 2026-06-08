# agent-hub/CONTEXT.md — RaddFlix System Context
Last updated: 2026-06-08 (TASK-040/041/042 — RemoteConfig split, delta purge, sync timeout fix)

## What is RaddFlix?
Pakistani Flutter streaming app. Content is zero-rated (free data) on Jazz SIM via JazzDrive.
Users install the APK, log in, and stream content. All content lives on JazzDrive cloud storage.

## Infrastructure

### Oracle VPS (92.4.95.252)
- Flask backend: `supervisorctl` → `raddflix_radd` → port 5000 (localhost only)
- App: `/opt/jazzmax/radd-hub/hub/`
- DB: `/opt/jazzmax/radd-hub/data/radd_hub.db` (SQLite WAL mode)
- Logs: `/opt/jazzmax/radd-hub/data/logs/raddhub.log`
- Restart: `sudo supervisorctl restart raddflix_radd`
- WireGuard: wg0 — split tunnel routing JazzDrive IPs through VPN
  - Works correctly for ALL JazzDrive traffic — JazzDrive is globally accessible

### GitHub Repo: raddclub/raddflix-app
- Flutter app: `raddflix_flutter/`
- Flask backend: `radd-hub/`
- Agent docs: `agent-hub/`, `AGENT_HANDOFF.md`, `AGENT_PROMPT.md`
- APK CI: `.github/workflows/build-apk.yml` (triggers on push to `raddflix_flutter/**`)

---

## JazzDrive Proxy Architecture

### Key fact: JazzDrive is globally accessible — NO geo-restriction
JazzDrive (jazzdrive.com.pk, cloud.jazzdrive.com.pk) works from any IP worldwide.
wg0 WireGuard works for ALL call types.
**Do NOT force proxies for JazzDrive calls.**

### PROXY_BYPASS=1 (normal production state)
When `PROXY_BYPASS=1` is set in DB settings:
- `is_proxy_bypass()` returns True
- `resolve_proxies()` returns None for all call types
- All proxy chains (`_ar_chain`, `_s2_chain`, `_sub_chain`, all others) go to `[None]` (direct via wg0)
- Pool health-check and recovery threads are skipped
- This is CORRECT — direct via wg0 is the intended path

### What causes 401/errors on JazzDrive calls?
If you see SAPI 401 with an HTML body like `<!DOCTYPE HTML`:
- This comes from a **dead proxy** returning its own error page, not from JazzDrive
- Fix: ensure `is_proxy_bypass()` guard is in place so dead proxies are skipped
- NOT a geo-restriction — JazzDrive works globally

### Call type summary
```
CALL TYPE                         | WITH PROXY_BYPASS=1  | CORRECT?
----------------------------------|----------------------|----------
_ar_chain (OAuth2 refresh)        | [None] direct wg0    | ✅
_s2_chain (SAPI login)            | [None] direct wg0    | ✅
_sub_chain (OTP verify)           | [None] direct wg0    | ✅
trigger_otp_flow                  | [None] direct wg0    | ✅
resend_otp                        | [None] direct wg0    | ✅
keepalive heartbeat (JSESSIONID)  | [None] direct wg0    | ✅
upload (JSESSIONID)               | [None] direct wg0    | ✅
```

---

## db.py API (CRITICAL)
```python
db.setting(k, default='')      # READ a setting
db.set_setting(k, v)           # WRITE a setting
# NEVER use db.get_setting() — it does NOT exist → AttributeError + HTTP 500
```

### SQLite write rule
For writes from background threads or admin routes: use `sqlite3.connect()` + `BEGIN IMMEDIATE`.
The shared `db.conn()` wrapper can be silently blocked by WAL read locks from background threads.
DB settings table columns: `k` / `v` (NOT `key` / `value`).

---

## Session Lifecycle (with PROXY_BYPASS=1)
```
Flask restart
  → startup_refresh()
  → android_refresh_session()
      → _ar_chain: OAuth2 /oauth2/refresh_token.php — direct via wg0 (~1s)
      → _s2_chain: SAPI /sapi/login/oauth — direct via wg0 (~2s)
  → session restored in ~3-5 seconds total
  → keepalive every 360 min: upload heartbeat file to Radd-Heartbeat/ folder (direct)
```
No OTP needed on restart IF `refresh_token` is stored in DB.

---

## OTP Flow (manual, when refresh_token expired or missing)
```
Admin page → Trigger OTP
  → trigger_otp_flow(): sends OTP SMS (direct via wg0 with PROXY_BYPASS=1)
  → User enters OTP in admin
  → submit_otp(): verifies code, saves session (direct via wg0 with PROXY_BYPASS=1)
  → Session saved, refresh_token stored
```

---

## Scan & Metadata Pipeline

### Overview
JazzDrive scan reads the user's JazzDrive folders, matches files to movie/TV metadata,
and writes results to SQLite. The Flutter app syncs from there.

### File detection
`_legacy/scanner.py` → `scan_account()` → lists all video files from JazzDrive.
Each file record has: `filename`, `remote_id`, `folder_path`, `size_bytes`, `season`, `episode`.

### TV vs Movie detection
TV is detected if **any file in the folder** matches either:
- `[Ss]\d{1,2}[Ee]\d{1,3}` pattern in filename (e.g. `S01E02`)
- `season` field already set on the file record

If TV is detected, `prefer='tv'` is passed to the metadata lookup chain.

### Episode parsing — `_parse_episode_info(filename)`
Three patterns tried in order:
1. `SxxExx` — `Spider Noir S01E02.mp4` → season=1, episode=2
2. `Season X Episode Y` — `Season 1 Episode 3.mp4` → season=1, episode=3
3. `NxNN` — `1x03.mp4` → season=1, episode=3

Returns `(None, None)` if none match — treated as a movie file.

### Season/episode stored in DB
`files` table has `season INTEGER` and `episode INTEGER` columns.
Deduplication key for episodes: `(account_id, title_id, season, episode)` — prevents the
same episode being stored twice if uploaded with two filenames (clean + dirty).

### Metadata lookup chain (in order)
For each folder group, the scanner tries:
1. **TMDB** (via `enricher.fetch_full_metadata()`) — best structured data, great for Hollywood
2. **IMDbAPI.dev** fallback — free, no API key, real IMDb data — best for Pakistani/Urdu/new content

#### TV-specific search fix (critical)
When prefer='tv', the `_clean_name` from `_clean_filename()` still contains the episode suffix
(e.g. `"Spider Noir S01E02"`). Before passing to IMDbAPI, the scanner strips it:
```python
_search_name = re.sub(r'\s*[Ss]\d{1,2}[Ee]\d{1,3}.*$', '', _clean_name).strip()
```
This ensures IMDbAPI searches for `"Spider Noir"` not `"Spider Noir S01E02"`.

### Metadata source priority (metadata_lookup.py)
For general lookups outside the legacy scanner:
`IMDbAPI.dev → OMDB → TMDB → AI → YouTube → Google KG`
IMDb-first because Pakistani/Urdu content is on IMDb long before TMDB.

### Scan log kinds
| Kind | Meaning |
|------|---------|
| `scan_start` | Scan began for account |
| `folder` | A folder was found with N files |
| `progress` | Running total of files found |
| `scan_done` | File discovery complete |
| `tmdb` | Metadata lookup started for a title |
| `tmdb_ok` | Title matched (TMDB or IMDb fallback) |
| `tmdb_miss` | No match after all sources tried |

### Media naming (`media_naming.py`)
`MediaPlan` struct: `{ title, year, folder_label, filename, season, episode, ... }`
TV files get filename: `"Show Name S01E02.ext"`
TV season folders: `"Show Season 1 (2024)"` or `"Show Season 1"` (no year)

---

## Flutter App Key Files
```
raddflix_flutter/lib/
  core/security/request_encoder.dart   XOR decode + base64 padding fix (CRITICAL)
  core/api/api_client.dart             Dio + XOR + auth interceptors
                                         connectTimeout: 6s (TASK-042 — was 15s)
                                         receiveTimeout: 30s (unchanged)
  core/db/local_db.dart                SQLCipher DB, schema v17
  core/db/sync_service.dart            Oracle-first sync with 5s probe on getVersion()
                                         Falls to JazzDrive delta if probe times out
                                         See STREAMING_ARCHITECTURE.md for full flow
  core/remote_config.dart              Split into loadCached() + fetchBackground()
                                         loadCached(): instant, reads SharedPreferences, NO network
                                         fetchBackground(): fire-and-forget after runApp, 4s timeout
  screens/player_screen.dart           Video player (6265 lines, all bugs fixed as of 2ac9e8dc)
                                         See agent-hub/PLAYER_SPEC.md for full architecture
  providers/auth_provider.dart         Auth state + session restore
```

## Flask Key Files
```
radd-hub/hub/
  jazzdrive.py           JazzDrive session, OTP, upload, keepalive
                           list_all_files_in_folder(folder_id): lists ALL files via
                           /media/video?action=get (returns ALL MIME types, not just video)
                           Used by upload_delta() to snapshot+purge before upload
  proxy_pool.py          SOCKS/HTTP proxy pool management
  keepalive.py           Heartbeat upload scheduler
  uploader.py            JazzDrive upload queue
  scanner.py             v3 scanner (_scan_worker, _enrich_low_confidence_titles)
  _legacy/scanner.py     Legacy scanner with enrich_and_save, TV detection, IMDb fallback
  media_naming.py        _detect_season_episode, _plan_tv, MediaPlan struct
  metadata_lookup.py     enrich() — IMDb-first lookup chain
  metadata.py            fetch_imdbapi(), enrich_title()
  _legacy/enricher.py    TMDB fetch_full_metadata(), _clean_filename()
  db.py                  DB helpers — only exports setting() and set_setting()
  routes/
    admin.py             Admin panel API (db/reset, db/restore)
    catalog_api.py       /api/catalog/*
    mobile_api.py        /api/auth/*, usage, history, /api/app/config
    settings.py          Proxy pool admin
    zero_rating.py       Zero-rating manager — delta generate/upload/purge
                           POST /zero-rating/purge-delta-folder: trash all files in delta folder
  templates/
    scan.html            Scan log UI — human-readable, suppresses internal chatter
    admin.html           Admin panel — Restore Catalog + Danger Zone
```

---

## GitHub Push Method (NO git shell ever)
Use Contents API for 1-2 files, Trees API for 3+ files (atomic commit).
See AGENT_PROMPT.md Step 3 for the exact Node.js templates.
Always fetch fresh SHA immediately before PUT — stale SHA = 409 conflict.
