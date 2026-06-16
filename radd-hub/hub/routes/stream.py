"""Search + download UI — includes queue CRUD, job controls, settings, and per-job logs.

v3.0 additions:
  - queue_add: parses year_hint / lang_hint from movie name via query_parser
  - queue_list: overlays year_hint / lang_hint / stage from in-memory job data
  - _DOMAIN_SETTINGS_KEYS: includes hdhub4u and moviesdrive
"""
from __future__ import annotations
import time
import uuid
from flask import Blueprint, render_template, request, jsonify
from .. import db, auth
from .. import downloader as dl

bp = Blueprint("stream", __name__)


# ─────────────────────────────────────────────
# Page
# ─────────────────────────────────────────────

@bp.route("/")
@auth.login_required
def page():
    return render_template("stream.html")


# ─────────────────────────────────────────────
# Queue list + add
# ─────────────────────────────────────────────

@bp.route("/api/queue")
@auth.login_required
def queue_list():
    with db.conn() as c:
        rows = [dict(r) for r in c.execute(
            "SELECT id, job_id, movie, site, status, progress, message, url, created_at, updated_at "
            "FROM queue ORDER BY id DESC LIMIT 200"
        ).fetchall()]
    # Overlay real-time in-memory status + enriched fields
    for row in rows:
        live = dl.get_active_job(row["job_id"])
        if live:
            row["status"]      = live.get("status",      row["status"])
            row["progress"]    = live.get("progress",    row["progress"])
            row["stage"]       = live.get("stage",       "")
            row["year_hint"]   = live.get("year_hint")
            row["lang_hint"]   = live.get("lang_hint")
            row["movie_clean"] = live.get("movie_clean", row["movie"])
        else:
            row.setdefault("stage",       "")
            row.setdefault("year_hint",   None)
            row.setdefault("lang_hint",   None)
            row.setdefault("movie_clean", row["movie"])
    return jsonify(rows)


@bp.route("/api/queue", methods=["POST"])
@auth.login_required
def queue_add():
    data  = request.get_json(force=True, silent=True) or request.form
    movie = (data.get("movie") or "").strip()
    site  = (data.get("site")  or "auto").strip()
    if not movie:
        return jsonify({"error": "movie required"}), 400

    # Parse query for hints
    parsed = dl.parse_movie_query(movie)
    if isinstance(parsed, dict):
        year_hint  = parsed.get("year_hint")
        lang_hint  = parsed.get("lang_hint")
        clean_name = parsed.get("clean", movie)
    else:
        year_hint  = getattr(parsed, "year", None)
        lang_hint  = getattr(parsed, "lang_hint", None)
        clean_name = getattr(parsed, "clean", movie)

    # --- Duplicate Check ---
    dup = db.check_duplicate(clean_name, year_hint)
    if dup:
        if dup["reason"] == "library":
            return jsonify({
                "ok": True,
                "skipped": [{"movie": movie, "reason": "already in library"}],
                "existing_title_id": dup["title_id"]
            })
        else:
            return jsonify({
                "ok": True,
                "skipped": [{"movie": movie, "reason": "already in queue"}],
                "job_id": dup["job_id"],
                "status": dup["status"]
            })
    # -----------------------

    jid = uuid.uuid4().hex[:10]
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO queue(job_id,movie,site,status,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            (jid, movie, site, "queued", now, now)
        )
    return jsonify({
        "ok":       True,
        "job_id":   jid,
        "year_hint": year_hint,
        "lang_hint": lang_hint,
        "movie_clean": clean_name,
    })


# ─────────────────────────────────────────────
# Per-job controls
# ─────────────────────────────────────────────

@bp.route("/api/queue/<job_id>/cancel", methods=["POST"])
@auth.login_required
def job_cancel(job_id):
    ok = dl.cancel_job(job_id)
    return jsonify({"ok": ok, "job_id": job_id})


@bp.route("/api/queue/<job_id>/pause", methods=["POST"])
@auth.login_required
def job_pause(job_id):
    ok = dl.pause_job(job_id)
    if not ok:
        with db.conn() as c:
            c.execute(
                "UPDATE queue SET status='paused', updated_at=? WHERE job_id=? "
                "AND status IN ('queued','processing')",
                (int(time.time()), job_id)
            )
        ok = True
    return jsonify({"ok": ok, "job_id": job_id})


@bp.route("/api/queue/<job_id>/resume", methods=["POST"])
@auth.login_required
def job_resume(job_id):
    ok = dl.resume_job(job_id)
    return jsonify({"ok": ok, "job_id": job_id})


