# JazzDrive APK Parity Audit

> **Date:** 2026-06-15. Full forensic comparison of our hub HTTP calls vs the
> real JazzDrive APK 8.0.1 (OkHttp 4 / Retrofit 2 / Gson). Every entry is
> confirmed — no guesses.

---

## Summary Table

| # | Area | Real APK | Our Hub (before fix) | Status |
|---|------|----------|---------------------|--------|
| 1 | `X-deviceid` format | `fac-fcbf291eddd5d372` | `fcbf291eddd5d372` (no prefix) | ✅ Fixed |
| 2 | Web OAuth portal UA | Android WebView UA | Dalvik/2.1.0 (Java HTTP UA) | ✅ Fixed |
| 3 | `Authorization` header | Always present (interceptor) | Missing when raw_at is None | ✅ Fixed |
| 4 | `Content-Type` on JSON POST | `application/json; charset=UTF-8` | `application/json` (no charset) | ✅ Fixed |
| 5 | `Accept` header on SAPI | `application/json` | `application/json, text/plain, */*` | ✅ Fixed |
| 6 | `Accept` in legacy scanner | `application/json` | `application/json, text/javascript, */*; q=0.01` | ✅ Fixed |
| 7 | `User-Agent` on SAPI calls | `omh android client` | `omh android client` | ✅ Correct |
| 8 | `X-Requested-With` | `com.jazz.drive` | `com.jazz.drive` | ✅ Correct |
| 9 | `X-devicename` | `Infinix Hot 9 Play` | `Infinix Hot 9 Play` | ✅ Correct |
| 10 | `x-request-id` | New UUID per request | New UUID per request | ✅ Correct |
| 11 | Authorization JSON format | compact, no spaces | compact, no spaces | ✅ Correct |
| 12 | `expiresin` field type | `"3600"` (string) | `"3600"` (string) | ✅ Correct |
| 13 | `lastrefreshdate` | Unix ms (`int(time*1000)`) | Unix ms (`int(time*1000)`) | ✅ Correct |
| 14 | `platform` in auth JSON | `"android"` (lowercase) | `"android"` (lowercase) | ✅ Correct |
| 15 | OAuth2 `grant_type` | `authorization_code` / `refresh_token` | both present | ✅ Correct |
| 16 | OAuth2 `redirect_uri` | `https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html` | same | ✅ Correct |
| 17 | `client_id` / `client_secret` | `fnbroot` / `f&rW23` | `fnbroot` / `f&rW23` | ✅ Correct |
| 18 | SAPI `responsetime=true` | present | present | ✅ Correct |
| 19 | `X-Funambol-ValidationKey` capture | yes | yes | ✅ Correct |
| 20 | SEC-1003 VK rotation | auto-handled | auto-handled | ✅ Correct |
| 21 | JSESSIONID cookie capture | automatic | automatic | ✅ Correct |
| 22 | SSL `verify=False` scope | ONLY `jazzdrive.com.pk` | ONLY `jazzdrive.com.pk` | ✅ Correct |
| 23 | Push/FCM token | sent via separate call | not sent | ⚪ Intentional — no push needed |
| 24 | HTTP/2 vs HTTP/1.1 | OkHttp uses HTTP/2 | `requests` uses HTTP/1.1 | ⚪ Acceptable — server supports both |

---

## Fixed Issues (Detail)

### Fix 1 — `X-deviceid` missing `fac-` prefix

**APK source:** `C9765k.java mo42302k()` — the function always prepends `fac-`
before the Android device ID string. Confirmed: "APK research: device_id prefix
is always 'fac-'".

```
Before: X-deviceid: fcbf291eddd5d372
After:  X-deviceid: fac-fcbf291eddd5d372
```

**Fix location:** `hub/jazzdrive.py` → `get_x_deviceid()` — normalises on read:
```python
return stored if stored.startswith("fac-") else f"fac-{stored}"
```
DB setting `JAZZDRIVE_DEVICE_ID` stores the raw Android ID (`fcbf291eddd5d372`);
the function auto-adds `fac-`. No DB change needed.

---

### Fix 2 — Web OAuth portal User-Agent: Dalvik → WebView

**Why it matters:** The JazzDrive APK shows the OAuth2 login portal inside an
Android `WebView`. The WebView sends a Chrome-based UA with the `; wv)` marker.
`Dalvik/2.1.0` is the raw Java `URLConnection` UA — something JazzDrive's web
server could fingerprint as a non-standard client.

```
Before: Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)
After:  Mozilla/5.0 (Linux; Android 10; Infinix X680F Build/QP1A.190711.020; wv)
        AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/87.0.4280.141
        Mobile Safari/537.36
```

