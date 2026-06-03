# RaddFlix — Replit Agent Workspace

## Project Overview
RaddFlix is a Pakistani streaming platform. Jazz SIM users stream movies/dramas FREE (zero-rated) via JazzDrive CDN (cloud.jazzdrive.com.pk). This Replit is used as an agent workspace — the real code lives on GitHub (raddclub/raddflix-app) and runs on Oracle Cloud.

## Quick Start for Any New Agent
1. Add secrets: `GITHUB_TOKEN` and `ORACLE_SSH_KEY`
2. Restore SSH key + verify Oracle is alive:
   ```bash
   node -e "const raw=process.env.ORACLE_SSH_KEY;const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);if(m)require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600})"
   ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/api/app/version"
   ```
3. Read core docs in `agent-hub/`:
   - `PRODUCT_CONTEXT.md` — full product context
   - `STREAMING_ARCHITECTURE.md` — immutable architecture rules
   - `FEATURES_ROADMAP.md` — planned features

## Key Files in This Workspace
- `push_to_github.sh` — commit & push changes to GitHub
- `push_to_oracle.sh` — deploy to Oracle (git pull + restart)
- `raddflix_config.json` — API base URL + min version config
- `agent-hub/` — architecture & feature spec docs
- `radd-hub/` — Flask server source code
- `raddflix_flutter/` — Flutter app source code
- `.github/workflows/` — CI + APK build workflows

## Infrastructure
- GitHub: raddclub/raddflix-app (main branch)
- Oracle: ubuntu@92.4.95.252 (SSH via ORACLE_SSH_KEY secret)
- API: http://92.4.95.252 (nginx port 80 → Flask port 5000)
- Supervisor service: `raddflix_radd`

## User Preferences
- Always show diff before committing
- Never touch Oracle without explicit approval
- Fix bugs in CRITICAL → HIGH → MEDIUM → LOW order
- Never commit secrets to GitHub
- Use GitHub API (Node.js) for multi-file commits from agent code
