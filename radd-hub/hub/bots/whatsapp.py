"""WhatsApp bot manager for RaddHub v3.0.

Wraps the v2 Node.js Baileys bot. Manages the subprocess lifecycle,
reads pairing codes, monitors QR/status, and exposes a clean Python API.
"""
from __future__ import annotations
import json
import logging
import os
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional

from hub import config, db

log = logging.getLogger("hub.bots.whatsapp")

# Paths — prefer a locally bundled bot dir; fall back to the sibling v2 install.
# Override by setting WA_BOT_DIR in .env.
_LOCAL_BOT_DIR = config.PROJECT_ROOT / "bots" / "whatsapp"
_V2_BOT_DIR    = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "whatsapp-bot"

def _resolve_bot_dir() -> Path:
    override = config.get_env("WA_BOT_DIR", "").strip()
    if override:
        return Path(override)
    if _LOCAL_BOT_DIR.exists():
        return _LOCAL_BOT_DIR
    return _V2_BOT_DIR

V2_BOT_DIR       = _resolve_bot_dir()   # canonical; re-exported for admin/bots routes
AUTH_DIR         = V2_BOT_DIR / "auth_info"
QR_PNG           = V2_BOT_DIR / "whatsapp-qr.png"
STATE_FILE       = V2_BOT_DIR / "bot-state.json"
DEBUG_LOG        = V2_BOT_DIR / "bot-debug.log"
PAIRING_NUM_FILE = V2_BOT_DIR / "pairing-number.txt"

_proc: Optional[subprocess.Popen] = None
_proc_lock = threading.Lock()
_log_lines: list[str] = []
_MAX_LOG_LINES = 500


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

def get_status() -> dict:
    """Return bot status dict."""
    with _proc_lock:
        running = _proc is not None and _proc.poll() is None

    state: dict = {}
    if STATE_FILE.exists():
        try:
            state = json.loads(STATE_FILE.read_text())
        except Exception:
            pass

    auth_exists = (AUTH_DIR / "creds.json").exists()
    # Pairing code is written to bot-state.json by the Node bot under "pairing_code".
    # pairing-number.txt holds the *phone number* used to request the code, not the code itself.
    pairing_code = state.get("pairing_code") or None

    return {
        "running": running,
        "connected": state.get("connected", False),
        "phone": state.get("bot_number", "") or state.get("botNum", "") or db.setting("WA_PHONE", ""),
        "auth_exists": auth_exists,
        "pairing_code": pairing_code,
        "state": state,
    }


def get_logs(n: int = 100) -> list[str]:
    """Return last n log lines from the bot debug log."""
    lines: list[str] = []
    if DEBUG_LOG.exists():
        try:
            all_lines = DEBUG_LOG.read_text(errors="replace").splitlines()
            lines = all_lines[-n:]
        except Exception:
            pass
    # Also include in-memory lines from this session
    lines = (_log_lines[-n:] + lines)[-n:]
    return lines


# ---------------------------------------------------------------------------
# Start / stop
# ---------------------------------------------------------------------------

