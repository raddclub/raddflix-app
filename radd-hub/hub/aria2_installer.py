from __future__ import annotations
import io
import os
import sys
import time
import shutil
import zipfile
import threading
import urllib.request
from collections import deque
from pathlib import Path
_ARIA2_VERSION = "1.37.0"
_ARIA2_URLS = {
    "win64":         f"https://github.com/aria2/aria2/releases/download/release-{_ARIA2_VERSION}/aria2-{_ARIA2_VERSION}-win-64bit-build1.zip",
    "win32":         f"https://github.com/aria2/aria2/releases/download/release-{_ARIA2_VERSION}/aria2-{_ARIA2_VERSION}-win-32bit-build1.zip",
    "linux_x86_64":  f"https://github.com/aria2/aria2/releases/download/release-{_ARIA2_VERSION}/aria2-{_ARIA2_VERSION}-linux-gnu-64bit-build1.tar.bz2",
    "linux_aarch64": f"https://github.com/aria2/aria2/releases/download/release-{_ARIA2_VERSION}/aria2-{_ARIA2_VERSION}-linux-gnu-aarch64-build1.tar.bz2",
}
_LOCK = threading.Lock()
_STATE: dict = {
    "running": False,
    "ok": None,
    "message": "",
    "started_at": None,
    "finished_at": None,
    "log_tail": deque(maxlen=80),
}

# Project-local bin dir: <project>/.local/bin/
# This makes the project self-contained — the binary travels with the project
# across Replit accounts, machines, and Linux servers.
def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent

def _bin_dir() -> Path:
    d = _project_root() / "local" / "bin"
    d.mkdir(parents=True, exist_ok=True)
    return d
def _ensure_local_bin_on_path() -> None:
    b = str(_bin_dir())
    cur = os.environ.get("PATH", "")
    sep = ";" if os.name == "nt" else ":"
    if b not in cur.split(sep):
        os.environ["PATH"] = b + sep + cur
_ensure_local_bin_on_path()
def _local_aria2_path() -> Path:
    name = "aria2c.exe" if os.name == "nt" else "aria2c"
    return _bin_dir() / name
def is_installed() -> bool:
    if _local_aria2_path().exists():
        return True
    return shutil.which("aria2c") is not None
def _detect_path() -> str | None:
    p = _local_aria2_path()
    if p.exists():
        return str(p)
    return shutil.which("aria2c")
def _platform_hint() -> str:
    import platform as _platform
    if os.name == "nt":
        return "win64" if sys.maxsize > 2**32 else "win32"
    if sys.platform == "darwin":
        return "macos"
    machine = _platform.machine().lower()
    if machine in ("aarch64", "arm64"):
        return "linux_aarch64"
    return "linux_x86_64"
def status() -> dict:
    return {
        "running": _STATE["running"],
        "ok": _STATE["ok"],
        "message": _STATE["message"],
        "started_at": _STATE["started_at"],
        "finished_at": _STATE["finished_at"],
        "installed": is_installed(),
        "path": _detect_path(),
        "platform": _platform_hint(),
        "supports_auto_install": True,   # all platforms now supported
        "log_tail": list(_STATE["log_tail"]),
    }
def _log(line: str) -> None:
    _STATE["log_tail"].append(str(line).rstrip())
