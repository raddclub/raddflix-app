from __future__ import annotations
import os
import sys
import glob
import shutil
import threading
import time
import re as _re
import logging
from pathlib import Path

# Bootstrap must run BEFORE _find_chromium() probes any binary so that
# LD_LIBRARY_PATH contains the Nix glib / glibc paths needed by the
# playwright headless-shell (otherwise probe fails even though the binary works).
try:
    from . import _bootstrap  # noqa: F401  sets LD_LIBRARY_PATH
except Exception:
    pass

from . import search_cache, turbo_cache

_BASE = os.path.dirname(os.path.abspath(__file__))
_CHROMIUM_CACHE_FILE = Path.home() / ".cache" / "radd-hub" / "chromium_path.txt"

from .query_parser import (
    slug_extras as _slug_extras,
    significant_words as _sig_words,
    slug_contains as _slug_contains,
)

_REL_STOPWORDS = {
    "the", "a", "an", "of", "and", "or", "in", "on", "at", "to",
    "for", "is", "it", "with", "from", "by", "as",
}

# ---- Thread-Isolated Browser Engine (v8.0) --------------------------------- #

_tls = threading.local()

class ThreadIsolatedBrowser:
    def __init__(self):
        self.pw = None
        self.browser = None
        self.context = None

    def start(self):
        from playwright.sync_api import sync_playwright
        import asyncio
        try:
            # Prevent "sync API inside asyncio loop" error by ensuring no loop is active in this thread
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    # If a loop is already running, we can't easily use the sync API here.
                    # However, in a threaded environment, we should try to create a new one or clear it.
                    pass
                else:
                    asyncio.set_event_loop(None)
            except Exception:
                pass

            # Absolute Isolation: Own PW instance for this thread
            self.pw = sync_playwright().start()
            
            # Resolve Chromium executable: try multiple sources in priority order
            def _find_chromium_exe() -> str:
                # 1. Already set and valid
                already = os.environ.get("RADD_CHROMIUM_EXECUTABLE", "")
                if already and os.path.exists(already):
                    return already
                # 2. Replit-provided Playwright Chromium (Nix store)
                replit_pw = os.environ.get("REPLIT_PLAYWRIGHT_CHROMIUM_EXECUTABLE", "")
                if replit_pw and os.path.exists(replit_pw):
                    return replit_pw
                # 3. Local browsers dir — any chromium_headless_shell-* version
                browsers_base = Path(_BASE) / ".." / "local" / "browsers"
                for pattern in [
                    "chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell",
                    "chromium-*/chrome-linux/chrome",
                ]:
                    matches = sorted(glob.glob(str(browsers_base / pattern)))
                    if matches:
                        return matches[-1]  # newest version
                # 4. System chromium
                for candidate in ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"]:
                    if os.path.exists(candidate):
                        return candidate
                return ""

            exe = _find_chromium_exe()
            if exe:
                os.environ["RADD_CHROMIUM_EXECUTABLE"] = exe
                # Point PLAYWRIGHT_BROWSERS_PATH at local store if exe is there
                local_browsers = str(Path(_BASE) / ".." / "local" / "browsers")
                if local_browsers in exe:
                    os.environ["PLAYWRIGHT_BROWSERS_PATH"] = local_browsers

            launch_kwargs = {"headless": True}
            if exe and os.path.exists(exe):
                launch_kwargs["executable_path"] = exe
            
            self.browser = self.pw.chromium.launch(**launch_kwargs)
            self.context = self.browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            )
            return True
        except Exception as e:
            logging.getLogger("hub.scraper").error(f"scraper: Thread-Isolated Browser init failed: {e}")
            self.stop()
            return False

    def stop(self):
        try:
            if self.context: self.context.close()
            if self.browser: self.browser.close()
            if self.pw: self.pw.stop()
        except Exception:
            pass
        self.context = self.browser = self.pw = None

def get_warm_page():
    """Return a thread-isolated page from a private browser instance."""
    mgr = getattr(_tls, "mgr", None)
    if not mgr:
        mgr = ThreadIsolatedBrowser()
        if mgr.start():
            _tls.mgr = mgr
        else:
            return None
    try:
        return mgr.context.new_page()
    except Exception:
        # Restart if dead
        mgr.stop()
        if mgr.start():
            return mgr.context.new_page()
    return None

def close_warm_browser():
    """No-op as browser is thread-managed."""
    pass


