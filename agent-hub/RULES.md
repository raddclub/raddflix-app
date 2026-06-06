# agent-hub/RULES.md — Non-Negotiable Agent Rules
Last updated: 2026-06-07

## Startup (every session, no exceptions)
1. Set up SSH key from `ORACLE_SSH_KEY` env var (see AGENT_PROMPT.md Step 1)
2. Read `AGENT_HANDOFF.md` + last 80 lines of `TASK_LOG.md` + `BUG_TRACKER.md`
3. Read `agent-hub/TASKS.md` — continue any OPEN tasks before starting new work

---

## Task Tracking (mandatory)
**Rule 0: Every change gets a task entry in `agent-hub/TASKS.md` BEFORE work begins.**
- Open a task row marked ⏳ IN PROGRESS when you START working
- Mark ✅ DONE when fully complete, tested, and pushed to GitHub
- If session ends with open tasks, the next agent sees them and continues
- Format: `| TASK-NNN | description | ⏳ / ✅ / ❌ | YYYY-MM-DD | notes |`

---

## JazzDrive Rules (read carefully — wrong assumptions here have caused bugs)
4. **JazzDrive is globally accessible — there is NO geo-restriction.**
   wg0 WireGuard works for ALL JazzDrive calls (login, OTP, uploads, keepalive).
5. **With PROXY_BYPASS=1, ALL proxy chains must go direct `[None]`.**
   Every chain builder (`_ar_chain`, `_s2_chain`, `_sub_chain`, etc.) must have
   an `is_proxy_bypass()` guard that sets chain to `[None]` immediately.
   Do NOT call `pool.get_best()` or `pool.get_proxy_chain()` when bypass=1 —
   pool proxies are dead/untested and cause 20-30s timeouts per attempt.
6. **SAPI 401 with HTML body (`<!DOCTYPE HTML`)** = dead proxy returning its own
   error page. Not JazzDrive. Fix: add `is_proxy_bypass()` guard to skip dead pool.
7. **Do NOT force proxy pool access for SAPI login/OTP steps.**
   These work direct via wg0 just like all other JazzDrive calls.

---

## Code Rules
8. **No git shell commands** — GitHub API only (Contents or Trees API)
9. **No bash heredoc** for Node scripts — use Replit `write` tool instead
10. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
11. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (black screen)
12. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
13. **XOR padding fix** stays in `core/security/request_encoder.dart`:
    `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
14. **No Oracle destructive changes** without explicit user approval

---

## Database Rules
15. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist → AttributeError + HTTP 500
16. **For bulk writes/DELETEs** use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()`
    — WAL mode background threads silently block shared-wrapper writes
17. **settings table columns** are `k` and `v` (NOT `key` / `value`)

---

## Debug Rules
18. **Debug code** must be gated behind `kDebugMode` — stripped from release APK

---

## End of Session (every session, no exceptions)
19. Mark all completed tasks ✅ DONE in `agent-hub/TASKS.md`
20. Append session summary to `agent-hub/history/TASK_LOG.md`
21. Update `BUG_TRACKER.md` with any new bugs found or fixed
22. Update `AGENT_HANDOFF.md` current state section
23. Update `AGENT_PROMPT.md` known issues table + any new rules
24. Push ALL doc changes to GitHub before ending session
