# Radd Hub — RaddFlix Admin Panel & API

Flask-based backend for the RaddFlix streaming platform. Handles admin panel, content management, mobile API, subscriptions, and JazzDrive integration.

**Runs on:** Oracle server `92.4.95.252`  
**Access:** nginx port 80 → Flask port 5000 (port 5000 is firewalled externally)  
**Supervisor service:** `raddflix_radd`  
**Server path:** `/opt/jazzmax/radd-hub/`  

## Quick Reference

```bash
# Restart
sudo supervisorctl restart raddflix_radd

# Logs (live)
sudo supervisorctl tail -f raddflix_radd

# Status
sudo supervisorctl status

# Check API is alive
curl -s http://localhost:5000/api/app/version
```

## Key Routes

| Route | Purpose |
|-------|---------|
| `/admin/` | Admin dashboard (auth required) |
| `/api/app/version` | Version check (public) |
| `/api/app/config` | Remote config for Flutter app |
| `/api/catalog/version` | Catalog version + forced_ts |
| `/api/catalog/sync` | Full catalog sync (JWT required) |
| `/api/catalog/delta` | Delta sync since timestamp (JWT required) |
| `/api/mobile/register` | User registration |
| `/api/mobile/login` | User login |
| `/subscriptions/` | Subscription management |
| `/zero_rating/` | Delta JSON generation + JazzDrive upload |
| `/upload/` | JazzDrive upload queue |
| `/stream/` | Content streaming queue |
| `/analytics/` | Usage analytics |

## Key Files

```
hub/
├── app.py                  ← Flask entry point + blueprints
├── routes/
│   ├── mobile_api.py       ← All /api/mobile/* endpoints
│   ├── catalog_api.py      ← Catalog sync, delta, poster push
│   ├── library.py          ← Trending, search, watch history
│   ├── zero_rating.py      ← Delta JSON + JazzDrive upload
│   ├── subscriptions.py    ← Subscription management
│   └── ...
├── jazzdrive.py            ← JazzDrive API client
├── _legacy/                ← ⚠️ DO NOT DELETE — required by imports
└── templates/              ← Admin panel HTML
data/
├── radd_hub.db             ← SQLCipher database (real data)
└── raddflix.db             ← Legacy empty DB (ignore)
```

## CRITICAL Rules

- **Never delete `hub/_legacy/`** — `jazzdrive.py` and `scanner.py` import from it
- **Never proxy JazzDrive through Oracle** — zero-rating breaks (phone→CDN must be direct)
- **JWT secret** is persisted in `settings` table key `mobile_jwt_secret` — survives restarts
- **Real DB** is `data/radd_hub.db` — the `data/raddflix.db` file is empty legacy

→ Architecture: [`agent-hub/STREAMING_ARCHITECTURE.md`](../agent-hub/STREAMING_ARCHITECTURE.md)
