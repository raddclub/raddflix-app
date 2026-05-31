# Radd Hub v3.0 — Flask Admin Panel

## What it is
The admin panel for RaddFlix. Admins manage content (movies/dramas), users, subscriptions, payments, and analytics from a web dashboard. Also serves ALL mobile API routes (auth, catalog, search, history, notifications, usage).

## Location
- **Server:** `/opt/jazzmax/radd-hub/`
- **GitHub:** `radd-hub/` folder in `raddclub/raddflix-app`
- **Runs on:** port 5000 (supervisor service: `raddflix_radd`)

## Tech Stack
- Python 3.12
- Flask (blueprints pattern)
- SQLite database
- Jinja2 templates
- Gunicorn (production WSGI)

## Key Files

| File | Purpose |
|------|---------|
| `hub/app.py` | Flask app factory, registers all blueprints, /health route |
| `hub/routes/library.py` | Content library API (movies, dramas, trending) |
| `hub/routes/mobile_api.py` | ALL mobile API (auth, subscription, history, usage, notifications) |
| `hub/routes/catalog_api.py` | Flutter catalog sync (version/sync/delta/posters) |
| `hub/routes/search_api.py` | Flutter app search |
| `hub/routes/stream.py` | Admin stream URL generation (calls JazzDrive server-side for admin use only) |
| `hub/routes/subscriptions.py` | Subscription management |
| `hub/routes/analytics.py` | View stats, watch counts |
| `hub/jazzdrive.py` | JazzDrive CDN integration (admin/server-side only) |
| `hub/scanner.py` | Content scanner (scans JazzDrive for new content) |
| `hub/_legacy/` | **DO NOT TOUCH** — jazzdrive.py and scanner.py import from here |
| `hub/templates/` | Jinja2 HTML templates for admin UI |

## How to Restart

```bash
sudo supervisorctl restart raddflix_radd
sudo supervisorctl status
```

## How to Check Logs

```bash
sudo supervisorctl tail -f raddflix_radd
# or
tail -f /var/log/supervisor/raddflix_radd-stdout.log
```

## Routes / Endpoints (summary)

| Route | Method | Purpose |
|-------|--------|---------|
| `/` | GET | Admin dashboard home |
| `/api/catalog/sync` | GET | Flutter catalog sync (full or delta) |
| `/api/search` | GET | Flutter app search |
| `/api/auth/*` | POST | Mobile auth (login, register, guest, device) |
| `/api/subscription/*` | GET/POST | Subscription plans and status |
| `/api/history/*` | GET/POST | Watch history |
| `/api/usage/*` | GET/POST | Data usage tracking |
| `/health` | GET | Health check (returns "RaddFlix Oracle OK") |
| `/admin/users` | GET | User management |

## Database
- SQLite file on server: `/opt/jazzmax/radd-hub/data/raddflix.db`
- Schema managed in `hub/db.py` (25+ tables)

## CRITICAL: _legacy folder
`hub/_legacy/` contains early JazzDrive auth code. `jazzdrive.py` and `scanner.py` import from here.
If this folder is missing, the service fails to start with ImportError.
It IS in GitHub (commit 1a65f8c8). A fresh `git pull` on the server includes it.

→ Full documentation: [`agent-hub/projects/radd-hub.md`](../agent-hub/projects/radd-hub.md)
