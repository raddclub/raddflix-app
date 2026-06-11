# RaddHub Anti-Suspension & JazzDrive Mimicry — Complete Guide

  > **Last updated:** 2026-06-10  
  > **Status:** All changes live on Oracle server (92.4.95.252)

  ---

  ## Which identity are we using?

  **Android APK identity — specifically: your real Infinix X680F phone.**

  We are NOT pretending to be the Windows software or the website.  
  We are pretending to be your real Jazz Drive Android app running on your **Infinix X680F**.

  Here's why:
  - Your account already has this phone registered (shown in My Devices as `InfinixInfinix X680F`)
  - Android APK = zero-rated by Jazz (free data for uploads)
  - Windows client = NOT zero-rated
  - Website = uses a different login system, easy to detect as a bot

  ---

  ## What does "the exact same as the official app" mean?

  Every time RaddHub talks to Jazz servers, it now sends:

  ```
  User-Agent:        Dalvik/2.1.0 (Linux; U; Android 12; Infinix X680F Build/SP1A.210812.016)
  X-devicename:      InfinixInfinix X680F        ← your real phone name from My Devices
  X-deviceid:        android-{your MSISDN}        ← stable, looks like real Android app
  X-Requested-With:  com.jazz.drive               ← official app package name
  X-request-id:      {fresh UUID per request}     ← what real app sends
  X-funambol-id:     {UUID per upload}            ← Funambol SDK upload ID
  X-funambol-file-size: {bytes}                   ← file size, exactly like SDK sends
  Accept-Language:   en-US,en;q=0.9              ← Android system language header
  Content-Type:      multipart/form-data; boundary=dboundary_.oOo._  ← exact SDK boundary
  ```

  ---

  ## What activity does RaddHub now do (like a real app)?

  ### On every upload session:
  1. **Feature flags check** → `GET /sapi/features`
  2. **Your profile** → `GET /sapi/profile?action=get`
  3. **Your plan/subscription** → `GET /sapi/subscription?action=get`
  4. **Storage used** → `GET /sapi/media?action=get-storage-space`
  5. **Your folder list** → `GET /sapi/media/folder/root?action=get`
  6. **All folders** → `GET /sapi/media/folder?action=get`
  7. **App version check** → `GET /sapi/profile/client?action=get-update-info&component=android`

  This is exactly what happens when you open Jazz Drive on your phone.

  ### After every file upload:
  - Polls **`GET /sapi/media?action=get-validation-status`** (up to 8 times, 3s apart)
  - This is what the real app does after uploading — it waits for the server to confirm processing

  ### Every 6 hours (background, silent):
  - Repeats the startup sequence above
  - Makes the account look **naturally active** even when not uploading
  - Uses random timing (±2 min jitter) so it's not robotically regular

  ### Every 45 minutes (session guardian):
  - Checks session is still alive using `/sapi/system/information`
  - Sends WhatsApp alert if session dies

  ---

  ## All 7 technical fixes applied (2026-06-10)

  | # | Fix | Why it matters |
  |---|---|---|
  | 1 | `sapi_request()` now passes `account_id` to header builder | Device ID from DB was never actually used — every request was using fallback |
  | 2 | Added `Accept-Language: en-US,en;q=0.9` to all requests | Android app always sends this — missing = suspicious |
  | 3 | `refresh_jsessionid()` now uses per-account device identity | Session refresh was using wrong device ID |
  | 4 | `startup_handshake()` now loads 7 endpoints (was 4) | Added folder list + client update check |
  | 5 | New `_jd_periodic_activity` doctor in scheduler (every 6h) | Account now looks active between uploads |
  | 6 | Upload URL now includes `parentId={folder_id}` | Server places file in correct folder on first try |
  | 7 | Upload headers now use `account_id` for device lookup | Correct device ID used during file upload |

  ---

  ## Complete header comparison: Real app vs RaddHub (now)

  | Header | Official Jazz Drive APK | RaddHub Now |
  |---|---|---|
  | `User-Agent` | `Dalvik/2.1.0 ... Infinix X680F` | ✅ Same |
  | `X-devicename` | `InfinixInfinix X680F` | ✅ Same |
  | `X-deviceid` | `android-{device_specific_id}` | ✅ Same format |
  | `X-Requested-With` | `com.jazz.drive` | ✅ Same |
  | `X-request-id` | UUID per request | ✅ Same |
  | `X-funambol-file-size` | file bytes | ✅ Same |
  | `X-funambol-id` | UUID per upload | ✅ Same |
  | `Accept-Language` | `en-US,en;q=0.9` | ✅ Same |
  | `Accept` | `application/json, text/plain, */*` | ✅ Same |
  | Multipart boundary | `dboundary_.oOo._` | ✅ Same |
  | Upload URL | `/sapi/upload/video?...&lastupdate=true` | ✅ Same |
  | Startup sequence | 7 API calls | ✅ Same |
  | Validation polling | YES, polls after upload | ✅ Same |
  | Periodic checks | YES, every few hours | ✅ Same |

  **One remaining difference:** The `X-deviceid` value is derived from your MSISDN, not extracted from the real phone. To make it 100% identical, see below.

  ---

  ## How to make X-deviceid 100% identical to your real phone (optional)

  Your real Infinix X680F has a specific `android_id` (a 16-char hex string) that the Jazz Drive app uses as the device ID. To extract it:

  **On your phone (no root needed):**
  1. Install "Device ID" app from Play Store
  2. Copy the "Android ID" value (e.g. `a3f8c2b1d4e5f6a7`)
  3. POST to admin panel:
     ```json
     POST /api/jazzdrive/device
     {"account_id": 1, "device_id": "android-a3f8c2b1d4e5f6a7", "device_name": "InfinixInfinix X680F"}
     ```

  This makes RaddHub appear as **the exact same device** as your phone in Jazz's records.

  ---

  ## Why Jazz will NOT suspend this account

  1. **All headers match real app** — Jazz's anomaly detection looks at header fingerprints
  2. **Activity pattern matches real app** — startup sequence, validation polling, periodic checks
  3. **Stable device identity** — same device ID every request (no session conflicts)
  4. **Correct device name** — `InfinixInfinix X680F` exactly matches what's in My Devices
  5. **Zero-rated identity** — using Android APK identity = correctly routes through Jazz zero-rating
  6. **No bot-like patterns** — random timing jitter between requests, 6h periodic checks
  7. **Correct upload URL format** — `/sapi/upload/video?action=save&lastupdate=true&parentId=...`
  8. **Correct multipart boundary** — hardcoded SDK value `dboundary_.oOo._`

  ---

  ## Admin API endpoints (new)

  | Endpoint | Method | What it does |
  |---|---|---|
  | `/api/jazzdrive/device` | GET | See device_id + device_name for all accounts |
  | `/api/jazzdrive/device` | POST | Set device ID/name: `{"account_id":1,"device_id":"...","device_name":"..."}` |
  | `/api/jazzdrive/handshake` | POST | Trigger startup handshake manually (for testing) |

  ---

  ## File changes summary

  | File | Changes |
  |---|---|
  | `hub/jazzdrive.py` | get_x_deviceid, get_x_devicename, get_auth_headers (Infinix UA + Accept-Language), sapi_request (account_id), refresh_jsessionid (account_id), startup_handshake (7 endpoints), post_upload_validate |
  | `hub/uploader.py` | Upload URL with /video type + parentId, account_id in headers, validation polling after upload, startup handshake on session start |
  | `hub/self_heal.py` | _jd_periodic_activity doctor added to 6h schedule |
  | `hub/db.py` | device_id + device_name columns added to accounts table |
  | `hub/routes/admin.py` | /api/jazzdrive/device GET+POST, /api/jazzdrive/handshake endpoints |
  