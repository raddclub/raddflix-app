"""
Playwright-based fallback resolvers for CDN sites that resist pure-HTTP scraping.

REFACTOR (v7.0): Absolute Thread Isolation.
Each thread now starts its own Playwright instance, Browser, and Context.
This prevents "cannot switch to a different thread" errors by ensuring
no Playwright objects are shared across thread boundaries.
"""
from __future__ import annotations
import logging
import time
import re
import os
import threading as _threading
from typing import Optional

log = logging.getLogger("hub.sites.pw_fallback")

# ── Constants ─────────────────────────────────────────────────────────────────

_DIRECT_EXT = (".mkv", ".mp4", ".avi", ".webm", ".mov", ".zip", ".rar", ".7z")

_CDN_CAPTURE_HOSTS = (
    "nexdrive.", "vcloud.", "fastdl.", "filepress.", "filebee.",
    "hubcloud.", "hubdrive.", "kutdrive.", "gpdl.", "gamerxyt.", "diskcdn.",
    "googlevideo.com", "googleusercontent.com", "drive.google.com",
    "mega.nz", "buzzheavier.", "gofile.io", "1fichier.com", "megaup.net",
    "pixeldrain.", "vikingfile.", "dgdrive.", "dropgalaxy.", "oxxfile.",
    "send.cm", "sendcm.", "fuckingfast.", "hexload.", "gdtot.",
    "streamwish.", "wishfast.", "filelions.", "doodstream.", "dood.",
    "streamhub.", "mdisk.", "streamruby.", "fsl.buzz", "fsl.video",
)

_FAST_HOSTS = (
    "gpdl.", "diskcdn.", "gamerxyt.", "fsl.buzz", "fsl.video",
    "buzzheavier.", "fastdl.", "pixeldrain.",
)

_DL_BTN_SELECTORS = [
    "a:has-text('Download Now')", "a:has-text('Free Download')",
    "a:has-text('Direct Download')", "a:has-text('Get Link')",
    "button:has-text('Generate')", "button:has-text('Get Link')",
    "button:has-text('Download')", "button:has-text('Download Now')",
    "a:has-text('Generate')", "#generate", "#generateBtn",
    ".generate-btn", "[id*='generate']", "[class*='generate']",
    "a.btn-success", "a.btn-primary", "a.download-btn", "[id*='download']",
]


# ── Thread-Isolated Browser Manager ───────────────────────────────────────────

_tls = _threading.local()

class ThreadIsolatedBrowser:
    def __init__(self):
        self.pw = None
        self.browser = None
        self.context = None
        self.page = None

    def start(self):
        from playwright.sync_api import sync_playwright
        import asyncio
        try:
            # Prevent "sync API inside asyncio loop" error by ensuring no loop is active in this thread
            try:
                loop = asyncio.get_event_loop()
                if not loop.is_running():
                    asyncio.set_event_loop(None)
            except Exception:
                pass

            # Absolute Isolation: Start PW instance inside this thread
            self.pw = sync_playwright().start()
            
            # Ensure chromium path is set
            correct_path = "/home/runner/workspace/radd-hub/local/browsers/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell"
            if os.path.exists(correct_path):
                os.environ["RADD_CHROMIUM_EXECUTABLE"] = correct_path
                os.environ["PLAYWRIGHT_BROWSERS_PATH"] = "/home/runner/workspace/radd-hub/local/browsers"
            
            launch_kwargs = {"headless": True}
            exe = os.environ.get("RADD_CHROMIUM_EXECUTABLE")
            if exe and os.path.exists(exe):
                launch_kwargs["executable_path"] = exe
            
            self.browser = self.pw.chromium.launch(**launch_kwargs)
            self.context = self.browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            )
            self.page = self.context.new_page()
            
            # Basic resource blocking
            def _handler(route):
                if route.request.resource_type in ("image", "font", "media", "stylesheet"):
                    return route.abort()
                return route.continue_()
            self.page.route("**/*", _handler)
            
            return True
        except Exception as e:
            log.error(f"ThreadIsolatedBrowser: init failed: {e}")
            self.stop()
            return False

    def stop(self):
        try:
            if self.page: self.page.close()
            if self.context: self.context.close()
            if self.browser: self.browser.close()
            if self.pw: self.pw.stop()
        except Exception:
            pass
        self.page = self.context = self.browser = self.pw = None

