"""
SSRMovies site plugin — v2.0 (Pure HTTP + Linkszilla Bridge)

Architecture:
- Wraps hub.scrapers.ssrmovies (Pure HTTP logic)
- Implements SitePlugin interface for Radd Hub v3 compatibility.
- Uses _cdn_helper to parse Linkszilla/Direct-Cloud bridges.
- Zero Playwright usage.
"""
from __future__ import annotations
import logging
import re
from .base import SitePlugin
from . import _cdn_resolvers, _cdn_helper
from hub.scrapers import ssrmovies as logic

log = logging.getLogger("hub.sites.ssrmovies")


class SSRMoviesPlugin(SitePlugin):
    name        = "SSRMovies"
    description = "ssrmovies.irish — Dual-audio via linkszilla CDN bridge (Pure HTTP v2.0)"
    version     = "2.0"
    domain_keys = ["domain_ssrmovies"]

    def __init__(self):
        self._cdn_fallbacks: list[str] = []

    # ── Step 1: Search ────────────────────────────────────────────────────────

    def search(self, page, movie_name: str, config: dict, check_control=None, log_fn=None) -> str:
        year_hint = str(config.get("year_hint") or config.get("year") or "").strip()
        if log_fn:
            log_fn(f"ssrmovies: Searching for '{movie_name}' year='{year_hint or 'any'}'...")

        results = logic.search(movie_name, year_hint)
        if not results:
            raise RuntimeError(f"No results found on SSRMovies for '{movie_name}'.")

        # Candidate Validation
        from hub.scraper import _validate_post_relevance
        for candidate in results[:5]:
            url = candidate["url"]
            ok, msg = _validate_post_relevance(movie_name, url, config)
            if ok:
                if log_fn:
                    log_fn(f"ssrmovies: Match found ({msg}) → '{candidate.get('title', '?')}'")
                return url
            else:
                if log_fn:
                    log_fn(f"ssrmovies: Candidate rejected ({msg}) → {url[:40]}...")

        raise RuntimeError(f"No relevant results on SSRMovies for '{movie_name}' after validation.")

    # ── Step 2: Post Page → Download Links ────────────────────────────────────

    def get_download_link(self, page, movie_url: str, config: dict,
                          check_control=None, log_fn=None) -> str:
        if log_fn:
            log_fn(f"ssrmovies: Analyzing post links: {movie_url}")

        links = logic.get_download_links(movie_url)
        if not links:
            raise RuntimeError(f"No download links found on SSRMovies page: {movie_url}")

        # Quality selection logic (prefer user quality)
        pref_q = (config.get("preferred_quality") or "720p").lower()
        preferred = [l for l in links if pref_q in l.get("quality", "").lower()]
        
        if not preferred:
            # Fallback to any HD if preferred not found
            preferred = [l for l in links if any(q in l.get("quality", "").lower() for q in ["720p", "1080p", "4k"])]
        
        if not preferred:
            preferred = links

        best = preferred[0]
        target_url = best["url"]
        
        if log_fn:
            log_fn(f"ssrmovies: Selected: {best.get('label', 'Link')} → {target_url[:60]}...")

        self._cdn_fallbacks = [l["url"] for l in preferred[1:5]]
        return target_url

    # ── Step 3: Bridge Resolution ─────────────────────────────────────────────

    def get_bridge_link(self, page, bridge_url: str, config: dict,
                        check_control=None, log_fn=None) -> str:
        """Resolve Linkszilla/Direct-Cloud bridges using HTTP helpers."""
        if log_fn:
            log_fn("[SSRMovies] Resolving bridge/cdn mirrors…")

        bl = bridge_url.lower()
        if "linkszilla" in bl or "direct-cloud.top" in bl:
            # Parse linkszilla dumps (Plain HTTP)
            all_cdns = _cdn_helper._parse_linkszilla_cdns_http(bridge_url)
            if all_cdns:
                self._cdn_fallbacks = all_cdns[1:]
                return all_cdns[0]

        all_candidates = [bridge_url] + self._cdn_fallbacks
        self._cdn_fallbacks = []

        winner = _cdn_resolvers.race_cdn_links(all_candidates, timeout=30)
        if winner: return winner

        return bridge_url

    # ── Step 4: Final Link Resolution ─────────────────────────────────────────

    def get_final_link(self, page, cdn_url: str, config: dict,
                       check_control=None, log_fn=None) -> str:
        """Resolve final direct URL via HTTP race or direct resolver."""
        all_cdns = [cdn_url] + self._cdn_fallbacks
        self._cdn_fallbacks = []

        if len(all_cdns) > 1:
            winner = _cdn_resolvers.race_cdn_links(all_cdns, timeout=22)
            if winner: return winner

        return _cdn_resolvers.resolve_any_cdn_http(cdn_url) or cdn_url
