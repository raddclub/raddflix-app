"""
Pure-HTTP CDN resolvers + parallel race engine.

Full flow for VegaMovies / RogMovies / GokuHD:
  Movie page → quality blocks → "Download Now" → nexdrive.pro/xxxxx (bridge)
  nexdrive page → G-Direct | V-Cloud | Filepress | Alternative Sources
                    ↓           ↓           ↓             ↓
  race_cdn_links() fires ALL in parallel — first real file URL wins.

Resolvers (pure HTTP, no browser):
  parse_nexdrive_page  – fetch bridge page, extract all CDN URLs
  resolve_vcloud_http  – VCloud: find token, POST generate, pick best server
  resolve_filepress_http – FilePress: walk to INSTANT DOWNLOAD → GDrive
  resolve_gofile_http  – GoFile API → direct cdn link
  resolve_megaup_http  – MegaUp: parse download form
  resolve_pixeldrain_url – /api/file/{id}?download
  resolve_1fichier_http  – 1fichier.com direct download
  resolve_gdirect_url    – follow Google Drive redirects
  resolve_generic_http   – HEAD check + redirect follower
  race_cdn_links(urls)   – parallel race, returns first direct-file URL
"""
from __future__ import annotations
import re
import logging
import time

log = logging.getLogger("hub.sites.cdn_resolvers")

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
_TIMEOUT = 15
_RACE_TIMEOUT = 22

_DIRECT_MIME = (
    "video/", "application/octet-stream", "application/x-matroska",
    "application/zip", "application/x-rar",
)
_DIRECT_EXT = (".mkv", ".mp4", ".avi", ".webm", ".mov", ".zip", ".rar", ".7z")


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def _sess(referer: str = "") -> "requests.Session":
    import requests
    s = requests.Session()
    s.headers.update({"User-Agent": _UA, "Accept-Language": "en-US,en;q=0.9"})
    if referer:
        s.headers["Referer"] = referer
    return s


def _is_direct_url(url: str, resp=None) -> bool:
    u = url.lower().split("?")[0]
    
    # Generic direct extensions
    if any(u.endswith(ext) for ext in _DIRECT_EXT):
        # Even if extension matches, if we have a response, check its content type
        if resp is not None:
            ct = (resp.headers.get("content-type") or "").lower()
            if "text/html" in ct or "text/plain" in ct:
                return False
        return True

    # Known direct CDN patterns
    if "googlevideo.com" in u or "googleusercontent.com/drive" in u:
        return True
    if "/api/file/" in u:
        return True

    if resp is not None:
        ct = (resp.headers.get("content-type") or "").lower()
        cl = int(resp.headers.get("content-length") or 0)
        
        # If it's HTML, it's NOT a direct media URL
        if "text/html" in ct:
            return False
            
        # Direct media types
        if any(t in ct for t in _DIRECT_MIME):
            # A media file should generally be larger than a few hundred KB.
            # If cl is missing (0), we trust the mime type but log it.
            if cl > 500000 or cl == 0:
                return True
            # If no content-length and explicitly video, trust it.
            if "video/" in ct:
                return True
    return False


def _follow_redirect(url: str, sess=None, max_redirects: int = 6) -> str | None:
    """Follow HTTP redirects without raising; returns final URL if it looks direct."""
    try:
        s = sess or _sess()
        # Use GET for the last hop if HEAD is blocked/lying, but HEAD is faster
        r = s.head(url, timeout=_TIMEOUT, allow_redirects=True)
        if _is_direct_url(r.url, r):
            return r.url
        
        # Some servers block HEAD but allow GET
        if r.status_code in (403, 405):
            r = s.get(url, timeout=_TIMEOUT, allow_redirects=True, stream=True)
            if _is_direct_url(r.url, r):
                return r.url
    except Exception:
        pass
    return None


# ──────────────────────────────────────────────────────────────────────────────
# 1. NexDrive bridge page parser
# ──────────────────────────────────────────────────────────────────────────────

def _unwrap_payload(url: str) -> str:
    if url.startswith("PAYLOAD:"):
        try:
            import json
            data = json.loads(url[8:])
            if isinstance(data, list) and len(data) > 0:
                return data[0].get("url", url)
        except: pass
    return url


def parse_nexdrive_page(url: str, referer: str = "") -> dict:
    """
    Fetch nexdrive.pro/xxxxx via static HTTP (xla cookie trick).
    Returns:
        {
            "gdirect":      str | None,     # Google Drive direct link
            "vcloud":       str | None,     # vcloud.zip/xxx
            "filepress":    str | None,     # filepress.wiki/file/xxx
            "alternatives": list[str],      # gofile, 1fichier, pixeldrain, megaup, vikingfile…
        }
    Sets xla=s4t cookie so nexdrive returns full content without JS execution.
    """
    url = _unwrap_payload(url)
    result: dict = {"gdirect": None, "vcloud": None, "filepress": None, "alternatives": []}
    try:
        import requests as _req
        from urllib.parse import urlparse as _up
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": referer or url})
        host = _up(url).hostname or ""
        if host:
            sess.cookies.set("xla", "s4t", domain=host)
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            log.warning("nexdrive: HTTP %d for %s", r.status_code, url)
            return result
        return _parse_nexdrive_html(r.text)
    except Exception as exc:
        log.warning("parse_nexdrive_page(%s): %s", url, exc)
        return result


