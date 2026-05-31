"""
Poster Proxy API — server-side TMDB/OMDB key rotation

The Flutter app NEVER holds API keys. It calls this endpoint,
and we handle all key rotation and caching.

GET /api/poster/search?title=...&year=...&media_type=...
  → { "poster_url": "https://...", "source": "tmdb|omdb|none", "cached": true }

POST /api/poster/batch   body: [{title, year, media_type, id}, ...]
  → { "results": { "<id>": { "poster_url": ..., "source": ... } } }

Source priority: TMDB → OMDB → none
Caching: 30 days in SQLite (table: poster_cache)
Keys: stored as PLAINTEXT in radd_hub.db keys table (no encryption)
"""

import json
import logging
import os
import sqlite3
import time
from pathlib import Path
from flask import Blueprint, jsonify, request

log = logging.getLogger("hub.poster_proxy")

poster_proxy_bp = Blueprint("poster_proxy", __name__)

# ── DB paths ──────────────────────────────────────────────────────────────────

def _data_dir() -> Path:
    d = os.environ.get("RADD_HUB_DATA_DIR", "")
    if d:
        return Path(d)
    return Path(__file__).parent.parent.parent / "data"  # was: / "radd-hub" / "data" — wrong


def _radd_db() -> sqlite3.Connection:
    """Connection to the main Radd Hub DB (keys table)."""
    db_path = str(_data_dir() / "radd_hub.db")
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


# ── Plaintext key reading (NO encryption) ────────────────────────────────────

def _get_active_keys(provider: str) -> list[str]:
    """
    Read all active keys for provider from DB, decrypting Fernet values.
    Uses the keys vault module for proper decryption.
    """
    try:
        from hub import keys as _keys_mod
        conn = _radd_db()
        rows = conn.execute(
            "SELECT value_enc FROM keys WHERE provider=? AND is_active=1 ORDER BY last_used_at ASC",
            (provider,)
        ).fetchall()
        conn.close()
        result = []
        for r in rows:
            val = r["value_enc"]
            try:
                if isinstance(val, (bytes, bytearray)):
                    decrypted = _keys_mod.decrypt(val)
                else:
                    decrypted = _keys_mod.decrypt(val.encode("utf-8") if isinstance(val, str) else val)
                if decrypted and decrypted.strip():
                    result.append(decrypted.strip())
            except Exception:
                pass
        return result
    except Exception as e:
        log.warning("Failed to read keys from DB: %s", e)
        return []


