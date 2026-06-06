---
name: WARP Split Tunnel + Proxy Bypass
description: Cloudflare WARP via WireGuard routes only Jazz IPs; PROXY_BYPASS=1 kills all proxy threads; accumulate-mode watchdog never removes IPs
---

## WARP Split Tunnel

Oracle's non-PK IP gets MED-1011 geo-block from JazzDrive. Fix: Cloudflare WARP via
WireGuard (wgcf) as a **split tunnel** — only the 3 Jazz IPs go through WARP.
All other traffic goes direct. Upload speed is unaffected.

Config at `/etc/wireguard/wg0.conf` — AllowedIPs = the 3 Jazz IPs only.
`JAZZDRIVE_PROXY_BYPASS=1` in DB = Flask sends Jazz calls direct → OS routes via wg0.

**Why:** Routing 0.0.0.0/0 through WARP would slow all traffic. Split tunnel keeps
uploads/app at full Oracle speed while Jazz API gets the PK IP it requires.

## Proxy Pool Bypass Mode

`JAZZDRIVE_PROXY_BYPASS=1` in `settings` table does two things:
1. Flask skips all proxy selection logic in `resolve_proxies()`
2. `proxy_pool.ProxyPool.start()` skips starting hc/recovery/disc threads

Without this, 33k proxies + 40 health-check threads = 6 GB RAM + 60% CPU permanently.
To re-enable proxies: set `JAZZDRIVE_PROXY_BYPASS=0` and restart Flask.

## Jazz IP Watchdog — Accumulate Mode

Jazz DNS load-balances across multiple IPs. Old watchdog replaced IPs → Errno 113.
v4 at `/opt/warp-watchdog/jazz_ip_watchdog.py` takes union of all sources, never shrinks.
Runs every 10 min via systemd timer. Known IPs persist to `known_jazz_ips.json`.

**How to apply:** If adding a new Jazz-related endpoint, add its domain to the DOMAINS
list in the watchdog so its IPs get accumulated into WireGuard AllowedIPs.
