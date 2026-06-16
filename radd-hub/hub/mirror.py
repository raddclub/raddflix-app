"""GitHub + Google Sheets mirror.

Wraps the v2.0 ``db_github`` and ``db_gsheets`` modules with two upgrades:

* Reads keys from the multi-key vault (auto-rotation, multiple GitHub
  tokens / multiple Google service-account JSONs supported).
* Triggered automatically by BOTH ``hub.scanner`` (dbgen) and
  ``hub.uploader`` (flix) so every JazzDrive file ends up in the same
  central repo + sheet, regardless of source.

A retry queue (``mirror_log`` table) holds failed pushes so a background
worker can re-attempt them.
"""
from __future__ import annotations
import os
import json
import time
import logging
import threading
from typing import Optional
from . import db, keys, config

log = logging.getLogger("hub.mirror")

# ------------------------------------------------------------------ #
# Config exposure: legacy modules read os.environ directly.          #
# We push vault values into env right before each call.              #
# ------------------------------------------------------------------ #

def _expose_github_env() -> bool:
    tok = keys.get_active_value("github")
    if not tok:
        return False
    os.environ["GITHUB_TOKEN"] = tok
    if not os.environ.get("GITHUB_REPO"):
        os.environ["GITHUB_REPO"] = db.setting("github_repo", "") or ""
    if not os.environ.get("GITHUB_BRANCH"):
        os.environ["GITHUB_BRANCH"] = db.setting("github_branch", "main") or "main"
    if not os.environ.get("GITHUB_DB_PATH"):
        os.environ["GITHUB_DB_PATH"] = db.setting("github_db_path", "library.json") or "library.json"
    return bool(os.environ.get("GITHUB_REPO"))


def _expose_gsheets_env() -> bool:
    sa = keys.get_active_value("gsheets_sa_json")
    if not sa:
        return False
    os.environ["GOOGLE_SERVICE_ACCOUNT_JSON"] = sa
    if not os.environ.get("GOOGLE_SHEET_ID"):
        os.environ["GOOGLE_SHEET_ID"] = db.setting("gsheet_id", "") or ""
    if not os.environ.get("GOOGLE_SHEET_NAME"):
        os.environ["GOOGLE_SHEET_NAME"] = db.setting("gsheet_name", "RaddHub Library") or "RaddHub Library"
    return bool(os.environ.get("GOOGLE_SHEET_ID"))


# ------------------------------------------------------------------ #
# Public push for a single file                                       #
# ------------------------------------------------------------------ #

def _file_to_entry(file_id: int) -> Optional[dict]:
    with db.conn() as c:
        r = c.execute(
            "SELECT f.*, t.title AS tmdb_title, t.year AS tmdb_year, "
            "       t.poster AS tmdb_poster, "
            "       t.rating AS tmdb_rating, t.tmdb_id AS tmdb_numeric_id "
            "FROM files f LEFT JOIN titles t ON t.id = f.title_id "
            "WHERE f.id=?", (file_id,)).fetchone()
        if not r:
            return None
    e = dict(r)
    # convert epoch back to ISO for human readability in mirrors
    if e.get("uploaded_at"):
        try:
            from datetime import datetime
            e["uploaded_at_iso"] = datetime.utcfromtimestamp(int(e["uploaded_at"])).isoformat()
        except Exception:
            pass
    return e


def push_file(file_id: int) -> dict:
    """Push one file to GitHub + Sheets. Records status back into DB."""
    entry = _file_to_entry(file_id)
    if not entry:
        return {"github": "skip", "gsheets": "skip", "error": "file not found"}

    out = {"github": "skip", "gsheets": "skip"}

    # ---- GitHub --------------------------------------------------
    if _expose_github_env():
        try:
            from ._legacy import db_github
            ok = db_github.push_merged_entry(str(file_id), entry)
            db.update_mirror_status(file_id, github="ok" if ok else "failed")
            out["github"] = "ok" if ok else "failed"
            if not ok:
                _enqueue_retry("github", "push_entry", str(file_id), entry)
        except Exception as e:
            log.warning("github push failed: %s", e)
            db.update_mirror_status(file_id, github="failed")
            out["github"] = "failed"
            _enqueue_retry("github", "push_entry", str(file_id), entry, last_error=str(e))

    # ---- Google Sheets ------------------------------------------
    if _expose_gsheets_env():
        try:
            from ._legacy import db_gsheets
            ok = db_gsheets.append_entry(entry.get("fingerprint", str(file_id)), entry)
            db.update_mirror_status(file_id, gsheets="ok" if ok else "failed")
            out["gsheets"] = "ok" if ok else "failed"
            if not ok:
                _enqueue_retry("gsheets", "push_entry", str(file_id), entry)
        except Exception as e:
            log.warning("gsheets push failed: %s", e)
            db.update_mirror_status(file_id, gsheets="failed")
            out["gsheets"] = "failed"
            _enqueue_retry("gsheets", "push_entry", str(file_id), entry, last_error=str(e))

    return out


