from __future__ import annotations
import re
import time
from urllib.parse import urljoin, urlparse
try:
    import requests
    from bs4 import BeautifulSoup, Tag
    _AVAILABLE = True
except ImportError:
    _AVAILABLE = False
    class BeautifulSoup:
        pass
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
}
class FakeElement:
    def __init__(self, tag: "Tag", base_url: str = ""):
        self._tag = tag
        self._base_url = base_url
    def inner_text(self) -> str:
        if not self._tag:
            return ""
        return self._tag.get_text(separator=" ", strip=True)
    def get_attribute(self, name: str) -> str | None:
        if not self._tag:
            return None
        val = self._tag.get(name)
        if val is None:
            return None
        s = " ".join(val) if isinstance(val, list) else str(val)
        if name in ("href", "src", "action") and s and not s.startswith(("http", "//", "javascript", "#", "mailto")):
            s = urljoin(self._base_url, s)
        return s
    def click(self):
        pass                             
    def is_visible(self, timeout=None) -> bool:
        return self._tag is not None
    def evaluate(self, js_expr: str, *args) -> str:
        try:
            m = re.search(r"closest\(['\"]([^'\"]+)['\"]", js_expr)
            if m and self._tag:
                selector = m.group(1)
                parent = self._tag.parent
                tags = {s.strip().split(".")[0].split("[")[0]
                        for s in selector.split(",")}
                while parent and parent.name:
                    if parent.name in tags:
                        return parent.get_text(separator=" ", strip=True)
                    parent = parent.parent
        except Exception:
            pass
        return ""
class _NullElement:
    def inner_text(self): return ""
    def get_attribute(self, name): return None
    def click(self): pass
    def is_visible(self, timeout=None): return False
    def evaluate(self, *a, **kw): return ""
class FakeLocator:
    def __init__(self, element):
        self._el = element
    @property
    def first(self):
        return self
    def click(self):
        pass
    def is_visible(self, timeout=None) -> bool:
        return self._el is not None and not isinstance(self._el, _NullElement)
class FakeContext:
    def __init__(self):
        self._cookies: list = []
    def clear_cookies(self):
        self._cookies = []
    def add_cookies(self, cookies):
        self._cookies.extend(cookies)
class FakePage:
    def __init__(self):
        if not _AVAILABLE:
            raise ImportError(
                "FakePage requires: pip install requests beautifulsoup4"
            )
        self._session = requests.Session()
        self._session.headers.update(HEADERS)
        self._url = ""
        self._soup: BeautifulSoup | None = None
        self._html = ""
        self.context = FakeContext()
    def goto(self, url: str, wait_until=None, timeout=60000) -> None:
        # Fail fast on unreachable scraper sites: HTTP fallback should never
        # hang 60s per page when the user is browsing without a working
        # headless browser. Cap at 12s, honor caller's smaller timeouts.
        # connect_timeout=4s, read_timeout=12s.
        wait_s = max(2.0, min(timeout / 1000.0, 12.0))
        try:
            resp = self._session.get(url, timeout=(4, wait_s),
                                     allow_redirects=True)
            resp.raise_for_status()
            self._url = resp.url
            self._html = resp.text
            self._soup = BeautifulSoup(self._html, "html.parser")
        except Exception as e:
            raise RuntimeError(f"FakePage.goto({url}) failed: {e}")
    @property
    def url(self) -> str:
        return self._url
    def wait_for_timeout(self, ms: int) -> None:
        pass                                    
    def wait_for_selector(self, selector: str, state=None, timeout=None) -> None:
        pass                                                      
    def query_selector_all(self, selector: str) -> list:
        if not self._soup:
            return []
        try:
            tags = self._soup.select(selector)
            return [FakeElement(tag, self._url) for tag in tags]
        except Exception:
            return []
    def query_selector(self, selector: str):
        if not self._soup:
            return _NullElement()
        try:
            tag = self._soup.select_one(selector)
            return FakeElement(tag, self._url) if tag else _NullElement()
        except Exception:
            return _NullElement()
    def get_by_text(self, pattern, exact: bool = False) -> FakeLocator:
        if not self._soup:
            return FakeLocator(None)
        try:
            if hasattr(pattern, "pattern"):                  
                pat = pattern
            else:
                pat = re.compile(re.escape(str(pattern)), re.IGNORECASE)
            for tag in self._soup.find_all(True):
                text = tag.get_text(separator=" ", strip=True)
                if pat.search(text):
                    return FakeLocator(FakeElement(tag, self._url))
        except Exception:
            pass
        return FakeLocator(None)
    def content(self) -> str:
        return self._html
    def title(self) -> str:
        if not self._soup:
            return ""
        t = self._soup.find("title")
        return t.get_text(strip=True) if t else ""
    def evaluate(self, js_expr: str, *args):
        """Emulate page.evaluate(js, args) for common scraper patterns.

        Handles the sigWords-style link-scanning pattern used by site plugins:
        a JS arrow function that calls document.querySelectorAll('a[href]')
        and filters links by keyword lists.
        """
        if not self._soup:
            return [] if ("querySelectorAll" in str(js_expr) or args) else None
        sig_words_arg = None
        if args and isinstance(args[0], list):
            sig_words_arg = [str(w).lower() for w in args[0]]
        elif "sigWords" in str(js_expr) or "querySelectorAll" in str(js_expr):
            sig_words_arg = []
        if sig_words_arg is not None:
            out = []
            for a in self._soup.select("a[href]"):
                href = a.get("href", "")
                if not href or href.startswith(("javascript", "#", "mailto")):
                    continue
                if not href.startswith("http"):
                    href = urljoin(self._url, href)
                text = a.get_text(separator=" ", strip=True).lower()
                slug = re.sub(r"https?://[^/]+", "", href)
                combined = slug + " " + text
                if sig_words_arg:
                    matched = [w for w in sig_words_arg if w in combined]
                    half = max(1, (len(sig_words_arg) + 1) // 2)
                    if len(matched) < half:
                        continue
                    out.append({"href": href, "score": len(matched), "text": text[:40]})
                else:
                    out.append({"href": href, "score": 0, "text": text[:40]})
            return sorted(out, key=lambda x: x["score"], reverse=True)[:5]
        return None
    def on(self, event: str, handler) -> None:
        pass
    def remove_listener(self, event: str, handler) -> None:
        pass
    def wait_for_load_state(self, state: str = "load", timeout: int = None) -> None:
        pass
    def close(self) -> None:
        pass
    def expect_navigation(self, **kwargs):
        return _NullContextMgr()
    def expect_download(self, **kwargs):
        return _NullContextMgr()
class _NullContextMgr:
    def __enter__(self): return self
    def __exit__(self, *args): pass
    @property
    def value(self): return None