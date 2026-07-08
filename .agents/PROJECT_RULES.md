# PROJECT_RULES.md — Non-Negotiable Rules

> All 10 rules apply to every agent, every session. No exceptions.

---

### Rule 1 — No git commands that write to GitHub

Never run `git commit`, `git push`, `git checkout -b`/branch-switching, `git reset`, or any other
git command that changes history or pushes to `origin`, from the shell. **Read-only local git
commands are fine and expected** (`git status`, `git log`, `git diff`, `git rev-parse HEAD`) — use
them freely to inspect your own working tree. The actual push to GitHub `main` always goes through
`bash auto_commit.sh "message" file1 [file2...]` (see `AGENT_PROMPT.md` Rule 42), which uses the
**GitHub Trees API** under the hood — no manual API scripting needed, just call the script.

There is intentionally no `origin` remote configured in the local clone — this is what forces the
API-based push path. To check whether local work is in sync with GitHub, query the REST API
(`curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/raddclub/raddflix-app/commits/main`),
not `git fetch origin`.

Why: a direct `git push` from the shell bypasses `auto_commit.sh`'s pending-log bookkeeping
(`agent-hub/UNPUSHED.txt`) and the recovery path (`recover_push.sh`) that exists for when an agent
session ends mid-edit. The GitHub API path via the script is atomic, auditable, and always works.

---

### Rule 2 — Never commit secrets

`GITHUB_TOKEN`, `ORACLE_SSH_KEY`, and any other credentials exist only in Replit Secrets.
The SSH key lives at `/tmp/oracle_key` during a session — it is created from the env var
at session start and disappears when the container restarts.

Never write secrets into any file that gets committed to GitHub.

---

### Rule 3 — Never touch Oracle destructively without user approval

Safe (always OK without asking):
- Read commands: `curl`, `tail logs`, `supervisorctl status`
- Viewing files: `cat`, `ls`

Requires explicit user approval:
- Any file modifications on Oracle
- Database changes
- Service configuration changes

The safe server update sequence (only after approval) is exactly what `bash push_to_oracle.sh`
(repo root) does — use the script rather than typing the sequence by hand, since it also refuses
to proceed on a dirty worktree or a non-fast-forward branch instead of silently stashing over
uncommitted server-side changes:
```
cd /opt/jazzmax && git fetch origin && git merge --ff-only origin/HEAD && sudo supervisorctl restart raddflix_radd
```
**Oracle does not auto-deploy on GitHub push.** The script must be run explicitly every time, and
again at the end of any session with multiple commits — see `agent-hub/RULES.md` Rule 44.
Always verify success afterward with `git rev-parse HEAD` on the server, compared against the
GitHub `main` SHA — don't rely on the script's own stdout alone if verifying a past deploy.

---

### Rule 4 — Never upgrade sqflite_sqlcipher

It is pinned at version `3.1.0+1` in `pubspec.yaml`. The SQLCipher Dart package
changed its key derivation API after this version. Upgrading makes the encrypted
SQLite database unreadable (key mismatch = blank app on every user's device).

If pubspec.yaml shows a different version, revert it to `3.1.0+1` immediately.

---

### Rule 5 — Debug code must be behind kDebugMode

Any diagnostic screen, logger, or testing tool must be wrapped:
```dart
if (!kDebugMode) return const SizedBox.shrink();
```

**The gate alone is not enough — the file also needs the import**, or the build breaks instead of
compiling:
```dart
import 'package:flutter/foundation.dart' show kDebugMode;
```
`package:flutter/material.dart` does not reliably re-export `kDebugMode`. This has silently broken
2 separate CI builds in the past because nobody checked the GitHub Actions run status after pushing
(see `agent-hub/RULES.md` Rule 43 and Rule 46). After adding any `kDebugMode` gate, grep the file
for this import before pushing, and check the Actions run conclusion afterward — don't assume.
Flutter's AoT compiler strips `kDebugMode`-gated code entirely from release APKs.
This means debug tools have zero surface area in production.

---

### Rule 6 — XOR padding fix must always exist

In `request_encoder.dart`, the decode method must always contain:
```dart
final pad = (4 - b64.length % 4) % 4;
b64 += '=' * pad;
```
The Oracle server uses `rstrip(b"=")` which strips 1–2 base64 padding characters.
Without this fix, `base64Url.decode` throws `FormatException` on every API response.
Removing or "cleaning up" this code breaks the entire app.

---

### Rule 7 — VideoController config restriction

Never add `androidAttachSurfaceAfterVideoParameters: true` to the `VideoController`
options. It causes a 3–5 second black screen before video plays on physical Android
devices. The bug is in the media_kit library's surface lifecycle on Android.

---

### Rule 8 — Append to TASK_LOG after every session

Before ending a session, push a summary to `agent-hub/history/TASK_LOG.md`.
Format:
```markdown
## Session YYYY-MM-DD
- What you did
- Files changed (path, what changed)
- Bugs fixed (with IDs)
- State at end of session
```
This is how the next agent knows what happened.

---

### Rule 9 — Always fetch fresh SHA before pushing

A cached SHA from a previous session or an earlier commit in the same session
will cause a 422 "SHA mismatch" error. Always call `getSha(path)` immediately
before calling `putFile(path, ...)` in the same script run.

---

### Rule 10 — Test Oracle via SSH tunnel only

Port 5000 on Oracle is bound to `localhost` only — it is NOT publicly accessible.
Always test like this:
```bash
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "curl -s http://localhost:5000/api/..."
```
Never try to hit `http://92.4.95.252:5000/...` directly — it will time out.
