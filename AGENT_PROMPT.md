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

1. **Verify secrets are present.** Check that `GITHUB_TOKEN` and `ORACLE_SSH_KEY` exist in
   this environment's Secrets.

   > **Why secrets may be missing — read this first:**
   > Replit Secrets are **per-Replit environment**. They are NOT shared between Repls
   > automatically. Every time a new Replit is created (a new agent session, a fork, etc.),
   > its secrets store starts empty even if the same secrets exist in another Replit.
   > This is expected Replit behaviour — it is not a bug.
   >
   > **If `GITHUB_TOKEN` or `ORACLE_SSH_KEY` are missing, do NOT stop and wait.**
   > Instead, tell the human exactly this:
   >
   > ---
   > **Action needed — add secrets to this Replit:**
   > This is a fresh Replit environment. Secrets don't carry over automatically between Repls.
   > Please add the following to this Replit's Secrets panel (not in chat):
   > - `GITHUB_TOKEN` — your GitHub personal access token (repo scope)
   > - `ORACLE_SSH_KEY` — the private SSH key for the Oracle VPS (the full key including header/footer lines)
   >
   > Steps: open the Replit sidebar → click the 🔒 **Secrets** tab → add each key with its value.
   > Once both are added, tell me and I'll continue with the clone.
   > ---
   >
   > After the human confirms the secrets are added, continue to step 2.
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

Older one-off audit reports and superseded handoff files have been deleted (2026-07-06 cleanup).
There is no `archive/` folder anymore — do not recreate one. If you think something is worth
preserving "for reference," it belongs as a section in `agent-hub/memory/` (a topic file) or
`AGENT_HANDOFF.md`, not as a standalone dated file.

## Working on this project — normal workflow

- Work from a real local clone of `raddclub/raddflix-app` (checked out into the workspace), edit files
  with normal file-editing tools, and commit/push with normal `git` commands. Do not use an in-memory
  "read from GitHub, patch a string, push back" pattern — it hides diffs from the person you're working
  with and makes mistakes hard to catch.
- **For EVERY file change — follow the 3-step workflow (Rule 42):**
  1. `bash log_pending.sh "message" file1 [file2...]` — logs intent BEFORE editing
  2. Edit the file(s)
  3. `bash auto_commit.sh "message" file1 [file2...]` — pushes immediately AFTER editing
  If the agent hits its context limit between steps 2 and 3, the user runs `bash recover_push.sh`
  to push all logged-but-unpushed changes automatically. See `agent-hub/RULES.md` Rule 42.
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