def _validate_post_relevance(
    query: str,
    post_url: str,
    config: dict,
    enriched_meta: dict | None = None,
) -> tuple[bool, str]:
    cfg = (config or {}).get("match_validation", {}) or {}
    min_ratio = float(cfg.get("min_significant_word_ratio", 0.7))
    slug = _re.sub(r"^https?://[^/]+", "", post_url or "").strip("/").lower()
    candidates: list[str] = [query or ""]
    if enriched_meta:
        for k in ("title", "original_title"):
            v = enriched_meta.get(k)
            if v: candidates.append(str(v))
    
    soft_keywords = {"season", "series", "s01", "s02", "s03", "s04", "s05", "s06", "s07", "s08", "s09", "s10", "hindi", "dual", "multi", "audio", "dubbed"}
    best_score = -1.0
    best_sig = []
    best_msg = "no match"

    for cand in candidates:
        sig = _sig_words(cand)
        if not sig: continue
        essential_sig = [w for w in sig if w.lower() not in soft_keywords]
        if not essential_sig: essential_sig = sig
        
        # ── Strict Digit Veto ──
        # If the query has a digit (1-9) and the slug has a different one, reject.
        q_digits = {w for w in essential_sig if w.isdigit() and len(w) == 1}
        s_words = set(_re.findall(r"[a-z0-9]+", slug.lower()))
        s_digits = {w for w in s_words if w.isdigit() and len(w) == 1}
        if q_digits and s_digits:
            if not (q_digits & s_digits):
                continue # DIFFERENT numbers found - skip this candidate
        
        # ── Strict Year Veto ──
        q_year = _re.search(r"(19|20)\d{2}", cand)
        s_year = _re.search(r"(19|20)\d{2}", slug)
        if q_year and s_year:
            if q_year.group(0) != s_year.group(0):
                continue # DIFFERENT years found - skip
        elif q_year and not s_year:
            # If query has year but slug doesn't, it might be a generic post (e.g. series)
            # but for movies it's a slight penalty in ranking, not necessarily a veto here.
            pass

        matched = [w for w in essential_sig if _slug_contains(w, slug)]
        ratio = len(matched) / len(essential_sig)
        
        # Leniency: if we matched at least 1 word or 50% of the title, 
        # and those matches are not just "soft" keywords, it's probably good.
        if ratio > best_score:
            best_score = ratio
            best_sig = essential_sig
            best_msg = f"{len(matched)}/{len(essential_sig)} sig words match"
            
        # Hard override: if ratio is decent (>= 50%) and we have at least 1 significant match
        if ratio >= 0.5 and len(matched) >= 1:
            return True, best_msg
        
        # Super-leniency for short titles (1-2 words)
        if len(essential_sig) <= 2 and len(matched) >= 1:
            return True, best_msg

    if best_score < min_ratio:
        return False, best_msg
    return True, best_msg

def _set_progress(job: dict, label: str):
    from .downloader import _update_db, _active_jobs
    _STAGE_PROG = {
        "searching": 10, "post": 25, "getting_link": 40, "bridge": 55, "generating": 70,
        "ai": 5, "downloading": 90, "done": 100,
    }
    _STAGE_LABEL = {
        "searching": "Searching sites…",
        "post": "Visiting movie post…",
        "getting_link": "Analyzing links…",
        "bridge": "Navigating bridge…",
        "generating": "Generating final link…",
        "ai": "AI analyzing…",
        "downloading": "Downloading…",
        "done": "Done",
    }
    job["status"] = "done" if label == "done" else "processing"
    job["progress"] = _STAGE_PROG.get(label, 0)
    job["stage_label"] = _STAGE_LABEL.get(label, label)
    job["last_activity"] = time.time()
    
    # Persist to DB only if job is known to downloader (prevents race on startup)
    if job["job_id"] in _active_jobs:
        _update_db(job["job_id"], status=job["status"], progress=job["progress"], message=job["stage_label"])
    else:
        # Fallback for early updates
        try:
            from . import db as _db_mod
            with _db_mod.conn() as _c:
                _c.execute("UPDATE queue SET status=?, progress=?, message=?, updated_at=? WHERE job_id=?",
                          (job["status"], job["progress"], job["stage_label"], int(time.time()), job["job_id"]))
        except: pass

