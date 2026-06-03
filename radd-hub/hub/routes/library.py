"""Library routes — titles, files, actor/genre/director filters, recommendations.
v3.0: Added filter_type, filter_genre, filter_dir, filter_actor, sort params,
      file_count on titles, /api/files per-title endpoint.
"""
import threading
from flask import Blueprint, render_template, request, jsonify, redirect
from .. import db, auth
from ..config import DATA_DIR as _DATA_DIR

bp = Blueprint("library", __name__)

def _normalize_media_type(raw: str) -> str:
    """Normalize DB media_type values to Flutter-expected 'movie' or 'show'."""
    mt = (raw or "movie").lower().strip()
    if mt in ("tv", "series", "tvshow", "tv show", "tv_show", "show"):
        return "show"
    return "movie"





def _regen_db_update_bg():
    """Background: regenerate db_update.json whenever catalog changes."""
    import json as _json, time as _time, datetime as _dt, os as _os
    from hub import db as _db
    out_path = str(_DATA_DIR / "db_update.json")
    try:
        with _db.conn() as c:
            title_rows = c.execute(
                "SELECT t.id, t.title, t.year, t.media_type, t.plot, "
                "t.rating, t.genres, t.language, t.is_free, t.updated_at, "
                "t.poster, t.poster_share_url, t.runtime, t.season_count, t.episode_count, "
                "f.id AS file_id, f.share_url AS file_share_url "
                "FROM titles t "
                "LEFT JOIN files f ON f.title_id = t.id "
                "AND (f.season IS NULL OR f.season = 0) "
                "WHERE t.is_published = 1 "
                "GROUP BY t.id ORDER BY t.id"
            ).fetchall()
        title_ids = [r["id"] for r in title_rows]
        titles_out = []
        for r in title_rows:
            genres = []
            try:
                genres = _json.loads(r["genres"] or "[]")
                if not isinstance(genres, list):
                    genres = [str(genres)]
            except Exception:
                pass
            titles_out.append({
                "id": r["id"], "title": r["title"] or "",
                "year": r["year"], "media_type": _normalize_media_type(r["media_type"]),
                "description": r["plot"] or "",
                "rating": float(r["rating"] or 0), "genres": genres,
                "language": r["language"] or "",
                "is_free": 1 if r["is_free"] else 0,
                "runtime": r.get("runtime"),
                "season_count": r.get("season_count"),
                "episode_count": r.get("episode_count"),
                "poster_url": r["poster"] or "",
                "poster_share_url": r.get("poster_share_url") or "",
                "db_version": int(r["updated_at"] or 0),
                "file_id": str(r["file_id"]) if r["file_id"] else None,
                "share_url": r.get("file_share_url") or "",  # BUG-SHARE: file-level share_url for movies
            })
        episodes_out = []
        if title_ids:
            ph = ",".join("?" * len(title_ids))
            with _db.conn() as c:
                ep_rows = c.execute(
                    "SELECT id, title_id, season, episode, share_url FROM files "
                    "WHERE title_id IN (" + ph + ") "
                    "AND season IS NOT NULL AND season > 0 "
                    "ORDER BY title_id, season, episode", title_ids
                ).fetchall()
            for r in ep_rows:
                episodes_out.append({
                    "id": r["id"], "title_id": r["title_id"],
                    "file_id": str(r["id"]),
                    "season": r["season"], "episode": r["episode"],
                    "label": "S{:02d}E{:02d}".format(r["season"] or 0, r["episode"] or 0),
                    "quality": None, "is_free": 0,
                    "share_url": r.get("share_url") or "",  # BUG-SHARE: episode-level JazzDrive share_url
                })
        now = int(_time.time())
        payload = {
            "version": now,
            "generated_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "titles": titles_out, "episodes": episodes_out,
        }
        with open(out_path, "w", encoding="utf-8") as f:
            _json.dump(payload, f, ensure_ascii=False, indent=2)
    except Exception:
        pass  # Never crash the web request over a background regen

_SORT_MAP = {
    "title":     "t.title ASC",
    "year_desc": "t.year DESC NULLS LAST",
    "year_asc":  "t.year ASC NULLS LAST",
    "rating":    "t.rating DESC NULLS LAST",
    "added":     "t.id DESC",
}


