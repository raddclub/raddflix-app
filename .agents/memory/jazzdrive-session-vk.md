---
  name: JazzDrive session validation_key
  description: validation_key is required for all SAPI calls; how to get it, what breaks without it, and fixes applied 2026-06-06.
  ---

  ## The rule
  Every JazzDrive SAPI call requires **both** `validation_key` (32-char hex) AND `JSESSIONID` (38-char). JSESSIONID alone returns HTTP 401. The code guards at `if not vk or not jid: return error` in `upload_json_to_jazzdrive` and `upload_to_jazzdrive`.

  **Why:** Confirmed live — curl with Cookie: JSESSIONID only → 401. With both → 200.

  ## How accounts get validation_key
  - **OTP login** (`submit_otp`): tries to save vk from response; if the login endpoint doesn't return one (Android-style OTP), vk stays empty.
  - **`refresh_session(account_id=N)`**: tries Android OAuth2 refresh_token → SAPI re-login. If refresh_token is valid, SAPI re-login returns vk + new JSESSIONID and saves both to DB. **This is the correct way to recover vk.**
  - `cloud.jazzdrive.com.pk` is hosted on AWS (54.254.59.168) — not geo-blocked. WARP is irrelevant for API access.

  ## _time_time bug (fixed 2026-06-06)
  `jazzdrive.py` had 4 occurrences of `_time_time()` (undefined) at lines 771, 781, 1605, 1926. Should be `time.time()`. Caused `refresh_session()` to crash before it could rotate tokens. Fixed with:
  ```bash
  sed -i 's/_time_time()/time.time()/g' /opt/jazzmax/radd-hub/hub/jazzdrive.py
  ```

  ## Token rotation danger
  `android_refresh_session` does early-persist of the rotated refresh_token BEFORE the SAPI re-login step. If SAPI step fails, the old refresh_token is gone. After the `_time_time` fix, refresh now works cleanly. If you see `invalid_grant` from refresh_token.php, the token was burned by a previous partial run — do OTP login again.

  ## delta_push MED-1030 (Folder not found)
  `jd_delta_folder_id` in the settings table is cached. If the JazzDrive folder is deleted, subsequent delta uploads fail with MED-1030. Fix:
  ```sql
  DELETE FROM settings WHERE k IN ('jd_delta_folder_id', 'jd_delta_file_id');
  ```
  Then call `run_full_pipeline()` from `hub.routes.delta_push` — it recreates the folder automatically.

  ## Re-uploading stuck files from Python
  `queue_manual_upload()` uses `daemon=True` threads — killed if Python process exits before upload completes. For reliable re-upload from a script:
  ```python
  from hub.uploader import upload_to_jazzdrive
  from pathlib import Path
  result = upload_to_jazzdrive(Path('/path/to/file.mp4'), account_id=15, auto_delete=False)
  ```
  Must first delete any stale `files` table entries for the same filename, otherwise the anti-double-upload guard will skip it.

  ## Current state (2026-06-06)
  - Account 15 (03286829827): vk=32 chars, jid=38 chars, expires ~2026-07-06
  - All 10 files in `files` table: is_ready=1, remote_id set, share_url set
  - delta_push: working, new share_url set, folder_id=1763725
  - refresh_token: rotated and stored; next refresh should work cleanly
  