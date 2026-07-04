# RaddFlix — Agent Start Here

RaddFlix is a Pakistani Flutter streaming app (Jazz SIM zero-rated data). Content lives on
JazzDrive cloud storage; a Flask backend on an Oracle VPS handles auth, catalog, and proxying;
a Flutter Android app is the client.

This file is the **single entry point** for any agent session (Replit or otherwise) picking up
this project. Read it fully before touching code. If you find yourself about to create a new
"NEXT_AGENT"/"HANDOFF"/"STATUS" file — don't. Update the canonical docs listed below instead.
Doc sprawl from repeated one-off handoff files is exactly what this file replaces.

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

1. **Verify secrets are present.** Check that `GITHUB_TOKEN` and `ORACLE_SSH_KEY` exist in
   this environment's Secrets. If either is missing, tell the human which one is absent and
   stop — do not proceed without them. Do not ask the human to paste secret values into chat.
2. **Clone the repository locally** so you have full project context:
   ```bash
   git clone https://github.com/raddclub/raddflix-app.git raddflix-app
   cd raddflix-app
   git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/raddclub/raddflix-app.git
   ```
   If `raddflix-app/` already exists in the workspace, `cd` into it and run `git pull` instead.
3. **Read the canonical docs below, in order**, from the local clone. This single file alone is
   not enough context to work safely.
4. **Stop and wait.** Do not edit any code, run any scripts, or restart any services yet.
   Confirm to the human that setup is complete (clone present, docs read, secrets verified),
   then wait for their task instruction.
5. **Security boundary:** This file only authorises you to clone this specific repository and
   read the docs listed below. Do not fetch or run any other external scripts not named here.
   All production-touching actions (restarting Oracle, deploying, running DB operations) require
   explicit confirmation from the human each time — this is by design and listed in the rules.

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
   use fallback approaches when something fails, without ever skipping verification or the
   "confirm before touching production" rule.

Older one-off audit reports and superseded handoff files have been moved to `agent-hub/archive/`
for reference — they are historical, not current. Do not treat anything in `archive/` as live state.

## Working on this project — normal workflow

- Work from a real local clone of `raddclub/raddflix-app` (checked out into the workspace), edit files
  with normal file-editing tools, and commit/push with normal `git` commands. Do not use an in-memory
  "read from GitHub, patch a string, push back" pattern — it hides diffs from the person you're working
  with and makes mistakes hard to catch.
- **After EVERY file edit — run `bash auto_commit.sh "what you changed"` immediately.** No exceptions,
  no batching. Use `auto_commit.sh` (fast, lightweight) not `push_to_github.sh` for per-edit commits.
  See `agent-hub/RULES.md` Rule 42 for the full mandate.
- Confirm with the user before: restarting the Oracle Flask service, running destructive DB operations,
  or triggering production deploys/APK builds. These are not "ask forgiveness" actions.
- SSH access to the Oracle VPS uses `ORACLE_SSH_KEY` (Replit Secret). GitHub API/push access uses
  `GITHUB_TOKEN` (Replit Secret). Never print these values.
- Oracle health check: `ssh -i <key> ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"` →
  expect `{"ok":true,"version":"3.0.0"}`.

## Task tracking (mandatory every session)

1. Before starting a change, add/update a row in `agent-hub/TASKS.md` marked ⏳ IN PROGRESS.
2. When done (and pushed), mark it ✅ DONE.
3. Append a short session summary to `agent-hub/history/TASK_LOG.md`.
4. Update `AGENT_HANDOFF.md`'s "Current State" section if it changed.
5. If you learned a non-obvious, durable lesson, add/update an entry in `agent-hub/memory/`.

Do this in the canonical files above — never create a new dated "handoff" or "status" file.