def _parse_nexdrive_html(html: str) -> dict:
    result: dict = {
        "gdirect": None, "vcloud": None, "filepress": None, "alternatives": [],
        "vclouds": [], "gdirects": [], "filepresses": [] # lists for multiple eps
    }
    seen: set[str] = set()

    def _add_alt(link: str):
        link = link.strip().rstrip(".,;)")
        if link and link not in seen:
            seen.add(link)
            result["alternatives"].append(link)

    # 1. href-based links with anchor text
    for m in re.finditer(r'<a\s[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.I | re.S):
        u = m.group(1).strip()
        anchor = re.sub(r'<[^>]+>', '', m.group(2)).strip().lower()
        if not u.startswith("http"):
            continue
        
        ul = u.lower()
        path = re.sub(r'https?://[^/]+', '', ul)
        is_batch = any(kw in anchor for kw in ["batch", "zip", "pack", "complete"]) or \
                   any(kw in path for kw in ["batch", "pack", "complete"]) or \
                   (path.endswith(".zip") or path.endswith(".rar"))
        
        entry = {"url": u, "anchor": anchor, "is_batch": is_batch}
        
        if "vcloud." in ul:
            result["vclouds"].append(entry)
            if not result["vcloud"] or (is_batch and not any(e["is_batch"] for e in result["vclouds"][:-1])):
                result["vcloud"] = u
        elif "filepress." in ul:
            result["filepresses"].append(entry)
            if not result["filepress"] or (is_batch and not any(e["is_batch"] for e in result["filepresses"][:-1])):
                result["filepress"] = u
        elif any(h in ul for h in ("drive.google.com", "googleusercontent.com", "googlevideo.com")):
            result["gdirects"].append(entry)
            if not result["gdirect"] or (is_batch and not any(e["is_batch"] for e in result["gdirects"][:-1])):
                result["gdirect"] = u
        elif "gofile.io" in ul:
            _add_alt(u)
        elif "1fichier.com" in ul:
            _add_alt(u)
        elif "megaup.net" in ul:
            _add_alt(u)
        elif "pixeldrain." in ul:
            _add_alt(u)
        elif "vikingfile." in ul:
            _add_alt(u)
        elif "buzzheavier." in ul:
            _add_alt(u)
        elif "gdtot." in ul or "gdtot.dad" in ul or "gdtot.pro" in ul:
            _add_alt(u)
        elif "dgdrive." in ul or "dropgalaxy." in ul:
            _add_alt(u)
        elif "oxxfile." in ul:
            _add_alt(u)

    # 2. Match naked URLs in window.open or scripts
    _JS_URLS = re.findall(r'window\.open\(["\'](https?://[^"\']+)["\']', html)
    for u in _JS_URLS:
        ul = u.lower()
        if "vcloud." in ul:
            result["vclouds"].append({"url": u, "anchor": "script", "is_batch": False})
            if not result["vcloud"]: result["vcloud"] = u
        elif "filepress." in ul:
            result["filepresses"].append({"url": u, "anchor": "script", "is_batch": False})
            if not result["filepress"]: result["filepress"] = u
        else:
            _add_alt(u)

    # 3. Match any button/link via regex fallback (catches remaining CDN patterns)
    _ANY_HREF = re.findall(r'href=["\'](https?://[^"\']+)["\']', html)
    for u in _ANY_HREF:
        ul = u.lower()
        if any(h in ul for h in (
            "vcloud.", "filepress.", "filebee.xyz", "fastdl.zip",
            "gofile.io", "1fichier.com", "gdtot.", "dgdrive.", "oxxfile.", "dropgalaxy.",
        )):
            if u not in seen:
                if "vcloud." in ul and not result["vcloud"]: result["vcloud"] = u
                if "filepress." in ul and not result["filepress"]: result["filepress"] = u
                if "filebee.xyz" in ul and not result["filepress"]: result["filepress"] = u
                # fastdl.zip is "G-Direct [Instant]" on nexdrive — treat as gdirect
                if "fastdl.zip" in ul and not result["gdirect"]: result["gdirect"] = u
                # gdtot/dgdrive/oxxfile → alternatives only (JS/CF protected)
                if any(h in ul for h in ("gdtot.", "dgdrive.", "oxxfile.", "dropgalaxy.")):
                    _add_alt(u)
                else:
                    _add_alt(u)


    # Prioritize Batch links in the main keys if they exist
    for key, list_key in [("vcloud", "vclouds"), ("filepress", "filepresses"), ("gdirect", "gdirects")]:
        batches = [e["url"] for e in result[list_key] if e["is_batch"]]
        if batches:
            result[key] = batches[0] # Pick first batch found

    # Also scan plain-text URLs
    # bare hostnames (no https://) like: gofile.io/d/xxxxx  1fichier.com/?xxx
    _ALT_HOSTS = (
        "gofile.io", "1fichier.com", "vikingfile.", "megaup.net",
        "pixeldrain.", "buzzheavier.",
    )
    # Full https:// URLs first
    _ALT_PAT_FULL = re.compile(
        r'https?://(?:gofile\.io|1fichier\.com|vikingfile\.[a-z]+|'
        r'megaup\.net|pixeldrain\.[a-z]+|buzzheavier\.[a-z]+)[^\s"\'<>]+',
        re.I,
    )
    for m in _ALT_PAT_FULL.finditer(html):
        _add_alt(m.group(0))
    # Bare-hostname URLs (no protocol prefix)
    _ALT_PAT_BARE = re.compile(
        r'(?<!["/])(?:gofile\.io|1fichier\.com|vikingfile\.[a-z]+|'
        r'megaup\.net|pixeldrain\.[a-z]+|buzzheavier\.[a-z]+)/[^\s"\'<>]+',
        re.I,
    )
    for m in _ALT_PAT_BARE.finditer(html):
        candidate = "https://" + m.group(0).rstrip(".,;)")
        _add_alt(candidate)

    log.debug(
        "nexdrive parsed: gdirect=%s vcloud=%s filepress=%s alts=%d",
        bool(result["gdirect"]), bool(result["vcloud"]),
        bool(result["filepress"]), len(result["alternatives"]),
    )
    return result


# ──────────────────────────────────────────────────────────────────────────────
# 2. V-Cloud HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_vcloud_http(url: str) -> str | None:
    """
    Try to generate a VCloud download link via pure HTTP.
    VCloud generates server URLs after a POST call — we replicate that here.
    Falls back gracefully; if None is returned the caller should use Playwright.
    """
    url = _unwrap_payload(url)
    import json as _json
    try:
        import requests as _req
        from urllib.parse import urlparse as _up
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        base_url = f"{_up(r.url).scheme}://{_up(r.url).netloc}"

        # ── Step 1: Extract Token Link ──
        m_token = re.search(r"var\s+url\s*=\s*['\"](https?://[^\s\"']+\?token=[A-Za-z0-9+/=]+)['\"]", html)
        if m_token:
            token_url = m_token.group(1)
            log.debug("vcloud_http: found token-link: %s", token_url[:60])
            
            # Step 2: Follow Token Link to landing page
            try:
                sess.headers.update({"Referer": url})
                r2 = sess.get(token_url, timeout=10, allow_redirects=True)
                if r2.status_code == 200:
                    # Collect all external hrefs on the landing page —
                    # VCloud uses many different server providers so we try all of them.
                    _known_dl_hosts = (
                        "hubcloud", "gpdl", "diskcdn", "gamerxyt",
                        "fsl.buzz", "fsl.video", "pixelserver",
                        "buzzheavier", "fastdl", "worker",
                    )
                    # First pass: prefer known fast-download hosts
                    all_hrefs = re.findall(r'href=["\'](' + r'https?://[^\s"\'<>]+' + r')["\']', r2.text, re.I)
                    # Try known high-priority hosts first, then anything else
                    ordered = (
                        [h for h in all_hrefs if any(k in h.lower() for k in _known_dl_hosts)]
                        + [h for h in all_hrefs if not any(k in h.lower() for k in _known_dl_hosts)
                           and "vcloud." not in h.lower()
                           and h.startswith("http")
                           and len(h) > 20]
                    )
                    for candidate in ordered:
                        try:
                            with sess.get(candidate, timeout=6, allow_redirects=True, stream=True) as r_val:
                                if _is_direct_url(r_val.url, r_val):
                                    log.debug("vcloud_http: validated final server link: %s", r_val.url[:60])
                                    return r_val.url
                                # Return intermediate CDN link for further resolution
                                if any(x in r_val.url.lower() for x in _known_dl_hosts):
                                    return r_val.url
                        except Exception:
                            continue
            except Exception as e:
                log.debug("vcloud_http: landing page error: %s", e)

        # ── Fallback: Original POST logic ──

        # ── Look for the file slug / token in the page ──
        slug = None
        # data-id attribute on the generate button
        for pat in [
            r'data-id=["\']([A-Za-z0-9_\-]{4,})["\']',
            r'"id"\s*:\s*"([A-Za-z0-9_\-]{4,})"',
            r"'id'\s*:\s*'([A-Za-z0-9_\-]{4,})'",
        ]:
            m = re.search(pat, html)
            if m:
                slug = m.group(1)
                break
        if not slug:
            # Derive from URL itself: vcloud.zip/{slug}
            m2 = re.search(r'vcloud\.[^/]+/([A-Za-z0-9_\-]{4,})', url)
            if m2:
                slug = m2.group(1)

        if not slug:
            return None

        # ── Try common generate endpoints ──
        endpoints = [
            f"{base_url}/api/v1/generate",
            f"{base_url}/api/download",
            f"{base_url}/generate",
            f"{base_url}/dl/generate",
            f"{base_url}/v2/generate",
        ]
        headers = {
            "X-Requested-With": "XMLHttpRequest",
            "Origin": base_url,
            "Referer": url,
            "Content-Type": "application/json",
        }
        for ep in endpoints:
            try:
                rp = sess.post(ep, json={"id": slug}, headers=headers, timeout=12)
                if rp.status_code not in (200, 201):
                    log.debug("vcloud_http: %s returned %d", ep, rp.status_code)
                    continue
                try:
                    d = rp.json()
                    log.debug("vcloud_http: response from %s: %s", ep, d)
                except Exception:
                    log.debug("vcloud_http: non-json response from %s: %s", ep, rp.text[:200])
                    continue
                # Pick the best server URL from JSON response
                # Priority: fsl > pixelserver > server1 > any other
                _SERVER_KEYS = [
                    "fsl", "fslv2", "fsl_url",
                    "pixelserver", "pixel_server",
                    "server1", "server_1", "server",
                    "link", "url", "download_url", "download",
                ]
                for key in _SERVER_KEYS:
                    v = d.get(key) or d.get("data", {}).get(key)
                    if v and isinstance(v, str) and v.startswith("http"):
                        log.debug("vcloud_http: found link via key=%s", key)
                        return v
                # Recursive scan for any HTTP URL in JSON
                raw_str = _json.dumps(d)
                urls = re.findall(r'https?://[^\s"\'<>]{20,}', raw_str)
                for u2 in urls:
                    if not any(bad in u2.lower() for bad in ["vcloud", "javascript"]):
                        return u2
            except Exception:
                continue

        # All HTTP strategies failed — Playwright fallback
        try:
            from hub.sites._pw_fallback import pw_resolve_vcloud
            log.info("resolve_vcloud_http: HTTP flow exhausted — trying Playwright fallback...")
            return pw_resolve_vcloud(url)
        except Exception as pw_exc:
            log.warning("resolve_vcloud_http PW fallback error: %s", pw_exc)

        return None
    except Exception as exc:
        log.debug("resolve_vcloud_http(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 3. FilePress HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_filepress_http(url: str, referer: str = "") -> str | None:
    """
    FilePress: find INSTANT DOWNLOAD → follow to Google Drive link.
    Page structure:
      filepress.wiki/file/{id}  → buttons: LOGIN | TELEGRAM | FAST CLOUD | INSTANT
      INSTANT DOWNLOAD → filepress.wiki/download/{id} → GDrive / direct link
    """
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": url})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text

        # Extract file ID from URL
        m_id = re.search(r'/file/([A-Za-z0-9]+)', url)
        if not m_id:
            return None
        file_id = m_id.group(1)
        base_url = re.match(r'(https?://[^/]+)', r.url)
        base = base_url.group(1) if base_url else ""

        # Try known download endpoint patterns
        for dl_path in [
            f"/download/{file_id}",
            f"/dl/{file_id}",
            f"/file/{file_id}/download",
            f"/fast-cloud/{file_id}",
        ]:
            try:
                r2 = sess.get(base + dl_path, timeout=_TIMEOUT, allow_redirects=True)
                # Check if we landed on a Google Drive download page
                if "drive.google.com" in r2.url or "googleusercontent.com" in r2.url:
                    return _resolve_gdrive(r2.url, sess)
                if _is_direct_url(r2.url, r2):
                    return r2.url
                # Scan response for GDrive links
                gd = _extract_gdrive_link(r2.text)
                if gd:
                    return gd
            except Exception:
                continue

        # Scan the original page for any GDrive / direct link
        gd = _extract_gdrive_link(html)
        if gd:
            return gd

        # Find INSTANT DOWNLOAD href in page HTML
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>\s*(?:INSTANT|FAST[^<]*)?DOWNLOAD',
            r'href=["\']([^"\']+/(?:download|dl)/[A-Za-z0-9]+)["\']',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                dl_url = _uj(r.url, m.group(1))
                try:
                    r3 = sess.get(dl_url, timeout=_TIMEOUT, allow_redirects=True)
                    if _is_direct_url(r3.url, r3):
                        return r3.url
                    gd2 = _extract_gdrive_link(r3.text)
                    if gd2:
                        return gd2
                except Exception:
                    pass

        return None
    except Exception as exc:
        log.debug("resolve_filepress_http(%s): %s", url, exc)
        return None


def _extract_gdrive_link(html: str) -> str | None:
    patterns = [
        r'https?://lh3\.googleusercontent\.com/drive-viewer/[^\s"\'<>]+',
        r'https?://drive\.usercontent\.google\.com/[^\s"\'<>]+',
        r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{30,}',
        r'"downloadUrl"\s*:\s*"(https?://[^"]+)"',
        r'"url"\s*:\s*"(https?://[^"]*(?:google|gstatic)[^"]+)"',
    ]
    for pat in patterns:
        m = re.search(pat, html, re.I)
        if m:
            link = m.group(1) if m.lastindex else m.group(0)
            return link.rstrip('",;)')
    return None


def _resolve_gdrive(url: str, sess=None) -> str:
    """Follow Google Drive page to extract the actual download URL."""
    try:
        s = sess or _sess()
        r = s.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if _is_direct_url(r.url, r):
            return r.url
        gd = _extract_gdrive_link(r.text)
        if gd:
            return gd
        # Try export=download for Drive file IDs
        m = re.search(r'/d/([A-Za-z0-9_\-]+)', url)
        if m:
            fid = m.group(1)
            return f"https://drive.google.com/uc?export=download&id={fid}&confirm=t"
    except Exception:
        pass
    return url


# ──────────────────────────────────────────────────────────────────────────────
# 4. GoFile HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_gofile_http(url: str) -> str | None:
    """
    GoFile public API — no auth required for public folders.
    GET api.gofile.io/contents/{id} → direct link for first file.
    """
    try:
        import requests as _req
        m = re.search(r'gofile\.io/d/([A-Za-z0-9]+)', url)
        if not m:
            return None
        folder_id = m.group(1)
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA})

        # Get a guest account token (required by GoFile API)
        token: str | None = None
        try:
            r_acct = sess.post(
                "https://api.gofile.io/accounts",
                timeout=10,
            )
            if r_acct.status_code == 200:
                token = r_acct.json().get("data", {}).get("token")
        except Exception:
            pass

        params: dict = {"wt": "4fd6sg89d7s6"}
        if token:
            params["token"] = token
            sess.cookies.set("accountToken", token, domain="gofile.io")

        r2 = sess.get(
            f"https://api.gofile.io/contents/{folder_id}",
            params=params,
            timeout=12,
        )
        if r2.status_code != 200:
            return None
        d = r2.json()
        if d.get("status") != "ok":
            return None

        children = d.get("data", {}).get("children", {})
        for _fid, info in children.items():
            if isinstance(info, dict) and info.get("type") == "file":
                link = info.get("link") or info.get("directLink")
                if link:
                    # Set required cookie for direct download
                    if token:
                        sess.cookies.set("accountToken", token, domain="gofile.io")
                    # Verify it's reachable
                    try:
                        rh = sess.head(link, timeout=8, allow_redirects=True)
                        if rh.status_code < 400:
                            return link
                    except Exception:
                        return link
        return None
    except Exception as exc:
        log.debug("resolve_gofile_http(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 5. MegaUp HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_megaup_http(url: str) -> str | None:
    """
    MegaUp: find the POST download form and follow redirect.
    """
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": url})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text

        # Look for a form with POST action
        m_form = re.search(r'<form[^>]+action=["\']([^"\']+)["\'][^>]*method=["\']post["\']', html, re.I)
        if not m_form:
            m_form = re.search(r'<form[^>]+method=["\']post["\'][^>]*action=["\']([^"\']+)["\']', html, re.I)
        if m_form:
            action = _uj(r.url, m_form.group(1))
            # Extract any hidden inputs
            hidden: dict = {}
            for inp in re.finditer(r'<input[^>]+type=["\']hidden["\'][^>]*>', html, re.I):
                nm = re.search(r'name=["\']([^"\']+)["\']', inp.group(0), re.I)
                vl = re.search(r'value=["\']([^"\']*)["\']', inp.group(0), re.I)
                if nm:
                    hidden[nm.group(1)] = vl.group(1) if vl else ""
            r2 = sess.post(action, data=hidden, timeout=_TIMEOUT, allow_redirects=True)
            if _is_direct_url(r2.url, r2):
                return r2.url
            # Scan response for links
            for pat in [
                r'href=["\']([^"\']+\.(?:mkv|mp4|avi|zip))["\']',
                r'(https?://[^\s"\'<>]+\.(?:mkv|mp4|avi))',
            ]:
                m = re.search(pat, r2.text, re.I)
                if m:
                    return m.group(1)

        # Direct href extraction
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>\s*DOWNLOAD\s*/\s*VIEW',
            r'href=["\']([^"\']+)["\'][^>]*>.*?download.*?now',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = _uj(r.url, m.group(1))
                if "megaup.net" not in candidate.lower():
                    if "dotflix." in candidate.lower():
                        dotflix_result = resolve_dotflix_http(candidate)
                        if dotflix_result:
                            return dotflix_result
                    return candidate

        # Scan page for DotFlix redirect links (MegaUp → DotFlix chain)
        for pat in [
            r'href=["\']([^"\']*dotflix\.[^"\']+)["\']',
            r'(https?://[^\s"\'<>]*dotflix\.[^\s"\'<>]+)',
        ]:
            m = re.search(pat, html, re.I)
            if m:
                dotflix_url = m.group(1)
                if dotflix_url.startswith("http"):
                    result = resolve_dotflix_http(dotflix_url)
                    if result:
                        return result

        return None
    except Exception as exc:
        log.debug("resolve_megaup_http(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 6. Pixeldrain URL builder (no HTTP call needed)
# ──────────────────────────────────────────────────────────────────────────────

def resolve_pixeldrain_url(url: str) -> str | None:
    """Convert pixeldrain share URL to direct API download URL."""
    m = re.search(r'pixeldrain\.[^/]+/(?:u|l)/([A-Za-z0-9]+)', url)
    if not m:
        return None
    file_id = m.group(1)
    base = re.match(r'(https?://pixeldrain\.[^/]+)', url)
    host = base.group(1) if base else "https://pixeldrain.com"
    direct = f"{host}/api/file/{file_id}?download"
    # Quick HEAD to verify
    try:
        import requests as _req
        r = _req.head(direct, timeout=8, allow_redirects=True,
                      headers={"User-Agent": _UA})
        if r.status_code < 400:
            return direct
    except Exception:
        pass
    return direct  # return anyway; HEAD failures might be false negatives


# ──────────────────────────────────────────────────────────────────────────────
# 7. 1Fichier HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_1fichier_http(url: str) -> str | None:
    """
    1fichier.com: try direct download link (guest has a waiting-time).
    We attempt to skip it by posting the form immediately.
    """
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": url})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text

        # Find POST form for guest download
        m_form = re.search(r'<form[^>]+action=["\']([^"\']+)["\']', html, re.I)
        if m_form:
            action = _uj(r.url, m_form.group(1))
            hidden: dict = {}
            for inp in re.finditer(r'<input[^>]+type=["\']hidden["\'][^>]*>', html, re.I):
                nm = re.search(r'name=["\']([^"\']+)["\']', inp.group(0), re.I)
                vl = re.search(r'value=["\']([^"\']*)["\']', inp.group(0), re.I)
                if nm:
                    hidden[nm.group(1)] = vl.group(1) if vl else ""
            hidden.setdefault("dl_no_ssl", "0")
            r2 = sess.post(action, data=hidden, timeout=_TIMEOUT, allow_redirects=True)
            if _is_direct_url(r2.url, r2):
                return r2.url
            # Find direct link in response
            for pat in [r'href=["\']([^"\']+\.(?:mkv|mp4|avi|zip))["\']',
                        r'(https?://[^\s"\'<>]+\.(?:mkv|mp4))']:
                m = re.search(pat, r2.text, re.I)
                if m:
                    return m.group(1)
        return None
    except Exception as exc:
        log.debug("resolve_1fichier_http(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 8. G-Direct / Google Drive resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_gdirect_url(url: str) -> str | None:
    """Follow a Google Drive / direct link to a downloadable URL."""
    try:
        import requests as _req
        ul = url.lower()
        if "googleusercontent.com" in ul and "ADGPM" in url:
            # High confidence direct link
            return url
            
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA})
        
        # Try generic redirect follower first
        res = _follow_redirect(url, sess=sess)
        if res: return res
        
        # Try export=download for Google Drive file IDs
        m = re.search(r'/d/([A-Za-z0-9_\-]+)', url)
        if m:
            fid = m.group(1)
            export_url = f"https://drive.google.com/uc?export=download&id={fid}&confirm=t"
            return _follow_redirect(export_url, sess=sess)
            
        return None
    except Exception as exc:
        log.debug("resolve_gdirect_url(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 9. VikingFile / generic HTTP resolver
# ──────────────────────────────────────────────────────────────────────────────

def resolve_generic_http(url: str) -> str | None:
    """
    Generic: try HEAD, follow redirects, look for a direct-file response.
    Works for VikingFile and many simple CDN shorteners.
    """
    try:
        import requests as _req
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": url})
        # HEAD first
        r = sess.head(url, timeout=_TIMEOUT, allow_redirects=True)
        if _is_direct_url(r.url, r):
            return r.url
        if r.url != url:
            # Followed a redirect
            r2 = sess.head(r.url, timeout=_TIMEOUT, allow_redirects=True)
            if _is_direct_url(r2.url, r2):
                return r2.url
        # GET and parse for a download button
        r3 = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        html = r3.text
        for pat in [
            r'href=["\']([^"\']+\.(?:mkv|mp4|avi|zip|rar))["\']',
            r'href=["\']([^"\']+)["\'][^>]*>\s*(?:Download|Get File)',
        ]:
            m = re.search(pat, html, re.I)
            if m:
                candidate = m.group(1)
                if candidate.startswith("http"):
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_generic_http(%s): %s", url, exc)
        return None


# ──────────────────────────────────────────────────────────────────────────────
# 10. Dispatcher + parallel race
# ──────────────────────────────────────────────────────────────────────────────

def resolve_fastdl_http(url: str, referer: str = "") -> str | None:
    """
    fastdl.zip resolver — handles two URL forms:

    Form 1 (embed/redirect page):
      fastdl.zip/embed?download=<token>
      → page contains: var reurl = "https://fastdl.zip/dl.php?link=<google_video_url>"
      → extract the link= param value → that IS the direct Google Video URL

    Form 2 (dl.php proxy page):
      fastdl.zip/dl.php?link=<direct_url>
      → extract the link= param value directly

    Vglist.cv is the same pattern — its "Download Now" page just wraps the link.
    """
    url = _unwrap_payload(url)
    try:
        import requests as _req
        from urllib.parse import parse_qs as _pqs, urlparse as _up2, unquote as _uq
        parsed_url = _up2(url)
        ul = url.lower()

        # ── Form 1: embed?download=TOKEN ─────────────────────────────────────
        if "embed" in ul and "download" in parsed_url.query:
            sess = _req.Session()
            sess.headers.update({"User-Agent": _UA,
                                  "Referer": "https://vegamovies.market/"})
            r = sess.get(url, timeout=_TIMEOUT, allow_redirects=False)
            html = r.text

            # Extract: var reurl = "https://fastdl.zip/dl.php?link=..."
            m_reurl = re.search(r'var\s+reurl\s*=\s*["\']([^"\']+)["\']', html)
            if m_reurl:
                reurl = m_reurl.group(1)
                # Now extract the link= param from dl.php URL
                qs2 = _pqs(_up2(reurl).query)
                direct = _uq(qs2.get("link", [""])[0])
                if direct.startswith("http") and "fastdl" not in direct.lower():
                    log.debug("resolve_fastdl_http(embed): extracted direct URL: %s", direct[:80])
                    return direct
            # Also check for meta refresh or JS window.location redirect
            m_redirect = re.search(
                r'(?:window\.location|location\.href)\s*=\s*["\']([^"\']+)["\']',
                html, re.I
            )
            if m_redirect:
                return resolve_fastdl_http(m_redirect.group(1))

        # ── Form 2: dl.php?link=DIRECT_URL ──────────────────────────────────
        qs = _pqs(parsed_url.query)
        link_param = _uq(qs.get("link", [""])[0])
        if link_param.startswith("http") and "fastdl" not in link_param.lower():
            log.debug("resolve_fastdl_http(dl.php): link param = %s", link_param[:80])
            # Validate it's reachable
            try:
                r = _req.head(link_param, timeout=10, allow_redirects=True,
                              headers={"User-Agent": _UA})
                if r.status_code < 400:
                    return r.url
            except Exception:
                return link_param  # return it optimistically

        # ── Fallback: scrape the page for Download Now link ──────────────────
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA,
                              "Referer": "https://vcloud.zip/"})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text

        # Also try extracting var reurl from any fastdl page
        m_reurl2 = re.search(r'var\s+reurl\s*=\s*["\']([^"\']+)["\']', html)
        if m_reurl2:
            reurl2 = m_reurl2.group(1)
            qs3 = _pqs(_up2(reurl2).query)
            direct2 = _uq(qs3.get("link", [""])[0])
            if direct2.startswith("http") and "fastdl" not in direct2.lower():
                return direct2

        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>.*?Download\s*Now',
            r'href=["\']([^"\']+)["\'][^>]*>.*?Download',
            r'window\.location\.href\s*=\s*["\'](https?://[^"\']+)["\']',
            r'location\.href\s*=\s*["\'](https?://[^"\']+)["\']',
            r'id=["\']tgbtn["\']\s+href=["\']([^"\']+)["\']',
            r'(https?://[^\s"\'<>]+\.(?:mkv|mp4|avi|zip|rar))',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = m.group(1)
                if candidate.startswith("http") and "fastdl" not in candidate.lower():
                    try:
                        r2 = sess.head(candidate, timeout=10, allow_redirects=True)
                        if r2.status_code < 400:
                            return r2.url
                    except Exception:
                        pass
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_fastdl_http(%s): %s", url, exc)
        return None


