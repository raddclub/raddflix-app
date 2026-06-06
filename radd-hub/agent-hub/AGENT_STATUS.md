# AGENT_STATUS.md
  > Current project status for agent coordination.
  > Last updated: 2026-06-06 (Session 2)

  ---

  ## Overall Health

  | Area | Status | Notes |
  |------|--------|-------|
  | App (Oracle) | ✅ RUNNING | `raddflix_radd` via supervisorctl, port 5000 |
  | Flutter app | ✅ STABLE | All 8 critical bugs fixed (see BUG_TRACKER.md) |
  | WARP Tunnel | ✅ ACTIVE | Split tunnel — only Jazz IPs via WARP (Cloudflare PK edge) |
  | JazzDrive Session | ✅ FRESH | vk=32 chars, jid=38 chars, expires ~2026-07-06 |
  | JazzDrive Upload | ✅ WORKING | PROXY_BYPASS=1 — direct via WARP, no proxy layer needed |
  | delta_push | ✅ WORKING | Catalog JSON live on JazzDrive, folder_id=1763725 |
  | All 10 files | ✅ is_ready=1 | remote_id + share_url set for all |
  | XOR Encoding | ✅ FIXED | Padding fix in request_encoder.dart (never remove) |
  | WhatsApp Bot | ⬜ STOPPED | autostart=false |
  | Server CPU | ✅ 6.9% | Was 60.7% before proxy pool cleanup |
  | Server RAM | ✅ 61 MB | Was 6,148 MB before proxy pool cleanup |

  ---

  ## Oracle Server Quick Reference

  ```
  IP:        92.4.95.252
  SSH:       ubuntu@92.4.95.252 (key from ORACLE_SSH_KEY secret)
  App path:  /opt/jazzmax/radd-hub/
  Service:   sudo supervisorctl restart raddflix_radd
  Real log:  /opt/jazzmax/radd-hub/data/logs/raddhub.log
  Health:    curl -s http://localhost:5000/healthz

  WARP:      sudo wg show wg0
  Watchdog:  sudo python3 /opt/warp-watchdog/jazz_ip_watchdog.py
  Jazz IPs:  /opt/warp-watchdog/known_jazz_ips.json
  ```

  ---

  ## WARP Tunnel Architecture

  Jazz IPs route through Cloudflare WARP (PK edge). All other traffic is direct.
  `JAZZDRIVE_PROXY_BYPASS=1` in DB — Flask skips proxy logic entirely.

  | Traffic type | Route |
  |---|---|
  | Jazz API (3 IPs) | wg0 → WARP → Cloudflare PK edge → JazzDrive |
  | Uploads to Oracle | Direct internet (full speed, unaffected) |
  | Admin panel | Direct internet |
  | Flutter app calls | Direct internet |

  **Jazz IP Watchdog** runs every 10 min. Accumulate mode — never removes IPs.

  ---

  ## JazzDrive Session (CRITICAL — read before any upload/delta work)

  Account 15 (03286829827) — role: flix
  - **validation_key** (vk, 32 chars) + **JSESSIONID** (38 chars) BOTH required for all SAPI calls
  - JSESSIONID alone → HTTP 401 (confirmed)
  - Get fresh session: `refresh_session(account_id=15)` in Python — needs valid refresh_token
  - Current refresh_token expires ~2026-07-06
  - If refresh_token shows `invalid_grant`: do OTP login from Settings page once
  - See `.agents/memory/jazzdrive-session-vk.md` for full detail

  ### delta_push quick fix reference
  | Symptom | Fix |
  |---------|-----|
  | "No active JazzDrive session" | Run `refresh_session(account_id=15)` |
  | MED-1030 Folder not found | `DELETE FROM settings WHERE k IN ('jd_delta_folder_id','jd_delta_file_id')` |
  | _time_time crash | Already fixed — `sed -i 's/_time_time()/time.time()/g'` applied |

  ---

  ## What's Been Done

  ### Session 2 (2026-06-06)
  - **jazzdrive.py bug fix**: 4x `_time_time()` → `time.time()` (crashed refresh_session)
  - **Session refresh**: account 15 now has vk + fresh jid via `refresh_session()`
  - **delta_push fixed**: stale folder cleared, catalog JSON live on JazzDrive
  - **3 stuck files uploaded**: Pitt Siyapa, Luka Chuppi, Vncenz0 S01E02 — all is_ready=1
  - **All 10 files**: is_ready=1 with remote_id and share_url

  ### Session 1 (2026-06-06)
  - **WARP split tunnel**: `/etc/wireguard/wg0.conf` — only 3 Jazz IPs via WARP
  - **Jazz IP Watchdog v4**: accumulate mode, never removes IPs, every 10 min
  - **Proxy pool disabled**: 33,068 proxies deleted, background threads off (`PROXY_BYPASS=1`)
  - **Keepalive**: 15 min hardcoded → 360 min DB-driven
  - **Account 03286829827**: OTP login restored, tokens valid 30 days

  ### Previously (2026-06-05)
  - **Proxy Pool God-Level** (150+ PK seeds, weighted rotation, circuit breaker, 8-source discovery)
  - **OTP Proxy Hardening** + retry chain + dual-domain HC
  - **Settings UI** — god-level proxy management panel

  ---

  ## Active Open Items

  | ID | Priority | Description |
  |----|---------|-------------|
  | DATA-01 | MEDIUM | *All Of Us Are Dead* — E03/E04/E05/E09 not in Oracle DB. Need JazzDrive upload + sync. |
  | SOURCE-01 | HIGH | Uploaded files are ~10-second clips — user must verify their download source delivers full content. |

  ---

  ## Critical Rules (quick reference)

  1. Never use git shell — GitHub Contents API only
  2. `sqflite_sqlcipher` pinned at `3.1.0+1` — NEVER upgrade
  3. XOR padding fix must always be in `request_encoder.dart`
  4. Never use `androidAttachSurfaceAfterVideoParameters: true`
  5. Always append to `agent-hub/history/TASK_LOG.md` after session
  6. Oracle deploy path: `/opt/jazzmax/radd-hub/`
  7. WARP manages Jazz routing — `JAZZDRIVE_PROXY_BYPASS=1` must stay set
  8. Keepalive interval: `keepalive_interval_min` in settings DB (currently 360 min)
  9. Jazz IP watchdog: `/opt/warp-watchdog/jazz_ip_watchdog.py` — accumulate mode
  10. JazzDrive needs vk+jid both — `refresh_session(account_id=15)` to renew
  