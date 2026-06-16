"""Refined Vegamovies scraper (v5.0 - Pure HTTP + Smart Ranking).

Key Improvements over v4.0:
- Smart title/year ranking — picks Gladiator (2000) over Gladiator II (2024).
- Parallel link probing (ThreadPoolExecutor, max 5 workers) for speed.
- Expanded CDN pattern covering all resolvers in _cdn_resolvers.
- Portable sitemap cache path (uses ~/.cache/radd-hub/).
- Nexdrive URLs correctly passed through to the race engine.
"""
from __future__ import annotations
import re
import time
import logging
import concurrent.futures
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
import requests
from bs4 import BeautifulSoup
from .base import (
    fetch, absolutize, quality_from_text, extract_size, normalize, clean_title, HEADERS
)

log = logging.getLogger("hub.scrapers.vegamovies")

DOMAINS = [
    "https://vegamovies.market",
    "https://vegamovies.is",
    "https://vegamovies.dev",
    "https://vegamovies.ph",
]

SITEMAP_CACHE_TTL = 3600 * 12  # 12 hours

# Noise words to ignore when computing extra-words penalty
_SLUG_NOISE = {
    "download", "movie", "film", "hindi", "dubbed", "english", "dual", "audio",
    "bluray", "blu", "ray", "webrip", "web", "rip", "hdrip", "hdtv", "hd",
    "cam", "dvdscr", "dvdrip", "hdcam", "hdts", "dvd", "remux", "x264", "x265",
    "h264", "h265", "hevc", "aac", "ddp", "atmos", "10bit", "8bit",
    "season", "episode", "complete", "pack", "batch", "series",
    "1080p", "720p", "480p", "360p", "2160p", "4k", "fhd",
    "part", "vol", "volume", "sub", "subs", "esub", "multi",
    "org", "official", "original", "remastered", "extended",
    "mkv", "mp4", "avi", "ts", "wmv",
    # Short codec/format fragments that appear in filenames
    "dl", "wb", "hdr", "dv", "dts", "dd", "nf", "amzn", "hulu",
    "prime", "hotstar", "disney", "netflix", "amazon",
    # Quality-adjacent numbers that aren't sequels
    "5k", "6k", "8k",
    # Common suffix junk
    "and", "the", "of", "in", "on", "with", "from", "to", "for", "or",
    "is", "it", "at", "by", "as", "be", "was", "are",
}


# ── Domain & Sitemap Helpers ─────────────────────────────────────────────────

def _domain() -> str:
    from hub import db
    override = db.setting("domain_vegamovies", "").strip()
    if override:
        return override.rstrip("/")
    return DOMAINS[0]


def _sitemap_cache_dir() -> Path:
    p = Path.home() / ".cache" / "radd-hub" / "sitemaps"
    p.mkdir(parents=True, exist_ok=True)
    return p


def _get_sitemaps(base_url: str) -> List[str]:
    cache_dir = _sitemap_cache_dir()
    import hashlib
    domain_hash = hashlib.md5(base_url.encode()).hexdigest()[:8]
    
    contents = []
    for i in range(1, 101):
        cache_path = cache_dir / f"vegamovies_{domain_hash}_sitemap{i}.xml"
        if cache_path.exists():
            age = time.time() - cache_path.stat().st_mtime
            if age < SITEMAP_CACHE_TTL:
                try:
                    contents.append(cache_path.read_text(encoding="utf-8"))
                    continue
                except Exception:
                    pass

        url = f"{base_url}/post-sitemap{i}.xml"
        try:
            # Use fetch for automatic Cloudflare bypass
            text = fetch(url)
            if text:
                cache_path.write_text(text, encoding="utf-8")
                contents.append(text)

            else:
                break  # sitemaps are sequential; stop on first 404
        except Exception:
            break
    return contents


# ── Candidate Ranking ────────────────────────────────────────────────────────

