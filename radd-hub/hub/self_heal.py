"""Advanced self-healing engine for Radd Hub v3.

Six independent doctors run on their own schedules inside one background
thread.  Each doctor is idempotent — safe to run multiple times — and
records its result in the shared _HEALTH dict that the
/api/health/badges endpoint exposes to the UI.

  thread_watchdog    60 s  — detect & restart dead background threads
  db_doctor         300 s  — PRAGMA integrity_check + rolling DB backup
  dep_doctor        900 s  — verify Python packages, auto pip-install missing
  fs_doctor         300 s  — ensure required dirs, purge stale temp files
  disk_doctor       600 s  — clean cache when disk space runs low
  config_doctor     600 s  — write sensible defaults for missing DB settings
  badge_updater      30 s  — refresh /api/health/badges with live status

Thread watchdog registration:
    self_heal.register_thread("name", target_fn, (stop_event,))
    Call this right after every threading.Thread(...).start() in app.py.
"""
from __future__ import annotations
import os
import sys
import time
import shutil
import logging
import threading
import subprocess
import sqlite3
from pathlib import Path
from typing import Callable, Optional
from . import config, db

log = logging.getLogger("hub.self_heal")

# ─────────────────────────────────────────────────────────────────────────────
# Public health state  (read by /api/health/badges)
# ─────────────────────────────────────────────────────────────────────────────
_HEALTH_LOCK = threading.Lock()
_HEALTH: dict[str, dict] = {
    "downloader": {"status": "unknown", "label": "Starting…", "ts": 0},
    "flix":       {"status": "unknown", "label": "Starting…", "ts": 0},
    "jd_indexer": {"status": "unknown", "label": "Starting…", "ts": 0},
    "bot":        {"status": "unknown", "label": "Starting…", "ts": 0},
    "system":     {"status": "unknown", "label": "Starting…", "ts": 0},
}

def set_health(key: str, status: str, label: str) -> None:
    """status: 'ok' | 'warn' | 'err' | 'unknown'"""
    with _HEALTH_LOCK:
        _HEALTH[key] = {"status": status, "label": label, "ts": int(time.time())}

def get_health() -> dict:
    with _HEALTH_LOCK:
        return {k: dict(v) for k, v in _HEALTH.items()}


# ─────────────────────────────────────────────────────────────────────────────
# Thread watchdog registry
# ─────────────────────────────────────────────────────────────────────────────
_REG_LOCK = threading.Lock()
_THREAD_REG: dict[str, dict] = {}
# {name: {factory, args, stop_event, restart_count, last_restart, cooldown_s}}

def register_thread(name: str, factory: Callable, args: tuple,
                    stop_event: threading.Event) -> None:
    """Register a restartable thread.  Call immediately after .start()."""
    with _REG_LOCK:
        _THREAD_REG[name] = {
            "factory":       factory,
            "args":          args,
            "stop_event":    stop_event,
            "restart_count": 0,
            "last_restart":  0.0,
            "cooldown_s":    60,      # doubles on repeated failures, cap 3600
        }
    log.debug("self_heal: registered thread '%s'", name)


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: thread watchdog
# ─────────────────────────────────────────────────────────────────────────────
def _thread_watchdog() -> dict:
    alive_names = {t.name for t in threading.enumerate()}
    fixed = []
    issues = []

    with _REG_LOCK:
        reg_copy = dict(_THREAD_REG)

    for name, info in reg_copy.items():
        if name in alive_names:
            continue  # healthy
        now = time.time()
        cooldown_until = info["last_restart"] + info["cooldown_s"]
        if now < cooldown_until:
            remaining = int(cooldown_until - now)
            log.debug("self_heal: '%s' dead — cooldown %ds remaining", name, remaining)
            issues.append(f"{name} (cooldown {remaining}s)")
            continue
        # Restart
        try:
            t = threading.Thread(
                target=info["factory"], args=info["args"],
                daemon=True, name=name,
            )
            t.start()
            new_count = info["restart_count"] + 1
            new_cooldown = min(info["cooldown_s"] * 2, 3600)
            with _REG_LOCK:
                _THREAD_REG[name]["restart_count"] = new_count
                _THREAD_REG[name]["last_restart"]  = now
                _THREAD_REG[name]["cooldown_s"]    = new_cooldown
            log.warning("self_heal: restarted dead thread '%s' (restart #%d)", name, new_count)
            fixed.append(f"{name} (restart #{new_count})")
            # Notify admins if thread has crashed repeatedly
            if new_count >= 3:
                _notify_admins(
                    f"⚠️ Radd Hub: thread '{name}' has crashed {new_count} times. "
                    f"It has been restarted automatically."
                )
        except Exception as e:
            log.error("self_heal: failed to restart '%s': %s", name, e)
            issues.append(f"{name} (restart failed: {e})")

    return {"fixed": fixed, "issues": issues}


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: database
# ─────────────────────────────────────────────────────────────────────────────
_DB_BACKUP_DIR = config.DATA_DIR / "backups"
_MAX_BACKUPS   = 30

