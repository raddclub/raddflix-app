"""
KatMovieHD site plugin — v3.0 (Pure HTTP + Smart Ranking)

Architecture:
- Wraps hub.scrapers.katmoviehd (Pure HTTP logic with v5.6 alignment)
- Implements SitePlugin interface for Radd Hub v3 compatibility.
- Zero Playwright usage for search and extraction.
- Concurrent CDN racing for final link resolution.
"""
from __future__ import annotations
import logging
import re
from .base import SitePlugin
from . import _cdn_resolvers
from hub.scrapers import katmoviehd as logic

log = logging.getLogger("hub.sites.katmoviehd")


class KatMovieHDPlugin(SitePlugin):
    name        = "KatMovieHD"
    description = "katmoviehd.com — Global/Korean/Dual Audio via Pure HTTP (v3.0)"
    version     = "3.0"
    domain_keys = ["domain_katmoviehd"]

    def __init__(self):
        self._cdn_fallbacks: list[str] = []

    # ── Step 1: Search ────────────────────────────────────────────────────────

    def search(self, page, movie_name: str, config: dict, check_control=None, log_fn=None) -> str:
        """Uses Sitemap/REST discovery with smart ranking."""
        year_hint = str(config.get("year_hint") or config.get("year") or "").strip()
        if log_fn:
            log_fn(f"katmoviehd: Searching for '{movie_name}' year='{year_hint or 'any'}'...")

        pref_lang = str(config.get("language") or config.get("lang_hint") or "").strip()
        results = logic.search(movie_name, year_hint, preferred_lang=pref_lang)

        if not results:
            raise RuntimeError(f"No results found on KatMovieHD for '{movie_name}'.")

        # Candidate Validation
        from hub.scraper import _validate_post_relevance
        for candidate in results[:5]:
            url = candidate["url"]
            ok, msg = _validate_post_relevance(movie_name, url, config)
            if ok:
                if log_fn:
                    log_fn(f"katmoviehd: Match found ({msg}) → '{candidate.get('title', '?')}'")
                return url
            else:
                if log_fn:
                    log_fn(f"katmoviehd: Candidate rejected ({msg}) → {url[:40]}...")

        raise RuntimeError(f"No relevant results on KatMovieHD for '{movie_name}' after validation.")

    # ── Step 2: Post Page → Download Links ────────────────────────────────────

    def get_download_link(self, page, movie_url: str, config: dict,
                          check_control=None, log_fn=None) -> str:
        """Extract and filter links from the movie post."""
        if log_fn:
            log_fn(f"katmoviehd: Analyzing post links: {movie_url}")

        pref_lang = str(config.get("language") or config.get("lang_hint") or "").strip()
        config["_movie_url"] = movie_url # for referer

        links = logic.get_download_links(movie_url, preferred_lang=pref_lang)
        if not links:
            raise RuntimeError(f"No download links found on KatMovieHD page: {movie_url}")

        # Priority: 720p > 480p > 1080p
        preferred = [l for l in links if "720p" in l.get("quality", "").lower()]
        if not preferred:
            preferred = [l for l in links if "480p" in l.get("quality", "").lower()]
        if not preferred:
            preferred = [l for l in links if "1080p" in l.get("quality", "").lower()]
        if not preferred:
            preferred = links

        best = preferred[0]
        target_url = best["url"]
        
        if log_fn:
            log_fn(f"katmoviehd: Selected: {best.get('label', 'Link')} → {target_url[:60]}...")

        self._cdn_fallbacks = [l["url"] for l in preferred[1:5]]
        return target_url

    # ── Step 3: Bridge Resolution ─────────────────────────────────────────────

    def get_bridge_link(self, page, bridge_url: str, config: dict,
                        check_control=None, log_fn=None) -> str:
        """Resolve bridge to CDN mirror."""
        if log_fn:
            log_fn("[KatMovieHD] Resolving bridge/cdn mirrors…")

        # Handle NexDrive explicitly
        if "nexdrive." in bridge_url.lower():
            try:
                res = _cdn_resolvers.resolve_nexdrive_http(bridge_url, referer=config.get("_movie_url"))
                if res: return res
            except Exception as e:
                if log_fn: log_fn(f"katmoviehd: nexdrive error: {e}")

        all_candidates = [bridge_url] + self._cdn_fallbacks
        self._cdn_fallbacks = []

        winner = _cdn_resolvers.race_cdn_links(all_candidates, timeout=30, referer=config.get("_movie_url"))
        if winner: return winner

        # Last-resort HTTP
        fallback = _cdn_resolvers.resolve_any_cdn_http(bridge_url, referer=config.get("_movie_url"))
        if fallback: return fallback

        raise RuntimeError("KatMovieHD: Failed to resolve a stable download link.")

    # ── Step 4: Final Link Resolution ─────────────────────────────────────────

    def get_final_link(self, page, cdn_url: str, config: dict,
                       check_control=None, log_fn=None) -> str:
        """Resolve final direct URL."""
        return _cdn_resolvers.resolve_any_cdn_http(cdn_url, referer=config.get("_movie_url")) or cdn_url
