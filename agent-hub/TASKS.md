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

---

## Backlog / Open

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| BACKLOG-01 | L-10: persist cinematicOpacity — needs PlayerPrefs.cinematicOpacity field added to player_prefs.dart | ❌ OPEN | 2026-06-07 | Deferred from TASK-026; low severity |

---

## Completed Archive

| ID | Task | Date | Outcome |
|----|------|------|---------|
| TASK-001 | BUG-A03a: _ar_chain bypass guard | 2026-06-07 | ✅ correct fix |
| TASK-002 | BUG-A03b: forced PK proxy in _s2_chain | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-003 | BUG-A03c: resolve_proxies revert | 2026-06-07 | ✅ correct fix |
| TASK-004 | BUG-A03d: forced pool.get_best() in _sub_chain | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-005 | Create agent-hub/CONTEXT.md, RULES.md, TASKS.md | 2026-06-07 | ✅ |
| TASK-006 | Update AGENT_PROMPT.md: task tracking rule, rules 13-14 | 2026-06-07 | ✅ |
| TASK-007 | Push all docs to GitHub (part 1) | 2026-06-07 | ✅ |
| TASK-008 | Fix BUG-A03e: _s2_chain + _sub_chain respect PROXY_BYPASS=1 | 2026-06-07 | ✅ |
| TASK-009 | Docs corrected — remove wrong geo-restriction claims | 2026-06-07 | ✅ |
| TASK-010 | Remove DATA-01 from AGENT_PROMPT.md (user confirmed complete) | 2026-06-07 | ✅ |
| TASK-011 | Fix admin db/reset: isolation_level=None + FTS rebuild + row counts | 2026-06-07 | ✅ |
| TASK-012 | Add Restore Catalog button in admin panel (POST /admin/api/db/restore) | 2026-06-07 | ✅ |
| TASK-013 | Fix metadata lookup order: IMDbAPI.dev first → OMDB → TMDB chain | 2026-06-07 | ✅ |
| TASK-014 | Improve scan log readability: strip extension/kind noise, plain English | 2026-06-07 | ✅ |
| TASK-015 | Fix TV show IMDbAPI search: strip S01E02 from query before searching | 2026-06-07 | ✅ |
| TASK-016 | Document TV seasons/episodes system + update all agent-hub .md files | 2026-06-07 | ✅ |
| TASK-017 | Fix scanner.py: enrich_and_save was TMDB-first; rewrite to IMDb-first | 2026-06-07 | ✅ |
| TASK-018 | Fix scan log events: rename tmdb/tmdb_ok/tmdb_miss to lookup/found/not_found | 2026-06-07 | ✅ |
| TASK-019 | Strip "Season N" from TV folder name before metadata search | 2026-06-07 | ✅ |
| TASK-020 | Scanner all real-world TV edge cases | 2026-06-07 | ✅ |
| TASK-021 | JazzDrive Dart integration test + CI job (jazzdrive-dart) | 2026-06-07 | ✅ |
| TASK-022 | Player screen — Pass 1 critical bugs (13 fixes) | 2026-06-07 | ✅ |
| TASK-023 | Player screen — Pass 2 deep audit (BUG-P-NEW-01 to 04) | 2026-06-07 | ✅ |
| TASK-024 | Player screen — Pass 3 verification (BUG-P-NEW-05) | 2026-06-07 | ✅ |
| TASK-025 | Player screen — Pass 4 full re-audit (BUG-P-NEW-06 + 07) | 2026-06-07 | ✅ |
| TASK-026 | Player screen — Pass 5 comprehensive 29-bug audit (2C+8H+9M+10L) | 2026-06-07 | ✅ 26 fixes applied; L-03/07/09/10 deferred (L-10 in BACKLOG-01) |
| TASK-027 | Player screen — Pass 6 full line-by-line audit (12 bugs fixed: N01–N12) | 2026-06-07 | ✅ All 12 fixed in one atomic commit |
