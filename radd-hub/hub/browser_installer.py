from __future__ import annotations
import os
import sys
import time
import shutil
import threading
import subprocess
from collections import deque
from pathlib import Path
_LOCK = threading.Lock()
_STATE: dict = {
    "running": False,
    "started_at": None,
    "finished_at": None,
    "ok": None,                                                       
    "message": "",
    "browser_path": None,
    "browser_kind": None,                                            
    "log_tail": deque(maxlen=200),
}
def _detect() -> tuple[str | None, str | None]:
    from . import scraper
    chrome, _pw = scraper._find_chromium()
    if chrome:
        return chrome, "chromium"
    ff = scraper._find_firefox()
    if ff:
        return ff, "firefox"
    for name in ("chromium", "chromium-browser", "google-chrome",
                 "google-chrome-stable", "chrome"):
        sys_chrome = shutil.which(name)
        if sys_chrome:
            return sys_chrome, "system"
    return None, None
def _refresh_scraper_cache(path: str | None, kind: str | None) -> None:
    if not path:
        return
    from . import scraper
    if kind in ("chromium", "system"):
        scraper._CHROMIUM_PATH = path
        scraper._CHROMIUM_PW_MANAGED = "ms-playwright" in path.replace("\\", "/")
        os.environ["RADD_CHROMIUM_EXECUTABLE"] = path
    elif kind == "firefox":
        scraper._FIREFOX_PATH = path
def is_installed() -> bool:
    path, _ = _detect()
    return bool(path)
def status() -> dict:
    path, kind = _detect()
    out = {
        "running": _STATE["running"],
        "ok": _STATE["ok"],
        "message": _STATE["message"],
        "started_at": _STATE["started_at"],
        "finished_at": _STATE["finished_at"],
        "browser_path": path,
        "browser_kind": kind,
        "installed": bool(path),
        "log_tail": list(_STATE["log_tail"]),
    }
    return out
def _log(line: str) -> None:
    _STATE["log_tail"].append(line.rstrip())
def _run_install() -> None:
    try:
        _STATE.update(running=True, ok=None, message="Installing Chromium…",
                      started_at=time.time(), finished_at=None)
        env = os.environ.copy()
        # Strip these so the subprocess picks its own clean lib search paths.
        # In particular LD_LIBRARY_PATH set by _bootstrap can confuse the
        # playwright install script when it's verifying the downloaded binary.
        env.pop("LD_LIBRARY_PATH", None)
        env.pop("_RADD_LD_BOOTSTRAPPED", None)
        # Do NOT set REPLIT_PLAYWRIGHT_CHROMIUM_EXECUTABLE for the install
        # subprocess — playwright's install should use its own default paths.
        env.pop("REPLIT_PLAYWRIGHT_CHROMIUM_EXECUTABLE", None)
        # Point playwright at our project-local browsers directory so the
        # downloaded browser travels with the project.
        _proj_browsers = Path(__file__).resolve().parent.parent / "local" / "browsers"
        try:
            _proj_browsers.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
        env["PLAYWRIGHT_BROWSERS_PATH"] = str(_proj_browsers)
        # Export into current process too so scraper.py finds the browser.
        os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(_proj_browsers))

        def _run_cmd(cmd):
            _log(">> " + " ".join(cmd))
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=env,
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                _log(line)
            return proc.wait()

        # 1. Try chromium (installs headless-shell on modern playwright — more
        #    portable than the full Chromium build, avoids glibc issues).
        rc = _run_cmd([sys.executable, "-m", "playwright", "install", "chromium"])
        if rc != 0:
            _log(f"!! chromium exit {rc} — trying firefox as a fallback…")
            rc = _run_cmd([sys.executable, "-m", "playwright", "install", "firefox"])

        # Clear any cached broken path so _find_chromium() re-probes from scratch.
        try:
            from . import scraper as _sc
            if _sc._CHROMIUM_CACHE_FILE.exists():
                _sc._CHROMIUM_CACHE_FILE.unlink()
        except Exception:
            pass

        path, kind = _detect()
        if path:
            _refresh_scraper_cache(path, kind)
            _STATE.update(ok=True,
                          message=f"Installed: {kind} ({Path(path).name})")
            _log(f"OK: {path}")
        else:
            _STATE.update(ok=False,
                          message="Install finished but no browser found. "
                                  "Try running `python -m playwright install "
                                  "chromium` manually.")
            _log("!! no browser detected after install")
    except FileNotFoundError as e:
        _STATE.update(ok=False, message=f"Cannot launch installer: {e}")
        _log(f"!! {e}")
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
        _STATE.update(ok=None, message="Starting install…",
                      started_at=None, finished_at=None)
        t = threading.Thread(target=_run_install, name="browser-installer",
                             daemon=True)
        t.start()
    time.sleep(0.05)
    return status()