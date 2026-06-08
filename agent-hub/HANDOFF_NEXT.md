# HANDOFF — RaddFlix Hub (as of TASK-046)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000 — PID 2978797, HTTP 302 OK
v3 DB: **17 titles / 28 files — all Live** (`is_published=1`)
Library, bulk controls, publish/unpublish, bulk delete — all working.
Admin/Scan/Settings pages: all `confirm()`/`prompt()` dialogs replaced.

---

## DB Facts (v3 = /opt/jazzmax/radd-hub/data/radd_hub.db)
- account_id=15, msisdn=03286829827
- legacy_id=2 maps to account_id=15
- **titles schema**: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- **files schema**: `scanned_at` (NOT `created_at`), fingerprint = `scan:<remote_id>`
- **scan_excluded_folders**: `[]` — MSISDN entry removed

---

## What Was Done (TASK-045 + TASK-046)

### TASK-045 — Catalog Import Fixed
- **Root cause**: `_import_legacy_into_v3_for_account` called `db.upsert_title()` which threw
  `UNIQUE constraint failed: titles.slug` on duplicate slugs → silently returned 0 rows → v3 empty.
- **Fix 1 (immediate)**: direct Python import — cleared v3, imported 20 legacy titles
  (slug-deduped), 28 files, auto-published 17. Removed 3 orphan 0-file titles.
- **Fix 2 (permanent)**: `scanner.py` — wrapped `db.upsert_title()` in try/except; UNIQUE slug
  conflict now falls back to `SELECT id FROM titles WHERE slug=?`. Commit: `6ccfa67`.

### TASK-046 — Admin UI Dialogs Fixed (12 bugs across 3 pages)
All `confirm()` and `prompt()` calls replaced — they're blocked by the Cloudflare tunnel.

**scan.html** — commits `82cd047` / `caf1710`:
- `changeRole()`: two-step arm+fire toast (keyed by account id)
- `removeExcluded()`: added `✔ Removed` toast on success, `✗ Failed` on error (was silently swallowing errors)

**admin.html** — commit `b8f19cb`:
- `waRelink()`: two-step toast
- `setQuota()`: inline number-input panel below the leaderboard table (replaces `prompt()`)
- `admSendBroadcast()`: two-step toast
- `dbClearGithub()`: two-step toast (was double-`confirm()`)
- `dbClearSheets()`: two-step toast (was double-`confirm()`)
- `dsRestartOracle()`: two-step toast

**settings.html** — commit `54a5beb`:
- `gsEnrich()`: two-step toast
- `delKey()`: two-step toast (keyed by key id)
- `triggerRelogin()`: removed `confirm()` + blocking `prompt()` — now shows inline OTP panel
  with text input + Verify button + Enter key support
- `_delSig()`: two-step toast

---

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit `6ccfa67`).
2. **`scan_excluded_folders` had the account MSISDN** — cleared to `[]`.
3. **`confirm()`/`prompt()` blocked by tunnel proxy** — ALL replaced. See Rule 38 in RULES.md.
4. **Template GitHub path**: `radd-hub/hub/templates/` NOT `hub/templates/`.
5. **Parallel GitHub PUTs on templates** cause 409 SHA conflict — push sequentially.
6. **Flask restart**: `sudo supervisorctl restart raddflix_radd` needs root. Use `kill <pid>` instead — supervisord auto-restarts it. Find PID: `pgrep -f 'radd_hub.py run'`.

---

## Next Likely Tasks
- **Fresh scan**: trigger a JazzDrive scan from admin UI → verify new files auto-import into v3
  without slug errors (UNIQUE slug fix now in place).
- **Flutter catalog**: wire Flutter app to the live catalog API to display the 17 titles.
- **Delta push**: generate a new delta.json from the 17 Live titles and upload to JazzDrive.

---

## Key Paths on Oracle
- App root: `/opt/jazzmax/radd-hub/`
- Scanner: `hub/scanner.py` (slug-conflict fix at ~line 888)
- DB: `data/radd_hub.db`
- Templates: `hub/templates/`

---

## SSH Setup (every session)
```bash
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('key ready')"
ssh -i /tmp/oracle_key ubuntu@92.4.95.252
```

## GitHub Push Rule
ALWAYS use Python urllib or Node https Contents/Trees API — never git shell.
Owner: `raddclub`, repo: `raddflix-app`, branch: `main`
Templates: `radd-hub/hub/templates/<file>` — push **sequentially**.
