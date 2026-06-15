# JazzDrive APK RE — Key Findings

**Source**: Jazz Drive 8.0.1 XAPK decompiled (29,381 Java files)
**Date**: June 2026

---

## Critical Auth Findings (from nk/c.java OAuth2Credentials.d())

### Authorization Header — CORRECT FORMAT
```
Authorization: oauth <Base64({"data":{"accesstoken":"<raw_at>","refreshtoken":"<rt>","platform":"android","expiresin":"<secs>","lastrefreshdate":<unix_ms>,"msisdn":"<msisdn>"}})>
```
**NOT** just `oauth <Base64(raw_token)>`. The full JSON credential wrapper is required.
Previous RaddHub implementation was wrong — fixed June 2026.

### `keytype=otp` DOES NOT EXIST
The string `keytype=otp` appears nowhere in the Jazz Drive 8.0.1 APK.
- Only `keytype=accesstoken` is used (in OAuth2LogoutTask, login/oauth)
- The `LOCKBOX_OTP` in the APK is for the Lockbox password manager feature — **NOT login**
- Login OTP is handled inside the MobileConnect WebView, never via a direct API call
- Correct login endpoint: `POST /sapi/credential/mobileconnect?action=validate` (code+state)

---

## Upload Flow (Confirmed)

### Pre-upload save-metadata → returns file GUID
`POST /sapi/upload/{mediaType}?action=save-metadata`
- Body: form-encoded `data=<URL-encoded JSON>`
- Request class: `UploadSaveMetadataRequest`
- Response class: `UploadSaveMetadataResponse`
  - `id` (String) — server-assigned file GUID ← **THE FILE ID**
  - `success` (String)
  - `status` (String)
  - `error` (ErrorWrapper)

### Binary upload → NO id field in response
`POST /sapi/upload?action=save` (multipart)
- Response class: `UploadResponse`
  - `status` (String) — U/C/A/V/I
  - `etag` (String)
  - `lastupdate` (long)
  - **NO id field** — ID already assigned by pre-upload step

### `ItemUploadTask` execution order
1. `m46417O1()` → `mo107994a(item)` → save-metadata → GUID stored in local DB
2. `m46445Z1()` → `mo107996c(item, inputStream)` → binary upload
3. `m46448a2(guid)` → fetch complete item metadata by GUID

---

## Scan/List Flow

### `GetMediaWrapper` (media list response)
- `media` — `List<Item>` — the items on this page
- `more` — `boolean` — true if more pages available
Pagination uses `offset` parameter.

### `SapiHandler.m52004k`
Always appends `responsetime=true` to every SAPI URL.

---

## Authentication Constants (from strings.xml + AES-CBC decryption)
| Key | Value |
|---|---|
| `app_server_host` | `cloud.jazzdrive.com.pk` |
| `app_server_scheme` | `https` |
| `oauth2_access_token_uri` | `https://jazzdrive.com.pk/oauth2/token.php` |
| `oauth2_auth_token_uri` | `https://jazzdrive.com.pk/oauth2/authorization.php` |
| `oauth2_redirect_uri` | `https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html` |
| `mobile_connect_login_url` | `/ui/html/mobileconnect.html?embedded=true#start` |
| `mobile_connect_redirect_url` | `/ui/html/clientoauth.html` |
| `oauth2_scope` | *(empty)* |
| `client_id` | `fnbroot` |
| `client_secret` | `f&rW23` |
| `User-Agent` | `omh android client` |
| Device ID prefix | `fac-` |

---

## Lockbox Feature (NOT related to login)
- `GET /sapi/lockbox/pin` → returns OTP for Lockbox password-manager unlock
- `POST /sapi/lockbox/unlock` with locked item IDs
- `POST /sapi/lockbox/lock` with item IDs
- `GET /sapi/lockbox/content`
- This is the Funambol Lockbox encrypted folder feature — unrelated to login/OTP

---

## SAPI Interceptors (OkHttp chain in pk/AbstractC30646d)
| # | Header | Value | Class |
|---|---|---|---|
| 1 | `x-request-id` | `UUID.randomUUID()` | C30920a AddRequestIdInterceptor |
| 2 | `User-Agent` | `omh android client` | C30921b AddUserAgentInterceptor |
| 3 | `X-deviceid` | `fac-<ANDROID_ID>` | C30924e DeviceInterceptor |
| 4 | `X-devicename` | device model | C30924e DeviceInterceptor |
| 5 | `Authorization` | `oauth <Base64(JSON_cred)>` | C12815c OAuth2AuthenticatorInterceptor |
| 6 | URL `validationkey` | `&validationkey=<vk>` | AbstractC12813a.m51833d() |
| 7 | URL `responsetime` | `&responsetime=true` | SapiHandler.m52004k() |