def _list_titles_filtered(q="", media_type="", genre="", director="", actor="",
                           sort="title", limit=200):
    """Flexible title query with optional filters. Returns list of dicts."""
    sort_clause = _SORT_MAP.get(sort, "t.title ASC")
    conditions  = []
    params      = []

    if q:
        conditions.append(
            "(t.title LIKE ? OR t.original_title LIKE ? OR t.cast_json LIKE ?)"
        )
        pat = f"%{q}%"
        params += [pat, pat, pat]
    if media_type:
        conditions.append("LOWER(t.media_type) = ?")
        params.append(media_type.lower())
    if genre:
        conditions.append("t.genres_csv LIKE ?")
        params.append(f"%{genre}%")
    if director:
        conditions.append("t.director LIKE ?")
        params.append(f"%{director}%")
    if actor:
        conditions.append("t.cast_json LIKE ?")
        params.append(f"%{actor}%")

    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    sql = f"""
        SELECT t.*,
               (SELECT COUNT(*) FROM files f WHERE f.title_id = t.id) AS file_count
        FROM   titles t
        {where}
        ORDER  BY {sort_clause}
        LIMIT  ?
    """
    params.append(limit)

    with db.conn() as c:
        try:
            rows = c.execute(sql, params).fetchall()
        except Exception:
            # Fallback: no file_count column if DB schema older
            sql2 = f"SELECT * FROM titles t {where} ORDER BY {sort_clause} LIMIT ?"
            rows = c.execute(sql2, params).fetchall()
    return [db._enrich_title(r) for r in rows]





def _notify_new_title_bg(title_id: int, val: int) -> None:
    """Background: create in-app notification + WhatsApp blast when a title is published.

    Skips if already notified (settings key notified_title_<id>).
    Only fires when val == 1 (title being published, not unpublished).
    """
    if val != 1:
        return
    import time as _t
    import threading as _th

    dedup_key = "notified_title_" + str(title_id)
    with db.conn() as c:
        already = c.execute(
            "SELECT v FROM settings WHERE k=?", (dedup_key,)
        ).fetchone()
        if already:
            return  # already notified once — skip re-publish cycles
        row = c.execute(
            "SELECT title, media_type, poster FROM titles WHERE id=?", (title_id,)
        ).fetchone()
    if not row:
        return

    t_name = row["title"] or "New Title"
    m_type = row["media_type"] or "movie"
    poster = row["poster"] or ""
    emoji  = "🎬" if m_type == "movie" else "📺"
    label  = "movie" if m_type == "movie" else "show"
    notif_title = emoji + " New on RaddFlix: " + t_name
    notif_body  = t_name + " (" + label + ") is now available. Open RaddFlix to watch!"
    wa_msg      = (emoji + " *New on RaddFlix!*\n"
                   "*" + t_name + "* is now available to stream.\n"
                   "Open the RaddFlix app to watch it now!")
    now = int(_t.time())

    with db.conn() as c:
        c.execute(
            "INSERT INTO notifications(user_id,title,body,image_url,created_at)"
            " VALUES(?,?,?,?,?)",
            (None, notif_title, notif_body, poster or None, now)
        )
        c.execute(
            "INSERT OR REPLACE INTO settings(k,v) VALUES(?,?)",
            (dedup_key, str(now))
        )

    import logging as _log
    _log = _log.getLogger("hub.library")

    def _wa_blast():
        try:
            import requests as _req
            with db.conn() as c:
                users = c.execute(
                    "SELECT phone FROM app_users"
                    " WHERE is_active=1 AND phone IS NOT NULL"
                ).fetchall()
            for u in users:
                phone = (u["phone"] or "").lstrip("0")
                if not phone.startswith("92"):
                    phone = "92" + phone
                jid = phone + "@s.whatsapp.net"
                try:
                    _req.post(
                        "http://127.0.0.1:3000/api/send-message",
                        json={"jid": jid, "text": wa_msg},
                        timeout=8,
                    )
                except Exception:
                    pass
        except Exception as _e:
            _log.warning("WA blast failed: %s", _e)

    def _wa_blast_delayed():
        # BUG-S13 fix: 60-second grace period lets admin cancel by un-publishing before blast fires
        _t.sleep(60)
        with db.conn() as _c:
            still_pub = _c.execute(
                "SELECT is_published FROM titles WHERE id=?", (title_id,)
            ).fetchone()
        if not still_pub or not still_pub["is_published"]:
            _log.info("WA blast cancelled — title %d was un-published during grace period", title_id)
            return
        _wa_blast()

    _th.Thread(target=_wa_blast_delayed, daemon=True, name="notif-wa-blast").start()

