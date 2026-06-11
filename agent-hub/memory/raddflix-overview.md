---
name: RaddFlix project overview
description: What RaddFlix is, where everything lives, who uses it, and the usage pattern that drives all safety decisions
---

## What it is
RaddFlix is a Pakistani streaming app for Jazz SIM users. Videos are stored on JazzDrive (Jazz's cloud storage) which is zero-rated for Jazz SIMs — so users stream for free. The backend ("the Hub") is a Flask app on Oracle Cloud that manages accounts, scanning, and uploading.

## Infrastructure
- Oracle server: ubuntu@92.4.95.252, port 22
- Flask app: /opt/jazzmax/radd-hub/ — supervised as `raddflix_radd`
- WA bot: supervised as `raddflix_wa_bot` (pid ~517687, long-running)
- DB: /opt/jazzmax/radd-hub/data/radd_hub.db (SQLite)
- GitHub repo: raddclub/raddflix-app (branch: main)
- Admin panel served by Flask at port 5000
- Health check: http://localhost:5000/healthz → {"ok":true,"version":"3.0.0"}

## Key code locations
- hub/jazzdrive.py — all JazzDrive API calls
- hub/self_heal.py — background doctors (session guardian, etc.)
- hub/uploader.py — upload queue logic
- hub/routes/upload.py — /jd-stats, /upload-* routes
- hub/templates/upload.html — upload admin UI
- hub/routes/settings.py — settings API routes
- hub/templates/settings.html — settings admin UI
- hub/_legacy/scanner.py — account scanner
- hub/bots/whatsapp.py — WA bot, notify_admins() at line ~212

## DB API (important — easy to get wrong)
- Read setting: `db.setting(key)` — NOT db.get_setting()
- Write setting: `db.set_setting(key, value)`

## Usage pattern (drives all safety decisions)
- Organizer: never used
- Scanner: 1-2x lifetime only (DB rebuild) — uses a separate account
- Uploader: DAILY 2-3 hours — must NEVER get suspended or lose session
- Upload account = most critical asset in the system