**Fix locations:** `hub/_legacy/scanner.py` → `jazzdrive_login()` and
`jazzdrive_verify_otp()` — both `_UA_ANDROID` constants updated.

---

### Fix 3 — `Authorization` header always present

**APK source:** `C12815c OAuth2AuthenticatorInterceptor` — an OkHttp interceptor
that runs on EVERY request and adds Authorization if the user is logged in, even
if the token is empty.

**Before:** `get_auth_headers()` only added the header `if raw_accesstoken:` —
accounts logged in before the `raw_accesstoken` DB column was added had no header.

**After:** The header is included whenever ANY auth token is present (VK, JID,
or raw_at). Empty `accesstoken` / `refreshtoken` fields are sent as `""` rather
than omitting the header entirely.

---

### Fix 4 — `Content-Type: application/json; charset=UTF-8`

**APK source:** OkHttp with Retrofit + Gson uses
`RequestBody.create(MediaType.get("application/json; charset=UTF-8"), json)`.

**Fix location:** `hub/jazzdrive.py` → `sapi_request()` — for POST/PUT/PATCH
with a JSON body:
```python
req_headers.setdefault("Content-Type", "application/json; charset=UTF-8")
```

---

### Fix 5 & 6 — `Accept` header standardised

**APK source:** Retrofit with Gson generates `Accept: application/json` on
annotated endpoints. No `text/plain` or `text/javascript` qualifiers.

```
Before (jazzdrive.py):     Accept: application/json, text/plain, */*
Before (legacy SAPI login): Accept: application/json, text/javascript, */*; q=0.01
Before (mobile_direct):     Accept: application/json, */*
After (all):                Accept: application/json
```

---

## Confirmed NOT Different (Would Not Help)

### FCM / Push Token
The real APK registers an FCM push token with JazzDrive during login so the server
can send push notifications. Our hub does not need push notifications — we have our
own keepalive heartbeat. Not sending this is intentional and harmless.

### HTTP/2 vs HTTP/1.1
OkHttp negotiates HTTP/2 via ALPN when the server supports it. Python `requests`
uses HTTP/1.1 by default. JazzDrive cloud servers accept both. This is not a
functional difference — all endpoints work correctly over HTTP/1.1.

### `scope` parameter in OAuth2
The real APK does NOT send a `scope` parameter to `token.php`. We confirmed this
by checking the APK strings and our verified live token exchanges. No fix needed.

### `deviceType` in `token.php` POST body
The real APK's `token.php` POST does NOT include `deviceType`, `deviceName`, or
`deviceId` as form fields. Device registration on JazzDrive happens via the SAPI
headers (`X-deviceid`, `X-devicename`), not the OAuth2 body. No fix needed.

### `validation_key` as header vs URL param
We send it in both places: as `validation_key:` header (inside `get_auth_headers`)
AND as `validationkey=` URL param (in `sapi_request`). The APK only sends it as
a URL param. The server accepts both. No functional impact.

---

## Device Identity (After All Fixes)

Every JazzDrive request from the hub now sends exactly:

```http
User-Agent: omh android client           ← SAPI calls
X-deviceid: fac-fcbf291eddd5d372         ← your real Infinix hardware ID, correctly prefixed
X-devicename: Infinix Hot 9 Play
X-Requested-With: com.jazz.drive
x-request-id: <fresh UUID per request>
Authorization: oauth <base64(cred_JSON)>
Content-Type: application/json; charset=UTF-8   ← POST/PUT/PATCH only
Accept: application/json
```

Web OAuth portal (authorization.php, signup.php, verify.php):
```http
User-Agent: Mozilla/5.0 (Linux; Android 10; Infinix X680F Build/QP1A.190711.020; wv)
            AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/87.0.4280.141
            Mobile Safari/537.36
X-Requested-With: com.jazz.drive
```

---

## My Devices Page — Why Blank Entry Still Shows

The blank unnamed entry in `cloud.jazzdrive.com.pk/#profile → My Devices` was
created by an EARLIER login session that sent `X-deviceid: fac-3257719165`
(the old MSISDN-based fallback) with no `X-devicename`.

JazzDrive stores a device record per unique `X-deviceid`. It does NOT update the
device name retroactively when the same device ID reconnects.

**To resolve:**
1. On the JazzDrive My Devices page, click **Unlink** on the blank entry.
2. The hub's next OTP login or `sapi_direct_login()` call will register a fresh
   device record with `fac-fcbf291eddd5d372` + name `Infinix Hot 9 Play`.

Alternatively, the entry will naturally update on next keepalive heartbeat if
JazzDrive re-evaluates device info on session ping (behaviour varies by JD version).
