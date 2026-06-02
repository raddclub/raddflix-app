"""RaddFlix catalog sync API — Flutter app offline-first database.

Registered in app.py at /api/catalog prefix.

Endpoints:
  GET  /api/catalog/version              current version + count
  GET  /api/catalog/db_update/version    lightweight version check
  GET  /api/catalog/sync                 full or delta catalog (JSON)
  GET  /api/catalog/posters              poster URLs for pre-caching
  GET  /api/catalog/db_update            zero-rated db_update.json
  GET  /api/catalog/delta                Oracle fallback for JazzDrive delta sync
  GET  /api/catalog/share_url            single-file share URL lookup
  POST /api/catalog/share_url/batch      batch share URL lookup (up to 50 file_ids)
  GET  /api/catalog/share_url/batch      same via ?ids=1,2,3 query param
  GET  /api/catalog/play                 generate/return cached direct streaming URL
  GET  /api/catalog/poster/<id>          public poster proxy (redirect to JD or TMDB)
  GET  /api/catalog/poster-push/status   coverage report: which titles need JD posters
  POST /api/catalog/poster-push/bulk     bulk-upload all missing posters to JazzDrive
  GET  /api/catalog/poster-push/job/<id> check background push job status
"""
from __future__ import annotations
import base64
import json
import os
import threading
import time
import datetime
import logging
from flask import Blueprint, request, jsonify, redirect
from functools import wraps
from hub import db

log = logging.getLogger("hub.catalog_api")

bp = Blueprint("catalog_api", __name__, url_prefix="/api/catalog")

# BUG-A35: Flutter calls GET /watch/api/play/<file_id> — register /watch blueprint
bp_watch = Blueprint("watch_api", __name__, url_prefix="/watch")

_poster_push_jobs: dict = {}


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _watch_base() -> str:
    """Return the external watch-server base URL from DB settings.

    Falls back to 'http://92.4.95.252' so poster URLs are always absolute
    even if WATCH_SERVER_EXTERNAL_URL is not set in the DB.
    """
    try:
        v = (db.setting("WATCH_SERVER_EXTERNAL_URL") or "").strip()
        return (v or "http://92.4.95.252").rstrip("/")
    except Exception:
        return "http://92.4.95.252"


def _catalog_version() -> int:
    with db.conn() as c:
        row = c.execute(
            "SELECT MAX(updated_at) AS v FROM titles WHERE is_published=1"
        ).fetchone()
        return int(row["v"] or 0)


def _count_published() -> int:
    with db.conn() as c:
        row = c.execute(
            "SELECT COUNT(*) AS n FROM titles WHERE is_published=1"
        ).fetchone()
        return int(row["n"] or 0)


def _poster_jd_url(title_id: int, poster_share_url: str) -> str:
    """Return the best poster URL for the Flutter app.

    Priority:
      1. poster_share_url — direct JazzDrive file share URL (zero-rated, permanent)
      2. Oracle public proxy  /api/catalog/poster/<id>  (requires internet)
    """
    if poster_share_url:
        return poster_share_url
    return _watch_base() + "/api/catalog/poster/" + str(title_id)


def _check_admin_auth() -> bool:
    """Check Basic auth against RADD_ADMIN_USER / RADD_ADMIN_PASS env vars."""
    admin_user = os.environ.get("RADD_ADMIN_USER", "admin")
    admin_pass = os.environ.get("RADD_ADMIN_PASS", "")
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Basic "):
        try:
            decoded = base64.b64decode(auth[6:]).decode()
            u, _, p = decoded.partition(":")
            if u == admin_user and p == admin_pass:
                return True
        except Exception:
            pass
    return False


# ─────────────────────────────────────────────────────────────────────────────
# Auth guard for Oracle catalog endpoints
# Public catalog data lives on JazzDrive CDN (zero-rated, last-24h snapshot).
# Oracle serves the COMPLETE database — must be JWT-protected so only registered
# subscribers can download the full catalog. Zero-rating is unaffected because
# the zero-rated path uses JazzDrive CDN directly, never touching Oracle.
# ─────────────────────────────────────────────────────────────────────────────

