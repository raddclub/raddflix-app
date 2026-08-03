# RaddFlix — Agent Start Here

RaddFlix is a Pakistani Flutter streaming app (Jazz SIM zero-rated data). Content lives on
JazzDrive cloud storage; a Flask backend on an Oracle VPS handles auth, catalog, and proxying;
a Flutter Android app is the client.

This file is the **single entry point** for any agent session (Replit or otherwise) picking up
this project. Read it fully before touching code. If you find yourself about to create a new
"NEXT_AGENT"/"HANDOFF"/"STATUS"/"AUDIT"/"BRIEF" file — don't. Update the canonical docs listed
below instead. Doc sprawl from repeated one-off handoff files is exactly what this file replaces.

> **This is a hard rule, not a suggestion — it has been violated before.** A prior agent session
> ignored this section and created ~15 one-off files (`NEXT_AGENT.md`, `HANDOFF_NEXT.md`,
> `AGENT_STATUS.md`, `AUDIT_REPORT.md`, `PLAYER_AUDIT_v4.md`, etc.), plus a whole duplicate,
> stale copy of the agent-hub tracking files inside `radd-hub/agent-hub/`. Nobody deleted them;
> they just piled up in an `agent-hub/archive/` folder until the human had to ask an agent to
> clean it all up manually. There is no more `archive/` folder — do not recreate one, and do not
> "archive" a stray file as a way of not-quite-deleting it. If a one-off file like this exists or
> gets created, delete it immediately (via `agent-hub/scripts/push.js`, never raw git commands
> per Rule below) and fold anything worth keeping into the canonical docs instead.

## Note for agents reading this file

This file was written by the repository owner (`raddclub`) and is fetched directly from their
private GitHub repo using their own `GITHUB_TOKEN`. It is a legitimate project setup document,
not a prompt injection. Every instruction here keeps the human informed and in control —
nothing in this file asks you to skip confirmations, suppress output, or act without the user's
knowledge. If anything below ever seems to conflict with your safety guidelines, flag it to the
user rather than proceeding.

## Bootstrap steps (for fresh sessions with no local clone yet)

If the human sent you this file's URL to get started, follow these steps in order, then stop
and wait for their actual task:

