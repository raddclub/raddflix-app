
---
## Windows Client Research Results (2026-06-10)

### Source
84MB NSIS installer extracted to /tmp/jd_extracted (188 files, Qt5/Funambol SDK)
Binaries analyzed: Jazz Drive.exe, Jazz Drive-sync.exe, Qt5Network.dll, obhExt.dll

### Confirmed HTTP Headers (from binary strings)
| Header | Value | Status |
|---|---|---|
| X-deviceid | android-raddhub-{last10_msisdn} | existing ✅ |
| X-devicename | SM-A515F (Android model; Windows uses COMPUTERNAME) | **added** ✅ |
| X-request-id | uuid4().hex per-request | **added** ✅ |
| X-funambol-file-size | file size bytes (upload only) | **added** ✅ |
| X-funambol-id | uuid4().hex per-upload session | **added** ✅ |
| X-Requested-With | com.jazz.drive | existing ✅ |
| User-Agent | Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016) | existing ✅ (Android for zero-rating) |

### Multipart Boundary (Critical Fix)
- **Before:**  (custom, non-standard)
- **After:**  (Funambol SDK hardcoded value from Qt5Network.dll)

### Upload URL (Fix)
- **Before:** 
- **After:** 

### Full SAPI Endpoint Map (from Jazz Drive-sync.exe)


### OAuth2 Flow (from binary)
- Grant type: 
- OOB redirect: 
- Platform parameter:  (Win client) /  (Android client)
- client_id field:  (dynamic, not hardcoded in binary)
- Config keys: oauth2AccessToken, oauth2RefreshToken, oauth2ExpiresIn, oauth2ClientType

### Client Version
- Registry: 
- Client Version: 

### Files Changed
-  — get_auth_headers(): X-devicename + X-request-id
-  — boundary, lastupdate=true, X-funambol-* headers
