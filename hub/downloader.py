"""Downloader — queue worker with in-memory job control (cancel/pause/resume).

v3.0 additions over v2.0:
  - query_parser(): extract year-hint and language-hint from user query
  - stage_label tracking: each job sets a human-readable stage in its message
  - enriched sc_config: year_hint and lang_hint flow into the scraper config
  - download_file(): speed/ETA logging via both aria2 and urllib backends
  - split_large_file(): split files >1.98 GB into 2 equal parts before upload
  - zip_season_folder(): zip all episode video files in a season folder
"""
from __future__ import annotations
import os
import re
import time
import shutil
import threading
import urllib.request
import urllib.parse
import logging
import zipfile
from pathlib import Path

from . import db, config
from .query_parser import parse as parse_movie_query

# Lazy import — avoids circular dependency at module load time
_metadata_lookup = None

def _get_metadata_lookup():
    """Return metadata_lookup module (imported on first use)."""
    global _metadata_lookup
    if _metadata_lookup is None:
        from . import metadata_lookup as _ml
        _metadata_lookup = _ml
    return _metadata_lookup

log = logging.getLogger("hub.downloader")
...
# ─────────────────────────────────────────────────────────────────────────────
# File post-processing helpers
# ─────────────────────────────────────────────────────────────────────────────

SPLIT_THRESHOLD_BYTES = int(1.98 * 1024 ** 3)  # 1.98 GB

_VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv",
    ".webm", ".ts", ".m4v", ".m2ts", ".3gp",
}


def split_large_file(file_path: Path, log_fn=None) -> list[Path]:
    """Split a single file >1.98 GB into N parts, each ≤ 1.98 GB.

    Returns a list of Path objects for the parts. If the file is ≤ 1.98 GB
    the original path is returned as a single-element list (no copy made).
    The original file is deleted after a successful split.
    """
    def _log(m):
        if log_fn: log_fn(m)
        else: log.info(m)

    size = file_path.stat().st_size
    if size <= SPLIT_THRESHOLD_BYTES:
        return [file_path]

    stem, sfx = file_path.stem, file_path.suffix
    chunk     = 8 * 1024 * 1024   # 8 MB buffer
    num_parts = (size + SPLIT_THRESHOLD_BYTES - 1) // SPLIT_THRESHOLD_BYTES
    
    _log(f"File is {size / 1024**3:.2f} GB > 1.98 GB — splitting into {num_parts} parts…")

    parts: list[Path] = []
    with open(file_path, "rb") as src:
        for i in range(1, num_parts + 1):
            part_path = file_path.parent / f"{stem}.Part{i}{sfx}"
            written = 0
            with open(part_path, "wb") as dst:
                while written < SPLIT_THRESHOLD_BYTES:
                    to_read = min(chunk, SPLIT_THRESHOLD_BYTES - written)
                    data = src.read(to_read)
                    if not data:
                        break
                    dst.write(data)
                    written += len(data)
            
            if written > 0:
                parts.append(part_path)
                _log(f"  - Created Part {i}: {part_path.stat().st_size / 1024**2:.0f} MB")
            else:
                # Should not happen given num_parts calculation
                break

    _log(f"Split complete: {len(parts)} parts created.")
    try:
        file_path.unlink()
    except Exception as e:
        _log(f"Warning: could not remove original after split: {e}")

    return parts


def zip_season_folder(folder_path: Path, job_name: str = "", log_fn=None) -> Path | None:
    """[DEPRECATED] Standard packaging is now folder-based, not ZIP-based.
    Kept as a stub to avoid breaking old callers.
    """
    return None


def extract_zip(zip_path: Path, log_fn=None) -> Path:
    """Extract a ZIP file to a sibling folder and return the folder path."""
    def _log(m):
        if log_fn: log_fn(m)
        else: log.info(m)

    dest = zip_path.parent / zip_path.stem
    dest.mkdir(parents=True, exist_ok=True)
    _log(f"Extracting {zip_path.name} to folder…")
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Phase 4: ZIP Integrity Check
            bad_file = zf.testzip()
            if bad_file:
                raise zipfile.BadZipFile(f"CRC check failed for {bad_file}")
            zf.extractall(dest)
        _log(f"Extraction complete: {dest.name}")
        try:
            zip_path.unlink()
        except:
            pass
        return dest
    except Exception as e:
        _log(f"ZIP Extraction failed: {e}")
        return zip_path


# ─────────────────────────────────────────────────────────────────────────────
# In-memory job registry  (job_id → job_obj)
# ─────────────────────────────────────────────────────────────────────────────

_active_jobs: dict[str, dict] = {}
_active_lock = threading.Lock()

def _max_parallel() -> int:
    try:
        val = db.setting("max_parallel")
        if val:
            return int(val)
    except Exception:
        pass
    return config.get_env_int("RADD_MAX_PARALLEL", 2)


def _register_job(job_obj: dict) -> None:
    with _active_lock:
        _active_jobs[job_obj["job_id"]] = job_obj


def _unregister_job(job_id: str) -> None:
    with _active_lock:
        _active_jobs.pop(job_id, None)


