"""Nix LD_LIBRARY_PATH bootstrap — run BEFORE any chromium/playwright import.

Ported from v2.0 services/stream/_bootstrap.py and extended for v3.0.
Idempotent: guarded by _RADD_LD_BOOTSTRAPPED env var so double-importing
this module is harmless.
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

# Make project root importable regardless of entry-point
_HUB_ROOT = Path(__file__).resolve().parent.parent
if str(_HUB_ROOT) not in sys.path:
    sys.path.insert(0, str(_HUB_ROOT))

# ---------------------------------------------------------------------------
# Nix Chromium shared library bootstrap
# ---------------------------------------------------------------------------

_PACKAGES: tuple[str, ...] = (
    "mesa-libgbm",
    "libdrm",
    "libxshmfence",
    "nss",
    "nspr",
    "cups",
    "libxkbcommon",
    "alsa-lib",
    "at-spi2-atk",
    "at-spi2-core",
    "atk",
    "pango",
    "cairo",
    "expat",
    "dbus",
    "fontconfig",
    "freetype",
    "libXcomposite",
    "libXdamage",
    "libXext",
    "libXfixes",
    "libXrandr",
    "libXrender",
    "libXtst",
    "libXi",
    "libX11",
    "libxcb",
    "libXcursor",
    "libXScrnSaver",
    "libxshmfence",
    "libGL",
    "glib-2",
    "gtk+3",
    "gdk-pixbuf",
)


def _is_native_elf_lib_dir(lib_dir: str) -> bool:
    """Return True if lib_dir contains at least one native .so matching our arch."""
    try:
        want = b"\x02" if sys.maxsize > 2**32 else b"\x01"
        for name in os.listdir(lib_dir):
            if not name.endswith((".so", ".so.0", ".so.1", ".so.2", ".so.3", ".so.4")):
                if ".so." not in name:
                    continue
            full = os.path.join(lib_dir, name)
            if os.path.islink(full):
                try:
                    full = os.path.realpath(full)
                except OSError:
                    continue
            if not os.path.isfile(full):
                continue
            try:
                with open(full, "rb") as fh:
                    head = fh.read(5)
            except OSError:
                continue
            if len(head) >= 5 and head[:4] == b"\x7fELF":
                return head[4:5] == want
        return False
    except OSError:
        return False


def _build_nix_ld_path() -> str:
    """Scan /nix/store for the packages chromium needs and build LD_LIBRARY_PATH."""
    try:
        entries = os.listdir("/nix/store")
    except OSError:
        return ""

    buckets: dict[str, list[str]] = {}
    for entry in entries:
        if entry.endswith("-dev") or entry.endswith("-bin"):
            continue
        m = re.match(r"^[a-z0-9]{20,}-(.+)$", entry)
        if not m:
            continue
        rest = m.group(1)
        for pkg in _PACKAGES:
            if rest.startswith(pkg + "-"):
                tail = rest[len(pkg) + 1:]
                if not tail or not tail[0].isdigit():
                    continue
                buckets.setdefault(pkg, []).append(entry)
                break

    paths: list[str] = []
    for pkg in _PACKAGES:
        for cand in sorted(buckets.get(pkg, []), reverse=True):
            lib = f"/nix/store/{cand}/lib"
            if os.path.isdir(lib) and _is_native_elf_lib_dir(lib):
                paths.append(lib)
                break
    return ":".join(paths)


def _ensure_nix_ld_path() -> None:
    """Idempotently prepend Nix chromium libs to LD_LIBRARY_PATH."""
    if not os.path.isdir("/nix/store"):
        return
    if os.environ.get("_RADD_LD_BOOTSTRAPPED") == "1":
        return
    
    # Try loading from cache file to avoid slow /nix/store scan
    cache_file = Path.home() / ".cache" / "radd-hub" / "nix_ld_path.txt"
    extra = ""
    if cache_file.exists():
        try:
            extra = cache_file.read_text().strip()
        except Exception: pass
    
    if not extra:
        extra = _build_nix_ld_path()
        if extra:
            try:
                cache_file.parent.mkdir(parents=True, exist_ok=True)
                cache_file.write_text(extra)
            except Exception: pass

    if not extra:
        return
    current = os.environ.get("LD_LIBRARY_PATH", "")
    new = extra if not current else f"{extra}:{current}"
    os.environ["LD_LIBRARY_PATH"] = new
    os.environ["_RADD_LD_BOOTSTRAPPED"] = "1"


# Run automatically on import
_ensure_nix_ld_path()


# ---------------------------------------------------------------------------
# Project-local binary paths — must run BEFORE any playwright / aria2c import
# ---------------------------------------------------------------------------
# By pointing PLAYWRIGHT_BROWSERS_PATH inside the project folder, browser
# binaries travel WITH the project.  Moving Replit accounts, cloning to a
# new machine, or running on any Linux server never breaks Playwright because
# the binaries are stored in the project tree, not in account-specific
# ~/.cache/ms-playwright/.
#
# Similarly, .local/bin is prepended to PATH so aria2c and cloudflared that
# were downloaded into the project directory are always found first.
# ---------------------------------------------------------------------------

_PROJ_ROOT    = Path(__file__).resolve().parent.parent   # radd-hub/
_LOCAL_BIN    = _PROJ_ROOT / "local" / "bin"
_LOCAL_BR     = _PROJ_ROOT / "local" / "browsers"


def _ensure_project_local_paths() -> None:
    """Prepend .local/bin to PATH and optionally point Playwright at .local/browsers."""
    bin_str = str(_LOCAL_BIN)
    current = os.environ.get("PATH", "")
    if bin_str not in current.split(os.pathsep):
        os.environ["PATH"] = bin_str + os.pathsep + current

    # We NO LONGER force PLAYWRIGHT_BROWSERS_PATH to .local here.
    # The smart logic in hub.installer.find_chromium_executable() or
    # radd_hub.py will set RADD_CHROMIUM_EXECUTABLE or handle the fallback.


_ensure_project_local_paths()
