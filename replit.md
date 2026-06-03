# RaddFlix — Replit Agent Workspace

## Project Overview
RaddFlix is a Pakistani streaming platform. Jazz SIM users stream movies/dramas FREE (zero-rated) via JazzDrive CDN (cloud.jazzdrive.com.pk). This Replit is used as an agent workspace — the real code lives on GitHub (raddclub/raddflix-app) and runs on Oracle Cloud.

## Quick Start for Any New Agent
1. Add secrets: `GITHUB_TOKEN` and `ORACLE_SSH_KEY`
2. Run: `curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/install.sh | bash`
3. Read: `AGENT_HANDOFF.md` (full context + rules)
4. Read: `.agents/tasks/BUG_TRACKER.md` (30 open bugs)

## Key Files in This Workspace
- `AGENT_HANDOFF.md` — master briefing (read first every session)
- `.agents/PROJECT_RULES.md` — non-negotiable rules
- `.agents/tasks/BUG_TRACKER.md` — all 30 bugs with status
- `.agents/memory/` — topic files (architecture, SSH, XOR, JazzDrive, bugs)
- `.agents/handoff/` — session handoff logs
- `agent-hub/` — original coordination files from GitHub repo

## Infrastructure
- GitHub: raddclub/raddflix-app (main branch)
- Oracle: ubuntu@92.4.95.252 (SSH via ORACLE_SSH_KEY secret)
- API: http://92.4.95.252 (nginx port 80 → Flask port 5000)

## User Preferences
- Always show diff before committing
- Never touch Oracle without explicit approval
- Fix bugs in CRITICAL → HIGH → MEDIUM → LOW order
- Never commit secrets to GitHub
- Use GitHub API (Node.js) for all commits — never git shell commands