def _db_doctor() -> dict:
    db_path = config.DB_PATH
    if not db_path.exists():
        return {"ok": False, "error": "DB file missing"}

    # 1. WAL checkpoint + integrity check using a single connection
    try:
        con = sqlite3.connect(str(db_path), timeout=10)
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        result = con.execute("PRAGMA integrity_check").fetchone()
        integrity_ok = (result and result[0] == "ok")
        con.close()
    except Exception as e:
        integrity_ok = False
        log.error("self_heal db_doctor: integrity check failed: %s", e)
        try:
            con.close()
        except Exception:
            pass

    if not integrity_ok:
        log.error("self_heal db_doctor: DB corruption detected — attempting restore")
        _restore_latest_backup(db_path)
        _apply_emergency_tokens()
        return {"ok": False, "action": "restore_attempted"}

    # 2. Rolling backup using SQLite native backup API (safe with WAL mode)
    _DB_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    ts_str = time.strftime("%Y%m%d_%H%M%S")
    bak    = _DB_BACKUP_DIR / f"radd_hub.{ts_str}.db"
    try:
        src_con = sqlite3.connect(str(db_path), timeout=10)
        dst_con = sqlite3.connect(str(bak), timeout=10)
        src_con.backup(dst_con)
        dst_con.close()
        src_con.close()
    except Exception as e:
        log.warning("self_heal db_doctor: backup failed: %s", e)
        try:
            dst_con.close()
            src_con.close()
        except Exception:
            pass
        return {"ok": True, "backup": False}

    # 3. Prune old backups (keep _MAX_BACKUPS most recent)
    backups = sorted(_DB_BACKUP_DIR.glob("radd_hub.*.db"), key=lambda f: f.stat().st_mtime)
    while len(backups) > _MAX_BACKUPS:
        try:
            backups.pop(0).unlink()
        except Exception:
            break

    return {"ok": True, "backup": str(bak.name)}


def _apply_emergency_tokens() -> None:
    """After a DB restore, re-inject the latest refresh tokens from the emergency file.
    This prevents losing a rotated token that was saved after the last DB backup."""
    efile = config.DATA_DIR / "auth" / "emergency_tokens.json"
    if not efile.exists():
        return
    try:
        import json as _json
        tokens = _json.loads(efile.read_text())
        with db.conn() as c:
            for acct_id_str, info in tokens.items():
                rt  = info.get("refresh_token") or ""
                raw = info.get("raw_accesstoken") or ""
                if not rt:
                    continue
                c.execute(
                    "UPDATE accounts SET refresh_token=?, raw_accesstoken=COALESCE(NULLIF(?,''),raw_accesstoken) WHERE id=?",
                    (rt, raw, int(acct_id_str))
                )
        log.info("self_heal: emergency tokens applied to %d account(s) after restore", len(tokens))
    except Exception as e:
        log.warning("self_heal: emergency token apply failed: %s", e)