def _catalog_require_auth(fn):
    """Decorator: require a valid Bearer access token on Oracle catalog routes.
    Injects _user_id and _phone kwargs into the wrapped function.
    Lazy-imports _verify_jwt from mobile_api to avoid circular import at module load.
    """
    @wraps(fn)
    def wrapper(*a, **kw):
        from hub.routes.mobile_api import _verify_jwt  # lazy — no circular import
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "auth required"}), 401
        payload = _verify_jwt(auth[7:])
        if not payload or payload.get("type") != "access":
            return jsonify({"error": "invalid or expired token"}), 401
        kw["_user_id"] = int(payload["sub"])
        kw["_phone"]   = payload.get("phone", "")
        return fn(*a, **kw)
    return wrapper


# ─────────────────────────────────────────────────────────────────────────────
# Core catalog endpoints
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/version")
def version():
    v = _catalog_version()
    resp = jsonify({"version": v, "count": _count_published()})
    resp.set_etag(str(v))
    resp.headers["Cache-Control"] = "max-age=60"
    return resp


@bp.route("/db_update/version")
def db_update_version():
    v = _catalog_version()
    return jsonify({"version": v, "count": _count_published()})


@bp.route("/sync")
@_catalog_require_auth
def sync(_user_id=None, _phone=None):
    since_raw = request.args.get("since", "0")
    try:
        since = int(since_raw)
    except (ValueError, TypeError):
        since = 0
    since_param = since if since > 0 else -1

    with db.conn() as c:
        title_rows = c.execute(
            """
            SELECT t.id, t.title, t.year, t.media_type, t.plot,
                   t.rating, t.genres, t.language, t.is_free, t.updated_at,
                   t.poster, t.poster_share_url, t.runtime, t.season_count, t.episode_count,
                   f.id AS file_id, f.share_url AS file_share_url
            FROM titles t
            LEFT JOIN files f ON f.title_id = t.id
              AND (f.season IS NULL OR f.season = 0)
            WHERE t.is_published = 1
              AND (t.updated_at IS NULL OR t.updated_at > ?)
            GROUP BY t.id
            ORDER BY t.updated_at DESC
            """, (since_param,)
        ).fetchall()

    titles = []
    title_ids = []
    for r in title_rows:
        title_ids.append(r["id"])
        genres = []
        try:
            genres = json.loads(r["genres"] or "[]")
            if not isinstance(genres, list):
                genres = [str(genres)]
        except Exception:
            pass
        psu = r["poster_share_url"] or ""
        titles.append({
            "id":              r["id"],
            "title":           r["title"] or "",
            "year":            (int(r["year"]) if r["year"] and str(r["year"]).isdigit() else None),
            "media_type":      ("show" if (r["media_type"] or "movie") in ("tv", "series") else (r["media_type"] or "movie")),
            "description":     r["plot"] or "",
            "rating":          r["rating"],
            "genres":          genres,
            "language":        r["language"] or "",
            "is_free":         1 if r["is_free"] else 0,
            "runtime":         r["runtime"],
            "season_count":    r["season_count"],
            "episode_count":   r["episode_count"],
            "poster_key":      "title_" + str(r["id"]),
            "poster_url":      r["poster"] or "",
            "poster_jd_url":   _poster_jd_url(r["id"], psu),
            "poster_share_url": psu,
            "db_version":      int(r["updated_at"] or 0),
            "file_id":         r["file_id"],
            "share_url":       r["file_share_url"] or "",
        })

    episodes = []
    if title_ids:
        placeholders = ",".join("?" * len(title_ids))
        with db.conn() as c:
            ep_rows = c.execute(
                "SELECT id, title_id, filename, season, episode, share_url "
                "FROM files "
                "WHERE title_id IN (" + placeholders + ") "
                "AND season IS NOT NULL AND season > 0 "
                "ORDER BY title_id, season, episode",
                title_ids
            ).fetchall()
        for r in ep_rows:
            episodes.append({
                "id":       r["id"],
                "title_id": r["title_id"],
                "file_id":  str(r["id"]),
                "season":   r["season"],
                "episode":  r["episode"],
                "label":    "S{:02d}E{:02d}".format(r["season"] or 0, r["episode"] or 0),
                "share_url": r["share_url"] or "",
                "is_free":  0,
            })

    return jsonify({"version": _catalog_version(), "titles": titles,
                    "episodes": episodes, "count": len(titles)})


