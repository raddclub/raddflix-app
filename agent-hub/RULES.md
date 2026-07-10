# agent-hub/RULES.md — Non-Negotiable Agent Rules
Last updated: 2026-07-08 (added Rules 43-46 — deploy verification gaps found during a full audit)

## Startup (every session, no exceptions)
1. Read `AGENT_PROMPT.md` (repo root) — the single entry point, links everything below.
2. Read `AGENT_HANDOFF.md` (current state) + last 80 lines of `agent-hub/history/TASK_LOG.md`.
3. Read `agent-hub/TASKS.md` — continue any OPEN tasks before starting new work.
4. Check `agent-hub/memory/MEMORY.md` for durable lessons relevant to the task.

Note: `BUG_TRACKER.md` referenced in older docs does not exist — tracked bugs live in `TASKS.md`.

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


## Sync Timeout Rules (TASK-042 — added 2026-06-08)
34. **`connectTimeout` in `api_client.dart` must stay at 6 seconds or less.**
35. **The `.timeout(Duration(seconds: 5))` on `CatalogApi.getVersion()` must stay.**
    File: `lib/core/db/sync_service.dart`. DO NOT remove.


---

## Duplicate Upload Guard Rules (TASK-048 → TASK-051)
40. **Every direct `_upload_file()` call site must have a JazzDrive-side duplicate guard.**
    Check `/media/video?parentId=FOLDER_ID&folderId=FOLDER_ID` for the target filename before
    calling `_upload_file()`. If found: record existing remote_id, skip upload, return.
    Both guarded paths are in `uploader.py`:
    - `upload_to_jazzdrive()` guard at ~L1287
    - `_upload_pending()` guard at ~L1791
    Verified safe: `assets.py:process_title_poster` (early-return if poster_share_url exists),
    `keepalive.py` (intentional unique-name heartbeat file), `library.py:push-poster-to-jd`
    (delete-before-upload guard added TASK-051).
    Any NEW direct `_upload_file()` call must add this guard.


## Auto-Commit Rule (MANDATORY — added 2026-07-04)
**Rule 42: Follow the 3-step log → edit → push workflow for EVERY file change.**

**Step 1 — BEFORE editing:** log the intent
```bash
bash log_pending.sh "describe what you will change" path/to/file.dart [more files...]
```
This writes to `agent-hub/UNPUSHED.txt`. If the agent hits its context limit before pushing,
the user runs `bash recover_push.sh` to push everything from that log automatically.

**Step 2 — Edit the files** (using normal write/edit tools)

**Step 3 — AFTER editing:** commit and push immediately
```bash
bash auto_commit.sh "describe what you changed" path/to/file.dart [more files...]
```
On success, `auto_commit.sh` clears `UNPUSHED.txt` automatically.

**Rules within Rule 42:**
- NEVER skip a commit — even a 1-line typo fix goes through all 3 steps
- NEVER batch edits across multiple files before pushing — one logical change = one commit
- `push_to_github.sh` is for end-of-session doc pushes only — Rule 42 is for per-edit commits
- If the agent limit is hit between steps 2 and 3: user runs `bash recover_push.sh` — done

---

## End of Session (every session, no exceptions)
25. Mark all completed tasks ✅ DONE in `agent-hub/TASKS.md`
26. Append session summary to `agent-hub/history/TASK_LOG.md`
27. Update `AGENT_HANDOFF.md` current state section (this is the ONLY handoff file — do not create a new one)
28. Update `PLAYER_SPEC.md` if any player architecture changed
29. Update `agent-hub/memory/` if you learned a durable, non-obvious lesson
30. Push ALL doc changes to GitHub before ending session (use `push_to_github.sh` or `auto_commit.sh`)


---

## Dart/Flutter Rules (added 2026-06-18)

**Rule 39: `PlatformDispatcher` requires `dart:ui`.**
`import 'dart:ui' show PlatformDispatcher;` must be added explicitly.
`package:flutter/material.dart` does NOT re-export it in Flutter 3.22.3.
Forgetting this causes `Undefined name 'PlatformDispatcher'` → build fails for every commit.

