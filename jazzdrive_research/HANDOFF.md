# JazzDrive Handoff — Current State

> Updated: 2026-06-15. For next agent to pick up immediately.

---

## Server

| Item | Value |
|------|-------|
| Oracle IP | 92.4.95.252 |
| SSH user | ubuntu |
| SSH key | Reconstruct from `ORACLE_SSH_KEY` env var at `/tmp/oracle_key` |
| App root | `/opt/jazzmax/radd-hub/` |
| Supervisor service | `sudo supervisorctl restart raddflix_radd` |
| DB path | `/opt/jazzmax/radd-hub/data/radd_hub.db` |
| Health check | `curl http://localhost:5000/healthz` → `{"ok":true,"version":"3.0.0"}` |

---

## Current Account State (Account ID 11)

| Field | Status |
|-------|--------|
| MSISDN | `03257719165` |
| `validation_key` | ✅ Valid (32 chars) — saved 2026-06-15 via manual recovery |
| `jsessionid` | ✅ Valid (38 chars) |
| `raw_accesstoken` | ✅ Valid (40 hex chars, OTP-issued 2026-06-15) |
| `refresh_token` | ❌ Dead — `invalid_grant` (burned by rapid restarts) |
| Uploader | ✅ Working — Karuppu (2026) folder active, poster uploaded |

---

## Session Self-Renewal

On next Flask restart, `startup_refresh` will:
1. Try OAuth2 refresh → `invalid_grant` (RT is dead) → WARNING logged
2. Fall through to `sapi_direct_login` using `raw_accesstoken`
3. If SAPI direct login succeeds → fresh VK+JID saved → uploads continue
4. If SAPI direct login fails transiently → WARNING logged, but existing VK still valid

The session will continue working until the VK expires. Fresh OTP login needed to restore the `refresh_token` chain.

---

## Non-Negotiable Rules

1. **No `git pull` on Oracle** — all code pushes go via GitHub Trees API (node scripts in `/tmp/`). GitHub token is in Replit env `GITHUB_TOKEN`. Oracle's `.env` is empty — no GITHUB_TOKEN there.
2. **No `git shell` commands** — only `git stash`, `git pull`, `git stash pop` on Oracle are blocked. Never run them.
3. **Never use OAuth2-rotated `access_token` for SAPI login** — always use DB `raw_accesstoken`.
4. **Patch workflow**: write Python script locally → `scp` to Oracle → `python3 /tmp/script.py` → read file back → push to GitHub.
5. **`db.setting(k)` not `db.get_setting(k)`** — only `setting()` exists. `get_setting()` doesn't exist and raises `AttributeError`.
6. **files table column is `filename`**, not `file_name` (no underscore).
7. **Dart semicolons before inline comments**: `expr); // comment` ← correct. Never after.
8. **Never upgrade `sqflite_sqlcipher` past 3.1.0+1** — SQLCipher Dart API changed.
9. **Never add `androidAttachSurfaceAfterVideoParameters: true`** — causes black screen.
10. **XOR padding fix must stay in `request_encoder.dart`** — do not remove.

---

## Open Items

| ID | Priority | Status | Notes |
|----|---------|--------|-------|
| DELETE-STUCK-FILE | HIGH | OPEN | Delete `files.id=37` (Karuppu 480p stuck file), let fresh upload proceed |
| RENEW-REFRESH-TOKEN | MEDIUM | OPEN | Fresh OTP login will renew RT chain automatically |
| RENEW-PK-PROXIES | MEDIUM | OPEN | All 8 PK SOCKS proxies dead. `sapi_direct_login` is fallback. |

---

## Key Files

| File | Purpose |
|------|---------|
| `hub/jazzdrive.py` | Main JD client: OTP flow, SAPI requests, refresh, upload, share |
| `hub/scanner.py` | Scan worker: OTP for accounts, folder walk, TMDB enrich |
| `hub/uploader.py` | Upload pipeline: file → JazzDrive → share link |
| `hub/keepalive.py` | Background heartbeat: keeps JSESSIONID alive |
| `hub/_legacy/scanner.py` | v2 scanner reused under hub facade |
| `hub/_legacy/jazz_keepalive.py` | v2 keepalive reused |
| `hub/proxy_pool.py` | PK proxy pool: health-check, scoring, circuit breaker |
| `hub/db.py` | Database helpers. Use `db.setting(k)` not `db.get_setting(k)` |

---

## Code Push Workflow (Step by Step)

```bash
# 1. Write patch script locally
cat > /tmp/my_patch.py << 'EOF'
# ... Python code to modify the file on Oracle ...
EOF

# 2. SCP and run
scp -i /tmp/oracle_key -o StrictHostKeyChecking=no /tmp/my_patch.py ubuntu@92.4.95.252:/tmp/
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "python3 /tmp/my_patch.py"

# 3. Read back the modified file
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "cat /opt/jazzmax/radd-hub/hub/jazzdrive.py" > /tmp/file_final.py

# 4. Push to GitHub via Trees API (node script reading from /tmp/file_final.py)
node /tmp/push_script.js

# 5. Restart Flask
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "sudo supervisorctl restart raddflix_radd && sleep 5 && curl -s http://localhost:5000/healthz"
```