@bp.route("/share_url")
@_catalog_require_auth
def get_share_url(_user_id=None, _phone=None):
    """GET /api/catalog/share_url?file_id=<id>  — single file share URL lookup."""
    file_id = request.args.get("file_id", "").strip()
    if not file_id:
        return jsonify({"error": "file_id required"}), 400
    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT f.share_url FROM files f "
                "JOIN titles t ON f.title_id = t.id "
                "WHERE f.id=? AND t.is_published=1",
                (file_id,)
            ).fetchone()
        if row and row["share_url"]:
            return jsonify({"ok": True, "share_url": row["share_url"]})
        return jsonify({"error": "not found"}), 404
    except Exception:
        log.exception("Error in get_share_url for file_id=%s", file_id)
        return jsonify({"error": "server error"}), 500


@bp.route("/share_url/batch", methods=["POST", "GET"])
@_catalog_require_auth
def batch_share_url(_user_id=None, _phone=None):
    """Resolve JazzDrive share_urls for multiple files in one request.

    POST /api/catalog/share_url/batch   body: {"file_ids": [1, 2, 3]}  (max 50)
    GET  /api/catalog/share_url/batch?ids=1,2,3
    """
    if request.method == "GET":
        ids_raw = request.args.get("ids", "")
        try:
            file_ids = [int(x.strip()) for x in ids_raw.split(",") if x.strip()]
        except (ValueError, TypeError):
            return jsonify({"error": "ids must be comma-separated integers"}), 400
    else:
        data = request.get_json(force=True, silent=True) or {}
        raw_ids = data.get("file_ids") or []
        try:
            file_ids = [int(x) for x in raw_ids]
        except (TypeError, ValueError):
            return jsonify({"error": "file_ids must be a list of integers"}), 400

    if not file_ids:
        return jsonify({"error": "file_ids required"}), 400
    if len(file_ids) > 50:
        return jsonify({"error": "max 50 file_ids per request"}), 400

    try:
        placeholders = ",".join("?" * len(file_ids))
        with db.conn() as c:
            rows = c.execute(
                "SELECT f.id, f.share_url FROM files f "
                "JOIN titles t ON f.title_id = t.id "
                "WHERE f.id IN (" + placeholders + ") AND t.is_published=1",
                file_ids
            ).fetchall()
        results = {str(r["id"]): r["share_url"] or None for r in rows}
        for fid in file_ids:
            results.setdefault(str(fid), None)
        found = sum(1 for v in results.values() if v)
        return jsonify({"ok": True, "results": results, "found": found,
                        "requested": len(file_ids)})
    except Exception:
        log.exception("Error in batch_share_url")
        return jsonify({"error": "server error"}), 500


