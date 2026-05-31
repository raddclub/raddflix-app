# AGENT_RULES.md — The Golden Rules
> **ALL AGENTS MUST FOLLOW THESE RULES WITHOUT EXCEPTION.**
> Violation = broken app, wasted work, frustrated user.
> Last Updated: 2026-05-31

---

## RULE 1 — READ BEFORE YOU ACT
**Before touching any code, read:**
1. `REINCARNATION.md` — full project context
2. `MASTER_PLAN.md` — the current task queue
3. The relevant `CODE_MAP.md` entries for files you'll touch

**Why:** This is a complex, multi-phase project. Files interact in non-obvious ways. Every past bug was caused by an agent who didn't read context first.

---

## RULE 2 — ONE TASK AT A TIME
**Pick ONE task from MASTER_PLAN.md. Complete it fully. Verify it. Then stop and ask user for approval before starting the next task.**

```
✅ Correct:
  Agent takes P1.1 → fixes MainActivity.kt → CI green → asks user "P1.1 done, proceed to P1.2?"
  User approves → Agent takes P1.2 → and so on

❌ Wrong:
  Agent takes P1.1 + P1.2 + P1.3 simultaneously, makes mistakes across all three,
  CI fails, no way to know which change broke what.
```

**Why:** Parallel task execution creates compounding failures. If CI breaks, you can't tell which change caused it. One task = one verification loop = confidence.

---

## RULE 3 — VERIFY BEFORE MARKING DONE
**A task is NOT done until:**
- [ ] The code change is committed to GitHub
- [ ] CI passes (check `.github/workflows/build-apk.yml` run status)
- [ ] No new errors in related files (run `grep` for obvious breakage)
- [ ] The `MASTER_PLAN.md` task status is updated to `✅ DONE`
- [ ] `TASK_LOG.md` has a new entry for this session

**How to check CI:**
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" \
  | python3 -c "import json,sys; [print(r['name'], r['status'], r['conclusion']) for r in json.load(sys.stdin)['workflow_runs']]"
```

---

## RULE 4 — DO NOT CREATE NEW BUGS
**Every change must be checked against these questions:**
1. Does this change break any other file that imports/uses the changed code?
2. Does this change alter any DB schema? If yes, is the migration handled?
3. Does this change affect the JWT/auth flow? If yes, existing tokens still valid?
4. Does this change affect `local_db.dart` schema? If yes, increment `catalogDbVersion` and add `_migrate()` case.
5. Does this change affect the API contract? If yes, does the Flutter client need updating too?

**The Double-Check Rule:** After writing your change, read the diff back and ask: "If I'm wrong about one thing here, what breaks?"

---

## RULE 5 — NEVER TOUCH ROOT LIB/ OR ROOT pubspec.yaml
```
root/lib/*.dart           ← DEAD. Old stubs. Do NOT edit.
root/pubspec.yaml         ← DEAD. Old deps. Do NOT edit.
raddflix_flutter/lib/     ← ✅ REAL app. Edit this.
raddflix_flutter/pubspec.yaml ← ✅ REAL deps. Edit this.
```
**Why:** Root lib/ contains JazzMAX/ZENO branded OLD stubs that are NOT used by CI or builds. Editing them does nothing but create confusion.

---

## RULE 6 — NEVER UPGRADE sqflite_sqlcipher
```yaml
sqflite_sqlcipher: 3.1.0+1  ← PINNED. DO NOT CHANGE.
```
3.2.0 introduced `flutter.compileSdkVersion` in Gradle which breaks CI (AGP version mismatch on Flutter 3.22.x). Until the CI config is updated to handle this, the pin stays. If in doubt, check REINCARNATION.md Phase notes.

---

## RULE 7 — ALL CHANGES VIA GITHUB API
**Oracle SSH does NOT work from Replit.** Never attempt `ssh ubuntu@92.4.95.252`.
All changes to backend, Flutter, and config files must go through GitHub API (commit pattern in REINCARNATION.md).

**Commit message format:**
```
type(scope): short description

fix(android): wire SECURITY_CHANNEL handler in MainActivity.kt
```
Types: `feat`, `fix`, `docs`, `refactor`, `security`, `test`, `ci`

---

## RULE 8 — NEVER HARDCODE SECRETS OR IPs
**WRONG:**
```python
return "http://92.4.95.252"   # hardcoded IP
SECRET = "dev-secret-123"      # hardcoded secret
```
**RIGHT:**
```python
return os.environ.get("WATCH_SERVER_URL", "")   # env var, empty fallback
SECRET = os.environ.get("SESSION_SECRET")        # env var only, crash if missing
```
The only allowed exception: `AppConstants.apiBaseUrl` default (because RemoteConfig overwrites it on startup, and the app must bootstrap somehow).

---

## RULE 9 — UPDATE DOCS AFTER EVERY SESSION
**Every session must end with:**
1. `MASTER_PLAN.md` — update task status (🔄 → ✅ or ❌)
2. `history/TASK_LOG.md` — append session entry (date, task, files changed, outcome)
3. `REINCARNATION.md` header — update "Last commit" and "Next Tasks" section

**Why:** Future agents (and future you) rely on accurate documentation. Stale docs are worse than no docs.

---

## RULE 10 — ASK FOR APPROVAL AT MILESTONES
**Always ask the user for approval:**
- After completing each Priority 1 task (P1.x)
- Before starting any task that modifies DB schema
- Before any task that changes the API contract
- Before deleting any files (e.g., removing root lib/ stubs)
- After completing a group of P2/P3/P4 tasks

**Format:**
```
✅ Task P1.1 complete. CI green. [brief summary of what was done]
Ready to start P1.2 (fix bulk_link_engine.py stream_links). Proceed?
```

---

## QUICK REFERENCE — DO / DON'T

| DO | DON'T |
|----|-------|
| Read REINCARNATION.md first | Jump straight to coding |
| One task at a time | Work on multiple tasks simultaneously |
| Verify CI green before done | Mark done without checking CI |
| Use GitHub API for all commits | Try SSH to Oracle |
| Use `AppColors.*` for colors | Hardcode `Color(0xFF...)` |
| Use `ApiPaths.*` for endpoints | Hardcode URL strings |
| Update MASTER_PLAN + TASK_LOG | Skip documentation |
| Ask user before next task | Auto-chain tasks |
| Use `db.get_db()` in Flask | Create raw sqlite3 connections |
| Relative Dart imports | `package:raddflix/...` imports |

---

*End of AGENT_RULES.md — 2026-05-31*
*These rules apply to ALL agents: Replit Agent, Claude, GPT, Gemini, future models.*
