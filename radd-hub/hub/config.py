"""Unified configuration: env loading, OS detection, path management.

Replaces v2.0 ``common/`` package and the per-service ``config.json`` files.
"""
from __future__ import annotations
import os
import sys
import json
import secrets
import logging
import platform
import string
from pathlib import Path
from typing import Optional

# --------------------------------------------------------------------------- #
# Paths                                                                       #
# --------------------------------------------------------------------------- #

PROJECT_ROOT = Path(__file__).resolve().parent.parent          # RaddHub-v3.0/
HUB_DIR      = Path(__file__).resolve().parent                 # RaddHub-v3.0/hub
DATA_DIR     = Path(os.environ.get("DATA_DIR")  or PROJECT_ROOT / "data")
MEDIA_DIR    = Path(os.environ.get("MEDIA_DIR") or DATA_DIR / "media")
STAGING_DIR  = Path(os.environ.get("STAGING_DIR") or DATA_DIR / "staging")
LOG_DIR      = DATA_DIR / "logs"
AUTH_DIR     = DATA_DIR / "auth"
CACHE_DIR    = DATA_DIR / "cache"
TEMP_DIR     = DATA_DIR / "tmp"
DB_PATH      = DATA_DIR / "radd_hub.db"
ENV_PATH     = PROJECT_ROOT / ".env"
ENV_EXAMPLE  = PROJECT_ROOT / ".env.example"

# Make MEDIA_DIR available everywhere (downloader uses DOWNLOAD_DIR env)
def ensure_dirs() -> None:
    for d in (DATA_DIR, MEDIA_DIR, STAGING_DIR, LOG_DIR, AUTH_DIR, CACHE_DIR, TEMP_DIR):
        d.mkdir(parents=True, exist_ok=True)
    # Downloader saves to STAGING_DIR; files move to MEDIA_DIR only on completion
    os.environ.setdefault("DOWNLOAD_DIR", str(STAGING_DIR))

# --------------------------------------------------------------------------- #
# OS detection                                                                #
# --------------------------------------------------------------------------- #

def os_name() -> str:
    p = sys.platform
    if p.startswith("win"):    return "windows"
    if p.startswith("darwin"): return "mac"
    return "linux"

def is_windows() -> bool: return os_name() == "windows"
def is_linux()   -> bool: return os_name() == "linux"
def is_mac()     -> bool: return os_name() == "mac"

# --------------------------------------------------------------------------- #
# .env loading                                                                #
# --------------------------------------------------------------------------- #

def _parse_env(text: str) -> dict:
    out = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip()
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        out[k] = v
    return out

def load_env() -> dict:
    """Load .env into os.environ if present. Returns parsed dict."""
    if not ENV_PATH.exists():
        return {}
    parsed = _parse_env(ENV_PATH.read_text(encoding="utf-8"))
    for k, v in parsed.items():
        os.environ[k] = v
    return parsed

def write_env(updates: dict, *, create_if_missing: bool = True) -> None:
    """Atomically merge ``updates`` into .env preserving order/comments."""
    if not ENV_PATH.exists():
        if create_if_missing and ENV_EXAMPLE.exists():
            ENV_PATH.write_text(ENV_EXAMPLE.read_text(encoding="utf-8"), encoding="utf-8")
        else:
            ENV_PATH.write_text("", encoding="utf-8")
    lines = ENV_PATH.read_text(encoding="utf-8").splitlines()
    seen = set()
    out_lines = []
    for line in lines:
        bare = line.strip()
        if (not bare) or bare.startswith("#") or ("=" not in bare):
            out_lines.append(line); continue
        key = bare.split("=", 1)[0].strip()
        if key in updates:
            out_lines.append(f"{key}={_quote(updates[key])}")
            seen.add(key)
        else:
            out_lines.append(line)
    for k, v in updates.items():
        if k not in seen:
            out_lines.append(f"{k}={_quote(v)}")
    ENV_PATH.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    # Reflect into current process
    for k, v in updates.items():
        os.environ[k] = str(v)

def _quote(v) -> str:
    s = "" if v is None else str(v)
    if s == "" or all(c.isalnum() or c in "._:/@,-" for c in s):
        return s
    return '"' + s.replace('"', '\\"') + '"'

# --------------------------------------------------------------------------- #
# Typed env getters                                                           #
# --------------------------------------------------------------------------- #

def get_env(name: str, default=None):
    return os.environ.get(name, default)

def get_env_bool(name: str, default: bool = False) -> bool:
    v = os.environ.get(name)
    if v is None: return default
    return str(v).strip().lower() in ("1", "true", "yes", "on", "y", "t")

def get_env_int(name: str, default: int = 0) -> int:
    try:    return int(os.environ.get(name, default))
    except: return default

# --------------------------------------------------------------------------- #
# First-run bootstrap                                                         #
# --------------------------------------------------------------------------- #

_ALPHABET = string.ascii_letters + string.digits + "-_"

def gen_password(n: int = 14) -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(n))

def first_run_bootstrap() -> dict:
    """Ensure .env exists with secure defaults; return summary."""
    summary = {"created_env": False, "generated_secret": False,
               "generated_admin_pwd": False, "admin_pwd": None}
    ensure_dirs()

    if not ENV_PATH.exists():
        if ENV_EXAMPLE.exists():
            ENV_PATH.write_text(ENV_EXAMPLE.read_text(encoding="utf-8"), encoding="utf-8")
        else:
            ENV_PATH.write_text("", encoding="utf-8")
        summary["created_env"] = True

    load_env()
    updates = {}

    if not os.environ.get("FLASK_SECRET_KEY"):
        updates["FLASK_SECRET_KEY"] = secrets.token_hex(32)
        summary["generated_secret"] = True

    if not os.environ.get("RADD_ADMIN_PASS"):
        pwd = gen_password(16)
        updates["RADD_ADMIN_PASS"] = pwd
        summary["generated_admin_pwd"] = True
        summary["admin_pwd"] = pwd

    if updates:
        write_env(updates)
    return summary

# --------------------------------------------------------------------------- #
# Logging                                                                     #
# --------------------------------------------------------------------------- #

class _JsonFormatter(logging.Formatter):
    def format(self, r):
        return json.dumps({"t": int(r.created), "lvl": r.levelname,
                           "name": r.name, "msg": r.getMessage()})

_LOGGING_READY = False
def setup_logging(name: str = "raddhub") -> logging.Logger:
    global _LOGGING_READY
    log = logging.getLogger(name)
    if _LOGGING_READY:
        return log
    level = getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO)
    h = logging.StreamHandler()
    if get_env_bool("LOG_JSON", False):
        h.setFormatter(_JsonFormatter())
    else:
        h.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s",
                                         datefmt="%Y-%m-%d %I:%M:%S %p"))
    root = logging.getLogger()
    root.handlers[:] = [h]
    root.setLevel(level)
    # File handler (rotating: 10 MB × 5 backups)
    try:
        from logging.handlers import RotatingFileHandler as _RFH
        ensure_dirs()
        fh = _RFH(LOG_DIR / "raddhub.log",
                  maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8")
        fh.setFormatter(h.formatter)
        root.addHandler(fh)
    except Exception:
        pass
    _LOGGING_READY = True
    return log

def get_logger(name: str = "raddhub") -> logging.Logger:
    return logging.getLogger(name)

# --------------------------------------------------------------------------- #
# Network                                                                     #
# --------------------------------------------------------------------------- #

def local_ip() -> Optional[str]:
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None
