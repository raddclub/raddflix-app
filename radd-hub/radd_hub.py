#!/usr/bin/env python3
"""Radd Hub v3.0 — all-in-one launcher and control CLI.

Usage:
    python radd_hub.py                    # start server (foreground)
    python radd_hub.py run                # start server (foreground)
    python radd_hub.py start              # start server (background)
    python radd_hub.py stop               # stop background server
    python radd_hub.py restart            # stop + start background
    python radd_hub.py status             # is server running?
    python radd_hub.py url                # print the best access URL
    python radd_hub.py logs [-n N]        # tail log (default 80 lines)
    python radd_hub.py setup [--fix]      # install deps + first-run setup
    python radd_hub.py doctor [--fix]     # environment self-check
    python radd_hub.py cli                # launch interactive stream CLI
    python radd_hub.py keys list          # list all keys/settings
    python radd_hub.py keys get PROVIDER  # get a key value
    python radd_hub.py keys set PROVIDER=val  # set a key value
    python radd_hub.py keys test PROVIDER # test a provider key
    python radd_hub.py sync               # trigger mirror push (GitHub+Sheets)
    python radd_hub.py dashboard          # live terminal dashboard
    python radd_hub.py export [--fmt csv|json] [--output FILE]  # export catalog
    python radd_hub.py broadcast "message"  # WA broadcast to verified users
    python radd_hub.py search "query"     # search local library
    python radd_hub.py tunnel [status|start|stop|url]  # Cloudflare tunnel
"""
from __future__ import annotations
import os
import sys
import time
import json
import signal
import socket
import shutil
import subprocess
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

# ── Dependency self-bootstrap ────────────────────────────────────────────────
# Must run BEFORE any third-party import.  If flask (or any dep) is missing we
# install requirements.txt and re-exec this same script so the new packages are
# visible to the fresh process — subprocess-pip does NOT reload sys.path in the
# current process.
def _ensure_deps() -> None:
    req = ROOT / "requirements.txt"
    if not req.exists():
        return
    try:
        import flask  # noqa: F401 — proxy for "deps already installed"
        return
    except ModuleNotFoundError:
        pass

    print("[radd-hub] Installing Python dependencies …", flush=True)
    base = [sys.executable, "-m", "pip", "install", "--quiet", "-r", str(req)]
    # Try vanilla first (works on Windows and most venvs), then Nix/PEP-668 flags
    for extra in [[], ["--break-system-packages"], ["--user"]]:
        rc = subprocess.call(base + extra)
        if rc == 0:
            break
    else:
        print("[radd-hub] WARNING: pip install may not have completed cleanly.", flush=True)

    # Re-exec so the current process sees the newly installed packages
    print("[radd-hub] Restarting with dependencies now available …", flush=True)
    os.execv(sys.executable, [sys.executable] + sys.argv)

_ensure_deps()
# ─────────────────────────────────────────────────────────────────────────────

PID_FILE = ROOT / "data" / "raddhub.pid"


def _bootstrap_chromium_env() -> None:
    """Set RADD_CHROMIUM_EXECUTABLE to the best working Playwright-compatible
    Chromium before hub modules are imported.
    """
    # ── Always set project-local PATH early ─────
    _local_bin = str(ROOT / "local" / "bin")
    _cur_path  = os.environ.get("PATH", "")
    if _local_bin not in _cur_path.split(os.pathsep):
        os.environ["PATH"] = _local_bin + os.pathsep + _cur_path

    if os.environ.get("RADD_CHROMIUM_EXECUTABLE", "").strip():
        return  # already set by caller

    try:
        from hub import installer as _ins
        path, is_pw = _ins.find_chromium_executable()
        if path:
            os.environ["RADD_CHROMIUM_EXECUTABLE"] = path
            # If it's a local PW-managed browser, we might need to set the root
            if is_pw and str(ROOT / "local") in path:
                 os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(ROOT / "local" / "browsers"))
    except Exception:
        pass

