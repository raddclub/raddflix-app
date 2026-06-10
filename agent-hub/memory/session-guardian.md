---
name: Session Guardian
description: The 45-min background doctor that monitors JazzDrive session health and sends WA alerts
---

## What it does
Added to hub/self_heal.py in the _SCHEDULE list at 2700s (45 min) interval.

Every 45 minutes:
1. Makes ONE lightweight GET call (get_storage_info) — read-only, zero suspension risk
2. If session dead → WA alert immediately (max once per hour via `session_guardian_last_alert` DB setting)
3. If alive but <7 days until expiry:
   - ≤2 days: 🔴 urgent WA alert (once/day via `session_guardian_expiry_alert_{account_id}` setting)
   - 3-7 days: 🟡 warning WA alert (once/day)
4. Alert includes account MSISDN + instructions to paste cookies

## How to re-paste cookies (user instructions)
1. Open cloud.jazzdrive.com.pk on Jazz phone browser
2. Log in → DevTools → copy cookies JSON
3. Open admin panel → Upload tab → Paste Cookies
4. Session resets for ~30 more days

## Related UI (upload.html)
- Session badge shows "expires in N days"
- Green = >7 days, amber = 3-7 days, red = ≤2 days
- Warning banner appears at ≤7 days with inline "Paste cookies" link

## Related 401 handling (uploader.py)
- HTTP 401 from JD during upload → WA alert sent (max once/hr via `upload_401_last_alert` setting)
- Message: session expired, open admin panel, paste cookies
- Then raises RuntimeError — upload queue pauses naturally

## Settings keys used
- session_guardian_last_alert — throttle dead-session alerts (1/hr)
- session_guardian_expiry_alert_{account_id} — throttle expiry alerts (1/day)
- upload_401_last_alert — throttle 401 mid-upload alerts (1/hr)
