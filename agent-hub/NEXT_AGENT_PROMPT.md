# Handoff Prompt — RaddFlix Replit Agent (New Account)
> Generated: 2026-05-31 | Copy this entire prompt into your new Replit Agent chat to continue.

---

## YOUR FIRST INSTRUCTION

Before anything else, read these three files from the GitHub repo in order:

```
1. agent-hub/REINCARNATION.md   ← Full project context (534 lines, read ALL of it)
2. agent-hub/AGENT_RULES.md     ← Golden rules you must follow
3. agent-hub/MASTER_PLAN.md     ← Task queue with statuses
```

Fetch them like this (GITHUB_TOKEN is in Replit Secrets):

```bash
H="Authorization: token $GITHUB_TOKEN"
BASE="https://raw.githubusercontent.com/raddclub/raddflix-app/main"
curl -sf -H "$H" "$BASE/agent-hub/REINCARNATION.md"
curl -sf -H "$H" "$BASE/agent-hub/AGENT_RULES.md"
curl -sf -H "$H" "$BASE/agent-hub/MASTER_PLAN.md"
```

Only start working after reading all three.

---

## PROJECT SUMMARY

**RaddFlix** — Pakistani streaming platform. Jazz SIM users stream videos data-free via JazzDrive CDN (zero-rated). Built as a Flutter Android app + Flask backend.

- **GitHub repo:** `raddclub/raddflix-app`
- **All changes via GitHub API only** — Oracle SSH (`ubuntu@92.4.95.252`) times out from Replit. Never try SSH.
- **GITHUB_TOKEN** is in Replit Secrets (already configured).

---

## CURRENT STATE (as of 2026-05-31, commit `59ea755`)

### What was done in the last session (Session 2)

All Priority 1 and 2 bugs have been fixed or verified:

| ID | Status | Summary |
|----|--------|---------|
| P1.1 | ✅ DONE | Security channel already wired in MainActivity.kt (was a false alarm) |
| P1.2 | ✅ DONE | stream_links table exists in DDL (was a false alarm) |
| P1.3 | ✅ DONE | bcrypt migration in mobile_api.py — salted passwords, SHA-256 migration path on login |
| P1.4 | ✅ DONE | Hardcoded `http://92.4.95.252` removed from catalog_api.py |
| P2.1 | ✅ DONE | FTS5 virtual table `titles_fts` + 3 sync triggers in db.py; search_api.py uses MATCH+BM25 with LIKE fallback |
| P2.2 | ✅ DONE | `_ip_window` memory leak fixed in security_telemetry.py |
| P2.3 | ✅ DONE | Frida/root detection already in MainActivity.kt (was a false alarm) |
| P2.4 | ✅ DONE | XOR encoding already enabled + XorWsgiMiddleware already wired (was a false alarm) |
| P2.5 | ✅ DONE | `_legacy` module directory exists (was a false alarm) |
| P2.6 | ✅ DONE | bcrypt>=4.0 added to requirements.txt |
| P3.2 | ✅ DONE | Bot state .gitignore created |
| P3.4 | ✅ DONE | `core/utils/auth_utils.dart` created; `_friendly()` deduped from login/register screens |
| P3.6 | ✅ DONE | "JazzBuzz" dead brand → "RaddFlix" in bulk_link_engine.py |
| P3.7 | ✅ DONE | constants.dart `otpDeviceSwitchEnabled` comment updated |
| P4.2–P4.5 | ✅ DONE | All already implemented (verified by reading code, no changes needed) |

### What is STILL OPEN (only 3 items, all need user input)

**P3.1** — Delete root `lib/*.dart` stubs (JazzMAX/ZENO dead branding)
- **Blocked by:** User must explicitly say "yes, delete root stubs" before you touch these
- **Action:** Delete root `lib/` directory contents + root `pubspec.yaml` + root `pubspec.lock` via GitHub API tree manipulation

**P3.3** — Replace `supportWhatsApp` placeholder number
- **Blocked by:** Need the real RaddFlix WhatsApp support phone number from the user
- **File:** `raddflix_flutter/lib/core/constants.dart`
- **Current value:** `'923001234567'` (placeholder)