def start() -> dict:
    """Start the WhatsApp bot subprocess (reuses existing v2 session)."""
    global _proc
    if not V2_BOT_DIR.exists():
        return {"ok": False, "error": f"Bot directory not found: {V2_BOT_DIR}"}

    # Check Node.js available
    import shutil
    node_bin = shutil.which("node")
    if not node_bin:
        return {"ok": False, "error": "node not found in PATH — install Node.js"}

    # Install npm deps if needed
    node_modules = V2_BOT_DIR / "node_modules"
    if not node_modules.exists():
        log.info("Installing WhatsApp bot npm dependencies...")
        r = subprocess.run(
            ["npm", "install", "--no-audit", "--no-fund"],
            cwd=str(V2_BOT_DIR),
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0:
            return {"ok": False, "error": f"npm install failed: {r.stderr[:500]}"}

    with _proc_lock:
        if _proc is not None and _proc.poll() is None:
            return {"ok": True, "message": "Bot already running", "pid": _proc.pid}

        env = os.environ.copy()
        _port = config.get_env_int("PORT", 5000)
        stream_api = os.environ.get("STREAM_API") or f"http://localhost:{_port}"
        env["STREAM_API"] = stream_api
        env["NODE_ENV"] = "production"

        try:
            _proc = subprocess.Popen(
                [node_bin, "index.js"],
                cwd=str(V2_BOT_DIR),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            # Background log reader
            threading.Thread(target=_read_logs, daemon=True).start()
            log.info("WhatsApp bot started (pid=%d)", _proc.pid)
            return {"ok": True, "message": "WhatsApp bot started", "pid": _proc.pid}
        except Exception as e:
            log.error("start error: %s", e)
            return {"ok": False, "error": str(e)}


def stop() -> dict:
    """Stop the WhatsApp bot subprocess."""
    global _proc
    with _proc_lock:
        if _proc is None or _proc.poll() is not None:
            _proc = None
            return {"ok": True, "message": "Bot was not running"}
        try:
            _proc.terminate()
            try:
                _proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _proc.kill()
            pid = _proc.pid
            _proc = None
            log.info("WhatsApp bot stopped (pid=%d)", pid)
            return {"ok": True, "message": f"Bot stopped (pid={pid})"}
        except Exception as e:
            return {"ok": False, "error": str(e)}


def restart() -> dict:
    stop()
    time.sleep(1)
    return start()


def request_pairing_code(phone: str) -> dict:
    """Write pairing-number.txt so the bot generates a pairing code on next start."""
    if not phone:
        return {"ok": False, "error": "Phone number required"}
    phone = phone.replace("+", "").replace(" ", "").replace("-", "")
    try:
        PAIRING_NUM_FILE.write_text(phone)
        # Touch .pairing-request sentinel
        (V2_BOT_DIR / ".pairing-request").touch()
        db.set_setting("WA_PHONE", phone)
        log.info("Pairing code requested for %s", phone)
        return {"ok": True, "message": f"Pairing code will appear after bot starts (phone: {phone})"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def relink() -> dict:
    """Wipe auth_info + state file and restart so the bot shows a fresh QR/pairing."""
    stop()
    time.sleep(0.5)
    import shutil as _shutil
    try:
        if AUTH_DIR.exists():
            _shutil.rmtree(str(AUTH_DIR))
        if STATE_FILE.exists():
            STATE_FILE.unlink()
        if QR_PNG.exists():
            QR_PNG.unlink()
        (_BOT_RELINK := V2_BOT_DIR / ".relink").write_text(str(int(time.time())))
    except Exception as e:
        log.warning("relink cleanup warning: %s", e)
    time.sleep(1)
    return start()


def send_message(jid: str, text: str) -> dict:
    """Enqueue a message for the bot to send by writing a temp JSON file.

    The Node.js bot polls WEBCMD_DIR (os.tmpdir()/radd_bot_cmd) for *.in.json
    files and writes responses to *.out.json files in the same directory.
    This must match WEBCMD_DIR in the Node bot's index.js exactly.
    """
    import tempfile
    import uuid as _uuid
    import json as _json

    _CMD_DIR = Path(tempfile.gettempdir()) / "radd_bot_cmd"
    _CMD_DIR.mkdir(exist_ok=True, parents=True)

    with _proc_lock:
        running = _proc is not None and _proc.poll() is None
    if not running:
        return {"ok": False, "error": "Bot not running"}

    rid     = _uuid.uuid4().hex[:12]
    in_path = _CMD_DIR / f"{rid}.in.json"
    in_path.write_text(_json.dumps({
        "id":   rid,
        "cmd":  "send",
        "jid":  jid,
        "text": text,
        "ts":   int(time.time()),
    }))

    out_path = _CMD_DIR / f"{rid}.out.json"
    deadline = time.time() + 8.0
    while time.time() < deadline:
        if out_path.exists():
            try:
                resp = _json.loads(out_path.read_text())
            except Exception as parse_err:
                try: out_path.unlink()
                except Exception: pass
                return {"ok": False, "error": f"Bad response from bot: {parse_err}"}
            finally:
                try: out_path.unlink()
                except Exception: pass
            return {"ok": True, "sent": resp.get("sent", True)}
        time.sleep(0.25)

    try: in_path.unlink()
    except Exception: pass
    return {"ok": False, "error": "Bot did not confirm send within 8 s"}


def _read_logs():
    global _proc
    if _proc and _proc.stdout:
        for line in _proc.stdout:
            line = line.rstrip()
            _log_lines.append(line)
            if len(_log_lines) > _MAX_LOG_LINES:
                _log_lines.pop(0)
            try:
                with open(str(DEBUG_LOG), "a") as f:
                    f.write(line + "\n")
            except Exception:
                pass
