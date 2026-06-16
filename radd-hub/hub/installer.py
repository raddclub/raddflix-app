"""Cross-platform auto-installer for Chromium, aria2, Node.js, and bot deps.

Covers: Linux (inc. Replit/NixOS), macOS, Windows.
Every public function is safe to call multiple times (idempotent).
"""
from __future__ import annotations
import os
import sys
import shutil
import logging
import subprocess
from pathlib import Path
from . import config

log = logging.getLogger("hub.installer")

# ──────────────────────────────────────────────
# Project-local binary directories
# ──────────────────────────────────────────────
# All binaries (aria2c, cloudflared, Playwright browsers) are stored INSIDE
# the project folder so the project is self-contained.  Moving Replit accounts,
# cloning to a new machine, or running on any server never breaks anything.

def _project_bin_dir() -> Path:
    """Return the project-local bin dir: <project>/.local/bin/"""
    d = config.PROJECT_ROOT / "local" / "bin"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _project_browsers_dir() -> Path:
    """Return the project-local browsers dir: <project>/.local/browsers/"""
    d = config.PROJECT_ROOT / "local" / "browsers"
    d.mkdir(parents=True, exist_ok=True)
    return d


# ──────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────

def _add_to_path(directory: str) -> None:
    """Prepend *directory* to PATH for the current process."""
    current = os.environ.get("PATH", "")
    parts = current.split(os.pathsep)
    if directory not in parts:
        os.environ["PATH"] = directory + os.pathsep + current