def _do_play(file_id: int):
    """Shared play logic — generate/return cached stream URL for a file.
    Called by both /api/catalog/play and /watch/api/play/<file_id> (BUG-A35).
    Returns a Flask Response."""
    try:
        cached = db.get_stream_link(file_id)
        if cached:
            return jsonify({
                "ok":        True,
                "file_id":   file_id,
                "direct_url": cached["download_url"],
                "expires_at": cached["expires_at"],
                "cached":    True,
            })

        with db.conn() as c:
            row = c.execute(
                "SELECT f.id, f.filename, f.share_url, f.account_id, "
                "       f.season, f.episode, t.title "
                "FROM files f JOIN titles t ON f.title_id = t.id "
                "WHERE f.id=? AND t.is_published=1",
                (file_id,)
            ).fetchone()

        if not row:
            return jsonify({"error": "file not found"}), 404
        if not row["share_url"]:
            return jsonify({"error": "no share_url for this file"}), 404

        from hub import jazzdrive
        res = jazzdrive.generate_direct_link(row["share_url"], row["filename"])
        if not res.get("ok"):
            return jsonify({"error": res.get("error") or "failed to generate link"}), 502

        direct_url = res["direct_link"]
        expires_in = 28800
        db.save_stream_link(file_id, direct_url,
                            expires_in=expires_in,
                            account_id=row["account_id"])

        label = None
        s = row["season"]
        e = row["episode"]
        if s and e:
            label = "S{:02d}E{:02d}".format(s or 0, e or 0)

        return jsonify({
            "ok":         True,
            "file_id":    file_id,
            "direct_url": direct_url,
            "expires_at": int(time.time()) + expires_in,
            "cached":     False,
            "title":      row["title"],
            "label":      label,
            "size_bytes": res.get("size_bytes"),
        })
    except Exception:
        log.exception("Error in play for file_id=%s", file_id)
        return jsonify({"error": "server error"}), 500


@bp.route("/play")
@_catalog_require_auth
def play(_user_id=None, _phone=None):
    """GET /api/catalog/play?file_id=<id>  — generate/return cached streaming URL."""
    file_id_str = request.args.get("file_id", "").strip()
    if not file_id_str:
        return jsonify({"error": "file_id required"}), 400
    try:
        file_id = int(file_id_str)
    except ValueError:
        return jsonify({"error": "invalid file_id"}), 400
    return _do_play(file_id)


@bp_watch.route("/api/play/<int:file_id>")
@_catalog_require_auth
def watch_play(file_id, _user_id=None, _phone=None):
    """BUG-A35: Flutter legacy path GET /watch/api/play/<file_id>.
    Delegates to shared _do_play() logic."""
    return _do_play(file_id)


@bp.route("/posters")
def posters():
    """GET /api/catalog/posters  — poster list for pre-caching."""
    with db.conn() as c:
        rows = c.execute(
            "SELECT id, poster, poster_share_url "
            "FROM titles WHERE is_published=1 AND poster IS NOT NULL"
        ).fetchall()
    return jsonify({"posters": [
        {
            "key":         "title_" + str(r["id"]),
            "url":         r["poster"],
            "jd_url":      r["poster_share_url"] or "",
            "poster_jd_url": _poster_jd_url(r["id"], r["poster_share_url"] or ""),
        }
        for r in rows if r["poster"]
    ]})


