from __future__ import annotations
import re
import time
SKIP_ALWAYS: set[str] = {
    "google.com", "t.me", "telegram", "facebook.com", "twitter.com",
    "instagram.com", "youtube.com", "whatsapp", "imdb.com",
    "search-assist", "doubleclick", "googlesyndication", "adservice",
    "adsystem", "analytics", "cloudflare.com/cdn-cgi", "schema.org",
    "gravatar", "disqus", "amazon-adsystem", "pagead",
    "clicknupload", "filemoon", "streamwish", "vidhide", "vidsrc",
}
_MOVIE_SITES: set[str] = {
    "vegamovies", "rogmovies", "ssrmovies", "katmoviehd", "rareanimes",
    "nexdrive", "mkvcinemas",
    "moviesflix", "filmyzilla", "bollyflix", "9xmovies", "mkvcage",
    "bolly4u", "filmymeet", "filmyhit", "jalshamoviez", "cinevood",
    "katworld.net",
}
_CDN_HOSTS: set[str] = {
    "pixeldrain", "gdflix", "hubcloud", "hubcdn", "pixel.hubcdn",
    "hubdrive", "kutdrive", "gofile.io", "mega.nz", "drive.google.com",
    "katdrive", "gdtot", "gdfiles", "10gbps", "fslv2",
    "googleusercontent.com", "googlevideo.com",
    "yummy.monster", "hub.yummy", "hub2.yummy",
    "kmhd.eu", "gd.kmhd.eu", "links.kmhd.eu",
    "mxdrop", "mixdrop", "m1xdrop", "streamtape", "strtape",
    "do7go", "playmogo", "doodstream", "dood.",
    "pkembed.site", "linkszilla.top", "direct-cloud.top",
    "fastdl.", "fslv2.", "dotflix.",
}
_INTERMEDIATE_PAGES: set[str] = {
    "pixel.hubcdn", "hubcdn.fans",
    "hubcloud", "hubdrive", "kutdrive",
    "gdtot", "gdfiles",
    "yummy.monster",
    "gofile.io",
    "katdrive.eu", "kmhd.eu",
    "mxdrop", "mixdrop", "m1xdrop",
    "streamtape", "strtape",
    "do7go", "playmogo",
    "pkembed.site", "linkszilla.top",
}
CDN_PRIORITY = [
    "gdflix", "pixeldrain",
    "hubcloud", "hubcdn", "pixel.hubcdn",
    "kutdrive", "hubdrive",
    "gofile.io",
    "gdtot", "gdfiles",
    "yummy.monster",
    "1fichier", "sendcm", "streamtape", "doodstream",
]
_GENERATE_PATTERNS = [
    "generate download link",
    "generate download",
    "get download link",
    "generate link",
    "download now",
    "get link",
    "click here to download",
    "direct download",
    "generate",
    "download",
    "continue",
    "unlock",
    "start download",
    "verify",
    "proceed",
]
def pixeldrain_direct(url: str) -> str:
    m = re.search(r'pixeldrain\.[^/]+/(?:u|l)/([A-Za-z0-9]+)', url)
    if m:
        file_id = m.group(1)
        base = re.match(r'(https?://pixeldrain\.[^/]+)', url)
        host = base.group(1) if base else "https://pixeldrain.com"
        return f"{host}/api/file/{file_id}?download"
    sep = "&" if "?" in url else "?"
    return url + sep + "download"
def _is_movie_site(url: str) -> bool:
    u = url.lower()
    return any(s in u for s in _MOVIE_SITES)
def _is_cdn_host(url: str) -> bool:
    u = url.lower()
    return any(s in u for s in _CDN_HOSTS)
def _is_intermediate(url: str) -> bool:
    u = url.lower()
    return any(s in u for s in _INTERMEDIATE_PAGES)
def _is_google_cdn(url: str) -> bool:
    u = url.lower()
    return any(g in u for g in ["googleusercontent.com", "googlevideo.com"])
def _score_download_button(href: str, text: str) -> int:
    href_l = href.lower()
    text_l = text.lower()
    if not href or not href.startswith("http"):
        return 0
    if "vcloud" in href_l:
        return 0
    if "/cdn-cgi/" in href_l or "challenges.cloudflare.com" in href_l:
        return 0
    if _is_movie_site(href):
        return 0
    if not _is_google_cdn(href):
        if any(s in href_l for s in SKIP_ALWAYS):
            return 0
    score = 0
    if _is_google_cdn(href):
        score += 500
    if "10gbps" in text_l or "10 gbps" in text_l or "yummy.monster" in href_l:
        score += 300
    if "pixelserver" in text_l or "pixeldrain" in href_l:
        score += 200
    if "fsl" in text_l or "fslv2" in href_l or "fastdl." in href_l:
        score += 150
    if score == 0:
        if any(cdn in href_l for cdn in ["gdflix", "hubcloud", "pixel.hubcdn",
                                          "hubdrive", "kutdrive", "gofile.io",
                                          "mega.nz", "katdrive", "dotflix."]):
            score += 80
    if score == 0:
        if any(kw in text_l for kw in ["download", "server", "direct", "get link"]):
            score += 10
    return score
def _click_generate_button(page, check_control=None) -> bool:
    for pattern in _GENERATE_PATTERNS:
        if check_control: check_control()
        try:
            btn = page.get_by_text(
                re.compile(pattern, re.IGNORECASE), exact=False
            ).first
            if btn.is_visible(timeout=2000):
                btn.click()
                return True
        except Exception:
            pass
    for sel in ["button.btn", "a.btn", ".btn-primary", ".btn-success",
                ".download-btn", "button[onclick]", "a[onclick]", "button", "a"]:
        if check_control: check_control()
        try:
            for el in page.query_selector_all(sel):
                if check_control: check_control()
                text = (el.inner_text() or "").lower()
                if any(kw in text for kw in ["generate", "get link", "download now",
                                              "direct download", "continue", "unlock",
                                              "download here"]):
                    el.click()
                    return True
        except Exception:
            pass
    return False
def _extract_best_link(page, check_control=None) -> tuple[int, str, str] | None:
    candidates: list[tuple[int, str, str]] = []
    for link in page.query_selector_all("a[href]"):
        if check_control: check_control()
        href = (link.get_attribute("href") or "").strip()
        text = (link.inner_text() or "").strip()
        score = _score_download_button(href, text)
        if score > 0:
            candidates.append((score, href, text))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0]
