# agent-hub/OPERATIONS.md — How to Work on RaddFlix

This is the practical "how do I actually do it" guide: connecting to GitHub, connecting to
Oracle, reading/editing files, and pushing changes safely. Read `AGENT_PROMPT.md` first for the
overall doc map — this file is the hands-on companion to it.

For deep server provisioning (fresh VPS setup, nginx/supervisor configs, DB migration between
servers) see `agent-hub/SERVER_SETUP.md` — that file is the full reference; this file is the
day-to-day workflow.

---

## 1. The two systems you'll touch

| System | What it is | How you reach it | Credential needed |
|---|---|---|---|
| **GitHub** | Source of truth for all code (`raddclub/raddflix-app`) | `git` over HTTPS, or the GitHub REST API | `GITHUB_TOKEN` |
| **Oracle VPS** | Production server running the Flask backend | SSH (`ssh ubuntu@92.4.95.252`) | `ORACLE_SSH_KEY` |

These are separate systems and separate credentials. Pushing to GitHub does **not** update
Oracle — Oracle only updates when you `git pull` on the server (via `push_to_oracle.sh` or by
hand). Nothing auto-deploys.

Both values live in this project's **Configurations** section (sidebar, shared env vars) — a
deliberate choice by the repository owner, not the Secrets store. Even though Configurations
values aren't masked the way Secrets are, treat them with the same care in practice: never print
their values in chat, never paste them into a file, never log them. Every script in this repo is
written to keep them out of shell history and out of files that get committed.

---

## 2. Getting the code / "loading files"

You should always be working from a **real local clone**, not a "fetch file over the API, patch
a string, push back" pattern. The API-patch pattern hides diffs and makes mistakes easy to miss
— it was used early in this project's history and caused real bugs (see `agent-hub/CONTEXT.md`
"GitHub Push Method" note, which is now superseded by this section: prefer a real clone whenever
one is available in your environment).

**If you already have a local clone** (e.g. this workspace has `raddflix-app/` checked out):
- Just read/edit files directly with your normal file tools. No special "loading" step.
- Check what's changed at any time: `git status`, `git diff`.

**If you need to clone fresh:**
```bash
git clone https://x-access-token:${GITHUB_TOKEN}@github.com/raddclub/raddflix-app.git raddflix-app
cd raddflix-app
```
Do this once per environment. Do not re-clone into a folder that already has a working copy —
you'll end up with two divergent trees.

**If a real git clone genuinely isn't available** (rare — e.g. a sandboxed context with only
HTTP access), fall back to the GitHub Contents/Trees API. See section 4b below. Treat this as
the exception, not the default.

---

## 3. Editing files

Nothing special here — edit files in the clone with whatever tools your environment provides
(text editor, `sed`, IDE, etc.). A few project-specific rules that matter when editing:

- Check `agent-hub/RULES.md` before touching player, auth, or DB code — it lists hard "never do
  X" rules that have caused real regressions (e.g. don't upgrade `sqflite_sqlcipher` past
  `3.1.0+1`, don't use `db.get_setting()` — it doesn't exist).
- Check `agent-hub/TASKS.md` for anything already IN PROGRESS before starting new work, to avoid
  colliding with another session.
- After any change, before committing: run `git diff` and actually read it. Don't stage/commit
  blind, especially after any programmatic string-replace edit — a bad replacement pattern once
  duplicated an entire file (see `AGENT_HANDOFF.md`, "Root-Cause: search_screen Corruption").

---

## 4. Pushing changes to GitHub

### 4a. Preferred: the helper script

```bash
bash push_to_github.sh                      # commits everything staged + pushes
bash push_to_github.sh "your commit message"
DRY_RUN=1 bash push_to_github.sh            # preview only — no commit, no push
```

