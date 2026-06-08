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

CURRENT STATE (as of 2026-06-08):
- Oracle Flask: running (PID 2978797, HTTP 302 OK)
- v3 DB: 17 titles / 28 files — all Live
- Library UI: Publish All / bulk controls / bulk delete all working
- Admin/Scan/Settings: all confirm()/prompt() replaced with two-step toasts + inline panels
- scanner.py: UNIQUE slug conflict handled (commit 6ccfa67)
- scan_excluded_folders: empty [] (MSISDN removed)

HARD RULES (never break):
- GitHub pushes: Python urllib Trees API only — no git shell
- sqflite_sqlcipher pinned at 3.1.0+1 — never upgrade
- biometricOnly = false always (breaks Infinix/MediaTek)
- Oracle port 5000 = localhost only (SSH tunnel to test)
- DB columns: k and v (not key/value) — db.setting(k) only
- v3 titles: plot (not overview), scanned_at (not created_at in files)
- Proxy bypass DB key = JAZZDRIVE_PROXY_BYPASS (value 1)
- Real DB path: /opt/jazzmax/radd-hub/data/radd_hub.db
- No confirm()/prompt() in Flask templates — two-step arm+fire toast instead
- Template GitHub path: radd-hub/hub/templates/ (NOT hub/templates/)
- Push template files sequentially — parallel PUTs cause 409 SHA conflicts

BEFORE FINISHING: update TASKS.md + HANDOFF_NEXT.md + TASK_LOG_APPEND.md and push to GitHub.