def _download_with_progress(url: str) -> bytes:
    _log(f">> GET {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "radd-stream/4.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        total = int(resp.headers.get("Content-Length") or 0)
        chunks: list[bytes] = []
        got = 0
        last_pct = -1
        while True:
            buf = resp.read(64 * 1024)
            if not buf:
                break
            chunks.append(buf)
            got += len(buf)
            if total:
                pct = int(got * 100 / total)
                if pct != last_pct and pct % 5 == 0:
                    _log(f"   {pct:3d}%  ({got // 1024} / {total // 1024} KB)")
                    last_pct = pct
        _log(f"   downloaded {got // 1024} KB")
        return b"".join(chunks)
def _install_linux_static() -> bool:
    """Download a pre-built static aria2c binary for Linux x86_64 / aarch64."""
    import platform as _platform
    import tarfile
    machine = _platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        key = "linux_x86_64"
    elif machine in ("aarch64", "arm64"):
        key = "linux_aarch64"
    else:
        _log(f"!! unsupported Linux arch: {machine}")
        return False
    url = _ARIA2_URLS.get(key)
    if not url:
        return False
    try:
        data = _download_with_progress(url)
    except Exception as e:
        _log(f"!! download failed: {e}")
        return False
    try:
        import io
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:bz2") as tf:
            target_member = None
            for m in tf.getmembers():
                if m.name.endswith("/aria2c") or m.name == "aria2c":
                    target_member = m
                    break
            if not target_member:
                _log("!! aria2c binary not found inside tar archive")
                return False
            f = tf.extractfile(target_member)
            if not f:
                return False
            dest = _local_aria2_path()
            dest.write_bytes(f.read())
            dest.chmod(0o755)
        _log(f"OK: {_local_aria2_path()}")
        return True
    except Exception as e:
        _log(f"!! extract failed: {e}")
        return False

def _install_windows() -> bool:
    arch = _platform_hint()
    url = _ARIA2_URLS.get(arch)
    if not url:
        _log(f"!! no aria2 build available for {arch}")
        return False
    try:
        data = _download_with_progress(url)
    except Exception as e:
        _log(f"!! download failed: {e}")
        return False
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            target = None
            for name in zf.namelist():
                if name.lower().endswith("aria2c.exe"):
                    target = name
                    break
            if not target:
                _log("!! aria2c.exe not found inside zip")
                return False
            _log(f"   extracting {target}")
            with zf.open(target) as src, open(_local_aria2_path(), "wb") as dst:
                shutil.copyfileobj(src, dst)
    except Exception as e:
        _log(f"!! extract failed: {e}")
        return False
    _log(f"OK: {_local_aria2_path()}")
    return True
def _run_install() -> None:
    try:
        _STATE.update(running=True, ok=None, message="Downloading aria2c…",
                      started_at=time.time(), finished_at=None)
        _log(f">> aria2c installer (platform={_platform_hint()})")
        if os.name == "nt":
            ok = _install_windows()
            if ok:
                _STATE.update(ok=True, message=f"aria2c {_ARIA2_VERSION} installed (Windows)")
            else:
                _STATE.update(ok=False,
                              message="Auto-install failed. Get it from "
                                      "https://github.com/aria2/aria2/releases")
        elif sys.platform == "darwin":
            _STATE.update(ok=False,
                          message="macOS: install aria2 via Homebrew: `brew install aria2`")
            _log("macOS: brew install aria2")
        else:
            # Linux — download static binary into .local/bin/ (no sudo needed)
            _log("Linux: downloading static aria2c binary …")
            ok = _install_linux_static()
            if ok:
                _STATE.update(ok=True,
                              message=f"aria2c {_ARIA2_VERSION} installed (Linux static binary)")
            else:
                _STATE.update(ok=False,
                              message="Static download failed. Try: apt install aria2  or  "
                                      "nix-env -iA nixpkgs.aria2")
    except Exception as e:
        _STATE.update(ok=False, message=f"Install error: {e}")
        _log(f"!! {e}")
    finally:
        _STATE.update(running=False, finished_at=time.time())
def ensure_installed_async(force: bool = False) -> dict:
    with _LOCK:
        if _STATE["running"]:
            return status()
        if not force and is_installed():
            return status()
        _STATE["log_tail"].clear()
        _STATE.update(ok=None, message="Starting aria2c install…",
                      started_at=None, finished_at=None)
        threading.Thread(target=_run_install, name="aria2-installer",
                         daemon=True).start()
    time.sleep(0.05)
    return status()