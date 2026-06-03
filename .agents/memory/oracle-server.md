---
name: Oracle Server Location
description: Production server path, supervisor name, git remote, and deploy process
---

## Production server
- Path: `/opt/jazzmax/` (NOT `/home/ubuntu/jazzmax/`)
- Git remote: `github.com/raddclub/raddflix-app` (same repo as Flutter app — monorepo)
- Supervisor service name: `raddflix_radd`
- Python server: `/opt/jazzmax/radd-hub/radd_hub.py run --skip-setup`
- Port: 5000 (behind nginx/proxy on 80)

## Key server files
- Mobile API routes: `/opt/jazzmax/radd-hub/hub/routes/mobile_api.py`
- Catalog API routes: `/opt/jazzmax/radd-hub/hub/routes/catalog_api.py`
- XOR encoding middleware: `/opt/jazzmax/radd-hub/hub/routes/request_encoding.py`
- App factory (blueprint registration): `/opt/jazzmax/radd-hub/hub/app.py`

## Deploy process
1. Push to GitHub from Replit or Oracle
2. On Oracle: `cd /opt/jazzmax && git pull && sudo supervisorctl restart raddflix_radd`
3. Script: `bash push_to_oracle.sh` (from Replit workspace)
4. GitHub Actions auto-builds APK on every push touching `raddflix_flutter/**`

**Why:** The /home/ubuntu/jazzmax/ path is a dev scratch copy; /opt/jazzmax/ is what supervisord runs.
