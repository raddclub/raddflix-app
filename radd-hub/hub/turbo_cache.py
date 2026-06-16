"""Turbo Cache — persistent tiered caching for search and link selection.

Tiers:
  - 'search': Post URLs found for a movie query (30 days).
  - 'links': Final download links found for a post URL (24 hours).
"""
from __future__ import annotations
import json
import time
import logging
from typing import Optional, Any
from . import db

log = logging.getLogger("hub.turbo_cache")

# Tiered Expiry (seconds)
EXPIRY_SEARCH = 30 * 24 * 3600  # 30 days
EXPIRY_LINKS  = 24 * 3600       # 24 hours

def get(query: str, site: str, cat: str) -> Optional[Any]:
    """Retrieve data from cache if not expired."""
    now = int(time.time())
    with db.conn() as c:
        row = c.execute(
            "SELECT data, expires_at FROM turbo_cache WHERE query=? AND site=? AND cat=?",
            (query.lower().strip(), site, cat)
        ).fetchone()
        
        if row:
            if row["expires_at"] > now:
                try:
                    return json.loads(row["data"])
                except Exception:
                    return None
            else:
                # Cleanup expired entry
                c.execute(
                    "DELETE FROM turbo_cache WHERE query=? AND site=? AND cat=?",
                    (query.lower().strip(), site, cat)
                )
    return None

def set(query: str, site: str, cat: str, data: Any):
    """Store data in cache with tiered expiry."""
    now = int(time.time())
    # search_results and search (post URL) get 30 days
    expiry = EXPIRY_SEARCH if cat in ("search", "search_results") else EXPIRY_LINKS
    
    try:
        json_data = json.dumps(data)
        with db.conn() as c:
            c.execute(
                "INSERT INTO turbo_cache(query, site, cat, data, expires_at) "
                "VALUES(?,?,?,?,?) ON CONFLICT(query, site, cat) DO UPDATE SET "
                "data=excluded.data, expires_at=excluded.expires_at",
                (query.lower().strip(), site, cat, json_data, now + expiry)
            )
    except Exception as e:
        log.warning("turbo_cache: failed to set %s for %s: %s", cat, query, e)

def cleanup():
    """Prune all expired entries."""
    now = int(time.time())
    with db.conn() as c:
        c.execute("DELETE FROM turbo_cache WHERE expires_at < ?", (now,))