def resolve_dotflix_http(url: str) -> str | None:
    """
    dotflix.fun/share/... (MegaUp → DotFlix chain).
    Finds the 'Direct Download' button → final CDN URL.
    """
    try:
        import requests as _req
        sess = _req.Session()
        sess.headers.update({"User-Agent": _UA, "Referer": url})
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>\s*Direct\s+Download',
            r'href=["\']([^"\']+)["\'][^>]*class=["\'][^"\']*btn[^"\']*["\'][^>]*>.*?Download',
            r'href=["\']([^"\']+\.(?:mkv|mp4|avi|zip))["\']',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = m.group(1)
                if candidate.startswith("http") and "dotflix" not in candidate.lower():
                    r2 = _req.head(candidate, timeout=_TIMEOUT, allow_redirects=True,
                                   headers={"User-Agent": _UA})
                    if _is_direct_url(r2.url, r2):
                        return r2.url
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_dotflix_http(%s): %s", url, exc)
        return None


def resolve_hubcloud_http(url: str) -> str | None:
    """
    HubCloud / HubDrive: POST to generate endpoint to get server URLs.
    Same page pattern as VCloud — produces FSLv2 / FSL / 10Gbps / PixelServer:2.
    """
    url = _unwrap_payload(url)
    try:
        import requests as _req
        import json as _json
        from urllib.parse import urlparse as _up
        sess = _sess(referer=url)
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        base_url = f"{_up(r.url).scheme}://{_up(r.url).netloc}"

        # ── Step 1: Follow Redirection ──
        # HubCloud/GPDL/Gamerxyt often use multiple hops
        if any(d in url.lower() for d in ["gpdl", "gamerxyt", "diskcdn"]):
            try:
                # Follow hops until we hit a known direct domain or find a button
                curr_url = url
                for _ in range(3):
                    r_hop = sess.get(curr_url, timeout=10, allow_redirects=True)
                    if _is_direct_url(r_hop.url, r_hop):
                        return r_hop.url
                    
                    # Look for download buttons on this hop
                    m_btn = re.search(
                        r'href=["\'](https?://(?:video-downloads\.googleusercontent\.com|[^"\']+\.(?:mkv|mp4|zip|rar))[^\s"\'<>]+)["\']',
                        r_hop.text, re.I
                    )
                    if m_btn:
                        candidate = m_btn.group(1)
                        with sess.get(candidate, timeout=5, allow_redirects=True, stream=True) as r_val:
                            if _is_direct_url(r_val.url, r_val):
                                return r_val.url
                    
                    if r_hop.url == curr_url: break
                    curr_url = r_hop.url
            except Exception as e:
                log.debug("hubcloud_http hop error: %s", e)

        # ── Step 2: POST Logic ──
        # Extract file slug from URL path (/drive/{slug}) or data attributes
        slug = None
        for pat in [
            r'(?:hubcloud|hubdrive|kutdrive)\.[^/]+/drive/([A-Za-z0-9_\-]{4,})',
            r'data-id=["\']([A-Za-z0-9_\-]{4,})["\']',
            r'"id"\s*:\s*"([A-Za-z0-9_\-]{4,})"',
        ]:
            m = re.search(pat, url + " " + html, re.I)
            if m:
                slug = m.group(1)
                break
        
        if not slug:
            # Fallback slug from vcloud pattern if any
            m2 = re.search(r'(?:vcloud|gpdl|hubcloud|gamerxyt)[^/]+/([A-Za-z0-9_\-]{4,})', url)
            if m2: slug = m2.group(1)

        if not slug:
            return None

        headers = {
            "X-Requested-With": "XMLHttpRequest",
            "Origin": base_url,
            "Referer": url,
            "Content-Type": "application/json",
        }
        for ep in [
            f"{base_url}/api/v1/generate",
            f"{base_url}/api/generate",
            f"{base_url}/generate",
        ]:
            try:
                rp = sess.post(ep, json={"id": slug}, headers=headers, timeout=12)
                if rp.status_code not in (200, 201):
                    continue
                try:
                    d = rp.json()
                except Exception:
                    continue
                _SERVER_KEYS = [
                    "fslv2", "fsl_url", "fsl", "pixelserver", "pixel_server",
                    "10gbps", "ten_gbps", "server1", "server_1", "server",
                    "link", "url", "download_url",
                ]
                for key in _SERVER_KEYS:
                    v = (d.get(key) or (d.get("data") or {}).get(key) or "")
                    if isinstance(v, str) and v.startswith("http") and len(v) > 20:
                        if "fastdl." in v.lower():
                            return resolve_fastdl_http(v) or v
                        return v
                raw_str = _json.dumps(d)
                for u2 in re.findall(r'https?://[^\s"\'<>]{20,}', raw_str):
                    if not any(bad in u2.lower() for bad in ["hubcloud", "hubdrive", "kutdrive"]):
                        return u2
            except Exception:
                continue
        return None
    except Exception as exc:
        log.debug("resolve_hubcloud_http(%s): %s", url, exc)
        return None


