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
| TASK-057 | A-Z full line-by-line audit of ALL code (Flutter Dart + Oracle Python) + fix every bug + build APK | ✅ DONE | 2026-06-08 | 8 bugs fixed across Flutter + Oracle; APK build1034 succeeded (run 27156269376) |
| TASK-056 | VERIFY-02: Re-verify complete data flow end-to-end (all 10 checks A–J) | ✅ DONE | 2026-06-08 | All checks passed, no bugs found |
| TASK-055 | Full end-to-end data flow verification (DONE — see detail below) | ✅ DONE | 2026-06-08 | All checks A–J passed; Inuyashiki/Reborn season fix applied |
| TASK-054 | Fix Bug 2 — TV show episodes missing from delta | ✅ DONE | 2026-06-08 | zero_rating.py + jazzdrive_service.dart + delta regen |
| TASK-053 | DOCS-HANDOFF: NEXT_AGENT_BRIEF.md | ✅ DONE | 2026-06-08 | Full Flutter data flow, ID system, library verify, play/download |
| TASK-052 | FIX-DELTA-PREPURGE: upload_delta() pre-purge + /purge-delta-folder route | ✅ DONE | 2026-06-08 | delete all files BEFORE upload — no more delta_RANDOM.txt |
| TASK-051 | BUG-AUDIT-01: 3 similar bugs (poster dup, folder-create race, _upload_pending missing rename) | ✅ DONE | 2026-06-08 | library.py + uploader.py |
| TASK-050 | FIX-DEDUP-03: _upload_pending() duplicate guard (scheduler path) | ✅ DONE | 2026-06-08 | pre-check + skip+record logic; also renamed Vncenz0→Vincenzo |
| TASK-049 | FIX-DELTA-ACCUM: Radd-Delta folder cleanup | ✅ DONE | 2026-06-08 | list_all_files_in_folder + perm-delete 26 orphaned files |
| TASK-048 | FIX-DEDUP-02: JazzDrive-side duplicate upload guard in uploader.py | ✅ DONE | 2026-06-08 | commit d54d188 |
| TASK-047 | FIX-DEDUP-01: JazzDrive duplicate file audit + delete 4 duplicate files | ✅ DONE | 2026-06-08 | |
| TASK-045 | Fix catalog import — v3 DB now populated | ✅ DONE | 2026-06-08 | commit 6ccfa67 |
| TASK-044 | FEAT-LIBRARY-PUBLISH: Library publish controls | ✅ DONE | 2026-06-08 | commit a8046eb |
| TASK-043 | FIX-AUTOPUBLISH: auto-publish after scan | ✅ DONE | 2026-06-08 | |
| TASK-042 | FIX-SYNC-TIMEOUT: fast Oracle→delta fallback | ✅ DONE | 2026-06-08 | |
| TASK-041 | FIX-DELTA-PURGE: Radd-Delta folder cleanup | ✅ DONE | 2026-06-08 | |
| TASK-040 | FIX-CONFIG-01: RemoteConfig instant cache load | ✅ DONE | 2026-06-08 | |
| TASK-039 | Audit fix batch: FIX-RETRY-01 + FIX-POSTER-01 + FIX-FOLDER-01 + TTL comment | ✅ DONE | 2026-06-08 | sha 78f14210 |
| TASK-038 | FIX-PLAYER-01: local video black screen | ✅ DONE | 2026-06-07 | sha 215bbc2, build1025 |
| TASK-037 | FIX-VAULT-01: revert biometricOnly to false | ✅ DONE | 2026-06-07 | sha 59fc972, build1024 |
| TASK-036 | Deep codebase audit — Colors.white20 + 100+ Dart files | ✅ DONE | 2026-06-07 | APK build1022 |
| TASK-035 | Fix Dart compile errors BUG-BUILD-01 + 02 | ✅ DONE | 2026-06-07 | APK build1021 |
| TASK-034 | Vault fix — hide files + biometric unlock | ✅ DONE | 2026-06-07 | VAULT-01..06; commit f14eac5 |
| TASK-032 | Smart Enhance — AI video enhancement suite | ✅ DONE | 2026-06-07 | |
| TASK-031 | HUD v2 — presets, drag-reorder, MX-style | ✅ DONE | 2026-06-07 | |
| TASK-030 | PlayerHudSettingsSheet — live-preview overlay | ✅ DONE | 2026-06-07 | |
| TASK-029 | IDEA-01: Universal Subtitle Hunter | ✅ DONE | 2026-06-07 | |
| TASK-028 | player_prefs.dart full schema audit | ✅ DONE | 2026-06-07 | |
| TASK-027 | Player screen — Pass 6 (12 bugs: N01–N12) | ✅ DONE | 2026-06-07 | |
| TASK-026 | Player screen — Pass 5 (29-bug audit) | ✅ DONE | 2026-06-07 | 26 fixes |
| TASK-025 | Player screen — Pass 4 (BUG-P-NEW-06 + 07) | ✅ DONE | 2026-06-07 | |
| TASK-024 | Player screen — Pass 3 (BUG-P-NEW-05) | ✅ DONE | 2026-06-07 | |
| TASK-023 | Player screen — Pass 2 (BUG-P-NEW-01 to 04) | ✅ DONE | 2026-06-07 | |
| TASK-022 | Player screen — Pass 1 (13 fixes) | ✅ DONE | 2026-06-07 | |
| TASK-021 | JazzDrive Dart integration test + CI job | ✅ DONE | 2026-06-07 | |
| TASK-020 | Scanner TV edge cases | ✅ DONE | 2026-06-07 | |
| TASK-019 | Strip "Season N" from TV folder before metadata search | ✅ DONE | 2026-06-07 | |
| TASK-018 | Fix scan log events rename | ✅ DONE | 2026-06-07 | |
| TASK-017 | Fix scanner.py: rewrite to IMDb-first | ✅ DONE | 2026-06-07 | |
| TASK-016 | Document TV seasons/episodes system | ✅ DONE | 2026-06-07 | |
| TASK-015 | Fix TV show IMDbAPI search | ✅ DONE | 2026-06-07 | |
| TASK-014 | Improve scan log readability | ✅ DONE | 2026-06-07 | |
| TASK-013 | Fix metadata lookup order | ✅ DONE | 2026-06-07 | |
| TASK-012 | Add Restore Catalog button | ✅ DONE | 2026-06-07 | |
| TASK-011 | Fix admin db/reset | ✅ DONE | 2026-06-07 | |
| TASK-010 | Remove DATA-01 from AGENT_PROMPT.md | ✅ DONE | 2026-06-07 | |
| TASK-009 | Docs corrected — remove wrong geo-restriction claims | ✅ DONE | 2026-06-07 | |
| TASK-008 | Fix BUG-A03e: _s2_chain + _sub_chain respect PROXY_BYPASS | ✅ DONE | 2026-06-07 | |
| TASK-007 | Push all docs to GitHub (part 1) | ✅ DONE | 2026-06-07 | |
| TASK-006 | Update AGENT_PROMPT.md | ✅ DONE | 2026-06-07 | |
| TASK-005 | Create agent-hub/CONTEXT.md, RULES.md, TASKS.md | ✅ DONE | 2026-06-07 | |
| TASK-004 | BUG-A03d: forced pool.get_best() in _sub_chain (reverted) | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-003 | BUG-A03c: resolve_proxies revert | ✅ DONE | 2026-06-07 | |
| TASK-002 | BUG-A03b: forced PK proxy in _s2_chain (reverted) | 2026-06-07 | ❌ wrong — reverted in TASK-008 |
| TASK-001 | BUG-A03a: _ar_chain bypass guard | ✅ DONE | 2026-06-07 | |

