"""
hub/routes/delta_push.py — JazzDrive delta.json generator + uploader

Generates a delta.json with episodes NESTED inside each title (the format
Flutter's _syncFromJazzDriveDelta() actually reads), validates nothing
critical is null, uploads to JazzDrive, and sets jd_delta_url in the DB.

Blueprint: POST /api/catalog/delta-push/trigger  (admin Basic auth)
           GET  /api/catalog/delta-push/status

Background thread: checks every 6h if catalog version changed → regenerates.
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
import threading
import time
import datetime
from pathlib import Path

from flask import Blueprint, jsonify, request
from hub import db

log = logging.getLogger("hub.delta_push")

bp = Blueprint("delta_push", __name__, url_prefix="/api/catalog/delta-push")

# ── State ─────────────────────────────────────────────────────────────────────
_state = {
    "last_upload_at":   None,   # epoch int
    "last_share_url":   None,   # str
    "last_version":     None,   # int — catalog version at last upload
    "last_error":       None,   # str
    "running":          False,
}
_state_lock = threading.Lock()

# ── Core: generate delta.json (nested format Flutter expects) ─────────────────

def generate_delta_json(out_path: str | Path) -> dict:
    """
    Build delta.json and write it to out_path.

    Format:
      {
        "version": <int>,
        "generated_at": "<ISO UTC>",
        "titles": [
          {
            "id", "title", "year", "media_type", "description",
            "rating", "genres", "language", "is_free", "db_version",
            "status", "is_ongoing", "poster_url", "poster_share_url",
            "share_url",        ← movie file's share_url (empty str for shows)
            "folder_share_url", ← from titles.folder_share_url
            "file_id",          ← str(file.id) for movies, null for shows
            "episodes": [       ← NESTED (not flat) — what Flutter reads
              { "id","file_id","season","episode","label",
                "quality","is_free","share_url" }
            ]
          }
        ]
      }

    Validation: asserts every movie has non-empty share_url + file_id,
    every episode has non-empty share_url. Logs warnings on violations.
    Returns {"ok": True, "title_count": N, "episode_count": M, "path": "..."}
    """
    out_path = Path(out_path)
    now_ts   = int(time.time())

    with db.conn() as c:
        # ── 1. All published titles (one row per title — movies get their movie file) ──
        title_rows = c.execute(
            """
            SELECT t.id, t.title, t.year, t.media_type, t.plot,
                   t.rating, t.genres, t.language,
                   t.is_free, t.updated_at, t.poster, t.status,
                   t.is_ongoing, t.folder_share_url, t.poster_share_url
            FROM titles t
            WHERE t.is_published = 1
            ORDER BY t.id
            """
        ).fetchall()

        # ── 2. Movie files (season IS NULL or 0 — one file per movie) ──
        movie_file_rows = c.execute(
            """
            SELECT f.id AS file_id, f.title_id, f.share_url, f.quality
            FROM files f
            JOIN titles t ON f.title_id = t.id
            WHERE t.is_published = 1
              AND (f.season IS NULL OR f.season = 0 OR f.season = '')
            GROUP BY f.title_id
            ORDER BY f.id
            """
        ).fetchall()
        # Map: title_id → {file_id, share_url, quality}
        movie_file_map: dict[int, dict] = {}
        for r in movie_file_rows:
            movie_file_map[r["title_id"]] = {
                "file_id":   str(r["file_id"]),
                "share_url": r["share_url"] or "",
                "quality":   r["quality"] or None,
            }

        # ── 3. All episode files (season > 0) ──
        ep_rows = c.execute(
            """
            SELECT f.id, f.title_id, f.season, f.episode, f.share_url, f.quality,
                   f.is_ready
            FROM files f
            JOIN titles t ON f.title_id = t.id
            WHERE t.is_published = 1
              AND f.season IS NOT NULL AND f.season > 0
            ORDER BY f.title_id, f.season, f.episode, f.id
            """
        ).fetchall()
        # Map: title_id → list of episode dicts
        eps_by_title: dict[int, list] = {}
        for r in ep_rows:
            eps_by_title.setdefault(r["title_id"], []).append(dict(r))

    # ── 4. Build titles list ─────────────────────────────────────────────────
    titles_out = []
    total_eps  = 0
    warn_count = 0

    for r in title_rows:
        tid = r["id"]

        # Normalize media_type
        mt_raw = (r["media_type"] or "movie").lower().strip()
        if mt_raw in ("tv", "series", "show", "tvshow"):
            media_type = "show"
        else:
            media_type = "movie"

        # Parse genres → always a JSON-encoded list string
        genres_raw = r["genres"] or "[]"
        try:
            genres_list = json.loads(genres_raw)
            if not isinstance(genres_list, list):
                genres_list = [str(genres_list)]
        except Exception:
            genres_list = []

        # Poster share URL
        psu = r["poster_share_url"] or ""

        # Movie file info
        mf = movie_file_map.get(tid, {})
        share_url        = mf.get("share_url", "") or ""
        file_id_str      = mf.get("file_id")          # None for shows
        folder_share_url = r["folder_share_url"] or ""

        # ── Episodes (nested) ────────────────────────────────────────────────
        episodes_out = []
        for ep in eps_by_title.get(tid, []):
            ep_share_url = ep["share_url"] or ""
            if not ep_share_url:
                log.warning(
                    "delta_push: EMPTY share_url — title_id=%d ep file_id=%d S%02dE%02d",
                    tid, ep["id"], ep["season"] or 0, ep["episode"] or 0
                )
                warn_count += 1

            episodes_out.append({
                "id":       ep["id"],
                "file_id":  str(ep["id"]),
                "season":   ep["season"],
                "episode":  ep["episode"],
                "label":    "S{:02d}E{:02d}".format(ep["season"] or 0, ep["episode"] or 0),
                "quality":  ep["quality"] or None,
                "is_free":  0,          # episodes inherit title is_free; keep 0 for safety
                "share_url": ep_share_url,
            })
        total_eps += len(episodes_out)

        # ── Validation: movies must have share_url + file_id ────────────────
        if media_type == "movie":
            if not share_url:
                log.warning("delta_push: EMPTY share_url for movie title_id=%d (%s)", tid, r["title"])
                warn_count += 1
            if not file_id_str:
                log.warning("delta_push: NO file for movie title_id=%d (%s)", tid, r["title"])
                warn_count += 1

        titles_out.append({
            "id":              tid,
            "title":           r["title"] or "",
            "year":            (int(r["year"]) if r["year"] and str(r["year"]).isdigit() else None),
            "media_type":      media_type,
            "description":     r["plot"] or "",
            "rating":          float(r["rating"]) if r["rating"] is not None else None,
            "genres":          json.dumps(genres_list),   # stored as JSON string in SQLite
            "language":        r["language"] or "",
            "is_free":         1 if r["is_free"] else 0,
            "db_version":      int(r["updated_at"] or 0),
            "status":          r["status"] or "released",
            "is_ongoing":      1 if r["is_ongoing"] else 0,
            "poster_url":      r["poster"] or "",
            "poster_share_url": psu,
            "share_url":       share_url,
            "folder_share_url": folder_share_url,
            "file_id":         file_id_str,     # None for shows, str for movies
            "episodes":        episodes_out,    # nested list (empty for movies)
        })

    # ── 5. Catalog version (MAX updated_at of published titles) ──────────────
    with db.conn() as c:
        ver_row = c.execute(
            "SELECT MAX(updated_at) AS v FROM titles WHERE is_published=1"
        ).fetchone()
    catalog_version = int(ver_row["v"] or now_ts)

    # ── 6. Write JSON ─────────────────────────────────────────────────────────
    payload = {
        "version":      catalog_version,
        "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "title_count":  len(titles_out),
        "ep_count":     total_eps,
        "titles":       titles_out,
    }
    out_path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))

    size_kb = out_path.stat().st_size // 1024
    log.info(
        "delta_push: generated %d titles, %d episodes, %d warnings → %s (%d KB)",
        len(titles_out), total_eps, warn_count, out_path, size_kb
    )
    return {
        "ok":            True,
        "title_count":   len(titles_out),
        "episode_count": total_eps,
        "warnings":      warn_count,
        "catalog_version": catalog_version,
        "size_kb":       size_kb,
        "path":          str(out_path),
    }


# ── Core: upload to JazzDrive + set jd_delta_url in DB ───────────────────────

def upload_and_configure(delta_path: str | Path) -> dict:
    """
    Upload delta_path to JazzDrive using upload_json_to_jazzdrive().
    On success, store the share_url as jd_delta_url in the settings table.
    Returns {"ok": True/False, "share_url": "...", ...}
    """
    from hub import jazzdrive as jd
    delta_path = Path(delta_path)

    log.info("delta_push: uploading %s to JazzDrive …", delta_path.name)
    result = jd.upload_json_to_jazzdrive(delta_path)

    if not result.get("ok"):
        log.error("delta_push: upload failed — %s", result.get("error"))
        return result

    share_url = result.get("share_url") or ""
    if not share_url:
        log.error("delta_push: upload returned ok=True but no share_url — %s", result)
        return {"ok": False, "error": "Upload succeeded but no share_url returned", "raw": result}

    db.set_setting("jd_delta_url", share_url)
    log.info("delta_push: jd_delta_url set → %s", share_url)
    return {"ok": True, "share_url": share_url, "upload_result": result}


# ── Full pipeline ─────────────────────────────────────────────────────────────

def run_full_pipeline() -> dict:
    """Generate delta.json → upload → configure. Thread-safe."""
    with _state_lock:
        if _state["running"]:
            return {"ok": False, "error": "Pipeline already running"}
        _state["running"] = True

    try:
        with tempfile.NamedTemporaryFile(
            suffix=".json", prefix="delta_", delete=False
        ) as tf:
            tmp_path = Path(tf.name)

        # Step 1: Generate
        gen = generate_delta_json(tmp_path)
        if not gen.get("ok"):
            return gen

        # Step 2: Upload + configure
        up = upload_and_configure(tmp_path)
        if not up.get("ok"):
            return up

        share_url       = up["share_url"]
        catalog_version = gen["catalog_version"]

        with _state_lock:
            _state["last_upload_at"] = int(time.time())
            _state["last_share_url"] = share_url
            _state["last_version"]   = catalog_version
            _state["last_error"]     = None

        return {
            "ok":              True,
            "share_url":       share_url,
            "title_count":     gen["title_count"],
            "episode_count":   gen["episode_count"],
            "warnings":        gen["warnings"],
            "catalog_version": catalog_version,
            "size_kb":         gen["size_kb"],
        }

    except Exception as exc:
        log.exception("delta_push: pipeline error")
        with _state_lock:
            _state["last_error"] = str(exc)
        return {"ok": False, "error": str(exc)}

    finally:
        with _state_lock:
            _state["running"] = False
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass


# ── Background refresh loop ───────────────────────────────────────────────────

_REFRESH_INTERVAL = 6 * 3600   # 6 hours

def delta_refresh_loop():
    """
    Background thread: every 6 hours, check if catalog version changed.
    If yes (or no upload ever done), regenerate delta.json and re-upload.
    Registered with self_heal in app.py so it auto-restarts on crash.
    """
    log.info("delta_push: refresh loop started (interval=%dh)", _REFRESH_INTERVAL // 3600)
    time.sleep(30)   # wait for server to fully start

    while True:
        try:
            # Read current catalog version
            with db.conn() as c:
                row = c.execute(
                    "SELECT MAX(updated_at) AS v FROM titles WHERE is_published=1"
                ).fetchone()
            current_version = int(row["v"] or 0)

            with _state_lock:
                last_version    = _state["last_version"]
                last_upload_at  = _state["last_upload_at"]
                is_running      = _state["running"]

            needs_refresh = (
                is_running is False and (
                    last_version is None           # never uploaded
                    or last_upload_at is None
                    or current_version != last_version   # catalog changed
                    or (time.time() - last_upload_at) > _REFRESH_INTERVAL  # 6h elapsed
                )
            )

            if needs_refresh:
                log.info(
                    "delta_push: refreshing (current_v=%d, last_v=%s)",
                    current_version, last_version
                )
                result = run_full_pipeline()
                if result.get("ok"):
                    log.info(
                        "delta_push: refresh OK — %d titles, %d eps, share_url=%s",
                        result["title_count"], result["episode_count"], result["share_url"]
                    )
                else:
                    log.error("delta_push: refresh FAILED — %s", result.get("error"))

        except Exception:
            log.exception("delta_push: refresh loop error (will retry)")

        time.sleep(_REFRESH_INTERVAL)


# ── Admin endpoints ───────────────────────────────────────────────────────────

def _check_admin() -> bool:
    import base64
    admin_user = os.environ.get("RADD_ADMIN_USER", "admin")
    admin_pass = os.environ.get("RADD_ADMIN_PASS", "")
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Basic "):
        try:
            decoded = base64.b64decode(auth[6:]).decode()
            u, _, p = decoded.partition(":")
            return u == admin_user and p == admin_pass
        except Exception:
            pass
    return False


@bp.route("/trigger", methods=["POST"])
def trigger():
    """POST /api/catalog/delta-push/trigger — manually regenerate + upload delta.json.
    Requires Basic auth (RADD_ADMIN_USER / RADD_ADMIN_PASS).
    Returns immediately with pipeline result (runs synchronously in request).
    """
    if not _check_admin():
        return jsonify({"error": "Unauthorized"}), 401
    result = run_full_pipeline()
    return jsonify(result), 200 if result.get("ok") else 500


@bp.route("/status")
def status():
    """GET /api/catalog/delta-push/status — public status (no secrets exposed)."""
    with _state_lock:
        s = dict(_state)
    return jsonify({
        "last_upload_at":  s["last_upload_at"],
        "last_version":    s["last_version"],
        "running":         s["running"],
        "last_error":      s["last_error"],
        "jd_delta_url_set": bool(s["last_share_url"] or db.setting("jd_delta_url")),
    })