def resolve_sendcm_http(url: str) -> str | None:
    """send.cm: extract the direct download link via page parsing or form POST."""
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _sess(referer=url)
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>\s*(?:Download Now|Free Download|Direct Download|Download File)',
            r'(?:download|file)_url\s*[=:]\s*["\']([^"\']+)["\']',
            r'(https?://[^\s"\'<>]+\.(?:mkv|mp4|avi|zip|rar)[^\s"\'<>]*)',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = m.group(1)
                if not candidate.startswith("http"):
                    candidate = _uj(r.url, candidate)
                if "send.cm" not in candidate.lower() and "sendcm" not in candidate.lower():
                    return candidate
        fm = re.search(
            r'<form[^>]+action=["\']([^"\']+)["\'][^>]*method=["\']post["\']', html, re.I
        )
        if fm:
            action = _uj(r.url, fm.group(1))
            hidden: dict = {}
            for inp in re.finditer(r'<input[^>]+type=["\']hidden["\'][^>]*>', html, re.I):
                nm = re.search(r'name=["\']([^"\']+)["\']', inp.group(0), re.I)
                vl = re.search(r'value=["\']([^"\']*)["\']', inp.group(0), re.I)
                if nm:
                    hidden[nm.group(1)] = vl.group(1) if vl else ""
            r2 = sess.post(action, data=hidden, timeout=_TIMEOUT, allow_redirects=True)
            if _is_direct_url(r2.url, r2):
                return r2.url
            if r2.status_code < 400 and "send.cm" not in r2.url.lower():
                return r2.url
        return None
    except Exception as exc:
        log.debug("resolve_sendcm_http(%s): %s", url, exc)
        return None


