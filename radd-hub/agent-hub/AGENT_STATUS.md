# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-06

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | `raddflix_radd` via supervisorctl, port 5000 |
| Flutter app | ✅ STABLE | All 8 critical bugs fixed (see BUG_TRACKER.md) |
| WARP Tunnel | ✅ ACTIVE | Split tunnel — only Jazz IPs via WARP (Cloudflare PK edge) |
| JazzDrive Upload | ✅ WORKING | PROXY_BYPASS=1 — direct via WARP, no proxy layer needed |
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

## WARP Tunnel Architecture (added 2026-06-06)

Jazz IPs route through Cloudflare WARP (PK edge). All other traffic is direct.
`JAZZDRIVE_PROXY_BYPASS=1` in DB — Flask skips proxy logic entirely.

| Traffic type | Route |
|---|---|
| Jazz API (3 IPs) | wg0 → WARP → Cloudflare PK edge → JazzDrive |
| Uploads to Oracle | Direct internet (full speed, unaffected) |
| Admin panel | Direct internet |
| Flutter app calls | Direct internet |

**Jazz IP Watchdog** runs every 10 min. Accumulate mode — never removes IPs.
If Jazz adds a new IP, watchdog picks it up from DNS and adds to WireGuard.

---

## What's Been Done (2026-06-06)

### Infrastructure Overhaul
- **WARP split tunnel**: `/etc/wireguard/wg0.conf` — only 3 Jazz IPs via WARP
- **Jazz IP Watchdog v4**: accumulate mode, never removes IPs, every 10 min
- **Proxy pool disabled**: 33,068 proxies deleted, background threads off (`PROXY_BYPASS=1`)
- **Keepalive**: 15 min hardcoded → 360 min DB-driven; reads DB at startup + each cycle
- **Account 03286829827**: OTP login restored, tokens valid 30 days

### Previously (2026-06-05)
- **Proxy Pool God-Level** (150+ PK seeds, weighted rotation, circuit breaker, 8-source discovery)
- **OTP Proxy Hardening** (commit 1887b63 — 6 bugs across trigger/resend/verify)
- **OTP retry chain + dual-domain HC** (commit aa7e280)
- **Settings UI** — god-level proxy management panel

---

## Active Open Items

| ID | Priority | Description |
|----|---------|-------------|
| DATA-01 | MEDIUM | *All Of Us Are Dead* — E03/E04/E05/E09 not in Oracle DB. Need JazzDrive upload + sync. |

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
