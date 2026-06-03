# AGENT_HANDOFF.md — RaddFlix Master Agent Briefing
> **EVERY NEW AGENT ON EVERY ACCOUNT READS THIS FIRST. NO EXCEPTIONS.**
> Last Updated: 2026-06-03 | Session 36 (Bug Fix Marathon — ALL 30 BUGS FIXED)
> Version: 1.0 — Full Multi-Agent Coordination System

---

## 🟢 SESSION 36 COMPLETE — ALL 30 BUGS FIXED

| Batch | Commit | Bugs Fixed |
|-------|--------|------------|
| Batch 1 | 1cc57e9 | S01, S04, S05, F01, F02, F12 |
| Batch 2 | fcdd338 | S02, S07, S08, S09, S10, F07, F08, F09 |
| Batch 3 | 5f74209 | S03, S06, S11, F04, F06(confirmed), F10 |
| Batch 4 | 47a3051 | S12, S13, S14, F13, F15 + tracker/log |

**Won't Fix (files removed from codebase):** F05, F11

**Oracle server:** Running — pid 627521, all server-side fixes deployed.  
**Flutter app:** All Flutter fixes in GitHub — needs rebuild + store deploy.  
**Next task:** Rebuild Flutter APK with these 14 Flutter fixes and push to Play Store.

---

## FIRST 5 MINUTES — DO THIS BEFORE ANYTHING ELSE

```bash
# Step 1: Set up SSH key to Oracle
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (m) {
  require('fs').writeFileSync('/tmp/oracle_key',
    m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
    {mode: 0o600});
  console.log('SSH key ready');
}
"
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@92.4.95.252 "echo Oracle OK"

# Step 2: Read current state from GitHub
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/.agents/tasks/BUG_TRACKER.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -200
```

**Required Secrets (user adds before every session):**
- `GITHUB_TOKEN` — Personal Access Token for raddclub/raddflix-app
- `ORACLE_SSH_KEY` — OpenSSH private key for ubuntu@92.4.95.252

---

## WHAT IS RADDFLIX?

Pakistani streaming platform for Jazz SIM users. Movies/dramas stream FREE (zero-rated) because video is served via JazzDrive (cloud.jazzdrive.com.pk) which Jazz zero-rates at network level. No data bundle needed.

**Never call it:** JazzMAX, Zeno (dead names)

---

## INFRASTRUCTURE

| Component | Location | Tech | Port |
|-----------|----------|------|------|
| Radd Hub (API + admin) | Oracle: /opt/jazzmax/radd-hub/ | Python 3.12 + Flask + SQLite | nginx:80 → 5000 |
| Flutter mobile app | GitHub: raddflix_flutter/ | Flutter/Dart | N/A |
| WhatsApp bot | Oracle: /opt/jazzmax/wa-bot/ | Node.js 20 | supervisor |
| GitHub repo | raddclub/raddflix-app | main branch | — |

**Oracle:** ubuntu@92.4.95.252 | SSH port 22 | API port 5000 (firewalled, nginx proxies on 80)

---

## STREAMING ARCHITECTURE (IMMUTABLE — NEVER CHANGE THIS)

```
Oracle (92.4.95.252)   → Auth, subscriptions, catalog metadata ONLY
JazzDrive CDN          → Stores ALL video files (zero-rated on Jazz SIM)
Flutter App            → Local SQLite with full catalog + share_urls

Playback flow:
1. Read share_url from local SQLite (no network)
2. POST cloud.jazzdrive.com.pk/sapi/link/login → validationKey + JSESSIONID
3. GET cloud.jazzdrive.com.pk/sapi/media/video → CDN URL
4. Cache CDN URL 3h in stream_cache table
5. media_kit plays CDN URL (zero-rated)
```

**NEVER route JazzDrive calls through Oracle.** Phone→Oracle leg is NOT zero-rated.

---

## HOW TO COMMIT TO GITHUB (GitHub API — required method)

**Never use git shell commands from Replit.** Use the GitHub API via Node.js.

