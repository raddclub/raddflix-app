# agent-hub/CONTEXT.md — RaddFlix System Context
Last updated: 2026-06-07

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
wg0 WireGuard routes all JazzDrive IPs and works correctly for all call types.
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

## Flutter App Key Files
```
raddflix_flutter/lib/
  core/security/request_encoder.dart   XOR decode + base64 padding fix (CRITICAL)
  core/api/api_client.dart             Dio + XOR + auth interceptors
  core/db/local_db.dart                SQLCipher DB, schema v17
  screens/player_screen.dart           Video player
  providers/auth_provider.dart         Auth state + session restore
```

## Flask Key Files
```
radd-hub/hub/
  jazzdrive.py           JazzDrive session, OTP, upload, keepalive
  proxy_pool.py          SOCKS/HTTP proxy pool management
  keepalive.py           Heartbeat upload scheduler
  uploader.py            JazzDrive upload queue
  scanner.py             Content scanner
  db.py                  DB helpers — only exports setting() and set_setting()
  routes/
    admin.py             Admin panel API
    catalog_api.py       /api/catalog/*
    mobile_api.py        /api/auth/*, usage, history, /api/app/config
    settings.py          Proxy pool admin
```

---

## GitHub Push Method (NO git shell ever)
Use Contents API for 1-2 files, Trees API for 3+ files (atomic commit).
See AGENT_PROMPT.md Step 3 for the exact Node.js templates.
Always fetch fresh SHA immediately before PUT — stale SHA = 409 conflict.
