# AGENT_STATUS.md
> Current project status for agent coordination.
> Last updated: 2026-06-09

---

## Overall Health

| Area | Status | Notes |
|------|--------|-------|
| App (Oracle) | ✅ RUNNING | `raddflix_radd` via supervisorctl, port 5000, pid 3008136 |
| Flutter app | ✅ STABLE | All 8 TASK-057 bugs fixed; APK build1034 succeeded |
| SAPI Proxy Pool | ✅ GOD-LEVEL | 150+ PK seeds, weighted rotation, circuit breaker |
| JazzDrive Upload | ✅ WORKING | Proxy-chain retry, speed/ETA/proxy shown in UI |
| XOR Encoding | ✅ FIXED | Padding fix in request_encoder.dart — NEVER remove |
| JazzDrive Session | ✅ HEALTHY | Account 03286829827 auto-recovers via Android OAuth2 + PK proxy |
| WhatsApp Bot | ✅ RUNNING | autostart=false, pid alive |
| APK CI | ✅ PASSING | build1034 (run 27156269376) — expires 2026-07-08 |
| Oracle Python (audit) | ✅ FIXED | FIX-ISONGOING + FIX-XOR-NEXTHR applied (commit 41fcc63) |

---

## Latest APK

| Build | Status | Fixes included | Size | Expires |
|-------|--------|----------------|------|---------|
| 1034 | ✅ LATEST | All TASK-057 Flutter fixes + prior fixes | 56.7 MB | 2026-07-08 |
| 1025 | OLD | FIX-PLAYER-01 + FIX-VAULT-01 | 56 MB | — |

GitHub Actions run: https://github.com/raddclub/raddflix-app/actions/runs/27156269376

---

## Current System State (as of 2026-06-08 — post TASK-057)

| Component | State |
|-----------|-------|
| Oracle Flask | ✅ RUNNING — PID 3008136, supervisorctl status OK |
| v3 DB | ✅ 17 titles / 28 files — all Live (`is_published=1`) |
| Library UI | ✅ Publish All / Unpublish All / bulk controls / bulk delete working |
| Admin UI | ✅ All confirm()/prompt() replaced with two-step arm+fire toasts |
| Scan UI | ✅ Excluded folders remove + role change two-step |
| Settings UI | ✅ OTP flow replaced with inline panel |
| scanner.py | ✅ UNIQUE slug conflict handled with fallback lookup (commit 6ccfa67) |
| scan_excluded_folders | ✅ Empty `[]` |
| JAZZDRIVE_PROXY_BYPASS | ✅ = 1 (direct wg0, all proxies bypassed) |
| delta_auto_enabled | ✅ = 1 (auto-runs every 6 hours) |
| is_ongoing bug | ✅ FIXED (commit 41fcc63) — string "0" was truthy |
| XOR _candidate_keys | ✅ FIXED (commit 41fcc63) — +1 hour window added |

---

## Key Architecture Facts (memorize before touching code)

- **Oracle VPS**: `92.4.95.252` — Flask port 5000, localhost only (SSH tunnel to test)
- **Supervisor name**: `raddflix_radd` — NOT `radd-hub` (that name does not exist)
- **Zero-rating**: `cloud.jazzdrive.com.pk` is Jazz network-whitelisted — no data bundle needed
- **Share URLs**: JazzDrive share_urls NEVER expire — security via APK integrity, not link expiry
- **Sync priority**: Oracle first (5s probe) → JazzDrive delta fallback on timeout
- **DB path**: `/opt/jazzmax/radd-hub/data/radd_hub.db` (SQLite WAL, this is the ONLY real DB)
- **Account**: MSISDN 03286829827 → v3 account_id=15, legacy_id=2
- **Proxy setting key**: `JAZZDRIVE_PROXY_BYPASS` = `1` (NOT `proxy_bypass`)
- **GitHub push**: Trees/Contents API ONLY — never git shell
- **Template GitHub path**: `radd-hub/hub/templates/` (NOT `hub/templates/`)

---

## v3 DB Schema Quirks (agents get this wrong constantly)

```
titles: plot (NOT overview), genres_csv, cast_json, is_published (0/1)
files:  scanned_at (NOT created_at), fingerprint='scan:<remote_id>'
db API: db.setting(k) / db.set_setting(k,v) — NEVER db.get_setting()
settings columns: k and v (NOT key / value)
```

---

## Critical Rules (never break these)

```
1.  No git shell — GitHub Trees/Contents API only
2.  sqflite_sqlcipher pinned at 3.1.0+1 — never upgrade
3.  androidAttachSurfaceAfterVideoParameters must NEVER be true (black screen)
4.  biometricOnly must be false — breaks vault on Infinix/MediaTek
5.  Oracle port 5000 NOT public — test via SSH tunnel only
6.  XOR padding fix stays in request_encoder.dart — never remove
7.  AppConstants.jazzDriveDeltaUrl = mutable static String (not getter)
8.  connectTimeout must stay 6s max — no-bundle Jazz SIM users depend on it
9.  5s timeout on CatalogApi.get
10. db.setting(k) only — db.get_setting() does NOT exist
11. Supervisor name = raddflix_radd — NOT radd-hub
12. Dart semicolons BEFORE inline comments: `expr); // comment` (never `expr) // comment;`)
13. No confirm()/prompt() in Flask templates — two-step arm+fire toast instead
14. Template GitHub path: radd-hub/hub/templates/ (NOT hub/templates/)
15. Push template files sequentially — parallel PUTs cause 409 SHA conflicts
```

---

## Open Issues (requires admin action, not code fixes)

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | ❌ OPEN | Need JD upload + sync |
| DATA-02 | 9 movies with deleted JD files | ❌ OPEN | Need manual re-upload to JazzDrive |
| OPS-01 | Account 03286829827 session | ✅ RESOLVED 2026-06-07 | BUG-A03 fixed. Auto-recovers via Android OAuth2 + PK proxy |

---

## SAPI Call Architecture

```
CALL TYPE                  | EXIT IP              | GEO-RESTRICTED?
---------------------------|----------------------|----------------
Keepalive (JSESSIONID)     | wg0 → Cloudflare     | NO  ✅
Upload (JSESSIONID)        | wg0 → Cloudflare     | NO  ✅
OAuth2 /oauth2/refresh     | wg0 → Cloudflare     | NO  ✅
SAPI login /sapi/login     | Pakistani SOCKS proxy| YES ⚠️
OTP verify                 | Pakistani SOCKS proxy| YES ⚠️
```

PROXY_BYPASS=1 skips proxies in resolve_proxies() for all callers.
_s2_chain bypasses resolve_proxies() and reads pool directly — PK proxy always used for login.


## 2026-06-09 — BUG-STALE-IDS
Server: force-bump + valid_title_ids. Flutter: pruneStaleIds (build1035 needed). Crypto audit: all pass.
