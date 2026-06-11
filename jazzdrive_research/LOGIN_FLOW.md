# JazzDrive Complete Login Flow & App Identity
## Full APK Reverse-Engineering Findings — Jazz Drive 8.0.1

---

## 1. App Identity Constants (from decompiled APK)

| Field | Value | Source |
|---|---|---|
| Package name | `com.jazz.androidsync` | AndroidManifest.xml |
| App name | `Jazz Drive` | strings.xml `app_system_name` |
| App version | `8.0.1` | C9818s.java `mo42427D()` |
| SAPI server | `https://cloud.jazzdrive.com.pk` | strings.xml `app_server_host` |
| Server port | `80` (scheme forces HTTPS) | strings.xml `app_server_port/scheme` |
| OAuth2 authorize URL | `https://jazzdrive.com.pk/oauth2/authorization.php` | strings.xml `oauth2_auth_token_uri` |
| OAuth2 token URL | `https://jazzdrive.com.pk/oauth2/token.php` | strings.xml `oauth2_access_token_uri` |
| OAuth2 redirect URI | `https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html` | strings.xml `oauth2_redirect_uri` |
| MobileConnect webview | `https://cloud.jazzdrive.com.pk/ui/html/mobileconnect.html?embedded=true#start` | strings.xml `mobile_connect_login_url` |
| client_id | **`fnbroot`** | AES-CBC decrypt of C24226a.f62869b |
| client_secret | **`f&rW23`** | AES-CBC decrypt of C24226a.f62871d |
| OAuth2 scope | *(empty string)* | strings.xml `oauth2_scope` |
| Auth in body | `true` | bools.xml `oauth2_authentication_in_body` |
| Nonce validation | `false` | bools.xml `oauth2_nonce_validation_enabled` |
| User-Agent prefix | `omh android client` | strings.xml `app_user_agent_prefix` |
| Device ID prefix | `fac-` | strings.xml `app_device_id_prefix` |
| Device ID source | `fac-<ANDROID_ID>` or `fac-ts<timestamp>` if no ANDROID_ID | C9765k.java `mo42302k()` |

### client_id / client_secret Decryption (AES-CBC)
Stored in `ec/C24226a.java` as 3 Base64 strings, decrypted via `jm/C26710a.m85218e()`:
```
C24226a.f62869b → client_id:
  ciphertext = "Rue+xcBPFH52y2oouyqG/w=="
  key        = "3Bdy7nzvB5PASpwfWQK2Iw=="
  iv         = "7/iZTGdzCrlcyKqC45Duow=="
  AES/CBC/PKCS7 → "fnbroot"

C24226a.f62871d → client_secret:
  ciphertext = "qMgs+GVzXZNaeqEl4PlZpw=="
  key        = "cvosadPhim8NNnDTDryUyQ=="
  iv         = "UDczopEQlTHb+3+P6xii7A=="
  AES/CBC/PKCS7 → "f&rW23"
```

---

## 2. HTTP Headers on EVERY Request (4 OkHttp Interceptors)

The app builds its OkHttpClient in `pk/AbstractC30646d.m100958g()` with interceptors in this order:

| # | Header | Value | Interceptor Class | File |
|---|---|---|---|---|
| 1 | `x-request-id` | `UUID.randomUUID()` (new UUID per request) | `C30920a` (`AddRequestIdInterceptor`) | `p508qk/C30920a.java` |
| 2 | `User-Agent` | `omh android client` (prefix; version may be appended) | `C30921b` (`AddUserAgentInterceptor`) | `p508qk/C30921b.java` |
| 3 | `X-deviceid` | `fac-<ANDROID_ID>` | `C30924e` (`DeviceInterceptor`) | `p508qk/C30924e.java` |
| 4 | `X-devicename` | Device model name string | `C30924e` (`DeviceInterceptor`) | `p508qk/C30924e.java` |
| 5 | `Authorization` | `oauth <Base64(accessToken)>` | `C12815c` (`OAuth2AuthenticatorInterceptor`) | `com/funambol/sapi/network/interceptor/C12815c.java` |
| 6 | URL param: `validationkey` | `&validationkey=<session_key>` (appended to URL) | `AbstractC12813a.m51833d()` | `com/funambol/sapi/network/interceptor/AbstractC12813a.java` |
| 7 | `responsetime` | `true` (URL param on all SAPI calls) | `SapiHandler.m52004k()` | `com/funambol/sapisync/sapi/SapiHandler.java` |

**Note:** Headers 1-4 are added to EVERY HTTP request (even non-auth). Header 5 only on authenticated endpoints. Header 6 is skipped on `/sapi/login` and `/sapi/mobile?signup`. Headers 6-7 are URL query params, not HTTP headers.

