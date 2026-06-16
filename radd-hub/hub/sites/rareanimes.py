"""
RareAnimes site plugin — v2.0 (Pure HTTP + Smart Ranking)

Architecture:
- Wraps hub.scrapers.rareanimes (Pure HTTP logic)
- Implements SitePlugin interface for Radd Hub v3 compatibility.
- Zero Playwright usage.
"""
from __future__ import annotations
import logging
import re
from .base import SitePlugin
from . import _cdn_resolvers
from hub.scrapers import rareanimes as logic

log = logging.getLogger("hub.sites.rareanimes")


class RareAnimesPlugin(SitePlugin):
    name        = "RareAnimes"
    description = "rareanimes.buzz — Anime specialist via Pure HTTP (v2.0)"
    version     = "2.0"
    domain_keys = ["domain_rareanimes"]

    def __init__(self):
        self._cdn_fallbacks: list[str] = []

    # ── Step 1: Search ────────────────────────────────────────────────────────

    def search(self, page, movie_name: str, config: dict, check_control=None, log_fn=None) -> str:
        year_hint = str(config.get("year_hint") or config.get("year") or "").strip()
        if log_fn:
            log_fn(f"rareanimes: Searching for '{movie_name}' year='{year_hint or 'any'}'...")

        results = logic.search(movie_name, year_hint)
        if not results:
            raise RuntimeError(f"No results found on RareAnimes for '{movie_name}'.")

        # Candidate Validation
        from hub.scraper import _validate_post_relevance
        for candidate in results[:5]:
            url = candidate["url"]
            ok, msg = _validate_post_relevance(movie_name, url, config)
            if ok:
                if log_fn:
                    log_fn(f"rareanimes: Match found ({msg}) → '{candidate.get('title', '?')}'")
                return url
            else:
                if log_fn:
                    log_fn(f"rareanimes: Candidate rejected ({msg}) → {url[:40]}...")

        raise RuntimeError(f"No relevant results on RareAnimes for '{movie_name}' after validation.")

    # ── Step 2: Post Page → Download Links ────────────────────────────────────

    def get_download_link(self, page, movie_url: str, config: dict,
                          check_control=None, log_fn=None) -> str:
        if log_fn:
            log_fn(f"rareanimes: Analyzing post links: {movie_url}")

        links = logic.get_download_links(movie_url)
        if not links:
            raise RuntimeError(f"No download links found on RareAnimes page: {movie_url}")

        # Quality selection logic
        pref_q = (config.get("preferred_quality") or "720p").lower()
        preferred = [l for l in links if pref_q in l.get("quality", "").lower()]
        
        if not preferred:
            preferred = [l for l in links if "720p" in l.get("quality", "").lower()]
        if not preferred:
            preferred = [l for l in links if "1080p" in l.get("quality", "").lower()]
        if not preferred:
            preferred = links

        best = preferred[0]
        target_url = best["url"]
        
        if log_fn:
            log_fn(f"rareanimes: Selected: {best.get('label', 'Link')} → {target_url[:60]}...")

        self._cdn_fallbacks = [l["url"] for l in preferred[1:5]]
        return target_url

    # ── Step 3: Bridge Resolution ─────────────────────────────────────────────

    def get_bridge_link(self, page, bridge_url: str, config: dict,
                        check_control=None, log_fn=None) -> str:
        all_candidates = [bridge_url] + self._cdn_fallbacks
        self._cdn_fallbacks = []

        winner = _cdn_resolvers.race_cdn_links(all_candidates, timeout=30)
        if winner: return winner

        return bridge_url

    # ── Step 4: Final Link Resolution ─────────────────────────────────────────

    def get_final_link(self, page, cdn_url: str, config: dict,
                       check_control=None, log_fn=None) -> str:
        return _cdn_resolvers.resolve_any_cdn_http(cdn_url) or cdn_url
