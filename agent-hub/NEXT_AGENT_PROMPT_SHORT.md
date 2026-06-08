You are continuing work on RaddFlix — a Pakistani Flutter streaming app (Jazz SIM zero-rated).
GITHUB_TOKEN and ORACLE_SSH_KEY are already in Replit Secrets. Start immediately.

STEP 1 — Restore SSH key (run this every session):
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('key ready')"

STEP 2 — Verify Oracle alive:
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
→ Expected: {"ok":true,"version":"3.0.0"}

STEP 3 — Read context + task list:
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/HANDOFF_NEXT.md
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md

STEP 4 — Run the full audit (your main task):
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/FULL_AUDIT_PROMPT.md
Follow every step in that file.

HARD RULES (never break):
- GitHub pushes: Python urllib Trees API only — no git shell
- sqflite_sqlcipher pinned at 3.1.0+1 — never upgrade
- biometricOnly = false always (breaks Infinix/MediaTek)
- Oracle port 5000 = localhost only (SSH tunnel to test)
- DB columns: k and v (not key/value) — db.setting(k) only
- Proxy bypass DB key = JAZZDRIVE_PROXY_BYPASS (value 1)
- Real DB path: /opt/jazzmax/radd-hub/data/radd_hub.db

BEFORE FINISHING: update TASKS.md + HANDOFF_NEXT.md + TASK_LOG_APPEND.md and push to GitHub.
