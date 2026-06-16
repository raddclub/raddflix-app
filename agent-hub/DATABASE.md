# RaddFlix — Database Reference

> **READ THIS FIRST.** Every session. There are ~15 `.db` files on Oracle. Only ONE has real data.

---

## ⚠️ THE TRAP (why every new agent gets confused)

Running `find /opt/jazzmax -name "*.db"` returns ~15 files:

```
/opt/jazzmax/radd-hub/hub/radd.db           ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/hub/radd_hub.db       ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/hub/raddflix.db       ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/radd.db               ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/radd_hub.db           ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/raddflix.db           ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/hub.db           ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/radd.db          ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/raddflix.db      ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/main.db          ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/raddhub.db       ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/data/jazzmax.db       ← 0 bytes  EMPTY
/opt/jazzmax/radd-hub/hub/_legacy/radd_media.db  ← 204K  OLD scanner DB, NOT active
/opt/jazzmax/radd-hub/data/radd_hub.db      ← 4.3MB  ✅ THE REAL ONE
/opt/jazzmax/radd-hub/data/backups/radd_hub.YYYYMMDD_HHMMSS.db  ← backups (read-only)
```

**Every 0-byte file is a stale artifact from old migration attempts.** They have no tables and no data. Querying them returns nothing. This is what causes agent confusion — the first result of `find` is often one of these empty files.

---

## ✅ THE REAL DATABASE

```
/opt/jazzmax/radd-hub/data/radd_hub.db
```

**Confirmed by**: `hub/config.py` line 29:
```python
DB_PATH = DATA_DIR / "radd_hub.db"   # DATA_DIR = /opt/jazzmax/radd-hub/data
```

Size: **~4.3 MB** (grows as catalog is scanned)

### Tables

| Table | Purpose |
|-------|---------|
| `files` | Every JazzDrive file — `remote_id`, `share_url`, `share_key`, `filename`, `season`, `episode` |
| `titles` | Movies + TV shows — IMDb ID, title, poster, metadata |
| `accounts` | JazzDrive Jazz SIM accounts — `msisdn`, `validation_key`, `jsessionid`, `node` |
| `settings` | App config key-value store — access via `db.setting(k)` NOT `db.get_setting(k)` |
| `app_users` | Flutter app registered users |
| `user_subscriptions` | Subscription plans per user |
| `scan_log` | Scanner run history |
| `stream_links` | Cached JazzDrive streaming URLs |
| `watch_history` | Per-user viewing history |
| `queue` | Upload queue |
| `keys` | API keys |

### Key columns in `files`

| Column | Type | Description |
|--------|------|-------------|
| `remote_id` | TEXT | JazzDrive file ID — used for Pass 0 link generation |
| `share_key` | TEXT | Share folder key (from share URL) |
| `share_url` | TEXT | Full share URL e.g. `https://cloud.jazzdrive.com.pk/share/f/...` |
| `share_folder_id` | TEXT | JazzDrive internal folder ID |
| `share_link_id` | TEXT | Share link ID |
| `filename` | TEXT | Original upload filename |
| `season` | INT | TV season number (NULL for movies) |
| `episode` | INT | TV episode number (NULL for movies) |
| `download_url` | TEXT | Empty — generated at runtime by Dart/Python, never stored |

---

## How to query

```bash
# Always use this path:
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db 'SELECT COUNT(*) FROM files;'

# Check remote_id coverage:
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
  'SELECT COUNT(*) total,
   SUM(CASE WHEN remote_id IS NULL OR remote_id="" THEN 1 ELSE 0 END) missing_rid
   FROM files;'

# Get sample files with share data:
sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
  'SELECT f.remote_id, f.filename, f.share_key, t.title
   FROM files f JOIN titles t ON f.title_id=t.id LIMIT 5;'
```

---

## About `_legacy/radd_media.db`

This 204K file is an **old scanner output DB** from before the current Flask app. It has a different schema (`files` table without `source`, `media_kind`, `github_status` etc.) and was the DB used by the v1 scanner. It is **not connected to Flask** and **not used by the app**. Do not write to it. Do not confuse it with the real DB.

---

## Backups

Automatic backups run every few minutes:
```
/opt/jazzmax/radd-hub/data/backups/radd_hub.YYYYMMDD_HHMMSS.db
```
These are read-only snapshots. The Flask admin panel's "Restore Catalog" restores from the latest backup.

---

## Oracle API (Flask on localhost:5000)

Flask is NOT publicly accessible. Always query via SSH tunnel:
```bash
ssh -i /tmp/oracle_key ubuntu@92.4.95.252 "curl -s http://localhost:5000/healthz"
```

The Flask app reads/writes `radd_hub.db` directly via `hub/db.py`. Use `db.setting(k)` to read settings — `db.get_setting()` does not exist.