_bootstrap_chromium_env()


# ─────────────────────────────────────────────
# helpers
# ─────────────────────────────────────────────

def _public_url(port: int) -> str:
    """Return the best public URL for this environment (Replit / LAN / localhost)."""
    for key in ("REPLIT_DEV_DOMAIN", "REPLIT_DOMAINS"):
        val = os.environ.get(key, "").split(",")[0].strip()
        if val:
            return f"https://{val}"
    try:
        from hub import config as _cfg
        ip = _cfg.local_ip()
        if ip:
            return f"http://{ip}:{port}"
    except Exception:
        pass
    return f"http://localhost:{port}"


def _banner(host: str, port: int, admin_user: str, admin_pwd: str | None) -> None:
    url = _public_url(port)
    local_url = f"http://{host}:{port}"
    print()
    print("=" * 64)
    print(f"  Radd Hub v3.0   →   {url}")
    if url != local_url:
        print(f"  Local           →   {local_url}")
    if admin_pwd:
        print(f"  Admin:  {admin_user}  /  {admin_pwd}")
        print(f"  (saved in .env as RADD_ADMIN_PASS)")
    print("  CLI:    python radd_hub.py cli")
    print("  Stop:   python radd_hub.py stop")
    print("=" * 64)
    print()


def _step(label: str) -> None:
    sys.stdout.write(f"  {label:<40}")
    sys.stdout.flush()


def _ok(msg: str = "ok") -> None:
    print(f"  {msg}")


def _port_open(port: int, timeout: float = 0.5) -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(("127.0.0.1", port))
        return True
    except Exception:
        return False
    finally:
        s.close()


def _read_pid() -> int | None:
    try:
        return int(PID_FILE.read_text().strip())
    except Exception:
        return None


def _write_pid(pid: int) -> None:
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(pid))


def _clear_pid() -> None:
    try:
        PID_FILE.unlink()
    except Exception:
        pass


def _pid_alive(pid: int) -> bool:
    if sys.platform == "win32":
        try:
            import psutil
            return psutil.pid_exists(pid)
        except ImportError:
            import ctypes
            SYNCHRONIZE = 0x100000
            handle = ctypes.windll.kernel32.OpenProcess(SYNCHRONIZE, False, pid)
            if handle:
                ctypes.windll.kernel32.CloseHandle(handle)
                return True
            return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


# ─────────────────────────────────────────────
# setup
# ─────────────────────────────────────────────

