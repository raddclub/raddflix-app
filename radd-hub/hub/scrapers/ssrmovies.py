"""SSRMovies scraper (v5.6 - Total Vegamovies Architectural Alignment).

Specialized for Hindi/Dual Audio content.
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

log = logging.getLogger("hub.scrapers.ssrmovies")

DOMAINS = [
    "https://ssrmovies.irish",
    "https://ssrmovies.fit",
    "https://ssrmovies.club",
    "https://ssrmovies.art",
]

SITEMAP_CACHE_TTL = 3600 * 12

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
}

# ── Domain & Sitemap Helpers ─────────────────────────────────────────────────

def _domain() -> str:
    from hub import db
    override = db.setting("domain_ssrmovies", "").strip()
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
    for i in range(1, 11):
        cache_path = cache_dir / f"ssrmovies_{domain_hash}_sitemap{i}.xml"
        if cache_path.exists():
            age = time.time() - cache_path.stat().st_mtime
            if age < SITEMAP_CACHE_TTL:
                try:
                    contents.append(cache_path.read_text(encoding="utf-8"))
                    continue
                except Exception:
                    pass

        url = f"{base_url}/post-sitemap{i}.xml"
        text = fetch(url)
        if not text and i == 1:
            url = f"{base_url}/post-sitemap.xml"
            text = fetch(url)
            
        if text:
            cache_path.write_text(text, encoding="utf-8")
            contents.append(text)
            if "post-sitemap.xml" in url: break
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

    if any(l in q.lower() for l in ["hindi", "dual", "multi"]):
        if any(l in slug for l in ["hindi", "dual", "multi"]): score += 40

    matched_count = sum(1 for qk in query_sig if slug_contains(qk, slug))
    if query_sig:
        coverage = matched_count / len(query_sig)
        score += coverage * 50

    return score


# ── Search Implementation ────────────────────────────────────────────────────

def search(title: str, year: str | None = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    base = _domain()
    y_str = str(year) if year and str(year) != "None" else ""
    
    queries_to_try = []
    if preferred_lang:
        queries_to_try.append((f"{title} {preferred_lang} {y_str}".strip(), preferred_lang))
    queries_to_try.append((f"{title} {y_str}".strip(), ""))

    for q, lang_val in queries_to_try:
        log.info("ssrmovies: Searching for '%s'...", q)

        # Strategy 1: REST API
        results = _search_via_rest_api(base, q, y_str)
        if results:
            log.info("ssrmovies: Found %d results via REST API", len(results))
            return results

        # Strategy 2: Sitemap
        results = _search_via_sitemaps(base, title, y_str, preferred_lang=lang_val)
        if results:
            log.info("ssrmovies: Found %d results via Sitemap", len(results))
            return results

        # Strategy 3: Standard Search
        import urllib.parse
        search_url = f"{base}/?s={urllib.parse.quote(q)}"
        html = fetch(search_url)
        if html:
            res = _parse_search_html(html, base, y_str)
            if res: return res

    return []


def _search_via_sitemaps(base: str, title: str, year: str, preferred_lang: str = "") -> List[Dict[str, Any]]:
    sitemaps = _get_sitemaps(base)
    if not sitemaps: return []

    q_full = f"{title} {preferred_lang} {year}".strip()
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
                "site": "ssrmovies",
                "quality": quality_from_text(slug),
            })
        if len(all_candidates) >= 1000: break

    if not all_candidates: return []
    all_candidates.sort(key=lambda c: _rank_candidate(c, keywords, year, q=q_full), reverse=True)
    return all_candidates[:15]


def _search_via_rest_api(base: str, q: str, year: str) -> List[Dict[str, Any]]:
    import urllib.parse as _up
    import json as _json
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
                    "site": "ssrmovies",
                    "quality": quality_from_text(title),
                })
            
            norm_title = normalize(q)
            keywords = [k for k in norm_title.split() if (len(k) > 1 or (len(k) == 1 and k.isdigit())) and k not in _SLUG_NOISE]
            scored = [(c, _rank_candidate(c, keywords, year, q=q)) for c in results]
            return [c for c, s in sorted(scored, key=lambda x: x[1], reverse=True) if s >= 0]
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
                "site": "ssrmovies",
                "quality": quality_from_text(title),
            })
    seen = set(); final = []
    for r in results:
        if r["url"] not in seen: final.append(r); seen.add(r["url"])
    return final


# ── Extraction Implementation ────────────────────────────────────────────────

_CDN_PAT = re.compile(
    r'https?://[^/\s"\'<>]*(?:'
    r'nexdrive\.|vcloud\.|gdflix\.|pixeldrain\.|hubcloud\.|mega\.nz|buzzheavier\.|filepress\.|drive\.google\.|gdtot\.|fastdl\.|linkszilla\.|direct-cloud\.'
    r')[^\s"\'<>]*', re.I
)

def get_download_links(page_url: str, season_hint: str = "", preferred_lang: str = "") -> List[Dict[str, Any]]:
    log.info("ssrmovies: Extracting links from: %s", page_url)

    # 1. REST API
    content_data = _get_download_links_via_rest_api(page_url)
    if content_data:
        html, title = content_data
        links = _parse_download_links_html(html, page_url, title, season_hint=season_hint)
        if links: return links

    # 2. Static Fallback
    html = fetch(page_url)
    if html:
        title_m = re.search(r'<title>(.*?)</title>', html, re.I)
        links = _parse_download_links_html(html, page_url, title_m.group(1) if title_m else "", season_hint=season_hint)
        if links: return links

    return []


def _get_download_links_via_rest_api(page_url: str) -> Optional[Tuple[str, str]]:
    m = re.match(r'(https?://[^/]+)/(.+?)/?$', page_url)
    if not m: return None
    base, slug = m.group(1), m.group(2).strip("/").split("/")[-1]
    api_url = f"{base}/wp-json/wp/v2/posts?slug={slug}&_fields=content,title"
    try:
        text = fetch(api_url)
        if text:
            import json as _json
            posts = _json.loads(text)
            if posts: return posts[0]["content"]["rendered"], posts[0]["title"]["rendered"]
    except: pass
    return None


def _parse_download_links_html(
    html: str, page_url: str, page_title: str, season_hint: str = ""
) -> List[Dict[str, Any]]:
    soup = BeautifulSoup(html, "lxml")
    content = soup.find("div", class_=re.compile(r"entry-content|post-content", re.I))
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
            
            if keywords and not any(k in ctx or k in anchor_low for k in keywords):
                continue
            candidates.append({"url": href, "anchor": anchor, "ctx": ctx})

    if not candidates: return []
    
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
        futures = [ex.submit(_probe, c, page_title) for c in candidates[:20]]
        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            if res: results.append(res)
            
    results.sort(key=lambda x: _priority(x), reverse=True)
    return results


def _probe(c: dict, page_title: str) -> Optional[dict]:
    url = c["url"]
    full_ctx = (c["anchor"] + " " + c["ctx"]).lower()
    server = _detect_server(url)
    qual = quality_from_text(full_ctx)
    if qual == "?": qual = quality_from_text(page_title)
    size = extract_size(full_ctx)
    return {
        "label": f"{qual} {server} {size}".strip(),
        "url": url,
        "server": server,
        "quality": qual,
        "size": size,
    }


def _detect_server(url: str) -> str:
    patterns = {"Google Drive": "drive.google", "Pixeldrain": "pixeldrain", "MEGA": "mega.nz", "FilePress": "filepress", "GDFlix": "gdflix", "vCloud": "vcloud", "FastDL": "fastdl", "NexDrive": "nexdrive", "LinkSzilla": "linkszilla", "Direct Cloud": "direct-cloud"}
    ul = url.lower()
    for name, pat in patterns.items():
        if pat in ul: return name
    return "Direct"


def _priority(link: dict) -> int:
    s = link["server"].lower()
    if "nexdrive" in s: return 2
    if "linkszilla" in s or "direct cloud" in s: return 3
    if "gdflix" in s or "direct" in s: return 4
    return 1
