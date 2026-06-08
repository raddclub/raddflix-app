# RaddFlix — Replit Agent Workspace

RaddFlix is a Pakistani Flutter streaming app (Jazz SIM zero-rated). Backend is Flask on Oracle VPS 92.4.95.252. This Replit is used as an agent workspace — the real code lives on GitHub (`raddclub/raddflix-app`) and runs on Oracle Cloud.

## Quick Start for Any New Agent
1. Add secrets: `GITHUB_TOKEN` and `ORACLE_SSH_KEY`
2. Restore SSH key + verify Oracle is alive:
   ```bash
   node -e "const raw=process.env.ORACLE_SSH_KEY;const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);if(m)require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600})"
   ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
   ```
3. Read core docs in `agent-hub/`:
   - `PRODUCT_CONTEXT.md` — full product context
   - `STREAMING_ARCHITECTURE.md` — immutable architecture rules
   - `AGENT_HANDOFF.md` — current state + rules + file map

## Key Files in This Workspace
- `agent-hub/` — architecture & feature spec docs
- `radd-hub/` — Flask server source code
- `raddflix_flutter/` — Flutter app source code
- `.github/workflows/` — CI + APK build workflows
- `.agents/tasks/BUG_TRACKER.md` — all known bugs + fix status
- `agent-hub/history/TASK_LOG.md` — session-by-session work log

## Infrastructure
- GitHub: raddclub/raddflix-app (main branch)
- Oracle: ubuntu@92.4.95.252 (SSH via ORACLE_SSH_KEY secret)
- API: http://92.4.95.252 (nginx port 80 → Flask port 5000)
- **Supervisor service: `raddflix_radd`** (NOT `radd-hub`)
- Restart command: `sudo supervisorctl restart raddflix_radd`

## User Preferences
- Never suggest new features — only fix existing bugs and broken code
- Fix bugs in CRITICAL → HIGH → MEDIUM → LOW order
- Never commit secrets to GitHub
- Use GitHub Trees API (Node.js) for multi-file commits
- Always show what changed before committing
- Never touch Oracle without explicit approval
- Add TASK row to agent-hub/TASKS.md BEFORE starting work (Rule 0)