def _restore_latest_backup(db_path: Path) -> bool:
    backups = sorted(_DB_BACKUP_DIR.glob("radd_hub.*.db"),
                     key=lambda f: f.stat().st_mtime, reverse=True)
    if not backups:
        log.error("self_heal: no backups found — cannot restore DB")
        return False
    try:
        shutil.copy2(str(backups[0]), str(db_path))
        log.warning("self_heal: DB restored from %s", backups[0].name)
        return True
    except Exception as e:
        log.error("self_heal: DB restore failed: %s", e)
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: Python dependencies
# ─────────────────────────────────────────────────────────────────────────────
_CRITICAL_PACKAGES = {
    "requests":   "requests",
    "flask":      "flask",
    "bs4":        "beautifulsoup4",
    "lxml":       "lxml",
    "PIL":        "Pillow",
    "feedparser": "feedparser",
    "dotenv":     "python-dotenv",
}

def _pip_install(pkg_name: str) -> bool:
    """Try pip install with multiple strategies for Replit/NixOS compatibility."""
    strategies = [
        [sys.executable, "-m", "pip", "install", "-q", pkg_name],
        [sys.executable, "-m", "pip", "install", "-q", "--break-system-packages", pkg_name],
        [sys.executable, "-m", "pip", "install", "-q", "--user", pkg_name],
    ]
    for cmd in strategies:
        try:
            result = subprocess.run(cmd, timeout=120, capture_output=True)
            if result.returncode == 0:
                return True
        except Exception:
            continue
    return False


def _dep_doctor() -> dict:
    missing = []
    for import_name, pkg_name in _CRITICAL_PACKAGES.items():
        try:
            __import__(import_name)
        except ImportError:
            log.warning("self_heal dep_doctor: missing '%s' — attempting install", pkg_name)
            if _pip_install(pkg_name):
                log.info("self_heal dep_doctor: installed '%s'", pkg_name)
                missing.append(f"{pkg_name} (installed)")
            else:
                log.error("self_heal dep_doctor: pip install '%s' failed", pkg_name)
                missing.append(f"{pkg_name} (FAILED)")

    # Node modules for bot
    bot_dir  = config.HUB_DIR.parent / "bots" / "whatsapp"
    nm_dir   = bot_dir / "node_modules"
    pkg_json = bot_dir / "package.json"
    if pkg_json.exists() and not nm_dir.exists():
        log.warning("self_heal dep_doctor: node_modules missing — running npm install")
        try:
            subprocess.run(
                ["npm", "install", "--prefer-offline"],
                cwd=str(bot_dir), timeout=180, check=True,
                capture_output=True,
            )
            log.info("self_heal dep_doctor: npm install OK")
            missing.append("node_modules (installed)")
        except Exception as e:
            log.error("self_heal dep_doctor: npm install failed: %s", e)

    return {"ok": not missing, "fixed": missing}


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: filesystem
# ─────────────────────────────────────────────────────────────────────────────
_STALE_PATTERNS   = ["*.part", "*.tmp", "*.!ut", "ka-*.bin", "*.crdownload"]
_STALE_AGE_SECS   = 3600   # 1 hour