def get_active_job(job_id: str) -> dict | None:
    with _active_lock:
        return _active_jobs.get(job_id)


def active_job_ids() -> list[str]:
    with _active_lock:
        return list(_active_jobs)


# ─────────────────────────────────────────────────────────────────────────────
# Queue control API
# ─────────────────────────────────────────────────────────────────────────────

def cancel_job(job_id: str) -> bool:
    """Cancel a running or queued job."""
    job = get_active_job(job_id)
    if job:
        job["cancel_event"].set()
        job["pause_event"].set()  # Unblock any pause wait
        _update_db(job_id, status="cancelled", message="Cancelled by user")
        return True
    # Job not in memory — if queued, just mark cancelled in DB
    with db.conn() as c:
        row = c.execute("SELECT status FROM queue WHERE job_id=?", (job_id,)).fetchone()
        if row and row["status"] in ("queued",):
            c.execute("UPDATE queue SET status='cancelled', message='Cancelled by user', "
                      "updated_at=? WHERE job_id=?", (int(time.time()), job_id))
            return True
    return False


def pause_job(job_id: str) -> bool:
    """Pause a running job."""
    job = get_active_job(job_id)
    if job:
        job["pause_event"].clear()
        job["status"] = "paused"
        _update_db(job_id, status="paused", message="Paused by user")
        return True
    return False


def resume_job(job_id: str) -> bool:
    """Resume a paused job."""
    job = get_active_job(job_id)
    if job:
        job["pause_event"].set()
        job["status"] = "processing"
        _update_db(job_id, status="processing", message="Resumed")
        return True
    # If job is 'paused' in DB but not in memory, re-queue it
    with db.conn() as c:
        row = c.execute("SELECT status FROM queue WHERE job_id=?", (job_id,)).fetchone()
        if row and row["status"] == "paused":
            c.execute("UPDATE queue SET status='queued', message='Resumed', "
                      "updated_at=? WHERE job_id=?", (int(time.time()), job_id))
            return True
    return False


def retry_job(job_id: str) -> bool:
    """Re-queue a failed/cancelled/error job."""
    cancel_job(job_id)
    with db.conn() as c:
        row = c.execute("SELECT status FROM queue WHERE job_id=?", (job_id,)).fetchone()
        if row and row["status"] in ("error", "cancelled", "failed", "done"):
            c.execute(
                "UPDATE queue SET status='queued', progress=0, message='Retrying', "
                "log=NULL, updated_at=? WHERE job_id=?",
                (int(time.time()), job_id)
            )
            return True
    return False


def remove_job(job_id: str) -> bool:
    """Cancel and delete a job from the queue."""
    cancel_job(job_id)
    with db.conn() as c:
        c.execute("DELETE FROM queue WHERE job_id=?", (job_id,))
    return True


def cancel_all_jobs() -> int:
    """Cancel all active and queued jobs. Returns count."""
    count = 0
    with _active_lock:
        for jid, job in list(_active_jobs.items()):
            job["cancel_event"].set()
            job["pause_event"].set()
            count += 1
    with db.conn() as c:
        n = c.execute(
            "UPDATE queue SET status='cancelled', message='Cancelled by user', "
            "updated_at=? WHERE status IN ('queued','processing','paused')",
            (int(time.time()),)
        ).rowcount
        count = max(count, n)
    return count


def remove_cancelled_jobs() -> int:
    """Remove cancelled/error/failed jobs from the queue."""
    with _active_lock:
        for jid, job in list(_active_jobs.items()):
            if job.get("status") in ("cancelled", "error", "failed"):
                job["cancel_event"].set()
                job["pause_event"].set()
    with db.conn() as c:
        return c.execute(
            "DELETE FROM queue WHERE status IN ('cancelled','error','failed')"
        ).rowcount


def pause_all_jobs() -> int:
    count = 0
    with _active_lock:
        for jid, job in list(_active_jobs.items()):
            job["pause_event"].clear()
            job["status"] = "paused"
            count += 1
    with db.conn() as c:
        c.execute(
            "UPDATE queue SET status='paused', updated_at=? WHERE status='processing'",
            (int(time.time()),)
        )
        c.execute(
            "UPDATE queue SET status='paused', updated_at=? WHERE status='queued'",
            (int(time.time()),)
        )
    return count


def resume_all_jobs() -> int:
    count = 0
    with _active_lock:
        for jid, job in list(_active_jobs.items()):
            job["pause_event"].set()
            job["status"] = "processing"
            count += 1
    with db.conn() as c:
        c.execute(
            "UPDATE queue SET status='queued', updated_at=? WHERE status='paused'",
            (int(time.time()),)
        )
    return count


def get_results() -> list[dict]:
    """Return all completed jobs with download URLs."""
    with db.conn() as c:
        rows = c.execute(
            "SELECT job_id, movie, url, message, updated_at FROM queue "
            "WHERE status='done' ORDER BY updated_at DESC LIMIT 200"
        ).fetchall()
    return [dict(r) for r in rows]


