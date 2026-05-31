"""Database Management — CRUD, raw SQL, and data grid."""
from __future__ import annotations
import json
import time
import sqlite3
import csv
import io
from flask import Blueprint, render_template, request, jsonify, Response, abort
from .. import db, auth, config

bp = Blueprint("db_mgmt", __name__)

# All tables exposed in DB Studio, grouped by category
TABLE_GROUPS = {
    "Library":       ["titles", "files", "accounts"],
    "Vault":         ["keys"],
    "Users":         ["users", "app_users", "app_refresh_tokens"],
    "Payments":      ["payment_methods", "received_sms_payments", "tid_payments"],
    "Subscriptions": ["plans", "user_subscriptions", "app_subscriptions"],
    "Analytics":     ["watch_history", "user_usage", "rate_limit_log"],
    "System":        ["settings", "scan_log", "mirror_log", "queue"],
    "App":           ["notifications", "stream_links", "recommendation_cache", "media_index"],
}

ALL_TABLES = {t for tables in TABLE_GROUPS.values() for t in tables}


def _table_exists(c: sqlite3.Connection, name: str) -> bool:
    r = c.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return bool(r)


def _safe_row(row) -> dict:
    """Convert a sqlite3.Row or dict to JSON-serializable dict.
    Bytes (BLOB) columns are rendered as '[BINARY Nb]' so JSON doesn't crash."""
    result = {}
    d = dict(row)
    for k, v in d.items():
        if isinstance(v, bytes):
            try:
                result[k] = v.decode("utf-8")
            except UnicodeDecodeError:
                result[k] = f"[BINARY {len(v)}B]"
        else:
            result[k] = v
    return result


@bp.route("/")
@auth.login_required
def page():
    return render_template("db_mgmt.html", active="db_mgmt")


@bp.route("/api/tables")
@auth.login_required
def list_tables():
    """Return all tables grouped by category. Skip tables that don't exist yet."""
    result = {}
    with db.conn() as c:
        for group, tables in TABLE_GROUPS.items():
            existing = [t for t in tables if _table_exists(c, t)]
            if existing:
                result[group] = existing
    return jsonify({"ok": True, "groups": result})


@bp.route("/api/table/<name>")
@auth.login_required
def get_table_data(name):
    """Fetch rows from a table with pagination, search and sorting."""
    if name not in ALL_TABLES:
        abort(403)

    limit  = min(int(request.args.get("limit", 50)), 500)
    offset = int(request.args.get("offset", 0))
    q      = request.args.get("q", "").strip()
    sort   = request.args.get("sort", "id")
    order  = "DESC" if request.args.get("order", "desc").lower() == "desc" else "ASC"

    try:
        with db.conn() as c:
            if not _table_exists(c, name):
                return jsonify({"ok": False, "error": f"Table '{name}' does not exist"}), 404

            cursor  = c.execute(f"PRAGMA table_info({name})")
            columns = [{"name": r["name"], "type": r["type"], "pk": bool(r["pk"])}
                       for r in cursor.fetchall()]
            col_names = {col["name"] for col in columns}

            where, params = "", []
            if q:
                # FTS5 for titles
                if name == "titles" and _table_exists(c, "catalog_fts"):
                    try:
                        fts_rows = c.execute(
                            "SELECT rowid FROM catalog_fts WHERE catalog_fts MATCH ? LIMIT 500",
                            (f"{q}*",)
                        ).fetchall()
                        ids = ",".join(str(r[0]) for r in fts_rows) if fts_rows else "0"
                        where = f" WHERE id IN ({ids})"
                    except Exception:
                        pass

                if not where:
                    text_cols = [col["name"] for col in columns
                                 if col["type"].upper() in ("TEXT", "VARCHAR")][:10]
                    if text_cols:
                        where  = " WHERE " + " OR ".join(f"{c2} LIKE ?" for c2 in text_cols)
                        params = [f"%{q}%"] * len(text_cols)

            # Extra filters — only apply to known columns
            mt = request.args.get("mt", "").strip()
            if mt and "media_type" in col_names:
                connector = " AND" if where else " WHERE"
                where += f"{connector} media_type = ?"
                params.append(mt)

            if request.args.get("nullsonly") == "1" and name == "titles":
                _nf = ["poster", "overview", "genres_csv", "cast_names",
                       "director", "rating", "imdb_rating"]
                _nc = " OR ".join(
                    f"({f} IS NULL OR CAST({f} AS TEXT) = '')" for f in _nf
                )
                connector = " AND" if where else " WHERE"
                where += f"{connector} ({_nc})"

            safe_sort = sort if sort in col_names else "id"
            total = c.execute(f"SELECT COUNT(*) FROM {name}{where}", params).fetchone()[0]
            rows  = c.execute(
                f"SELECT * FROM {name}{where} ORDER BY {safe_sort} {order} LIMIT ? OFFSET ?",
                params + [limit, offset]
            ).fetchall()

            return jsonify({
                "ok": True, "columns": columns,
                "rows": [_safe_row(r) for r in rows],
                "total": total, "limit": limit, "offset": offset,
            })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["POST"])
