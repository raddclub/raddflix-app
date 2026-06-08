# agent-hub/RULES.md — Non-Negotiable Agent Rules
Last updated: 2026-06-08 (added Rules 32–38 — RemoteConfig, sync, delta, confirm/prompt, template paths)

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
    clean filename before passing to any title search API.
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
23. **VideoEnhanceSuite cinematic toggle must be bidirectional:**
    Compare `map['cinematicMode']` against `_cinematicMode`; call `_toggleCinematic()` only
    when they differ.
24. **A-B loop: always sync UI state to controller:**
    Any widget that sets A-B points MUST call `_abLoop.setA(d)` / `_abLoop.setB(d)`.

---

## Admin UI Rules (TASK-046 — added 2026-06-08)
38. **Never use `confirm()` or `prompt()` in any Flask template** — they are blocked by the
    Cloudflare tunnel / proxy that the admin panel runs behind.
    **Replacement patterns:**
    - **Destructive actions** (delete, wipe, reset, restart): use **two-step arm+fire** toast:
      ```js
      if (!window._armed_actionName) {
        window._armed_actionName = true;
        toast('⚠ Are you sure? — click again to confirm', 4000);
        setTimeout(() => { window._armed_actionName = false; }, 4000);
        return;
      }
      window._armed_actionName = false;
      // proceed with the action
      ```
    - **Input required** (quota, OTP): add an **inline panel** in HTML that slides open:
      show an `<input>` + confirm button inline in the page — do NOT use `prompt()`.
    - Scope the arm key by item id for per-row actions: `_armed_deleteKey_${id}`.

39. **Flask template GitHub path is `radd-hub/hub/templates/`** — NOT `hub/templates/`.
    When pushing `scan.html`, `admin.html`, `settings.html`, `library.html`, etc. to GitHub,
    always use `radd-hub/hub/templates/<filename>` as the remote path.
    Parallel GitHub PUT calls will fail with 409 SHA conflict — push templates **sequentially**.

---

## RemoteConfig Rules (TASK-040 — added 2026-06-08)
32. **RemoteConfig has TWO methods — never merge them back into one:**
    - `RemoteConfig.loadCached()` — awaited in `main()` before `runApp()`. Reads ONLY from
      SharedPreferences. ZERO network calls. Instant.
    - `RemoteConfig.fetchBackground()` — called AFTER `runApp()`, fire-and-forget, NOT awaited.
      Has 4-second timeout. Hits Oracle `/api/config`.
    - Legacy `fetch()` shim exists for backwards compatibility — do not remove it.

33. **`AppConstants.jazzDriveDeltaUrl` must remain a mutable `static String`** — NOT a getter.

---

## Sync Timeout Rules (TASK-042 — added 2026-06-08)
34. **`connectTimeout` in `api_client.dart` must stay at 6 seconds or less.**
35. **The `.timeout(Duration(seconds: 5))` on `CatalogApi.getVersion()` must stay.**
    File: `lib/core/db/sync_service.dart`. DO NOT remove.

---

## Delta Folder Purge Rules (TASK-041 — added 2026-06-08)
36. **Always purge the JazzDrive delta folder BEFORE uploading a new delta.json.**
37. **`list_all_files_in_folder(account_id, folder_id)` in `jazzdrive.py` uses `/media/file?action=get`**
    — this is the correct endpoint for `mediatype="file"` items (delta.json/.txt uploads).
    `/media/video` returns ZERO results for non-video items — do NOT use it for file-type listing.
    Soft-delete (`trash_files`) returns false-positive success for `media_type="file"` but does NOT
    remove files. Always use `delete_files_permanent()` to clean old delta files.

---

## End of Session (every session, no exceptions)
25. Mark all completed tasks ✅ DONE in `agent-hub/TASKS.md`
26. Append session summary to `agent-hub/history/TASK_LOG.md`
27. Update `BUG_TRACKER.md` with any new bugs found or fixed
28. Update `AGENT_HANDOFF.md` current state section
29. Update `HANDOFF_NEXT.md` with what was done + what's next
30. Update `PLAYER_SPEC.md` if any player architecture changed
31. Push ALL doc changes to GitHub before ending session