def get_job_log(job_id: str) -> str:
    """Return the per-job log text."""
    with db.conn() as c:
        row = c.execute("SELECT log FROM queue WHERE job_id=?", (job_id,)).fetchone()
    return (row["log"] or "") if row else ""


# ─────────────────────────────────────────────────────────────────────────────
# Queue Worker
# ─────────────────────────────────────────────────────────────────────────────

def _update_db(job_id: str, **fields) -> None:
    fields["updated_at"] = int(time.time())
    sets = ", ".join(f"{k}=?" for k in fields)
    vals = list(fields.values()) + [job_id]
    try:
        with db.conn() as c:
            c.execute(f"UPDATE queue SET {sets} WHERE job_id=?", vals)
    except Exception as e:
        log.warning("DB update error for %s: %s", job_id, e)


def queue_download(url: str, title: str, account_id: int = 0, movie_title_hint: str = "", site: str = "auto") -> str:
    """Helper to queue a download with a specific URL and title."""
    import uuid
    jid = uuid.uuid4().hex[:10]
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO queue(job_id, movie, url, site, status, created_at, updated_at) VALUES(?,?,?,?,?,?,?)",
            (jid, movie_title_hint or title, url, site, "queued", now, now)
        )
    log.info("Queued download job %s: %s (url=%s)", jid, title, url)
    return jid


# How long (seconds) a job may show zero progress before the watchdog re-queues it
_HANG_TIMEOUT_SECS = int(os.environ.get("RADD_HANG_TIMEOUT", "600"))  # 10 min default

# Per-job last-progress timestamps  { job_id: float }
_job_last_progress: dict[str, float] = {}
_progress_lock = threading.Lock()


def _touch_progress(job_id: str) -> None:
    """Record that job_id made progress right now."""
    with _progress_lock:
        _job_last_progress[job_id] = time.time()


def _clear_progress(job_id: str) -> None:
    with _progress_lock:
        _job_last_progress.pop(job_id, None)


def queue_loop(stop_event: threading.Event) -> None:
    """Background loop: process 'queued' jobs from the database.

    Improvements over v3.0:
    - Startup recovery: resets any 'processing' jobs left from a previous crash
      back to 'queued' so they are automatically retried.
    - Hang watchdog: if an active job reports no progress for RADD_HANG_TIMEOUT
      seconds (default 600) it is cancelled and re-queued so a fresh attempt
      can be made (possibly via a different site/CDN mirror).
    """
    log.info("Downloader queue worker started")
    active_threads: dict[str, threading.Thread] = {}

    # ── Startup recovery ─────────────────────────────────────────────────────
    try:
        with db.conn() as c:
            stuck = c.execute(
                "SELECT job_id, movie FROM queue WHERE status='processing'"
            ).fetchall()
        if stuck:
            log.warning(
                "Startup recovery: %d job(s) left in 'processing' state — "
                "resetting to 'queued'", len(stuck)
            )
            with db.conn() as c:
                c.execute(
                    "UPDATE queue SET status='queued', message='Resumed after restart', "
                    "updated_at=? WHERE status='processing'",
                    (int(time.time()),)
                )
            for row in stuck:
                log.info("  Recovered: %s (%s)", row["job_id"], row["movie"])
    except Exception as e:
        log.warning("Startup recovery error: %s", e)

    while not stop_event.wait(3):
        # ── Reap finished threads ────────────────────────────────────────────
        for jid in list(active_threads):
            if not active_threads[jid].is_alive():
                del active_threads[jid]
                _unregister_job(jid)
                _clear_progress(jid)

        # ── Hang watchdog ────────────────────────────────────────────────────
        now = time.time()
        with _progress_lock:
            stale = [
                jid for jid, ts in _job_last_progress.items()
                if now - ts > _HANG_TIMEOUT_SECS and jid in active_threads
            ]
        for jid in stale:
            log.warning(
                "Hang watchdog: job %s has not progressed in %ds — "
                "cancelling and re-queuing", jid, _HANG_TIMEOUT_SECS
            )
            job_obj = get_active_job(jid)
            if job_obj:
                job_obj["cancel_event"].set()
                job_obj["pause_event"].set()
            # Give the thread a moment to exit, then force-requeue in DB
            t = active_threads.get(jid)
            if t:
                t.join(timeout=5)
            with db.conn() as c:
                c.execute(
                    "UPDATE queue SET status='queued', message='Re-queued by hang watchdog', "
                    "progress=0, updated_at=? WHERE job_id=? AND status='processing'",
                    (int(time.time()), jid)
                )
            _clear_progress(jid)
            if jid in active_threads:
                del active_threads[jid]
            _unregister_job(jid)

        if len(active_threads) >= _max_parallel():
            continue

        # Skip dispatching new jobs when download service is disabled
        if db.setting("DOWNLOAD_ENABLED", "1") != "1":
            continue

        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT * FROM queue WHERE status='queued' ORDER BY id LIMIT 1"
                ).fetchone()

            if not row:
                continue

            job_row = dict(row)
            job_id  = job_row["job_id"]

            # Mark as processing immediately to prevent double-pickup
            _update_db(job_id, status="processing", message="Starting…")
            _touch_progress(job_id)

            t = threading.Thread(target=_process_job, args=(job_row,), daemon=True,
                                 name=f"job-{job_id}")
            t.start()
            active_threads[job_id] = t

        except Exception as e:
            log.warning("queue_loop error: %s", e)


