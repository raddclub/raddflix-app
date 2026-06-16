from __future__ import annotations
import json
import os
import time
import threading
from pathlib import Path
_BASE = Path(__file__).parent
_CACHE_DIR = _BASE / ".cache"
_CACHE_FILE = _CACHE_DIR / "search_cache.json"
TTL_OK_SEC = 6 * 3600
TTL_FAIL_SEC = 1 * 3600
_lock = threading.Lock()
_data: dict[str, dict] | None = None
def _load() -> dict:
    global _data
    if _data is not None:
        return _data

    try:
        if _CACHE_FILE.exists():
            _data = json.loads(_CACHE_FILE.read_text())
        else:
            _data = {}
    except Exception:
        _data = {}
    return _data
def _save() -> None:
    try:
        _CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _CACHE_FILE.write_text(json.dumps(_data or {}, indent=2))
    except Exception:
        pass
def _key(movie: str, site: str) -> str:
    return f"{site.lower()}::{movie.strip().lower()}"
def get(movie: str, site: str) -> dict | None:
    with _lock:
        d = _load().get(_key(movie, site))
        if not d:
            return None
        ts = d.get("ts", 0)
        ttl = TTL_FAIL_SEC if d.get("failed") else TTL_OK_SEC
        if time.time() - ts > ttl:
            return None
        return dict(d)
def update(movie: str, site: str, **steps) -> None:
    with _lock:
        data = _load()
        k = _key(movie, site)
        entry = data.get(k, {})
        entry.update({kk: vv for kk, vv in steps.items() if vv is not None})
        entry["ts"] = time.time()
        data[k] = entry
        _save()
def mark_failed(movie: str, site: str, error: str = "") -> None:
    update(movie, site, failed=True, error=error[:200])
def clear(movie: str | None = None, site: str | None = None) -> None:
    with _lock:
        data = _load()
        if movie is None and site is None:
            data.clear()
        else:
            mk = (movie or "").strip().lower()
            sk = (site or "").lower()
            for k in list(data.keys()):
                s, _, m = k.partition("::")
                if (not mk or mk == m) and (not sk or sk == s):
                    data.pop(k, None)
        _save()