**P3.5** — Clean up legacy `titles` table columns
- **Blocked by:** Risky schema migration — needs careful planning and user sign-off
- **Problem:** `titles` table has redundant columns: `cast`, `cast_names`, `cast_json` (keep only `cast_json`); `overview` (duplicate of `plot`); `omdb_id` (duplicate of `imdb_id`)
- **Requires:** DB migration in `db.py` + `catalogDbVersion` bump in `constants.dart` + `_migrate()` case in `local_db.dart`

**P4.1** — Deploy full WhatsApp bot to production
- Supervisor currently runs `hub/bots/whatsapp/` (simple). Full-featured bot is in `bots/whatsapp/`
- Needs Oracle server access to update supervisor config — coordinate with user

---

## CRITICAL RULES (condensed — read full AGENT_RULES.md for details)

1. **Read REINCARNATION.md + AGENT_RULES.md + MASTER_PLAN.md before ANY work**
2. **All changes via GitHub API** — no SSH, no local file edits
3. **NEVER touch `root/lib/` or `root/pubspec.yaml`** — they are dead stubs with wrong branding
4. **NEVER upgrade `sqflite_sqlcipher`** — pinned at `3.1.0+1` (3.2.0 breaks CI)
5. **Ask user for approval before deleting files** (especially P3.1)
6. **Verify CI green after every commit**
7. **Update MASTER_PLAN.md + TASK_LOG.md after every task**

---

## HOW TO COMMIT (GitHub API pattern — Oracle SSH does NOT work)

```bash
H="Authorization: token $GITHUB_TOKEN"
REPO="raddclub/raddflix-app"

# 1. Create blob for each changed file
SHA=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/git/blobs" \
  -d "{\"encoding\":\"base64\",\"content\":\"$(base64 -w0 /path/to/file)\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# 2. Get current HEAD + tree SHA
HEAD=$(curl -s -H "$H" "https://api.github.com/repos/$REPO/git/refs/heads/main" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['object']['sha'])")
TREE=$(curl -s -H "$H" "https://api.github.com/repos/$REPO/git/commits/$HEAD" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['tree']['sha'])")

# 3. Create new tree
NEW_TREE=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/git/trees" \
  -d "{\"base_tree\":\"$TREE\",\"tree\":[{\"path\":\"path/to/file\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$SHA\"}]}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# 4. Create commit
NEW_COMMIT=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/git/commits" \
  -d "{\"message\":\"fix(scope): description\",\"tree\":\"$NEW_TREE\",\"parents\":[\"$HEAD\"]}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")

# 5. Advance branch
curl -s -X PATCH -H "$H" -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/git/refs/heads/main" \
  -d "{\"sha\":\"$NEW_COMMIT\"}"
```

---

## ARCHITECTURE IN 60 SECONDS

```
[Flutter Android App]  ──HTTPS──▶  [Flask Backend @ 92.4.95.252:5000]
      │                                         │
      │ SQLCipher (AES-256)             SQLite WAL
      │ local catalog DB                server DB
      │                                         │
      └───────────────────────────────▶ [JazzDrive CDN]
                 Zero-rated for Jazz SIM         share_urls never expire
```

**Key files to know:**
- `raddflix_flutter/lib/core/constants.dart` — all app constants, feature flags
- `raddflix_flutter/lib/core/db/local_db.dart` — Flutter SQLCipher schema (v13)
- `radd-hub/hub/db.py` — Flask SQLite schema (DDL array + init_db())
- `radd-hub/hub/routes/mobile_api.py` — auth/subscription API endpoints
- `radd-hub/hub/routes/catalog_api.py` — catalog sync API
- `raddflix_flutter/android/app/src/main/kotlin/com/raddflix/app/MainActivity.kt` — native channels

---

## HOW TO CHECK CI STATUS

```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" \
  | python3 -c "
import json, sys
for r in json.load(sys.stdin)['workflow_runs']:
    print(r['name'], r['status'], r['conclusion'], r['head_sha'][:8])
"
```

---

## YOUR STARTING TASK

Ask the user which of the 3 open items they want to tackle first:

1. **P3.1** — Delete root lib/ stubs (say "yes, delete them" to proceed)
2. **P3.3** — Provide the real WhatsApp support number to replace the placeholder
3. **P3.5** — DB column cleanup (review the migration plan first)
4. **P4.1** — WhatsApp bot deployment (needs Oracle server access coordination)

Or ask if there are new features/tasks to work on beyond the current backlog.

**Do not start any task until the user gives a clear direction.**