def _process_job(job_row: dict) -> None:
    job_id   = job_row["job_id"]
    movie    = job_row["movie"]
    site     = job_row["site"] or "auto"

    log.info("Processing job %s: %s (site=%s)", job_id, movie, site)

    # ── Parse query for hints ────────────────────────────────────────────────
    parsed   = parse_movie_query(movie)
    # Ensure we handle both dict (old) and dataclass (new)
    if isinstance(parsed, dict):
        year_hint = parsed.get("year_hint")
        lang_hint = parsed.get("lang_hint")
        qual_hint = parsed.get("quality_hint")
        clean_name = parsed.get("clean")
    else:
        year_hint = getattr(parsed, "year", None)
        lang_hint = getattr(parsed, "lang_hint", None)
        qual_hint = getattr(parsed, "quality_hint", None)
        clean_name = getattr(parsed, "clean", movie)

    pause_evt  = threading.Event()
    cancel_evt = threading.Event()
    pause_evt.set()  # Running (not paused)

    job_obj = {
        "job_id":       job_id,
        "movie":        movie,
        "movie_clean":  clean_name,
        "movie_url":    job_row.get("url"),
        "year_hint":    year_hint,
        "lang_hint":    lang_hint,
        "qual_hint":    qual_hint,
        "status":       "processing",
        "progress":     0,
        "stage":        "starting",
        "pause_event":  pause_evt,
        "cancel_event": cancel_evt,
    }
    _register_job(job_obj)

    # Resolve quality/language: hint from query overrides stored preference
    pref_lang = db.setting("preferred_language", "Hindi") or "Hindi"
    if lang_hint:
        pref_lang = lang_hint

    pref_quality = db.setting("preferred_quality", "1080p") or "1080p"
    if qual_hint:
        pref_quality = qual_hint

    # Map DB setting keys → plugin-facing domain dict keys
    _DOMAIN_MAP = {
        "domain_vegamovies":  "vegamovies_domain",
        "domain_katmoviehd":  "katmoviehd_domain",
        "domain_rogmovies":   "rogmovies_domain",
        "domain_ssrmovies":   "ssrmovies_domain",
        "domain_rareanimes":  "rareanimes_domain",
        "domain_hdhub4u":     "domain_hdhub4u",
        "domain_moviesdrive": "domain_moviesdrive",
        "domain_nexdrive":    "nexdrive_domain",
        "domain_vcloud":      "vcloud_domain",
    }
    _domains: dict[str, str] = {}
    for _db_key, _plugin_key in _DOMAIN_MAP.items():
        _val = (db.setting(_db_key, "") or "").strip()
        if _val:
            _domains[_plugin_key] = _val

    sc_config = {
        "auto_download":   (db.setting("auto_download", "1") or "1") == "1",
        "download_dir":    db.setting("download_dir",  str(config.STAGING_DIR)) or str(config.STAGING_DIR),
        "parallel_race":   config.get_env_bool("RADD_PARALLEL_RACE", True),
        "quality":         pref_quality,
        "language":        pref_lang,
        "content_type":    db.setting("content_type", "any") or "any",
        "year_hint":       year_hint,
        "lang_hint":       lang_hint,
        "query":           movie,
        "movie_clean":     clean_name,
        "domains":         _domains,
        "browser": {
            "headless": (db.setting("headless", "1") or "1") == "1",
        },
    }

    log_lines: list[str] = []

    def _stage(label: str) -> None:
        """Update the current human-readable stage label."""
        job_obj["stage"] = label
        _update_db(job_id, status=job_obj.get("status", "processing"), message=label)

    def log_fn(msg: str) -> None:
        ts = time.strftime("%H:%M:%S")
        line = f"[{ts}] {msg}"
        log_lines.append(line)
        log.debug("[job %s] %s", job_id, msg)
        _update_db(
            job_id,
            status=job_obj.get("status", "processing"),
            progress=job_obj.get("progress", 0),
            message=msg,
            log="\n".join(log_lines[-500:]),
        )
        # Touch hang watchdog on every log so the watchdog knows we're alive
        _touch_progress(job_id)

    try:
        hints_str = ""
        if year_hint: hints_str += f" [{year_hint}]"
        if lang_hint: hints_str += f" [{lang_hint}]"
        log_fn(f"Starting: {clean_name}{hints_str}  (original query: {movie})")

        _stage(f"Searching for {clean_name}…")

        if site == "upload":
            log_fn("Upload job: skipping search, using local file directly")
        elif site == "direct":
            # Direct URL download — skip scraping entirely
            direct_url = (job_row.get("url") or "").strip()
            if not direct_url:
                raise ValueError("Direct download job is missing a URL")
            _stage("Downloading from direct URL…")
            log_fn(f"Direct URL: {direct_url[:120]}")
            staging_dir = Path(sc_config.get("download_dir") or str(config.STAGING_DIR))
            staging_dir.mkdir(parents=True, exist_ok=True)
            dl_path = download_file(
                direct_url,
                dest_dir=staging_dir,
                job=job_obj,
                log_fn=log_fn,
            )
            if "/skipped/already_uploaded/" in str(dl_path):
                log_fn("File already in library — nothing to upload.")
                _update_db(job_id, status="done", progress=100, message="Already in library")
                return
            job_obj["download_path"] = str(dl_path)
            job_obj["status"] = "done"
            log_fn(f"Download complete: {dl_path.name}")

        else:
            try:
                from . import scraper
                if site == "auto":
                    scraper.run_job_ai(job_obj, sc_config, log_fn)
                else:
                    try:
                        from . import sites
                        plugin = sites.get_plugin(site)
                        _stage(f"Searching {site}…")
                        scraper.run_job(job_obj, sc_config, plugin, log_fn)
                    except Exception as e:
                        log_fn(f"Plugin error for site '{site}': {e}")
                        raise
            except ImportError as e:
                log_fn(f"Scraper module not available: {e}")
                raise

        final_status = job_obj.get("status", "done")
        if final_status not in ("cancelled", "error", "failed"):
            final_status = "done"
            log_fn("Job complete!")

        _update_db(job_id, status=final_status, progress=100)

        # ── Enrich title metadata using full 6-tier fallback chain ─────────────────
        # After the download/scrape completes, we know the movie title and year hint.
        # Try to enrich metadata (TMDB→OMDB→AI→IMDbAPI→YouTube→Google KG) so the
        # admin panel immediately shows poster/plot/cast for the new title.
        if final_status == "done" and clean_name:
            try:
                ml = _get_metadata_lookup()

                class _DP:
                    pass

                _dp = _DP()
                _dp.title      = clean_name
                _dp.year       = int(year_hint) if year_hint and str(year_hint).isdigit() else None
                _dp.media_type = "movie"
                enriched_meta = ml.enrich(_dp, config={})
                if enriched_meta:
                    # Save to titles DB if the title already exists, or upsert it
                    try:
                        existing_title = db.find_title_by_name(clean_name)
                        if existing_title:
                            db.update_title(existing_title["id"], enriched_meta)
                            log.debug("Enriched title %r after download (id=%s)", clean_name, existing_title["id"])
                    except Exception:
                        pass
            except Exception as _ee:
                log.debug("Post-download enrichment failed for %r: %s", clean_name, _ee)

        if site == "upload":
            from . import uploader
            uploaded_path = Path(movie)
            if not uploaded_path.is_absolute():
                uploaded_path = Path(config.MEDIA_DIR) / movie
            if not uploaded_path.exists():
                raise FileNotFoundError(f"Upload file not found: {uploaded_path}")
            _stage("Uploading to JazzDrive…")
            result = uploader.upload_to_jazzdrive(
                uploaded_path,
                movie_title=clean_name,
                job_id=job_id,
                log_fn=log_fn,
                auto_delete=True,
            )
            if result.get("ok"):
                share = result.get("share_url") or ""
                if share:
                    _update_db(job_id, url=share)
            else:
                raise RuntimeError(result.get("error") or "Upload failed")
        elif final_status == "done":
            # ── Post-process + JazzDrive upload + auto-delete ─────────────────
            downloaded_paths_str = job_obj.get("download_path")
            if downloaded_paths_str:
                try:
                    from . import uploader
                    
                    # Handle multiple files (Seasons)
                    path_list = downloaded_paths_str.split("||")
                    all_share_urls = []
                    
                    for p_idx, path_str in enumerate(path_list):
                        if not path_str: continue
                        dl_path = Path(path_str)
                        if not dl_path.exists():
                            log_fn(f"Warning: downloaded file not found: {path_str}")
                            continue

                        # ── Move completed file from staging → media dir ───────────
                        staging = config.STAGING_DIR.resolve()
                        try:
                            dl_resolved = dl_path.resolve()
                            if staging in dl_resolved.parents or dl_resolved.parent == staging:
                                from . import media_naming as _mn
                                _plan = _mn.derive_media_plan(dl_path.name)
                                target_name = _plan.filename
                                
                                dest = config.MEDIA_DIR / target_name
                                dest.parent.mkdir(parents=True, exist_ok=True)
                                
                                if dest.exists() and dest != dl_path:
                                    dest = config.MEDIA_DIR / (Path(target_name).stem + f"_{p_idx}" + Path(target_name).suffix)
                                
                                shutil.move(str(dl_path), str(dest))
                                log_fn(f"Moved to media folder with clean name: {dest.name}")
                                dl_path = dest
                        except Exception as _mv_err:
                            log_fn(f"Warning: could not move from staging: {_mv_err}")

                        upload_targets: list[Path] = []
                        is_season = False

                        # ── Handle ZIPs and Folders (Seasons) ─────────────────────
                        if dl_path.suffix.lower() == ".zip":
                            _stage(f"Extracting season ZIP ({p_idx+1}/{len(path_list)})…")
                            dl_path = extract_zip(dl_path, log_fn)

                        if dl_path.is_dir():
                            is_season = True
                            _stage("Preparing episodes…")
                            video_files = sorted(
                                [f for f in dl_path.rglob("*")
                                 if f.is_file() and f.suffix.lower() in _VIDEO_EXTENSIONS],
                                key=lambda f: (f.parent.name, f.name),
                            )
                            if video_files:
                                log_fn(f"Detected {len(video_files)} episode(s) in season folder.")
                                upload_targets = video_files
                            else:
                                log_fn("No video files found in season folder — skipping upload")
                        else:
                            _stage(f"Preparing upload {p_idx+1}/{len(path_list)}…")
                            upload_targets = split_large_file(dl_path, log_fn)

                        share_urls: list[str] = []
                        success_count = 0
                        for idx, part_path in enumerate(upload_targets, 1):
                            if not part_path.exists():
                                log_fn(f"Warning: part file not found, skipping upload: {part_path.name}")
                                continue

                            title_hint = f"{clean_name} Part {idx}" if len(upload_targets) > 1 else clean_name
                            if is_season:
                                label = f"[{p_idx+1}] Episode {idx}/{len(upload_targets)}: {part_path.name}"
                                # Try to preserve episode name from filename
                                title = part_path.stem
                            else:
                                label = (f"[{p_idx+1}] Part {idx}/{len(upload_targets)}: {part_path.name}"
                                         if len(upload_targets) > 1 else part_path.name)
                                title = title_hint

                            _stage(f"Uploading {label}…")
                            result = uploader.upload_to_jazzdrive(
                                part_path,
                                movie_title=title,
                                job_id=job_id,
                                log_fn=log_fn,
                                auto_delete=True,
                            )
                            if result.get("ok"):
                                success_count += 1
                                share = result.get("share_url") or ""
                                if share: share_urls.append(share)
                            elif "already" in str(result.get("error","")).lower():
                                success_count += 1
                                log_fn(f"Already in library ✓ {part_path.name}")
                            else:
                                log_fn(f"Upload failed: {result.get('error', '?')}")

                        if is_season and dl_path.is_dir():
                            if success_count > 0:
                                # If at least one thing worked, we can clean up if it's mostly done, 
                                # but usually for seasons we only delete if EVERYTHING worked.
                                if success_count == len(upload_targets):
                                    try: shutil.rmtree(dl_path)
                                    except: pass
                                else:
                                    log_fn(f"Partial upload success — keeping folder for review: {dl_path.name}")
                            else:
                                log_fn(f"Upload failed completely — keeping folder: {dl_path.name}")
                        
                        all_share_urls.extend(share_urls)

                    if all_share_urls:
                        _update_db(job_id, status="done", url=" | ".join(all_share_urls), message="Job complete!")
                    else:
                        _update_db(job_id, status="done", message="Job complete!")

                except Exception as _ue:
                    log_fn(f"JazzDrive upload error: {_ue}")
                    _update_db(job_id, status="error", message=f"Upload error: {_ue}")
            else:
                # legacy fallback — scan media dir for new files
                try:
                    from . import uploader
                    uploader.trigger_scan_now()
                except Exception:
                    pass

    except InterruptedError as e:
        log_fn(f"Cancelled: {e}")
        _update_db(job_id, status="cancelled", message=str(e))

    except Exception as e:
        log.exception("Job %s failed: %s", job_id, e)
        log_fn(f"ERROR: {e}")
        _update_db(job_id, status="error", message=str(e)[:300])

    finally:
        _unregister_job(job_id)