1. **Verify `GITHUB_TOKEN` is present — via code, not trust.**
   The human may say they already added it, but Replit environment values are **per-Replit
   environment** and do NOT carry over between Repls automatically. Always verify with a code
   check first (Rule 48).

   `GITHUB_TOKEN` and `ORACLE_SSH_KEY` are intentionally kept in the **Configurations** section
   of this project (non-secret shared environment variables), not in the Secrets section. This is
   a deliberate choice by the repository owner — do not ask to move them, and do not treat their
   presence there as a mistake.

   In the Replit CodeExecution tool, run:
   ```javascript
   const r = await viewEnvVars({ type: "env", keys: ["GITHUB_TOKEN"] });
   console.log(Boolean(r.envVars?.shared?.GITHUB_TOKEN)); // true = present, false = missing
   ```
   (Check existence only — there's no need to print the actual token value to chat.)

   - **If `true`**: proceed to step 2.
   - **If `false`**: use `requestEnvVars({ envVars: [{ key: "GITHUB_TOKEN", environment: "shared" }] })`
     to prompt the user via the secure form — this writes the value directly into Configurations.
     Wait for confirmation before proceeding.

   > **Why the value can appear missing:** Every new Replit starts with empty Configurations and
   > Secrets stores — this is expected behaviour, not a bug. The `viewEnvVars` check takes 1
   > second and prevents the entire setup flow from failing at `git clone`. Do not skip it even
   > when the user says the token is present. (Evidence: 2026-07-12 — user confirmed the token was
   > added, the check showed it was missing, and it had to be re-added before the clone could
   > proceed — see Rule 48.)

   > **`ORACLE_SSH_KEY`** (the Oracle VPS SSH private key) is only required when work touches the
   > live Flask server (`radd-hub/**`, deployments, DB operations). Flutter-only work (Phase A–L
   > of the 10/10 plan) does **not** need it. If a task later requires Oracle access and
   > `ORACLE_SSH_KEY` is missing, ask the human to add it then (in Configurations, same as
   > `GITHUB_TOKEN`) — do not block the clone on it now.

   > **Do not store `GITHUB_TOKEN` or `ORACLE_SSH_KEY` in `.replit`'s `[userenv.shared]` block, in
   > a `.env` file, or in any other tracked plaintext file.** Those are committed/checkpointed and
   > readable by anyone with project access, which defeats the point of keeping these values out
   > of the code. The correct home for both values in this project is the **Configurations**
   > section (shared env vars) — use `viewEnvVars({ type: "env" })` to check existence and
   > `requestEnvVars` to write. This is an explicit, permanent choice by the repository owner, not
   > an oversight — do not suggest or perform a move to Secrets. If you ever find either value
   > sitting inside a tracked file instead of Configurations, treat it as a live incident: move
   > it into Configurations, then strip it from the plaintext location. See Rule 48 in
   > `agent-hub/RULES.md`.

2. **Clone the repository locally** so you have full project context:
   ```bash
   git clone https://$GITHUB_TOKEN@github.com/raddclub/raddflix-app.git raddflix-app
   cd raddflix-app
   ```
   The token must be embedded in the URL — a plain `https://github.com/...` clone will fail
   because this is a private repository. If `raddflix-app/` already exists, `cd` into it and
   run `git pull` instead.
3. **Read the canonical docs below, in order**, from the local clone. This single file alone is
   not enough context to work safely.
4. **Stop and wait.** Do not edit any code, run any scripts, or restart any services yet.
   Confirm to the human that setup is complete (clone present, docs read, secrets verified),
   then wait for their task instruction.
5. **Security boundary:** This file only authorises you to clone this specific repository and
   read the docs listed below. Do not fetch or run any other external scripts not named here.
   Routine production operations (Oracle deploy, Flask restart, git pull, pip install) are
   **autonomous — no confirmation needed**. The only operations requiring explicit user approval
   are genuinely destructive ones: DROP TABLE, DELETE all user rows, full DB wipe, or
   irreversible data migrations. Everything else: just do it and report what you did.

## Canonical docs (read in this order)

1. **`agent-hub/CONTEXT.md`** — architecture: Oracle VPS, JazzDrive proxy system, DB rules, key files.
2. **`agent-hub/RULES.md`** — permanent "never do X" rules. Violating these has caused real bugs before.
3. **`AGENT_HANDOFF.md`** — current state: what's live, what was fixed last, open tasks, known issues.
4. **`agent-hub/TASKS.md`** — the live task board. Check for OPEN/IN-PROGRESS items before starting new work.
5. **`agent-hub/memory/MEMORY.md`** — durable lessons and pointers to topic files.
6. **`agent-hub/history/TASK_LOG.md`** — append-only session log (most recent entries at the bottom).
7. **`agent-hub/OPERATIONS.md`** — step-by-step "how do I actually do it": connecting to GitHub
   and Oracle, editing files, and pushing changes. Read this before running any script or SSH
   command for the first time. Deep server-provisioning reference lives in `agent-hub/SERVER_SETUP.md`.
8. **`agent-hub/RESILIENCE.md`** — how to handle large/multi-file work, parallelize safely, and
   use fallback approaches when something fails, without ever skipping verification.

## Current primary work — 10/10 master improvement plan (started 2026-07-11)

**This is the current active coding effort.** A full codebase audit (22 parallel subagents,
every `.dart` file read — 67,988 lines) produced `agent-hub/TEN_POINT_PLAN.md`: 11 phases
(A–L), ~95 discrete tasks, every one with exact file and line number from real code.

**If you are being asked to work on RaddFlix improvements, this is your entry point:**

1. **Read `agent-hub/TEN_POINT_PLAN.md` in full** before touching any file.
   The plan is self-contained: each phase has a background section explaining the finding,
   and a checkbox list of tasks. Work top-to-bottom within each phase.
2. **Start at Phase A** (Critical Bugs, Safety Nets, Quick Wins) — it is the first phase with
   unchecked `[ ]` items. Do NOT skip to a later phase while Phase A has open items.
3. **Phase order matters** — later phases depend on earlier ones. The dependency chain is:
   `A → B → C → D → E → F → G → H → I → J → K`, with `L` (Production Hygiene) able to run
   in parallel with any phase since it is isolated single-file gating changes.
4. Follow Rule 42 (`log_pending.sh` → edit → `auto_commit.sh`) for every single file change.
   Check a checkbox `[x]` in `TEN_POINT_PLAN.md` only after the push has succeeded and the
   GitHub Actions CI build is confirmed green (Rule 46).
5. After every push touching `raddflix_flutter/**`, confirm CI status (Rule 46 + Rule 50).
   Always check `build-apk.yml`. If the push also touches `test/`, `pubspec.yaml`, or
   `.github/workflows/`, also check the separate `ci-tests.yml` job:
   ```bash
   curl -s -H "Authorization: token $GITHUB_TOKEN" \
     "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/runs?per_page=1"
   # Also run this if test/ or pubspec.yaml or .github/workflows/ was touched:
   curl -s -H "Authorization: token $GITHUB_TOKEN" \
     "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/ci-tests.yml/runs?per_page=1"
   ```
6. If `agent-hub/UNPUSHED.txt` has content when your session starts, run `bash recover_push.sh`
   before doing anything else — a previous agent's edit may not have landed yet.

### Phase summary (A = start here, L = can run any time)

| Phase | Topic | Key risk areas |
|---|---|---|
| **A** | **Critical bugs + session leaks + quick wins** | `edit_profile_screen.dart`, 3 providers, voice stub, fake bandwidth |
| B | Database: N+1, transactions, missing indexes | `sync_service.dart`, `local_db.dart` |
| C | Player: panel boilerplate, `_savePrefs` debounce, dead vars | `player_screen.dart` |
| D | Widgets: dedup RaddTextField, RaddSheet IndexedStack, RepaintBoundary | widget layer |
| E | Providers: split CatalogNotifier, globals to Riverpod | provider layer |
| F | Design system migration — remaining 70% of screens (28 tasks) | all screens |
| G | go_router, animation consolidation, dead series files, folder reorg | architecture |
| H | Test infrastructure | new `test/` directory |
| I | Dead code removal | 13 dead series files, layout_designer dead copy |
| J | Player God Class full decomposition into 5 controllers | `player_screen.dart` (9,458 lines) |
| K | Final performance polish | profiling pass |
| **L** | **Production Hygiene — debug leaks, raw exceptions, revenue bug** | 6 screens + player |

> **Phase L is high priority regardless of where you are in the other phases** — it contains
> user-visible security issues: the "Debug Logs" tile is shown to every user in the Profile
> screen right now (no gate), 6 screens display raw `e.toString()` exception strings to users,
> and a revenue-leak bug (`_isFree` stuck `true` on content transition) is confirmed in
> `player_screen.dart` L1099–1105. These are the Phase L items — read the plan for exact details.

## UI/UX design-system migration — secondary ongoing effort (started 2026-07-09)

This is a long-running background effort. Phases 2, 3, 4, 5 are ✅ COMPLETE (color/radius/spacing
token migration across most screens, CI green on every commit). Phase 0 (Flutter SDK/tooling
setup) and Phase 1 (Player HUD live-device measurement) are blocked on needing a real
Flutter emulator/device — no Flutter SDK in this Replit environment.

**If you are continuing UI/UX work specifically** (not the 10/10 plan):

1. Read `docs/AUDIT_UI_UX_REPORT.md` — original evidence-gathering audit.
2. Read `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` — full analysis and roadmap (background).
3. Read `agent-hub/UI_UX_MIGRATION_PLAN.md` — **the actual checklist.** Find the first phase
   with any unchecked `[ ]` item and continue there. Do not jump ahead.
4. Follow Rule 42 and Rule 47 (`preflight_check.sh` runs automatically on every `.dart` push).
5. `auto_commit.sh` runs `preflight_check.sh` automatically before every push touching `.dart`
   files — it blocks the two mistake patterns that broke CI in earlier sessions (missing
   design-token imports, invalid `const SomeStaticClass.field` syntax). `SKIP_PREFLIGHT=1`
   bypasses it for a genuine false positive only.

> **Do not treat the UI/UX migration as the primary effort unless the human explicitly asks for
> it.** The 10/10 plan (Phase A above) is the priority — it fixes crashes, data leaks, and
> revenue bugs that affect real users right now.

## Design system docs — Player architecture (read before touching the Player)

`docs/design-system/` contains a frozen v1.0 UI/UX design system plus an `IMPLEMENTATION_PLAN.md`.
**Do not trust older mental models of the Player's file layout.** A 2026-07-08 live import trace
found the Player is NOT ~50 external `widgets/player/*.dart` files as earlier drafts claimed —
it is 7 private classes defined inline inside `player_screen.dart`, plus 2 live external sheets
used by `PlayerSettingsScreen`, plus 2 shared helpers. 50 files in `widgets/player/` are dead
code, never imported anywhere (re-verified 2026-07-08, user declined deletion — they are
intentionally-parked unshipped features). Full corrected inventory:
`docs/design-system/09-migration-guide.md` ("Player — corrected 2026-07-08" section).

## Working on this project — normal workflow

- Work from a real local clone of `raddclub/raddflix-app` (checked out into the workspace) and edit
  files with normal file-editing tools. **Read-only local `git` commands are fine and expected**
  (`git status`, `git log`, `git diff`, `git rev-parse HEAD`) — use them to check your own working
  tree state. What you must NOT do is `git commit` / `git push` to GitHub directly, or an in-memory
  "read from GitHub, patch a string, push back" pattern — the actual push to `main` always goes
  through `auto_commit.sh` (GitHub Trees API), so every commit is atomic and auditable. There is no
  `origin` remote configured locally on purpose — this forces the API path. Verify sync state against
  GitHub with the REST API (`curl` + `GITHUB_TOKEN`), not `git fetch origin`.
- **For EVERY file change — follow the 3-step workflow (Rule 42):**
  1. `bash log_pending.sh "message" file1 [file2...]` — logs intent BEFORE editing
  2. Edit the file(s)
  3. `bash auto_commit.sh "message" file1 [file2...]` — pushes immediately AFTER editing
  If the agent hits its context limit between steps 2 and 3, the user runs `bash recover_push.sh`
  to push all logged-but-unpushed changes automatically. See `agent-hub/RULES.md` Rule 42.
- **Autonomous operations** — perform without asking: `push_to_oracle.sh`, Flask restart, git pull,
  `pip install`, supervisorctl commands, GitHub pushes, CI checks, APK builds. Do these and report
  what happened. The only operations that require explicit user approval are **irreversibly
  destructive** ones: DROP TABLE, DELETE all user rows, full database wipe, or permanent data
  migrations that cannot be rolled back.
- SSH access to the Oracle VPS uses `ORACLE_SSH_KEY` (Replit Configuration value, shared env
  var). GitHub API/push access uses `GITHUB_TOKEN` (same — Configuration value, not a Secret).
  Never print these values.
- Oracle health check: `ssh -i <key> ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"` →
  expect `{"ok":true,"version":"3.0.0"}`.
- **Oracle does NOT auto-deploy on push.** `push_to_oracle.sh` is the only thing that updates the
  live server, and it only runs when a human/agent explicitly runs it. If a session makes several
  commits to `main` that touch `radd-hub/**` (including a "just docs" commit that also happens to
  bundle a code file), a mid-session `push_to_oracle.sh` run does NOT cover commits made *after* it.
  **Run `push_to_oracle.sh` once more at the very end of the session** (against final HEAD) rather
  than trusting an earlier run — then confirm with `ssh ... "cd /opt/jazzmax && git rev-parse HEAD"`
  that it matches the GitHub `main` SHA exactly.
- **After ANY push that touches `raddflix_flutter/**`**, check the actual GitHub Actions run status
  via the API before calling the work done — do not assume a successful push means a successful
  build. CI failures are silent otherwise (this has happened twice — see `agent-hub/RULES.md`
  Rule 40 and the `kdebugmode-import-gotcha` memory file):
  ```bash
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/runs?per_page=1"
  ```
- **There are TWO `hub/` directories in this repo: a dead one at the repo root, and the real one at
  `radd-hub/hub/`.** This trips up path-based greps/edits both in the local clone AND on the Oracle
  server (which mirrors the same repo layout). Always target `radd-hub/hub/...` — never bare `hub/...`.
  Verify which file is actually live by checking the supervisor config's `directory=` value
  (`/opt/jazzmax/radd-hub`), not by guessing from the path that "looks right."

## Task tracking (mandatory every session)

1. Before starting a change, add/update a row in `agent-hub/TASKS.md` marked ⏳ IN PROGRESS.
2. When done (and pushed), mark it ✅ DONE.
3. Append a short session summary to `agent-hub/history/TASK_LOG.md`.
4. Update `AGENT_HANDOFF.md`'s "Current State" section if it changed.
5. If you learned a non-obvious, durable lesson, add/update an entry in `agent-hub/memory/`.

Do this in the canonical files above — never create a new dated "handoff" or "status" file.

## Android background play — what is correct in 2026 (Rule 44)

> Added 2026-08-03. Do NOT rely on training-data knowledge about background play — this rule
> is the ground truth for this project.

**The full architecture is already in this repo and works.** Do NOT rewrite or replace it.
Key facts every agent must know before touching background-play or notification code:

1. **Foreground service (`PlaybackService.kt`) is already implemented and complete.**
   It handles: MediaStyle notification, play/pause/seek transport controls, audio focus management
   (gain/loss/transient/duck), headphone unplug detection, lock-screen artwork loading, and
   broadcast forwarding to Flutter. Do NOT add a second foreground service.

2. **`POST_NOTIFICATIONS` must be declared in `AndroidManifest.xml` AND requested at runtime.**
   On Android 13+ (API 33+) the runtime request is required or the notification is invisible.
   As of 2026-08-03, `MainActivity.kt::onStart()` requests it automatically on first launch.
   The `<uses-permission>` is already in `AndroidManifest.xml` (line 28).

3. **`_backgroundAudio` defaults to `true` (since 2026-08-03).**
   Prior default was `false` — that was the root cause of "background play doesn't work".
   Persisted under `pref_bgaudio`. Do not change the default back to `false`.

4. **When app goes to background and `_backgroundAudio == true`:**
   - Flutter drops the video track (`vid=no`) immediately
   - `_notifyBgState()` calls `startBgPlayback` on the pip channel
   - `MainActivity.kt` starts the foreground service with the current position, poster URL, and title
   - `PlaybackService.kt` requests audio focus and begins a 1-second position refresh loop
   - Audio continues playing; notification shows in shade and lock screen

5. **On Android 13+ the foreground service type must be `mediaPlayback`.**
   Already declared: `android:foregroundServiceType="mediaPlayback"` in `AndroidManifest.xml`.
   Without this, `startForeground()` throws on API 34+.

6. **Do NOT use `WakeLock` while audio-only play is active.** The `WakeLockService` holds a
   screen wake lock only while the player is in foreground — it has an inactivity timeout.
   For background audio (screen off), wake lock is NOT needed and wastes battery. Audio focus
   + foreground service keeps audio alive with screen off on all modern Android versions.

7. **`READ_MEDIA_AUDIO` is a separate Android 13+ permission from `READ_MEDIA_VIDEO`.**
   `MediaStorePlugin.kt::requestPermission()` requests both together in a single system dialog.
   The Music tab calls `checkAudioPermission()` independently and previously showed a permission
   error when both `_load()` and `_loadMusic()` raced at `initState` (timing bug — fixed
   2026-08-03). Do NOT add a separate `requestAudioPermission` channel method; call the
   existing `requestMediaPermission` from the music tab if not granted.

## Before you end any session (mandatory self-audit)

Run this check before your final message, every session:

```bash
find . -iname "*.md" -newer AGENT_HANDOFF.md -not -path "./node_modules/*"
```

Any file this turns up that is NOT one of the canonical docs listed above must be either:
(a) merged into the relevant canonical doc, then deleted, or (b) deleted outright if it's a
throwaway note. Never leave a new standalone `.md` file behind "just in case" — that habit is
exactly what caused the doc-sprawl cleanup this rule was added after. If you're unsure whether
something is worth keeping, ask the human — don't default to keeping it.