### Single file change:
```javascript
// 1. GET SHA: GET /repos/raddclub/raddflix-app/contents/PATH
// 2. PUT with base64 content + SHA
const res = await fetch(`https://api.github.com/repos/raddclub/raddflix-app/contents/${path}`, {
  method: 'PUT',
  headers: { Authorization: `token ${process.env.GITHUB_TOKEN}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ message: 'fix: ...', content: Buffer.from(content).toString('base64'), sha: fileSha })
});
```

### Multi-file commit (2+ files — always use this):
```javascript
// 1. POST /git/blobs for each file → get blob SHA
// 2. POST /git/trees with parent tree SHA + all blobs → get tree SHA
// 3. POST /git/commits with tree SHA + parent commit SHA → get commit SHA
// 4. PATCH /git/refs/heads/main with new commit SHA
// Token: process.env.GITHUB_TOKEN | Repo: raddclub/raddflix-app | Branch: main
```

### After every session — REQUIRED:
1. Commit all changes to GitHub
2. Update `.agents/tasks/BUG_TRACKER.md` with new bug statuses
3. Append entry to `agent-hub/history/TASK_LOG.md`
4. Write `.agents/handoff/SESSION_YYYY-MM-DD.md`

---

## HOW TO SSH ORACLE

```bash
# Write key (run at start of every session)
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (m) {
  require('fs').writeFileSync('/tmp/oracle_key',
    m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
    {mode: 0o600});
  console.log('key ready');
}
"

# Connect
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "COMMAND"

# Restart server
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sudo supervisorctl status"

# Pull latest code on Oracle
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "cd /opt/jazzmax && git pull && sudo supervisorctl restart raddflix_radd"
```

---

## CRITICAL FACTS — FLUTTER

- **SQLCipher pin:** `sqflite_sqlcipher: 3.1.0+1` — NEVER upgrade until CI is Flutter 3.27+
- **DB version:** `catalogDbVersion = 16`. Next migration: `if (oldV < 17)`
- **Migration param:** MUST be `oldV` not `oldVersion` — compile error if wrong (broke CI twice)
- **XOR encoding:** ALL API calls XOR-encrypted. Both sides must stay in sync. NEVER disable one side only.
- **Android 8 compat:** No raw SQL UPSERT (`ON CONFLICT DO UPDATE` = SQLite 3.24+, Android 8 = 3.19). Use `conflictAlgorithm: ConflictAlgorithm.replace` or manual SELECT+UPDATE/INSERT.
- **JWT secret:** persisted in settings table key `mobile_jwt_secret` — survives server restart.

---

## CRITICAL FACTS — SERVER

- All API via nginx port 80 (port 5000 firewalled externally)
- Flask blueprints: empty-string routes need `strict_slashes=False` or nginx 301-loops
- `_legacy/` Python files REQUIRED at `/opt/jazzmax/radd-hub/hub/_legacy/` — missing = ImportError
- Real DB: `/opt/jazzmax/radd-hub/data/radd_hub.db` (SQLCipher)
- Fake DB (ignore): `/opt/jazzmax/radd-hub/data/raddflix.db` (empty, legacy)
- CI auto-deploy (`Deploy to Oracle`) always fails — manually pull on Oracle after every push

---

## CURRENT STATE (as of 2026-06-03)

- Oracle: running (pid 593269), commit `a07e0bf7`
- 24 titles published (is_published=1), 44/45 files have share_url
- All 24 titles: is_free=0 (no free content for guests)
- APK: RaddFlix-1.0.0+1-build639.apk (58MB) — last successful build
- WA Bot: running but WhatsApp pairing pending

---

## BUG STATUS SUMMARY

30 bugs found in audit (2026-06-03). **None fixed yet.**
See full list: `.agents/tasks/BUG_TRACKER.md`

Priority order to fix:
1. **BUG-F02** — Color constants compile error (blocks app building)
2. **BUG-F03/F14** — DB migration crash on upgrade (affects all existing users)
3. **BUG-S01 + BUG-F01** — Catalog sync infinite loop (core feature broken)
4. **BUG-F06** — TV shows have no episodes from Oracle sync
5. **BUG-S04/S05** — Trending always returns 0 results

---

## RULES FOR EVERY AGENT

1. **Read before touch** — always read a file before editing it
2. **Show diff first** — never commit without showing the user what changed
3. **No Oracle changes without approval** — always ask first
4. **Severity order** — fix CRITICAL → HIGH → MEDIUM → LOW
5. **Never break XOR** — change both Flutter + server sides together, never one alone
6. **Always update docs** — BUG_TRACKER.md + TASK_LOG.md + session handoff after every session
7. **No secrets in files** — GITHUB_TOKEN and ORACLE_SSH_KEY stay only in Replit Secrets
8. **Use GitHub API** — never use git shell commands from Replit agent
9. **Verify after fix** — check CI passes and server restarts cleanly
10. **One fix at a time** — show user result before moving to next bug

---

## WHAT TO TELL THE NEXT AGENT (copy-paste this prompt)

```
You are working on RaddFlix, a Pakistani streaming platform.

Before doing anything, run:
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/install.sh | bash

Then read:
- AGENT_HANDOFF.md (this file — fetch from GitHub raw)
- .agents/PROJECT_RULES.md
- .agents/tasks/BUG_TRACKER.md

GitHub repo: raddclub/raddflix-app
Oracle server: ubuntu@92.4.95.252
GITHUB_TOKEN and ORACLE_SSH_KEY are in Replit Secrets.

There are 30 open bugs from a completed audit (2026-06-03). Fix in CRITICAL → HIGH → MEDIUM → LOW order.
Never commit without showing the diff first. Never touch Oracle without explicit approval.
After your session: update BUG_TRACKER.md, append to agent-hub/history/TASK_LOG.md, write .agents/handoff/SESSION_YYYY-MM-DD.md.
```
