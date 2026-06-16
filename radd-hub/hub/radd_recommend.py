"""F7 — TMDB recommendation engine seeded by the user's library.

Pulls the top-rated entries from the unified v3 library, asks TMDB for
"similar" titles per seed, dedupes against what the user already has, and
caches results for 12h in `recommendation_cache`.
"""
from __future__ import annotations
import json
import logging
import time
from typing import List, Optional
import requests
from . import db, keys

log = logging.getLogger("hub.recommend")

CACHE_TTL_S = 12 * 3600
SEED_LIMIT  = 12
TMDB_BASE   = "https://api.themoviedb.org/3"

def get_recommendations(limit: int = 24) -> List[dict]:
    """Main entry point: return a list of recommended titles."""
    try:
        owned_titles = _get_owned_titles()
        seeds = _get_seeds(SEED_LIMIT)
        
        bag = []
        seen_tmdb = set()
        
        for s in seeds:
            sid = s.get("tmdb_id")
            mtype = s.get("media_type") or "movie"
            if not sid:
                continue
            
            cached = _cache_get(sid, mtype)
            if cached is None:
                cached = _fetch_tmdb_recommendations(sid, mtype)
                if cached:
                    _cache_put(sid, mtype, cached)
            
            for item in (cached or []):
                tid = item.get("tmdb_id")
                if not tid or tid in seen_tmdb:
                    continue
                
                title_lower = item.get("title", "").lower().strip()
                if title_lower in owned_titles:
                    continue
                
                seen_tmdb.add(tid)
                bag.append(item)
                
                if len(bag) >= limit:
                    return bag
        
        return bag
    except Exception as e:
        log.warning("get_recommendations error: %s", e)
        return []


def _get_owned_titles() -> set[str]:
    owned = set()
    with db.conn() as c:
        rows = c.execute("SELECT title FROM titles").fetchall()
        for r in rows:
            if r["title"]:
                owned.add(r["title"].lower().strip())
    return owned


def _get_seeds(limit: int) -> List[dict]:
    with db.conn() as c:
        rows = c.execute(
            "SELECT tmdb_id, media_type, title, year, rating "
            "FROM titles WHERE tmdb_id IS NOT NULL "
            "ORDER BY COALESCE(rating, 0) DESC, created_at DESC LIMIT ?",
            (limit,)
        ).fetchall()
    return [dict(r) for r in rows]


def _cache_get(seed_id: int, mtype: str) -> Optional[List[dict]]:
    now = int(time.time())
    with db.conn() as c:
        row = c.execute(
            "SELECT payload_json, fetched_at FROM recommendation_cache "
            "WHERE seed_tmdb_id=? AND media_type=?",
            (seed_id, mtype)
        ).fetchone()
    
    if not row:
        return None
    if now - row["fetched_at"] > CACHE_TTL_S:
        return None
    
    try:
        return json.loads(row["payload_json"])
    except Exception:
        return None


def _cache_put(seed_id: int, mtype: str, payload: List[dict]) -> None:
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO recommendation_cache "
            "(seed_tmdb_id, media_type, payload_json, fetched_at) "
            "VALUES (?, ?, ?, ?)",
            (seed_id, mtype, json.dumps(payload[:30]), now)
        )


def _fetch_tmdb_recommendations(seed_id: int, mtype: str) -> List[dict]:
    api_key = keys.get_active_value("tmdb")
    if not api_key:
        log.warning("TMDB key missing, cannot fetch recommendations")
        return []
    
    url = f"{TMDB_BASE}/{mtype}/{seed_id}/recommendations"
    try:
        r = requests.get(url, params={"api_key": api_key, "language": "en-US"}, timeout=10)
        if r.status_code != 200:
            if r.status_code in (401, 403):
                keys.mark_invalid("tmdb", api_key)
            elif r.status_code == 429:
                keys.mark_exhausted("tmdb", api_key)
            return []
        
        results = r.json().get("results", [])
        out = []
        for it in results[:20]:
            out.append({
                "tmdb_id": it.get("id"),
                "title":   it.get("title") or it.get("name") or "",
                "year":    (it.get("release_date") or it.get("first_air_date") or "")[:4],
                "rating":  it.get("vote_average"),
                "overview": it.get("overview"),
                "poster":  f"https://image.tmdb.org/t/p/w342{it.get('poster_path')}" 
                           if it.get("poster_path") else "",
                "media_type": mtype,
                "why": "based on your library",
            })
        return out
    except Exception as e:
        log.warning("TMDB API error: %s", e)
        return []
