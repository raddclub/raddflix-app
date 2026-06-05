# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-05

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | `raddflix_radd` via supervisorctl, port 5000 |
| Flutter app | ✅ STABLE | All 8 critical bugs fixed (see BUG_TRACKER.md) |
| SAPI Proxy Pool | ✅ GOD-LEVEL | 150+ PK seeds, weighted rotation, circuit breaker |
| JazzDrive Upload | ✅ WORKING | Proxy-chain retry, speed/ETA/proxy displayed in UI |
| XOR Encoding | ✅ FIXED | Padding fix in request_encoder.dart (never remove) |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |

---

## Oracle Server Quick Reference

```
IP:        92.4.95.252
SSH:       ubuntu@92.4.95.252 (key from ORACLE_SSH_KEY secret)
App path:  /opt/jazzmax/radd-hub/
Service:   sudo supervisorctl restart raddflix_radd
Logs:      sudo tail -f /var/log/raddflix_radd.out.log
           sudo tail -f /var/log/raddflix_radd.err.log
Health:    curl -s http://localhost:5000/healthz
```

---

## What's Been Done (2026-06-05)

### Proxy Pool — God-Level Upgrade
- **150+ Pakistani proxy seeds** across 6 ASNs (PTCL, StormFiber, Nayatel, Wateen, WorldCall, Micronet)
- **Weighted scoring rotation** — fast+reliable proxies serve first
- **CircuitBreaker class** — >80% dead → auto-fallback to direct, upload never breaks
- **Fast recovery thread** — re-tests disabled proxies every 5 min
- **`get_proxy_chain(n=3)`** — ordered retry list for upload loops
- **8-source auto-discovery** (was 5): added pubproxy.com, proxy-list.download, geonode page 2
- **Bulk import** — paste 100+ proxy URLs at once via UI
- **Per-proxy SAPI test** — live test button per row in panel
- **Reset Dead** — bulk re-enable all disabled proxies
- **Export** — download full proxy list as .txt
- **God-level UI panel** — stat cards, filter bar, sortable table, score column, ping bars, 10s refresh

### Settings Page
- Old inline proxy section → `{% include "_proxy_pool_panel.html" %}` (god-level panel)
- 5 new API endpoints: `/pool/stats`, `/pool/bulk-import`, `/pool/test/<id>`, `/pool/reset-dead`, `/pool/export`

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
7. Pull + restart: `git pull origin main && supervisorctl restart raddflix_radd`
8. Two proxy paths: `resolve_proxies(purpose='sapi')` (pool) vs `purpose='otp'` (old single-proxy)