@bp.route("/api/queue/<job_id>/retry", methods=["POST"])
@auth.login_required
def job_retry(job_id):
    ok = dl.retry_job(job_id)
    return jsonify({"ok": ok, "job_id": job_id})


@bp.route("/api/queue/<job_id>", methods=["DELETE"])
@auth.login_required
def job_remove(job_id):
    dl.remove_job(job_id)
    return jsonify({"ok": True, "job_id": job_id})


# ─────────────────────────────────────────────
# Per-job log
# ─────────────────────────────────────────────

@bp.route("/api/queue/<job_id>/log")
@auth.login_required
def job_log(job_id):
    log_text = dl.get_job_log(job_id)
    return jsonify({"log": log_text, "job_id": job_id})


# ─────────────────────────────────────────────
# Bulk controls
# ─────────────────────────────────────────────

@bp.route("/api/queue/cancel-all", methods=["POST"])
@auth.login_required
def bulk_cancel():
    n = dl.cancel_all_jobs()
    return jsonify({"ok": True, "affected": n})


@bp.route("/api/queue/remove-cancelled", methods=["POST"])
@auth.login_required
def bulk_remove_cancelled():
    n = dl.remove_cancelled_jobs()
    return jsonify({"ok": True, "removed": n})


@bp.route("/api/queue/pause-all", methods=["POST"])
@auth.login_required
def bulk_pause():
    n = dl.pause_all_jobs()
    return jsonify({"ok": True, "affected": n})


@bp.route("/api/queue/resume-all", methods=["POST"])
@auth.login_required
def bulk_resume():
    n = dl.resume_all_jobs()
    return jsonify({"ok": True, "affected": n})


@bp.route("/api/queue/clear-done", methods=["POST"])
@auth.login_required
def clear_done():
    with db.conn() as c:
        n = c.execute(
            "DELETE FROM queue WHERE status IN ('done','cancelled')"
        ).rowcount
    return jsonify({"ok": True, "deleted": n})


# ─────────────────────────────────────────────
# Results (completed jobs with links)
# ─────────────────────────────────────────────

@bp.route("/api/results")
@auth.login_required
def results():
    rows = dl.get_results()
    return jsonify(rows)


# ─────────────────────────────────────────────
# Download settings (get / save)
# ─────────────────────────────────────────────

_DL_SETTINGS_KEYS = [
    "auto_download", "download_dir", "headless", "max_parallel",
    "preferred_quality", "preferred_language", "content_type",
]
_DOMAIN_SETTINGS_KEYS = [
    "domain_vegamovies", "domain_katmoviehd", "domain_rogmovies",
    "domain_ssrmovies",  "domain_rareanimes",
    "domain_hdhub4u",    "domain_moviesdrive",
    "domain_nexdrive",   "domain_vcloud",
]

_ALL_SETTINGS_KEYS = _DL_SETTINGS_KEYS + _DOMAIN_SETTINGS_KEYS


@bp.route("/api/settings")
@auth.login_required
def get_dl_settings():
    result = {}
    for k in _ALL_SETTINGS_KEYS:
        result[k] = db.setting(k, "")
    # Defaults
    if not result.get("auto_download"):       result["auto_download"]       = "1"
    if not result.get("headless"):            result["headless"]            = "1"
    if not result.get("max_parallel"):        result["max_parallel"]        = "2"
    if not result.get("preferred_quality"):   result["preferred_quality"]   = "1080p"
    if not result.get("preferred_language"):  result["preferred_language"]  = "Hindi"
    if not result.get("content_type"):        result["content_type"]        = "any"
    return jsonify(result)


@bp.route("/api/settings", methods=["POST"])
@auth.login_required
def save_dl_settings():
    data = request.get_json(force=True, silent=True) or {}
    saved = {}
    for k in _ALL_SETTINGS_KEYS:
        if k in data:
            v = str(data[k]).strip()
            db.set_setting(k, v)
            saved[k] = v
    return jsonify({"ok": True, "saved": saved})