---

## Backlog / Open

| ID | Task | Status | Notes |
|----|------|--------|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 | ❌ OPEN | Need JazzDrive upload + sync by admin |
| DATA-02 | 9 movies with deleted JD files (Animal, Dune, Inception, Interstellar, Inuyashiki, Oppenheimer, Reborn, The Ninth Gate, Super Mario Galaxy) | ❌ OPEN | Need manual re-upload to JazzDrive by admin |

---

## TASK-057 Detail — A-Z Full Audit + Fix + APK Build (DONE)

**Flutter bugs fixed (commit 3a68806 + bf50cd6):**
| ID | Severity | File | Bug | Fix |
|----|---------|------|-----|-----|
| BUG-TAB-01 | HIGH | show_detail_screen.dart | TabController recreated on pull-to-refresh without disposing old one → memory leak | Dispose old controller before replacing |
| BUG-DL-THROTTLE | MEDIUM | download_service.dart | SQLite progress updated 100s of times/sec → DB flood | Throttled to 5% boundary |
| FIX-URI-01 | MEDIUM | splash_screen.dart | `uri.split('/').last` drops query params on deep-link URIs | `Uri.parse(uri).pathSegments.last` with fallback |
| FIX-LIKE-01 | MEDIUM | local_db.dart | LIKE query didn't escape `%` / `_` meta-chars in user search | Escape user input before LIKE |
| FIX-SEARCH-INIT | LOW | search_screen.dart | `initialFilter` param didn't trigger `_doSearch()` → empty results | Call `_doSearch()` when initialFilter is set |
| FIX-ID-CAST | LOW | catalog_item.dart | `json['id'] as int` throws `TypeError` on null id | Safe cast with null fallback |

**Oracle Python bugs fixed (commit 41fcc63):**
| ID | Severity | File | Bug | Fix |
|----|---------|------|-----|-----|
| FIX-ISONGOING | HIGH | zero_rating.py | `is_ongoing` compared string `"0"` which is truthy in Python → events never marked as not-ongoing | Cast to `int()` before comparison |
| FIX-XOR-NEXTHR | MEDIUM | request_encoding.py | `_candidate_keys` missing +1 hour for forward-clock edge | Added `utc_hour + 1` candidate |

**APK:** `RaddFlix-1.0.0+1-build1034.apk` (56.7 MB) — run 27156269376 — expires 2026-07-08