# ─────────────────────────────────────────────────────────────────────────────
# File download helpers
# ─────────────────────────────────────────────────────────────────────────────

def _safe_filename(name: str) -> str:
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name)
    name = name.strip('. ')
    return name or "movie_download"


def _get_filename_from_url(url: str, headers: dict | None = None, fallback_title: str | None = None) -> str:
    name = "movie_download.mkv"
    if headers:
        cd = headers.get("Content-Disposition", "")
        m = re.search(r'filename\*?=["\']?(?:UTF-8\'\')?([^"\';]+)', cd, re.IGNORECASE)
        if m:
            name = _safe_filename(urllib.parse.unquote(m.group(1).strip()))
    
    if name == "movie_download.mkv" or len(name) < 4:
        path = urllib.parse.urlparse(url).path
        name = urllib.parse.unquote(path.split("/")[-1])
    
    name = _safe_filename(name)
    
    # If the name is generic (like l.mp4, v.mp4, play.php) and we have a title, use it.
    stem = name.split(".")[0].lower()
    if fallback_title and (len(stem) < 3 or stem in ("l", "v", "video", "download", "play", "index")):
        ext = name.split(".")[-1] if "." in name else "mp4"
        if len(ext) > 4: ext = "mp4"
        name = _safe_filename(fallback_title) + "." + ext
        
    return name if name and '.' in name else "movie_download.mkv"


