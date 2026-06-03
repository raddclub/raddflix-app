# PROJECT_RULES.md — RaddFlix Agent Non-Negotiable Rules
> Every agent on every account follows these. No exceptions.
> Last Updated: 2026-06-03

---

## THE 10 GOLDEN RULES

### Rule 1 — Read Before You Touch
Before changing any file:
1. Read `agent-hub/history/TASK_LOG.md` — know what was done
2. Read `AGENT_HANDOFF.md` — get full context
3. Read `.agents/tasks/BUG_TRACKER.md` — see bug status
4. Read the actual file on Oracle/GitHub before editing

### Rule 2 — Show Diff, Get Approval
- Write the proposed change
- Show the user exactly what will change (diff format)
- Wait for explicit approval
- Then commit

### Rule 3 — No Oracle Changes Without Approval
- Never `ssh ... "sudo supervisorctl restart"` without user saying OK
- Never edit files on Oracle directly — commit to GitHub, then pull on Oracle
- Exception: reading files on Oracle is always allowed

### Rule 4 — Fix in Priority Order
```
CRITICAL → HIGH → MEDIUM → LOW
```
Do not start a MEDIUM bug while a CRITICAL is open.

### Rule 5 — Never Break XOR Encoding
- XOR is active on both Flutter (XorInterceptor) and server (XorWsgiMiddleware + encode_response)
- If you change one side, you MUST change the other in the same commit
- Never disable XOR on one side only
- `encode_response()` accepts `status=` kwarg — always pass it

### Rule 6 — Always Update Documentation After Work
Every session must end with:
- [ ] `.agents/tasks/BUG_TRACKER.md` — update bug statuses
- [ ] `agent-hub/history/TASK_LOG.md` — append session entry
- [ ] `.agents/handoff/SESSION_YYYY-MM-DD.md` — write handoff file
- [ ] `agent-hub/REINCARNATION.md` — update IMMEDIATE STATUS section

### Rule 7 — No Secrets in Files
- `GITHUB_TOKEN` stays only in Replit Secrets
- `ORACLE_SSH_KEY` stays only in Replit Secrets
- Never hardcode IP addresses in production code
- Never commit `.replit` file changes to GitHub

### Rule 8 — Use GitHub API, Not Git Shell
```javascript
// Correct: GitHub API via Node.js
// Wrong: git remote add / git push (protected in Replit agent)
```
Multi-file commit pattern: blob → tree → commit → PATCH ref

### Rule 9 — SQLCipher Version is Locked
```yaml
sqflite_sqlcipher: 3.1.0+1  # NEVER change this
```
3.2.x breaks Gradle on Flutter 3.22 CI. Do not upgrade until CI uses Flutter 3.27+.

### Rule 10 — Verify Before Marking Done
A bug is NOT fixed until:
- Code committed to GitHub main
- CI Flutter Analyze passes
- Server restarted and responding (if server change)
- BUG_TRACKER.md updated to 🟢

---

## DO / DON'T TABLE

| DO | DON'T |
|----|-------|
| Use `oldV` in migration params | Use `oldVersion` (compile error) |
| Use `conflictAlgorithm: ConflictAlgorithm.replace` | Use `ON CONFLICT DO UPDATE` (SQLite 3.24+ only) |
| Pass `status=` to `encode_response()` | Forget status — it drops 4xx/5xx codes |
| Use `strict_slashes=False` on Flask empty routes | Leave it off (nginx 301-loops) |
| Check CI after every commit | Mark done before CI result |
| Read Oracle files via SSH before editing | Edit blindly without reading |
| Use Node.js for GitHub API calls | Use curl for large base64 payloads |
| Pull on Oracle after every GitHub push | Assume Oracle auto-updates |

---

## VERIFICATION CHECKLIST

After any code change:
```bash
# Check CI
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" | \
  node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');JSON.parse(d).workflow_runs.forEach(r=>console.log(r.name,r.status,r.conclusion))"

# Check server health
curl -s http://92.4.95.252/api/app/version
```
