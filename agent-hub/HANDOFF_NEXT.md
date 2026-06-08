# agent-hub/HANDOFF_NEXT.md — Next Agent Handoff
> Generated: 2026-06-08 | Session: Infrastructure Sprint (TASK-040/041/042/043)
> **Read this AFTER AGENT_HANDOFF.md and BEFORE touching any code.**

---

## What happened this session (2026-06-08 — Infrastructure Sprint)

Four infrastructure tasks completed. No player changes. Latest commit: `a45b0735`

| Task | Feature | Commits |
|------|---------|---------|
| TASK-040 | RemoteConfig split — loadCached (instant) + fetchBackground (4s fire-and-forget) | `4020cdf` |
| TASK-041 | Delta folder purge — list+trash all old files before each upload | `f8cd79b` |
| TASK-042 | Fast Oracle→delta fallback — connectTimeout 6s, 5s probe on getVersion | `b709ebe` |
| TASK-043 | Auto-publish fix — all titles with share_url published after scan (NULL + scope bug) | `a45b0735` |

---

## TASK-043 — Auto-Publish Fix

**Status:** ✅ Complete | Commit: `a45b0735`

**Problem:** `_auto_publish_titled_files()` in `scanner.py` had two bugs that prevented newly
scanned titles from being auto-published:

1. **NULL condition bug** — `AND is_published=0` in SQLite never matches rows where
   `is_published IS NULL` (SQLite `NULL = 0` evaluates to NULL, not true). Titles inserted
   without an explicit `is_published` value had NULL and were silently skipped.

2. **Account scope too narrow** — the query filtered `WHERE account_id=?` in the files
   subquery. A title with a file from account A wouldn't be published when scanning account B,
   even though the title has a valid share_url and should be visible.

**Fix in `radd-hub/hub/scanner.py`:**
```python
# BEFORE (broken):
" AND is_published=0", (now, account_id)

# AFTER (fixed):
" AND (is_published IS NULL OR is_published != 1)",
# + removed account_id=? filter from files subquery
(now,)
```

**Immediate DB fix also applied** — ran the corrected SQL on the live DB. Published 4 titles
that had been stuck with NULL is_published despite having valid share_url files.

**Result:** After any scan completes (or is stopped by user), ALL titles across the entire
catalog that have at least one file with a non-empty share_url are published in one pass.


---

## TASK-044 — Library Publish Controls

**Status:** ✅ Complete | Commit: `a8046eb`

**What was added to `/library/`:**

### Backend (`library.py`)
- `POST /api/titles/publish-all` — publishes all titles with any file share_url (same logic as scan auto-publish)
- `POST /api/titles/unpublish-all` — hides all titles from the app
- `POST /api/titles/bulk-set-published` — body `{ids:[...], is_published: bool}` — sets publish status for a list of IDs
- Added `filter_pub` filter to `_list_titles_filtered` (`published` / `unpublished`)
- Added `pub_first` and `unpub_first` sort options to `_SORT_MAP`
- Raised list limit from 200 → 500

### Frontend (`library.html`)
- **Header**: ✅ Publish All and 🚫 Unpublish All buttons added next to existing controls
- **Filter bar**: Status filter pills — All / ✅ Published / ⬜ Unpublished
- **Sort select**: Added "Published first" and "Unpublished first" options
- **Table**: Checkbox column + **Status column** (🟢 Live / grey Hidden) — click status to quick-toggle without opening modal
- **Grid cards**: Checkbox in top-left corner + Live/Hidden badge under media type
- **Bulk action bar**: Floating bar appears when ≥1 item selected — shows count, "Publish Selected", "Unpublish Selected", "✕ Clear"
- **Select All**: Checkbox in results header + table thead synced
- **Inline sync**: Toggling publish from modal OR row status cell updates the row immediately — no reload needed

### Architecture note
- `togglePublished()` (modal button) now also syncs the row's pub-dot/badge inline
- `_initAdminButtons()` uses pre-loaded `_titles._is_published` for instant modal open; still fetches for `is_free`

---

## TASK-040 — RemoteConfig Split

**Status:** ✅ Complete | Commit: `4020cdf`

**Problem:** `RemoteConfig.fetch()` was awaited in `main()` before `runApp()`. If Oracle was
slow or unreachable, the splash screen hung while waiting for the network response.