def _extract_all_links(page) -> list[tuple[int, str, str]]:
    candidates: list[tuple[int, str, str]] = []
    for link in page.query_selector_all("a[href]"):
        href = (link.get_attribute("href") or "").strip()
        text = (link.inner_text() or "").strip()
        score = _score_download_button(href, text)
        if score > 0:
            candidates.append((score, href, text))
    return sorted(candidates, reverse=True)
def navigate_vcloud(page, url: str, archive_mode: bool = False,
                    check_control=None, collect_fallbacks: bool = False):
    """
    Navigate a VCloud page, click 'Generate Download Link', collect all server options.

    collect_fallbacks=False (default): returns str (best URL).
    collect_fallbacks=True: returns list[str] (best URL first, then alternates),
      allowing the caller to race all server options in parallel.
    """
    if check_control: check_control()
    page.goto(url, wait_until="domcontentloaded", timeout=60000)

    # Quick 404 / file-not-found detection
    try:
        body_text = page.inner_text("body")
        bl = body_text.lower()
        if "404" in body_text and ("not found" in bl or "file not found" in bl
                                    or "removed" in bl):
            raise RuntimeError(f"VCloud: 404 File Not Found: {url}")
    except RuntimeError:
        raise
    except Exception:
        pass

    try:
        if check_control: check_control()
        page.wait_for_selector(
            ".loader, .loading, .spinner, [class*='loader'], [class*='spin'], "
            ".preloader, #preloader, .overlay",
            state="hidden",
            timeout=20000,
        )
    except Exception:
        pass
    page.wait_for_timeout(3000)
    clicked = _click_generate_button(page, check_control=check_control)
    if clicked:
        page.wait_for_timeout(5000)
        try:
            if check_control: check_control()
            page.wait_for_selector(
                "a[href*='pixeldrain'], a[href*='yummy.monster'], "
                "a[href*='pixel.hubcdn'], a[href*='hubcloud'], "
                "a[href*='gdflix'], a[href*='gofile.io'], a[href*='mega.nz'], "
                "a[href*='googleusercontent'], a[href*='googlevideo'], "
                "a[href*='fastdl.'], a[href*='fslv2']",
                timeout=20000,
            )
        except Exception:
            pass
        page.wait_for_timeout(2000)

    # Collect ALL ranked CDN links from the page
    all_links = _extract_all_links(page)

    if not all_links:
        raw = page.content()
        fallback_patterns = [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]+googlevideo\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]*yummy\.monster/[^\s"\'<>]+',
            r'https?://pixeldrain\.[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
            r'https?://[^\s"\'<>]*gdflix[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*hubcloud[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*pixel\.hubcdn[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*gofile\.io/[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*fastdl\.[^\s"\'<>]+',
        ]
        found: list[str] = []
        for pat in fallback_patterns:
            for m in re.findall(pat, raw):
                m = m.rstrip(".,;)")
                if m not in found:
                    found.append(m)
        if found:
            best_url = _finalise_url(page, found[0])
            if collect_fallbacks:
                extras = []
                for u in found[1:]:
                    try:
                        extras.append(_finalise_url(page, u))
                    except Exception:
                        extras.append(u)
                return [best_url] + extras
            return best_url
        raise RuntimeError(f"No CDN download links found on vcloud page: {url}")

    # archive_mode: prefer zip/batch links first
    if archive_mode:
        for _, href, text in all_links:
            blob = (text + " " + href).lower()
            if any(kw in blob for kw in [".zip", ".rar", ".7z",
                                          "batch", "season pack",
                                          "complete pack", "all episodes",
                                          "full season", "zip file",
                                          "season zip"]):
                return _finalise_url(page, href)

    # Return best link; optionally include all others as fallbacks
    best_url = _finalise_url(page, all_links[0][1])
    if collect_fallbacks:
        extras: list[str] = []
        for _, href, _ in all_links[1:]:
            try:
                extras.append(_finalise_url(page, href))
            except Exception:
                extras.append(href)
        return [best_url] + extras
    return best_url
def navigate_links_kmhd(page, url: str) -> str:
    import urllib.parse as _urlparse
    import base64 as _base64
    import json as _json
    try:
        import requests as _req
    except ImportError:
        return url
    u = url.lower()
    if "get.kmhd.eu" in u or "wait.kmhd.eu" in u:
        try:
            qs = _urlparse.parse_qs(_urlparse.urlparse(url).query)
            b64 = qs.get("url", [""])[0]
            if b64:
                decoded = _base64.b64decode(b64 + "==").decode("utf-8", errors="replace")
                if "kmhe.eu/file/" in decoded or "links.kmhd.eu/file/" in decoded:
                    url = decoded
                elif decoded.startswith("http"):
                    url = decoded
        except Exception:
            pass
        u = url.lower()
    if "kmhe.eu" in u:
        url = url.replace("kmhe.eu", "links.kmhd.eu")
        u = url.lower()
    if "/atchs/" in url.lower():
        return navigate_kmhd_atchs(page, url)
    m = re.search(r"/file/([A-Za-z0-9_\-]+)", url)
    if not m:
        return url
    file_id = m.group(1)
    base_url = "https://links.kmhd.eu"
    try:
        session = _req.Session()
        session.headers.update({
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            )
        })
        r1 = session.get(f"{base_url}/file/{file_id}", timeout=15, allow_redirects=True)
        if "/locked" in r1.url:
            unlock_url = r1.url.replace("locked?", "locked?/unlock&")
            session.post(
                unlock_url,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Origin": base_url,
                    "Referer": r1.url,
                    "X-Sveltekit-Action": "1",
                },
                data={},
                timeout=15,
            )
        r_data = session.get(
            f"{base_url}/file/{file_id}/__data.json",
            timeout=15,
        )
        data_nodes = []
        for line in r_data.text.split("\n"):
            line = line.strip()
            if line:
                try:
                    data_nodes.append(_json.loads(line))
                except Exception:
                    pass
        upload_links: dict[str, str] = {}
        for node in data_nodes:
            if not isinstance(node, dict) or "data" not in node:
                continue
            data_arr = node["data"]
            for item in data_arr:
                if isinstance(item, dict) and "gdflix_res" in item:
                    for cdn_key, ptr in item.items():
                        if isinstance(ptr, int) and 0 <= ptr < len(data_arr):
                            val = data_arr[ptr]
                            if (isinstance(val, str)
                                    and val.lower() not in ("none", "", "null")):
                                upload_links[cdn_key] = val
                    break
        if not upload_links:
            return url
        cdn_candidates: list[str] = []
        if upload_links.get("gdflix_res"):
            cdn_candidates.append(
                f"https://gd.kmhd.eu/file/{upload_links['gdflix_res']}"
            )
        if upload_links.get("hubdrive_res"):
            cdn_candidates.append(
                f"https://hubcloud.foo/drive/{upload_links['hubdrive_res']}"
            )
        if upload_links.get("hubcloud_res"):
            cdn_candidates.append(
                f"https://hubcloud.foo/drive/{upload_links['hubcloud_res']}"
            )
        if upload_links.get("katdrive_res"):
            cdn_candidates.append(
                f"https://katdrive.eu/file/{upload_links['katdrive_res']}"
            )
        if upload_links.get("pixeldrain_res"):
            cdn_candidates.append(
                f"https://pixeldrain.com/u/{upload_links['pixeldrain_res']}"
            )
        if upload_links.get("fichier_res"):
            val = upload_links["fichier_res"]
            cdn_candidates.append(
                f"https://1fichier.com/{val}"
                if val.startswith("?")
                else f"https://1fichier.com/?{val}"
            )
        if upload_links.get("sendcm_res"):
            cdn_candidates.append(
                f"https://send.cm/{upload_links['sendcm_res']}"
            )
        if upload_links.get("ffast_res"):
            cdn_candidates.append(
                f"https://fuckingfast.net/{upload_links['ffast_res']}"
            )
        # 1. Race HTTP-fast CDNs in parallel first (pixeldrain, 1fichier, send.cm, fuckingfast)
        try:
            from ._cdn_resolvers import race_cdn_links
            http_fast = [
                u for u in cdn_candidates
                if any(d in u.lower() for d in [
                    "pixeldrain.com", "1fichier.com", "send.cm", "fuckingfast.net",
                ])
            ]
            if http_fast:
                result = race_cdn_links(http_fast, timeout=12)
                if result:
                    return result
        except Exception:
            pass
        # 2. Playwright fallback: try each CDN sequentially
        for cdn_url in cdn_candidates:
            try:
                result = _finalise_url(page, cdn_url)
                if result and result != cdn_url:
                    return result
                if any(d in cdn_url for d in ["pixeldrain.com", "1fichier.com"]):
                    return result
            except Exception:
                continue
        if cdn_candidates:
            return cdn_candidates[0]
    except Exception:
        pass
    return url