def _run(cmd, *, cwd=None, env=None, capture=False) -> int:
    """Run a command and return its exit code."""
    display = " ".join(map(str, cmd)) if isinstance(cmd, (list, tuple)) else cmd
    log.info("$ %s", display)
    try:
        if capture:
            r = subprocess.run(cmd, cwd=cwd, env=env,
                               shell=isinstance(cmd, str),
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
            return r.returncode
        return subprocess.call(cmd, cwd=cwd, env=env,
                               shell=isinstance(cmd, str))
    except Exception as e:
        log.warning("command failed: %s", e)
        return -1


def _is_replit() -> bool:
    return bool(os.environ.get("REPL_ID") or os.environ.get("REPLIT_DEPLOYMENT"))


def _is_nix() -> bool:
    return os.path.isdir("/nix")


# ──────────────────────────────────────────────
# Nix / Replit path wrangling
# ──────────────────────────────────────────────

_NIX_BIN_DIRS = [
    "/home/runner/.nix-profile/bin",
    "/root/.nix-profile/bin",
    "/nix/var/nix/profiles/default/bin",
    "/run/current-system/sw/bin",
    # some Replit accounts put Node here
    "/home/runner/workspace/.cache/nix/profiles/default/bin",
]


def _extend_path_for_nix() -> None:
    """Add common Nix profile bin dirs to PATH so shutil.which finds them."""
    current = os.environ.get("PATH", "")
    parts = current.split(os.pathsep)
    added = False
    for d in _NIX_BIN_DIRS:
        if d not in parts and os.path.isdir(d):
            parts.insert(0, d)
            added = True
    # Also search /nix/store for node executables
    if _is_nix() and not shutil.which("node"):
        try:
            nix_store = Path("/nix/store")
            for entry in nix_store.iterdir():
                if "nodejs" in entry.name and (entry / "bin" / "node").exists():
                    d = str(entry / "bin")
                    if d not in parts:
                        parts.insert(0, d)
                        added = True
                    break
        except Exception:
            pass
    if added:
        os.environ["PATH"] = os.pathsep.join(parts)


# ──────────────────────────────────────────────
# Python dependencies
# ──────────────────────────────────────────────

def ensure_python_deps(req_path: Path) -> bool:
    """pip install -r requirements.txt, with Replit/NixOS fallbacks."""
    if not req_path.exists():
        return True

    base_cmd = [sys.executable, "-m", "pip", "install", "--quiet", "-r", str(req_path)]

    # Try plain install first
    rc = _run(base_cmd, capture=True)
    if rc == 0:
        return True

    # PEP 668 / NixOS — try --break-system-packages
    rc = _run(base_cmd + ["--break-system-packages"], capture=True)
    if rc == 0:
        return True

    # Last resort: --user
    rc = _run(base_cmd + ["--user"], capture=True)
    return rc == 0


# ──────────────────────────────────────────────
# Node.js detection & installation
# ──────────────────────────────────────────────

def _node_bin() -> str | None:
    """Return the path to the node executable, or None."""
    _extend_path_for_nix()
    return shutil.which("node") or shutil.which("node.exe")


def _npm_bin() -> str | None:
    """Return the path to the npm executable, or None."""
    _extend_path_for_nix()
    return shutil.which("npm") or shutil.which("npm.cmd")


def ensure_node() -> bool:
    """Ensure Node.js 18+ is available; try to install it if not.

    Returns True if node is available afterwards.
    """
    _extend_path_for_nix()
    if _node_bin():
        return True

    log.info("node not found — attempting install")
    o = config.os_name()

    if o == "linux":
        if _is_replit():
            log.warning(
                "Node.js not found on Replit. Add 'nodejs' via the Replit "
                "Packages panel (search for nodejs-18 or nodejs-22)."
            )
            return False

        # nix-env (rootless)
        if shutil.which("nix-env"):
            _run(["nix-env", "-iA", "nixpkgs.nodejs-22_x"])
            _extend_path_for_nix()
            if _node_bin():
                return True

        # apt (Debian / Ubuntu)
        if shutil.which("apt-get"):
            _run(["sudo", "-n", "apt-get", "update", "-qq"])
            if _run(["sudo", "-n", "apt-get", "install", "-y", "nodejs", "npm"]) == 0:
                return bool(_node_bin())

        # dnf (Fedora)
        if shutil.which("dnf"):
            if _run(["sudo", "-n", "dnf", "install", "-y", "nodejs", "npm"]) == 0:
                return bool(_node_bin())

    elif o == "mac":
        if shutil.which("brew"):
            if _run(["brew", "install", "node"]) == 0:
                return bool(_node_bin())

    elif o == "windows":
        return _install_node_windows()

    return bool(_node_bin())


def _install_node_windows() -> bool:
    """Download and run the Node.js 22 LTS installer for Windows."""
    import urllib.request, tempfile
    url = (
        "https://nodejs.org/dist/v22.14.0/"
        "node-v22.14.0-x64.msi"
    )
    tmp = Path(tempfile.mktemp(suffix=".msi"))
    log.info("Downloading Node.js for Windows …")
    try:
        urllib.request.urlretrieve(url, str(tmp))
        rc = _run(["msiexec", "/i", str(tmp), "/quiet", "/norestart"])
        tmp.unlink(missing_ok=True)
        # Node's default install dir
        node_dir = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "nodejs"
        if node_dir.exists():
            _add_to_path(str(node_dir))
        return bool(_node_bin())
    except Exception as e:
        log.warning("Node.js Windows install failed: %s", e)
        return False


# ──────────────────────────────────────────────
# npm / bot dependencies
# ──────────────────────────────────────────────

def ensure_node_deps(bot_dir: Path) -> bool:
    """Run npm install in *bot_dir* if node_modules is absent or stale."""
    if not (bot_dir / "package.json").exists():
        return True  # no JS project here

    modules = bot_dir / "node_modules"

    # Re-install if node_modules is completely missing
    if modules.exists():
        return True  # already installed

    npm = _npm_bin()
    if not npm:
        log.warning("npm not found — cannot install bot deps in %s", bot_dir)
        return False

    log.info("npm install in %s …", bot_dir)
    rc = _run(
        [npm, "install", "--no-audit", "--no-fund", "--prefer-offline"],
        cwd=str(bot_dir),
    )
    if rc != 0:
        # retry without --prefer-offline (might be first run)
        rc = _run([npm, "install", "--no-audit", "--no-fund"], cwd=str(bot_dir))
    return rc == 0


def ensure_all_bot_deps() -> dict:
    """Install npm deps for every bundled bot directory.

    Checks both the local bots/ tree (v3) and the sibling v2 bot dir.
    Returns a dict: {dir_name: True/False/skipped}.
    """
    results: dict = {}

    # Respect bot enable flags from .env (default false to avoid unnecessary npm installs).
    try:
        config.load_env()
    except Exception:
        pass
    bot_enabled = {
        "whatsapp": config.get_env_bool("ENABLE_WHATSAPP_BOT", False),
        "telegram": config.get_env_bool("ENABLE_TELEGRAM_BOT", False),
    }

    # v3 bundled bots
    bots_root = config.PROJECT_ROOT / "bots"
    if bots_root.is_dir():
        for sub in sorted(bots_root.iterdir()):
            if sub.is_dir() and (sub / "package.json").exists():
                if not bot_enabled.get(sub.name, True):
                    results[sub.name] = "skipped (disabled in .env)"
                    log.info("bot deps [%s]: skipped (disabled in .env)", sub.name)
                    continue
                ok = ensure_node_deps(sub)
                results[sub.name] = ok
                log.info("bot deps [%s]: %s", sub.name, "ok" if ok else "FAILED")

    # v2 sibling bot (optional, may not exist)
    v2_wa = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "whatsapp-bot"
    if v2_wa.is_dir() and (v2_wa / "package.json").exists() and bot_enabled.get("whatsapp", False):
        ok = ensure_node_deps(v2_wa)
        results["RaddHub-v2.0/whatsapp-bot"] = ok
        log.info("bot deps [v2/whatsapp-bot]: %s", "ok" if ok else "FAILED")

    return results


# ──────────────────────────────────────────────
# Playwright / Chromium
# ──────────────────────────────────────────────

def _chromium_marker() -> Path:
    """Marker file written after a successful Chromium install (project-local)."""
    return config.PROJECT_ROOT / "local" / ".chromium_ok"


def ensure_chromium() -> bool:
    """Install Playwright Chromium into .local/browsers/ if not already present."""
    try:
        import playwright  # noqa: F401
    except ImportError:
        log.info("playwright not installed — skipping chromium install")
        return False

    # 1) Check if we already have a launchable browser (Consolidated logic)
    path, is_pw = find_chromium_executable()
    if path:
        os.environ["RADD_CHROMIUM_EXECUTABLE"] = path
        # If it's a local PW-managed browser, we need to set the root so playwright sees it
        if is_pw and str(config.PROJECT_ROOT / "local") in path:
             os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(_project_browsers_dir()))
        
        log.info("using existing chromium: %s", path)
        return True

    # 2) Install into project-local .local/browsers (last resort)
    browsers_dir = _project_browsers_dir()
    log.info("No launchable Chromium found. Installing Playwright Chromium into %s …", browsers_dir)
    marker = _chromium_marker()
    env = os.environ.copy()
    env["PLAYWRIGHT_BROWSERS_PATH"] = str(browsers_dir)
    os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(browsers_dir)
    _add_to_path(str(_project_bin_dir()))

    try:
        # --with-deps needs apt/sudo; skip on Replit or non-root
        on_replit = _is_replit()
        use_deps  = sys.platform == "linux" and not on_replit and os.geteuid() == 0
        extra     = ["--with-deps"] if use_deps else []
        rc = _run(
            [sys.executable, "-m", "playwright", "install", "chromium", *extra],
            env=env,
        )
        if rc != 0 and extra:
            # --with-deps may fail on non-sudo systems; retry without it
            log.info("Retrying playwright install without --with-deps …")
            rc = _run(
                [sys.executable, "-m", "playwright", "install", "chromium"],
                env=env,
            )
        if rc == 0:
            try:
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.touch()
            except Exception:
                pass
            # Cache the browser path so startup probing is instant
            try:
                new_path, _ = find_chromium_executable()
                if new_path:
                    _cache = Path.home() / ".cache" / "radd-hub" / "chromium_path.txt"
                    _cache.parent.mkdir(parents=True, exist_ok=True)
                    _cache.write_text(f"{new_path}|pw")
                    os.environ.setdefault("RADD_CHROMIUM_EXECUTABLE", new_path)
                    log.info("Chromium path cached: %s", new_path)
            except Exception as _ce:
                log.debug("chromium path cache failed: %s", _ce)
        return rc == 0
    except Exception as e:
        log.warning("chromium install failed: %s", e)
        return False


