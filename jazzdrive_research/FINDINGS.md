# Jazz Drive 8.0.1 — Reverse Engineering Findings
> Decompiled 2026-06-11. Source:  in raddclub/raddflix-app.
> Base APK: 61 MB, 29,381 Java source files (jadx 1.5.1). Minor errors: 89 (non-blocking).

## 1. Server Configuration (from )

| Key | Value |
|-----|-------|
|  |  |
|  |  |
|  |  |
|  |  |
|  |  |
|  |  (client creds in POST body, NOT Basic header) |
|  |  |
|  |  |

**CRITICAL**: Token endpoint is  not . Both may work but  is canonical.

## 2. Network Security Config

- **No SSL pinning** — cleartext traffic allowed for 
- Subdomain:  is the main API host
- All SAPI calls go to 

## 3. Android App Credentials

From  (OAuth2ScreenController):
-  = 
-  =  (URL-decoded: )
- **auth_code exchange key format**: 

These credentials are used in the  call.

## 4. Authorization Header Scheme

The Android app uses **two separate auth mechanisms simultaneously**:

### A. validationkey (Query Parameter)
- Added to every SAPI request as a query string param: 
- Also sent as  response header in some cases (server-side rotation)
- Max URL length before query→body migration: 2048 bytes

### B. OAuth Bearer Token (Authorization Header)
From  (OAuth2AuthenticatorInterceptor):

- The  is Base64-encoded (NOT the Bearer OAuth2 standard)
- The  prefix is lowercase (not )
- Token is fetched from local storage via 

### C. JSESSIONID (Cookie)

- Set by server on first login, must be maintained across all requests
- 60-minute idle timeout (keep-alive required every ~15 min)

### D. X-deviceid Header


**NOTE**: Oracle  correctly sets Cookie, X-deviceid, X-Requested-With, User-Agent. It does NOT set  because Oracle stores the raw_accesstoken and can reconstruct it. This is correct for web-API use.

## 5. SAPI URL Builder ()

Every SAPI request URL is built as:

Note:  is always appended. Oracle's  does NOT include this.

## 6. Item Status Codes ()

| Server Status | Internal Code |
|---|---|
|  | 8 (Accepted/Processing) |
|  | 6 (Completed) |
|  | 5 (Invalid/Error) |
|  | 2 (Updated/Done) |
|  | 4 (Validating) |
| (empty) | 2 (default) |

## 7. SAPI Error Codes

| Code | Meaning |
|------|---------|
|  | Invalid/expired session |
|  | Session not found |
|  | ValidationKey rotated — new key in  |
|  | Authentication required |
|  | General media error |
|  | Media not found |
|  | Media already exists |
|  | Item not found (triggers ) |
|  | Quota exceeded |
|  | Invalid media type |
|  | File too large |
|  | Upload in progress (resume) |
|  | Upload already complete |
|  | Mandatory email not set |
|  | Terms and conditions not accepted |
|  | Profile error |
|  | Label error |
|  | Subscription error |

## 8. Media Item Model ()

Fields in scan responses ():

| JSON Field | Java Field | Type |
|---|---|---|
| uid=1000(runner) gid=1000(runner) groups=1000(runner) |  |  |
|  |  |  |
|  |  |  |
|  /  |  |  enum |
|  |  |  |
|  |  |  (epoch ms) |
|  |  |  (epoch ms) |
| Thu Jun 11 12:20:00 PM UTC 2026 | Thu Jun 11 12:20:00 PM UTC 2026 |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |

**MediaType enum values**: , ,  (document), 

## 9. Known Working Endpoints (from )

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET |  | List media (main scan endpoint) |
| GET |  | Get quota info |
| POST |  | Import item by ID |
| POST |  | Check item validation |
| POST |  | Save upload metadata |
| GET |  | Get media set (shared folder) |
| POST |  | Create media set |
| POST |  | Update media set permissions |
| POST |  | Find duplicate files |
| GET |  | Pic of the day |
| GET |  | Download thumbnail |
| POST |  | Login |
| GET |  | Mobile info |

## 10. Package Structure Summary

Key packages in :
-  — core HTTP layer (URL builder, binary upload)
-  — Retrofit interface, all media endpoints
-  — Auth interceptor (validationkey, login flow)
-  — OAuth2 interceptor (Authorization: oauth header)
-  — Room DB for pending upload queue
-  — Upload request/response models
-  — Full upload workflow (size check, quota, binary upload, metadata)
