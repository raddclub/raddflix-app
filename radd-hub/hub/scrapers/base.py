"""Shared HTTP helpers for all scrapers."""
from __future__ import annotations
import logging
import time
import re
import urllib.parse
from typing import Optional

log = logging.getLogger("hub.scrapers")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
    "DNT": "1",
}

TIMEOUT = 20


def get_session():
    import requests
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def fetch(url: str, session=None, timeout: int = TIMEOUT, retries: int = 2) -> Optional[str]:
    if session is None:
        session = get_session()
    
    # Use the base domain as referer for better bypass success
    try:
        up = urllib.parse.urlparse(url)
        if up.netloc:
            session.headers.update({"Referer": f"{up.scheme}://{up.netloc}/"})
    except:
        pass

    for attempt in range(retries + 1):
        try:
            r = session.get(url, timeout=timeout, allow_redirects=True)
            body_low = r.text.lower()
            # ── Cloudflare / Blocked Fallback ──
            is_blocked = r.status_code in (403, 503)
            # Only consider it a CF challenge if status isn't 200 OR we see explicit challenge markers
            is_challenge = False
            if "cf-browser-verification" in body_low or "ray id" in body_low or "one more step" in body_low:
                is_challenge = True
            
            if r.status_code == 200 and not (is_blocked or is_challenge):
                return r.text

            # 403 is a hard block — no point retrying
            if r.status_code == 403 and not is_challenge:
                log.warning("fetch %s → HTTP 403 (blocked, aborting retries)", url)
                return None

            if is_blocked or is_challenge:
                # Use pure HTTP or thread-isolated PW in sites/_pw_fallback.py instead.
                pass

            log.warning("fetch %s → HTTP %s", url, r.status_code)
        except Exception as e:
            err_str = str(e)
            # Infinite redirect loop — no point retrying
            if "redirect" in err_str.lower() and "exceed" in err_str.lower():
                log.warning("fetch %s → redirect loop, aborting retries", url)
                return None
            log.warning("fetch %s attempt %d error: %s", url, attempt, e)
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    return None


def clean_title(t: str) -> str:
    t = re.sub(r"\(?\d{4}\)?", "", t)
    t = re.sub(r"\b(720p|1080p|480p|4K|UHD|BluRay|WEB-DL|HDRip|DVDRip|HEVC|x265|x264)\b", "", t, flags=re.I)
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def normalize(s: str) -> str:
    # Lowercase and replace non-alphanumeric (except space) with space, then collapse spaces
    s = (s or "").lower()
    s = re.sub(r"[^\w\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def quality_from_text(text: str) -> str:
    text = text.upper()
    for q in ["4K", "2160P", "1080P", "720P", "480P", "360P"]:
        if q in text:
            return q.replace("P", "p").replace("2160p", "4K")
    return "?"


def extract_size(text: str) -> str:
    m = re.search(r"(\d[\d.]+\s*(?:GB|MB|TB))", text, re.I)
    return m.group(1).strip() if m else ""


def absolutize(href: str, base_url: str) -> str:
    if href.startswith("http"):
        return href
    return urllib.parse.urljoin(base_url, href)