def push_full_library() -> dict:
    """Push the entire merged library to GitHub as one snapshot."""
    out = {"github": "skip", "gsheets": "skip"}
    if _expose_github_env():
        try:
            with db.conn() as c:
                rows = [dict(r) for r in c.execute(
                    "SELECT f.*, t.title AS tmdb_title, t.year AS tmdb_year "
                    "FROM files f LEFT JOIN titles t ON t.id=f.title_id"
                ).fetchall()]
            full = {str(r["id"]): r for r in rows}
            from ._legacy import db_github
            ok = db_github.push_db(full)
            out["github"] = "ok" if ok else "failed"
        except Exception as e:
            log.warning("github full push failed: %s", e)
            out["github"] = "failed"
    return out


# ------------------------------------------------------------------ #
# Async fire-and-forget                                               #
# ------------------------------------------------------------------ #

def push_file_async(file_id: int) -> None:
    threading.Thread(target=push_file, args=(file_id,), daemon=True).start()


# ------------------------------------------------------------------ #
# Retry queue                                                         #
# ------------------------------------------------------------------ #

def _enqueue_retry(target: str, action: str, ref: str, payload: dict,
                   last_error: str = "") -> None:
    now = int(time.time())
    with db.conn() as c:
        c.execute("INSERT INTO mirror_log(target,action,ref,payload,status,attempts,"
                  "last_error,next_retry_at,created_at,updated_at) "
                  "VALUES(?,?,?,?,?,?,?,?,?,?)",
                  (target, action, ref, json.dumps(payload), "pending",
                   1, last_error, now + 300, now, now))


def retry_loop(stop_event: threading.Event, interval_s: int = 60) -> None:
    while not stop_event.wait(interval_s):
        if db.setting("MIRROR_ENABLED", "1") != "1":
            log.debug("retry_loop: MIRROR_ENABLED=0, skipping tick")
            continue
        try:
            now = int(time.time())
            with db.conn() as c:
                pending = c.execute(
                    "SELECT * FROM mirror_log WHERE status='pending' "
                    "AND next_retry_at <= ? ORDER BY id LIMIT 20",
                    (now,)).fetchall()
            for r in pending:
                try:
                    payload = json.loads(r["payload"] or "{}")
                except Exception:
                    payload = {}
                ok = False
                if r["target"] == "github" and _expose_github_env():
                    try:
                        from ._legacy import db_github
                        ok = bool(db_github.push_merged_entry(r["ref"], payload))
                    except Exception as e:
                        log.warning("retry github: %s", e)
                elif r["target"] == "gsheets" and _expose_gsheets_env():
                    try:
                        from ._legacy import db_gsheets
                        ok = bool(db_gsheets.append_entry(r["ref"], payload))
                    except Exception as e:
                        log.warning("retry gsheets: %s", e)
                with db.conn() as c:
                    if ok:
                        c.execute("UPDATE mirror_log SET status='ok', updated_at=? WHERE id=?",
                                  (int(time.time()), r["id"]))
                    else:
                        attempts = (r["attempts"] or 0) + 1
                        backoff = min(3600, 60 * (2 ** attempts))
                        status = "failed" if attempts > 8 else "pending"
                        c.execute("UPDATE mirror_log SET attempts=?, next_retry_at=?, "
                                  "status=?, updated_at=? WHERE id=?",
                                  (attempts, int(time.time()) + backoff, status,
                                   int(time.time()), r["id"]))
        except Exception as e:
            log.warning("retry loop: %s", e)