# ──────────────────────────────────────────────
# aria2
# ──────────────────────────────────────────────

def ensure_aria2() -> bool:
    """Locate or install aria2c.

    Tries in order:
      1. Already on PATH (any platform)
      2. nix-env install (Replit / NixOS)
      3. apt-get / dnf / pacman (generic Linux)
      4. Download static Linux binary from GitHub (last resort on Linux)
      5. Homebrew (macOS)
      6. Download portable .exe (Windows)
    """
    _extend_path_for_nix()
    if shutil.which("aria2c"):
        return True

    o = config.os_name()

    if o == "linux":
        # ── 1. nix-env (Replit / NixOS) ──────────────────────────────────────
        if shutil.which("nix-env"):
            log.info("aria2c: trying nix-env install …")
            rc = _run(["nix-env", "-iA", "nixpkgs.aria2"], capture=True)
            _extend_path_for_nix()
            if shutil.which("aria2c"):
                log.info("aria2c installed via nix-env")
                return True

        # ── 2. System package managers ────────────────────────────────────────
        for pkg_cmd in (
            ["apt-get", "install", "-y", "aria2"],
            ["dnf",     "install", "-y", "aria2"],
            ["pacman",  "-S",  "--noconfirm", "aria2"],
        ):
            mgr = pkg_cmd[0]
            if shutil.which(mgr):
                rc = _run(["sudo", "-n"] + pkg_cmd, capture=True)
                if rc == 0 and shutil.which("aria2c"):
                    return True

        # ── 3. Download static binary (universal Linux fallback) ──────────────
        if _download_aria2_linux_static():
            _extend_path_for_nix()
            return bool(shutil.which("aria2c"))

        log.warning(
            "aria2c auto-install failed on this Linux environment. "
            "Install it manually: apt install aria2 / nix-env -iA nixpkgs.aria2"
        )

    elif o == "mac":
        if shutil.which("brew"):
            if _run(["brew", "install", "aria2"]) == 0:
                return bool(shutil.which("aria2c"))

    elif o == "windows":
        if _download_aria2_windows():
            _extend_path_for_nix()
            return bool(shutil.which("aria2c"))
        log.info("Install aria2 manually from https://aria2.github.io/")

    return bool(shutil.which("aria2c"))