**Solution:** Split into two methods:

```
main() before runApp():
  await RemoteConfig.loadCached()
    → reads ONLY from SharedPreferences — instant, zero network
    → sets AppConstants.jazzDriveDeltaUrl from cache
    → app always starts fast, delta URL always available offline

main() after runApp() — fire-and-forget:
  RemoteConfig.fetchBackground()    // NOT awaited
    → hits Oracle /api/config with 4-second timeout
    → updates AppConstants.jazzDriveDeltaUrl (hot-updates in memory)
    → refreshes SharedPreferences cache for next cold start
    → silently ignored if Oracle unreachable
```

**Files changed:**
- `raddflix_flutter/lib/core/remote_config.dart` — added `loadCached()`, `fetchBackground()`; kept legacy `fetch()` shim
- `raddflix_flutter/lib/main.dart` — `await loadCached()` before runApp, `fetchBackground()` after

**Critical rules (never undo):**
- `loadCached()` must NEVER make network calls — it is the "instant startup" path
- `fetchBackground()` must NEVER be awaited before `runApp()`
- `AppConstants.jazzDriveDeltaUrl` must stay a mutable `static String` (not a getter)
- Legacy `fetch()` shim calls `fetchBackground()` — kept for any callers that still use `fetch()`

---

## TASK-041 — Delta Folder Purge

**Status:** ✅ Complete | Commit: `f8cd79b`

**Problem:** Every `upload_delta()` call added a new `delta.json` file to the JazzDrive delta
folder without removing old ones. Over time the folder accumulated duplicate JSONs with stale
catalog data.

**Solution:** Snapshot + trash all existing files BEFORE upload, then upload new file.

**New function in `jazzdrive.py`:**
```python
def list_all_files_in_folder(folder_id):
    # Uses /media/video?action=get — returns ALL MIME types despite the name
    # Do NOT use /media?action=list — it filters by MIME and misses .json files
```

**Rewritten `upload_delta()` in `zero_rating.py`:**
```
1. list_all_files_in_folder(delta_folder_id) → snapshot of all files
2. Upload new delta.json
3. If upload OK → trash ALL files from snapshot (not re-listed after upload)
4. Save new share_url to settings.jd_delta_url
```

**New manual route:** `POST /zero-rating/purge-delta-folder`
- Admin UI button shows file count before purge
- Trashes ALL files in the configured delta folder
- Returns count of files trashed

**Files changed:**
- `radd-hub/hub/jazzdrive.py` — new `list_all_files_in_folder()`
- `radd-hub/hub/routes/zero_rating.py` — rewritten `upload_delta()`, new purge route + button

**Critical rules (never undo):**
- SAPI `/media/video?action=get` returns ALL file types — don't switch to a type-filtered endpoint
- Snapshot files BEFORE upload (not after) — prevents accidentally trashing the new file
- Purge is automatic on every upload — admin manual purge button is just a maintenance helper

---

## TASK-042 — Fast Oracle→Delta Fallback

**Status:** ✅ Complete | Commit: `b709ebe`

**Problem:** Sync order was already correct (Oracle first → JazzDrive delta fallback). But
`connectTimeout` was 15s. On Jazz SIM with no bundle, TCP packets to Oracle (92.4.95.252) are
silently dropped by the operator, not refused. App blocked for **15 seconds** before every cold
start if user had no bundle.

**Fix 1 — `api_client.dart`:**
```dart
connectTimeout: const Duration(seconds: 6),  // was 15s
receiveTimeout: const Duration(seconds: 30),  // unchanged
```

**Fix 2 — `sync_service.dart`:**
```dart
// Inside _syncFromOracle():
final serverVersion = await CatalogApi.getVersion().timeout(
  const Duration(seconds: 5),
);
// getVersion() = lightweight probe (returns 3 integers)
// If Oracle doesn't respond in 5s → TimeoutException → caught by sync() → falls to delta
// syncFull() / syncDelta() keep their full 30s receiveTimeout
```

**Result:**

| User | Oracle response | What happens |
|------|----------------|-------------|
| Has bundle | < 1s | Oracle sync, delta never used |
| No bundle (Jazz SIM) | ~5s timeout | Falls to JazzDrive delta in ≤ 5s total |
| Slow connection | 2-4s but responds | Oracle sync completes normally |

