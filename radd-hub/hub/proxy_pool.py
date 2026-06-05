"""SAPI Proxy Pool — auto-rotating, health-checked, self-healing.

Auto-rotates through a pool of Pakistani proxies for cloud.jazzdrive.com.pk (SAPI).
Dead proxies are demoted; recovered proxies are re-enabled automatically.
Background threads handle health checking and auto-discovery.
"""

import threading
import time
import json
import logging
import concurrent.futures
from typing import Optional

log = logging.getLogger("hub.proxy_pool")

# ── Built-in seed list (tested against SAPI on first run) ──────────────────
_BUILTIN_SEEDS = [
    # ─ confirmed working ─
    "socks5://103.121.120.242:1080",   # Karachi, AS131275
    # ─ Pakistani SOCKS5 pool ─
    "socks5://182.191.84.2:1080",
    "socks5://39.45.111.44:1080",
    "socks5://182.191.84.6:1080",
    "socks5://182.191.84.10:1080",
    "socks5://39.45.114.158:1080",
    "socks5://39.45.111.45:1080",
    "socks5://182.191.90.122:1080",
    "socks5://111.119.160.18:1080",
    "socks5://202.141.240.26:1080",
    "socks5://103.255.5.110:1080",
    "socks5://111.119.178.131:1080",
    "socks5://103.141.144.116:1080",
    "socks5://103.26.55.21:1080",
    "socks5://103.106.1.22:1080",
    "socks5://103.25.101.8:1080",
    "socks5://39.40.88.58:1080",
    "socks5://39.40.88.59:1080",
    "socks5://39.40.88.60:1080",
    "socks5://103.149.84.200:1080",
    "socks5://103.149.84.201:1080",
    "socks5://39.45.122.53:1080",
    "socks5://39.45.122.54:1080",
    "socks5://103.88.237.18:1080",
    "socks5://103.88.237.19:1080",
    "socks5://39.37.150.1:1080",
    "socks5://39.37.150.2:1080",
    "socks5://39.37.178.10:1080",
    "socks5://39.37.178.11:1080",
    "socks5://103.47.67.130:1080",
    "socks5://103.47.67.131:1080",
    "socks5://119.73.120.2:1080",
    "socks5://119.73.120.3:1080",
    "socks5://203.128.5.10:1080",
    "socks5://203.128.5.11:1080",
    "socks5://103.94.184.66:1080",
    "socks5://103.94.184.67:1080",
    "socks5://103.211.218.2:1080",
    "socks5://103.211.218.3:1080",
    # ─ Pakistani HTTP/HTTPS proxies ─
    "http://103.141.144.116:8080",
    "http://202.141.240.26:8080",
    "http://111.119.160.18:8080",
    "http://103.255.5.110:8080",
    "http://111.119.178.131:8080",
    "http://39.45.111.44:8080",
    "http://182.191.84.2:8080",
    "http://182.191.84.6:8080",
    "http://103.26.55.21:8080",
    "http://103.106.1.22:8080",
    "http://103.25.101.8:8080",
    "http://39.40.88.58:8080",
    "http://119.73.120.2:8080",
    "http://203.128.5.10:8080",
    "http://103.94.184.66:8080",
    "http://103.211.218.2:8080",
    "http://39.37.150.1:8080",
    "http://39.37.178.10:8080",
    "http://103.47.67.130:8080",
    "http://39.45.122.53:3128",
    "http://39.45.122.54:3128",
    "http://203.128.5.10:3128",
    "http://103.149.84.200:3128",
]

# ── SAPI test config (a 401 from JazzDrive = proxy is alive) ───────────────
import json as _json, base64 as _b64, urllib.parse as _up
_FAKE_AT  = "a" * 40
_SAPI_TEST_URL = (
    "https://cloud.jazzdrive.com.pk/sapi/login/oauth"
    "?action=login&platform=Android&keytype=accesstoken"
    "&key=" + _up.quote(_b64.b64encode(_json.dumps({"data":{"accesstoken":"a"*40}}).encode()).decode(), safe="")
)
_SAPI_TEST_HEADERS = {
    "User-Agent":       "Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)",
    "X-Requested-With": "com.jazz.drive",
    "Accept":           "application/json",
}


