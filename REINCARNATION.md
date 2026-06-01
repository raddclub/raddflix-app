# RaddFlix — Project Reincarnation Context
> Last updated: 2026-06-01 by Agent (Brand Studio P6 build)

## What is this project?
RaddFlix is a Pakistani zero-rated streaming platform with two components:
1. **radd-hub** — Flask-based admin panel running on Oracle VPS (Ubuntu), managed via SSH/supervisor
2. **raddflix_flutter** — Flutter Android app, built via GitHub Actions, served to Jazz SIM users

## Repository
- Repo: `raddclub/raddflix-app` (GitHub, public)
- Branch: `main`
- All agent code changes go via **GitHub API only** (no SSH, no local builds)
- SSH key in `ORACLE_SSH_KEY` secret, GitHub token in `GITHUB_TOKEN` secret

## Server
- Oracle VPS: `92.4.95.252`
- Admin panel: `http://92.4.95.252` (port 5000 via supervisor)
- Radd Hub entry: `radd-hub/radd_hub.py` → `radd-hub/hub/app.py` (Flask factory)

## Stack
- Backend: Python/Flask (`radd-hub/hub/`)
- Frontend: Jinja2 templates in `radd-hub/hub/templates/`
- DB: SQLite (`settings` k/v table used for all config)
- Mobile: Flutter (`raddflix_flutter/lib/`)
- CI/CD: GitHub Actions (`.github/workflows/build-apk.yml`)

## Phases completed (as of P6)
- **P1–P5**: Core streaming, admin panel, JazzDrive integration, subscriptions, payments
- **P6 (Brand Studio)**: `/brand/` admin section — colors, tagline, logo, onboarding pages, icon/splash upload, GitHub Actions APK trigger from browser

## Key files changed in P6
- `radd-hub/hub/routes/brand_studio.py` — new blueprint (7 routes)
- `radd-hub/hub/templates/brand_studio.html` — new 3-tab admin UI
- `radd-hub/hub/routes/api.py` — /api/config extended with brand_ fields
- `radd-hub/hub/app.py` — brand_studio blueprint registered
- `radd-hub/hub/templates/base.html` — Brand Studio in sidebar
- `raddflix_flutter/lib/core/remote_config.dart` — caches brand_ fields
- `raddflix_flutter/lib/screens/onboarding_screen.dart` — live pages from SharedPreferences
- `raddflix_flutter/lib/screens/splash_screen.dart` — brand_splash_color applied
- `.github/workflows/build-apk.yml` — brand_build input + apply-assets step

## How to read any file
```
curl -H "Authorization: token $GITHUB_TOKEN" https://raw.githubusercontent.com/raddclub/raddflix-app/main/FILENAME
```

## Agent rules (summary)
- Always show user_query popup BEFORE writing any code
- All changes via GitHub API only
- Confirm with popup before each major section
- Update REINCARNATION.md, MASTER_PLAN.md, NEXT_AGENT_PROMPT.md when done
