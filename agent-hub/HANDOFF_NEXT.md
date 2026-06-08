# HANDOFF — RaddFlix Hub (as of TASK-045)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000  
v3 DB: **17 titles / 28 files — all Live** (correct after full import fix)  
Library, bulk controls, publish/unpublish, bulk delete — all working.

## DB Facts (v3 = /opt/jazzmax/radd-hub/data/radd_hub.db)
- account_id=15, msisdn=03286829827  
- legacy_id=2 maps to account_id=15  
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`  
- files schema: no `created_at` — use `scanned_at`  
- files fingerprint pattern: `scan:<remote_id|legacy_file_id>`

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67):  
   on UNIQUE slug conflict during import, now falls back to slug-lookup so files still link.  
2. **`scan_excluded_folders` had the account MSISDN** — already cleared to `[]`.  
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.  
4. **No `sqlite_sequence` DELETE needed** — just `DELETE FROM titles/files` is fine for reset.

## What Was Fixed (TASK-045)
- Root cause: `_import_legacy_into_v3_for_account` called `upsert_title` which throws  
  UNIQUE slug on duplicate legacy titles → silently returns 0 rows → v3 stays empty.  
- Fix 1 (immediate): direct Python import script — clear v3, copy 20 legacy titles  
  (slug-deduplicated), 28 files, auto-publish 17 titles with share_url.  
  Removed 3 orphan 0-file titles (Wildcat 1988, Wildcats Cait, The Rajasaab).  
- Fix 2 (permanent): scanner.py try/except around `db.upsert_title` — UNIQUE slug  
  conflict now falls back to SELECT by slug so file linking continues.

## Next Likely Tasks
- **Scan trigger**: run a fresh JazzDrive scan from the admin UI and verify new files  
  auto-import into v3 without slug errors.  
- **File count display**: library cards show file counts — verify these match v3.  
- **Flutter app**: connect to the live catalog API and display the 17 titles.

## Key Paths on Oracle
- App: `/opt/jazzmax/radd-hub/`  
- Scanner: `hub/scanner.py` (slug-conflict fix at line ~888)  
- DB: `data/radd_hub.db`  
- Library template: `hub/templates/library.html`

## SSH
`node -e "require('fs').writeFileSync('/tmp/oracle_key', process.env.ORACLE_SSH_KEY); require('fs').chmodSync('/tmp/oracle_key',0o600)"`  
then: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252`

## GitHub Push Rule
ALWAYS use Python urllib or Node https Trees API — never git shell.  
Owner: raddclub, repo: raddflix-app, branch: main  
scanner.py lives at: `radd-hub/hub/scanner.py`
