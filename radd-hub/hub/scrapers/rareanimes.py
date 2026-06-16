"""RareAnimes scraper."""
from __future__ import annotations
import re, logging
from .base import fetch, absolutize, quality_from_text, extract_size, clean_title

log = logging.getLogger("hub.scrapers.rareanimes")
DOMAINS = ["https://rareanimes.buzz", "https://rareanimes.co"]


def _domain():
    from hub import db
    v = db.setting("domain_rareanimes", "").strip().rstrip("/")
    return v if v else DOMAINS[0]


def search(title: str, year: str = "") -> list[dict]:
    base = _domain()
    q = f"{title} {year}".strip()
    url = f"{base}/?s={q.replace(' ', '+')}"
    html = fetch(url)
    if not html:
        return []
    results = []
    for m in re.finditer(r'<h\d[^>]*class="[^"]*(?:entry-title|post-title|title)[^"]*"[^>]*>\s*<a\s+href="([^"]+)"[^>]*>([^<]+)', html, re.S | re.I):
        href, text = m.group(1), m.group(2).strip()
        if not href.startswith("http"):
            href = absolutize(href, base)
        yr_m = re.search(r"(20\d\d|19\d\d)", text)
        results.append({
            "title": clean_title(text),
            "year": yr_m.group(1) if yr_m else year,
            "url": href,
            "site": "rareanimes",
            "thumb": "",
            "quality": quality_from_text(text),
        })
        if len(results) >= 8:
            break
    return results


def get_download_links(page_url: str) -> list[dict]:
    html = fetch(page_url)
    if not html:
        return []
    links = []
    _DL_KW = ["download", "drive", "link", "server", "480", "720", "1080", "4k", "hd", "gdflix", "pixeldrain", "hubcloud"]
    for m in re.finditer(r'<a[^>]+href="(https?://[^"]+)"[^>]*>([^<]{2,80})</a>', html, re.I):
        href, label = m.group(1), m.group(2).strip()
        if any(k in label.lower() or k in href.lower() for k in _DL_KW):
            links.append({
                "label": label,
                "url": href,
                "server": _detect_server(href),
                "quality": quality_from_text(label + " " + page_url),
                "size": extract_size(label),
            })
    seen = set(); out = []
    for l in links:
        if l["url"] not in seen:
            seen.add(l["url"]); out.append(l)
    return out[:20]


def _detect_server(url):
    for name, pat in [("Google Drive","drive.google"),("Pixeldrain","pixeldrain"),("GDFlix","gdflix"),("HubCloud","hubcloud"),("MEGA","mega.nz")]:
        if pat in url.lower(): return name
    return "Direct"