def _rank_candidate(candidate: Dict[str, Any], query_keywords: List[str], year_hint: str, q: str = "") -> float:
    """Higher is better. Score a sitemap candidate against the search query."""
    from hub.query_parser import string_similarity, slug_contains

    url = candidate.get("url", "")
    slug_raw = url.rstrip("/").split("/")[-1]
    slug = slug_raw.replace("download-", "").lower()
    slug_words = set(re.findall(r"[a-z0-9]+", slug))
    
    score = 0.0
    
    # ── Roman numeral sequel indicators ──
    _ROMAN_SEQUEL = {"ii", "iii", "iv", "vi", "vii", "viii", "ix"}

    # ── Significant words from slug ──
    slug_sig = set()
    for w in slug_words:
        if w in _SLUG_NOISE: continue
        if re.fullmatch(r"(19|20)\d{2}", w): continue
        if len(w) == 1 and not w.isdigit(): continue
        if len(w) == 1 and w.isdigit():
            slug_sig.add(w)
            continue
        if len(w) < 2: continue
        slug_sig.add(w)
    slug_sig.update(w for w in slug_words if w in _ROMAN_SEQUEL)

    # ── Significant words from query ──
    query_sig = set()
    for kw in query_keywords:
        kl = kw.lower()
        if len(kl) >= 1:
            query_sig.add(kl)
        if kl in _ROMAN_SEQUEL:
            query_sig.add(kl)
    
    # ── Strict Season/Sequel Check ──
    q_digits = {w for w in query_sig if w.isdigit() and len(w) == 1}
    s_digits = {w for w in slug_sig if w.isdigit() and len(w) == 1}
    if q_digits and s_digits:
        if not (q_digits & s_digits):
            return -999998.0  # VETO: Conflicting sequel/season numbers

    # ── Core Keyword Veto (Title Matching) ──
    # Core keywords = everything except the preferred language tokens and single digits
    core_query_sig = {kw for kw in query_sig if kw not in ["hindi", "dual", "multi"]}
    # Significant non-digit core words (the actual title)
    # Exclude years from the title veto list
    title_core_sig = {
        kw for kw in core_query_sig 
        if not (kw.isdigit() and len(kw) == 1)
        and not re.fullmatch(r"(19|20)\d{2}", kw)
    }
    
    if core_query_sig:
        has_any_match = any(slug_contains(qk, slug) for qk in core_query_sig)
        if title_core_sig:
            title_matched = any(slug_contains(qk, slug) for qk in title_core_sig)
            # Strict: if no title word matches the slug, veto unconditionally
            if not title_matched:
                return -999999.0
        elif not has_any_match:
            return -999999.0

    # ── Movie vs Season Bias ──
    # If the query doesn't mention season/complete but the slug does, penalize
    if not any(w in q.lower() for w in ["season", "series", "complete", "episodes", "pack"]):
        if any(w in slug for w in ["season", "series", "complete", "episodes", "pack"]):
            score -= 30

    # ── Similarity Scoring ──
    slug_no_year = re.sub(r"(19|20)\d{2}", "", slug).replace("-", " ").strip()
    query_no_year = re.sub(r"(19|20)\d{2}", "", q).strip()
    sim = string_similarity(query_no_year, slug_no_year)
    score += sim * 30

    # ── Year Match ──
    yr_in_slug = re.search(r"(19|20)\d{2}", slug)
    if yr_in_slug:
        slug_year = yr_in_slug.group(0)
        if year_hint and str(year_hint) == slug_year:
            score += 15
        elif year_hint and str(year_hint) != slug_year:
            try:
                dist = abs(int(year_hint) - int(slug_year))
                score -= min(dist * 5, 50)
            except ValueError: pass
    else:
        score -= 5

    # ── Extra Words Penalty ──
    extra_count = 0
    for sw in slug_sig:
        if not any(slug_contains(sw, qk) or slug_contains(qk, sw) for qk in query_sig):
            extra_count += 1
    score -= extra_count * 8

    # ── Language Match Bonus ──
    if any(l in q.lower() for l in ["hindi", "dual", "multi"]):
        if any(l in slug for l in ["hindi", "dual", "multi"]):
            score += 40

    # ── Coverage Bonus ──
    matched_count = sum(1 for qk in query_sig if slug_contains(qk, slug))
    if query_sig:
        coverage = matched_count / len(query_sig)
        score += coverage * 50

    return score


# ── Search Implementation ────────────────────────────────────────────────────