**Files changed:**
- `raddflix_flutter/lib/core/api/api_client.dart` — connectTimeout 15s → 6s
- `raddflix_flutter/lib/core/db/sync_service.dart` — 5s probe on getVersion()

**Critical rules (never undo):**
- connectTimeout MUST stay ≤ 6s — see RULES.md Rule 34
- 5s timeout on getVersion() MUST stay — see RULES.md Rule 35
- Do NOT add short timeouts to syncFull/syncDelta — catalog downloads need 30s on slow connections

---

## Open Ops Issues (carry forward)

- **OPEN-OPS-01**: JazzDrive session for 03286829827 may need OTP re-login after Oracle restarts
  Until fixed: uploads fail, keepalive fails, delta upload 401 errors
- **OPEN-DATA-01**: All Of Us Are Dead — E03/E04/E05/E09 missing from JazzDrive

---

## Current State at End of Session

| Component | State |
|-----------|-------|
| Oracle Flask | ✅ Running |
| JazzDrive delta | ✅ Functional (purge + upload working) |
| Flutter sync | ✅ Fast fallback (≤5s to delta for no-bundle users) |
| RemoteConfig | ✅ Instant startup (loadCached + fetchBackground split) |
| Latest commit | `6e7e517` (docs) on `main` |

---

## Next Agent — Suggested Work (in priority order)

### HIGH PRIORITY — Security wiring (half-built, needs completion)
**Wire `MainActivity.kt` security MethodChannel** — AppGuard needs native channel for:
- `getSignatureFingerprint` — read APK signing cert SHA-256
- `checkFrida` — scan `/proc/self/maps` for Frida strings
- `checkRoot` — check `su` binary paths
The exact Kotlin code is in SECURITY_ARCHITECTURE.md. This is the last step to activate APK tamper detection.

**Wire share_url scrambling in `local_db.dart`:**
- `mergeDeltaTitle()` → `RequestEncoder.scrambleUrl(shareUrl, deviceId)` before insert
- `upsertEpisode()` → same for episode share_url
- Any read of share_url → `RequestEncoder.unscrambleUrl(url, deviceId)`
Code already exists in `request_encoder.dart` — just needs wiring.

### MEDIUM — Scheduler for delta auto-upload
Add a cron job / APScheduler task that calls `upload_delta()` every 24 hours automatically.
Currently admin must manually click "Generate + Upload" in the admin panel.
File: `radd-hub/hub/scheduler.py` (APScheduler already used for keepalive)

### LOW — Player features (see PLAYER_FEATURE_IDEAS.md)
- IDEA-06: Subtitle Personality Engine (ALL CAPS → bold red, ♪ → italic gradient, etc.)
- IDEA-07: Player Skin Palette Generator (extract palette from poster → theme player)
- IDEA-05: Cinematic Frame Capture (triple-tap → 2.39:1 crop + export as story)

---

## Download fresh files

```bash
# api_client.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/api/api_client.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/api_client.dart','wb').write(base64.b64decode(d['content']))"

# sync_service.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/db/sync_service.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/sync_service.dart','wb').write(base64.b64decode(d['content']))"

# remote_config.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/core/remote_config.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/remote_config.dart','wb').write(base64.b64decode(d['content']))"

# jazzdrive.py
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/radd-hub/hub/jazzdrive.py" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/jazzdrive.py','wb').write(base64.b64decode(d['content']))"

# zero_rating.py
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/radd-hub/hub/routes/zero_rating.py" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/zero_rating.py','wb').write(base64.b64decode(d['content']))"

# player_screen.dart
curl -sH "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/screens/player_screen.dart" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('/tmp/ps.dart','wb').write(base64.b64decode(d['content']))"
echo "Lines: $(wc -l < /tmp/ps.dart)"
```

---

## GitHub Push Recipe

Use Trees API for multi-file atomic commits:
1. `GET /repos/{owner}/{repo}/git/refs/heads/main` → commitSha
2. `GET /repos/{owner}/{repo}/git/commits/{commitSha}` → treeSha
3. `POST /git/trees` with base_tree + file content → newTreeSha
4. `POST /git/commits` → newCommitSha
5. `PATCH /git/refs/heads/main` → update HEAD

Owner: `raddclub`, Repo: `raddflix-app`, Branch: `main`.
**NEVER use git shell commands.**