def _mark_key_invalid(provider: str, value: str):
    """Mark a key as inactive after confirmed 401."""
    try:
        conn = _radd_db()
        conn.execute(
            "UPDATE keys SET is_active=0, last_status='invalid', failure_count=failure_count+1 "
            "WHERE provider=? AND value_enc=?",
            (provider, value)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        log.debug("mark_invalid failed: %s", e)


def _mark_key_ok(provider: str, value: str):
    """Record a successful use of a key."""
    try:
        conn = _radd_db()
        conn.execute(
            "UPDATE keys SET last_status='ok', total_uses=total_uses+1, last_used_at=? "
            "WHERE provider=? AND value_enc=?",
            (int(time.time()), provider, value)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        log.debug("mark_ok failed: %s", e)


# ── Poster cache (SQLite) ─────────────────────────────────────────────────────

_CACHE_TTL_DAYS = 30
_cache_conn = None


def _cache_db():
    global _cache_conn
    if _cache_conn:
        return _cache_conn
    cache_path = str(_data_dir() / "poster_cache.db")
    conn = sqlite3.connect(cache_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS poster_cache (
            cache_key   TEXT PRIMARY KEY,
            poster_url  TEXT,
            source      TEXT,
            cached_at   INTEGER,
            expires_at  INTEGER
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_pc_expires ON poster_cache(expires_at)")
    conn.commit()
    _cache_conn = conn
    return conn


def _make_cache_key(title: str, year: int, media_type: str) -> str:
    import hashlib
    raw = f"{title.lower().strip()}|{year}|{media_type}"
    return hashlib.md5(raw.encode()).hexdigest()


def _cache_get(title: str, year: int, media_type: str):
    key = _make_cache_key(title, year, media_type)
    now = int(time.time())
    try:
        row = _cache_db().execute(
            "SELECT poster_url, source FROM poster_cache WHERE cache_key=? AND expires_at>?",
            (key, now)
        ).fetchone()
        if row and row["source"] != "none":
            return {"poster_url": row["poster_url"], "source": row["source"], "cached": True}
    except Exception:
        pass
    return None


def _cache_set(title: str, year: int, media_type: str, poster_url: str, source: str):
    key = _make_cache_key(title, year, media_type)
    now = int(time.time())
    # Cache misses only for 6h; hits for 30 days
    ttl = 6 * 3600 if source == "none" else _CACHE_TTL_DAYS * 86400
    expires = now + ttl
    try:
        _cache_db().execute(
            "INSERT OR REPLACE INTO poster_cache(cache_key,poster_url,source,cached_at,expires_at)"
            " VALUES(?,?,?,?,?)",
            (key, poster_url, source, now, expires)
        )
        _cache_db().commit()
    except Exception:
        pass


# ── TMDB search ───────────────────────────────────────────────────────────────

_TMDB_SEARCH = "https://api.themoviedb.org/3/search/{kind}"
_TMDB_IMG    = "https://image.tmdb.org/t/p/w342"


def _search_tmdb(title: str, year: int, media_type: str) -> str | None:
    import requests as req

    # Also try env var fallback keys
    env_keys = [k for k in [
        os.environ.get("TMDB_API_KEY"),
        os.environ.get("TMDB_API_KEY_1"),
        os.environ.get("TMDB_API_KEY_2"),
    ] if k]

    db_keys = _get_active_keys("tmdb")
    all_keys = list(dict.fromkeys(db_keys + env_keys))  # deduplicated, DB first

    if not all_keys:
        log.warning("No TMDB keys available")
        return None

    kinds = ["movie", "tv"] if media_type in ("movie", "anime") else ["tv", "movie"]

    for api_key in all_keys:
        success = False
        for kind in kinds:
            params = {"api_key": api_key, "query": title, "language": "en-US"}
            if year and kind == "movie":
                params["year"] = year
            url = _TMDB_SEARCH.format(kind=kind)
            try:
                r = req.get(url, params=params, timeout=8)
                if r.status_code in (401, 403):
                    log.warning("TMDB key invalid (HTTP %s): %s...", r.status_code, api_key[:8])
                    _mark_key_invalid("tmdb", api_key)
                    break  # try next key
                if r.status_code == 429:
                    log.warning("TMDB key rate-limited (429)")
                    break  # try next key
                if r.status_code != 200:
                    continue
                results = r.json().get("results") or []
                if results and results[0].get("poster_path"):
                    _mark_key_ok("tmdb", api_key)
                    return _TMDB_IMG + results[0]["poster_path"]
                success = True  # API worked, just no poster
            except Exception as e:
                log.debug("TMDB request failed: %s", e)
        if success:
            break  # key worked but no poster found — no point trying next key
    return None


# ── OMDB search ───────────────────────────────────────────────────────────────

_OMDB_BASE = "https://www.omdbapi.com/"


def _search_omdb(title: str, year: int) -> str | None:
    import requests as req

    env_keys = [k for k in [
        os.environ.get("OMDB_API_KEY"),
        os.environ.get("OMDB_API_KEY_1"),
    ] if k]

    db_keys = _get_active_keys("omdb")
    all_keys = list(dict.fromkeys(db_keys + env_keys))

    if not all_keys:
        return None

    for api_key in all_keys:
        params = {"apikey": api_key, "t": title, "r": "json"}
        if year:
            params["y"] = year
        try:
            r = req.get(_OMDB_BASE, params=params, timeout=8)
            if r.status_code == 401:
                _mark_key_invalid("omdb", api_key)
                continue
            if r.status_code != 200:
                continue
            data = r.json()
            if data.get("Response") == "True":
                poster = data.get("Poster", "")
                if poster and poster != "N/A":
                    _mark_key_ok("omdb", api_key)
                    return poster
        except Exception as e:
            log.debug("OMDB request failed: %s", e)
    return None




# ── IMDbAPI.dev search (free, no key, great for Pakistani/South Asian content) ─

_IMDBAPI_BASE = "https://imdbapi.dev/api/v1"

def _search_imdbapi(title: str, year: int, media_type: str) -> str | None:
    """Search IMDbAPI.dev — free API, no key needed. Best for Pakistani/Punjabi content."""
    import requests as req
    import urllib.parse
    
    kinds = ["movie"] if media_type in ("movie",) else ["tvSeries", "movie"]
    if media_type in ("drama", "series", "tv", "show", "anime"):
        kinds = ["tvSeries", "tvMiniSeries", "movie"]
    
    for kind in kinds:
        try:
            params = {"q": title, "type": kind}
            if year:
                params["year"] = str(year)
            r = req.get(f"{_IMDBAPI_BASE}/titles/search",
                       params=params, timeout=10,
                       headers={"User-Agent": "RaddFlix/1.5"})
            if r.status_code != 200:
                continue
            results = r.json()
            if not isinstance(results, list):
                results = (results or {}).get("results") or []
            for item in results[:3]:
                img = item.get("primaryImage") or {}
                url = img.get("url") or ""
                # Also check top-level poster field
                if not url:
                    url = item.get("poster") or item.get("image") or ""
                if url and url.startswith("http"):
                    log.info("IMDbAPI hit for %r: %s", title, url[:60])
                    return url
        except Exception as e:
            log.debug("IMDbAPI.dev failed for %r: %s", title, e)
    return None


# ── YouTube thumbnail fallback (last resort for regional content) ─────────────

def _search_youtube_poster(title: str, year: int) -> str | None:
    """Search YouTube for a trailer and use maxresdefault thumbnail as poster."""
    import requests as req, re as _re, urllib.parse as _up
    query = f"{title} {year or ''} official trailer".strip()
    search_url = f"https://www.youtube.com/results?search_query={_up.quote(query)}"
    try:
        r = req.get(search_url,
                   headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
                   timeout=12)
        video_ids = _re.findall('"videoId":"([^"]+)"', r.text)
        if video_ids:
            v_id = video_ids[0]
            poster = f"https://img.youtube.com/vi/{v_id}/maxresdefault.jpg"
            check = req.head(poster, timeout=5)
            if check.status_code == 200 and int(check.headers.get("content-length", 0)) > 5000:
                return poster
            return f"https://img.youtube.com/vi/{v_id}/hqdefault.jpg"
    except Exception as e:
        log.debug("YouTube poster fallback failed for %r: %s", title, e)
    return None

# ── Endpoints ─────────────────────────────────────────────────────────────────

@poster_proxy_bp.route("/api/poster/search")
def poster_search():
    title = (request.args.get("title") or "").strip()
    year_str = request.args.get("year", "0")
    media_type = (request.args.get("media_type") or "movie").lower()

    if not title:
        return jsonify({"error": "title is required"}), 400

    try:
        year = int(year_str)
    except Exception:
        year = 0

    cached = _cache_get(title, year, media_type)
    if cached:
        return jsonify(cached)

    poster_url = _search_tmdb(title, year, media_type)
    if poster_url:
        _cache_set(title, year, media_type, poster_url, "tmdb")
        return jsonify({"poster_url": poster_url, "source": "tmdb", "cached": False})

    poster_url = _search_omdb(title, year)
    if poster_url:
        _cache_set(title, year, media_type, poster_url, "omdb")
        return jsonify({"poster_url": poster_url, "source": "omdb", "cached": False})

    # IMDbAPI.dev — free, no key, great for Pakistani/Punjabi/South Asian content
    poster_url = _search_imdbapi(title, year, media_type)
    if poster_url:
        _cache_set(title, year, media_type, poster_url, "imdbapi")
        return jsonify({"poster_url": poster_url, "source": "imdbapi", "cached": False})

    # YouTube thumbnail — absolute last resort
    poster_url = _search_youtube_poster(title, year)
    if poster_url:
        _cache_set(title, year, media_type, poster_url, "youtube")
        return jsonify({"poster_url": poster_url, "source": "youtube", "cached": False})

    _cache_set(title, year, media_type, "", "none")
    return jsonify({"poster_url": None, "source": "none", "cached": False})


@poster_proxy_bp.route("/api/poster/batch", methods=["POST"])
def poster_batch():
    items = request.get_json()
    if not isinstance(items, list):
        return jsonify({"error": "body must be a JSON array"}), 400

    results = {}
    for item in items[:50]:
        item_id = str(item.get("id", ""))
        title = (item.get("title") or "").strip()
        year = int(item.get("year") or 0)
        media_type = (item.get("media_type") or "movie").lower()

        if not title:
            continue

        cached = _cache_get(title, year, media_type)
        if cached:
            results[item_id] = cached
            continue

        poster_url = _search_tmdb(title, year, media_type)
        source = "tmdb"
        if not poster_url:
            poster_url = _search_omdb(title, year)
            source = "omdb" if poster_url else "none"
        if not poster_url:
            poster_url = _search_imdbapi(title, year, media_type)
            source = "imdbapi" if poster_url else "none"
        if not poster_url:
            poster_url = _search_youtube_poster(title, year)
            source = "youtube" if poster_url else "none"

        _cache_set(title, year, media_type, poster_url or "", source)
        results[item_id] = {"poster_url": poster_url, "source": source, "cached": False}

    return jsonify({"results": results})


@poster_proxy_bp.route("/api/poster/keys")
def poster_keys_status():
    """Show active key counts (values masked). No auth — internal use only."""
    tmdb = _get_active_keys("tmdb")
    omdb = _get_active_keys("omdb")
    return jsonify({
        "tmdb": {"count": len(tmdb), "keys": [k[:8] + "..." for k in tmdb]},
        "omdb": {"count": len(omdb), "keys": [k[:8] + "..." for k in omdb]},
    })


@poster_proxy_bp.route("/api/poster/add_key", methods=["POST"])
def add_poster_key():
    """
    Add a new TMDB or OMDB key as plaintext.
    POST body: {"provider": "tmdb", "key": "abc123", "label": "key3"}
    """
    data = request.get_json() or {}
    provider = (data.get("provider") or "").lower()
    value = (data.get("key") or "").strip()
    label = (data.get("label") or "").strip()

    if provider not in ("tmdb", "omdb"):
        return jsonify({"error": "provider must be tmdb or omdb"}), 400
    if not value:
        return jsonify({"error": "key is required"}), 400

    try:
        now = int(time.time())
        conn = _radd_db()
        cur = conn.execute(
            "INSERT INTO keys(provider,label,value_enc,is_active,created_at,updated_at) VALUES(?,?,?,1,?,?)",
            (provider, label, value, now, now)
        )
        conn.commit()
        key_id = cur.lastrowid
        conn.close()
        return jsonify({"success": True, "id": key_id, "provider": provider})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