@bp.route("/")
@auth.login_required
def page():
    q            = request.args.get("q",        "").strip()
    filter_type  = request.args.get("type",     "").strip()
    filter_genre = request.args.get("genre",    "").strip()
    filter_dir   = request.args.get("director", "").strip()
    filter_actor = request.args.get("actor",    "").strip()
    sort         = request.args.get("sort",     "title").strip()
    if sort not in _SORT_MAP:
        sort = "title"

    titles = _list_titles_filtered(
        q=q, media_type=filter_type, genre=filter_genre,
        director=filter_dir, actor=filter_actor,
        sort=sort, limit=200,
    )

    # Fetch unidentified files (those without a title_id)
    orphans = []
    if not filter_type and not filter_genre and not filter_dir and not filter_actor:
        with db.conn() as c:
            sql_orphans = "SELECT * FROM files WHERE title_id IS NULL"
            if q:
                sql_orphans += " AND filename LIKE ?"
                rows_orphans = c.execute(sql_orphans + " LIMIT 100", (f"%{q}%",)).fetchall()
            else:
                rows_orphans = c.execute(sql_orphans + " LIMIT 100").fetchall()
            orphans = [dict(r) for r in rows_orphans]

    return render_template("library.html",
        titles=titles,
        orphans=orphans,
        query=q,
        filter_type=filter_type,
        filter_genre=filter_genre,
        filter_dir=filter_dir,
        filter_actor=filter_actor,
        sort=sort,
        stats=db.count_library(),
    )


# ---------------------------------------------------------------------------
# JSON API — list / search
# ---------------------------------------------------------------------------

@bp.route("/api/list")
@auth.login_required
def api_list():
    return jsonify(db.list_titles(
        limit=int(request.args.get("limit", 200)),
        q=request.args.get("q", ""),
    ))


@bp.route("/api/title/<int:title_id>")
@auth.login_required
def api_title(title_id):
    with db.conn() as c:
        t = c.execute("SELECT * FROM titles WHERE id=?", (title_id,)).fetchone()
    if not t:
        return jsonify({"error": "not found"}), 404
    return jsonify({"title": dict(t),
                    "files": db.list_files_for_title(title_id)})


@bp.route("/api/files")
@auth.login_required
def api_files_for_title():
    """List files for a title. ?title_id=<int>"""
    title_id = request.args.get("title_id", "").strip()
    if not title_id or not title_id.isdigit():
        return jsonify({"error": "title_id required"}), 400
    try:
        files = db.list_files_for_title(int(title_id))
        return jsonify(files)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@bp.route("/api/recent")
@auth.login_required
def api_recent():
    return jsonify(db.list_files(
        limit=int(request.args.get("limit", 50)),
        source=request.args.get("source"),
    ))


@bp.route("/api/poster/<int:title_id>")
@auth.login_required
def api_poster(title_id):
    """Proxy route to generate a zero-rated direct link for a title's poster."""
    import time
    from .. import jazzdrive, turbo_cache
    
    # 1. Check Cache first
    cache_key = f"poster_{title_id}"
    cached = turbo_cache.get(cache_key, site="jazzdrive", cat="links")
    if cached:
        return redirect(cached, code=302)

    # 2. Lookup share URL in DB
    with db.conn() as c:
        row = c.execute("SELECT poster_share_url, poster FROM titles WHERE id=?", (title_id,)).fetchone()
    
    if not row or not row["poster_share_url"]:
        # Fallback to TMDB if no JD asset
        if row and row["poster"]:
             return redirect(row["poster"], code=302)
        return jsonify({"error": "poster not found"}), 404

    # 3. Generate Direct Link
    res = jazzdrive.generate_direct_link(row["poster_share_url"], target_filename="poster.jpg")
    if res.get("ok"):
        direct_link = res["direct_link"]
        # Cache (default expiry for 'links' is 24h)
        turbo_cache.set(cache_key, site="jazzdrive", cat="links", data=direct_link)
        return redirect(direct_link, code=302)

    return jsonify({"error": "could not generate link", "detail": res.get("error")}), 503


@bp.route("/api/user/status")
@auth.login_required
def api_user_status():
    """Return mock or real quota status for the JazzBuzz app."""
    import time
    # In a real app, this would query the 'users' table or Jazz network API
    return jsonify({
        "ok": True,
        "user": {
            "username": "Cinema Explorer",
            "tier": "Premium",
            "quota_total_gb": 10.0,
            "quota_used_gb": 4.25,
            "quota_remaining_gb": 5.75,
            "data_speed": "4G/LTE+",
            "network": "Jazz Zero-Rated",
            "is_optimized": True,
            "points": 1240,
            "expires_at": int(time.time()) + (24 * 86400)
        }
    })




# ---------------------------------------------------------------------------
# Trending endpoint — top-rated published titles (ranked by rating × vote_count)
# Falls back to rating-only sort if watch_history is sparse.
# ---------------------------------------------------------------------------