def _fs_doctor() -> dict:
    dirs = [config.MEDIA_DIR, config.STAGING_DIR, config.CACHE_DIR, config.DATA_DIR,
            config.DATA_DIR / "backups"]
    created = []
    for d in dirs:
        if not d.exists():
            try:
                d.mkdir(parents=True, exist_ok=True)
                created.append(str(d))
                log.info("self_heal fs_doctor: created missing dir %s", d)
            except Exception as e:
                log.warning("self_heal fs_doctor: could not create %s: %s", d, e)

    # Purge stale temp files from media, staging, and cache dirs
    purged = 0
    cutoff = time.time() - _STALE_AGE_SECS
    for search_dir in [config.MEDIA_DIR, config.STAGING_DIR, config.CACHE_DIR]:
        if not search_dir.exists():
            continue
        for pattern in _STALE_PATTERNS:
            for f in search_dir.rglob(pattern):
                try:
                    if f.stat().st_mtime < cutoff:
                        f.unlink()
                        purged += 1
                except Exception:
                    pass

    return {"ok": True, "created_dirs": created, "purged_files": purged}


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: disk space
# ─────────────────────────────────────────────────────────────────────────────
_WARN_FREE_MB    = 500
_CRITICAL_FREE_MB = 100

def _disk_doctor() -> dict:
    try:
        usage = shutil.disk_usage(str(config.DATA_DIR))
        free_mb = usage.free // (1024 * 1024)
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if free_mb < _CRITICAL_FREE_MB:
        log.error("self_heal disk_doctor: CRITICAL low disk: %d MB free — purging cache", free_mb)
        _aggressive_cache_clean()
        _notify_admins(f"⚠️ Radd Hub: disk critically low ({free_mb} MB). Cache purged.")
        return {"ok": False, "free_mb": free_mb, "action": "purged_cache"}

    if free_mb < _WARN_FREE_MB:
        log.warning("self_heal disk_doctor: low disk: %d MB free", free_mb)
        return {"ok": False, "free_mb": free_mb, "warning": "low_disk"}

    return {"ok": True, "free_mb": free_mb}


def _aggressive_cache_clean() -> None:
    """Delete everything in CACHE_DIR and old log files."""
    if config.CACHE_DIR.exists():
        for f in config.CACHE_DIR.iterdir():
            try:
                if f.is_file():
                    f.unlink()
            except Exception:
                pass
    # Remove log files older than 7 days
    log_dir = config.LOG_DIR
    if log_dir.exists():
        cutoff = time.time() - 7 * 86400
        for f in log_dir.glob("*.log*"):
            try:
                if f.stat().st_mtime < cutoff:
                    f.unlink()
            except Exception:
                pass


# ─────────────────────────────────────────────────────────────────────────────
# Doctor: config defaults
# ─────────────────────────────────────────────────────────────────────────────
_REQUIRED_SETTINGS: dict[str, str] = {
    "upload_parallel_uploads":  "1",
    "upload_max_file_size_gb":  "0",
    "upload_chunk_size_mb":     "4",
    "upload_max_retries":       "3",
    "upload_retry_base_delay":  "2",
    "upload_auto_delete":       "true",
    "upload_bandwidth_limit_mbps": "0",
    "keepalive_interval_min":   "15",
    "download_max_parallel":    "2",
    "bot_notify_on_done":       "true",
}

def _config_doctor() -> dict:
    fixed = []
    for key, default in _REQUIRED_SETTINGS.items():
        if db.setting(key) is None:
            db.set_setting(key, default)
            fixed.append(key)
    return {"ok": True, "defaulted": fixed}