@auth.login_required
def create_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data = request.get_json(force=True, silent=True) or {}
    if not data:
        return jsonify({"ok": False, "error": "No data provided"}), 400
    try:
        cols = list(data.keys())
        sql  = (f"INSERT INTO {name} ({', '.join(cols)}) "
                f"VALUES ({', '.join(['?'] * len(cols))})")
        with db.conn() as c:
            cur = c.execute(sql, list(data.values()))
            return jsonify({"ok": True, "lastrowid": cur.lastrowid})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["PUT"])
@auth.login_required
def update_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data    = request.get_json(force=True, silent=True) or {}
    pks     = data.get("_pks", {})
    updates = data.get("_updates", {})
    if not pks or not updates:
        return jsonify({"ok": False, "error": "Missing primary keys or updates"}), 400
    try:
        set_clause   = ", ".join(f"{k} = ?" for k in updates)
        where_clause = " AND ".join(f"{k} = ?" for k in pks)
        sql = f"UPDATE {name} SET {set_clause} WHERE {where_clause}"
        with db.conn() as c:
            c.execute(sql, list(updates.values()) + list(pks.values()))
            return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/table/<name>/row", methods=["DELETE"])
@auth.login_required
def delete_row(name):
    if name not in ALL_TABLES:
        abort(403)
    data = request.get_json(force=True, silent=True) or {}
    if not data:
        return jsonify({"ok": False, "error": "No primary keys provided"}), 400
    try:
        where_clause = " AND ".join(f"{k} = ?" for k in data)
        sql = f"DELETE FROM {name} WHERE {where_clause}"
        with db.conn() as c:
            c.execute(sql, list(data.values()))
            return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/sql", methods=["POST"])