@bp.route("/api/trending")
@auth.login_required
def api_trending():
    """Return top trending titles for the RaddFlix app Trending Now row."""
    limit = int(request.args.get("limit", 20))
    media_type = request.args.get("type", "").strip().lower()

    conditions = ["t.is_published = 1", "t.poster IS NOT NULL AND t.poster != ''"]
    params = []

    if media_type:
        conditions.append("LOWER(t.media_type) = ?")
        params.append(media_type)

    where = "WHERE " + " AND ".join(conditions)

    # Primary: rank by watch_history view count (last 60 days) × rating
    sql = f"""
        SELECT t.id, t.title, t.year, t.media_type, t.plot,
               t.rating, t.genres, t.language, t.is_free, t.updated_at,
               t.poster, t.poster_share_url, t.runtime,
               t.season_count, t.episode_count,
               (SELECT id FROM files WHERE title_id = t.id LIMIT 1) AS file_id,
               (SELECT COUNT(*) FROM watch_history wh
                JOIN files fi ON fi.id = CAST(wh.file_id AS INTEGER)
                WHERE fi.title_id = t.id
                  AND wh.watched_at >= (strftime('%s', 'now') - 5184000)
               ) AS recent_views
        FROM titles t
        {where}
        ORDER BY (recent_views * 3 + COALESCE(t.rating, 0)) DESC
        LIMIT ?
    """
    params.append(limit)

    try:
        with db.conn() as c:
            rows = c.execute(sql, params).fetchall()

        result = []
        for r in rows:
            import json as _json
            genres = []
            try:
                genres = _json.loads(r["genres"] or "[]")
                if not isinstance(genres, list):
                    genres = [str(genres)]
            except Exception:
                pass
            result.append({
                "id": r["id"],
                "title": r["title"] or "",
                "year": r["year"],
                "media_type": _normalize_media_type(r["media_type"]),
                "description": r["plot"] or "",
                "rating": float(r["rating"] or 0),
                "genres": genres,
                "language": r["language"] or "",
                "is_free": 1 if r["is_free"] else 0,
                "runtime": r["runtime"],
                "season_count": r["season_count"],
                "episode_count": r["episode_count"],
                "poster_url": r["poster"] or "",
                "poster_share_url": r["poster_share_url"] or "",
                "db_version": int(r["updated_at"] or 0),
                "file_id": str(r["file_id"]) if r["file_id"] else None,
                "recent_views": r["recent_views"],
            })

        return jsonify({"ok": True, "trending": result, "count": len(result)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

# ---------------------------------------------------------------------------
# Filter endpoints (v2-compatible)
# ---------------------------------------------------------------------------

@bp.route("/api/actor")
@auth.login_required
def api_by_actor():
    """Filter library titles by actor. ?name=Shah+Rukh+Khan&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    with db.conn() as c:
        rows = c.execute(
            "SELECT * FROM titles WHERE cast_json LIKE ? ORDER BY rating DESC LIMIT ?",
            (f"%{name}%", limit)
        ).fetchall()
    return jsonify({"ok": True, "actor": name, "count": len(rows),
                    "results": [dict(r) for r in rows]})


@bp.route("/api/genre")
@auth.login_required
def api_by_genre():
    """Filter library titles by genre. ?name=Action&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    with db.conn() as c:
        rows = c.execute(
            "SELECT * FROM titles WHERE genres_csv LIKE ? ORDER BY rating DESC LIMIT ?",
            (f"%{name}%", limit)
        ).fetchall()
    return jsonify({"ok": True, "genre": name, "count": len(rows),
                    "results": [dict(r) for r in rows]})


@bp.route("/api/director")
@auth.login_required
def api_by_director():
    """Filter library titles by director. ?name=Christopher+Nolan&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    with db.conn() as c:
        rows = c.execute(
            "SELECT * FROM titles WHERE director LIKE ? ORDER BY rating DESC LIMIT ?",
            (f"%{name}%", limit)
        ).fetchall()
    return jsonify({"ok": True, "director": name, "count": len(rows),
                    "results": [dict(r) for r in rows]})


@bp.route("/api/has")
@auth.login_required
def api_has():
    """Check if a title is in the library. ?title=Inception&year=2010"""
    title = request.args.get("title", "").strip()
    year  = request.args.get("year", "").strip()
    if not title:
        return jsonify({"ok": False, "error": "Missing ?title= parameter"}), 400
    with db.conn() as c:
        sql  = "SELECT id, title, year, poster FROM titles WHERE title LIKE ?"
        args = [f"%{title}%"]
        if year:
            sql  += " AND year LIKE ?"
            args.append(f"{year}%")
        row = c.execute(sql, args).fetchone()
    if row:
        return jsonify({"ok": True, "has": True, "title": dict(row)})
    return jsonify({"ok": True, "has": False})


@bp.route("/api/search")
@auth.login_required
def api_search():
    """Full-text search across title, original_title, cast, director, genres.
    ?q=inception&limit=50
    """
    q     = request.args.get("q", "").strip()
    limit = int(request.args.get("limit", 50))
    if not q:
        return jsonify({"ok": False, "error": "Missing ?q= parameter"}), 400
    pat = f"%{q}%"
    with db.conn() as c:
        rows = c.execute(
            "SELECT * FROM titles WHERE "
            "title LIKE ? OR original_title LIKE ? OR cast_json LIKE ? "
            "OR director LIKE ? OR genres_csv LIKE ? "
            "ORDER BY rating DESC LIMIT ?",
            (pat, pat, pat, pat, pat, limit)
        ).fetchall()
    return jsonify({"ok": True, "query": q, "count": len(rows),
                    "results": [dict(r) for r in rows]})


# ---------------------------------------------------------------------------
# Recommendations
# ---------------------------------------------------------------------------

@bp.route("/api/recommendations")
@auth.login_required
def api_recommendations():
    """TMDB-powered recommendations.  ?limit=10"""
    limit = int(request.args.get("limit", 10))
    try:
        from .. import radd_recommend
        items = radd_recommend.get_recommendations(limit=limit)
        return jsonify({"ok": True, "count": len(items), "items": items})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "items": []}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Admin CRUD — edit / delete / enrich / link / toggle
# ─────────────────────────────────────────────────────────────────────────────
import time as _time

@bp.route("/api/title/<int:title_id>", methods=["PUT"])
@auth.login_required
def api_edit_title(title_id):
    """Update title metadata fields."""
    data = request.get_json(force=True, silent=True) or {}
    allowed = [
        "title", "year", "media_type", "rating", "plot",
        "director", "genres_csv", "languages_csv",
        "runtime", "language", "country", "poster",
    ]
    sets, params = [], []
    for key in allowed:
        if key in data:
            sets.append(f"{key}=?")
            params.append(data[key])
    if not sets:
        return jsonify({"error": "no fields to update"}), 400
    sets.append("updated_at=?")
    params += [int(_time.time()), title_id]
    with db.conn() as c:
        c.execute(f"UPDATE titles SET {', '.join(sets)} WHERE id=?", params)
    return jsonify({"ok": True})


@bp.route("/api/title/<int:title_id>/set-free", methods=["POST"])
@auth.login_required
def api_set_free(title_id):
    data = request.get_json(force=True, silent=True) or {}
    val = 1 if data.get("is_free") else 0
    import time as _tm
    with db.conn() as c:
        c.execute("UPDATE titles SET is_free=?, updated_at=? WHERE id=?",
                  (val, int(_tm.time()), title_id))
    threading.Thread(target=_regen_db_update_bg, daemon=True).start()
    return jsonify({"ok": True, "is_free": val})


@bp.route("/api/title/<int:title_id>/set-published", methods=["POST"])
@auth.login_required
def api_set_published(title_id):
    data = request.get_json(force=True, silent=True) or {}
    val = 1 if data.get("is_published") else 0
    import time as _tm
    with db.conn() as c:
        c.execute("UPDATE titles SET is_published=?, updated_at=? WHERE id=?",
                  (val, int(_tm.time()), title_id))
    # Auto-regenerate db_update.json so zero-rated users get updated catalog
    threading.Thread(target=_regen_db_update_bg, daemon=True).start()
    # Auto-notify users when a title goes live (in-app + WhatsApp)
    threading.Thread(target=_notify_new_title_bg, args=(title_id, val), daemon=True).start()
    return jsonify({"ok": True, "is_published": val})


@bp.route("/api/title/<int:title_id>/delete", methods=["DELETE", "POST"])
@auth.login_required
def api_delete_title(title_id):
    data = request.get_json(force=True, silent=True) or {}
    delete_files = bool(data.get("delete_files", False))
    with db.conn() as c:
        if delete_files:
            c.execute("DELETE FROM files WHERE title_id=?", (title_id,))
        else:
            c.execute("UPDATE files SET title_id=NULL WHERE title_id=?", (title_id,))
        c.execute("DELETE FROM titles WHERE id=?", (title_id,))
    return jsonify({"ok": True})


@bp.route("/api/title/<int:title_id>/enrich-omdb", methods=["POST"])
@auth.login_required
def api_enrich_omdb(title_id):
    """Fetch metadata from OMDB and save to title."""
    import requests as _req
    from .. import keys as _keys
    with db.conn() as c:
        t = c.execute(
            "SELECT title, year, imdb_id FROM titles WHERE id=?", (title_id,)
        ).fetchone()
    if not t:
        return jsonify({"error": "not found"}), 404
    key = _keys.get_active_value("omdb")
    if not key:
        return jsonify({"error": "no OMDB key configured"}), 503
    params = {"apikey": key, "plot": "full"}
    if t["imdb_id"]:
        params["i"] = t["imdb_id"]
    else:
        params["t"] = t["title"]
        if t["year"]:
            params["y"] = str(t["year"])[:4]
    try:
        # BUG-HTTP: was http://; OMDB requires HTTPS for paid keys (avoids redirect+slowness)
        r = _req.get("https://www.omdbapi.com/", params=params, timeout=10)
        omdb = r.json()
    except Exception as e:
        return jsonify({"error": str(e)}), 503
    if omdb.get("Response") != "True":
        return jsonify({"error": omdb.get("Error", "no result")}), 404
    def _f(v): return None if not v or v == "N/A" else v
    def _rating(s):
        try: return float((s or "").split("/")[0])
        except: return None
    now = int(_time.time())
    updates = {}
    if _f(omdb.get("Title")):    updates["title"]         = omdb["Title"]
    if _f(omdb.get("Year")):     updates["year"]          = omdb["Year"][:4]
    if _f(omdb.get("Plot")):     updates["plot"]          = omdb["Plot"]
    if _f(omdb.get("Director")): updates["director"]      = omdb["Director"]
    # cast_names dropped (P3.5) — actor data lives in cast_json from TMDB
    if _f(omdb.get("Genre")):    updates["genres_csv"]    = omdb["Genre"]
    if _f(omdb.get("Language")): updates["languages_csv"] = omdb["Language"]
    if _f(omdb.get("Poster")):   updates["poster"]        = omdb["Poster"]
    if _f(omdb.get("imdbID")):   updates["imdb_id"]       = omdb["imdbID"]
    rt = _f(omdb.get("Runtime"))
    if rt:
        try: updates["runtime"] = int(rt.split()[0])
        except: pass
    rv = _rating(omdb.get("imdbRating"))
    if rv: updates["imdb_rating"] = rv
    if updates:
        sets = [f"{k}=?" for k in updates] + ["updated_at=?"]
        vals = list(updates.values()) + [now, title_id]
        with db.conn() as c:
            c.execute(f"UPDATE titles SET {', '.join(sets)} WHERE id=?", vals)
    return jsonify({"ok": True, "updated": list(updates.keys()), "omdb_title": omdb.get("Title")})



@bp.route("/api/title/<int:title_id>/push-poster-to-jd", methods=["POST"])
@auth.login_required
def api_push_poster_jd(title_id):
    """Download best poster (TMDB->TVmaze->Wikipedia) and upload to JazzDrive same folder."""
    import tempfile, time, requests as _req, urllib.parse
    from pathlib import Path as _P
    from .. import uploader as _up, jazzdrive as _jd

    with db.conn() as c:
        title = c.execute(
            "SELECT id, title, year, media_type, poster, folder_share_url "
            "FROM titles WHERE id=?", (title_id,)
        ).fetchone()
        if not title:
            return jsonify({"error": "title not found"}), 404
        file_row = c.execute(
            "SELECT remote_folder_id FROM files "
            "WHERE title_id=? AND remote_folder_id IS NOT NULL AND remote_folder_id!='' LIMIT 1",
            (title_id,)
        ).fetchone()

    if not file_row:
        return jsonify({"error": "No JazzDrive folder for this title -- run Scanner first"}), 400

    folder_id = int(file_row["remote_folder_id"])
    mt = (title["media_type"] or "").lower()

    poster_url = title["poster"] or ""

    if not poster_url and mt in ("tv", "series", "show", "anime", "drama"):
        try:
            q = urllib.parse.quote(title["title"])
            r = _req.get(f"https://api.tvmaze.com/singlesearch/shows?q={q}", timeout=8)
            if r.status_code == 200:
                img = r.json().get("image") or {}
                poster_url = img.get("original") or img.get("medium") or ""
        except Exception:
            pass

    if not poster_url:
        try:
            base = title["title"].replace(" ", "_")
            yr = str(title["year"] or "")
            for suf in ([f"_({yr}_film)"] if yr else []) + ["_(film)", "_(TV_series)", ""]:
                slug = urllib.parse.quote(base + suf)
                r = _req.get(f"https://en.wikipedia.org/api/rest_v1/page/summary/{slug}", timeout=8)
                if r.status_code == 200:
                    th = r.json().get("thumbnail") or {}
                    if th.get("source"):
                        poster_url = th["source"]
                        break
        except Exception:
            pass

    if not poster_url:
        return jsonify({"error": "No poster found from TMDB/TVmaze/Wikipedia"}), 400

    try:
        r = _req.get(poster_url, timeout=20)
        if r.status_code != 200:
            return jsonify({"error": f"Poster download failed: HTTP {r.status_code}"}), 400
        if len(r.content) < 2048:
            return jsonify({"error": "Downloaded file too small -- not a valid image"}), 400
    except Exception as e:
        return jsonify({"error": f"Download error: {e}"}), 400

    tmp = _P(tempfile.mktemp(suffix=".jpg", prefix=f"poster_{title_id}_"))
    tmp.write_bytes(r.content)

    try:
        acct = _up.get_active_account()
        if not acct:
            return jsonify({"error": "No active JazzDrive account -- add one under Scanner"}), 500

        vk   = acct.get("validation_key") or acct.get("validationkey") or ""
        jsid = acct.get("jsessionid") or ""
        aid  = acct.get("id")

        if not vk or not jsid:
            return jsonify({"error": "JazzDrive session expired -- re-verify OTP in Scanner"}), 500

        import requests as _rq2
        sess = _rq2.Session()

        result = _up._upload_file(
            sess, vk, jsid, tmp,
            parent_id=folder_id,
            override_name="poster.jpg",
            account_id=aid,
        )
        jd_file_id = (result or {}).get("id", 0)

        poster_share_url = ""
        folder_share = title["folder_share_url"] or ""
        if folder_share:
            try:
                link_res = _jd.generate_folder_image_link(folder_share, filename_hint="poster")
                if link_res.get("ok") and link_res.get("url"):
                    poster_share_url = link_res["url"]
            except Exception as e:
                import logging
                logging.getLogger("hub.library").warning("push-poster-to-jd link error: %s", e)

        with db.conn() as c:
            c.execute(
                "UPDATE titles SET poster_share_url=?, updated_at=? WHERE id=?",
                (poster_share_url or None, int(time.time()), title_id),
            )

        return jsonify({
            "ok": True,
            "jd_file_id": jd_file_id,
            "folder_id": folder_id,
            "poster_share_url": poster_share_url or "(view link pending)",
            "source_url": poster_url,
        })
    finally:
        try:
            tmp.unlink()
        except Exception:
            pass


@bp.route("/api/file/<int:file_id>/link", methods=["POST"])
@auth.login_required
def api_link_file(file_id):
    """Link an orphan file to a title."""
    data = request.get_json(force=True, silent=True) or {}
    title_id = data.get("title_id")
    if not title_id:
        return jsonify({"error": "title_id required"}), 400
    with db.conn() as c:
        c.execute("UPDATE files SET title_id=? WHERE id=?", (title_id, file_id))
    return jsonify({"ok": True})


@bp.route("/api/titles/bulk-enrich-omdb", methods=["POST"])
@auth.login_required
def api_bulk_enrich_omdb():
    """Bulk-enrich up to 10 titles missing plot from OMDB."""
    import requests as _req
    from .. import keys as _keys
    key = _keys.get_active_value("omdb")
    if not key:
        return jsonify({"error": "no OMDB key configured"}), 503
    with db.conn() as c:
        rows = c.execute(
            "SELECT id, title, year, imdb_id FROM titles "
            "WHERE (plot IS NULL OR plot='') LIMIT 10"
        ).fetchall()
    results = []
    for t in rows:
        params = {"apikey": key, "plot": "full"}
        if t["imdb_id"]:
            params["i"] = t["imdb_id"]
        else:
            params["t"] = t["title"]
            if t["year"]: params["y"] = str(t["year"])[:4]
        try:
            r = _req.get("https://www.omdbapi.com/", params=params, timeout=8)
            omdb = r.json()
            def _f(v): return None if not v or v == "N/A" else v
            if omdb.get("Response") == "True":
                updates = {}
                if _f(omdb.get("Plot")):     updates["plot"]       = omdb["Plot"]
                if _f(omdb.get("Director")): updates["director"]   = omdb["Director"]
                # cast_names dropped (P3.5) — actor data lives in cast_json from TMDB
                if _f(omdb.get("Genre")):    updates["genres_csv"] = omdb["Genre"]
                if _f(omdb.get("Poster")):   updates["poster"]     = omdb["Poster"]
                if _f(omdb.get("imdbID")):   updates["imdb_id"]    = omdb["imdbID"]
                if updates:
                    sets = [f"{k}=?" for k in updates] + ["updated_at=?"]
                    vals = list(updates.values()) + [int(_time.time()), t["id"]]
                    with db.conn() as c2:
                        c2.execute(f"UPDATE titles SET {', '.join(sets)} WHERE id=?", vals)
                results.append({"id": t["id"], "title": t["title"], "ok": True, "updated": list(updates.keys())})
            else:
                results.append({"id": t["id"], "title": t["title"], "ok": False, "error": omdb.get("Error")})
        except Exception as e:
            results.append({"id": t["id"], "title": t["title"], "ok": False, "error": str(e)})
        _time.sleep(0.25)
    return jsonify({"ok": True, "processed": len(results), "results": results})


@bp.route("/api/titles/re-enrich-all", methods=["POST"])
@auth.login_required
def api_re_enrich_all():
    """Background re-enrichment of all incomplete titles (confidence < 60) across
    all accounts using TMDB + OMDB keys from the vault.
    Returns immediately; enrichment runs in a daemon thread."""
    import threading
    from .. import scanner as _scanner, db as _db

    accounts = _db.list_accounts()
    if not accounts:
        return jsonify({"ok": False, "error": "No JazzDrive accounts configured"}), 400

    def _run():
        for acct in accounts:
            try:
                n = _scanner._enrich_low_confidence_titles(acct["id"])
                log.info("re-enrich-all: account %s → %s titles enriched", acct["id"], n or 0)
            except Exception as _e:
                log.debug("re-enrich-all error for account %s: %s", acct["id"], _e)

    threading.Thread(target=_run, daemon=True, name="re-enrich-all").start()
    return jsonify({
        "ok": True,
        "accounts": len(accounts),
        "message": (
            f"Re-enrichment started for {len(accounts)} account(s) in the background. "
            "Titles with confidence < 60 (missing plot/poster/genres) will be filled "
            "using TMDB + OMDB. Check the Scan log for per-title progress."
        ),
    })


@bp.route("/api/files/auto-identify", methods=["POST"])
@auth.login_required
def api_auto_identify():
    """Parse orphan filenames, create titles if needed, link files automatically."""
    import re as _re, time as _time
    with db.conn() as c:
        orphans = c.execute(
            "SELECT id, filename, season, episode FROM files WHERE title_id IS NULL"
        ).fetchall()
    if not orphans:
        return jsonify({"ok": True, "created": [], "linked": 0, "message": "No orphans to identify"})

    def _parse(fn):
        base = _re.sub(r"\.[a-z0-9]{2,4}$", "", fn, flags=_re.I)
        m = _re.match(r"^(.+?)\s+[Ss](\d+)[Ee](\d+)", base)
        if m:
            return {"title": m.group(1).strip(), "type": "series",
                    "season": int(m.group(2)), "episode": int(m.group(3)), "year": None}
        m = _re.match(r"^(.+?)\s*\((\d{4})\)", base)
        if m:
            return {"title": m.group(1).strip(), "type": "movie",
                    "year": m.group(2), "season": None, "episode": None}
        return {"title": base.strip(), "type": "movie", "year": None, "season": None, "episode": None}

    groups, now = {}, int(_time.time())
    for f in orphans:
        info = _parse(f["filename"])
        key  = info["title"].lower().strip()
        if key not in groups:
            groups[key] = {"info": info, "files": []}
        groups[key]["files"].append(f)

    created, linked = [], 0
    for key, g in groups.items():
        info, files = g["info"], g["files"]
        with db.conn() as c:
            ex = c.execute("SELECT id FROM titles WHERE LOWER(title)=LOWER(?)", (info["title"],)).fetchone()
        if ex:
            title_id = ex["id"]
        else:
            with db.conn() as c:
                cur = c.execute(
                    "INSERT INTO titles (title, year, media_type, is_published, is_free, updated_at, created_at) "
                    "VALUES (?, ?, ?, 1, 0, ?, ?)",
                    (info["title"], info.get("year"), info["type"], now, now)
                )
                title_id = cur.lastrowid
            created.append({"id": title_id, "title": info["title"], "type": info["type"]})
        for f in files:
            season  = f["season"]  if f["season"]  is not None else info.get("season")
            episode = f["episode"] if f["episode"] is not None else info.get("episode")
            with db.conn() as c:
                c.execute("UPDATE files SET title_id=?, season=?, episode=? WHERE id=?",
                          (title_id, season, episode, f["id"]))
            linked += 1
    return jsonify({"ok": True, "created": created, "linked": linked,
                    "message": f"Created {len(created)} titles, linked {linked} files"})


@bp.route("/set-status", methods=["POST"])
@auth.login_required
def set_status():
    """Manually set status + is_ongoing for a title.

    Body: {title_id: int, status: "ongoing"|"completed"|"released"|"cancelled"}
    """
    data      = request.get_json(force=True, silent=True) or {}
    title_id  = data.get("title_id")
    status    = (data.get("status") or "").strip().lower()
    if not title_id or status not in ("ongoing", "completed", "released", "cancelled"):
        return jsonify({"ok": False,
                        "error": "title_id required; status must be ongoing/completed/released/cancelled"}), 400
    is_ongoing = 1 if status == "ongoing" else 0
    now = int(_time.time())
    with db.conn() as c:
        c.execute(
            "UPDATE titles SET status=?, is_ongoing=?, updated_at=? WHERE id=?",
            (status, is_ongoing, now, int(title_id))
        )
        if c.rowcount == 0:
            return jsonify({"ok": False, "error": "Title not found"}), 404
    # Regenerate db_update.json in background so app gets updated catalog
    import threading as _thr
    _thr.Thread(target=_regen_db_update_bg, daemon=True).start()
    return jsonify({"ok": True, "title_id": title_id, "status": status, "is_ongoing": is_ongoing})