# ─────────────────────────────────────────────────────────────────────────────
# Badge updater — assembles _HEALTH from live data every 30 s
# ─────────────────────────────────────────────────────────────────────────────
def _update_badges() -> None:
    now = int(time.time())
    alive = {t.name for t in threading.enumerate()}

    # ── Downloader ────────────────────────────────────────────────────────────
    try:
        thread_ok = "download-queue" in alive
        rows = []
        with db.conn() as c:
            rows = c.execute(
                "SELECT status FROM queue WHERE status IN ('queued','running') LIMIT 20"
            ).fetchall()
        active_jobs = sum(1 for r in rows if r["status"] == "running")
        queued_jobs = sum(1 for r in rows if r["status"] == "queued")
        if not thread_ok:
            set_health("downloader", "err", "Worker stopped")
        elif active_jobs:
            set_health("downloader", "ok", f"{active_jobs} downloading")
        elif queued_jobs:
            set_health("downloader", "ok", f"{queued_jobs} queued")
        else:
            set_health("downloader", "ok", "Idle")
    except Exception as e:
        set_health("downloader", "warn", f"Error: {str(e)[:30]}")

    # ── Flix ──────────────────────────────────────────────────────────────────
    try:
        thread_ok = "upload-watcher" in alive
        flix_accounts = db.list_accounts(role="flix", hide_secrets=False)
        # Account is "ok" if token is fresh OR it has a refresh_token/raw_accesstoken
        # to silently renew — OTP is only required when neither exists.
        ok_sessions = [a for a in flix_accounts
                       if (a.get("token_expires_at") and a["token_expires_at"] > now)
                       or (a.get("refresh_token") or "").strip()
                       or (a.get("raw_accesstoken") or "").strip()]
        
        has_silent_path = any((a.get("refresh_token") or "").strip() or 
                              (a.get("raw_accesstoken") or "").strip() for a in flix_accounts)

        if not thread_ok:
            set_health("flix", "err", "Watcher stopped")
        elif not flix_accounts:
            set_health("flix", "warn", "No account set")
        elif not ok_sessions:
            set_health("flix", "err", "Re-login required")
        else:
            # Cross-check with actual keepalive heartbeat results.
            ka_dead = False
            ka_cf   = 0
            try:
                from . import keepalive as _ka
                ka_data = _ka.get_status()
                for acct_st in ka_data.get("accounts", {}).values():
                    ka_cf = max(ka_cf, acct_st.get("consecutive_failures", 0))
                if ka_cf >= 3:
                    ka_dead = True
            except Exception:
                pass

            # Also flag dead when the error message clearly says OTP is required,
            # even before 3 consecutive failures accumulate.
            if not ka_dead:
                try:
                    from . import keepalive as _ka2
                    for _st in _ka2.get_status().get("accounts", {}).values():
                        _err = (_st.get("last_error") or "").lower()
                        if ("invalid_grant" in _err or "otp required" in _err
                                or "otp re-login" in _err or "refresh failed" in _err):
                            if _st.get("consecutive_failures", 0) >= 1:
                                ka_dead = True
                                ka_cf = _st.get("consecutive_failures", 1)
                        break
                except Exception:
                    pass

            if ka_dead:
                # Gather last error to decide whether silent refresh can recover.
                ka_last_err = ""
                try:
                    from . import keepalive as _ka2
                    for _st in _ka2.get_status().get("accounts", {}).values():
                        ka_last_err = (_st.get("last_error") or "").lower()
                        break
                except Exception:
                    pass
                refresh_broken = (
                    "invalid_grant" in ka_last_err
                    or "otp required" in ka_last_err
                    or "otp re-login" in ka_last_err
                    or "refresh failed" in ka_last_err
                )
                # After 5+ consecutive failures or a confirmed broken refresh,
                # the silent-refresh path is exhausted — escalate to re-login.
                if has_silent_path and ka_cf < 5 and not refresh_broken:
                    set_health("flix", "warn", "Refreshing session…")
                else:
                    set_health("flix", "err", "Re-login required")
            else:
                # token_expires_at check for "Session active"
                expiring = [a for a in ok_sessions
                            if a.get("token_expires_at", 0) - now < 600]
                if expiring and has_silent_path:
                    set_health("flix", "warn", "Refreshing session…")
                else:
                    set_health("flix", "ok", "Session active")
    except Exception as e:
        set_health("flix", "warn", f"Error: {str(e)[:30]}")

    # ── JD Indexer ────────────────────────────────────────────────────────────
    try:
        scan_accounts = db.list_accounts(role="scan")
        linked = [a for a in scan_accounts if a.get("token_expires_at")]
        if not scan_accounts:
            set_health("jd_indexer", "warn", "No accounts")
        elif not linked:
            set_health("jd_indexer", "warn", f"{len(scan_accounts)} not linked")
        else:
            set_health("jd_indexer", "ok",
                       f"{len(linked)}/{len(scan_accounts)} linked")
    except Exception as e:
        set_health("jd_indexer", "warn", f"Error: {str(e)[:30]}")

    # ── Bot Manager ───────────────────────────────────────────────────────────
    try:
        bot_ok = "bot-manager" in alive
        wa_state = "unknown"
        try:
            from .bots import whatsapp as _wa
            st = _wa.get_status()
            if st.get("connected"):
                wa_state = "connected"
            elif st.get("running"):
                wa_state = "connecting"
            else:
                wa_state = "closed"
        except Exception:
            with db.conn() as c:
                row = c.execute(
                    "SELECT state FROM bot_status_index WHERE fingerprint='wa-bot-state' LIMIT 1"
                ).fetchone()
            wa_state = (row["state"] if row else "unknown").lower()
        if not bot_ok:
            set_health("bot", "err", "Manager stopped")
        elif wa_state in ("open", "connected"):
            set_health("bot", "ok", "Connected")
        elif wa_state in ("close", "disconnected", "timeout"):
            set_health("bot", "err", "Disconnected")
        elif wa_state in ("connecting", "qr"):
            set_health("bot", "warn", "Connecting…")
        else:
            set_health("bot", "warn", "Status unknown")
    except Exception as e:
        set_health("bot", "warn", "Bot status N/A")

    # ── System ────────────────────────────────────────────────────────────────
    try:
        usage    = shutil.disk_usage(str(config.DATA_DIR))
        free_mb  = usage.free // (1024 * 1024)
        expected = {"mirror-retry", "upload-watcher", "download-queue",
                    "keepalive", "bot-manager"}
        dead     = expected - alive
        if dead:
            set_health("system", "warn", f"{len(dead)} thread(s) down")
        elif free_mb < _WARN_FREE_MB:
            set_health("system", "warn", f"Low disk: {free_mb}MB")
        else:
            set_health("system", "ok", f"All healthy")
    except Exception as e:
        set_health("system", "warn", "Check failed")


