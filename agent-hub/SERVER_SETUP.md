# RaddFlix — Complete Server Setup & Migration Guide

> **Goal:** Move the backend to any new Ubuntu server in under 30 minutes.  
> Every command is copy-paste ready. Every common error has a fix.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Server Requirements](#2-server-requirements)
3. [System Packages](#3-system-packages)
4. [Clone the Repository](#4-clone-the-repository)
5. [Python Setup](#5-python-setup)
6. [Environment Variables (.env)](#6-environment-variables-env)
7. [Supervisord — Run Flask as a Service](#7-supervisord--run-flask-as-a-service)
8. [Nginx — Reverse Proxy](#8-nginx--reverse-proxy)
9. [Optional: HTTPS with Self-Signed Certificate](#9-optional-https-with-self-signed-certificate)
10. [Database Migration (Old → New Server)](#10-database-migration-old--new-server)
11. [First-Run Verification](#11-first-run-verification)
12. [Routine Operations](#12-routine-operations)
13. [Update Deployed Code](#13-update-deployed-code)
14. [Common Errors and Fixes](#14-common-errors-and-fixes)
15. [Flutter App — Point to New Server](#15-flutter-app--point-to-new-server)

---

## 1. Architecture Overview

```
Flutter App  ──HTTP──▶  nginx :80 (or :443)
                              │
                              ▼
                     Flask :5000  (radd-hub Python app)
                              │
                              ▼
                     SQLite   data/radd_hub.db
```

| Component | Role | Port |
|-----------|------|------|
| nginx | Reverse proxy, rate-limiting, security headers | 80 / 443 |
| Flask (radd-hub) | REST API + admin panel | 5000 (localhost only) |
| SQLite | All persistent data | file |
| supervisord | Keeps Flask alive, auto-restarts on crash | — |

**Current Oracle server:** `ubuntu@92.4.95.252`  
**App directory on Oracle:** `/opt/jazzmax/radd-hub`  
**Supervisor service name:** `raddflix_radd`

---

## 2. Server Requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| RAM | 1 GB | 2 GB |
| CPU | 1 vCPU | 2 vCPU |
| Disk | 10 GB | 50 GB (for media staging) |
| Python | 3.10 | 3.11 or 3.12 |
| User | Any sudoer | `ubuntu` |

---

## 3. System Packages

Run as root / with sudo on the new server:

```bash
sudo apt update && sudo apt upgrade -y

# Core
sudo apt install -y \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev

# Nginx
sudo apt install -y nginx

# Supervisor
sudo apt install -y supervisor

# SQLite CLI (for debugging)
sudo apt install -y sqlite3

# Optional: lxml native libs (speeds up lxml wheel build)
sudo apt install -y libxml2-dev libxslt1-dev

# Optional: Playwright Chromium deps (only needed if scan uses headless browser)
sudo apt install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libxcomposite1 libxdamage1 libxfixes3 \
    libxrandr2 libgbm1 libasound2 libpango-1.0-0 \
    libcairo2 libxshmfence1
```

---

## 4. Clone the Repository

```bash
# Choose your app directory (match whatever is in supervisor/nginx configs)
APPDIR="/opt/jazzmax"
sudo mkdir -p "$APPDIR"
sudo chown ubuntu:ubuntu "$APPDIR"

cd "$APPDIR"
git clone https://github.com/raddclub/raddflix-app.git radd-hub

# Or pull if already cloned:
cd "$APPDIR/radd-hub"
git pull
```

> **Note:** The GitHub repo root IS the `radd-hub` app directory.  
> The Flask package lives at `radd-hub/hub/` inside it.

---

## 5. Python Setup

### Option A — Virtual environment (recommended)

```bash
cd /opt/jazzmax/radd-hub

python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
```

> For Playwright (headless browser scanning), also run:
> ```bash
> playwright install chromium
> playwright install-deps chromium
> ```

### Option B — System-wide (simpler, less isolated)

```bash
cd /opt/jazzmax/radd-hub
pip3 install -r requirements.txt --break-system-packages
```

### Which `requirements.txt`?

Use **`radd-hub/requirements.txt`** (full list):

```
flask>=3.0
werkzeug>=3.0
requests>=2.31
beautifulsoup4>=4.12
lxml>=4.9
python-dotenv>=1.0
watchdog>=3.0
cryptography>=42.0
gspread>=6.0
google-auth>=2.27
google-auth-oauthlib>=1.2
google-auth-httplib2>=0.2
pillow>=10.0
groq>=0.9
psutil>=5.9
colorama>=0.4.6
httpx>=0.27
packaging>=24.0
feedparser>=6.0
playwright>=1.40
flask-cors>=4.0
nest-asyncio
bcrypt>=4.0
```

> The root `requirements.txt` is a shorter subset for Replit CI. Always use `radd-hub/requirements.txt` on the server.

---

## 6. Environment Variables (.env)

Create `/opt/jazzmax/radd-hub/.env`:

```bash
nano /opt/jazzmax/radd-hub/.env
```

### Minimum required variables

```ini
# ─── Flask ───────────────────────────────────────────────────
FLASK_SECRET_KEY=<generate: python3 -c "import secrets; print(secrets.token_hex(32))">
RADD_ADMIN_PASS=<your admin panel password>

# ─── Data paths (optional — defaults to <appdir>/data/) ──────
# DATA_DIR=/opt/jazzmax/radd-hub/data
# MEDIA_DIR=/opt/jazzmax/radd-hub/data/media
# STAGING_DIR=/opt/jazzmax/radd-hub/data/staging

# ─── Feature flags (all optional — defaults shown) ───────────
# ENABLE_MIRROR_RETRY=1
# ENABLE_UPLOAD_WATCHER=1
# ENABLE_DOWNLOAD_QUEUE=1
# ENABLE_SELF_HEAL=1
# ENABLE_SCHEDULER=0
# ENABLE_DOMAIN_DOCTOR=0
# ENABLE_QUALITY_UPGRADE=0

# ─── Logging ─────────────────────────────────────────────────
# LOG_LEVEL=INFO
# LOG_JSON=0

# ─── JazzDrive master switch ─────────────────────────────────
JAZZDRIVE_ENABLED=1
```

### Generate secrets quickly

```bash
# Flask secret key
python3 -c "import secrets; print(secrets.token_hex(32))"

# Admin password (14-char alphanumeric)
python3 -c "import secrets, string; abc=string.ascii_letters+string.digits+'-_'; print(''.join(secrets.choice(abc) for _ in range(14)))"
```

> **If `.env` does not exist:** The app creates it automatically on first run via `config.first_run_bootstrap()`, generating `FLASK_SECRET_KEY` and `RADD_ADMIN_PASS`. Check the supervisor logs after first start to see the generated admin password.

---

## 7. Supervisord — Run Flask as a Service

### Create the supervisor config

```bash
sudo nano /etc/supervisor/conf.d/raddflix_radd.conf
```

Paste:

```ini
[program:raddflix_radd]
directory=/opt/jazzmax/radd-hub
command=/opt/jazzmax/radd-hub/.venv/bin/python radd_hub.py run
; If using system Python (Option B above), use this instead:
; command=python3 /opt/jazzmax/radd-hub/radd_hub.py run
autostart=true
autorestart=true
startretries=5
startsecs=10
stopwaitsecs=30
redirect_stderr=true
stdout_logfile=/var/log/supervisor/raddflix_radd.log
stdout_logfile_maxbytes=20MB
stdout_logfile_backups=5
environment=HOME="/home/ubuntu",USER="ubuntu"
user=ubuntu
```

> **Service name is `raddflix_radd`** — used in every supervisorctl command below.  
> Do NOT use `radd-hub` or `raddflix` — those do not exist.

### Load and start

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start raddflix_radd
sudo supervisorctl status raddflix_radd
```

Expected output:
```
raddflix_radd   RUNNING   pid 12345, uptime 0:00:05
```

### Supervisor quick-reference

```bash
# Status
sudo supervisorctl status raddflix_radd

# Restart (use the script when available — it backs up DB first)
sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh

# Or raw restart (skips backup):
sudo supervisorctl restart raddflix_radd

# Stop
sudo supervisorctl stop raddflix_radd

# Live logs (last 100 lines)
sudo supervisorctl tail -100 raddflix_radd

# Follow logs
sudo tail -f /var/log/supervisor/raddflix_radd.log
```

---

## 8. Nginx — Reverse Proxy

The nginx configs live in the repo at:

```
agent-hub/nginx/raddflix.conf         ← HTTP (port 80)
agent-hub/nginx/raddflix-ssl.conf     ← HTTPS (port 443, self-signed)
```

### Install HTTP config

```bash
# Copy from repo
sudo cp /opt/jazzmax/radd-hub/agent-hub/nginx/raddflix.conf \
        /etc/nginx/sites-available/raddflix

# Enable it
sudo ln -sf /etc/nginx/sites-available/raddflix \
            /etc/nginx/sites-enabled/raddflix

# Disable the default site
sudo rm -f /etc/nginx/sites-enabled/default
```

### Add rate-limiting zones (required by the HTTP config)

The nginx config references rate-limit zones defined in a separate file.  
Create it:

```bash
sudo nano /etc/nginx/conf.d/raddflix_security.conf
```

Paste:

```nginx
# RaddFlix rate-limiting zones
limit_req_zone $binary_remote_addr zone=auth_limit:10m    rate=10r/m;
limit_req_zone $binary_remote_addr zone=register_limit:5m rate=3r/m;
limit_req_zone $binary_remote_addr zone=guest_limit:5m    rate=5r/m;
limit_req_zone $binary_remote_addr zone=api_limit:20m     rate=60r/s;
```

### Test and reload nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl enable nginx
```

### Change the server IP/domain in nginx config

By default the config has `server_name 92.4.95.252 _;`.  
If your new server has a different IP or a domain, edit both lines:

```bash
sudo sed -i 's/92.4.95.252/YOUR_NEW_IP/g' /etc/nginx/sites-available/raddflix
sudo nginx -t && sudo systemctl reload nginx
```

---

## 9. Optional: HTTPS with Self-Signed Certificate

Only do this if the Flutter app is configured to use HTTPS.

```bash
# Generate self-signed cert (valid 1 year)
sudo openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/ssl/private/raddflix.key \
    -out    /etc/ssl/certs/raddflix.crt \
    -subj   "/CN=raddflix/O=RaddFlix/C=PK"

# Install the SSL nginx config
sudo cp /opt/jazzmax/radd-hub/agent-hub/nginx/raddflix-ssl.conf \
        /etc/nginx/sites-available/raddflix-ssl
sudo ln -sf /etc/nginx/sites-available/raddflix-ssl \
            /etc/nginx/sites-enabled/raddflix-ssl

sudo nginx -t && sudo systemctl reload nginx
```

> For a real domain with Let's Encrypt:
> ```bash
> sudo apt install -y certbot python3-certbot-nginx
> sudo certbot --nginx -d yourdomain.com
> ```

---

## 10. Database Migration (Old → New Server)

> **The only file that matters:** `data/radd_hub.db` (~4.3 MB, contains all users, catalog, settings, subscriptions)  
> All other `.db` files on the server are 0-byte ghosts — ignore them.

### Copy DB from Oracle to new server

Run this from Replit (or any machine with SSH access to both servers):

```bash
# 1. SSH into Oracle and dump the DB
ssh ubuntu@92.4.95.252 \
    "sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db '.backup /tmp/radd_hub_backup.db'"

# 2. Copy to new server
scp ubuntu@92.4.95.252:/tmp/radd_hub_backup.db \
    ubuntu@NEW_SERVER_IP:/tmp/radd_hub_backup.db

# 3. On new server: stop Flask, move DB in, start Flask
ssh ubuntu@NEW_SERVER_IP "
    sudo supervisorctl stop raddflix_radd
    mkdir -p /opt/jazzmax/radd-hub/data
    cp /tmp/radd_hub_backup.db /opt/jazzmax/radd-hub/data/radd_hub.db
    chown ubuntu:ubuntu /opt/jazzmax/radd-hub/data/radd_hub.db
    sudo supervisorctl start raddflix_radd
"
```

### Verify DB integrity

```bash
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db "PRAGMA integrity_check;"
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db "SELECT COUNT(*) FROM files;"
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db "SELECT COUNT(*) FROM app_users;"
```

### Database tables reference

| Table | Contents |
|-------|----------|
| `files` | Every JazzDrive file — remote_id, share_url, filename, season/episode |
| `titles` | Movies + TV shows — IMDb ID, title, poster, metadata |
| `accounts` | JazzDrive Jazz SIM accounts |
| `settings` | App config key-value store (read via `db.setting(k)`) |
| `app_users` | Flutter app registered users |
| `user_subscriptions` | Subscription plans per user |
| `watch_history` | Per-user viewing history |
| `scan_log` | Scanner run history |
| `stream_links` | Cached streaming URLs |
| `keys` | API keys vault |

---

## 11. First-Run Verification

### Step 1: Flask health check

```bash
curl -s http://localhost:5000/healthz
# Expected: {"ok": true, "version": "3.0.0"}

curl -s http://localhost:5000/readyz
# Expected: {"ok": true}
```

### Step 2: Nginx health check

```bash
curl -s http://localhost/health
# Expected: RaddFlix Oracle OK

curl -s http://localhost/healthz
# Expected: {"ok": true, "version": "3.0.0"}
```

### Step 3: API endpoint

```bash
curl -s http://localhost/api/config
# Expected: JSON with server config

curl -s http://localhost/api/app/version
# Expected: {"ok": true, "version": "1.0.0"}
```

### Step 4: Admin panel

Open in browser: `http://YOUR_SERVER_IP/admin`  
Login with `RADD_ADMIN_PASS` from `.env`

### Step 5: Full system status

```bash
# Supervisor
sudo supervisorctl status

# Nginx
sudo systemctl status nginx

# DB
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db "SELECT COUNT(*) FROM files;"

# Logs (last 30 lines)
sudo supervisorctl tail -30 raddflix_radd
```

---

## 12. Routine Operations

### Safe restart (with DB backup)

```bash
sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh
```

This script: backs up the DB → restarts Flask → waits for health check.

### Skip backup if in a hurry

```bash
sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh --skip-backup
```

### Manual DB backup

```bash
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
    ".backup /opt/jazzmax/radd-hub/data/backups/radd_hub.$(date +%Y%m%d_%H%M%S).db"
```

Automatic backups run via the nightly script at:
```
/opt/jazzmax/radd-hub/data/backups/radd_hub.YYYYMMDD_HHMMSS.db
```

### View live Flask logs

```bash
sudo tail -f /var/log/supervisor/raddflix_radd.log
```

### Check disk usage

```bash
df -h /opt/jazzmax
du -sh /opt/jazzmax/radd-hub/data/
```

---

## 13. Update Deployed Code

### From Replit (preferred)

```bash
bash push_to_oracle.sh
```

This pulls latest GitHub code on Oracle, installs deps, restarts Flask.

### Manually on the server

```bash
cd /opt/jazzmax/radd-hub
git pull
pip3 install -r requirements.txt --break-system-packages -q
sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh
```

---

## 14. Common Errors and Fixes

---

### ❌ `supervisorctl: command not found`

```bash
sudo apt install -y supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor
```

---

### ❌ `sudo supervisorctl status` shows `raddflix_radd  FATAL  Exited too quickly`

**Check logs:**
```bash
sudo supervisorctl tail -50 raddflix_radd
```

**Most common causes:**

| Error in log | Fix |
|---|---|
| `ModuleNotFoundError: No module named 'flask'` | Run `pip3 install -r requirements.txt --break-system-packages` |
| `ModuleNotFoundError: No module named 'hub'` | Check `directory=` in supervisor conf — must be `/opt/jazzmax/radd-hub`, not `hub/` |
| `Permission denied: '/opt/jazzmax/...'` | `sudo chown -R ubuntu:ubuntu /opt/jazzmax` |
| `Address already in use (port 5000)` | `sudo fuser -k 5000/tcp` then restart |
| `SyntaxError` | Wrong Python version — check `python3 --version`, need 3.10+ |

---

### ❌ nginx `Job for nginx.service failed`

```bash
sudo nginx -t    # shows exact config error
```

Most common: missing rate-limit zones file. Fix:
```bash
sudo nano /etc/nginx/conf.d/raddflix_security.conf
# Paste the limit_req_zone lines from Section 8 above
sudo nginx -t && sudo systemctl restart nginx
```

---

### ❌ `502 Bad Gateway` from nginx

Flask is not running or crashed.

```bash
# Check if Flask is up
curl -s http://localhost:5000/healthz

# If not — check supervisor
sudo supervisorctl status raddflix_radd
sudo supervisorctl tail -30 raddflix_radd
sudo supervisorctl restart raddflix_radd
```

---

### ❌ `403 Forbidden` on `/admin`

Admin session may have expired, or nginx is blocking the request.

```bash
# Test directly (bypass nginx)
curl -s http://localhost:5000/admin
```

If that works, check nginx config is proxying `/admin` correctly.  
If Flask returns 403 too — check `RADD_ADMIN_PASS` in `.env` and log in again.

---

### ❌ Flask starts but returns `500` on all API calls

DB is likely missing or corrupt.

```bash
# Check DB exists and has correct path
ls -lh /opt/jazzmax/radd-hub/data/radd_hub.db

# If 0 bytes or missing — restore from backup:
ls /opt/jazzmax/radd-hub/data/backups/
cp /opt/jazzmax/radd-hub/data/backups/radd_hub.LATEST.db \
   /opt/jazzmax/radd-hub/data/radd_hub.db
sudo supervisorctl restart raddflix_radd
```

---

### ❌ `git pull` fails on server (`error: Your local changes would be overwritten`)

```bash
cd /opt/jazzmax/radd-hub
git stash
git pull
```

---

### ❌ `pip3 install` fails with `externally-managed-environment`

Use `--break-system-packages` or a venv:
```bash
pip3 install -r requirements.txt --break-system-packages
```

---

### ❌ Playwright errors (`Browser not found` / `ExecutableNotFound`)

```bash
python3 -m playwright install chromium
python3 -m playwright install-deps chromium
```

If still failing on headless, install system deps:
```bash
sudo apt install -y libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libpango-1.0-0 libcairo2
```

---

### ❌ JazzDrive session expired after restart

On restart Flask automatically tries to refresh the JSESSIONID using the stored `refresh_token`. If it fails:

1. Go to Admin → Accounts panel
2. Trigger a new OTP login for the affected SIM
3. Enter the OTP — this stores a fresh `refresh_token` (valid months)

Future restarts will renew silently without OTP.

---

### ❌ Flask not reachable from public internet (curl from outside fails)

Check firewall rules:

```bash
# Ubuntu UFW
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw status
```

**Oracle Cloud extra step** — Oracle has a VCN Security List that blocks ports by default.  
Go to: OCI Console → Networking → VCNs → your VCN → Security Lists → Default  
Add Ingress rules for TCP port 80 and 443 from `0.0.0.0/0`.

---

## 15. Flutter App — Point to New Server

The Flutter app reads the server URL from `raddflix_config.json` in the repo root:

```json
{
  "api_base_url": "http://92.4.95.252",
  "min_version_code": 1,
  "update_url": "https://github.com/raddclub/raddflix-app/releases/latest",
  "note": "Update api_base_url here to change the server without rebuilding the APK"
}
```

**To point the app at a new server:**

1. Edit `raddflix_config.json` — change `api_base_url` to the new IP or domain
2. Push to GitHub
3. Existing APKs will pick up the new URL on next config refresh (no rebuild needed)

If the server uses HTTPS with a self-signed cert, also set `ALLOW_SELF_SIGNED=true` in the Flutter build config, or switch to Let's Encrypt.

---

## Quick-Start Checklist (New Server)

```
[ ] Ubuntu 22.04+ with SSH access
[ ] sudo apt update && apt install git nginx supervisor python3 python3-pip python3-venv sqlite3
[ ] git clone https://github.com/raddclub/raddflix-app.git /opt/jazzmax/radd-hub
[ ] cd /opt/jazzmax/radd-hub && python3 -m venv .venv && source .venv/bin/activate
[ ] pip install -r requirements.txt
[ ] Create /opt/jazzmax/radd-hub/.env with FLASK_SECRET_KEY and RADD_ADMIN_PASS
[ ] Create /etc/supervisor/conf.d/raddflix_radd.conf (Section 7)
[ ] sudo supervisorctl reread && update && start raddflix_radd
[ ] curl -s http://localhost:5000/healthz  → {"ok":true}
[ ] Create /etc/nginx/conf.d/raddflix_security.conf (rate zones)
[ ] sudo cp agent-hub/nginx/raddflix.conf /etc/nginx/sites-available/raddflix && ln -sf...
[ ] sudo nginx -t && systemctl reload nginx
[ ] curl -s http://localhost/health → "RaddFlix Oracle OK"
[ ] Copy data/radd_hub.db from old server (Section 10)
[ ] Update raddflix_config.json with new server IP
[ ] Open http://YOUR_IP/admin — login works
[ ] Open http://YOUR_IP/healthz → version 3.0.0
```

---

*Last updated: June 2026 — matches Oracle server at `92.4.95.252`, Flask v3.0.0, supervisord service `raddflix_radd`.*
