"""
VegaMovies site plugin — v4.0 (Smart Ranking + Nexdrive Bridge)

Architecture:
- Wraps hub.scrapers.vegamovies (Pure HTTP logic with v5.0 smart ranking)
- Implements SitePlugin interface for Radd Hub v3 compatibility.
- Nexdrive bridge pages are now properly parsed before CDN resolution.
- Zero Playwright usage.
"""
from __future__ import annotations
import logging
import re
from .base import SitePlugin
from . import _cdn_resolvers
from hub.scrapers import vegamovies as logic

log = logging.getLogger("hub.sites.vegamovies")


class VegaMoviesPlugin(SitePlugin):
    name        = "VegaMovies"
    description = "vegamovies.market — Hollywood/Korean/Western (Hindi Dubbed) via Sitemap + Pure HTTP (v4.0)"
    version     = "4.0"
    domain_keys = ["domain_vegamovies"]

    def __init__(self):
        self._cdn_fallbacks: list[str] = []

    @staticmethod
    def _extract_season(text: str) -> str:
        """Extract a season number from a query string like 'Solo Leveling Season 2' → '2'.
        Also handles 'S03' → '3' (strips leading zeros).
        """
        # Improved regex with word boundaries and specific prefixes
        m = re.search(r"\b(?:season|s)\s*0*(\d+)\b", text, re.I)
        return m.group(1) if m else ""

    # ── Step 1: Search ────────────────────────────────────────────────────────

    def search(self, page, movie_name: str, config: dict, check_control=None, log_fn=None) -> str:
        """
        Uses Sitemap-first discovery with smart year/title ranking.
        Returns the URL of the best matching post.
        Also stores the detected season_hint in config for downstream steps.
        """
        year_hint = str(config.get("year_hint") or config.get("year") or "").strip()
        if log_fn:
            log_fn(f"vegamovies: Searching for '{movie_name}' year='{year_hint or 'any'}'...")

        # Extract and persist season hint for use in get_download_link
        season = self._extract_season(movie_name) or self._extract_season(
            str(config.get("season", ""))
        )
        if season:
            config["_season_hint"] = season

        pref_lang = str(config.get("language") or config.get("lang_hint") or "").strip()
        results = logic.search(movie_name, year_hint, preferred_lang=pref_lang)

        if not results:
            raise RuntimeError(f"No results found on VegaMovies for '{movie_name}'.")

        # ── Candidate Validation Loop ──
        # Try the top 5 results to find one that passes the relevance check.
        # This prevents the job from dying if the #1 pick is a decoy.
        from hub.scraper import _validate_post_relevance
        
        for candidate in results[:5]:
            url = candidate["url"]
            ok, msg = _validate_post_relevance(movie_name, url, config)
            if ok:
                if log_fn:
                    log_fn(f"vegamovies: Match found ({msg}) → '{candidate.get('title', '?')}' — {url[:60]}...")
                return url
            else:
                if log_fn:
                    log_fn(f"vegamovies: Candidate rejected ({msg}) → {url[:40]}...")

        raise RuntimeError(f"No relevant results found on VegaMovies for '{movie_name}' after checking top candidates.")

    # ── Step 2: Post Page → Download Links ────────────────────────────────────

    def get_download_link(self, page, movie_url: str, config: dict,
                          check_control=None, log_fn=None) -> str:
        """Extract and filter links from the movie post."""
        if log_fn:
            log_fn(f"vegamovies: Analyzing post links: {movie_url}")

        # Retrieve season hint stored during search step
        season_hint = str(config.get("_season_hint") or config.get("season") or "").strip()
        pref_lang = str(config.get("language") or config.get("lang_hint") or "").strip()
        
        # Store movie_url in config for use as referer in get_final_link
        config["_movie_url"] = movie_url

        if season_hint and log_fn:
            log_fn(f"vegamovies: Season filter active: Season {season_hint}")

        links = logic.get_download_links(movie_url, season_hint=season_hint, preferred_lang=pref_lang)
        if not links:
            raise RuntimeError(f"No download links found on VegaMovies page: {movie_url}")

        # ── Smart Selection Logic ──
        # If we have a season_hint, prioritize "Complete Packs" (is_batch)
        if season_hint:
            batches = [l for l in links if l.get("is_batch")]
            if batches:
                if log_fn:
                    log_fn(f"vegamovies: Season detected, prioritizing {len(batches)} batch/pack links.")
                links = batches  # Filter to only batches for the quality selection below

        # Priority: 720p > (480p/360p) > 1080p (smallest size)
        
        # 1. Try 720p
        preferred = [l for l in links if "720p" in l.get("quality", "").lower()]
        
        # 2. Try 480p or 360p
        if not preferred:
            preferred = [l for l in links if any(q in l.get("quality", "").lower() for q in ["480p", "360p"])]
            if preferred and log_fn:
                log_fn("vegamovies: 720p not found, falling back to 480p/360p")

        # 3. Try 1080p (lowest size)
        if not preferred:
            p1080 = [l for l in links if "1080p" in l.get("quality", "").lower()]
            if p1080:
                if log_fn:
                    log_fn("vegamovies: 720p/480p/360p not found, falling back to 1080p (min size)")
                # Sort 1080p links by size (ascending)
                def _size_kb(l):
                    s = l.get("size", "").upper()
                    if not s: return 999999999
                    try:
                        num = float(re.search(r"(\d[\d.]+)", s).group(1))
                        if "GB" in s: num *= 1024 * 1024
                        elif "MB" in s: num *= 1024
                        return int(num)
                    except: return 999999999
                p1080.sort(key=_size_kb)
                preferred = p1080[:1]

        # 4. Final fallback: best available
        if not preferred:
            if log_fn:
                log_fn("vegamovies: Specified tiers not found, using best available.")
            preferred = links

        best = preferred[0]
        # Store is_batch status in config for use in get_bridge_link/get_final_link
        config["_is_batch"] = bool(best.get("is_batch"))
        
        target_url = best["url"]
        
        # If the URL is a PAYLOAD, we must extract a single valid URL to return
        # but store the full payload in config for bridge resolution.
        if target_url.startswith("PAYLOAD:"):
            config["_original_payload"] = target_url
            try:
                import json
                data = json.loads(target_url[8:])
                if isinstance(data, list) and len(data) > 0:
                    target_url = data[0].get("url", target_url)
            except: pass

        if log_fn:
            log_fn(f"vegamovies: Selected: {best.get('label', 'Link')} → {target_url[:60]}...")

        # Store fallbacks for CDN race
        self._cdn_fallbacks = [l["url"] for l in preferred[1:5]]

        return target_url

    # ── Step 3: Bridge Resolution ─────────────────────────────────────────────

    def get_bridge_link(self, page, bridge_url: str, config: dict,
                        check_control=None, log_fn=None, is_batch: bool = False) -> str:
        """Resolve a bridge URL (e.g. NexDrive) to a stable CDN mirror."""
        if log_fn:
            log_fn("[VegaMovies] Resolving bridge/cdn mirrors…")

        is_batch_mode = bool(is_batch or config.get("_is_batch"))
        
        # If bridge_url is already a payload, we extract the core URL for NexDrive check
        actual_bridge_url = bridge_url
        if bridge_url.startswith("PAYLOAD:"):
            try:
                import json
                data = json.loads(bridge_url[8:])
                if isinstance(data, list) and len(data) > 0:
                    actual_bridge_url = data[0].get("url", bridge_url)
            except: pass

        # Handle NexDrive explicitly if it matches
        if "nexdrive." in actual_bridge_url.lower():
            if log_fn:
                log_fn(f"vegamovies: Parsing nexdrive bridge page...")
            try:
                res = _cdn_resolvers.resolve_nexdrive_http(actual_bridge_url, referer=config.get("_movie_url"), is_batch=is_batch_mode)
                if res:
                    if log_fn:
                        log_fn(f"vegamovies: NexDrive resolved → {res[:60]}...")
                    return res
            except Exception as e:
                if log_fn: log_fn(f"vegamovies: nexdrive error: {e}")

        all_candidates = {bridge_url, actual_bridge_url}
        
        # Priority: If we have an original PAYLOAD from get_download_link, use it!
        orig_payload = config.get("_original_payload")
        if orig_payload:
            all_candidates.add(orig_payload)
        
        # Add any fallbacks collected during get_download_link
        for fb in self._cdn_fallbacks:
            all_candidates.add(fb)
        self._cdn_fallbacks = []  # clear

        if log_fn:
            log_fn(f"vegamovies: Racing {len(all_candidates)} unique CDN mirror(s) (batch_mode={is_batch_mode})...")

        # Pass movie_url as referer to help bypass CDN hotlink protection
        movie_url_ref = config.get("_movie_url", "")
        # Convert set to list for the race engine
        candidates_list = list(all_candidates)
        winner = _cdn_resolvers.race_cdn_links(candidates_list, timeout=30, referer=movie_url_ref, is_batch=is_batch_mode)
        
        if winner:
            # 1. If winner is already a payload, return it directly
            if winner.startswith("PAYLOAD:"):
                return winner
                
            # 2. Wrap single winner URL into a single-item PAYLOAD to restore metadata
            import json
            for cand in candidates_list:
                if cand.startswith("PAYLOAD:"):
                    try:
                        data = json.loads(cand[8:])
                        if isinstance(data, list):
                            for item in data:
                                if item.get("url") == winner:
                                    return "PAYLOAD:" + json.dumps([item])
                    except: pass
            return winner

        # Last-resort HTTP: try resolving just the first candidate directly
        if candidates_list:
            fallback = _cdn_resolvers.resolve_any_cdn_http(candidates_list[0], referer=movie_url_ref)
            if fallback: return fallback

        # Playwright last-resort: navigate the bridge URL(s) with a real browser
        try:
            from hub.sites._pw_fallback import pw_resolve_any_cdn
            if log_fn:
                log_fn("vegamovies: All HTTP bridge resolvers failed — launching browser as final fallback...")
            for cand_url in candidates_list[:3]:
                if cand_url.startswith("PAYLOAD:"):
                    try:
                        import json as _pj
                        _pd = _pj.loads(cand_url[8:])
                        if isinstance(_pd, list) and _pd:
                            cand_url = _pd[0].get("url", cand_url)
                    except Exception:
                        continue
                if cand_url.startswith("PAYLOAD:"):
                    continue
                pw_result = pw_resolve_any_cdn(cand_url, log_fn=log_fn)
                if pw_result:
                    if log_fn:
                        log_fn(f"vegamovies: Browser fallback succeeded → {pw_result[:60]}...")
                    return pw_result
        except Exception as pw_exc:
            if log_fn:
                log_fn(f"vegamovies: Browser fallback error: {pw_exc}")

        raise RuntimeError("VegaMovies: Failed to resolve a stable download link.")

    # ── Step 4: Final Link Resolution ─────────────────────────────────────────

    def get_final_link(self, page, cdn_url: str, config: dict,
                       check_control=None, log_fn=None, is_batch: bool = False) -> str:
        """Resolve the final direct download URL via CDN race engine."""
        # Use config hint if provided, otherwise trust the parameter
        is_batch_mode = config.get("_is_batch", is_batch)
        
        all_candidates: set[str] = set()
        for part in cdn_url.split("||"):
            part = part.strip()
            if part:
                all_candidates.add(part)
        
        # Add any fallbacks collected during get_download_link
        for fb in self._cdn_fallbacks:
            all_candidates.add(fb)
        self._cdn_fallbacks = []  # clear

        if log_fn:
            log_fn(f"vegamovies: Racing {len(all_candidates)} unique CDN mirror(s) (batch_mode={is_batch_mode})...")

        # Pass movie_url as referer to help bypass CDN hotlink protection
        movie_url_ref = config.get("_movie_url", "")
        # Convert set to list for the race engine
        candidates_list = list(all_candidates)
        winner = _cdn_resolvers.race_cdn_links(candidates_list, timeout=30, referer=movie_url_ref, is_batch=is_batch_mode)
        
        if winner:
            # If the winner is already a PAYLOAD, it might be a batch or a set of resolved links.
            # However, usually race_cdn_links returns a simple resolved direct URL.
            # If we were given a PAYLOAD originally, we must ensure we return a PAYLOAD.
            
            # 1. If winner is already a payload, return it directly
            if winner.startswith("PAYLOAD:"):
                return winner
                
            # 2. If it is a simple URL, check if we had a payload in our original candidates
            # that this winner belongs to. This is common when racing multiple mirrors.
            # For simplicity, if we have a winner, we wrap it in a single-item PAYLOAD
            # so that _do_download can extract its metadata if needed.
            
            # Look for the original PAYLOAD that contained this URL to restore metadata
            import json
            for cand in candidates_list:
                if cand.startswith("PAYLOAD:"):
                    try:
                        data = json.loads(cand[8:])
                        if isinstance(data, list):
                            for item in data:
                                if item.get("url") == winner:
                                    # Found it! Return the whole payload item
                                    return "PAYLOAD:" + json.dumps([item])
                    except: pass
            
            # Fallback: Just return the winner URL as-is (downloader handles both)
            return winner

        # Last-resort: try resolving just the first candidate directly
        if candidates_list:
            fallback = _cdn_resolvers.resolve_any_cdn_http(candidates_list[0], referer=movie_url_ref)
            if fallback:
                return fallback

        raise RuntimeError("VegaMovies: Failed to resolve a stable download link.")
