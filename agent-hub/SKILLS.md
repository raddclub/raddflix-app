# RaddFlix Agent Skills & Rules
> Non-negotiable rules for every agent. Violating them breaks production.
> Last Updated: 2026-06-02

---

## Rule 0 — Reincarnation (Read This Every Session)

Read these files from GitHub before doing anything:

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/MASTER_TASKLIST.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/TASK_LOG.md" | tail -150
```

After reading, tell the user: what the last session did, what the recommended next tasks are, and ask what to work on. Never start coding without completing Rule 0.

---

## Rule 1 — Read Before You Touch

Before any change:
1. Read agent-hub/history/TASK_LOG.md to know what was already done
2. Read agent-hub/CODE_MAP.md for the file you are about to change
3. If touching the server, SSH in and read the file before editing

Never assume a file's content. Always read first.

---

## Rule 2 — SSH Connection Pattern

Key is OPENSSH format stored with spaces instead of newlines in Replit Secrets.
Use Node.js to reformat (confirmed working 2026-06-02):

```bash
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
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@92.4.95.252 "echo OK"
```

To restart the server:
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "sudo supervisorctl restart raddflix_radd && sudo supervisorctl status"
```

---

## Rule 3 — GitHub API Pattern

All code changes go via GitHub API. Never use git shell commands from Replit.

Single-file change:
```javascript
// 1. GET file to obtain SHA: GET /repos/raddclub/raddflix-app/contents/PATH
// 2. PUT with base64 content + SHA: PUT /repos/raddclub/raddflix-app/contents/PATH
```

Multi-file commit (preferred for 2+ files):
```
1. POST /git/blobs for each file  (get blob SHA per file)
2. POST /git/trees with parent tree SHA + all blob SHAs
3. POST /git/commits with tree SHA + parent commit SHA
4. PATCH /git/refs/heads/main with new commit SHA
```

Token: process.env.GITHUB_TOKEN | Repo: raddclub/raddflix-app | Branch: main

---

## Rule 4 — Do Not Create New Bugs

Before committing any change, check:
1. Does this break any file that imports the changed code?
2. Does this change the DB schema? If yes, increment catalogDbVersion and add if (oldV < N) block.
3. Does this affect the JWT/auth flow? Existing tokens still valid?
4. Does this affect the API contract? Flutter client updated too?
5. Does this change XOR encoding on one side only? (NEVER — must change both sides together)

---

## Rule 5 — Verify Before Marking Done

A task is NOT done until:
- Code is committed to GitHub main
- CI passes (check Actions runs)
- MASTER_TASKLIST.md updated
- agent-hub/history/TASK_LOG.md has a new entry

Check CI:
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=3" | \
  node -e "const d=require('fs').readFileSync('/dev/stdin','utf8');JSON.parse(d).workflow_runs.forEach(r=>console.log(r.name,r.status,r.conclusion))"
```
