# AGENT HANDOFF — Jazz Drive / RaddFlix
**Date**: 2026-06-11
**Session**: APK RE complete + login flow fully reverse-engineered

---

## What Was Done This Session

### 1. All 6 Backend Bugs Fixed & Deployed
| # | File | Fix |
|---|---|---|
| 1 | `radd-hub/hub/uploader.py` | `_pre_upload_save_metadata()` — calls `POST /sapi/upload/{mediaType}?action=save-metadata` BEFORE binary upload, parses `data.id` → GUID |
| 2 | `radd-hub/hub/uploader.py` | Fallback listing triggers on ANY HTTP 200 (was: only empty-body 200) |
| 3 | `radd-hub/hub/jazzdrive.py` | `responsetime=true` added to all `sapi_request()` calls |
| 4 | `radd-hub/hub/uploader.py` | `&responsetime=true` added to direct binary upload URL |
| 5 | `radd-hub/hub/_legacy/scanner.py` | Pagination loop for `GetMediaWrapper.more=true` (uses `offset=N`) |
| 6 | All files syntax-checked and service restarted (`supervisorctl restart raddflix_radd`) |

### 2. APK RE: Complete Login Flow Found
Full details in `jazzdrive_research/LOGIN_FLOW.md` (commit b325a34).
Key findings:
- **client_id = `fnbroot`**, **client_secret = `f&rW23`** (AES-CBC decrypted from ec/C24226a.java)
- **OAuth2 WebView flow**: `jazzdrive.com.pk/oauth2/authorization.php` → `token.php`
- **MobileConnect flow**: Jazz SIM zero-rated login via `/sapi/credential/mobileconnect?action=validate`
- **4 missing HTTP headers**: `x-request-id`, `User-Agent: omh android client`, `X-deviceid: fac-<ANDROID_ID>`, `X-devicename`
- **validationkey** refreshed silently from EVERY SAPI response (AbstractC12813a.m51847w)

### 3. Research Docs Pushed to GitHub
`jazzdrive_research/` at `raddclub/raddflix-app` — 8 files:
- FINDINGS.md, UPLOAD_FLOW.md, FIX_GUIDE.md, API_REFERENCE.md, AUTH_FLOW.md, HANDOFF.md, README.md
- **NEW**: LOGIN_FLOW.md (complete auth reverse engineering)

---

## Current State

### Oracle Server
- **Host**: `ubuntu@92.4.95.252`, SSH key at `/tmp/oracle_key` (regenerate if expired)
- **Service**: `sudo supervisorctl status raddflix_radd` → RUNNING pid 16162, port 5000
- **Repo**: `/opt/jazzmax/` → `raddclub/raddflix-app` (main branch)
- **Flask app**: `/opt/jazzmax/radd-hub/hub/`
- **Memory**: `/opt/jazzmax/.agents/memory/` (2 topic files: jazzdrive-api.md, jazzdrive-login-flow.md)

### What Is NOT Done Yet (Next Agent's Tasks)

#### PRIORITY 1 — Add missing HTTP headers to jazzdrive.py
The 4 OkHttp interceptor headers Oracle is missing:
```python
# In sapi_request() in radd-hub/hub/jazzdrive.py:
import uuid
headers = {
    "User-Agent":   "omh android client",
    "x-request-id": str(uuid.uuid4()),   # new per request
    "X-deviceid":   "fac-oracle-proxy",
    "X-devicename": "OracleProxy",
    "Authorization": f"oauth {base64.b64encode(access_token.encode()).decode()}"
}
```

#### PRIORITY 2 — MobileConnect login endpoint
Jazz SIM users (zero-rated) log in via `/sapi/credential/mobileconnect?action=validate`.
Oracle has NO endpoint for this. Add to `radd-hub/hub/routes/`:
```python
POST /jd/mobileconnect/validate
Body: {"code": "...", "state": "..."}
→ forwards to SAPI, stores access_token + refresh_token + msisdn
```

#### PRIORITY 3 — validationkey refresh from every response
Currently Oracle may only set validationkey on login. The real app updates it from EVERY SAPI response body. Check/fix `jazzdrive.py` `sapi_request()` to parse and store `data.validationkey` after every call.

#### PRIORITY 4 — OAuth2 token exchange endpoint  
Build an endpoint so the Flutter app can exchange an OAuth2 code for tokens via Oracle:
```
POST /jd/oauth2/token
Body: {"code": "<auth_code>"}
→ Oracle POSTs to https://jazzdrive.com.pk/oauth2/token.php
  with client_id=fnbroot, client_secret=f&rW23
→ Returns access_token + refresh_token
```

#### PRIORITY 5 — Flutter app (RaddFlix)
The RaddFlix Flutter app at `raddclub/raddflix-app` needs to implement:
- MobileConnect login screen (Jazz SIM detection)
- OAuth2 webview login screen (for non-SIM users)
- Token storage (SharedPreferences / FlutterSecureStorage)
- SAPI integration using Oracle as proxy (zero-rated via Jazz network)

---

## Rules for Next Agent
1. Use `db.setting()` not `db.get_setting()` in Oracle Flask code
2. Service restart: `sudo supervisorctl restart raddflix_radd` (NOT systemctl)
3. For complex Python over SSH: use `/tmp/script.py` + `scp` pattern (heredoc fails with triple-quoted strings)
4. `responsetime=true` on ALL SAPI URLs (confirmed from SapiHandler.m52004k)
5. No destructive git ops — use Python subprocess for git commands
6. Main repo at `/opt/jazzmax/` (NOT `/opt/jazzmax/radd-hub/`)
7. `validationkey` is a URL query param, not a header

---

## Key API Facts (confirmed from APK RE)

```
SAPI server:  https://cloud.jazzdrive.com.pk
OAuth2 auth:  https://jazzdrive.com.pk/oauth2/authorization.php
OAuth2 token: https://jazzdrive.com.pk/oauth2/token.php
Redirect URI: https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html
client_id:    fnbroot
client_secret: f&rW23

Auth header:  Authorization: oauth <base64(accessToken)>
Session key:  &validationkey=<key>  (URL param, refreshed from every response)
Upload GUID:  POST /sapi/upload/{mediaType}?action=save-metadata → data.id (String)
Pagination:   GetMediaWrapper.more (bool) + offset=N param

All requests need:
  x-request-id: <UUID>
  User-Agent: omh android client
  X-deviceid: fac-<device_id>
  X-devicename: <model>
  &responsetime=true  (URL param)
```

---

## GitHub
- Repo: `raddclub/raddflix-app`
- Latest commit: `b325a34` (LOGIN_FLOW.md added)
- Branch: `main`
- Research docs: `jazzdrive_research/` (8 files)
