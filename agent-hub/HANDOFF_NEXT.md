# HANDOFF — RaddFlix Hub (as of TASK-049)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000
v3 DB: **17 titles / 28 files — all Live** (correct after full import fix)
Radd-Delta JazzDrive folder: **1 file** (delta_2_ypdj45.txt, id=242552932, 13KB)
All 26 orphaned delta files permanently deleted.

## DB Facts (v3 = /opt/jazzmax/radd-hub/data/radd_hub.db)
- account_id=15, msisdn=03286829827
- legacy_id=2 maps to account_id=15
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- files schema: no `created_at` — use `scanned_at`
- files fingerprint pattern: `scan:<remote_id>` (scanned) or `upl:<md5>` (uploaded)
- settings: `jd_delta_folder_id=1763725`, `jd_delta_remote_id=242552932`

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67).
2. **`scan_excluded_folders` had the account MSISDN** — already cleared to `[]`.
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.
4. **`trash_files(media_type="file")` returns false-positive success** — files are NOT actually
   soft-deleted. Always use `delete_files_permanent()` for file-type (delta) cleanup. This is
   documented in RULES.md Rule 37 and in the `upload_delta()` code comment.
5. **`/media/video` blind to `mediatype="file"` items** — use `/media/file?action=get` to list
   delta.json/.txt files in Radd-Delta. `list_all_files_in_folder()` now correctly uses this.

## What Was Done (TASK-047 + TASK-048 + TASK-049)

### TASK-049 — Radd-Delta Folder Accumulation Fix
**Root causes:**
1. `upload_delta()` only tracked ONE `prev_remote_id` via settings — any orphaned files from
   DB resets or missed saves accumulated forever.
2. `/media/video` was used to list Radd-Delta contents but returns 0 for `mediatype="file"` items.
3. `trash_files(media_type="file")` returns success but does NOT actually soft-delete files.

**Fixes applied:**
1. **`jazzdrive.py`**: Added `list_all_files_in_folder(account_id, folder_id)` using `/media/file`
   endpoint — correctly lists all non-video files filtered by folder.
2. **`zero_rating.py` `upload_delta()`**: Rewritten purge logic:
   - Pre-upload: snapshot ALL files in Radd-Delta via `list_all_files_in_folder()`
   - Upload new delta.json
   - Post-upload: permanently delete ALL snapshotted files via `delete_files_permanent()`
   (not trash_files — see bug #4 above)
3. **Immediate cleanup**: Permanently deleted 26 orphaned delta files from Radd-Delta.
4. **RULES.md Rule 37**: Corrected — `/media/file` not `/media/video`.
- Commit: a892a07

### TASK-047 — JazzDrive Duplicate File Audit & Cleanup
- Trashed: Luka Chuppi (1), Pitt Siyapa (1), Vncenz0 S01E02 (1) and (2).

### TASK-048 — Uploader Duplicate Guard (uploader.py)
- Pre-upload sapi_request check; skips if filename exists in target folder. Commit d54d188.

## Next Likely Tasks
- **Fresh scan**: trigger JazzDrive scan → verify new files auto-import without slug errors/duplicates.
- **Flutter catalog**: wire Flutter app to the live catalog API to display the 17 titles.
- **Delta regeneration**: generate fresh delta.json from the 17 Live titles and upload.

## Key Paths on Oracle
- App: `/opt/jazzmax/radd-hub/`
- jazzdrive.py: `hub/jazzdrive.py` (list_all_files_in_folder added at line ~479)
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
Key paths: `radd-hub/hub/jazzdrive.py`, `radd-hub/hub/routes/zero_rating.py`
