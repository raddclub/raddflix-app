# JazzDrive Auth Flow — Session Refresh & SAPI Headers

> Source: `hub/jazzdrive.py`. Verified 2026-06-15 via live HTTP tests.

---

## Authorization Header Format (Required on Every JazzDrive Request)

Built by `get_auth_headers()`. Mirrors the 4 OkHttp interceptors from JazzDrive APK 8.0.1:

```http
User-Agent: omh android client
x-request-id: <new UUID per request>
X-deviceid: <from DB JAZZDRIVE_DEVICE_ID setting, or fac-<last10-of-MSISDN>>
X-devicename: <from DB JAZZDRIVE_DEVICE_NAME, default "Infinix Hot 9 Play">
X-Requested-With: com.jazz.drive
Authorization: oauth <Base64(JSON)>
Cookie: JSESSIONID=<jid>       ← only on SAPI calls where JID is known
validation_key: <vk>           ← only on SAPI calls where VK is known
```

**Authorization JSON structure** (base64-encoded, not URL-encoded):
```json
{
  "data": {
    "accesstoken":    "<raw_accesstoken — 40-char hex>",
    "refreshtoken":   "<refresh_token — 40-char hex>",
    "platform":       "android",
    "expiresin":      "3600",
    "lastrefreshdate": <Unix ms timestamp>,
    "msisdn":         "<03xxxxxxxxx>"
  }
}
```

**Critical rule**: For SAPI login (`keytype=accesstoken`), the `Authorization.data.accesstoken`
MUST be the SAME token as the `key=` URL parameter. The SAPI server validates they match.

---

## SAPI Request Pattern

All authenticated SAPI calls go through `sapi_request()` in `hub/jazzdrive.py`.

**URL pattern:**
```
https://cloud.jazzdrive.com.pk/sapi/<endpoint>?action=<action>&validationkey=<vk>&responsetime=true[&other_params]
```

**Built-in behaviours:**

1. **SEC-1003 auto-rotation** — when server returns `{"error":{"code":"SEC-1003","data":"<new_vk>"}}`, the new VK is saved and the request is retried automatically (up to 3 retries).
2. **JSESSIONID refresh** — when server returns a new `JSESSIONID` cookie on 2xx, it's saved to DB and session file automatically.
3. **`X-Funambol-ValidationKey` header** — if server rotates VK in a response header, it's captured and saved.
4. **Response body VK** — every successful SAPI response body may contain `data.validationkey`; if it differs from the current VK, it's captured (mirrors Android app `AbstractC12813a.m51847w`).
5. **401 auto-recovery** — calls `refresh_session()` which tries OAuth2 then SAPI direct login.
6. **SAPI backoff** — after all recovery strategies fail, the account enters a 30-min backoff. During backoff, all SAPI calls for that account skip the costly retry sequence.

---

## Session Refresh Chain (`refresh_session`)

Called on Flask startup (`startup_refresh`) and on SAPI 401:

```
refresh_session(account_id)
│
├─ Strategy 1: Android OAuth2 (android_refresh_session)
│  │  Requires: refresh_token in DB
│  │
│  ├─ Step 1: POST https://jazzdrive.com.pk/oauth2/token.php
│  │    data: grant_type=refresh_token
│  │          client_id=fnbroot
│  │          client_secret=f&rW23
│  │          refresh_token=<current_rt>
│  │    → {access_token (b64-JSON), refresh_token (NEW, rotated), expires_in}
│  │
│  │  [IMMEDIATELY save new refresh_token to DB before Step 2]
│  │  [RT is saved even if Step 2 fails — chain is never lost]
│  │
│  ├─ Step 2: GET https://cloud.jazzdrive.com.pk/sapi/login/oauth
│  │    ?action=login&platform=Android&keytype=accesstoken
│  │    &key=<url_encoded(base64({"data":{"accesstoken":"<DB raw_accesstoken>"}}))>
│  │    Headers: full get_auth_headers() with DB raw_accesstoken
│  │    → {validationkey, jsessionid, access_token (b64)}
│  │
│  └─ Save new VK + JID + raw_at to DB + session file
│     Return {"ok": True}
│
├─ Strategy 2: sapi_direct_login (fallback when OAuth2 fails)
│  │  Requires: raw_accesstoken in DB
│  │  Triggered when: invalid_grant, network error, no refresh_token
│  │
│  ├─ GET https://cloud.jazzdrive.com.pk/sapi/login/oauth
│  │    ?action=login&platform=Android&keytype=accesstoken
│  │    &key=<url_encoded(base64({"data":{"accesstoken":"<raw_accesstoken>"}}))>
│  │    Headers: full get_auth_headers() with raw_accesstoken
│  │    → {validationkey, jsessionid}
│  │
│  └─ Save new VK + JID to DB
│     Return {"ok": True}
│
└─ If both fail: Return {"ok": False, "error": "All refresh strategies failed. OAuth2: ... | SAPI direct: ..."}
```

