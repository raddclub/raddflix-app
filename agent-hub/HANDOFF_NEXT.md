# HANDOFF — RaddFlix Hub (as of TASK-058)

## State of Play
Flask app running at Oracle VPS 92.4.95.252:5000 (nginx 80→5000) — v3.0.0 healthy
Supervisor process name: **`raddflix_radd`** (NOT `radd-hub`)
DB: **17 titles / 28 files — all Live**
Delta: folder_id=1763725, remote_id=242554393
Account 03286829827: session healthy, auto-recovers via Android OAuth2 + PK proxy

## DB Facts
- account_id=15, msisdn=03286829827
- titles schema: `plot` (NOT `overview`), `genres_csv`, `cast_json`
- files schema: no `created_at` — use `scanned_at`
- files.fingerprint TEXT UNIQUE NOT NULL — DB-level guard against double-queuing
- files.remote_id TEXT (no UNIQUE — intentional)
- settings: `jd_delta_folder_id=1763725`, `jd_delta_remote_id=242554393`

## Known Bugs / Gotchas
1. **`upsert_title` UNIQUE slug bug** — fixed in scanner.py (commit 6ccfa67).
0. **`catalog_forced_version`** — set to `1781003205` (bumped 2026-06-09). All devices will full-sync on next open. The forced_ts is stored in Oracle `settings` table.
2. **`scan_excluded_folders`** — already cleared to `[]`.
3. **`confirm()` blocked by tunnel proxy** — all admin confirm dialogs use two-step arm+fire.
4. **`trash_files()` false-positive** — always use `delete_files_permanent()` for cleanup.
5. **`db.get_setting()`** — does NOT exist; use `db.setting(k)`.
6. **`is_ongoing` string "0"** — fixed (commit 41fcc63); cast to `int()` in zero_rating.py.
7. **`_candidate_keys` missing next-hour** — fixed (commit 41fcc63); +1 hour window added.

## APK Status

| Build | Status | Fixes included | Size | Expires |
|-------|--------|----------------|------|---------|
| **1035** | ⏳ NEEDS BUILD | BUG-STALE-IDS Flutter pruneStaleIds | — | — |
| 1034 | ✅ CURRENT | All TASK-057 fixes | 56.7 MB | 2026-07-08 |
| 1025 | OLD | FIX-PLAYER-01 + FIX-VAULT-01 | 56 MB | — |

GitHub Actions run: https://github.com/raddclub/raddflix-app/actions/runs/27156269376
Latest Flutter commit: `bf50cd6` | Oracle commit: `41fcc63`

## TASK-058 Fixes (2026-06-09) — BUG-STALE-IDS

**Root cause:** Oracle DB rebuild → new title IDs (1-20) → same version hash →
Flutter skipped re-sync → stale entries (id=28 Spider-Noir, file_id=31 dead) → 404 → "Jazz SIM Required"

**Server (live — affects build1034 now):**
| ID | File | Fix |
|----|------|-----|
| BUG-STALE-IDS | hub/routes/catalog_api.py | Force-bumped catalog version to 1781003205 |
| BUG-STALE-IDS | hub/routes/catalog_api.py | Added `valid_title_ids` to /sync response |

**Flutter (GitHub only — build1035 needed):**
| ID | File | Fix |
|----|------|-----|
| BUG-STALE-IDS | lib/core/api/catalog_api.dart | syncFull() returns SyncFullResult{items,validTitleIds} |
| BUG-STALE-IDS | lib/core/db/local_db.dart | pruneStaleIds() removes titles not in valid set |
| BUG-STALE-IDS | lib/core/db/sync_service.dart | Full sync calls pruneStaleIds() after persist |
| BUG-PRUNE-SQL | lib/core/db/local_db.dart | Restored $placeholders in NOT IN SQL (bash ate it) |

**Crypto audit result:** RequestEncoder + _XorInterceptor + server request_encoding.py — all correct, no issues.

## TASK-057 Bugs Fixed (2026-06-08)

**Flutter (commits 3a68806, bf50cd6):**
| ID | File | Bug |
|----|------|-----|
| BUG-TAB-01 | show_detail_screen.dart | TabController memory leak on pull-to-refresh |
| BUG-DL-THROTTLE | download_service.dart | SQLite progress DB flooded (100s updates/sec) |
| FIX-URI-01 | splash_screen.dart | `uri.split('/').last` drops query params |
| FIX-LIKE-01 | local_db.dart | LIKE query didn't escape `%`/`_` meta-chars |
| FIX-SEARCH-INIT | search_screen.dart | `initialFilter` didn't trigger `_doSearch()` |
| FIX-ID-CAST | catalog_item.dart | `json['id'] as int` throws TypeError on null |

**Oracle Python (commit 41fcc63):**
| ID | File | Bug |
|----|------|-----|
| FIX-ISONGOING | zero_rating.py | `is_ongoing` string "0" truthy in Python |
| FIX-XOR-NEXTHR | request_encoding.py | `_candidate_keys` missing +1 hour |

## Non-Negotiable Rules

- Never upgrade sqflite_sqlcipher past 3.1.0+1
- Never add androidAttachSurfaceAfterVideoParameters: true
- XOR padding fix must stay in request_encoder.dart — never remove
- GitHub pushes via Trees/Contents API only — no git shell
- Oracle Python3 for large file GitHub API calls
- GitHub token in local Replit env GITHUB_TOKEN (Oracle .env empty)
- SSH key: reconstruct from ORACLE_SSH_KEY env var to /tmp/oracle_key on each session
- db.setting(k) not db.get_setting(k)
- DB: /opt/jazzmax/radd-hub/data/radd_hub.db
- Supervisor: `sudo supervisorctl restart raddflix_radd`
- After ANY direct SQL change to is_published: regenerate delta via Python script
- Add tasks to TASKS.md BEFORE making changes
- Dart semicolons MUST come BEFORE inline comments: `expr); // comment`

## Open (data gaps — need admin re-upload)

| ID | Issue |
|----|-------|
| DATA-01 | All Of Us Are Dead — missing E03/E04/E05/E09 |
| DATA-02 | 9 movies with deleted JD files (Animal, Dune, Inception, Interstellar, Inuyashiki, Oppenheimer, Reborn, The Ninth Gate, Super Mario Galaxy) |