@bp.route("/db_update")
@_catalog_require_auth
def db_update(_user_id=None, _phone=None):
    now = int(time.time())
    with db.conn() as c:
        title_rows = c.execute(
            "SELECT t.id, t.title, t.year, t.media_type, t.plot, "
            "       t.rating, t.genres, t.language, t.is_free, t.updated_at, "
            "       t.poster, t.poster_share_url, t.runtime, t.season_count, t.episode_count, "
            "       f.id AS file_id, f.share_url AS file_share_url "
            "FROM titles t "
            "LEFT JOIN files f ON f.title_id = t.id "
            "  AND (f.season IS NULL OR f.season = 0) "
            "WHERE t.is_published = 1 "
            "GROUP BY t.id ORDER BY t.id"
        ).fetchall()

    title_ids, titles_out = [], []
    for r in title_rows:
        title_ids.append(r["id"])
        genres = []
        try:
            genres = json.loads(r["genres"] or "[]")
            if not isinstance(genres, list):
                genres = [str(genres)]
        except Exception:
            pass
        psu = r["poster_share_url"] or ""
        titles_out.append({
            "id":              r["id"],
            "title":           r["title"] or "",
            "year":            (int(r["year"]) if r["year"] and str(r["year"]).isdigit() else None),
            "media_type":      ("show" if (r["media_type"] or "movie") in ("tv", "series") else (r["media_type"] or "movie")),
            "description":     r["plot"] or "",
            "rating":          r["rating"],
            "genres":          genres,
            "language":        r["language"] or "",
            "is_free":         1 if r["is_free"] else 0,
            "runtime":         r["runtime"],
            "poster_url":      r["poster"] or "",
            "poster_jd_url":   _poster_jd_url(r["id"], psu),
            "poster_share_url": psu,
            "db_version":      int(r["updated_at"] or 0),
            "file_id":         str(r["file_id"]) if r["file_id"] is not None else None,
            "share_url":       r["file_share_url"] or "",
        })

    episodes_out = []
    if title_ids:
        placeholders = ",".join("?" * len(title_ids))
        with db.conn() as c:
            ep_rows = c.execute(
                "SELECT id, title_id, filename, season, episode, share_url "
                "FROM files WHERE title_id IN (" + placeholders + ") "
                "AND season IS NOT NULL AND season > 0 "
                "ORDER BY title_id, season, episode",
                title_ids
            ).fetchall()
        for r in ep_rows:
            episodes_out.append({
                "id":       r["id"],
                "title_id": r["title_id"],
                "file_id":  str(r["id"]),
                "season":   r["season"],
                "episode":  r["episode"],
                "label":    "S{:02d}E{:02d}".format(r["season"] or 0, r["episode"] or 0),
                "share_url": r["share_url"] or "",
                "quality":  None,
                "is_free":  0,
            })

    catalog_version = _catalog_version() or now
    response = jsonify({
        "version":      catalog_version,
        "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "titles":       titles_out,
        "episodes":     episodes_out,
    })
    response.headers["Content-Disposition"] = "attachment; filename=db_update.json"
    response.headers["Cache-Control"] = "no-cache"
    return response


@bp.route("/delta")
@_catalog_require_auth
def delta(_user_id=None, _phone=None):
    """GET /api/catalog/delta — Oracle fallback for Flutter SyncService._syncFromJazzDriveDelta()."""
    now = int(time.time())
    with db.conn() as c:
        title_rows = c.execute(
            "SELECT t.id, t.title, t.year, t.media_type, t.plot, "
            "       t.rating, t.genres, t.language, t.is_free, t.updated_at, "
            "       t.poster, t.poster_share_url, t.runtime, t.season_count, t.episode_count, "
            "       f.id AS file_id, f.share_url AS file_share_url "
            "FROM titles t "
            "LEFT JOIN files f ON f.title_id = t.id "
            "  AND (f.season IS NULL OR f.season = 0) "
            "WHERE t.is_published = 1 "
            "GROUP BY t.id ORDER BY t.id"
        ).fetchall()

    title_ids, titles_out = [], []
    for r in title_rows:
        title_ids.append(r["id"])
        genres = []
        try:
            genres = json.loads(r["genres"] or "[]")
            if not isinstance(genres, list):
                genres = [str(genres)]
        except Exception:
            pass
        psu = r["poster_share_url"] or ""
        titles_out.append({
            "id":              r["id"],
            "title":           r["title"] or "",
            "year":            (int(r["year"]) if r["year"] and str(r["year"]).isdigit() else None),
            "media_type":      ("show" if (r["media_type"] or "movie") in ("tv", "series") else (r["media_type"] or "movie")),
            "description":     r["plot"] or "",
            "rating":          r["rating"],
            "genres":          genres,
            "language":        r["language"] or "",
            "is_free":         1 if r["is_free"] else 0,
            "runtime":         r["runtime"],
            "poster_url":      r["poster"] or "",
            "poster_jd_url":   _poster_jd_url(r["id"], psu),
            "poster_share_url": psu,
            "db_version":      int(r["updated_at"] or 0),
            "file_id":         str(r["file_id"]) if r["file_id"] is not None else None,
            "share_url":       r["file_share_url"] or "",
        })

    episodes_out = []
    if title_ids:
        placeholders = ",".join("?" * len(title_ids))
        with db.conn() as c:
            ep_rows = c.execute(
                "SELECT id, title_id, filename, season, episode, share_url "
                "FROM files WHERE title_id IN (" + placeholders + ") "
                "AND season IS NOT NULL AND season > 0 "
                "ORDER BY title_id, season, episode",
                title_ids
            ).fetchall()
        for r in ep_rows:
            episodes_out.append({
                "id":       r["id"],
                "title_id": r["title_id"],
                "file_id":  str(r["id"]),
                "season":   r["season"],
                "episode":  r["episode"],
                "label":    "S{:02d}E{:02d}".format(r["season"] or 0, r["episode"] or 0),
                "share_url": r["share_url"] or "",
                "quality":  None,
                "is_free":  0,
            })

    catalog_version = _catalog_version() or now
    return jsonify({
        "version":      catalog_version,
        "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "titles":       titles_out,
        "episodes":     episodes_out,
    })