def _download_aria2_linux_static() -> bool:
    """Download a pre-built static aria2c binary for Linux x86_64 / aarch64.

    The binary is saved to .local/bin/ inside the project folder so it
    travels with the project across Replit accounts and machines.
    """
    import urllib.request
    import tarfile
    import platform

    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        asset = "aria2-1.37.0-linux-gnu-64bit-build1.tar.bz2"
    elif machine in ("aarch64", "arm64"):
        asset = "aria2-1.37.0-linux-gnu-aarch64-build1.tar.bz2"
    else:
        log.warning("aria2 static binary: unsupported arch %s", machine)
        return False

    base_url  = "https://github.com/aria2/aria2/releases/download/release-1.37.0/"
    url       = base_url + asset
    bin_dir   = _project_bin_dir()          # project-local .local/bin/
    aria2_bin = bin_dir / "aria2c"

    if aria2_bin.exists():
        _add_to_path(str(bin_dir))
        log.info("aria2c already present at %s", aria2_bin)
        return True

    log.info("Downloading static aria2c for Linux (%s) into %s …", machine, bin_dir)

    import tempfile
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".tar.bz2", delete=False) as tmp:
            urllib.request.urlretrieve(url, tmp.name)
            tmp_path = Path(tmp.name)

        with tarfile.open(tmp_path, "r:bz2") as tf:
            for member in tf.getmembers():
                if member.name.endswith("/aria2c") or member.name == "aria2c":
                    f = tf.extractfile(member)
                    if f:
                        aria2_bin.write_bytes(f.read())
                        aria2_bin.chmod(0o755)
                        break

        if aria2_bin.exists():
            _add_to_path(str(bin_dir))
            log.info("aria2c installed at %s", aria2_bin)
            return True

    except Exception as exc:
        log.warning("aria2c static download failed: %s", exc)
        try:
            if aria2_bin.exists():
                aria2_bin.unlink()
        except Exception:
            pass
    finally:
        if tmp_path and tmp_path.exists():
            try:
                tmp_path.unlink()
            except Exception:
                pass

    return False


def _download_aria2_windows() -> bool:
    """Download portable aria2c for Windows into .local/bin/."""
    import urllib.request, zipfile, tempfile

    bin_dir   = _project_bin_dir()          # project-local .local/bin/
    aria2_exe = bin_dir / "aria2c.exe"
    if aria2_exe.exists():
        _add_to_path(str(bin_dir))
        return True

    url = (
        "https://github.com/aria2/aria2/releases/download/"
        "release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
    )
    try:
        log.info("Downloading aria2c for Windows …")
        bin_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
            urllib.request.urlretrieve(url, tmp.name)
            tmp_path = Path(tmp.name)
        with zipfile.ZipFile(tmp_path) as zf:
            for member in zf.namelist():
                if member.endswith("aria2c.exe"):
                    aria2_exe.write_bytes(zf.read(member))
                    break
        tmp_path.unlink(missing_ok=True)
        if aria2_exe.exists():
            _add_to_path(str(bin_dir))
            log.info("aria2c installed at %s", aria2_exe)
            return True
    except Exception as exc:
        log.warning("aria2c Windows download failed: %s", exc)
    return False


