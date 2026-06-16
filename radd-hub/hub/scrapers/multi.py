"""Multi-site search: runs all scrapers in parallel and merges results."""
from __future__ import annotations
import logging
import concurrent.futures
from typing import Optional

log = logging.getLogger("hub.scrapers.multi")

SCRAPERS = {
    "vegamovies":  "hub.scrapers.vegamovies",
    "rogmovies":   "hub.scrapers.rogmovies",
    "katmoviehd":  "hub.scrapers.katmoviehd",
    "ssrmovies":   "hub.scrapers.ssrmovies",
    "rareanimes":  "hub.scrapers.rareanimes",
}


def _load(module_name: str):
    import importlib
    try:
        return importlib.import_module(module_name)
    except Exception as e:
        log.error("Failed to load scraper %s: %s", module_name, e)
        return None


def search_all(
    title: str,
    year: str = "",
    sites: Optional[list[str]] = None,
    max_workers: int = 6,
    timeout: int = 30,
) -> list[dict]:
    """Search all (or selected) scrapers in parallel. Returns merged list sorted by site."""
    from .. import turbo_cache
    
    if sites is None:
        sites = list(SCRAPERS.keys())
    else:
        sites = [s for s in sites if s in SCRAPERS]

    results: list[dict] = []
    
    # 1. Global Cache Check
    cache_key = f"{title} {year}".strip().lower()
    cached_results = []
    for site in sites:
        hits = turbo_cache.get(cache_key, site, "search_results")
        if hits:
            cached_results.extend(hits)
            
    if cached_results:
        log.info("multi-search '%s': returning %d cached results", cache_key, len(cached_results))
        return cached_results

    def _search(site: str) -> list[dict]:
        mod = _load(SCRAPERS[site])
        if mod is None:
            return []
        try:
            hits = mod.search(title, year) or []
            if hits:
                # Save individual site results to cache
                turbo_cache.set(cache_key, site, "search_results", hits)
            return hits
        except Exception as e:
            log.warning("scraper %s search error: %s", site, e)
            return []

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = {ex.submit(_search, site): site for site in sites}
        for fut in concurrent.futures.as_completed(futures, timeout=timeout):
            site = futures[fut]
            try:
                hits = fut.result()
                for h in hits:
                    h.setdefault("site", site)
                results.extend(hits)
            except Exception as e:
                log.warning("scraper %s future error: %s", site, e)

    log.info("multi-search '%s %s': %d total results from %d sites", title, year, len(results), len(sites))
    return results


def get_links(page_url: str, site: str) -> list[dict]:
    """Get download links from a specific scraped page URL."""
    if site not in SCRAPERS:
        log.error("Unknown site: %s", site)
        return []
    mod = _load(SCRAPERS[site])
    if mod is None:
        return []
    try:
        return mod.get_download_links(page_url) or []
    except Exception as e:
        log.error("get_links %s %s: %s", site, page_url, e)
        return []
