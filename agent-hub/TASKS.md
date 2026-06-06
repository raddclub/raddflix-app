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
| TASK-001 | Fix BUG-A03a: _ar_chain proxy bypass not respected (tried dead pool with PROXY_BYPASS=1) | ✅ DONE | 2026-06-07 | commit 54f2434 |
| TASK-002 | Fix BUG-A03b: Force PK proxy in _s2_chain — WRONG diagnosis, caused delay | ✅ REVERTED | 2026-06-07 | See TASK-008 |
| TASK-003 | Fix BUG-A03c: Revert resolve_proxies bypass exception | ✅ DONE | 2026-06-07 | commit 54f2434 |
| TASK-004 | Fix BUG-A03d: submit_otp forced pool.get_best() — WRONG, caused delay | ✅ REVERTED | 2026-06-07 | See TASK-008 |
| TASK-005 | Create agent-hub/CONTEXT.md, RULES.md, TASKS.md | ✅ DONE | 2026-06-07 | |
| TASK-006 | Update AGENT_PROMPT.md: task tracking rule, rules 13-14 | ✅ DONE | 2026-06-07 | Updated again in TASK-009 |
| TASK-007 | Push all docs to GitHub (part 1) | ✅ DONE | 2026-06-07 | |
| TASK-008 | Fix BUG-A03e: _s2_chain and _sub_chain must respect PROXY_BYPASS=1 (was forcing dead proxies) | ✅ DONE | 2026-06-07 | JazzDrive global, no geo-restriction. Both chains now use is_proxy_bypass() guard → [None] direct |
| TASK-009 | Update all MD docs: correct wrong geo-restriction diagnosis | ✅ DONE | 2026-06-07 | |

---

## Backlog / Open

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| DATA-01 | Upload missing All Of Us Are Dead E03/E04/E05/E09 to JazzDrive | ❌ OPEN | - | Need content files, then run upload queue |

---

## Completed Archive

| ID | Task | Date | Outcome |
|----|------|------|---------|
| TASK-001 | BUG-A03a: _ar_chain bypass guard | 2026-06-07 | ✅ correct fix |
| TASK-002 | BUG-A03b: forced PK proxy in _s2_chain | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-003 | BUG-A03c: resolve_proxies revert | 2026-06-07 | ✅ correct fix |
| TASK-004 | BUG-A03d: forced pool.get_best() in _sub_chain | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-005 | Create agent-hub docs | 2026-06-07 | ✅ |
| TASK-006 | Update AGENT_PROMPT | 2026-06-07 | ✅ |
| TASK-007 | Push docs part 1 | 2026-06-07 | ✅ |
| TASK-008 | BUG-A03e: correct both chain builders — bypass → direct | 2026-06-07 | ✅ |
| TASK-009 | Docs corrected (geo-restriction diagnosis was wrong) | 2026-06-07 | ✅ |
