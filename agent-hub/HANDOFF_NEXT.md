# HANDOFF — RaddFlix Hub (as of TASK-048)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000
v3 DB: **17 titles / 28 files — all Live** (correct after full import fix)
Library, bulk controls, publish/unpublish, bulk delete — all working.

## DB Facts (v3 = /opt/jazzmax/radd-hub/data/radd_hub.db)
- account_id=15, msisdn=03286829827
- legacy_id=2 maps to account_id=15
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- files schema: no `created_at` — use `scanned_at`
- files fingerprint pattern: `scan:<remote_id>` (scanned) or `upl:<md5>` (uploaded)

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67):
   on UNIQUE slug conflict during import, now falls back to slug-lookup so files still link.
2. **`scan_excluded_folders` had the account MSISDN** — already cleared to `[]`.
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.
4. **No `sqlite_sequence` DELETE needed** — just `DELETE FROM titles/files` is fine for reset.

## What Was Done (TASK-047 + TASK-048)

### TASK-047 — JazzDrive Duplicate File Audit & Cleanup
- Scanned account 03286829827 (account_id=15) for duplicate files on JazzDrive.
- Found 4 duplicates across 3 folders (all `filename (N).mp4` variants, same size as original).
- Trashed via `jazzdrive.trash_files()`: ids 242527434, 242531171, 242531168, 242527574.
  - Luka Chuppi (2019) (1).mp4
  - Pitt Siyapa (2026) (1).mp4
  - Vncenz0 S01E02 (1).mp4
  - Vncenz0 S01E02 (2).mp4
- All 4 confirmed in JazzDrive trash (soft-delete, recoverable).

### TASK-048 — Uploader Duplicate Guard (radd-hub/hub/uploader.py)
**Root cause (two gaps):**
1. DB fingerprint check uses `upl:<md5>` for uploads but scanned files use `scan:<remote_id>`.
   After DB reset or auto-delete, re-uploaded files find no match → upload proceeds → JazzDrive
   silently renames to `filename (1).mp4`.
2. No JazzDrive-side existence check before uploading — no way to know file already exists there.

**Fix (commit d54d188):** After folder resolution, `upload_to_jazzdrive()` now:
1. Calls `sapi_request('/media/video', 'get', params={'parentId': folder_id})` live.
2. Scans response for a non-softdeleted file whose name matches `target_filename` (case-insensitive).
3. If found: skips upload, records existing `remote_id` in DB, creates share link, returns
   `{"ok": True, "skipped": True, "reason": "already_on_jazzdrive"}`.
4. If check fails (network error): logs debug and continues to upload normally (non-fatal).
Injected at line 1287 of uploader.py (after folder resolution, before extension/size checks).

## Next Likely Tasks
- **Fresh scan**: trigger a JazzDrive scan from admin UI → verify new files auto-import into v3
  without slug errors and without creating duplicates.
- **Flutter catalog**: wire Flutter app to the live catalog API to display the 17 titles.
- **Delta push**: generate a new delta.json from the 17 Live titles and upload to JazzDrive.

## Key Paths on Oracle
- App: `/opt/jazzmax/radd-hub/`
- Uploader: `hub/uploader.py` (duplicate guard injected at line 1287)
- Scanner: `hub/scanner.py` (slug-conflict fix at line ~888)
- DB: `data/radd_hub.db`

## SSH
```
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('SSH key ready')"
```
then: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252`

## GitHub Push Rule
ALWAYS use Python urllib or Node https Trees API — never git shell.
Owner: raddclub, repo: raddflix-app, branch: main
uploader.py lives at: `radd-hub/hub/uploader.py`