def _run_single_site(page, job: dict, config: dict, plugin, log_fn,
                     extra_stop: threading.Event | None = None) -> str:
    pause_ev: threading.Event  = job["pause_event"]
    site = plugin.name
    log_fn(f"[{site}] Getting download link…")
    _set_progress(job, "getting_link")

    def check_control():
        if job["cancel_event"].is_set(): raise InterruptedError("Job cancelled")
        if extra_stop and extra_stop.is_set(): raise InterruptedError("Stopped")
        pause_ev.wait()

    # 1. Search
    movie_url = job.get("movie_url")
    if not movie_url:
        _set_progress(job, "searching")
        # SitePlugin.search(self, page, movie_name, config, check_control, log_fn)
        movie_url = plugin.search(page, job["movie_clean"], config, check_control=check_control, log_fn=log_fn)
        
        # ── VALIDATION: Ensure the search result is actually relevant ────────
        ok, msg = _validate_post_relevance(job["movie_clean"], movie_url, config)
        if not ok:
            log_fn(f"[{site}] Validation FAILED: {msg}")
            log_fn(f"[{site}] Found URL looks irrelevant: {movie_url}")
            raise RuntimeError(f"[{site}] Search result failed relevance check: {msg}")
            
        job["movie_url"] = movie_url
        log_fn(f"[{site}] Found (verified): {movie_url[:60]}...")

    # 2. Extract Bridge Link
    _set_progress(job, "post")
    log_fn(f"[{site}] Analyzing post page…")
    # SitePlugin.get_download_link(self, page, movie_url, config, check_control, log_fn)
    bridge_url = plugin.get_download_link(page, movie_url, config, check_control=check_control, log_fn=log_fn)
    
    # 3. Resolve Final Direct Link
    _set_progress(job, "bridge")
    log_fn(f"[{site}] Resolving bridge/cdn mirrors…")
    
    final_urls = []
    # Some plugins return multiple links joined by || (e.g. episodes)
    for inter in bridge_url.split("||"):
        check_control()
        # SitePlugin.get_bridge_link(self, page, bridge_url, config, check_control, log_fn)
        cdn_target = plugin.get_bridge_link(page, inter, config, check_control=check_control, log_fn=log_fn)
        
        # SitePlugin.get_final_link(self, page, cdn_url, config, check_control, log_fn)
        final = plugin.get_final_link(page, cdn_target, config, check_control=check_control, log_fn=log_fn)
        if final:
            final_urls.append(final)

    if not final_urls:
        raise RuntimeError(f"[{site}] Failed to generate final links.")
        
    final_str = "||".join(final_urls)
    log_fn(f"[{site}] Success: {len(final_urls)} link(s) ready.")
    return final_str

_BAD_FINAL_HOST_MARKERS = ("/cdn-cgi/", "challenges.cloudflare.com", "cf-chl", "__cf_chl_")
def _is_bad_final_url(url: str) -> bool:
    u = (url or "").lower()
    return any(s in u for s in _BAD_FINAL_HOST_MARKERS)

def _setup_page_fast_load(page):
    def _intercept(route):
        if route.request.resource_type in ["image", "font", "media"]: return route.abort()
        if any(b in route.request.url for b in ["google-analytics", "doubleclick", "adnxs", "facebook"]): return route.abort()
        return route.continue_()
    try: page.route("**/*", _intercept)
    except Exception: pass

def run_job(job: dict, config: dict, plugin, log_fn):
    page = None
    try:
        # Lazy init Playwright if the plugin is NOT VegaMovies (Pure HTTP)
        if plugin.name.lower() != "vegamovies":
            page = get_warm_page()
            if page:
                _setup_page_fast_load(page)
            else:
                log_fn("Warning: Playwright browser could not be started. Scraper may fail.")

        final_url = _run_single_site(page, job, config, plugin, log_fn)
        job["result_url"] = final_url
        job["site_used"] = plugin.name
        log_fn(f"LINK READY ✓ → {final_url[:60]}...")
        if config.get("auto_download") and not job["cancel_event"].is_set():
            _do_download(job, config, final_url, log_fn)
        
        # If we reached here without exception and it's not already done, mark as done
        if job["status"] != "done":
            _set_progress(job, "done")
    except Exception as e:
        # DO NOT overwrite 'done' status with error (prevents race/success masking)
        if job.get("status") != "done":
            job["status"] = "error"
            job["error"] = str(e)
            log_fn(f"ERROR: {e}")
        else:
            log_fn(f"Note: Ignoring post-success error: {e}")
    finally:
        if page:
            try: page.close()
            except: pass

# Per-site timeout in seconds (how long to try one site before moving on)
_PER_SITE_TIMEOUT = int(__import__("os").environ.get("RADD_SITE_TIMEOUT", "300"))