def _test_proxy(url: str, timeout: int = 12) -> dict:
    """Test a proxy against cloud.jazzdrive.com.pk/sapi.
    Returns {ok, ping_ms, sapi_status, error}.
    A 401/400/200 from JazzDrive = proxy is alive and Pakistani."""
    import requests as _req
    p = {"http": url, "https": url}
    t0 = time.time()
    try:
        r = _req.get(_SAPI_TEST_URL, proxies=p, timeout=timeout,
                     headers=_SAPI_TEST_HEADERS, verify=True)
        ms = round((time.time() - t0) * 1000)
        ok = r.status_code in (200, 400, 401, 403, 500)
        return {"ok": ok, "ping_ms": ms, "sapi_status": r.status_code, "error": None}
    except Exception as e:
        return {"ok": False, "ping_ms": None, "sapi_status": None,
                "error": str(e)[:120]}


class ProxyPool:
    """Thread-safe rotating proxy pool stored in DB sapi_proxies table."""

    def __init__(self):
        self._lock        = threading.Lock()
        self._pool: list  = []          # list of dicts from DB, ordered by score
        self._idx         = 0           # round-robin cursor
        self._loaded_at   = 0.0
        self._hc_thread   = None
        self._disc_thread = None
        self._started     = False

    # ── startup ───────────────────────────────────────────────────────────
    def start(self):
        if self._started:
            return
        self._started = True
        self._ensure_table()
        self._seed_if_empty()
        self._reload()
        # background health checker every 10 min
        self._hc_thread = threading.Thread(
            target=self._hc_loop, daemon=True, name="proxy-hc")
        self._hc_thread.start()
        # background auto-discoverer every 30 min
        self._disc_thread = threading.Thread(
            target=self._disc_loop, daemon=True, name="proxy-disc")
        self._disc_thread.start()
        log.info("ProxyPool: started with %d proxies", len(self._pool))

    # ── DB helpers ────────────────────────────────────────────────────────
    def _ensure_table(self):
        from . import db
        with db.conn() as c:
            c.execute("""CREATE TABLE IF NOT EXISTS sapi_proxies (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                url          TEXT UNIQUE NOT NULL,
                fail_count   INTEGER DEFAULT 0,
                ok_count     INTEGER DEFAULT 0,
                last_ok_at   INTEGER DEFAULT 0,
                last_fail_at INTEGER DEFAULT 0,
                avg_ms       INTEGER DEFAULT 0,
                is_enabled   INTEGER DEFAULT 1,
                source       TEXT DEFAULT 'seed',
                added_at     INTEGER DEFAULT 0
            )""")

    def _seed_if_empty(self):
        from . import db
        with db.conn() as c:
            n = c.execute("SELECT COUNT(*) AS n FROM sapi_proxies").fetchone()["n"]
        if n == 0:
            log.info("ProxyPool: seeding %d built-in proxies", len(_BUILTIN_SEEDS))
            now = int(time.time())
            from . import db as _db
            with _db.conn() as c:
                for url in _BUILTIN_SEEDS:
                    try:
                        c.execute(
                            "INSERT OR IGNORE INTO sapi_proxies(url,source,added_at) VALUES(?,?,?)",
                            (url, 'seed', now))
                    except Exception:
                        pass
            # Test seeds in background so startup is fast
            threading.Thread(target=self._test_seeds_bg, daemon=True).start()

    def _test_seeds_bg(self):
        """Test all untested seeds in background."""
        time.sleep(5)  # let hub finish startup first
        from . import db
        with db.conn() as c:
            untested = [r["url"] for r in c.execute(
                "SELECT url FROM sapi_proxies WHERE last_ok_at=0 AND last_fail_at=0"
            ).fetchall()]
        if not untested:
            return
        log.info("ProxyPool: testing %d seed proxies in background…", len(untested))
        good = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=25) as ex:
            futs = {ex.submit(_test_proxy, url, 10): url for url in untested}
            for fut in concurrent.futures.as_completed(futs):
                url = futs[fut]
                try:
                    res = fut.result()
                    self._update_proxy_result(url, res["ok"], res.get("ping_ms"))
                    if res["ok"]:
                        good += 1
                except Exception:
                    pass
        log.info("ProxyPool: seed test done — %d/%d alive", good, len(untested))
        self._reload()

    def _reload(self):
        """Reload pool from DB, sorted by score (low fail first, fast first)."""
        from . import db
        try:
            with db.conn() as c:
                rows = c.execute(
                    "SELECT * FROM sapi_proxies WHERE is_enabled=1 ORDER BY fail_count ASC, avg_ms ASC"
                ).fetchall()
            with self._lock:
                self._pool = [dict(r) for r in rows]
                self._idx  = 0
                self._loaded_at = time.time()
            log.debug("ProxyPool: reloaded %d enabled proxies", len(self._pool))
        except Exception as e:
            log.warning("ProxyPool: reload failed: %s", e)

    # ── rotation ──────────────────────────────────────────────────────────
    def get_best(self) -> Optional[dict]:
        """Return a requests-compatible proxies dict for the next best proxy.
        Rotates round-robin among healthy (fail_count < 5) proxies.
        Returns None if pool is empty or all proxies are dead."""
        if time.time() - self._loaded_at > 300:   # reload every 5 min
            threading.Thread(target=self._reload, daemon=True).start()

        with self._lock:
            if not self._pool:
                return None
            # Try up to pool_size proxies to find a healthy one
            n = len(self._pool)
            for _ in range(n):
                proxy = self._pool[self._idx % n]
                self._idx = (self._idx + 1) % n
                if proxy.get("fail_count", 0) < 5:
                    url = proxy["url"]
                    return {"http": url, "https": url, "_url": url}
            # All proxies unhealthy — return least-bad one
            best = min(self._pool, key=lambda p: p.get("fail_count", 99))
            url = best["url"]
            return {"http": url, "https": url, "_url": url}

    def current_pool_status(self) -> dict:
        with self._lock:
            total = len(self._pool)
            healthy = sum(1 for p in self._pool if p.get("fail_count", 0) < 3)
        return {"total": total, "healthy": healthy}

    # ── mark success/fail ────────────────────────────────────────────────
    def mark_success(self, url: str, ms: Optional[int] = None):
        if not url:
            return
        from . import db
        now = int(time.time())
        try:
            with db.conn() as c:
                if ms is not None:
                    c.execute(
                        "UPDATE sapi_proxies SET fail_count=0, ok_count=ok_count+1, "                        "last_ok_at=?, is_enabled=1, "                        "avg_ms=CASE WHEN avg_ms=0 THEN ? ELSE (avg_ms*3+?)/4 END "                        "WHERE url=?",
                        (now, ms, ms, url))
                else:
                    c.execute(
                        "UPDATE sapi_proxies SET fail_count=0, ok_count=ok_count+1, "                        "last_ok_at=?, is_enabled=1 WHERE url=?",
                        (now, url))
        except Exception:
            pass

    def mark_fail(self, url: str):
        if not url:
            return
        from . import db
        now = int(time.time())
        try:
            with db.conn() as c:
                c.execute(
                    "UPDATE sapi_proxies SET fail_count=fail_count+1, last_fail_at=?, "                    "is_enabled=CASE WHEN fail_count+1 >= 5 THEN 0 ELSE 1 END "                    "WHERE url=?",
                    (now, url))
                row = c.execute("SELECT fail_count FROM sapi_proxies WHERE url=?",
                                (url,)).fetchone()
                if row and row["fail_count"] >= 5:
                    log.info("ProxyPool: disabled dead proxy %s (5 consecutive fails)", url)
        except Exception:
            pass
        self._maybe_reload_soon()

    def _maybe_reload_soon(self):
        threading.Thread(target=lambda: (time.sleep(2), self._reload()),
                         daemon=True).start()

    def _update_proxy_result(self, url: str, ok: bool, ms: Optional[int]):
        if ok:
            self.mark_success(url, ms)
        else:
            self.mark_fail(url)

    # ── health checker ────────────────────────────────────────────────────
    def _hc_loop(self):
        time.sleep(60)  # initial delay
        while True:
            try:
                self._run_health_check()
            except Exception as e:
                log.warning("ProxyPool: HC error: %s", e)
            time.sleep(600)  # every 10 min

    def run_health_check_now(self) -> dict:
        """Trigger an immediate health check (blocking). Returns summary."""
        return self._run_health_check()

    def _run_health_check(self) -> dict:
        from . import db
        with db.conn() as c:
            all_proxies = [r["url"] for r in c.execute(
                "SELECT url FROM sapi_proxies ORDER BY last_ok_at ASC"
            ).fetchall()]
        if not all_proxies:
            return {"tested": 0, "alive": 0}
        log.info("ProxyPool: health-checking %d proxies…", len(all_proxies))
        alive = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
            futs = {ex.submit(_test_proxy, url, 10): url for url in all_proxies}
            for fut in concurrent.futures.as_completed(futs):
                url = futs[fut]
                try:
                    res = fut.result()
                    self._update_proxy_result(url, res["ok"], res.get("ping_ms"))
                    if res["ok"]:
                        alive += 1
                except Exception:
                    pass
        self._reload()
        log.info("ProxyPool: HC done — %d/%d alive", alive, len(all_proxies))
        return {"tested": len(all_proxies), "alive": alive}

    # ── auto-discovery ────────────────────────────────────────────────────
    def _disc_loop(self):
        time.sleep(300)  # 5 min after startup
        while True:
            try:
                result = self.discover_new()
                log.info("ProxyPool: discovery added %d new working proxies",
                         result.get("added", 0))
            except Exception as e:
                log.warning("ProxyPool: discovery error: %s", e)
            time.sleep(1800)  # every 30 min

    def discover_new(self) -> dict:
        """Fetch Pakistani proxies from multiple sources, test against SAPI, add working ones."""
        candidates: list[str] = []

        import requests as _req

        # ── Source 1: geonode SOCKS5 ──
        try:
            r = _req.get(
                "https://proxylist.geonode.com/api/proxy-list"
                "?country=PK&protocols=socks5&limit=100&page=1&sort_by=lastChecked&sort_type=desc",
                timeout=15)
            for e in r.json().get("data", []):
                host = (e.get("ip") or "").strip()
                port = str(e.get("port") or "")
                if host and port:
                    candidates.append(f"socks5://{host}:{port}")
        except Exception as e:
            log.debug("ProxyPool disc geonode SOCKS5: %s", e)

        # ── Source 2: geonode HTTP/HTTPS ──
        try:
            r = _req.get(
                "https://proxylist.geonode.com/api/proxy-list"
                "?country=PK&protocols=http,https&limit=100&page=1&sort_by=lastChecked&sort_type=desc",
                timeout=15)
            for e in r.json().get("data", []):
                host = (e.get("ip") or "").strip()
                port = str(e.get("port") or "")
                protos = e.get("protocols") or ["http"]
                proto = protos[0] if protos else "http"
                if host and port:
                    candidates.append(f"{proto}://{host}:{port}")
        except Exception as e:
            log.debug("ProxyPool disc geonode HTTP: %s", e)

        # ── Source 3: proxyscrape SOCKS5 ──
        try:
            r = _req.get(
                "https://api.proxyscrape.com/v3/free-proxy-list/get"
                "?request=displayproxies&country=pk&protocol=socks5&format=text",
                timeout=15)
            for line in r.text.strip().splitlines():
                line = line.strip()
                if ":" in line:
                    candidates.append(f"socks5://{line}")
        except Exception as e:
            log.debug("ProxyPool disc proxyscrape SOCKS5: %s", e)

        # ── Source 4: proxyscrape HTTP ──
        try:
            r = _req.get(
                "https://api.proxyscrape.com/v3/free-proxy-list/get"
                "?request=displayproxies&country=pk&protocol=http&format=text",
                timeout=15)
            for line in r.text.strip().splitlines():
                line = line.strip()
                if ":" in line:
                    candidates.append(f"http://{line}")
        except Exception as e:
            log.debug("ProxyPool disc proxyscrape HTTP: %s", e)

        # ── Source 5: openproxy.space SOCKS5 Pakistan ──
        try:
            r = _req.get("https://openproxy.space/list/socks5", timeout=15,
                         headers={"Accept": "application/json"})
            data = r.json()
            items = data if isinstance(data, list) else data.get("data", [])
            for item in items:
                ip = item.get("ip", "")
                port = str(item.get("port", ""))
                country = (item.get("country") or item.get("countryCode") or "").upper()
                if ip and port and country in ("PK", "PAKISTAN"):
                    candidates.append(f"socks5://{ip}:{port}")
        except Exception as e:
            log.debug("ProxyPool disc openproxy: %s", e)

        if not candidates:
            return {"candidates": 0, "added": 0}

        # Deduplicate
        from . import db
        with db.conn() as c:
            existing = {r["url"] for r in c.execute("SELECT url FROM sapi_proxies").fetchall()}
        new_candidates = [u for u in dict.fromkeys(candidates) if u not in existing]
        if not new_candidates:
            return {"candidates": len(candidates), "added": 0}

        log.info("ProxyPool disc: testing %d new candidates…", len(new_candidates))
        added = 0
        now = int(time.time())
        with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
            futs = {ex.submit(_test_proxy, url, 10): url for url in new_candidates}
            for fut in concurrent.futures.as_completed(futs):
                url = futs[fut]
                try:
                    res = fut.result()
                    if res["ok"]:
                        try:
                            with db.conn() as c:
                                c.execute(
                                    "INSERT OR IGNORE INTO sapi_proxies"                                    "(url,fail_count,ok_count,last_ok_at,avg_ms,is_enabled,source,added_at)"                                    " VALUES(?,0,1,?,?,1,'discovered',?)",
                                    (url, now, res.get("ping_ms") or 0, now))
                            added += 1
                            log.debug("ProxyPool: +%s (%dms)", url, res.get("ping_ms") or 0)
                        except Exception:
                            pass
                except Exception:
                    pass

        if added:
            self._reload()
        return {"candidates": len(candidates), "tested": len(new_candidates), "added": added}

    # ── list for UI ───────────────────────────────────────────────────────
    def list_all(self) -> list:
        from . import db
        with db.conn() as c:
            rows = c.execute(
                "SELECT * FROM sapi_proxies ORDER BY is_enabled DESC, fail_count ASC, avg_ms ASC"
            ).fetchall()
        return [dict(r) for r in rows]

    def add_proxy(self, url: str, test: bool = True) -> dict:
        from . import db
        url = url.strip()
        if not url:
            return {"ok": False, "error": "Empty URL"}
        now = int(time.time())
        try:
            with db.conn() as c:
                c.execute("INSERT OR IGNORE INTO sapi_proxies(url,source,added_at) VALUES(?,?,?)",
                          (url, 'manual', now))
        except Exception as e:
            return {"ok": False, "error": str(e)}
        if test:
            res = _test_proxy(url)
            self._update_proxy_result(url, res["ok"], res.get("ping_ms"))
            self._reload()
            return {"ok": True, "alive": res["ok"], "ping_ms": res.get("ping_ms"),
                    "sapi_status": res.get("sapi_status")}
        self._reload()
        return {"ok": True, "alive": None}

    def remove_proxy(self, proxy_id: int) -> dict:
        from . import db
        try:
            with db.conn() as c:
                c.execute("DELETE FROM sapi_proxies WHERE id=?", (proxy_id,))
            self._reload()
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def enable_proxy(self, proxy_id: int, enabled: bool) -> dict:
        from . import db
        try:
            with db.conn() as c:
                c.execute("UPDATE sapi_proxies SET is_enabled=?, fail_count=0 WHERE id=?",
                          (1 if enabled else 0, proxy_id))
            self._reload()
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}


# ── Singleton ──────────────────────────────────────────────────────────────
pool = ProxyPool()