**Rule 40: Verify DebugLogger methods exist before calling them.**
Before adding any `DebugLogger.methodName()` call to any file, confirm the method is
declared in `lib/core/debug/debug_logger.dart`. Past failures: 6 missing methods caused
2 consecutive build failures (run#27753380200, run#27753231660).
Current v2 method list: `log`, `logError`, `logWarn`, `logApi`, `logState`, `logTap`,
`logNav`, `logLifecycle`, `logFeature`, `logCrash`, `getLastLines`, `getRecent`,
`getFiltered`, `clearBuffer`, `getLogPath`, `copyToClipboard`, `flush`, `share`, `shareLogs`.

**Rule 41: Never parallel-push multiple commits to GitHub.**
Always push commits SEQUENTIALLY with ≥1.2s delay between each push.
Parallel PUT requests to the GitHub Contents API create branch tree SHA conflicts
(second push cannot resolve parent commit SHA while first is in-flight).

---

## Deploy Verification Rules (added 2026-07-08 — after catching a real gap)

**Rule 43: `kDebugMode` needs an explicit import — Rule 21 gating alone is not enough.**
Any file using `if (kDebugMode)` must have `import 'package:flutter/foundation.dart' show kDebugMode;`.
`package:flutter/material.dart` does not reliably re-export it. This has broken 2 separate CI builds
(`28886249595`, `28886554849`) silently — nobody noticed until a 3rd session checked run status.
**After adding any `kDebugMode` gate, grep the file for the foundation.dart import before pushing —
don't rely on visual review.**

**Rule 44: Oracle does not auto-deploy — redeploy against FINAL HEAD, not mid-session HEAD.**
`push_to_oracle.sh` only updates the server when explicitly run. If a session makes multiple commits
to `main` after an earlier Oracle deploy (even "docs-only" commits, since those can bundle a real
code file), the server is now stale relative to `main` and nobody notices unless someone diffs commit
SHAs. **Always run `push_to_oracle.sh` one final time at the end of a session that touched
`radd-hub/**`, and confirm via SSH `git rev-parse HEAD` that it equals the GitHub `main` SHA —
do not trust an earlier mid-session deploy.**

**Rule 45: There are two `hub/` directories — a dead one at repo root, and the real one at `radd-hub/hub/`.**
This affects more than template pushes (see Rule 39) — it also breaks SSH verification commands on
Oracle, since the server's git checkout mirrors this same repo layout and both directories exist
there too. A `grep`/`cat`/`diff` against bare `hub/...` on Oracle will silently return content from
the DEAD copy, giving a false sense that a fix is missing or present. **Confirm which file is live by
checking the supervisor config's `directory=` value first** (`sudo cat /etc/supervisor/conf.d/*.conf`)
— for `raddflix_radd` it is `/opt/jazzmax/radd-hub`, so the live file is always under
`radd-hub/hub/...`, never bare `hub/...`.

**Rule 46: A successful `git push` / GitHub Actions trigger does not mean the build succeeded.**
After any push touching `raddflix_flutter/**`, fetch the actual workflow run status via the GitHub
API (`GET /repos/.../actions/workflows/build-apk.yml/runs`) and check `conclusion == "success"`.
Do not consider Flutter-touching work complete just because the push itself returned 200.

**Rule 47: `auto_commit.sh` now runs `preflight_check.sh` automatically before every push that
touches a `.dart` file — do not bypass it without a reason.** (Added 2026-07-10 after a session
found `AppColors`-import and `const AppColors.error` mistakes from an earlier commit that had
gone unnoticed until a later session's CI check.) `preflight_check.sh` is a heuristic, not a real
compiler (no Flutter/Dart SDK is available in this environment — see Phase 0), so it only catches
the two known repeat-mistake classes: (1) a design-token class (`AppColors`, `AppRadius`,
`RaddRadius`, `RaddSpace`, `RaddTheme`, `RaddType`, `RaddMotion`, `AppIcons`, `AppConstants`,
`AppRoutes`) referenced without its corresponding import, and (2) `const SomeStaticOnlyClass.x`
where the class has no const constructor (only static fields). `auto_commit.sh` aborts the push
if either pattern is found. `SKIP_PREFLIGHT=1 bash auto_commit.sh ...` bypasses it for a genuine
false positive — state why in the commit message when you do. **This does not replace Rule 46** —
CI is still the only real compiler check; this just avoids paying for a red build on mistakes we
already know how to catch for free. When adding a new `Radd*`/`App*` token class to the design
system, add it to the `REQUIRES_IMPORT` map in `preflight_check.sh` too.
