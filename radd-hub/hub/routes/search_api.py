"""RaddFlix search API — Flutter app title search.

Registered in app.py at /api/search prefix.

P2.1 upgrade: Uses FTS5 full-text search (titles_fts virtual table) for fast,
              accurate results with prefix matching and diacritic removal.
              Falls back to LIKE queries if FTS5 is unavailable (e.g., older DBs
              before init_db() has run the FTS5 migration).

Endpoints:
  GET /api/search?q=<term>&type=all|movie|tv&limit=30
"""
from __future__ import annotations
import json
import logging
from flask import Blueprint, request, jsonify
from hub import db

log = logging.getLogger("hub.search_api")

bp = Blueprint("search_api", __name__, url_prefix="/api/search")

_SELECT = """
    t.id AS title_id, t.title, t.year, t.media_type, t.poster,
    t.rating, t.plot, t.overview, t.genres, t.language, t.is_free,
    f.id AS file_id
"""


def _type_filter(kind: str) -> str:
    if kind == "movie":
        return "AND t.media_type = 'movie'"
    elif kind in ("tv", "show"):
        return "AND t.media_type IN ('tv', 'show', 'series')"
    return ""


def _fts_search(c, q: str, type_sql: str, limit: int):
    """FTS5 search using titles_fts virtual table.

    Uses quoted-phrase + prefix (*) matching so 'aveng' finds 'Avengers'.
    bm25() orders by relevance; exact title prefix is boosted to position 0.
    Returns None (not an empty list) if FTS5 is unavailable.
    """
    try:
        escaped = q.replace('"', '""')
        fts_q   = f'"{escaped}"*'
        rows = c.execute(f"""
            SELECT {_SELECT}
            FROM titles_fts ft
            JOIN titles t ON t.id = ft.rowid
            LEFT JOIN files f ON f.title_id = t.id
                AND (f.season IS NULL OR f.season = 0)
            WHERE t.is_published = 1
              {type_sql}
              AND titles_fts MATCH ?
            GROUP BY t.id
            ORDER BY
                CASE WHEN t.title LIKE ? COLLATE NOCASE THEN 0 ELSE 1 END,
                bm25(titles_fts),
                t.title COLLATE NOCASE
            LIMIT ?
        """, (fts_q, f"%{q}%", limit)).fetchall()
        return rows
    except Exception as e:
        log.warning("FTS5 search unavailable, falling back to LIKE: %s", e)
        return None


def _like_search(c, q: str, type_sql: str, limit: int):
    """Legacy LIKE fallback — used on first boot before FTS5 is populated."""
    pattern = f"%{q}%"
    return c.execute(f"""
        SELECT {_SELECT}
        FROM titles t
        LEFT JOIN files f ON f.title_id = t.id
            AND (f.season IS NULL OR f.season = 0)
        WHERE t.is_published = 1
          {type_sql}
          AND (
              t.title    LIKE ? COLLATE NOCASE
           OR t.plot     LIKE ? COLLATE NOCASE
           OR t.overview LIKE ? COLLATE NOCASE
           OR t.genres   LIKE ? COLLATE NOCASE
           OR t.language LIKE ? COLLATE NOCASE
          )
        GROUP BY t.id
        ORDER BY
            CASE WHEN t.title LIKE ? COLLATE NOCASE THEN 0 ELSE 1 END,
            t.title COLLATE NOCASE
        LIMIT ?
    """, (pattern, pattern, pattern, pattern, pattern, pattern, limit)).fetchall()


@bp.route("", methods=["GET"], strict_slashes=False)
def search():
    q     = (request.args.get("q", "") or "").strip()
    kind  = (request.args.get("type", "all") or "all").lower()
    limit = min(int(request.args.get("limit", 30) or 30), 100)

    if len(q) < 2:
        return jsonify({"error": "query must be at least 2 characters", "results": []}), 400

    tf = _type_filter(kind)

    with db.conn() as c:
        rows = _fts_search(c, q, tf, limit)
        if rows is None:
            rows = _like_search(c, q, tf, limit)

    results = []
    for r in rows:
        genres = []
        try:
            raw = r["genres"]
            if raw:
                parsed = json.loads(raw)
                genres = parsed if isinstance(parsed, list) else []
        except Exception:
            pass
        results.append({
            "id":         r["title_id"],
            "title":      r["title"],
            "year":       (int(r["year"]) if r["year"] and str(r["year"]).isdigit() else None),
            "media_type": ("show" if r["media_type"] in ("tv", "series") else (r["media_type"] or "movie")),
            "poster":     r["poster"],
            "rating":     r["rating"],
            "plot":       r["plot"] or r["overview"],
            "genres":     genres,
            "language":   r["language"],
            "is_free":    1 if r["is_free"] else 0,
            "file_id":    r["file_id"],
        })

    return jsonify({"query": q, "count": len(results), "results": results})