---

## 3. Complete Login Flow — Three Paths

### Path A: OAuth2 WebView (Standard Login)

```
Step 1 — Build authorize URL:
  GET https://jazzdrive.com.pk/oauth2/authorization.php
    ?response_type=code
    &client_id=fnbroot
    &redirect_uri=https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html
    &access_type=offline
    &scope=
    &state=<random int 0-100000>

Step 2 — User logs in via WebView (username+password or MSISDN+OTP via Jazz web)

Step 3 — WebView intercepts redirect to redirect_uri:
  GET https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html?code=<AUTH_CODE>&state=<state>
  App extracts `code` and verifies `state`

Step 4 — Exchange code for tokens:
  POST https://jazzdrive.com.pk/oauth2/token.php
  Content-Type: application/x-www-form-urlencoded
  Body: grant_type=authorization_code
        &code=<AUTH_CODE>
        &redirect_uri=https%3A%2F%2Fcloud.jazzdrive.com.pk%2Fui%2Fhtml%2Fclientoauth.html
        &client_id=fnbroot
        &client_secret=f%26rW23
  [oauth2_authentication_in_body=true → credentials in body, NOT Basic Auth header]

Step 5 — Response (JSON):
  {
    "access_token": "<bearer_token>",
    "refresh_token": "<refresh_token>",
    "expires_in": "<seconds>"
  }

Step 6 — Store tokens.
  All subsequent SAPI calls:
  Authorization: oauth <Base64(access_token)>
```

### Path B: MobileConnect (Jazz SIM — Zero-Rated)

```
Step 1 — Open WebView to:
  https://cloud.jazzdrive.com.pk/ui/html/mobileconnect.html?embedded=true#start

Step 2 — Network: Jazz SIM auto-detected by server (MSISDN header injection by Jazz network)
  Server sends OTP if needed. Webview handles UI.

Step 3 — WebView JS callback returns `code` + `state` to Android app.

Step 4 — Validate via SAPI:
  POST /sapi/credential/mobileconnect?action=validate&responsetime=true
  Authorization: oauth <Base64(accessToken)>   [or empty if not logged in]
  Content-Type: application/json
  Body: {"data": {"code": "<code>", "state": "<state>"}}

Step 5 — Response:
  {"data": {
    "access_token": "<token>",
    "refresh_token": "<refresh>",
    "msisdn": "92XXXXXXXXXX",
    "expires_in": "<secs>",
    "lastrefreshdate": 1234567890
  }}

Step 6 — Store tokens and proceed as in OAuth2 path.
```
**This is the primary login path for Jazz SIM users (zero-rated). Oracle does NOT implement this.**

### Path C: Legacy SAPI Login (Basic Auth)

```
Step 1 — POST /sapi/login?action=login&responsetime=true
  Authorization: Basic <Base64(username:password)>
  Content-Type: application/json

Step 2 — Response:
  {"data": {
    "validationkey": "<session_key>",
    "jsessionid": "<session_id>"
  }}
  Model: com.funambol.mobileconnect.model.LoginResponse

Step 3 — All subsequent SAPI calls append:
  &validationkey=<session_key>
  [AbstractC12813a.m51847w() updates validationkey from EVERY response]

Step 4 — On 401 (NotAuthorizedCallException):
  Interceptor re-POSTs login, gets fresh validationkey, retries original request
```

---

## 4. validationkey Lifecycle (Critical)

The `validationkey` is the "session identity" of a SAPI connection:
- **Set on login** — server sends it in `data.validationkey` of login response
- **Updated on every response** — `AbstractC12813a.m51847w()` reads `data.validationkey` from EVERY SAPI JSON response and stores the latest one
- **Appended to every URL** — `m51833d()` adds `&validationkey=<latest>` to all request URLs
- **Skipped for** — `/sapi/login?action=login` and `/sapi/mobile?action=signup`
- **401 handling** — interceptor re-logs in to get new validationkey, then retries the request

**Oracle gap**: The validationkey update-from-response logic may not be working — if a newer validationkey from a recent response is not picked up, the next request uses a stale one → 401 cascade.

---

## 5. Token Refresh (OAuth2)

The `Authorization` header response from server can include a new token:
```
Response header: Authorization: oauth <new_base64_encoded_token>
```
`C12815c.m51859x()` reads the response `Authorization` header, decodes it, and updates the stored access_token if the server rotates it silently.

---

## 6. What Oracle is Missing (Identity Gaps)