def navigate_katdrive(page, url: str) -> str:
    u = url.lower()
    if "gd.kmhd.eu" in u:
        return navigate_gdflix(page, url)
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        try:
            page.wait_for_selector(
                ".loader, .loading, .spinner, [class*='loader'], #preloader, .overlay",
                state="hidden",
                timeout=15000,
            )
        except Exception:
            pass
        page.wait_for_timeout(4000)
        _click_generate_button(page)
        page.wait_for_timeout(5000)
        try:
            page.wait_for_selector(
                "a[href*='gdflix'], a[href*='pixeldrain'], a[href*='hubcloud'], "
                "a[href*='gofile.io'], a[href*='googleusercontent'], a[href*='yummy.monster'], "
                "a[href*='fastdl.'], a[href*='fslv2']",
                timeout=15000,
            )
        except Exception:
            pass
        page.wait_for_timeout(2000)
        candidates: list[tuple[int, str, str]] = []
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            text = (link.inner_text() or "").strip()
            if not href.startswith("http"):
                continue
            if _is_movie_site(href):
                continue
            hl = href.lower()
            score = _score_download_button(href, text)
            if score == 0:
                if "gamerxyt" in hl or "katdrive" in hl:
                    score = 50
                elif any(kw in text.lower() for kw in ["server", "download", "gdflix", "direct"]):
                    score = 20
            if score > 0:
                candidates.append((score, href, text))
        if candidates:
            candidates.sort(reverse=True)
            _, best_url, _ = candidates[0]
            if "gamerxyt" in best_url.lower():
                return _navigate_gamerxyt(page, best_url)
            return _finalise_url(page, best_url)
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]+googlevideo\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]*gdflix[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*pixeldrain[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
            r'https?://[^\s"\'<>]*yummy\.monster/[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*hubcloud[^\s"\'<>]+',
        ]:
            for m in re.findall(pat, raw):
                m = m.rstrip(".,;)")
                if not _is_movie_site(m):
                    return _finalise_url(page, m)
    except Exception:
        pass
    return url
def _navigate_gamerxyt(page, url: str) -> str:
    try:
        resp_url = [None]
        def on_response(response):
            ru = response.url
            if any(d in ru.lower() for d in ["googleusercontent", "googlevideo",
                                               "pixeldrain", "yummy.monster"]):
                resp_url[0] = ru
        page.on("response", on_response)
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(5000)
        page.remove_listener("response", on_response)
        if resp_url[0]:
            return resp_url[0]
        current = page.url
        if _is_google_cdn(current) or "pixeldrain" in current.lower():
            return _finalise_url(page, current)
        best = _extract_best_link(page)
        if best:
            _, best_url, _ = best
            return _finalise_url(page, best_url)
    except Exception:
        pass
    return url
def _smart_navigate(page, url: str) -> str:
    found_url = [None]
    def on_request(request):
        u = request.url.lower()
        if any(ext in u for ext in [".mp4", ".mkv", ".avi", ".zip", ".rar"]):
            if "google" in u or "pixeldrain" in u or "yummy" in u or "fsl" in u:
                found_url[0] = request.url
    def on_response(response):
        if response.status == 200:
            u = response.url.lower()
            ct = (response.headers.get("content-type") or "").lower()
            if "video/" in ct or "application/octet-stream" in ct or "application/x-matroska" in ct:
                found_url[0] = response.url
    try:
        page.on("request", on_request)
        page.on("response", on_response)
        page.goto(url, wait_until="load", timeout=60000)
        page.wait_for_timeout(4000)
        if found_url[0]: return found_url[0]
        for _ in range(3):
            if _click_generate_button(page):
                page.wait_for_timeout(5000)
                if found_url[0]: return found_url[0]
            best = _extract_best_link(page)
            if best:
                score, best_url, _ = best
                if score >= 150:                                        
                    return best_url
            page.wait_for_timeout(2000)
    except Exception:
        pass
    finally:
        try:
            page.remove_listener("request", on_request)
            page.remove_listener("response", on_response)
        except Exception:
            pass
    return found_url[0] if found_url[0] else url
def _finalise_url(page, url: str) -> str:
    u = url.lower()
    if "/cdn-cgi/" in u or "challenges.cloudflare.com" in u:
        return url
    if _is_google_cdn(url):
        return url
    if "pixeldrain" in u:
        return pixeldrain_direct(url)
    if any(d in u for d in ["links.kmhd.eu", "get.kmhd.eu", "wait.kmhd.eu", "kmhe.eu"]):
        return navigate_links_kmhd(page, url)
    if "gd.kmhd.eu" in u:
        return navigate_gdflix(page, url)
    if any(d in u for d in ["katdrive.eu", "kmhd.eu"]):
        return navigate_katdrive(page, url)
    if any(d in u for d in ["pixel.hubcdn", "hubcdn.fans", "uploadflix.com"]):
        return navigate_pixel_hubcdn(page, url)
    if "yummy.monster" in u:
        return navigate_hub_yummy(page, url)
    if any(d in u for d in ["hubcloud", "hubdrive", "kutdrive"]):
        return navigate_hubcloud(page, url)
    if any(d in u for d in ["gdflix", "katdrive.eu"]):
        return navigate_gdflix(page, url)
    if any(d in u for d in ["gdtot", "gdfiles", "direct-cloud.top", "gdtot.cfd"]):
        return navigate_gdtot(page, url)
    if "gofile.io" in u:
        return navigate_gofile(page, url)
    if "mediafire.com" in u:
        return navigate_mediafire(page, url)
    if "swisstransfer.com" in u:
        return navigate_swisstransfer(page, url)
    if "pkembed.site" in u:
        return navigate_pkembed(page, url)
    if "pkspeed" in u:
        return navigate_pkspeed(page, url)
    if any(d in u for d in ["cloudvideo", "cloud-video"]):
        return navigate_cloudvideo(page, url)
    if any(d in u for d in ["streamtape", "strtape"]):
        return navigate_streamtape(page, url)
    if any(d in u for d in ["mxdrop", "mixdrop", "m1xdrop"]):
        return navigate_mixdrop(page, url)
    if any(d in u for d in ["do7go", "playmogo"]):
        return navigate_do7go(page, url)
    if any(d in u for d in ["doodstream", "dood."]):
        return navigate_doodstream(page, url)
    if "linkszilla" in u:
        return navigate_linkszilla(page, url)
    if any(d in u for d in ["fastdl.", "fslv2."]):
        try:
            from ._cdn_resolvers import resolve_fastdl_http
            out = resolve_fastdl_http(url)
            if out:
                return out
        except Exception:
            pass
    if "dotflix." in u:
        try:
            from ._cdn_resolvers import resolve_dotflix_http
            out = resolve_dotflix_http(url)
            if out:
                return out
        except Exception:
            pass
    return url
def navigate_pkembed(page, url: str) -> str:
    """Navigate pkembed.site to extract quality-ranked direct MP4 download URLs.

    Strategy (v2.0):
      1. Navigate to the embed page.
      2. Click the "Download" tab/button to reveal the quality selection panel.
      3. Parse quality links (HD / Normal / Low) from the panel — ranked by size.
      4. Return the highest-quality URL; fall back to network-sniff / JS-parse.
    """
    _QUALITY_ORDER = ["hd", "high", "1080", "720", "normal", "medium", "480", "low", "360"]

    def _rank_quality(label: str) -> int:
        l = label.lower()
        for i, kw in enumerate(_QUALITY_ORDER):
            if kw in l:
                return i
        return len(_QUALITY_ORDER)

    def _best_from_links(links: list[tuple[str, str]]) -> str | None:
        """Pick the highest-quality direct .mp4/.mkv link."""
        direct = [
            (lbl, href) for lbl, href in links
            if href.startswith("http") and any(
                ext in href.lower() for ext in [".mp4", ".mkv", ".m3u8"]
            )
        ]
        if not direct:
            return None
        direct.sort(key=lambda x: _rank_quality(x[0]))
        return direct[0][1]

    try:
        found_url: list[str | None] = [None]

        def _on_request(request):
            ru = request.url
            rl = ru.lower()
            if any(ext in rl for ext in [".mp4", ".mkv", ".m3u8"]):
                if "font" not in rl and "css" not in rl:
                    found_url[0] = ru

        def _on_response(response):
            if response.status == 200:
                ru = response.url
                rl = ru.lower()
                ct = (response.headers.get("content-type") or "").lower()
                if ("video/" in ct or "application/octet-stream" in ct) and "font" not in rl:
                    found_url[0] = ru

        page.on("request", _on_request)
        page.on("response", _on_response)
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(3000)

        # ── Step 1: Click the "Download" tab / button ──────────────────────────
        _DOWNLOAD_TAB_SELECTORS = [
            "a[href*='download'], button:has-text('Download')",
            ".download-tab, .tab-download, [data-tab='download']",
            "li:has-text('Download'), .nav-tab:has-text('Download')",
            "a.tab:has-text('Download')",
        ]
        clicked_tab = False
        for sel in _DOWNLOAD_TAB_SELECTORS:
            try:
                el = page.query_selector(sel)
                if el and el.is_visible():
                    el.click()
                    page.wait_for_timeout(2000)
                    clicked_tab = True
                    break
            except Exception:
                continue

        if not clicked_tab:
            # Try JS-evaluated click on anything labelled "Download"
            try:
                clicked_tab = page.evaluate("""() => {
                    const els = [...document.querySelectorAll('a, button, li, span, div')];
                    for (const el of els) {
                        if (/download/i.test(el.innerText || '') && el.offsetParent !== null) {
                            el.click(); return true;
                        }
                    }
                    return false;
                }""")
                if clicked_tab:
                    page.wait_for_timeout(2000)
            except Exception:
                pass

        # ── Step 2: Parse quality panel links ─────────────────────────────────
        raw = page.content()
        quality_links: list[tuple[str, str]] = []

        # Pattern A: anchor tags with quality label text (HD / Normal / Low / 720p…)
        _QUAL_PAT = re.compile(
            r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',
            re.I | re.S,
        )
        for m in _QUAL_PAT.finditer(raw):
            href, inner = m.group(1), re.sub(r"<[^>]+>", "", m.group(2)).strip()
            hl = href.lower()
            if not href.startswith("http"):
                continue
            if any(ext in hl for ext in [".mp4", ".mkv"]):
                quality_links.append((inner or href, href))
            elif any(kw in inner.lower() for kw in [
                "hd", "high", "normal", "medium", "low", "720", "480", "1080", "360"
            ]):
                quality_links.append((inner, href))

        # Pattern B: JS object arrays — {label:"HD", file:"https://…"} etc.
        _JS_QUAL_PAT = re.compile(
            r'["\']?(?:label|quality|res(?:olution)?)["\']?\s*:\s*["\']([^"\']+)["\']'
            r'.{0,200}?["\']?(?:file|src|url)["\']?\s*:\s*["\']([^"\']+)["\']',
            re.I | re.S,
        )
        for m in _JS_QUAL_PAT.finditer(raw):
            lbl, href = m.group(1).strip(), m.group(2).strip()
            if href.startswith("http") and any(ext in href.lower() for ext in [".mp4", ".mkv", ".m3u8"]):
                quality_links.append((lbl, href))

        best = _best_from_links(quality_links)
        if best:
            page.remove_listener("request", _on_request)
            page.remove_listener("response", _on_response)
            return best

        # ── Step 3: Wait a little more for network sniff to catch a video URL ──
        page.wait_for_timeout(4000)
        page.remove_listener("request", _on_request)
        page.remove_listener("response", _on_response)

        if found_url[0]:
            return found_url[0]

        # ── Step 4: Regex / JS fallback patterns ──────────────────────────────
        raw2 = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+\.(?:mp4|mkv|m3u8)(?:\?[^\s"\'<>]*)?',
            r'"file"\s*:\s*"(https?://[^"]+)"',
            r'"src"\s*:\s*"(https?://[^"]+\.(?:mp4|mkv|m3u8)[^"]*)"',
            r'source\s+src=["\']([^"\']+\.(?:mp4|mkv|m3u8)[^"\']*)',
        ]:
            for m in re.findall(pat, raw2):
                if isinstance(m, tuple):
                    m = m[0]
                if m.startswith("http") and "font" not in m.lower():
                    return m.rstrip(".,;)")

        # ── Step 5: iframe hand-off ───────────────────────────────────────────
        for iframe_src in re.findall(r'<iframe[^>]+src=["\']([^"\']+)["\']', raw2, re.I):
            if iframe_src.startswith("http") and "pkembed.site" not in iframe_src.lower():
                result = navigate_pkspeed(page, iframe_src)
                if result and result != iframe_src:
                    return result

        # ── Step 6: Full pkspeed fallback ─────────────────────────────────────
        result = navigate_pkspeed(page, url)
        if result and result != url:
            return result

    except Exception:
        pass
    return url


def navigate_do7go(page, url: str) -> str:
    """Navigate do7go.com (ClVideo) to extract the stream/download URL."""
    try:
        found_url = [None]
        def _on_request(request):
            ru = request.url
            rl = ru.lower()
            if any(ext in rl for ext in [".mp4", ".mkv", ".m3u8"]):
                found_url[0] = ru
        page.on("request", _on_request)
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(6000)
        page.remove_listener("request", _on_request)
        if found_url[0]:
            return found_url[0]
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+\.(?:mp4|mkv)(?:\?[^\s"\'<>]*)?',
            r'"file"\s*:\s*"(https?://[^"]+)"',
            r'src\s*:\s*["\']([^"\']+\.(?:mp4|m3u8)[^"\']*)["\']',
        ]:
            for m in re.findall(pat, raw):
                if isinstance(m, tuple):
                    m = m[0]
                if m.startswith("http"):
                    return m.rstrip(".,;)")
        _click_generate_button(page)
        page.wait_for_timeout(4000)
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            hl = href.lower()
            if any(ext in hl for ext in [".mp4", ".mkv"]):
                return href
            if link.get_attribute("download") is not None and href.startswith("http"):
                return href
    except Exception:
        pass
    return url


# ──────────────────────────────────────────────────────────────────────────────
# LinkSZilla CDN dump parser
# LinkSZilla shows ALL CDN mirrors as plain text (not just <a href>).
# We parse both href attributes and raw HTML content.
# ──────────────────────────────────────────────────────────────────────────────
_LINKSZILLA_CDN_PRIORITY = [
    ("gdflix",          100),
    ("hubcloud",         90),
    ("direct-cloud",     85),
    ("uploadflix",       80),
    ("pixeldrain",       75),
    ("gofile.io",        70),
    ("vikingfile",       65),
    ("megaup.net",       60),
    ("1fichier.com",     55),
    ("hexload.com",      50),
    ("desiupload",       45),
    ("clicknupload",     42),
    ("streamtape",       40),
    ("mixdrop",          35),
    ("m1xdrop",          35),
    ("sendcm",           30),
    ("send.cm",          30),
    ("fuckingfast",      25),
    ("multiup.io",       20),
    ("watch-online",     15),
    ("buzzheavier",      12),
]

def _linkszilla_score(u: str) -> int:
    ul = u.lower()
    for kw, sc in _LINKSZILLA_CDN_PRIORITY:
        if kw in ul:
            return sc
    return 0

_LINKSZILLA_CDN_PAT = re.compile(
    r'https?://'
    r'(?:'
    r'(?:[\w\-]+\.)?gdflix\.[a-z]{2,6}|'
    r'hubcloud\.[a-z]{2,6}|'
    r'dl\.direct-cloud\.top|direct-cloud\.top|'
    r'dl\.uploadflix\.com|uploadflix\.[a-z]{2,6}|'
    r'pixeldrain\.[a-z]{2,6}|'
    r'gofile\.io|'
    r'vikingfile\.[a-z]{2,6}|'
    r'megaup\.net|'
    r'1fichier\.com|'
    r'hexload\.com|'
    r'desiupload\.co|'
    r'streamtape\.com|'
    r'(?:m1xdrop|mixdrop)\.[a-z]{2,6}|'
    r'send\.cm|sendcm\.[a-z]{2,6}|'
    r'fuckingfast\.(?:net|co)[a-z]*|'
    r'multiup\.io|'
    r'clicknupload\.[a-z]{2,6}|'
    r'watch-online\.[a-z]{2,6}|'
    r'buzzheavier\.com'
    r')'
    r'[^\s"\'<>{}\[\]\\|]+',
    re.I,
)

def _parse_linkszilla_cdns(page, url: str) -> list[str]:
    """
    Navigate a LinkSZilla page and extract ALL CDN mirror URLs — both from
    <a href> attributes and from plain-text content (the page renders bare URLs
    as readable text, not hyperlinks). Returns URLs sorted by CDN priority.
    """
    seen: set[str] = set()
    found: list[str] = []

    _KNOWN = [
        "gdflix", "hubcloud", "direct-cloud.top", "uploadflix",
        "pixeldrain", "gofile.io", "vikingfile", "megaup.net",
        "1fichier.com", "hexload.com", "desiupload.co",
        "streamtape.com", "mixdrop", "m1xdrop", "sendcm", "send.cm",
        "fuckingfast", "multiup.io", "clicknupload", "watch-online",
        "buzzheavier",
    ]

    def _add(u: str) -> None:
        u = u.strip().rstrip(".,;)'\"")
        if not u or len(u) < 12 or u in seen:
            return
        if not u.startswith("http"):
            u = "https://" + u
        if "linkszilla" in u.lower():
            return
        seen.add(u)
        found.append(u)

    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(3000)
        try:
            page.wait_for_selector(
                "text=Unlocked Links, .unlocked, #links, .links-container, "
                ".download-links, #download",
                timeout=10000,
            )
        except Exception:
            pass
        page.wait_for_timeout(2000)

        # 1. Collect from <a href> elements
        for link in page.query_selector_all("a[href]"):
            try:
                href = (link.get_attribute("href") or "").strip()
                if href.startswith("http") and any(cdn in href.lower() for cdn in _KNOWN):
                    _add(href)
            except Exception:
                pass

        # 2. Extract from raw HTML — handles plain-text CDN URLs not wrapped in <a>
        raw = page.content()
        for m in _LINKSZILLA_CDN_PAT.finditer(raw):
            _add(m.group(0))

        found.sort(key=lambda u: _linkszilla_score(u), reverse=True)
        return found
    except Exception:
        return []


def _parse_linkszilla_cdns_http(url: str) -> list[str]:
    """
    Plain HTTP version of LinkSZilla parser.
    Uses requests to fetch the bridge page and regex to extract all CDN mirrors.
    """
    from hub.scrapers.base import fetch
    try:
        html = fetch(url)
        if not html:
            return []
        
        seen: set[str] = set()
        found: list[str] = []
        
        # Extract mirrors from raw HTML (regex captures both text and hrefs)
        for m in _LINKSZILLA_CDN_PAT.finditer(html):
            u = m.group(0).strip().rstrip(".,;)'\"")
            if not u or len(u) < 12 or u in seen:
                continue
            if "linkszilla" in u.lower():
                continue
            seen.add(u)
            found.append(u)
            
        found.sort(key=lambda u: _linkszilla_score(u), reverse=True)
        return found
    except Exception:
        return []


def navigate_linkszilla(page, url: str) -> str:
    """
    LinkSZilla: parse ALL CDN mirror URLs from the unlocked-links page,
    race HTTP-resolvable ones in parallel, fall back to Playwright for others.
    """
    try:
        all_cdns = _parse_linkszilla_cdns(page, url)
        if not all_cdns:
            current = page.url
            if "linkszilla" not in current.lower() and current.startswith("http"):
                return _finalise_url(page, current)
            return url

        _HTTP_FAST = {
            "pixeldrain", "1fichier.com", "megaup.net", "gofile.io",
            "vikingfile", "hexload.com", "desiupload.co",
            "sendcm", "send.cm", "fuckingfast", "multiup.io", "buzzheavier",
        }
        http_queue: list[str] = []
        playwright_queue: list[str] = []
        for cdn_url in all_cdns:
            ul = cdn_url.lower()
            if any(d in ul for d in _HTTP_FAST):
                http_queue.append(cdn_url)
            else:
                playwright_queue.append(cdn_url)

        if http_queue:
            try:
                from ._cdn_resolvers import race_cdn_links
                result = race_cdn_links(http_queue, timeout=18)
                if result:
                    return result
            except Exception:
                pass

        for cdn_url in (playwright_queue + http_queue)[:3]:
            try:
                result = _finalise_url(page, cdn_url)
                if result and result != cdn_url:
                    return result
            except Exception:
                continue

        return all_cdns[0]
    except Exception:
        pass
    return url


def navigate_pkspeed(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(4000)
        _click_generate_button(page)
        page.wait_for_timeout(3000)
        video = page.query_selector("video source, video")
        if video:
            src = video.get_attribute("src") or ""
            if src.startswith("http"):
                return src
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            hl = href.lower()
            if any(ext in hl for ext in [".mp4", ".mkv", ".avi", ".webm"]):
                return href
            if link.get_attribute("download") is not None and href.startswith("http"):
                return href
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+\.(?:mp4|mkv|avi|webm)(?:\?[^\s"\'<>]*)?',
        ]:
            for m in re.findall(pat, raw):
                return m.rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_cloudvideo(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(5000)
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+\.m3u8[^\s"\'<>]*',
            r'https?://[^\s"\'<>]+\.mp4(?:\?[^\s"\'<>]*)?',
            r'"file"\s*:\s*"(https?://[^"]+)"',
            r'"src"\s*:\s*"(https?://[^"]+)"',
        ]:
            for m in re.findall(pat, raw):
                if isinstance(m, tuple):
                    m = m[0]
                if m.startswith("http"):
                    return m.rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_mixdrop(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        # Wait for download countdown to complete (typically 3–8 s)
        try:
            page.wait_for_selector(
                "a#download-btn, a.btn-download, a[id*='download'], "
                ".vd-download, a:has-text('DOWNLOAD')",
                timeout=15000,
            )
        except Exception:
            page.wait_for_timeout(8000)
        page.wait_for_timeout(2000)

        raw = page.content()
        for pat in [
            r'wurl\s*=\s*"(//[^"]+)"',
            r'wurl\s*=\s*"(https?://[^"]+)"',
            r'DDL\s*=\s*["\']([^"\']+)["\']',
            r'"(https?://[^"]+\.mp4[^"]*)"',
            r'(https?://[^\s"\'<>]+\.mp4(?:\?[^\s"\'<>]*)?)',
            r'"file"\s*:\s*"(https?://[^"]+)"',
            r'src\s*:\s*["\']([^"\']+\.(?:mp4|mkv)[^"\']*)["\']',
        ]:
            for m in re.findall(pat, raw):
                if isinstance(m, tuple):
                    m = m[0]
                if m.startswith("//"):
                    m = "https:" + m
                if m.startswith("http") and not any(
                    d in m.lower() for d in ["mixdrop", "m1xdrop", "mixdr"]
                ):
                    return m.rstrip(".,;)")

        # Try clicking the DOWNLOAD button directly
        for sel in ["a#download-btn", "a.btn-download", "a:has-text('DOWNLOAD')",
                    ".vd-download a", "a[download]"]:
            try:
                btn = page.query_selector(sel)
                if btn:
                    href = (btn.get_attribute("href") or "").strip()
                    if href.startswith("http") and not any(
                        d in href.lower() for d in ["mixdrop", "m1xdrop"]
                    ):
                        return href
            except Exception:
                pass
    except Exception:
        pass
    return url
def navigate_streamtape(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(4000)
        raw = page.content()
        m = re.search(
            r"getElementById\('robotlink'\)\.innerHTML\s*=\s*'([^']+)'\s*\+\s*\('([^']+)'\)",
            raw,
        )
        if m:
            part1 = m.group(1)
            part2 = m.group(2)[3:]
            full = "https://streamtape.com" + part1 + part2
            return full
        for pat in [
            r'(https?://[^\s"\'<>]*streamtape[^\s"\'<>]*/get_video[^\s"\'<>]*)',
            r'(https?://[^\s"\'<>]+\.mp4(?:\?[^\s"\'<>]*)?)',
        ]:
            for f in re.findall(pat, raw):
                return f.rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_doodstream(page, url: str) -> str:
    try:
        real_url = [None]
        def on_request(request):
            ru = request.url
            if "pass_md5" in ru or any(ext in ru for ext in [".mp4", ".mkv"]):
                real_url[0] = ru
        def on_response(response):
            ru = response.url
            rl = ru.lower()
            if "pass_md5" in rl or (any(ext in rl for ext in [".mp4", ".mkv"])
                                     and "do" in rl):
                real_url[0] = ru
        page.on("request", on_request)
        page.on("response", on_response)
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(8000)
        page.remove_listener("request", on_request)
        page.remove_listener("response", on_response)
        if real_url[0]:
            return real_url[0]
        current = page.url
        if any(ext in current.lower() for ext in [".mp4", ".mkv"]):
            return current
        _click_generate_button(page)
        page.wait_for_timeout(5000)
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+/pass_md5/[^\s"\'<>]+',
            r'"(https?://[^"]+\.mp4[^"]*)"',
        ]:
            for m in re.findall(pat, raw):
                if isinstance(m, tuple):
                    m = m[0]
                return m.rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_gofile(page, url: str) -> str:
    try:
        page.goto(url, wait_until="load", timeout=60000)
        page.wait_for_timeout(8000)
        for attempt in range(3):
            for link in page.query_selector_all("a[href*='store'], a[download], a[href*='/download/']"):
                href = (link.get_attribute("href") or "").strip()
                if href.startswith("http"):
                    return href
            btn = page.query_selector("button i.fa-download, .download-button, button:has-text('Download')")
            if btn:
                try:
                    btn.click()
                    page.wait_for_timeout(3000)
                except Exception:
                    pass
            page.wait_for_timeout(2000)
        raw = page.content()
        patterns = [
            r'https?://store[^\s"\'<>]+gofile\.io/[^\s"\'<>]+',
            r'https?://[^\s"\'<>]+gofile\.io/download/[^\s"\'<>]+',
        ]
        for pat in patterns:
            for m in re.findall(pat, raw):
                return m.rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_pixel_hubcdn(page, url: str) -> str:
    for attempt in range(3):
        real_url = _try_extract_pixel_hubcdn(page, url)
        if real_url and real_url != url:
            return real_url
        try:
            page.wait_for_timeout(2000)
        except Exception:
            pass
    return url
def _try_extract_pixel_hubcdn(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        try:
            page.wait_for_selector(
                ".loader, .loading, .spinner, [class*='loader'], #preloader",
                state="hidden", timeout=15000,
            )
        except Exception:
            pass
        real_url: str | None = None
        deadline = time.time() + 25
        while time.time() < deadline:
            try:
                for a in page.query_selector_all("a[href]"):
                    href = (a.get_attribute("href") or "").strip()
                    if not href.startswith("http"):
                        continue
                    if (_is_google_cdn(href)
                            or "yummy.monster" in href.lower()
                            or "pixeldrain" in href.lower()):
                        real_url = href
                        break
                if real_url:
                    break
                for a in page.query_selector_all("a[href]"):
                    try:
                        txt = (a.inner_text() or "").strip().lower()
                    except Exception:
                        txt = ""
                    href = (a.get_attribute("href") or "").strip()
                    if ("download here" in txt and href.startswith("http")
                            and not _is_movie_site(href)
                            and "t.me" not in href
                            and "telegram" not in href.lower()
                            and not any(s in href.lower() for s in SKIP_ALWAYS)):
                        real_url = href
                        break
                if real_url:
                    break
            except Exception:
                pass
            page.wait_for_timeout(800)
        if real_url:
            return _finalise_url(page, real_url)
        raw = page.content()
        patterns = [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]+googlevideo\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]*yummy\.monster/[^\s"\'<>]+',
            r'https?://pixeldrain\.[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
        ]
        for pat in patterns:
            for m in re.findall(pat, raw):
                m = m.rstrip(".,;)")
                return _finalise_url(page, m)
    except Exception:
        pass
    return url
def navigate_hub_yummy(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        try:
            page.wait_for_selector(
                ".loader, .loading, .spinner, [class*='loader'], #preloader",
                state="hidden", timeout=15000,
            )
        except Exception:
            pass
        page.wait_for_timeout(4000)
        current = page.url
        if _is_google_cdn(current) or "pixeldrain" in current.lower():
            return _finalise_url(page, current)
        best = _extract_best_link(page)
        if best:
            score, best_url, _ = best
            if _is_google_cdn(best_url) or "pixeldrain" in best_url.lower():
                return _finalise_url(page, best_url)
            if "yummy.monster" in best_url.lower():
                return url
            if score >= 80:
                return _finalise_url(page, best_url)
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]+googlevideo\.com/[^\s"\'<>]{20,}',
            r'https?://pixeldrain\.[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
        ]:
            for m in re.findall(pat, raw):
                m = m.rstrip(".,;)")
                return _finalise_url(page, m)
    except Exception:
        pass
    return url
def navigate_gdflix(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(4000)
        _click_generate_button(page)
        page.wait_for_timeout(3000)
        candidates: list[tuple[int, str]] = []
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            text = (link.inner_text() or "").strip().lower()
            if not href.startswith("http"):
                continue
            if any(s in href for s in SKIP_ALWAYS):
                continue
            if _is_movie_site(href):
                continue
            score = 0
            if _is_google_cdn(href):
                score = 200
            elif "pixeldrain" in href:
                score = 180
            elif any(kw in text for kw in ["10gbps", "fslv2", "server 1", "fast"]):
                score = 10
            elif any(kw in text for kw in ["server", "download", "direct"]):
                score = 5
            elif text:
                score = 1
            if score > 0:
                candidates.append((score, href))
        if candidates:
            candidates.sort(reverse=True)
            return _finalise_url(page, candidates[0][1])
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://pixeldrain\.[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
            r'https?://[^\s"\'<>]*yummy\.monster/[^\s"\'<>]+',
        ]:
            for m in re.findall(pat, raw):
                return _finalise_url(page, m.rstrip(".,;)"))
    except Exception:
        pass
    return url
def navigate_hubcloud(page, url: str, collect_fallbacks: bool = False):
    """
    HubCloud / HubDrive: click 'Generate Direct Download Link', collect all server options.
    Page pattern is identical to VCloud — produces FSLv2, FSL, 10Gbps, PixelServer:2 buttons.

    collect_fallbacks=False (default): returns str (best resolved URL).
    collect_fallbacks=True: returns list[str] (all server URLs, best first).
    """
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        try:
            page.wait_for_selector(
                ".loader, .loading, .spinner, [class*='loader'], [class*='spin'], "
                ".preloader, #preloader, .overlay",
                state="hidden", timeout=15000,
            )
        except Exception:
            pass
        page.wait_for_timeout(4000)

        # 404 / file-gone detection
        try:
            body_text = page.inner_text("body")
            bl = body_text.lower()
            if "404" in body_text and any(w in bl for w in ["not found", "file not found", "removed"]):
                return [] if collect_fallbacks else url
        except Exception:
            pass

        # Already redirected to a direct CDN?
        current_l = page.url.lower()
        if any(d in current_l for d in ["googleusercontent", "googlevideo", "pixeldrain"]):
            best = _finalise_url(page, page.url)
            return [best] if collect_fallbacks else best

        # Click "Generate Direct Download Link"
        _click_generate_button(page)
        page.wait_for_timeout(5000)

        # Wait for server buttons (FSLv2, FSL, 10Gbps, PixelServer:2)
        try:
            page.wait_for_selector(
                "a[href*='fastdl.'], a[href*='fslv2'], a[href*='fsl'], "
                "a[href*='pixeldrain'], a[href*='googlevideo'], "
                "a[href*='googleusercontent']",
                timeout=15000,
            )
        except Exception:
            pass
        page.wait_for_timeout(2000)

        # Collect ALL ranked server links via shared scoring helper
        all_links = _extract_all_links(page)
        if all_links:
            if collect_fallbacks:
                results: list[str] = []
                for _, href, _ in all_links:
                    try:
                        results.append(_finalise_url(page, href))
                    except Exception:
                        results.append(href)
                return results
            return _finalise_url(page, all_links[0][1])

        # HTML pattern fallback
        raw = page.content()
        for pat in [
            r'https?://[^\s"\'<>]+googleusercontent\.com/[^\s"\'<>]{20,}',
            r'https?://[^\s"\'<>]+googlevideo\.com/[^\s"\'<>]{20,}',
            r'https?://pixeldrain\.[^\s"\'<>]+/(?:u|l)/[A-Za-z0-9]+',
            r'https?://[^\s"\'<>]*fastdl\.[^\s"\'<>]+',
            r'https?://[^\s"\'<>]*yummy\.monster/[^\s"\'<>]+',
        ]:
            for m in re.findall(pat, raw):
                m = m.rstrip(".,;)")
                best = _finalise_url(page, m)
                return [best] if collect_fallbacks else best

        return [] if collect_fallbacks else url
    except Exception:
        pass
    return [] if collect_fallbacks else url
def navigate_kmhd_atchs(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(4000)
        priority = [
            ("hubcloud", 100), ("hubdrive", 95),
            ("gdflix",   90),  ("gd.kmhd",  88),
            ("katdrive", 80),  ("kat.kmhd", 78),
            ("pixeldrain", 60),
            ("sendcm",   40),  ("send.cm",  40),
            ("fuckingfast", 30), ("ffast",   30),
            ("1fichier", 20),
        ]
        candidates: list[tuple[int, str]] = []
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            if not href.startswith("http"):
                continue
            hl = href.lower()
            for kw, score in priority:
                if kw in hl:
                    candidates.append((score, href))
                    break
        candidates.sort(reverse=True)
        for _, mirror_url in candidates:
            try:
                out = _finalise_url(page, mirror_url)
                if out and out != mirror_url:
                    return out
            except Exception:
                continue
        if candidates:
            return candidates[0][1]
    except Exception:
        pass
    return url
def navigate_gdtot(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(5000)
        _click_generate_button(page)
        page.wait_for_timeout(6000)
        for attempt in range(2):
            best = _extract_best_link(page)
            if best:
                score, best_url, _ = best
                if score >= 80:
                    return _finalise_url(page, best_url)
            if _click_generate_button(page):
                page.wait_for_timeout(5000)
        for link in page.query_selector_all("a[href]"):
            href = (link.get_attribute("href") or "").strip()
            if any(d in href.lower() for d in ["pixeldrain", "drive.google", "yummy.monster", "cloud.top"]):
                return _finalise_url(page, href)
    except Exception:
        pass
    return url
def get_best_download_link(page, url: str) -> str:
    return _finalise_url(page, url)
def navigate_mediafire(page, url: str) -> str:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        try:
            page.wait_for_selector("a#downloadButton, a.input.popsok, a[aria-label*='Download']", timeout=15000)
        except Exception:
            page.wait_for_timeout(3000)
        for sel in ["a#downloadButton", "a.input.popsok", "a[aria-label*='Download']"]:
            try:
                el = page.query_selector(sel)
                if el:
                    href = (el.get_attribute("href") or "").strip()
                    if href.startswith("http") and "mediafire.com/file" not in href:
                        return href
            except Exception:
                pass
        raw = page.content()
        m = re.search(r'https?://download[^\s"\'<>]+mediafire\.com/[^\s"\'<>]+', raw)
        if m:
            return m.group(0).rstrip(".,;)")
    except Exception:
        pass
    return url
def navigate_swisstransfer(page, url: str) -> str:
    try:
        import urllib.request as _ur
        import json as _json
        m = re.search(r"swisstransfer\.com/d/([A-Za-z0-9\-]+)", url)
        if not m:
            return url
        link_uuid = m.group(1)
        api = f"https://www.swisstransfer.com/api/links/{link_uuid}"
        req = _ur.Request(api, headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json",
        })
        with _ur.urlopen(req, timeout=15) as resp:
            data = _json.loads(resp.read().decode("utf-8", errors="replace"))
        container_uuid = (
            data.get("data", {}).get("containerUUID")
            or data.get("containerUUID")
        )
        if not container_uuid:
            return url
        return (
            f"https://www.swisstransfer.com/api/download/"
            f"{container_uuid}/{link_uuid}"
        )
    except Exception:
        return url