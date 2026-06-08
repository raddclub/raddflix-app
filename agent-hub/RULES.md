# agent-hub/RULES.md — Non-Negotiable Agent Rules
Last updated: 2026-06-08 (added Rules 32–36 for RemoteConfig, sync timeouts, delta purge)

## Startup (every session, no exceptions)
1. Set up SSH key from `ORACLE_SSH_KEY` env var (see AGENT_PROMPT.md Step 1)
2. Read `AGENT_HANDOFF.md` + last 80 lines of `TASK_LOG.md` + `BUG_TRACKER.md`
3. Read `agent-hub/TASKS.md` — continue any OPEN tasks before starting new work

---

## Task Tracking (mandatory)
**Rule 0: Every change gets a task entry in `agent-hub/TASKS.md` BEFORE work begins.**
- Open a task row marked ⏳ IN PROGRESS when you START working
- Mark ✅ DONE when fully complete, tested, and pushed to GitHub
- If session ends with open tasks, the next agent sees them and continues
- Format: `| TASK-NNN | description | ⏳ / ✅ / ❌ | YYYY-MM-DD | notes |`

---

## JazzDrive Rules (read carefully — wrong assumptions here have caused bugs)
4. **JazzDrive is globally accessible — there is NO geo-restriction.**
   wg0 WireGuard works for ALL JazzDrive calls (login, OTP, uploads, keepalive).
5. **With PROXY_BYPASS=1, ALL proxy chains must go direct `[None]`.**
   Every chain builder (`_ar_chain`, `_s2_chain`, `_sub_chain`, etc.) must have
   an `is_proxy_bypass()` guard that sets chain to `[None]` immediately.
   Do NOT call `pool.get_best()` or `pool.get_proxy_chain()` when bypass=1 —
   pool proxies are dead/untested and cause 20-30s timeouts per attempt.
6. **SAPI 401 with HTML body (`<!DOCTYPE HTML`)** = dead proxy returning its own
   error page. Not JazzDrive. Fix: add `is_proxy_bypass()` guard to skip dead pool.
7. **Do NOT force proxy pool access for SAPI login/OTP steps.**
   These work direct via wg0 just like all other JazzDrive calls.

---

## Code Rules
8. **No git shell commands** — GitHub API only (Contents or Trees API)
9. **No bash heredoc** for Node scripts — use Replit `write` tool instead
10. **Never upgrade** `sqflite_sqlcipher` past `3.1.0+1`
11. **Never add** `androidAttachSurfaceAfterVideoParameters: true` to VideoController (black screen)
12. **Oracle port 5000 is not public** — test Flask APIs via SSH tunnel only
13. **XOR padding fix** stays in `core/security/request_encoder.dart`:
    `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove
14. **No Oracle destructive changes** without explicit user approval

---

## Database Rules
15. **Use `db.setting(k)` not `db.get_setting(k)`** — `get_setting` does not exist → AttributeError + HTTP 500
16. **For bulk writes/DELETEs** use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()`
    — WAL mode background threads silently block shared-wrapper writes
17. **settings table columns** are `k` and `v` (NOT `key` / `value`)

---

## Scan & Metadata Rules
18. **TV show IMDb search** — always strip the episode suffix (`S01E02`, etc.) from the
    clean filename before passing to any title search API. "Spider Noir S01E02" finds nothing;
    "Spider Noir" finds tt30460310. Already done in `_legacy/scanner.py` prefer='tv' path.
19. **Metadata lookup order** — IMDbAPI.dev first, then OMDB, then TMDB, then AI/YouTube/KG.
    Pakistani/Urdu content is on IMDb long before TMDB. Never revert to TMDB-first.
20. **IMDbAPI.dev is free and keyless** — use it aggressively as a first/fallback source.
    Endpoint: `https://imdbapi.dev/api/v1/search?q=<title>&type=<movie|tv>`

---

## Debug Rules
21. **Debug code** must be gated behind `kDebugMode` — stripped from release APK

---

## Player Screen Rules (player_screen.dart)
22. **`_ControlsOverlay` has two separate night-mode callbacks — never swap them:**
    - `onToggleCinematic` → toggles `_cinematicMode` (dims the controls overlay via Opacity)
    - `onToggleNightMode` → applies `_prefs.copyWith(nightMode: !_prefs.nightMode)` + save + `_applyVideoFilters()`
    The More Sheet "Night Mode" tile uses `onToggleCinematic`. The Quick Bar "nightmode" slot
    and Video Display Sheet use `onToggleNightMode`. Do NOT cross-wire them.
