---
name: Account suspension fixes — what caused them and what was fixed
description: Root causes of Jazz account suspensions and the specific fixes applied per session
---

## Root causes confirmed
1. Keepalive fake uploads → uploads to /dev/null to simulate activity — **REMOVED** (session 1)
2. Scanner using 10 threads with 0.05s BFS delay — too aggressive for Jazz's servers — **FIXED** (session 2)
3. SAPI backoff state resetting on Flask restart — fixed accounts would hammer API again — **FIXED** (session 2)
4. Session JSESSIONID expiring silently — nobody knew until uploads stopped — **FIXED** with Session Guardian (session 3)

## Fix details

### Session 2 — Scan Safety (commit 2296647)
- Scanner threads: 10 → 3 (configurable via settings)
- BFS delay: 0.05s → 0.8s (configurable via settings)
- SAPI backoff persisted to disk: sapi_backoff.json (survives Flask restarts)
- Scan Safety card added to settings.html
- /api/scan-safety and /api/log-retention endpoints added to routes/settings.py

### Session 3 — Session Guardian (commit aeca7bc)
- _session_guardian() added to self_heal.py _SCHEDULE at 2700s (45 min)
- Single read-only probe (get_storage_info) — zero suspension risk
- WA alert if session dead (max once/hr via session_guardian_last_alert setting)
- WA alert if <7 days until expiry (once/day)
- jd-stats route returns expires_in_days + token_expires_at
- upload.html shows expiry countdown: green >7d, amber 3-7d, red ≤2d
- Warning banner at ≤7d with "Paste cookies" link
- uploader.py 401 → WA alert max once/hr via upload_401_last_alert setting

## What uploading itself does NOT cause suspensions
- The uploader makes normal Jazz API calls from Oracle's datacenter IP
- Jazz expects uploads from various IPs — it's the rate/pattern that matters
- Upload account has been safe since session 1 when fake keepalive was removed
- The real risk now is session expiry going unnoticed, not upload behavior
