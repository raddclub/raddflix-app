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
| TASK-013 | Fix metadata lookup order: IMDbAPI.dev first → OMDB → TMDB chain | 2026-06-07 | ✅ Fixed in metadata_lookup.py + _legacy/scanner.py fallback |
| TASK-014 | Improve scan log readability: strip extension/kind noise, plain English | 2026-06-07 | ✅ Fixed in scan.html + scanner emit messages |
| TASK-015 | Fix TV show IMDbAPI search: strip S01E02 from query before searching | 2026-06-07 | ✅ Fixed in _legacy/scanner.py — SxxExx stripped for prefer=tv |
| TASK-016 | Document TV seasons/episodes system + update all agent-hub .md files | 2026-06-07 | ✅ This session |
| TASK-017 | Fix scanner.py: enrich_and_save was TMDB-first; rewrite to IMDb-first with full chain | 2026-06-07 | ✅ metadata_lookup.enrich() now primary; TMDB is final safety net only |
| TASK-018 | Fix scan log events: rename tmdb/tmdb_ok/tmdb_miss to lookup/found/not_found | 2026-06-07 | ✅ scan.html updated; backward compat kept for old log entries |
| TASK-019 | Strip "Season N" from TV folder name before metadata search | 2026-06-07 | ✅ Fixed in enrich_and_save — both SxxExx and "Season N" stripped |
| TASK-020 | ✅ DONE | 2026-06-07 | Scanner all real-world TV edge cases: Episode N/Ep N (Pakistani drama), numeric-only files (1.mp4), E01 alone; folder-name fallback for corrupted filenames (V!ncenz0); pipe/date strip; secondary folder-name search |
