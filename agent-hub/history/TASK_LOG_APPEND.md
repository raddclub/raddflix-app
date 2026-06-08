## Session 2026-06-07 — JazzDrive Dart Integration Test

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| TASK-021 | JazzDrive Dart integration test + CI job | ✅ DONE |

### Files changed
| File | Change | Commit |
|------|--------|--------|
| raddflix_flutter/test_suite/jazzdrive_dart_test.dart | New: real HTTP Dart test, 8 test cases | 9614dae |
| .github/workflows/ci-tests.yml | New job: jazzdrive-dart (continue-on-error) | 9614dae, 72beab0, this commit |
| agent-hub/TASKS.md | Added TASK-021 | this commit |

### Key findings (from running the test — CI run #681)
1. **Dart link generation code is correct** — Pass 0, Pass 3 all work
2. **JazzDrive filenames use original upload names** — files uploaded as "Vncenz0 S01E01.mp4" (corrupted special char) are stored that way on JazzDrive. Pass 1/2 substring match can never work for these (app sends "Vincenzo", CDN has "Vncenz0"). Only Pass 0 (remote_id) or Pass 3 (SxxExx episode code) can match.
3. **GitHub Actions can't reliably reach cloud.jazzdrive.com.pk** — rotating Azure IPs, sometimes blocked. jazzdrive-dart job is continue-on-error. When reachable, tests pass.
4. **Luka Chuppi folder has 2 files** (original + duplicate) — remote_id is essential for movies too, not just TV.

### State at end of session
- Oracle Flask: ✅ RUNNING
- Account: ✅ ACTIVE (session auto-recovers)
- Open tasks: none

---

## Session 2026-06-08 — Infrastructure Sprint (TASK-040/041/042)

### Tasks completed
| ID | Task | Status |
|----|------|--------|
| TASK-040 | RemoteConfig split — loadCached() instant startup + fetchBackground() fire-and-forget | ✅ DONE |
| TASK-041 | Delta folder purge — list+snapshot+trash all old files before each upload | ✅ DONE |
| TASK-042 | Fast Oracle→delta fallback — connectTimeout 6s, 5s probe on getVersion() | ✅ DONE |

### Commits
| Commit | Change |
|--------|--------|
| `4020cdf` | TASK-040: RemoteConfig loadCached + fetchBackground split |
| `f8cd79b` | TASK-041: Delta folder purge — list_all_files_in_folder + purge before upload |
| `b709ebe` | TASK-042: Fast Oracle→delta fallback — connectTimeout 6s, 5s probe timeout |
| `6e7e517` | docs: TASK-042 logged |

### TASK-040 — RemoteConfig Split

**Problem:** `RemoteConfig.fetch()` was awaited in `main()` before `runApp()`. Splash screen hung
while waiting for Oracle `/api/config` if Oracle was slow or unreachable. No-bundle users saw a
frozen splash for up to 4 seconds before the app even rendered.

**Fix:** Split into two methods:
- `loadCached()` — awaited before `runApp()`, reads ONLY from SharedPreferences, instant,
  zero network. Sets `AppConstants.jazzDriveDeltaUrl` from cache.
- `fetchBackground()` — called after `runApp()`, NOT awaited, 4s timeout, hits Oracle
  `/api/config`, updates memory + refreshes SharedPreferences cache.
- Legacy `fetch()` shim retained for backwards compatibility.

**Files:** `remote_config.dart`, `main.dart`

### TASK-041 — Delta Folder Purge

**Problem:** Every `upload_delta()` added a new delta.json to JazzDrive without removing old ones.
Folder accumulated stale files. Undefined behaviour when Flutter downloaded the delta — no
guarantee it got the latest one.

**Fix:**
- New `list_all_files_in_folder(folder_id)` in `jazzdrive.py`:
  Uses `SAPI /media/video?action=get` — the only endpoint that returns ALL file types
  (including `.json`). Standard listing endpoints filter by MIME and miss JSON files.
- `upload_delta()` rewritten: snapshot all files BEFORE upload → upload new JSON →
  trash all files from snapshot (never re-list after upload, avoids trashing new file).
- New manual route `POST /zero-rating/purge-delta-folder` + UI button showing file count.

**Files:** `jazzdrive.py`, `routes/zero_rating.py`

### TASK-042 — Fast Oracle→Delta Fallback

**Problem:** Sync order was already correct (Oracle first, delta fallback) but `connectTimeout`
was 15s. On Jazz SIM with no bundle, TCP packets to Oracle are silently dropped by the operator
(not refused), so the app blocked for 15s before every cold start.

**Fix 1 (`api_client.dart`):** `connectTimeout: 15s → 6s`
**Fix 2 (`sync_service.dart`):** `.timeout(Duration(seconds: 5))` on `CatalogApi.getVersion()`.
`getVersion()` is a lightweight probe (returns 3 integers). If Oracle doesn't answer in 5s →
TimeoutException → caught by `sync()` → falls immediately to JazzDrive delta.
`syncFull()` / `syncDelta()` keep their full 30s timeout — large catalog downloads need it.

**Result:**
| User | What happens |
|------|-------------|
| Has bundle | Oracle responds < 1s → full Oracle sync, delta untouched |
| No bundle (Jazz SIM) | Oracle probe times out in 5s → falls to delta |
| Slow connection | Oracle probe takes 2-4s but responds → Oracle sync continues |

**Files:** `api_client.dart`, `sync_service.dart`

### Architectural rules added (RULES.md)
- Rule 32: RemoteConfig loadCached vs fetchBackground — never merge, never add network to loadCached
- Rule 33: AppConstants.jazzDriveDeltaUrl must stay mutable static String
- Rule 34: connectTimeout must stay ≤ 6s — no-bundle UX depends on it
- Rule 35: 5s timeout on getVersion() must stay — do not add short timeouts to syncFull/syncDelta
- Rule 36: Always purge delta folder BEFORE upload (snapshot + trash strategy)
- Rule 37: list_all_files_in_folder must use /media/video?action=get — it's the only endpoint that returns all MIME types

### State at end of session
- Oracle Flask: ✅ RUNNING
- JazzDrive delta: ✅ Functional (purge + upload working)
- Flutter sync: ✅ Fast fallback (≤5s to delta for no-bundle users)
- RemoteConfig: ✅ Instant startup (loadCached + fetchBackground split)
- Latest commit: `6e7e517` (docs) on main
- Open tasks: none

---