def run_job_ai(job: dict, config: dict, log_fn):
    """Smart multi-site downloader with per-site timeout and full fallback.

    Improvements over v3.0:
    - Tries EVERY real site (not just AI-prioritized subset) before giving up.
    - Per-site timeout (RADD_SITE_TIMEOUT, default 300s / 5 min).  If a site
      hangs on CDN resolution or Playwright, we move on instead of blocking.
    - Clears stale per-site state (movie_url, result_url) between attempts so
      a bad URL from site A does not poison site B.
    - Non-existent site names (e.g. PikaHD, GokuHD) are silently skipped.
    - Accumulates per-site errors and surfaces them all in the final error msg.
    - Touch the hang-watchdog progress timer on each site transition.
    """
    from . import sites as site_registry
    _set_progress(job, "ai")

    # Build ordered site list from AI router; fall back to all real sites
    try:
        from .ai_router import get_prioritised_sites
        site_names = get_prioritised_sites(job["movie"])
    except Exception:
        try:
            from .ai_router import get_all_sites
            site_names = get_all_sites()
        except Exception:
            site_names = [p.name for p in site_registry.get_plugins_in_order([])]

    # Deduplicate while keeping priority order
    seen: set[str] = set()
    ordered: list[str] = []
    for n in site_names:
        if n not in seen:
            seen.add(n)
            ordered.append(n)

    errors: dict[str, str] = {}

    for name in ordered:
        if job["cancel_event"].is_set():
            break

        # Load plugin — skip silently if it does not exist
        try:
            plugin = site_registry.get_plugin(name)
        except Exception as e:
            log_fn(f"[Auto] Skipping {name}: {e}")
            continue

        # Clear per-site artifacts so the next plugin starts fresh
        for key in ("movie_url", "result_url", "site_used", "error"):
            job.pop(key, None)

        log_fn(f"[Auto] Trying {name} ({ordered.index(name)+1}/{len(ordered)})…")
        job["status"] = "processing"

        # Touch the hang watchdog so this transition counts as "progress"
        try:
            from .downloader import _touch_progress
            _touch_progress(job["job_id"])
        except Exception:
            pass

        # Run with a per-site hard timeout using a daemon thread
        site_exc: list[Exception | None] = [None]
        finished = threading.Event()

        def _try(p=plugin, exc_box=site_exc, done=finished):
            try:
                run_job(job, config, p, log_fn)
            except Exception as e:
                exc_box[0] = e
            finally:
                done.set()

        t = threading.Thread(target=_try, daemon=True, name=f"site-{name}-{job['job_id'][:6]}")
        t.start()
        finished.wait(timeout=_PER_SITE_TIMEOUT)

        if job.get("status") == "done":
            log_fn(f"[Auto] ✓ {name} succeeded!")
            return

        if not finished.is_set():
            # Timed out — thread is still running in background
            err_msg = f"timed out after {_PER_SITE_TIMEOUT}s"
            log_fn(f"[{name}] {err_msg} — moving to next site")
        else:
            exc = site_exc[0]
            err_msg = str(exc) if exc else (job.get("error") or "unknown error")
            log_fn(f"[{name}] Failed: {err_msg}")

        errors[name] = err_msg
        # Reset status so the next site attempt isn't short-circuited
        job["status"] = "processing"
        job.pop("error", None)

    if job.get("status") != "done":
        summary = "; ".join(f"{k}: {v[:80]}" for k, v in errors.items()) or "no sites available"
        job["status"] = "error"
        job["error"] = f"All sites failed — {summary}"
        log_fn(f"[Auto] All {len(errors)} site(s) exhausted. {job['error']}")

