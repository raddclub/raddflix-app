# Anti-Suspension Implementation — Real Device Identity Patch

  > **Date:** 2026-06-10
  > **Trigger:** My Devices screenshot showing real registered devices

  ## Real Device IDs Found

  From cloud.jazzdrive.com.pk/profile → My Devices:

  | Icon | Device Name | Last Activity |
  |---|---|---|
  | Windows | `DESKTOP-F4QOSS2` | Today |
  | Android | `InfinixInfinix X680F` | Today |

  **Key insight:** Android device name format is `{manufacturer}{model}` = `Infinix` + `Infinix X680F` → `InfinixInfinix X680F`

  ---

  ## All Changes Applied (2026-06-10)

  ### 1. `hub/db.py` — New account columns

  Migration added two new columns to the `accounts` table:

  ```python
  "ALTER TABLE accounts ADD COLUMN device_id TEXT",
  "ALTER TABLE accounts ADD COLUMN device_name TEXT",
  ```

  Allows storing the real device ID and name per Jazz account.

  ---

  ### 2. `hub/jazzdrive.py` — Real device identity

  #### `get_x_deviceid()` — uses stored real device ID

  ```python
  # Priority order:
  # 1. accounts.device_id   ← set via admin API or extracted from real APK session
  # 2. Deterministic fallback: android-{last10_msisdn}
  ```

  #### `get_x_devicename()` — NEW function

  ```python
  # Priority order:
  # 1. accounts.device_name  ← default: InfinixInfinix X680F (from My Devices screenshot)
  # 2. JAZZDRIVE_DEVICE_NAME setting
  # 3. Hardcoded default: "InfinixInfinix X680F"
  ```

  #### `get_auth_headers()` — Infinix X680F User-Agent

  ```python
  "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 12; Infinix X680F Build/SP1A.210812.016)",
  "X-devicename": get_x_devicename(msisdn, account_id=account_id),
  "X-deviceid":   get_x_deviceid(msisdn, account_id=account_id),
  ```

  Before → After:
  | Header | Before | After |
  |---|---|---|
  | `User-Agent` | `SM-A515F` | `Infinix X680F` |
  | `X-devicename` | `SM-A515F` | `InfinixInfinix X680F` |
  | `X-deviceid` | `android-raddhub-{msisdn}` | stored real ID or `android-{msisdn}` |

  #### `startup_handshake()` — NEW function

  Mimics the exact startup sequence of the official JazzDrive app:

  ```
  1. GET /sapi/features                              (feature flags)
  2. GET /sapi/profile?action=get                    (user profile)
  3. GET /sapi/subscription?action=get               (active plan)
  4. GET /sapi/media?action=get-storage-space        (quota)
  ```

  Called in background thread on every upload session start. Makes RaddHub
  look identical to the official app to Jazz servers.

  #### `post_upload_validate()` — NEW function

  Polls `/sapi/media?action=get-validation-status` after each upload
  (confirmed from Jazz Drive Windows binary strings):

  ```
  "Starting upload status validation..."
  "Upload status validation completed: no more items to validate"
  ```

  Polls up to 8 times with 3-second intervals + random jitter. Runs in
  background thread — does not block the next upload.

  ---

  ### 3. `hub/uploader.py` — Upload URL + validation

  #### Upload URL now includes media type

  ```
  BEFORE: /sapi/upload?action=save&lastupdate=true&...
  AFTER:  /sapi/upload/video?action=save&lastupdate=true&...
  ```

  MIME → SAPI type mapping:
  - `video/*` → `video`
  - `audio/*` → `audio`
  - `image/*` → `picture`
  - other → `file`

  #### Validation polling wired after upload

  ```python
  # After upload OK:
  threading.Thread(target=lambda: jazzdrive.post_upload_validate(vk, jsid, ...),
                   daemon=True, name="jd-validate").start()
  ```

  #### Startup handshake wired before upload

  ```python
  # After session verified, before first upload attempt:
  threading.Thread(target=lambda: jazzdrive.startup_handshake(vk, jsid, ...),
                   daemon=True, name="jd-handshake").start()
  ```

  ---

  ### 4. `radd_hub.py` — Admin API endpoints

  #### `GET /api/admin/jazzdrive/device`
  List all accounts with their device_id and device_name.

  #### `POST /api/admin/jazzdrive/device`
  Set device_id and/or device_name per account.

  ```json
  {
    "account_id": 1,
    "device_id": "android-abc1234567",
    "device_name": "InfinixInfinix X680F"
  }
  ```

  #### `POST /api/admin/jazzdrive/startup-handshake`
  Trigger the startup handshake manually for testing/verification.

  ---

  ## Complete Anti-Suspension Header Profile

  Every request from RaddHub now sends:

  ```
  User-Agent:       Dalvik/2.1.0 (Linux; U; Android 12; Infinix X680F Build/SP1A.210812.016)
  X-deviceid:       android-{last10_msisdn}  [or stored real ID]
  X-devicename:     InfinixInfinix X680F     [real registered device name]
  X-Requested-With: com.jazz.drive
  X-request-id:     {uuid4 per request}
  X-funambol-file-size: {bytes}
  X-funambol-id:    {uuid4 per upload}
  Content-Type:     multipart/form-data; boundary=dboundary_.oOo._
  Cookie:           JSESSIONID={jid}
  validation_key:   {vk}
  ```

  ---

  ## How to Set the Real Android Device ID

  If you want RaddHub to use the EXACT same device ID as your Infinix X680F
  (so it appears as the same device on Jazz servers, not a new third device):

  1. Extract the `X-deviceid` value from the real Jazz Drive app on your phone
     (capture network traffic or check app storage on rooted device)
  2. POST it to: `/api/admin/jazzdrive/device`
     ```json
     {"account_id": 1, "device_id": "YOUR_REAL_ANDROID_DEVICE_ID", "device_name": "InfinixInfinix X680F"}
     ```

  Until then, RaddHub uses `android-{last10_msisdn}` which appears as a
  separate "new device" on Jazz servers — safe, but visible as a 3rd device.
  