**Important**: `startup_refresh` failure does NOT wipe VK/JID. The uploader reads VK directly
from DB via `get_active_account()` and calls `verify_jd_session()` independently. A failed
refresh only means silent renewal failed — uploads continue while VK is valid.

---

## SAPI Token Resolution Rules

```
For SAPI login (keytype=accesstoken):
  MUST use DB raw_accesstoken (OTP-issued, SAPI-registered)
  NEVER use OAuth2-rotated access_token (not registered in SAPI → HTTP 401 empty body)

For OAuth2 refresh (token.php):
  MUST use current refresh_token from DB
  refresh_token rotates on each call — save immediately, do not call twice

For all other SAPI calls:
  MUST have valid validation_key + JSESSIONID
  Obtained via OTP login or refresh_session() chain above
```

---

## Keepalive

`hub/_legacy/jazz_keepalive.py` runs a background thread that:

1. Sends a heartbeat to `GET /sapi/system/information` every ~5 minutes.
2. If `consecutive_failures >= 2`, calls `refresh_session()`.
3. If `consecutive_failures >= 4` and conflict detected, pauses for 10 minutes.
4. Records each heartbeat result to an in-memory event log (last 100 events).
5. Updates `accounts.last_keepalive_at` on success.

**Effect**: As long as heartbeats succeed, JSESSIONID never expires from idle.
JSESSIONID expires after 3600s WITHOUT any SAPI call — keepalive prevents this.

---

## Proxy Architecture

```
JAZZDRIVE_PROXY_BYPASS=1 (current Oracle setting):
  ALL JD traffic → wg0 VPN → Cloudflare exit → JazzDrive
  No proxy pool calls made.

JAZZDRIVE_PROXY_BYPASS=0:
  OAuth2 calls (jazzdrive.com.pk): resolve_proxies(purpose='otp')
  SAPI login calls: direct pool access via proxy_pool.pool.get_best()
  Other SAPI calls: resolve_proxies(purpose='sapi')

proxy_pool table (sapi_proxies):
  Health-checked Pakistani SOCKS proxies.
  Circuit breaker: >80% dead → fallback to direct.
  Fast recovery thread: retests disabled proxies every 5 min.
```

**Key fact**: JazzDrive is NOT geo-restricted. Confirmed by live tests from Replit
(USA), Oracle (India), and direct IP. The only restriction is the UA gate.

---

## Concurrency Guards

1. **Per-account refresh lock** (`_refresh_locks`): prevents two threads from calling `android_refresh_session()` for the same account simultaneously — second caller waits, then detects DB RT changed and returns early (no double burn).

2. **Cooldown guard** (`_REFRESH_COOLDOWN_S = 120s`): after a successful refresh, subsequent calls within 120 seconds return current DB tokens without making a network call.

3. **SAPI backoff** (`_SAPI_BACKOFF`, 30 min): after all recovery fails, skips retry for 30 minutes. Cleared immediately on new OTP login.

4. **Global lock** (`_lock`): protects all DB writes to accounts table.