| # | Header/Param | Status | Impact |
|---|---|---|---|
| `x-request-id` | ❌ NOT sent | Server may log/trace requests per ID; some features may need it |
| `User-Agent: omh android client` | ❌ NOT sent (using default OkHttp UA or none) | Server may check UA for feature flags |
| `X-deviceid: fac-<ANDROID_ID>` | ❌ NOT sent | Server uses this to identify devices; multi-device management |
| `X-devicename: <model>` | ❌ NOT sent | Server shows device name in user's account panel |
| `MobileConnect login` | ❌ NOT implemented | Jazz SIM users (zero-rated) can't log in via Oracle proxy |
| `validationkey refresh` | ⚠️ May be stale | If Oracle doesn't update validationkey from responses → 401 on second+ calls |
| `client_id=fnbroot` | ✅ Now known | Can be used in OAuth2 token exchange via Oracle |
| `client_secret=f&rW23` | ✅ Now known | Same — URL-encode the `&` as `%26` |

---

## 7. Recommended Oracle Fixes

### Fix 1 — Add missing headers to every outbound request (jazzdrive.py)
```python
import uuid

DEFAULT_HEADERS = {
    "User-Agent":   "omh android client",
    "x-request-id": None,       # set per-request: str(uuid.uuid4())
    "X-deviceid":   "fac-oracle-proxy",   # stable fake device ID
    "X-devicename": "OracleProxy",
}

def sapi_request(...):
    headers = dict(DEFAULT_HEADERS)
    headers["x-request-id"] = str(uuid.uuid4())
    ...
```

### Fix 2 — validationkey: update from every response body
```python
def _update_validationkey(response_json, config):
    data = response_json.get("data", {})
    if "validationkey" in data:
        config.validationkey = data["validationkey"]
        db.set_setting("validationkey", data["validationkey"])
```
Call this after every successful SAPI response.

### Fix 3 — MobileConnect login endpoint (for Jazz SIM users)
```python
@app.route("/jd/mobileconnect/validate", methods=["POST"])
def mobileconnect_validate():
    data = request.json
    code = data.get("code")
    state = data.get("state")
    resp = sapi_request("credential/mobileconnect", "validate",
                        body={"data": {"code": code, "state": state}})
    tokens = resp["data"]
    # store access_token, refresh_token, msisdn
    return jsonify(tokens)
```

### Fix 4 — OAuth2 token exchange (for building auth via Oracle)
```python
import requests, urllib.parse

def exchange_oauth2_code(code):
    resp = requests.post("https://jazzdrive.com.pk/oauth2/token.php",
        data={
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  "https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html",
            "client_id":     "fnbroot",
            "client_secret": "f&rW23",
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=10
    )
    return resp.json()
```

---

## 8. HTTP Request Example (Authenticated)

A real authenticated SAPI request from the Android app looks like this:

```http
GET https://cloud.jazzdrive.com.pk/sapi/media?action=get&scoring=true&responsetime=true&validationkey=<KEY>
User-Agent: omh android client
Authorization: oauth <Base64(accessToken)>
x-request-id: 3f9a8b21-dead-beef-cafe-012345678abc
X-deviceid: fac-a1b2c3d4e5f6a1b2
X-devicename: Xiaomi Redmi Note 8
Accept: application/json
```

---

## 9. Source File Map

| Concern | File |
|---|---|
| SAPI URL builder (responsetime, validationkey) | `com/funambol/sapisync/sapi/SapiHandler.java` |
| OAuth2 token injection (`Authorization: oauth`) | `com/funambol/sapi/network/interceptor/C12815c.java` |
| validationkey management, 401 retry | `com/funambol/sapi/network/interceptor/AbstractC12813a.java` |
| x-request-id interceptor | `p508qk/C30920a.java` |
| User-Agent interceptor | `p508qk/C30921b.java` |
| X-deviceid/X-devicename interceptor | `p508qk/C30924e.java` |
| OkHttp client builder (all interceptors wired) | `pk/AbstractC30646d.java` |
| AES-CBC decryption of client_id/secret | `jm/C26710a.java` |
| Encrypted credentials store | `ec/C24226a.java` |
| Jazz-specific Customization (all URLs/flags) | `com/funambol/android/C9818s.java` |
| MobileConnect validate Retrofit interface | `p401mj/InterfaceC29445c.java` |
| Device ID generation (fac- prefix + ANDROID_ID) | `com/funambol/android/C9765k.java` |
| All string constants (URLs, UA, device prefix) | `resources/res/values/strings.xml` |
| OAuth2 flags (auth_in_body, nonce_validation) | `resources/res/values/bools.xml` |
