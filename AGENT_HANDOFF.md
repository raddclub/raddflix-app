# AGENT HANDOFF — Jazz Drive / RaddFlix
**Date**: 2026-06-11
**Session**: JazzDrive identity hardening — 100% APK parity achieved

---

## What Was Done This Session

### 1. jazzdrive.py — 6 patches (full Android APK identity parity)

| # | Function | Change |
|---|---|---|
| 1 | get_x_deviceid() | Prefix changed android-raddhub- → fac- (APK: fac-<ANDROID_ID>, strings.xml app_device_id_prefix) |
| 2 | get_auth_headers() | User-Agent: Dalvik/... → omh android client (APK strings.xml app_user_agent_prefix) |
| 3 | get_auth_headers() | Added x-request-id: UUID per request (APK C30920a AddRequestIdInterceptor) |
| 4 | get_auth_headers() | Added X-devicename: Samsung Galaxy A51 (APK C30924e DeviceInterceptor, DB-settable via JAZZDRIVE_DEVICE_NAME) |
| 5 | get_auth_headers() | Added Authorization: oauth Base64(raw_accesstoken) when token available (APK C12815c OAuth2AuthenticatorInterceptor) |
| 6 | sapi_request() | Passes raw_accesstoken from DB tokens to get_auth_headers() — every authenticated SAPI call carries Authorization |
| 7 | sapi_request() | After every 2xx response: reads data.validationkey from JSON body and persists (APK AbstractC12813a.m51847w) |
| 8 | _android_refresh_session_inner() | SAPI step now uses get_auth_headers() for correct identity headers |
| 9 | refresh_jsessionid() | Passes raw_accesstoken for Authorization header on re-login calls |

### 2. routes/jd_auth.py — new file (3 endpoints)

| Endpoint | Purpose |
|----------|---------|
| GET /api/jd/oauth2/authorize_url | Returns full OAuth2 authorize URL (fnbroot client_id, state, redirect_uri) |
| POST /api/jd/oauth2/token | Exchanges auth code via token.php with fnbroot/f&rW23 credentials in body |
| POST /api/jd/mobileconnect/validate | Forwards code+state to /sapi/credential/mobileconnect?action=validate |

All 3 endpoints carry the full Android identity headers on every outbound JazzDrive call.
All 3 endpoints verified live on Oracle.

### 3. app.py — jd_auth blueprint registered at /api/jd/*

---

## Current State

### Oracle Server
- **Host**: ubuntu@92.4.95.252, SSH key at /tmp/oracle_key (regenerate if expired)
- **Service**: sudo supervisorctl status raddflix_radd → RUNNING, port 5000
- **Repo**: /opt/jazzmax/ → raddclub/raddflix-app (main branch)
- **Flask app**: /opt/jazzmax/radd-hub/hub/

### JazzDrive Identity — Complete Parity Checklist
| APK Interceptor | Header/Param | Oracle Status |
|---|---|---|
| C30920a AddRequestIdInterceptor | x-request-id: UUID (new per request) | DONE |
| C30921b AddUserAgentInterceptor | User-Agent: omh android client | DONE |
| C30924e DeviceInterceptor | X-deviceid: fac-<suffix> | DONE |
| C30924e DeviceInterceptor | X-devicename: Samsung Galaxy A51 | DONE |
| C12815c OAuth2AuthenticatorInterceptor | Authorization: oauth Base64(token) | DONE |
| SapiHandler.m52004k | &responsetime=true URL param | DONE (was already) |
| AbstractC12813a.m51847w | validationkey refreshed from every response body | DONE |
| AbstractC12813a.m51833d | &validationkey=<key> URL param | DONE (was already) |
| OAuth2 WebView | GET /api/jd/oauth2/authorize_url | DONE |
| token.php exchange | POST /api/jd/oauth2/token | DONE |
| MobileConnect | POST /api/jd/mobileconnect/validate | DONE |

### What Is NOT Done Yet (Flutter side)
1. MobileConnect login screen — WebView to mobileconnect.html?embedded=true#start, JS bridge, call POST /api/jd/mobileconnect/validate
2. OAuth2 WebView login screen — call GET /api/jd/oauth2/authorize_url, open WebView, intercept redirect, call POST /api/jd/oauth2/token
3. Token storage in Flutter — FlutterSecureStorage for access_token + refresh_token
4. SAPI calls via Oracle proxy — already working, Oracle adds all identity headers before forwarding

---

## Rules for Next Agent
1. Use db.setting() not db.get_setting() in Oracle Flask code
2. Service restart: sudo supervisorctl restart raddflix_radd (NOT systemctl)
3. JAZZDRIVE_DEVICE_NAME DB setting controls X-devicename (default: "Samsung Galaxy A51")
4. responsetime=true on ALL SAPI URLs (confirmed from SapiHandler.m52004k)
5. git stash gotcha: if git pull fails after stash, && skips stash pop. Pop manually or avoid stash.
6. Main repo at /opt/jazzmax/ (NOT /opt/jazzmax/radd-hub/)
7. validationkey is both a URL query param AND refreshed from every response body

---

## Key API Facts (confirmed from APK RE)

SAPI server:  https://cloud.jazzdrive.com.pk
OAuth2 auth:  https://jazzdrive.com.pk/oauth2/authorization.php
OAuth2 token: https://jazzdrive.com.pk/oauth2/token.php
Redirect URI: https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html
MobileConnect: https://cloud.jazzdrive.com.pk/ui/html/mobileconnect.html?embedded=true#start
client_id:    fnbroot
client_secret: f&rW23
Auth header:  Authorization: oauth <base64(accessToken)>
Session key:  &validationkey=<key>  (URL param + refreshed from every response body)
Device ID:    X-deviceid: fac-<msisdn_suffix>
Device name:  X-devicename: Samsung Galaxy A51  (DB-settable: JAZZDRIVE_DEVICE_NAME)
Request ID:   x-request-id: <UUID>  (new per request)
User-Agent:   omh android client
responsetime: &responsetime=true (URL param on all SAPI calls)

---

## GitHub
- Repo: raddclub/raddflix-app
- Latest commit: 3cd109c (jazzdrive.py identity parity)
- Branch: main
