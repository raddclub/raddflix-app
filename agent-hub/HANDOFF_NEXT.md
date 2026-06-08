# HANDOFF — RaddFlix Hub (as of TASK-050)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000
v3 DB: **17 titles / 28 files — all Live**
Radd-Delta JazzDrive folder: **1 file** (delta.txt, id=242552967, 16KB)
Vincenzo folder: **2 files** — correctly named `Vincenzo S01E01.mp4` + `Vincenzo S01E02.mp4`
All duplicate upload guards now active on BOTH upload paths.

## DB Facts (v3 = /opt/jazzmax/radd-hub/data/radd_hub.db)
- account_id=15, msisdn=03286829827
- legacy_id=2 maps to account_id=15
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- files schema: no `created_at` — use `scanned_at`
- files fingerprint pattern: `scan:<remote_id>` (scanned) or `upl:<md5>` (uploaded)
- settings: `jd_delta_folder_id=1763725`, `jd_delta_remote_id=242552967`
- files.fingerprint TEXT UNIQUE NOT NULL — DB-level guard prevents double-queuing
- files.remote_id TEXT (no UNIQUE — intentional for show/season edge cases)

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67).
2. **`scan_excluded_folders` had the account MSISDN** — already cleared to `[]`.
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.
4. **`trash_files(media_type="file")` returns false-positive success** — files are NOT actually
   soft-deleted. Always use `delete_files_permanent()` for file-type (delta) cleanup.
   Documented in RULES.md Rule 37 and in `upload_delta()` code comment.
5. **`/media/video` blind to `mediatype="file"` items** — use `/media/file?action=get` to list
   delta.json/.txt files in Radd-Delta. `list_all_files_in_folder()` correctly uses this.
6. **trash_files() false-positive for video-type too** — confirmed Vncenz0 (1) and (2) were NOT
   actually trashed after TASK-047. Always prefer `delete_files_permanent()` for cleanup.

## Duplicate Upload Guard — Full Coverage
Both upload paths now protected against re-uploading files that already exist on JazzDrive:

| Path | DB guard | JazzDrive-side guard |
|------|----------|----------------------|
| `upload_to_jazzdrive()` (manual) | ✅ fingerprint UNIQUE | ✅ TASK-048 |
| `queue_manual_upload()` | ✅ (calls above) | ✅ (calls above) |
| `_upload_pending()` (scheduler) | ✅ `is_ready=-2` claim | ✅ TASK-050 |

Guard logic (both paths): after folder resolution, query `/media/video` for the target folder,
compare `plan.filename.lower()` against all non-softdeleted filenames. If match found:
- Record existing remote_id in DB (UPDATE files SET is_ready=1, remote_id=...)
- Create share link for existing file
- `clear_live_stat(file_id)` + return — no upload, no local file delete.
Guard is non-fatal: network errors log debug and fall through to upload.

Live test result (2026-06-08): 10/10 active catalog files ✅ guard fires correctly.
9 ghost-title folders show empty (Interstellar, Dune etc — removed from JD, normal).

## What Was Done (TASK-047 → TASK-050)

### TASK-050 — _upload_pending() Duplicate Guard
**Gap:** `_upload_pending()` called `_upload_file()` directly, bypassing the TASK-048 guard.
**Fix:** Injected `/media/video` pre-check + skip+record logic after folder resolution,
before `_upload_file()`. Covers movies AND episodes. Commit: 3b04e4d.
**Bonus fix:** Renamed `Vncenz0 S01E01/02.mp4` → `Vincenzo S01E01/02.mp4` on JazzDrive;
permanently deleted 2 leftover duplicate Vncenz0 files (ids 242527574, 242531168).

### TASK-049 — Radd-Delta Folder Accumulation Fix
1. `jazzdrive.py`: Added `list_all_files_in_folder()` using `/media/file` endpoint.
2. `zero_rating.py upload_delta()`: Pre-snapshot all files → upload new → `delete_files_permanent()` all old.
3. 26 orphaned delta files permanently deleted. Commits: a892a07, df4e7c4.

### TASK-048 — Uploader Duplicate Guard (upload_to_jazzdrive)
Pre-upload sapi_request check; skips if filename exists in target folder. Commit d54d188.

### TASK-047 — JazzDrive Duplicate File Audit & Cleanup
Attempted trash of duplicate files. NOTE: trash_files() is a false-positive (see bug #6).

## Next Likely Tasks
- **Fresh scan**: trigger JazzDrive scan → verify new files auto-import without slug errors/duplicates.
- **Flutter catalog**: wire Flutter app to the live catalog API to display the 17 titles.
- **Delta regeneration**: generate fresh delta.json from the 17 Live titles and upload.
- **DB ghost titles cleanup**: 9 DB records with stale/empty JD folders (Interstellar, Dune etc)
  — either delete from DB or re-upload those files to JD.

## Key Paths on Oracle
- App: `/opt/jazzmax/radd-hub/`
- uploader.py: `hub/uploader.py` (both duplicate guards — upload_to_jazzdrive L1287, _upload_pending L1791)
- jazzdrive.py: `hub/jazzdrive.py` (list_all_files_in_folder)
- zero_rating.py: `hub/routes/zero_rating.py` (upload_delta rewritten)
- DB: `data/radd_hub.db`

## SSH
```
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('SSH key ready')"
```
then: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252`

## GitHub Push Rule
ALWAYS use Python urllib or Node https Trees API — never git shell.
Owner: raddclub, repo: raddflix-app, branch: main
Key paths: `radd-hub/hub/uploader.py`, `radd-hub/hub/jazzdrive.py`, `radd-hub/hub/routes/zero_rating.py`
