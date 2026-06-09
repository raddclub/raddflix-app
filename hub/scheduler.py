"""Smart background scheduler.

Two independent loops run as daemon threads:

1. rescan_ongoing      — checks 'ongoing' titles every 24 h for new episodes.
   Uses episode-number comparison (not count) to detect truly new content.

2. scheduled_downloads — user-configured recurring downloads (e.g. "Game of Thrones S5,
   every Monday").  Stored in the `scheduled_downloads` DB table.
"""
from __future__ import annotations
import logging
import re
import threading
import time
from pathlib import Path
from typing import Optional
from . import db

log = logging.getLogger("hub.scheduler")

# ─────────────────────────────────────────────────────────────────────────────
# DB helpers — scheduled_downloads table
# ─────────────────────────────────────────────────────────────────────────────

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS scheduled_downloads (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    label       TEXT NOT NULL,          -- human-readable name
    query       TEXT NOT NULL,          -- search query (title + year)
    site        TEXT DEFAULT 'auto',    -- scraper site or 'auto'
    quality     TEXT DEFAULT '1080p',
    language    TEXT DEFAULT 'Hindi',
    season_hint INTEGER DEFAULT NULL,   -- restrict to this season
    frequency   TEXT DEFAULT 'daily',   -- 'daily' | 'weekly' | '12h' | 'manual'
    day_of_week INTEGER DEFAULT NULL,   -- 0=Mon … 6=Sun (for weekly)
    is_active   INTEGER DEFAULT 1,
    last_run_at INTEGER DEFAULT NULL,
    next_run_at INTEGER DEFAULT 0,
    run_count   INTEGER DEFAULT 0,
    last_status TEXT DEFAULT NULL,
    created_at  INTEGER DEFAULT (strftime('%s','now'))
);
"""

def ensure_schema():
    with db.conn() as c:
        c.executescript(SCHEMA_SQL)

ensure_schema()


def _freq_seconds(freq: str, day_of_week: Optional[int] = None) -> int:
    if freq == "12h":    return 43200
    if freq == "weekly":
        now = time.localtime()
        dow = now.tm_wday
        target = day_of_week if day_of_week is not None else 0
        delta = (target - dow) % 7 or 7
        return delta * 86400
    return 86400  # daily default


def list_schedules() -> list[dict]:
    with db.conn() as c:
        return [dict(r) for r in c.execute("SELECT * FROM scheduled_downloads ORDER BY id").fetchall()]


def add_schedule(label: str, query: str, site: str = "auto",
                 quality: str = "1080p", language: str = "Hindi",
                 season_hint: Optional[int] = None,
                 frequency: str = "daily", day_of_week: Optional[int] = None) -> int:
    ensure_schema()
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO scheduled_downloads "
            "(label,query,site,quality,language,season_hint,frequency,day_of_week,is_active,next_run_at,created_at) "
            "VALUES(?,?,?,?,?,?,?,?,1,?,?)",
            (label, query, site, quality, language, season_hint, frequency, day_of_week, now, now)
        )
        return c.execute("SELECT last_insert_rowid()").fetchone()[0]


def delete_schedule(schedule_id: int):
    with db.conn() as c:
        c.execute("DELETE FROM scheduled_downloads WHERE id=?", (schedule_id,))


def toggle_schedule(schedule_id: int, active: bool):
    with db.conn() as c:
        c.execute("UPDATE scheduled_downloads SET is_active=? WHERE id=?",
                  (1 if active else 0, schedule_id))


# ─────────────────────────────────────────────────────────────────────────────
# Episode number parsing — smarter than count comparison
# ─────────────────────────────────────────────────────────────────────────────

def _ep_numbers(filenames: list[str]) -> set[tuple[int, int]]:
    """Return set of (season, episode) tuples found in the filenames."""
    found = set()
    for fn in filenames:
        # S01E02, s1e2, 1x02, ep02 patterns
        for pat in [
            r'[Ss](\d{1,2})[Ee](\d{1,2})',
            r'(\d{1,2})[xX](\d{2})',
            r'[Ss]eason\s*(\d+).*?[Ee]p(?:isode)?\s*(\d+)',
        ]:
            m = re.search(pat, fn)
            if m:
                found.add((int(m.group(1)), int(m.group(2))))
                break
    return found


def _highest_episode(nums: set[tuple[int, int]], season: Optional[int] = None) -> int:
    """Return highest episode number in a season (or overall)."""
    if not nums:
        return 0
    filtered = {e for s, e in nums if season is None or s == season}
    return max(filtered) if filtered else 0


# ─────────────────────────────────────────────────────────────────────────────
# Ongoing title rescan
# ─────────────────────────────────────────────────────────────────────────────

def rescan_ongoing_titles(log_fn=None):
    """Check titles marked is_ongoing=1 for new episodes using episode-number comparison."""
    def _log(msg):
        if log_fn: log_fn(msg)
        log.info(msg)

    _log("Scheduler: checking ongoing titles for new episodes…")

    with db.conn() as c:
        ongoing = c.execute(
            "SELECT id, title, year, season_count FROM titles "
            "WHERE is_ongoing=1 OR status='ongoing'"
        ).fetchall()

    if not ongoing:
        _log("No ongoing titles found.")
        return

    from . import scraper as _scraper, config as _cfg

    for t in ongoing:
        title_id = t["id"]
        name     = t["title"]
        year     = t["year"]
        season   = t["season_count"] or 1

        _log(f"Checking: {name} (S{season})…")

        with db.conn() as c:
            existing_files = c.execute(
                "SELECT filename, season, episode FROM files WHERE title_id=?", (title_id,)
            ).fetchall()

        existing_eps = _ep_numbers([f["filename"] for f in existing_files])
        max_existing = _highest_episode(existing_eps, season)
        _log(f"  We have up to episode {max_existing} in S{season:02d}")

        query = f"{name}"
        if year: query += f" ({year})"
        sc_cfg = {
            "auto_download": False,
            "quality":  db.setting("preferred_quality",  "1080p") or "1080p",
            "language": db.setting("preferred_language", "Hindi")  or "Hindi",
        }
        job = {
            "job_id": f"rescan-{title_id}-{int(time.time())}",
            "movie": query, "movie_clean": name, "year_hint": year,
            "status": "processing",
            "pause_event": threading.Event(), "cancel_event": threading.Event(),
        }
        job["pause_event"].set()

        try:
            _scraper.run_job_ai(job, sc_cfg, _log)
            raw_links = job.get("result_url") or ""
            links = [l.strip() for l in raw_links.split("||") if l.strip()]
            if not links:
                _log(f"  No links found for {name}.")
                continue

            # Heuristic: links ordered by episode → pick links beyond what we have
            new_links = links[max_existing:] if max_existing < len(links) else []
            if not new_links:
                _log(f"  {name}: already up-to-date ({len(links)} links, have ep {max_existing}).")
                continue

            _log(f"  {name}: {len(new_links)} new episode(s) found → queuing…")
            for link in new_links:
                with db.conn() as c:
                    import uuid
                    jid = uuid.uuid4().hex[:10]
                    now = int(time.time())
                    c.execute(
                        "INSERT INTO queue(job_id, movie, url, site, status, message, created_at, updated_at) "
                        "VALUES(?,?,?,?,?,?,?,?)",
                        (jid, query, link, job.get("site_used", "auto"), "queued",
                         "Auto-queued by ongoing rescan", now, now)
                    )
        except Exception as e:
            _log(f"  Error rescanning {name}: {e}")

    _log("Ongoing rescan complete.")


# ─────────────────────────────────────────────────────────────────────────────
# Scheduled downloads runner
# ─────────────────────────────────────────────────────────────────────────────

def run_scheduled_downloads(log_fn=None):
    """Process scheduled_downloads entries whose next_run_at <= now."""
    def _log(msg):
        if log_fn: log_fn(msg)
        log.info(msg)

    now = int(time.time())
    ensure_schema()

    with db.conn() as c:
        due = c.execute(
            "SELECT * FROM scheduled_downloads WHERE is_active=1 AND next_run_at<=?", (now,)
        ).fetchall()

    if not due:
        return

    _log(f"Scheduler: {len(due)} scheduled download(s) due.")

    for sched in due:
        sched = dict(sched)
        query = sched["query"]
        site  = sched["site"] or "auto"
        _log(f"  Running scheduled: [{sched['label']}] query={query!r} site={site}")

        try:
            with db.conn() as c:
                import uuid
                jid = uuid.uuid4().hex[:10]
                c.execute(
                    "INSERT INTO queue(job_id, movie, site, status, message, created_at, updated_at) "
                    "VALUES(?,?,?,?,?,?,?)",
                    (jid, query, site, "queued",
                     f"Auto-queued by schedule: {sched['label']}", now, now)
                )
            sched_status = "ok"
        except Exception as e:
            _log(f"  Error queuing {query!r}: {e}")
            sched_status = f"error: {e}"

        freq_sec = _freq_seconds(sched.get("frequency", "daily"), sched.get("day_of_week"))
        with db.conn() as c:
            c.execute(
                "UPDATE scheduled_downloads SET last_run_at=?, next_run_at=?, "
                "run_count=run_count+1, last_status=? WHERE id=?",
                (now, now + freq_sec, sched_status, sched["id"])
            )


# ─────────────────────────────────────────────────────────────────────────────
# Background loop
# ─────────────────────────────────────────────────────────────────────────────

def scheduler_loop(stop_event: threading.Event):
    # Short initial delay so the server is fully up
    if stop_event.wait(120):
        return

    while not stop_event.is_set():
        try:
            rescan_ongoing_titles()
        except Exception as e:
            log.error("Ongoing rescan error: %s", e)

        try:
            run_scheduled_downloads()
        except Exception as e:
            log.error("Scheduled downloads error: %s", e)

        # Check every 30 minutes (catches weekly/daily/12h windows)
        if stop_event.wait(1800):
            break


def start(stop_event: threading.Event):
    t = threading.Thread(
        target=scheduler_loop, args=(stop_event,),
        daemon=True, name="hub-scheduler"
    )
    t.start()
    log.info("Smart background scheduler started (30-min check interval)")
