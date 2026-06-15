# JazzDrive Authentication Flow
## Jazz Drive 8.0.1 APK — Confirmed via full decompile (29,381 Java files)
## Updated: June 2026

---

## Android OAuth2 Credentials (AES-CBC decrypted from ec/C24226a.java)
| Field | Value | Source |
|---|---|---|
| client_id | `fnbroot` | AES-CBC decrypt of C24226a.f62869b |
| client_secret | `f&rW23` | AES-CBC decrypt of C24226a.f62871d |
| OAuth2 token URL | `https://jazzdrive.com.pk/oauth2/token.php` | strings.xml `oauth2_access_token_uri` |
| OAuth2 authorize URL | `https://jazzdrive.com.pk/oauth2/authorization.php` | strings.xml `oauth2_auth_token_uri` |
| OAuth2 redirect URI | `https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html` | strings.xml `oauth2_redirect_uri` |
| MobileConnect WebView URL | `https://cloud.jazzdrive.com.pk/ui/html/mobileconnect.html?embedded=true#start` | strings.xml `mobile_connect_login_url` |
| MobileConnect redirect | `/ui/html/clientoauth.html` | strings.xml `mobile_connect_redirect_url` |
| SAPI server | `https://cloud.jazzdrive.com.pk` | strings.xml `app_server_host` + `app_server_scheme` |

---

## Authorization Header Format (CRITICAL — from nk/c.java OAuth2Credentials.d())

**ALL authenticated SAPI requests** use this header:
```
Authorization: oauth <Base64(JSON)>
```
where JSON is:
```json
{"data":{"accesstoken":"<raw_at>","refreshtoken":"<rt>","platform":"android","expiresin":"<secs>","lastrefreshdate":<unix_ms>,"msisdn":"<msisdn>"}}
```

**NOT** `Authorization: oauth <Base64(raw_token)>` — the full JSON wrapper is required.

## validationkey (URL parameter, not header)
- Added as URL query param `&validationkey=<vk>` to all SAPI requests
- Skipped for `/sapi/login`, `/sapi/mobile?action=signup`, `/sapi/download/thumbnail`
- Updated from EVERY SAPI response body (`data.validationkey`) by AbstractC12813a.m51847w()
- On SEC-1003 response: `{"error":{"code":"SEC-1003","data":"<new_vk>"}}` → update VK + retry

---

## Login Paths

### Path A: OAuth2 WebView (Standard Login)
```
1. GET https://jazzdrive.com.pk/oauth2/authorization.php
     ?response_type=code&client_id=fnbroot
     &redirect_uri=<encoded_redirect>&access_type=offline&scope=&state=<random>
2. User authenticates in WebView (username+password)
3. WebView intercepts redirect to clientoauth.html?code=<CODE>&state=<state>
4. POST https://jazzdrive.com.pk/oauth2/token.php
   Body: grant_type=authorization_code&code=<CODE>
         &redirect_uri=<redirect_uri>&client_id=fnbroot&client_secret=f%26rW23
   [oauth2_authentication_in_body=true → credentials in body, NOT Basic Auth]
5. Response: {"access_token":"<at>","refresh_token":"<rt>","expires_in":"<secs>"}
6. GET /sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key=<b64_at>
   → {"data":{"validationkey":"<vk>","jsessionid":"..."}}
```

### Path B: MobileConnect (Jazz SIM — Zero-Rated)
```
1. Open WebView to: https://cloud.jazzdrive.com.pk/ui/html/mobileconnect.html?embedded=true#start
2. Jazz network injects MSISDN header; server sends SMS OTP
3. User enters OTP in WebView; WebView JS returns code+state to app
4. POST /sapi/credential/mobileconnect?action=validate&responsetime=true
   Authorization: oauth <Base64(cred_json)>
   Body: {"data": {"code": "<code>", "state": "<state>"}}
5. Response: {"data": {"access_token":"<at>","refresh_token":"<rt>",
              "msisdn":"92XXXXXXXXXX","expires_in":"<secs>","lastrefreshdate":<ms>}}
```
**NOTE**: `keytype=otp` does NOT exist in the Jazz Drive 8.0.1 APK. There is no headless API
to submit a raw SMS OTP. The OTP is handled inside the MobileConnect WebView.

### Path C: Token Refresh (Long-Lived)
```
POST https://jazzdrive.com.pk/oauth2/token.php
Body: grant_type=refresh_token&refresh_token=<rt>
      &client_id=fnbroot&client_secret=f%26rW23
Response: {"access_token":"<new_at>","refresh_token":"<new_rt>","expires_in":"<secs>"}
```
JazzDrive rotates the refresh_token on every exchange.

---

## Token Lifecycle
| Token | Lifetime | Stored In | Used For |
|---|---|---|---|
| `access_token` (raw hex) | ~1h | DB `raw_accesstoken` | `Authorization: oauth <b64(json)>` header |
| `refresh_token` | ~90 days (rotates) | DB `refresh_token` | Exchange for new access_token |
| `validationkey` | session | DB `validation_key` | URL param `&validationkey=<vk>` on all SAPI calls |
| `jsessionid` | session (~8h) | DB `jsessionid` | Cookie `JSESSIONID=<jid>` |

---

## Oracle RaddHub Status
- ✅ `CLOUD_BASE = "https://cloud.jazzdrive.com.pk"` correct
- ✅ `ANDROID_CLIENT_ID = "fnbroot"` correct
- ✅ `ANDROID_CLIENT_SECRET = "f&rW23"` correct  
- ✅ `Authorization: oauth <Base64(JSON_cred)>` header format **now fixed** (was raw token b64)
- ✅ `validationkey` added as URL query param on SAPI requests
- ✅ `keytype=otp` candidates removed (were sending to non-existent endpoint)
- ✅ MobileConnect validate (`/sapi/credential/mobileconnect?action=validate`) now used
- ✅ `android_refresh_session` now uses `token.php` (APK-correct) instead of `refresh_token.php`