# ─────────────────────────────────────────────────────────────────────────────
# Direct URL download  (paste a link — skip the scraping pipeline entirely)
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/api/queue/direct", methods=["POST"])
@auth.login_required
def queue_direct():
    """Queue one or more direct download URLs without scraping.

    Body JSON: { urls: "http://…\nhttp://…", name: "Movie Title" }
    Each non-empty line becomes its own queue job with site='direct'.
    The existing post-processing pipeline (ZIP extract → split → JazzDrive upload)
    runs exactly the same as for regular downloads.
    """
    import re as _re
    import urllib.parse as _up

    data  = request.get_json(force=True, silent=True) or {}
    raw   = (data.get("urls") or data.get("url") or "").strip()
    urls  = [u.strip() for u in raw.splitlines() if u.strip()]
    name  = (data.get("name") or "").strip()

    if not urls:
        return jsonify({"ok": False, "error": "At least one URL is required"}), 400

    # Auto-derive a display name from the first URL when the user left it blank
    if not name:
        try:
            path_part = _up.unquote(_up.urlparse(urls[0]).path)
            stem = path_part.rstrip("/").split("/")[-1]
            stem = _re.sub(r"\.\w{1,5}$", "", stem)           # strip extension
            name = _re.sub(r"[._\-]+", " ", stem).strip()       # spaces
        except Exception:
            pass
        if not name:
            name = "Direct Download"

    now    = int(time.time())
    queued: list[dict] = []
    skipped: list[dict] = []

    # BUG-3 fix: Check for duplicates before queuing direct downloads
    dup = db.check_duplicate(name)
    if dup:
        if dup["reason"] == "library":
            return jsonify({
                "ok": True,
                "skipped": [{"name": name, "reason": "already in library"}],
                "existing_title_id": dup.get("title_id")
            })
        elif dup["reason"] == "queue":
            return jsonify({
                "ok": True,
                "skipped": [{"name": name, "reason": "already in queue"}],
                "job_id": dup.get("job_id"),
                "status": dup.get("status")
            })

    with db.conn() as c:
        for url in urls:
            jid = uuid.uuid4().hex[:10]
            c.execute(
                "INSERT INTO queue(job_id, movie, url, site, status, created_at, updated_at) "
                "VALUES (?,?,?,?,?,?,?)",
                (jid, name, url, "direct", "queued", now, now),
            )
            queued.append({"job_id": jid, "url": url})

    return jsonify({"ok": True, "queued": len(queued), "jobs": queued, "name": name})

# ─────────────────────────────────────────────
# Batch queue (add many movies at once)
# ─────────────────────────────────────────────

@bp.route("/api/queue/batch", methods=["POST"])
@auth.login_required
def queue_batch():
    data   = request.get_json(force=True, silent=True) or {}
    movies = data.get("movies") or []
    site   = (data.get("site") or "auto").strip()
    if not movies:
        return jsonify({"error": "movies list required"}), 400
    now   = int(time.time())
    count = 0
    skipped = 0
    with db.conn() as c:
        for movie in movies:
            movie = (movie or "").strip()
            if not movie:
                continue
            # BUG-4 fix: Check for duplicates before queuing each movie
            dup = db.check_duplicate(movie)
            if dup:
                skipped += 1
                continue
            jid = uuid.uuid4().hex[:10]
            c.execute(
                "INSERT INTO queue(job_id,movie,site,status,created_at,updated_at) "
                "VALUES(?,?,?,?,?,?)",
                (jid, movie, site, "queued", now, now)
            )
            count += 1
    return jsonify({"ok": True, "queued": count, "skipped": skipped})


# ─────────────────────────────────────────────
# Search (lightweight — returns sites to queue from)
# ─────────────────────────────────────────────

@bp.route("/api/search")
@auth.login_required
def search_sites():
    q    = (request.args.get("q")    or "").strip()
    year = (request.args.get("year") or "").strip()
    if not q:
        return jsonify({"error": "q required"}), 400
    query = f"{q} {year}".strip() if year else q
    from .. import sites as _sites
    plugins = _sites.list_plugins()
    results = [
        {
            "title": query,
            "site":  p["name"],
            "year":  year or None,
            "links": [],
        }
        for p in plugins
    ]
    return jsonify({"results": results, "query": query})


# ─────────────────────────────────────────────
# App log (last N lines — global, for debug)
# ─────────────────────────────────────────────

@bp.route("/api/logs")
@auth.login_required
def app_logs():
    from pathlib import Path
    from .. import config as _cfg
    log_file = _cfg.LOG_DIR / "raddhub.log"
    if not log_file.exists():
        return jsonify({"logs": "No logs yet."})
    try:
        lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
        return jsonify({"logs": "\n".join(lines[-100:])})
    except Exception as e:
        return jsonify({"logs": f"Error reading logs: {e}"})
