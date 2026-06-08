# agent-hub/TASKS.md — Agent Task Tracker
Last updated: 2026-06-08

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
| TASK-029 | IDEA-01: Universal Subtitle Hunter | ✅ DONE | 2026-06-07 | SubtitleHunter + ZIP + fuzzy match + sheet + URL loader |
| TASK-040 | FIX-CONFIG-01: RemoteConfig instant cache load, Oracle fetch in background | ✅ DONE | 2026-06-08 | loadCached() awaited on startup; fetchBackground() fire-and-forget after runApp() |
| TASK-041 | FIX-DELTA-PURGE: Radd-Delta folder cleanup — trash all old files before each upload | ✅ DONE | 2026-06-08 | list_all_files_in_folder() + purge before upload + manual purge route |
| TASK-042 | FIX-SYNC-TIMEOUT: fast Oracle→delta fallback (connectTimeout 6s, 5s probe on getVersion) | ✅ DONE | 2026-06-08 | No-bundle users fall to delta in ≤5s instead of 15s |
| TASK-043 | FIX-AUTOPUBLISH: auto-publish all titles with share_url after scan — fix NULL + account scope | ✅ DONE | 2026-06-08 | Fixed NULL condition bug + removed account_id filter; 4 titles published immediately on live DB |
| TASK-044 | FEAT-LIBRARY-PUBLISH: Library publish controls — Publish All, Unpublish All, Publish Selected, status filter, quick inline toggle | ✅ DONE | 2026-06-08 | commit a8046eb — 3 new API routes + full HTML UI overhaul |

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
| TASK-028 | player_prefs.dart full schema audit (P01–P04 + BACKLOG-01) | 2026-06-07 | ✅ 3 critical bugs fixed; BACKLOG-01 resolved; 5 duplicate-field pairs documented |
| TASK-030 | PlayerHudSettingsSheet — live-preview transparent layout & controls settings overlay | 2026-06-07 | ✅ |
| TASK-031 | HUD v2 — presets, orientation tabs, drag-reorder Quick Bar, button shapes, MX-style auto-rotation, dedup guard | 2026-06-07 | ✅ |
| TASK-032 | Smart Enhance — MX-style AI video enhancement suite (8 presets, master toggle, intensity, before/after compare) | 2026-06-07 | ✅ |
| TASK-034 | Vault fix — hide files from gallery/file manager + biometric unlock fix | ✅ | 2026-06-07 | 6 bugs: VAULT-01..06; commit f14eac5 |
| TASK-035 | Fix Dart compile errors blocking APK build (BUG-BUILD-01 + 02) | ✅ | 2026-06-07 | _openSettings→_openPlayerSettings; Colors.white87→Color(0xDEFFFFFF); APK build1021 succeeded |
| TASK-036 | Deep codebase audit — fix Colors.white20 compile error + sweep all 100+ Dart files for build-blocking bugs | ✅ | 2026-06-07 | BUG-BUILD-03: Colors.white20→Color(0x33FFFFFF) in layout_designer_screen; all 100+ files clean; APK build1022 success |
| TASK-037 | FIX-VAULT-01: revert biometricOnly to false — fixes vault auth on Infinix/MediaTek | 2026-06-07 | ✅ sha 59fc972, build1024 |
| TASK-038 | FIX-PLAYER-01: local video black screen — _duration==Duration.zero not _position | 2026-06-07 | ✅ sha 215bbc2, build1025 |
| TASK-039 | Audit fix batch: FIX-RETRY-01 + FIX-POSTER-01 + FIX-FOLDER-01 + TTL comment | 2026-06-08 | ✅ sha 78f14210 — 4 bugs/gaps fixed |
