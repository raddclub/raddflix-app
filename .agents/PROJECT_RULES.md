# PROJECT_RULES.md — Non-Negotiable Rules

> All 13 rules apply to every agent, every session. No exceptions.
> Last updated: 2026-06-07

---

### Rule 1 — No git shell commands

Never run `git add`, `git commit`, `git push`, `git checkout`, or any other
git command from the shell. Always use the **GitHub Contents API** via Node.js.

The correct pattern:
```js
// GET sha → PUT file with {message, content: base64, sha}
// See AGENT_HANDOFF.md for the full working code
```

Why: git commands in Replit can corrupt state and are blocked by the agent sandbox.
The GitHub API is atomic, auditable, and always works.

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

The safe server update sequence (only after approval):
```
cd /opt/jazzmax && git stash && git pull origin main && git stash pop && supervisorctl restart raddflix_radd
```

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

---

### Rule 11 — Never swap the two night-mode callbacks in _ControlsOverlay

`_ControlsOverlay` has two distinct night-mode callbacks:
- `onToggleCinematic` → dims the controls overlay via `Opacity(opacity: _cinematicOpacity)`
- `onToggleNightMode` → applies a blue-light colour filter via `_applyVideoFilters()`

The Quick Bar "Night" slot must be wired to `onToggleNightMode`.
The More Sheet item 11 "Night Mode" must be wired to `onToggleCinematic`.
Cross-wiring them silently applies the wrong effect — the symptom is subtle and hard to debug.

---

### Rule 12 — VideoEnhanceSuite cinematic toggle must be bidirectional

When reading back the result map from `_openVideoEnhanceSuite()`:
```dart
// WRONG — only fires when new value is true; toggle-off is silently dropped
if (map['cinematicMode'] as bool? ?? false) _toggleCinematic();

// CORRECT — compare against current state, toggle only when they differ
final newCinematic = map['cinematicMode'] as bool? ?? _cinematicMode;
if (newCinematic != _cinematicMode) _toggleCinematic();
```

---

### Rule 13 — A-B loop controller and UI state must stay in sync

Any widget that sets A-B loop points (ClipTrimmer, AbLoopPanel, etc.) MUST call
`_abLoop.setA(d)` / `_abLoop.setB(d)` alongside updating the `_abLoopStart` / `_abLoopEnd`
state vars. Updating only the state vars leaves `_abLoop.isActive = false`, which breaks
both the `maybeSeekBack()` enforcement and the seek bar A/B markers.