# ─────────────────────────────────────────────────────────────────────────────
# Notification helper
# ─────────────────────────────────────────────────────────────────────────────
def _notify_admins(msg: str) -> None:
    try:
        from .bots import whatsapp as _wa
        _wa.notify_admins(msg)
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# Scheduler — one thread, multiple doctors on independent intervals
# ─────────────────────────────────────────────────────────────────────────────
_SCHEDULE = [
    # (name,              fn,               interval_s)
    ("badge_updater",  _update_badges,    30),
    ("thread_watchdog",_thread_watchdog,  60),
    ("fs_doctor",      _fs_doctor,        300),
    ("db_doctor",      _db_doctor,        60),
    ("disk_doctor",    _disk_doctor,      600),
    ("config_doctor",  _config_doctor,    600),
    ("dep_doctor",     _dep_doctor,       900),
]


def loop(stop_event: threading.Event) -> None:
    """Main self-heal loop.  Wakes every 10 s and dispatches due doctors."""
    log.info("self_heal: engine started (%d doctors)", len(_SCHEDULE))

    # Track last-run time for each doctor
    last_run = {name: 0.0 for name, _, _ in _SCHEDULE}

    # Run config_doctor immediately so defaults are set before anything else
    try:
        _config_doctor()
    except Exception:
        pass

    while not stop_event.wait(10):
        now = time.time()
        for name, fn, interval_s in _SCHEDULE:
            if now - last_run[name] < interval_s:
                continue
            last_run[name] = now
            try:
                result = fn()
                if isinstance(result, dict):
                    issues = result.get("issues") or result.get("fixed") or []
                    if issues:
                        log.info("self_heal [%s]: %s", name, issues)
            except Exception as e:
                log.warning("self_heal [%s] error: %s", name, e)

    log.info("self_heal: engine stopped")
