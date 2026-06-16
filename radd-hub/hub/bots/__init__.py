"""Bot process manager for WhatsApp and Telegram.

Spawns and monitors Node.js bot processes in the background.
"""
from __future__ import annotations
import os
import secrets
import subprocess
import threading
import logging
import time
import shutil
from pathlib import Path
from .. import config, installer

log = logging.getLogger("hub.bots")

# Generate a shared API key so the bot can call Flask endpoints without a
# browser session.  Set once at import time so it survives restarts without
# changing (Flask and the bot process both read it from os.environ).
if not os.environ.get("BOT_API_KEY"):
    os.environ["BOT_API_KEY"] = secrets.token_hex(20)

_PROCS: dict[str, subprocess.Popen] = {}
_LOCK = threading.Lock()

def start_all(stop_event: threading.Event) -> None:
    """Start enabled bots and keep them running.
    
    Controlled by .env flags:
      ENABLE_WHATSAPP_BOT=1   — start the WhatsApp bot
      ENABLE_TELEGRAM_BOT=1   — start the Telegram bot
    Both default to 0 (disabled).
    """
    _logged_disabled: set[str] = set()

    while not stop_event.wait(10):
        if config.get_env_bool("ENABLE_WHATSAPP_BOT", False):
            _logged_disabled.discard("whatsapp")
            _ensure_running("whatsapp", config.PROJECT_ROOT / "bots" / "whatsapp")
        else:
            if "whatsapp" not in _logged_disabled:
                log.debug("WhatsApp bot disabled (set ENABLE_WHATSAPP_BOT=1 in .env to enable)")
                _logged_disabled.add("whatsapp")
            _stop("whatsapp")

        if config.get_env_bool("ENABLE_TELEGRAM_BOT", False):
            _logged_disabled.discard("telegram")
            _ensure_running("telegram", config.PROJECT_ROOT / "bots" / "telegram")
        else:
            if "telegram" not in _logged_disabled:
                log.debug("Telegram bot disabled (set ENABLE_TELEGRAM_BOT=1 in .env to enable)")
                _logged_disabled.add("telegram")
            _stop("telegram")


def _ensure_running(name: str, bot_dir: Path) -> None:
    with _LOCK:
        proc = _PROCS.get(name)
        if proc and proc.poll() is None:
            return # Still running

        if not bot_dir.exists():
            log.warning("Bot dir not found: %s — skipping %s", bot_dir, name)
            return

        log.info("Starting %s bot...", name)

        # 1. Extend PATH for Nix/Replit node installations
        installer._extend_path_for_nix()

        # 2. Install deps if needed
        if not installer.ensure_node_deps(bot_dir):
            log.warning("Skipping %s bot (npm install failed)", name)
            return

        # 3. Spawn
        node = shutil.which("node") or shutil.which("node.exe")
        if not node:
            log.warning("node not found; cannot start bot")
            return
            
        try:
            # Pass current env (including BOT_API_KEY) to bot subprocess
            env = os.environ.copy()
            env["RADD_LIBRARY_DB"] = str(config.DATA_DIR / "radd_hub.db")
            env["STREAM_API"]      = f"http://127.0.0.1:{os.environ.get('PORT', 5000)}"

            # Redirect bot stdout/stderr to a log file so errors are visible
            log_path = bot_dir / "bot-node.log"
            log_fh   = open(log_path, "a")

            p = subprocess.Popen(
                [node, "index.js"],
                cwd=str(bot_dir),
                env=env,
                stdout=log_fh,
                stderr=log_fh,
            )
            _PROCS[name] = p
            log.info("✓ %s bot started (PID %d)", name, p.pid)
        except Exception as e:
            log.warning("Failed to start %s bot: %s", name, e)


def _stop(name: str) -> None:
    with _LOCK:
        proc = _PROCS.pop(name, None)
        if proc:
            log.info("Stopping %s bot...", name)
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
