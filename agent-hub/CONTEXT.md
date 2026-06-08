# agent-hub/CONTEXT.md — RaddFlix System Context
Last updated: 2026-06-08 (TASK-045/046 — catalog import fixed, confirm/prompt dialogs replaced)

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
  - If supervisorctl requires root password: `kill <pid>` instead — supervisord auto-restarts it
  - Find Flask PID: `pgrep -f 'radd_hub.py run'`
- WireGuard: wg0 — split tunnel routing JazzDrive IPs through VPN
  - Works correctly for ALL JazzDrive traffic — JazzDrive is globally accessible

### GitHub Repo: raddclub/raddflix-app
- Flutter app: `raddflix_flutter/`
- Flask backend: `radd-hub/`  ← templates live at `radd-hub/hub/templates/`
- Agent docs: `agent-hub/`, `AGENT_HANDOFF.md`, `AGENT_PROMPT.md`
- APK CI: `.github/workflows/build-apk.yml` (triggers on push to `raddflix_flutter/**`)

---

## Live DB State (as of 2026-06-08)
```
v3 DB: /opt/jazzmax/radd-hub/data/radd_hub.db
  Titles:  17  (all Live / is_published=1)
  Files:   28  (all have share_url)
  Account: 03286829827 → account_id=15, legacy_id=2
```

### v3 Schema Quirks (CRITICAL — agents frequently get this wrong)
```python
# titles table
plot        # description field — NOT 'overview' (that's the legacy schema name)
genres_csv  # comma string
cast_json   # JSON (no 'cast_names' column in v3)
is_published # INTEGER 0=Hidden 1=Live

# files table
scanned_at  # timestamp — NOT 'created_at'
fingerprint # pattern: 'scan:<remote_id>'

# NEVER use db.get_setting() — AttributeError → HTTP 500
# Use db.setting(k) / db.set_setting(k, v)
# Settings columns: k and v (NOT key / value)
```

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
- All proxy chains go to `[None]` (direct via wg0)
- This is CORRECT — direct via wg0 is the intended path

---

## db.py API (CRITICAL)
```python
db.setting(k, default='')      # READ a setting
db.set_setting(k, v)           # WRITE a setting
# NEVER use db.get_setting() — it does NOT exist → AttributeError + HTTP 500
```

### SQLite write rule
For writes from background threads or admin routes: use `sqlite3.connect()` + `BEGIN IMMEDIATE`.
DB settings table columns: `k` / `v` (NOT `key` / `value`).

---

## Admin UI Rules
**No `confirm()` or `prompt()` in Flask templates** — blocked by Cloudflare tunnel/proxy.
All destructive actions use two-step arm+fire toast pattern.
All input-required flows (OTP, quota) use inline HTML panels.
See RULES.md Rule 38 for implementation pattern.

---

## Template GitHub Paths (CRITICAL — wrong path = 404 or pushes to wrong place)
```
Admin panel:   radd-hub/hub/templates/admin.html
Scan page:     radd-hub/hub/templates/scan.html
Settings page: radd-hub/hub/templates/settings.html
Library page:  radd-hub/hub/templates/library.html
Base layout:   radd-hub/hub/templates/base.html
scanner.py:    radd-hub/hub/scanner.py
```
Push template files **sequentially** — parallel GitHub PUTs cause 409 SHA conflicts.

---

## Session Lifecycle (with PROXY_BYPASS=1)
```
Flask restart
  → startup_refresh()
  → android_refresh_session()
...
  metadata.py            fetch_imdbapi(), enrich_title()
  _legacy/enricher.py    TMDB fetch_full_metadata(), _clean_filename()
  db.py                  DB helpers — only exports setting() and set_setting()
  routes/
    admin.py             Admin panel API (db/reset, db/restore)
    catalog_api.py       /api/catalog/*
    mobile_api.py        /api/auth/*, usage, history, /api/app/config
    settings.py          Proxy pool admin
    scan.py              Scan routes + excluded-folders CRUD
    zero_rating.py       Zero-rating manager — delta generate/upload/purge
  templates/             (see Template GitHub Paths above)
```

---

## GitHub Push Method (NO git shell ever)
Use Contents API for 1-2 files, Trees API for 3+ files (atomic commit).
See AGENT_PROMPT.md Step 3 for the exact Node.js templates.
Always fetch fresh SHA immediately before PUT — stale SHA = 409 conflict.
**Push template files sequentially — parallel PUTs conflict on the same SHA.**