@auth.login_required
def execute_sql():
    data = request.get_json(force=True, silent=True) or {}
    sql  = data.get("sql", "").strip()
    if not sql:
        return jsonify({"ok": False, "error": "No SQL provided"}), 400
    try:
        with db.conn() as c:
            cur = c.execute(sql)
            if cur.description:
                columns = [d[0] for d in cur.description]
                rows    = [_safe_row(dict(zip(columns, r))) for r in cur.fetchall()]
                return jsonify({"ok": True, "columns": columns, "rows": rows, "type": "select"})
            else:
                return jsonify({"ok": True, "changes": c.total_changes, "type": "exec"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/export/<name>")
@auth.login_required
def export_table(name):
    """Export a table as CSV or JSON. Strict whitelist enforced."""
    if name not in ALL_TABLES:
        abort(403)
    fmt = request.args.get("format", "csv").lower()
    try:
        with db.conn() as c:
            if not _table_exists(c, name):
                return "Table not found", 404
            rows = c.execute(f"SELECT * FROM {name}").fetchall()
            if not rows:
                return "Table is empty", 200
            data = [_safe_row(r) for r in rows]
            if fmt == "json":
                return Response(
                    json.dumps(data, indent=2),
                    mimetype="application/json",
                    headers={"Content-Disposition": f"attachment; filename={name}.json"},
                )
            output = io.StringIO()
            writer = csv.DictWriter(output, fieldnames=data[0].keys())
            writer.writeheader()
            writer.writerows(data)
            return Response(
                output.getvalue(), mimetype="text/csv",
                headers={"Content-Disposition": f"attachment; filename={name}.csv"},
            )
    except Exception as e:
        return str(e), 500


@bp.route("/api/stats")
@auth.login_required
def db_stats():
    try:
        db_path    = config.DB_PATH
        size_bytes = db_path.stat().st_size if db_path.exists() else 0
        counts: dict = {}
        with db.conn() as c:
            tables_count = c.execute(
                "SELECT COUNT(*) FROM sqlite_master "
                "WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_fts%'"
            ).fetchone()[0]
            for t in ["titles", "files", "app_users", "tid_payments", "watch_history",
                      "plans", "payment_methods", "received_sms_payments"]:
                try:
                    counts[t] = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                except Exception:
                    counts[t] = 0
        return jsonify({"ok": True, "size_bytes": size_bytes,
                        "tables_count": tables_count, "row_counts": counts,
                        "ts": int(time.time())})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Smart Bulk Enrichment — multi-source merge strategy
# Sources: TMDB (full details+credits) → OMDB → IMDbAPI.dev → AI → YouTube → Google KG
# Only missing fields are filled; existing data is NEVER overwritten.
# ─────────────────────────────────────────────────────────────────────────────
import urllib.parse as _uparse
import urllib.request as _ureq
import re as _re

_TMDB_W500    = "https://image.tmdb.org/t/p/w500"
_TMDB_ORIG    = "https://image.tmdb.org/t/p/original"
_ENRICH_REQD  = ["poster", "overview", "genres_csv", "cast_names", "director",
                  "rating", "imdb_rating"]


def _needs_enrichment(row: dict) -> list[str]:
    """Return list of missing field names. Empty list → row is complete, skip."""
    missing = []
    for f in _ENRICH_REQD:
        # overview and plot are aliases
        val = row.get(f) or (row.get("plot") if f == "overview" else None)
        if not val:
            missing.append(f)
    return missing


def _http_json(url: str, timeout: float = 12.0):
    """GET url → parsed JSON, or None on any failure."""
    try:
        req = _ureq.Request(url, headers={
            "User-Agent": "Radd-Hub/4.0",
            "Accept":     "application/json",
        })
        with _ureq.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", errors="replace"))
    except Exception:
        return None


def _tmdb_full(title: str, year, media_type: str, keys_list: list) -> dict:
    """Search TMDB → fetch full detail+credits response → return rich field dict."""
    q  = _uparse.quote_plus(title or "")
    yr = str(year or "")[:4]
    yr_int = int(yr) if yr.isdigit() else None
    mt = (media_type or "movie").lower()

    for key in keys_list:
        try:
            hit = None
            hit_kind = "movie"
            search_order = ["tv", "movie"] if mt in ("tv", "drama", "anime", "series") else ["movie", "tv"]

            for kind in search_order:
                yp = (f"&year={yr_int}" if yr_int and kind == "movie"
                      else (f"&first_air_date_year={yr_int}" if yr_int else ""))
                for lang_p in ["", "&language=hi-IN"]:
                    data = _http_json(
                        f"https://api.themoviedb.org/3/search/{kind}"
                        f"?api_key={key}&query={q}{yp}{lang_p}"
                    )
                    results = (data or {}).get("results") or []
                    if results:
                        wt   = title.lower().strip()
                        best = results[0]
                        for r in results:
                            tn = (r.get("title") or r.get("name") or "").lower()
                            if tn == wt:
                                best = r
                                break
                        hit      = best
                        hit_kind = kind
                        break
                if hit:
                    break

            if not hit or not hit.get("id"):
                continue

            tmdb_id = hit["id"]
            det = _http_json(
                f"https://api.themoviedb.org/3/{hit_kind}/{tmdb_id}"
                f"?api_key={key}&append_to_response=credits,external_ids"
            )
            if not det:
                continue

            out: dict = {"tmdb_id": tmdb_id, "media_type": hit_kind}

            # Title / original
            out["title"]          = hit.get("title") or hit.get("name") or title
            out["original_title"] = (hit.get("original_title") or
                                     hit.get("original_name") or title)

            # Year / release_date
            rd = hit.get("release_date") or hit.get("first_air_date") or ""
            if rd:
                out["release_date"] = rd
                try:
                    out["year"] = int(rd[:4])
                except Exception:
                    pass
            if not out.get("year") and yr_int:
                out["year"] = yr_int

            # Poster + backdrop
            pp = det.get("poster_path") or ""
            if pp:
                out["poster"] = f"{_TMDB_W500}{pp}"
            bp = det.get("backdrop_path") or ""
            if bp:
                out["backdrop"] = f"{_TMDB_ORIG}{bp}"

            # Rating
            va = det.get("vote_average")
            if va:
                out["rating"] = round(float(va), 1)
            vc = det.get("vote_count")
            if vc:
                out["vote_count"] = int(vc)

            # Overview
            ov = (det.get("overview") or "").strip()
            if ov:
                out["overview"] = ov
                out["plot"]     = ov

            # Genres
            genres = [g["name"] for g in (det.get("genres") or []) if g.get("name")]
            if genres:
                out["genres_csv"] = ", ".join(genres)
                out["genres"]     = json.dumps(genres)

            # Runtime / seasons
            if hit_kind == "movie":
                rt = det.get("runtime")
                if rt:
                    out["runtime"] = int(rt)
            else:
                rts = det.get("episode_run_time") or []
                if rts:
                    out["runtime"] = int(rts[0])
                sc = det.get("number_of_seasons")
                if sc:
                    out["season_count"] = int(sc)
                ec = det.get("number_of_episodes")
                if ec:
                    out["episode_count"] = int(ec)

            # External IDs → imdb_id
            ext  = det.get("external_ids") or {}
            imdb = ext.get("imdb_id") or ""
            if imdb:
                out["imdb_id"] = imdb

            # Credits → cast + director
            credits   = det.get("credits") or {}
            cast_list = (credits.get("cast") or [])[:10]
            if cast_list:
                out["cast_names"] = ", ".join(
                    c["name"] for c in cast_list if c.get("name")
                )
                out["cast"] = json.dumps([
                    {"name": c.get("name"), "character": c.get("character", "")}
                    for c in cast_list if c.get("name")
                ])
            crew       = credits.get("crew") or []
            directors  = [c["name"] for c in crew
                          if c.get("job") == "Director" and c.get("name")]
            if directors:
                out["director"] = ", ".join(directors)

            # Language
            ol = det.get("original_language") or ""
            if ol:
                out["original_lang"] = ol

            return out

        except Exception:
            continue

    return {}


def _omdb_full(title: str, year, keys_list: list) -> dict:
    """OMDB → IMDB rating, director, cast, genres, runtime, full plot."""
    q  = _uparse.quote_plus(title or "")
    yp = f"&y={str(year or '')[:4]}" if year else ""

    for key in keys_list:
        try:
            data = None
            for ttype in ["movie", "series", ""]:
                tp = f"&type={ttype}" if ttype else ""
                d  = _http_json(
                    f"https://www.omdbapi.com/?apikey={key}&t={q}{yp}{tp}&plot=full"
                )
                if d and d.get("Response") == "True":
                    data = d
                    break
            if not data:
                continue

            def clean(v: str) -> str:
                s = (v or "").strip()
                return "" if s in ("N/A", "None", "null", "-", "") else s

            def flt(s) -> float | None:
                try:
                    return float(_re.sub(r"[^0-9.]", "", str(s or ""))) or None
                except Exception:
                    return None

            # IMDB rating from Ratings list first, then imdbRating field
            imdb_rating = None
            for r in (data.get("Ratings") or []):
                if "Internet Movie Database" in r.get("Source", ""):
                    try:
                        imdb_rating = float(r["Value"].split("/")[0])
                    except Exception:
                        pass
            if not imdb_rating:
                imdb_rating = flt(data.get("imdbRating"))

            rt_m    = _re.search(r"(\d+)", data.get("Runtime") or "")
            runtime = int(rt_m.group(1)) if rt_m else None

            genres_csv = ", ".join(
                g.strip() for g in clean(data.get("Genre") or "").split(",") if g.strip()
            )
            cast_names = ", ".join(
                a.strip() for a in clean(data.get("Actors") or "").split(",") if a.strip()
            )

            poster = clean(data.get("Poster") or "")
            if poster and not poster.startswith("http"):
                poster = ""

            yr_m = _re.search(r"(?:19|20)\d{2}", data.get("Year") or "")
            yr_v = int(yr_m.group()) if yr_m else None

            ts           = flt(data.get("totalSeasons"))
            season_count = int(ts) if ts else None

            out = {
                "imdb_id":     clean(data.get("imdbID") or ""),
                "title":       clean(data.get("Title") or "") or title,
                "year":        yr_v,
                "media_type":  "tv" if data.get("Type") == "series" else "movie",
                "overview":    clean(data.get("Plot") or ""),
                "plot":        clean(data.get("Plot") or ""),
                "genres_csv":  genres_csv,
                "cast_names":  cast_names,
                "director":    clean(data.get("Director") or ""),
                "imdb_rating": imdb_rating,
                "poster":      poster,
                "runtime":     runtime,
                "language":    clean((data.get("Language") or "").split(",")[0].strip()),
                "country":     clean((data.get("Country") or "").split(",")[0].strip()[:2].upper()),
            }
            if season_count:
                out["season_count"] = season_count

            return {k: v for k, v in out.items() if v not in (None, "", 0)}

        except Exception:
            continue

    return {}


def _enrich_merged(row: dict, log_fn=None, force: bool = False) -> dict:
    """
    Run all 6 enrichment sources and merge their results.
    IMDbAPI leads because it has the best Asian/Pakistani/Bollywood coverage and is free.
    Priority per field:
      poster      → IMDbAPI > TMDB > YouTube > Google KG > OMDB
      imdb_rating → IMDbAPI > OMDB > AI
      rating      → IMDbAPI > TMDB > AI
      overview    → IMDbAPI > TMDB > OMDB > AI > Google KG
      genres_csv  → IMDbAPI > TMDB > OMDB > AI
      cast_names  → IMDbAPI > OMDB > TMDB > AI
      director    → IMDbAPI > OMDB > TMDB > AI
    When force=True, overwrites even existing non-null fields.
    Returns dict of fields to UPDATE.
    """
    from .. import metadata_lookup as ml

    title = (row.get("title") or "").strip()
    year  = row.get("year")
    mt    = row.get("media_type") or "movie"
    if not title:
        return {}

    def say(msg: str):
        if log_fn:
            log_fn(msg)

    sources: dict[str, dict] = {}
    tmdb_keys = ml._tmdb_keys({})
    omdb_keys = ml._omdb_keys({})

    # 1. TMDB — best poster quality + full credits
    if tmdb_keys:
        say("→ TMDB …")
        r = _tmdb_full(title, year, mt, tmdb_keys)
        if r:
            sources["tmdb"] = r
            say(f"  ✓ TMDB: {r.get('title')} ({r.get('year')}) "
                f"poster={bool(r.get('poster'))} rating={r.get('rating')} "
                f"cast={bool(r.get('cast_names'))}")
        else:
            say("  ✗ TMDB: not found")
    else:
        say("  — TMDB: no keys configured")

    # 2. OMDB — IMDB rating, director, full cast, runtime
    if omdb_keys:
        say("→ OMDB …")
        r = _omdb_full(title, year, omdb_keys)
        if r:
            sources["omdb"] = r
            say(f"  ✓ OMDB: imdb_rating={r.get('imdb_rating')} "
                f"dir={r.get('director')!r} cast={bool(r.get('cast_names'))}")
        else:
            say("  ✗ OMDB: not found")
    else:
        say("  — OMDB: no keys configured")

    # 3. IMDbAPI.dev — free, no key, great for Pakistani/Bollywood/South Asian
    say("→ IMDbAPI.dev …")
    try:
        r = ml._imdbapi_search(title, year, mt) or {}
        if r:
            sources["imdbapi"] = r
            say(f"  ✓ IMDbAPI: {r.get('title')} imdb={r.get('imdb_id')!r} "
                f"poster={bool(r.get('poster'))}")
        else:
            say("  ✗ IMDbAPI: not found")
    except Exception as exc:
        say(f"  ✗ IMDbAPI error: {exc}")

    # 4. AI (Groq→Gemini→OpenAI→OpenRouter) — only if fields still missing
    still_missing = [f for f in _ENRICH_REQD
                     if not row.get(f) and not any(s.get(f) for s in sources.values())]
    if still_missing:
        say(f"→ AI fallback (missing: {', '.join(still_missing)}) …")
        try:
            r = ml._ai_search(title, year, {}) or {}
            if r:
                sources["ai"] = r
                say(f"  ✓ AI ({r.get('source','ai')}): {r.get('title')} ({r.get('year')})")
            else:
                say("  ✗ AI: no result from any provider")
        except Exception as exc:
            say(f"  ✗ AI error: {exc}")
    else:
        say("  — AI: skipped (all required fields covered)")

    # 5. YouTube — poster-only last resort
    need_poster = (not row.get("poster") and
                   not any(s.get("poster") for s in sources.values()))
    if need_poster:
        say("→ YouTube (poster fallback) …")
        try:
            r = ml._youtube_search(title, year) or {}
            if r.get("poster"):
                sources["youtube"] = r
                say(f"  ✓ YouTube: poster acquired")
            else:
                say("  ✗ YouTube: no poster found")
        except Exception as exc:
            say(f"  ✗ YouTube error: {exc}")

    # 6. Google Knowledge Graph — poster + overview, absolute last resort
    need_gkg = (
        (not row.get("poster") and
         not any(s.get("poster") for s in sources.values())) or
        (not row.get("overview") and not row.get("plot") and
         not any(s.get("overview") for s in sources.values()))
    )
    if need_gkg:
        say("→ Google Knowledge Graph …")
        try:
            r = ml._google_search(title, year) or {}
            if r:
                sources["gkg"] = r
                say(f"  ✓ Google KG: overview={bool(r.get('overview'))} "
                    f"poster={bool(r.get('poster'))}")
        except Exception as exc:
            say(f"  ✗ Google KG error: {exc}")

    if not sources:
        return {}

    # ── Merge ────────────────────────────────────────────────────────────────
    # IMDbAPI leads — best Asian/Pakistani/Bollywood/South Asian coverage, fully free
    PRIO = ["imdbapi", "tmdb", "omdb", "ai", "youtube", "gkg"]

    def pick(field: str, prio: list | None = None):
        for src in (prio or PRIO):
            v = sources.get(src, {}).get(field)
            if v is not None and v != "" and v != "N/A":
                return v
        return None

    updates: dict = {}

    def merge(field: str, value, existing_key: str | None = None):
        """Write to updates only if row is missing this field, or force=True overwrites."""
        ek  = existing_key or field
        cur = row.get(ek)
        if (force or cur in (None, "", 0, "N/A")) and value not in (None, "", 0, "N/A"):
            updates[field] = value

    # External IDs
    merge("tmdb_id",        pick("tmdb_id",        ["tmdb", "imdbapi"]))
    merge("imdb_id",        pick("imdb_id",        ["imdbapi", "omdb", "tmdb"]))
    merge("original_title", pick("original_title"))
    merge("release_date",   pick("release_date",   ["imdbapi", "tmdb", "omdb"]))

    # Core metadata
    yr = pick("year", ["imdbapi", "tmdb", "omdb"])
    if yr is not None:
        merge("year", str(yr))
    merge("media_type", pick("media_type"))

    # Ratings
    merge("rating",      pick("rating",      ["imdbapi", "tmdb", "ai"]))
    merge("imdb_rating", pick("imdb_rating", ["imdbapi", "omdb", "ai"]))
    merge("vote_count",  pick("vote_count",  ["tmdb", "imdbapi"]))

    # Descriptive text
    ov = pick("overview", ["imdbapi", "tmdb", "omdb", "ai", "gkg"])
    merge("overview", ov)
    merge("plot",     ov, existing_key="plot")
    merge("genres_csv", pick("genres_csv", ["imdbapi", "tmdb", "omdb", "ai"]))
    merge("genres",     pick("genres",     ["imdbapi", "tmdb"]))
    merge("cast_names", pick("cast_names", ["imdbapi", "omdb", "tmdb", "ai"]))
    merge("cast",       pick("cast",       ["imdbapi", "tmdb"]))
    merge("director",   pick("director",   ["imdbapi", "omdb", "tmdb", "ai"]))

    # Media specs
    merge("runtime",       pick("runtime",       ["imdbapi", "omdb", "tmdb"]))
    merge("season_count",  pick("season_count",  ["imdbapi", "omdb", "tmdb"]))
    merge("episode_count", pick("episode_count", ["imdbapi", "tmdb"]))

    # Assets  — IMDbAPI first for Asian content, TMDB as quality backup
    merge("poster",      pick("poster",      ["imdbapi", "tmdb", "youtube", "gkg", "omdb"]))
    merge("backdrop",    pick("backdrop",    ["tmdb", "imdbapi"]))
    merge("trailer_url", pick("trailer_url", ["youtube", "imdbapi"]))

    # Country / language
    merge("country",  pick("country",  ["imdbapi", "omdb", "tmdb", "ai"]))
    merge("language", pick("language", ["imdbapi", "omdb", "tmdb", "ai"]))

    return {k: v for k, v in updates.items() if v not in (None, "", 0)}


@bp.route("/api/enrich", methods=["POST"])
@auth.login_required
def enrich_titles():
    """Bulk enrichment with multi-source merge. Streams SSE progress events."""
    from flask import stream_with_context as _swc

    data     = request.get_json(force=True, silent=True) or {}
    ids      = data.get("ids", [])
    do_force = bool(data.get("force", False))

    def generate():
        try:
            with db.conn() as c:
                if not ids or ids == "all":
                    rows = c.execute("SELECT * FROM titles ORDER BY id").fetchall()
                else:
                    ph   = ",".join("?" * len(ids))
                    rows = c.execute(
                        f"SELECT * FROM titles WHERE id IN ({ph}) ORDER BY id",
                        [int(i) for i in ids]
                    ).fetchall()

            total = len(rows)
            yield f"event: start\ndata: {json.dumps({'total': total})}\n\n"

            enriched = skipped = failed = 0
            t0 = time.time()

            for row in rows:
                rd  = _safe_row(row)
                rid = rd.get("id")
                ttl = rd.get("title") or f"ID {rid}"

                missing = _needs_enrichment(rd)
                if not do_force and not missing:
                    skipped += 1
                    yield (f"event: row\ndata: "
                           f"{json.dumps({'id': rid, 'title': ttl, 'status': 'skipped', 'reason': 'already complete'})}"
                           f"\n\n")
                    continue

                if do_force:
                    missing = _ENRICH_REQD  # all fields shown as targets when force-refreshing

                logs: list[str] = []
                yield (f"event: row\ndata: "
                       f"{json.dumps({'id': rid, 'title': ttl, 'status': 'enriching', 'missing': missing})}"
                       f"\n\n")

                try:
                    updates = _enrich_merged(rd, log_fn=logs.append, force=do_force)
                    if updates:
                        sets = ", ".join(f"{k} = ?" for k in updates)
                        vals = list(updates.values()) + [int(time.time()), rid]
                        with db.conn() as c:
                            c.execute(
                                f"UPDATE titles SET {sets}, updated_at = ? WHERE id = ?",
                                vals
                            )
                        enriched += 1
                        yield (f"event: row\ndata: "
                               f"{json.dumps({'id': rid, 'title': ttl, 'status': 'done', 'updated': list(updates.keys()), 'log': logs})}"
                               f"\n\n")
                    else:
                        failed += 1
                        yield (f"event: row\ndata: "
                               f"{json.dumps({'id': rid, 'title': ttl, 'status': 'failed', 'reason': 'no data from any source', 'log': logs})}"
                               f"\n\n")

                except Exception as exc:
                    failed += 1
                    yield (f"event: row\ndata: "
                           f"{json.dumps({'id': rid, 'title': ttl, 'status': 'failed', 'reason': str(exc), 'log': logs})}"
                           f"\n\n")

            elapsed = round(time.time() - t0, 1)
            yield (f"event: done\ndata: "
                   f"{json.dumps({'enriched': enriched, 'skipped': skipped, 'failed': failed, 'elapsed': elapsed})}"
                   f"\n\n")

        except Exception as exc:
            yield f"event: error\ndata: {json.dumps({'error': str(exc)})}\n\n"

    return Response(
        _swc(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Titles null-field stats — used by the DB Studio null stats bar
# ─────────────────────────────────────────────────────────────────────────────
@bp.route("/api/titles/nullstats")
@auth.login_required
def titles_null_stats():
    """Return per-field null/filled counts for the titles table."""
    FIELDS = [
        "poster", "overview", "genres_csv", "cast_names", "director",
        "rating", "imdb_rating", "imdb_id", "tmdb_id", "backdrop",
        "trailer_url", "year", "release_date", "original_title",
    ]
    try:
        with db.conn() as c:
            if not _table_exists(c, "titles"):
                return jsonify({"ok": False, "error": "titles table not found"})
            total = c.execute("SELECT COUNT(*) FROM titles").fetchone()[0]
            fields: dict = {}
            for f in FIELDS:
                try:
                    null_n = c.execute(
                        f"SELECT COUNT(*) FROM titles "
                        f"WHERE {f} IS NULL OR CAST({f} AS TEXT) = ''",
                    ).fetchone()[0]
                    fields[f] = {
                        "null":   null_n,
                        "filled": total - null_n,
                        "pct":    round((total - null_n) / total * 100) if total else 0,
                    }
                except Exception:
                    pass
            return jsonify({"ok": True, "total": total, "fields": fields})
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)})


# ─────────────────────────────────────────────────────────────────────────────
# CSV Export — download any table as a .csv file
# ─────────────────────────────────────────────────────────────────────────────
@bp.route("/api/export/<table>")
@auth.login_required
def export_table(table: str):
    """Stream a table as a CSV download. Respects ?q= search filter."""
    if table not in ALL_TABLES:
        abort(404)
    q = request.args.get("q", "").strip()
    try:
        with db.conn() as c:
            if not _table_exists(c, table):
                abort(404)
            cur = c.cursor()
            if q:
                col_names = [r[1] for r in c.execute(f"PRAGMA table_info({table})").fetchall()]
                text_cols = [n for n in col_names
                             if n not in ("id", "created_at", "updated_at")][:15]
                if text_cols:
                    conds = " OR ".join(f"CAST({n} AS TEXT) LIKE ?" for n in text_cols)
                    cur.execute(f"SELECT * FROM {table} WHERE {conds}", [f"%{q}%"] * len(text_cols))
                else:
                    cur.execute(f"SELECT * FROM {table}")
            else:
                cur.execute(f"SELECT * FROM {table}")

            rows      = cur.fetchall()
            col_names = [d[0] for d in cur.description]

            out = io.StringIO()
            w   = csv.writer(out)
            w.writerow(col_names)
            for row in rows:
                w.writerow([
                    v.decode("utf-8", errors="replace") if isinstance(v, bytes) else v
                    for v in row
                ])

            return Response(
                out.getvalue(),
                mimetype="text/csv",
                headers={"Content-Disposition": f'attachment; filename="{table}.csv"'},
            )
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)})
