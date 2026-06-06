# agent-hub/TASKS.md — Agent Task Tracker
Last updated: 2026-06-07

## Rule
**Every change, fix, or feature gets a task row BEFORE work starts.**
Mark ✅ DONE when fully complete + pushed to GitHub.
Mark ⏳ IN PROGRESS when actively being worked.
Mark ❌ BLOCKED when waiting on user input or external dependency.
This file is the handoff bridge — the next agent reads this first.

---

## Current Sprint

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| TASK-001 | Fix BUG-A03a: _ar_chain proxy bypass not respected (PROXY_BYPASS=1 tried dead pool) | ✅ DONE | 2026-06-07 | commit 54f2434 |
| TASK-002 | Fix BUG-A03b: SAPI login geo-restricted to PK IPs — use pool.get_best() in _s2_chain | ✅ DONE | 2026-06-07 | commit 54f2434 |
| TASK-003 | Fix BUG-A03c: Revert over-broad resolve_proxies bypass — was breaking all SAPI calls | ✅ DONE | 2026-06-07 | commit 54f2434 |
| TASK-004 | Fix BUG-A03d: submit_otp _sub_chain same geo-restriction fix — use pool.get_best() | ✅ DONE | 2026-06-07 | same pattern as _s2_chain |
| TASK-005 | Create agent-hub/CONTEXT.md, RULES.md, TASKS.md (were missing) | ✅ DONE | 2026-06-07 | this file |
| TASK-006 | Update AGENT_PROMPT.md: fix known issues table, add task tracking rule | ✅ DONE | 2026-06-07 | |
| TASK-007 | Push all BUG-A03d fix + docs to GitHub (atomic tree commit) | ✅ DONE | 2026-06-07 | |

---

## Backlog / Open

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| DATA-01 | Upload missing All Of Us Are Dead E03/E04/E05/E09 to JazzDrive | ❌ OPEN | - | Need content files, then run upload queue |
| OPS-02 | Add self-healing PK proxy refresher (auto-discovers + tests PK SOCKS5 proxies weekly) | ❌ OPEN | - | Proposed — needs user approval |

---

## Completed (Archive)

| ID | Task | Date | Commit |
|----|------|------|--------|
| TASK-001 | BUG-A03a proxy bypass fix | 2026-06-07 | 54f2434 |
| TASK-002 | BUG-A03b SAPI geo-restriction fix | 2026-06-07 | 54f2434 |
| TASK-003 | BUG-A03c resolve_proxies revert | 2026-06-07 | 54f2434 |
| TASK-004 | BUG-A03d submit_otp proxy fix | 2026-06-07 | (this commit) |
| TASK-005 | Create agent-hub docs | 2026-06-07 | (this commit) |
| TASK-006 | Update AGENT_PROMPT.md | 2026-06-07 | (this commit) |
| TASK-007 | Push all docs + code | 2026-06-07 | (this commit) |