def _get_isolated_page():
    """Get or create the thread-isolated page."""
    mgr = getattr(_tls, "mgr", None)
    if not mgr:
        mgr = ThreadIsolatedBrowser()
        if mgr.start():
            _tls.mgr = mgr
        else:
            return None
    return mgr.page


def _wait_for_cf_pass(page, timeout_s: float = 18.0) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            title = (page.title() or "").lower()
            if "just a moment" not in title and "cloudflare" not in title:
                return True
        except Exception:
            pass
        time.sleep(1.2)
    return False


def _is_cdn_url(url: str) -> bool:
    ul = url.lower()
    return any(h in ul for h in _CDN_CAPTURE_HOSTS)


def _is_direct_media(url: str) -> bool:
    u = url.lower().split("?")[0]
    return any(u.endswith(ext) for ext in _DIRECT_EXT)


# ── 1. VegaMovies page renderer ───────────────────────────────────────────────

def pw_extract_cdn_links_from_page(url: str, log_fn=None) -> str:
    page = _get_isolated_page()
    if not page:
        return ""

    try:
        if log_fn: log_fn(f"[PW] Rendering page: {url[:70]}...")
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        _wait_for_cf_pass(page)
        
        try: page.wait_for_selector("a[href]", timeout=8000)
        except: pass

        time.sleep(2.5)
        html = page.content()
        if log_fn: log_fn(f"[PW] Page rendered — {len(html):,} chars captured.")
        return html
    except Exception as exc:
        log.warning("pw_extract_cdn_links_from_page(%s): %s", url, exc)
        return ""


# ── 2. NexDrive Playwright resolver ───────────────────────────────────────────

def pw_resolve_nexdrive(url: str, referer: str = "", is_batch: bool = False, log_fn=None) -> Optional[str]:
    page = _get_isolated_page()
    if not page: return None

    captured_navigations: list[str] = []
    def _on_request(req):
        ru = req.url
        if _is_cdn_url(ru) and "nexdrive." not in ru.lower():
            captured_navigations.append(ru)

    try:
        page.on("request", _on_request)
        if referer: page.set_extra_http_headers({"Referer": referer})
        
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        _wait_for_cf_pass(page)
        time.sleep(2.0)
        
        html = page.content()
        from ._cdn_resolvers import _parse_nexdrive_html, race_cdn_links
        parsed = _parse_nexdrive_html(html)

        candidates: list[str] = []
        for key in ("gdirect", "vcloud", "filepress"):
            v = parsed.get(key)
            if v: candidates.append(v)
        candidates.extend(parsed.get("alternatives", [])[:5])
        candidates.extend([cu for cu in captured_navigations if cu not in candidates])

        if not candidates: return None
        return race_cdn_links(candidates, timeout=25, referer=url, is_batch=is_batch)
    except Exception as exc:
        log.warning("pw_resolve_nexdrive(%s): %s", url, exc)
        return None
    finally:
        try: page.remove_listener("request", _on_request)
        except: pass


# ── 3. VCloud Playwright resolver ─────────────────────────────────────────────

def pw_resolve_vcloud(url: str, log_fn=None) -> Optional[str]:
    page = _get_isolated_page()
    if not page: return None

    popup_urls: list[str] = []
    captured_navigations: list[str] = []

    def _on_popup(popup):
        try:
            pu = popup.url
            if pu and pu != "about:blank": popup_urls.append(pu)
            popup.close()
        except: pass

    def _on_request(req):
        ru = req.url
        if (_is_direct_media(ru) or any(h in ru.lower() for h in _FAST_HOSTS)):
            if "vcloud" not in ru.lower(): captured_navigations.append(ru)

    try:
        page.context.on("page", _on_popup)
        page.on("request", _on_request)
        
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        _wait_for_cf_pass(page)
        time.sleep(1.5)

        clicked = False
        for sel in _DL_BTN_SELECTORS:
            try:
                btn = page.query_selector(sel)
                if btn and btn.is_visible():
                    btn.click()
                    clicked = True
                    time.sleep(3.5)
                    break
            except: continue

        all_found = popup_urls + captured_navigations
        if all_found:
            return next((u for u in all_found if any(h in u.lower() for h in _FAST_HOSTS)), all_found[0])

        html = page.content()
        all_hrefs = re.findall(r'href=["\'](' + r'https?://[^\s"\'<>]+' + r')["\']', html, re.I)
        for h in all_hrefs:
            if any(host in h.lower() for host in _FAST_HOSTS) and "vcloud" not in h.lower():
                return h
        return None
    except Exception as exc:
        log.warning("pw_resolve_vcloud(%s): %s", url, exc)
        return None
    finally:
        try: 
            page.context.remove_listener("page", _on_popup)
            page.remove_listener("request", _on_request)
        except: pass