_aria2_usable: bool | None = None  # cached result after first probe


def _has_aria2() -> bool:
    """Return True only if aria2c is on PATH AND runs without errors.

    Caches the result so we only pay the subprocess cost once per process.
    The binary may exist on PATH but crash at startup (e.g. glibc mismatch
    on this Replit/Nix environment) — checking the exit code catches that.
    """
    global _aria2_usable
    if _aria2_usable is not None:
        return _aria2_usable
    try:
        from .installer import _extend_path_for_nix, _add_to_path
        from pathlib import Path as _Path
        _extend_path_for_nix()
        custom_bin = _Path.home() / ".raddhub" / "bin"
        if custom_bin.is_dir():
            _add_to_path(str(custom_bin))
    except Exception:
        pass
    if not shutil.which("aria2c"):
        _aria2_usable = False
        return False
    try:
        result = __import__("subprocess").run(
            ["aria2c", "--version"],
            capture_output=True, timeout=5,
        )
        _aria2_usable = (result.returncode == 0)
    except Exception:
        _aria2_usable = False
    if not _aria2_usable:
        log.warning("aria2c found on PATH but failed --version probe (glibc/runtime issue) "
                    "— falling back to urllib downloader")
    return _aria2_usable


def download_file(
    url: str,
    dest_dir: Path | str | None = None,
    job: dict | None = None,
    log_fn=None,
    referer: str | None = None,
) -> Path:
    dest_dir = Path(dest_dir or DOWNLOAD_DIR)
    dest_dir.mkdir(parents=True, exist_ok=True)

    def log_local(msg):
        if log_fn:
            log_fn(f"[Downloader] {msg}")

    # --- Deduplication Check ---
    try:
        # Quick HEAD request to get filename/size if possible
        import urllib.request as _ur
        h_headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        }
        if referer:
            h_headers["Referer"] = referer
            
        req = _ur.Request(url, method="HEAD", headers=h_headers)
        with _ur.urlopen(req, timeout=10) as resp:
            headers = dict(resp.headers)
            size_str = headers.get("Content-Length", "0")
            size = int(size_str)
            name = _get_filename_from_url(url, headers, job.get("movie") if job else None)
            
            existing = db.find_file_by_name(name, size)
            if existing:
                log_local(f"Skipping download: {name} ({size/1024**2:.1f} MB) already exists in library.")
                return Path(f"/skipped/already_uploaded/{name}")
    except Exception:
        pass

    def check_control():
        if job:
            pe = job.get("pause_event")
            ce = job.get("cancel_event")
            while pe and not pe.is_set():
                if ce and ce.is_set():
                    raise InterruptedError("Download cancelled")
                pe.wait(0.5)
            if ce and ce.is_set():
                raise InterruptedError("Download cancelled")

    if _has_aria2():
        return _download_aria2(url, dest_dir, job, log_local, check_control, referer=referer)
    return _download_urllib(url, dest_dir, job, log_local, check_control, referer=referer)


