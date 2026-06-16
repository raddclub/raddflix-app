"""Cloudflare Quick Tunnel — zero-config remote access for headless Linux.

Downloads the cloudflared binary to .local/bin/ inside the project folder
(travels with the project) and starts a quick tunnel that exposes the local
Flask server at a public HTTPS URL with no account or config required.

Public API
----------
start(port)       → dict  — download cloudflared if needed, start tunnel
stop()            → dict  — stop the tunnel
status()          → dict  — current state
get_url()         → str | None
ensure_binary()   → bool  — download binary without starting tunnel
binary_present()  → bool
"""
from __future__ import annotations
import io
import os
import re
import sys
import stat
import time
import shutil
import platform
import tarfile
import threading
import subprocess
import urllib.request
from collections import deque
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
_LOCAL_BIN    = _PROJECT_ROOT / "local" / "bin"

_CF_URLS: dict[str, str] = {
    "linux_x86_64":  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
    "linux_amd64":   "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
    "linux_aarch64": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64",
    "linux_arm64":   "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64",
    "linux_armv7l":  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm",
    "darwin_x86_64": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz",
    "darwin_arm64":  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz",
    "windows_amd64": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe",
    "windows_AMD64": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe",
    "windows_x86":   "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-386.exe",
}

_LOCK  = threading.Lock()
_STATE: dict = {
    "running":    False,
    "ok":         None,
    "url":        None,
    "pid":        None,
    "message":    "",
    "started_at": None,
    "log_tail":   deque(maxlen=120),
}
_proc: subprocess.Popen | None = None


def _log(msg: str) -> None:
    _STATE["log_tail"].append(str(msg).rstrip())


def _platform_key() -> str | None:
    system  = platform.system().lower()   # linux / darwin / windows
    machine = platform.machine().lower()  # x86_64 / aarch64 / amd64 / ...
    key = f"{system}_{machine}"
    if key in _CF_URLS:
        return key
    aliases = {
        "windows_amd64": "windows_AMD64",
    }
    return aliases.get(key)


def _bin_name() -> str:
    return "cloudflared.exe" if sys.platform == "win32" else "cloudflared"


def _bin_path() -> Path:
    return _LOCAL_BIN / _bin_name()


def _system_cf() -> str | None:
    return shutil.which("cloudflared")


def binary_present() -> bool:
    return _bin_path().exists() or bool(_system_cf())


def _cf_exe() -> str | None:
    p = _bin_path()
    if p.exists():
        return str(p)
    return _system_cf()


def ensure_binary() -> bool:
    """Download cloudflared to .local/bin/ if not already present."""
    if binary_present():
        return True

    key = _platform_key()
    url = _CF_URLS.get(key or "")
    if not url:
        _log(f"!! cloudflared: unsupported platform ({platform.system()} {platform.machine()})")
        return False

    _LOCAL_BIN.mkdir(parents=True, exist_ok=True)
    bin_path = _bin_path()
    is_tgz   = url.endswith(".tgz")

    _log(f">> Downloading cloudflared ({platform.system()} {platform.machine()}) …")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "radd-hub/3.0"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read()
        _log(f"   downloaded {len(data) // 1024} KB")
    except Exception as e:
        _log(f"!! cloudflared download failed: {e}")
        return False

    try:
        if is_tgz:
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
                for member in tf.getmembers():
                    if member.name.endswith("cloudflared") or member.name == "cloudflared":
                        f = tf.extractfile(member)
                        if f:
                            bin_path.write_bytes(f.read())
                            break
                else:
                    _log("!! cloudflared binary not found inside tgz")
                    return False
        else:
            bin_path.write_bytes(data)

        if sys.platform != "win32":
            bin_path.chmod(bin_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

        _log(f"OK: cloudflared installed at {bin_path}")
        return True

    except Exception as e:
        _log(f"!! cloudflared install failed: {e}")
        try:
            bin_path.unlink(missing_ok=True)
        except Exception:
            pass
        return False


def _monitor(proc: subprocess.Popen, port: int) -> None:
    """Read cloudflared stderr and extract the public tunnel URL."""
    assert proc.stderr is not None
    url_pattern = re.compile(r"https://[a-z0-9\-]+\.trycloudflare\.com")

    for raw in proc.stderr:
        line = raw.rstrip() if isinstance(raw, str) else raw.decode("utf-8", errors="replace").rstrip()
        _log(line)

        if not _STATE["url"]:
            m = url_pattern.search(line)
            if m:
                tunnel_url = m.group(0)
                with _LOCK:
                    _STATE["url"]     = tunnel_url
                    _STATE["ok"]      = True
                    _STATE["message"] = f"Active: {tunnel_url}"
                _log(f">> Public URL: {tunnel_url}")

    rc = proc.wait()
    with _LOCK:
        if _STATE["running"]:
            _STATE["running"] = False
            _STATE["ok"]      = False if _STATE["url"] is None else _STATE["ok"]
            _STATE["message"] = f"Tunnel stopped (rc={rc})"
            _STATE["url"]     = None
    _log(f">> cloudflared exited (rc={rc})")


def start(port: int = 5000) -> dict:
    """Start a Cloudflare quick tunnel to localhost:port."""
    global _proc

    with _LOCK:
        if _STATE["running"]:
            return status()
        _STATE.update(running=True, ok=None, url=None, pid=None,
                      message="Starting tunnel…", started_at=time.time())
        _STATE["log_tail"].clear()

    if not binary_present():
        _log("cloudflared not found — downloading…")
        if not ensure_binary():
            with _LOCK:
                _STATE.update(running=False, ok=False,
                              message="cloudflared download failed — check internet")
            return status()

    exe = _cf_exe()
    if not exe:
        with _LOCK:
            _STATE.update(running=False, ok=False,
                          message="cloudflared binary missing after install")
        return status()

    cmd = [exe, "tunnel", "--url", f"http://127.0.0.1:{port}", "--no-autoupdate"]
    _log(f">> {' '.join(cmd)}")

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except Exception as e:
        with _LOCK:
            _STATE.update(running=False, ok=False,
                          message=f"Failed to launch cloudflared: {e}")
        return status()

    _proc = proc
    with _LOCK:
        _STATE["pid"] = proc.pid

    t = threading.Thread(target=_monitor, args=(proc, port),
                         name="tunnel-monitor", daemon=True)
    t.start()

    for _ in range(40):
        time.sleep(0.5)
        if _STATE["url"]:
            break

    return status()


def stop() -> dict:
    """Stop the running tunnel."""
    global _proc
    with _LOCK:
        proc  = _proc
        alive = _STATE["running"]

    if proc and proc.poll() is None:
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    with _LOCK:
        _STATE.update(running=False, ok=None, url=None,
                      pid=None, message="Tunnel stopped")
    _proc = None
    return status()


def status() -> dict:
    with _LOCK:
        return {
            "running":        _STATE["running"],
            "ok":             _STATE["ok"],
            "url":            _STATE["url"],
            "pid":            _STATE["pid"],
            "message":        _STATE["message"],
            "started_at":     _STATE["started_at"],
            "binary_present": binary_present(),
            "binary_path":    str(_bin_path()) if binary_present() else None,
            "log_tail":       list(_STATE["log_tail"]),
        }


def get_url() -> str | None:
    """Return the public HTTPS tunnel URL, or None if not active."""
    return _STATE.get("url")
