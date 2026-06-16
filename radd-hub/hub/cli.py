"""Radd Hub v3.0 — interactive stream CLI.

Launch via:  python radd_hub.py cli
Or directly: python -m hub.cli

Includes all v1.0/v2.0 features:
  - Full ASCII banner
  - readline arrow-key history
  - Batch multi-movie Ctrl+D input mode
  - Full interactive settings menu (quality, language, content_type, domains)
  - Spinner live-progress watch
  - In-process scraper execution when server is not running
"""
from __future__ import annotations
import os
import sys
import time
import json
import threading
import argparse
from pathlib import Path

# Ensure project root is on path
_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

# Bootstrap Nix LD_LIBRARY_PATH for Chromium before any imports
try:
    from . import _bootstrap  # noqa: F401
except ImportError:
    try:
        import hub._bootstrap  # noqa: F401
    except ImportError:
        pass

from . import config, db
config.load_env()
db.init_db()

# Optional readline for arrow-key history + tab-completion (graceful fallback on Windows)
try:
    import readline as _readline
    _readline.set_history_length(500)
    _HAS_READLINE = True
except ImportError:
    _HAS_READLINE = False

# All REPL command names (populated after command functions are defined — see _setup_tab_completion)
_REPL_COMMANDS: list[str] = []


def _setup_tab_completion() -> None:
    """Register readline tab-completer for REPL command names."""
    if not _HAS_READLINE:
        return

    def _completer(text: str, state: int) -> str | None:
        matches = [c for c in _REPL_COMMANDS if c.startswith(text)]
        return matches[state] if state < len(matches) else None

    _readline.set_completer(_completer)
    _readline.parse_and_bind("tab: complete")


# ─────────────────────────────────────────────────────────────────────────────
# ANSI helpers
# ─────────────────────────────────────────────────────────────────────────────

_HAS_COLOR = sys.stdout.isatty()

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _HAS_COLOR else text

def green(t):   return _c("92",  t)
def red(t):     return _c("91",  t)
def yellow(t):  return _c("93",  t)
def cyan(t):    return _c("96",  t)
def bold(t):    return _c("1",   t)
def muted(t):   return _c("2",   t)
def magenta(t): return _c("95",  t)


# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────

BANNER = f"""{bold(cyan('''
┌─────────────────────────────────────────────────────┐
│         Radd Hub  v3.0  Stream CLI                  │
│   AI-Powered Movie Download Link Generator          │
└─────────────────────────────────────────────────────┘'''))}
"""


# ─────────────────────────────────────────────────────────────────────────────
# Status / progress helpers
# ─────────────────────────────────────────────────────────────────────────────

_STATUS_COLOR = {
    "done":       green,
    "error":      red,
    "failed":     red,
    "processing": cyan,
    "searching":  cyan,
    "generating": yellow,
    "downloading": cyan,
    "paused":     yellow,
    "queued":     muted,
    "cancelled":  muted,
}

def _fmt_status(s: str) -> str:
    fn = _STATUS_COLOR.get(s, lambda x: x)
    return fn(s.upper())

def _bar(pct: float, width: int = 20) -> str:
    pct = max(0.0, min(100.0, float(pct or 0)))
    filled = int(width * pct / 100)
    return "[" + "█" * filled + "░" * (width - filled) + f"] {pct:5.1f}%"

def _ago(ts: int | None) -> str:
    if not ts: return "—"
    d = int(time.time()) - ts
    if d < 60:    return f"{d}s ago"
    if d < 3600:  return f"{d // 60}m ago"
    return f"{d // 3600}h ago"


# ─────────────────────────────────────────────────────────────────────────────
# API calls to running hub server
# ─────────────────────────────────────────────────────────────────────────────

def _api_base() -> str:
    port = config.get_env_int("PORT", 5000)
    return f"http://localhost:{port}"


def _get_session_cookie() -> str | None:
    """Try to auto-auth against the local server."""
    import urllib.request, urllib.parse, urllib.error, http.cookiejar
    base = _api_base()
    jar  = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    admin_user = config.get_env("RADD_ADMIN_USER", "admin")
    admin_pass = config.get_env("RADD_ADMIN_PASS", "")
    if not admin_pass:
        return None
    body = urllib.parse.urlencode({
        "username": admin_user,
        "password": admin_pass,
    }).encode()
    try:
        opener.open(f"{base}/auth/login", body, timeout=5)
        for cookie in jar:
            if "session" in cookie.name.lower():
                return f"{cookie.name}={cookie.value}"
    except Exception:
        pass
    return None


_session_cookie: str | None = None
_session_loaded = False

def _cookie() -> str:
    global _session_cookie, _session_loaded
    if not _session_loaded:
        _session_cookie = _get_session_cookie()
        _session_loaded = True
    return _session_cookie or ""


