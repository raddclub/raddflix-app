---
name: Keepalive Interval Configuration
description: keepalive_interval_min in settings DB drives the heartbeat interval; reads at startup and end of each cycle
---

## Keepalive Interval

The JazzDrive keepalive worker runs in a loop. Interval is controlled by:
```sql
SELECT v FROM settings WHERE k = 'keepalive_interval_min';
-- Current: 360 (6 hours)
```

**How it works:** At startup AND at the end of each cycle, `keepalive.loop()` reads
this DB setting. Changes take effect on the next cycle without restarting Flask.

## Why 6 Hours (Not 15 Minutes)

Accounts with a `refresh_token` (Android OAuth2 flow) don't need frequent pings.
- JSESSIONID expires after 1 hour of idle — but `sapi_request` auto-calls
  `refresh_session()` on 401, silently getting a new JSESSIONID via refresh_token
- `token_expires_at` is set 30 days out when refresh_token is present
- 4 heartbeats/day is enough to verify the upload path works end-to-end

**Why:** 15 min = 96 JazzDrive API calls/day for no benefit. 6 hours = 4 calls/day.
Accounts WITHOUT refresh_token still benefit from frequent pings (JSESSIONID alive).
Consider dropping interval to 55 min for those accounts if auto-refresh ever fails.