_GDRIVE_HOSTS = (
    "video-downloads.googleusercontent.com",
    "drive.usercontent.google.com",
    "doc-0a-00-docs.googleusercontent.com",
)
_GDRIVE_HEADERS = [
    "--header=User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "--header=Accept: */*",
    "--header=Referer: https://drive.google.com/",
]


def _is_gdrive_url(url: str) -> bool:
    try:
        from urllib.parse import urlparse
        host = urlparse(url).netloc.lower()
        return any(h in host for h in _GDRIVE_HOSTS)
    except Exception:
        return False


def _download_aria2(url, dest_dir, job, log, check_control, referer=None):
    import subprocess
    log(f"Using aria2c: {url[:80]}...")
    try:
        before_files = {p.name for p in dest_dir.iterdir() if p.is_file()}
    except OSError:
        before_files = set()
    cmd = [
        "aria2c",
        "--continue=true",
        "--max-connection-per-server=16",
        "--split=16",
        "--min-split-size=1M",
        "--file-allocation=none",
        "--auto-file-renaming=false",
        "--allow-overwrite=false",
        "--remote-time=true",
        "--retry-wait=5",
        "--max-tries=10",
        "--check-integrity=true",
        "--conditional-get=true",
        "--console-log-level=error",
        "--summary-interval=1",
        "--show-console-readout=false",
        f"--dir={dest_dir}",
        "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    ]
    if referer:
        cmd.append(f"--referer={referer}")
    
    if _is_gdrive_url(url):
        # cmd.extend(_GDRIVE_HEADERS) # Deprecated in favor of passed referer
        pass
    cmd.append(url)
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    _ARIA_RX = re.compile(
        r"\[#\w+\s+([\d.]+\s*[KMGTP]?i?B)/([\d.]+\s*[KMGTP]?i?B)\((\d+)%\)"
        r".*?DL:\s*([\d.]+\s*[KMGTP]?i?B)"
        r"(?:.*?ETA:\s*(\S+))?",
        re.IGNORECASE,
    )
    def _to_bytes(s: str) -> float:
        s = s.upper().replace("I", "")
        m = re.match(r"([\d.]+)\s*([KMGTP]?B)", s)
        if not m: return 0
        val, unit = float(m.group(1)), m.group(2)
        mult = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
        return val * mult.get(unit, 1)

    filename = None
    for line in proc.stdout:
        check_control()
        line = line.rstrip()
        m = _ARIA_RX.search(line)
        if m:
            done_s, total_s, pct_s, speed, eta = m.groups()
            
            # Calculate smooth float percentage
            try:
                done_b = _to_bytes(done_s)
                total_b = _to_bytes(total_s)
                if total_b > 0:
                    pct = (done_b / total_b) * 100
                else:
                    pct = float(pct_s)
            except Exception:
                pct = float(pct_s)

            # Update progress on job object so queue list sees it
            if job:
                try:
                    job["progress"] = pct
                except Exception:
                    pass
            log(f"Progress: {pct:.1f}%  {done_s}/{total_s}  Speed: {speed}/s  ETA: {eta or '—'}")
            # Touch hang watchdog on each progress tick
            if job:
                try:
                    _touch_progress(job.get("job_id", ""))
                except Exception:
                    pass
        elif "[#" in line:
            log(f"aria2: {line}")
        if "Download complete" in line or "saved" in line.lower():
            sm = re.search(r"saved\s+(.+)", line, re.IGNORECASE)
            if sm:
                filename = sm.group(1).strip()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError(f"aria2c failed (code {proc.returncode})")
    if filename:
        res_path = Path(filename)
        if not res_path.is_absolute():
            res_path = dest_dir / res_path
            
        # Fix generic names like l.mp4
        fallback = job.get("movie") if job else None
        if fallback and res_path.exists():
             stem = res_path.stem.lower()
             if len(stem) < 3 or stem in ("l", "v", "video", "download", "play", "index"):
                 new_name = _safe_filename(fallback) + res_path.suffix
                 if not (res_path.parent / new_name).exists():
                     try:
                         res_path.rename(res_path.parent / new_name)
                         res_path = res_path.parent / new_name
                         log(f"Renamed generic file to: {res_path.name}")
                     except Exception:
                         pass
        return res_path
    try:
        after_files = {p.name for p in dest_dir.iterdir() if p.is_file()}
    except OSError:
        after_files = set()
    new_names = after_files - before_files
    if new_names:
        new_paths = sorted((dest_dir / n for n in new_names),
                           key=lambda p: p.stat().st_size, reverse=True)
        return new_paths[0]
    files = sorted(dest_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    if files:
        return files[0]
    raise RuntimeError("aria2c download finished but file not found")


def _download_urllib(url, dest_dir, job, log, check_control, referer=None):
    log(f"Downloading: {url[:80]}...")
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept": "*/*",
    }
    if referer:
        headers["Referer"] = referer
        
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        headers    = dict(resp.headers)
        ct         = headers.get("Content-Type", headers.get("content-type", ""))
        if ct.lower().startswith("text/html"):
            raise RuntimeError(f"Server returned HTML (not a media file). URL: {url[:100]}")
        
        fallback = job.get("movie") if job else None
        filename   = _get_filename_from_url(url, headers, fallback_title=fallback)
        total      = int(headers.get("Content-Length", 0))
        dest       = dest_dir / filename
        log(f"Saving: {filename}  ({total // 1048576 if total else '?'} MB)")
        downloaded = 0
        start_time = time.time()
        last_log   = start_time
        last_bytes = 0
        chunk_size = 512 * 1024

        def _fmt(n: int) -> str:
            for u in ("B", "KB", "MB", "GB"):
                if n < 1024: return f"{n:.1f}{u}"
                n /= 1024
            return f"{n:.1f}TB"

        def _eta(secs: float) -> str:
            s = int(max(0, secs))
            if s < 60:   return f"{s}s"
            if s < 3600: return f"{s // 60}m{s % 60:02d}s"
            return f"{s // 3600}h{(s % 3600) // 60:02d}m"

        with open(dest, "wb") as f:
            while True:
                check_control()
                chunk = resp.read(chunk_size)
                if not chunk:
                    break
                f.write(chunk)
                downloaded += len(chunk)
                now = time.time()
                if now - last_log >= 1:
                    speed = (downloaded - last_bytes) / max(0.001, now - last_log)
                    if total:
                        pct = downloaded / total * 100
                        if job:
                            try: job["progress"] = pct
                            except Exception: pass
                        log(f"Progress: {pct:.1f}%  {_fmt(downloaded)}/{_fmt(total)}"
                            f"  Speed: {_fmt(int(speed))}/s  ETA: {_eta((total-downloaded)/max(1,speed))}")
                        try:
                            _touch_progress(job.get("job_id", "") if job else "")
                        except Exception:
                            pass
                    else:
                        log(f"Downloaded: {_fmt(downloaded)}  Speed: {_fmt(int(speed))}/s")
                    last_log   = now
                    last_bytes = downloaded
    log(f"Done: {dest}")
    return dest
