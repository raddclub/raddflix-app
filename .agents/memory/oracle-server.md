---
name: Oracle Server Location
description: Production server path, supervisor name, git remote, deploy process, WARP tunnel, and Jazz IP watchdog
---

## Production server
- Path: `/opt/jazzmax/` (NOT `/home/ubuntu/jazzmax/`)
- Git remote: `github.com/raddclub/raddflix-app` (same repo as Flutter app — monorepo)
- Supervisor service name: `raddflix_radd`
- Python server: `/opt/jazzmax/radd-hub/radd_hub.py run --skip-setup`
- Port: 5000 (behind nginx/proxy on 80)

## Key server files
- Mobile API routes: `/opt/jazzmax/radd-hub/hub/routes/mobile_api.py`
- Catalog API routes: `/opt/jazzmax/radd-hub/hub/routes/catalog_api.py`
- XOR encoding middleware: `/opt/jazzmax/radd-hub/hub/routes/request_encoding.py`
- App factory (blueprint registration): `/opt/jazzmax/radd-hub/hub/app.py`
- Proxy pool: `/opt/jazzmax/radd-hub/hub/proxy_pool.py`
- Keepalive worker: `/opt/jazzmax/radd-hub/hub/keepalive.py`

## Deploy process
1. Push to GitHub from Replit or Oracle
2. On Oracle: `cd /opt/jazzmax && git pull && sudo supervisorctl restart raddflix_radd`
3. Script: `bash push_to_oracle.sh` (from Replit workspace)
4. GitHub Actions auto-builds APK on every push touching `raddflix_flutter/**`

**Why:** The /home/ubuntu/jazzmax/ path is a dev scratch copy; /opt/jazzmax/ is what supervisord runs.

---

## Cloudflare WARP Split Tunnel (added 2026-06-06)

Oracle's IP is not Pakistani — JazzDrive returns MED-1011 geo-block without Jazz SIM IP.
Solution: Cloudflare WARP via WireGuard. Only Jazz IPs route through WARP. Everything else
(uploads, app traffic, admin panel) goes direct via Oracle's normal internet link.

**Config:** `/etc/wireguard/wg0.conf`
- WARP peer pubkey: `bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=`
- Endpoint: `162.159.192.1:2408`
- AllowedIPs (split tunnel): `54.179.95.148/32, 54.254.59.168/32, 175.41.133.62/32`
- Enabled on boot: `sudo systemctl enable wg-quick@wg0`

**Flask config:** `JAZZDRIVE_PROXY_BYPASS=1` in `settings` DB table — Flask skips all
proxy logic, goes direct (OS routes Jazz IPs through WARP transparently).

**Verify tunnel:**
```bash
sudo wg show wg0
ip route show | grep wg0   # should show only 3 Jazz IPs
curl -o /dev/null -w '%{http_code}' https://cloud.jazzdrive.com.pk/sapi/login/oauth?action=login
# Expected: 400 (auth rejection, not geo-block)
```

**Why PROXY_BYPASS=1 disables proxy threads:** In `proxy_pool.py`, `ProxyPool.start()`
checks this DB setting. If bypass=1, it skips starting hc/recovery/disc background
threads entirely. Without this, 33,000 proxies + 40 health-check threads consumed
6 GB RAM and 60% CPU continuously for no reason.

---

## Jazz IP Watchdog v4

Jazz load-balances `cloud.jazzdrive.com.pk` across multiple IPs. DNS returns different
IPs on different calls. If WireGuard only has the current DNS result, packets to the
other IP get dropped → [Errno 113] No route to host.

**Watchdog:** `/opt/warp-watchdog/jazz_ip_watchdog.py`
- Accumulate mode: union of (fresh DNS) + (current WG IPs) + (historical known IPs)
- Never removes any IP that was ever seen
- Persists to: `/opt/warp-watchdog/known_jazz_ips.json`
- Runs every 10 min via: `jazz-ip-watchdog.timer` (systemd)

**Current known IPs:** `54.179.95.148`, `54.254.59.168`, `175.41.133.62`

**Why accumulate mode:** Jazz rotates IPs via DNS load-balancing. Flask caches an IP
while WG only allows the new one → Errno 113. Solution: keep all IPs ever seen in WG.

---

## Keepalive Configuration

- **Setting:** `keepalive_interval_min` in `settings` DB table
- **Current value:** `360` (6 hours = 4 heartbeats/day)
- **How to change:** Update DB setting; takes effect at end of current cycle (no restart needed)
- **Why 6 hours:** Account has refresh_token (90-day validity). JSESSIONID auto-renews
  on demand via `refresh_session()` when any SAPI call gets 401. No need for frequent pings.

```sql
UPDATE settings SET v='360' WHERE k='keepalive_interval_min';
```