def _req(method: str, path: str, body: dict | None = None) -> dict:
    """Make authenticated HTTP request to running hub server."""
    import urllib.request, urllib.error, json as _json
    base = _api_base()
    url  = f"{base}{path}"
    data = _json.dumps(body).encode() if body is not None else None
    req  = urllib.request.Request(
        url, data=data, method=method,
        headers={
            "Content-Type": "application/json",
            "Cookie": _cookie(),
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return _json.loads(r.read())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: return _json.loads(raw)
        except Exception: return {"error": raw or f"HTTP {e.code}"}
    except Exception as e:
        return {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Direct DB operations (when server not running)
# ─────────────────────────────────────────────────────────────────────────────

def _queue_list_db() -> list[dict]:
    with db.conn() as c:
        rows = c.execute(
            "SELECT job_id, movie, site, status, progress, message, url, created_at, updated_at "
            "FROM queue ORDER BY id DESC LIMIT 100"
        ).fetchall()
    return [dict(r) for r in rows]


def _queue_add_db(movie: str, site: str = "auto") -> str:
    import uuid
    jid = uuid.uuid4().hex[:10]
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO queue(job_id,movie,site,status,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            (jid, movie, site, "queued", now, now)
        )
    return jid


# ─────────────────────────────────────────────────────────────────────────────
# In-process job execution (when hub server is not running)
# ─────────────────────────────────────────────────────────────────────────────

_local_jobs: dict[str, dict] = {}
_local_jobs_lock = threading.Lock()


def _run_job_in_process(job_id: str, movie: str, site: str, log_fn) -> None:
    """Run a scraper job directly in this process (no server needed)."""
    import uuid as _uuid
    job = {
        "job_id":       job_id,
        "movie":        movie,
        "status":       "queued",
        "progress":     0,
        "pause_event":  threading.Event(),
        "cancel_event": threading.Event(),
    }
    job["pause_event"].set()

    with _local_jobs_lock:
        _local_jobs[job_id] = job

    sc_config = {
        "auto_download":   (db.setting("auto_download", "1") or "1") == "1",
        "download_dir":    db.setting("download_dir", str(config.MEDIA_DIR)) or str(config.MEDIA_DIR),
        "quality":         db.setting("preferred_quality", "1080p") or "1080p",
        "language":        db.setting("preferred_language", "Hindi") or "Hindi",
        "content_type":    db.setting("content_type", "any") or "any",
        "browser": {
            "headless": (db.setting("headless", "1") or "1") == "1",
        },
    }

    try:
        from . import scraper
        if site == "auto":
            scraper.run_job_ai(job, sc_config, log_fn)
        else:
            try:
                from . import sites
                plugin = sites.get_plugin(site)
                scraper.run_job(job, sc_config, plugin, log_fn)
            except Exception as e:
                log_fn(f"Plugin error for '{site}': {e}")
                raise
    except Exception as e:
        log_fn(f"ERROR: {e}")
        job["status"] = "error"
    finally:
        with _local_jobs_lock:
            _local_jobs.pop(job_id, None)

    return job


# ─────────────────────────────────────────────────────────────────────────────
# Settings menu (full interactive v2-compatible)
# ─────────────────────────────────────────────────────────────────────────────

_QUALITY_OPTS   = ["360p", "480p", "720p", "1080p", "4k"]
_LANGUAGE_OPTS  = ["Hindi", "Urdu", "Punjabi", "Dual Audio", "Any"]
_CONTENT_OPTS   = ["movie", "anime", "series", "any"]
_SITE_OPTS      = ["auto"]  # extended dynamically

_DOMAIN_KEYS = [
    ("domain_vegamovies",  "VegaMovies domain",  "https://vegamovies.market"),
    ("domain_katmoviehd",  "KatMovieHD domain",  "https://katmoviehd.pictures"),
    ("domain_rogmovies",   "RogMovies domain",   "https://rogmovies.vip"),
    ("domain_ssrmovies",   "SSRMovies domain",   "https://ssrmovies.green"),
    ("domain_rareanimes",  "RareAnimes domain",  "https://www.rareanimes.buzz"),
    ("domain_nexdrive",    "NexDrive domain",    "nexdrive.pro"),
    ("domain_vcloud",      "VCloud domain",      "vcloud.zip"),
    ("domain_hdhub4u",     "HdHub4u domain",     "https://hdhub4u.mov"),
    ("domain_moviesdrive", "MoviesDrive domain", "https://moviesdrive.world"),
]


def _load_settings() -> dict:
    return {
        "auto_download":      db.setting("auto_download", "1") or "1",
        "download_dir":       db.setting("download_dir",  str(config.MEDIA_DIR)) or str(config.MEDIA_DIR),
        "headless":           db.setting("headless",      "1") or "1",
        "max_parallel":       db.setting("max_parallel",  "2") or "2",
        "active_site":        db.setting("active_site",   "auto") or "auto",
        "preferred_quality":  db.setting("preferred_quality", "1080p") or "1080p",
        "preferred_language": db.setting("preferred_language", "Hindi") or "Hindi",
        "content_type":       db.setting("content_type",  "any") or "any",
        **{k: db.setting(k, default) or default for k, _, default in _DOMAIN_KEYS},
    }


def _save_settings(s: dict) -> None:
    for k, v in s.items():
        db.set_setting(k, str(v))


def settings_menu() -> None:
    """Full interactive settings menu (v2-compatible, 11 options)."""
    cfg = _load_settings()

    # Build site list dynamically
    all_sites = ["auto"]
    try:
        from . import sites as _sites
        all_sites += [p["name"] for p in _sites.list_plugins()]
    except Exception:
        pass

    while True:
        auto_dl = cfg["auto_download"] in ("1", "true", "yes", "on")
        headless = cfg["headless"] in ("1", "true", "yes", "on")
        print(f"\n{bold(magenta('╔════════════════════ SETTINGS ════════════════════╗'))}")
        print(f"  1. Auto-download:      {green('ON') if auto_dl else red('OFF')}")
        print(f"  2. Download directory: {cyan(cfg['download_dir'])}")
        print(f"  3. Headless browser:   {green('ON') if headless else yellow('OFF (browser visible)')}")
        print(f"  4. Max parallel:       {cyan(cfg['max_parallel'])}")
        print(f"  5. Default site:       {cyan(cfg['active_site'])}")
        print(f"  6. Preferred quality:  {cyan(cfg['preferred_quality'])}  (360p/480p/720p/1080p/4k)")
        print(f"  7. Preferred language: {cyan(cfg['preferred_language'])}  (Hindi/Urdu/Punjabi/Dual Audio/Any)")
        print(f"  8. Content type:       {cyan(cfg['content_type'])}  (movie/anime/series/any)")
        print(f"  9. Domain settings")
        print(f" 10. Show all settings (JSON)")
        print(f" 11. Save & exit settings")
        print(f"  0. Exit without saving")
        print()
        try:
            choice = input("  Choice: ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n  {yellow('Settings not saved.')}")
            break

        if choice == "1":
            cfg["auto_download"] = "0" if auto_dl else "1"
            state = "ENABLED" if cfg["auto_download"] == "1" else "DISABLED"
            print(f"  {green(f'Auto-download {state}.')}")
            if cfg["auto_download"] == "1":
                print(f"  {yellow('Files will be downloaded after link generation.')}")

        elif choice == "2":
            d = input(f"  Download dir [{cfg['download_dir']}]: ").strip()
            if d:
                cfg["download_dir"] = d
                print(f"  {green(f'Download dir: {d}')}")

        elif choice == "3":
            cfg["headless"] = "0" if headless else "1"
            state = "ON" if cfg["headless"] == "1" else "OFF (browser visible)"
            print(f"  {green(f'Headless: {state}')}")

        elif choice == "4":
            v = input(f"  Max parallel [current: {cfg['max_parallel']}]: ").strip()
            try:
                n = int(v)
                if 1 <= n <= 10:
                    cfg["max_parallel"] = str(n)
                    print(f"  {green(f'Max parallel → {n}')}")
                else:
                    print(f"  {red('Enter 1–10.')}")
            except ValueError:
                if v:
                    print(f"  {red('Invalid number.')}")

        elif choice == "5":
            print()
            for i, s in enumerate(all_sites):
                print(f"    {i+1}. {s}")
            idx = input("  Pick number: ").strip()
            try:
                cfg["active_site"] = all_sites[int(idx) - 1]
                site_val = cfg["active_site"]
                print(f"  {green(f'Default site → {site_val}')}")
            except (ValueError, IndexError):
                if idx:
                    print(f"  {red('Invalid choice.')}")

        elif choice == "6":
            print(f"  Quality options: {', '.join(_QUALITY_OPTS)}")
            v = input(f"  Preferred quality [{cfg['preferred_quality']}]: ").strip().lower()
            if v in _QUALITY_OPTS:
                cfg["preferred_quality"] = v
                print(f"  {green(f'Quality → {v}')}")
            elif v:
                print(f"  {red(f'Invalid. Choose from: {chr(44).join(_QUALITY_OPTS)}')}")

        elif choice == "7":
            print(f"  Language options: {', '.join(_LANGUAGE_OPTS)}")
            v = input(f"  Preferred language [{cfg['preferred_language']}]: ").strip()
            matched = next((o for o in _LANGUAGE_OPTS if o.lower() == v.lower()), None)
            if matched:
                cfg["preferred_language"] = matched
                print(f"  {green(f'Language → {matched}')}")
                if matched != "Any":
                    print(f"  {yellow(f'Note: Downloads will prioritize {matched} audio.')}")
            elif v:
                print(f"  {red(f'Invalid. Choose: {chr(44).join(_LANGUAGE_OPTS)}')}")

        elif choice == "8":
            print("  Content type options:")
            print("    movie  — single movie file")
            print("    anime  — anime show/movie (ZIP/RAR archives preferred)")
            print("    series — TV drama/series (ZIP/RAR archives preferred)")
            print("    any    — no filter")
            v = input(f"  Content type [{cfg['content_type']}]: ").strip().lower()
            if v in _CONTENT_OPTS:
                cfg["content_type"] = v
                print(f"  {green(f'Content type → {v}')}")
                if v in ("anime", "series"):
                    print(f"  {yellow('ZIP/RAR archives will be preferred.')}")
            elif v:
                print(f"  {red(f'Choose from: {chr(44).join(_CONTENT_OPTS)}')}")

        elif choice == "9":
            print(f"\n  {bold('Domain settings')} (press Enter to keep current):")
            for key, label, default in _DOMAIN_KEYS:
                cur = cfg.get(key, default)
                new_val = input(f"  {label} [{cur}]: ").strip()
                if new_val:
                    cfg[key] = new_val
            print(f"  {green('Domains updated.')}")

        elif choice == "10":
            display = {k: v for k, v in cfg.items()}
            print(f"\n{json.dumps(display, indent=2)}")

        elif choice == "11":
            _save_settings(cfg)
            print(f"  {green('Settings saved!')}")
            break

        elif choice == "0":
            print(f"  {yellow('Settings not saved.')}")
            break

        elif choice:
            print(f"  {red('Invalid choice. Enter 0–11.')}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI commands
# ─────────────────────────────────────────────────────────────────────────────

def cmd_queue(args):
    """Show the download queue."""
    try:
        rows = _req("GET", "/stream/api/queue")
        if isinstance(rows, dict) and "error" in rows:
            rows = _queue_list_db()
    except Exception:
        rows = _queue_list_db()

    if not rows:
        print(muted("  Queue is empty."))
        return

    print()
    print(bold(f"  {'JOB ID':<12}  {'MOVIE':<36}  {'SITE':<14}  {'STATUS':<14}  PROGRESS"))
    print("  " + "─" * 92)
    for r in rows:
        pct   = float(r.get("progress") or 0)
        bar   = _bar(pct, 14)
        movie = (r.get("movie") or "")[:35]
        print(f"  {r['job_id']:<12}  {movie:<36}  {(r.get('site') or 'auto'):<14}  "
              f"{_fmt_status(r.get('status','?')):<14}  {bar}")
        if r.get("message"):
            print(f"  {'':12}  {muted(r['message'][:80])}")
    print()


def cmd_add(args):
    """Queue one or more movies."""
    movies = args.movie if isinstance(args.movie, list) else [args.movie]
    site   = getattr(args, "site", "auto") or "auto"
    for m in movies:
        m = m.strip()
        if not m: continue
        try:
            d = _req("POST", "/stream/api/queue", {"movie": m, "site": site})
            if d.get("ok"):
                print(f"  {green('Queued')}: {m}  (job {d.get('job_id')})")
            else:
                jid = _queue_add_db(m, site)
                print(f"  {yellow('Queued (via DB)')}: {m}  (job {jid})")
        except Exception:
            jid = _queue_add_db(m, site)
            print(f"  {yellow('Queued (via DB)')}: {m}  (job {jid})")


def cmd_cancel(args):
    jid = args.job_id
    d   = _req("POST", f"/stream/api/queue/{jid}/cancel")
    if d.get("ok"):
        print(f"  {green('Cancelled')}: {jid}")
    else:
        print(f"  {red('Error')}: {d.get('error','unknown')}")


def cmd_pause(args):
    jid = args.job_id
    d   = _req("POST", f"/stream/api/queue/{jid}/pause")
    print(f"  {green('Paused') if d.get('ok') else red('Error: '+str(d.get('error','?')))}: {jid}")


def cmd_resume(args):
    jid = args.job_id
    d   = _req("POST", f"/stream/api/queue/{jid}/resume")
    print(f"  {green('Resumed') if d.get('ok') else red('Error: '+str(d.get('error','?')))}: {jid}")


def cmd_retry(args):
    jid = args.job_id
    d   = _req("POST", f"/stream/api/queue/{jid}/retry")
    print(f"  {green('Re-queued') if d.get('ok') else red('Error: '+str(d.get('error','?')))}: {jid}")


def cmd_remove(args):
    jid = args.job_id
    d   = _req("DELETE", f"/stream/api/queue/{jid}")
    print(f"  {green('Removed') if d.get('ok') else red('Error: '+str(d.get('error','?')))}: {jid}")


def cmd_clear(args):
    d = _req("POST", "/stream/api/queue/clear-done")
    print(f"  {green('Cleared')} {d.get('deleted', 0)} finished jobs.")


def cmd_cancel_all(args):
    if not getattr(args, "yes", False):
        try:
            ans = input("  Cancel ALL active jobs? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            return
        if ans != "y": return
    d = _req("POST", "/stream/api/queue/cancel-all")
    print(f"  {green('Done')} — cancelled {d.get('affected', 0)} jobs.")


def cmd_pause_all(args):
    d = _req("POST", "/stream/api/queue/pause-all")
    print(f"  {green('Done')} — paused {d.get('affected', 0)} jobs.")


def cmd_resume_all(args):
    d = _req("POST", "/stream/api/queue/resume-all")
    print(f"  {green('Done')} — resumed {d.get('affected', 0)} jobs.")


def cmd_log(args):
    jid = args.job_id
    d   = _req("GET", f"/stream/api/queue/{jid}/log")
    if "error" in d:
        with db.conn() as c:
            row = c.execute("SELECT log FROM queue WHERE job_id=?", (jid,)).fetchone()
        text = row["log"] if row and row["log"] else "(no log)"
    else:
        text = d.get("log") or "(no log)"
    print()
    print(text)
    print()


def _watch_live(job_id: str, secs: int = 3) -> None:
    """Spinner-based live watcher for a single job (v2-style)."""
    _SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    i = 0
    last_stage = None
    last_log   = ""
    last_hb    = 0

    print(f"  {muted(f'Watching [{job_id}] — Ctrl+C to detach (job continues in bg)')}")
    try:
        while True:
            # Try live server first
            d = _req("GET", f"/stream/api/queue/{job_id}/log")
            status_d = None
            try:
                ql = _req("GET", "/stream/api/queue")
                if isinstance(ql, list):
                    status_d = next((r for r in ql if r.get("job_id") == job_id), None)
            except Exception:
                pass

            if status_d is None:
                with db.conn() as c:
                    row = c.execute(
                        "SELECT status, progress, message FROM queue WHERE job_id=?", (job_id,)
                    ).fetchone()
                if row:
                    status_d = dict(row)

            s = (status_d or {}).get("status", "unknown")
            pct = float((status_d or {}).get("progress") or 0)
            msg = (status_d or {}).get("message") or ""

            sp = _SPIN[i % len(_SPIN)] if s not in ("done", "error", "cancelled") else "✓"
            line = f"  {sp} [{job_id}]  {_fmt_status(s)}  {_bar(pct)}  {muted(msg[:40])}"
            sys.stdout.write("\r\033[K" + line)
            sys.stdout.flush()

            # Print new log lines
            log_text = (d.get("log") or "") if isinstance(d, dict) else ""
            if log_text and log_text != last_log:
                new_lines = log_text.splitlines()
                old_lines = last_log.splitlines()
                for ln in new_lines[len(old_lines):]:
                    sys.stdout.write(f"\n  {muted(ln)}")
                sys.stdout.flush()
                last_log = log_text

            if s in ("done", "error", "cancelled", "failed"):
                print()
                if status_d:
                    if status_d.get("url"):
                        print(f"\n  {green('URL:')}  {cyan(status_d['url'])}")
                    if s in ("error", "failed"):
                        print(f"\n  {red('Error:')} {status_d.get('message','')}")
                break

            time.sleep(secs)
            i += 1

    except KeyboardInterrupt:
        print(f"\n  {yellow(f'(detached — job [{job_id}] continues in background)')}")


def cmd_watch(args):
    """Watch queue status, refreshing every few seconds."""
    jid  = getattr(args, "job_id", None)
    secs = getattr(args, "interval", 3)

    if jid:
        _watch_live(jid, secs)
        return

    print(f"  Watching queue (Ctrl+C to stop, refresh every {secs}s)...")
    try:
        while True:
            os.system("cls" if sys.platform.startswith("win") else "clear")
            cmd_queue(args)
            time.sleep(secs)
    except KeyboardInterrupt:
        print("\n  Stopped.")


def cmd_results(args):
    """Show completed jobs with download links."""
    d = _req("GET", "/stream/api/results")
    if isinstance(d, dict) and "error" in d:
        with db.conn() as c:
            rows = [dict(r) for r in c.execute(
                "SELECT job_id, movie, url, updated_at FROM queue WHERE status='done' "
                "ORDER BY updated_at DESC LIMIT 50"
            ).fetchall()]
    else:
        rows = d if isinstance(d, list) else []

    if not rows:
        print(muted("  No completed downloads yet."))
        return
    print()
    print(bold(f"  {'MOVIE':<40}  URL"))
    print("  " + "─" * 80)
    for r in rows:
        movie = (r.get("movie") or "")[:39]
        url   = (r.get("url")   or "—")[:60]
        print(f"  {movie:<40}  {cyan(url)}")
    print()


def cmd_file(args):
    """Add all movie names from a text file (one per line)."""
    f = Path(args.file)
    if not f.exists():
        print(red(f"  File not found: {f}"))
        return
    lines = [
        l.strip() for l in f.read_text(encoding="utf-8").splitlines()
        if l.strip() and not l.startswith("#")
    ]
    print(f"  Queueing {len(lines)} movies from {f.name}...")
    site = getattr(args, "site", "auto") or "auto"
    for line in lines:
        args.movie = [line]
        args.site  = site
        cmd_add(args)


def cmd_settings(args):
    """Show or update download settings (GET) or open interactive menu (no args)."""
    if not getattr(args, "key", None):
        # If called from REPL without args → open interactive menu
        settings_menu()
        return
    # CLI: radd settings KEY VALUE
    key = args.key
    val = getattr(args, "value", None)
    if val is None:
        # Just read one setting
        d = _req("GET", "/stream/api/settings")
        if isinstance(d, dict):
            v = d.get(key)
            if v is not None:
                print(f"  {key}: {cyan(str(v))}")
            else:
                print(f"  {yellow('Key not found:')} {key}")
        return
    r = _req("POST", "/stream/api/settings", {key: val})
    if r.get("ok"):
        db.set_setting(key, str(val))
        print(f"  {green('Saved')}: {key} = {val}")
    else:
        print(red(f"  Error: {r.get('error','unknown')}"))


def cmd_status(args):
    """Show server status."""
    import socket
    port = config.get_env_int("PORT", 5000)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(("127.0.0.1", port))
        up = True
    except Exception:
        up = False
    finally:
        s.close()

    state = green("running") if up else red("stopped")
    print(f"  Server: {state}  (port {port})")

    if up:
        d = _req("GET", "/api/status")
        if not d.get("error"):
            stats = d.get("stats", {})
            print(f"  Version: {cyan(d.get('version', '?'))}")
            print(f"  Library: {cyan(str(stats.get('titles','?')))} titles / "
                  f"{cyan(str(stats.get('files','?')))} files")


# ─────────────────────────────────────────────────────────────────────────────
# NEW COMMANDS (backported from v1.0/v2.0 analysis)
# ─────────────────────────────────────────────────────────────────────────────

def cmd_dashboard(args):
    """Live auto-refreshing terminal dashboard — queue + library + bot status."""
    interval = getattr(args, "interval", 3)
    print(f"  {muted('Dashboard — Ctrl+C to exit, refreshing every')} {interval}s")
    try:
        while True:
            os.system("cls" if sys.platform.startswith("win") else "clear")
            print(BANNER)

            # ── Server status ──────────────────────────────────────────
            import socket as _sock
            port = config.get_env_int("PORT", 5000)
            sk   = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
            sk.settimeout(0.3)
            try:
                sk.connect(("127.0.0.1", port))
                up = True
            except Exception:
                up = False
            finally:
                sk.close()
            state = green("● RUNNING") if up else red("● STOPPED")
            print(f"  Server  {state}  (port {port})")

            # ── Library stats ──────────────────────────────────────────
            if up:
                try:
                    st = _req("GET", "/api/status")
                    if not st.get("error"):
                        s = st.get("stats", {})
                        print(f"  Library {cyan(str(s.get('titles','?')))} titles  "
                              f"{cyan(str(s.get('files','?')))} files  "
                              f"v{st.get('version','?')}")
                except Exception:
                    pass

            # ── Queue ──────────────────────────────────────────────────
            print()
            print(bold("  ── Queue ───────────────────────────────────────────"))
            try:
                ql = _req("GET", "/stream/api/queue")
                if isinstance(ql, list) and ql:
                    for r in ql[:15]:
                        jid  = (r.get("job_id") or "")[:10]
                        mov  = (r.get("movie") or "")[:36]
                        s    = r.get("status", "?")
                        pct  = float(r.get("progress") or 0)
                        msg  = (r.get("message") or "")[:30]
                        line = f"  {cyan(jid)}  {mov:<36}  {_fmt_status(s)}  {_bar(pct)}"
                        if msg:
                            line += f"  {muted(msg)}"
                        print(line)
                    if len(ql) > 15:
                        print(f"  {muted(f'… and {len(ql)-15} more')}")
                else:
                    print(f"  {muted('Queue is empty.')}")
            except Exception:
                with db.conn() as c:
                    rows = [dict(r) for r in c.execute(
                        "SELECT job_id, movie, status, progress FROM queue "
                        "WHERE status NOT IN ('done','cancelled') ORDER BY created_at DESC LIMIT 10"
                    ).fetchall()]
                if rows:
                    for r in rows:
                        print(f"  {cyan((r['job_id'] or '')[:10])}  {(r['movie'] or '')[:36]:<36}"
                              f"  {_fmt_status(r['status'])}  {_bar(float(r['progress'] or 0))}")
                else:
                    print(f"  {muted('Queue is empty.')}")

            # ── Bot status ─────────────────────────────────────────────
            print()
            print(bold("  ── Bots ────────────────────────────────────────────"))
            if up:
                try:
                    bd = _req("GET", "/bots/api/whatsapp/qr")
                    wa_ok = bd.get("connected", False)
                    wa_st = green("connected") if wa_ok else yellow("disconnected")
                    print(f"  WhatsApp  {wa_st}")
                    td = _req("GET", "/bots/api/telegram/status")
                    tg_ok = td.get("running", False)
                    tg_st = green("running") if tg_ok else muted("stopped")
                    print(f"  Telegram  {tg_st}")
                except Exception:
                    print(f"  {muted('Bot status unavailable.')}")
            else:
                print(f"  {muted('Server offline.')}")

            print()
            print(muted(f"  [Ctrl+C to exit  •  refreshes every {interval}s]"))
            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n  Dashboard stopped.")


def cmd_export(args):
    """Export the local library catalog to a CSV or JSON file."""
    fmt      = getattr(args, "fmt", "json") or "json"
    out_path = getattr(args, "output", None)

    # Try API first
    url = f"/api/export/catalog?fmt={fmt}"
    if hasattr(args, "type") and args.type:
        url += f"&type={args.type}"

    d = _req("GET", url)

    if isinstance(d, dict) and d.get("ok") and fmt == "json":
        catalog = d.get("catalog", [])
        if out_path is None:
            out_path = "radd_catalog.json"
        import json as _json
        Path(out_path).write_text(_json.dumps(catalog, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"  {green('Exported')} {len(catalog)} records → {cyan(out_path)}")
        return

    # CSV: the API returns raw bytes, so query DB directly for CLI
    if fmt == "csv":
        import csv
        import io
        if out_path is None:
            out_path = "radd_catalog.csv"
        with db.conn() as c:
            rows = [dict(r) for r in c.execute(
                "SELECT t.id, t.title, t.year, t.media_type, t.genres_csv, t.director, t.rating, "
                "       t.tmdb_id, f.filename, f.share_url, f.size_bytes, f.quality, f.source "
                "FROM titles t LEFT JOIN files f ON f.title_id = t.id "
                "ORDER BY t.title COLLATE NOCASE"
            ).fetchall()]
        out = io.StringIO()
        fieldnames = ["id","title","year","media_type","genres_csv","director","rating",
                      "tmdb_id","filename","share_url","size_bytes","quality","source"]
        w = csv.DictWriter(out, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
        Path(out_path).write_text(out.getvalue(), encoding="utf-8")
        print(f"  {green('Exported')} {len(rows)} records → {cyan(out_path)}")
        return

    # Fallback: query DB for JSON
    with db.conn() as c:
        rows = [dict(r) for r in c.execute(
            "SELECT t.id, t.title, t.year, t.media_type, t.genres_csv, t.director, t.rating, "
            "       t.tmdb_id, f.filename, f.share_url, f.size_bytes, f.quality, f.source "
            "FROM titles t LEFT JOIN files f ON f.title_id = t.id "
            "ORDER BY t.title COLLATE NOCASE"
        ).fetchall()]
    if out_path is None:
        out_path = "radd_catalog.json"
    import json as _json
    Path(out_path).write_text(_json.dumps(rows, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"  {green('Exported')} {len(rows)} records → {cyan(out_path)}")


def cmd_broadcast(args):
    """Send a WhatsApp broadcast message to all verified bot users."""
    msg   = getattr(args, "message", None)
    roles = getattr(args, "roles", "verified") or "verified"

    if not msg:
        try:
            msg = input(cyan("  Broadcast message: ")).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Cancelled.")
            return

    if not msg:
        print(red("  No message entered."))
        return

    role_list = [r.strip() for r in roles.split(",") if r.strip()]

    # Try server API first
    d = _req("POST", "/api/whatsapp/broadcast", {"message": msg, "roles": role_list})
    if isinstance(d, dict) and d.get("ok"):
        print(f"  {green('Broadcast sent')}  "
              f"sent={cyan(str(d.get('sent',0)))}  "
              f"failed={red(str(d.get('failed',0))) if d.get('failed') else muted('0')}  "
              f"total={d.get('total',0)}")
        if d.get("errors"):
            for e in d["errors"][:5]:
                print(f"  {red('ERR')} {e.get('jid','')} — {e.get('error','')}")
        return

    # Fallback: write broadcast commands directly to bot-cmd/ IPC directory
    import json as _json
    import uuid as _uuid
    users_path = _ROOT / "bots" / "whatsapp" / "users.json"
    try:
        user_data = _json.loads(users_path.read_text()) if users_path.exists() else {}
    except Exception:
        user_data = {}

    jids: list[str] = []
    for role in role_list:
        for entry in (user_data.get(role) or []):
            jid = entry if "@" in str(entry) else f"{entry}@s.whatsapp.net"
            if jid not in jids:
                jids.append(jid)

    if not jids:
        print(muted(f"  No users found in roles: {', '.join(role_list)}"))
        return

    cmd_dir = _ROOT / "bots" / "whatsapp" / "bot-cmd"
    cmd_dir.mkdir(parents=True, exist_ok=True)
    sent = 0
    for jid in jids:
        try:
            cmd_file = cmd_dir / f"send_{_uuid.uuid4().hex[:8]}.json"
            cmd_file.write_text(_json.dumps({"action": "send", "jid": jid, "message": msg}))
            sent += 1
        except Exception as e:
            print(f"  {red('ERR')} {jid}: {e}")
    print(f"  {green('Broadcast queued')}  "
          f"queued={cyan(str(sent))}  "
          f"total={len(jids)}  "
          f"{muted('(bot will deliver when connected)')}")


def cmd_search_library(args):
    """Search the local library by title, genre, director, or actor."""
    query = getattr(args, "query", None)
    if not query:
        try:
            query = input(cyan("  Search library: ")).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Cancelled.")
            return
    if not query:
        print(red("  No query entered."))
        return

    q = f"%{query}%"
    with db.conn() as c:
        rows = [dict(r) for r in c.execute(
            "SELECT t.title, t.year, t.media_type, t.genres_csv, t.director, t.rating, "
            "       COUNT(f.id) AS file_count "
            "FROM titles t LEFT JOIN files f ON f.title_id = t.id "
            "WHERE t.title LIKE ? OR t.genres_csv LIKE ? OR t.director LIKE ? "
            "      OR t.cast_names LIKE ? "
            "GROUP BY t.id ORDER BY t.title COLLATE NOCASE LIMIT 40",
            (q, q, q, q)
        ).fetchall()]

    if not rows:
        print(muted(f'  No results for "{query}".'))
        return

    print()
    print(bold(f"  {'TITLE':<40} {'YEAR':>4}  {'TYPE':<8}  {'RATING':>6}  FILES"))
    print("  " + "─" * 72)
    for r in rows:
        title  = (r.get("title") or "")[:39]
        year   = str(r.get("year") or "—")
        typ    = (r.get("media_type") or "—")[:8]
        rating = f"{r['rating']:.1f}" if r.get("rating") else "—"
        files  = str(r.get("file_count") or 0)
        print(f"  {title:<40} {year:>4}  {typ:<8}  {rating:>6}  {cyan(files)}")
    print()
    print(muted(f'  {len(rows)} result(s) for "{query}"'))
    print()


def cmd_url(args):
    """Print the best URL to access this instance."""
    port = config.get_env_int("PORT", 5000)
    for key in ("REPLIT_DEV_DOMAIN", "REPLIT_DOMAINS"):
        val = os.environ.get(key, "").split(",")[0].strip()
        if val:
            url = f"https://{val}"
            break
    else:
        url = f"http://localhost:{port}"
    tunnel_url = None
    try:
        from . import tunnel as _tunnel
        tunnel_url = _tunnel.get_url()
    except Exception:
        pass
    print()
    print(bold("  ── Access URLs ─────────────────────────────────────"))
    print(f"  Web UI:   {cyan(url)}")
    if tunnel_url:
        print(f"  Tunnel:   {cyan(tunnel_url)}  (public, shareable)")
    print(f"  CLI:      python radd_hub.py cli")
    print()


def cmd_tunnel(args):
    """Manage the Cloudflare quick tunnel."""
    action = getattr(args, "action", "status") or "status"
    port = config.get_env_int("PORT", 5000)
    try:
        from . import tunnel as _tunnel
    except ImportError as e:
        print(red(f"  Tunnel module unavailable: {e}"))
        return

    if action == "start":
        print(f"  Starting Cloudflare tunnel → localhost:{port} …")
        st = _tunnel.start(port)
        if st.get("url"):
            print(f"  {green('Tunnel URL:')}  {cyan(st['url'])}")
            print(f"  Share this URL to access the web UI from anywhere.")
        else:
            print(f"  Status: {st.get('message', 'unknown')}")
        for line in (st.get("log_tail") or [])[-5:]:
            print(f"    {muted(line)}")

    elif action == "stop":
        st = _tunnel.stop()
        print(f"  {green('Tunnel stopped.')}  {st.get('message', '')}")

    elif action == "url":
        url = _tunnel.get_url()
        if url:
            print(cyan(url))
        else:
            print(yellow("  Tunnel not running.  Start with: tunnel start"))

    else:  # status
        st = _tunnel.status()
        print()
        print(bold("  ── Tunnel status ───────────────────────────────────"))
        if st["running"]:
            print(f"  Status:   {green('running')}  (pid {st.get('pid', '?')})")
            if st.get("url"):
                print(f"  URL:      {cyan(st['url'])}")
        else:
            print(f"  Status:   {muted('stopped')}")
        print(f"  Binary:   {'present' if st.get('binary_present') else red('not downloaded')}")
        if st.get("binary_path"):
            print(f"  Path:     {muted(st['binary_path'])}")
        print()


def cmd_stats(args):
    """Show detailed database statistics."""
    print()
    print(bold("  ── Library ─────────────────────────────────────────"))
    with db.conn() as c:
        t_count = c.execute("SELECT COUNT(*) FROM titles").fetchone()[0]
        f_count = c.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        sz      = c.execute("SELECT COALESCE(SUM(size_bytes),0) FROM files").fetchone()[0]
        q_count = c.execute("SELECT COUNT(*) FROM queue").fetchone()[0]
        q_done  = c.execute("SELECT COUNT(*) FROM queue WHERE status='done'").fetchone()[0]
        q_err   = c.execute("SELECT COUNT(*) FROM queue WHERE status IN ('error','failed')").fetchone()[0]
        q_pend  = c.execute("SELECT COUNT(*) FROM queue WHERE status IN ('queued','downloading','paused')").fetchone()[0]
        by_type = c.execute(
            "SELECT media_type, COUNT(*) n FROM titles GROUP BY media_type ORDER BY n DESC"
        ).fetchall()

    sz_gb = sz / 1073741824
    print(f"  Titles:  {cyan(str(t_count))}")
    print(f"  Files:   {cyan(str(f_count))}")
    print(f"  Size:    {cyan(f'{sz_gb:.2f} GB')}")
    print()
    print(bold("  ── By Type ─────────────────────────────────────────"))
    for row in by_type:
        print(f"  {(row[0] or 'unknown'):<12}  {cyan(str(row[1]))}")
    print()
    print(bold("  ── Queue ───────────────────────────────────────────"))
    print(f"  Total:       {cyan(str(q_count))}")
    print(f"  Done:        {green(str(q_done))}")
    print(f"  Active:      {yellow(str(q_pend))}")
    print(f"  Errors:      {red(str(q_err)) if q_err else muted('0')}")
    print()


# ─────────────────────────────────────────────────────────────────────────────
# Help text
# ─────────────────────────────────────────────────────────────────────────────

_HELP = """
  Radd Hub v3.0 — Stream CLI

  Commands:
    add <movie>              Queue a movie (supports quotes for multi-word)
    add                      Paste movies (Ctrl+D to finish batch)
    add -f file.txt          Batch-queue from text file (one per line)
    queue  / q               List the download queue
    watch  [job_id]          Live spinner view (Ctrl+C to detach)
    log <job_id>             Show per-job log
    results                  Show completed jobs with download links
    cancel <job_id>          Cancel a job
    pause  <job_id>          Pause a job
    resume <job_id>          Resume a paused job
    retry  <job_id>          Re-queue a failed job
    remove <job_id>          Remove a job from the queue
    cancel-all  / ca         Cancel all active jobs
    pause-all   / pa         Pause all jobs
    resume-all  / ra         Resume all jobs
    clear                    Remove all done/cancelled jobs
    settings                 Open interactive settings menu
    settings KEY VALUE       Set a single download setting
    status                   Show server status + library stats
    dashboard  / dash        Live auto-refresh dashboard (all services)
    export [--fmt csv|json]  Export library catalog to file
    broadcast <msg>          Send WhatsApp broadcast to all verified users
    search <query>           Search local library by title/genre/director
    stats                    Show detailed database statistics
    url                      Print the best URL to access this instance
    tunnel [start|stop|url]  Manage Cloudflare quick tunnel for remote access
    help / ?                 Show this help
    exit / quit / q!         Exit CLI
"""


# ─────────────────────────────────────────────────────────────────────────────
# Interactive REPL
# ─────────────────────────────────────────────────────────────────────────────

def _parse_cmd(line: str):
    parts = line.split()
    if not parts:
        return None, []
    return parts[0].lower(), parts[1:]


def repl():
    """Interactive REPL loop with full v2-style UX."""
    global _REPL_COMMANDS
    _REPL_COMMANDS = [
        "add", "queue", "q", "watch", "w", "log", "logs", "results",
        "cancel", "pause", "resume", "retry", "remove",
        "cancel-all", "ca", "pause-all", "pa", "resume-all", "ra",
        "clear", "file", "settings", "config", "s", "status",
        "dashboard", "dash", "export", "broadcast", "search", "stats",
        "url", "tunnel",
        "help", "?", "h", "exit", "quit", "q!",
    ]
    _setup_tab_completion()

    print(BANNER)
    cfg_site    = db.setting("active_site", "auto") or "auto"
    cfg_auto_dl = db.setting("auto_download", "1") or "1"
    auto_label  = green("ON") if cfg_auto_dl in ("1", "true") else muted("OFF")
    print(f"  Mode: {cyan(cfg_site)}  |  Auto-download: {auto_label}")
    print(f"  Type {bold('help')} for commands, {bold('settings')} to configure.\n")

    while True:
        try:
            line = input(cyan("  radd> ")).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Bye!")
            break

        if not line:
            continue

        cmd, rest = _parse_cmd(line)

        if cmd in ("exit", "quit", "q!"):
            print("  Bye!")
            break

        elif cmd in ("help", "?", "h"):
            print(_HELP)

        elif cmd in ("queue", "q"):
            cmd_queue(argparse.Namespace())

        elif cmd in ("watch", "w"):
            jid = rest[0] if rest else None
            secs = 3
            if len(rest) >= 2:
                try: secs = int(rest[1])
                except ValueError: pass
            cmd_watch(argparse.Namespace(job_id=jid, interval=secs))

        elif cmd == "add":
            site = db.setting("active_site", "auto") or "auto"
            if rest and rest[0] == "-f":
                fn = rest[1] if len(rest) > 1 else ""
                cmd_file(argparse.Namespace(file=fn, site=site))
            elif rest:
                movie = " ".join(rest).strip('"\'')
                if movie:
                    cmd_add(argparse.Namespace(movie=[movie], site=site))
                else:
                    print(red("  Usage: add <movie name>"))
            else:
                # Batch Ctrl+D mode (v2-style)
                print(f"  {muted('Enter movie names (one per line, Ctrl+D when done):')}")
                movies = []
                try:
                    while True:
                        ln = input("  > ").strip()
                        if ln:
                            movies.append(ln)
                except (EOFError, KeyboardInterrupt):
                    pass
                if movies:
                    print(f"  Queueing {len(movies)} movies...")
                    for m in movies:
                        cmd_add(argparse.Namespace(movie=[m], site=site))
                else:
                    print(muted("  No movies entered."))

        elif cmd == "cancel" and rest:
            cmd_cancel(argparse.Namespace(job_id=rest[0]))

        elif cmd == "pause" and rest:
            cmd_pause(argparse.Namespace(job_id=rest[0]))

        elif cmd == "resume" and rest:
            cmd_resume(argparse.Namespace(job_id=rest[0]))

        elif cmd == "retry" and rest:
            cmd_retry(argparse.Namespace(job_id=rest[0]))

        elif cmd == "remove" and rest:
            cmd_remove(argparse.Namespace(job_id=rest[0]))

        elif cmd in ("cancel-all", "ca"):
            cmd_cancel_all(argparse.Namespace(yes=False))

        elif cmd in ("pause-all", "pa"):
            cmd_pause_all(argparse.Namespace())

        elif cmd in ("resume-all", "ra"):
            cmd_resume_all(argparse.Namespace())

        elif cmd == "clear":
            cmd_clear(argparse.Namespace())

        elif cmd in ("log", "logs") and rest:
            cmd_log(argparse.Namespace(job_id=rest[0]))

        elif cmd == "results":
            cmd_results(argparse.Namespace())

        elif cmd in ("settings", "config", "s"):
            if len(rest) >= 2:
                cmd_settings(argparse.Namespace(key=rest[0], value=rest[1]))
            elif len(rest) == 1:
                cmd_settings(argparse.Namespace(key=rest[0], value=None))
            else:
                settings_menu()

        elif cmd == "status":
            cmd_status(argparse.Namespace())

        elif cmd == "file" and rest:
            site = db.setting("active_site", "auto") or "auto"
            cmd_file(argparse.Namespace(file=rest[0], site=site))

        elif cmd in ("dashboard", "dash"):
            secs = 3
            if rest:
                try:
                    secs = int(rest[0])
                except ValueError:
                    pass
            cmd_dashboard(argparse.Namespace(interval=secs))

        elif cmd == "export":
            fmt      = "json"
            out_path = None
            typ      = None
            i = 0
            while i < len(rest):
                if rest[i] in ("--fmt", "-f") and i + 1 < len(rest):
                    fmt = rest[i + 1]; i += 2
                elif rest[i] in ("--output", "-o") and i + 1 < len(rest):
                    out_path = rest[i + 1]; i += 2
                elif rest[i] in ("--type", "-t") and i + 1 < len(rest):
                    typ = rest[i + 1]; i += 2
                else:
                    i += 1
            cmd_export(argparse.Namespace(fmt=fmt, output=out_path, type=typ))

        elif cmd == "broadcast":
            msg = " ".join(rest).strip().strip('"\'') if rest else None
            cmd_broadcast(argparse.Namespace(message=msg, roles="verified"))

        elif cmd in ("search", "find"):
            query = " ".join(rest).strip() if rest else None
            cmd_search_library(argparse.Namespace(query=query))

        elif cmd == "stats":
            cmd_stats(argparse.Namespace())

        elif cmd == "url":
            cmd_url(argparse.Namespace())

        elif cmd == "tunnel":
            action = rest[0] if rest else "status"
            cmd_tunnel(argparse.Namespace(action=action))

        elif cmd:
            print(red(f"  Unknown command: {cmd}  (type 'help' for list)"))


# ─────────────────────────────────────────────────────────────────────────────
# CLI entry point (non-interactive)
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="radd-stream", description="Radd Hub Stream CLI")
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("queue",      aliases=["q"],  help="list queue").set_defaults(fn=cmd_queue)

    sa = sub.add_parser("add",   help="queue a movie")
    sa.add_argument("movie", nargs="+")
    sa.add_argument("--site", "-s", default="auto")
    sa.set_defaults(fn=cmd_add)

    sf = sub.add_parser("file",  help="batch-queue from file")
    sf.add_argument("file")
    sf.add_argument("--site", "-s", default="auto")
    sf.set_defaults(fn=cmd_file)

    sc = sub.add_parser("cancel",  help="cancel a job")
    sc.add_argument("job_id")
    sc.set_defaults(fn=cmd_cancel)

    sp = sub.add_parser("pause",   help="pause a job")
    sp.add_argument("job_id")
    sp.set_defaults(fn=cmd_pause)

    sr = sub.add_parser("resume",  help="resume a job")
    sr.add_argument("job_id")
    sr.set_defaults(fn=cmd_resume)

    sry = sub.add_parser("retry",  help="retry a failed job")
    sry.add_argument("job_id")
    sry.set_defaults(fn=cmd_retry)

    srm = sub.add_parser("remove", help="remove a job")
    srm.add_argument("job_id")
    srm.set_defaults(fn=cmd_remove)

    slg = sub.add_parser("log",    help="show job log")
    slg.add_argument("job_id")
    slg.set_defaults(fn=cmd_log)

    sw = sub.add_parser("watch",   help="watch queue live")
    sw.add_argument("job_id", nargs="?")
    sw.add_argument("-n", dest="interval", type=int, default=3)
    sw.set_defaults(fn=cmd_watch)

    sca = sub.add_parser("cancel-all", help="cancel all jobs")
    sca.add_argument("--yes", "-y", action="store_true")
    sca.set_defaults(fn=cmd_cancel_all)

    sub.add_parser("pause-all",  help="pause all jobs").set_defaults(fn=cmd_pause_all)
    sub.add_parser("resume-all", help="resume all jobs").set_defaults(fn=cmd_resume_all)
    sub.add_parser("clear",      help="remove done/cancelled jobs").set_defaults(fn=cmd_clear)
    sub.add_parser("results",    help="show completed downloads").set_defaults(fn=cmd_results)
    sub.add_parser("status",     help="show server status").set_defaults(fn=cmd_status)

    sst = sub.add_parser("settings", help="show/set download settings or open menu")
    sst.add_argument("key",   nargs="?")
    sst.add_argument("value", nargs="?")
    sst.set_defaults(fn=cmd_settings)

    # ── New commands ──────────────────────────────────────────────────────────

    sdash = sub.add_parser("dashboard", aliases=["dash"],
                           help="live auto-refresh dashboard")
    sdash.add_argument("-n", dest="interval", type=int, default=3)
    sdash.set_defaults(fn=cmd_dashboard)

    sexp = sub.add_parser("export", help="export library catalog to CSV/JSON")
    sexp.add_argument("--fmt",    "-f", default="json", choices=["json", "csv"],
                      help="output format (default: json)")
    sexp.add_argument("--output", "-o", default=None,
                      help="output file path (default: radd_catalog.json/csv)")
    sexp.add_argument("--type",   "-t", default=None,
                      help="filter by type: movie / series / anime")
    sexp.set_defaults(fn=cmd_export)

    sbcast = sub.add_parser("broadcast", help="send WA broadcast to all verified users")
    sbcast.add_argument("message", nargs="?", help="message text")
    sbcast.add_argument("--roles", "-r", default="verified",
                        help="comma-separated roles (default: verified)")
    sbcast.set_defaults(fn=cmd_broadcast)

    ssearch = sub.add_parser("search", help="search local library")
    ssearch.add_argument("query", nargs="?", help="search query")
    ssearch.set_defaults(fn=cmd_search_library)

    sub.add_parser("stats", help="show DB statistics").set_defaults(fn=cmd_stats)

    sub.add_parser("url",    help="print the best access URL").set_defaults(fn=cmd_url)

    stun = sub.add_parser("tunnel", help="manage Cloudflare quick tunnel")
    stun.add_argument("action", nargs="?", default="status",
                      choices=["status", "start", "stop", "url"],
                      help="tunnel action (default: status)")
    stun.set_defaults(fn=cmd_tunnel)

    return p


def main(argv: list[str] | None = None) -> int:
    p = build_parser()
    args = p.parse_args(argv)

    if not args.cmd:
        repl()
        return 0

    fn = getattr(args, "fn", None)
    if fn:
        return fn(args) or 0
    p.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