What it does, in order: verifies `GITHUB_TOKEN` works and has push access to this repo →
confirms the local folder is actually this repo's git checkout (refuses to run otherwise) →
stages changes and blocks the commit if it contains conflict markers or secret-looking files
(`.env`, `.pem`, private keys) → fetches from GitHub first and refuses to push if your local
copy is behind (won't silently clobber newer remote work) → commits → pushes using the token as
a per-request header only (never written to `.git/config`, so it can't leak by someone reading
that file later).

If it fails, it tells you exactly why (missing tool, bad token, no push access, diverged
branch, dirty merge, etc.) and stops — it does not attempt partial recovery or force-push.

### 4b. Manual git (equivalent, if you want to do it by hand)

```bash
cd raddflix-app
git add -A
git commit -m "describe the change"
git fetch origin
git status   # confirm you're not behind origin/main
git push origin HEAD:main
```
Use a token-scoped URL only in-memory, never saved to `.git/config`:
```bash
git -c http.extraHeader="Authorization: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)" push origin HEAD:main
```

### 4c. Fallback: GitHub REST API (no local git available)

Only use this when a real clone isn't possible. Steps: get the current commit SHA for `main` →
create a blob for each changed file (`git/blobs`) → create a new tree from the base tree plus
those blobs (`git/trees`) → create a commit pointing at that tree (`git/commits`) → move the
`main` ref to the new commit (`git/refs/heads/main`, `PATCH`). This lets you push multiple files
as **one atomic commit** instead of one commit per file. Always re-read the current ref SHA
immediately before you start — a stale SHA causes a 409 conflict if anything else pushed in the
meantime. All calls need `Authorization: token $GITHUB_TOKEN`.

---

## 5. Connecting to Oracle & deploying

### 5a. One-off SSH command (health check, quick look)

```bash
ssh -i <path-to-key> -o StrictHostKeyChecking=accept-new ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
# expect: {"ok":true,"version":"3.0.0"}
```
The key itself comes from the `ORACLE_SSH_KEY` Configuration value, which is PEM text, not a
file path — you have to materialize it to a temp file first (see below) rather than pasting it
inline.

### 5b. Preferred: the helper script (pulls latest code + restarts + verifies)

```bash
bash push_to_oracle.sh
```
Always push to GitHub first — this script deploys whatever is currently on `origin/main` /
`origin/HEAD`, not your local uncommitted changes.

What it does: restores the `ORACLE_SSH_KEY` Configuration value to a temp file (auto-deleted on exit, even on Ctrl-C or
a crash) → tests the SSH connection → confirms `/opt/jazzmax` is a valid git repo before
touching it → pulls with fast-forward only (refuses to auto-merge over a dirty or diverged
server tree — you'd have to SSH in and fix that by hand, since it usually means someone edited
files directly on the server) → installs any new Python deps → restarts the `raddflix_radd`
supervisor service → confirms it actually reports `RUNNING` → hits `/api/app/version` and
confirms it responds before declaring success. If any step fails, it stops and tells you exactly
what to check — it never silently reports success.

### 5c. Manual deploy (equivalent, by hand)

```bash
# materialize the key once
node -e "
const raw = process.env.ORACLE_SSH_KEY;
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
require('fs').writeFileSync('/tmp/oracle_key', m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n', {mode:0o600});
"
SSH="ssh -i /tmp/oracle_key -o StrictHostKeyChecking=accept-new"

$SSH ubuntu@92.4.95.252 "cd /opt/jazzmax && git status --porcelain"   # must be empty before pulling
$SSH ubuntu@92.4.95.252 "cd /opt/jazzmax && git pull --ff-only"
$SSH ubuntu@92.4.95.252 "cd /opt/jazzmax && pip3 install -r requirements.txt -q --break-system-packages"
$SSH ubuntu@92.4.95.252 "sudo supervisorctl restart raddflix_radd && sudo supervisorctl status raddflix_radd"
$SSH ubuntu@92.4.95.252 "curl -s http://localhost:5000/api/app/version"

rm -f /tmp/oracle_key   # always clean up
```

### 5d. Things that will bite you on Oracle specifically

- If `git status --porcelain` on the server is non-empty, something was edited directly on the
  box — do not `git pull` over it blindly; SSH in, inspect, and decide whether to stash/discard.
- `git pull` alone can silently create a merge commit on the server if history diverged. Always
  use `--ff-only` (both scripts and the manual steps above do this) so a divergence stops you
  instead of quietly rewriting server history.
- Restarting `raddflix_radd` briefly drops active sessions — confirm with the user before
  restarting during active hours, per `AGENT_PROMPT.md`'s "ask first" rules.
- `sudo` on the server must work non-interactively (`sudo -n`) for the scripts to succeed. If it
  prompts for a password, the script will fail fast instead of hanging — that means passwordless
  sudo for `supervisorctl` needs to be (re)configured on the box.

---

## 6. Order of operations for a typical change

1. Check `agent-hub/TASKS.md` for open work, mark your task ⏳ IN PROGRESS.
2. Edit files in the local clone (section 3).
3. `git diff` — read it.
4. `bash push_to_github.sh "describe the change"` (section 4a).
5. If the change affects the live backend (not just the Flutter app or docs): confirm with the
   user, then `bash push_to_oracle.sh` (section 5b).
6. Mark the task ✅ DONE in `agent-hub/TASKS.md`, update `AGENT_HANDOFF.md`'s current-state
   section, append a line to `agent-hub/history/TASK_LOG.md`, and add a `agent-hub/memory/`
   entry if you learned something non-obvious.

---

## 7. Quick troubleshooting index

| Symptom | Likely cause | Where to look |
|---|---|---|
| `push_to_github.sh` fails "behind origin" | Someone else pushed since you last pulled | `git pull --rebase origin main`, resolve, retry |
| `push_to_oracle.sh` fails "dirty worktree" | Server files edited directly (not via git) | SSH in, `git status`/`git diff`, decide stash vs. discard |
| `push_to_oracle.sh` fails "not a fast-forward" | Server branch diverged from GitHub history | SSH in, inspect `git log`, resolve manually — do not force |
| API doesn't respond after restart | Deploy broke the server, or slow startup | `sudo supervisorctl tail raddflix_radd`, check `data/logs/raddhub.log` |
| `push_to_github.sh` fails "invalid or expired" | `GITHUB_TOKEN` Configuration value rotated/expired | Regenerate PAT with `repo` scope, update the value in Configurations |
| "Cannot connect to Oracle" | Key malformed, IP unreachable, or firewall | Re-check the `ORACLE_SSH_KEY` Configuration value's format, confirm `92.4.95.252` is reachable |