# ── 4. FastDL Playwright resolver ─────────────────────────────────────────────

def pw_resolve_fastdl(url: str, log_fn=None) -> Optional[str]:
    page = _get_isolated_page()
    if not page: return None

    captured: list[str] = []
    def _on_response(resp):
        if _is_direct_media(resp.url): captured.append(resp.url)

    try:
        page.on("response", _on_response)
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        _wait_for_cf_pass(page)
        time.sleep(1.5)

        for sel in ["#tgbtn", "a:has-text('Download Now')", "a:has-text('Download')", ".download-btn"]:
            try:
                btn = page.query_selector(sel)
                if btn and btn.is_visible():
                    try: 
                        with page.expect_navigation(timeout=10000, wait_until="commit"):
                            btn.click()
                    except: btn.click()
                    time.sleep(2.5)
                    break
            except: continue

        if captured: return captured[0]
        if _is_direct_media(page.url): return page.url

        html = page.content()
        for pat in [r'href=["\'](https?://[^\s"\'<>]+\.(?:mkv|mp4|avi|zip|rar)[^\s"\'<>]*)["\']']:
            m = re.search(pat, html, re.I)
            if m and "fastdl" not in m.group(1).lower(): return m.group(1)
        return None
    except Exception as exc:
        log.warning("pw_resolve_fastdl(%s): %s", url, exc)
        return None
    finally:
        try: page.remove_listener("response", _on_response)
        except: pass


# ── 5. Generic Playwright resolver ────────────────────────────────────────────

def pw_resolve_generic(url: str, log_fn=None) -> Optional[str]:
    page = _get_isolated_page()
    if not page: return None

    captured: list[str] = []
    popup_urls: list[str] = []

    def _on_request(req):
        ru = req.url
        if _is_direct_media(ru) or _is_cdn_url(ru):
            if url.split("/")[2] not in ru: captured.append(ru)

    def _on_popup(popup):
        try:
            pu = popup.url
            if pu and pu != "about:blank": popup_urls.append(pu)
            popup.close()
        except: pass

    try:
        page.on("request", _on_request)
        page.context.on("page", _on_popup)
        
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        _wait_for_cf_pass(page)
        time.sleep(1.5)

        for sel in _DL_BTN_SELECTORS:
            try:
                btn = page.query_selector(sel)
                if btn and btn.is_visible():
                    btn.click()
                    time.sleep(3.0)
                    if captured or popup_urls: break
            except: continue

        all_results = ([u for u in captured if _is_direct_media(u)] + [u for u in popup_urls if _is_direct_media(u)])
        if all_results: return all_results[0]
        return None
    except Exception as exc:
        log.warning("pw_resolve_generic(%s): %s", url, exc)
        return None
    finally:
        try:
            page.remove_listener("request", _on_request)
            page.context.remove_listener("page", _on_popup)
        except: pass


# ── 6. Router ─────────────────────────────────────────────────────────────────

def pw_resolve_any_cdn(url: str, log_fn=None) -> Optional[str]:
    ul = url.lower()
    if "nexdrive." in ul: return pw_resolve_nexdrive(url, log_fn=log_fn)
    if "vcloud." in ul: return pw_resolve_vcloud(url, log_fn=log_fn)
    if "fastdl." in ul: return pw_resolve_fastdl(url, log_fn=log_fn)
    return pw_resolve_generic(url, log_fn=log_fn)