23. **VideoEnhanceSuite cinematic toggle must be bidirectional:**
    Compare `map['cinematicMode']` against `_cinematicMode`; call `_toggleCinematic()` only
    when they differ. Never call unconditionally when value is `true` — that breaks toggle-off.
24. **A-B loop: always sync UI state to controller:**
    Any widget that sets A-B points (ClipTrimmer, AbLoopPanel, etc.) MUST call
    `_abLoop.setA(d)` / `_abLoop.setB(d)` in addition to updating `_abLoopStart`/`_abLoopEnd`.
    Updating only the state vars breaks `maybeSeekBack()` enforcement and seek bar markers.

---

## RemoteConfig Rules (TASK-040 — added 2026-06-08)
32. **RemoteConfig has TWO methods — never merge them back into one:**
    - `RemoteConfig.loadCached()` — awaited in `main()` before `runApp()`. Reads ONLY from
      SharedPreferences. ZERO network calls. Instant. Sets `AppConstants.jazzDriveDeltaUrl`
      from cache so delta is available immediately on every cold start, including offline starts.
    - `RemoteConfig.fetchBackground()` — called AFTER `runApp()`, fire-and-forget, NOT awaited.
      Has 4-second timeout. Hits Oracle `/api/config`. Updates `AppConstants.jazzDriveDeltaUrl`
      AND refreshes the SharedPreferences cache.
    - Legacy `fetch()` shim exists for backwards compatibility — it calls `fetchBackground()`.
      Do not remove it. Do not add network calls inside `loadCached()`.

33. **`AppConstants.jazzDriveDeltaUrl` must remain a mutable `static String`** — NOT a getter.
    RemoteConfig.loadCached() and fetchBackground() both write to it. A `get` getter cannot
    be written to. Any refactor that turns this into a getter breaks offline delta.

---

## Sync Timeout Rules (TASK-042 — added 2026-06-08)
34. **`connectTimeout` in `api_client.dart` must stay at 6 seconds or less.**
    It was previously 15s. On Jazz SIM with no bundle, TCP packets to Oracle can be silently
    dropped by the operator — the app would block for 15s before falling to JazzDrive delta.
    6s is still generous for real internet connections (Oracle responds < 1s in practice).
    NEVER raise this back to 15s — it kills no-bundle UX.

35. **The `.timeout(Duration(seconds: 5))` on `CatalogApi.getVersion()` must stay.**
    File: `lib/core/db/sync_service.dart`, inside `_syncFromOracle()`.
    `getVersion()` is the Oracle probe — a tiny call that returns 3 integers. If it doesn't
    answer in 5s, the user has no bundle and we fall immediately to JazzDrive delta.
    `syncFull()` and `syncDelta()` intentionally keep their full 30s receiveTimeout — large
    catalog downloads on slow-but-real connections need that time. DO NOT add short timeouts
    to syncFull/syncDelta. DO NOT remove the timeout from getVersion().

---

## Delta Folder Purge Rules (TASK-041 — added 2026-06-08)
36. **Always purge the JazzDrive delta folder BEFORE uploading a new delta.json.**
    `upload_delta()` in `zero_rating.py` snapshots all files via `list_all_files_in_folder()`
    BEFORE starting the upload, then trashes them ALL after the new file is successfully uploaded.
    This keeps the delta folder clean (only the current delta.json lives there at all times).
    NEVER skip the pre-upload snapshot — if you only purge after upload you risk trashing
    the new file if the folder listing is re-fetched after the upload.

37. **`list_all_files_in_folder(folder_id)` in `jazzdrive.py` uses `/media/video?action=get`**
    — despite the name, this SAPI endpoint returns ALL file types (not just video). This is the
    only endpoint that reliably lists all files in a folder. Do NOT use `/media?action=list` or
    any other listing endpoint — they filter by MIME type and miss `.json` files.

---

## End of Session (every session, no exceptions)
25. Mark all completed tasks ✅ DONE in `agent-hub/TASKS.md`
26. Append session summary to `agent-hub/history/TASK_LOG.md`
27. Update `BUG_TRACKER.md` with any new bugs found or fixed
28. Update `AGENT_HANDOFF.md` current state section
29. Update `HANDOFF_NEXT.md` with what was done + what's next
30. Update `PLAYER_SPEC.md` if any player architecture changed
31. Push ALL doc changes to GitHub before ending session
