"""KatMovieHD scraper (v6.0 - High-Speed Triple-Layer Crawler).

Specialized for K-Dramas, Anime, and Global content.
Uses Double-Hop recursive extraction to bypass kmhd.eu bridges.
"""
from __future__ import annotations
import re
import time
import logging
import concurrent.futures
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from bs4 import BeautifulSoup
from .base import (
    fetch, absolutize, quality_from_text, extract_size, normalize, clean_title, HEADERS
)

log = logging.getLogger("hub.scrapers.katmoviehd")

DOMAINS = [
    "https://katmoviehd.lol",
    "https://new1.katmoviehd.cymru",
    "https://katmoviehd.fit",
    "https://katmoviehd.fans",
]

SITEMAP_CACHE_TTL = 3600 * 12

_BRIDGE_DOMAINS = ["kmhd.eu", "katworld.net", "gdstream.net", "katdrive.eu"]

_SLUG_NOISE = {
    "download", "movie", "film", "hindi", "dubbed", "english", "dual", "audio",
    "bluray", "blu", "ray", "webrip", "web", "rip", "hdrip", "hdtv", "hd",
    "season", "episode", "complete", "pack", "batch", "series",
    "1080p", "720p", "480p", "360p", "2160p", "4k", "fhd", "esub", "mkv",
}

# ── Domain & Sitemap Helpers ─────────────────────────────────────────────────

def _domain() -> str:
    from hub import db
    override = db.setting("domain_katmoviehd", "").strip()
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
    for i in range(1, 21):
        cache_path = cache_dir / f"katmoviehd_{domain_hash}_sitemap{i}.xml"
        if cache_path.exists():
            age = time.time() - cache_path.stat().st_mtime
            if age < SITEMAP_CACHE_TTL:
                try:
                    contents.append(cache_path.read_text(encoding="utf-8"))
                    continue
                except: pass

        url = f"{base_url}/post-sitemap{i}.xml"
        text = fetch(url)
        if text:
            cache_path.write_text(text, encoding="utf-8")
            contents.append(text)
        else:
            break
    return contents

# ── Candidate Ranking ────────────────────────────────────────────────────────

def _rank_candidate(candidate: Dict[str, Any], query_keywords: List[str], year_hint: str, q: str = "") -> float:
    from hub.query_parser import string_similarity, slug_contains

    url = candidate.get("url", "")
    slug_raw = url.rstrip("/").split("/")[-1]
    slug = slug_raw.replace("download-", "").lower()
    slug_words = set(re.findall(r"[a-z0-9]+", slug))
    
    score = 0.0
    _ROMAN_SEQUEL = {"ii", "iii", "iv", "vi", "vii", "viii", "ix"}

    slug_sig = set()
    for w in slug_words:
        if w in _SLUG_NOISE: continue
        if re.fullmatch(r"(19|20)\d{2}", w): continue
        if len(w) == 1 and not w.isdigit(): continue
        if len(w) == 1 and w.isdigit(): slug_sig.add(w); continue
        if len(w) < 2: continue
        slug_sig.add(w)
    slug_sig.update(w for w in slug_words if w in _ROMAN_SEQUEL)

    query_sig = set()
    for kw in query_keywords:
        kl = kw.lower()
        if len(kl) >= 1: query_sig.add(kl)
        if kl in _ROMAN_SEQUEL: query_sig.add(kl)
    
    q_digits = {w for w in query_sig if w.isdigit() and len(w) == 1}
    s_digits = {w for w in slug_sig if w.isdigit() and len(w) == 1}
    if q_digits and s_digits:
        if not (q_digits & s_digits): return -999998.0

    core_query_sig = {kw for kw in query_sig if kw not in ["hindi", "dual", "multi"]}
    title_core_sig = {kw for kw in core_query_sig if not (kw.isdigit() and len(kw) == 1) and not re.fullmatch(r"(19|20)\d{2}", kw)}
    
    if core_query_sig:
        has_any_match = any(slug_contains(qk, slug) for qk in core_query_sig)
        if title_core_sig:
            title_matched = any(slug_contains(qk, slug) for qk in title_core_sig)
            if not title_matched and len(title_core_sig) > 1: return -999999.0
            elif not title_matched and not has_any_match: return -999999.0
        elif not has_any_match: return -999999.0

    if not any(w in q.lower() for w in ["season", "series", "complete", "episodes", "pack"]):
        if any(w in slug for w in ["season", "series", "complete", "episodes", "pack"]):
            score -= 30

    slug_no_year = re.sub(r"(19|20)\d{2}", "", slug).replace("-", " ").strip()
    query_no_year = re.sub(r"(19|20)\d{2}", "", q).strip()
    sim = string_similarity(query_no_year, slug_no_year)
    score += sim * 30

    yr_in_slug = re.search(r"(19|20)\d{2}", slug)
    if yr_in_slug:
        slug_year = yr_in_slug.group(0)
        if year_hint and str(year_hint) == slug_year: score += 15
        elif year_hint and str(year_hint) != slug_year:
            try: dist = abs(int(year_hint) - int(slug_year)); score -= min(dist * 5, 50)
            except: pass
    else: score -= 5

    extra_count = 0
    for sw in slug_sig:
        if not any(slug_contains(sw, qk) or slug_contains(qk, sw) for qk in query_sig): extra_count += 1
    score -= extra_count * 8

    matched_count = sum(1 for qk in query_sig if slug_contains(qk, slug))
    if query_sig:
        coverage = matched_count / len(query_sig)
        score += coverage * 50

    return score