# ─────────────────────────────────────────────────────────────────────────────
# Public poster proxy  (no auth — poster images are not streaming secrets)
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/poster/<int:title_id>")
def public_poster(title_id: int):
    """GET /api/catalog/poster/<id>
    Public poster proxy — no auth required.

    Resolution order:
      1. poster_share_url → calls JazzDrive generate_direct_link → 302 redirect
         (This gives a time-limited but zero-rated direct JD image URL)
      2. poster (TMDB URL)   → 302 redirect  (needs internet bundle)
      3. 404
    """
    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT id, poster, poster_share_url FROM titles WHERE id=? AND is_published=1",
                (title_id,)
            ).fetchone()
    except Exception:
        log.exception("poster lookup error for title %d", title_id)
        return jsonify({"error": "server error"}), 500

    if not row:
        return jsonify({"error": "title not found"}), 404

    psu = row["poster_share_url"] or ""
    if psu:
        try:
            from hub import jazzdrive
            res = jazzdrive.generate_folder_image_link(psu, filename_hint="poster")
            if res.get("ok") and res.get("url"):
                return redirect(res["url"], code=302)
        except Exception as e:
            log.warning("poster proxy JD link error for title %d: %s", title_id, e)

    if row["poster"]:
        return redirect(row["poster"], code=302)

    return jsonify({"error": "no poster available"}), 404


# ─────────────────────────────────────────────────────────────────────────────
# Poster Push — bulk upload title posters to JazzDrive
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/poster-push/status")
def poster_push_status():
    """GET /api/catalog/poster-push/status
    Coverage report: which published titles have JD-hosted posters.
    Public (no auth) — just shows upload coverage, no secrets.
    """
    with db.conn() as c:
        rows = c.execute(
            "SELECT id, title, poster, poster_share_url "
            "FROM titles WHERE is_published=1 ORDER BY id"
        ).fetchall()

    result = []
    for r in rows:
        psu = r["poster_share_url"] or ""
        result.append({
            "id":              r["id"],
            "title":           r["title"],
            "has_tmdb_poster": bool(r["poster"]),
            "has_jd_poster":   bool(psu),
            "poster_share_url": psu or None,
        })

    needs = sum(1 for r in result if r["has_tmdb_poster"] and not r["has_jd_poster"])
    running_jobs = {jid: j for jid, j in _poster_push_jobs.items() if j["status"] == "running"}

    return jsonify({
        "ok":           True,
        "total":        len(result),
        "has_jd_poster": sum(1 for r in result if r["has_jd_poster"]),
        "needs_upload": needs,
        "active_jobs":  len(running_jobs),
        "titles":       result,
    })


