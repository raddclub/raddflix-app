# agent-hub/RULES.md — Non-Negotiable Agent Rules
Last updated: 2026-06-07

## Startup (every session, no exceptions)
1. Set up SSH key from `ORACLE_SSH_KEY` env var (see AGENT_PROMPT.md Step 1)
2. Read `AGENT_HANDOFF.md` + last 80 lines of `TASK_LOG.md` + `BUG_TRACKER.md`
3. Read `agent-hub/TASKS.md` — continue any OPEN tasks before starting new work

---

## Task Tracking (NEW — mandatory)
**Rule 0: Every change gets a task entry in `agent-hub/TASKS.md` BEFORE work begins.**
- Open a task when you START working on it
- Close it with ✅ DONE when fully complete, tested, and pushed to GitHub
- If agent session ends with open tasks, the next agent sees them and continues
- Format: `| TASK-NNN | description | ⏳ IN PROGRESS / ✅ DONE / ❌ BLOCKED | YYYY-MM-DD | notes |`

---

## Code Rules
4. **No git shell commands** — GitHub API only (Contents or Trees API)
5. **No bash heredoc** for Node scripts — use Replit `write` tool instead
6. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
7. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (black screen)
8. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
9. **XOR padding fix** stays in `core/security/request_encoder.dart`:
   `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
10. **No Oracle destructive changes** without explicit user approval

---

## Database Rules
11. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist → AttributeError + HTTP 500
12. **For bulk writes/DELETEs** use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()`
    — WAL mode background threads silently block shared-wrapper writes
13. **settings table columns** are `k` and `v` (NOT `key` / `value`)

---

## JazzDrive Proxy Rules
14. **`_s2_chain` and `_sub_chain` MUST use `proxy_pool.pool.get_best()` directly**
    — resolve_proxies() returns None with PROXY_BYPASS=1, but SAPI login/OTP verify
    are geo-restricted to Pakistani IPs. Direct pool access bypasses the bypass flag.
15. **Do NOT make `resolve_proxies(purpose='sapi')` bypass-immune** — this breaks
    keepalive/uploads (JSESSIONID-based calls, not geo-restricted, should go direct)
16. **When a SAPI 401 body starts with `<!DOCTYPE HTML`** = geo-block (not API error).
    Fix: add a Pakistani proxy to `sapi_proxies` table.

---

## Debug Rules
17. **Debug code** must be gated behind `kDebugMode` — stripped from release APK

---

## End of Session (every session, no exceptions)
18. Append session summary to `agent-hub/history/TASK_LOG.md`
19. Update `BUG_TRACKER.md` with any new bugs found or fixed
20. Update `AGENT_HANDOFF.md` current state section
21. Update `AGENT_PROMPT.md` known issues table
22. Mark all completed tasks ✅ in `agent-hub/TASKS.md`
23. Push ALL doc changes to GitHub before ending session
