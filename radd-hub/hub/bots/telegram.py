"""Telegram bot manager for RaddHub v3.0.

Wraps the optional Telegram bot subprocess (Python-based). If no Telegram
bot script is present, all functions return graceful stubs so the admin UI
still renders correctly without errors.
"""
from __future__ import annotations
import logging
import os
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional

from hub import config, db

log = logging.getLogger("hub.bots.telegram")

_BOT_SCRIPT = config.PROJECT_ROOT / "telegram-bot" / "bot.py"
_LOG_FILE   = config.DATA_DIR / "logs" / "telegram-bot.log"

_proc: Optional[subprocess.Popen] = None
_proc_lock = threading.Lock()
_log_lines: list[str] = []
_MAX_LOG_LINES = 300


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

def get_status() -> dict:
    with _proc_lock:
        running = _proc is not None and _proc.poll() is None
    enabled = config.get_env_bool("ENABLE_TELEGRAM_BOT", False)
    has_token = bool(db.setting("TELEGRAM_BOT_TOKEN") or os.environ.get("TELEGRAM_BOT_TOKEN"))
    return {
        "ok":        True,
        "enabled":   enabled,
        "running":   running,
        "has_token": has_token,
        "script":    str(_BOT_SCRIPT),
        "script_exists": _BOT_SCRIPT.exists(),
    }


def get_logs(n: int = 100) -> list[str]:
    lines: list[str] = []
    if _LOG_FILE.exists():
        try:
            all_lines = _LOG_FILE.read_text(errors="replace").splitlines()
            lines = all_lines[-n:]
        except Exception:
            pass
    lines = (_log_lines[-n:] + lines)[-n:]
    return lines


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

def start() -> dict:
    global _proc
    if not _BOT_SCRIPT.exists():
        return {"ok": False,
                "error": "Telegram bot script not found. "
                         "Place your bot at telegram-bot/bot.py in the project root."}

    token = (db.setting("TELEGRAM_BOT_TOKEN") or
             os.environ.get("TELEGRAM_BOT_TOKEN") or "")
    if not token:
        return {"ok": False,
                "error": "TELEGRAM_BOT_TOKEN not set. Add it via Settings → Telegram bot."}

    import sys
    with _proc_lock:
        if _proc is not None and _proc.poll() is None:
            return {"ok": True, "message": "Telegram bot already running", "pid": _proc.pid}

        env = os.environ.copy()
        env["TELEGRAM_BOT_TOKEN"] = token
        _port = config.get_env_int("PORT", 5000)
        env["STREAM_API"] = f"http://localhost:{_port}"
        try:
            _proc = subprocess.Popen(
                [sys.executable, str(_BOT_SCRIPT)],
                cwd=str(_BOT_SCRIPT.parent),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            threading.Thread(target=_read_logs, daemon=True).start()
            log.info("Telegram bot started (pid=%d)", _proc.pid)
            return {"ok": True, "message": "Telegram bot started", "pid": _proc.pid}
        except Exception as e:
            return {"ok": False, "error": str(e)}


def stop() -> dict:
    global _proc
    with _proc_lock:
        if _proc is None or _proc.poll() is not None:
            _proc = None
            return {"ok": True, "message": "Bot was not running"}
        try:
            _proc.terminate()
            try: _proc.wait(timeout=5)
            except subprocess.TimeoutExpired: _proc.kill()
            pid  = _proc.pid
            _proc = None
            log.info("Telegram bot stopped (pid=%d)", pid)
            return {"ok": True, "message": f"Stopped (pid={pid})"}
        except Exception as e:
            return {"ok": False, "error": str(e)}


def restart() -> dict:
    stop()
    time.sleep(1)
    return start()


# ---------------------------------------------------------------------------
# Internal log reader
# ---------------------------------------------------------------------------

def _read_logs():
    global _proc
    if _proc and _proc.stdout:
        for line in _proc.stdout:
            line = line.rstrip()
            _log_lines.append(line)
            if len(_log_lines) > _MAX_LOG_LINES:
                _log_lines.pop(0)
            try:
                config.LOG_DIR.mkdir(parents=True, exist_ok=True)
                with open(str(_LOG_FILE), "a") as f:
                    f.write(line + "\n")
            except Exception:
                pass
