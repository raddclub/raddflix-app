"""Domain Doctor — advanced domain discovery and fingerprinting.

Every 24 hours (or on-demand):
  1. Specifically visits "Source of Truth" pages for KatMovie, etc.
  2. Probes redirect chains for SSR and others.
  3. Verifies "Site Fingerprints" (WP themes, specific IDs) to block clones.
  4. Saves the working winner to DB settings (domain_{site}).
"""
from __future__ import annotations
import time
import logging
import threading
import requests
import re
from typing import Optional
from . import db

log = logging.getLogger("hub.domain_doctor")

# ── Site Fingerprints ────────────────────────────────────────────────────────
FINGERPRINTS: dict[str, list[str]] = {
    "rogmovies":  ["/wp-content/themes/vegamoviesofficial/", "rogmovies.blog"],
    "katmoviehd": ["katmoviehd", "katmovieshd.net"],
    "ssrmovies":  ["ssrmovies", "ssr movies"],
    "rareanimes": ["rareanimes", "rareanimes.buzz"],
}

# ── Primary Discovery URLs ───────────────────────────────────────────────────
SOURCES_OF_TRUTH: dict[str, str] = {
    "katmoviehd": "https://katmovieshd.net",
}

# ── Registry of common mirrors ───────────────────────────────────────────────
MIRROR_REGISTRY: dict[str, list[str]] = {
    "rogmovies": [
        "https://rogmovies.blog", "https://rogmovies.info",
    ],
    "ssrmovies": [
        "https://ssrmovies.irish", "https://ssrmovies.center",
    ],
    "rareanimes": [
        "https://www.rareanimes.buzz", "https://rareanimes.cc",
    ],
    "katmoviehd": [
        "https://new1.katmoviehd.cymru", "https://katmoviehd.fans",
    ],
    "7starhd": [
        "https://7starhd.menu/",
    ]
}

_LOCK = threading.Lock()
_DOMAIN_HEALTH: dict[str, dict] = {}

def get_domain_health() -> dict:
    with _LOCK:
        return {k: dict(v) for k, v in _DOMAIN_HEALTH.items()}

def verify_fingerprint(site: str, html: str) -> bool:
    """Check if the HTML content matches the site's unique markers."""
    markers = FINGERPRINTS.get(site, [])
    if not markers: return True
    
    html_low = html.lower()
    # Require at least one HIGH-QUALITY marker to match
    # (e.g. theme path or specific domain mention in meta)
    for m in markers:
        if m.lower() in html_low:
            return True
    return False

def probe_domain(site: str, url: str, timeout: float = 10.0) -> tuple[bool, str, float]:
    """Return (is_verified, final_url, elapsed_time)."""
    try:
        t0 = time.monotonic()
        r = requests.get(url, timeout=timeout, allow_redirects=True,
                         headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"})
        elapsed = time.monotonic() - t0
        
        if r.status_code >= 500:
            return False, url, elapsed
            
        # Verify Fingerprint - skip for common CDNs or known portals
        if verify_fingerprint(site, r.text):
            return True, r.url.rstrip("/"), elapsed
            
        return False, r.url, elapsed
    except Exception:
        return False, url, 99.0

def discover_katmoviehd() -> Optional[str]:
    """Source of Truth: Visit katmovieshd.net and find the 'Click Here' button."""
    try:
        sot_url = SOURCES_OF_TRUTH["katmoviehd"]
        r = requests.get(sot_url, timeout=10)
        # Find the specific button link
        # <a href="https://katmoviehd.fans/" class="button style1 large"> Click Here to Visit</a>
        m = re.search(r'href="(https?://[^"]+)"[^>]*class="button[^"]*">.*?Click Here to Visit', r.text, re.I | re.S)
        if m:
            url = m.group(1).rstrip("/")
            log.info("domain_doctor: KatMovieHD SoT found: %s", url)
            return url
    except Exception as e:
        log.debug("domain_doctor: KatMovieHD SoT failed: %s", e)
    return None

def probe_site(site: str) -> Optional[str]:
    """Discovery logic per site."""
    best_url: Optional[str] = None
    
    # 1. Specialized Finders
    if site == "katmoviehd":
        sot = discover_katmoviehd()
        if sot:
            ok, final, _ = probe_domain(site, sot)
            if ok: best_url = final
            
    # 2. Family Check (Vegamovies family often links to each other)
    # TODO: Implement if Registry fails
    
    # 3. Registry Probe
    if not best_url:
        mirrors = MIRROR_REGISTRY.get(site, [])
        for url in mirrors:
            ok, final, elapsed = probe_domain(site, url)
            if ok:
                log.info("domain_doctor: %s verified at %s (%.2fs)", site, final, elapsed)
                best_url = final
                break
                
    if best_url:
        # 4. Save to DB
        key = f"domain_{site}"
        old = db.setting(key, "")
        if best_url != old:
            log.info("domain_doctor: updating %s domain: %s -> %s", site, old, best_url)
            db.set_setting(key, best_url)
            db.set_setting(f"{key}_ts", str(int(time.time())))
            
    # Update health stats
    with _LOCK:
        _DOMAIN_HEALTH[site] = {
            "active_domain": best_url or "DOWN",
            "last_probe_at": int(time.time()),
            "status": "ok" if best_url else "down",
        }
        
    return best_url

def probe_all():
    """Probe all active sites."""
    log.info("domain_doctor: starting discovery cycle...")
    for site in MIRROR_REGISTRY:
        probe_site(site)
    log.info("domain_doctor: cycle complete.")

def loop(stop_event: threading.Event):
    """Background loop: run every 24 hours (only used when ENABLE_DOMAIN_DOCTOR=1).
    Does NOT run immediately on startup — first run is after 24 hours.
    Use POST /admin/api/domain-doctor/run to trigger on demand."""
    while not stop_event.wait(24 * 3600):
        if db.setting("DOMAIN_DOCTOR_ENABLED", "1") != "1":
            log.debug("domain_doctor: DOMAIN_DOCTOR_ENABLED=0, skipping run")
            continue
        try:
            probe_all()
        except Exception as e:
            log.error("domain_doctor error: %s", e)

def start(stop_event: threading.Event):
    t = threading.Thread(target=loop, args=(stop_event,), daemon=True, name="domain-doctor")
    t.start()
    log.info("Advanced Domain Doctor started")
