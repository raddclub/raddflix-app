# HANDOFF — RaddFlix Hub (as of TASK-051)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000 — v3.0.0 healthy
DB: **17 titles / 28 files — all Live**
Radd-Delta: **1 file** (delta.txt id=242552967, 16KB)
Vincenzo folder: **2 files** — `Vincenzo S01E01.mp4` + `Vincenzo S01E02.mp4`
Duplicate upload guard: **FULL COVERAGE** on all upload paths.

## DB Facts
- account_id=15, msisdn=03286829827
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- files schema: no `created_at` — use `scanned_at`
- files.fingerprint TEXT UNIQUE NOT NULL — DB-level guard against double-queuing
- files.remote_id TEXT (no UNIQUE — intentional)
- settings: `jd_delta_folder_id=1763725`, `jd_delta_remote_id=242552967`

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67).
2. **`scan_excluded_folders`** — already cleared to `[]`.
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.
4. **`trash_files()` false-positive for BOTH file-type AND video-type** — confirmed both return
   success without actually removing. ALWAYS use `delete_files_permanent()` for cleanup.
   (TASK-047 trash of Vncenz0 dupes was also false-positive — deleted via delete_files_permanent
   during TASK-050.)
5. **`/media/video` blind to `mediatype="file"` items** — use `/media/file?action=get` + 
   `list_all_files_in_folder()` for non-video files (delta.txt, etc).

## Duplicate Upload Guard — Full Coverage (post TASK-050 + TASK-051)

| Upload path | DB guard | JD-side guard |
|---|---|---|
| `upload_to_jazzdrive()` (manual) | ✅ fingerprint UNIQUE | ✅ TASK-048 |
| `queue_manual_upload()` | ✅ (calls above) | ✅ (calls above) |
| `_upload_pending()` (scheduler) | ✅ `is_ready=-2` claim | ✅ TASK-050 |
| `push-poster-to-jd` route | ✅ delete-before-upload | ✅ TASK-051 BUG-A |

All paths tested: 10/10 active catalog files detect existing JD files correctly.

## What Was Done (TASK-048 → TASK-051)

### TASK-051 — Post-audit bug fixes (3 bugs)
**Found via audit of all `_upload_file()` call sites after TASK-050:**

**BUG-A (`routes/library.py` push-poster-to-jd):** Added duplicate poster guard — query
`/media/video` for existing `poster*.jpg` in the JD folder, call `delete_files_permanent()`
on all found, then upload fresh `poster.jpg`. Prevents `poster (1).jpg` accumulation.

**BUG-B (`uploader.py _get_or_create_folder`):** Added per-(parent_id, name) lock +
double-check pattern. Two concurrent upload threads (scheduler + manual upload) for the
same show could both see the folder missing and both call `_create_folder()` → duplicate
JD folders. Also: if `_create_folder()` returns None (API error), now retries `_list_folders()`
once — catches the case where a concurrent thread succeeded while ours failed.

**BUG-C (`uploader.py _upload_pending`):** Added `rename_video()` call after `_set_file_folder()`
in `_upload_pending()`. Mirrors the defense-in-depth rename in `upload_to_jazzdrive()` — JD
async uploads can ignore the multipart filename; explicit rename guarantees canonical name.

### TASK-050 — _upload_pending() duplicate guard
Injected `/media/video` pre-check after folder resolution, before `_upload_file()`.
Bonus: renamed `Vncenz0` → `Vincenzo` on JD, deleted 2 leftover duplicate files. Commit: 3b04e4d.

### TASK-049 — Radd-Delta folder accumulation fix
`list_all_files_in_folder()` + rewritten `upload_delta()`. Commits: a892a07, df4e7c4.

### TASK-048 — upload_to_jazzdrive() duplicate guard. Commit d54d188.

## `_upload_file()` direct call audit (TASK-051)
All direct `_upload_file()` calls verified:
- `uploader.py:1410` — inside `upload_to_jazzdrive()` retry loop ✅ guarded
- `uploader.py:1848` — inside `_upload_pending()` ✅ TASK-050 guard
- `routes/library.py:874` — poster upload ✅ TASK-051 BUG-A delete-before-upload
- `assets.py:78` — `process_title_poster()` ✅ early-return if `poster_share_url` exists
- `keepalive.py:322` — heartbeat, unique date-stamped name, intentional accumulation ✅

## Key Paths on Oracle
- uploader.py: `hub/uploader.py`
  - `upload_to_jazzdrive()` dup guard: ~L1287
  - `_get_or_create_folder()` race fix: ~L625 (lock) + ~L640 (double-check)
  - `_upload_pending()` dup guard: ~L1791 / rename: ~L1862
- library.py: `hub/routes/library.py` — poster dup guard: ~L855
- jazzdrive.py: `hub/jazzdrive.py` — `list_all_files_in_folder()`
- zero_rating.py: `hub/routes/zero_rating.py` — `upload_delta()`
- DB: `data/radd_hub.db`

## SSH
```
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('SSH key ready')"
```
then: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252`

## GitHub Push Rule
ALWAYS use Python urllib Trees API — never git shell.
Owner: raddclub, repo: raddflix-app, branch: main
Key paths: `radd-hub/hub/uploader.py`, `radd-hub/hub/routes/library.py`, `radd-hub/hub/routes/zero_rating.py`
