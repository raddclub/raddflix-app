---
## Session: 2026-06-04 — Bug Investigation and Fixes

BUG #4 FIXED: Screen goes black after 2-3s of local video playback
  Root cause: _checkQuota() was checking sub_expires_at for ALL localPath cases
  including user-owned local folder files (fileId empty). Stale quota cache
  fired pushReplacementNamed(planExpired) 1-3s in, killing the player screen.
  Fix: added widget.fileId.isNotEmpty guard. Commit: 6808fc1

BUG #3 FIXED: Initial 1-2s black screen on local video
  Root cause: androidAttachSurfaceAfterVideoParameters:false attaches surface
  before first frame is decoded. Buffering spinner showed but video was black.
  Fix: wrapped Video in AnimatedOpacity that starts at 0.0 and fades in at 400ms
  once _playing becomes true. Commit: 6808fc1

BUG #2 DATA ISSUE: Missing episodes All Of Us Are Dead
  Oracle DB has S01E01,E02,E06,E07,E08,E10,E11,E12 — NO E03,E04,E05,E09
  Need to upload those 4 episodes to JazzDrive and sync to DB.

BUG #1 NETWORK ISSUE: JazzDrive fails without Jazz SIM
  cloud.jazzdrive.com.pk requires Jazz SIM. Code is correct.

Rules confirmed: androidAttachSurfaceAfterVideoParameters stays false,
sqflite_sqlcipher stays at 3.1.0+1, Oracle via SSH tunnel only.

---
## Session: 2026-06-05 — God-Level Proxy Pool + Upload UI Overhaul

### What was done

**proxy_pool.py — Full God-Level Rewrite:**
- Expanded seed list from 65 → 150+ proxies across 6 Pakistani ASNs (PTCL AS9541, StormFiber AS131275, Nayatel AS38193, Wateen AS45595, WorldCall AS17762, Micronet AS24499)
- Replaced basic round-robin with WEIGHTED SCORING rotation: score = (reliability * 80) + (speed_bonus * 20) — best proxies serve first
- Added CircuitBreaker class: if >80% proxies dead, falls back to DIRECT connection automatically (app never breaks)
- Added FAST RECOVERY thread: re-tests disabled proxies every 5 min (not just HC every 10 min) — dead proxies come back automatically
- Added get_proxy_chain(n=3): returns ordered retry chain for upload loops — if proxy fails mid-upload, caller retries with next best
- Expanded auto-discovery from 5 → 8 sources: geonode (3 pages), proxyscrape (2), openproxy.space, pubproxy.com, proxy-list.download
- Added bulk_import(urls, test=True) — add 100s of proxies at once
- Added test_proxy_by_id(proxy_id) — per-proxy live test with SAPI result
- Added reset_dead() — bulk re-enable all disabled proxies
- Added export_list() — plain URL list for backup/import
- Added get_stats() — detailed dashboard stats (total/alive/dead/avg_ping/circuit_open/by_source)
- Increased ThreadPoolExecutor workers from 25 → 40 for faster parallel testing
- Added `score` field to list_all() output for UI display

**routes/settings.py — 5 New API Endpoints:**
- GET  /settings/api/pool/stats → detailed statistics for dashboard
- POST /settings/api/pool/bulk-import → {urls, test} → bulk add proxies
- POST /settings/api/pool/test/<id> → per-proxy live test
- POST /settings/api/pool/reset-dead → re-enable all disabled, queue recovery
- GET  /settings/api/pool/export → full URL list export

**templates/_proxy_pool_panel.html — God-Level UI:**
- Live stat cards: Total / Alive / Dead / Avg Ping / Circuit Status
- Filter bar: All / Alive / Dead+Disabled / SOCKS5 / HTTP
- Sortable table: click column headers to sort (URL, Status, Score, Ping, OK, Fails)
- Score column (color-coded: green=high, yellow=mid, red=low)
- Ping bar visualization per proxy
- Per-proxy TEST button (live SAPI test inline)
- Bulk import panel: paste 100s of proxies at once, auto-detects format
- Export button: downloads proxy list as .txt
- Reset Dead button: re-enables all + queues recovery
- Auto-refresh every 10s (was 30s)
- Circuit breaker status card

### Files changed
- radd-hub/hub/proxy_pool.py
- radd-hub/hub/routes/settings.py
- radd-hub/hub/templates/_proxy_pool_panel.html
- radd-hub/agent-hub/history/TASK_LOG.md

### State at end of session
- Proxy pool: 150+ seeds, weighted rotation, circuit breaker, 5-min fast recovery, 8 discovery sources
- All 5 new settings API endpoints added (stats, bulk-import, test-one, reset-dead, export)
- UI: god-level proxy panel with live stats, filter, sort, bulk import, export, per-proxy test
- Upload never breaks: circuit breaker falls back to direct if all proxies dead
- Login never breaks: OTP/refresh uses separate resolve_proxies(purpose='otp') path, unaffected
- No duplicate functions — all additions extend existing architecture
