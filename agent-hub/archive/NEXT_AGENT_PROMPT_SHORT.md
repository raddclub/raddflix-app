You are continuing work on RaddFlix — a Pakistani Flutter streaming app (Jazz SIM zero-rated).

LATEST SESSION (2026-06-18): FIX-VF-STARTUP + FEAT-TIMELINE (PlaybackTimeline diagnostics) committed. Build #1147 triggered. No open bugs.
GITHUB_TOKEN and ORACLE_SSH_KEY are already in Replit Secrets. Start immediately.

STEP 1 — Restore SSH key (run this every session):
node -e "const raw=process.env.ORACLE_SSH_KEY||'';const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600});console.log('key ready')"

STEP 2 — Verify Oracle alive:
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
→ Expected: {"ok":true,"version":"3.0.0"}

STEP 3 — Read context + task list:
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/HANDOFF_NEXT.md
curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASKS.md

CURRENT STATE (as of 2026-06-17 — post player UX session):
- Oracle Flask: running as raddflix_radd (PID 3008136)
- v3 DB: 17 titles / 28 files — all Live
- APK: build1034 (run 27156269376) — expires 2026-07-08
- TASK-057 complete: 8 bugs fixed (6 Flutter + 2 Oracle Python)
- Player UX: 8 MX Player layout improvements (floating ball, sidebar 3-state, clock, speed track, side panels, auto-rotate)
  Commits: 01fc775f (prefs), bd75f9d6 (screen)
- Account 03286829827: session healthy, auto-recovers via Android OAuth2 + PK proxy

HARD RULES (never break):
- GitHub pushes: Trees/Contents API only — no git shell
- sqflite_sqlcipher pinned at 3.1.0+1 — never upgrade
- biometricOnly = false always (breaks Infinix/MediaTek)
- Oracle port 5000 = localhost only (SSH tunnel to test)
- DB columns: k and v (not key/value) — db.setting(k) only
- v3 titles: plot (not overview), scanned_at (not created_at in files)
- Proxy bypass DB key = JAZZDRIVE_PROXY_BYPASS (value 1)
- Real DB path: /opt/jazzmax/radd-hub/data/radd_hub.db
- Supervisor process: raddflix_radd (NOT radd-hub)
- No confirm()/prompt() in Flask templates — two-step arm+fire toast instead
- Template GitHub path: radd-hub/hub/templates/ (NOT hub/templates/)
- Dart semicolons BEFORE inline comments — never after
- Never suggest new features — only fix bugs

BEFORE FINISHING: update TASKS.md + HANDOFF_NEXT.md + TASK_LOG_APPEND.md and push to GitHub.