def cmd_setup(args) -> int:
    fix = getattr(args, "fix", False)
    print("\n  Radd Hub v3.0 — setup")
    print("  " + "─" * 42)

    # ── Bootstrap project-local paths FIRST ──────────────────────────────────
    # _bootstrap_chromium_env() was already called at the top of this script.
    # We just ensure the directories exist here.
    _local_browsers = ROOT / "local" / "browsers"
    _local_bin = ROOT / "local" / "bin"
    _local_browsers.mkdir(parents=True, exist_ok=True)
    _local_bin.mkdir(parents=True, exist_ok=True)

    # ── Python dependencies ──────────────────────────────────────────────────
    _step("Python dependencies")
    try:
        req = ROOT / "requirements.txt"
        if req.exists():
            base = [sys.executable, "-m", "pip", "install", "--quiet", "-r", str(req)]
            # Try plain first, then Nix/PEP-668 fallbacks
            rc = subprocess.call(base,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if rc != 0:
                rc = subprocess.call(base + ["--break-system-packages"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if rc != 0:
                rc = subprocess.call(base + ["--user"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            _ok("ok" if rc == 0 else "WARN (some packages could not be installed)")
        else:
            _ok("no requirements.txt found")
    except Exception as e:
        _ok(f"WARN: {e}")

    # ── Environment & dirs ───────────────────────────────────────────────────
    _step("Initialising environment")
    try:
        from hub import config
        config.ensure_dirs()
        summary = config.first_run_bootstrap()
        bits = []
        if summary["created_env"]:         bits.append("created .env")
        if summary["generated_secret"]:    bits.append("secret key generated")
        if summary["generated_admin_pwd"]: bits.append(f"admin_pwd={summary['admin_pwd']}")
        _ok(", ".join(bits) or "already configured")
    except Exception as e:
        _ok(f"WARN: {e}")

    # ── Database ─────────────────────────────────────────────────────────────
    _step("Initialising database")
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
        _ok("ok")
    except Exception as e:
        _ok(f"WARN: {e}")

    # ── Node.js ──────────────────────────────────────────────────────────────
    _step("Node.js / npm")
    try:
        from hub import installer as _ins
        node_ok = _ins.ensure_node()
        node_exe = shutil.which("node") or shutil.which("node.exe")
        if node_exe:
            try:
                ver = subprocess.check_output([node_exe, "--version"],
                                              stderr=subprocess.DEVNULL).decode().strip()
            except Exception:
                ver = "found"
            _ok(ver)
        else:
            _ok("WARN — Node.js not found; WhatsApp/Telegram bots won't run")
    except Exception as e:
        _ok(f"WARN: {e}")

    # ── Bot npm dependencies ─────────────────────────────────────────────────
    _step("Bot npm dependencies")
    try:
        from hub import installer as _ins
        results = _ins.ensure_all_bot_deps()
        if not results:
            _ok("skipped (no bots dir)")
        else:
            failed = [k for k, v in results.items() if not v]
            _ok("ok" if not failed else f"WARN: {', '.join(failed)} failed")
    except Exception as e:
        _ok(f"WARN: {e}")

    # ── aria2c ───────────────────────────────────────────────────────────────
    _step("aria2c")
    try:
        from hub import installer as _ins
        _ins.ensure_aria2()
        found = shutil.which("aria2c")
        _ok(f"present ({found})" if found else
            "not found — add via system packages (optional)")
    except Exception as e:
        _ok(f"skipped ({e})")

    # ── Playwright / Chromium ─────────────────────────────────────────────────
    _step("Playwright chromium")
    try:
        from hub import installer as _ins
        chromium_ok = _ins.ensure_chromium()
        if chromium_ok:
            # After a fresh install, probe for the actual binary path and cache it
            # so _bootstrap_chromium_env() finds it on next startup without a
            # slow glob across the nix store.
            try:
                from hub.scraper import _find_chromium
                found_path, _ = _find_chromium()
                if found_path:
                    os.environ.setdefault("RADD_CHROMIUM_EXECUTABLE", found_path)
                    _cache = Path.home() / ".cache" / "radd-hub" / "chromium_path.txt"
                    _cache.parent.mkdir(parents=True, exist_ok=True)
                    _cache.write_text(f"{found_path}|pw")
            except Exception:
                pass
            _ok(f"ok ({os.environ.get('RADD_CHROMIUM_EXECUTABLE', 'path cached')})")
        else:
            _ok("WARN (playwright not installed or chromium download failed)")
    except Exception as e:
        _ok(f"WARN: {e}")

    print()
    print("  Setup complete.")
    print("  Run:  python radd_hub.py run")
    print()
    return 0


# ─────────────────────────────────────────────
# doctor
# ─────────────────────────────────────────────

def cmd_doctor(args) -> int:
    fix = getattr(args, "fix", False)
    print("\n  Radd Hub v3.0 — environment check")
    print("  " + "─" * 48)

    rc = 0
    py = sys.version_info
    print(f"  python:       {py.major}.{py.minor}.{py.micro}  {'ok' if py >= (3, 10) else 'WARN: 3.10+ recommended'}")

    for tool, optional in [("aria2c", False), ("node", True), ("npm", True)]:
        exe = shutil.which(tool)
        suffix = "  [optional: bots only]" if optional and not exe else ""
        print(f"  {tool:<14} {exe or '(not found)'}{suffix}")

    for pkg, req in [("flask", True), ("playwright", True), ("werkzeug", True),
                     ("requests", True), ("groq", False), ("psutil", False)]:
        try:
            __import__(pkg)
            status = "installed"
        except ImportError:
            status = "NOT installed" + ("  [REQUIRED]" if req else "  [optional]")
            if req: rc = 1
        print(f"  {pkg:<14} {status}")

    try:
        from hub import config as _cfg
        _cfg.load_env()
        port = _cfg.get_env_int("PORT", 5000)
        env_path = ROOT / ".env"
        print(f"\n  .env:         {env_path}  ({'present' if env_path.exists() else 'MISSING'})")
        print(f"  data dir:     {_cfg.DATA_DIR}")
        print(f"  media dir:    {_cfg.MEDIA_DIR}")
        print(f"  log dir:      {_cfg.LOG_DIR}")
        running = _port_open(port)
        print(f"  server:       {'running' if running else 'stopped'}  (port {port})")

        if fix and rc > 0:
            print("\n  --fix: installing missing packages...")
            cmd_setup(argparse.Namespace(fix=True))
    except Exception as e:
        print(f"  Config error: {e}")

    print()
    return rc


# ─────────────────────────────────────────────
# run (foreground)
# ─────────────────────────────────────────────

def cmd_run(args) -> int:
    skip_setup = getattr(args, "skip_setup", False)
    if skip_setup:
        # Fast path: skip slow env/dep checks and go straight to launching Flask.
        # Config load + DB init still run (they're fast, ~1 s) to ensure the DB
        # schema is current and env vars are populated before request handlers run.
        try:
            from hub import config as _cfg, db as _db
            _cfg.load_env()
            _cfg.ensure_dirs()
            _cfg.setup_logging("raddhub")
            _db.init_db()
        except Exception as _e:
            print(f"[radd-hub] WARNING: minimal init error: {_e}", flush=True)
    else:
        cmd_setup(args)

    from hub import config
    from hub.app import create_app
    app = create_app()

    port = int(os.environ.get("PORT", 5000))
    host = os.environ.get("HOST", "0.0.0.0")
    admin_user = os.environ.get("RADD_ADMIN_USER", "admin")
    admin_pwd  = os.environ.get("RADD_ADMIN_PASS")
    _banner(config.local_ip() or host, port, admin_user, admin_pwd)

    from werkzeug.serving import run_simple
    run_simple(host, port, app, threaded=True, use_reloader=False)
    return 0


# ─────────────────────────────────────────────
# start / stop / restart (background)
# ─────────────────────────────────────────────

def cmd_start(args) -> int:
    try:
        from hub import config
        config.load_env()
        port = config.get_env_int("PORT", 5000)
    except Exception:
        port = int(os.environ.get("PORT", 5000))

    pid = _read_pid()
    if pid and _pid_alive(pid):
        print(f"  Already running  pid={pid}  http://localhost:{port}")
        return 0

    log_file = ROOT / "data" / "logs" / "raddhub.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env.setdefault("PORT", str(port))
    with open(log_file, "a") as lf:
        popen_kwargs: dict = dict(
            cwd=str(ROOT),
            env=env,
            stdout=lf,
            stderr=lf,
        )
        if sys.platform == "win32":
            DETACHED_PROCESS = 0x00000008
            CREATE_NEW_PROCESS_GROUP = 0x00000200
            popen_kwargs["creationflags"] = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
        else:
            popen_kwargs["start_new_session"] = True
        proc = subprocess.Popen(
            [sys.executable, str(ROOT / "radd_hub.py"), "run"],
            **popen_kwargs,
        )
    _write_pid(proc.pid)
    url = _public_url(port)
    print(f"  Started  pid={proc.pid}  port={port}")
    print(f"  URL:     {url}")
    if url != f"http://localhost:{port}":
        print(f"  Local:   http://localhost:{port}")
    print(f"  Log:     {log_file}")
    print(f"  Stop:    python radd_hub.py stop")
    for _ in range(20):
        time.sleep(0.5)
        if _port_open(port):
            print("  Ready!")
            break
    return 0


def cmd_stop(args) -> int:
    pid = _read_pid()
    if not pid:
        print("  Not running (no PID file).")
        return 0
    if not _pid_alive(pid):
        print(f"  Already stopped (pid {pid} dead).")
        _clear_pid()
        return 0
    try:
        if sys.platform == "win32":
            subprocess.call(
                ["taskkill", "/F", "/PID", str(pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            os.kill(pid, signal.SIGTERM)
            for _ in range(20):
                time.sleep(0.5)
                if not _pid_alive(pid):
                    break
            if _pid_alive(pid):
                os.kill(pid, signal.SIGKILL)
        _clear_pid()
        print(f"  Stopped  (pid {pid})")
    except Exception as e:
        print(f"  Error stopping pid {pid}: {e}")
        return 1
    return 0


def cmd_restart(args) -> int:
    cmd_stop(args)
    time.sleep(1)
    return cmd_start(args)


# ─────────────────────────────────────────────
# status
# ─────────────────────────────────────────────

def cmd_url(args) -> int:
    """Print the best URL to access this instance."""
    try:
        from hub import config
        config.load_env()
        port = config.get_env_int("PORT", 5000)
    except Exception:
        port = int(os.environ.get("PORT", 5000))

    url = _public_url(port)

    # Check for an active Cloudflare tunnel too
    tunnel_url = None
    try:
        from hub import tunnel as _tunnel
        tunnel_url = _tunnel.get_url()
    except Exception:
        pass

    print()
    print("  Radd Hub v3.0 — Access URLs")
    print("  " + "─" * 36)
    print(f"  Web UI:   {url}")
    if tunnel_url:
        print(f"  Tunnel:   {tunnel_url}  (public, shareable)")
    print(f"  CLI:      python radd_hub.py cli")
    print()
    return 0


def cmd_tunnel(args) -> int:
    """Manage the Cloudflare quick tunnel for remote web UI access."""
    action = getattr(args, "action", "status") or "status"

    try:
        from hub import config
        config.load_env()
        port = config.get_env_int("PORT", 5000)
    except Exception:
        port = int(os.environ.get("PORT", 5000))

    try:
        from hub import tunnel as _tunnel
    except ImportError as e:
        print(f"  Tunnel module unavailable: {e}")
        return 1

    if action == "start":
        print(f"  Starting Cloudflare tunnel → localhost:{port} …")
        st = _tunnel.start(port)
        if st.get("url"):
            print(f"  Tunnel URL:  {st['url']}")
            print(f"  Share this URL to access the app from anywhere.")
        else:
            print(f"  Status: {st.get('message', 'unknown')}")
        log_lines = st.get("log_tail") or []
        for line in log_lines[-5:]:
            print(f"    {line}")
        return 0 if st.get("ok") else 1

    elif action == "stop":
        st = _tunnel.stop()
        print(f"  Tunnel stopped.  {st.get('message', '')}")
        return 0

    elif action == "url":
        url = _tunnel.get_url()
        if url:
            print(url)
            return 0
        else:
            print("  Tunnel not running. Start with:  python radd_hub.py tunnel start")
            return 1

    else:  # status (default)
        st = _tunnel.status()
        print()
        print("  Radd Hub — Tunnel status")
        print("  " + "─" * 32)
        if st["running"]:
            print(f"  Status:   running  (pid {st.get('pid', '?')})")
            if st.get("url"):
                print(f"  URL:      {st['url']}")
        else:
            print(f"  Status:   stopped")
        print(f"  Binary:   {'present' if st.get('binary_present') else 'not downloaded'}")
        if st.get("binary_path"):
            print(f"  Path:     {st['binary_path']}")
        print()
        return 0


def cmd_status(args) -> int:
    try:
        from hub import config
        config.load_env()
        port = config.get_env_int("PORT", 5000)
    except Exception:
        port = int(os.environ.get("PORT", 5000))

    pid   = _read_pid()
    alive = pid and _pid_alive(pid)
    up    = _port_open(port)

    print()
    print("  Radd Hub v3.0 — status")
    print("  " + "─" * 32)
    print(f"  Process:   {'running' if alive else 'stopped'}  (pid {pid or '—'})")
    print(f"  HTTP:      {'up' if up else 'down'}  (port {port})")
    if up:
        url = _public_url(port)
        print(f"  URL:       {url}")
        if url != f"http://localhost:{port}":
            print(f"  Local:     http://localhost:{port}")
    print()
    return 0 if up else 1


# ─────────────────────────────────────────────
# logs
# ─────────────────────────────────────────────

def cmd_logs(args) -> int:
    try:
        from hub import config
        config.load_env()
        log_file = config.LOG_DIR / "raddhub.log"
    except Exception:
        log_file = ROOT / "data" / "logs" / "raddhub.log"

    n = getattr(args, "n", 80)
    if not log_file.exists():
        print("  No log file yet. Run the server first.")
        return 0
    lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
    for line in lines[-n:]:
        print(line)
    return 0


# ─────────────────────────────────────────────
# keys
# ─────────────────────────────────────────────

def cmd_keys(args) -> int:
    try:
        from hub import config
        config.load_env()
        from hub import db
        db.init_db()
    except Exception as e:
        print(f"  Init error: {e}")
        return 1

    action = getattr(args, "action", "list")

    if action == "list":
        print("\n  Radd Hub — API key vault")
        print("  " + "─" * 50)
        providers = ["tmdb", "groq", "gemini", "openai", "openrouter",
                     "github", "gsheets_sa_json", "telegram", "omdb"]
        try:
            with db.conn() as c:
                for prov in providers:
                    rows = c.execute(
                        "SELECT is_active, last_status FROM keys WHERE provider=?", (prov,)
                    ).fetchall()
                    active   = sum(1 for r in rows if r["is_active"])
                    status_s = ", ".join({r["last_status"] for r in rows if r["last_status"]} or {"—"})
                    print(f"  {prov:<24} {active}/{len(rows)} active  status={status_s}")
        except Exception as e:
            print(f"  DB error: {e}")
        print()
        return 0

    if action == "get":
        prov = (getattr(args, "key", "") or "").strip()
        if not prov:
            print("  Usage: keys get PROVIDER")
            return 1
        try:
            from hub import keys as _keys
            val = _keys.get_active_value(prov)
            print(val if val is not None else "(not set)")
        except Exception as e:
            print(f"  Error: {e}")
        return 0

    if action == "set":
        kv = (getattr(args, "key", "") or "").strip()
        if "=" not in kv:
            print("  Usage: keys set PROVIDER=value")
            return 1
        provider, _, value = kv.partition("=")
        provider = provider.strip()
        value    = value.strip()
        try:
            from hub import keys as _keys
            _keys.add_key(provider, value, "cli")
            print(f"  Saved key for {provider}")
        except ValueError as e:
            print(f"  Error: {e}")
            from hub import keys as _keys
            print(f"  Known providers: {', '.join(_keys.PROVIDERS)}")
        except Exception as e:
            print(f"  Error: {e}")
        return 0

    if action == "test":
        prov = (getattr(args, "key", "") or "").strip().lower()
        if not prov:
            print("  Usage: keys test PROVIDER")
            return 1
        try:
            from hub import keys as _keys
            val = _keys.get_active_value(prov)
            if val is None:
                print(f"  No active key found for {prov}")
                return 1
            # Basic test per provider
            if prov == "tmdb":
                import urllib.request, urllib.error
                url = f"https://api.themoviedb.org/3/configuration?api_key={val}"
                try:
                    urllib.request.urlopen(url, timeout=5)
                    print(f"  {prov}: OK")
                    return 0
                except urllib.error.HTTPError as e:
                    print(f"  {prov}: FAILED — HTTP {e.code}")
                    return 1
            elif prov == "telegram":
                import urllib.request, urllib.error
                url = f"https://api.telegram.org/bot{val}/getMe"
                try:
                    r = urllib.request.urlopen(url, timeout=5)
                    data = json.loads(r.read())
                    print(f"  {prov}: OK — @{data['result']['username']}")
                    return 0
                except Exception as e:
                    print(f"  {prov}: FAILED — {e}")
                    return 1
            else:
                print(f"  {prov}: key present (no live test for this provider)")
                return 0
        except Exception as e:
            print(f"  Error: {e}")
            return 1

    print(f"  Unknown action: {action}")
    return 1


# ─────────────────────────────────────────────
# cli (interactive stream)
# ─────────────────────────────────────────────

def cmd_cli(args) -> int:
    try:
        from hub.cli import main as cli_main
        # Pass [] so hub/cli doesn't inherit sys.argv (which still contains 'cli')
        # and correctly falls through to the interactive REPL.
        cli_main([])
        return 0
    except ImportError as e:
        print(f"  Stream CLI unavailable: {e}")
        print("  Try: python radd_hub.py setup")
        return 1


# ─────────────────────────────────────────────
# dashboard  (backported from v2.0)
# ─────────────────────────────────────────────

def cmd_dashboard(args) -> int:
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
        from hub.cli import cmd_dashboard as _dash
        _dash(args)
        return 0
    except ImportError as e:
        print(f"  Dashboard unavailable: {e}")
        return 1


# ─────────────────────────────────────────────
# export  (backported from v1.0)
# ─────────────────────────────────────────────

def cmd_export(args) -> int:
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
        from hub.cli import cmd_export as _exp
        _exp(args)
        return 0
    except ImportError as e:
        print(f"  Export unavailable: {e}")
        return 1


# ─────────────────────────────────────────────
# broadcast  (backported from v2.0)
# ─────────────────────────────────────────────

def cmd_broadcast(args) -> int:
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
        from hub.cli import cmd_broadcast as _bcast
        _bcast(args)
        return 0
    except ImportError as e:
        print(f"  Broadcast unavailable: {e}")
        return 1


# ─────────────────────────────────────────────
# search  (backported from v1.0)
# ─────────────────────────────────────────────

def cmd_search(args) -> int:
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
        from hub.cli import cmd_search_library as _srch
        _srch(args)
        return 0
    except ImportError as e:
        print(f"  Search unavailable: {e}")
        return 1


# ─────────────────────────────────────────────
# sync (mirror push)
# ─────────────────────────────────────────────

def cmd_sync(args) -> int:
    """3-way GitHub + Google Sheets full-DB sync (ported from v1.0)."""
    try:
        from hub import config, db
        config.load_env()
        db.init_db()
    except Exception as e:
        print(f"  Init error: {e}")
        return 1

    mode = getattr(args, "mode", "both")
    print(f"  Pushing full database snapshot to mirrors (mode={mode}) …")
    try:
        from hub.sync import sync_all, status as sync_status
        result = sync_all(mode=mode)
    except Exception as e:
        print(f"  Sync error: {e}")
        return 1

    total = result.get("total_records", 0)
    print(f"  Total records in snapshot: {total}")

    if "github" in result:
        r = result["github"]
        ok_str = "✓ OK" if r.get("ok") else f"✗ FAILED: {r.get('error','?')}"
        print(f"  GitHub   → {ok_str}  ({r.get('elapsed', '?')}s)")

    if "gsheets" in result:
        r = result["gsheets"]
        ok_str = "✓ OK" if r.get("ok") else f"✗ FAILED: {r.get('error','?')}"
        print(f"  Sheets   → {ok_str}  ({r.get('elapsed', '?')}s)")

    gh_ok = result.get("github", {}).get("ok", True)
    gs_ok = result.get("gsheets", {}).get("ok", True)
    return 0 if (gh_ok and gs_ok) else 1


# ─────────────────────────────────────────────
# main
# ─────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(
        prog="radd_hub.py",
        description="Radd Hub v3.0 — all-in-one launcher",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = p.add_subparsers(dest="cmd")

    def _add(name, help_text):
        return sub.add_parser(name, help=help_text)

    r = _add("run",     "start server in foreground (default)")
    r.add_argument("--skip-setup", action="store_true", dest="skip_setup",
                   help="skip slow dep/env checks and start Flask immediately")
    r.set_defaults(fn=cmd_run, fix=False)

    s = _add("start",   "start server in background (PID file)")
    s.set_defaults(fn=cmd_start)

    t = _add("stop",    "stop background server")
    t.set_defaults(fn=cmd_stop)

    rs = _add("restart", "stop + start background server")
    rs.set_defaults(fn=cmd_restart)

    st = _add("status", "show server status")
    st.set_defaults(fn=cmd_status)

    lg = _add("logs",   "tail server log")
    lg.add_argument("-n", type=int, default=80, dest="n")
    lg.set_defaults(fn=cmd_logs)

    su = _add("setup",  "install deps + first-run setup")
    su.add_argument("--fix", action="store_true")
    su.set_defaults(fn=cmd_setup)

    dr = _add("doctor", "environment self-check")
    dr.add_argument("--fix", action="store_true")
    dr.set_defaults(fn=cmd_doctor)

    cl = _add("cli",    "launch interactive stream CLI")
    cl.set_defaults(fn=cmd_cli)

    kp = _add("keys",   "manage API keys  (list | get | set | test)")
    kp.add_argument("action", choices=["list", "get", "set", "test"])
    kp.add_argument("key",    nargs="?", help="provider name (or PROVIDER=value for set)")
    kp.set_defaults(fn=cmd_keys)

    sy = _add("sync",   "push full DB snapshot to GitHub + Sheets (3-way sync)")
    sy.add_argument("--mode", default="both",
                    choices=["github", "gsheets", "both"],
                    help="which mirror to push to (default: both)")
    sy.set_defaults(fn=cmd_sync)

    db_cmd = _add("dashboard", "live auto-refresh terminal dashboard")
    db_cmd.add_argument("-n", dest="interval", type=int, default=3,
                        help="refresh interval in seconds (default 3)")
    db_cmd.set_defaults(fn=cmd_dashboard)

    exp = _add("export",    "export library catalog to CSV or JSON file")
    exp.add_argument("--fmt",    "-f", default="json", choices=["json","csv"],
                     help="output format (default: json)")
    exp.add_argument("--output", "-o", default=None,
                     help="output path (default: radd_catalog.json / .csv)")
    exp.add_argument("--type",   "-t", default=None,
                     help="filter: movie / series / anime")
    exp.set_defaults(fn=cmd_export)

    bcast = _add("broadcast", "send WhatsApp broadcast to all verified users")
    bcast.add_argument("message", nargs="?", help="message text")
    bcast.add_argument("--roles", "-r", default="verified",
                       help="comma-separated roles (default: verified)")
    bcast.set_defaults(fn=cmd_broadcast)

    srch = _add("search", "search local library by title / genre / director")
    srch.add_argument("query", nargs="?", help="search query")
    srch.set_defaults(fn=cmd_search)

    url_p = _add("url", "print the best URL to access this instance")
    url_p.set_defaults(fn=cmd_url)

    tun_p = _add("tunnel", "manage Cloudflare quick tunnel for remote access")
    tun_p.add_argument("action", nargs="?", default="status",
                       choices=["status", "start", "stop", "url"],
                       help="tunnel action (default: status)")
    tun_p.set_defaults(fn=cmd_tunnel)

    # Accept --cli as a legacy alias for the 'cli' subcommand
    argv = sys.argv[1:]
    argv = ["cli" if a == "--cli" else a for a in argv]

    args = p.parse_args(argv)

    if not args.cmd:
        args.fix = False
        return cmd_run(args)

    return args.fn(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nbye")
        sys.exit(0)