def resolve_fuckingfast_http(url: str) -> str | None:
    """fuckingfast.net: extract direct download link."""
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _sess(referer=url)
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*(?:class|id)=["\'][^"\']*(?:btn-download|download-btn)[^"\']*["\']',
            r'href=["\']([^"\']+)["\'][^>]*>\s*(?:Download Now|Free Download|Download File)',
            r'"(?:download_url|file_url|url)"\s*:\s*"([^"]+)"',
            r'(https?://[^\s"\'<>]+\.(?:mkv|mp4|avi|zip|rar)[^\s"\'<>]*)',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = m.group(1)
                if not candidate.startswith("http"):
                    candidate = _uj(r.url, candidate)
                if "fuckingfast" not in candidate.lower():
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_fuckingfast_http(%s): %s", url, exc)
        return None


def resolve_hexload_http(url: str) -> str | None:
    """hexload.com: extract direct download link."""
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _sess(referer=url)
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        for pat in [
            r'href=["\']([^"\']+)["\'][^>]*>\s*(?:Download|Free Download|Direct Download)',
            r'"download_link"\s*:\s*"([^"]+)"',
            r'"(?:file_url|url)"\s*:\s*"([^"]+)"',
            r'(https?://[^\s"\'<>]+\.(?:mkv|mp4|avi|zip|rar)[^\s"\'<>]*)',
        ]:
            m = re.search(pat, html, re.I | re.S)
            if m:
                candidate = m.group(1)
                if not candidate.startswith("http"):
                    candidate = _uj(r.url, candidate)
                if "hexload" not in candidate.lower():
                    try:
                        r2 = _req.head(candidate, timeout=8, allow_redirects=True,
                                       headers={"User-Agent": _UA})
                        if r2.status_code < 400:
                            return r2.url
                    except Exception:
                        pass
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_hexload_http(%s): %s", url, exc)
        return None


def resolve_gdtot_http(url: str) -> str | None:
    """
    GDToT / similar G-Drive indexers (gdtot.dad, gdtot.pro, etc).
    These often sit behind Cloudflare JS challenge so pure-HTTP rarely works.
    We attempt a quick HEAD/GET; if that fails we return None and the race
    engine falls through to the next CDN.
    """
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _sess(referer="https://vegamovies.market/")
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        # Look for a direct GDrive or download link
        gd = _extract_gdrive_link(html)
        if gd:
            return gd
        # Look for direct download button href
        for pat in [
            r'href=["\'](https?://[^"\']+(?:download|dl)[^"\']+)["\']',
            r'href=["\'](https?://drive\.google\.com/[^"\']+)["\']',
        ]:
            m = re.search(pat, html, re.I)
            if m:
                candidate = m.group(1)
                if "gdtot" not in candidate.lower():
                    return candidate
        return None
    except Exception as exc:
        log.debug("resolve_gdtot_http(%s): %s", url, exc)
        return None


def resolve_dropgalaxy_http(url: str) -> str | None:
    """
    DropGalaxy / dgdrive.pro — attempt static fetch.
    These are JS-heavy so usually returns None; race engine moves on.
    """
    try:
        import requests as _req
        from urllib.parse import urljoin as _uj
        sess = _sess(referer="https://vegamovies.market/")
        r = sess.get(url, timeout=_TIMEOUT, allow_redirects=True)
        if r.status_code != 200:
            return None
        html = r.text
        gd = _extract_gdrive_link(html)
        if gd:
            return gd
        for pat in [
            r'href=["\'](https?://[^"\']+\.(?:mkv|mp4|zip|rar)[^"\']*)["\']',
            r'(?:download_url|file_url)\s*[=:]\s*["\'](https?://[^"\']+)["\']',
        ]:
            m = re.search(pat, html, re.I)
            if m:
                return m.group(1)
        return None
    except Exception as exc:
        log.debug("resolve_dropgalaxy_http(%s): %s", url, exc)
        return None


def resolve_nexdrive_http(url: str, referer: str = "", is_batch: bool = False) -> str | None:
    """
    nexdrive.pro bridge page resolver.
    Parses the bridge page (using xla=s4t cookie), extracts all CDN links,
    then races them to find the first working direct URL.
    """
    # If URL is a PAYLOAD, extract the core URL
    actual_url = url
    if url.startswith("PAYLOAD:"):
        try:
            import json
            data = json.loads(url[8:])
            if isinstance(data, list) and len(data) > 0:
                actual_url = data[0].get("url", url)
        except: pass
        
    parsed = parse_nexdrive_page(actual_url, referer=referer)

    # Collect candidates in priority order
    candidates: list[str] = []
    for key in ("gdirect", "vcloud", "filepress"):
        v = parsed.get(key)
        if v:
            candidates.append(v)
    candidates.extend(parsed.get("alternatives", [])[:4])

    if not candidates:
        log.debug("resolve_nexdrive_http: no CDN links found via HTTP on %s", url)
        # Playwright fallback — NexDrive may be Cloudflare-gated or JS-only
        try:
            from hub.sites._pw_fallback import pw_resolve_nexdrive
            log.info("resolve_nexdrive_http: HTTP found no links — trying Playwright fallback...")
            return pw_resolve_nexdrive(actual_url, referer=referer, is_batch=is_batch)
        except Exception as pw_exc:
            log.warning("resolve_nexdrive_http PW fallback error: %s", pw_exc)
        return None

    log.debug("resolve_nexdrive_http: racing %d CDN link(s) from nexdrive bridge (is_batch=%s)", len(candidates), is_batch)
    # Race all found CDN links (they won't be nexdrive URLs, so no recursion risk)
    return race_cdn_links(candidates, timeout=20, referer=referer, is_batch=is_batch)


def resolve_any_cdn_http(url: str, referer: str = "") -> str | None:
    """Route a CDN URL to the correct HTTP resolver."""
    # ── Early: unwrap generic dl.php?link= proxy pattern ─────────────────────
    # Sites like gamerxyt.com/dl.php?link=<url> wrap a real CDN URL in a query param.
    # Detect and short-circuit so we don't burn a full resolver on the wrapper host.
    if "dl.php" in url.lower():
        try:
            from urllib.parse import urlparse as _up3, parse_qs as _pqs3, unquote as _uq3
            _qs3 = _pqs3(_up3(url).query)
            _link3 = _uq3(_qs3.get("link", [""])[0])
            if _link3.startswith("http"):
                log.debug("resolve_any_cdn_http: dl.php wrapper → %s", _link3[:80])
                # Recurse with the unwrapped URL so it gets the right resolver
                return resolve_any_cdn_http(_link3, referer=referer)
        except Exception:
            pass

    ul = url.lower()
    if "nexdrive." in ul:
        return resolve_nexdrive_http(url, referer=referer)
    if "fastdl." in ul:
        return resolve_fastdl_http(url, referer=referer)
    if "dotflix." in ul:
        return resolve_dotflix_http(url)
    if "vcloud." in ul:
        return resolve_vcloud_http(url)
    if any(d in ul for d in ["hubcloud.", "hubdrive.", "kutdrive.", "gpdl", "gamerxyt", "diskcdn"]):
        return resolve_hubcloud_http(url)
    if "send.cm" in ul or "sendcm." in ul:
        return resolve_sendcm_http(url)
    if "fuckingfast." in ul:
        return resolve_fuckingfast_http(url)
    if "hexload.com" in ul:
        return resolve_hexload_http(url)
    if "gdtot." in ul:
        return resolve_gdtot_http(url)
    if "dgdrive." in ul or "dropgalaxy." in ul:
        return resolve_dropgalaxy_http(url)
    if "oxxfile." in ul:
        return resolve_generic_http(url)
    if "drive.google.com" in ul or "googleusercontent.com" in ul:
        return resolve_gdirect_url(url)
    return resolve_generic_http(url)


def race_cdn_links(cdn_links: list[str], timeout: int = _RACE_TIMEOUT, referer: str = "", is_batch: bool = False) -> str | None:
    """
    Fire HTTP resolvers for every CDN link in parallel.
    Returns the first direct-file URL found, or None if all fail within timeout.

    Winner-takes-all: as soon as one thread returns a valid URL, the others
    continue to completion but their results are discarded.
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    if not cdn_links:
        return None

    deduped = list(dict.fromkeys(cdn_links))  # preserve order, drop dupes
    
    # ── Internal Ranking Logic ──
    def _rank_url(u: str) -> int:
        u_low = u.lower()
        
        # Determine if this link looks like a real BATCH (ZIP or Folder)
        # We ignore .zip domains like vcloud.zip
        is_real_zip = u_low.endswith(".zip") or any(w in u_low for w in ["/zip/", "/folder/", "/batch/", "complete"])
        if ".zip/" in u_low: is_real_zip = False # likely vcloud/hexload subpath
        
        if is_batch:
            if is_real_zip: return -1 # Absolute top priority for batch jobs
            if "googlevideo.com" in u_low or "googleusercontent.com" in u_low: return 0
            if "fastdl." in u_low or "filepress." in u_low: return 1
            if "drive.google.com" in u_low: return 0
            if "megaup.net" in u_low: return 2
            return 4 # Penalize unknown links in batch mode
             
        # Standard Movie/Single Mode
        if "googlevideo.com" in u_low or "googleusercontent.com" in u_low or "/file/" in u_low:
            return 0  # Top priority (known direct)
        if "fastdl." in u_low or "filepress." in u_low or "filebee." in u_low:
            return 1  # High priority
        if "vcloud." in u_low:
            return 3  # Lower priority (often requires browser/token)
        return 2  # Medium priority

    deduped.sort(key=_rank_url)
    
    log.info("race_cdn_links: racing %d URLs (prioritized, batch_mode=%s): %s", 
             len(deduped), is_batch, [u[:60] for u in deduped])

    def _try(u: str) -> tuple[str, str | None]:
        # If the input is a PAYLOAD, we need to extract the actual URL to probe it
        probe_url = u
        if u.startswith("PAYLOAD:"):
            try:
                import json
                data = json.loads(u[8:])
                if isinstance(data, list) and len(data) > 0:
                    probe_url = data[0].get("url", u)
            except: pass

        if probe_url.startswith("PAYLOAD:"):
             return u, None # Should not happen if parsed correctly
            
        rank = _rank_url(probe_url)
        if rank > 0:
            # Staggered start for lower priority mirrors
            time.sleep(rank * 1.5)
            
        try:
            log.debug("race_cdn_links: probing %s...", probe_url[:70])
            result = resolve_any_cdn_http(probe_url, referer=referer)
            if result:
                log.info("race_cdn_links: ✓ %s resolved to %s", probe_url[:40], result[:70])
            else:
                log.debug("race_cdn_links: × %s failed to resolve", probe_url[:40])
            
            # Extra verification for batch mode: 
            if is_batch and result:
                if any(ext in result.lower() for ext in [".mkv", ".mp4", ".mp4?"]):
                    time.sleep(2) 
            return u, result
        except Exception as exc:
            log.warning("race_cdn_links: worker error for %s: %s", u[:50], exc)
            return u, None

    max_workers = min(len(deduped), 6)
    with ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="cdn_race") as ex:
        futures = {ex.submit(_try, u): u for u in deduped}
        winner: str | None = None
        winner_source: str | None = None

        for fut in as_completed(futures, timeout=timeout):
            try:
                source_url, resolved = fut.result(timeout=1)
                if resolved:
                    log.info("race_cdn_links: Winner found! %s → %s", source_url[:50], resolved[:80])
                    # FINAL VALIDATION: Ensure the winner actually returns a file
                    try:
                        import requests as _req
                        
                        low = resolved.lower()
                        # Optimization: if it's already a direct link or a token-link, trust it.
                        if resolved.startswith("PAYLOAD:") or \
                           (any(k in low for k in ("googlevideo.com", "googleusercontent.com", "vcloud.")) \
                           and not any(ext in low for ext in (".zip", ".rar"))):
                            log.info("race_cdn_links: trusting high-confidence link: %s", resolved[:60])
                            winner = resolved
                            winner_source = source_url
                            break

                        # Use HEAD first (faster, doesn't consume data)
                        is_ok = False
                        r_check = _req.head(resolved, timeout=10, allow_redirects=True, 
                                           headers={"User-Agent": _UA})
                        if _is_direct_url(r_check.url, r_check):
                            is_ok = True
                        elif r_check.status_code in (403, 405):
                            # Some servers block HEAD, try GET stream=True
                            with _req.get(resolved, timeout=10, allow_redirects=True, stream=True, 
                                         headers={"User-Agent": _UA}) as r_get:
                                if _is_direct_url(r_get.url, r_get):
                                    is_ok = True
                        
                        if is_ok:
                            log.info("race_cdn_links: verified winner from %s → %s",
                                     source_url[:60], resolved[:80])
                            winner = resolved
                            winner_source = source_url
                            break
                        else:
                            log.warning("race_cdn_links: winner %s rejected (not a direct file)", resolved[:60])
                    except Exception as e_check:
                        log.debug("race_cdn_links: verification failed for %s: %s", resolved[:60], e_check)
                        # If we can't even HEAD/GET it, it's not a winner. Continue race.
                        continue
                else:
                    log.debug("race_cdn_links: %s → None", source_url[:60])
            except Exception:
                pass
    
    if winner:
        # If the winner was a PAYLOAD item, we want to return a PAYLOAD containing ONLY the winning item
        # so that downstream metadata is preserved.
        if winner_source and winner_source.startswith("PAYLOAD:"):
            try:
                import json
                data = json.loads(winner_source[8:])
                if isinstance(data, list):
                    for item in data:
                        # If this item matches the winner URL, return it as a single-item payload
                        # OR if the winner IS the payload URL itself (e.g. from a resolver that returns PAYLOAD)
                        if item.get("url") == winner:
                             return "PAYLOAD:" + json.dumps([item])
            except: pass
        return winner

    # ── Playwright last-resort: all HTTP resolvers returned None ──────────────
    log.info("race_cdn_links: all HTTP resolvers failed — trying Playwright fallback on top %d URL(s)...", min(3, len(deduped)))
    try:
        from hub.sites._pw_fallback import pw_resolve_any_cdn
        for pu in deduped[:3]:
            probe = pu
            if probe.startswith("PAYLOAD:"):
                try:
                    import json as _pj
                    _pd = _pj.loads(probe[8:])
                    if isinstance(_pd, list) and _pd:
                        probe = _pd[0].get("url", probe)
                except Exception:
                    continue
            if probe.startswith("PAYLOAD:"):
                continue
            pw_result = pw_resolve_any_cdn(probe)
            if pw_result:
                log.info("race_cdn_links: Playwright winner from %s → %s", probe[:60], pw_result[:60])
                return pw_result
    except Exception as pw_exc:
        log.warning("race_cdn_links PW fallback error: %s", pw_exc)

    return None


# ──────────────────────────────────────────────────────────────────────────────
# 11. Quality parser helper (parses label text from movie-page download blocks)
# ──────────────────────────────────────────────────────────────────────────────

def parse_quality_from_label(text: str) -> str:
    """
    Parse quality tag from a download block label.
    e.g. "Project Y (2025) {Hindi-Korean} 480p x264 [315MB]" → "480p"
         "720p 10Bit x265 [514MB]"                            → "720p"
         "1080p x264 [2.2GB]"                                 → "1080p"
    """
    t = text.upper()
    for q in ["4K", "2160P", "1080P", "720P", "480P", "360P"]:
        if q in t:
            return q.replace("2160P", "4K").lower().replace("p", "p") \
                     .replace("4k", "4K")
    return "?"


def parse_size_from_label(text: str) -> str:
    """Extract file size from label e.g. '[315MB]' → '315MB'"""
    m = re.search(r'\[?(\d[\d.]+\s*(?:GB|MB|TB))\]?', text, re.I)
    return m.group(1).strip() if m else ""