def _probe_chromium(path: str) -> bool:
    """Verify a chromium binary actually launches."""
    if not (path and os.path.isfile(path) and os.access(path, os.X_OK)):
        return False
    try:
        # Fast binary sanity check.
        r = subprocess.run(
            [path, "--version"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=3.0,
            env=os.environ,
        )
        return r.returncode == 0 and b"hrom" in (r.stdout or b"")
    except Exception:
        return False


def find_chromium_executable() -> tuple[str | None, bool]:
    """Find the best Playwright-compatible Chromium executable.
    Priority:
      1. System-installed (Chrome, Edge, Chromium)
      2. Global Playwright cache (e.g. AppData/Local/ms-playwright)
      3. Cached path from previous run
      4. Project-local .local/browsers (last resort)
    Returns (path, is_pw_managed).
    """
    # 0. Check env override
    env_path = os.environ.get("RADD_CHROMIUM_EXECUTABLE", "").strip()
    if env_path and _probe_chromium(env_path):
        return env_path, False

    # 1. System browsers
    for name in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "chrome", "msedge"):
        found = shutil.which(name)
        if found and _probe_chromium(found):
            return found, False

    # 2. Global Playwright cache
    import glob as _glob
    pw_roots = [
        config.PROJECT_ROOT / ".cache" / "ms-playwright", # Replit workspace cache
        Path.home() / "AppData" / "Local" / "ms-playwright",
        Path.home() / ".cache" / "ms-playwright",
        Path("/usr/local/share/ms-playwright"),
    ]
    if os.environ.get("LOCALAPPDATA"):
        pw_roots.append(Path(os.environ["LOCALAPPDATA"]) / "ms-playwright")

    pw_patterns = [
        "chromium_headless_shell-*/chrome-headless-shell-win*/chrome-headless-shell.exe",
        "chromium-*/chrome-win*/chrome.exe",
        "chromium_headless_shell-*/chrome-headless-shell-linux*/chrome-headless-shell",
        "chromium-*/chrome-linux*/chrome",
        "chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium",
    ]
    for root in pw_roots:
        if root.exists():
            for pat in pw_patterns:
                matches = sorted(_glob.glob(str(root / pat)), reverse=True)
                for m in matches:
                    if _probe_chromium(m):
                        return m, True

    # 3. Cached path
    _cache_file = Path.home() / ".cache" / "radd-hub" / "chromium_path.txt"
    try:
        if _cache_file.exists():
            line = _cache_file.read_text().strip()
            if "|" in line:
                cached_path, cached_kind = line.split("|", 1)
                if _probe_chromium(cached_path):
                    return cached_path, (cached_kind == "pw")
    except Exception:
        pass

    # 4. Project-local .local/browsers
    local_root = _project_browsers_dir()
    for pat in pw_patterns:
        matches = sorted(_glob.glob(str(local_root / pat)), reverse=True)
        for m in matches:
            if _probe_chromium(m):
                return m, True

    return None, False


# ──────────────────────────────────────────────
# Doctor / diagnostics
# ──────────────────────────────────────────────

def doctor() -> dict:
    """Return a diagnostic dict about the environment."""
    import importlib.util
    _extend_path_for_nix()
    out: dict = {
        "os":      config.os_name(),
        "python":  sys.version.split()[0],
        "replit":  _is_replit(),
        "nix":     _is_nix(),
    }
    out["node"]   = shutil.which("node") or False
    out["npm"]    = shutil.which("npm") or False
    out["aria2c"] = bool(shutil.which("aria2c"))

    # Node version
    if out["node"]:
        try:
            r = subprocess.run([out["node"], "--version"],
                               capture_output=True, text=True, timeout=5)
            out["node_version"] = r.stdout.strip()
        except Exception:
            out["node_version"] = "unknown"
    else:
        out["node_version"] = None

    # Chromium
    out["chromium"] = False
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            try:
                pw.chromium.launch(headless=True).close()
                out["chromium"] = True
            except Exception:
                pass
    except Exception:
        pass

    # Python packages
    for pkg in ("flask", "requests", "gspread", "watchdog", "cryptography",
                "playwright", "bs4", "cryptography"):
        out[pkg] = importlib.util.find_spec(pkg) is not None

    # Bot node_modules
    bots_root = config.PROJECT_ROOT / "bots"
    if bots_root.is_dir():
        for sub in sorted(bots_root.iterdir()):
            if sub.is_dir() and (sub / "package.json").exists():
                out[f"bot_{sub.name}_modules"] = (sub / "node_modules").exists()

    return out
