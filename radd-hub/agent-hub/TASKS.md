# TASKS.md — Radd Hub Agent Task Tracker
Last updated: 2026-06-08

## Current State
Flask running on Oracle 92.4.95.252 as `raddflix_radd` (port 5000, nginx proxies 80→5000).
DB: /opt/jazzmax/radd-hub/data/radd_hub.db — 17 titles / 28 files — all Live.

## Rule
Add a task row BEFORE making any changes. Mark done when pushed + verified.

---

## Task Log

| ID | Task | Status | Date | Notes |
|----|------|--------|------|-------|
| TASK-057 | A-Z full audit — Oracle Python fixes | ✅ DONE | 2026-06-08 | FIX-ISONGOING + FIX-XOR-NEXTHR; commit 41fcc63; Flask restarted |
| TASK-056 | Full end-to-end verification (checks A–J) | ✅ DONE | 2026-06-08 | All passed |
| TASK-055 | Data flow verification + Inuyashiki/Reborn season fix | ✅ DONE | 2026-06-08 | UPDATE files SET season=1,episode=1 WHERE id IN (7,12) |
| TASK-054 | Fix TV episodes missing from delta | ✅ DONE | 2026-06-08 | zero_rating.py media_type check + delta regen |
| TASK-053 | DOCS-HANDOFF | ✅ DONE | 2026-06-08 | NEXT_AGENT_BRIEF.md created |
| TASK-052 | FIX-DELTA-PREPURGE | ✅ DONE | 2026-06-08 | |
| TASK-051 | BUG-AUDIT-01: 3 bugs | ✅ DONE | 2026-06-08 | poster dup, folder race, rename_video |
| TASK-050 | FIX-DEDUP-03: _upload_pending guard | ✅ DONE | 2026-06-08 | |
| TASK-049 | FIX-DELTA-ACCUM: Delta folder cleanup | ✅ DONE | 2026-06-08 | 26 orphaned files deleted |
| TASK-048 | FIX-DEDUP-02: upload guard in uploader.py | ✅ DONE | 2026-06-08 | commit d54d188 |
| TASK-047 | FIX-DEDUP-01: delete 4 duplicate files | ✅ DONE | 2026-06-08 | |
| TASK-045 | Fix catalog import v3 | ✅ DONE | 2026-06-08 | commit 6ccfa67 |
| BUG-A03 | SAPI login geo-restriction fix | ✅ DONE | 2026-06-07 | commit 54f2434+bdea6d2 |
| BUG-A01 | Admin db/reset fix | ✅ DONE | 2026-06-06 | commit f8affe1 |
| BUG-A02 | mobile_api db.get_setting→db.setting fix | ✅ DONE | 2026-06-06 | |

---

## Open (data gaps — need admin action)

| ID | Issue | Notes |
|----|-------|-------|
| DATA-01 | All Of Us Are Dead E03/04/05/09 missing | Need JD upload + sync |
| DATA-02 | 9 movies with deleted JD files | Need manual re-upload to JazzDrive |

## 2026-06-09 — BUG-STALE-IDS Server Patch

| ID | Task | Status | Notes |
|----|------|--------|-------|
| SRV-STALE-IDS | Force-bump catalog version + add valid_title_ids to /sync | ✅ DONE | version=1781003205, valid_title_ids in /sync response, service restarted |
| SRV-CRYPTO-AUDIT | Audit request_encoding.py XOR logic | ✅ DONE | All correct — candidate keys, padding, device_id lookup |
