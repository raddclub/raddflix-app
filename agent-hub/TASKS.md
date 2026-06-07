# agent-hub/TASKS.md — Agent Task Tracker
Last updated: 2026-06-07

## Rule
**Every change, fix, or feature gets a task row BEFORE work starts.**
Mark ✅ DONE when fully complete + pushed to GitHub.
Mark ⏳ IN PROGRESS when actively being worked.
Mark ❌ BLOCKED when waiting on user input or external dependency.
This file is the handoff bridge — the next agent reads this first.

---

## Current Sprint — Player Pass 2 (next agent picks these up)

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| TASK-024 | BUG-08: Subtitle sync slider state lost on track change | ❌ OPEN | — | Slider resets to 0ms when user switches subtitle track; should persist per-track |
| TASK-025 | BUG-09: Audio delay UI shows wrong unit (ms vs frames) | ❌ OPEN | — | `audioDelayMs` displayed correctly but step increments are in frames, not ms |
| TASK-026 | BUG-10: Sleep timer does not persist through background/resume | ❌ OPEN | — | Timer resets on `AppLifecycleState.resumed` — should resume from remaining seconds |
| TASK-027 | BUG-11: Rage-skip fires during A-B loop active segment | ❌ OPEN | — | Should be suppressed when `abLoop.isActive` |
| TASK-028 | BUG-12: Volume boost >1.0× causes distortion without warning | ❌ OPEN | — | Need soft-clip warning at >1.5× and hard cap at 3.0× |
| TASK-029 | BUG-13: PiP window loses subtitle overlay | ❌ OPEN | — | Sub layer not included in PiP surface; requires MediaSession metadata fallback |
| TASK-030 | BUG-15: Speed presets panel shows decimal formatting inconsistency | ❌ OPEN | — | 1.0 shows as "1.0×" but 1.25 shows as "1.25×" — align to 1 decimal place always |
| TASK-031 | BUG-16: Seek bar thumb invisible on 'wave' and 'film' styles | ❌ OPEN | — | CustomPainter for wave/film styles doesn't draw thumb; use default thumb overlay |
| TASK-032 | LAYOUT-03: Quick Shortcut Bar overflows on small screens (<360px wide) | ❌ OPEN | — | 5 items at 46px + 24px spacing = 254px; wraps on 320px screens → use SingleChildScrollView |
| TASK-033 | UX-02: Night Mode toggle in quick bar should update _cinematicOpacity live | ❌ OPEN | — | Currently calls `onToggleCinematic` which only toggles bool; opacity not reset to pref |
| TASK-034 | CLEAN-01: Remove dead `_bgPlayEnabled` local field — now managed via onBgPlayToggle | ❌ OPEN | — | Verify field usage, remove duplicate, test BG play toggle from quick bar |

---

## Backlog / Open

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| FEAT-001 | Phase B: Fully custom gesture remapping UI | ❌ OPEN | — | Map any gesture to any action; 12 actions, 8 gesture zones |
| FEAT-002 | Phase C: Floating subtitle editor (drag sub box on screen) | ❌ OPEN | — | Drag handle on sub overlay, persist position to PlayerPrefs |
| FEAT-003 | Phase D: Bookmark export (share image of frame + timestamp) | ❌ OPEN | — | Screenshot + overlay → share sheet |
| FEAT-004 | Phase E: Watch party (host/join via WebSocket, sync position) | ❌ OPEN | — | See watchPartyEnabled pref; backend endpoint needed |
| FEAT-005 | Phase F: Chapter auto-detect from video file metadata | ❌ OPEN | — | Parse FFprobe chapter data on Oracle; send with video metadata |

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
| TASK-020 | Scanner all real-world TV edge cases (Episode N/Ep N, numeric-only files, E01 alone, folder-name fallback, pipe/date strip, secondary folder-name search) | 2026-06-07 | ✅ |
| TASK-021 | Re-scan missing metadata: Flask endpoint POST /api/admin/rescan-metadata + admin panel button | 2026-06-07 | ✅ |
| TASK-022 | Player Pass 1 critical bugs: BUG-01 through BUG-07, BUG-14, LAYOUT-01/02, UX-01 (11 fixes) | 2026-06-07 | ✅ commit d2dd57e |
| TASK-023 | Player UI customization: center btn position (center/bottom/hidden) + Quick Shortcut Bar | 2026-06-07 | ✅ commit f0eb788 — player_screen.dart + player_prefs.dart + player_settings_screen.dart |