@bp.route("/poster-push/bulk", methods=["POST"])
def poster_push_bulk():
    """POST /api/catalog/poster-push/bulk  (admin Basic auth required)
    Bulk-upload posters for all published titles that have a TMDB poster_url
    but are missing poster_share_url on JazzDrive.

    Runs in a background thread.  Returns a job_id to poll via
    GET /api/catalog/poster-push/job/<job_id>

    Optional body: {"force": true}  to re-upload even if poster_share_url exists.
    """
    if not _check_admin_auth():
        return jsonify({"error": "admin auth required (Basic)"}), 401

    data = request.get_json(force=True, silent=True) or {}
    force = bool(data.get("force", False))

    if force:
        with db.conn() as c:
            rows = c.execute(
                "SELECT id, title, poster, year, media_type FROM titles "
                "WHERE is_published=1 AND poster IS NOT NULL"
            ).fetchall()
    else:
        with db.conn() as c:
            rows = c.execute(
                "SELECT id, title, poster, year, media_type FROM titles "
                "WHERE is_published=1 AND poster IS NOT NULL "
                "AND (poster_share_url IS NULL OR poster_share_url='')"
            ).fetchall()

    if not rows:
        return jsonify({"ok": True, "message": "All published titles already have JD posters", "pushed": 0})

    from hub import uploader as _up
    acct = _up.get_active_account()
    if not acct:
        return jsonify({"error": "No active JazzDrive account — add one in Scanner"}), 503

    account_id = acct["id"]
    job_id = str(int(time.time()))
    _poster_push_jobs[job_id] = {
        "status":     "running",
        "total":      len(rows),
        "done":       0,
        "failed":     0,
        "errors":     [],
        "started_at": int(time.time()),
        "finished_at": None,
    }

    def _worker(rows, account_id, job_id):
        from hub import assets
        job = _poster_push_jobs[job_id]
        for r in rows:
            if job.get("stop_requested"):
                break
            try:
                result = assets.process_title_poster(r["id"], r["poster"], account_id)
                if result:
                    job["done"] += 1
                    log.info("poster-push: %s → JD ok (%s…)", r["title"], str(result)[:50])
                else:
                    job["failed"] += 1
                    job["errors"].append({
                        "title_id": r["id"], "title": r["title"],
                        "error": "process_title_poster returned None"
                    })
            except Exception as e:
                job["failed"] += 1
                job["errors"].append({"title_id": r["id"], "title": r["title"], "error": str(e)})
                log.exception("poster-push failed for title %d (%s)", r["id"], r["title"])
        job["status"] = "done"
        job["finished_at"] = int(time.time())
        elapsed = job["finished_at"] - job["started_at"]
        log.info("poster-push job %s complete: %d ok / %d failed in %ds",
                 job_id, job["done"], job["failed"], elapsed)

    t = threading.Thread(
        target=_worker,
        args=([dict(r) for r in rows], account_id, job_id),
        daemon=True,
        name="poster-push-" + job_id,
    )
    t.start()

    return jsonify({
        "ok":      True,
        "job_id":  job_id,
        "total":   len(rows),
        "message": "Uploading {} poster{} to JazzDrive in background".format(
            len(rows), "s" if len(rows) != 1 else ""
        ),
    })


@bp.route("/poster-push/job/<job_id>")
def poster_push_job(job_id: str):
    """GET /api/catalog/poster-push/job/<job_id>  — poll background push job."""
    job = _poster_push_jobs.get(job_id)
    if not job:
        return jsonify({"error": "job not found — may have expired after server restart"}), 404
    pct = round(100 * job["done"] / max(job["total"], 1))
    return jsonify({
        "ok":         True,
        "job_id":     job_id,
        "status":     job["status"],
        "total":      job["total"],
        "done":       job["done"],
        "failed":     job["failed"],
        "pct":        pct,
        "errors":     job["errors"][-10:],
        "started_at": job["started_at"],
        "finished_at": job["finished_at"],
    })


@bp.route("/poster-push/job/<job_id>/stop", methods=["POST"])
def poster_push_stop(job_id: str):
    """POST /api/catalog/poster-push/job/<job_id>/stop  — gracefully stop a running job."""
    job = _poster_push_jobs.get(job_id)
    if not job:
        return jsonify({"error": "job not found"}), 404
    job["stop_requested"] = True
    return jsonify({"ok": True, "message": "Stop requested"})