def _do_download(job: dict, config: dict, url: str, log_fn):
    from . import downloader, db as _db
    _set_progress(job, "downloading")
    
    import json as _json
    from . import config as _hub_config  # config param shadows module; use alias
    watch_dir = Path(_db.setting("upload_watch_root") or str(_hub_config.MEDIA_DIR))
    dest_dir = Path(config.get("download_dir") or downloader.DOWNLOAD_DIR).expanduser().resolve()
    
    # --- Parse Payload ---
    items = []
    if url.startswith("PAYLOAD:"):
        try:
            items = _json.loads(url[8:])
        except Exception as e:
            log_fn(f"Failed to parse payload: {e}")
            items = [{"url": u, "metadata": {}} for u in url[8:].split("||")]
    else:
        items = [{"url": u, "metadata": {}} for u in url.split("||")]
    
    saved_paths = []
    total_parts = len(items)
    
    for idx, item in enumerate(items):
        if job["cancel_event"].is_set(): break
        u = item["url"]
        meta = item.get("metadata", {})
        
        try:
            part_num = idx + 1
            
            # --- Resume-Batch Logic ---
            if meta.get("show") and meta.get("season") is not None and meta.get("episode") is not None:
                if _db.is_episode_in_library(meta["show"], meta["season"], meta["episode"]):
                    log_fn(f"Resume-Batch: [S{meta['season']:02d}E{meta['episode']:02d}] already in library - skipping.")
                    continue

            log_fn(f"Downloading part {part_num}/{total_parts}...")
            
            # --- Global Progress Proxy ---
            def progress_proxy(pct):
                # Map local part percentage to global job percentage
                global_pct = ((part_num - 1) * 100 + pct) / total_parts
                job["progress"] = global_pct

            # We use a sub-dict for job to intercept progress updates
            job_proxy = job.copy()
            # Note: updating job_proxy["progress"] won't trigger the real progress reporting
            # but downloader.download_file writes to job['progress'].
            # So we create a wrapper object that handles the math.
            class JobProgressWrapper(dict):
                def __setitem__(self, key, value):
                    if key == "progress":
                        try:
                            global_pct = ((part_num - 1) * 100 + float(value)) / total_parts
                            job["progress"] = global_pct
                        except: pass
                    super().__setitem__(key, value)

            job_wrapper = JobProgressWrapper(job)
            
            # Use the movie post URL as referer for better compatibility with CDNs
            referer = job.get("movie_url")
            saved = downloader.download_file(u, dest_dir, job_wrapper, log_fn, referer=referer)
            
            if saved.suffix.lower() == ".zip":
                log_fn(f"ZIP detected! Automatically extracting: {saved.name}")
                folder = downloader.extract_zip(saved, log_fn)
                for video in folder.rglob("*"):
                    if video.is_file() and video.suffix.lower() in downloader._VIDEO_EXTENSIONS:
                        parts = downloader.split_large_file(video, log_fn)
                        for p in parts:
                            target = watch_dir / p.name
                            if not target.exists():
                                log_fn(f"Auto-Extraction: Moving {p.name} to uploader...")
                                p.rename(target)
                                
                                # --- Immediate Claim (Anti-Watcher Race) ---
                                try:
                                    from . import uploader as _upl
                                    fp = _upl._fingerprint_file(target)
                                    _db.upsert_file({
                                        "fingerprint": f"upl:{fp}",
                                        "local_path": str(target),
                                        "filename": target.name,
                                        "is_ready": -2, # Claimed
                                        "source": "upload",
                                        "uploaded_at": int(time.time()),
                                    })
                                except Exception as _claim_err:
                                    log_fn(f"Warning: could not pre-claim file: {_claim_err}")
                                    
                                saved_paths.append(str(target))
                try: 
                    import shutil
                    shutil.rmtree(folder)
                except: pass
            else:
                parts = downloader.split_large_file(saved, log_fn)
                for p in parts:
                    target = watch_dir / p.name
                    if not target.exists():
                        log_fn(f"Auto-Download: Moving {p.name} to uploader...")
                        p.rename(target)
                        
                        # --- Immediate Claim (Anti-Watcher Race) ---
                        try:
                            from . import uploader as _upl
                            fp = _upl._fingerprint_file(target)
                            _db.upsert_file({
                                "fingerprint": f"upl:{fp}",
                                "local_path": str(target),
                                "filename": target.name,
                                "is_ready": -2, # Claimed
                                "source": "upload",
                                "uploaded_at": int(time.time()),
                            })
                        except Exception as _claim_err:
                            log_fn(f"Warning: could not pre-claim file: {_claim_err}")
                    else:
                        log_fn(f"Auto-Download: {p.name} already exists in uploader. Skipping move.")
                        
                    saved_paths.append(str(target))
        except Exception as e:
            log_fn(f"DL Error: {e}")
            if total_parts == 1: raise
            
    if saved_paths or total_parts == 0:
        job["download_path"] = "||".join(saved_paths)
        _set_progress(job, "done")
        log_fn(f"AUTOMATIC WORKFLOW COMPLETE: {len(saved_paths)} file(s) sent to uploader.")
    else:
        # Check if we skipped everything because it's in library
        all_skipped = True
        for item in items:
            m = item.get("metadata", {})
            if not m.get("show") or not _db.is_episode_in_library(m["show"], m["season"], m["episode"]):
                all_skipped = False
                break
        if all_skipped:
             _set_progress(job, "done")
             log_fn("All parts already in library. Job complete.")
        else:
             raise RuntimeError("No files were successfully downloaded or processed.")

# ---- Browser Discovery (Used by browser_installer.py) ---------------------- #

_CHROMIUM_PATH = None
_FIREFOX_PATH = None
_CHROMIUM_PW_MANAGED = False

def _find_chromium():
    try:
        from . import installer
        return installer.find_chromium_executable()
    except ImportError:
        return None, False

def _find_firefox():
    return None, False