# ── Extraction Implementation ────────────────────────────────────────────────

_CDN_PAT = re.compile(
    r'https?://[^/\s"\'<>]*(?:'
    r'nexdrive\.|vcloud\.|gdflix\.|pixeldrain\.|hubcloud\.|mega\.nz|buzzheavier\.|filepress\.|drive\.google\.|gdtot\.|fastdl\.|katdrive\.|katfile\.|dropgalaxy\.|dgdrive\.|kmhd\.eu|katworld\.net'
    r')[^\s"\'<>]*', re.I
)

def search(title: str, year: str | None = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    base = _domain()
    y_str = str(year) if year and str(year) != "None" else ""
    q = f"{title} {y_str}".strip()
    
    log.info("katmoviehd: Turbo-searching for '%s'...", q)

    import urllib.parse

    # Run sitemap + HTML search in parallel so we never miss recent titles
    # that may not be indexed in sitemaps yet.
    sitemap_results: List[Dict[str, Any]] = []
    html_results: List[Dict[str, Any]] = []

    def _run_sitemap():
        return _search_via_sitemaps(base, title, y_str)

    def _run_html():
        url = f"{base}/?s={urllib.parse.quote(q)}"
        html = fetch(url)
        if html:
            return _parse_search_html(html, base, y_str)
        return []

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        f_sm = ex.submit(_run_sitemap)
        f_html = ex.submit(_run_html)
        try: sitemap_results = f_sm.result(timeout=25) or []
        except Exception: sitemap_results = []
        try: html_results = f_html.result(timeout=25) or []
        except Exception: html_results = []

    # Merge and deduplicate, preferring sitemap order but adding unique HTML hits
    seen_urls: set[str] = set()
    merged: List[Dict[str, Any]] = []
    for r in sitemap_results + html_results:
        u = r.get("url", "")
        if u and u not in seen_urls:
            seen_urls.add(u)
            merged.append(r)

    if merged:
        log.info("katmoviehd: merged %d sitemap + %d html = %d unique candidates",
                 len(sitemap_results), len(html_results), len(merged))
        return merged[:15]

    # 2. REST API (last resort — often 403 but worth one try)
    results = _search_via_rest_api(base, q, y_str)
    if results: return results

    return []

def _search_via_sitemaps(base: str, title: str, year: str) -> List[Dict[str, Any]]:
    sitemaps = _get_sitemaps(base)
    if not sitemaps: return []

    norm_title = normalize(title)
    keywords = [k for k in norm_title.split() if (len(k) > 1 or (len(k) == 1 and k.isdigit())) and k not in _SLUG_NOISE]
    if not keywords: keywords = [norm_title]
    kw_patterns = [re.escape(k) for k in keywords]

    all_candidates: List[Dict[str, Any]] = []
    pattern = r'<loc>(https?://[^/]+/([^<]+))</loc>'

    for sitemap in sitemaps:
        for m in re.finditer(pattern, sitemap, re.I):
            url, slug = m.group(1), m.group(2)
            if base not in url or any(x in slug for x in ["wp-content", "category", "tag"]): continue
            
            norm_slug = slug.replace("-", " ").lower()
            matches = [k for k in kw_patterns if re.search(k, norm_slug)]
            threshold = max(1, int(len(kw_patterns) * 0.7))
            if len(matches) < threshold: continue

            yr_m = re.search(r"(20\d\d|19\d\d)", slug)
            all_candidates.append({
                "title": slug.replace("-", " ").title(),
                "year": yr_m.group(1) if yr_m else year,
                "url": url,
                "site": "katmoviehd",
                "quality": quality_from_text(slug),
            })
        if len(all_candidates) >= 1000: break

    if not all_candidates: return []
    all_candidates.sort(key=lambda c: _rank_candidate(c, keywords, year, q=title), reverse=True)
    return all_candidates[:15]

def _search_via_rest_api(base: str, q: str, year: str) -> List[Dict[str, Any]]:
    import urllib.parse as _up, json as _json
    api_url = f"{base}/wp-json/wp/v2/posts?search={_up.quote(q)}&per_page=15&_fields=title,link"
    try:
        text = fetch(api_url)
        if text:
            posts = _json.loads(text)
            results = []
            for p in posts:
                title = p.get("title", {}).get("rendered", "")
                link = p.get("link", "")
                if not link: continue
                ym = re.search(r"(20\d\d|19\d\d)", title)
                results.append({
                    "title": clean_title(title),
                    "year": ym.group(1) if ym else year,
                    "url": link,
                    "site": "katmoviehd",
                    "quality": quality_from_text(title),
                })
            return results
    except: pass
    return []

def _parse_search_html(html: str, base: str, year: str) -> List[Dict[str, Any]]:
    results = []
    soup = BeautifulSoup(html, "lxml")
    for art in soup.find_all(["article", "div"], class_=re.compile(r"post|entry|item", re.I)):
        link = art.find("a", href=True)
        if not link or base not in link["href"]: continue
        title = link.get_text().strip() or link.get("title", "")
        if title:
            ym = re.search(r"(20\d\d|19\d\d)", title)
            results.append({
                "title": clean_title(title),
                "year": ym.group(1) if ym else year,
                "url": absolutize(link["href"], base),
                "site": "katmoviehd",
                "quality": quality_from_text(title),
            })
    return results

def get_download_links(page_url: str, season_hint: str = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    log.info("katmoviehd: Recursive extraction from: %s", page_url)
    html = fetch(page_url)
    if not html: return []
    
    title_m = re.search(r'<title>(.*?)</title>', html, re.I)
    page_title = title_m.group(1) if title_m else ""
    
    links = _parse_download_links_html(html, page_url, page_title, season_hint=season_hint)
    
    final_results = []
    bridge_links = []
    for l in links:
        if any(b in l["url"] for b in ["kmhd.eu", "katworld.net"]):
            bridge_links.append(l)
        else: final_results.append(l)
            
    if bridge_links:
        log.info("katmoviehd: Crawling %d bridge pages...", len(bridge_links))
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as ex:
            futures = [ex.submit(_crawl_bridge, b["url"], page_title, season_hint) for b in bridge_links[:15]]
            for fut in concurrent.futures.as_completed(futures):
                final_results.extend(fut.result())

    seen = set(); unique = []
    for r in final_results:
        if r["url"] not in seen:
            unique.append(r); seen.add(r["url"])
            
    unique.sort(key=lambda x: _priority(x), reverse=True)
    return unique

def _crawl_bridge(url: str, parent_title: str, season_hint: str) -> List[dict]:
    try:
        html = fetch(url)
        if not html: return []
        return _parse_download_links_html(html, url, parent_title, season_hint=season_hint, is_bridge=True)
    except: return []

def _parse_download_links_html(
    html: str, page_url: str, page_title: str, season_hint: str = "", is_bridge: bool = False
) -> List[Dict[str, Any]]:
    soup = BeautifulSoup(html, "lxml")
    content = soup.find("div", class_=re.compile(r"entry-content|post-content|single-post-content", re.I))
    search_area = str(content) if content else html
    all_links = list(re.finditer(r'<a\s[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', search_area, re.I | re.S))
    
    clean_page_title = clean_title(page_title).lower()
    keywords = [k for k in clean_page_title.split() if len(k) > 2 and k not in _SLUG_NOISE]

    candidates = []
    for m in all_links:
        href, anchor = m.group(1), m.group(2)
        if _CDN_PAT.search(href):
            start = max(0, m.start() - 500)
            ctx = re.sub(r'<[^>]+>', ' ', search_area[start:m.start()]).lower()
            anchor_low = anchor.lower()
            if not is_bridge and keywords and not any(k in ctx or k in anchor_low for k in keywords): continue
            if season_hint and season_hint.lower() not in ctx and season_hint.lower() not in anchor_low:
                if not is_bridge: continue
            candidates.append({"url": href, "anchor": anchor, "ctx": ctx})

    if not candidates: return []
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
        futures = [ex.submit(_probe, c, page_title) for c in candidates[:20]]
        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            if res: results.append(res)
    return results

def _probe(c: dict, page_title: str) -> Optional[dict]:
    url = c["url"]
    full_ctx = (c["anchor"] + " " + c["ctx"]).lower()
    server = _detect_server(url)
    qual = quality_from_text(full_ctx)
    if qual == "?": qual = quality_from_text(page_title)
    size = extract_size(full_ctx)
    return {"label": f"{qual} {server} {size}".strip(), "url": url, "server": server, "quality": qual, "size": size}

def _detect_server(url: str) -> str:
    patterns = {"Bridge": r"(kmhd\.eu|katworld\.net)", "KatDrive": "katdrive", "GDFlix": "gdflix", "NexDrive": "nexdrive", "Pixeldrain": "pixeldrain", "FilePress": "filepress", "VCloud": "vcloud", "Mega": "mega.nz", "FastDL": "fastdl"}
    ul = url.lower()
    for name, pat in patterns.items():
        if re.search(pat, ul): return name
    return "Direct"

def _priority(link: dict) -> int:
    s = link["server"].lower()
    if "bridge" in s: return 0
    if "nexdrive" in s or "katdrive" in s: return 5
    if "gdflix" in s or "vcloud" in s: return 4
    if "pixeldrain" in s or "filepress" in s: return 3
    return 1