def search(title: str, year: str | None = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    base = _domain()
    y_str = str(year) if year and str(year) != "None" else ""
    
    # --- Strategy Loop ---
    # We try with language first (high precision), then without (high recall)
    queries_to_try = []
    if preferred_lang:
        queries_to_try.append((f"{title} {preferred_lang} {y_str}".strip(), preferred_lang))
    queries_to_try.append((f"{title} {y_str}".strip(), ""))

    for q, lang_val in queries_to_try:
        log.info("vegamovies: Searching for '%s'...", q)

        # Strategy 0: Homepage check (for new releases/hot posts)
        log.info("vegamovies: Checking homepage for hot posts...")
        hp_html = fetch(base)
        if hp_html:
            hp_results = _parse_search_html(hp_html, base, y_str)
            if hp_results:
                # Build keywords
                norm_title = normalize(title)
                keywords = [k for k in norm_title.split() 
                            if (len(k) > 1 or (len(k) == 1 and k.isdigit())) 
                            and k not in _SLUG_NOISE]
                
                # Filter and rank homepage results
                scored = []
                for r in hp_results:
                    score = _rank_candidate(r, keywords, y_str, q=q)
                    if score > 0:
                        scored.append((score, r))
                
                if scored:
                    scored.sort(key=lambda x: x[0], reverse=True)
                    # ── Quality gate: require at least 50% keyword slug coverage ──
                    # This prevents a wrong-show homepage hit from blocking the REST API.
                    from hub.query_parser import slug_contains as _sc
                    best_url = scored[0][1].get("url", "")
                    best_slug = best_url.rstrip("/").split("/")[-1].lower().replace("download-", "")
                    kw_hit = sum(1 for kw in keywords if _sc(kw, best_slug))
                    kw_total = len(keywords) if keywords else 1
                    if keywords and kw_hit / kw_total >= 0.5:
                        log.info("vegamovies: Found match on homepage! (%d/%d kw in slug)", kw_hit, kw_total)
                        return [x[1] for x in scored]
                    else:
                        log.info(
                            "vegamovies: Homepage candidate rejected (slug coverage %d/%d < 50%%) — falling through to REST API",
                            kw_hit, kw_total,
                        )

        # Strategy 1: REST API (Typesense-backed, most reliable for legacy content)
        results = _search_via_rest_api(base, q, y_str)
        if results:
            log.info("vegamovies: Found %d results via REST API", len(results))
            return results

        # Strategy 2: Multi-Sitemap (Fast fallback for new releases)
        results = _search_via_sitemaps(base, title, y_str, preferred_lang=lang_val)
        if results:
            log.info("vegamovies: Found %d results via Sitemap", len(results))
            return results

        # Strategy 3: Standard HTML Search fallback
        log.info("vegamovies: API failed, trying HTML search...")
        # standard WP search: /?s=query
        import urllib.parse
        search_url = f"{base}/?s={urllib.parse.quote(q)}"
        html = fetch(search_url)
        if html:
            res = _parse_search_html(html, base, y_str)
            if res: return res

    return []


def _search_via_sitemaps(base: str, title: str, year: str, preferred_lang: str = "") -> List[Dict[str, Any]]:
    sitemaps = _get_sitemaps(base)
    if not sitemaps:
        return []

    q_full = f"{title} {preferred_lang} {year}".strip()

    # Build keyword list from the title
    norm_title = normalize(title)
    # Include words > 1 char OR all single digits (sequels/seasons), but skip common noise
    keywords = [k for k in norm_title.split() 
                if (len(k) > 1 or (len(k) == 1 and k.isdigit())) 
                and k not in _SLUG_NOISE]
    if not keywords:
        keywords = [norm_title]
    kw_patterns = [re.escape(k) for k in keywords]
    threshold = max(1, int(len(kw_patterns) * 0.7))

    all_candidates: List[Dict[str, Any]] = []
    pattern = r'<loc>(https?://[^/]+/download-([^<]+))</loc>'

    for sitemap in sitemaps:
        for m in re.finditer(pattern, sitemap, re.I):
            url, slug = m.group(1), m.group(2)
            norm_slug = slug.replace("-", " ").lower()
            matches = [k for k in kw_patterns if re.search(k, norm_slug)]

            # Need at least 70% keyword coverage, or 2+ matches for long queries
            threshold = max(1, int(len(kw_patterns) * 0.7))
            if len(matches) < threshold:
                continue

            display_title = slug.replace("download-", "").replace("-", " ").title()
            yr_m = re.search(r"(20\d\d|19\d\d)", slug)
            all_candidates.append({
                "title": display_title,
                "year": yr_m.group(1) if yr_m else year,
                "url": url,
                "site": "vegamovies",
                "quality": quality_from_text(slug),
            })

        # Collect from all sitemaps to ensure we get the absolute best keyword matches
        # (Regex matching is fast, so we cap at 1000 to avoid extreme memory use)
        if len(all_candidates) >= 1000:
            break

    if not all_candidates:
        return []

    # ── Smart ranking ────────────────────────────────────────────────────────
    all_candidates.sort(
        key=lambda c: _rank_candidate(c, keywords, year, q=q_full),
        reverse=True,
    )
    
    # ── Parallel Title Verification ──
    # To be 100% correct, we probe the top 5 candidates in parallel to get their
    # ACTUAL page titles. This catches cases where the slug is misleading.
    top_picks = all_candidates[:5]
    log.info("vegamovies: Verifying titles for top %d sitemap candidates...", len(top_picks))
    
    import concurrent.futures
    verified_results = []
    
    def _verify_one(c: dict):
        probe = _micro_probe(c["url"])
        if not probe or probe.get("title") == "BLACKLISTED":
            return None
            
        # Update the candidate with the real verified title and metadata
        c["title"] = clean_title(probe["title"])
        c["meta_type"] = probe["type"]
        c["meta_section"] = probe["section"]
        c["is_movie"] = probe["full_match"]
        
        # ── Veto News/Updates ──
        # If explicitly categorized as news/updates, penalize heavily
        if any(w in c["meta_section"] for w in ["news", "update", "notice", "announcement"]):
             c["veto"] = True
        
        return c

    with concurrent.futures.ThreadPoolExecutor(max_workers=5, thread_name_prefix="vega_search_probe") as ex:
        futures = [ex.submit(_verify_one, c) for c in top_picks]
        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            if res and not res.get("veto"):
                verified_results.append(res)
    
    if verified_results:
        # Re-sort using updated verified titles + Metadata Bonus
        def _final_score(c):
            base = _rank_candidate(c, keywords, year, q=q_full)
            if c.get("is_movie"): base += 20  # DNA-confirmed movie post
            return base
            
        verified_results.sort(key=_final_score, reverse=True)
        log.info("vegamovies: Sitemap top pick (verified): '%s'", verified_results[0]["title"])
        return verified_results

    return all_candidates[:10]


def _search_via_rest_api(base: str, q: str, year: str) -> List[Dict[str, Any]]:
    # New JSON search API (v6.0 - Typesense-backed)
    import urllib.parse as _up
    import json as _json
    api_url = f"{base}/search.php?q={_up.quote(q)}&page=1"
    try:
        text = fetch(api_url)
        if text:
            data = _json.loads(text)
            results = []
            for hit in data.get("hits", []):
                doc = hit.get("document", {})
                title = doc.get("post_title", "")
                link = doc.get("permalink", "")
                if not link.startswith("http"):
                    link = base.rstrip("/") + "/" + link.lstrip("/")
                
                post_year = ""
                # Try to extract year from title
                ym = re.search(r"(20\d\d|19\d\d)", title)
                if ym: post_year = ym.group(1)
                
                results.append({
                    "title": clean_title(title),
                    "year": post_year or doc.get("post_date", ""),
                    "url": link,
                    "site": "vegamovies",
                    "quality": quality_from_text(title),
                })
            
            # Apply smart ranking to REST results too
            norm_title = normalize(q)
            keywords = [k for k in norm_title.split() 
                        if (len(k) > 1 or (len(k) == 1 and k.isdigit())) 
                        and k not in _SLUG_NOISE]
            
            scored = [(c, _rank_candidate(c, keywords, year, q=q)) for c in results]
            # Filter out negative-scored (vetoed) candidates before returning
            results = [c for c, s in sorted(scored, key=lambda x: x[1], reverse=True) if s >= 0]
            return results
    except Exception as e:
        log.warning("vegamovies: API search failed: %s", e)
    return []


def _parse_search_html(html: str, base: str, year: str) -> List[Dict[str, Any]]:
    results = []
    soup = BeautifulSoup(html, "lxml")
    
    # Strategy A: Standard WP post blocks
    for art in soup.find_all(["article", "div"], class_=re.compile(r"post|entry|blog|item", re.I)):
        link = art.find("a", href=True)
        if not link: continue
        href = absolutize(link["href"], base)
        if "/download-" in href:
            title = link.get_text().strip() or link.get("title", "")
            if title:
                post_year = ""
                ym = re.search(r"(20\d\d|19\d\d)", title)
                if ym: post_year = ym.group(1)
                
                results.append({
                    "title": clean_title(title),
                    "year": post_year or year,
                    "url": href,
                    "site": "vegamovies",
                    "quality": quality_from_text(title),
                })

    # Strategy B: Liberal link search (for homepages/grids)
    if not results:
        for link in soup.find_all("a", href=re.compile(r"/download-", re.I)):
            href = absolutize(link["href"], base)
            title = link.get_text().strip() or link.get("title", "")
            if not title:
                # Try finding title in sibling elements (some grids have title below image)
                parent = link.parent
                if parent:
                    title = parent.get_text().strip()
            
            if title and len(title) > 5:
                post_year = ""
                ym = re.search(r"(20\d\d|19\d\d)", title)
                if ym: post_year = ym.group(1)
                
                results.append({
                    "title": clean_title(title),
                    "year": post_year or year,
                    "url": href,
                    "site": "vegamovies",
                    "quality": quality_from_text(title),
                })
    
    # Deduplicate by URL
    seen = set()
    final = []
    for r in results:
        if r["url"] not in seen:
            final.append(r)
            seen.add(r["url"])

    return final


# ── Extraction Implementation ────────────────────────────────────────────────

# CDN pattern — matches any URL that contains a known CDN hostname
# Uses [^/]* to allow arbitrary subdomains (e.g. new26.gdtot.dad)
_CDN_PAT = re.compile(
    r'https?://[^/\s"\'<>]*(?:'
    r'nexdrive\.|'
    r'vcloud\.|'
    r'gdflix\.|'
    r'pixeldrain\.|'
    r'hubcloud\.|hubdrive\.|kutdrive\.|'
    r'mega\.nz|'
    r'buzzheavier\.|'
    r'filepress\.|filebee\.|'
    r'drive\.google\.|googleusercontent\.|'
    r'gdtot\.|'
    r'fastdl\.|'
    r'dotflix\.|'
    r'send\.cm|sendcm\.|'
    r'fuckingfast\.|'
    r'hexload\.|'
    r'jai-shree-ram\.|'
    r'vikingfile\.|'
    r'gofile\.io|'
    r'megaup\.net|'
    r'1fichier\.com|'
    r'dgdrive\.|dropgalaxy\.|'
    r'oxxfile\.|'
    r'streamwish\.|wishfast\.|'
    r'filelions\.|'
    r'doodstream\.|dood\.|'
    r'streamhub\.|'
    r'mdisk\.|'
    r'streamruby\.|'
    r'fsl\.buzz|fsl\.video|'
    r'worker\.|gamerxyt\.|gpdl\.|diskcdn\.'
    r')[^\s"\'<>]*',
    re.I,
)


def _parse_size_to_bytes(size_str: str) -> int:
    if not size_str: return 0
    m = re.search(r"(\d[\d.]+)\s*(GB|MB|TB|B)", size_str, re.I)
    if not m: return 0
    val, unit = float(m.group(1)), m.group(2).upper()
    mult = {"B": 1, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
    return int(val * mult.get(unit, 1))


def get_download_links(page_url: str, season_hint: str = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    """
    Extract all download link options from a VegaMovies post page.

    Args:
        page_url:    Full URL of the movie/series post.
        season_hint: Optional season number (e.g. "1", "2") from the original
                     search query.
        preferred_lang: Optional language preference (e.g. "Hindi").
    """
    log.info("vegamovies: Extracting links from: %s (lang_pref=%s)", page_url, preferred_lang or "any")

    # 1. Try REST API for clean HTML
    content_data = _get_download_links_via_rest_api(page_url)
    if content_data:
        html, title = content_data
        links = _parse_download_links_html(html, page_url, title, season_hint=season_hint, preferred_lang=preferred_lang)
        if links:
            return links
        log.info("vegamovies: REST API HTML had no CDN links — trying static fetch...")

    # 2. Static HTML Fallback
    html = fetch(page_url)
    if html:
        title_m = re.search(r'<title>(.*?)</title>', html, re.I)
        links = _parse_download_links_html(
            html, page_url,
            title_m.group(1) if title_m else "",
            season_hint=season_hint,
            preferred_lang=preferred_lang,
        )
        if links:
            return links
        log.info("vegamovies: Static HTML had no CDN links — trying Playwright browser render...")
    else:
        log.info("vegamovies: Static fetch blocked/failed — trying Playwright browser render...")

    # 3. Playwright Fallback — renders JS-heavy or Cloudflare-protected pages
    try:
        from hub.sites._pw_fallback import pw_extract_cdn_links_from_page
        log.info("vegamovies: Launching browser for page render fallback on %s ...", page_url)
        rendered_html = pw_extract_cdn_links_from_page(page_url)
        if rendered_html:
            links = _parse_download_links_html(
                rendered_html, page_url, "",
                season_hint=season_hint,
                preferred_lang=preferred_lang,
            )
            if links:
                log.info("vegamovies: Playwright fallback yielded %d link(s).", len(links))
                return links
    except Exception as pw_exc:
        log.warning("vegamovies: Playwright fallback error: %s", pw_exc)

    return []


def _get_download_links_via_rest_api(page_url: str) -> Optional[Tuple[str, str]]:
    # Extract slug — take the full path after the domain
    m = re.match(r'(https?://[^/]+)/(.+?)/?$', page_url)
    if not m:
        return None
    base = m.group(1)
    full_path = m.group(2).strip("/")
    # Use the last path segment as the slug
    slug = full_path.split("/")[-1]
    api_url = f"{base}/wp-json/wp/v2/posts?slug={slug}&_fields=content,title,slug"
    try:
        # Use fetch for consistent Cloudflare bypass
        text = fetch(api_url)
        if text:
            import json as _json
            posts = _json.loads(text)
            if posts and isinstance(posts, list):
                p = posts[0]
                p_slug = p.get("slug", "")
                p_title = p.get("title", {}).get("rendered", "")
                if (slug.lower() in p_slug.lower() or
                        slug.lower() in p_title.lower() or
                        p_slug.lower() in slug.lower()):
                    return p["content"]["rendered"], p_title
    except Exception:
        pass
    return None


def _parse_download_links_html(
    html: str, page_url: str, page_title: str, season_hint: str = "", preferred_lang: str = ""
) -> List[Dict[str, Any]]:
    # ── Contextual Season Splitting ──
    # If a season_hint is provided and the page seems to have multiple seasons,
    # isolate the relevant section of the HTML to avoid cross-season link extraction.
    working_html = html
    if season_hint and season_hint.isdigit():
        # Find all season headers (e.g., "Season 1", "Season 02", "S03")
        # Refined regex: Look for headers or bold text, avoid matches inside <a> tags
        # We look for patterns like <h1>Season 1</h1> or <strong>Season 1</strong>
        s_headers = list(re.finditer(r'<(?:h\d|strong|b|p)>.*?(?:Season|S)\s*0?(\d+).*?</(?:h\d|strong|b|p)>', html, re.I | re.S))
        distinct_seasons = set(m.group(1) for m in s_headers)
        if len(distinct_seasons) > 1:
            # Multiple distinct seasons detected!
            target_start = -1
            target_end = len(html)
            
            for i, m in enumerate(s_headers):
                if m.group(1) == season_hint:
                    target_start = m.start()
                    # Find the next header with a DIFFERENT season number
                    for next_m in s_headers[i+1:]:
                        if next_m.group(1) != season_hint:
                            target_end = next_m.start()
                            break
                    break
            
            # Safety: only apply isolation if we found a block that is reasonably large (>500 chars)
            # or contains links. If the block is tiny, it might just be a summary header.
            if target_start != -1 and (target_end - target_start) > 500:
                candidate_section = html[target_start:target_end]
                # Only use the isolated section if it actually contains CDN links.
                # If the section has no CDN links (e.g. headers only), fall back to
                # the full page so we don't throw away all the download buttons.
                if _CDN_PAT.search(candidate_section):
                    log.info("vegamovies: Isolated Season %s section (chars %d to %d)",
                             season_hint, target_start, target_end)
                    working_html = candidate_section
                else:
                    log.info("vegamovies: Season %s section has no CDN links — using full page content.", season_hint)
            else:
                log.info("vegamovies: Season %s block too small, using full page content.", season_hint)

    # Scope to main content to avoid sidebar/footer noise
    soup = BeautifulSoup(working_html, "lxml")
    content = soup.find("div", class_=re.compile(r"entry-content|post-content|single-post-content", re.I))
    search_area = str(content) if content else working_html

    # Capture all <a> tags with their position
    all_links = list(re.finditer(r'<a\s[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', search_area, re.I | re.S))

    # Title verification keywords
    clean_page_title = clean_title(page_title).lower()
    keywords = [k for k in clean_page_title.split() if len(k) > 2 and k not in _SLUG_NOISE]

    candidates = []
    for m in all_links:
        href, anchor = m.group(1), m.group(2)
        if _CDN_PAT.search(href):
            # ── Contextual Verification ──
            start = max(0, m.start() - 500)
            ctx = re.sub(r'<[^>]+>', ' ', search_area[start:m.start()]).lower()
            anchor_low = anchor.lower()
            
            # If we have keywords, ensure at least one matches in the context or anchor
            if keywords:
                if not any(k in ctx or k in anchor_low for k in keywords):
                    continue

            # ── Structural Fingerprinting ──
            score = 0
            # Look backwards for container indicators
            container_chunk = search_area[max(0, m.start() - 300):m.start()]
            
            # Boost if inside a professional download container
            if any(cls in container_chunk.lower() for cls in ["download-link", "button", "btn-box", "mirror", "server"]):
                score += 10
            
            # Boost if anchor contains "Download" or "Mirror"
            if any(w in anchor.lower() for w in ["download", "mirror", "server", "direct", "fast"]):
                score += 5
            
            # Penalize if preceded by "Source" or "Credit" (often attribution links)
            if any(w in container_chunk.lower()[-50:] for w in ["source:", "credit:", "via:"]):
                score -= 15

            # ── Capture Context ──
            # Look backwards up to 500 chars for quality tags (720p, 1080p, etc.)
            start = max(0, m.start() - 500)
            ctx_chunk = working_html[start:m.start()]
            # Strip tags and normalize
            ctx_text = re.sub(r'<[^>]+>', ' ', ctx_chunk)
            ctx_text = re.sub(r'\s+', ' ', ctx_text).strip()
            
            candidates.append({
                "url": href, 
                "anchor": re.sub(r'<[^>]+>', ' ', anchor).lower(),
                "page_ctx": ctx_text,
                "structural_score": score
            })

    # ── Also scan onclick and data-url attributes for CDN links ──
    # VegaMovies 2025/2026 pages sometimes use JS click handlers instead of plain hrefs
    _EXTRA_CDN_PATS = [
        # onclick="window.open('URL')" or onclick="window.location.href='URL'"
        re.compile(r'''onclick=["\'][^"\']*(?:window\.(?:open|location(?:\.href)?))\s*\(?\s*["\']?(https?://[^\s"\'<>\)]+)''', re.I),
        # data-url / data-href / data-link attributes
        re.compile(r'''data-(?:url|href|link|src)=["\']([^"\']+)["\']''', re.I),
        # Naked URLs in button value or data attributes
        re.compile(r'''(?:value|data-download)=["\'](https?://[^"\'<>]+)["\']''', re.I),
    ]
    for pat in _EXTRA_CDN_PATS:
        for m in pat.finditer(working_html):
            href = m.group(1).strip().rstrip("'\")")
            if href.startswith("http") and _CDN_PAT.search(href):
                # Find position context
                start = max(0, m.start() - 500)
                ctx_text = re.sub(r'<[^>]+>', ' ', working_html[start:m.start()])
                ctx_text = re.sub(r'\s+', ' ', ctx_text).strip()
                candidates.append({
                    "url": href,
                    "anchor": "onclick/data-attr",
                    "page_ctx": ctx_text,
                    "structural_score": 8,  # High confidence — explicit download trigger
                })

    if not candidates:
        log.info("vegamovies: No CDN links found on page %s", page_url)
        return []
        
    # Sort candidates by structural confidence first
    candidates.sort(key=lambda x: x["structural_score"], reverse=True)

    # ── Determine effective season filter ────────────────────────────────────
    # Priority: season_hint from search query > page_title detection
    # season_hint is preferred because the combined S1+S2 page title says
    # "Season 1-2" which would incorrectly extract "1" for a Season 2 search.
    effective_season: str = ""
    if season_hint and str(season_hint).strip().isdigit():
        effective_season = str(season_hint).strip()
    else:
        # Fallback: detect from page title — only use if NOT a combined page
        # (combined pages have "1-2", "1 – 2", "1 & 2" etc.)
        if not re.search(r"(\d)\s*[-–&]\s*(\d)", page_title):
            m_pt = re.search(r"season\s?(\d+)|s0?(\d+)", page_title.lower())
            if m_pt:
                effective_season = m_pt.group(1) or m_pt.group(2)

    # ── Parallel Title Probing ───────────────────────────────────────────────
    probe_targets = candidates[:20]  # cap to avoid excessive requests

    # Pre-warm unique domains in the main thread to solve Cloudflare challenges
    # and avoid "Cannot switch to a different thread" errors in the pool.
    # Skip nexdrive — it uses an xla=s4t cookie trick, not a browser session,
    # and hitting nexdrive.pro for warm-up just gets 503s.
    _NO_PREWARM = ("nexdrive.", "pixeldrain.", "mega.", "gofile.", "1fichier.",
                   "megaup.", "vikingfile.", "send.cm", "sendcm.")
    unique_domains = set()
    for c in probe_targets:
        m_dom = re.match(r'(https?://[^/]+)', c["url"])
        if m_dom:
            dom = m_dom.group(1).lower()
            if not any(skip in dom for skip in _NO_PREWARM):
                unique_domains.add(m_dom.group(1))

    if unique_domains:
        log.info("vegamovies: Pre-warming %d CDN domains in main thread...", len(unique_domains))
        for dom in unique_domains:
            try:
                fetch(dom, timeout=10)
            except:
                pass

    log.info(
        "vegamovies: Probing %d CDN links in parallel (season_filter=%s)...",
        min(len(probe_targets), 20), effective_season or "none",
    )

    # Clean the page title to use for show name in library checks
    clean_show_name = clean_title(page_title)

    def _probe(c: dict) -> Optional[dict]:
        title = _get_title_from_url(c["url"])
        if title == "BLACKLISTED":
            return None

        # ── Fallback Title ──
        # If probe failed (empty title), try to use anchor text or context
        if not title:
            # If anchor is just "Download" or similar junk, use context or page title
            if any(w in c["anchor"].lower() for w in ["download", "mirror", "server", "direct", "fast"]):
                title = c["page_ctx"][:100] # Use a bit of context
            else:
                title = c["anchor"]
        
        if not title:
            # Final fallback: use the page title itself
            title = page_title

        # ── Season Filter ──
        if effective_season:
            s_link = re.search(r"season\s?(\d+)|s0?(\d+)", title.lower())
            if s_link:
                s_link_num = s_link.group(1) or s_link.group(2)
                if s_link_num != effective_season:
                    log.debug("vegamovies: Skipping %s (season %s ≠ %s)", c["url"][:50], s_link_num, effective_season)
                    return None

        # ── Language Detection ──
        # Extract language tags from the probed title
        full_ctx = (title + " " + c["anchor"] + " " + c["page_ctx"]).lower()
        
        is_hindi = any(kw in full_ctx for kw in ["hindi", "dual", "multi"])
        is_english = "english" in full_ctx
        
        # ── Metadata Extraction ──
        is_batch = (
            any(kw in title.lower() for kw in ["batch", "zip", "pack", "complete", "added", "episodes", "collection", "series"])
            or ".zip" in c["url"].lower()
        )
        # Improved Episode Regex: specific prefixes + word boundaries
        ep_m = re.search(r"(?:\bepisode\s*|\bep\s*|\bep-|\be|s\d+e)(\d+)\b", title, re.I)
        ep_num = ep_m.group(1) if ep_m else None
        
        # ── Pre-Flight Library Check ──
        from hub import db
        in_library = False
        
        # User mandate: Always prefer ZIP/Batch if available. 
        # Removing the 'count >= 10' veto to ensure Zips are always processed.
        if is_batch and effective_season:
             pass 

        elif ep_num and effective_season:
            in_library = db.is_episode_in_library(clean_show_name, int(effective_season), int(ep_num))
            if in_library:
                log.info("vegamovies: [Pre-Flight] [S%02dE%02d] found in library - skipping.", int(effective_season), int(ep_num))

        # Quality Detection
        specific_ctx = title + " " + c["anchor"]
        qual = quality_from_text(specific_ctx)
        if qual == "?": qual = quality_from_text(c["page_ctx"])
        if qual == "?": qual = quality_from_text(page_title)
            
        serv = _detect_server(c["url"])

        # ── 7GB Quality Fallback Logic ──
        # If 720p Batch/Zip size > 7GB, mark it for potential fallback
        size_str = extract_size(c["page_ctx"] + " " + title)
        size_bytes = _parse_size_to_bytes(size_str)
        is_oversized = False
        if is_batch and qual == "720p" and size_bytes > (7 * 1024**3):
            log.info("vegamovies: 720p Batch detected as oversized (%s) - will prefer 480p if available", f"{size_bytes/1024**3:.1f}GB")
            is_oversized = True

        return {
            "url": c["url"],
            "title": title,
            "ep_num": ep_num,
            "quality": qual,
            "server": serv,
            "is_batch": is_batch and not ep_num,
            "is_episode": bool(ep_num),
            "ctx": full_ctx,
            "is_hindi": is_hindi,
            "is_english": is_english,
            "in_library": in_library,
            "size_bytes": size_bytes,
            "is_oversized": is_oversized
        }

    raw_results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5, thread_name_prefix="vega_probe") as ex:
        futures = {ex.submit(_probe, c): c for c in probe_targets}
        for fut in concurrent.futures.as_completed(futures, timeout=60):
            try:
                result = fut.result(timeout=2)
                if result:
                    raw_results.append(result)
            except Exception:
                pass

    if not raw_results:
        log.warning("vegamovies: All CDN probes failed for %s", page_url)
        return []

    # ── 7GB Fallback Execution ──
    # If we have oversized 720p batches, check if 480p batches exist
    has_oversized = any(r.get("is_oversized") for r in raw_results)
    if has_oversized:
        has_480p_batch = any(r["is_batch"] and r["quality"] == "480p" for r in raw_results)
        if has_480p_batch:
            log.info("vegamovies: Applying 7GB Fallback: Filtering out 720p oversized batches in favor of 480p")
            raw_results = [r for r in raw_results if not r.get("is_oversized")]

    # ── Language Selection Logic ──
    # 1. Filter by preferred language if possible
    probed_links = raw_results
    if preferred_lang and preferred_lang.lower() == "hindi":
        hindi_links = [r for r in raw_results if r["is_hindi"]]
        if hindi_links:
            probed_links = hindi_links
            log.info("vegamovies: Found %d links matching Hindi preference.", len(hindi_links))
        else:
            log.info("vegamovies: No Hindi links found. Falling back to all available links (English/Original).")

    # 2. Filter out already-downloaded episodes (Pre-Flight Veto)
    raw_links = []
    skipped_count = 0
    for lnk in probed_links:
        if lnk.get("in_library") and not lnk.get("is_batch"):
            skipped_count += 1
            continue
        raw_links.append(lnk)
    
    if skipped_count > 0:
        log.info("vegamovies: Pre-flight check skipped %d episodes (already in library).", skipped_count)

    if not raw_links:
        log.info("vegamovies: All episodes on this page are already in your library.")
        return []

    # ── Grouping & Joining ───────────────────────────────────────────────────
    processed = {}
    for lnk in raw_links:
        cat = "batch" if lnk["is_batch"] else (f"ep_{lnk['ep_num']}" if lnk["ep_num"] else "single")
        key = (lnk["quality"], lnk["server"], cat)
        if key not in processed:
            processed[key] = lnk

    qs_clusters: Dict[tuple, dict] = {}
    for (q, s, c), val in processed.items():
        k = (q, s)
        if k not in qs_clusters:
            qs_clusters[k] = {"batches": [], "episodes": {}}
        if c == "batch":
            qs_clusters[k]["batches"].append(val)
        else:
            qs_clusters[k]["episodes"][c] = val

    final: List[Dict[str, Any]] = []
    is_series = any(kw in page_title.lower() for kw in ["season", "series", "s01", "s02", "complete"])

    for (q, s), data in qs_clusters.items():
        for b in data["batches"]:
            final.append({
                "label": f"{q} {s} [Batch/Zip]",
                "url": b["url"],
                "quality": q,
                "server": s,
                "is_batch": True,
                "size": extract_size(b["ctx"]),
            })
        if data["episodes"]:
            sorted_eps = sorted(
                data["episodes"].values(),
                key=lambda e: int(e["ep_num"]) if (e["ep_num"] and e["ep_num"].isdigit()) else 999,
            )
            
            # --- Season Perfection: Return JobPayload JSON ---
            import json as _json
            payload = []
            for e in sorted_eps:
                payload.append({
                    "url": e["url"],
                    "metadata": {
                        "show": clean_show_name,
                        "season": int(effective_season) if effective_season else None,
                        "episode": int(e["ep_num"]) if e["ep_num"] else None,
                        "quality": e["quality"]
                    }
                })
            
            payload_str = "PAYLOAD:" + _json.dumps(payload)
            
            # Smart labels for missing episodes
            ep_nums = [e["ep_num"] for e in sorted_eps if e["ep_num"]]
            if ep_nums:
                label = f"{q} {s} [New Eps: {', '.join(ep_nums)}]"
            else:
                label = f"{q} {s} [Single]"
                
            final.append({
                "label": label,
                "url": payload_str,
                "quality": q,
                "server": s,
                "episodes": ep_nums,
                "size": extract_size(sorted_eps[0]["ctx"]) if len(sorted_eps) == 1 else "",
            })

    final.sort(key=_priority)
    log.info("vegamovies: Extracted %d download options from %s", len(final), page_url)
    return final


def _priority(link: dict) -> int:
    s = link["server"].lower()
    lbl = link["label"].lower()
    if "[batch/zip]" in lbl:
        if "fastdl" in s: return 1
        if "vcloud" in s: return 2
        return 3
    if "vcloud" in s: return 4
    if "fastdl" in s: return 5
    if "gdflix" in s or "direct" in s: return 6
    if "nexdrive" in s: return 7
    return 10


def _micro_probe(url: str) -> Dict[str, Any]:
    """
    Perform a 'Precision Strike' probe: fetch only the start of the page
    to extract Title, JSON-LD Schema, and Metadata.
    """
    try:
        # Range header: ask for first 32KB where <head> usually lives
        # Note: fetch() doesn't currently support range headers, so we use a simplified version
        # but we use fetch() to handle cookies/bypass first
        headers = {**HEADERS, "Range": "bytes=0-32768"}
        
        # 1. Try with fetch() first to get session/cookies
        # (Assuming fetch() handles the session/cookies globally or we can use a dummy request)
        fetch(url) 
        
        # Now use requests with the range header
        import requests
        from .base import get_session
        sess = get_session()
        
        with sess.get(url, headers=headers, timeout=8, stream=True) as r:
            if r.status_code not in (200, 206, 301, 302):
                # Fallback to full fetch if range fails or Cloudflare still active
                decoded = fetch(url)
                if not decoded: return {}
            else:
                html = b""
                for chunk in r.iter_content(chunk_size=16384):
                    html += chunk
                    if b"</head>" in html.lower() or len(html) > 131072:
                        break
                decoded = html.decode("utf-8", "ignore")
            
            # 1. Extract Title
            title = ""
            m_title = re.search(r"<title>(.*?)</title>", decoded, re.I | re.S)
            if m_title:
                title = m_title.group(1).strip()
                title = re.sub(
                    r"\s*[-|–]\s*(VegaMovies|GDFlix|vCloud|FastDL|NexDrive|HubCloud)[^\n]*$",
                    "", title, flags=re.I,
                )
            
            # 2. Extract Schema Type (JSON-LD)
            schema_type = "unknown"
            m_schema = re.search(r'"@type"\s*:\s*"([^"]+)"', decoded, re.I)
            if m_schema:
                schema_type = m_schema.group(1).lower()
                
            # 3. Extract Section/Category
            section = "unknown"
            m_section = re.search(r'property="article:section"\s+content="([^"]+)"', decoded, re.I)
            if m_section:
                section = m_section.group(1).lower()

            return {
                "title": title,
                "type": schema_type,
                "section": section,
                "full_match": any(w in schema_type for w in ["movie", "series", "episode"]) or
                              any(w in title.lower() for w in ["movie", "series", "episode", "season", "complete"])
            }
    except Exception:
        pass
    return {}

def _get_title_from_url(url: str) -> str:
    # Wrap micro_probe for backward compatibility
    return _micro_probe(url).get("title", "")


def _detect_server(url: str) -> str:
    ul = url.lower()
    patterns = {
        "Google Drive": "drive.google",
        "Pixeldrain":   "pixeldrain",
        "MEGA":         "mega.nz",
        "FilePress":    "filepress",
        "FileBee":      "filebee",
        "GDFlix":       "gdflix",
        "vCloud":       "vcloud",
        "FastDL":       "fastdl",
        "NexDrive":     "nexdrive",
        "HubCloud":     "hubcloud",
        "HubDrive":     "hubdrive",
        "KutDrive":     "kutdrive",
        "DotFlix":      "dotflix",
        "Send.cm":      "send.cm",
        "FuckingFast":  "fuckingfast",
        "HexLoad":      "hexload",
        "VikingFile":   "vikingfile",
        "GoFile":       "gofile",
        "MegaUp":       "megaup",
        "1Fichier":     "1fichier",
        "JaiShreeRam":  "jai-shree-ram",
    }
    for name, pat in patterns.items():
        if pat in ul:
            return name
    return "Direct"
